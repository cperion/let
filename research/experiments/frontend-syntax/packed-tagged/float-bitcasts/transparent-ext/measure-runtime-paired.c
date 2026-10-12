#define _POSIX_C_SOURCE 200809L
#include "abc.h"
#include <dlfcn.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    void *library;
    abc_status (*abc_module_load)(const void *,size_t,abc_module **,abc_error *);
    void (*abc_module_free)(abc_module *);
    abc_status (*abc_vm_create)(const abc_limits *,abc_vm **,abc_error *);
    abc_status (*abc_vm_load)(abc_vm *,const abc_module *,abc_error *);
    void (*abc_vm_free)(abc_vm *);
    abc_status (*abc_vm_call)(abc_vm *,const abc_module *,const char *,const uint64_t *,size_t,uint64_t *,size_t,size_t *,abc_error *);
} runtime;
static void check(int ok,const char *why) {if(!ok){fprintf(stderr,"%s\n",why);exit(1);}}
#define LOAD(NAME) do { void *symbol=dlsym(r.library,#NAME);check(symbol!=NULL,dlerror());_Static_assert(sizeof symbol==sizeof r.NAME,"function pointer size");memcpy(&r.NAME,&symbol,sizeof symbol); } while(0)
static runtime open_runtime(const char *path) {
    runtime r={0};r.library=dlopen(path,RTLD_NOW|RTLD_LOCAL);check(r.library!=NULL,dlerror());
    LOAD(abc_module_load);LOAD(abc_module_free);LOAD(abc_vm_create);LOAD(abc_vm_load);LOAD(abc_vm_free);LOAD(abc_vm_call);
    return r;
}
static double clock_ns(void) {struct timespec t;check(clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t)==0,"clock");return 1e9*(double)t.tv_sec+(double)t.tv_nsec;}
static int compare(const void *a,const void *b) {double x=*(const double *)a,y=*(const double *)b;return (x>y)-(x<y);}
int main(int argc,char **argv) {
    check(argc==4||argc==5,"usage: measure-runtime-paired before.so after.so manifest [reverse]");
    runtime engines[2];
    if(argc==5&&strcmp(argv[4],"load-reverse")==0) {engines[1]=open_runtime(argv[2]);engines[0]=open_runtime(argv[1]);}
    else {engines[0]=open_runtime(argv[1]);engines[1]=open_runtime(argv[2]);}
    FILE *manifest=fopen(argv[3],"r");check(manifest!=NULL,"manifest");
    char name[128],path[1024],input_text[64],expected_text[64];unsigned mode;
    puts("fixture,mode,before_ns,after_ns,delta_percent");
    while(fscanf(manifest,"%127s %u %1023s %63s %63s",name,&mode,path,input_text,expected_text)==5) {
        FILE *file=fopen(path,"rb");check(file!=NULL,"bytecode");
        check(fseek(file,0,SEEK_END)==0,"seek");long length=ftell(file);check(length>=0,"length");rewind(file);
        void *image=malloc((size_t)length);check(image!=NULL,"image allocation");check(fread(image,1,(size_t)length,file)==(size_t)length,"image read");fclose(file);
        abc_module *modules[2]={0};abc_vm *vms[2]={0};abc_error errors[2];
        uint64_t input=strtoull(input_text,NULL,0),expected=strtoull(expected_text,NULL,0),outputs[2]={0};size_t counts[2]={0};
        double times[2][15];
        for(unsigned i=0;i<2;i++) {
            runtime *r=&engines[i];abc_limits limits={.mode=(abc_execution_mode)mode};
            check(r->abc_module_load(image,(size_t)length,&modules[i],&errors[i])==ABC_OK,errors[i].message);
            check(r->abc_vm_create(&limits,&vms[i],&errors[i])==ABC_OK,errors[i].message);
            check(r->abc_vm_load(vms[i],modules[i],&errors[i])==ABC_OK,errors[i].message);
            for(unsigned warm=0;warm<20000;warm++) check(r->abc_vm_call(vms[i],modules[i],"main",&input,1,&outputs[i],1,&counts[i],&errors[i])==ABC_OK,errors[i].message);
        }
        /* Keep samples long enough to reduce timer noise, and alternate both orders.
         * Bytecode length controls sample work, never language execution limits. */
        unsigned iterations=(unsigned)(100000000/(length+100));if(iterations<100000)iterations=100000;
        for(unsigned sample=0;sample<15;sample++) for(unsigned pass=0;pass<2;pass++) {
            unsigned i=(sample+pass+(argc==5))%2;runtime *r=&engines[i];int status=0;
            double start=clock_ns();
            for(unsigned n=0;n<iterations;n++) status|=r->abc_vm_call(vms[i],modules[i],"main",&input,1,&outputs[i],1,&counts[i],&errors[i]);
            times[i][sample]=(clock_ns()-start)/iterations;check(status==ABC_OK,errors[i].message);
            check(counts[i]==1&&outputs[i]==expected,"exact result");
        }
        for(unsigned i=0;i<2;i++){qsort(times[i],15,sizeof(double),compare);engines[i].abc_vm_free(vms[i]);engines[i].abc_module_free(modules[i]);}
        double a=times[0][7],b=times[1][7];printf("%s,%u,%.3f,%.3f,%+.2f\n",name,mode,a,b,100*(b/a-1));fflush(stdout);free(image);
    }
    fclose(manifest);for(unsigned i=0;i<2;i++)dlclose(engines[i].library);return 0;
}
