/* Link a test copy of generated stencils.o with --gc-sections after localizing
   its `calloc` symbol (a stencil label, not libc's allocator). Production uses
   extracted bytes, not this link. Checks the primitive ABI, not the full JIT. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define JIT __attribute__((preserve_none))
#define ARGS uint64_t *asp,uint64_t *bsp,uint64_t *csp, \
    uint64_t r0,uint64_t r1,uint64_t r2,uint64_t r3, \
    uint64_t r4,uint64_t r5,uint64_t r6,uint64_t r7
#define DECLARE(name) extern JIT uint64_t name(ARGS)
DECLARE(sub_0_1);DECLARE(sub_1_0);DECLARE(sub_7_6);
DECLARE(divu_0_1);DECLARE(divu_1_0);
DECLARE(u32_sub_0_1);DECLARE(u32_sub_1_0);
DECLARE(float_fsub_0_1);DECLARE(float_fsub_1_0);
DECLARE(float_fdiv_0_1);DECLARE(float_fdiv_1_0);
DECLARE(float_flt_0_1);DECLARE(float_flt_1_0);
DECLARE(memcpy_0_1);DECLARE(memcpy_1_0);
typedef JIT uint64_t (*primitive)(ARGS);
static uint64_t observed[8],a[1],b[1],c[1];
static unsigned continued,cases;
char HOLE_ERROR[1];
/* HOLE_IMM is linked as the absolute value 65539 for the copy primitives. */
void *HOLE_FINAL(void *destination,const void *source,size_t bytes) {
    return memmove(destination,source,bytes);
}
JIT uint64_t HOLE_NEXT(ARGS) {
    assert(asp==a&&bsp==b&&csp==c);
    uint64_t registers[]={r0,r1,r2,r3,r4,r5,r6,r7};
    memcpy(observed,registers,sizeof observed);continued++;return 0;
}
static uint64_t bits(double value) {uint64_t result;memcpy(&result,&value,sizeof result);return result;}
static void check(primitive operation,unsigned destination,unsigned source,
                  uint64_t selected,uint64_t opposite,uint64_t expected,int trapped) {
    uint64_t registers[]={101,102,103,104,105,106,107,108};
    registers[destination]=selected;registers[source]=opposite;continued=0;
    uint64_t status=operation(a,b,c,registers[0],registers[1],registers[2],registers[3],
                             registers[4],registers[5],registers[6],registers[7]);
    if(trapped){assert(status==(uint64_t)(uintptr_t)HOLE_ERROR);assert(!continued);}
    else {
        assert(status==0&&continued==1);registers[destination]=expected;
        assert(!memcmp(observed,registers,sizeof registers));
    }
    cases++;
}
static void check_copy(void) {
    enum { COPY_BYTES=65539, STORAGE_BYTES=2*COPY_BYTES+64 };
    static uint8_t storage[STORAGE_BYTES],original[STORAGE_BYTES],expected[STORAGE_BYTES];
    const unsigned destinations[]={5,23,5,COPY_BYTES+17};
    const unsigned sources[]={23,5,5,5};
    for(unsigned bank=0;bank<2;bank++)for(unsigned shape=0;shape<4;shape++) {
        for(unsigned index=0;index<STORAGE_BYTES;index++)original[index]=(uint8_t)(index*37+index/251);
        memcpy(storage,original,sizeof storage);memcpy(expected,original,sizeof expected);
        for(unsigned index=0;index<COPY_BYTES;index++)expected[destinations[shape]+index]=original[sources[shape]+index];
        uint64_t destination=(uint64_t)(uintptr_t)(storage+destinations[shape]);
        uint64_t source=(uint64_t)(uintptr_t)(storage+sources[shape]);
        check(bank?memcpy_1_0:memcpy_0_1,bank,1-bank,destination,source,destination,0);
        assert(!memcmp(storage,expected,sizeof storage));
    }
}
int main(void) {
    check_copy();
    check(sub_0_1,0,1,10,3,7,0);
    check(sub_1_0,1,0,3,10,UINT64_MAX-6,0);
    check(sub_7_6,7,6,3,10,UINT64_MAX-6,0);
    check(divu_0_1,0,1,10,3,3,0);check(divu_1_0,1,0,3,10,0,0);
    check(divu_0_1,0,1,10,0,0,1);check(divu_1_0,1,0,10,0,0,1);
    check(divu_0_1,0,1,0,10,0,0);check(divu_1_0,1,0,0,10,0,0);
    check(u32_sub_0_1,0,1,UINT64_C(0x100000003),5,UINT32_MAX-1,0);
    check(u32_sub_1_0,1,0,UINT64_C(0x100000003),5,UINT32_MAX-1,0);
    check(float_fsub_0_1,0,1,bits(10),bits(3),bits(7),0);
    check(float_fsub_1_0,1,0,bits(3),bits(10),bits(-7),0);
    check(float_fdiv_0_1,0,1,bits(8),bits(2),bits(4),0);
    check(float_fdiv_1_0,1,0,bits(2),bits(8),bits(0.25),0);
    check(float_flt_0_1,0,1,bits(3),bits(10),1,0);
    check(float_flt_1_0,1,0,bits(10),bits(3),0,0);
    check(float_flt_0_1,0,1,UINT64_C(0x7ff8000000000001),bits(3),0,0);
    check(float_flt_1_0,1,0,bits(3),UINT64_C(0x7ff8000000000001),0,0);
    printf("native selected-first primitives: %u contracts, other registers preserved\n",cases);
    return 0;
}
