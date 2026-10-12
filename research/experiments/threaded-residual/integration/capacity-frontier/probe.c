#include "vm_internal.h"
#include "residualize.h"
#include "threaded.h"
#include <assert.h>
#include <inttypes.h>
int main(int argc,char **argv){
    assert(argc==2);abc_module *m=NULL;abc_vm *vm=NULL;abc_error error;
    abc_limits limits={.mode=ABC_EXEC_THREADED};
    assert(abc_module_read(argv[1],&m,&error)==ABC_OK);
    assert(abc_vm_create(&limits,&vm,&error)==ABC_OK);
    assert(abc_vm_load(vm,m,&error)==ABC_OK);
    abc_execution_image *image=vm->images->execution;
    const abc_thread_word *t=(const abc_thread_word *)image->code;
    for(size_t i=0;i<image->code_size/8;){
        unsigned form=0;while(form<ABC_FORM_COUNT&&abc_thread_forms[form].handler!=t[i].handler)form++;
        assert(form<ABC_FORM_COUNT&&abc_thread_forms[form].words);
        for(unsigned stack=0;stack<3;stack++)if(form==ABC_FORM_GUARD(stack))
            printf("guard %c: bytes=%"PRIu64" packed_error=%"PRIx64"\n",'A'+stack,t[i+1].bits,t[i+3].bits);
        i+=abc_thread_forms[form].words;
    }
    abc_vm_free(vm);abc_module_free(m);return 0;
}
