#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile uint64_t sink;
static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC_RAW,&t);
    return (double)t.tv_sec+(double)t.tv_nsec*1e-9;
}
static int compare(const void *a,const void *b) {
    double x=*(const double *)a,y=*(const double *)b;
    return (x>y)-(x<y);
}
/* An algorithm baseline, not a C implementation of ABC tagged arithmetic. */
static __attribute__((noinline)) uint64_t run(int floating,uint32_t n) {
    /* Keep each timed invocation opaque to interprocedural call hoisting. */
    __asm__ volatile("" : "+r"(n));
    if(floating) {
        double x=1;
        for(uint32_t i=0;i<n;i++) x+=0.5;
        return (uint64_t)(x*2);
    }
    uint32_t x=12345;
    for(uint32_t i=0;i<n;i++) x=((x^(x>>7))*5+i)&65535u;
    return x;
}
int main(int argc,char **argv) {
    if(argc!=4) return 2;
    int trials=atoi(argv[3]),floating=!strcmp(argv[1],"f64-carried");
    uint32_t n=(uint32_t)strtoul(argv[2],NULL,10);
    if(trials<3||!(trials&1)) return 2;
    double *times=calloc((size_t)trials,sizeof *times);
    if(!times) return 1;
    sink=run(floating,n);
    for(int i=0;i<trials;i++) {
        double start=now();sink=run(floating,n);times[i]=now()-start;
    }
    qsort(times,(size_t)trials,sizeof *times,compare);
    printf("%llu %.9f\n",(unsigned long long)sink,times[trials/2]);
    free(times);return 0;
}
