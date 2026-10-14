#include "vm_internal.h"
#include "residualize.h"
#include "generated/runtime_primitives.h"

static abc_status holding_entry(abc_exec_context *context,uint64_t address,unsigned arguments,int copy,unsigned *index) {
    const abc_module *m=context->m;uintptr_t base=(uintptr_t)m->code;
    const abc_function *fn=address>=base&&address-base<m->code_size?abc_function_entry(m,(uint32_t)(address-base)):NULL;
    if(!fn||fn->arguments!=arguments||fn->results||fn->hidden_bytes||fn->has_halt)
        return abc_fail(&context->error,ABC_ARGUMENTS,UINT32_MAX,"invalid holding operation signature");
    for(unsigned i=0;i<arguments;i++)if(fn->argument_kinds[i]!=ABC_KIND_ADDR)
        return abc_fail(&context->error,ABC_ARGUMENTS,UINT32_MAX,"holding inputs must be addresses");
    for(uint32_t pc=fn->entry;pc<fn->end;pc+=abc_instruction_length(m->code+pc)) {
        const abc_instruction_metadata *op=abc_instruction_info(m->code+pc);
        if(op->kind==K_CALL||op->kind==K_TCALL||op->kind==K_ICALL||op->kind==K_ITCALL||op->kind==K_ABORT||op->kind==K_HALT||
           op->transfer_kind==ABC_TRANSFER_CHECK||op->operation==ABC_OPERATION_DIVU||op->operation==ABC_OPERATION_DIVS||
           op->operation==ABC_OPERATION_REMU||op->operation==ABC_OPERATION_REMS||op->operation==ABC_OPERATION_POWS||
           op->operation==ABC_OPERATION_F2IS||op->operation==ABC_OPERATION_F2IU)
            return abc_fail(&context->error,ABC_ARGUMENTS,UINT32_MAX,"holding operations cannot invoke ABC callbacks or abort");
        if(op->kind==K_FCALL) {
            const abc_extern *ext=&m->externs[abc_u16(m->code+pc+1)];int id=abc_primitive_index(ext->name);
            if(id!=ABC_PRIMITIVE_OWNER_DATA&&id!=ABC_PRIMITIVE_OWNER_INITIALIZED&&id!=ABC_PRIMITIVE_OWNER_ENQUEUE&&
                !(copy&&(id==ABC_PRIMITIVE_OWNER_HOLD||id==ABC_PRIMITIVE_OWNER_COMMIT)))
                return abc_fail(&context->error,ABC_ARGUMENTS,UINT32_MAX,"holding operation has a forbidden runtime/foreign effect");
        }
    }
    *index=(unsigned)(fn-m->functions);return ABC_OK;
}
abc_status abc_type_bind(abc_exec_context *context,size_t size,size_t align,unsigned kind,uint64_t copy,uint64_t release,const abc_type_ops **out) {
    abc_image *image=context->image;abc_error *error=&context->error;
    if(!align||(align&(align-1))||kind>ABC_OWNER_SHARED)
        return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"invalid generated holding layout");
    /* Published descriptors already checked immutable module entries. */
    for(abc_type_ops *p=image->type_ops;p;p=p->next)
        if(p->payload_size==size&&p->payload_align==align&&p->owner_kind==kind&&
           copy==(uintptr_t)(context->m->code+context->m->functions[p->copy_holding].entry)&&
           release==(uintptr_t)(context->m->code+context->m->functions[p->release_holdings].entry)){*out=p;return ABC_OK;}
    unsigned ci,ri;abc_status status=holding_entry(context,copy,2,1,&ci);
    if(status==ABC_OK)status=holding_entry(context,release,1,0,&ri);
    if(status!=ABC_OK)return status;
    abc_type_ops *ops=malloc(sizeof *ops);
    if(!ops)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"holding descriptor allocation failed");
    *ops=(abc_type_ops){size,align,(abc_owner_kind)kind,ci,ri,image,NULL};
    context->pending_type=ops;*out=ops;return ABC_OK;
}
abc_status abc_type_publish(abc_exec_context *context) {
    abc_type_ops *ops=context->pending_type;context->pending_type=NULL;
    if(!ops)return ABC_OK;
    const abc_function *r=&ops->image->module->functions[ops->release_holdings];size_t cells=r->max_c+1;
    if(cells<r->max_a)cells=r->max_a;if(cells<r->max_b)cells=r->max_b;
    /* Finish reservation/preparation after source execution returns. Publish
     * only after success; source never observes an unprepared descriptor. */
    abc_status status=abc_context_reserve(&context->worker->cleanup,cells,&context->error);
    if(status==ABC_OK)status=abc_execution_prepare_holding(ops->image->execution,ops->release_holdings,&context->error);
    if(status==ABC_OK)status=abc_execution_prepare_holding(ops->image->execution,ops->copy_holding,&context->error);
    if(status!=ABC_OK){free(ops);context->error.offset=context->operation_pc;return status;}
    ops->next=ops->image->type_ops;ops->image->type_ops=ops;return ABC_OK;
}
