#define _GNU_SOURCE
#include "abc.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t);
    return (double)t.tv_sec+(double)t.tv_nsec*1e-9;
}
static void require(abc_status status,const abc_error *error) {
    if(status!=ABC_OK){fprintf(stderr,"%s at %u: %s\n",abc_status_name(status),error->offset,error->message);exit(1);}
}
int main(int argc,char **argv) {
    if(argc!=3)return 2;
    int trials=atoi(argv[2]);if(trials<1||trials>101)return 2;
    abc_module *module=NULL;abc_vm *vm=NULL;abc_error error;
    require(abc_module_read(argv[1],&module,&error),&error);
    abc_limits limits={.stack_cells=65536,.mode=ABC_EXEC_INTERPRETED};
    double start=now();require(abc_vm_create(&limits,&vm,&error),&error);
    require(abc_vm_load(vm,module,&error),&error);double prepare=now()-start;
    uint64_t result=0,expected=0;size_t count=0;
    start=now();require(abc_vm_call(vm,module,"main",NULL,0,&expected,1,&count,&error),&error);
    double warmup=now()-start;if(count!=1)return 3;
    double samples[101];
    for(int i=0;i<trials;i++){
        start=now();require(abc_vm_call(vm,module,"main",NULL,0,&result,1,&count,&error),&error);
        samples[i]=now()-start;if(count!=1||result!=expected)return 4;
    }
    printf("%" PRIu64 " %.9f %.9f",expected,prepare,warmup);
    for(int i=0;i<trials;i++)printf(" %.9f",samples[i]);putchar('\n');
    abc_vm_free(vm);abc_module_free(module);return 0;
}
