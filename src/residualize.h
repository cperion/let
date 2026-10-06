#ifndef ABC_RESIDUALIZE_H
#define ABC_RESIDUALIZE_H
#include "vm_internal.h"

typedef struct abc_ic_state abc_ic_state;
typedef struct abc_native_image {
    uint8_t *code; size_t code_size, mapping_size;
    void **entries; uint32_t entry_count;
    uint64_t *stack_end[3];
    abc_ic_state *sites; uint32_t site_count, transitions;
    size_t virtual_calls, virtual_returns, virtual_tails, real_calls;
    size_t compiled_versions; void *lazy_state; unsigned lazy;
} abc_native_image;

abc_status abc_residualize_module(const abc_module *module, uint8_t *image_base, const abc_vm *vm, unsigned lazy, abc_native_image **out, abc_error *error);
void abc_native_site_stats(const abc_native_image *image, abc_site_stats *stats);
void abc_native_image_free(abc_native_image *image);

#endif

