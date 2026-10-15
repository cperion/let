#ifndef ABC_OWNER_H
#define ABC_OWNER_H
#include "abc.h"
#include <stdatomic.h>
#include <stdbool.h>

/* Standalone C core. Source allocation/cleanup binding is not implemented. */
typedef enum { ABC_OWNER_LOCAL, ABC_OWNER_SHARED, ABC_OWNER_IMMORTAL } abc_owner_kind;
struct abc_owner;
struct abc_owner_context;
typedef void (*abc_release_fn)(struct abc_owner_context *,struct abc_owner *);

typedef struct abc_owner {
    union { uint64_t local; _Atomic uint64_t shared; } count;
    abc_release_fn release_outgoing;
    struct abc_owner *release_next;
    size_t payload_offset;
    abc_owner_kind kind;
} abc_owner;

typedef struct abc_owner_context {
    abc_owner *release_head, *release_tail;
    bool draining;
    size_t allocations, frees, retains, releases, release_entries;
} abc_owner_context;

abc_status abc_owner_new(abc_owner_context *,size_t,size_t,abc_owner_kind,abc_release_fn,abc_owner **,abc_error *);
abc_status abc_owner_retain(abc_owner_context *,abc_owner *,abc_error *);
void abc_owner_release(abc_owner_context *,abc_owner *);
void abc_owner_drain(abc_owner_context *);
abc_status abc_owner_replace(abc_owner_context *,abc_owner **,abc_owner *,abc_error *);
void *abc_owner_payload(const abc_owner *);
#endif
