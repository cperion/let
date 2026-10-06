#include "symbolic.h"
#include "dynamic.h"

void abc_symbolic_context_free(abc_symbolic_context *x) {
    for(unsigned s=0;s<3;s++) free(x->s[s]); free(x->cont); memset(x,0,sizeof *x);
}

int abc_symbolic_context_copy(abc_symbolic_context *to,const abc_symbolic_context *from) {
    memset(to,0,sizeof *to); to->c_origin=from->c_origin; to->c_bias=from->c_bias;
    to->ncont=from->ncont; to->contcap=from->ncont; to->generic=from->generic;
    to->reg_return=from->reg_return; memcpy(to->limit,from->limit,sizeof to->limit);
    if(from->ncont) {
        to->cont=malloc((size_t)from->ncont*sizeof *to->cont);
        if(!to->cont) { abc_symbolic_context_free(to); return 0; }
        memcpy(to->cont,from->cont,(size_t)from->ncont*sizeof *to->cont);
    }
    for(unsigned s=0;s<3;s++) {
        to->n[s]=to->cap[s]=from->n[s];
        if(from->n[s]) {
            to->s[s]=malloc((size_t)from->n[s]*sizeof *to->s[s]);
            if(!to->s[s]) { abc_symbolic_context_free(to); return 0; }
            memcpy(to->s[s],from->s[s],(size_t)from->n[s]*sizeof *to->s[s]);
        }
    }
    return 1;
}

static int value_equal(const abc_symbolic_value *a,const abc_symbolic_value *b) {
    return a->kind==b->kind&&a->stack==b->stack&&a->dst_stack==b->dst_stack&&
        a->dynamic_width==b->dynamic_width&&a->dynamic_repr==b->dynamic_repr&&a->dynamic_tags==b->dynamic_tags&&
        a->reg==b->reg&&a->home==b->home&&a->dst_home==b->dst_home&&
        a->constant==b->constant;
}

int abc_symbolic_vcont_equal(const abc_symbolic_continuation *a,const abc_symbolic_continuation *b) {
    return a->return_pc==b->return_pc&&a->target==b->target&&a->abase==b->abase&&
        a->bbase==b->bbase&&a->cbase==b->cbase&&a->old_origin==b->old_origin&&
        a->old_bias==b->old_bias&&a->dst==b->dst;
}

int abc_symbolic_continuation_equal(const abc_symbolic_context *a,const abc_symbolic_context *b) {
    if(a->ncont!=b->ncont)return 0;
    for(uint32_t i=0;i<a->ncont;i++)if(!abc_symbolic_vcont_equal(&a->cont[i],&b->cont[i]))return 0;
    return 1;
}

int abc_symbolic_context_equal(const abc_symbolic_context *a,const abc_symbolic_context *b) {
    if(a->c_origin!=b->c_origin||a->c_bias!=b->c_bias||a->ncont!=b->ncont||
            a->generic!=b->generic||a->reg_return!=b->reg_return)return 0;
    for(uint32_t i=0;i<a->ncont;i++)if(!abc_symbolic_vcont_equal(&a->cont[i],&b->cont[i]))return 0;
    for(unsigned s=0;s<3;s++){
        if(a->n[s]!=b->n[s])return 0;
        for(uint32_t i=0;i<a->n[s];i++)if(!value_equal(&a->s[s][i],&b->s[s][i]))return 0;
    }
    return 1;
}

int abc_symbolic_context_family_equal(const abc_symbolic_context *a,const abc_symbolic_context *b) {
    if(a->c_origin!=b->c_origin||a->c_bias!=b->c_bias||a->ncont!=b->ncont||
            a->reg_return!=b->reg_return)return 0;
    for(unsigned s=0;s<3;s++)if(a->n[s]!=b->n[s])return 0;
    for(uint32_t i=0;i<a->ncont;i++)if(!abc_symbolic_vcont_equal(&a->cont[i],&b->cont[i]))return 0;
    return 1;
}

static int canonical_generic_context(const abc_symbolic_context *x) {
    if(!x->generic)return 0;
    for(unsigned s=0;s<3;s++)for(uint32_t i=0;i<x->n[s];i++) {
        int32_t home=s==ABC_SYM_C?x->c_bias+(int32_t)i-x->c_origin:(int32_t)i;
        abc_symbolic_value expected=abc_symbolic_home(s,home);
        if(!value_equal(&x->s[s][i],&expected))return 0;
    }
    return 1;
}

int abc_symbolic_generic_context_equal(const abc_symbolic_context *a,const abc_symbolic_context *b) {
    return canonical_generic_context(a)&&canonical_generic_context(b)&&abc_symbolic_context_family_equal(a,b);
}

static int stack_grow(abc_symbolic_context *x,unsigned s,uint32_t need) {
    if(need<=x->cap[s])return 1; uint32_t n=x->cap[s]?x->cap[s]*2:8; while(n<need)n*=2;
    abc_symbolic_value *p=realloc(x->s[s],(size_t)n*sizeof *p);
    if(!p)return 0; x->s[s]=p; x->cap[s]=n; return 1;
}

int abc_symbolic_push(abc_symbolic_context *x,unsigned s,abc_symbolic_value value) {
    if(!stack_grow(x,s,x->n[s]+1))return 0; x->s[s][x->n[s]++]=value; return 1;
}

int abc_symbolic_push_continuation(abc_symbolic_context *x,abc_symbolic_continuation value) {
    if(x->ncont==x->contcap){
        uint32_t n=x->contcap?x->contcap*2:4; if(n<x->contcap)return 0;
        abc_symbolic_continuation *p=realloc(x->cont,(size_t)n*sizeof *p);
        if(!p)return 0; x->cont=p; x->contcap=n;
    }
    x->cont[x->ncont++]=value; return 1;
}

abc_symbolic_value abc_symbolic_pop(abc_symbolic_context *x,unsigned s) { return x->s[s][--x->n[s]]; }
abc_symbolic_value *abc_symbolic_top(abc_symbolic_context *x,unsigned s,unsigned depth) { return &x->s[s][x->n[s]-1-depth]; }

abc_symbolic_value abc_symbolic_home(unsigned stack,int32_t home) {
    abc_symbolic_value v={.kind=ABC_SYM_HOME,.stack=(uint8_t)stack,.dst_stack=(uint8_t)stack,.home=home,.dst_home=home}; return v;
}
abc_symbolic_value abc_symbolic_constant(uint64_t value,unsigned stack,int32_t home) {
    abc_symbolic_value v={.kind=ABC_SYM_CONST,.dst_stack=(uint8_t)stack,.dst_home=home,.constant=value}; return v;
}
abc_symbolic_value abc_symbolic_backend(uint32_t backend,unsigned stack,int32_t home) {
    abc_symbolic_value v={.kind=ABC_SYM_BACKEND,.dst_stack=(uint8_t)stack,.reg=backend,.dst_home=home}; return v;
}
abc_symbolic_value abc_symbolic_rehome(abc_symbolic_value value,unsigned stack,int32_t home) {
    value.kind=ABC_SYM_HOME;value.stack=(uint8_t)stack;value.dst_stack=(uint8_t)stack;value.reg=0;value.home=home;value.dst_home=home;value.constant=0;return value;
}
void abc_symbolic_forget_dynamic(abc_symbolic_value *value) {
    value->dynamic_width=0;value->dynamic_repr=ABC_SYM_REPR_NONE;value->dynamic_tags=0;
}

