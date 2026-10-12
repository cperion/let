#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile uint64_t sink;
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t); return (double)t.tv_sec+(double)t.tv_nsec*1e-9; }
static uint32_t next32(uint32_t s) { s^=s<<13; s^=s>>17; return s^(s<<5); }
static uint32_t step32(uint32_t x) { return (x&1)?x*3+1:x>>1; }
static __attribute__((noinline)) uint32_t fib(uint32_t n) { return n<2?n:fib(n-1)+fib(n-2); }
static uint64_t run(const char *name,uint64_t n) {
    if(!strcmp(name,"loop")) { uint32_t acc=0; while(n) { acc=next32(acc)^(uint32_t)n; n--; } return acc; }
    if(!strcmp(name,"skip")) { uint32_t s=2463534242u; while(n--) s=next32(s); return s; }
    if(!strcmp(name,"branch")) { uint32_t x=0x12345678u,acc=0; while(n--) { x=step32(x); acc+=x&255u; } return acc; }
    if(!strcmp(name,"sum2")) { uint32_t a=0x12345678u,b=0x9e3779b9u; while(n--) { a=next32(a); b=next32(b); } return a^b; }
    if(!strcmp(name,"mul")) { uint32_t x=0x12345678u,acc=0; while(n--) { x=x*33u+17u; acc+=x&65535u; } return acc; }
    if(!strcmp(name,"divide")) { uint32_t x=0x76543210u,acc=0; while(n--) { uint32_t q=x/3u; acc+=x-q*3u; x=q+0x9e3779b9u; } return acc; }
    if(!strcmp(name,"mix")) { uint32_t x=0x12345678u,acc=0; while(n--) { x=(x^(x>>7))*5u+1u; acc+=x&1023u; } return acc; }
    return fib((uint32_t)n);
}
int main(int argc,char **argv) {
    if(argc!=4) return 2;
    int trials=atoi(argv[3]); if(trials<1||trials>1000) return 2;
    /* A fresh volatile input prevents reuse/hoisting of a pure kernel result. */
    volatile uint64_t n=strtoull(argv[2],NULL,10);
    double *times=calloc((size_t)trials,sizeof *times); if(!times)return 2;
    double t=now(); sink=run(argv[1],n); double first=now()-t;
    uint64_t expected=sink;
    for(int i=0;i<trials;i++) { t=now(); sink=run(argv[1],n); times[i]=now()-t; if(sink!=expected)return 3; }
    printf("{\"result\":%llu,\"first\":%.9f,\"samples\":[",(unsigned long long)sink,first);
    for(int i=0;i<trials;i++)printf("%s%.9f",i?",":"",times[i]);
    puts("]}"); free(times); return 0;
}

