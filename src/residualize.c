#define _GNU_SOURCE
#include "residualize.h"
#include "symbolic.h"
#include "dynamic.h"
#include "generated/stencils.h"
#include "generated/stencil_layout.h"
_Static_assert(ABC_SYM_EQ==ABC_JBR_EQ && ABC_SYM_NE==ABC_JBR_NE &&
               ABC_SYM_LT==ABC_JBR_LT && ABC_SYM_LE==ABC_JBR_LE &&
               ABC_SYM_LTU==ABC_JBR_LTU && ABC_SYM_LEU==ABC_JBR_LEU,
               "symbolic/native branch relation mismatch");
#include <sys/mman.h>
#include <unistd.h>

enum { VK_CONST=ABC_SYM_CONST, VK_REG=ABC_SYM_BACKEND, VK_HOME=ABC_SYM_HOME };
enum { JS_A=ABC_SYM_A, JS_B=ABC_SYM_B, JS_C=ABC_SYM_C };
typedef abc_symbolic_value JValue;
typedef abc_symbolic_continuation VCont;
typedef abc_symbolic_context Context;
#define context_free abc_symbolic_context_free
#define context_copy abc_symbolic_context_copy
#define vcont_equal abc_symbolic_vcont_equal
#define continuation_equal abc_symbolic_continuation_equal
#define context_equal abc_symbolic_context_equal
#define context_family_equal abc_symbolic_context_family_equal
#define generic_context_equal abc_symbolic_generic_context_equal
#define push abc_symbolic_push
#define push_cont abc_symbolic_push_continuation
#define pop abc_symbolic_pop
#define top abc_symbolic_top
#define home_value abc_symbolic_home
#define rehome_value abc_symbolic_rehome
#define const_value abc_symbolic_constant
#define reg_value abc_symbolic_backend
typedef struct Version Version;
typedef struct Compiler Compiler;
struct Version { uint64_t saved[12]; uint32_t pc; Context in; uint8_t *address,*body,*lazy_site; int32_t lazy_addend; uint8_t lazy_kind; unsigned compiling,compiled; Compiler *owner; Version *next; };
typedef struct { uint8_t *site; uint8_t kind; int32_t addend; Version *target; } Fixup;
struct Compiler {
    const abc_module *module; const abc_vm *vm; uint8_t *image_base, *base, *pos, *end, *stub_pos; uint64_t *stack_end[3];
    Version **versions, **function_entries; uint8_t *block, *recursive;
    Version **queue; size_t nq, qhead, qcap, placements, virtual_calls, virtual_returns, virtual_tails, real_calls;
    Fixup *fixups; size_t nfix, fixcap;
    abc_status status; abc_error *error; uint32_t current_pc;
    abc_ic_state *sites; struct abc_native_image *image; size_t mapping_size; unsigned lazy;
};
typedef __attribute__((preserve_none)) uint64_t (*NativeFn)(
    uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
typedef __attribute__((preserve_none)) uint64_t (*LazyFn)(
    uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
typedef struct { uint8_t *site; uint8_t kind; int32_t addend; } ICPatch;
struct abc_ic_state {
    const abc_module *module; const abc_function *signature; abc_native_image *owner;
    void *observed; ICPatch *patches; size_t npatch, patchcap; uint8_t phase, tail;
};
static __attribute__((preserve_none)) uint64_t ic_observe_call(uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
static __attribute__((preserve_none)) uint64_t ic_specific_call(uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
static __attribute__((preserve_none)) uint64_t ic_final_call(uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
static __attribute__((preserve_none)) uint64_t ic_observe_tail(uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
static __attribute__((preserve_none)) uint64_t ic_specific_tail(uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
static __attribute__((preserve_none)) uint64_t ic_final_tail(uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);

static void put8(uint8_t *p,int8_t value) { memcpy(p,&value,1); }
static void put32(uint8_t *p,int32_t value) { memcpy(p,&value,4); }
static void put64(uint8_t *p,int64_t value) { memcpy(p,&value,8); }
static void patch(uint8_t *site,unsigned kind,int32_t addend,int64_t target) {
    if(kind==RPC32) put32(site,(int32_t)(target+addend-(int64_t)(intptr_t)site));
    else if(kind==R32) put32(site,(int32_t)(target+addend));
    else if(kind==R8) put8(site,(int8_t)(target+addend));
    else put64(site,target+addend);
}
static int reserve(Compiler *c,size_t n) {
    if((size_t)(c->end-c->pos)>=n) return 1;
    c->status=abc_fail(c->error,ABC_NOMEM,c->current_pc,"compiled code exhausted after %zu bytes, %zu stencils (%zu/%zu versions)",(size_t)(c->pos-c->base),c->placements,c->qhead,c->nq); return 0;
}
static int grow(void **p,size_t *cap,size_t need,size_t size) {
    if(need<=*cap) return 1; size_t n=*cap ? *cap*2 : 32; while(n<need) n*=2;
    void *q=realloc(*p,n*size); if(!q) return 0; *p=q; *cap=n; return 1;
}
static int add_fixup(Compiler *c,uint8_t *site,unsigned kind,int32_t addend,Version *target) {
    if(!grow((void **)&c->fixups,&c->fixcap,c->nfix+1,sizeof *c->fixups)) return 0;
    c->fixups[c->nfix++]=(Fixup){site,(uint8_t)kind,addend,target}; return 1;
}
static int place(Compiler *c,unsigned id,uint64_t immediate,Version *taken) {
    if(id>=sizeof stencils/sizeof stencils[0]) { c->status=abc_fail(c->error,ABC_INVALID,UINT32_MAX,"invalid stencil id"); return 0; }
    const Stencil *s=&stencils[id]; c->placements++; if(!reserve(c,s->len)) return 0;
    uint8_t *at=c->pos; memcpy(at,s->code,s->len); c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++) { const Reloc *r=&s->rel[i]; uint8_t *site=at+r->off;
        if(r->hole==HOLE_NEXT) patch(site,r->kind,r->addend,(int64_t)(intptr_t)c->pos);
        else if(r->hole==HOLE_TAKEN) { if(!taken || !add_fixup(c,site,r->kind,r->addend,taken)) return 0; }
        else if(r->hole==HOLE_IMM) patch(site,r->kind,r->addend,(int64_t)immediate);
        else if(r->hole==HOLE_IMM2) patch(site,r->kind,r->addend,(int64_t)(immediate>>32));
        else if(r->hole==HOLE_FINAL || r->hole==HOLE_ERROR) patch(site,r->kind,r->addend,(int64_t)immediate);
        else patch(site,r->kind,r->addend,0);
    }
    return 1;
}
static uint64_t lazy_dispatch(uint64_t state);
static int place_lazy_entry(Compiler *c,Version *v) {
    const Stencil *s=&stencils[ABC_STENCIL_LAZY_ENTRY];c->placements++;if((size_t)(c->stub_pos-c->pos)<s->len){c->status=abc_fail(c->error,ABC_NOMEM,v->pc,"lazy entry-stub region exhausted");return 0;}
    c->stub_pos-=s->len;c->end=c->stub_pos;v->address=c->stub_pos;uint8_t *at=v->address;memcpy(at,s->code,s->len);
    for(unsigned i=0;i<s->nrel;i++){const Reloc *r=&s->rel[i];uint8_t *site=at+r->off;if(r->hole==HOLE_STATE)patch(site,r->kind,r->addend,(int64_t)(intptr_t)v);
        else if(r->hole==HOLE_FINAL){patch(site,r->kind,r->addend,(int64_t)(intptr_t)lazy_dispatch);v->lazy_site=site;v->lazy_kind=(uint8_t)r->kind;v->lazy_addend=r->addend;}else return 0;}
    return v->lazy_site!=NULL;
}
static int place_dynamic(Compiler *c,const uint8_t *instruction,uint32_t pc,uint32_t na,uint32_t nb,int32_t nc,int tail,int32_t return_offset){
    const Stencil *s=&stencils[tail?ABC_STENCIL_DYNAMIC_TAIL:ABC_STENCIL_DYNAMIC];c->placements++;if(!reserve(c,s->len))return 0;uint8_t *at=c->pos;memcpy(at,s->code,s->len);c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++){const Reloc *r=&s->rel[i];uint8_t *site=at+r->off;int64_t value;if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)c->pos;else if(r->hole==HOLE_TAKEN&&tail)value=return_offset;else if(r->hole==HOLE_FINAL)value=(int64_t)(intptr_t)vm_dynamic_native;else if(r->hole==HOLE_STATE)value=(int64_t)(intptr_t)instruction;else if(r->hole==HOLE_IMM)value=pc;else if(r->hole==HOLE_BIAS)value=na;else if(r->hole==HOLE_IMM2)value=nb;else if(r->hole==HOLE_ERROR)value=nc;else return 0;patch(site,r->kind,r->addend,value);}return 1;
}
static int place_managed_write(Compiler *c,unsigned reg,uint32_t offset,uint32_t bytes){
    const Stencil *s=&stencils[ABC_STENCIL_MANAGED_WRITE(reg)];c->placements++;if(!reserve(c,s->len))return 0;uint8_t *at=c->pos;memcpy(at,s->code,s->len);c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++){const Reloc *r=&s->rel[i];uint8_t *site=at+r->off;int64_t value;if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)c->pos;else if(r->hole==HOLE_FINAL)value=(int64_t)(intptr_t)vm_dynamic_write_native;else if(r->hole==HOLE_IMM)value=offset;else if(r->hole==HOLE_IMM2)value=bytes;else return 0;patch(site,r->kind,r->addend,value);}return 1;
}
static int place_fcall(Compiler *c,unsigned id,uint32_t abase,const abc_extern *ext,abc_foreign_address target,uint64_t error) {
    const Stencil *s=&stencils[id];c->placements++;if(!reserve(c,s->len))return 0;uint8_t *at=c->pos;memcpy(at,s->code,s->len);c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++){const Reloc *r=&s->rel[i];uint8_t *site=at+r->off;int64_t value;
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)c->pos;else if(r->hole==HOLE_IMM)value=abase;
        else if(r->hole==HOLE_FINAL)value=(int64_t)(intptr_t)abc_foreign_select(ext);else if(r->hole==HOLE_STATE)value=(int64_t)(intptr_t)ext;
        else if(r->hole==HOLE_BIAS)value=(int64_t)(intptr_t)target;else if(r->hole==HOLE_ERROR)value=(int64_t)error;else return 0;patch(site,r->kind,r->addend,value);
    }return 1;
}
static int place_biased(Compiler *c,unsigned id,uint64_t immediate,int32_t b_bias,Version *taken) {
    if(id>=sizeof stencils/sizeof stencils[0]) return 0; const Stencil *s=&stencils[id]; c->placements++; if(!reserve(c,s->len)) return 0;
    uint8_t *at=c->pos; memcpy(at,s->code,s->len); c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++) { const Reloc *r=&s->rel[i]; uint8_t *site=at+r->off;
        if(r->hole==HOLE_NEXT) patch(site,r->kind,r->addend,(int64_t)(intptr_t)c->pos);
        else if(r->hole==HOLE_TAKEN) { if(!taken||!add_fixup(c,site,r->kind,r->addend,taken)) return 0; }
        else if(r->hole==HOLE_IMM) patch(site,r->kind,r->addend,(int64_t)immediate);
        else if(r->hole==HOLE_IMM2) patch(site,r->kind,r->addend,(int64_t)(immediate>>32));
        else if(r->hole==HOLE_BIAS) patch(site,r->kind,r->addend,b_bias);
        else return 0;
    }
    return 1;
}
static int place_call_jump(Compiler *c,uint64_t immediate,int32_t b_bias,int32_t return_offset,Version *taken) {
    const Stencil *s=&stencils[ABC_STENCIL_CALL_JUMP]; c->placements++; if(!reserve(c,s->len)) return 0;
    uint8_t *at=c->pos; memcpy(at,s->code,s->len); c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++) { const Reloc *r=&s->rel[i]; uint8_t *site=at+r->off;
        if(r->hole==HOLE_NEXT) patch(site,r->kind,r->addend,(int64_t)(intptr_t)c->pos);
        else if(r->hole==HOLE_TAKEN) { if(!taken||!add_fixup(c,site,r->kind,r->addend,taken)) return 0; }
        else if(r->hole==HOLE_IMM) patch(site,r->kind,r->addend,(int64_t)immediate);
        else if(r->hole==HOLE_IMM2) patch(site,r->kind,r->addend,(int64_t)(immediate>>32));
        else if(r->hole==HOLE_BIAS) patch(site,r->kind,r->addend,b_bias);
        else if(r->hole==HOLE_ERROR) patch(site,r->kind,r->addend,return_offset);
        else return 0;
    }
    return 1;
}
typedef struct { uint8_t *site,*error_site; uint8_t kind,error_kind; int32_t addend,error_addend; } GuardFix;
static int place_guard(Compiler *c,unsigned stack,uint32_t cells,uint64_t error,GuardFix *fix) {
    const Stencil *s=&stencils[ABC_STENCIL_GUARD(stack)]; c->placements++; if(!reserve(c,s->len)) return 0;
    uint8_t *at=c->pos; memcpy(at,s->code,s->len); c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++) { const Reloc *r=&s->rel[i]; uint8_t *site=at+r->off; int64_t value;
        if(r->hole==HOLE_NEXT) value=(int64_t)(intptr_t)c->pos;
        else if(r->hole==HOLE_IMM) { value=cells; if(fix) { fix->site=site; fix->kind=(uint8_t)r->kind; fix->addend=r->addend; } }
        else if(r->hole==HOLE_FINAL) value=(int64_t)(intptr_t)c->stack_end[stack];
        else if(r->hole==HOLE_ERROR) { value=(int64_t)error; if(fix) { fix->error_site=site; fix->error_kind=(uint8_t)r->kind; fix->error_addend=r->addend; } }
        else return 0;
        patch(site,r->kind,r->addend,value);
    }
    return 1;
}
static int ensure_capacity(Compiler *c,Context *x,unsigned stack,uint32_t cells,uint64_t error) {
    if(cells<=x->limit[stack]) return 1;
    if(!place_guard(c,stack,cells,error,NULL)) return 0; x->limit[stack]=cells; return 1;
}
static int ic_rewrite(abc_ic_state *s,NativeFn helper) {
    abc_native_image *image=s->owner;
    if(mprotect(image->code,image->mapping_size,PROT_READ|PROT_WRITE)) return 0;
    for(size_t i=0;i<s->npatch;i++) patch(s->patches[i].site,s->patches[i].kind,s->patches[i].addend,(int64_t)(intptr_t)helper);
    __builtin___clear_cache((char *)image->code,(char *)image->code+image->code_size);
    return !mprotect(image->code,image->mapping_size,PROT_READ|PROT_EXEC);
}
static NativeFn ic_validate(abc_ic_state *s,uint64_t target,uint64_t *status,const abc_function **callee) {
    for(uint32_t i=0;i<s->owner->entry_count;i++) if(target==i ||
        target==s->module->functions[i].entry ||
        (uint64_t)(uintptr_t)s->owner->entries[i]==target ||
        (uint64_t)(uintptr_t)(s->module->code+s->module->functions[i].entry)==target) {
        const abc_function *f=&s->module->functions[i];
        if(f->has_halt) { *status=ABC_INVALID; return NULL; }
        if(!abc_same_signature(s->signature,f)) { *status=ABC_ARGUMENTS; return NULL; }
        *callee=f; *status=ABC_OK; return (NativeFn)s->owner->entries[i];
    }
    *status=ABC_INVALID; return NULL;
}
static uint64_t resolve_raw_target(uint64_t target,uint64_t state) {
    uint64_t status=ABC_INVALID;const abc_function *callee=NULL;
    NativeFn entry=ic_validate((abc_ic_state *)(uintptr_t)state,target,&status,&callee);
    return (uint64_t)(uintptr_t)entry;
}
static NativeFn ic_select(abc_ic_state *s,uint64_t target,unsigned expected_phase,uint64_t *status,const abc_function **callee) {
    if(expected_phase==1 && target!=(uint64_t)(uintptr_t)s->observed) {
        NativeFn final=s->tail?ic_final_tail:ic_final_call;
        if(!ic_rewrite(s,final)) { *status=ABC_IO; return NULL; }
        s->phase=2; s->owner->transitions++;
    }
    NativeFn fn=ic_validate(s,target,status,callee); if(!fn) return NULL;
    if(expected_phase==0) {
        s->observed=(void *)(uintptr_t)target; NativeFn specific=s->tail?ic_specific_tail:ic_specific_call;
        if(!ic_rewrite(s,specific)) { *status=ABC_IO; return NULL; }
        s->phase=1; s->owner->transitions++;
    }
    return fn;
}
static int ic_capacity(const abc_ic_state *s,const abc_function *f,const uint64_t *asp,const uint64_t *bsp,const uint64_t *csp) {
    uintptr_t a=(uintptr_t)asp,b=(uintptr_t)bsp,c=(uintptr_t)csp;
    uintptr_t ae=(uintptr_t)s->owner->stack_end[JS_A],be=(uintptr_t)s->owner->stack_end[JS_B],ce=(uintptr_t)s->owner->stack_end[JS_C];
    return a<=ae && b<=be && c<=ce && f->max_a<=(ae-a)/sizeof(uint64_t) && f->max_b<=(be-b)/sizeof(uint64_t) &&
        f->max_c-f->arguments<=(ce-c)/sizeof(uint64_t);
}
#define IC_ARGS uint64_t *asp,uint64_t *bsp,uint64_t *csp,uint64_t target,uint64_t state,uint64_t h2,uint64_t h3,uint64_t h4,uint64_t h5,uint64_t h6,uint64_t h7
#define IC_UNUSED (void)h2;(void)h3;(void)h4;(void)h5;(void)h6;(void)h7
#define IC_ERROR(S,E) ((E)|((uint64_t)(S)->signature->entry<<16))
static __attribute__((preserve_none)) uint64_t ic_observe_call(IC_ARGS) { IC_UNUSED; abc_ic_state *s=(abc_ic_state *)(uintptr_t)state; uint64_t status; const abc_function *f=NULL; NativeFn fn=ic_select(s,target,0,&status,&f); if(fn&&!ic_capacity(s,f,asp,bsp,csp))return IC_ERROR(s,ABC_STACK); return fn?fn(asp,bsp,csp,0,0,0,0,0,0,0,0):IC_ERROR(s,status); }
static __attribute__((preserve_none)) uint64_t ic_specific_call(IC_ARGS) { IC_UNUSED; abc_ic_state *s=(abc_ic_state *)(uintptr_t)state; uint64_t status; const abc_function *f=NULL; NativeFn fn=ic_select(s,target,1,&status,&f); if(fn&&!ic_capacity(s,f,asp,bsp,csp))return IC_ERROR(s,ABC_STACK); return fn?fn(asp,bsp,csp,0,0,0,0,0,0,0,0):IC_ERROR(s,status); }
static __attribute__((preserve_none)) uint64_t ic_final_call(IC_ARGS) { IC_UNUSED; abc_ic_state *s=(abc_ic_state *)(uintptr_t)state; uint64_t status; const abc_function *f=NULL; NativeFn fn=ic_validate(s,target,&status,&f); if(fn&&!ic_capacity(s,f,asp,bsp,csp))return IC_ERROR(s,ABC_STACK); return fn?fn(asp,bsp,csp,0,0,0,0,0,0,0,0):IC_ERROR(s,status); }
static __attribute__((preserve_none)) uint64_t ic_observe_tail(IC_ARGS) { IC_UNUSED; uint64_t *volatile a=asp,*volatile b=bsp,*volatile c=csp; abc_ic_state *s=(abc_ic_state *)(uintptr_t)state; uint64_t status; const abc_function *f=NULL; NativeFn fn=ic_select(s,target,0,&status,&f); if(!fn)return IC_ERROR(s,status); if(!ic_capacity(s,f,a,b,c))return IC_ERROR(s,ABC_STACK); __attribute__((musttail)) return fn(a,b,c,0,0,0,0,0,0,0,0); }
static __attribute__((preserve_none)) uint64_t ic_specific_tail(IC_ARGS) { IC_UNUSED; uint64_t *volatile a=asp,*volatile b=bsp,*volatile c=csp; abc_ic_state *s=(abc_ic_state *)(uintptr_t)state; uint64_t status; const abc_function *f=NULL; NativeFn fn=ic_select(s,target,1,&status,&f); if(!fn)return IC_ERROR(s,status); if(!ic_capacity(s,f,a,b,c))return IC_ERROR(s,ABC_STACK); __attribute__((musttail)) return fn(a,b,c,0,0,0,0,0,0,0,0); }
static __attribute__((preserve_none)) uint64_t ic_final_tail(IC_ARGS) { IC_UNUSED; uint64_t *volatile a=asp,*volatile b=bsp,*volatile c=csp; abc_ic_state *s=(abc_ic_state *)(uintptr_t)state; uint64_t status; const abc_function *f=NULL; NativeFn fn=ic_validate(s,target,&status,&f); if(!fn)return IC_ERROR(s,status); if(!ic_capacity(s,f,a,b,c))return IC_ERROR(s,ABC_STACK); __attribute__((musttail)) return fn(a,b,c,0,0,0,0,0,0,0,0); }
#undef IC_ERROR
#undef IC_UNUSED
#undef IC_ARGS
static int place_ic(Compiler *c,unsigned id,uint64_t immediate,int32_t b_bias,abc_ic_state *state,NativeFn helper) {
    if(id>=sizeof stencils/sizeof stencils[0]) return 0; const Stencil *s=&stencils[id]; c->placements++; if(!reserve(c,s->len)) return 0;
    uint8_t *at=c->pos; memcpy(at,s->code,s->len); c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++) { const Reloc *r=&s->rel[i]; uint8_t *site=at+r->off;
        if(r->hole==HOLE_NEXT) patch(site,r->kind,r->addend,(int64_t)(intptr_t)c->pos);
        else if(r->hole==HOLE_IMM) patch(site,r->kind,r->addend,(int64_t)immediate);
        else if(r->hole==HOLE_IMM2) patch(site,r->kind,r->addend,(int64_t)(immediate>>32));
        else if(r->hole==HOLE_BIAS) patch(site,r->kind,r->addend,b_bias);
        else if(r->hole==HOLE_STATE) patch(site,r->kind,r->addend,(int64_t)(intptr_t)state);
        else if(r->hole==HOLE_FINAL) {
            patch(site,r->kind,r->addend,(int64_t)(intptr_t)helper);
            if(!grow((void **)&state->patches,&state->patchcap,state->npatch+1,sizeof *state->patches)) return 0;
            state->patches[state->npatch++]=(ICPatch){site,(uint8_t)r->kind,r->addend};
        } else return 0;
    }
    return 1;
}
static int place_raw_indirect(Compiler *c,unsigned id,uint64_t immediate,int32_t b_bias,uint64_t error,abc_ic_state *state) {
    if(id>=sizeof stencils/sizeof stencils[0])return 0;const Stencil *s=&stencils[id];
    c->placements++;if(!reserve(c,s->len))return 0;uint8_t *at=c->pos;memcpy(at,s->code,s->len);c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++){const Reloc *r=&s->rel[i];uint8_t *site=at+r->off;int64_t value;
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)c->pos;
        else if(r->hole==HOLE_IMM)value=(int64_t)(uint32_t)immediate;
        else if(r->hole==HOLE_IMM2)value=(int64_t)(uint32_t)(immediate>>32);
        else if(r->hole==HOLE_BIAS)value=b_bias;
        else if(r->hole==HOLE_FINAL)value=(int64_t)(intptr_t)resolve_raw_target;
        else if(r->hole==HOLE_STATE)value=(int64_t)(intptr_t)state;
        else if(r->hole==HOLE_ERROR)value=(int64_t)error;
        else return 0;patch(site,r->kind,r->addend,value);
    }
    return 1;
}


