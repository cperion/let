/* Public ownership contract: loaded VMs retain modules independently of callers. */
#include "abc.h"
#include <stdio.h>

static int call(abc_vm *vm, const abc_module *module, abc_error *error) {
    uint64_t result=0; size_t count=0;
    if(abc_vm_call(vm,module,"main",NULL,0,&result,1,&count,error)!=ABC_OK) return 0;
    if(count!=1 || result!=42) {
        fprintf(stderr,"validate-lifetime: unexpected result\n"); return 0;
    }
    return 1;
}
int main(int argc, char **argv) {
    if(argc!=2) { fprintf(stderr,"usage: validate-lifetime module.abc\n"); return 2; }
    unsigned checks=0;
    for(unsigned first=0;first<4;first++) for(unsigned second=0;second<4;second++)
    for(unsigned invocation=0;invocation<3;invocation++) {
        abc_module *module=NULL; abc_vm *vm[2]={NULL,NULL}; abc_error error;
        abc_limits limits={.mode=(abc_execution_mode)first};
        if(abc_module_read(argv[1],&module,&error)!=ABC_OK) goto failed;
        if(abc_vm_create(&limits,&vm[0],&error)!=ABC_OK || abc_vm_load(vm[0],module,&error)!=ABC_OK) goto failed;
        limits.mode=(abc_execution_mode)second;
        if(abc_vm_create(&limits,&vm[1],&error)!=ABC_OK || abc_vm_load(vm[1],module,&error)!=ABC_OK) goto failed;
        if(invocation==1 && (!call(vm[0],module,&error) || !call(vm[1],module,&error))) goto failed;
        /* module remains a valid borrowed pointer while either VM owns an image. */
        abc_module_free(module);
        if(invocation==2 && !call(vm[0],module,&error)) goto released_failure;
        abc_vm_free(vm[0]); vm[0]=NULL;
        if(invocation==2 && !call(vm[1],module,&error)) goto released_failure;
        abc_vm_free(vm[1]);
        checks++;
        continue;
failed:
        fprintf(stderr,"validate-lifetime: %s\n",error.message);
        abc_vm_free(vm[0]); abc_vm_free(vm[1]); abc_module_free(module); return 1;
released_failure:
        fprintf(stderr,"validate-lifetime: %s\n",error.message);
        abc_vm_free(vm[0]); abc_vm_free(vm[1]); return 1;
    }
    printf("validated %u public module/VM lifetime cases (all mode pairs, uncalled and called images)\n",checks);
    return 0;
}
