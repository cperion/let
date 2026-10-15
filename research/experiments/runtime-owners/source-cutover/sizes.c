/* Source-fixture storage measurement, not a timing/performance benchmark. */
#include "residualize.h"
#include "lifetime.h"
#include <stdio.h>
int main(int argc,char **argv) {
    for(int i=1;i<argc;i++) {
        abc_module *m=NULL;abc_vm *vm=NULL;abc_error e;
        abc_limits limits={.mode=ABC_EXEC_INTERPRETED};
        if(abc_module_read(argv[i],&m,&e)!=ABC_OK||abc_vm_create(&limits,&vm,&e)!=ABC_OK||abc_vm_load(vm,m,&e)!=ABC_OK){fprintf(stderr,"%s\n",e.message);return 1;}
        uint32_t entries=0,max_homes=0;
        for(uint32_t f=0;f<m->function_count;f++)if(m->functions[f].c_entry){
            const abc_function *fn=&m->functions[f];uint32_t homes=fn->max_a+fn->max_b+fn->max_c+1;
            entries++;if(homes>max_homes)max_homes=homes;
        }
        abc_execution_image *code=vm->images->lifecycle;
        printf("%s: bytecode=%zu image=%u lifecycle-functions=%u relocations=%u native-body=%zu native-storage=%zu max-callback-home-bytes=%u owner=%zu activation-header=%zu\n",
            argv[i],m->code_size,m->image_size,entries,m->c_entry_count,code->code_size,code->storage_size,max_homes*8,sizeof(abc_owner),sizeof(abc_cleanup_frame));
        abc_vm_free(vm);abc_module_free(m);
    }
    return 0;
}
