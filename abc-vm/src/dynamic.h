#ifndef ABC_DYNAMIC_H
#define ABC_DYNAMIC_H
#include "vm_internal.h"
#include "whippet_types.h"

enum {
    ABC_ANY_UNIT, ABC_ANY_BOOL, ABC_ANY_U8, ABC_ANY_U16, ABC_ANY_U32, ABC_ANY_U64,
    ABC_ANY_I32, ABC_ANY_I64, ABC_ANY_F64, ABC_ANY_STRING, ABC_ANY_PTR, ABC_ANY_WORD,
    ABC_ANY_CLOSURE, ABC_ANY_AGGREGATE
};


typedef enum {
    ABC_RESIDUAL_DYNAMIC_OPERATION,
    ABC_RESIDUAL_DYNAMIC_CALL,
    ABC_RESIDUAL_DYNAMIC_TAIL_CALL,
    ABC_RESIDUAL_DYNAMIC_MATERIALIZE,
    ABC_RESIDUAL_DYNAMIC_CALLABLE
} abc_residual_dynamic_kind;

typedef struct {
    uint64_t origin;
    uint64_t selector;
    uint64_t descriptor;
    uint64_t adjustment;
    uint64_t target;
    uint64_t literal_low;
    uint64_t literal_high;
    uint32_t arguments;
    uint32_t results;
    uint8_t kind;
    uint8_t reverse;
    uint8_t has_literal;
    uint8_t literal_primitive;
    uint8_t literal_flags;
    uint8_t materialize_decode;
    uint8_t has_environment;
} abc_residual_dynamic_site;

struct abc_dynamic_heap {
    struct abc_whippet_heap gc;
    _Atomic unsigned collection_requested;
    unsigned temporary_count;
    uint64_t temporary[4], call_roots[255], *suspended;
    size_t suspended_count;
    unsigned call_root_count;
};

uint64_t abc_any_unit(void);
unsigned abc_any_tag(const abc_vm *vm,uint64_t value);
abc_status vm_dynamic(abc_run *run,const uint8_t *p,uint32_t pc);
uint64_t vm_dynamic_residual_native(uint64_t **asp,uint64_t **bsp,
    uint64_t **csp,const uint8_t *state,uint32_t pc);
void abc_dynamic_collect(abc_vm *vm);
void abc_dynamic_destroy(abc_vm *vm);

#endif

