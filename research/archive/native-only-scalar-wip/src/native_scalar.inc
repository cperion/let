/* These bodies run only after their operand tag has been proved. They use
   the same typed arithmetic/check stencils as ordinary ABC instructions. */
static int native_normalize(Compiler *c,unsigned reg,unsigned tag) {
    unsigned width=abc_numeric_width(tag);
    if(width==8||width==16)return place(c,ABC_STENCIL_IMMEDIATE(ABC_JIMM_AND,reg),(UINT64_C(1)<<width)-1,NULL);
    if(width==32)return place(c,ABC_STENCIL_UNARY(abc_numeric_signed(tag)?ABC_JUN_SX32:ABC_JUN_ZX32,reg),0,NULL);
    return 1;
}
static int native_scalar_cast(Compiler *c,Context *x,uint32_t pc,unsigned from,unsigned to,JValue *result) {
    JValue *value=top(x,JS_A,0);
    if(to==ABC_ANY_UNIT){*result=*value;return 1;}
    if(to==ABC_ANY_WORD){*result=*value;return 1;}
    if(!decode_numeric(c,x,value))return 0;
    int r=writable(c,x,value);if(r<0)return 0;
    uint64_t error=ABC_ABORT|(UINT64_C(3)<<8)|((uint64_t)pc<<16);
    if(from==to){
        if(to==ABC_ANY_F64&&!place(c,ABC_STENCIL_FLOAT_CANON(r),0,NULL))return 0;
    }else if(to==ABC_ANY_F64){
        if(!place(c,ABC_STENCIL_FLOAT_UNARY(abc_numeric_signed(from)?ABC_JFUN_I2FS:ABC_JFUN_I2FU,r),0,NULL))return 0;
    }else {
        if(from==ABC_ANY_F64){
            if(!place(c,ABC_STENCIL_FLOAT_UNARY(abc_numeric_signed(to)?ABC_JFUN_F2IS:ABC_JFUN_F2IU,r),error,NULL))return 0;
            from=abc_numeric_signed(to)?ABC_ANY_I64:ABC_ANY_U64;
        }
        unsigned fw=abc_numeric_width(from),tw=abc_numeric_width(to);
        if(fw!=tw){
            if(abc_numeric_signed(to)){
                if(abc_numeric_signed(from)){
                    if(tw==32&&!place(c,ABC_STENCIL_CHECK(3,r),error,NULL))return 0;
                }else if(!place(c,tw==32?ABC_STENCIL_CHECK_I31(r):ABC_STENCIL_CHECK(4,r),error,NULL))return 0;
            }else {
                if(abc_numeric_signed(from)&&!place(c,ABC_STENCIL_CHECK(4,r),error,NULL))return 0;
                if(tw<64&&!place(c,ABC_STENCIL_CHECK(tw==8?0:tw==16?1:2,r),error,NULL))return 0;
            }
        }
        if(!native_normalize(c,(unsigned)r,to))return 0;
    }
    *result=*value;abc_symbolic_forget_dynamic(result);return 1;
}
static int native_literal(const Compiler *c,uint32_t pc,unsigned input,unsigned *tag,uint64_t *bits) {
    const uint8_t *p=c->module->code+pc;
    const abc_dynamic_constant *literal=&c->module->dynamic_constants[abc_u32(p+2)];
    *bits=0;memcpy(bits,literal->payload,literal->length);
    /* Primitive scalar numbering and representation tags deliberately differ
       only beyond the numeric primitives. Do not use this for object types. */
    static const unsigned tags[]={ABC_ANY_UNIT,ABC_ANY_BOOL,ABC_ANY_U8,ABC_ANY_U16,ABC_ANY_U32,ABC_ANY_U64,ABC_ANY_I32,ABC_ANY_I64,ABC_ANY_F64};
    if(literal->kind>=sizeof tags/sizeof *tags)return 0;*tag=tags[literal->kind];
    if((literal->flags&1)&&abc_numeric_integer(input)){
        int source_signed=literal->kind==ABC_PRIM_I32||literal->kind==ABC_PRIM_I64;
        unsigned width=abc_numeric_width(input);
        if(abc_numeric_signed(input)){
            int64_t q=source_signed?abc_signed(*bits):*bits<=INT64_MAX?(int64_t)*bits:INT64_MIN;
            if(width==32?(q<INT32_MIN||q>INT32_MAX):(!source_signed&&*bits>INT64_MAX))return 0;
            *bits=(uint64_t)q;
        }else {
            if(source_signed&&abc_signed(*bits)<0)return 0;
            if(width<64&&*bits>((UINT64_C(1)<<width)-1))return 0;
        }
        *tag=input;
    }
    unsigned width=abc_numeric_width(*tag);
    if(width==8)*bits&=255;else if(width==16)*bits&=65535;
    else if(width==32)*bits=abc_numeric_signed(*tag)?(uint64_t)(int64_t)(int32_t)*bits:(uint32_t)*bits;
    return abc_numeric_result(EXT_DADD+(p[1]-EXT_DADDL),input,*tag)!=UINT_MAX;
}
static int native_scalar_body(Compiler *c,Context *x,uint32_t pc,abc_symbolic_dynamic *effect,unsigned tag,JValue *result) {
    unsigned selector=effect->selector;
    if(selector==EXT_ANY_CAST||selector==EXT_ANY_BOX){
        uint16_t want=abc_symbolic_test_tags(c->module,effect->descriptor);
        return native_scalar_cast(c,x,pc,tag,(unsigned)__builtin_ctz(want),result);
    }
    if(selector>=EXT_DADDL&&selector<=EXT_DXORL){
        unsigned literal_tag;uint64_t bits;if(!native_literal(c,pc,tag,&literal_tag,&bits))return 0;
        JValue literal=const_value(bits,JS_A,(int32_t)x->n[JS_A]);
        literal.dynamic_tags=(uint16_t)(1u<<literal_tag);literal.dynamic_repr=ABC_SYM_REPR_RAW;
        literal.dynamic_width=(uint8_t)abc_numeric_width(literal_tag);
        if(!push(x,JS_A,literal))return 0;
        uint32_t base=x->n[JS_A]-2;
        if(c->module->code[pc+6]){JValue q=x->s[JS_A][base];x->s[JS_A][base]=x->s[JS_A][base+1];x->s[JS_A][base+1]=q;}
        unsigned op=EXT_DADD+(selector-EXT_DADDL),out=abc_numeric_result(op,tag,literal_tag);
        int ok=native_numeric_body(c,x,pc,op,out,result);
        /* Restore the input stack shape expected by the symbolic instruction. */
        x->n[JS_A]--;
        result->dst_stack=JS_A;result->dst_home=(int32_t)base;return ok;
    }
    JValue *value=top(x,JS_A,0);if(!decode_numeric(c,x,value))return 0;
    int r=writable(c,x,value);if(r<0)return 0;
    if(selector==EXT_DREQUIRE_BOOL){*result=*value;abc_symbolic_forget_dynamic(result);return 1;}
    if(selector==EXT_DLNOT){
        /* ANY_BOX preserves bool payload bits; unlike typed LNOT, this is not
           XOR 1 unless a canonical 0/1 payload has also been proved. */
        JValue zero=const_value(0,JS_A,0);int rr=materialize_mask(c,x,&zero,1u<<(unsigned)r);
        if(rr<0||!place(c,ABC_STENCIL_BINARY(ABC_JOP_EQ,r,rr),0,NULL))return 0;
    }else {
        unsigned stencil=tag==ABC_ANY_F64?ABC_STENCIL_FLOAT_UNARY(ABC_JFUN_FNEG,r):
            ABC_STENCIL_UNARY(selector==EXT_DNEG?ABC_JUN_NEG:ABC_JUN_NOT,r);
        if(!place(c,stencil,0,NULL)||!native_normalize(c,(unsigned)r,tag))return 0;
    }
    *result=*value;
    if(selector==EXT_DLNOT)abc_symbolic_forget_dynamic(result);
    else {result->dynamic_tags=(uint16_t)(1u<<tag);result->dynamic_repr=ABC_SYM_REPR_RAW;result->dynamic_width=(uint8_t)abc_numeric_width(tag);}
    return 1;
}
static int native_scalar_cfg(NativeSymbolicSink *sink,uint32_t pc,abc_symbolic_dynamic *effect,uint16_t allowed) {
    Compiler *c=sink->compiler;Context *x=sink->machine->context;JValue *input=top(x,JS_A,0);
    uint16_t have=input->dynamic_tags?input->dynamic_tags:ABC_SYM_DYNAMIC_TAGS_UNKNOWN;
    uint16_t tags=have&allowed;
    if(have==tags&&tags&&!(tags&(tags-1)))return native_scalar_body(c,x,pc,effect,(unsigned)__builtin_ctz(tags),&effect->result[0]);
    uint64_t error=ABC_ABORT|(UINT64_C(6)<<8)|((uint64_t)pc<<16);
    if(!tags){if(!place(c,ABC_STENCIL_ABORT,error,NULL))return 0;sink->machine->exit=ABC_SYM_EXIT_TERMINATED;return 0;}
    TypeAliases aliases;if(!capture_aliases(x,*input,NULL,&aliases))return 0;
    int reg=native_scalar_tag(c,x,input,0);Fixup branches[16],mismatch;
    if(reg<0){free(aliases.bits);return 0;}
    for(unsigned tag=0;tag<16;tag++)if(tags&(1u<<tag)){
        JValue expected=const_value(tag,JS_A,0);int rr=materialize_mask(c,x,&expected,1u<<(unsigned)reg);
        if(rr<0||!local_branch(c,ABC_STENCIL_BRANCH(ABC_JBR_EQ,reg,rr),&branches[tag])){free(aliases.bits);return 0;}
    }
    if(!local_branch(c,ABC_STENCIL_JUMP,&mismatch)){free(aliases.bits);return 0;}
    uint32_t base=x->n[JS_A]-effect->pops,next=pc+abc_instruction_length(c->module->code+pc);
    for(unsigned tag=0;tag<16;tag++)if(tags&(1u<<tag)){
        bind_local(c,&branches[tag]);Context arm;if(!context_copy(&arm,x)){free(aliases.bits);return 0;}
        refine_aliases(&arm,&aliases,1,(uint16_t)(1u<<tag));abc_symbolic_dynamic leaf=*effect;
        int ok=native_scalar_body(c,&arm,pc,&leaf,tag,&leaf.result[0]);arm.n[JS_A]=base;
        if(ok&&effect->pushes)ok=push(&arm,JS_A,leaf.result[0]);
        if(ok)ok=emit_jump(c,edge(c,pc,next,&arm));context_free(&arm);
        if(!ok){free(aliases.bits);return 0;}
    }
    free(aliases.bits);bind_local(c,&mismatch);if(!place(c,ABC_STENCIL_ABORT,error,NULL))return 0;
    sink->machine->exit=ABC_SYM_EXIT_CONTROL;return 0;
}
