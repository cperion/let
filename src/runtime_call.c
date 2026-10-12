#include "vm_internal.h"
#include "runtime_call.h"

abc_status abc_runtime_invoke(const abc_extern *ext,abc_foreign_address unused,const uint64_t *args,uint64_t *out) {
    (void)unused;
    abc_run *run=abc_active_run;
    if(!run||!abc_primitive_signature(ext))return ABC_INVALID;
    abc_owner_context *context=&run->v->owners;
    abc_error *error=run->e;
    int primitive=abc_primitive_index(ext->name);
    abc_owner_scope *scope=(abc_owner_scope *)(uintptr_t)args[0];
    abc_owner **slot=NULL;
    switch(primitive) {
    case ABC_PRIMITIVE_SCOPE_ENTER: {
        uintptr_t start=(uintptr_t)run->v->c,end=start+run->v->capacity*sizeof(uint64_t),p=(uintptr_t)scope;
        if(p<start||p>end||args[1]>end-p)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"holding scope is outside VM frame storage");
        return abc_owner_scope_enter(context,scope,(size_t)args[1],error);
    }
    case ABC_PRIMITIVE_SCOPE_LEAVE:return abc_owner_scope_leave(context,scope,error);
    case ABC_PRIMITIVE_OWNER_DATA:
        if(!args[0])return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"missing owner data");
        *out=(uint64_t)(uintptr_t)abc_owner_payload((abc_owner *)(uintptr_t)args[0]);return ABC_OK;
    case ABC_PRIMITIVE_OWNER_SET:
        return abc_owner_set(context,(abc_owner *)(uintptr_t)args[0],(abc_owner *)(uintptr_t)args[1],error);
    default:
        slot=abc_owner_slot(context,scope,(size_t)args[1]);
        if(!slot)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"holding slot has no active scope");
        break;
    }
    if(primitive==ABC_PRIMITIVE_OWNER_DROP) {
        abc_owner *old=*slot;*slot=NULL;abc_owner_release(context,old);abc_owner_drain(context);return ABC_OK;
    }
    if(*slot)return abc_fail(error,ABC_INVALID,UINT32_MAX,"holding destination is already initialized");
    switch(primitive) {
    case ABC_PRIMITIVE_OWNER_NEW: {
        if(args[2]>=ABC_TYPE_COUNT)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"unsupported runtime owner layout");
        abc_owner *owner;
        abc_status status=abc_owner_new(context,&abc_runtime_types[args[2]],(size_t)args[3],&owner,error);
        if(status!=ABC_OK)return status;
        *slot=owner;*out=(uint64_t)(uintptr_t)owner;return ABC_OK;
    }
    case ABC_PRIMITIVE_OWNER_RETAIN: {
        abc_owner *owner=(abc_owner *)(uintptr_t)args[2];
        abc_status status=abc_owner_retain(context,owner,error);if(status==ABC_OK)*slot=owner;return status;
    }
    case ABC_PRIMITIVE_OWNER_MOVE: {
        abc_owner **source=abc_owner_slot(context,(abc_owner_scope *)(uintptr_t)args[2],(size_t)args[3]);
        if(!source||source==slot||!*source)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"invalid holding transfer source");
        *slot=*source;*source=NULL;return ABC_OK;
    }
    default:return abc_fail(error,ABC_INVALID,UINT32_MAX,"unimplemented runtime operation");
    }
}
