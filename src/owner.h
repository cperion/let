#ifndef ABC_OWNER_H
#define ABC_OWNER_H
#include "abc.h"
#include "type_ops.h"
#include <stdatomic.h>
#include <stdbool.h>

typedef struct abc_owner {
    union { uint64_t local; _Atomic uint64_t shared; } count;
    const abc_type_ops *ops;
    struct abc_owner *release_next;
} abc_owner;

/* Compiler-emitted, explicitly initialized records in ordinary frame storage.
 * Slots are semantic holdings, not machine registers or a scan of stack cells.
 * A record must be left before RET/TCALL reuses its storage. Failure drains the
 * linked records before the VM resets any stack; it does not run source defers. */
typedef struct abc_owner_scope {
    struct abc_owner_scope *previous;
    size_t slots;
    abc_owner *held[];
} abc_owner_scope;
typedef struct abc_owner_context {
    abc_owner *release_head, *release_tail;
    bool draining;
    size_t allocations, frees, retains, releases;
} abc_owner_context;

abc_status abc_owner_new(abc_owner_context *,const abc_type_ops *,size_t,abc_owner **,abc_error *);
abc_status abc_owner_retain(abc_owner_context *,abc_owner *,abc_error *);
void abc_owner_release(abc_owner_context *,abc_owner *);
abc_owner *abc_owner_dequeue(abc_owner_context *);
void abc_owner_destroy(abc_owner_context *,abc_owner *);
void *abc_owner_payload(const abc_owner *);
uint64_t *abc_owner_initialized(const abc_owner *);
abc_status abc_owner_scope_enter(abc_owner_scope **,void *,size_t,abc_error *);
abc_status abc_owner_scope_leave(abc_owner_context *,abc_owner_scope **,abc_owner_scope *,abc_error *);
void abc_owner_unwind(abc_owner_context *,abc_owner_scope **);
abc_owner **abc_owner_slot(abc_owner_scope *,abc_owner_scope *,size_t);
#endif
