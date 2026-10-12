#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
/* Public standalone emitted-C export ABI, matching the existing AOT runner. */
typedef struct { uint32_t status; uint32_t offset; uint8_t reason; } abc_aot_error;
typedef int (*abc_aot_entry)(const uint64_t *,size_t,uint64_t *,size_t,abc_aot_error *);
typedef struct { const char *name; uint32_t arguments; uint32_t results; abc_aot_entry entry; } abc_aot_export;
extern const abc_aot_export *abc_aot_find(const char *);
static volatile uint64_t sink;
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t); return (double)t.tv_sec+(double)t.tv_nsec*1e-9; }
int main(int argc,char **argv) {
    if(argc!=3)return 2;
    int trials=atoi(argv[2]); if(trials<1||trials>1000)return 2;
    const abc_aot_export *entry=abc_aot_find("main");
    if(!entry||entry->arguments!=1||entry->results!=1)return 2;
    volatile uint64_t input=strtoull(argv[1],NULL,10);
    uint64_t argument=input,result=0; abc_aot_error error;
    double *samples=calloc((size_t)trials,sizeof *samples); if(!samples)return 2;
    double t=now(); if(entry->entry(&argument,1,&result,1,&error))return 3; double first=now()-t;
    uint64_t expected=result; sink=result;
    for(int i=0;i<trials;i++) {
        argument=input; t=now(); if(entry->entry(&argument,1,&result,1,&error))return 3; samples[i]=now()-t;
        sink=result; if(result!=expected)return 3;
    }
    printf("{\"result\":%llu,\"first\":%.9f,\"samples\":[",(unsigned long long)sink,first);
    for(int i=0;i<trials;i++)printf("%s%.9f",i?",":"",samples[i]);
    puts("]}"); free(samples); return 0;
}