static int reg_uses(const Context *x,unsigned reg) {
    int n=0; for(unsigned s=0;s<3;s++) for(uint32_t i=0;i<x->n[s];i++) n+=x->s[s][i].kind==VK_REG && x->s[s][i].reg==reg; return n;
}
static int store_id(unsigned stack,unsigned reg) { return ABC_STENCIL_STORE(stack,reg); }
static int load_id(unsigned stack,unsigned reg) { return ABC_STENCIL_LOAD(stack,reg); }
static int spill_reg(Compiler *c,Context *x,unsigned reg) {
    for(unsigned s=0;s<3;s++) for(uint32_t i=0;i<x->n[s];i++) { JValue *v=&x->s[s][i];
        if(v->kind==VK_REG && v->reg==reg) {
            if(!place(c,(unsigned)store_id(v->dst_stack,reg),(uint64_t)((int64_t)v->dst_home*8),NULL)) return 0;
            *v=rehome_value(*v,v->dst_stack,v->dst_home);
        }
    }
    return 1;
}
static int free_reg_mask(Compiler *c,Context *x,unsigned mask) {
    for(unsigned r=0;r<8;r++) if(!(mask&(1u<<r))&&!reg_uses(x,r)) return (int)r;
    for(unsigned r=0;r<8;r++) if(!(mask&(1u<<r))&&spill_reg(c,x,r)) return (int)r;
    return -1;
}
static int free_reg(Compiler *c,Context *x) { return free_reg_mask(c,x,0); }
static int materialize_mask(Compiler *c,Context *x,JValue *v,unsigned mask) {
    if(v->kind==VK_REG) return v->reg; int r=free_reg_mask(c,x,mask); if(r<0) return -1;
    unsigned id=v->kind==VK_CONST ? ABC_STENCIL_CONST(r) : (unsigned)load_id(v->stack,r);
    uint64_t imm=v->kind==VK_CONST ? v->constant : (uint64_t)((int64_t)v->home*8);
    if(!place(c,id,imm,NULL)) return -1; v->kind=VK_REG; v->reg=(uint8_t)r; return r;
}
static int materialize(Compiler *c,Context *x,JValue *v) { return materialize_mask(c,x,v,0); }
static int writable(Compiler *c,Context *x,JValue *v);
static int materialize_dynamic(Compiler *c,Context *x,JValue *v) {
    if(v->dynamic_repr!=ABC_SYM_REPR_RAW)return 1;uint16_t tags=v->dynamic_tags;
    unsigned tag=tags&&!(tags&(uint16_t)(tags-1))?(unsigned)__builtin_ctz((unsigned)tags):UINT_MAX;
    int supported=abc_numeric_integer(tag)&&v->dynamic_width==abc_numeric_width(tag);
    if(!supported){if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_INVALID,c->current_pc,"cannot materialize specialized dynamic representation");return 0;}
    int reg=writable(c,x,v);if(reg<0||!place(c,ABC_STENCIL_DYNAMIC_ENCODE(reg),(uint64_t)__builtin_ctz((unsigned)tags),NULL))return 0;
    v->kind=VK_REG;v->reg=(uint32_t)reg;v->dynamic_repr=ABC_SYM_REPR_ENCODED;return 1;
}
static int writable(Compiler *c,Context *x,JValue *v) {
    int r=materialize(c,x,v); if(r<0 || reg_uses(x,(unsigned)r)==1) return r;
    int d=free_reg_mask(c,x,1u<<(unsigned)r); if(d<0 || !place(c,ABC_STENCIL_MOV(d,r),0,NULL)) return -1;
    v->reg=(uint8_t)d; return d;
}
static int save_value(Compiler *c,Context *x,JValue *v) {
    if(v->kind==VK_HOME && v->stack==v->dst_stack && v->home==v->dst_home) return 1;
    int r=materialize(c,x,v); if(r<0) return 0;
    return place(c,(unsigned)store_id(v->dst_stack,(unsigned)r),(uint64_t)((int64_t)v->dst_home*8),NULL);
}
static int flush_context(Compiler *c,Context *x) {
    for(int s=2;s>=0;s--) for(uint32_t i=0;i<x->n[s];i++) { JValue *v=&x->s[s][i];
        if(v->kind!=VK_CONST||v->dynamic_repr==ABC_SYM_REPR_RAW) { if(!materialize_dynamic(c,x,v)||!save_value(c,x,v)) return 0; *v=rehome_value(*v,v->dst_stack,v->dst_home); }
    }
    return 1;
}
static int conform_context(Compiler *c,Context *x,int forget) {
    for(int s=2;s>=0;s--) for(uint32_t i=0;i<x->n[s];i++) { JValue *v=&x->s[s][i];
        int32_t home=s==JS_C?x->c_bias+(int32_t)i-x->c_origin:(int32_t)i;
        v->dst_stack=(uint8_t)s; v->dst_home=home;
        if(!materialize_dynamic(c,x,v)||!save_value(c,x,v)) return 0;
        if(forget)abc_symbolic_forget_dynamic(v); *v=rehome_value(*v,s,home);
    }
    memset(x->limit,0,sizeof x->limit); x->generic=(uint8_t)forget; return 1;
}

