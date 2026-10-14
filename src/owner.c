#include "internal.h"
#include "owner.h"
#include <assert.h>

/* The current ABC host ABI is 64-bit (internal.h). Keep compiler frame records
 * explicit; a future wasm binding must generate its corresponding layout. */
_Static_assert(sizeof(abc_owner_scope)==2*sizeof(uint64_t),"holding scope header ABI");
_Static_assert(sizeof(abc_owner *)==sizeof(uint64_t),"holding scope slot ABI");

static int allocation_layout(const abc_type_ops *ops,size_t bytes,size_t *offset,size_t *total,size_t *alignment) {
    size_t a=ops->payload_align;
    if(!a || (a&(a-1)) || bytes<ops->payload_size || sizeof(abc_owner)+sizeof(uint64_t)>SIZE_MAX-(a-1))return 0;
    *offset=(sizeof(abc_owner)+sizeof(uint64_t)+a-1)&~(a-1);
    if(bytes>SIZE_MAX-*offset)return 0;
    size_t n=*offset+bytes;
    if(a<_Alignof(abc_owner))a=_Alignof(abc_owner);
    if(n>SIZE_MAX-(a-1))return 0;
    *alignment=a;*total=(n+a-1)&~(a-1);return 1;
}
void *abc_owner_payload(const abc_owner *owner) {
    size_t align=owner->ops->payload_align;
    size_t offset=(sizeof *owner+sizeof(uint64_t)+align-1)&~(align-1);
    return (unsigned char *)(uintptr_t)owner+offset;
}
/* Explicit initialized-holding prefix, not a zero-filled payload assumption.
 * Generated construction advances it only after each holding is installed. */
uint64_t *abc_owner_initialized(const abc_owner *owner) {
    return (uint64_t *)((unsigned char *)abc_owner_payload(owner)-sizeof(uint64_t));
}
abc_status abc_owner_new(abc_owner_context *context,const abc_type_ops *ops,size_t bytes,abc_owner **out,abc_error *error) {
    size_t offset,total,alignment;
    if(!ops||!out||ops->owner_kind==ABC_OWNER_IMMORTAL||ops->owner_kind>ABC_OWNER_IMMORTAL ||
       !allocation_layout(ops,bytes,&offset,&total,&alignment))
        return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"invalid owner layout or allocation extent");
    abc_owner *owner=aligned_alloc(alignment,total);
    if(!owner)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"owner allocation failed");
    owner->ops=ops;owner->release_next=NULL;
    if(ops->owner_kind==ABC_OWNER_SHARED)atomic_init(&owner->count.shared,1);
    else owner->count.local=1;
    *abc_owner_initialized(owner)=0;
    (void)offset; /* Source payload is uninitialized; only the prefix is valid. */
    context->allocations++;*out=owner;return ABC_OK;
}
abc_status abc_owner_retain(abc_owner_context *context,abc_owner *owner,abc_error *error) {
    if(!owner)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"missing owner to retain");
    if(owner->ops->owner_kind==ABC_OWNER_IMMORTAL)return ABC_OK;
    if(owner->ops->owner_kind==ABC_OWNER_SHARED) {
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
    if(!owner||owner->ops->owner_kind==ABC_OWNER_IMMORTAL)return;
    uint64_t old;
    if(owner->ops->owner_kind==ABC_OWNER_SHARED) {
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
abc_owner *abc_owner_dequeue(abc_owner_context *context) {
    abc_owner *owner=context->release_head;
    if(owner){context->release_head=owner->release_next;if(!context->release_head)context->release_tail=NULL;}
    return owner;
}
void abc_owner_destroy(abc_owner_context *context,abc_owner *owner) {
    free(owner);context->frees++;
}
abc_owner **abc_owner_slot(abc_owner_scope *top,abc_owner_scope *scope,size_t slot) {
    for(abc_owner_scope *s=top;s;s=s->previous)if(s==scope)return slot<s->slots?&s->held[slot]:NULL;
    return NULL;
}
abc_status abc_owner_scope_enter(abc_owner_scope **top,void *storage,size_t bytes,abc_error *error) {
    if(!storage||(uintptr_t)storage%_Alignof(abc_owner_scope)||bytes<sizeof(abc_owner_scope)||
       (bytes-sizeof(abc_owner_scope))%sizeof(abc_owner *))
        return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"invalid holding scope storage");
    for(abc_owner_scope *s=*top;s;s=s->previous)if(s==storage)
        return abc_fail(error,ABC_INVALID,UINT32_MAX,"holding scope entered twice");
    abc_owner_scope *scope=storage;scope->slots=(bytes-sizeof *scope)/sizeof(abc_owner *);
    for(size_t i=0;i<scope->slots;i++)scope->held[i]=NULL;
    scope->previous=*top;*top=scope;return ABC_OK;
}
abc_status abc_owner_scope_leave(abc_owner_context *context,abc_owner_scope **top,abc_owner_scope *scope,abc_error *error) {
    if(!scope||*top!=scope)return abc_fail(error,ABC_INVALID,UINT32_MAX,"holding scopes must leave in call order");
    *top=scope->previous;
    for(size_t i=scope->slots;i;i--) {
        abc_owner *held=scope->held[i-1];scope->held[i-1]=NULL;abc_owner_release(context,held);
    }
    return ABC_OK;
}
void abc_owner_unwind(abc_owner_context *context,abc_owner_scope **top) {
    while(*top) {
        abc_status status=abc_owner_scope_leave(context,top,*top,NULL);assert(status==ABC_OK);(void)status;
    }
}
