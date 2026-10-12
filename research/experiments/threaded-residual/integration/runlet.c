#define _POSIX_C_SOURCE 200809L
#include "abc.h"
#include "vm_internal.h"
#include "residualize.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static double now(void){struct timespec t;if(clock_gettime(CLOCK_MONOTONIC,&t))abort();return t.tv_sec+t.tv_nsec*1e-9;}
static int compare(const void *a,const void *b){double x=*(const double *)a,y=*(const double *)b;return (x>y)-(x<y);}
static int fail(const abc_error *error){fprintf(stderr,"%u:%u %s\n",error->status,error->offset,error->message);return 1;}
int main(int argc,char **argv){
    if(argc!=4){fprintf(stderr,"runlet off|threaded|lazy|eager MODULE EXPECTED\n");return 2;}
    abc_execution_mode mode;
    if(!strcmp(argv[1],"off"))mode=ABC_EXEC_INTERPRETED;
    else if(!strcmp(argv[1],"threaded"))mode=ABC_EXEC_THREADED;
    else if(!strcmp(argv[1],"lazy"))mode=ABC_EXEC_LAZY;
    else if(!strcmp(argv[1],"eager"))mode=ABC_EXEC_COMPILED;
    else return 2;
    const uint64_t expected=strtoull(argv[3],NULL,10);
    abc_error error;abc_module *module=NULL;abc_vm *vm=NULL;
    double t=now();if(abc_module_read(argv[2],&module,&error)!=ABC_OK)return fail(&error);double read=now()-t;
    abc_limits limits={.stack_cells=1u<<20,.mode=mode};t=now();
    if(abc_vm_create(&limits,&vm,&error)!=ABC_OK||abc_vm_load(vm,module,&error)!=ABC_OK)return fail(&error);
    double prepare=now()-t,first=0,times[7];
    for(unsigned i=0;i<8;i++){
        uint64_t value=0;size_t count=0;t=now();
        abc_status status=abc_vm_call(vm,module,"main",NULL,0,&value,1,&count,&error);
        double elapsed=now()-t;if(status!=ABC_OK)return fail(&error);
        if(count!=1||value!=expected){fprintf(stderr,"incorrect result\n");return 1;}
        if(!i)first=elapsed;else times[i-1]=elapsed;
    }
    qsort(times,7,sizeof *times,compare);
    abc_execution_image *image=vm->images->execution;
    printf("%.9f %.9f %.9f %.9f %zu %zu %zu\n",read,prepare,first,times[3],
        image?image->code_size:0,image?image->storage_size:0,image?image->compiled_versions:0);
    abc_vm_free(vm);abc_module_free(module);return 0;
}
