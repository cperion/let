/* Scalar EXT executes ordinary symbolic ABC. The sink supplies only physical
   representation operations and unresolved checked control flow. */
static int scalar_primitive(abc_symbolic_machine *m,unsigned op,unsigned descriptor,
        abc_symbolic_value *value,abc_symbolic_value *other,abc_symbolic_value *result) {
    if(op==ABC_SYM_SCALAR_DECODE&&value->dynamic_repr==ABC_SYM_REPR_RAW)return 1;
    if(op==ABC_SYM_SCALAR_CANONICAL&&value->kind==ABC_SYM_CONST){
        if(float_nan_bits(value->constant))value->constant=UINT64_C(0x7ff8000000000000);return 1;
    }
    if(!m->emit_scalar_value){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    if(m->emit_scalar_value(m->sink,m->pc,op,descriptor,value,other,result))return 1;
    if(m->exit==ABC_SYM_EXIT_BLOCK)m->exit=ABC_SYM_EXIT_FAILURE;return 0;
}
#include "generated/symbolic_scalar_ops.inc"
static int scalar_literal(abc_symbolic_machine *m,unsigned input,unsigned *tag,uint64_t *bits) {
    const uint8_t *p=m->code+m->pc;const abc_dynamic_constant *literal=&m->module->dynamic_constants[abc_u32(p+2)];
    *bits=0;memcpy(bits,literal->payload,literal->length);*tag=abc_primitive_tag(literal->kind);
    return abc_scalar_literal(input,tag,bits,literal->flags&1)&&
        abc_numeric_result(EXT_DADD+(p[1]-EXT_DADDL),input,*tag)!=UINT_MAX;
}
static int scalar_equality(abc_symbolic_machine *m,unsigned kind) {
    abc_symbolic_context *x=m->context;
    if(kind==ABC_ANY_F64)return abc_symbolic_machine_float_binary(m,OP_FEQ_A,ABC_SYM_A);
    if(kind!=ABC_ANY_STRING&&kind<14)return abc_symbolic_machine_binary(m,OP_EQ_A,ABC_SYM_A);
    abc_symbolic_value result;
    if(!scalar_primitive(m,kind==ABC_ANY_STRING?ABC_SYM_SCALAR_STRING_EQ:ABC_SYM_SCALAR_MIXED_EQ,0,
        abc_symbolic_top(x,ABC_SYM_A,0),abc_symbolic_top(x,ABC_SYM_B,0),&result))return 0;
    (void)abc_symbolic_pop(x,ABC_SYM_B);*abc_symbolic_top(x,ABC_SYM_A,0)=result;return 1;
}
int abc_symbolic_scalar_arm(abc_symbolic_machine *m,abc_symbolic_dynamic *effect,unsigned tag,abc_symbolic_value *out) {
    abc_symbolic_context *x=m->context;unsigned selector=effect->selector;
    uint32_t base=x->n[ABC_SYM_A]-effect->pops;int equality=selector==EXT_DEQ||selector==EXT_DNE;
    if(tag==UINT_MAX){
        if(equality){*out=abc_symbolic_constant(selector==EXT_DNE,ABC_SYM_A,(int32_t)base);return 1;}
        return abc_symbolic_machine_abort(m,6);
    }
    if(selector==EXT_ANY_CAST||selector==EXT_ANY_BOX){
        abc_any_layout layout=abc_any_descriptor_layout(&m->module->descriptors[effect->descriptor]);
        if(layout.form==ABC_ANY_LAYOUT_IDENTITY||!layout.cells){*out=x->s[ABC_SYM_A][base];return 1;}
        if(!scalar_primitive(m,ABC_SYM_SCALAR_DECODE,0,&x->s[ABC_SYM_A][base],NULL,NULL)||!scalar_convert(m,tag,layout.tag))return 0;
        *out=x->s[ABC_SYM_A][base];abc_symbolic_forget_dynamic(out);return 1;
    }
    int literal=selector>=EXT_DADDL&&selector<=EXT_DXORL;
    int binary=(selector>=EXT_DADD&&selector<=EXT_DXOR)||selector==EXT_DLT||selector==EXT_DLE||equality;
    if(binary||literal){
        unsigned result_tag=tag;
        if(!equality||tag<=ABC_ANY_F64||tag==ABC_ANY_PTR||tag>=14){
            for(unsigned i=0;i<effect->pops;i++)if(!scalar_primitive(m,ABC_SYM_SCALAR_DECODE,0,&x->s[ABC_SYM_A][base+i],NULL,NULL))return 0;
        }
        abc_symbolic_value right;
        if(literal){
            unsigned lt;uint64_t bits;if(!scalar_literal(m,tag,&lt,&bits))return abc_symbolic_machine_abort(m,6);
            selector=EXT_DADD+(selector-EXT_DADDL);result_tag=abc_numeric_result(selector,tag,lt);
            right=abc_symbolic_constant(bits,ABC_SYM_A,(int32_t)base);
            if(m->code[m->pc+6]){abc_symbolic_value q=x->s[ABC_SYM_A][base];x->s[ABC_SYM_A][base]=right;right=q;}
        }else right=abc_symbolic_pop(x,ABC_SYM_A);
        /* The temporary keeps its existing physical home. This is stack
           transport in the shared VM, not a new temporary-value allocator. */
        if(!abc_symbolic_push(x,ABC_SYM_B,right))return machine_fail(m,"scalar operand transport failed");
        int ok=equality?scalar_equality(m,tag):scalar_binary(m,selector,result_tag);
        if(!ok)return 0;
        if(effect->selector==EXT_DNE&&!abc_symbolic_machine_unary(m,OP_LNOT_A,ABC_SYM_A))return 0;
        *out=*abc_symbolic_top(x,ABC_SYM_A,0);
        if(!equality&&selector!=EXT_DLT&&selector!=EXT_DLE){out->dynamic_tags=(uint16_t)(1u<<result_tag);out->dynamic_width=(uint8_t)abc_numeric_width(result_tag);out->dynamic_repr=ABC_SYM_REPR_RAW;out->zero_extended=0;}
        if(!literal&&!abc_symbolic_push(x,ABC_SYM_A,abc_symbolic_constant(0,ABC_SYM_A,(int32_t)base+1)))return machine_fail(m,"scalar input shape restoration failed");
    }else {
        if(!scalar_primitive(m,ABC_SYM_SCALAR_DECODE,0,&x->s[ABC_SYM_A][base],NULL,NULL)||!scalar_unary(m,selector,tag))return 0;
        *out=x->s[ABC_SYM_A][base];
        if(selector==EXT_DLNOT||selector==EXT_DREQUIRE_BOOL)abc_symbolic_forget_dynamic(out);
        else {out->dynamic_tags=(uint16_t)(1u<<tag);out->dynamic_width=(uint8_t)abc_numeric_width(tag);out->dynamic_repr=ABC_SYM_REPR_RAW;out->zero_extended=0;}
    }
    out->dst_stack=ABC_SYM_A;out->dst_home=(int32_t)base;return 1;
}
static int scalar_instruction(const abc_module *module,const abc_symbolic_dynamic *effect) {
    if(effect->selector==EXT_ANY_CAST||effect->selector==EXT_ANY_IS)return 1;
    if(effect->selector==EXT_ANY_BOX){const abc_descriptor *d=&module->descriptors[effect->descriptor];
        return d->tag==ABC_DESC_PRIMITIVE&&d->payload[0]!=ABC_PRIM_STRING;}
    return effect->selector>=EXT_DNEG&&effect->selector<=EXT_DREQUIRE_BOOL;
}
static int scalar_dispatch(abc_symbolic_machine *m,abc_symbolic_dynamic *effect) {
    if(!m->emit_scalar_value||!m->emit_scalar_split){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    abc_symbolic_context *x=m->context;uint32_t base=x->n[ABC_SYM_A]-effect->pops;
    unsigned selector=effect->selector;uint16_t tags=0;unsigned family=ABC_SYM_SCALAR_UNARY;
    const uint16_t integers=(uint16_t)(((1u<<(ABC_ANY_I64+1))-1)&~((1u<<ABC_ANY_U8)-1));
    const uint16_t numeric=(uint16_t)(integers|(1u<<ABC_ANY_F64));
    if(selector==EXT_ANY_BOX||selector==EXT_ANY_CAST||selector==EXT_ANY_IS){
        const abc_descriptor *d=&m->module->descriptors[effect->descriptor];abc_any_layout layout=abc_any_descriptor_layout(d);
        if(!layout.form)return abc_symbolic_machine_abort(m,6);
        if(selector==EXT_ANY_BOX&&layout.form==ABC_ANY_LAYOUT_SCALAR){
            if(!layout.cells)effect->result[0]=abc_symbolic_constant(immediate(ABC_ANY_UNIT,0),ABC_SYM_A,(int32_t)base);
            else {
                effect->result[0]=x->s[ABC_SYM_A][base];int fits=abc_symbolic_dynamic_box_specialization(m->module,effect->descriptor,effect->result[0]);
                abc_symbolic_dynamic_descriptor_fact(m->module,effect->descriptor,&effect->result[0]);
                if(!fits)effect->result[0].dynamic_width=0;effect->result[0].dynamic_repr=ABC_SYM_REPR_RAW;
            }
            if(!layout.cells)abc_symbolic_dynamic_descriptor_fact(m->module,effect->descriptor,&effect->result[0]);return 1;
        }
        if(selector==EXT_ANY_IS){
            int matches;if(abc_symbolic_dynamic_test(m->module,effect->descriptor,x->s[ABC_SYM_A][base],&matches)){
                effect->result[0]=abc_symbolic_constant((uint64_t)matches,ABC_SYM_A,(int32_t)base);return 1;}
            return scalar_primitive(m,ABC_SYM_SCALAR_TEST,effect->descriptor,&x->s[ABC_SYM_A][base],NULL,effect->result);
        }
        if(layout.form==ABC_ANY_LAYOUT_OBJECT)return scalar_primitive(m,ABC_SYM_SCALAR_UNBOX,effect->descriptor,&x->s[ABC_SYM_A][base],NULL,effect->result);
        if(layout.form==ABC_ANY_LAYOUT_IDENTITY&&layout.tag==255){effect->result[0]=x->s[ABC_SYM_A][base];return 1;}
        tags=(numeric&(1u<<layout.tag))?numeric:(uint16_t)(1u<<layout.tag);
    }else if(selector==EXT_DNEG)tags=numeric;
    else if(selector==EXT_DNOT)tags=integers;
    else if(selector==EXT_DLNOT||selector==EXT_DREQUIRE_BOOL)tags=(1u<<ABC_ANY_BOOL);
    else if(selector>=EXT_DADDL&&selector<=EXT_DXORL){
        for(unsigned tag=ABC_ANY_U8;tag<=ABC_ANY_F64;tag++){unsigned lt;uint64_t bits;if(scalar_literal(m,tag,&lt,&bits))tags|=(uint16_t)(1u<<tag);}
    }else if(selector==EXT_DEQ||selector==EXT_DNE){
        family=ABC_SYM_SCALAR_EQUALITY;uint16_t a=x->s[ABC_SYM_A][base].dynamic_tags,b=x->s[ABC_SYM_A][base+1].dynamic_tags;
        if(!a)a=ABC_SYM_DYNAMIC_TAGS_UNKNOWN;if(!b)b=ABC_SYM_DYNAMIC_TAGS_UNKNOWN;
        unsigned first=UINT_MAX;int seen=0,certain=1;
        for(unsigned i=0;i<14;i++)if(a&(1u<<i))for(unsigned j=0;j<14;j++)if(b&(1u<<j)){
            unsigned kind=abc_scalar_equality_kind(i,j);if(!seen){first=kind;seen=1;}else if(first!=kind)certain=0;
            if(kind!=UINT_MAX)tags|=(uint16_t)(1u<<kind);
        }
        if(certain)return abc_symbolic_scalar_arm(m,effect,first,&effect->result[0]);
    }else {
        family=ABC_SYM_SCALAR_NUMERIC;int certain;
        tags=abc_symbolic_numeric_results(selector,x->s[ABC_SYM_A][base],x->s[ABC_SYM_A][base+1],&certain);
        if(certain)return abc_symbolic_scalar_arm(m,effect,(unsigned)__builtin_ctz(tags),&effect->result[0]);
    }
    if(family==ABC_SYM_SCALAR_UNARY){
        uint16_t have=x->s[ABC_SYM_A][base].dynamic_tags;if(!have)have=ABC_SYM_DYNAMIC_TAGS_UNKNOWN;
        tags&=have;if(have==tags&&tags&&!(tags&(tags-1)))return abc_symbolic_scalar_arm(m,effect,(unsigned)__builtin_ctz(tags),&effect->result[0]);
    }
    if(!tags&&family!=ABC_SYM_SCALAR_EQUALITY)return abc_symbolic_machine_abort(m,6);
    if(m->emit_scalar_split(m->sink,m->pc,effect,family,tags))return 1;
    if(m->exit==ABC_SYM_EXIT_BLOCK)m->exit=ABC_SYM_EXIT_FAILURE;return 0;
}