static int conform_generic(Compiler *c,Context *x) { return conform_context(c,x,1); }

static int binary_index(unsigned op) {
    static const int map[]={ABC_JOP_ADD,ABC_JOP_SUB,ABC_JOP_MUL,ABC_JOP_DIVU,ABC_JOP_DIVS,ABC_JOP_REMU,ABC_JOP_REMS,ABC_JOP_AND,ABC_JOP_OR,ABC_JOP_XOR,ABC_JOP_SHL,ABC_JOP_SHR,ABC_JOP_SAR,ABC_JOP_EQ,ABC_JOP_NE,ABC_JOP_LT,ABC_JOP_LE,ABC_JOP_LTU,ABC_JOP_LEU};
    unsigned pair=(op-OP_ADD_A)/2; return pair<sizeof map/sizeof map[0]?map[pair]:-1;
}
static int binary32_index(int op) {
    switch(op) { case ABC_JOP_ADD:return ABC_J32_ADD; case ABC_JOP_SUB:return ABC_J32_SUB; case ABC_JOP_MUL:return ABC_J32_MUL;
    case ABC_JOP_AND:return ABC_J32_AND; case ABC_JOP_OR:return ABC_J32_OR; case ABC_JOP_XOR:return ABC_J32_XOR; default:return -1; }
}
static int follows_zx32(const Compiler *c,uint32_t pc,unsigned stack) {
    return pc<c->module->code_size && !c->block[pc] && c->module->code[pc]==(stack==JS_B?OP_ZX32_B:OP_ZX32_A);
}

