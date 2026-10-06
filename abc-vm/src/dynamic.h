#ifndef ABC_DYNAMIC_H
#define ABC_DYNAMIC_H
#include "vm_internal.h"
#include "whippet_types.h"

enum {
    ABC_ANY_UNIT, ABC_ANY_BOOL, ABC_ANY_U8, ABC_ANY_U16, ABC_ANY_U32, ABC_ANY_U64,
    ABC_ANY_I32, ABC_ANY_I64, ABC_ANY_F64, ABC_ANY_STRING, ABC_ANY_PTR, ABC_ANY_WORD,
    ABC_ANY_CLOSURE, ABC_ANY_AGGREGATE
};


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
void abc_dynamic_collect(abc_vm *vm);
void abc_dynamic_destroy(abc_vm *vm);

#endif

