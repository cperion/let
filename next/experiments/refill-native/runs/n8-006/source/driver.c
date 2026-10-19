#define _GNU_SOURCE
#include <assert.h>
#include <inttypes.h>
#include <sched.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include "ops.h"

typedef struct { uint64_t op, arg; } Ins;
typedef struct {
    const Ins *ip;
    uint64_t *memory, backed, r, t, bank[8], b;
} Start;
typedef struct {
    uint64_t bank[8], b;
    uint64_t *asp;
    const Ins *ip;
    uint64_t r, t;
} Snapshot;
_Static_assert(sizeof(Ins)==16 && offsetof(Start,bank)==40 && offsetof(Start,b)==104, "start ABI");
_Static_assert(offsetof(Snapshot,asp)==72 && offsetof(Snapshot,t)==96, "snapshot ABI");
extern uint64_t vm_demand(const Start *);
extern uint64_t vm_eager(const Start *);
extern uint64_t vm_return_only(const Start *);
typedef uint64_t (*Run)(const Start *);
static Run runners[]={vm_demand,vm_eager,vm_return_only};
static const char *names[]={"demand","eager","return-only"};
enum { CAP=8192, CODE=2048 };
typedef struct { Ins *code; size_t n; const char *name; uint64_t expected; } Program;
typedef struct { uint64_t a[CAP], b, steps; size_t n; const Ins *ip; int live, halted; } Oracle;
static Oracle oracle;
static uint64_t *base;
#ifdef CHECKED
static uint64_t checked_events, checked_cases, states[3][8][9], handlers[3][8][9][OP_COUNT];
static unsigned current_policy;
#endif

