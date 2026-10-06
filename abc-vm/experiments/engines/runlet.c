#define _GNU_SOURCE
#include "abc.h"
#include "vm_internal.h"
#include "residualize.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t); return (double)t.tv_sec+(double)t.tv_nsec*1e-9;
}
static int cmp_double(const void *a,const void *b) { double x=*(const double *)a,y=*(const double *)b; return (x>y)-(x<y); }
static double median(double *v,int n) { qsort(v,(size_t)n,sizeof *v,cmp_double); return v[n/2]; }
static int fail(const char *where,const abc_error *e) { fprintf(stderr,"%s: %s (%s)\n",where,e->message,abc_status_name(e->status)); return 1; }

int main(int argc,char **argv) {
    if(argc<3||argc>4) { fprintf(stderr,"usage: runlet interpreted|compiled MODULE [TRIALS]\n"); return 2; }
    int trials=argc==4?atoi(argv[3]):9; if(trials<3||!(trials&1)) { fprintf(stderr,"TRIALS must be odd and >=3\n"); return 2; }
    abc_execution_mode mode=!strcmp(argv[1],"compiled")?ABC_EXEC_COMPILED:!strcmp(argv[1],"lazy")?ABC_EXEC_LAZY:!strcmp(argv[1],"interpreted")?ABC_EXEC_INTERPRETED:-1;
    if((int)mode<0) { fprintf(stderr,"invalid mode\n"); return 2; }
    abc_error e; abc_module *m=NULL; abc_vm *vm=NULL; double *read_times=calloc((size_t)trials,sizeof *read_times),*exec_times=calloc((size_t)trials,sizeof *exec_times);
    if(!read_times||!exec_times) return 1;
    for(int i=0;i<trials;i++) { double t=now(); abc_module *q=NULL; if(abc_module_read(argv[2],&q,&e)!=ABC_OK) return fail("read",&e); read_times[i]=now()-t; abc_module_free(q); }
    if(abc_module_read(argv[2],&m,&e)!=ABC_OK) return fail("read",&e);
    abc_limits limits={.stack_cells=UINT32_C(1)<<20,.mode=mode};
    double prepare_start=now(); if(abc_vm_create(&limits,&vm,&e)!=ABC_OK||abc_vm_load(vm,m,&e)!=ABC_OK) return fail("prepare",&e); double prepare_time=now()-prepare_start;
    uint64_t result=0; size_t nresults=0;
    double warmup_start=now();if(abc_vm_call(vm,m,"main",NULL,0,&result,1,&nresults,&e)!=ABC_OK) return fail("warmup",&e);double warmup_time=now()-warmup_start;
    for(int i=0;i<trials;i++) { double t=now(); if(abc_vm_call(vm,m,"main",NULL,0,&result,1,&nresults,&e)!=ABC_OK) return fail("call",&e); exec_times[i]=now()-t; }
    size_t code_bytes=0; if(mode!=ABC_EXEC_INTERPRETED&&vm->images&&vm->images->native) {
        abc_native_image *native=vm->images->native; code_bytes=native->code_size; const char *dump=getenv("ABC_DUMP_NATIVE");
        if(dump) { FILE *f=fopen(dump,"wb"); if(!f||fwrite(native->code,1,native->code_size,f)!=native->code_size) { perror("native dump"); return 1; } fclose(f);
            fprintf(stderr,"native base=%p bytes=%zu",(void *)native->code,native->code_size); for(uint32_t i=0;i<native->entry_count;i++) fprintf(stderr," entry%u=%zu",i,(size_t)((uint8_t *)native->entries[i]-native->code)); fputc('\n',stderr);
        }
    }
    printf("%llu %.9f %.9f %.9f %zu %.9f\n",(unsigned long long)result,median(exec_times,trials),median(read_times,trials),prepare_time,code_bytes,warmup_time);
    abc_vm_free(vm); abc_module_free(m); free(read_times); free(exec_times); return nresults==1?0:1;
}
