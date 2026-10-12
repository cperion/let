#ifndef ABC_ANY_REPR_H
#define ABC_ANY_REPR_H
#include "whippet_types.h"
#include "gc-api.h"

enum {
    ABC_ANY_UNIT, ABC_ANY_BOOL, ABC_ANY_U8, ABC_ANY_U16, ABC_ANY_U32, ABC_ANY_U64,
    ABC_ANY_I32, ABC_ANY_I64, ABC_ANY_F64, ABC_ANY_STRING, ABC_ANY_PTR, ABC_ANY_WORD,
    ABC_ANY_CLOSURE, ABC_ANY_AGGREGATE
};
enum { ABC_OBJECT_WORD_MAP=64, ABC_OBJECT_MANAGED=65, ABC_OBJECT_STORAGE=66 };
typedef struct { uint64_t bits; uint8_t tag; } scalar_box;
typedef struct { uint32_t length; char bytes[]; } string_box;
typedef struct { uint64_t address, length, owner; } managed_box;
typedef struct { uint32_t size, owner_count; unsigned char storage[]; } aggregate_box;
struct abc_dynamic_heap {
    struct abc_whippet_heap gc;
    unsigned temporary_count;
    uint64_t temporary[4], call_roots[255], *suspended;
    size_t suspended_count;
    uint64_t *native_roots; /* live physical register bank, only during collection */
    unsigned call_root_count;
};

#define IMM_PREFIX UINT64_C(0xffff000000000000)
#define IMM_MASK   UINT64_C(0xffff000000000000)
#define TAG_SHIFT 40
#define PAYLOAD_MASK UINT64_C(0x000000ffffffffff)
#define FLOAT_OFFSET UINT64_C(0x0001000000000000)
#define POSITIVE_NAN_COUNT UINT64_C(0x000fffffffffffff)

/* Representation primitives shared by the interpreter and extracted stencils.
   Always inline: these are bit operations, never native runtime dispatch. */
#define ABC_REPR_INLINE static __attribute__((always_inline)) inline
ABC_REPR_INLINE uint64_t immediate(unsigned tag,uint64_t payload) {
    return IMM_PREFIX|((uint64_t)tag<<TAG_SHIFT)|(payload&PAYLOAD_MASK);
}
ABC_REPR_INLINE int float_nan_bits(uint64_t bits) {
    return (bits&UINT64_C(0x7ff0000000000000))==UINT64_C(0x7ff0000000000000)&&(bits&UINT64_C(0x000fffffffffffff));
}
ABC_REPR_INLINE uint64_t encode_float(uint64_t bits) {
    uint64_t rank=float_nan_bits(bits)?UINT64_MAX-2*POSITIVE_NAN_COUNT+1:
        bits<UINT64_C(0x8000000000000000)?bits:bits-POSITIVE_NAN_COUNT;
    return rank+FLOAT_OFFSET;
}
ABC_REPR_INLINE uint64_t decode_float(uint64_t encoded) {
    uint64_t rank=encoded-FLOAT_OFFSET;
    if(rank<=UINT64_C(0x7ff0000000000000))return rank;
    if(rank<UINT64_MAX-2*POSITIVE_NAN_COUNT+1)return rank+POSITIVE_NAN_COUNT;
    return UINT64_C(0x7ff8000000000000);
}
typedef int (*abc_heap_contains_fn)(struct gc_heap *,struct gc_ref);
ABC_REPR_INLINE abc_object *abc_repr_object(const struct abc_dynamic_heap *heap,uint64_t value,abc_heap_contains_fn contains) {
    if(!heap||!heap->gc.heap||(value&15)||(value>>48)||!contains(heap->gc.heap,gc_ref(value)))return NULL;
    abc_object *o=(abc_object *)(uintptr_t)value;
    return (o->tag&1u)&&o->published&&ABC_GC_TAG_KIND(o->tag)==o->kind?o:NULL;
}
ABC_REPR_INLINE unsigned abc_repr_tag(const struct abc_dynamic_heap *heap,uint64_t value,abc_heap_contains_fn contains) {
    if((value&IMM_MASK)==IMM_PREFIX)return (unsigned)((value>>TAG_SHIFT)&255);
    abc_object *o=abc_repr_object(heap,value,contains);if(!o)return ABC_ANY_F64;
    if(o->kind==ABC_OBJECT_MANAGED)return ABC_ANY_AGGREGATE;
    if(o->kind==ABC_ANY_STRING||o->kind==ABC_ANY_WORD||o->kind==ABC_ANY_CLOSURE||o->kind==ABC_ANY_AGGREGATE)return o->kind;
    return ((scalar_box *)o->data)->tag;
}
ABC_REPR_INLINE int abc_repr_scalar(unsigned tag) {return tag<=ABC_ANY_F64||tag==ABC_ANY_PTR;}
/* Requires a scalar tag established by the preceding check. */
ABC_REPR_INLINE uint64_t abc_repr_bits(uint64_t value,unsigned tag) {
    if(tag==ABC_ANY_F64)return decode_float(value);
    if((value&IMM_MASK)==IMM_PREFIX){uint64_t payload=value&PAYLOAD_MASK;
        return tag==ABC_ANY_I32||tag==ABC_ANY_I64?(uint64_t)((int64_t)(payload<<24)>>24):payload;}
    return ((scalar_box *)((abc_object *)(uintptr_t)value)->data)->bits;
}
ABC_REPR_INLINE int abc_repr_fits(unsigned tag,uint64_t bits) {
    return tag==ABC_ANY_I32||tag==ABC_ANY_I64?bits+(UINT64_C(1)<<39)<(UINT64_C(1)<<40):bits<=PAYLOAD_MASK;
}
ABC_REPR_INLINE int abc_repr_string_equal(uint64_t left,uint64_t right) {
    const string_box *a=(const string_box *)((const abc_object *)(uintptr_t)left)->data;
    const string_box *b=(const string_box *)((const abc_object *)(uintptr_t)right)->data;
    if(a->length!=b->length)return 0;
    for(uint32_t i=0;i<a->length;i++)if(a->bytes[i]!=b->bytes[i])return 0;
    return 1;
}
#undef ABC_REPR_INLINE
#endif
