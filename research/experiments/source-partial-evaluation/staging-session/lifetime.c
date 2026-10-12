#include "abc.h"
#include <stdio.h>
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    abc_module *module=NULL;abc_vm *vm=NULL;abc_error error;
    abc_limits limits={.mode=ABC_EXEC_LAZY};
    if(abc_module_read(argv[1],&module,&error)!=ABC_OK)return 3;
    if(abc_vm_create(&limits,&vm,&error)!=ABC_OK)return 4;
    if(abc_vm_load(vm,module,&error)!=ABC_OK)return 5;
    uint64_t result=0;size_t count=0;
    if(abc_vm_call(vm,module,"main",NULL,0,&result,1,&count,&error)!=ABC_OK)return 6;
    if(count!=1||result!=42)return 7;
    abc_module_free(module); /* The public API says the VM retains this module. */
    abc_vm_free(vm);
    puts("released caller module ownership before VM destruction");
    return 0;
}