static int machine_fail(abc_symbolic_machine *m,const char *message) {
    m->exit=ABC_SYM_EXIT_FAILURE; abc_fail(m->error,ABC_NOMEM,m->pc,"%s",message); return 0;
}

int abc_symbolic_machine_push(abc_symbolic_machine *m,unsigned stack,uint64_t value) {
    abc_symbolic_value v=abc_symbolic_constant(value,stack,(int32_t)m->context->n[stack]);
    return abc_symbolic_push(m->context,stack,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_dup(abc_symbolic_machine *m,unsigned stack) {
    abc_symbolic_value v=*abc_symbolic_top(m->context,stack,0);
    v.dst_stack=(uint8_t)stack; v.dst_home=(int32_t)m->context->n[stack];
    return abc_symbolic_push(m->context,stack,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_drop(abc_symbolic_machine *m,unsigned stack) {
    (void)m; (void)abc_symbolic_pop(m->context,stack); return 1;
}
int abc_symbolic_machine_transfer(abc_symbolic_machine *m,unsigned from,unsigned to,int consume) {
    abc_symbolic_value v=consume?abc_symbolic_pop(m->context,from):*abc_symbolic_top(m->context,from,0);
    v.dst_stack=(uint8_t)to; v.dst_home=(int32_t)m->context->n[to];
    return abc_symbolic_push(m->context,to,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_cpush(abc_symbolic_machine *m,unsigned from) {
    abc_symbolic_value v=abc_symbolic_pop(m->context,from);
    v.dst_stack=ABC_SYM_C; v.dst_home=m->context->c_bias+(int32_t)m->context->n[ABC_SYM_C]-m->context->c_origin;
    return abc_symbolic_push(m->context,ABC_SYM_C,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_cpushn(abc_symbolic_machine *m,unsigned count) {
    for(unsigned i=0;i<count;i++)if(!abc_symbolic_machine_cpush(m,ABC_SYM_A))return 0;
    return 1;
}
int abc_symbolic_machine_cpop(abc_symbolic_machine *m) {
    (void)abc_symbolic_pop(m->context,ABC_SYM_C); return 1;
}
int abc_symbolic_machine_cget(abc_symbolic_machine *m,unsigned to,unsigned depth) {
    abc_symbolic_value v=*abc_symbolic_top(m->context,ABC_SYM_C,depth);
    v.dst_stack=(uint8_t)to; v.dst_home=(int32_t)m->context->n[to];
    return abc_symbolic_push(m->context,to,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_cget_range(abc_symbolic_machine *m,unsigned to,unsigned depth,unsigned count) {
    for(unsigned i=0;i<count;i++)if(!abc_symbolic_machine_cget(m,to,depth+i))return 0;
    return 1;
}
int abc_symbolic_machine_cset(abc_symbolic_machine *m,unsigned from,unsigned depth) {
    abc_symbolic_value v=abc_symbolic_pop(m->context,from);
    abc_symbolic_value *to=abc_symbolic_top(m->context,ABC_SYM_C,depth);
    v.dst_stack=to->dst_stack; v.dst_home=to->dst_home; *to=v; return 1;
}

int abc_symbolic_machine_binary(abc_symbolic_machine *m,unsigned opcode,unsigned destination) {
    abc_symbolic_context *x=m->context;
    abc_symbolic_value left=*abc_symbolic_top(x,ABC_SYM_A,0),right=*abc_symbolic_top(x,ABC_SYM_B,0),result;
    int folded=0;
    if(left.kind==ABC_SYM_CONST&&right.kind==ABC_SYM_CONST) {
        result=left; result.constant=abc_symbolic_fold_binary(opcode,left.constant,right.constant,&folded);
    }
    if(m->emit_binary) {
        if(!m->emit_binary(m->sink,m->pc,opcode,destination,folded,left,right,&result)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!folded) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_value *home=abc_symbolic_top(x,destination,0);
    abc_symbolic_forget_dynamic(&result);result.dst_stack=home->dst_stack; result.dst_home=home->dst_home;
    (void)abc_symbolic_pop(x,destination==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A);
    *abc_symbolic_top(x,destination,0)=result; return 1;
}

int abc_symbolic_machine_float_binary(abc_symbolic_machine *m,unsigned opcode,unsigned destination) {
    abc_symbolic_context *x=m->context;
    abc_symbolic_value left=*abc_symbolic_top(x,ABC_SYM_A,0),right=*abc_symbolic_top(x,ABC_SYM_B,0),result;
    int folded=left.kind==ABC_SYM_CONST&&right.kind==ABC_SYM_CONST;
    if(folded) { result=left; result.constant=abc_symbolic_fold_float(opcode,left.constant,right.constant); }
    if(m->emit_float_binary) {
        if(!m->emit_float_binary(m->sink,m->pc,opcode,destination,folded,left,right,&result)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!folded) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_value *home=abc_symbolic_top(x,destination,0);
    abc_symbolic_forget_dynamic(&result);result.dst_stack=home->dst_stack; result.dst_home=home->dst_home;
    (void)abc_symbolic_pop(x,destination==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A);
    *abc_symbolic_top(x,destination,0)=result; return 1;
}

int abc_symbolic_machine_float_unary(abc_symbolic_machine *m,unsigned opcode) {
    abc_symbolic_value input=*abc_symbolic_top(m->context,ABC_SYM_A,0),result=input;
    int folded=input.kind==ABC_SYM_CONST,trapped=0;
    if(folded) {
        if(opcode==OP_FNEG)result.constant=input.constant^UINT64_C(0x8000000000000000);
        else if(opcode==OP_I2FS)result.constant=vm_i2fs(input.constant);
        else if(opcode==OP_I2FU)result.constant=vm_i2fu(input.constant);
        else { uint64_t value=0; int valid=opcode==OP_F2IS?vm_f2is(input.constant,&value):vm_f2iu(input.constant,&value);
            if(valid)result.constant=value; else trapped=1; }
    }
    if(m->emit_float_unary) {
        if(!m->emit_float_unary(m->sink,m->pc,opcode,folded,trapped,input,&result)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!folded) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    if(trapped) { m->exit=ABC_SYM_EXIT_TERMINATED; return 0; }
    abc_symbolic_value *home=abc_symbolic_top(m->context,ABC_SYM_A,0);
    abc_symbolic_forget_dynamic(&result);result.dst_stack=home->dst_stack; result.dst_home=home->dst_home; *home=result; return 1;
}

int abc_symbolic_machine_unary(abc_symbolic_machine *m,unsigned opcode,unsigned stack) {
    abc_symbolic_value input=*abc_symbolic_top(m->context,stack,0),result; int folded=input.kind==ABC_SYM_CONST;
    if(folded) { result=input; result.constant=abc_symbolic_fold_unary(opcode,input.constant); }
    if(m->emit_unary) {
        if(!m->emit_unary(m->sink,m->pc,opcode,stack,folded,input,&result)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!folded) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_value *home=abc_symbolic_top(m->context,stack,0);
    abc_symbolic_forget_dynamic(&result);if(opcode==OP_SX32_A||opcode==OP_SX32_B||opcode==OP_ZX32_A||opcode==OP_ZX32_B)result.dynamic_width=32;
    result.dst_stack=home->dst_stack; result.dst_home=home->dst_home; *home=result; return 1;
}

static unsigned immediate_binary(unsigned op) {
    switch(op) {
    case OP_ADDI_A:return OP_ADD_A; case OP_SUBI_A:return OP_SUB_A; case OP_MULI_A:return OP_MUL_A;
    case OP_ANDI_A:return OP_AND_A; case OP_ORI_A:return OP_OR_A; case OP_XORI_A:return OP_XOR_A;
    case OP_SHLI_A:return OP_SHL_A; case OP_SHRI_A:return OP_SHR_A; case OP_SARI_A:return OP_SAR_A;
    default:return OP_ADD_A;
    }
}
int abc_symbolic_machine_immediate(abc_symbolic_machine *m,unsigned opcode,unsigned stack,uint64_t immediate) {
    abc_symbolic_value input=*abc_symbolic_top(m->context,stack,0),result; int folded=input.kind==ABC_SYM_CONST;
    if(folded) { int ok=0; result=input; result.constant=abc_symbolic_fold_binary(immediate_binary(opcode),input.constant,immediate,&ok); folded=ok; }
    if(m->emit_immediate) {
        if(!m->emit_immediate(m->sink,m->pc,opcode,stack,immediate,folded,input,&result)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!folded) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_value *home=abc_symbolic_top(m->context,stack,0);
    abc_symbolic_forget_dynamic(&result);result.dst_stack=home->dst_stack; result.dst_home=home->dst_home; *home=result; return 1;
}

static unsigned c_operand_binary(unsigned op) {
    switch(op) { case OP_ADDC_A:return OP_ADD_A; case OP_SUBC_A:return OP_SUB_A;
    case OP_MULC_A:return OP_MUL_A; case OP_XORC_A:return OP_XOR_A; default:return OP_ADD_A; }
}
int abc_symbolic_machine_c_operand(abc_symbolic_machine *m,unsigned opcode,unsigned stack,unsigned depth) {
    abc_symbolic_value left=*abc_symbolic_top(m->context,stack,0),right=*abc_symbolic_top(m->context,ABC_SYM_C,depth),result;
    int folded=left.kind==ABC_SYM_CONST&&right.kind==ABC_SYM_CONST;
    if(folded) { int ok=0; result=left; result.constant=abc_symbolic_fold_binary(c_operand_binary(opcode),left.constant,right.constant,&ok); folded=ok; }
    if(m->emit_c_operand) {
        if(!m->emit_c_operand(m->sink,m->pc,opcode,stack,folded,left,right,&result)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!folded) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_value *home=abc_symbolic_top(m->context,stack,0);
    abc_symbolic_forget_dynamic(&result);result.dst_stack=home->dst_stack; result.dst_home=home->dst_home; *home=result; return 1;
}

int abc_symbolic_machine_pow(abc_symbolic_machine *m,unsigned opcode) {
    abc_symbolic_context *x=m->context; abc_symbolic_value left=*abc_symbolic_top(x,ABC_SYM_A,0);
    abc_symbolic_value right=*abc_symbolic_top(x,ABC_SYM_B,0),result;
    int folded=left.kind==ABC_SYM_CONST&&right.kind==ABC_SYM_CONST&&
        !(opcode==OP_POWS&&abc_signed(right.constant)<0);
    if(folded) { result=left; result.constant=vm_pow(left.constant,right.constant); }
    if(m->emit_pow) {
        if(!m->emit_pow(m->sink,m->pc,opcode,ABC_SYM_A,folded,left,right,&result)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!folded) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_value *home=abc_symbolic_top(x,ABC_SYM_A,0);
    abc_symbolic_forget_dynamic(&result);result.dst_stack=home->dst_stack; result.dst_home=home->dst_home;
    (void)abc_symbolic_pop(x,ABC_SYM_B); *home=result; return 1;
}

int abc_symbolic_machine_check(abc_symbolic_machine *m,unsigned opcode) {
    abc_symbolic_value input=*abc_symbolic_top(m->context,ABC_SYM_A,0);
    int known=input.kind==ABC_SYM_CONST,trapped=0;
    if(known)trapped=opcode==OP_CHKU8?input.constant>255:opcode==OP_CHKU16?input.constant>65535:
        opcode==OP_CHKU32?input.constant>UINT32_MAX:opcode==OP_CHKI32?
        (abc_signed(input.constant)<INT32_MIN||abc_signed(input.constant)>INT32_MAX):(int)(input.constant>>63);
    if(m->emit_check) {
        if(!m->emit_check(m->sink,m->pc,opcode,known,trapped,input)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!known) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    if(trapped) { m->exit=ABC_SYM_EXIT_TERMINATED; return 0; }
    return 1;
}

int abc_symbolic_machine_control(abc_symbolic_machine *m,abc_symbolic_control_kind kind,
        unsigned opcode,unsigned relation,unsigned reverse,unsigned stack,
        uint32_t target,uint32_t fallthrough,uint64_t immediate) {
    if(!m->emit_control) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_control control={.kind=kind,.opcode=opcode,.relation=relation,.reverse=reverse,
.target=target,.fallthrough=fallthrough};
    if(kind==ABC_SYM_CONTROL_JUMP) { control.known=control.taken=1; }
    else if(kind==ABC_SYM_CONTROL_ZERO) {
        control.left=abc_symbolic_pop(m->context,stack); control.known=control.left.kind==ABC_SYM_CONST;
        if(control.known)control.taken=abc_symbolic_branch((abc_symbolic_relation)relation,control.left.constant,0);
    } else if(kind==ABC_SYM_CONTROL_INTEGER||kind==ABC_SYM_CONTROL_FLOAT) {
        control.left=abc_symbolic_pop(m->context,ABC_SYM_A); control.right=abc_symbolic_pop(m->context,ABC_SYM_B);
        control.known=control.left.kind==ABC_SYM_CONST&&control.right.kind==ABC_SYM_CONST;
        if(control.known)control.taken=kind==ABC_SYM_CONTROL_FLOAT?
            (relation==0?vm_flt(control.left.constant,control.right.constant):relation==1?
             vm_fle(control.left.constant,control.right.constant):vm_feq(control.left.constant,control.right.constant)):
            abc_symbolic_branch((abc_symbolic_relation)relation,control.left.constant,control.right.constant);
    } else {
        control.left=abc_symbolic_pop(m->context,ABC_SYM_A);
        control.right=abc_symbolic_constant(immediate,ABC_SYM_A,0); control.known=control.left.kind==ABC_SYM_CONST;
        if(control.known)control.taken=reverse?abc_symbolic_branch((abc_symbolic_relation)relation,immediate,control.left.constant):
            abc_symbolic_branch((abc_symbolic_relation)relation,control.left.constant,immediate);
    }
    if(!m->emit_control(m->sink,m->pc,&control)) {
        m->exit=ABC_SYM_EXIT_FAILURE;
        if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic control emission failed");
        return 0;
    }
    m->exit=ABC_SYM_EXIT_CONTROL; return 0;
}

int abc_symbolic_machine_switch(abc_symbolic_machine *m,unsigned count,uint32_t fallthrough) {
    if(!m->emit_control) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_control control={.kind=ABC_SYM_CONTROL_SWITCH,.opcode=OP_SWITCH,
.fallthrough=fallthrough,.count=count};
    control.left=abc_symbolic_pop(m->context,ABC_SYM_A); control.known=control.left.kind==ABC_SYM_CONST;
    if(control.known) {
        uint64_t index=control.left.constant; control.taken=index<count; control.target=fallthrough;
        if(index<count)control.target=(uint32_t)((int64_t)fallthrough+abc_i32(m->code+m->pc+3+4*(uint32_t)index));
    }
    if(!m->emit_control(m->sink,m->pc,&control)) {
        m->exit=ABC_SYM_EXIT_FAILURE;
        if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic switch emission failed");
        return 0;
    }
    m->exit=ABC_SYM_EXIT_CONTROL; return 0;
}

int abc_symbolic_machine_abort(abc_symbolic_machine *m,unsigned reason) {
    if(!m->emit_abort) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    if(!m->emit_abort(m->sink,m->pc,reason)) {
        m->exit=ABC_SYM_EXIT_FAILURE;
        if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic abort emission failed");
        return 0;
    }
    m->exit=ABC_SYM_EXIT_TERMINATED; return 0;
}

int abc_symbolic_machine_halt(abc_symbolic_machine *m) {
    if(!m->emit_halt) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    if(!m->emit_halt(m->sink,m->pc,0)) {
        m->exit=ABC_SYM_EXIT_FAILURE;
        if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic halt emission failed");
        return 0;
    }
    m->exit=ABC_SYM_EXIT_TERMINATED; return 0;
}

int abc_symbolic_machine_effect(abc_symbolic_machine *m,unsigned opcode) {
    if(!m->emit_effect) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    if(m->emit_effect(m->sink,m->pc,opcode))return 1;
    if(m->exit==ABC_SYM_EXIT_BOUNDARY||m->exit==ABC_SYM_EXIT_CONTROL||m->exit==ABC_SYM_EXIT_TERMINATED)return 0;
    m->exit=ABC_SYM_EXIT_FAILURE;
    if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic effect emission failed");
    return 0;
}

int abc_symbolic_machine_memory(abc_symbolic_machine *m,unsigned opcode) {
    if(!m->emit_memory){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    abc_symbolic_context *x=m->context;abc_memory_op op=op_memory[opcode];
    abc_symbolic_memory memory={.opcode=opcode,.action=op.action,.stack=op.to_b?ABC_SYM_B:ABC_SYM_A};
    if(op.action==M_ALLOC||op.action==M_FREE)memory.cells=(abc_u16(m->code+m->pc+1)+7)/8;
    if(op.action==M_FREE&&x->n[ABC_SYM_C]<memory.cells)return machine_fail(m,"symbolic C-stack underflow");
    if(op.action==M_FSTORE||op.action==M_GSTORE) {
        if(!x->n[memory.stack])return machine_fail(m,"symbolic memory store underflow");
        memory.first=*abc_symbolic_top(x,memory.stack,0);
    } else if(op.action==M_PLOAD) {
        if(!x->n[memory.stack])return machine_fail(m,"symbolic memory load underflow");
        memory.first=*abc_symbolic_top(x,memory.stack,0);memory.result=memory.first;
    } else if(op.action==M_PSTORE||op.action==M_XLOAD||op.action==M_INDEX||op.action==M_COPY) {
        if(!x->n[ABC_SYM_A]||!x->n[ABC_SYM_B])return machine_fail(m,"symbolic memory operand underflow");
        memory.first=*abc_symbolic_top(x,ABC_SYM_A,0);memory.second=*abc_symbolic_top(x,ABC_SYM_B,0);memory.result=memory.first;
    }
    if(!m->emit_memory(m->sink,m->pc,&memory)) {
        if(m->exit==ABC_SYM_EXIT_BOUNDARY||m->exit==ABC_SYM_EXIT_CONTROL||m->exit==ABC_SYM_EXIT_TERMINATED)return 0;
        m->exit=ABC_SYM_EXIT_FAILURE;if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic memory emission failed");return 0;
    }
    if(op.action==M_ALLOC) {
        int32_t start=x->c_bias+(int32_t)x->n[ABC_SYM_C]-x->c_origin;
        for(uint32_t i=0;i<memory.cells;i++)if(!abc_symbolic_push(x,ABC_SYM_C,abc_symbolic_home(ABC_SYM_C,start+(int32_t)i)))return machine_fail(m,"symbolic C-stack allocation failed");
    } else if(op.action==M_FREE)x->n[ABC_SYM_C]-=memory.cells;
    else if(op.action==M_FLOAD||op.action==M_FADDR||op.action==M_GLOAD||op.action==M_GADDR) {
        memory.result.dst_stack=(uint8_t)memory.stack;memory.result.dst_home=(int32_t)x->n[memory.stack];
        if(!abc_symbolic_push(x,memory.stack,memory.result))return machine_fail(m,"symbolic memory result allocation failed");
    } else if(op.action==M_FSTORE||op.action==M_GSTORE)(void)abc_symbolic_pop(x,memory.stack);
    else if(op.action==M_PLOAD) {
        abc_symbolic_value *home=abc_symbolic_top(x,memory.stack,0);memory.result.dst_stack=home->dst_stack;memory.result.dst_home=home->dst_home;*home=memory.result;
    } else if(op.action==M_PSTORE||op.action==M_COPY) {
        (void)abc_symbolic_pop(x,ABC_SYM_A);(void)abc_symbolic_pop(x,ABC_SYM_B);
    } else if(op.action==M_XLOAD||op.action==M_INDEX) {
        (void)abc_symbolic_pop(x,ABC_SYM_B);abc_symbolic_value *home=abc_symbolic_top(x,ABC_SYM_A,0);memory.result.dst_stack=home->dst_stack;memory.result.dst_home=home->dst_home;*home=memory.result;
    } else return machine_fail(m,"unknown symbolic memory action");
    return 1;
}

static int dynamic_contract(const abc_module *module,const uint8_t *p,abc_symbolic_dynamic *effect) {
    unsigned e=p[1];*effect=(abc_symbolic_dynamic){.selector=e,.tail=e==EXT_DTCALL};
    if(e==EXT_ANY_BOX||e==EXT_ANY_CAST||e==EXT_ANY_IS) {
        uint32_t di=abc_u32(p+2);if(!module||di>=module->descriptor_count)return 0;effect->descriptor=di;const abc_descriptor *d=&module->descriptors[di];unsigned cells;
        if(d->tag==ABC_DESC_PRIMITIVE){unsigned prim=d->payload[0];cells=prim==ABC_PRIM_UNIT?0:prim==ABC_PRIM_STRING?2:1;}
        else if(d->tag==ABC_DESC_SLICE)cells=2;else if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_RECORD||d->tag==ABC_DESC_ARRAY||d->tag==ABC_DESC_SUM)cells=1;else return 0;
        if(e==EXT_ANY_BOX){effect->pops=cells;effect->pushes=1;}else if(e==EXT_ANY_CAST){effect->pops=1;effect->pushes=cells;}else effect->pops=effect->pushes=1;return 1;
    }
    if((e>=EXT_DNEG&&e<=EXT_DLNOT)||e==EXT_DREQUIRE_BOOL){effect->pops=effect->pushes=1;return 1;}
    if((e>=EXT_DADD&&e<=EXT_DXOR)||(e>=EXT_DEQ&&e<=EXT_DLE)){effect->pops=2;effect->pushes=1;return 1;}
    if(e>=EXT_DADDL&&e<=EXT_DXORL){effect->pops=effect->pushes=1;return 1;}
    if(e==EXT_DCALL||e==EXT_DTCALL){effect->pops=(unsigned)p[2]+1;effect->pushes=p[3];return 1;}
    if(e==EXT_STRING_CAT){effect->pops=2;effect->pushes=1;return 1;}if(e==EXT_STRING_TEXT){effect->pops=effect->pushes=1;return 1;}
    if(e==EXT_WORD_NEW||e==EXT_WORD_DIRECT||e==EXT_MANAGED_NEW){
        if(e==EXT_WORD_NEW||e==EXT_MANAGED_NEW)
            effect->descriptor=abc_u32(p+2);
        else effect->descriptor=abc_u32(p+6);
        effect->pushes=1;return 1;
    }
    if(e==EXT_CLOSURE_NEW||e==EXT_MANAGED_COPY){
        effect->descriptor=abc_u32(p+(e==EXT_MANAGED_COPY?2:6));
        effect->pops=effect->pushes=1;return 1;
    }
    if((e>=EXT_WORD_GET&&e<=EXT_WORD_FREEZE)||e==EXT_WORD_BIND){effect->pops=e==EXT_WORD_COUNT||e==EXT_WORD_FREEZE?1:e==EXT_WORD_SET||e==EXT_WORD_METHOD||e==EXT_WORD_BIND?3:2;effect->pushes=1;return 1;}
    return 0;
}

int abc_symbolic_machine_indirect(abc_symbolic_machine *m,unsigned frame_cells,unsigned arguments,unsigned destination,int tail) {
    if(!m->emit_indirect){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}abc_symbolic_context *x=m->context;const abc_function *site=m->module?abc_find_site(m->module,m->pc):NULL;
    if(!site||x->n[ABC_SYM_A]<arguments||!x->n[ABC_SYM_B]||(tail&&x->n[ABC_SYM_C]<frame_cells))return machine_fail(m,"symbolic indirect-call shape mismatch");
    uint32_t abase=x->n[ABC_SYM_A]-arguments,cbase=x->n[ABC_SYM_C]-frame_cells;abc_symbolic_indirect effect={.frame_cells=frame_cells,.arguments=arguments,.results=site->results,.destination=destination,.tail=(unsigned)tail,.target=*abc_symbolic_top(x,ABC_SYM_B,0)};
    if(!m->emit_indirect(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    if(effect.direct){x->n[ABC_SYM_B]--;return tail?abc_symbolic_machine_tail(m,effect.direct_target,frame_cells,arguments):abc_symbolic_machine_call(m,effect.direct_target,arguments,destination,m->pc+abc_instruction_length(m->code+m->pc));}
    x->n[ABC_SYM_B]--;if(tail){
        int32_t coff=x->c_bias+(int32_t)cbase-x->c_origin,new_bias=coff+(int32_t)arguments;abc_symbolic_value args[255];for(unsigned i=0;i<arguments;i++)args[i]=x->s[ABC_SYM_A][abase+i];x->n[ABC_SYM_A]=abase;x->n[ABC_SYM_C]=cbase;
        for(unsigned i=arguments;i;i--){unsigned index=i-1;abc_symbolic_value q=args[index];q.dst_stack=ABC_SYM_C;q.dst_home=new_bias-1-(int32_t)index;if(!abc_symbolic_push(x,ABC_SYM_C,q))return machine_fail(m,"symbolic indirect-tail argument allocation failed");}
        x->c_origin=(int32_t)x->n[ABC_SYM_C];x->c_bias=new_bias;m->exit=ABC_SYM_EXIT_CONTROL;return 0;
    }
    x->n[ABC_SYM_A]=abase;for(unsigned i=0;i<effect.results;i++){abc_symbolic_value q=effect.result[i];q.dst_stack=(uint8_t)destination;q.dst_home=(int32_t)x->n[destination];if(!abc_symbolic_push(x,destination,q))return machine_fail(m,"symbolic indirect-call result allocation failed");}return 1;
}

int abc_symbolic_machine_call(abc_symbolic_machine *m,uint32_t target,unsigned arguments,unsigned destination,uint32_t return_pc) {
    if(!m->emit_call){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}abc_symbolic_context *x=m->context;int fi=m->module?abc_find_function(m->module,target):-1;
    if(fi<0||x->n[ABC_SYM_A]<arguments)return machine_fail(m,"symbolic direct-call shape mismatch");const abc_function *callee=&m->module->functions[fi];
    uint32_t abase=x->n[ABC_SYM_A]-arguments,cbase=x->n[ABC_SYM_C];int32_t ctop=x->c_bias+(int32_t)cbase-x->c_origin,new_bias=ctop+(int32_t)arguments;
    abc_symbolic_call effect={.target=target,.arguments=arguments,.results=callee->results,.destination=destination,
        .continuation={return_pc,target,abase,x->n[ABC_SYM_B],cbase,x->c_origin,x->c_bias,(uint8_t)destination}};
    if(!m->emit_call(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    if(effect.virtualize) {
        abc_symbolic_value args[255];for(unsigned i=0;i<arguments;i++)args[i]=x->s[ABC_SYM_A][abase+i];x->n[ABC_SYM_A]=abase;
        for(unsigned i=arguments;i;i--){unsigned index=i-1;abc_symbolic_value q=args[index];q.dst_stack=ABC_SYM_C;q.dst_home=new_bias-1-(int32_t)index;if(!abc_symbolic_push(x,ABC_SYM_C,q))return machine_fail(m,"symbolic call argument allocation failed");}
        x->c_origin=(int32_t)x->n[ABC_SYM_C];x->c_bias=new_bias;if(!abc_symbolic_push_continuation(x,effect.continuation))return machine_fail(m,"symbolic continuation allocation failed");
        if(!m->emit_edge||!m->emit_edge(m->sink,m->pc,target)){m->exit=ABC_SYM_EXIT_FAILURE;return 0;}m->exit=ABC_SYM_EXIT_CONTROL;return 0;
    }
    x->n[ABC_SYM_A]=abase;for(unsigned i=0;i<effect.results;i++){abc_symbolic_value q=effect.result[i];q.dst_stack=(uint8_t)destination;q.dst_home=(int32_t)x->n[destination];if(!abc_symbolic_push(x,destination,q))return machine_fail(m,"symbolic call result allocation failed");}
    return 1;
}

int abc_symbolic_machine_tail(abc_symbolic_machine *m,uint32_t target,unsigned frame_cells,unsigned arguments) {
    if(!m->emit_tail){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}abc_symbolic_context *x=m->context;
    if(x->n[ABC_SYM_A]<arguments||x->n[ABC_SYM_C]<frame_cells)return machine_fail(m,"symbolic tail-call shape mismatch");
    abc_symbolic_tail effect={.target=target,.frame_cells=frame_cells,.arguments=arguments};if(!m->emit_tail(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}if(effect.residualize){m->exit=ABC_SYM_EXIT_TERMINATED;return 0;}
    uint32_t abase=x->n[ABC_SYM_A]-arguments,cbase=x->n[ABC_SYM_C]-frame_cells;int32_t coff=x->c_bias+(int32_t)cbase-x->c_origin,new_bias=coff+(int32_t)arguments;
    abc_symbolic_value args[255];for(unsigned i=0;i<arguments;i++)args[i]=x->s[ABC_SYM_A][abase+i];x->n[ABC_SYM_A]=abase;x->n[ABC_SYM_C]=cbase;
    for(unsigned i=arguments;i;i--){unsigned index=i-1;abc_symbolic_value q=args[index];q.dst_stack=ABC_SYM_C;q.dst_home=new_bias-1-(int32_t)index;if(!abc_symbolic_push(x,ABC_SYM_C,q))return machine_fail(m,"symbolic tail argument allocation failed");}
    x->c_origin=(int32_t)x->n[ABC_SYM_C];x->c_bias=new_bias;
    if(!m->emit_edge||!m->emit_edge(m->sink,m->pc,target)){m->exit=ABC_SYM_EXIT_FAILURE;return 0;}m->exit=ABC_SYM_EXIT_CONTROL;return 0;
}

int abc_symbolic_machine_return(abc_symbolic_machine *m,unsigned frame_cells,unsigned results_count) {
    abc_symbolic_context *x=m->context;abc_symbolic_return effect={frame_cells,results_count,!x->ncont};
    if(x->ncont) {
        abc_symbolic_continuation frame=x->cont[x->ncont-1];
        if(x->n[ABC_SYM_A]!=frame.abase+results_count||x->n[ABC_SYM_B]!=frame.bbase||x->n[ABC_SYM_C]!=frame.cbase+frame_cells)return machine_fail(m,"symbolic return shape mismatch");
        abc_symbolic_value results[255];for(unsigned i=0;i<results_count;i++)results[i]=x->s[ABC_SYM_A][frame.abase+i];
        x->n[ABC_SYM_A]=frame.abase;x->n[ABC_SYM_B]=frame.bbase;x->n[ABC_SYM_C]=frame.cbase;x->c_origin=frame.old_origin;x->c_bias=frame.old_bias;x->ncont--;
        for(unsigned i=0;i<results_count;i++){abc_symbolic_value q=results[i];q.dst_stack=frame.dst;q.dst_home=(int32_t)x->n[frame.dst];if(!abc_symbolic_push(x,frame.dst,q))return machine_fail(m,"symbolic return result allocation failed");}
        if(!m->emit_return||!m->emit_return(m->sink,m->pc,&effect)){m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
        if(!m->emit_edge||!m->emit_edge(m->sink,m->pc,frame.return_pc)){m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
        m->exit=ABC_SYM_EXIT_CONTROL;return 0;
    }
    if(x->n[ABC_SYM_A]!=results_count||x->n[ABC_SYM_B]||x->n[ABC_SYM_C]!=frame_cells)return machine_fail(m,"symbolic terminal return shape mismatch");
    if(!m->emit_return){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    if(!m->emit_return(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    m->exit=ABC_SYM_EXIT_TERMINATED;return 0;
}

void abc_symbolic_dynamic_descriptor_fact(const abc_module *module,unsigned descriptor,abc_symbolic_value *value) {
    const abc_descriptor *d=&module->descriptors[descriptor];unsigned tag=ABC_ANY_AGGREGATE,width=0,repr=ABC_SYM_REPR_BOXED;
    if(d->tag==ABC_DESC_PRIMITIVE) {
        static const uint8_t tags[]={ABC_ANY_UNIT,ABC_ANY_BOOL,ABC_ANY_U8,ABC_ANY_U16,ABC_ANY_U32,ABC_ANY_U64,ABC_ANY_I32,ABC_ANY_I64,ABC_ANY_F64,ABC_ANY_STRING,0,ABC_ANY_WORD};
        static const uint8_t widths[]={0,1,8,16,32,64,32,64,64,0,0,0};
        unsigned primitive=d->payload[0];
        if(primitive==ABC_PRIM_ANY){value->dynamic_tags=ABC_SYM_DYNAMIC_TAGS_UNKNOWN;value->dynamic_repr=ABC_SYM_REPR_UNKNOWN;return;}
        if(primitive>=sizeof tags)return;tag=tags[primitive];width=widths[primitive];
        repr=(primitive==ABC_PRIM_UNIT||primitive==ABC_PRIM_F64)?ABC_SYM_REPR_ENCODED:ABC_SYM_REPR_UNKNOWN;
    } else if(d->tag==ABC_DESC_POINTER)tag=ABC_ANY_PTR;
    value->dynamic_tags=(uint16_t)(1u<<tag);value->dynamic_width=(uint8_t)width;value->dynamic_repr=(uint8_t)repr;
}

static int dynamic_immediate(unsigned tag,uint64_t value) {
    if(tag==ABC_ANY_U32||tag==ABC_ANY_U64)return value<=(UINT64_C(1)<<40)-1;
    if(tag==ABC_ANY_I32||tag==ABC_ANY_I64){int64_t signed_value=(int64_t)value;return signed_value>=-(INT64_C(1)<<39)&&signed_value<(INT64_C(1)<<39);}
    return 0;
}

int abc_symbolic_dynamic_box_specialization(const abc_module *module,unsigned descriptor,abc_symbolic_value input) {
    const abc_descriptor *d=&module->descriptors[descriptor];if(d->tag!=ABC_DESC_PRIMITIVE)return 0;unsigned primitive=d->payload[0];
    if((primitive==ABC_PRIM_U32||primitive==ABC_PRIM_I32)&&!input.dynamic_tags&&input.dynamic_repr==ABC_SYM_REPR_NONE&&input.dynamic_width==32)return 1;
    if(input.kind!=ABC_SYM_CONST)return 0;unsigned tag=primitive==ABC_PRIM_U32?ABC_ANY_U32:primitive==ABC_PRIM_I32?ABC_ANY_I32:primitive==ABC_PRIM_U64?ABC_ANY_U64:primitive==ABC_PRIM_I64?ABC_ANY_I64:UINT_MAX;
    return tag!=UINT_MAX&&dynamic_immediate(tag,input.constant);
}

int abc_symbolic_dynamic_cast_matches(const abc_module *module,unsigned descriptor,abc_symbolic_value input) {
    abc_symbolic_value expected={0};abc_symbolic_dynamic_descriptor_fact(module,descriptor,&expected);
    return module->descriptors[descriptor].tag==ABC_DESC_PRIMITIVE&&(expected.dynamic_width==32||expected.dynamic_width==64)&&input.dynamic_repr==ABC_SYM_REPR_RAW&&
        expected.dynamic_tags&&expected.dynamic_tags!=ABC_SYM_DYNAMIC_TAGS_UNKNOWN&&input.dynamic_tags==expected.dynamic_tags&&input.dynamic_width==expected.dynamic_width;
}

int abc_symbolic_dynamic_binary_specialization(unsigned selector,abc_symbolic_value left,abc_symbolic_value right,unsigned *opcode) {
    uint16_t tags=left.dynamic_tags;if(left.dynamic_repr!=ABC_SYM_REPR_RAW||right.dynamic_repr!=ABC_SYM_REPR_RAW||!tags||
            tags==ABC_SYM_DYNAMIC_TAGS_UNKNOWN||(tags&(uint16_t)(tags-1))||tags!=right.dynamic_tags||left.dynamic_width!=right.dynamic_width)return 0;
    int narrow=(tags==(uint16_t)(1u<<ABC_ANY_U32)||tags==(uint16_t)(1u<<ABC_ANY_I32))&&left.dynamic_width==32;
    int wide=(tags==(uint16_t)(1u<<ABC_ANY_U64)||tags==(uint16_t)(1u<<ABC_ANY_I64))&&left.dynamic_width==64&&left.kind==ABC_SYM_CONST&&right.kind==ABC_SYM_CONST;
    if(!narrow&&!wide)return 0;switch(selector){
    case EXT_DADD:*opcode=OP_ADD_A;break;case EXT_DSUB:*opcode=OP_SUB_A;break;case EXT_DMUL:*opcode=OP_MUL_A;break;
    case EXT_DAND:*opcode=OP_AND_A;break;case EXT_DOR:*opcode=OP_OR_A;break;case EXT_DXOR:*opcode=OP_XOR_A;break;default:return 0;
    }
    if(wide){int ok=0;uint64_t value=abc_symbolic_fold_binary(*opcode,left.constant,right.constant,&ok);return ok&&dynamic_immediate((unsigned)__builtin_ctz((unsigned)tags),value);}
    return 1;
}

int abc_symbolic_machine_dynamic(abc_symbolic_machine *m) {
    if(!m->emit_dynamic){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}abc_symbolic_context *x=m->context;abc_symbolic_dynamic effect;
    if(!dynamic_contract(m->module,m->code+m->pc,&effect)||x->n[ABC_SYM_A]<effect.pops)return machine_fail(m,"invalid symbolic dynamic contract");
    for(unsigned i=0;i<effect.pushes;i++)effect.result[i]=abc_symbolic_home(ABC_SYM_A,(int32_t)(x->n[ABC_SYM_A]-effect.pops+i));
    if(effect.selector==EXT_ANY_BOX&&effect.pushes){abc_symbolic_dynamic_descriptor_fact(m->module,effect.descriptor,&effect.result[0]);uint32_t base=x->n[ABC_SYM_A]-effect.pops;if(effect.pops==1&&abc_symbolic_dynamic_box_specialization(m->module,effect.descriptor,x->s[ABC_SYM_A][base]))effect.result[0].dynamic_repr=ABC_SYM_REPR_ENCODED;}
    if(!m->emit_dynamic(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY||m->exit==ABC_SYM_EXIT_CONTROL||m->exit==ABC_SYM_EXIT_TERMINATED)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    if(effect.direct){uint32_t base=x->n[ABC_SYM_A]-effect.pops;abc_symbolic_value args[255];unsigned supplied=effect.pops-1;for(unsigned i=0;i<supplied;i++)args[i]=x->s[ABC_SYM_A][base+1+i];x->n[ABC_SYM_A]=base;if(effect.direct_environment){abc_symbolic_value q=effect.environment;q.dst_stack=ABC_SYM_A;q.dst_home=(int32_t)x->n[ABC_SYM_A];if(!abc_symbolic_push(x,ABC_SYM_A,q))return machine_fail(m,"symbolic dynamic environment allocation failed");}for(unsigned i=0;i<supplied;i++){abc_symbolic_value q=args[i];q.dst_stack=ABC_SYM_A;q.dst_home=(int32_t)x->n[ABC_SYM_A];if(!abc_symbolic_push(x,ABC_SYM_A,q))return machine_fail(m,"symbolic dynamic argument allocation failed");}return abc_symbolic_machine_call(m,effect.direct_target,effect.direct_arguments,ABC_SYM_A,m->pc+abc_instruction_length(m->code+m->pc));}
    x->n[ABC_SYM_A]-=effect.pops;for(unsigned i=0;i<effect.pushes;i++)if(!abc_symbolic_push(x,ABC_SYM_A,effect.result[i]))return machine_fail(m,"symbolic dynamic result allocation failed");
    if(!effect.tail)return 1;
    if(x->ncont) {
        abc_symbolic_continuation frame=x->cont[x->ncont-1];if(x->n[ABC_SYM_A]!=frame.abase+effect.pushes||x->n[ABC_SYM_B]!=frame.bbase)return machine_fail(m,"symbolic dynamic tail result mismatch");
        x->n[ABC_SYM_C]=frame.cbase;abc_symbolic_value results[255];for(unsigned i=0;i<effect.pushes;i++)results[i]=x->s[ABC_SYM_A][frame.abase+i];
        x->n[ABC_SYM_A]=frame.abase;x->n[ABC_SYM_B]=frame.bbase;x->c_origin=frame.old_origin;x->c_bias=frame.old_bias;x->ncont--;
        for(unsigned i=0;i<effect.pushes;i++){abc_symbolic_value q=results[i];q.dst_stack=frame.dst;q.dst_home=(int32_t)x->n[frame.dst];if(!abc_symbolic_push(x,frame.dst,q))return machine_fail(m,"symbolic dynamic continuation allocation failed");}
        if(!m->emit_edge||!m->emit_edge(m->sink,m->pc,frame.return_pc)){m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    }
    m->exit=ABC_SYM_EXIT_CONTROL;return 0;
}

int abc_symbolic_machine_foreign(abc_symbolic_machine *m) {
    if(!m->emit_foreign){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}const uint8_t *p=m->code+m->pc;unsigned index=abc_u16(p+1);
    if(!m->module||index>=m->module->extern_count)return machine_fail(m,"invalid symbolic foreign index");const abc_extern *ext=&m->module->externs[index];
    abc_symbolic_context *x=m->context;if(x->n[ABC_SYM_A]<ext->arguments)return machine_fail(m,"symbolic foreign argument underflow");
    abc_symbolic_foreign effect={.index=index,.arguments=ext->arguments,.results=ext->results};if(ext->results)effect.result[0]=abc_symbolic_home(ABC_SYM_A,(int32_t)(x->n[ABC_SYM_A]-ext->arguments));
    if(!m->emit_foreign(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    x->n[ABC_SYM_A]-=ext->arguments;if(ext->results&&!abc_symbolic_push(x,ABC_SYM_A,effect.result[0]))return machine_fail(m,"symbolic foreign result allocation failed");
    return 1;
}

abc_symbolic_exit abc_symbolic_machine_boundary(abc_symbolic_machine *m) {
    m->opcode=m->code[m->pc]; m->exit=ABC_SYM_EXIT_BOUNDARY; return m->exit;
}

uint64_t abc_symbolic_fold_binary(unsigned op,uint64_t x,uint64_t y,int *ok) {
    *ok=1; switch(op) {
    case OP_ADD_A: return x+y; case OP_SUB_A: return x-y; case OP_MUL_A: return x*y;
    case OP_DIVU_A: if(!y){*ok=0;return 0;} return x/y;
    case OP_DIVS_A: if(!y){*ok=0;return 0;} return y==UINT64_MAX?0-x:(uint64_t)(abc_signed(x)/abc_signed(y));
    case OP_REMU_A: if(!y){*ok=0;return 0;} return x%y;
    case OP_REMS_A: if(!y){*ok=0;return 0;} return y==UINT64_MAX?0:(uint64_t)(abc_signed(x)%abc_signed(y));
    case OP_AND_A: return x&y; case OP_OR_A: return x|y; case OP_XOR_A: return x^y;
    case OP_SHL_A: return y>=64?0:x<<y; case OP_SHR_A: return y>=64?0:x>>y; case OP_SAR_A: return vm_sar(x,y);
    case OP_EQ_A: return x==y; case OP_NE_A: return x!=y; case OP_LT_A: return abc_signed(x)<abc_signed(y);
    case OP_LE_A: return abc_signed(x)<=abc_signed(y); case OP_LTU_A: return x<y; case OP_LEU_A: return x<=y;
    default: *ok=0; return 0;
    }
}

uint64_t abc_symbolic_fold_unary(unsigned op,uint64_t x) {
    switch(op) {
    case OP_NEG_A:return 0-x; case OP_NOT_A:return ~x; case OP_LNOT_A:return x^1;
    case OP_ZX32_A:return x&UINT32_MAX; case OP_SX32_A:return (uint64_t)(int64_t)abc_i32_from_u64(x);
    default:return x;
    }
}

uint64_t abc_symbolic_fold_float(unsigned op,uint64_t x,uint64_t y) {
    switch(op) {
    case OP_FADD_A:return vm_fadd(x,y); case OP_FSUB_A:return vm_fsub(x,y);
    case OP_FMUL_A:return vm_fmul(x,y); case OP_FDIV_A:return vm_fdiv(x,y);
    case OP_FLT_A:return vm_flt(x,y); case OP_FLE_A:return vm_fle(x,y);
    default:return vm_feq(x,y);
    }
}

int abc_symbolic_branch(abc_symbolic_relation relation,uint64_t a,uint64_t b) {
    switch(relation) {
    case ABC_SYM_EQ:return a==b; case ABC_SYM_NE:return a!=b;
    case ABC_SYM_LT:return abc_signed(a)<abc_signed(b); case ABC_SYM_LE:return abc_signed(a)<=abc_signed(b);
    case ABC_SYM_LTU:return a<b; case ABC_SYM_LEU:return a<=b;
    }
    return 0;
}

int abc_symbolic_reaches_function(const abc_module *m,int from,int goal,uint8_t *seen) {
    if(seen[from]) return 0; seen[from]=1; const abc_function *f=&m->functions[from];
    for(uint32_t pc=f->entry;pc<f->end;) {
        unsigned op=m->code[pc],kind=op_kind[op]; uint32_t next=pc+abc_instruction_length(m->code+pc);
        if(kind==K_CALL||kind==K_TCALL) {
            uint32_t target=(uint32_t)((int64_t)next+abc_i32(m->code+pc+1)); int to=abc_find_function(m,target);
            if(to==goal || (to>=0&&abc_symbolic_reaches_function(m,to,goal,seen))) return 1;
        }
        pc=next;
    }
    return 0;
}

int abc_symbolic_has_unknown_call(const abc_module *m,int from,uint8_t *seen) {
    if(seen[from]) return 0; seen[from]=1; const abc_function *f=&m->functions[from];
    for(uint32_t pc=f->entry;pc<f->end;) {
        unsigned op=m->code[pc],kind=op_kind[op]; uint32_t next=pc+abc_instruction_length(m->code+pc);
        if(kind==K_ICALL||kind==K_ITCALL) return 1;
        if(kind==K_CALL||kind==K_TCALL) {
            uint32_t target=(uint32_t)((int64_t)next+abc_i32(m->code+pc+1)); int to=abc_find_function(m,target);
            if(to>=0&&abc_symbolic_has_unknown_call(m,to,seen)) return 1;
        }
        pc=next;
    }
    return 0;
}

