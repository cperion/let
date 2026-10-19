/* Signed frontiers must not inflate nonnegative capacity knowledge. */
#include "internal.h"
#include <assert.h>
int main(int argc,char **argv){
    assert(argc==2);abc_module *module=NULL;abc_error error;unsigned checks=0;
    assert(abc_module_read(argv[1],&module,&error)==ABC_OK);
    const char *names[]={"runA","afterA","runB","afterB","middleA","middleB"};
    const unsigned roots[]={0,2,5,7,3,8},calls[]={0,3,5,8,3,8};
    for(unsigned mode=0;mode<4;mode++)for(size_t capacity=2;capacity<=6;capacity++){
        abc_vm *vm=NULL;abc_limits limits={.mode=(abc_execution_mode)mode,.stack_cells=capacity};
        assert(abc_vm_create(&limits,&vm,&error)==ABC_OK);
        assert(abc_vm_load(vm,module,&error)==ABC_OK);
        for(unsigned repeat=0;repeat<3;repeat++)for(unsigned test=0;test<6;test++){
            uint64_t argument=40,result=UINT64_C(0xabcdef);size_t count=99;
            /* The interpreter stores the inner continuation; residual virtual
               calls omit it under the existing physical-capacity policy. */
            size_t required=((test&1)||test>=4)?(mode==ABC_EXEC_INTERPRETED?6:5):3;
            abc_status status=abc_vm_call(vm,module,names[test],&argument,test>=4?0:1,&result,1,&count,&error);
            if(capacity>=required){
                if(status!=ABC_OK||count!=1||result!=42)goto failed;
            }else{
                uint32_t pc=module->functions[capacity<3&&test<4?roots[test]:calls[test]].entry;
                if(status!=ABC_STACK||error.offset!=pc||result!=UINT64_C(0xabcdef))goto failed;
            }
            checks++;continue;
failed:
            fprintf(stderr,"capacity frontier: mode=%u cap=%zu export=%s status=%u pc=%u result=%llu count=%zu\n",
                mode,capacity,names[test],status,error.offset,(unsigned long long)result,count);
            abc_vm_free(vm);abc_module_free(module);return 1;
        }
        abc_vm_free(vm);
    }
    abc_module_free(module);
    printf("validated %u capacity-frontier cases: A/B shrink, subsequent allocation, original PCs, tight limits and repeated calls\n",checks);
    return 0;
}
