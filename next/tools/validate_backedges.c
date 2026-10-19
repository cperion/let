/* Native structural regression, in addition to mirrored output/pressure tests.
 * Inspect existing version accounting, not host-specific instruction byte sizes. */
#include "residualize.h"
#include <stdio.h>
#include <stdlib.h>

static void require(int valid,const char *message) {
    if(!valid){fprintf(stderr,"backedge validation: %s\n",message);exit(1);}
}
int main(int argc,char **argv) {
    require(argc==2,"expected fixture module");
    abc_error error={0};abc_module *module=NULL;
    require(abc_module_read(argv[1],&module,&error)==ABC_OK,error.message);
    for(unsigned mode=0;mode<4;mode++) {
        abc_limits limits={.stack_cells=64,.mode=(abc_execution_mode)mode};abc_vm *vm=NULL;
        require(abc_vm_create(&limits,&vm,&error)==ABC_OK,error.message);
        require(abc_vm_load(vm,module,&error)==ABC_OK,error.message);
        for(unsigned pass=0;pass<2;pass++) {
            uint64_t result=0;size_t count=0;
            require(abc_vm_call(vm,module,"main",NULL,0,&result,1,&count,&error)==ABC_OK,error.message);
            require(count==1&&result==6,"loop result or per-call image reset changed");
            if(mode!=ABC_EXEC_INTERPRETED) {
                abc_execution_image *native=vm->images->execution;
                /* Entry + known header/body + two register placements, each
                 * with header/body/exit = 9. Lazy needs just one of the exits.
                 * Fewer versions are allowed; gratuitous HOME versions are not. */
                size_t bound=mode==ABC_EXEC_LAZY?8:9;
                require(native&&native->compiled_versions>0&&native->compiled_versions<=bound,
                    "constant weakening introduced extra loop realizations");
            }
        }
        abc_vm_free(vm);
    }
    abc_module_free(module);
    puts("validated backedge register placement: four modes, repeated calls and residual version bounds");
    return 0;
}
