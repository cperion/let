#include "abc.h"
#include "vm_internal.h"
#include "residualize.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static unsigned noted;
static double host_mix(uint64_t x,double y) { return (double)x+y+0.5; }
static uint64_t host_wide(uint64_t a,double b,uint64_t c,const uint64_t *d,double e,uint64_t f,double g,const uint64_t *h,double i,uint64_t j) { return a+(uint64_t)b+c+*d+(uint64_t)e+f+(uint64_t)g+*h+(uint64_t)i+j; }
static void host_note(uint64_t x) { noted=(unsigned)x; }
static uint64_t bits(double d) { uint64_t x; memcpy(&x,&d,8); return x; }
static int fail(const char *what,const abc_error *e) {
    fprintf(stderr,"validate-api: %s: %s\n",what,e->message); return 1;
}
int main(int argc,char **argv) {
    if(argc<2||argc>5) { fprintf(stderr,"usage: validate-api callables.abc [virtual.abc] [foreign.abc] [dynamic-gc.abc]\n"); return 2; }
    abc_module *m=NULL; abc_vm *v=NULL; abc_error e; abc_limits limits={.mode=ABC_EXEC_COMPILED};
    uint64_t add=0,sub=0,cell=40,args[3],result=0; size_t n=0; abc_site_stats stats;
    if(abc_module_read(argv[1],&m,&e)!=ABC_OK) return fail("read",&e);
    if(abc_module_export_address(m,"add",&add,&e)!=ABC_OK || abc_module_export_address(m,"sub",&sub,&e)!=ABC_OK) return fail("address",&e);
    if(abc_vm_create(&limits,&v,&e)!=ABC_OK || abc_vm_load(v,m,&e)!=ABC_OK) return fail("load",&e);
    if(abc_vm_site_stats(v,m,&stats,&e)!=ABC_OK || stats.transitions || stats.specific || stats.final_generic) return fail("initial stats",&e);
    args[0]=(uint64_t)(uintptr_t)&cell; args[1]=2; args[2]=add;
    if(abc_vm_call(v,m,"invoke",args,3,&result,1,&n,&e)!=ABC_OK || n!=1 || result!=42) return fail("specific call",&e);
    if(abc_vm_site_stats(v,m,&stats,&e)!=ABC_OK || stats.transitions || stats.specific || stats.final_generic) return fail("direct resolver stats",&e);
    args[2]=sub;
    if(abc_vm_call(v,m,"invoke",args,3,&result,1,&n,&e)!=ABC_OK || result!=38) return fail("mismatch call",&e);
    if(abc_vm_site_stats(v,m,&stats,&e)!=ABC_OK || stats.transitions || stats.specific || stats.final_generic) return fail("stable direct resolver stats",&e);
    args[2]=0;
    if(abc_vm_call(v,m,"invoke",args,3,&result,1,&n,&e)!=ABC_INVALID) return fail("invalid final target",&e);
    if(abc_vm_site_stats(v,m,&stats,&e)!=ABC_OK || stats.transitions || stats.specific || stats.final_generic) return fail("invalid direct resolver stats",&e);
    abc_vm_free(v); abc_module_free(m);
    if(argc>=3) {
        m=NULL; v=NULL; result=0; n=0;
        if(abc_module_read(argv[2],&m,&e)!=ABC_OK) return fail("virtual read",&e);
        if(abc_vm_create(&limits,&v,&e)!=ABC_OK || abc_vm_load(v,m,&e)!=ABC_OK) return fail("virtual load",&e);
        abc_native_image *native=v->images?v->images->native:NULL;
        if(!native) { fprintf(stderr,"validate-api: residual native image is missing\n"); return 1; }
        if(abc_vm_call(v,m,"main",NULL,0,&result,1,&n,&e)!=ABC_OK || n!=1 || result!=42) return fail("virtual call",&e);
        abc_vm_free(v);v=NULL;limits.mode=ABC_EXEC_LAZY;
        if(abc_vm_create(&limits,&v,&e)!=ABC_OK||abc_vm_load(v,m,&e)!=ABC_OK)return fail("lazy load",&e);native=v->images?v->images->native:NULL;
        if(!native||!native->lazy||native->compiled_versions){fprintf(stderr,"validate-api: lazy residual entries activated before first call\n");return 1;}
        if(abc_vm_call(v,m,"main",NULL,0,&result,1,&n,&e)!=ABC_OK||n!=1||result!=42)return fail("lazy call",&e);
        size_t compiled=native->compiled_versions;if(!compiled){fprintf(stderr,"validate-api: lazy residual entry was not activated\n");return 1;}
        if(abc_vm_call(v,m,"main",NULL,0,&result,1,&n,&e)!=ABC_OK||native->compiled_versions!=compiled){fprintf(stderr,"validate-api: lazy version was not reused\n");return 1;}
        abc_vm_free(v); abc_module_free(m);limits.mode=ABC_EXEC_COMPILED;
    }
    if(argc>=4) {
        abc_module *fm=NULL; if(abc_module_read(argv[3],&fm,&e)!=ABC_OK)return fail("foreign read",&e);
        for(unsigned mode=0;mode<3;mode++){limits.mode=(abc_execution_mode)mode;v=NULL;
            if(abc_vm_create(&limits,&v,&e)!=ABC_OK)return fail("foreign VM",&e);
            if(abc_vm_load(v,fm,&e)!=ABC_NOT_FOUND){fprintf(stderr,"validate-api: unbound foreign load accepted\n");return 1;}abc_vm_free(v);v=NULL;
            if(abc_vm_create(&limits,&v,&e)!=ABC_OK ||
               abc_vm_bind_foreign(v,"host_mix",(abc_foreign_address)host_mix,&e)!=ABC_OK ||
               abc_vm_bind_foreign(v,"host_wide",(abc_foreign_address)host_wide,&e)!=ABC_OK ||
               abc_vm_bind_foreign(v,"host_note",(abc_foreign_address)host_note,&e)!=ABC_OK || abc_vm_load(v,fm,&e)!=ABC_OK)return fail("foreign load",&e);
            uint64_t fa[10]={4,bits(2.5),1,2,3,bits(4.0),5,bits(6.0),7,bits(8.0)};
            if(abc_vm_call(v,fm,"mix",fa,2,&result,1,&n,&e)!=ABC_OK||result!=bits(7.0))return fail("foreign mixed call",&e);
            uint64_t pv=4,qv=8,wa[10]={1,bits(2.0),3,(uint64_t)(uintptr_t)&pv,bits(5.0),6,bits(7.0),(uint64_t)(uintptr_t)&qv,bits(9.0),10};
            if(abc_vm_call(v,fm,"wide",wa,10,&result,1,&n,&e)!=ABC_OK||result!=55)return fail("foreign wide call",&e);
            noted=0;fa[0]=37;if(abc_vm_call(v,fm,"note",fa,1,&result,1,&n,&e)!=ABC_OK||result!=37||noted!=37)return fail("foreign void call",&e);
            abc_vm_free(v);
        } abc_module_free(fm);
    }
    if(argc>=5) {
        abc_module *dm=NULL;if(abc_module_read(argv[4],&dm,&e)!=ABC_OK)return fail("dynamic read",&e);
        for(unsigned mode=0;mode<3;mode++){limits.mode=(abc_execution_mode)mode;v=NULL;result=0;n=0;if(abc_vm_create(&limits,&v,&e)!=ABC_OK||abc_vm_load(v,dm,&e)!=ABC_OK)return fail("dynamic load",&e);if(abc_vm_call(v,dm,"build",NULL,0,NULL,0,&n,&e)!=ABC_OK||n)return fail("dynamic build",&e);if(abc_vm_request_collection(v,&e)!=ABC_OK)return fail("collection request",&e);if(abc_vm_call(v,dm,"check",NULL,0,&result,1,&n,&e)!=ABC_OK||n!=1||result!=1)return fail("root after collection",&e);if(abc_vm_request_collection(v,&e)!=ABC_OK||abc_vm_call(v,dm,"check_managed",NULL,0,&result,1,&n,&e)!=ABC_OK||n!=1||result!=77)return fail("managed interior root after collection",&e);abc_vm_free(v);}abc_module_free(dm);
    }
    puts("validated eager/lazy residual callable resolution, foreign calls, Whippet module/mutated managed-interior roots, and stable linkage"); return 0;
}

