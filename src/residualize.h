#ifndef ABC_RESIDUALIZE_H
#define ABC_RESIDUALIZE_H
#include "vm_internal.h"

typedef struct abc_execution_image {
    /* Aggregate diagnostic sizes; immutable regions belong to the emitter. */
    size_t code_size, storage_size;
    void **entries;
    size_t virtual_calls, virtual_returns, virtual_tails, real_calls;
    size_t compiled_versions; void *lazy_state; unsigned lazy;
    struct abc_exec_emitter *emitter;
} abc_execution_image;

abc_status abc_residualize_module(const abc_module *module,uint8_t *image_base,const abc_vm *vm,
    abc_execution_mode mode,abc_execution_image **out,abc_error *error);
void abc_execution_image_free(abc_execution_image *image);
abc_status abc_execution_prepare_holding(abc_execution_image *,unsigned,abc_error *);
#endif
