/* Execute original and optimized foreign fixtures with the same host bindings. */
#include "abc.h"
#include <assert.h>
#include <stdio.h>
static unsigned calls;
static uint64_t difference(uint64_t left,uint64_t right) {
    calls++;assert(left==10&&right==3);return left-right;
}
static void observe(uint64_t left,uint64_t right) {
    calls++;assert(left==10&&right==3);
}
int main(int argc,char **argv) {
    assert(argc==3);
    for(int file=1;file<argc;file++) {
        abc_module *module=NULL;abc_error error;
        assert(abc_module_read(argv[file],&module,&error)==ABC_OK);
        for(int mode=ABC_EXEC_INTERPRETED;mode<=ABC_EXEC_THREADED;mode++) {
            abc_limits limits={.stack_cells=64,.mode=(abc_execution_mode)mode};
            abc_vm *vm=NULL;uint64_t argument=111,results[2]={999,999};size_t count=0;
            assert(abc_vm_create(&limits,&vm,&error)==ABC_OK);
            assert(abc_vm_bind_foreign(vm,"difference",(abc_foreign_address)difference,&error)==ABC_OK);
            assert(abc_vm_bind_foreign(vm,"observe",(abc_foreign_address)observe,&error)==ABC_OK);
            assert(abc_vm_load(vm,module,&error)==ABC_OK);calls=0;
            abc_status status=abc_vm_call(vm,module,"main",&argument,1,results,2,&count,&error);
            if(status!=ABC_OK)fprintf(stderr,"%s: %s at %u\n",argv[file],error.message,error.offset);
            assert(status==ABC_OK&&count==2&&results[0]==7&&results[1]==111&&calls==1);
            abc_vm_free(vm);
        }
        abc_module_free(module);
    }
    puts("foreign original/optimized: ordered arguments, live prefix and single effect PASS");
    return 0;
}