typedef struct { Compiler *compiler; abc_symbolic_machine *machine; } NativeSymbolicSink;
static int native_emit_binary(void *opaque,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        JValue left,JValue right,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; int bi=binary_index(opcode),b32=binary32_index(bi);
    uint32_t next=origin+op_len[c->module->code[origin]];
    int u32=follows_zx32(c,next,destination)&&b32>=0&&!(destination==JS_B&&bi==ABC_JOP_SUB);
    if(folded) {
        if(u32) { result->constant=(uint32_t)result->constant; sink->machine->extra_advance=op_len[c->module->code[next]]; }
        return 1;
    }
    JValue *dst=top(x,destination,0),*other=top(x,destination==JS_A?JS_B:JS_A,0);
    int rd=writable(c,x,dst);
    if(rd<0) goto failed;
    int rs=materialize_mask(c,x,other,1u<<(unsigned)rd);
    if(rs<0) goto failed;
    uint64_t op_error=(bi>=ABC_JOP_DIVU&&bi<=ABC_JOP_REMS)?
        (uint64_t)ABC_ABORT|(UINT64_C(1)<<8)|((uint64_t)origin<<16):0;
    unsigned stencil=u32?(destination==JS_B?ABC_STENCIL_BINARY32_REV(b32,rd,rs):ABC_STENCIL_BINARY32(b32,rd,rs)):
        (destination==JS_B?ABC_STENCIL_BINARY_REV(bi,rd,rs):ABC_STENCIL_BINARY(bi,rd,rs));
    if(!place(c,stencil,op_error,NULL)) goto failed;
    *result=*dst; result->kind=VK_REG; result->reg=(uint32_t)rd;
    if(u32)sink->machine->extra_advance=op_len[c->module->code[next]];
    (void)left; (void)right; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int unary_index(unsigned op);
static int native_emit_unary(void *opaque,uint32_t origin,unsigned opcode,unsigned stack,int folded,
        JValue input,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; int ui=unary_index(opcode); JValue *value=top(x,stack,0); int reg=writable(c,x,value);
    if(ui<0||reg<0||!place(c,ABC_STENCIL_UNARY(ui,reg),0,NULL)) {
        if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
        return 0;
    }
    *result=*value; result->kind=VK_REG; result->reg=(uint32_t)reg;
    (void)folded; (void)input; return 1;
}
static int native_emit_float_binary(void *opaque,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        JValue left,JValue right,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; if(folded)return 1;
    unsigned fi=(opcode-OP_FADD_A)/2; JValue *dst=top(x,destination,0);
    JValue *other=top(x,destination==JS_A?JS_B:JS_A,0); int rd=writable(c,x,dst);
    if(rd<0)goto failed; int rs=materialize_mask(c,x,other,1u<<(unsigned)rd);
    if(rs<0||!place(c,destination==JS_B?ABC_STENCIL_FLOAT_BINARY_REV(fi,rd,rs):ABC_STENCIL_FLOAT_BINARY(fi,rd,rs),0,NULL))goto failed;
    *result=*dst; result->kind=VK_REG; result->reg=(uint32_t)rd;
    (void)left; (void)right; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int native_emit_float_unary(void *opaque,uint32_t origin,unsigned opcode,int folded,int trapped,
        JValue input,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; uint64_t error=(uint64_t)ABC_ABORT|(UINT64_C(3)<<8)|((uint64_t)origin<<16);
    if(trapped)return place(c,ABC_STENCIL_ABORT,error,NULL);
    if(folded)return 1;
    JValue *value=top(x,JS_A,0); int reg=writable(c,x,value); unsigned fi=opcode-OP_FNEG;
    if(reg<0||!place(c,ABC_STENCIL_FLOAT_UNARY(fi,reg),(opcode==OP_F2IS||opcode==OP_F2IU)?error:0,NULL))goto failed;
    *result=*value; result->kind=VK_REG; result->reg=(uint32_t)reg;
    (void)input; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int native_emit_pow(void *opaque,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        JValue left,JValue right,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; if(folded)return 1; JValue *lhs=top(x,JS_A,0),*rhs=top(x,JS_B,0);
    int ra=writable(c,x,lhs); if(ra<0)goto failed; int rb=materialize_mask(c,x,rhs,1u<<(unsigned)ra);
    uint64_t error=(uint64_t)ABC_ABORT|(UINT64_C(4)<<8)|((uint64_t)origin<<16);
    if(rb<0||!place(c,opcode==OP_POW?ABC_STENCIL_POW(ra,rb):ABC_STENCIL_POWS(ra,rb),error,NULL))goto failed;
    *result=*lhs; result->kind=VK_REG; result->reg=(uint32_t)ra;
    (void)destination; (void)left; (void)right; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int native_emit_check(void *opaque,uint32_t origin,unsigned opcode,int known,int trapped,JValue input) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; uint64_t error=(uint64_t)ABC_ABORT|(UINT64_C(3)<<8)|((uint64_t)origin<<16);
    if(trapped)return place(c,ABC_STENCIL_ABORT,error,NULL);
    if(known)return 1; JValue *value=top(x,JS_A,0); int reg=materialize(c,x,value);
    if(reg>=0&&place(c,ABC_STENCIL_CHECK(opcode-OP_CHKU8,reg),error,NULL))return 1;
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    (void)input; return 0;
}
static int unary_index(unsigned op) {
    static const int map[]={ABC_JUN_NEG,ABC_JUN_NOT,ABC_JUN_LNOT,ABC_JUN_ZX32,ABC_JUN_SX32};
    unsigned pair=(op-OP_NEG_A)/2; return pair<5?map[pair]:-1;
}
static int immediate_index(unsigned op) {
    unsigned pair=(op-OP_ADDI_A)/2; return pair<=ABC_JIMM_SAR?(int)pair:-1;
}
static int native_emit_immediate(void *opaque,uint32_t origin,unsigned opcode,unsigned stack,uint64_t immediate,
        int folded,JValue input,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; int ii=immediate_index(opcode); JValue *value=top(x,stack,0); int reg=writable(c,x,value);
    uint32_t next=origin+op_len[c->module->code[origin]]; int u32=follows_zx32(c,next,stack);
    if(ii<0||reg<0)goto failed; unsigned stencil; uint64_t patched=immediate;
    if(ii>=ABC_JIMM_SHL&&immediate>=(uint64_t)(u32?32:64)) {
        if(ii==ABC_JIMM_SAR) { stencil=u32?ABC_STENCIL_IMMEDIATE32(ii,reg):ABC_STENCIL_IMMEDIATE(ii,reg); patched=u32?31:63; }
        else { stencil=ABC_STENCIL_CONST(reg); patched=0; }
    } else stencil=u32?ABC_STENCIL_IMMEDIATE32(ii,reg):ABC_STENCIL_IMMEDIATE(ii,reg);
    if(!place(c,stencil,patched,NULL))goto failed;
    *result=*value; result->kind=VK_REG; result->reg=(uint32_t)reg;
    if(u32)sink->machine->extra_advance=op_len[c->module->code[next]];
    (void)folded; (void)input; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int native_emit_c_operand(void *opaque,uint32_t origin,unsigned opcode,unsigned stack,int folded,
        JValue left,JValue right,JValue *result) {
    static const int opc[]={ABC_JOP_ADD,ABC_JOP_SUB,ABC_JOP_MUL,ABC_JOP_XOR};
    static const int opc32[]={ABC_J32_ADD,ABC_J32_SUB,ABC_J32_MUL,ABC_J32_XOR};
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; unsigned which=(opcode-OP_ADDC_A)/2,depth=c->module->code[origin+1];
    JValue *value=top(x,stack,0),*rhs=top(x,JS_C,depth); int rd=writable(c,x,value);
    if(rd<0)goto failed; int rs=materialize_mask(c,x,rhs,1u<<(unsigned)rd);
    uint32_t next=origin+op_len[c->module->code[origin]]; int u32=follows_zx32(c,next,stack);
    unsigned stencil=u32?ABC_STENCIL_BINARY32(opc32[which],rd,rs):ABC_STENCIL_BINARY(opc[which],rd,rs);
    if(which>=4||rs<0||!place(c,stencil,0,NULL))goto failed;
    *result=*value; result->kind=VK_REG; result->reg=(uint32_t)rd;
    if(u32)sink->machine->extra_advance=op_len[c->module->code[next]];
    (void)folded; (void)left; (void)right; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int load_kind(abc_memory_op op) {
    if(op.width==1)return 0; if(op.width==2)return 1; if(op.width==4)return op.sign?3:2; return op.width==8?4:-1;
}
static int store_kind(unsigned width) { return width==1?0:width==2?1:width==4?2:width==8?3:-1; }
static int native_emit_memory(void *opaque,uint32_t origin,abc_symbolic_memory *memory) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;
    unsigned opcode=memory->opcode;const uint8_t *p=c->module->code+origin;abc_memory_op mo=op_memory[opcode];c->current_pc=origin;
    if(mo.action==M_ALLOC) {
        unsigned cells=memory->cells;int32_t start=x->c_bias+(int32_t)x->n[JS_C]-x->c_origin;
        uint64_t packed=(uint32_t)cells|((uint64_t)(uint32_t)start<<32);
        if(cells&&(!ensure_capacity(c,x,JS_C,(uint32_t)(start+(int32_t)cells),(uint64_t)ABC_STACK|((uint64_t)origin<<16))||!place(c,ABC_STENCIL_CALLOC,packed,NULL)))goto failed;
    } else if(mo.action==M_FREE) {
        /* The generated transfer owns the C-stack contraction. */
    } else if(mo.action==M_FLOAD) {
        unsigned s=memory->stack;int r=free_reg(c,x),lk=load_kind(mo);
        int32_t off=(x->c_bias+(int32_t)x->n[JS_C]-x->c_origin)*8-(int32_t)abc_u16(p+1);
        if(r<0||lk<0||!place(c,ABC_STENCIL_FRAME_LOAD(lk,r),(uint64_t)(int64_t)off,NULL))goto failed;
        memory->result=reg_value((unsigned)r,s,(int32_t)x->n[s]);
    } else if(mo.action==M_FSTORE) {
        if(!materialize_dynamic(c,x,&memory->first))goto failed;int r=materialize(c,x,&memory->first),sk=store_kind(mo.width);
        int32_t off=(x->c_bias+(int32_t)x->n[JS_C]-x->c_origin)*8-(int32_t)abc_u16(p+1);
        if(r<0||sk<0||!place(c,ABC_STENCIL_FRAME_STORE(sk,r),(uint64_t)(int64_t)off,NULL))goto failed;
    } else if(mo.action==M_FADDR) {
        unsigned s=memory->stack;int r=free_reg(c,x);int32_t off=(x->c_bias+(int32_t)x->n[JS_C]-x->c_origin)*8-(int32_t)abc_u16(p+1);
        if(r<0||!place(c,ABC_STENCIL_FRAME_ADDR(r),(uint64_t)(int64_t)off,NULL))goto failed;memory->result=reg_value((unsigned)r,s,(int32_t)x->n[s]);
    } else if(mo.action==M_GLOAD) {
        unsigned s=memory->stack;int r=free_reg(c,x),lk=load_kind(mo);uint64_t address=(uint64_t)(uintptr_t)c->image_base+abc_u32(p+1);
        if(!c->image_base||r<0||lk<0||!place(c,ABC_STENCIL_GLOBAL_LOAD(lk,r),address,NULL))goto failed;memory->result=reg_value((unsigned)r,s,(int32_t)x->n[s]);
    } else if(mo.action==M_GSTORE) {
        if(!materialize_dynamic(c,x,&memory->first))goto failed;int r=materialize(c,x,&memory->first),sk=store_kind(mo.width);uint64_t address=(uint64_t)(uintptr_t)c->image_base+abc_u32(p+1);
        if(!c->image_base||r<0||sk<0||!place(c,ABC_STENCIL_GLOBAL_STORE(sk,r),address,NULL))goto failed;
    } else if(mo.action==M_GADDR) {
        unsigned s=memory->stack;int r=free_reg(c,x);uint64_t address=(uint64_t)(uintptr_t)c->image_base+abc_u32(p+1);
        if(!c->image_base||r<0||!place(c,ABC_STENCIL_GLOBAL_ADDR(r),address,NULL))goto failed;memory->result=reg_value((unsigned)r,s,(int32_t)x->n[s]);
    } else if(mo.action==M_PLOAD) {
        JValue value=memory->first;int r=writable(c,x,top(x,memory->stack,0)),lk=load_kind(mo);
        if(r<0||lk<0||!place(c,ABC_STENCIL_MEM_LOAD(lk,r),abc_u16(p+1),NULL))goto failed;value.kind=VK_REG;value.reg=(uint32_t)r;memory->result=value;
    } else if(mo.action==M_PSTORE) {
        JValue address=memory->first,value=memory->second;if(!materialize_dynamic(c,x,&value))goto failed;int ra=materialize(c,x,&address);if(ra<0)goto failed;
        int rv=materialize_mask(c,x,&value,1u<<(unsigned)ra),sk=store_kind(mo.width);
        if(rv<0||sk<0||!place(c,ABC_STENCIL_MEM_STORE(sk,ra,rv),abc_u16(p+1),NULL)||(c->module->dynamic_profile&&!place_managed_write(c,(unsigned)ra,abc_u16(p+1),mo.width)))goto failed;
    } else if(mo.action==M_XLOAD||mo.action==M_INDEX) {
        JValue address=memory->first,index=memory->second;int ra=writable(c,x,top(x,JS_A,0));if(ra<0)goto failed;
        int ri=materialize_mask(c,x,&index,1u<<(unsigned)ra);if(ri<0||!place(c,ABC_STENCIL_INDEX(ra,ri),mo.action==M_INDEX?abc_u16(p+1):mo.width,NULL))goto failed;
        if(mo.action==M_XLOAD){int lk=load_kind(mo);if(lk<0||!place(c,ABC_STENCIL_MEM_LOAD(lk,ra),0,NULL))goto failed;}
        address.kind=VK_REG;address.reg=(uint32_t)ra;memory->result=address;
    } else if(mo.action==M_COPY) {
        JValue dst=memory->first,src=memory->second;int rd=materialize(c,x,&dst);if(rd<0)goto failed;
        int rs=materialize_mask(c,x,&src,1u<<(unsigned)rd);uint32_t bytes=abc_u16(p+1);
        if(rs<0||!place(c,ABC_STENCIL_MEMCPY(rd,rs),bytes,NULL)||(c->module->dynamic_profile&&bytes&&!place_managed_write(c,(unsigned)rd,0,bytes)))goto failed;
    } else goto failed;
    return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native memory sink emission failed");
    return 0;
}
static int containing_function(const abc_module *m,uint32_t pc) {
    for(uint32_t i=0;i<m->function_count;i++) if(pc>=m->functions[i].entry&&pc<m->functions[i].end) return (int)i;
    return -1;
}



static int inline_candidate(Compiler *c,const Context *x,uint32_t caller_pc,uint32_t target,const VCont *frame) {
    int fi=abc_find_function(c->module,target), current=containing_function(c->module,caller_pc);
    if(fi<0 || c->recursive[fi]) return 0;
    if(current==fi) return 0;
    for(uint32_t i=0;i<x->ncont;i++) if(x->cont[i].target==target) return 0;
    for(Version *v=c->versions[target];v;v=v->next) {
        if(v->in.ncont!=x->ncont+1)continue;unsigned i=0;for(;i<x->ncont;i++)if(!vcont_equal(&v->in.cont[i],&x->cont[i]))break;
        if(i==x->ncont&&vcont_equal(&v->in.cont[i],frame))return 1;
    }
    unsigned continuations=0;
    for(Version *v=c->versions[target];v;v=v->next) { int first=1; for(Version *u=c->versions[target];u!=v;u=u->next)if(continuation_equal(&u->in,&v->in)){first=0;break;} continuations+=(unsigned)first; }
    return continuations<ABC_BLOCK_VERSION_LIMIT;
}
static Version *version_for(Compiler *c,uint32_t pc,const Context *in) {
    unsigned count=0; for(Version *v=c->versions[pc];v;v=v->next) {
        if(generic_context_equal(&v->in,in)) return v;
        if(context_equal(&v->in,in)) { int accepts=1; for(unsigned s=0;s<3;s++) accepts&=in->limit[s]>=v->in.limit[s]; if(accepts) return v; }
        if(context_family_equal(&v->in,in)) count++;
    }
    if(count>=ABC_BLOCK_VERSION_LIMIT) { c->status=abc_fail(c->error,ABC_INVALID,pc,"compiled block version limit reached without compatible generic context"); return NULL; }
    Version *v=calloc(1,sizeof *v); if(!v || !context_copy(&v->in,in)) { free(v); c->status=abc_fail(c->error,ABC_NOMEM,pc,"block version allocation failed"); return NULL; }
    v->pc=pc;v->owner=c;
    if(c->lazy&&!place_lazy_entry(c,v)){context_free(&v->in);free(v);if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,pc,"lazy entry-stub allocation failed");return NULL;}
    v->next=c->versions[pc]; c->versions[pc]=v;
    if(!c->lazy){if(!grow((void **)&c->queue,&c->qcap,c->nq+1,sizeof *c->queue)) { c->status=abc_fail(c->error,ABC_NOMEM,pc,"compiler queue allocation failed"); return NULL; }c->queue[c->nq++]=v;} return v;
}
static Version *edge(Compiler *c,uint32_t from,uint32_t target,Context *x) {
    if(target<=from) for(unsigned s=0;s<3;s++) for(uint32_t i=0;i<x->n[s];i++) {
        JValue *v=&x->s[s][i]; if(v->kind==VK_CONST) { if(materialize(c,x,v)<0 || !save_value(c,x,v)) return NULL; *v=rehome_value(*v,v->dst_stack,v->dst_home); }
    }
    unsigned versions=0; for(Version *v=c->versions[target];v;v=v->next) versions+=context_family_equal(&v->in,x);
    if(versions>=ABC_BLOCK_VERSION_LIMIT-1 && !conform_generic(c,x)) return NULL;
    return version_for(c,target,x);
}

static int discover_blocks(Compiler *c) {
    const abc_module *m=c->module;
    for(uint32_t f=0;f<m->function_count;f++) c->block[m->functions[f].entry]=1;
    for(uint32_t f=0;f<m->function_count;f++) for(uint32_t pc=m->functions[f].entry;pc<m->functions[f].end;) {
        unsigned op=m->code[pc], kind=op_kind[op]; uint32_t next=pc+abc_instruction_length(m->code+pc);
        if(kind==K_BRANCH || kind==K_BRI || kind==K_JMP32) { uint32_t target=(uint32_t)((int64_t)next+(kind==K_JMP32?abc_i32(m->code+pc+1):abc_i16(m->code+pc+(kind==K_BRI?2:1)))); c->block[target]=1; if(op!=OP_JMP&&op!=OP_JMP32) c->block[next]=1; }
        else if(kind==K_SWITCH){for(unsigned j=0;j<abc_u16(m->code+pc+1);j++)c->block[(uint32_t)((int64_t)next+abc_i32(m->code+pc+3+4*j))]=1;c->block[next]=1;}
        if(kind==K_CALL && next<m->functions[f].end) c->block[next]=1; pc=next;
    }
    return 1;
}
static int compile_version(Compiler *c,Version *v);
static __attribute__((noinline)) uint64_t lazy_prepare(Version *v){
    Compiler *c=v->owner;abc_error local,*e=abc_active_run&&abc_active_run->e?abc_active_run->e:&local;c->error=e;c->status=ABC_OK;c->current_pc=v->pc;
    if(mprotect(c->base,c->mapping_size,PROT_READ|PROT_WRITE))c->status=abc_fail(e,ABC_IO,v->pc,"cannot make lazy code writable");
    else if(!compile_version(c,v)&&c->status==ABC_OK)c->status=abc_fail(e,ABC_INVALID,v->pc,"lazy block compilation failed");
    if(c->status==ABC_OK)for(size_t i=0;i<c->nfix;i++){Fixup *f=&c->fixups[i];if(!f->target->address){c->status=abc_fail(e,ABC_INVALID,f->target->pc,"lazy edge target has no stable stub");break;}patch(f->site,f->kind,f->addend,(int64_t)(intptr_t)f->target->address);}
    if(c->status==ABC_OK){const Stencil *jump=&stencils[ABC_STENCIL_JUMP];memcpy(v->address,jump->code,jump->len);for(unsigned i=0;i<jump->nrel;i++){const Reloc *r=&jump->rel[i];if(r->hole!=HOLE_TAKEN){c->status=abc_fail(e,ABC_INVALID,v->pc,"invalid lazy activation stencil");break;}patch(v->address+r->off,r->kind,r->addend,(int64_t)(intptr_t)v->body);}c->image->compiled_versions++;c->image->code_size=(size_t)(c->pos-c->base);c->image->virtual_calls=c->virtual_calls;c->image->virtual_returns=c->virtual_returns;c->image->virtual_tails=c->virtual_tails;c->image->real_calls=c->real_calls;}
    __builtin___clear_cache((char *)c->base,(char *)c->base+c->mapping_size);if(mprotect(c->base,c->mapping_size,PROT_READ|PROT_EXEC)&&c->status==ABC_OK)c->status=abc_fail(e,ABC_IO,v->pc,"cannot protect lazy code");
    v->saved[11]=c->status==ABC_OK?0:(uint64_t)c->status|((uint64_t)v->pc<<16);return (uint64_t)(uintptr_t)v->body;
}
static uint64_t lazy_dispatch(uint64_t state){Version *v=(Version *)(uintptr_t)state;v->saved[11]=0;return v->compiled?(uint64_t)(uintptr_t)v->body:lazy_prepare(v);}
static int emit_jump(Compiler *c,Version *target) { return target && place(c,ABC_STENCIL_JUMP,0,target); }

static int local_branch(Compiler *c,unsigned stencil,Fixup *fix);
static void bind_local(Compiler *c,const Fixup *fix);
static int edge_emits_code(const Compiler *c,uint32_t from,uint32_t target,const Context *x) {
    if(target<=from)for(unsigned s=0;s<3;s++)for(uint32_t i=0;i<x->n[s];i++)if(x->s[s][i].kind==VK_CONST)return 1;
    unsigned versions=0;for(Version *v=c->versions[target];v;v=v->next)versions+=context_family_equal(&v->in,x);
    return versions>=ABC_BLOCK_VERSION_LIMIT-1;
}
/* Publishing registers to distinct canonical homes is safe on either edge:
   it changes neither register bits nor a live home source. Representation
   changes, constants and parallel home copies must wait for the decision. */
static int edge_spills_only(const Context *x) {
    for(unsigned s=0;s<3;s++)for(uint32_t i=0;i<x->n[s];i++){
        const JValue *v=&x->s[s][i];int32_t home=s==JS_C?x->c_bias+(int32_t)i-x->c_origin:(int32_t)i;
        if(v->kind==VK_CONST||v->dynamic_repr==ABC_SYM_REPR_RAW)return 0;
        if(v->kind==VK_HOME&&(v->stack!=s||v->home!=home))return 0;
    }
    return 1;
}
static int native_emit_control(void *opaque,uint32_t origin,const abc_symbolic_control *control) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin;
    if(control->kind==ABC_SYM_CONTROL_SWITCH) {
        if(control->known)return emit_jump(c,edge(c,origin,control->target,x));
        JValue index=control->left; int reg=materialize(c,x,&index); if(reg<0)return 0;
        const uint8_t *p=c->module->code+origin;
        for(unsigned j=0;j<control->count;j++) {
            JValue imm=const_value(j,JS_A,0);int ri=materialize_mask(c,x,&imm,1u<<(unsigned)reg);
            Context taken;if(ri<0||!context_copy(&taken,x))return 0;
            uint32_t target=(uint32_t)((int64_t)control->fallthrough+abc_i32(p+3+4*j));int ok;
            if(edge_emits_code(c,origin,target,x)&&!edge_spills_only(x)){
                Fixup skip;ok=local_branch(c,ABC_STENCIL_BRANCH(ABC_JBR_NE,reg,ri),&skip)&&emit_jump(c,edge(c,origin,target,&taken));
                if(ok)bind_local(c,&skip);
            }else{
                Version *tv=edge(c,origin,target,&taken);ok=tv&&place(c,ABC_STENCIL_BRANCH(ABC_JBR_EQ,reg,ri),0,tv);
            }
            context_free(&taken);if(!ok)return 0;
        }
        return emit_jump(c,edge(c,origin,control->fallthrough,x));
    }
    if(control->kind==ABC_SYM_CONTROL_JUMP||control->known) {
        uint32_t chosen=control->kind==ABC_SYM_CONTROL_JUMP||control->taken?control->target:control->fallthrough;
        return emit_jump(c,edge(c,origin,chosen,x));
    }
    if(control->target==control->fallthrough)return emit_jump(c,edge(c,origin,control->target,x));
    JValue left=control->left,right=control->right; int rl=materialize(c,x,&left),rr=-1;
    if(rl<0)return 0;
    if(control->kind!=ABC_SYM_CONTROL_ZERO) { rr=materialize_mask(c,x,&right,1u<<(unsigned)rl); if(rr<0)return 0; }
    unsigned stencil;
    if(control->kind==ABC_SYM_CONTROL_ZERO)stencil=control->relation==ABC_SYM_EQ?ABC_STENCIL_JZ(rl):ABC_STENCIL_JNZ(rl);
    else if(control->kind==ABC_SYM_CONTROL_FLOAT) {
        unsigned operation=control->relation==ABC_SYM_LT?0:
            control->relation==ABC_SYM_LE?1:
            control->relation==ABC_SYM_EQ?2:UINT_MAX;
        if(operation==UINT_MAX)return 0;
        stencil=ABC_STENCIL_FLOAT_BRANCH(operation,rl,rr);
    }
    else stencil=ABC_STENCIL_BRANCH(control->relation,control->reverse?rr:rl,control->reverse?rl:rr);
    Context taken;if(!context_copy(&taken,x))return 0;
    if((edge_emits_code(c,origin,control->target,x)||edge_emits_code(c,origin,control->fallthrough,x))&&!edge_spills_only(x)){
        Fixup branch;int ok=local_branch(c,stencil,&branch)&&emit_jump(c,edge(c,origin,control->fallthrough,x));
        if(ok){bind_local(c,&branch);ok=emit_jump(c,edge(c,origin,control->target,&taken));}
        context_free(&taken);return ok;
    }
    Version *tv=edge(c,origin,control->target,&taken),*fv=edge(c,origin,control->fallthrough,x);
    context_free(&taken);return tv&&fv&&place(c,stencil,0,tv)&&emit_jump(c,fv);
}
static int native_emit_abort(void *opaque,uint32_t origin,unsigned reason) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; c->current_pc=origin;
    uint64_t error=(uint64_t)ABC_ABORT|((uint64_t)reason<<8)|((uint64_t)origin<<16);
    return place(c,ABC_STENCIL_ABORT,error,NULL);
}
static int native_emit_halt(void *opaque,uint32_t origin,unsigned unused) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin;
    for(uint32_t i=0;i<x->n[JS_A];i++) { JValue *value=&x->s[JS_A][i];
        value->dst_stack=JS_A; value->dst_home=(int32_t)i; if(!materialize_dynamic(c,x,value)||!save_value(c,x,value))return 0; }
    (void)unused; return place(c,ABC_STENCIL_RETURN_OK,0,NULL);
}

