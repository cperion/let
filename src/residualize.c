#include "residualize.h"
#include "symbolic.h"
#include "execution_emit.h"
#include "runtime_call.h"
#include "generated/execution_forms.h"
_Static_assert(ABC_SYM_EQ==ABC_JBR_EQ && ABC_SYM_NE==ABC_JBR_NE &&
               ABC_SYM_LT==ABC_JBR_LT && ABC_SYM_LE==ABC_JBR_LE &&
               ABC_SYM_LTU==ABC_JBR_LTU && ABC_SYM_LEU==ABC_JBR_LEU,
               "symbolic/native branch relation mismatch");

/* Execution family/continuation threshold; independent of build-time tooling. */
enum { ABC_EXECUTION_VERSION_LIMIT = 16 };
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
struct Version { uint32_t pc; Context in; abc_exec_label entry,body; unsigned compiling,compiled; Compiler *owner; Version *next; };
typedef abc_exec_label Fixup;
struct Compiler {
    const abc_module *module; const abc_vm *vm; uint8_t *image_base;
    abc_exec_emitter *emitter;
    Version **versions, **function_entries; uint8_t *block, *recursive;
    Version **queue; size_t nq, qhead, qcap, virtual_calls, virtual_returns, virtual_tails, real_calls;
    abc_status status; abc_error *error; uint32_t current_pc;
    struct abc_execution_image *image; unsigned lazy, register_count, release_glue;
};
static int emitted(Compiler *c,abc_status status) {
    if(status!=ABC_OK)c->status=status;
    return status==ABC_OK;
}
static int emit_form(Compiler *c,unsigned form,const abc_exec_operands *operands) {
    return emitted(c,c->emitter->ops->emit(c->emitter,form,operands,c->current_pc,c->error));
}
static int grow(void **p,size_t *cap,size_t need,size_t size) {
    if(need<=*cap) return 1; size_t n=*cap ? *cap*2 : 32; while(n<need) n*=2;
    void *q=realloc(*p,n*size); if(!q) return 0; *p=q; *cap=n; return 1;
}
static int place(Compiler *c,unsigned id,uint64_t immediate,Version *taken) {
    const abc_exec_operands operands={.value={immediate},.target=taken?taken->entry:ABC_EXEC_NO_LABEL};
    return emit_form(c,id,&operands);
}
/* MEMCPY binds the same overlap-safe library operation as the interpreter.
   The byte count and function address are separate stencil operands. */
static int place_memory_copy(Compiler *c,unsigned destination_register,unsigned source_register,uint32_t bytes) {
    const abc_exec_operands operands={.value={bytes,(uintptr_t)memmove},.target=ABC_EXEC_NO_LABEL};
    return emit_form(c,ABC_FORM_MEMCPY(destination_register,source_register),&operands);
}
static abc_status lazy_prepare(void *state,abc_error *error);
static int place_fcall(Compiler *c,unsigned id,uint32_t abase,const abc_extern *ext,abc_foreign_address target,uint64_t error) {
    abc_foreign_bridge_fn bridge=abc_primitive_index(ext->name)>=0?abc_runtime_invoke:abc_foreign_select(ext);
    const abc_exec_operands operands={.value={(uint64_t)abase*8,(uintptr_t)bridge,(uintptr_t)ext,(uintptr_t)target,error},.target=ABC_EXEC_NO_LABEL};
    return emit_form(c,id,&operands);
}
/* Rebase is frame transport, independent of the following transfer. Zero
   movement emits nothing; each nonzero movement carries one displacement in bytes. */
static int rebase_frame(Compiler *c,int64_t a,int64_t b,int64_t frame) {
    const int64_t bytes[3]={a,b,frame};
    for(unsigned s=0;s<3;s++)if(bytes[s]) {
        if(!place(c,ABC_FORM_REBASE(s),(uint64_t)bytes[s],NULL))return 0;
    }
    return 1;
}
static int place_guard(Compiler *c,unsigned stack,uint32_t cells,uint64_t error) {
    const abc_exec_operands operands={.value={(uint64_t)cells*8,(uintptr_t)abc_execution_limit,error},.target=ABC_EXEC_NO_LABEL};
    return emit_form(c,ABC_FORM_GUARD(stack),&operands);
}
/* Frontiers are signed coordinates relative to the unchanged physical base.
   limit[] is nonnegative proven headroom, not the current logical depth. */
static int ensure_capacity(Compiler *c,Context *x,unsigned stack,int64_t cells,uint64_t error) {
    if(cells<=(int64_t)x->limit[stack]) return 1;
    /* Every physical base lies within its VM stack. An impossible positive
       request must fail on execution, without narrowing or inventing knowledge. */
    if((uint64_t)cells>ABC_MAX_FILE)return place(c,ABC_FORM_ABORT,error,NULL);
    _Static_assert(ABC_MAX_FILE<=INT32_MAX/8,"capacity must fit native byte displacement");
    if(!place_guard(c,stack,(uint32_t)cells,error)) return 0;
    x->limit[stack]=(uint32_t)cells; return 1;
}
/* Resolution never executes ABC. Integer frontiers allow checking capacity
   before forming out-of-bounds C pointers or writing the new argument frame. */
static uint64_t resolve_execution_target(uint64_t target,uint64_t pc,
        uintptr_t a,uintptr_t b,uintptr_t c,uint64_t *entry) {
    abc_exec_context *run=abc_active_context;uint32_t index;
    abc_status status=vm_resolve_indirect(run,(uint32_t)pc,target,&index);
    if(status!=ABC_OK)return (uint64_t)status|(pc<<16);
    const abc_function *function=&run->m->functions[index];
    const abc_execution_image *image=run->image->execution;
    uintptr_t ae=(uintptr_t)abc_execution_limit(JS_A),be=(uintptr_t)abc_execution_limit(JS_B),ce=(uintptr_t)abc_execution_limit(JS_C);
    if(a>ae||b>be||c>ce||function->max_a>(ae-a)/8||function->max_b>(be-b)/8||
       function->max_c-function->arguments>(ce-c)/8)return (uint64_t)ABC_STACK|(pc<<16);
    *entry=(uint64_t)(uintptr_t)image->entries[index];return ABC_OK;
}
static int place_indirect_resolution(Compiler *c,uint32_t pc,int64_t a_bytes,int64_t b_bytes,int64_t c_bytes) {
    const abc_exec_operands operands={.value={(uintptr_t)resolve_execution_target,pc,(uint64_t)a_bytes,(uint64_t)b_bytes,(uint64_t)c_bytes},.target=ABC_EXEC_NO_LABEL};
    return emit_form(c,ABC_FORM_RESOLVE_INDIRECT,&operands);
}


