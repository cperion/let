#ifndef ABC_SCALAR_RULES_H
#define ABC_SCALAR_RULES_H
#include <limits.h>
#include "any_repr.h"
#include "opcodes.h"
/* Tag validity/promotion is shared by concrete checks, symbolic facts and
   extracted register checks. None of these routines executes an EXT opcode. */
static inline unsigned abc_numeric_width(unsigned tag) {
    static const uint8_t widths[]={0,1,8,16,32,64,32,64,64};
    return tag<sizeof widths?widths[tag]:0;
}
static inline int abc_numeric_integer(unsigned tag) { return tag>=ABC_ANY_U8&&tag<=ABC_ANY_I64; }
static inline int abc_numeric_signed(unsigned tag) { return tag==ABC_ANY_I32||tag==ABC_ANY_I64; }
static __attribute__((always_inline)) inline unsigned abc_scalar_promote(unsigned left,unsigned right,int floating) {
    if(left>=ABC_ANY_U8&&left<=ABC_ANY_U64&&right>=ABC_ANY_U8&&right<=ABC_ANY_U64)return left>right?left:right;
    if(left>=ABC_ANY_I32&&left<=ABC_ANY_I64&&right>=ABC_ANY_I32&&right<=ABC_ANY_I64)return left>right?left:right;
    return floating&&left==ABC_ANY_F64&&right==ABC_ANY_F64?ABC_ANY_F64:UINT_MAX;
}
static inline int abc_scalar_float_allowed(unsigned selector) {
    return (selector>=EXT_DADD&&selector<=EXT_DDIV)||selector==EXT_DLT||selector==EXT_DLE;
}
static inline unsigned abc_numeric_result(unsigned selector,unsigned left,unsigned right) {
    if((selector<EXT_DADD||selector>EXT_DXOR)&&selector!=EXT_DLT&&selector!=EXT_DLE)return UINT_MAX;
    return abc_scalar_promote(left,right,abc_scalar_float_allowed(selector));
}
static inline uint16_t abc_numeric_arguments(unsigned result) {
    uint16_t mask=0;for(unsigned tag=ABC_ANY_U8;tag<=ABC_ANY_F64;tag++)
        if(abc_numeric_result(EXT_DADD,tag,result)==result)mask|=(uint16_t)(1u<<tag);
    return mask;
}
static __attribute__((always_inline)) inline unsigned abc_scalar_equality_kind(unsigned a,unsigned b) {
    if(abc_numeric_integer(a)&&abc_numeric_integer(b)){
        int sa=abc_numeric_signed(a),sb=abc_numeric_signed(b);
        return sa==sb?(sa?ABC_ANY_I32:ABC_ANY_U8):sa?14:15;
    }
    return a==b?a:UINT_MAX;
}
static __attribute__((always_inline)) inline int abc_scalar_mixed_equal(uint64_t left,uint64_t right) {
    return left==right&&!(left>>63);
}
static inline uint16_t abc_scalar_equality_arguments(unsigned kind,unsigned operand) {
    const uint16_t u=(1u<<ABC_ANY_U8)|(1u<<ABC_ANY_U16)|(1u<<ABC_ANY_U32)|(1u<<ABC_ANY_U64);
    const uint16_t s=(1u<<ABC_ANY_I32)|(1u<<ABC_ANY_I64);
    if(kind==ABC_ANY_U8)return u;if(kind==ABC_ANY_I32)return s;
    if(kind==14)return operand==1?s:u;if(kind==15)return operand==1?u:s;
    return (uint16_t)(1u<<kind);
}
static inline int abc_scalar_literal(unsigned input,unsigned *literal,uint64_t *bits,unsigned adopt) {
    if(adopt&&abc_numeric_integer(input)){
        int signed_literal=abc_numeric_signed(*literal);unsigned width=abc_numeric_width(input);
        if(abc_numeric_signed(input)){
            int64_t q=signed_literal?(int64_t)*bits:*bits<=INT64_MAX?(int64_t)*bits:INT64_MIN;
            if(width==32?(q<INT32_MIN||q>INT32_MAX):(!signed_literal&&*bits>INT64_MAX))return 0;
            *bits=(uint64_t)q;
        }else {
            if(signed_literal&&(int64_t)*bits<0)return 0;
            if(width<64&&*bits>((UINT64_C(1)<<width)-1))return 0;
        }
        *literal=input;
    }
    unsigned width=abc_numeric_width(*literal);
    if(width==8)*bits&=255;else if(width==16)*bits&=65535;
    else if(width==32)*bits=abc_numeric_signed(*literal)?(uint64_t)(int64_t)(int32_t)*bits:(uint32_t)*bits;
    return 1;
}
#endif