/* Proofs refer to current live occurrences, not register identities retained
   across instructions. Capture aliases before canonicalization changes homes. */
typedef struct { uint8_t *bits; size_t offset[3]; } TypeAliases;
static int same_native_value(JValue a,JValue b) {
    if(a.kind!=b.kind||a.dynamic_repr!=b.dynamic_repr||a.dynamic_tags!=b.dynamic_tags||a.dynamic_width!=b.dynamic_width||a.zero_extended!=b.zero_extended)return 0;
    return a.kind==VK_REG?a.reg==b.reg:a.kind==VK_HOME?(a.stack==b.stack&&a.home==b.home):a.constant==b.constant;
}
static int capture_aliases(const Context *x,JValue first,const JValue *second,TypeAliases *aliases) {
    aliases->offset[0]=0;aliases->offset[1]=x->n[JS_A];aliases->offset[2]=(size_t)x->n[JS_A]+x->n[JS_B];
    size_t count=aliases->offset[2]+x->n[JS_C];aliases->bits=calloc(count?count:1,1);if(!aliases->bits)return 0;
    for(unsigned s=0;s<3;s++)for(uint32_t i=0;i<x->n[s];i++)
        aliases->bits[aliases->offset[s]+i]=(uint8_t)(same_native_value(first,x->s[s][i])|(second&&same_native_value(*second,x->s[s][i])?2:0));
    return 1;
}
static void refine_aliases(Context *x,const TypeAliases *aliases,unsigned which,uint16_t allowed) {
    x->generic=0;
    for(unsigned s=0;s<3;s++)for(uint32_t i=0;i<x->n[s];i++)if(aliases->bits[aliases->offset[s]+i]&which) {
        JValue *v=&x->s[s][i];uint16_t tags=v->dynamic_tags?v->dynamic_tags:ABC_SYM_DYNAMIC_TAGS_UNKNOWN;
        v->dynamic_tags=tags&allowed;
        /* Type proof does not imply normalization or immediate representation. */
        if(v->dynamic_repr==ABC_SYM_REPR_NONE)v->dynamic_repr=ABC_SYM_REPR_UNKNOWN;
    }
}
/* Local branches select an arm BEFORE its edge normalization emits moves.
   These relocations are resolved immediately, never retained as fake versions. */