static int reg_uses(const Context *x,unsigned reg) {
    int n=0; for(unsigned s=0;s<3;s++) for(uint32_t i=0;i<x->n[s];i++) n+=x->s[s][i].kind==VK_REG && x->s[s][i].reg==reg; return n;
}
static int store_id(unsigned stack,unsigned reg) { return ABC_FORM_STORE(stack,reg); }
static int load_id(unsigned stack,unsigned reg) { return ABC_FORM_LOAD(stack,reg); }
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
    for(unsigned r=0;r<c->register_count;r++) if(!(mask&(1u<<r))&&!reg_uses(x,r)) return (int)r;
    for(unsigned r=0;r<c->register_count;r++) if(!(mask&(1u<<r))&&spill_reg(c,x,r)) return (int)r;
    return -1;
}
static int free_reg(Compiler *c,Context *x) { return free_reg_mask(c,x,0); }
static int materialize_mask(Compiler *c,Context *x,JValue *v,unsigned mask) {
    if(v->kind==VK_REG) return v->reg; int r=free_reg_mask(c,x,mask); if(r<0) return -1;
    unsigned id=v->kind==VK_CONST ? ABC_FORM_CONST(r) : (unsigned)load_id(v->stack,r);
    uint64_t imm=v->kind==VK_CONST ? v->constant : (uint64_t)((int64_t)v->home*8);
    if(!place(c,id,imm,NULL)) return -1; v->kind=VK_REG; v->reg=(uint8_t)r; return r;
}
static int materialize(Compiler *c,Context *x,JValue *v) { return materialize_mask(c,x,v,0); }
static int writable(Compiler *c,Context *x,JValue *v);
static int save_value(Compiler *c,Context *x,JValue *v);
static int local_branch(Compiler *c,unsigned stencil,Fixup *fix);
static void bind_local(Compiler *c,const Fixup *fix);
static int writable(Compiler *c,Context *x,JValue *v) {
    int r=materialize(c,x,v); if(r<0 || reg_uses(x,(unsigned)r)==1) return r;
    int d=free_reg_mask(c,x,1u<<(unsigned)r); if(d<0 || !place(c,ABC_FORM_MOV(d,r),0,NULL)) return -1;
    v->reg=(uint8_t)d; return d;
}
static int save_value(Compiler *c,Context *x,JValue *v) {
    if(v->kind==VK_HOME && v->stack==v->dst_stack && v->home==v->dst_home) return 1;
    int r=materialize(c,x,v); if(r<0) return 0;
    return place(c,(unsigned)store_id(v->dst_stack,(unsigned)r),(uint64_t)((int64_t)v->dst_home*8),NULL);
}
static int flush_context(Compiler *c,Context *x) {
    for(int s=2;s>=0;s--) for(uint32_t i=0;i<x->n[s];i++) { JValue *v=&x->s[s][i];
        if(v->kind!=VK_CONST) { if(!save_value(c,x,v)) return 0; *v=rehome_value(*v,v->dst_stack,v->dst_home); }
    }
    return 1;
}
static int conform_generic(Compiler *c,Context *x) {
    for(int s=2;s>=0;s--) for(uint32_t i=0;i<x->n[s];i++) { JValue *v=&x->s[s][i];
        int32_t home=s==JS_C?x->c_bias+(int32_t)i-x->c_origin:(int32_t)i;
        v->dst_stack=(uint8_t)s; v->dst_home=home;
        if(!save_value(c,x,v)) return 0;
        *v=rehome_value(*v,s,home);
    }
    memset(x->limit,0,sizeof x->limit); x->generic=1; return 1;
}

static int binary_index(unsigned op) {
    static const int map[]={ABC_JOP_ADD,ABC_JOP_SUB,ABC_JOP_MUL,ABC_JOP_DIVU,ABC_JOP_DIVS,ABC_JOP_REMU,ABC_JOP_REMS,ABC_JOP_AND,ABC_JOP_OR,ABC_JOP_XOR,ABC_JOP_SHL,ABC_JOP_SHR,ABC_JOP_SAR,ABC_JOP_EQ,ABC_JOP_NE,ABC_JOP_LT,ABC_JOP_LE,ABC_JOP_LTU,ABC_JOP_LEU};
    unsigned pair=op-ABC_OPERATION_ADD; return pair<sizeof map/sizeof map[0]?map[pair]:-1;
}
static int binary32_index(int op) {
    switch(op) { case ABC_JOP_ADD:return ABC_J32_ADD; case ABC_JOP_SUB:return ABC_J32_SUB; case ABC_JOP_MUL:return ABC_J32_MUL;
    case ABC_JOP_AND:return ABC_J32_AND; case ABC_JOP_OR:return ABC_J32_OR; case ABC_JOP_XOR:return ABC_J32_XOR; default:return -1; }
}
static int follows_zx32(const Compiler *c,uint32_t pc,unsigned stack) {
    return pc<c->module->code_size && !c->block[pc] && c->module->code[pc]==(stack==JS_B?OP_ZX32_B:OP_ZX32_A);
}

typedef struct { Compiler *compiler; abc_symbolic_machine *machine; } NativeSymbolicSink;

