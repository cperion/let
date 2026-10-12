#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Standalone ABI feasibility probe, NOT another ABC execution engine.
 * The tape uses final handler pointers, not serialized opcodes. */
typedef union Word Word;
#define CC __attribute__((preserve_none))
#define NOINLINE __attribute__((noinline))
#define ARGS const Word *ip, uint64_t *asp, uint64_t *bsp, uint64_t *csp, \
    uint64_t r0, uint64_t r1, uint64_t r2, uint64_t r3, \
    uint64_t r4, uint64_t r5, uint64_t r6, uint64_t r7
#define PASS ip,asp,bsp,csp,r0,r1,r2,r3,r4,r5,r6,r7
#define NEXT() __attribute__((musttail)) return ip[0].handler(PASS)
typedef CC uint64_t (*Handler)(ARGS);
union Word {
    Handler handler;
    uint64_t bits;
    int64_t offset;
    const Word *target;
};
_Static_assert(sizeof(Word)==8, "eight-byte tape word required");
_Static_assert(_Alignof(Word)==8, "eight-byte alignment required");

CC NOINLINE uint64_t const_r2(ARGS) { r2=ip[1].bits; ip+=2; NEXT(); }
CC NOINLINE uint64_t add_r2_r5(ARGS) { r2+=r5; ip++; NEXT(); }
CC NOINLINE uint64_t addi_r2(ARGS) { r2+=ip[1].bits; ip+=2; NEXT(); }
CC NOINLINE uint64_t load_C_r5(ARGS) {
    memcpy(&r5,(const unsigned char *)csp+ip[1].offset,8); ip+=2; NEXT();
}
CC NOINLINE uint64_t load_A_r3(ARGS) {
    memcpy(&r3,(const unsigned char *)asp+ip[1].offset,8); ip+=2; NEXT();
}
CC NOINLINE uint64_t store_A_r2(ARGS) {
    memcpy((unsigned char *)asp+ip[1].offset,&r2,8); ip+=2; NEXT();
}
CC NOINLINE uint64_t bne_r2_r3(ARGS) { ip=r2!=r3?ip[1].target:ip+2; NEXT(); }
CC NOINLINE uint64_t jump(ARGS) { ip=ip[1].target; NEXT(); }
CC NOINLINE uint64_t finish(ARGS) {
    (void)ip;
    const uint64_t registers[8]={r0,r1,r2,r3,r4,r5,r6,r7};
    memcpy(asp+2,registers,sizeof registers);
    asp[10]=(uintptr_t)asp; asp[11]=(uintptr_t)bsp; asp[12]=(uintptr_t)csp;
    return 0;
}

static const uint64_t seed[8]={
    UINT64_C(0x0123456789abcdef),UINT64_C(0xfedcba9876543210),
    UINT64_C(0x3141592653589793),UINT64_C(0xcafebabedeadbeef),
    UINT64_C(0x8877665544332211),UINT64_C(0x1122334455667788),
    UINT64_C(0x8000000000000000),UINT64_C(0xffffffffffffffff)
};
static double now(void) {
    struct timespec t;
    if(clock_gettime(CLOCK_MONOTONIC,&t))abort();
    return (double)t.tv_sec+(double)t.tv_nsec*1e-9;
}
static NOINLINE uint64_t enter(const Word *ip,uint64_t *a,uint64_t *b,uint64_t *c) {
    return ip[0].handler(ip,a,b,c,seed[0],seed[1],seed[2],seed[3],
                         seed[4],seed[5],seed[6],seed[7]);
}
static int check(const uint64_t *a,uint64_t *b,uint64_t *c,
                 uint64_t result,uint64_t r3,uint64_t r5) {
    uint64_t expected[8];memcpy(expected,seed,sizeof expected);
    expected[2]=result;expected[3]=r3;expected[5]=r5;
    if(a[1]!=result || memcmp(a+2,expected,sizeof expected) ||
       a[10]!=(uintptr_t)a || a[11]!=(uintptr_t)b || a[12]!=(uintptr_t)c ||
       a[13]!=UINT64_C(0xd00dd00dd00dd00d) || *b!=123 || c[-1]!=1) {
        fprintf(stderr,"register/pointer/store preservation failure\n");return 0;
    }
    return 1;
}
static void initialize(uint64_t *a,uint64_t n) {
    memset(a,0,14*sizeof *a); a[0]=n;a[13]=UINT64_C(0xd00dd00dd00dd00d);
}
static int compare(const void *a,const void *b) {
    double x=*(const double *)a,y=*(const double *)b;return (x>y)-(x<y);
}
int main(int argc,char **argv) {
    uint64_t n=argc>1?strtoull(argv[1],NULL,10):UINT64_C(10000000);
    if(!n || n>UINT64_C(1000000000)){fprintf(stderr,"iterations: 1..1000000000\n");return 2;}
    uint64_t a[14],b[1]={123},c[1]={1};
    /* Every pointer is bound after final allocation: no moving published tape. */
    Word *tape=calloc(12,sizeof *tape);
    if(!tape)return 2;
    tape[0].handler=const_r2;tape[1].bits=0;
    tape[2].handler=load_C_r5;tape[3].offset=-8;
    tape[4].handler=load_A_r3;tape[5].offset=0;
    tape[6].handler=add_r2_r5;
    tape[7].handler=bne_r2_r3;tape[8].target=tape+6;
    tape[9].handler=store_A_r2;tape[10].offset=8;
    tape[11].handler=finish;
    const uint64_t cases[]={1,2,7,16,255,65537};
    for(size_t i=0;i<sizeof cases/sizeof cases[0];i++) {
        initialize(a,cases[i]);
        if(enter(tape,a,b,c+1)||!check(a,b,c+1,cases[i],cases[i],1))return 1;
    }
    /* Immediate wraparound, forward branch linkage, and a skipped record. */
    Word small[11]={0};
    small[0].handler=const_r2;small[1].bits=UINT64_MAX;
    small[2].handler=addi_r2;small[3].bits=8;
    small[4].handler=jump;small[5].target=small+8;
    small[6].handler=const_r2;small[7].bits=99; /* must be skipped */
    small[8].handler=store_A_r2;small[9].offset=8;small[10].handler=finish;
    initialize(a,0);
    if(enter(small,a,b,c+1)||!check(a,b,c+1,7,seed[3],seed[5]))return 1;
    small[4].handler=store_A_r2;small[5].offset=8;
    small[6].handler=jump;small[7].target=small+10;
    initialize(a,0);
    if(enter(small,a,b,c+1)||!check(a,b,c+1,7,seed[3],seed[5]))return 1;
    double elapsed[7];
    for(unsigned trial=0;trial<7;trial++) {
        initialize(a,n);double start=now();uint64_t status=enter(tape,a,b,c+1);
        elapsed[trial]=now()-start;
        if(status||!check(a,b,c+1,n,n,1))return 1;
        printf("trial=%u iterations=%llu seconds=%.9f ns_per_record=%.4f\n",
               trial,(unsigned long long)n,elapsed[trial],elapsed[trial]*1e9/(2.0*n+5));
    }
    qsort(elapsed,7,sizeof elapsed[0],compare);
    printf("PASS correctness_cases=8 timed_calls=7 tape_bytes=96 "
           "median_ns_per_record=%.4f\n",elapsed[3]*1e9/(2.0*n+5));
    free(tape);return 0;
}