static int local_branch(Compiler *c,unsigned stencil,Fixup *fix) {
    Version local={0};size_t first=c->nfix;
    if(!place(c,stencil,0,&local))return 0;
    if(c->nfix!=first+1){c->nfix=first;c->status=abc_fail(c->error,ABC_INVALID,c->current_pc,"invalid local branch stencil");return 0;}
    *fix=c->fixups[--c->nfix];fix->target=NULL;return 1;
}
static void bind_local(Compiler *c,const Fixup *fix) { patch(fix->site,fix->kind,fix->addend,(int64_t)(intptr_t)c->pos); }
static int native_type_branch(NativeSymbolicSink *sink,uint32_t pc,uint16_t want) {
    Compiler *c=sink->compiler;Context *x=sink->machine->context;const uint8_t *p=c->module->code+pc;
    uint32_t bp=pc+abc_instruction_length(p);unsigned op=c->module->code[bp];TypeAliases aliases;
    if(!capture_aliases(x,*top(x,JS_A,0),NULL,&aliases))return 0;
    if(!conform_context(c,x,0)||!place_dynamic(c,p,pc,x->n[JS_A],x->n[JS_B],x->c_bias+(int32_t)x->n[JS_C]-x->c_origin,0,0)){free(aliases.bits);return 0;}
    int reg=free_reg(c,x);int32_t home=(int32_t)x->n[JS_A]-1;
    if(reg<0||!place(c,ABC_STENCIL_LOAD(JS_A,reg),(uint64_t)((int64_t)home*8),NULL)){free(aliases.bits);return 0;}
    (void)pop(x,JS_A);Context taken;if(!context_copy(&taken,x)){free(aliases.bits);return 0;}
    int taken_true=op==OP_JNZ_A;
    refine_aliases(&taken,&aliases,1,taken_true?want:(uint16_t)~want);
    refine_aliases(x,&aliases,1,taken_true?(uint16_t)~want:want);free(aliases.bits);
    uint32_t next=bp+op_len[op],target=(uint32_t)((int64_t)next+abc_i16(c->module->code+bp+1));Fixup branch;
    if(!local_branch(c,taken_true?ABC_STENCIL_JNZ(reg):ABC_STENCIL_JZ(reg),&branch)||!emit_jump(c,edge(c,bp,next,x))){context_free(&taken);return 0;}
    bind_local(c,&branch);int ok=emit_jump(c,edge(c,bp,target,&taken));context_free(&taken);
    if(ok)sink->machine->exit=ABC_SYM_EXIT_CONTROL;return 0;
}
static int place_numeric(Compiler *c,unsigned id,uint32_t base,unsigned selector,uint64_t helper) {
    const Stencil *s=&stencils[id];c->placements++;if(!reserve(c,s->len))return 0;uint8_t *at=c->pos;memcpy(at,s->code,s->len);c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++){const Reloc *r=&s->rel[i];int64_t value;
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)c->pos;else if(r->hole==HOLE_FINAL)value=(int64_t)helper;
        else if(r->hole==HOLE_STATE)value=(int64_t)(intptr_t)c->vm;else if(r->hole==HOLE_IMM)value=base;
        else if(r->hole==HOLE_IMM2)value=selector;else return 0;patch(at+r->off,r->kind,r->addend,value);
    }return 1;
}
static int decode_numeric(Compiler *c,Context *x,JValue *value) {
    if(value->dynamic_repr==ABC_SYM_REPR_RAW)return 1;
    int reg=writable(c,x,value);if(reg<0||!place_numeric(c,ABC_STENCIL_NUMERIC_DECODE(reg),0,0,(uint64_t)(uintptr_t)abc_dynamic_numeric_bits))return 0;
    value->dynamic_repr=ABC_SYM_REPR_RAW;return 1;
}
static int native_numeric_body(Compiler *c,Context *x,uint32_t pc,unsigned selector,unsigned tag,JValue *result) {
    uint32_t base=x->n[JS_A]-2;JValue *left=&x->s[JS_A][base],*right=&x->s[JS_A][base+1];
    if(!decode_numeric(c,x,left)||!decode_numeric(c,x,right))return 0;
    int rd=writable(c,x,left);if(rd<0)return 0;int rs=materialize_mask(c,x,right,1u<<(unsigned)rd);if(rs<0)return 0;
    int signed_value=abc_numeric_signed(tag),op=-1;
    switch(selector){
    case EXT_DADD:op=ABC_JOP_ADD;break;case EXT_DSUB:op=ABC_JOP_SUB;break;case EXT_DMUL:op=ABC_JOP_MUL;break;
    case EXT_DDIV:op=signed_value?ABC_JOP_DIVS:ABC_JOP_DIVU;break;case EXT_DREM:op=signed_value?ABC_JOP_REMS:ABC_JOP_REMU;break;
    case EXT_DSHL:op=ABC_JOP_SHL;break;case EXT_DSHR:op=ABC_JOP_SHR;break;case EXT_DSAR:op=ABC_JOP_SAR;break;
    case EXT_DAND:op=ABC_JOP_AND;break;case EXT_DOR:op=ABC_JOP_OR;break;case EXT_DXOR:op=ABC_JOP_XOR;break;
    case EXT_DPOW:break;default:return 0;
    }
    uint64_t error=(uint64_t)ABC_ABORT|(UINT64_C(1)<<8)|((uint64_t)pc<<16);int narrow=binary32_index(op);
    unsigned stencil=selector==EXT_DPOW?ABC_STENCIL_POW(rd,rs):narrow>=0?ABC_STENCIL_BINARY32(narrow,rd,rs):ABC_STENCIL_BINARY(op,rd,rs);
    if(!place(c,stencil,error,NULL))return 0;
    unsigned width=abc_numeric_width(tag);
    if(width<32){if(!place(c,ABC_STENCIL_IMMEDIATE(ABC_JIMM_AND,rd),(UINT64_C(1)<<width)-1,NULL))return 0;}
    else if(!place(c,ABC_STENCIL_UNARY(signed_value?ABC_JUN_SX32:ABC_JUN_ZX32,rd),0,NULL))return 0;
    *result=*left;result->kind=VK_REG;result->reg=(uint32_t)rd;result->dynamic_tags=(uint16_t)(1u<<tag);
    result->dynamic_width=(uint8_t)width;result->dynamic_repr=ABC_SYM_REPR_RAW;result->zero_extended=0;return 1;
}
static int native_dynamic_helper(Compiler *c,Context *x,uint32_t pc,abc_symbolic_dynamic *effect,uint16_t numeric_tags) {
    uint32_t base=x->n[JS_A]-effect->pops;unsigned runtime_tail=effect->tail&&!x->ncont;
    int32_t return_offset=(x->c_bias-x->c_origin-1)*8;
    /* Scalar helpers cannot mutate live stack values. Calls and object effects
       retain the conservative boundary; all roots still get materialized. */
    int preserve=effect->selector<=EXT_DREQUIRE_BOOL;
    if(!conform_context(c,x,!preserve)||!place_dynamic(c,c->module->code+pc,pc,x->n[JS_A],x->n[JS_B],x->c_bias+(int32_t)x->n[JS_C]-x->c_origin,runtime_tail,return_offset))return 0;
    if(!runtime_tail)for(unsigned i=0;i<effect->pushes;i++){int r=free_reg(c,x);int32_t home=(int32_t)(base+i);
        if(r<0||!place(c,ABC_STENCIL_LOAD(JS_A,(unsigned)r),(uint64_t)((int64_t)home*8),NULL))return 0;
        effect->result[i]=reg_value((unsigned)r,JS_A,home);
    }
    if(effect->pushes==1){
        if(effect->selector==EXT_ANY_BOX)abc_symbolic_dynamic_descriptor_fact(c->module,effect->descriptor,&effect->result[0]);
        else if(effect->selector>=EXT_DADD&&effect->selector<=EXT_DXOR)abc_symbolic_numeric_fact(&effect->result[0],numeric_tags);
    }return 1;
}
static int numeric_is_narrow(unsigned tag) { return tag==ABC_ANY_U8||tag==ABC_ANY_U16||tag==ABC_ANY_U32||tag==ABC_ANY_I32; }
static int native_numeric_cfg(NativeSymbolicSink *sink,uint32_t pc,abc_symbolic_dynamic *effect,uint16_t tags) {
    Compiler *c=sink->compiler;Context *x=sink->machine->context;uint32_t base=x->n[JS_A]-2,next=pc+abc_instruction_length(c->module->code+pc);
    TypeAliases aliases;if(!capture_aliases(x,x->s[JS_A][base],&x->s[JS_A][base+1],&aliases))return 0;
    if(!conform_context(c,x,0)){free(aliases.bits);return 0;}
    int reg=free_reg(c,x);
    if(reg<0||!place_numeric(c,ABC_STENCIL_NUMERIC_CLASSIFY(reg),base,effect->selector,(uint64_t)(uintptr_t)abc_dynamic_numeric_classify)){free(aliases.bits);return 0;}
    Fixup branches[16],fallback;
    for(unsigned tag=0;tag<16;tag++)if(tags&(1u<<tag)){
        JValue constant=const_value(tag+1,JS_A,0);int rr=materialize_mask(c,x,&constant,1u<<(unsigned)reg);
        if(rr<0||!local_branch(c,ABC_STENCIL_BRANCH(ABC_JBR_EQ,reg,rr),&branches[tag])){free(aliases.bits);return 0;}
    }
    if(!local_branch(c,ABC_STENCIL_JUMP,&fallback)){free(aliases.bits);return 0;}
    for(unsigned tag=0;tag<16;tag++)if(tags&(1u<<tag)){
        bind_local(c,&branches[tag]);Context arm;if(!context_copy(&arm,x)){free(aliases.bits);return 0;}
        refine_aliases(&arm,&aliases,3,abc_numeric_arguments(tag));abc_symbolic_dynamic leaf=*effect;
        int ok=numeric_is_narrow(tag)?native_numeric_body(c,&arm,pc,effect->selector,tag,&leaf.result[0]):native_dynamic_helper(c,&arm,pc,&leaf,(uint16_t)(1u<<tag));
        if(ok){arm.n[JS_A]=base;ok=push(&arm,JS_A,leaf.result[0])&&emit_jump(c,edge(c,pc,next,&arm));}
        context_free(&arm);if(!ok){free(aliases.bits);return 0;}
    }
    free(aliases.bits);bind_local(c,&fallback);
    /* Classification zero means type mismatch, not an unknown successful
       result. Keep the original helper's safepoint/error behavior, but do not
       invent a successful edge that would consume the version budget. */
    if(!native_dynamic_helper(c,x,pc,effect,0)||
       !place(c,ABC_STENCIL_ABORT,(uint64_t)ABC_ABORT|(UINT64_C(6)<<8)|((uint64_t)pc<<16),NULL))return 0;
    sink->machine->exit=ABC_SYM_EXIT_CONTROL;return 0;
}
static int native_emit_dynamic(void *opaque,uint32_t pc,abc_symbolic_dynamic *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;const uint8_t *p=c->module->code+pc;uint32_t base=x->n[JS_A]-effect->pops;c->current_pc=pc;
    if(effect->selector==EXT_ANY_BOX&&c->module->descriptors[effect->descriptor].tag==ABC_DESC_PRIMITIVE&&
       c->module->descriptors[effect->descriptor].payload[0]==ABC_PRIM_UNIT){
        effect->result[0]=const_value(abc_any_unit(),JS_A,(int32_t)base);
        abc_symbolic_dynamic_descriptor_fact(c->module,effect->descriptor,&effect->result[0]);return 1;
    }
    if(effect->selector==EXT_ANY_IS){
        uint16_t want=abc_symbolic_test_tags(c->module,effect->descriptor);uint32_t next=pc+abc_instruction_length(p);
        if(want&&next<c->module->code_size&&!c->block[next]&&(c->module->code[next]==OP_JZ_A||c->module->code[next]==OP_JNZ_A)){
            int ok=native_type_branch(sink,pc,want);if(!ok&&sink->machine->exit!=ABC_SYM_EXIT_CONTROL)goto failed;return ok;
        }
    }
    if(effect->selector==EXT_ANY_BOX&&effect->pops==1&&effect->pushes==1&&abc_symbolic_dynamic_box_specialization(c->module,effect->descriptor,x->s[JS_A][base])){
        effect->result[0]=x->s[JS_A][base];abc_symbolic_dynamic_descriptor_fact(c->module,effect->descriptor,&effect->result[0]);effect->result[0].dynamic_repr=ABC_SYM_REPR_RAW;return 1;
    }
    if(effect->selector==EXT_ANY_CAST&&effect->pops==1&&effect->pushes==1&&abc_symbolic_dynamic_cast_matches(c->module,effect->descriptor,x->s[JS_A][base])){
        effect->result[0]=x->s[JS_A][base];abc_symbolic_forget_dynamic(&effect->result[0]);return 1;
    }
    uint16_t tags=0;
    if(effect->selector>=EXT_DADD&&effect->selector<=EXT_DXOR){
        int certain;tags=abc_symbolic_numeric_results(effect->selector,x->s[JS_A][base],x->s[JS_A][base+1],&certain);
        if(certain&&numeric_is_narrow((unsigned)__builtin_ctz((unsigned)tags))){
            if(!native_numeric_body(c,x,pc,effect->selector,(unsigned)__builtin_ctz((unsigned)tags),&effect->result[0]))goto failed;return 1;
        }
        unsigned opcode;if(abc_symbolic_dynamic_binary_specialization(effect->selector,x->s[JS_A][base],x->s[JS_A][base+1],&opcode)){
            int ok=0;effect->result[0]=x->s[JS_A][base];effect->result[0].constant=abc_symbolic_fold_binary(opcode,x->s[JS_A][base].constant,x->s[JS_A][base+1].constant,&ok);
            if(!ok)goto failed;effect->result[0].kind=VK_CONST;effect->result[0].dynamic_repr=ABC_SYM_REPR_RAW;return 1;
        }
        uint16_t narrow=(uint16_t)((1u<<ABC_ANY_U8)|(1u<<ABC_ANY_U16)|(1u<<ABC_ANY_U32)|(1u<<ABC_ANY_I32));
        if(!certain&&(tags&narrow)){
            uint32_t next=pc+abc_instruction_length(p);Context family=*x;family.n[JS_A]=base+1;unsigned versions=0;
            for(Version *v=c->versions[next];v;v=v->next)versions+=context_family_equal(&v->in,&family);
            /* Reserve the existing generic slot; never split a saturated family. */
            if(versions+(unsigned)__builtin_popcount((unsigned)tags)<ABC_BLOCK_VERSION_LIMIT){
                int ok=native_numeric_cfg(sink,pc,effect,tags);if(!ok&&sink->machine->exit!=ABC_SYM_EXIT_CONTROL)goto failed;return ok;
            }
        }
    }
    if(!native_dynamic_helper(c,x,pc,effect,tags))goto failed;return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,pc,"native dynamic specialization emission failed");return 0;
}

