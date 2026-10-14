#include "vm_internal.h"
#include "runtime_call.h"

abc_status abc_runtime_invoke(const abc_extern *ext,abc_foreign_address unused,const uint64_t *args,uint64_t *out) {
    (void)unused;
    abc_exec_context *run=abc_active_context;
    if(!run||!abc_primitive_signature(ext))return ABC_INVALID;
    abc_owner_context *context=&run->worker->owners;abc_error *error=&run->error;
    int primitive=abc_primitive_index(ext->name);
    abc_owner_scope *scope=(abc_owner_scope *)(uintptr_t)args[0];abc_owner **slot=NULL;
    switch(primitive) {
    case ABC_PRIMITIVE_TYPE_BIND: {
        if(args[2]>ABC_OWNER_SHARED)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"invalid owner policy");
        const abc_type_ops *ops;abc_status status=abc_type_bind(run,(size_t)args[0],(size_t)args[1],(unsigned)args[2],args[3],args[4],&ops);
        if(status==ABC_OK)*out=(uintptr_t)ops;return status;
    }
    case ABC_PRIMITIVE_SCOPE_ENTER: {
        uintptr_t start=(uintptr_t)run->c,end=start+run->capacity*sizeof(uint64_t),p=(uintptr_t)scope;
        if(p<start||p>end||args[1]>end-p)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"holding scope is outside execution frame storage");
        return abc_owner_scope_enter(&run->scopes,scope,(size_t)args[1],error);
    }
    case ABC_PRIMITIVE_SCOPE_LEAVE:return abc_owner_scope_leave(context,&run->scopes,scope,error);
    case ABC_PRIMITIVE_OWNER_DATA:
        if(!args[0])return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"missing owner data");
        *out=(uintptr_t)abc_owner_payload((abc_owner *)(uintptr_t)args[0]);return ABC_OK;
    case ABC_PRIMITIVE_OWNER_INITIALIZED:
        *out=*abc_owner_initialized((abc_owner *)(uintptr_t)args[0]);return ABC_OK;
    case ABC_PRIMITIVE_OWNER_COMMIT:
        *abc_owner_initialized((abc_owner *)(uintptr_t)args[0])=args[1];return ABC_OK;
    case ABC_PRIMITIVE_OWNER_HOLD:
        return args[0]?abc_owner_retain(context,(abc_owner *)(uintptr_t)args[0],error):ABC_OK;
    case ABC_PRIMITIVE_OWNER_ENQUEUE:
        abc_owner_release(context,(abc_owner *)(uintptr_t)args[0]);return ABC_OK;
    default:
        slot=abc_owner_slot(run->scopes,scope,(size_t)args[1]);
        if(!slot)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"holding slot has no active scope");
    }
    if(primitive==ABC_PRIMITIVE_OWNER_DROP) {
        abc_owner *old=*slot;*slot=NULL;abc_owner_release(context,old);return ABC_OK;
    }
    if(*slot)return abc_fail(error,ABC_INVALID,UINT32_MAX,"holding destination is already initialized");
    switch(primitive) {
    case ABC_PRIMITIVE_OWNER_NEW: {
        const abc_type_ops *ops=(const abc_type_ops *)(uintptr_t)args[2];
        int found=0;
        for(abc_image *image=run->session->images;image&&!found;image=image->next)
            for(abc_type_ops *p=image->type_ops;p;p=p->next)if(p==ops){found=1;break;}
        if(!found)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"unbound runtime owner layout");
        abc_owner *owner;abc_status status=abc_owner_new(context,ops,(size_t)args[3],&owner,error);
        if(status!=ABC_OK)return status;
        *slot=owner;*out=(uintptr_t)owner;return ABC_OK;
    }
    case ABC_PRIMITIVE_OWNER_RETAIN: {
        abc_owner *owner=(abc_owner *)(uintptr_t)args[2];
        abc_status status=abc_owner_retain(context,owner,error);if(status==ABC_OK)*slot=owner;return status;
    }
    case ABC_PRIMITIVE_OWNER_MOVE: {
        abc_owner **source=abc_owner_slot(run->scopes,(abc_owner_scope *)(uintptr_t)args[2],(size_t)args[3]);
        if(!source||source==slot||!*source)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"invalid holding transfer source");
        *slot=*source;*source=NULL;return ABC_OK;
    }
    default:return abc_fail(error,ABC_INVALID,UINT32_MAX,"unimplemented runtime operation");
    }
}
