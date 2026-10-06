#include "vm_internal.h"

uint64_t vm_sar(uint64_t x,uint64_t n) {
    if(n>=64)return x>>63?UINT64_MAX:0;
    return n?(x>>n)|(x>>63?UINT64_MAX<<(64-n):0):x;
}
uint64_t vm_pow(uint64_t x,uint64_t n) {
    uint64_t result=1;while(n){if(n&1)result*=x;x*=x;n>>=1;}return result;
}
int32_t abc_i32_from_u64(uint64_t x) {
    uint32_t low=(uint32_t)x;
    return low<UINT32_C(0x80000000)?(int32_t)low:(int32_t)abc_signed((uint64_t)low|UINT64_C(0xffffffff00000000));
}
