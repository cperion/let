#include "native_emit.h"
#include "generated/execution_forms.h"
#include "generated/stencils.h"

/* Independent byte-wise relocation oracle. This test deliberately reads stencil
   metadata; production residualization must not do so. No generated code runs. */
static unsigned checks;
static void require(int condition,const char *what,unsigned form) {
    if(!condition){fprintf(stderr,"native emission: %s, form %u\n",what,form);exit(1);}
    checks++;
}
static void expected_patch(uint8_t *out,const uint8_t *actual,const Reloc *r,uint64_t target) {
    uint64_t bits=target+(uint64_t)(int64_t)r->addend;
    unsigned width=r->kind==R8?1:r->kind==R64?8:4;
    if(r->kind==RPC32)bits-=(uintptr_t)(actual+r->off);
    for(unsigned byte=0;byte<width;byte++)out[r->off+byte]=(uint8_t)(bits>>(8*byte));
}
static uint64_t prepare(uint64_t state,uint64_t *error){*error=0;return state;}
static uint64_t resolve(uint64_t target,uint64_t pc,uintptr_t a,uintptr_t b,uintptr_t c,uint64_t *entry) {
    (void)pc;(void)a;(void)b;(void)c;*entry=target;return 0;
}
static abc_status bridge(const abc_extern *ext,abc_foreign_address target,const uint64_t *in,uint64_t *out) {
    (void)ext;(void)target;(void)in;(void)out;return ABC_OK;
}
static void foreign_target(void) {}
static uint64_t *bounds(unsigned stack){(void)stack;return NULL;}

