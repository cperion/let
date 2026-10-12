#include "generated/banked.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *what,const abc_error *e) {
    fprintf(stderr,"cache validation %s: %s at 0x%x: %s\n",what,abc_status_name(e->status),e->offset,e->message);
    exit(1);
}

/* Enter each exact cache state with both backing cells and nonzero dead ABI
 * arguments. The logical-stack oracle never reads the register representation. */
static void validate_dead_arguments(abc_vm *vm) {
    static const uint8_t ops[]={OP_ADD_A,OP_ADD_B,OP_MUL_A,OP_XOR_B,
        OP_DUP_A,OP_DROP_A,OP_CPUSH_A,OP_CPOP,OP_MOVE_AB,OP_COPY_BA,
        OP_CGET0_A,OP_CSET0_A,OP_DIVU_A,OP_SHL_A,OP_POW};
    unsigned cases=0;
    for(unsigned ca=0;ca<=4;ca++) for(unsigned cb=0;cb<=4-ca;cb++)
    for(unsigned cc=0;cc<=3;cc++) for(unsigned pattern=0;pattern<2;pattern++)
    for(size_t op=0;op<sizeof ops/sizeof *ops;op++) {
        uint64_t a[16],b[16],c[16];size_t na=2+ca,nb=2+cb,nc=2+cc;
        for(size_t i=0;i<na;i++) a[i]=11+i;
        for(size_t i=0;i<nb;i++) b[i]=21+i;
        for(size_t i=0;i<nc;i++) c[i]=31+i;
        vm->na=vm->nb=vm->nc=2;vm->nf=0;vm->ca=ca;vm->cb=cb;vm->cc=cc;
        memcpy(vm->a,a,2*sizeof *a);memcpy(vm->b,b,2*sizeof *b);memcpy(vm->c,c,2*sizeof *c);
        uint64_t poison=pattern?UINT64_C(0x123456789abcdef0):UINT64_MAX;
        for(unsigned i=0;i<4;i++) vm->h[i]=poison-i;
        for(unsigned i=0;i<3;i++) vm->cr[i]=poison-i-4;
        for(unsigned i=0;i<ca;i++) vm->h[i]=a[2+i];
        for(unsigned i=0;i<cb;i++) vm->h[3-i]=b[2+i];
        for(unsigned i=0;i<cc;i++) vm->cr[i]=c[2+i];
        switch(ops[op]) {
        case OP_ADD_A: a[na-1]+=b[--nb];break;
        case OP_ADD_B: b[nb-1]+=a[--na];break;
        case OP_MUL_A: a[na-1]*=b[--nb];break;
        case OP_XOR_B: b[nb-1]^=a[--na];break;
        case OP_DUP_A: a[na]=a[na-1];na++;break;
        case OP_DROP_A: na--;break;
        case OP_CPUSH_A: c[nc++]=a[--na];break;
        case OP_CPOP: nc--;break;
        case OP_MOVE_AB: b[nb++]=a[--na];break;
        case OP_COPY_BA: a[na++]=b[nb-1];break;
        case OP_CGET0_A: a[na++]=c[nc-1];break;
        case OP_CSET0_A: c[nc-1]=a[--na];break;
        case OP_DIVU_A: a[na-1]/=b[--nb];break;
        case OP_SHL_A: a[na-1]<<=b[--nb];break;
        case OP_POW: {uint64_t x=a[na-1],n=b[--nb],value=1;while(n--)value*=x;a[na-1]=value;break;}
        default: abort();
        }
        uint8_t code[]={ops[op],OP_HALT};abc_error e={0};
        abc_run run={.v=vm,.code=code,.e=&e};
        abc_run *previous=abc_active_run;abc_active_run=&run;
        unsigned state=(ca*5+cb)*4+cc;
        abc_status status=(abc_status)abc_tables[state][code[0]](
            code,vm->a+2,vm->b+2,vm->c+2,vm->h[0],vm->h[1],vm->h[2],vm->h[3],
            vm->cr[0],vm->cr[1],vm->cr[2]);
        abc_active_run=previous;
        if(status!=ABC_OK) fail("dead ABI arguments",&e);
        if(!run.done||vm->ca||vm->cb||vm->cc||vm->na!=na||vm->nb!=nb||vm->nc!=nc||
           memcmp(vm->a,a,na*sizeof *a)||memcmp(vm->b,b,nb*sizeof *b)||memcmp(vm->c,c,nc*sizeof *c)) {
            fprintf(stderr,"dead ABI argument mismatch: state=(%u,%u,%u) op=%u pattern=%u\n",ca,cb,cc,ops[op],pattern);
            exit(1);
        }
        cases++;
    }
    printf("validated %u exact-state handlers with poisoned dead ABI arguments\n",cases);
}

int main(int argc,char **argv) {
    if(argc!=3) { fprintf(stderr,"usage: validate-cache module oracle\n"); return 2; }
    abc_error e; abc_module *m=NULL; abc_vm *vm=NULL;
    if(abc_module_read(argv[1],&m,&e)!=ABC_OK) fail("module",&e);
    abc_limits limits={.stack_cells=64,.mode=ABC_EXEC_INTERPRETED};
    if(abc_vm_create(&limits,&vm,&e)!=ABC_OK) fail("VM",&e);
    validate_dead_arguments(vm);
    FILE *f=fopen(argv[2],"r"); if(!f) { perror(argv[2]); return 1; }
    char name[128]; unsigned count,cases=0; uint64_t expected[32],actual[32];
    while(fscanf(f,"%127s %u",name,&count)==2) {
        if(count>32) { fprintf(stderr,"oversized oracle row %s\n",name); return 1; }
        for(unsigned i=0;i<count;i++) if(fscanf(f,"%" SCNu64,&expected[i])!=1) { fprintf(stderr,"truncated oracle\n"); return 1; }
        for(unsigned pass=0;pass<2;pass++) {
            /* Repeat after RET quickening, with different dead values. */
            for(unsigned i=0;i<4;i++) vm->h[i]=UINT64_MAX-i-pass;
            for(unsigned i=0;i<3;i++) vm->cr[i]=UINT64_MAX-i-pass-4;
            size_t got=0; abc_status s=abc_vm_call(vm,m,name,NULL,0,actual,32,&got,&e);
            if(s!=ABC_OK) fail(name,&e);
            if(got!=count || memcmp(actual,expected,count*sizeof *actual)) {
                fprintf(stderr,"cache validation mismatch in %s (pass %u)\n",name,pass); return 1;
            }
        }
        cases++;
    }
    fclose(f); abc_vm_free(vm); abc_module_free(m);
    printf("validated %u cache-state transitions\n",cases); return 0;
}

