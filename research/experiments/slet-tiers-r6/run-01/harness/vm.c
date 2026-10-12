#define _GNU_SOURCE
#include "abc.h"
#include "vm_internal.h"
#include "residualize.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t); return (double)t.tv_sec+(double)t.tv_nsec*1e-9; }
static int fail(const char *where,const abc_error *e) { fprintf(stderr,"%s: %s (%s)\n",where,e->message,abc_status_name(e->status)); return 1; }
int main(int argc,char **argv) {
    if(argc!=5)return 2;
    int trials=atoi(argv[4]); if(trials<1||trials>1000)return 2;
    abc_execution_mode mode=!strcmp(argv[1],"eager")?ABC_EXEC_COMPILED:!strcmp(argv[1],"lazy")?ABC_EXEC_LAZY:!strcmp(argv[1],"interpreter")?ABC_EXEC_INTERPRETED:-1;
    if((int)mode<0)return 2;
    abc_error error; abc_module *module=NULL; abc_vm *vm=NULL;
    double t=now(); if(abc_module_read(argv[2],&module,&error)!=ABC_OK)return fail("read",&error); double read=now()-t;
    abc_limits limits={.stack_cells=UINT32_C(1)<<20,.mode=mode};
    t=now(); if(abc_vm_create(&limits,&vm,&error)!=ABC_OK||abc_vm_load(vm,module,&error)!=ABC_OK)return fail("prepare",&error); double prepare=now()-t;
    uint64_t input=strtoull(argv[3],NULL,10),result=0; size_t count=0;
    double *samples=calloc((size_t)trials,sizeof *samples); if(!samples)return 2;
    t=now(); if(abc_vm_call(vm,module,"main",&input,1,&result,1,&count,&error)!=ABC_OK)return fail("first",&error); double first=now()-t;
    if(count!=1)return 3;
    uint64_t expected=result;
    for(int i=0;i<trials;i++) {
        t=now(); if(abc_vm_call(vm,module,"main",&input,1,&result,1,&count,&error)!=ABC_OK)return fail("sample",&error); samples[i]=now()-t;
        if(count!=1||result!=expected)return 3;
    }
    size_t bytes=vm->images&&vm->images->native?vm->images->native->code_size:0;
    printf("{\"result\":%llu,\"read\":%.9f,\"prepare\":%.9f,\"first\":%.9f,\"native_bytes\":%zu,\"samples\":[",(unsigned long long)result,read,prepare,first,bytes);
    for(int i=0;i<trials;i++)printf("%s%.9f",i?",":"",samples[i]);
    puts("]}"); free(samples); abc_vm_free(vm); abc_module_free(module); return 0;
}
