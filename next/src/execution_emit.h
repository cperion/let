#ifndef ABC_EXECUTION_EMIT_H
#define ABC_EXECUTION_EMIT_H
#include "execution_context.h"

/* Preparation-time labels and bound physical operands. These are not a value
   IR: emit consumes an operand packet immediately into final backend storage. */
typedef uint32_t abc_exec_label;
#define ABC_EXEC_NO_LABEL UINT32_MAX
typedef struct {
    uint64_t value[5];
    abc_exec_label target;
} abc_exec_operands;
typedef struct { size_t body_bytes,allocation_bytes,regions; } abc_exec_storage;
typedef struct { const uint8_t *base;size_t body_bytes,allocation_bytes; } abc_exec_region;
typedef struct abc_exec_emitter abc_exec_emitter;
typedef abc_status (*abc_exec_prepare_fn)(void *,abc_error *);
typedef struct {
    abc_status (*label)(abc_exec_emitter *,abc_exec_label *,uint32_t,abc_error *);
    abc_status (*bind)(abc_exec_emitter *,abc_exec_label,uint32_t,abc_error *);
    abc_status (*emit)(abc_exec_emitter *,unsigned,const abc_exec_operands *,uint32_t,abc_error *);
    abc_status (*lazy_entry)(abc_exec_emitter *,abc_exec_label,abc_exec_label,void *,abc_exec_prepare_fn,uint32_t,abc_error *);
    abc_status (*publish)(abc_exec_emitter *,uint32_t,abc_error *);
    uintptr_t (*address)(const abc_exec_emitter *,abc_exec_label);
    abc_exec_storage (*storage)(const abc_exec_emitter *);
    void (*discard_preparation)(abc_exec_emitter *);
    void (*destroy)(abc_exec_emitter *);
    uint64_t (*enter)(const abc_exec_emitter *,uintptr_t,uint64_t *,uint64_t *,uint64_t *);
    abc_exec_region (*region)(const abc_exec_emitter *,size_t);
} abc_exec_emitter_ops;
struct abc_exec_emitter {
    const abc_exec_emitter_ops *ops;
    unsigned register_count;
};

abc_status abc_native_emitter_create(size_t code_bytes,abc_exec_emitter **out,abc_error *error);
abc_status abc_threaded_emitter_create(abc_exec_emitter **out,abc_error *error);
#endif
