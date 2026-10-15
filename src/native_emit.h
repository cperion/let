#ifndef ABC_NATIVE_EMIT_H
#define ABC_NATIVE_EMIT_H
#include "internal.h"

/* Backend-private relocation token. Callers may copy/pass it, but must not
   interpret its storage. No native relocation kind escapes this interface. */
typedef struct { uintptr_t opaque[2]; } abc_native_patch;
typedef uint64_t (*abc_native_prepare_fn)(uint64_t,uint64_t *);
typedef uint64_t *(*abc_native_bounds_fn)(unsigned);
typedef void *(*abc_native_copy_fn)(void *,const void *,size_t);
typedef uint64_t (*abc_native_resolve_fn)(uint64_t,uint64_t,uintptr_t,uintptr_t,uintptr_t,uint64_t *);

/* The caller reserves exactly this many bytes before emission. Zero means an
   invalid form. All emitted references remain private to the native image. */
size_t abc_native_form_size(unsigned form);
int abc_native_patch_present(const abc_native_patch *reference);
void abc_native_bind(const abc_native_patch *reference,uint64_t value);

int abc_native_emit_simple(uint8_t *at,unsigned form,uint64_t immediate,abc_native_patch *taken);
int abc_native_emit_copy(uint8_t *at,unsigned destination,unsigned source,uint32_t bytes,abc_native_copy_fn copy_fn);
int abc_native_emit_foreign(uint8_t *at,unsigned form,uint32_t argument_cells,
    abc_foreign_bridge_fn bridge,const abc_extern *external,abc_foreign_address target,uint64_t error);
int abc_native_emit_guard(uint8_t *at,unsigned stack,uint64_t bytes,abc_native_bounds_fn bounds,uint64_t error);
int abc_native_emit_resolve(uint8_t *at,abc_native_resolve_fn resolver,uint32_t pc,
    int64_t a_bytes,int64_t b_bytes,int64_t c_bytes);
int abc_native_emit_lazy(uint8_t *at,void *state,abc_native_prepare_fn prepare);
int abc_native_emit_c_entry(uint8_t *,uint64_t,uint64_t,uint64_t,abc_native_patch *);
#endif
