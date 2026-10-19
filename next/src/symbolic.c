#include "symbolic.h"

void abc_symbolic_context_free(abc_symbolic_context *x) {
    for(unsigned s=0;s<3;s++) free(x->s[s]); free(x->cont); memset(x,0,sizeof *x);
}

int abc_symbolic_context_copy(abc_symbolic_context *to,const abc_symbolic_context *from) {
    memset(to,0,sizeof *to); to->c_origin=from->c_origin; to->c_bias=from->c_bias;
    to->ncont=from->ncont; to->contcap=from->ncont; to->generic=from->generic;
    memcpy(to->limit,from->limit,sizeof to->limit);
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
            a->generic!=b->generic)return 0;
    for(uint32_t i=0;i<a->ncont;i++)if(!abc_symbolic_vcont_equal(&a->cont[i],&b->cont[i]))return 0;
    for(unsigned s=0;s<3;s++){
        if(a->n[s]!=b->n[s])return 0;
        for(uint32_t i=0;i<a->n[s];i++)if(!value_equal(&a->s[s][i],&b->s[s][i]))return 0;
    }
    return 1;
}

int abc_symbolic_context_family_equal(const abc_symbolic_context *a,const abc_symbolic_context *b) {
    if(a->c_origin!=b->c_origin||a->c_bias!=b->c_bias||a->ncont!=b->ncont)return 0;
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

static int machine_fail(abc_symbolic_machine *m,const char *message) {
    m->exit=ABC_SYM_EXIT_FAILURE; abc_fail(m->error,ABC_NOMEM,m->pc,"%s",message); return 0;
}

/* The interpreter captures a push's input before consuming its source or
   changing cache ownership. In particular, copying a HOME descriptor is not a
   value capture. Keep this obligation in the shared transfers, not at a later
   block-conformance boundary. */
static int machine_capture(abc_symbolic_machine *m,abc_symbolic_value *value) {
    if(value->kind!=ABC_SYM_HOME||!m->capture)return 1;
    if(m->capture(m->sink,m->pc,value))return 1;
    m->exit=ABC_SYM_EXIT_FAILURE;
    if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic value capture failed");
    return 0;
}

int abc_symbolic_machine_push(abc_symbolic_machine *m,unsigned stack,uint64_t value) {
    abc_symbolic_value v=abc_symbolic_constant(value,stack,(int32_t)m->context->n[stack]);
    return abc_symbolic_push(m->context,stack,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_dup(abc_symbolic_machine *m,unsigned stack) {
    abc_symbolic_value v=*abc_symbolic_top(m->context,stack,0);
    if(!machine_capture(m,&v))return 0;
    v.dst_stack=(uint8_t)stack; v.dst_home=(int32_t)m->context->n[stack];
    return abc_symbolic_push(m->context,stack,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_drop(abc_symbolic_machine *m,unsigned stack) {
    (void)m; (void)abc_symbolic_pop(m->context,stack); return 1;
}
int abc_symbolic_machine_transfer(abc_symbolic_machine *m,unsigned from,unsigned to,int consume) {
    abc_symbolic_value v=*abc_symbolic_top(m->context,from,0);
    if(!machine_capture(m,&v))return 0;
    if(consume)(void)abc_symbolic_pop(m->context,from);
    v.dst_stack=(uint8_t)to; v.dst_home=(int32_t)m->context->n[to];
    return abc_symbolic_push(m->context,to,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_cpush(abc_symbolic_machine *m,unsigned from) {
    abc_symbolic_value v=*abc_symbolic_top(m->context,from,0);
    if(!machine_capture(m,&v))return 0;
    (void)abc_symbolic_pop(m->context,from);
    v.dst_stack=ABC_SYM_C; v.dst_home=m->context->c_bias+(int32_t)m->context->n[ABC_SYM_C]-m->context->c_origin;
    return abc_symbolic_push(m->context,ABC_SYM_C,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_cpushn(abc_symbolic_machine *m,unsigned selected_stack,unsigned count) {
    for(unsigned i=0;i<count;i++)if(!abc_symbolic_machine_cpush(m,selected_stack))return 0;
    return 1;
}
int abc_symbolic_machine_cpop(abc_symbolic_machine *m) {
    (void)abc_symbolic_pop(m->context,ABC_SYM_C); return 1;
}
int abc_symbolic_machine_cget(abc_symbolic_machine *m,unsigned to,unsigned depth) {
    abc_symbolic_value v=*abc_symbolic_top(m->context,ABC_SYM_C,depth);
    if(!machine_capture(m,&v))return 0;
    v.dst_stack=(uint8_t)to; v.dst_home=(int32_t)m->context->n[to];
    return abc_symbolic_push(m->context,to,v)||machine_fail(m,"symbolic stack allocation failed");
}
int abc_symbolic_machine_cget_range(abc_symbolic_machine *m,unsigned to,unsigned depth,unsigned count) {
    for(unsigned i=0;i<count;i++)if(!abc_symbolic_machine_cget(m,to,depth+i))return 0;
    return 1;
}
int abc_symbolic_machine_cset(abc_symbolic_machine *m,unsigned from,unsigned depth) {
    abc_symbolic_value v=*abc_symbolic_top(m->context,from,0);
    if(!machine_capture(m,&v))return 0;
    (void)abc_symbolic_pop(m->context,from);
    abc_symbolic_value *to=abc_symbolic_top(m->context,ABC_SYM_C,depth);
    v.dst_stack=to->dst_stack; v.dst_home=to->dst_home; *to=v; return 1;
}

int abc_symbolic_machine_binary(abc_symbolic_machine *m,unsigned opcode,unsigned destination) {
    abc_symbolic_context *x=m->context;
    unsigned opposite_stack=destination==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A;
    abc_symbolic_value left=*abc_symbolic_top(x,destination,0),right=*abc_symbolic_top(x,opposite_stack,0),result;
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
    result.dst_stack=home->dst_stack; result.dst_home=home->dst_home;
    (void)abc_symbolic_pop(x,destination==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A);
    *abc_symbolic_top(x,destination,0)=result; return 1;
}

int abc_symbolic_machine_float_binary(abc_symbolic_machine *m,unsigned opcode,unsigned destination) {
    abc_symbolic_context *x=m->context;
    unsigned opposite_stack=destination==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A;
    abc_symbolic_value left=*abc_symbolic_top(x,destination,0),right=*abc_symbolic_top(x,opposite_stack,0),result;
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
    result.dst_stack=home->dst_stack; result.dst_home=home->dst_home;
    (void)abc_symbolic_pop(x,destination==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A);
    *abc_symbolic_top(x,destination,0)=result; return 1;
}

int abc_symbolic_machine_float_unary(abc_symbolic_machine *m,unsigned opcode,unsigned selected_stack) {
    abc_symbolic_value input=*abc_symbolic_top(m->context,selected_stack,0),result=input;
    int folded=input.kind==ABC_SYM_CONST,trapped=0;
    if(folded) {
        if(opcode==ABC_OPERATION_FNEG)result.constant=input.constant^UINT64_C(0x8000000000000000);
        else if(opcode==ABC_OPERATION_I2FS)result.constant=vm_i2fs(input.constant);
        else if(opcode==ABC_OPERATION_I2FU)result.constant=vm_i2fu(input.constant);
        else { uint64_t value=0; int valid=opcode==ABC_OPERATION_F2IS?vm_f2is(input.constant,&value):vm_f2iu(input.constant,&value);
            if(valid)result.constant=value; else trapped=1; }
    }
    if(m->emit_float_unary) {
        if(!m->emit_float_unary(m->sink,m->pc,opcode,selected_stack,folded,trapped,input,&result)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!folded) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    if(trapped) { m->exit=ABC_SYM_EXIT_TERMINATED; return 0; }
    abc_symbolic_value *home=abc_symbolic_top(m->context,selected_stack,0);
    result.dst_stack=home->dst_stack; result.dst_home=home->dst_home; *home=result; return 1;
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
    result.dst_stack=home->dst_stack; result.dst_home=home->dst_home; *home=result; return 1;
}

static unsigned immediate_binary(unsigned op) {
    switch(op) {
    case ABC_OPERATION_ADDI:return ABC_OPERATION_ADD; case ABC_OPERATION_SUBI:return ABC_OPERATION_SUB; case ABC_OPERATION_MULI:return ABC_OPERATION_MUL;
    case ABC_OPERATION_ANDI:return ABC_OPERATION_AND; case ABC_OPERATION_ORI:return ABC_OPERATION_OR; case ABC_OPERATION_XORI:return ABC_OPERATION_XOR;
    case ABC_OPERATION_SHLI:return ABC_OPERATION_SHL; case ABC_OPERATION_SHRI:return ABC_OPERATION_SHR; case ABC_OPERATION_SARI:return ABC_OPERATION_SAR;
    default:__builtin_unreachable();
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
    result.dst_stack=home->dst_stack; result.dst_home=home->dst_home; *home=result; return 1;
}

static unsigned c_operand_binary(unsigned op) {
    switch(op) { case ABC_OPERATION_ADDC:return ABC_OPERATION_ADD; case ABC_OPERATION_SUBC:return ABC_OPERATION_SUB;
    case ABC_OPERATION_MULC:return ABC_OPERATION_MUL; case ABC_OPERATION_XORC:return ABC_OPERATION_XOR; default:__builtin_unreachable(); }
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
    result.dst_stack=home->dst_stack; result.dst_home=home->dst_home; *home=result; return 1;
}

int abc_symbolic_machine_pow(abc_symbolic_machine *m,unsigned opcode,unsigned selected_stack) {
    unsigned opposite_stack=selected_stack==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A;
    abc_symbolic_context *x=m->context; abc_symbolic_value left=*abc_symbolic_top(x,selected_stack,0);
    abc_symbolic_value right=*abc_symbolic_top(x,opposite_stack,0),result;
    int folded=left.kind==ABC_SYM_CONST&&right.kind==ABC_SYM_CONST&&
        !(opcode==ABC_OPERATION_POWS&&abc_signed(right.constant)<0);
    if(folded) { result=left; result.constant=vm_pow(left.constant,right.constant); }
    if(m->emit_pow) {
        if(!m->emit_pow(m->sink,m->pc,opcode,selected_stack,folded,left,right,&result)) {
            m->exit=ABC_SYM_EXIT_FAILURE;
            if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic sink emission failed");
            return 0;
        }
    } else if(!folded) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_value *home=abc_symbolic_top(x,selected_stack,0);
    result.dst_stack=home->dst_stack; result.dst_home=home->dst_home;
    (void)abc_symbolic_pop(x,opposite_stack); *home=result; return 1;
}

int abc_symbolic_machine_check(abc_symbolic_machine *m,unsigned opcode,unsigned selected_stack) {
    abc_symbolic_value input=*abc_symbolic_top(m->context,selected_stack,0);
    int known=input.kind==ABC_SYM_CONST,trapped=0;
    if(known)trapped=opcode==ABC_OPERATION_CHKU8?input.constant>255:opcode==ABC_OPERATION_CHKU16?input.constant>65535:
        opcode==ABC_OPERATION_CHKU32?input.constant>UINT32_MAX:opcode==ABC_OPERATION_CHKI32?
        (abc_signed(input.constant)<INT32_MIN||abc_signed(input.constant)>INT32_MAX):(int)(input.constant>>63);
    if(m->emit_check) {
        if(!m->emit_check(m->sink,m->pc,opcode,selected_stack,known,trapped,input)) {
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
        control.left=abc_symbolic_pop(m->context,stack); control.right=abc_symbolic_pop(m->context,stack==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A);
        control.known=control.left.kind==ABC_SYM_CONST&&control.right.kind==ABC_SYM_CONST;
        if(control.known)control.taken=kind==ABC_SYM_CONTROL_FLOAT?
            (relation==ABC_SYM_LT?vm_flt(control.left.constant,control.right.constant):relation==ABC_SYM_LE?
             vm_fle(control.left.constant,control.right.constant):vm_feq(control.left.constant,control.right.constant)):
            abc_symbolic_branch((abc_symbolic_relation)relation,control.left.constant,control.right.constant);
    } else {
        control.left=abc_symbolic_pop(m->context,stack);
        control.right=abc_symbolic_constant(immediate,stack,0); control.known=control.left.kind==ABC_SYM_CONST;
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

int abc_symbolic_machine_switch(abc_symbolic_machine *m,unsigned selected_stack,unsigned count,uint32_t fallthrough) {
    if(!m->emit_control) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    abc_symbolic_control control={.kind=ABC_SYM_CONTROL_SWITCH,.opcode=ABC_OPERATION_SWITCH,
.fallthrough=fallthrough,.count=count};
    control.left=abc_symbolic_pop(m->context,selected_stack); control.known=control.left.kind==ABC_SYM_CONST;
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

int abc_symbolic_machine_halt(abc_symbolic_machine *m,unsigned selected_stack) {
    if(!m->emit_halt) { m->exit=ABC_SYM_EXIT_BOUNDARY; return 0; }
    if(!m->emit_halt(m->sink,m->pc,selected_stack)) {
        m->exit=ABC_SYM_EXIT_FAILURE;
        if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic halt emission failed");
        return 0;
    }
    m->exit=ABC_SYM_EXIT_TERMINATED; return 0;
}

int abc_symbolic_machine_memory(abc_symbolic_machine *m) {
    if(!m->emit_memory){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    abc_symbolic_context *x=m->context;
    const abc_instruction_metadata *metadata=abc_instruction_info(m->code+m->pc);
    unsigned action=metadata->memory_action,selected_stack=metadata->selected_stack;
    unsigned opposite_stack=selected_stack==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A;
    abc_symbolic_memory memory={.opcode=m->code[m->pc],.action=action,.stack=selected_stack};
    if(action==M_ALLOC||action==M_FREE)memory.cells=(abc_u16(m->code+m->pc+1)+7)/8;
    if(action==M_FREE&&x->n[ABC_SYM_C]<memory.cells)return machine_fail(m,"symbolic C-stack underflow");
    if(action==M_FSTORE||action==M_GSTORE) {
        if(!x->n[memory.stack])return machine_fail(m,"symbolic memory store underflow");
        memory.first=*abc_symbolic_top(x,memory.stack,0);
    } else if(action==M_PLOAD) {
        if(!x->n[memory.stack])return machine_fail(m,"symbolic memory load underflow");
        memory.first=*abc_symbolic_top(x,memory.stack,0);memory.result=memory.first;
    } else if(action==M_PSTORE||action==M_XLOAD||action==M_INDEX||action==M_COPY) {
        if(!x->n[selected_stack]||!x->n[opposite_stack])return machine_fail(m,"symbolic memory operand underflow");
        memory.first=*abc_symbolic_top(x,selected_stack,0);
        memory.second=*abc_symbolic_top(x,opposite_stack,0);memory.result=memory.first;
    }
    if(!m->emit_memory(m->sink,m->pc,&memory)) {
        if(m->exit==ABC_SYM_EXIT_BOUNDARY||m->exit==ABC_SYM_EXIT_CONTROL||m->exit==ABC_SYM_EXIT_TERMINATED)return 0;
        m->exit=ABC_SYM_EXIT_FAILURE;if(!m->error||m->error->status==ABC_OK)abc_fail(m->error,ABC_NOMEM,m->pc,"symbolic memory emission failed");return 0;
    }
    if(action==M_ALLOC) {
        int32_t start=x->c_bias+(int32_t)x->n[ABC_SYM_C]-x->c_origin;
        for(uint32_t i=0;i<memory.cells;i++)if(!abc_symbolic_push(x,ABC_SYM_C,abc_symbolic_home(ABC_SYM_C,start+(int32_t)i)))return machine_fail(m,"symbolic C-stack allocation failed");
    } else if(action==M_FREE)x->n[ABC_SYM_C]-=memory.cells;
    else if(action==M_FLOAD||action==M_FADDR||action==M_GLOAD||action==M_GADDR) {
        memory.result.dst_stack=(uint8_t)selected_stack;memory.result.dst_home=(int32_t)x->n[selected_stack];
        if(!abc_symbolic_push(x,selected_stack,memory.result))return machine_fail(m,"symbolic memory result allocation failed");
    } else if(action==M_FSTORE||action==M_GSTORE)(void)abc_symbolic_pop(x,selected_stack);
    else if(action==M_PLOAD) {
        abc_symbolic_value *home=abc_symbolic_top(x,selected_stack,0);memory.result.dst_stack=home->dst_stack;memory.result.dst_home=home->dst_home;*home=memory.result;
    } else if(action==M_PSTORE||action==M_COPY) {
        (void)abc_symbolic_pop(x,selected_stack);(void)abc_symbolic_pop(x,opposite_stack);
    } else if(action==M_XLOAD||action==M_INDEX) {
        (void)abc_symbolic_pop(x,opposite_stack);abc_symbolic_value *home=abc_symbolic_top(x,selected_stack,0);memory.result.dst_stack=home->dst_stack;memory.result.dst_home=home->dst_home;*home=memory.result;
    } else return machine_fail(m,"unknown symbolic memory action");
    return 1;
}

int abc_symbolic_machine_indirect(abc_symbolic_machine *m,unsigned frame_cells,unsigned arguments,unsigned destination,int tail) {
    if(!m->emit_indirect){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}abc_symbolic_context *x=m->context;const abc_function *site=m->module?abc_find_site(m->module,m->pc):NULL;
    unsigned target_stack=destination==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A;
    if(!site||x->n[destination]<arguments||!x->n[target_stack]||(tail&&x->n[ABC_SYM_C]<frame_cells))return machine_fail(m,"symbolic indirect-call shape mismatch");
    uint32_t argument_base=x->n[destination]-arguments;
    abc_symbolic_indirect effect={.frame_cells=frame_cells,.arguments=arguments,.results=site->results,
        .destination=tail?ABC_STACK_NONE:destination,.argument_stack=destination,.tail=(unsigned)tail,.target=*abc_symbolic_top(x,target_stack,0)};
    if(!m->emit_indirect(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    if(effect.direct){x->n[target_stack]--;return tail?abc_symbolic_machine_tail(m,effect.direct_target,frame_cells,arguments,destination):abc_symbolic_machine_call(m,effect.direct_target,arguments,destination,m->pc+abc_instruction_length(m->code+m->pc));}
    /* An unresolved tail has no symbolic successor in this activation. Its
       sink has transported the live arguments and transferred control; do not
       emit capture/CPUSH work after that terminating transfer. */
    if(tail){m->exit=ABC_SYM_EXIT_CONTROL;return 0;}
    x->n[target_stack]--;
    x->n[destination]=argument_base;
    for(unsigned i=0;i<effect.results;i++){
        abc_symbolic_value value=effect.result[i];
        if(value.kind==ABC_SYM_HOME&&(value.stack!=destination||value.home!=(int32_t)x->n[destination])&&!machine_capture(m,&value))return 0;
        value.dst_stack=(uint8_t)destination;value.dst_home=(int32_t)x->n[destination];
        if(!abc_symbolic_push(x,destination,value))return machine_fail(m,"symbolic indirect-call result allocation failed");
    }
    return 1;
}

int abc_symbolic_machine_call(abc_symbolic_machine *m,uint32_t target,unsigned arguments,unsigned destination,uint32_t return_pc) {
    if(!m->emit_call){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}abc_symbolic_context *x=m->context;int fi=m->module?abc_find_function(m->module,target):-1;
    if(fi<0||x->n[destination]<arguments)return machine_fail(m,"symbolic direct-call shape mismatch");const abc_function *callee=&m->module->functions[fi];
    uint32_t argument_base=x->n[destination]-arguments,cbase=x->n[ABC_SYM_C];int32_t ctop=x->c_bias+(int32_t)cbase-x->c_origin,new_bias=ctop+(int32_t)arguments;
    abc_symbolic_call effect={.target=target,.arguments=arguments,.results=callee->results,.destination=destination,
        .continuation={return_pc,target,x->n[ABC_SYM_A]-(destination==ABC_SYM_A?arguments:0),
            x->n[ABC_SYM_B]-(destination==ABC_SYM_B?arguments:0),cbase,x->c_origin,x->c_bias,(uint8_t)destination}};
    if(!m->emit_call(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    if(effect.virtualize) {
        for(unsigned i=0;i<arguments;i++)if(!abc_symbolic_machine_cpush(m,destination))return 0;
        x->c_origin=(int32_t)x->n[ABC_SYM_C];x->c_bias=new_bias;if(!abc_symbolic_push_continuation(x,effect.continuation))return machine_fail(m,"symbolic continuation allocation failed");
        if(!m->emit_edge||!m->emit_edge(m->sink,m->pc,target)){m->exit=ABC_SYM_EXIT_FAILURE;return 0;}m->exit=ABC_SYM_EXIT_CONTROL;return 0;
    }
    x->n[destination]=argument_base;for(unsigned i=0;i<effect.results;i++){abc_symbolic_value q=effect.result[i];
        if(q.kind==ABC_SYM_HOME&&(q.stack!=destination||q.home!=(int32_t)x->n[destination])&&!machine_capture(m,&q))return 0;
        q.dst_stack=(uint8_t)destination;q.dst_home=(int32_t)x->n[destination];if(!abc_symbolic_push(x,destination,q))return machine_fail(m,"symbolic call result allocation failed");}
    return 1;
}

int abc_symbolic_machine_tail(abc_symbolic_machine *m,uint32_t target,unsigned frame_cells,unsigned arguments,unsigned argument_stack) {
    if(!m->emit_tail){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}abc_symbolic_context *x=m->context;
    if(x->n[argument_stack]<arguments||x->n[ABC_SYM_C]<frame_cells)return machine_fail(m,"symbolic tail-call shape mismatch");
    abc_symbolic_tail effect={.target=target,.frame_cells=frame_cells,.arguments=arguments,.argument_stack=argument_stack};
    if(!m->emit_tail(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    if(effect.residualize){m->exit=ABC_SYM_EXIT_TERMINATED;return 0;}
    uint32_t cbase=x->n[ABC_SYM_C]-frame_cells;int32_t coff=x->c_bias+(int32_t)cbase-x->c_origin,new_bias=coff+(int32_t)arguments;
    /* Captured arguments remain in the allocation context until transported. */
    for(unsigned i=0;i<arguments;i++)
        if(!machine_capture(m,&x->s[argument_stack][x->n[argument_stack]-arguments+i]))return 0;
    x->n[ABC_SYM_C]=cbase;
    for(unsigned i=0;i<arguments;i++)if(!abc_symbolic_machine_cpush(m,argument_stack))return 0;
    x->c_origin=(int32_t)x->n[ABC_SYM_C];x->c_bias=new_bias;
    if(!m->emit_edge||!m->emit_edge(m->sink,m->pc,target)){m->exit=ABC_SYM_EXIT_FAILURE;return 0;}m->exit=ABC_SYM_EXIT_CONTROL;return 0;
}

int abc_symbolic_machine_return(abc_symbolic_machine *m,unsigned frame_cells,unsigned results_count,unsigned source_stack) {
    abc_symbolic_context *x=m->context;abc_symbolic_return effect={frame_cells,results_count,!x->ncont,source_stack};
    if(x->ncont) {
        abc_symbolic_continuation frame=x->cont[x->ncont-1];
        if(x->n[ABC_SYM_A]!=frame.abase+(source_stack==ABC_SYM_A?results_count:0)||
           x->n[ABC_SYM_B]!=frame.bbase+(source_stack==ABC_SYM_B?results_count:0)||
           x->n[ABC_SYM_C]!=frame.cbase+frame_cells)return machine_fail(m,"symbolic return shape mismatch");
        if(frame.dst!=source_stack){
            uint32_t source_base=source_stack==ABC_SYM_A?frame.abase:frame.bbase;
            for(unsigned i=0;i<results_count;i++)
                if(!machine_capture(m,&x->s[source_stack][source_base+i]))return 0;
            for(unsigned i=0;i<results_count;i++){
                abc_symbolic_value value=x->s[source_stack][source_base+i];value.dst_stack=frame.dst;value.dst_home=(int32_t)x->n[frame.dst];
                if(!abc_symbolic_push(x,frame.dst,value))return machine_fail(m,"symbolic return result allocation failed");
            }
            x->n[source_stack]=source_base;
        }
        x->n[ABC_SYM_C]=frame.cbase;x->c_origin=frame.old_origin;x->c_bias=frame.old_bias;x->ncont--;
        if(!m->emit_return||!m->emit_return(m->sink,m->pc,&effect)){m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
        if(!m->emit_edge||!m->emit_edge(m->sink,m->pc,frame.return_pc)){m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
        m->exit=ABC_SYM_EXIT_CONTROL;return 0;
    }
    if(x->n[source_stack]!=results_count||x->n[source_stack==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A]||x->n[ABC_SYM_C]!=frame_cells)return machine_fail(m,"symbolic terminal return shape mismatch");
    if(!m->emit_return){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    if(!m->emit_return(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    m->exit=ABC_SYM_EXIT_TERMINATED;return 0;
}

int abc_symbolic_machine_foreign(abc_symbolic_machine *m,unsigned selected_stack) {
    if(!m->emit_foreign){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}const uint8_t *p=m->code+m->pc;unsigned index=abc_u16(p+1);
    if(!m->module||index>=m->module->extern_count)return machine_fail(m,"invalid symbolic foreign index");const abc_extern *ext=&m->module->externs[index];
    abc_symbolic_context *x=m->context;if(x->n[selected_stack]<ext->arguments)return machine_fail(m,"symbolic foreign argument underflow");
    abc_symbolic_foreign effect={.index=index,.arguments=ext->arguments,.results=ext->results,.selected_stack=selected_stack};if(ext->results)effect.result[0]=abc_symbolic_home(selected_stack,(int32_t)(x->n[selected_stack]-ext->arguments));
    if(!m->emit_foreign(m->sink,m->pc,&effect)){if(m->exit==ABC_SYM_EXIT_BOUNDARY)return 0;m->exit=ABC_SYM_EXIT_FAILURE;return 0;}
    x->n[selected_stack]-=ext->arguments;if(ext->results&&!abc_symbolic_push(x,selected_stack,effect.result[0]))return machine_fail(m,"symbolic foreign result allocation failed");
    return 1;
}

abc_symbolic_exit abc_symbolic_machine_boundary(abc_symbolic_machine *m) {
    m->opcode=m->code[m->pc]; m->exit=ABC_SYM_EXIT_BOUNDARY; return m->exit;
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
        unsigned kind=abc_instruction_info(m->code+pc)->kind; uint32_t next=pc+abc_instruction_length(m->code+pc);
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
        unsigned kind=abc_instruction_info(m->code+pc)->kind; uint32_t next=pc+abc_instruction_length(m->code+pc);
        if(kind==K_ICALL||kind==K_ITCALL) return 1;
        if(kind==K_CALL||kind==K_TCALL) {
            uint32_t target=(uint32_t)((int64_t)next+abc_i32(m->code+pc+1)); int to=abc_find_function(m,target);
            if(to>=0&&abc_symbolic_has_unknown_call(m,to,seen)) return 1;
        }
        pc=next;
    }
    return 0;
}

