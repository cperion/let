#include "vm_internal.h"
#include "residualize.h"
#include "execution_emit.h"
#include "generated/runtime_primitives.h"

/* This validates compiler-private release code, not arbitrary pointer bytecode.
 * Preparation specializes ordinary checked ABC through the shared computation and
 * allocator into a direct callable entry. No interpreter/field-plan fallback. */
static abc_status release_function(abc_exec_context *context,uint64_t address,unsigned *index) {
    const abc_module *m=context->m;uintptr_t base=(uintptr_t)m->code;
    const abc_function *fn=address>=base&&address-base<m->code_size?abc_function_entry(m,(uint32_t)(address-base)):NULL;
    if(!fn||fn->arguments!=1||fn->results||fn->argument_kinds[0]!=ABC_KIND_ADDR||fn->hidden_bytes||fn->has_halt)
        return abc_fail(&context->error,ABC_ARGUMENTS,UINT32_MAX,"invalid release operation signature");
    for(uint32_t pc=fn->entry;pc<fn->end;pc+=abc_instruction_length(m->code+pc)) {
        const abc_instruction_metadata *op=abc_instruction_info(m->code+pc);
        if(op->kind==K_CALL||op->kind==K_TCALL||op->kind==K_ICALL||op->kind==K_ITCALL||op->kind==K_ABORT||op->kind==K_HALT||
           op->transfer_kind==ABC_TRANSFER_CHECK||op->operation==ABC_OPERATION_DIVU||op->operation==ABC_OPERATION_DIVS||
           op->operation==ABC_OPERATION_REMU||op->operation==ABC_OPERATION_REMS||op->operation==ABC_OPERATION_POWS||
           op->operation==ABC_OPERATION_F2IS||op->operation==ABC_OPERATION_F2IU)
            return abc_fail(&context->error,ABC_ARGUMENTS,UINT32_MAX,"release operations cannot invoke ABC callbacks or abort");
        if(op->kind==K_FCALL) {
            const abc_extern *ext=&m->externs[abc_u16(m->code+pc+1)];
            int id=abc_primitive_index(ext->name);
            if(id!=ABC_PRIMITIVE_OWNER_RELEASE_FIELD&&id!=ABC_PRIMITIVE_OWNER_DATA&&
               id!=ABC_PRIMITIVE_OWNER_INITIALIZED&&id!=ABC_PRIMITIVE_OWNER_ENQUEUE)
                return abc_fail(&context->error,ABC_ARGUMENTS,UINT32_MAX,"release operation has a forbidden runtime/foreign effect");
        }
    }
    *index=(unsigned)(fn-m->functions);return ABC_OK;
}
abc_status abc_release_bind(abc_exec_context *context,uint64_t address,const abc_release_code **out) {
    abc_image *image=context->image;
    for(abc_release_code *p=image->releases;p;p=p->next)
        if(address==(uintptr_t)(context->m->code+context->m->functions[p->function].entry)){*out=p;return ABC_OK;}
    unsigned function;abc_status status=release_function(context,address,&function);
    if(status!=ABC_OK)return status;
    abc_release_code *code=NULL;
    status=abc_compile_release(context->m,image->bytes,function,&code,&context->error);
    if(status!=ABC_OK)return status;
    code->next=image->releases;image->releases=code;*out=code;return ABC_OK;
}
void abc_release_code_free(abc_release_code *code) {
    if(!code)return;code->emitter->ops->destroy(code->emitter);free(code);
}