static int native_emit_foreign(void *opaque,uint32_t pc,abc_symbolic_foreign *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;const abc_extern *ext=&c->module->externs[effect->index];
    uint32_t abase=x->n[JS_A]-effect->arguments;for(uint32_t j=abase;j<x->n[JS_A];j++){JValue *q=&x->s[JS_A][j];q->dst_stack=JS_A;q->dst_home=(int32_t)j;if(!save_value(c,x,q))return 0;*q=rehome_value(*q,JS_A,(int32_t)j);}
    if(!flush_context(c,x))return 0;abc_foreign_address target=abc_foreign_lookup(c->vm,ext->name);uint64_t error=(uint64_t)ABC_INVALID|((uint64_t)pc<<16);
    return target&&place_fcall(c,effect->results?ABC_STENCIL_FCALL1:ABC_STENCIL_FCALL0,abase,ext,target,error);
}

static int native_emit_edge(void *opaque,uint32_t origin,uint32_t target) {
    NativeSymbolicSink *sink=opaque;return emit_jump(sink->compiler,edge(sink->compiler,origin,target,sink->machine->context));
}

static int ensure_raw_indirect_capacity(Compiler *c,Context *x,const abc_function *site,
                                        uint32_t abase,uint32_t bbase,int32_t cbase,uint64_t error) {
    uint32_t max_a=0,max_b=0,max_c=0;
    for(uint32_t i=0;i<c->module->function_count;i++){const abc_function *f=&c->module->functions[i];
        if(!abc_same_signature(site,f))continue;
        if(f->max_a>max_a)max_a=f->max_a;if(f->max_b>max_b)max_b=f->max_b;
        uint32_t extra=f->max_c>=f->arguments?f->max_c-f->arguments:0;if(extra>max_c)max_c=extra;
    }
    return ensure_capacity(c,x,JS_A,abase+max_a,error)&&
           ensure_capacity(c,x,JS_B,bbase+max_b,error)&&
           ensure_capacity(c,x,JS_C,(uint32_t)cbase+max_c,error);
}

static int native_emit_indirect(void *opaque,uint32_t pc,abc_symbolic_indirect *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;const abc_function *site=abc_find_site(c->module,pc);
    unsigned n=effect->arguments;if(!site||x->n[JS_A]<n||!x->n[JS_B]||(effect->tail&&x->n[JS_C]<effect->frame_cells)){c->status=abc_fail(c->error,ABC_INVALID,pc,"native indirect-call sink rejected instruction");return 0;}
    uint32_t abase=x->n[JS_A]-n;
    int raw=c->module->callable_profile&&!c->module->dynamic_profile;
    int32_t logical_c=x->c_bias+(int32_t)x->n[JS_C]-x->c_origin+(int32_t)n+(effect->tail?-(int32_t)effect->frame_cells:1);
    if(raw&&!ensure_raw_indirect_capacity(c,x,site,abase,x->n[JS_B]-1,logical_c,(uint64_t)ABC_STACK|((uint64_t)pc<<16)))return 0;
    JValue target=effect->target;target.dst_stack=JS_B;target.dst_home=(int32_t)x->n[JS_B]-1;if(!save_value(c,x,&target))return 0;
    if(effect->tail) {
        uint32_t cbase=x->n[JS_C]-effect->frame_cells;int32_t coff=x->c_bias+(int32_t)cbase-x->c_origin;
        if(!place_guard(c,JS_C,coff+(int32_t)n>0?(uint32_t)(coff+(int32_t)n):0,(uint64_t)ABC_STACK|((uint64_t)pc<<16),NULL))return 0;
        for(unsigned j=0;j<n;j++){JValue *arg=&x->s[JS_A][abase+j];arg->dst_stack=JS_A;arg->dst_home=(int32_t)(abase+j);if(!materialize_dynamic(c,x,arg)||!save_value(c,x,arg))return 0;}
        for(unsigned j=0;j<n;j++){JValue arg=home_value(JS_A,(int32_t)(abase+j));int r=materialize(c,x,&arg);if(r<0||!place(c,ABC_STENCIL_STORE(JS_C,r),(uint64_t)((int64_t)(coff+(int32_t)n-1-(int32_t)j)*8),NULL))return 0;}
        target=home_value(JS_B,target.dst_home);int rt=materialize(c,x,&target);if(rt<0)return 0;uint64_t packed=(uint32_t)abase|((uint64_t)(uint32_t)(coff+(int32_t)n)<<32);
        if(c->module->callable_profile&&!c->module->dynamic_profile)
            return place_raw_indirect(c,ABC_STENCIL_RAW_TCALLI(rt),packed,(int32_t)x->n[JS_B]-1,(uint64_t)ABC_INVALID|((uint64_t)pc<<16),&c->sites[site-c->module->sites]);
        abc_ic_state *ic=&c->sites[site-c->module->sites];ic->tail=1;NativeFn helper=ic->phase==2?ic_final_tail:ic->phase==1?ic_specific_tail:ic_observe_tail;
        return place_ic(c,ABC_STENCIL_TCALLI(rt),packed,(int32_t)x->n[JS_B]-1,ic,helper);
    }
    int32_t ctop=x->c_bias+(int32_t)x->n[JS_C]-x->c_origin;
    if(!place_guard(c,JS_C,ctop+(int32_t)n+1>0?(uint32_t)(ctop+(int32_t)n+1):0,(uint64_t)ABC_STACK|((uint64_t)pc<<16),NULL))return 0;
    for(unsigned j=0;j<n;j++){JValue *arg=&x->s[JS_A][abase+j];if(!materialize_dynamic(c,x,arg))return 0;int r=materialize(c,x,arg);if(r<0||!place(c,ABC_STENCIL_STORE(JS_C,r),(uint64_t)((int64_t)(ctop+(int32_t)n-(int32_t)j)*8),NULL))return 0;}
    if(!place(c,ABC_STENCIL_RETURN_SENTINEL,(uint64_t)((int64_t)ctop*8),NULL)||!flush_context(c,x))return 0;target=home_value(JS_B,target.dst_home);int rt=materialize(c,x,&target);if(rt<0)return 0;
    uint64_t packed=(uint32_t)abase|((uint64_t)(uint32_t)(ctop+(int32_t)n+1)<<32);
    if(c->module->callable_profile&&!c->module->dynamic_profile){
        if(!place_raw_indirect(c,ABC_STENCIL_RAW_CALLI(rt),packed,(int32_t)x->n[JS_B]-1,(uint64_t)ABC_INVALID|((uint64_t)pc<<16),&c->sites[site-c->module->sites]))return 0;
    }else{
        abc_ic_state *ic=&c->sites[site-c->module->sites];ic->tail=0;NativeFn helper=ic->phase==2?ic_final_call:ic->phase==1?ic_specific_call:ic_observe_call;
        if(!place_ic(c,ABC_STENCIL_CALLI(rt),packed,(int32_t)x->n[JS_B]-1,ic,helper))return 0;
    }
    for(uint32_t j=0;j<site->results;j++)effect->result[j]=home_value(JS_A,(int32_t)(abase+j));return 1;
}

static int native_emit_call(void *opaque,uint32_t pc,abc_symbolic_call *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;int fi=abc_find_function(c->module,effect->target);
    unsigned n=effect->arguments;uint32_t abase=x->n[JS_A]-n;int32_t ctop=x->c_bias+(int32_t)x->n[JS_C]-x->c_origin;
    if(fi<0){c->status=abc_fail(c->error,ABC_INVALID,pc,"native direct-call sink rejected target");return 0;}const abc_function *callee_function=&c->module->functions[fi];
    uint64_t error=(uint64_t)ABC_STACK|((uint64_t)pc<<16);
    if(inline_candidate(c,x,pc,effect->target,&effect->continuation)) {
        if(!ensure_capacity(c,x,JS_A,abase+callee_function->max_a,error)||!ensure_capacity(c,x,JS_B,x->n[JS_B]+callee_function->max_b,error)||!ensure_capacity(c,x,JS_C,(uint32_t)(ctop+(int32_t)callee_function->max_c),error))return 0;
        effect->virtualize=1;c->virtual_calls++;return 1;
    }
    if(!ensure_capacity(c,x,JS_A,abase+callee_function->max_a,error)||!ensure_capacity(c,x,JS_B,x->n[JS_B]+callee_function->max_b,error)||!ensure_capacity(c,x,JS_C,(uint32_t)(ctop+1+(int32_t)callee_function->max_c),error))return 0;
    Version *callee=NULL;
    if(c->recursive[fi]) {
        for(unsigned j=0;j<n;j++){JValue *arg=&x->s[JS_A][abase+j];arg->dst_stack=JS_A;arg->dst_home=(int32_t)(abase+j);if(!materialize_dynamic(c,x,arg)||!save_value(c,x,arg))return 0;*arg=rehome_value(*arg,JS_A,(int32_t)(abase+j));}
        if(!flush_context(c,x))return 0;
        for(unsigned j=8;j<n;j++)if(!place(c,ABC_STENCIL_LOAD(JS_A,0),(uint64_t)((int64_t)(abase+j)*8),NULL)||!place(c,ABC_STENCIL_STORE(JS_C,0),(uint64_t)((int64_t)(ctop+(int32_t)n-(int32_t)j)*8),NULL))return 0;
        for(unsigned j=0;j<n&&j<8;j++)if(!place(c,ABC_STENCIL_LOAD(JS_A,j),(uint64_t)((int64_t)(abase+j)*8),NULL))return 0;
        Context in={0};in.c_origin=(int32_t)n;in.reg_return=callee_function->results==1;in.limit[JS_A]=callee_function->max_a;in.limit[JS_B]=callee_function->max_b;in.limit[JS_C]=callee_function->max_c-callee_function->arguments;
        if(n){in.s[JS_C]=malloc((size_t)n*sizeof *in.s[JS_C]);if(!in.s[JS_C]){c->status=abc_fail(c->error,ABC_NOMEM,pc,"native direct-call sink allocation failed");return 0;}in.n[JS_C]=in.cap[JS_C]=n;for(unsigned j=0;j<n;j++){int32_t home=-1-(int32_t)j;JValue q=j<8?reg_value(j,JS_C,home):home_value(JS_C,home);q.dst_stack=JS_C;q.dst_home=home;in.s[JS_C][n-1-j]=q;}}
        callee=version_for(c,effect->target,&in);context_free(&in);if(!callee)return 0;
    } else {
        for(unsigned j=0;j<n;j++){JValue *arg=&x->s[JS_A][abase+j];if(!materialize_dynamic(c,x,arg))return 0;int r=materialize(c,x,arg);if(r<0||!place(c,ABC_STENCIL_STORE(JS_C,r),(uint64_t)((int64_t)(ctop+(int32_t)n-(int32_t)j)*8),NULL))return 0;}
        if(!flush_context(c,x))return 0;callee=c->function_entries[fi];if(!callee){c->status=abc_fail(c->error,ABC_INVALID,pc,"native direct-call sink missing entry");return 0;}
    }
    uint64_t packed=(uint32_t)abase|((uint64_t)(uint32_t)(ctop+(int32_t)n+1)<<32);
    if(!place_call_jump(c,packed,(int32_t)x->n[JS_B],ctop*8,callee)||!place_biased(c,ABC_STENCIL_CALL_RESUME,packed,(int32_t)x->n[JS_B],NULL))return 0;
    c->real_calls++;for(uint32_t j=0;j<callee_function->results;j++)effect->result[j]=c->recursive[fi]&&callee_function->results==1?reg_value(0,JS_A,(int32_t)(abase+j)):home_value(JS_A,(int32_t)(abase+j));
    return 1;
}

