#include "lifetime.h"
#include "execution_context.h"

_Static_assert(sizeof(abc_owner)==32,"source concrete allocation header");
_Static_assert(sizeof(abc_cleanup_frame)==16,"source activation header");
#define BRIDGE(name) static abc_status name(const abc_extern *e,abc_foreign_address target,const uint64_t *a,uint64_t *out)
#define UNUSED() do{(void)e;(void)target;(void)out;}while(0)
BRIDGE(source_alloc) {
    UNUSED();abc_exec_context *run=abc_active_context;abc_owner **slot=(abc_owner **)(uintptr_t)a[0],*owner=NULL;
    if(a[1]<sizeof(abc_owner))return abc_fail(&run->error,ABC_INVALID,UINT32_MAX,"invalid concrete owner extent");
    abc_status status=abc_owner_alloc((size_t)a[1],(size_t)a[2],ABC_OWNER_LOCAL,
        (abc_drop_fields_fn)(uintptr_t)a[3],&owner,&run->error);
    if(status!=ABC_OK)return status;
    /* Every outgoing holding is null, including inactive construction storage,
       before the first holding is published. No progress word or runtime plan. */
    memset((uint8_t *)owner+sizeof *owner,0,(size_t)a[1]-sizeof *owner);
    abc_owner *old=*slot;*slot=owner;abc_owner_release(&run->owners,old);if(run->owners.head)abc_owner_drain(&run->owners);return ABC_OK;
}
BRIDGE(source_hold) {
    UNUSED();abc_exec_context *run=abc_active_context;abc_owner **slot=(abc_owner **)(uintptr_t)a[0];
    abc_status status=abc_owner_replace(&run->owners,slot,(abc_owner *)(uintptr_t)a[1],&run->error);
    if(status==ABC_OK&&run->owners.head)abc_owner_drain(&run->owners);return status;
}
BRIDGE(source_drop) {
    UNUSED();abc_owner_context *context=(abc_owner_context *)(uintptr_t)a[0];abc_owner **slot=(abc_owner **)(uintptr_t)a[1];
    abc_owner *owner=*slot;*slot=NULL;abc_owner_release(context,owner);return ABC_OK;
}
BRIDGE(source_clear) {
    UNUSED();abc_exec_context *run=abc_active_context;
    ((abc_cleanup_fn)(uintptr_t)a[1])(&run->owners,(void *)(uintptr_t)a[0]);
    if(run->owners.head)abc_owner_drain(&run->owners);return ABC_OK;
}
BRIDGE(source_enter) {
    UNUSED();abc_exec_context *run=abc_active_context;abc_cleanup_frame *frame=(abc_cleanup_frame *)(uintptr_t)a[0];
    frame->previous=run->cleanup;frame->drop=(abc_cleanup_fn)(uintptr_t)a[1];run->cleanup=frame;return ABC_OK;
}
BRIDGE(source_leave) {
    UNUSED();abc_exec_context *run=abc_active_context;abc_cleanup_frame *frame=(abc_cleanup_frame *)(uintptr_t)a[0];
    if(run->cleanup!=frame)return abc_fail(&run->error,ABC_INVALID,UINT32_MAX,"source activation cleanup order mismatch");
    run->cleanup=frame->previous;frame->drop(&run->owners,frame);if(run->owners.head)abc_owner_drain(&run->owners);return ABC_OK;
}
abc_foreign_bridge_fn abc_source_binding(const abc_extern *e) {
    if(!abc_source_contract(e))return NULL;
    if(!strcmp(e->name,"__let_rt_source_alloc"))return source_alloc;
    if(!strcmp(e->name,"__let_rt_source_hold"))return source_hold;
    if(!strcmp(e->name,"__let_rt_source_drop"))return source_drop;
    if(!strcmp(e->name,"__let_rt_source_clear"))return source_clear;
    if(!strcmp(e->name,"__let_rt_source_enter"))return source_enter;
    return source_leave;
}
void abc_source_unwind(abc_exec_context *run) {
    while(run->cleanup){abc_cleanup_frame *frame=run->cleanup;run->cleanup=frame->previous;frame->drop(&run->owners,frame);}
    abc_owner_drain(&run->owners);
}
abc_status abc_source_lifecycle_check(const abc_module *m,abc_error *error) {
    for(uint32_t i=0;i<m->function_count;i++)if(m->functions[i].c_entry) {
        const abc_function *f=&m->functions[i];
        for(uint32_t pc=f->entry;pc<f->end;pc+=abc_instruction_length(m->code+pc)) {
            const abc_instruction_metadata *op=abc_instruction_info(m->code+pc);
            /* Cleanup bodies are ordinary scalar/address/control code. They may
               enqueue through exactly one non-failing C binding, never call ABC,
               allocate owners, suspend, abort, or perform checked conversions. */
            unsigned k=op->kind,o=op->operation;
            if(k==K_CALL||k==K_TCALL||k==K_ICALL||k==K_ITCALL||k==K_ABORT||k==K_HALT||
               o==ABC_OPERATION_DIVS||o==ABC_OPERATION_DIVU||o==ABC_OPERATION_REMS||o==ABC_OPERATION_REMU||
               o==ABC_OPERATION_CPUSH||o==ABC_OPERATION_CPUSHN||o==ABC_OPERATION_CPOP||
               o==ABC_OPERATION_CALLOC||o==ABC_OPERATION_CFREE||
               o==ABC_OPERATION_POWS||o==ABC_OPERATION_F2IS||o==ABC_OPERATION_F2IU||
               o==ABC_OPERATION_CHKU8||o==ABC_OPERATION_CHKU16||o==ABC_OPERATION_CHKU32||o==ABC_OPERATION_CHKI32||o==ABC_OPERATION_CHKNN)
                return abc_fail(error,ABC_INVALID,pc,"unsupported potentially failing lifecycle C-entry body");
            if(k==K_FCALL){const abc_extern *ext=&m->externs[abc_u16(m->code+pc+1)];
                if(strcmp(ext->name,"__let_rt_source_drop")||!abc_source_contract(ext))
                    return abc_fail(error,ABC_INVALID,pc,"lifecycle C-entry may only enqueue field releases");
            }
        }
    }
    return ABC_OK;
}
