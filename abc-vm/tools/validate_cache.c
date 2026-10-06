#include "abc.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *what,const abc_error *e) {
    fprintf(stderr,"cache validation %s: %s at 0x%x: %s\n",what,abc_status_name(e->status),e->offset,e->message);
    exit(1);
}

int main(int argc,char **argv) {
    if(argc!=3) { fprintf(stderr,"usage: validate-cache module oracle\n"); return 2; }
    abc_error e; abc_module *m=NULL; abc_vm *vm=NULL;
    if(abc_module_read(argv[1],&m,&e)!=ABC_OK) fail("module",&e);
    abc_limits limits={.stack_cells=64,.mode=ABC_EXEC_INTERPRETED};
    if(abc_vm_create(&limits,&vm,&e)!=ABC_OK) fail("VM",&e);
    FILE *f=fopen(argv[2],"r"); if(!f) { perror(argv[2]); return 1; }
    char name[128]; unsigned count,cases=0; uint64_t expected[32],actual[32];
    while(fscanf(f,"%127s %u",name,&count)==2) {
        if(count>32) { fprintf(stderr,"oversized oracle row %s\n",name); return 1; }
        for(unsigned i=0;i<count;i++) if(fscanf(f,"%" SCNu64,&expected[i])!=1) { fprintf(stderr,"truncated oracle\n"); return 1; }
        size_t got=0; abc_status s=abc_vm_call(vm,m,name,NULL,0,actual,32,&got,&e);
        if(s!=ABC_OK) fail(name,&e);
        if(got!=count || memcmp(actual,expected,count*sizeof *actual)) {
            fprintf(stderr,"cache validation mismatch in %s\n",name); return 1;
        }
        cases++;
    }
    fclose(f); abc_vm_free(vm); abc_module_free(m);
    printf("validated %u cache-state transitions\n",cases); return 0;
}

