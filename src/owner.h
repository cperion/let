#ifndef ABC_OWNER_H
#define ABC_OWNER_H
#include "abc.h"
#include <stdatomic.h>
#include <stdbool.h>

/* Private counting/queue core; concrete source/VM bindings live in lifetime.c. */
typedef enum { ABC_OWNER_LOCAL, ABC_OWNER_SHARED, ABC_OWNER_IMMORTAL } abc_owner_kind;
typedef struct abc_owner abc_owner;
typedef struct abc_owner_context abc_owner_context;
/* Release outgoing holdings by enqueueing only. Never free this object, drain,
 * allocate, suspend or invoke source code. NULL means no outgoing holdings. */
typedef void (*abc_drop_fields_fn)(abc_owner_context *,abc_owner *);

/* Embed as the first member of the concrete allocation. Offsets/extent belong
 * to its caller and drop function, not a runtime layout descriptor.
 * kind and drop_fields are immutable after initialization. */
struct abc_owner {
    union { uint64_t local; _Atomic uint64_t shared; } count;
    abc_drop_fields_fn drop_fields;
    abc_owner *next_dead;
    abc_owner_kind kind;
};

/* Zero-initialize once; confined to the thread currently draining this queue. */
struct abc_owner_context {
    abc_owner *head, *tail;
    bool draining;
};

/* bytes includes the header. Payload is uninitialized: the C caller must make
 * its fields cleanup-valid before releasing/publishing. Failure leaves *out
 * unchanged. Allocated objects are local/shared; immortal objects are static. */
abc_status abc_owner_alloc(size_t bytes,size_t alignment,abc_owner_kind,
    abc_drop_fields_fn,abc_owner **out,abc_error *);
/* Requires an existing holding/borrow protecting owner; never resurrects zero. */
abc_status abc_owner_retain(abc_owner *,abc_error *);
/* Decrement/enqueue only, including when called by drop_fields. NULL is a no-op. */
void abc_owner_release(abc_owner_context *,abc_owner *);
/* Complete queued field drops and frees, iteratively and without allocation. */
void abc_owner_drain(abc_owner_context *);
/* Retain before replacement; failure leaves slot/count unchanged. Enqueues old
 * owner without draining. Slot is exclusively writable by this caller. */
abc_status abc_owner_replace(abc_owner_context *,abc_owner **slot,abc_owner *incoming,abc_error *);
#endif