static int native_capture(void *opaque,uint32_t pc,abc_symbolic_value *value) {
    NativeSymbolicSink *sink=opaque;sink->compiler->current_pc=pc;
    return materialize(sink->compiler,sink->machine->context,value)>=0;
}
static int native_emit_binary(void *opaque,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        JValue left,JValue right,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; int bi=binary_index(opcode),b32=binary32_index(bi);
    uint32_t next=origin+abc_instruction_length(c->module->code+origin);
    int u32=follows_zx32(c,next,destination)&&b32>=0;
    if(folded) {
        if(u32) { result->constant=(uint32_t)result->constant; sink->machine->extra_advance=abc_instruction_length(c->module->code+next); }
        return 1;
    }
    JValue *dst=top(x,destination,0),*other=top(x,destination==JS_A?JS_B:JS_A,0);
    int rd=writable(c,x,dst);
    if(rd<0) goto failed;
    int rs=materialize_mask(c,x,other,1u<<(unsigned)rd);
    if(rs<0) goto failed;
    uint64_t op_error=(bi>=ABC_JOP_DIVU&&bi<=ABC_JOP_REMS)?
        (uint64_t)ABC_ABORT|(UINT64_C(1)<<8)|((uint64_t)origin<<16):0;
    unsigned stencil=u32?ABC_FORM_BINARY32(b32,rd,rs):ABC_FORM_BINARY(bi,rd,rs);
    if(!place(c,stencil,op_error,NULL)) goto failed;
    *result=*dst; result->kind=VK_REG; result->reg=(uint32_t)rd;
    if(u32)sink->machine->extra_advance=abc_instruction_length(c->module->code+next);
    (void)left; (void)right; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int unary_index(unsigned op);
static int native_emit_unary(void *opaque,uint32_t origin,unsigned opcode,unsigned stack,int folded,
        JValue input,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin;if(folded)return 1;
    /* Kind-only raw identity: the verified value retains its existing placement. */
    if(opcode==ABC_OPERATION_F2BITS||opcode==ABC_OPERATION_BITS2F) { *result=input;return 1; }
    int ui=unary_index(opcode); JValue *value=top(x,stack,0); int reg=writable(c,x,value);
    if(ui<0||reg<0||!place(c,ABC_FORM_UNARY(ui,reg),0,NULL)) {
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
    unsigned fi=opcode-ABC_OPERATION_FADD; JValue *dst=top(x,destination,0);
    JValue *other=top(x,destination==JS_A?JS_B:JS_A,0); int rd=writable(c,x,dst);
    if(rd<0)goto failed; int rs=materialize_mask(c,x,other,1u<<(unsigned)rd);
    if(rs<0||!place(c,ABC_FORM_FLOAT_BINARY(fi,rd,rs),0,NULL))goto failed;
    *result=*dst; result->kind=VK_REG; result->reg=(uint32_t)rd;
    (void)left; (void)right; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int native_emit_float_unary(void *opaque,uint32_t origin,unsigned opcode,unsigned selected_stack,int folded,int trapped,
        JValue input,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; uint64_t error=(uint64_t)ABC_ABORT|(UINT64_C(3)<<8)|((uint64_t)origin<<16);
    if(trapped)return place(c,ABC_FORM_ABORT,error,NULL);
    if(folded)return 1;
    JValue *value=top(x,selected_stack,0); int reg=writable(c,x,value); unsigned fi=opcode-ABC_OPERATION_FNEG;
    if(reg<0||!place(c,ABC_FORM_FLOAT_UNARY(fi,reg),(opcode==ABC_OPERATION_F2IS||opcode==ABC_OPERATION_F2IU)?error:0,NULL))goto failed;
    *result=*value; result->kind=VK_REG; result->reg=(uint32_t)reg;
    (void)input; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int native_emit_pow(void *opaque,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        JValue left,JValue right,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; if(folded)return 1; JValue *lhs=top(x,destination,0),*rhs=top(x,destination==JS_A?JS_B:JS_A,0);
    int ra=writable(c,x,lhs); if(ra<0)goto failed; int rb=materialize_mask(c,x,rhs,1u<<(unsigned)ra);
    uint64_t error=(uint64_t)ABC_ABORT|(UINT64_C(4)<<8)|((uint64_t)origin<<16);
    if(rb<0||!place(c,opcode==ABC_OPERATION_POW?ABC_FORM_POW(ra,rb):ABC_FORM_POWS(ra,rb),error,NULL))goto failed;
    *result=*lhs; result->kind=VK_REG; result->reg=(uint32_t)ra;
    (void)destination; (void)left; (void)right; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int native_emit_check(void *opaque,uint32_t origin,unsigned opcode,unsigned selected_stack,int known,int trapped,JValue input) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin; uint64_t error=(uint64_t)ABC_ABORT|(UINT64_C(3)<<8)|((uint64_t)origin<<16);
    if(trapped)return place(c,ABC_FORM_ABORT,error,NULL);
    if(known)return 1; JValue *value=top(x,selected_stack,0); int reg=materialize(c,x,value);
    if(reg>=0&&place(c,ABC_FORM_CHECK(opcode-ABC_OPERATION_CHKU8,reg),error,NULL))return 1;
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    (void)input; return 0;
}
static int unary_index(unsigned op) {
    static const int map[]={ABC_JUN_NEG,ABC_JUN_NOT,ABC_JUN_LNOT,ABC_JUN_ZX32,ABC_JUN_SX32,ABC_JUN_ZX8,ABC_JUN_ZX16};
    unsigned pair=op-ABC_OPERATION_NEG; return pair<sizeof map/sizeof map[0]?map[pair]:-1;
}
static int immediate_index(unsigned op) {
    unsigned pair=op-ABC_OPERATION_ADDI; return pair<=ABC_JIMM_SAR?(int)pair:-1;
}
static int native_emit_immediate(void *opaque,uint32_t origin,unsigned opcode,unsigned stack,uint64_t immediate,
        int folded,JValue input,JValue *result) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin;if(folded)return 1; int ii=immediate_index(opcode); JValue *value=top(x,stack,0); int reg=writable(c,x,value);
    uint32_t next=origin+abc_instruction_length(c->module->code+origin);
    /* Low-result truncation commutes with these arithmetic/bitwise operations
       and left shift, but not with right shift: high input bits remain observable.
       Keep SHRI/SARI full-width and let the following ZX32 execute separately. */
    int u32=ii>=0&&ii<=ABC_JIMM_SHL&&follows_zx32(c,next,stack);
    if(ii<0||reg<0)goto failed; unsigned stencil; uint64_t patched=immediate;
    if(ii>=ABC_JIMM_SHL&&immediate>=(uint64_t)(u32?32:64)) {
        if(ii==ABC_JIMM_SAR) { stencil=u32?ABC_FORM_IMMEDIATE32(ii,reg):ABC_FORM_IMMEDIATE(ii,reg); patched=u32?31:63; }
        else { stencil=ABC_FORM_CONST(reg); patched=0; }
    } else stencil=u32?ABC_FORM_IMMEDIATE32(ii,reg):ABC_FORM_IMMEDIATE(ii,reg);
    if(!place(c,stencil,patched,NULL))goto failed;
    *result=*value; result->kind=VK_REG; result->reg=(uint32_t)reg;
    if(u32)sink->machine->extra_advance=abc_instruction_length(c->module->code+next);
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
    c->current_pc=origin;if(folded)return 1;
    abc_decoded_instruction instruction;abc_decode_instruction(c->module->code+origin,c->module->code_size-origin,&instruction);
    unsigned which=opcode-ABC_OPERATION_ADDC,depth=instruction.operands[0];
    JValue *value=top(x,stack,0),*rhs=top(x,JS_C,depth); int rd=writable(c,x,value);
    if(rd<0)goto failed; int rs=materialize_mask(c,x,rhs,1u<<(unsigned)rd);
    uint32_t next=origin+instruction.length; int u32=follows_zx32(c,next,stack);
    unsigned stencil=u32?ABC_FORM_BINARY32(opc32[which],rd,rs):ABC_FORM_BINARY(opc[which],rd,rs);
    if(which>=4||rs<0||!place(c,stencil,0,NULL))goto failed;
    *result=*value; result->kind=VK_REG; result->reg=(uint32_t)rd;
    if(u32)sink->machine->extra_advance=abc_instruction_length(c->module->code+next);
    (void)folded; (void)left; (void)right; return 1;
failed:
    if(c->status==ABC_OK)c->status=abc_fail(c->error,ABC_NOMEM,origin,"native symbolic sink emission failed");
    return 0;
}
static int load_kind(const abc_instruction_metadata *metadata) {
    unsigned width=metadata->memory_width;
    if(width==1)return 0; if(width==2)return 1; if(width==4)return metadata->sign_extend?3:2; return width==8?4:-1;
}
static int store_kind(unsigned width) { return width==1?0:width==2?1:width==4?2:width==8?3:-1; }
static int native_emit_memory(void *opaque,uint32_t origin,abc_symbolic_memory *memory) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;
    const uint8_t *p=c->module->code+origin;
    const abc_instruction_metadata *mo=abc_instruction_info(p);c->current_pc=origin;
    if(mo->memory_action==M_ALLOC) {
        unsigned cells=memory->cells;int32_t start=x->c_bias+(int32_t)x->n[JS_C]-x->c_origin;
        const abc_exec_operands operands={.value={cells,(uint64_t)((int64_t)start*8)},.target=ABC_EXEC_NO_LABEL};
        if(cells&&(!ensure_capacity(c,x,JS_C,(int64_t)x->c_bias+x->n[JS_C]-x->c_origin+cells,(uint64_t)ABC_STACK|((uint64_t)origin<<16))||!emit_form(c,ABC_FORM_CALLOC,&operands)))goto failed;
    } else if(mo->memory_action==M_FREE) {
        /* The generated transfer owns the C-stack contraction. */
    } else if(mo->memory_action==M_FLOAD) {
        unsigned s=memory->stack;int r=free_reg(c,x),lk=load_kind(mo);
        int32_t off=(x->c_bias+(int32_t)x->n[JS_C]-x->c_origin)*8-(int32_t)abc_u16(p+1);
        if(r<0||lk<0||!place(c,ABC_FORM_FRAME_LOAD(lk,r),(uint64_t)(int64_t)off,NULL))goto failed;
        memory->result=reg_value((unsigned)r,s,(int32_t)x->n[s]);
    } else if(mo->memory_action==M_FSTORE) {
        int r=materialize(c,x,&memory->first),sk=store_kind(mo->memory_width);
        int32_t off=(x->c_bias+(int32_t)x->n[JS_C]-x->c_origin)*8-(int32_t)abc_u16(p+1);
        if(r<0||sk<0||!place(c,ABC_FORM_FRAME_STORE(sk,r),(uint64_t)(int64_t)off,NULL))goto failed;
    } else if(mo->memory_action==M_FADDR) {
        unsigned s=memory->stack;int r=free_reg(c,x);int32_t off=(x->c_bias+(int32_t)x->n[JS_C]-x->c_origin)*8-(int32_t)abc_u16(p+1);
        if(r<0||!place(c,ABC_FORM_FRAME_ADDR(r),(uint64_t)(int64_t)off,NULL))goto failed;memory->result=reg_value((unsigned)r,s,(int32_t)x->n[s]);
    } else if(mo->memory_action==M_GLOAD) {
        unsigned s=memory->stack;int r=free_reg(c,x),lk=load_kind(mo);uint64_t address=(uint64_t)(uintptr_t)c->image_base+abc_u32(p+1);
        if(!c->image_base||r<0||lk<0||!place(c,ABC_FORM_GLOBAL_LOAD(lk,r),address,NULL))goto failed;memory->result=reg_value((unsigned)r,s,(int32_t)x->n[s]);
    } else if(mo->memory_action==M_GSTORE) {
        int r=materialize(c,x,&memory->first),sk=store_kind(mo->memory_width);uint64_t address=(uint64_t)(uintptr_t)c->image_base+abc_u32(p+1);
        if(!c->image_base||r<0||sk<0||!place(c,ABC_FORM_GLOBAL_STORE(sk,r),address,NULL))goto failed;
    } else if(mo->memory_action==M_GADDR) {
        unsigned s=memory->stack;int r=free_reg(c,x);uint64_t address=(uint64_t)(uintptr_t)c->image_base+abc_u32(p+1);
        if(!c->image_base||r<0||!place(c,ABC_FORM_GLOBAL_ADDR(r),address,NULL))goto failed;memory->result=reg_value((unsigned)r,s,(int32_t)x->n[s]);
    } else if(mo->memory_action==M_PLOAD) {
        JValue value=memory->first;int r=writable(c,x,top(x,memory->stack,0)),lk=load_kind(mo);
        if(r<0||lk<0||!place(c,ABC_FORM_MEM_LOAD(lk,r),abc_u16(p+1),NULL))goto failed;value.kind=VK_REG;value.reg=(uint32_t)r;memory->result=value;
    } else if(mo->memory_action==M_PSTORE) {
        JValue address=memory->first,value=memory->second;int ra=materialize(c,x,&address);if(ra<0)goto failed;
        int rv=materialize_mask(c,x,&value,1u<<(unsigned)ra),sk=store_kind(mo->memory_width);
        if(rv<0||sk<0||!place(c,ABC_FORM_MEM_STORE(sk,ra,rv),abc_u16(p+1),NULL))goto failed;
    } else if(mo->memory_action==M_XLOAD||mo->memory_action==M_INDEX) {
        JValue address=memory->first,index=memory->second;int ra=writable(c,x,top(x,memory->stack,0));if(ra<0)goto failed;
        int ri=materialize_mask(c,x,&index,1u<<(unsigned)ra);if(ri<0||!place(c,ABC_FORM_INDEX(ra,ri),mo->memory_action==M_INDEX?abc_u16(p+1):mo->memory_width,NULL))goto failed;
        if(mo->memory_action==M_XLOAD){int lk=load_kind(mo);if(lk<0||!place(c,ABC_FORM_MEM_LOAD(lk,ra),0,NULL))goto failed;}
        address.kind=VK_REG;address.reg=(uint32_t)ra;memory->result=address;
    } else if(mo->memory_action==M_COPY) {
        JValue dst=memory->first,src=memory->second;int rd=materialize(c,x,&dst);if(rd<0)goto failed;
        int rs=materialize_mask(c,x,&src,1u<<(unsigned)rd);uint32_t bytes=abc_u32(p+1);
        if(rs<0||!place_memory_copy(c,(unsigned)rd,(unsigned)rs,bytes))goto failed;
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
    return continuations<ABC_EXECUTION_VERSION_LIMIT;
}
static Version *version_for(Compiler *c,uint32_t pc,const Context *in) {
    unsigned count=0; for(Version *v=c->versions[pc];v;v=v->next) {
        if(generic_context_equal(&v->in,in)) return v;
        if(context_equal(&v->in,in)) { int accepts=1; for(unsigned s=0;s<3;s++) accepts&=in->limit[s]>=v->in.limit[s]; if(accepts) return v; }
        if(context_family_equal(&v->in,in)) count++;
    }
    if(count>=ABC_EXECUTION_VERSION_LIMIT) { c->status=abc_fail(c->error,ABC_INVALID,pc,"compiled block version limit reached without compatible generic context"); return NULL; }
    Version *v=calloc(1,sizeof *v); if(!v || !context_copy(&v->in,in)) { free(v); c->status=abc_fail(c->error,ABC_NOMEM,pc,"block version allocation failed"); return NULL; }
    v->pc=pc;v->owner=c;
    if(!emitted(c,c->emitter->ops->label(c->emitter,&v->entry,pc,c->error))){context_free(&v->in);free(v);return NULL;}
    v->body=v->entry;
    if(c->lazy&&(!emitted(c,c->emitter->ops->label(c->emitter,&v->body,pc,c->error))||
       !emitted(c,c->emitter->ops->lazy_entry(c->emitter,v->entry,v->body,v,lazy_prepare,pc,c->error)))){context_free(&v->in);free(v);return NULL;}
    v->next=c->versions[pc]; c->versions[pc]=v;
    if(!c->lazy){if(!grow((void **)&c->queue,&c->qcap,c->nq+1,sizeof *c->queue)) { c->status=abc_fail(c->error,ABC_NOMEM,pc,"compiler queue allocation failed"); return NULL; }c->queue[c->nq++]=v;} return v;
}
static Version *edge(Compiler *c,uint32_t from,uint32_t target,Context *x) {
    if(target<=from) for(unsigned s=0;s<3;s++) for(uint32_t i=0;i<x->n[s];i++) {
        JValue *v=&x->s[s][i]; if(v->kind==VK_CONST) {
            /* Weaken knowledge, not placement. The cache may spill under real
               pressure; a backedge alone does not require a memory home.
               Construct a canonical register descriptor: materialize() changes
               kind/placement but retains the old constant payload. */
            int reg=materialize(c,x,v); if(reg<0)return NULL;
            *v=reg_value((unsigned)reg,v->dst_stack,v->dst_home);
        }
    }
    unsigned versions=0; for(Version *v=c->versions[target];v;v=v->next) versions+=context_family_equal(&v->in,x);
    if(versions>=ABC_EXECUTION_VERSION_LIMIT-1 && !conform_generic(c,x)) return NULL;
    return version_for(c,target,x);
}

static int discover_blocks(Compiler *c) {
    const abc_module *m=c->module;
    for(uint32_t f=0;f<m->function_count;f++) c->block[m->functions[f].entry]=1;
    for(uint32_t f=0;f<m->function_count;f++) for(uint32_t pc=m->functions[f].entry;pc<m->functions[f].end;) {
        abc_decoded_instruction instruction;
        abc_decode_instruction(m->code+pc,m->functions[f].end-pc,&instruction);
        const uint8_t *operands=instruction.operands;
        unsigned kind=instruction.metadata->kind,operation=instruction.metadata->operation;
        uint32_t next=pc+instruction.length;
        if(kind==K_BRANCH || kind==K_BRI || kind==K_JMP32) {
            int32_t displacement=kind==K_JMP32?abc_i32(operands):abc_i16(operands+(kind==K_BRI?1:0));
            uint32_t target=(uint32_t)((int64_t)next+displacement);
            c->block[target]=1;
            if(operation!=ABC_OPERATION_JMP&&operation!=ABC_OPERATION_JMP32)c->block[next]=1;
        } else if(kind==K_SWITCH) {
            for(unsigned j=0;j<abc_u16(operands);j++)
                c->block[(uint32_t)((int64_t)next+abc_i32(operands+2+4*j))]=1;
            c->block[next]=1;
        }
        if(kind==K_CALL && next<m->functions[f].end)c->block[next]=1;
        pc=next;
    }
    return 1;
}
static int compile_version(Compiler *c,Version *v);
static abc_status lazy_prepare(void *state,abc_error *error){
    Version *v=state;Compiler *c=v->owner;c->error=error;c->status=ABC_OK;c->current_pc=v->pc;
    if(v->compiled)return ABC_OK;
    if(!compile_version(c,v)&&c->status==ABC_OK)c->status=abc_fail(error,ABC_INVALID,v->pc,"lazy block compilation failed");
    if(c->status==ABC_OK){abc_exec_storage storage=c->emitter->ops->storage(c->emitter);c->image->compiled_versions++;c->image->code_size=storage.body_bytes;c->image->storage_size=storage.allocation_bytes;c->image->virtual_calls=c->virtual_calls;c->image->virtual_returns=c->virtual_returns;c->image->virtual_tails=c->virtual_tails;c->image->real_calls=c->real_calls;}
    return c->status;
}
static int emit_jump(Compiler *c,Version *target) { return target && place(c,ABC_FORM_JUMP,0,target); }

static int local_branch(Compiler *c,unsigned stencil,Fixup *fix);
static void bind_local(Compiler *c,const Fixup *fix);
static int edge_emits_code(const Compiler *c,uint32_t from,uint32_t target,const Context *x) {
    if(target<=from)for(unsigned s=0;s<3;s++)for(uint32_t i=0;i<x->n[s];i++)if(x->s[s][i].kind==VK_CONST)return 1;
    unsigned versions=0;for(Version *v=c->versions[target];v;v=v->next)versions+=context_family_equal(&v->in,x);
    return versions>=ABC_EXECUTION_VERSION_LIMIT-1;
}
/* Publishing registers to distinct canonical homes is safe on either edge:
   it changes neither register bits nor a live home source. Representation
   changes, constants and parallel home copies must wait for the decision. */
static int edge_spills_only(const Context *x) {
    for(unsigned s=0;s<3;s++)for(uint32_t i=0;i<x->n[s];i++){
        const JValue *v=&x->s[s][i];int32_t home=s==JS_C?x->c_bias+(int32_t)i-x->c_origin:(int32_t)i;
        if(v->kind==VK_CONST)return 0;
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
                Fixup skip;ok=local_branch(c,ABC_FORM_BRANCH(ABC_JBR_NE,reg,ri),&skip)&&emit_jump(c,edge(c,origin,target,&taken));
                if(ok)bind_local(c,&skip);
            }else{
                Version *tv=edge(c,origin,target,&taken);ok=tv&&place(c,ABC_FORM_BRANCH(ABC_JBR_EQ,reg,ri),0,tv);
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
    /* The shared branch has consumed these cells, but both captured inputs
       remain live until the comparison. Do not reuse the right input's
       register while materializing the left (which may be a constant/home). */
    JValue left=control->left,right=control->right;
    unsigned right_live=control->kind!=ABC_SYM_CONTROL_ZERO&&right.kind==VK_REG?1u<<right.reg:0;
    int rl=materialize_mask(c,x,&left,right_live),rr=-1;
    if(rl<0)return 0;
    if(control->kind!=ABC_SYM_CONTROL_ZERO) { rr=materialize_mask(c,x,&right,1u<<(unsigned)rl); if(rr<0)return 0; }
    unsigned stencil;
    if(control->kind==ABC_SYM_CONTROL_ZERO)stencil=control->relation==ABC_SYM_EQ?ABC_FORM_JZ(rl):ABC_FORM_JNZ(rl);
    else if(control->kind==ABC_SYM_CONTROL_FLOAT) {
        unsigned operation=control->relation==ABC_SYM_LT?0:
            control->relation==ABC_SYM_LE?1:
            control->relation==ABC_SYM_EQ?2:UINT_MAX;
        if(operation==UINT_MAX)return 0;
        stencil=ABC_FORM_FLOAT_BRANCH(operation,rl,rr);
    }
    else stencil=ABC_FORM_BRANCH(control->relation,control->reverse?rr:rl,control->reverse?rl:rr);
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
    return place(c,ABC_FORM_ABORT,error,NULL);
}
/* Only use after result publication, when cached frame values are dead.
   Source and destination are distinct private operand regions, not scratch. */
static int copy_return_vector(Compiler *c,unsigned source,unsigned destination,uint32_t results) {
    if(source==destination)return 1;
    for(uint32_t i=0;i<results;i++)
        if(!place(c,ABC_FORM_LOAD(source,0),(uint64_t)i*8,NULL)||
           !place(c,ABC_FORM_STORE(destination,0),(uint64_t)i*8,NULL))return 0;
    return 1;
}
static int native_emit_halt(void *opaque,uint32_t origin,unsigned source_stack) {
    NativeSymbolicSink *sink=opaque; Compiler *c=sink->compiler; Context *x=sink->machine->context;
    c->current_pc=origin;
    for(uint32_t i=0;i<x->n[source_stack];i++) { JValue *value=&x->s[source_stack][i];
        value->dst_stack=(uint8_t)source_stack; value->dst_home=(int32_t)i; if(!save_value(c,x,value))return 0; }
    return copy_return_vector(c,source_stack,JS_A,x->n[source_stack])&&place(c,ABC_FORM_RETURN_OK,0,NULL);
}

/* Local references address an arm or resume point inside this version. Bind
   them before publication; never retain the temporary target as a version. */
static int local_reference(Compiler *c,unsigned stencil,uint64_t immediate,Fixup *fix) {
    if(!emitted(c,c->emitter->ops->label(c->emitter,fix,c->current_pc,c->error)))return 0;
    const abc_exec_operands operands={.value={immediate},.target=*fix};
    return emit_form(c,stencil,&operands);
}
static int local_branch(Compiler *c,unsigned stencil,Fixup *fix) {
    return local_reference(c,stencil,0,fix);
}
static void bind_local(Compiler *c,const Fixup *fix) { (void)emitted(c,c->emitter->ops->bind(c->emitter,*fix,c->current_pc,c->error)); }
static int native_emit_foreign(void *opaque,uint32_t pc,abc_symbolic_foreign *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;const abc_extern *ext=&c->module->externs[effect->index];
    unsigned selected_stack=effect->selected_stack;
    uint32_t argument_base=x->n[selected_stack]-effect->arguments;
    if(c->release_glue) {
        int id=abc_primitive_index(ext->name);
        if(id==ABC_PRIMITIVE_OWNER_DATA||id==ABC_PRIMITIVE_OWNER_INITIALIZED||id==ABC_PRIMITIVE_OWNER_ENQUEUE) {
            JValue *input=&x->s[selected_stack][argument_base];
            int reg=effect->results?writable(c,x,input):materialize(c,x,input);if(reg<0)return 0;
            uintptr_t callee=id==ABC_PRIMITIVE_OWNER_DATA?(uintptr_t)abc_owner_payload:
                id==ABC_PRIMITIVE_OWNER_INITIALIZED?(uintptr_t)abc_owner_initialized:(uintptr_t)abc_owner_release;
            unsigned form=id==ABC_PRIMITIVE_OWNER_DATA?ABC_FORM_RELEASE_DATA(reg):
                id==ABC_PRIMITIVE_OWNER_INITIALIZED?ABC_FORM_RELEASE_PROGRESS(reg):ABC_FORM_RELEASE_ENQUEUE(reg);
            if(!place(c,form,callee,NULL))return 0;
            if(effect->results)effect->result[0]=reg_value((unsigned)reg,selected_stack,(int32_t)argument_base);
            return 1;
        }
        if(id!=ABC_PRIMITIVE_OWNER_RELEASE_FIELD||effect->arguments!=3||effect->results)
            return emitted(c,abc_fail(c->error,ABC_ARGUMENTS,pc,"invalid direct release primitive"));
        JValue *offset=&x->s[selected_stack][argument_base+1],*ordinal=&x->s[selected_stack][argument_base+2];
        if(offset->kind!=VK_CONST||ordinal->kind!=VK_CONST||offset->constant%sizeof(abc_owner *)||!ordinal->constant)
            return emitted(c,abc_fail(c->error,ABC_ARGUMENTS,pc,"release field needs constant aligned offset and ordinal"));
        int reg=materialize(c,x,&x->s[selected_stack][argument_base]);if(reg<0)return 0;
        const abc_exec_operands operands={.value={(uintptr_t)abc_owner_release_field,offset->constant,ordinal->constant},.target=ABC_EXEC_NO_LABEL};
        return emit_form(c,ABC_FORM_RELEASE_FIELD(reg),&operands);
    }
    for(uint32_t j=argument_base;j<x->n[selected_stack];j++){
        JValue *value=&x->s[selected_stack][j];value->dst_stack=(uint8_t)selected_stack;value->dst_home=(int32_t)j;
        if(!save_value(c,x,value))return 0;*value=rehome_value(*value,selected_stack,(int32_t)j);
    }
    if(!flush_context(c,x))return 0;abc_foreign_address target=abc_foreign_lookup(c->vm,ext->name);uint64_t error=(uint64_t)ABC_INVALID|((uint64_t)pc<<16);
    return (target||abc_primitive_index(ext->name)>=0)&&place_fcall(c,ABC_FORM_FCALL(selected_stack,effect->results),argument_base,ext,target,error);
}

static int native_emit_edge(void *opaque,uint32_t origin,uint32_t target) {
    NativeSymbolicSink *sink=opaque;return emit_jump(sink->compiler,edge(sink->compiler,origin,target,sink->machine->context));
}

static int transport_return_vector(Compiler *c,unsigned destination,uint32_t results);

static int native_emit_indirect(void *opaque,uint32_t pc,abc_symbolic_indirect *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;
    unsigned selected_stack=effect->argument_stack,opposite_stack=selected_stack==JS_A?JS_B:JS_A;
    unsigned arguments=effect->arguments;
    uint32_t argument_base=x->n[selected_stack]-arguments,target_home=x->n[opposite_stack]-1;
    uint32_t abase=selected_stack==JS_A?argument_base:target_home;
    uint32_t bbase=selected_stack==JS_B?argument_base:target_home;
    int32_t ctop=x->c_bias+(int32_t)x->n[JS_C]-x->c_origin;
    int32_t argument_start=effect->tail?ctop-(int32_t)effect->frame_cells:ctop+1;
    int64_t a_bytes=(int64_t)abase*8,b_bytes=(int64_t)bbase*8;
    int64_t c_bytes=((int64_t)argument_start+arguments)*8;
    /* Constants need publication too: the resolver/transport reads physical
       arguments, whereas flush_context deliberately retains symbolic constants. */
    for(unsigned i=0;i<arguments;i++){
        JValue *argument=&x->s[selected_stack][argument_base+i];
        argument->dst_stack=(uint8_t)selected_stack;argument->dst_home=(int32_t)(argument_base+i);
        if(!save_value(c,x,argument))return 0;
        *argument=rehome_value(*argument,selected_stack,(int32_t)(argument_base+i));
    }
    JValue *target=&x->s[opposite_stack][target_home];
    target->dst_stack=(uint8_t)opposite_stack;target->dst_home=(int32_t)target_home;
    if(!save_value(c,x,target))return 0;
    *target=rehome_value(*target,opposite_stack,(int32_t)target_home);
    /* Preserve live values before calling the resolver. After this
       boundary r0 holds only the checked entry and r1 is a transport scratch;
       neither is permanently reserved in the symbolic allocation state. */
    if(!flush_context(c,x)||
       !place(c,ABC_FORM_LOAD(opposite_stack,0),(uint64_t)target_home*8,NULL)||
       !place_indirect_resolution(c,pc,a_bytes,b_bytes,c_bytes))return 0;
    for(unsigned i=0;i<arguments;i++){
        int64_t destination=((int64_t)argument_start+arguments-1-i)*8;
        if(!place(c,ABC_FORM_LOAD(selected_stack,1),(uint64_t)(argument_base+i)*8,NULL)||
           !place(c,ABC_FORM_STORE(JS_C,1),(uint64_t)destination,NULL))return 0;
    }
    if(effect->tail){
        /* The existing continuation cell is untouched. Its caller restores C
           from that cell, not from this callee's possibly different arity. */
        return rebase_frame(c,a_bytes,b_bytes,c_bytes)&&place(c,ABC_FORM_CONTINUE(0),0,NULL);
    }
    Fixup resume;
    if(!local_reference(c,ABC_FORM_STORE_LABEL,(uint64_t)((int64_t)ctop*8),&resume)||
       !rebase_frame(c,a_bytes,b_bytes,c_bytes)||!place(c,ABC_FORM_CONTINUE(0),0,NULL))return 0;
    bind_local(c,&resume);
    if(effect->results!=1&&!transport_return_vector(c,selected_stack,effect->results))return 0;
    if(!rebase_frame(c,-a_bytes,-b_bytes,-(int64_t)ctop*8))return 0;
    for(unsigned i=0;i<effect->results;i++)effect->result[i]=effect->results==1?
        reg_value(0,selected_stack,(int32_t)(argument_base+i)):
        home_value(selected_stack,(int32_t)(argument_base+i));
    c->real_calls++;return 1;
}

/* At a real-call resume all caller values have homes and the callee's
   register values are dead, except r0 for the uniform single-result ABI.
   General vectors stay in their source bank until this direct transport. */
static int transport_return_vector(Compiler *c,unsigned destination,uint32_t results) {
    if(!results)return 1;
    Fixup already_placed;
    if(!local_branch(c,destination==JS_A?ABC_FORM_JZ(2):ABC_FORM_JNZ(2),&already_placed))return 0;
    unsigned source=destination==JS_A?JS_B:JS_A;
    if(!copy_return_vector(c,source,destination,results))return 0;
    bind_local(c,&already_placed);return 1;
}
static int native_emit_call(void *opaque,uint32_t pc,abc_symbolic_call *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;
    int fi=abc_find_function(c->module,effect->target);
    unsigned n=effect->arguments,selected_stack=effect->destination;
    uint32_t argument_base=x->n[selected_stack]-n;
    uint32_t abase=effect->continuation.abase,bbase=effect->continuation.bbase;
    int32_t ctop=x->c_bias+(int32_t)x->n[JS_C]-x->c_origin;
    if(fi<0){c->status=abc_fail(c->error,ABC_INVALID,pc,"native direct-call sink rejected target");return 0;}
    const abc_function *function=&c->module->functions[fi];
    uint64_t error=(uint64_t)ABC_STACK|((uint64_t)pc<<16);
    int virtualize=inline_candidate(c,x,pc,effect->target,&effect->continuation);
    if(!ensure_capacity(c,x,JS_A,(int64_t)abase+function->max_a,error)||
       !ensure_capacity(c,x,JS_B,(int64_t)bbase+function->max_b,error)||
       !ensure_capacity(c,x,JS_C,(int64_t)x->c_bias+x->n[JS_C]-x->c_origin+(virtualize?0:1)+function->max_c,error))return 0;
    if(virtualize){effect->virtualize=1;c->virtual_calls++;return 1;}
    Version *callee=NULL;
    int register_result=function->results==1;
    if(c->recursive[fi]) {
        int pass_register=n==1,argument_register=-1;
        if(pass_register){argument_register=materialize(c,x,&x->s[selected_stack][argument_base]);if(argument_register<0)return 0;}
        if(pass_register)for(unsigned stack=0;stack<3;stack++)for(uint32_t i=0;i<x->n[stack];i++){
            if(stack==selected_stack&&i==argument_base)continue;JValue *value=&x->s[stack][i];
            if(value->kind==VK_HOME&&(value->stack!=value->dst_stack||value->home!=value->dst_home))pass_register=0;
        }
        if(pass_register){
            uint32_t count=x->n[selected_stack];x->n[selected_stack]=argument_base;
            if(!flush_context(c,x)){x->n[selected_stack]=count;return 0;}x->n[selected_stack]=count;
            if(argument_register&&!place(c,ABC_FORM_MOV(0,(unsigned)argument_register),0,NULL))return 0;
        }else{
            for(unsigned j=0;j<n;j++){
                JValue *argument=&x->s[selected_stack][argument_base+j];
                argument->dst_stack=(uint8_t)selected_stack;argument->dst_home=(int32_t)(argument_base+j);
                if(!save_value(c,x,argument))return 0;
                *argument=rehome_value(*argument,selected_stack,(int32_t)(argument_base+j));
            }
            if(!flush_context(c,x))return 0;
            for(unsigned j=c->register_count;j<n;j++)if(!place(c,ABC_FORM_LOAD(selected_stack,0),(uint64_t)(argument_base+j)*8,NULL)||
                !place(c,ABC_FORM_STORE(JS_C,0),(uint64_t)((int64_t)(ctop+(int32_t)n-(int32_t)j)*8),NULL))return 0;
            for(unsigned j=0;j<n&&j<c->register_count;j++)if(!place(c,ABC_FORM_LOAD(selected_stack,j),(uint64_t)(argument_base+j)*8,NULL))return 0;
        }
        Context entry={0};entry.c_origin=(int32_t)n;
        entry.limit[JS_A]=function->max_a;entry.limit[JS_B]=function->max_b;entry.limit[JS_C]=function->max_c-function->arguments;
        if(n){
            entry.s[JS_C]=malloc((size_t)n*sizeof *entry.s[JS_C]);
            if(!entry.s[JS_C]){c->status=abc_fail(c->error,ABC_NOMEM,pc,"native direct-call sink allocation failed");return 0;}
            entry.n[JS_C]=entry.cap[JS_C]=n;
            for(unsigned j=0;j<n;j++){
                int32_t home=-1-(int32_t)j;JValue value=j<c->register_count?reg_value(j,JS_C,home):home_value(JS_C,home);
                value.dst_stack=JS_C;value.dst_home=home;entry.s[JS_C][n-1-j]=value;
            }
        }
        callee=version_for(c,effect->target,&entry);context_free(&entry);if(!callee)return 0;
    }else{
        for(unsigned j=0;j<n;j++){
            JValue *argument=&x->s[selected_stack][argument_base+j];int reg=materialize(c,x,argument);
            if(reg<0||!place(c,ABC_FORM_STORE(JS_C,reg),(uint64_t)((int64_t)(ctop+(int32_t)n-(int32_t)j)*8),NULL))return 0;
        }
        if(!flush_context(c,x))return 0;callee=c->function_entries[fi];
        if(!callee){c->status=abc_fail(c->error,ABC_INVALID,pc,"native direct-call sink missing entry");return 0;}
    }
    int64_t a_bytes=(int64_t)abase*8,b_bytes=(int64_t)bbase*8,c_bytes=((int64_t)ctop+n+1)*8;
    Fixup resume;
    if(!local_reference(c,ABC_FORM_STORE_LABEL,(uint64_t)((int64_t)ctop*8),&resume)||
       !rebase_frame(c,a_bytes,b_bytes,c_bytes)||!emit_jump(c,callee))return 0;
    bind_local(c,&resume);
    if(!register_result&&!transport_return_vector(c,selected_stack,function->results))return 0;
    /* RET arrives with C at this call's continuation cell, independently of
       any changed argument count along a tail-call chain. */
    if(!rebase_frame(c,-a_bytes,-b_bytes,-(int64_t)ctop*8))return 0;
    c->real_calls++;
    for(uint32_t j=0;j<function->results;j++)effect->result[j]=register_result?
        reg_value(0,selected_stack,(int32_t)(argument_base+j)):home_value(selected_stack,(int32_t)(argument_base+j));
    return 1;
}

static int native_emit_tail(void *opaque,uint32_t pc,abc_symbolic_tail *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;int fi=abc_find_function(c->module,effect->target);
    if(fi<0||!c->versions[effect->target]){c->status=abc_fail(c->error,ABC_INVALID,pc,"native tail-call sink rejected target");return 0;}
    uint32_t abase=x->n[JS_A]-(effect->argument_stack==JS_A?effect->arguments:0);
    uint32_t bbase=x->n[JS_B]-(effect->argument_stack==JS_B?effect->arguments:0);
    uint32_t cbase=x->n[JS_C]-effect->frame_cells;int64_t coff=(int64_t)x->c_bias+cbase-x->c_origin;
    const abc_function *callee=&c->module->functions[fi];uint64_t error=(uint64_t)ABC_STACK|((uint64_t)pc<<16);
    if(!ensure_capacity(c,x,JS_A,(int64_t)abase+callee->max_a,error)||!ensure_capacity(c,x,JS_B,(int64_t)bbase+callee->max_b,error)||!ensure_capacity(c,x,JS_C,coff+callee->max_c,error))return 0;
    c->virtual_tails++;return 1;
}

static int native_emit_return(void *opaque,uint32_t pc,const abc_symbolic_return *effect) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;c->current_pc=pc;
    if(c->release_glue)return !effect->results&&place(c,ABC_FORM_RETURN_OK,0,NULL);
    if(!effect->terminal){c->virtual_returns++;return 1;}
    unsigned source_stack=effect->source_stack;
    if(effect->results==1){if(x->n[source_stack]!=1)return 0;JValue *value=&x->s[source_stack][0];int reg=materialize(c,x,value);if(reg<0||(reg&&!place(c,ABC_FORM_MOV(0,reg),0,NULL)))return 0;}
    else for(uint32_t i=0;i<x->n[source_stack];i++){
        JValue *value=&x->s[source_stack][i];value->dst_stack=(uint8_t)source_stack;value->dst_home=(int32_t)i;
        if(!save_value(c,x,value))return 0;
    }
    /* Values have been published: r0 holds every single result,
       r1 receives the existing C continuation, and r2 is now free for the
       explicit source tag. It was not reserved during ordinary execution.
       Normalize C to its existing continuation cell only for native transfer;
       the caller no longer needs the last callee's argument count. */
    int64_t return_offset=((int64_t)x->c_bias-x->c_origin-1)*8;
    Fixup host;
    if(!place(c,ABC_FORM_LOAD(JS_C,1),(uint64_t)return_offset,NULL)||
       !place(c,ABC_FORM_CONST(2),UINT32_MAX,NULL)||
       !local_branch(c,ABC_FORM_BRANCH(ABC_JBR_EQ,1,2),&host)||
       !rebase_frame(c,0,0,return_offset)||
       !place(c,ABC_FORM_CONST(2),source_stack,NULL)||
       !place(c,ABC_FORM_CONTINUE(1),0,NULL))return 0;
    bind_local(c,&host);
    /* Host entry has no operand prefixes. Its existing delivery bank is A;
       either private bank has the same host stack capacity. */
    if(effect->results==1){if(!place(c,ABC_FORM_STORE(JS_A,0),0,NULL))return 0;}
    else if(!copy_return_vector(c,source_stack,JS_A,effect->results))return 0;
    return place(c,ABC_FORM_RETURN_OK,0,NULL);
}

static int compile_version(Compiler *c,Version *v) {
    Context x; if(!context_copy(&x,&v->in)) return 0;
    if(!emitted(c,c->emitter->ops->bind(c->emitter,v->body,v->pc,c->error))){context_free(&x);return 0;}
    v->compiling=1;
    const uint8_t *code=c->module->code; uint32_t pc=v->pc; int live=1;
    while(live && pc<c->module->code_size) {
        if(pc!=v->pc && c->block[pc]) { Version *to=edge(c,pc-1,pc,&x); if(!emit_jump(c,to)) goto failed; break; }
        abc_symbolic_machine machine={.module=c->module,.code=code,.blocks=c->block,.pc=pc,.end=c->module->code_size,
            .context=&x,.error=c->error,.transfer_mask=ABC_SYM_TRANSFER_STACK|ABC_SYM_TRANSFER_VALUE|ABC_SYM_TRANSFER_CONTROL|ABC_SYM_TRANSFER_EFFECT};
        NativeSymbolicSink native_sink={c,&machine}; machine.sink=&native_sink;machine.capture=native_capture;
        machine.emit_binary=native_emit_binary; machine.emit_float_binary=native_emit_float_binary;
        machine.emit_pow=native_emit_pow; machine.emit_check=native_emit_check;
        machine.emit_unary=native_emit_unary; machine.emit_float_unary=native_emit_float_unary;
        machine.emit_immediate=native_emit_immediate; machine.emit_c_operand=native_emit_c_operand;
        machine.emit_control=native_emit_control; machine.emit_abort=native_emit_abort; machine.emit_halt=native_emit_halt;
        machine.emit_memory=native_emit_memory;machine.emit_return=native_emit_return;machine.emit_call=native_emit_call;machine.emit_indirect=native_emit_indirect;machine.emit_tail=native_emit_tail;
        machine.emit_foreign=native_emit_foreign;machine.emit_edge=native_emit_edge;
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

static void free_preparation(Compiler *c) {
    if(c->versions)for(size_t pc=0;pc<c->module->code_size;pc++){Version *v=c->versions[pc];while(v){Version *next=v->next;context_free(&v->in);free(v);v=next;}}
    free(c->block);free(c->versions);free(c->function_entries);free(c->recursive);free(c->queue);
}
void abc_execution_image_free(abc_execution_image *image) {
    if(!image)return;Compiler *c=image->lazy_state;if(c){free_preparation(c);free(c);}
    if(image->emitter)image->emitter->ops->destroy(image->emitter);
    free(image->entries);free(image);
}
abc_status abc_residualize_module(const abc_module *m,uint8_t *image_base,const abc_vm *vm,abc_execution_mode mode,abc_execution_image **out,abc_error *e) {
    abc_clear(e); if(out) *out=NULL; if(!m||!vm||!out||(mode!=ABC_EXEC_COMPILED&&mode!=ABC_EXEC_LAZY&&mode!=ABC_EXEC_THREADED)) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid residualizer input");
    Compiler c={0}; c.module=m; c.vm=vm; c.image_base=image_base; c.error=e; c.status=ABC_OK;c.lazy=mode==ABC_EXEC_LAZY;
    c.block=calloc(m->code_size,1); c.versions=calloc(m->code_size,sizeof *c.versions); c.function_entries=calloc(m->function_count,sizeof *c.function_entries); c.recursive=calloc(m->function_count,1);
    if(!c.block||!c.versions||!c.function_entries||!c.recursive){free_preparation(&c);return abc_fail(e,ABC_NOMEM,UINT32_MAX,"residualizer allocation failed");}
    c.status=mode==ABC_EXEC_THREADED?abc_threaded_emitter_create(&c.emitter,e):abc_native_emitter_create(m->code_size,&c.emitter,e);
    if(c.status!=ABC_OK){free_preparation(&c);return c.status;}
    c.register_count=c.emitter->register_count;discover_blocks(&c);
    for(uint32_t f=0;f<m->function_count;f++) {
        uint8_t *seen=calloc(m->function_count,1); if(!seen) { c.status=abc_fail(e,ABC_NOMEM,m->functions[f].entry,"call graph allocation failed"); break; }
        c.recursive[f]=(uint8_t)abc_symbolic_reaches_function(m,(int)f,(int)f,seen); memset(seen,0,m->function_count);
        c.recursive[f]|=(uint8_t)abc_symbolic_has_unknown_call(m,(int)f,seen); free(seen);
    }
    void **entries=calloc(m->function_count,sizeof *entries);
    if(!entries)c.status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"execution entry allocation failed");
    for(uint32_t f=0;f<m->function_count&&c.status==ABC_OK;f++) {
        Context x={0}; const abc_function *fn=&m->functions[f]; uint32_t n=fn->arguments; x.c_origin=(int32_t)n;
        x.limit[JS_A]=fn->max_a; x.limit[JS_B]=fn->max_b; x.limit[JS_C]=fn->max_c-fn->arguments;
        if(n) { x.s[JS_C]=malloc((size_t)n*sizeof(JValue)); if(!x.s[JS_C]) { c.status=abc_fail(e,ABC_NOMEM,m->functions[f].entry,"entry context allocation failed"); break; } x.n[JS_C]=x.cap[JS_C]=n;
            for(uint32_t i=0;i<n;i++) x.s[JS_C][n-1-i]=home_value(JS_C,-1-(int32_t)i);
        }
        Version *v=version_for(&c,m->functions[f].entry,&x); context_free(&x); if(!v) break; c.function_entries[f]=v;
    }
    if(!c.lazy)while(c.qhead<c.nq&&c.status==ABC_OK) if(!compile_version(&c,c.queue[c.qhead++])&&c.status==ABC_OK) c.status=ABC_INVALID;
    if(c.status==ABC_OK)c.status=c.emitter->ops->publish(c.emitter,UINT32_MAX,e);
    abc_execution_image *image=NULL;
    if(c.status==ABC_OK) { image=calloc(1,sizeof *image); if(!image) c.status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"native image allocation failed"); }
    if(c.status==ABC_OK) {
        abc_exec_storage storage=c.emitter->ops->storage(c.emitter);
        image->emitter=c.emitter;image->code_size=storage.body_bytes;image->storage_size=storage.allocation_bytes;image->entries=entries;image->lazy=c.lazy;
        image->virtual_calls=c.virtual_calls; image->virtual_returns=c.virtual_returns; image->virtual_tails=c.virtual_tails; image->real_calls=c.real_calls;image->compiled_versions=c.qhead;
        for(uint32_t f=0;f<m->function_count;f++)image->entries[f]=(void *)c.emitter->ops->address(c.emitter,c.function_entries[f]->entry);
        if(c.lazy){Compiler *saved=malloc(sizeof *saved);if(!saved)c.status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"lazy compiler state allocation failed");else{*saved=c;saved->image=image;image->lazy_state=saved;for(size_t pc=0;pc<m->code_size;pc++)for(Version *v=saved->versions[pc];v;v=v->next)v->owner=saved;}}
        if(c.status==ABC_OK){*out=image;if(!c.lazy)c.emitter->ops->discard_preparation(c.emitter);}
    }
    if(c.status!=ABC_OK){free(image);free(entries);c.emitter->ops->destroy(c.emitter);}
    if(!c.lazy||c.status!=ABC_OK)free_preparation(&c);
    return c.status;
}

abc_status abc_compile_release(const abc_module *m,uint8_t *image_base,unsigned function,abc_release_code **out,abc_error *error) {
    *out=NULL;const abc_function *fn=&m->functions[function];
    Compiler c={.module=m,.image_base=image_base,.error=error,.status=ABC_OK,.register_count=7,.release_glue=1};
    /* r7 is the direct native ABI's runtime-context argument, not an ABC cell
     * or an allocator-created value. All value placement uses the same allocator. */
    c.block=calloc(m->code_size,1);c.versions=calloc(m->code_size,sizeof *c.versions);
    if(!c.block||!c.versions){free_preparation(&c);return abc_fail(error,ABC_NOMEM,fn->entry,"release preparation allocation failed");}
    c.status=abc_native_emitter_create(m->code_size,&c.emitter,error);
    if(c.status!=ABC_OK){free_preparation(&c);return c.status;}
    discover_blocks(&c);
    Context x={.c_origin=1};x.limit[JS_A]=fn->max_a;x.limit[JS_B]=fn->max_b;x.limit[JS_C]=fn->max_c-1;
    Version *body=NULL;abc_exec_label entry=ABC_EXEC_NO_LABEL;
    if(!push(&x,JS_C,reg_value(0,JS_C,-1)))c.status=abc_fail(error,ABC_NOMEM,fn->entry,"release argument allocation failed");
    if(c.status==ABC_OK){body=version_for(&c,fn->entry,&x);if(!body&&c.status==ABC_OK)c.status=ABC_NOMEM;}
    context_free(&x);
    size_t b=(size_t)fn->max_a*8,cc=b+(size_t)fn->max_b*8+8;
    size_t bytes=cc+(size_t)fn->max_c*8;
    if(c.status==ABC_OK)c.status=c.emitter->ops->label(c.emitter,&entry,fn->entry,error);
    if(c.status==ABC_OK)c.status=c.emitter->ops->bind(c.emitter,entry,fn->entry,error);
    if(c.status==ABC_OK){
        const abc_exec_operands op={.value={bytes,b,cc},.target=body->entry};
        c.status=c.emitter->ops->emit(c.emitter,ABC_FORM_RELEASE_ENTRY,&op,fn->entry,error);
    }
    while(c.qhead<c.nq&&c.status==ABC_OK)
        if(!compile_version(&c,c.queue[c.qhead++])&&c.status==ABC_OK)c.status=abc_fail(error,ABC_INVALID,fn->entry,"release compilation failed");
    if(c.status==ABC_OK)c.status=c.emitter->ops->publish(c.emitter,fn->entry,error);
    abc_release_code *code=NULL;
    if(c.status==ABC_OK){code=malloc(sizeof *code);if(!code)c.status=abc_fail(error,ABC_NOMEM,fn->entry,"release entry allocation failed");}
    if(c.status==ABC_OK){
        *code=(abc_release_code){(abc_release_fn)c.emitter->ops->address(c.emitter,entry),c.emitter,function,bytes,NULL};
        c.emitter->ops->discard_preparation(c.emitter);*out=code;
    }else c.emitter->ops->destroy(c.emitter);
    free_preparation(&c);return c.status;
}

