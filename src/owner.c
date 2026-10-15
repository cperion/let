#include "internal.h"
#include "owner.h"
#include <assert.h>

static int allocation_layout(size_t bytes,size_t a,size_t *offset,size_t *total,size_t *alignment) {
    if(!a || (a&(a-1)) || sizeof(abc_owner)>SIZE_MAX-(a-1))return 0;
    *offset=(sizeof(abc_owner)+a-1)&~(a-1);
    if(bytes>SIZE_MAX-*offset)return 0;
    size_t n=*offset+bytes;
    if(a<_Alignof(abc_owner))a=_Alignof(abc_owner);
    if(n>SIZE_MAX-(a-1))return 0;
    *alignment=a;*total=(n+a-1)&~(a-1);return 1;
}
void *abc_owner_payload(const abc_owner *owner) {
    return (unsigned char *)(uintptr_t)owner+owner->payload_offset;
}
abc_status abc_owner_new(abc_owner_context *context,size_t bytes,size_t align,abc_owner_kind kind,abc_release_fn release,abc_owner **out,abc_error *error) {
    size_t offset,total,alignment;
    if(!release||!out||kind>ABC_OWNER_SHARED ||
       !allocation_layout(bytes,align,&offset,&total,&alignment))
        return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"invalid owner layout or allocation extent");
    abc_owner *owner=aligned_alloc(alignment,total);
    if(!owner)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"owner allocation failed");
    owner->release_outgoing=release;owner->release_next=NULL;
    owner->payload_offset=offset;owner->kind=kind;
    if(kind==ABC_OWNER_SHARED)atomic_init(&owner->count.shared,1);
    else owner->count.local=1;
    /* Payload initialization remains the C caller's responsibility. */
    context->allocations++;*out=owner;return ABC_OK;
}
abc_status abc_owner_retain(abc_owner_context *context,abc_owner *owner,abc_error *error) {
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
    context->retains++;return ABC_OK;
}
void abc_owner_release(abc_owner_context *context,abc_owner *owner) {
    if(!owner||owner->kind==ABC_OWNER_IMMORTAL)return;
    uint64_t old;
    if(owner->kind==ABC_OWNER_SHARED) {
        old=atomic_fetch_sub_explicit(&owner->count.shared,1,memory_order_release);
        if(old==1)atomic_thread_fence(memory_order_acquire);
    } else {old=owner->count.local;assert(old);owner->count.local=old-1;}
    assert(old);context->releases++;
    if(old!=1)return;
    owner->release_next=NULL;
    if(context->release_tail)context->release_tail->release_next=owner;
    else context->release_head=owner;
    context->release_tail=owner;
}
void abc_owner_drain(abc_owner_context *context) {
    assert(!context->draining);context->draining=true;
    while(context->release_head) {
        abc_owner *owner=context->release_head;
        context->release_head=owner->release_next;
        if(!context->release_head)context->release_tail=NULL;
        context->release_entries++;
        owner->release_outgoing(context,owner);
        free(owner);context->frees++;
    }
    context->draining=false;
}
abc_status abc_owner_replace(abc_owner_context *context,abc_owner **slot,abc_owner *incoming,abc_error *error) {
    if(!slot)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"missing holding destination");
    if(incoming){abc_status status=abc_owner_retain(context,incoming,error);if(status!=ABC_OK)return status;}
    abc_owner *old=*slot;*slot=incoming;abc_owner_release(context,old);return ABC_OK;
}
