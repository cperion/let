/* Bind the common scalar control flow to the existing symbolic cache. No EXT
   algorithm or operation-family selection is implemented in this file. */
#define SCALAR_ENTER (UINT_MAX-1u)
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
/* Abstract evaluation of the tag predicates. Unknown outcomes emit ordinary
   checked successors; the generated common computation supplies their bodies. */
static int scalar_select(abc_symbolic_machine *m,abc_symbolic_dynamic *effect,unsigned family,uint16_t allowed,unsigned *selected) {
    if(*selected!=SCALAR_ENTER)return 1;
    abc_symbolic_context *x=m->context;uint32_t base=x->n[ABC_SYM_A]-effect->pops;
    uint16_t tags=0;unsigned known=UINT_MAX;int certain=0;
    abc_symbolic_value left=x->s[ABC_SYM_A][base];
    if(family==ABC_SYM_SCALAR_UNARY){
        uint16_t have=left.dynamic_tags?left.dynamic_tags:ABC_SYM_DYNAMIC_TAGS_UNKNOWN;
        tags=have&allowed;certain=!tags||(tags==have&&!(tags&(tags-1)));
        if(tags)known=(unsigned)__builtin_ctz(tags);
    }else {
        uint16_t a=left.dynamic_tags,b=x->s[ABC_SYM_A][base+1].dynamic_tags;
        if(!a)a=ABC_SYM_DYNAMIC_TAGS_UNKNOWN;if(!b)b=ABC_SYM_DYNAMIC_TAGS_UNKNOWN;
        int seen=0;certain=1;
        for(unsigned i=0;i<14;i++)if(a&(1u<<i))for(unsigned j=0;j<14;j++)if(b&(1u<<j)){
            unsigned kind=family==ABC_SYM_SCALAR_NUMERIC?abc_scalar_promote(i,j,!!(allowed&(1u<<ABC_ANY_F64))):abc_scalar_equality_kind(i,j);
            if(!seen){known=kind;seen=1;}else if(known!=kind)certain=0;
            if(kind!=UINT_MAX)tags|=(uint16_t)(1u<<kind);
        }
        tags&=allowed;
    }
    if(certain){*selected=known;return 1;}
    if(!m->emit_scalar_split){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    (void)m->emit_scalar_split(m->sink,m->pc,effect,family,tags);
    if(m->exit==ABC_SYM_EXIT_BLOCK)m->exit=ABC_SYM_EXIT_FAILURE;return 0;
}
static int scalar_test(abc_symbolic_machine *m,unsigned descriptor,abc_symbolic_value *input,abc_symbolic_value *result) {
    int matches;
    if(abc_symbolic_dynamic_test(m->module,descriptor,*input,&matches)){
        *result=abc_symbolic_constant((uint64_t)matches,input->dst_stack,input->dst_home);return 1;
    }
    return scalar_primitive(m,ABC_SYM_SCALAR_TEST,descriptor,input,NULL,result);
}
int abc_symbolic_machine_require(abc_symbolic_machine *m,abc_symbolic_value *predicate,unsigned reason) {
    if(predicate->kind==ABC_SYM_CONST)return predicate->constant?1:abc_symbolic_machine_abort(m,reason);
    if(!m->emit_guard){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    if(m->emit_guard(m->sink,m->pc,predicate,reason))return 1;
    m->exit=ABC_SYM_EXIT_FAILURE;return 0;
}
static int scalar_effect(abc_symbolic_machine *m,abc_symbolic_dynamic *effect) {
    if(!m->emit_dynamic){m->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    if(m->emit_dynamic(m->sink,m->pc,effect))return 1;
    if(m->exit==ABC_SYM_EXIT_BLOCK)m->exit=ABC_SYM_EXIT_FAILURE;return 0;
}
#include "generated/symbolic_scalar_ops.inc"
#undef SCALAR_ENTER
