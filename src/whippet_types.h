#ifndef ABC_WHIPPET_TYPES_H
#define ABC_WHIPPET_TYPES_H
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
struct abc_vm;
struct abc_module;
struct gc_heap;
struct gc_mutator;
struct abc_whippet_roots { struct abc_vm *vm; };
typedef struct abc_object {
    uintptr_t tag;
    size_t bytes;
    uint32_t descriptor;
    uint8_t kind, published;
    uint16_t reserved;
    const struct abc_module *module;
    unsigned char data[];
} abc_object;
#define ABC_GC_TAG(kind) (((uintptr_t)(kind) << 1) | 1u)
#define ABC_GC_TAG_KIND(tag) ((unsigned)(((tag) >> 1) & 0x7fu))
struct abc_whippet_heap {
    struct gc_heap *heap;
    struct gc_mutator *mutator;
    struct abc_whippet_roots roots;
};
#endif