static void reset_oracle(const Start *s) {
    memset(&oracle,0,sizeof oracle);
    assert(s->r<8 && s->t<=8 && s->backed+s->t<CAP);
    oracle.ip=s->ip; oracle.n=s->backed+s->t;
    memcpy(oracle.a,s->memory,s->backed*8);
    for(size_t i=0;i<s->t;i++) oracle.a[s->backed+i]=s->bank[(s->r+i)%8];
    /* All test entries start with logically empty B; its physical bits are poison. */
}
static void ref_step(void) {
    Oracle *o=&oracle;
    assert(!o->halted && ++o->steps<10000000);
    const Ins in=*o->ip++;
    if(in.op>=OP_GET0 && in.op<=OP_GET31) {
        size_t d=in.op-OP_GET0;
        assert(d<o->n && o->n<CAP);
        uint64_t v=o->a[o->n-1-d]; o->a[o->n++]=v; return;
    }
    switch(in.op) {
    case OP_PUSH: assert(o->n<CAP);o->a[o->n++]=in.arg;break;
    case OP_DROP: assert(o->n);o->n--;break;
    case OP_TO_B: assert(o->n && !o->live);o->b=o->a[--o->n];o->live=1;break;
    case OP_FROM_B: assert(o->live && o->n<CAP);o->a[o->n++]=o->b;o->live=0;break;
    case OP_ADD: assert(o->n && o->live);o->a[o->n-1]+=o->b;o->live=0;break;
    case OP_ADDI: assert(o->n);o->a[o->n-1]+=in.arg;break;
    case OP_NIP: assert(o->n>=2);o->a[o->n-2]=o->a[o->n-1];o->n--;break;
    case OP_SET1: {
        assert(o->n>=3);uint64_t v=o->a[--o->n];o->a[o->n-2]=v;break;
    }
    case OP_JNZ: case OP_BGE2: {
        assert(o->n);uint64_t v=o->a[--o->n];
        if(in.op==OP_JNZ ? v!=0 : v>=2) o->ip=(const Ins *)(uintptr_t)in.arg;
        break;
    }
    case OP_CALL: case OP_CALL_B:
        assert(!o->live && o->n && o->n<CAP);
        assert(((uintptr_t)o->ip&15)==0);
        o->a[o->n++]=(uintptr_t)o->ip | (in.op==OP_CALL_B);
        o->ip=(const Ins *)(uintptr_t)in.arg;break;
    case OP_RET: {
        assert(!o->live && o->n>=3);
        uint64_t value=o->a[o->n-1],target=o->a[o->n-2];o->n-=3;
        o->ip=(const Ins *)(uintptr_t)(target&~UINT64_C(1));
        if(target&1){o->b=value;o->live=1;}else o->a[o->n++]=value;
        break;
    }
    case OP_HALT: assert(o->n && !o->live);o->halted=1;break;
    default: abort();
    }
}
#ifdef CHECKED
void check_snapshot(const Snapshot *s) {
    assert(s->r<8 && s->t<=8 && s->asp>=base && s->asp<=base+CAP);
    size_t backed=(size_t)(s->asp-base);
    assert(backed+s->t==oracle.n && s->ip==oracle.ip);
    assert(!oracle.live || s->b==oracle.b);
    for(size_t i=0;i<backed;i++) assert(base[i]==oracle.a[i]);
    for(size_t i=0;i<s->t;i++) assert(s->bank[(s->r+i)%8]==oracle.a[backed+i]);
    checked_events++;states[current_policy][s->r][s->t]++;
    assert(s->ip->op<OP_COUNT);handlers[current_policy][s->r][s->t][s->ip->op]++;
    ref_step();
}
#endif
static size_t emit(Program *p,uint64_t op,uint64_t arg) {
    assert(p->n<CODE);p->code[p->n]=(Ins){op,arg};return p->n++;
}
static Program program(const char *name) {
    Program p={.code=aligned_alloc(16,CODE*sizeof(Ins)),.name=name};assert(p.code);return p;
}
static void target(Program *p,size_t at,size_t to) {p->code[at].arg=(uintptr_t)&p->code[to];}
static uint64_t fib_value(unsigned n) {
    uint64_t a=0,b=1;while(n--){uint64_t t=a+b;a=b;b=t;}return a;
}
static Program fib(unsigned n) {
    Program p=program("fib20");p.expected=fib_value(n);
    emit(&p,OP_PUSH,n);size_t entry=emit(&p,OP_CALL,0);emit(&p,OP_HALT,0);
    size_t f=p.n;target(&p,entry,f);
    emit(&p,OP_GET1,0);size_t branch=emit(&p,OP_BGE2,0);
    emit(&p,OP_GET1,0);emit(&p,OP_RET,0);
    target(&p,branch,p.n);
    emit(&p,OP_GET1,0);emit(&p,OP_ADDI,(uint64_t)-1);
    target(&p,emit(&p,OP_CALL,0),f);
    emit(&p,OP_GET2,0);emit(&p,OP_ADDI,(uint64_t)-2);
    target(&p,emit(&p,OP_CALL_B,0),f);
    emit(&p,OP_ADD,0);emit(&p,OP_RET,0);return p;
}
static void accumulate(Program *p) {
    /* ... accumulator counter term -> ... updated-accumulator counter */
    emit(p,OP_TO_B,0);emit(p,OP_GET1,0);emit(p,OP_ADD,0);emit(p,OP_SET1,0);
}
static void loop_end(Program *p,size_t loop) {
    emit(p,OP_ADDI,(uint64_t)-1);emit(p,OP_GET0,0);
    target(p,emit(p,OP_JNZ,0),loop);emit(p,OP_DROP,0);
}
static Program expressions(void) {
    Program p=program("expressions64");p.expected=2080*256;
    emit(&p,OP_PUSH,0);emit(&p,OP_PUSH,256);size_t loop=p.n;
    for(unsigned i=1;i<=64;i++)emit(&p,OP_PUSH,i);
    for(unsigned i=1;i<64;i++){emit(&p,OP_TO_B,0);emit(&p,OP_ADD,0);}
    accumulate(&p);loop_end(&p,loop);emit(&p,OP_HALT,0);return p;
}
static Program locals(void) {
    Program p=program("locals12");p.expected=66*8*64;
    for(unsigned i=0;i<12;i++)emit(&p,OP_PUSH,i);
    emit(&p,OP_PUSH,0);emit(&p,OP_PUSH,64);size_t loop=p.n;
    for(unsigned i=0;i<12;i++)emit(&p,OP_PUSH,123+i);
    for(unsigned i=0;i<12;i++)emit(&p,OP_DROP,0);
    for(unsigned k=0;k<8;k++)for(unsigned i=0;i<12;i++) {
        emit(&p,OP_GET0+13-i,0);accumulate(&p);
    }
    loop_end(&p,loop);
    for(unsigned i=0;i<12;i++)emit(&p,OP_NIP,0);
    emit(&p,OP_HALT,0);return p;
}
static Program oscillation(void) {
    Program p=program("oscillation");p.expected=0;
    for(unsigned i=0;i<31;i++)emit(&p,OP_PUSH,123+i);
    emit(&p,OP_PUSH,4096);size_t loop=p.n;
    emit(&p,OP_TO_B,0);emit(&p,OP_FROM_B,0);emit(&p,OP_ADDI,(uint64_t)-1);
    emit(&p,OP_GET0,0);target(&p,emit(&p,OP_JNZ,0),loop);
    for(unsigned i=0;i<31;i++)emit(&p,OP_NIP,0);
    emit(&p,OP_HALT,0);return p;
}
static Start start(const Ins *ip) {
    Start s={.ip=ip,.memory=base,.b=UINT64_C(0xbadbadbad)};
    for(unsigned i=0;i<8;i++)s.bank[i]=UINT64_C(0xdead00000000)+i;
    return s;
}
static uint64_t evaluate(const Start *s,uint64_t *steps) {
    reset_oracle(s);while(!oracle.halted)ref_step();
    if(steps)*steps=oracle.steps;
    return oracle.a[oracle.n-1];
}
static void validate(const Start *s,uint64_t expected) {
    uint64_t saved[CAP];assert(s->backed<CAP);
    memcpy(saved,s->memory,s->backed*8);
    assert(evaluate(s,NULL)==expected);
    for(unsigned p=0;p<3;p++) {
        memcpy(s->memory,saved,s->backed*8);
#ifdef CHECKED
        current_policy=p;reset_oracle(s);
#endif
        assert(runners[p](s)==expected);
#ifdef CHECKED
        assert(oracle.halted);checked_cases++;
#endif
    }
}
#ifdef CHECKED
static uint64_t rng=UINT64_C(0x20261019);
static uint64_t random64(void) {rng^=rng<<13;rng^=rng>>7;rng^=rng<<17;return rng;}
static void fixtures(void) {
    Program p=program("fixture");
    /* Inject every physical ring state, with empty/short/long backing prefixes. */
    for(unsigned r=0;r<8;r++)for(unsigned t=0;t<=8;t++)for(unsigned m=0;m<=16;m+=8) {
        unsigned depth=m+t;
        for(unsigned op=0;op<OP_COUNT;op++) {
            if(op==OP_RET || op==OP_HALT)continue;
            if(op>=OP_GET0 && op-OP_GET0>=depth)continue;
            if(!depth && op!=OP_PUSH)continue;
            if((op==OP_DROP || op==OP_NIP) && depth<2)continue;
            if(op==OP_SET1 && depth<3)continue;
            Start s=start(p.code);s.r=r;s.t=t;s.backed=m;
            for(unsigned i=0;i<m;i++)base[i]=100+i;
            for(unsigned i=0;i<t;i++)s.bank[(r+i)%8]=100+m+i;
            p.n=0;
            if(op==OP_ADD) {emit(&p,OP_GET0,0);emit(&p,OP_TO_B,0);emit(&p,OP_ADD,0);}
            else if(op==OP_FROM_B) {emit(&p,OP_TO_B,0);emit(&p,OP_FROM_B,0);}
            else if(op==OP_TO_B) {emit(&p,op,0);emit(&p,OP_FROM_B,0);}
            else if(op==OP_JNZ || op==OP_BGE2) {
                emit(&p,OP_GET0,0);size_t branch=emit(&p,op,0);
                emit(&p,OP_ADDI,1);target(&p,branch,p.n);
            } else if(op==OP_CALL || op==OP_CALL_B) {
                size_t call=emit(&p,op,0);
                if(op==OP_CALL_B)emit(&p,OP_FROM_B,0);
                emit(&p,OP_HALT,0);target(&p,call,p.n);
                emit(&p,OP_GET1,0);emit(&p,OP_RET,0);
            } else emit(&p,op,17);
            emit(&p,OP_HALT,0);
            validate(&s,evaluate(&s,NULL));
        }
    }
    for(unsigned trial=0;trial<100;trial++) {
        p.n=0;unsigned depth=0,live=0;
        for(unsigned i=0;i<256;i++) {
            uint64_t choice=random64()%7;
            if(live) {if(depth && (choice&1))emit(&p,OP_ADD,0);else{emit(&p,OP_FROM_B,0);depth++;}live=0;}
            else if(!depth || (choice==0 && depth<96)){emit(&p,OP_PUSH,random64());depth++;}
            else if(choice==1 && depth<96){emit(&p,OP_GET0+random64()%(depth<32?depth:32),0);depth++;}
            else if(choice==2){emit(&p,OP_TO_B,0);depth--;live=1;}
            else if(choice==3 && depth>1){emit(&p,OP_DROP,0);depth--;}
            else if(choice==4 && depth>1){emit(&p,OP_NIP,0);depth--;}
            else if(choice==5 && depth>2){emit(&p,OP_SET1,0);depth--;}
            else emit(&p,OP_ADDI,random64());
        }
        if(live){emit(&p,OP_FROM_B,0);depth++;}
        if(!depth){emit(&p,OP_PUSH,0);depth++;}
        while(depth-->1)emit(&p,OP_NIP,0);
        emit(&p,OP_HALT,0);Start s=start(p.code);validate(&s,evaluate(&s,NULL));
    }
    free(p.code);
}
#else
static uint64_t now(void) {
    struct timespec t;assert(clock_gettime(CLOCK_MONOTONIC_RAW,&t)==0);
    return (uint64_t)t.tv_sec*1000000000+t.tv_nsec;
}
static volatile uint64_t sink;
static uint64_t batch(Run run,const Start *s,uint64_t count,uint64_t expected) {
    uint64_t sum=0,begin=now();
    for(uint64_t i=0;i<count;i++)sum+=run(s);
    uint64_t elapsed=now()-begin;sink=sum;assert(sum==count*expected);return elapsed;
}
static void measure(const Program *p) {
    Start s=start(p->code);uint64_t steps;
    assert(evaluate(&s,&steps)==p->expected);
    /* Same iteration count for every policy. Warm all, calibrate demand to 30 ms. */
    for(unsigned i=0;i<3;i++)batch(runners[i],&s,8,p->expected);
    uint64_t count=1;
    while(batch(runners[0],&s,count,p->expected)<30000000) {count*=2;assert(count<(1u<<24));}
    static const unsigned order[6][3]={{0,1,2},{0,2,1},{1,0,2},{1,2,0},{2,0,1},{2,1,0}};
    for(unsigned sample=0;sample<18;sample++)for(unsigned j=0;j<3;j++) {
        unsigned policy=order[sample%6][j];
        uint64_t elapsed=batch(runners[policy],&s,count,p->expected);
        printf("%s,%s,%u,%"PRIu64",%"PRIu64",%.3f,%"PRIu64",%"PRIu64"\n",
               p->name,names[policy],sample,count,elapsed,(double)elapsed/count,steps,sink);
    }
}
#endif
int main(void) {
    cpu_set_t allowed,chosen;CPU_ZERO(&allowed);assert(sched_getaffinity(0,sizeof allowed,&allowed)==0);
    int cpu=0;while(cpu<CPU_SETSIZE && !CPU_ISSET(cpu,&allowed))cpu++;assert(cpu<CPU_SETSIZE);
    CPU_ZERO(&chosen);CPU_SET(cpu,&chosen);assert(sched_setaffinity(0,sizeof chosen,&chosen)==0);
    long page=sysconf(_SC_PAGESIZE);assert(page>0 && (CAP*8)%(size_t)page==0);
    void *mapping=mmap(NULL,CAP*8+2*(size_t)page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);assert(mapping!=MAP_FAILED);
    base=(uint64_t *)((char *)mapping+page);assert(mprotect(base,CAP*8,PROT_READ|PROT_WRITE)==0);
    Program programs[]={fib(20),expressions(),locals(),oscillation()};
    printf("# cpu=%d clock=CLOCK_MONOTONIC_RAW ring_registers=8\n",cpu);
#ifdef CHECKED
    fixtures();
    for(unsigned p=0;p<3;p++) {
        unsigned visited=0;for(unsigned r=0;r<8;r++)for(unsigned t=0;t<=8;t++)visited+=states[p][r][t]!=0;
        printf("%s fixture_checked_states=%u/72\n",names[p],visited);assert(visited==72);
    }
#endif
    for(unsigned i=0;i<4;i++) {
#ifdef CHECKED
        memset(states,0,sizeof states);memset(handlers,0,sizeof handlers);
#endif
        Start s=start(programs[i].code);validate(&s,programs[i].expected);
#ifdef CHECKED
        for(unsigned p=0;p<3;p++) {
            unsigned visited=0,hot=0;
            for(unsigned r=0;r<8;r++)for(unsigned t=0;t<=8;t++) {
                visited+=states[p][r][t]!=0;
                for(unsigned op=0;op<OP_COUNT;op++)hot+=handlers[p][r][t][op]!=0;
            }
            printf("workload=%s policy=%s states=%u handlers=%u\n",programs[i].name,names[p],visited,hot);
        }
#endif
    }
#ifdef CHECKED
    printf("validated_policy_runs=%"PRIu64" checked_instruction_entries=%"PRIu64"\n",checked_cases,checked_events);
#else
    puts("workload,policy,sample,iterations,total_ns,ns_per_run,instructions_per_run,checksum");
    for(unsigned i=0;i<4;i++)measure(&programs[i]);
#endif
    for(unsigned i=0;i<4;i++)free(programs[i].code);
    assert(munmap(mapping,CAP*8+2*(size_t)page)==0);return 0;
}
