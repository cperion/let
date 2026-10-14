#ifndef ABC_RELEASE_H
#define ABC_RELEASE_H
#include "abc.h"
typedef enum { ABC_OWNER_LOCAL, ABC_OWNER_SHARED, ABC_OWNER_IMMORTAL } abc_owner_kind;
struct abc_owner;
struct abc_owner_context;
struct abc_exec_emitter;
/* Process-local prepared code, never a serialized pointer or source callback. */
typedef void (*abc_release_fn)(struct abc_owner_context *,struct abc_owner *);
typedef struct abc_release_code {
    abc_release_fn entry;
    struct abc_exec_emitter *emitter;
    unsigned function;
    size_t home_bytes; /* fixed native home reservation; excludes ABI/compiler spills */
    struct abc_release_code *next;
} abc_release_code;
#endif