int main(void) {
    size_t maximum=0;
    for(unsigned f=0;f<ABC_FORM_COUNT;f++)if(stencils[f].len>maximum)maximum=stencils[f].len;
    uint8_t *allocation=malloc(maximum+32),*expected=malloc(maximum);
    require(allocation&&expected,"allocation",0);
    uint8_t *at=allocation+16;
    const uint64_t patterns[]={0,UINT64_C(0x0123456789abcdef),UINT64_MAX,UINT64_C(0xffffffff00000008)};
    for(unsigned f=0;f<ABC_FORM_COUNT;f++){
        const Stencil *s=&stencils[f];
        require(abc_native_form_size(f)==s->len,"size",f);
        for(unsigned p=0;p<sizeof patterns/sizeof patterns[0];p++){
            memset(allocation,0xa5,maximum+32);memcpy(expected,s->code,s->len);
            abc_native_patch ref={0};uint64_t target=(uintptr_t)(at+s->len-1),imm=patterns[p];unsigned targets=0;
            require(abc_native_emit_simple(at,f,imm,&ref),"simple emission",f);
            for(unsigned i=0;i<s->nrel;i++){
                const Reloc *r=&s->rel[i];uint64_t value=0;
                if(r->hole==HOLE_NEXT)value=(uintptr_t)(at+s->len);
                else if(r->hole==HOLE_TAKEN){value=target;targets++;}
                else if(r->hole==HOLE_IMM||r->hole==HOLE_FINAL||r->hole==HOLE_ERROR)value=imm;
                else if(r->hole==HOLE_IMM2)value=imm>>32;
                expected_patch(expected,at,r,value);
            }
            require(targets<=1,"one target per form",f);
            require(abc_native_patch_present(&ref)==(targets!=0),"reference presence",f);
            if(targets){abc_native_patch copied=ref;abc_native_bind(&copied,target);}
            require(!memcmp(at,expected,s->len),"simple bytes",f);
            for(unsigned i=0;i<16;i++)require(allocation[i]==0xa5,"leading canary",f);
            for(size_t i=s->len;i<maximum+16;i++)require(at[i]==0xa5,"trailing canary",f);
        }
    }
    abc_extern ext={0};
    const uint64_t error=ABC_ABORT|(UINT64_C(3)<<8)|(UINT64_C(0x12345678)<<16);
    for(unsigned f=0;f<ABC_FORM_COUNT;f++){
        const Stencil *s=&stencils[f];uint64_t values[8]={0};int specialized=1,ok=0;
        memset(allocation,0xa5,maximum+32);memcpy(expected,s->code,s->len);
        values[HOLE_NEXT]=(uintptr_t)(at+s->len);
        if(f>=ABC_FORM_MEMCPY_BASE&&f<ABC_FORM_MEMCPY_BASE+64){
            unsigned r=f-ABC_FORM_MEMCPY_BASE;
            values[HOLE_IMM]=65539;values[HOLE_FINAL]=(uintptr_t)memmove;
            ok=abc_native_emit_copy(at,r/8,r%8,65539,memmove);
        }else if(f>=ABC_FORM_FCALL_BASE&&f<ABC_FORM_FCALL_BASE+4){
            values[HOLE_IMM]=24;values[HOLE_FINAL]=(uintptr_t)bridge;
            values[HOLE_STATE]=(uintptr_t)&ext;values[HOLE_BIAS]=(uintptr_t)foreign_target;values[HOLE_ERROR]=error;
            ok=abc_native_emit_foreign(at,f,24,bridge,&ext,foreign_target,error);
        }else if(f>=ABC_FORM_GUARD_BASE&&f<ABC_FORM_GUARD_BASE+3){
            values[HOLE_IMM]=513*8;values[HOLE_FINAL]=(uintptr_t)bounds;values[HOLE_ERROR]=error;
            ok=abc_native_emit_guard(at,f-ABC_FORM_GUARD_BASE,513*8,bounds,error);
        }else if(f==ABC_FORM_RESOLVE_INDIRECT){
            values[HOLE_IMM]=(uint64_t)(int64_t)-24;values[HOLE_BIAS]=40;values[HOLE_IMM2]=(uint64_t)(int64_t)-8;
            values[HOLE_STATE]=1234;values[HOLE_FINAL]=(uintptr_t)resolve;
            ok=abc_native_emit_resolve(at,resolve,1234,-24,40,-8);
        }else if(f==ABC_FORM_LAZY_ENTRY){
            values[HOLE_STATE]=(uintptr_t)&ext;values[HOLE_FINAL]=(uintptr_t)prepare;
            ok=abc_native_emit_lazy(at,&ext,prepare);
        }else if(f==ABC_FORM_SERVICE){
            values[HOLE_IMM]=(uintptr_t)foreign_target;values[HOLE_STATE]=4321;
            ok=abc_native_emit_service(at,(uintptr_t)foreign_target,4321);
        }else specialized=0;
        if(!specialized)continue;
        require(ok,"specialized emission",f);
        for(unsigned i=0;i<s->nrel;i++){
            require(s->rel[i].hole<sizeof values/sizeof values[0],"hole index",f);
            expected_patch(expected,at,&s->rel[i],values[s->rel[i].hole]);
        }
        require(!memcmp(at,expected,s->len),"specialized bytes",f);
        for(unsigned i=0;i<16;i++)require(allocation[i]==0xa5,"specialized leading canary",f);
        for(size_t i=s->len;i<maximum+16;i++)require(at[i]==0xa5,"specialized trailing canary",f);
    }
    require(!abc_native_form_size(ABC_FORM_COUNT),"invalid form size",ABC_FORM_COUNT);
    require(!abc_native_emit_simple(at,ABC_FORM_COUNT,0,NULL),"invalid form",ABC_FORM_COUNT);
    require(!abc_native_emit_simple(at,ABC_FORM_JUMP,0,NULL),"missing target",ABC_FORM_JUMP);
    require(!abc_native_emit_copy(at,8,0,0,memmove),"invalid register",0);
    require(!abc_native_emit_guard(at,3,0,bounds,0),"invalid stack",0);
    printf("native emitter: %u checks, %u forms x 4 payloads, specialized bindings and canaries pass\n",checks,ABC_FORM_COUNT);
    free(expected);free(allocation);return 0;
}
