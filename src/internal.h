#ifndef ABC_INTERNAL_H
#define ABC_INTERNAL_H
#include "abc.h"
#include "opcodes.h"
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdatomic.h>

#if !defined(__GNUC__) && !defined(__clang__)
#error "ABC VM requires compiler support for __attribute__((musttail))"
#endif
#define ABC_MUSTTAIL __attribute__((musttail))
_Static_assert(sizeof(void *) == 8, "ABC2 requires a 64-bit host");
enum { ABC_MAX_FILE = 16 * 1024 * 1024, ABC_MAX_FUNCTIONS = 65536 };
/* Serialized kinds retain INT=0, ADDR=1 and FLOAT=2 compatibility. */
enum { ABC_KIND_INT, ABC_KIND_ADDR, ABC_KIND_FLOAT, ABC_KIND_ANY, ABC_KIND_BLOCK };
enum { ABC_DESC_PRIMITIVE, ABC_DESC_POINTER, ABC_DESC_SLICE, ABC_DESC_SIGNATURE, ABC_DESC_RECORD, ABC_DESC_ARRAY, ABC_DESC_SUM, ABC_DESC_CLOSURE };
enum { ABC_PRIM_UNIT, ABC_PRIM_BOOL, ABC_PRIM_U8, ABC_PRIM_U16, ABC_PRIM_U32, ABC_PRIM_U64, ABC_PRIM_I32, ABC_PRIM_I64, ABC_PRIM_F64, ABC_PRIM_STRING, ABC_PRIM_ANY, ABC_PRIM_WORD };
typedef struct { uint8_t tag, flags; uint16_t length; uint8_t *payload; } abc_descriptor;
typedef struct { uint32_t offset, descriptor; } abc_gc_root;
typedef struct { uint8_t kind, flags; uint16_t length; uint8_t *payload; } abc_dynamic_constant;
typedef struct {
    uint32_t entry, end, arguments, results, hidden_bytes, max_a, max_b, max_c; unsigned has_halt, allocation_free;
    uint8_t argument_kinds[255], result_kinds[255];
} abc_function;
typedef struct { char *name; uint32_t function; } abc_export;
typedef struct { char *name; uint8_t arguments, results, argument_kinds[10], result_kinds[1]; } abc_extern;
typedef abc_status (*abc_foreign_bridge_fn)(const abc_extern *,abc_foreign_address,const uint64_t *,uint64_t *);
typedef struct { uint32_t offset, function; } abc_code_reloc;
struct abc_module {
    uint8_t *code; size_t code_size;
    abc_function *functions; uint32_t function_count;
    abc_export *exports; uint32_t export_count;
    uint8_t *image, *load_kinds; uint32_t data_size, image_size;
    unsigned memory_profile, callable_profile, foreign_profile, dynamic_profile; atomic_uint references;
    abc_function *sites; uint32_t site_count;
    abc_code_reloc *relocs; uint32_t reloc_count;
    abc_extern *externs; uint32_t extern_count;
    abc_descriptor *descriptors; uint32_t descriptor_count;
    abc_dynamic_constant *dynamic_constants; uint32_t dynamic_constant_count;
    abc_gc_root *gc_roots; uint32_t gc_root_count;
};
static inline uint16_t abc_u16(const uint8_t *p) { return (uint16_t)(p[0] | (uint16_t)p[1] << 8); }
static inline uint32_t abc_instruction_length(const uint8_t *p) { return p[0]==OP_SWITCH ? 3u+4u*abc_u16(p+1) : p[0]==OP_EXT ? ext_len[p[1]] : op_len[p[0]]; }
static inline uint32_t abc_u32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
static inline uint64_t abc_u64(const uint8_t *p) { return abc_u32(p) | (uint64_t)abc_u32(p + 4) << 32; }
static inline int64_t abc_signed(uint64_t x) {
    return x <= INT64_MAX ? (int64_t)x : -1 - (int64_t)(UINT64_MAX - x);
}
static inline int32_t abc_i32(const uint8_t *p) { return (int32_t)abc_signed((uint64_t)abc_u32(p) | ((p[3] & 128) ? UINT64_C(0xffffffff00000000) : 0)); }
static inline int32_t abc_i16(const uint8_t *p) { uint32_t x = abc_u16(p); return x < 32768 ? (int32_t)x : (int32_t)x - 65536; }
static inline uint64_t abc_imm8(uint8_t x) { return x < 128 ? x : UINT64_MAX - (255 - x); }
static inline abc_status abc_fail(abc_error *e, abc_status s, uint32_t off, const char *fmt, ...) {
    if (e) {
        e->status = s; e->offset = off; e->reason = 0;
        va_list ap; va_start(ap, fmt); vsnprintf(e->message, sizeof e->message, fmt, ap); va_end(ap);
    }
    return s;
}
static inline void abc_clear(abc_error *e) { if (e) { memset(e, 0, sizeof *e); e->offset = UINT32_MAX; } }
int abc_find_export(const abc_module *m, const char *name);
int abc_find_function(const abc_module *m, uint32_t entry);
static inline const abc_function *abc_function_entry(const abc_module *m,uint32_t entry) {
    uint32_t lo=0,hi=m->function_count; while(lo<hi){uint32_t mid=lo+(hi-lo)/2,v=m->functions[mid].entry;if(v<entry)lo=mid+1;else hi=mid;}
    return lo<m->function_count&&m->functions[lo].entry==entry?&m->functions[lo]:NULL;
}
const abc_function *abc_find_site(const abc_module *module,uint32_t offset);
static inline int abc_same_signature(const abc_function *a,const abc_function *b) {
    return a->arguments==b->arguments && a->results==b->results && a->hidden_bytes==b->hidden_bytes &&
        !memcmp(a->argument_kinds,b->argument_kinds,a->arguments) && !memcmp(a->result_kinds,b->result_kinds,a->results);
}
abc_status abc_load_memory(const void *bytes, size_t size, abc_module **out, abc_error *error);
abc_foreign_bridge_fn abc_foreign_select(const abc_extern *ext);
abc_status abc_foreign_invoke(const abc_extern *ext,abc_foreign_address fn,const uint64_t *args,uint64_t *out);
#endif

