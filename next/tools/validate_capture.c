#include "symbolic.h"
#include <stdio.h>
#include <stdlib.h>

typedef struct { abc_symbolic_context *context; abc_error *error; unsigned calls; int fail; } Probe;
static void require(int ok,const char *message){if(!ok){fprintf(stderr,"capture contract: %s\n",message);exit(1);}}
static int capture(void *opaque,uint32_t pc,abc_symbolic_value *value){
    Probe *p=opaque;p->calls++;
    require(pc==0x55&&value->kind==ABC_SYM_HOME,"capture must receive the source read and its instruction PC");
    for(unsigned s=0;s<3;s++)require(p->context->n[s]==1,"capture must precede source consumption and destination replacement");
    if(p->fail){abc_fail(p->error,ABC_INVALID,pc,"injected capture failure");return 0;}
    value->kind=ABC_SYM_BACKEND;value->reg=7;return 1;
}
int main(void){
    unsigned tests=0;
    for(unsigned op=0;op<6;op++)for(unsigned failure=0;failure<2;failure++){
        abc_symbolic_context x={0};abc_error error={0};
        for(unsigned s=0;s<3;s++)require(abc_symbolic_push(&x,s,abc_symbolic_home(s,0)),"initial allocation");
        Probe p={&x,&error,0,(int)failure};abc_symbolic_machine m={.context=&x,.sink=&p,.capture=capture,.pc=0x55,.error=&error};
        int ok;unsigned destination;
        switch(op){
        case 0:ok=abc_symbolic_machine_dup(&m,ABC_SYM_A);destination=ABC_SYM_A;break;
        case 1:ok=abc_symbolic_machine_transfer(&m,ABC_SYM_A,ABC_SYM_B,0);destination=ABC_SYM_B;break;
        case 2:ok=abc_symbolic_machine_transfer(&m,ABC_SYM_A,ABC_SYM_B,1);destination=ABC_SYM_B;break;
        case 3:ok=abc_symbolic_machine_cpush(&m,ABC_SYM_A);destination=ABC_SYM_C;break;
        case 4:ok=abc_symbolic_machine_cget(&m,ABC_SYM_B,0);destination=ABC_SYM_B;break;
        default:ok=abc_symbolic_machine_cset(&m,ABC_SYM_B,0);destination=ABC_SYM_C;break;
        }
        require(p.calls==1,"one source capture per transfer");
        if(failure){
            require(!ok&&m.exit==ABC_SYM_EXIT_FAILURE&&error.status==ABC_INVALID&&error.offset==0x55,"capture failure must retain its status and PC");
            for(unsigned s=0;s<3;s++)require(x.n[s]==1&&x.s[s][0].kind==ABC_SYM_HOME,"failed capture must not consume or replace cells");
        }else{
            abc_symbolic_value *v=abc_symbolic_top(&x,destination,0);
            require(ok&&v->kind==ABC_SYM_BACKEND&&v->reg==7&&v->dst_stack==destination,"destination must name the captured value");
        }
        abc_symbolic_context_free(&x);tests++;
    }
    for(unsigned kind=0;kind<2;kind++){
        abc_symbolic_context x={0};abc_error error={0};Probe p={&x,&error,0,0};
        abc_symbolic_value value=kind?abc_symbolic_backend(3,ABC_SYM_A,0):abc_symbolic_constant(42,ABC_SYM_A,0);
        require(abc_symbolic_push(&x,ABC_SYM_A,value),"initial value allocation");
        abc_symbolic_machine m={.context=&x,.sink=&p,.capture=capture,.pc=0x55,.error=&error};
        require(abc_symbolic_machine_dup(&m,ABC_SYM_A)&&!p.calls,"captured registers and constants must rename without a home read");
        require(x.s[ABC_SYM_A][1].kind==value.kind&&x.s[ABC_SYM_A][1].reg==value.reg&&x.s[ABC_SYM_A][1].constant==value.constant,"renaming must preserve value identity");
        abc_symbolic_context_free(&x);tests++;
    }
    printf("validated %u capture contracts (ordering, failure/PC preservation, register/constant renaming)\n",tests);
    return 0;
}
