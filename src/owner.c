#include "internal.h"
#include "owner.h"
#include <assert.h>

abc_status abc_owner_alloc(size_t bytes,size_t alignment,abc_owner_kind kind,abc_drop_fields_fn drop,abc_owner **out,abc_error *error) {
    if(!out||bytes<sizeof(abc_owner)||!alignment||(alignment&(alignment-1))||
       (kind!=ABC_OWNER_LOCAL&&kind!=ABC_OWNER_SHARED))
        return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"invalid owner allocation");
    if(alignment<_Alignof(abc_owner))alignment=_Alignof(abc_owner);
    if(bytes>SIZE_MAX-(alignment-1))
        return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"owner allocation extent overflow");
    size_t total=(bytes+alignment-1)&~(alignment-1);
    abc_owner *owner=aligned_alloc(alignment,total);
    if(!owner)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"owner allocation failed");
    owner->drop_fields=drop;owner->next_dead=NULL;owner->kind=kind;
    if(kind==ABC_OWNER_SHARED)atomic_init(&owner->count.shared,1);
    else owner->count.local=1;
    *out=owner;return ABC_OK;
}
abc_status abc_owner_retain(abc_owner *owner,abc_error *error) {
    if(!owner)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"missing owner to retain");
    if(owner->kind==ABC_OWNER_IMMORTAL)return ABC_OK;
    if(owner->kind==ABC_OWNER_SHARED) {
        uint64_t count=atomic_load_explicit(&owner->count.shared,memory_order_relaxed);
        do {
            if(!count)return abc_fail(error,ABC_INVALID,UINT32_MAX,"cannot resurrect a released owner");
            if(count==UINT64_MAX)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"owner reference count limit reached");
        } while(!atomic_compare_exchange_weak_explicit(&owner->count.shared,&count,count+1,memory_order_relaxed,memory_order_relaxed));
    } else {
        if(!owner->count.local)return abc_fail(error,ABC_INVALID,UINT32_MAX,"cannot resurrect a released owner");
        if(owner->count.local==UINT64_MAX)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"owner reference count limit reached");
        owner->count.local++;
    }
    return ABC_OK;
}
void abc_owner_release(abc_owner_context *context,abc_owner *owner) {
    if(!owner||owner->kind==ABC_OWNER_IMMORTAL)return;
    uint64_t old;
    if(owner->kind==ABC_OWNER_SHARED) {
        old=atomic_fetch_sub_explicit(&owner->count.shared,1,memory_order_release);
        if(old==1)atomic_thread_fence(memory_order_acquire);
    } else {old=owner->count.local;assert(old);owner->count.local=old-1;}
    assert(old);
    if(old!=1)return;
    owner->next_dead=NULL;
    if(context->tail)context->tail->next_dead=owner;
    else context->head=owner;
    context->tail=owner;
}
void abc_owner_drain(abc_owner_context *context) {
    assert(!context->draining);context->draining=true;
    while(context->head) {
        abc_owner *owner=context->head;
        context->head=owner->next_dead;
        if(!context->head)context->tail=NULL;
        if(owner->drop_fields)owner->drop_fields(context,owner);
        free(owner);
    }
    context->draining=false;
}
abc_status abc_owner_replace(abc_owner_context *context,abc_owner **slot,abc_owner *incoming,abc_error *error) {
    if(!slot)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"missing holding destination");
    if(incoming){abc_status status=abc_owner_retain(incoming,error);if(status!=ABC_OK)return status;}
    abc_owner *old=*slot;*slot=incoming;abc_owner_release(context,old);return ABC_OK;
}
