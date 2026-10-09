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

/* Numeric dispatch is shared by concrete execution and symbolic CFGs.
   UINT_MAX means type mismatch; width promotion never mixes signedness. */
static inline unsigned abc_numeric_width(unsigned tag) {
    static const uint8_t widths[]={0,1,8,16,32,64,32,64,64};
    return tag<sizeof widths?widths[tag]:0;
}
static inline int abc_numeric_integer(unsigned tag) { return tag>=ABC_ANY_U8&&tag<=ABC_ANY_I64; }
static inline int abc_numeric_signed(unsigned tag) { return tag==ABC_ANY_I32||tag==ABC_ANY_I64; }
static inline unsigned abc_numeric_result(unsigned selector,unsigned left,unsigned right) {
    if(selector<EXT_DADD||selector>EXT_DXOR)return UINT_MAX;
    if(left==ABC_ANY_F64&&right==ABC_ANY_F64)
        return selector==EXT_DADD||selector==EXT_DSUB||selector==EXT_DMUL||selector==EXT_DDIV?ABC_ANY_F64:UINT_MAX;
    if(!abc_numeric_integer(left)||!abc_numeric_integer(right)||abc_numeric_signed(left)!=abc_numeric_signed(right))return UINT_MAX;
    return abc_numeric_width(left)>=abc_numeric_width(right)?left:right;
}
static inline uint16_t abc_numeric_arguments(unsigned result) {
    uint16_t mask=0;
    for(unsigned tag=ABC_ANY_U8;tag<=ABC_ANY_F64;tag++)
        if(abc_numeric_result(EXT_DADD,tag,result)==result)mask|=(uint16_t)(1u<<tag);
    return mask;
}
uint64_t abc_dynamic_numeric_classify(uint64_t state,uint64_t left,uint64_t right,uint64_t selector);
uint64_t abc_dynamic_numeric_bits(uint64_t value,uint64_t state);

uint64_t abc_any_unit(void);
unsigned abc_any_tag(const abc_vm *vm,uint64_t value);
abc_status vm_dynamic(abc_run *run,const uint8_t *p,uint32_t pc);
uint64_t vm_dynamic_residual_native(uint64_t **asp,uint64_t **bsp,
    uint64_t **csp,const uint8_t *state,uint32_t pc);
void abc_dynamic_collect(abc_vm *vm);
void abc_dynamic_destroy(abc_vm *vm);

#endif