static int native_emit_tail(void *opaque,uint32_t pc,abc_symbolic_tail *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;int fi=abc_find_function(c->module,effect->target);
    if(fi<0||!c->versions[effect->target]){c->status=abc_fail(c->error,ABC_INVALID,pc,"native tail-call sink rejected target");return 0;}
    uint32_t abase=x->n[JS_A]-effect->arguments,cbase=x->n[JS_C]-effect->frame_cells;int32_t coff=x->c_bias+(int32_t)cbase-x->c_origin;
    const abc_function *callee=&c->module->functions[fi];uint64_t error=(uint64_t)ABC_STACK|((uint64_t)pc<<16);
    if(!ensure_capacity(c,x,JS_A,abase+callee->max_a,error)||!ensure_capacity(c,x,JS_B,x->n[JS_B]+callee->max_b,error)||!ensure_capacity(c,x,JS_C,(uint32_t)(coff+(int32_t)callee->max_c),error))return 0;
    c->virtual_tails++;return 1;
}

static int native_emit_return(void *opaque,uint32_t pc,const abc_symbolic_return *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;c->current_pc=pc;
    if(!effect->terminal){c->virtual_returns++;return 1;}
    if(x->reg_return){if(x->n[JS_A]!=1)return 0;JValue *q=&x->s[JS_A][0];if(!materialize_dynamic(c,x,q))return 0;int reg=materialize(c,x,q);if(reg<0||(reg&&!place(c,ABC_STENCIL_MOV(0,reg),0,NULL)))return 0;}
    else for(uint32_t i=0;i<x->n[JS_A];i++){JValue *q=&x->s[JS_A][i];q->dst_stack=JS_A;q->dst_home=(int32_t)i;if(!materialize_dynamic(c,x,q)||!save_value(c,x,q))return 0;}
    int32_t return_offset=(x->c_bias-x->c_origin-1)*8;return place(c,ABC_STENCIL_RETURN_CONT,(uint64_t)(int64_t)return_offset,NULL);
}

static int native_emit_effect(void *opaque,uint32_t pc,unsigned opcode) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;c->status=abc_fail(c->error,ABC_INVALID,pc,"native effect sink does not support %s",op_name[opcode]);return 0;
}

static int compile_version(Compiler *c,Version *v) {
    Context x; if(!context_copy(&x,&v->in)) return 0;v->body=c->pos;if(!c->lazy)v->address=v->body;v->compiling=1;
    const uint8_t *code=c->module->code; uint32_t pc=v->pc; int live=1;
    while(live && pc<c->module->code_size) {
        if(pc!=v->pc && c->block[pc]) { Version *to=edge(c,pc-1,pc,&x); if(!emit_jump(c,to)) goto failed; break; }
        abc_symbolic_machine machine={.module=c->module,.code=code,.blocks=c->block,.pc=pc,.end=c->module->code_size,
            .context=&x,.error=c->error,.transfer_mask=ABC_SYM_TRANSFER_STACK|ABC_SYM_TRANSFER_VALUE|ABC_SYM_TRANSFER_CONTROL|ABC_SYM_TRANSFER_EFFECT};
        NativeSymbolicSink native_sink={c,&machine}; machine.sink=&native_sink;
        machine.emit_binary=native_emit_binary; machine.emit_float_binary=native_emit_float_binary;
        machine.emit_pow=native_emit_pow; machine.emit_check=native_emit_check;
        machine.emit_unary=native_emit_unary; machine.emit_float_unary=native_emit_float_unary;
        machine.emit_immediate=native_emit_immediate; machine.emit_c_operand=native_emit_c_operand;
        machine.emit_control=native_emit_control; machine.emit_abort=native_emit_abort; machine.emit_halt=native_emit_halt;
        machine.emit_effect=native_emit_effect; machine.emit_memory=native_emit_memory;machine.emit_return=native_emit_return;machine.emit_call=native_emit_call;machine.emit_indirect=native_emit_indirect;machine.emit_tail=native_emit_tail;
        machine.emit_dynamic=native_emit_dynamic;machine.emit_foreign=native_emit_foreign;machine.emit_edge=native_emit_edge;
        abc_symbolic_exit symbolic_exit=abc_symbolic_dispatch(&machine);
        if(symbolic_exit==ABC_SYM_EXIT_FAILURE) { c->status=c->error?c->error->status:ABC_NOMEM; goto failed; }
        if(symbolic_exit==ABC_SYM_EXIT_CONTROL||symbolic_exit==ABC_SYM_EXIT_TERMINATED) { live=0; break; }
        if(machine.pc!=pc) { pc=machine.pc; continue; }
        c->status=abc_fail(c->error,ABC_INVALID,pc,"generated symbolic dispatcher stopped without progress");
        goto failed;
    }
    context_free(&x); v->compiled=1;v->compiling=0; return 1;
failed: context_free(&x);v->compiling=0; return 0;
}

void abc_native_site_stats(const abc_native_image *image,abc_site_stats *stats) {
    stats->generic=image->site_count; stats->specific=stats->final_generic=0; stats->transitions=image->transitions;
    for(uint32_t i=0;i<image->site_count;i++) if(image->sites[i].phase==1) { stats->generic--; stats->specific++; }
        else if(image->sites[i].phase==2) { stats->generic--; stats->final_generic++; }
}
void abc_native_image_free(abc_native_image *image) {
    if(!image)return;Compiler *c=image->lazy_state;if(c){for(size_t pc=0;pc<c->module->code_size;pc++){Version *v=c->versions[pc];while(v){Version *next=v->next;context_free(&v->in);free(v);v=next;}}free(c->block);free(c->versions);free(c->function_entries);free(c->recursive);free(c->queue);free(c->fixups);free(c);}
    if(image->code)munmap(image->code,image->mapping_size);for(uint32_t i=0;i<image->site_count;i++)free(image->sites[i].patches);free(image->sites);free(image->entries);free(image);
}
abc_status abc_residualize_module(const abc_module *m,uint8_t *image_base,const abc_vm *vm,unsigned lazy,abc_native_image **out,abc_error *e) {
    abc_clear(e); if(out) *out=NULL; if(!m||!vm||!out) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid residualizer input");
    Compiler c={0}; c.module=m; c.vm=vm; c.image_base=image_base; c.error=e; c.status=ABC_OK;c.lazy=lazy;
    c.stack_end[JS_A]=vm->a+vm->capacity; c.stack_end[JS_B]=vm->b+vm->capacity; c.stack_end[JS_C]=vm->c+vm->capacity;
    c.block=calloc(m->code_size,1); c.versions=calloc(m->code_size,sizeof *c.versions); c.function_entries=calloc(m->function_count,sizeof *c.function_entries); c.recursive=calloc(m->function_count,1);
    if(m->site_count) c.sites=calloc(m->site_count,sizeof *c.sites);
    size_t pages=(size_t)sysconf(_SC_PAGESIZE), wanted=m->code_size*4096+pages; wanted=(wanted+pages-1)&~(pages-1);
    if(wanted>UINT32_C(0x60000000)) wanted=UINT32_C(0x60000000);
    c.base=mmap(NULL,wanted,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,-1,0);c.mapping_size=wanted;
    if(!c.block||!c.versions||!c.function_entries||!c.recursive||(m->site_count&&!c.sites)||c.base==MAP_FAILED) { if(c.base!=MAP_FAILED&&c.base) munmap(c.base,wanted); free(c.block); free(c.versions); free(c.function_entries); free(c.recursive); free(c.sites); return abc_fail(e,ABC_NOMEM,UINT32_MAX,"residualizer allocation failed"); }
    c.pos=c.base; c.end=c.base+wanted;c.stub_pos=c.end; discover_blocks(&c);
    for(uint32_t f=0;f<m->function_count;f++) {
        uint8_t *seen=calloc(m->function_count,1); if(!seen) { c.status=abc_fail(e,ABC_NOMEM,m->functions[f].entry,"call graph allocation failed"); break; }
        c.recursive[f]=(uint8_t)abc_symbolic_reaches_function(m,(int)f,(int)f,seen); memset(seen,0,m->function_count);
        c.recursive[f]|=(uint8_t)abc_symbolic_has_unknown_call(m,(int)f,seen); free(seen);
    }
    for(uint32_t i=0;i<m->site_count;i++) { c.sites[i].module=m; c.sites[i].signature=&m->sites[i]; }
    void **entries=calloc(m->function_count,sizeof *entries);
    for(uint32_t f=0;f<m->function_count&&c.status==ABC_OK;f++) {
        Context x={0}; const abc_function *fn=&m->functions[f]; uint32_t n=fn->arguments; x.c_origin=(int32_t)n;
        x.limit[JS_A]=fn->max_a; x.limit[JS_B]=fn->max_b; x.limit[JS_C]=fn->max_c-fn->arguments;
        if(n) { x.s[JS_C]=malloc((size_t)n*sizeof(JValue)); if(!x.s[JS_C]) { c.status=abc_fail(e,ABC_NOMEM,m->functions[f].entry,"entry context allocation failed"); break; } x.n[JS_C]=x.cap[JS_C]=n;
            for(uint32_t i=0;i<n;i++) x.s[JS_C][n-1-i]=home_value(JS_C,-1-(int32_t)i);
        }
        Version *v=version_for(&c,m->functions[f].entry,&x); context_free(&x); if(!v) break; c.function_entries[f]=v; entries[f]=v;
    }
    if(!c.lazy)while(c.qhead<c.nq&&c.status==ABC_OK) if(!compile_version(&c,c.queue[c.qhead++])&&c.status==ABC_OK) c.status=ABC_INVALID;
    if(c.status==ABC_OK) for(size_t i=0;i<c.nfix;i++) { Fixup *f=&c.fixups[i]; if(!f->target->compiled) { c.status=abc_fail(e,ABC_INVALID,f->target->pc,"uncompiled edge target"); break; } patch(f->site,f->kind,f->addend,(int64_t)(intptr_t)f->target->address); }
    if(c.status==ABC_OK && mprotect(c.base,wanted,PROT_READ|PROT_EXEC)) c.status=abc_fail(e,ABC_IO,UINT32_MAX,"cannot protect compiled code");
    abc_native_image *image=NULL;
    if(c.status==ABC_OK) { image=calloc(1,sizeof *image); if(!image) c.status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"native image allocation failed"); }
    if(c.status==ABC_OK) {
        image->code=c.base; image->code_size=(size_t)(c.pos-c.base); image->mapping_size=wanted; image->entries=entries; image->entry_count=m->function_count;image->lazy=c.lazy;
        image->stack_end[JS_A]=c.stack_end[JS_A]; image->stack_end[JS_B]=c.stack_end[JS_B]; image->stack_end[JS_C]=c.stack_end[JS_C];
        image->sites=c.sites; image->site_count=m->site_count; image->virtual_calls=c.virtual_calls; image->virtual_returns=c.virtual_returns; image->virtual_tails=c.virtual_tails; image->real_calls=c.real_calls;image->compiled_versions=c.qhead;
        for(uint32_t f=0;f<m->function_count;f++) image->entries[f]=((Version *)entries[f])->address;
        for(uint32_t i=0;i<image->site_count;i++) image->sites[i].owner=image;
        if(c.lazy){Compiler *saved=malloc(sizeof *saved);if(!saved)c.status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"lazy compiler state allocation failed");else{*saved=c;saved->image=image;image->lazy_state=saved;for(size_t pc=0;pc<m->code_size;pc++)for(Version *v=saved->versions[pc];v;v=v->next)v->owner=saved;}}
        if(c.status==ABC_OK)*out=image;
    } else {
        munmap(c.base,wanted); free(entries); for(uint32_t i=0;i<m->site_count;i++) free(c.sites[i].patches); free(c.sites);
    }
    if(c.status!=ABC_OK&&image){free(image);munmap(c.base,wanted);free(entries);for(uint32_t i=0;i<m->site_count;i++)free(c.sites[i].patches);free(c.sites);}
    if(!c.lazy||c.status!=ABC_OK){for(size_t pc=0;pc<m->code_size;pc++){Version *v=c.versions[pc];while(v){Version *next=v->next;context_free(&v->in);free(v);v=next;}}
        free(c.block);free(c.versions);free(c.function_entries);free(c.recursive);free(c.queue);free(c.fixups);}
    return c.status;
}

