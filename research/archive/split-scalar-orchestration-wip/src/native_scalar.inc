/* Physical representation and CFG binding only. Scalar language operations
   execute in symbolic.c through generated ordinary-ABC compositions. */
static int native_scalar_arm(NativeSymbolicSink *sink,Context *x,uint32_t pc,abc_symbolic_dynamic *effect,unsigned tag) {
    Compiler *c=sink->compiler;abc_symbolic_machine machine=*sink->machine;
    NativeSymbolicSink local={c,&machine};machine.context=x;machine.sink=&local;
    machine.pc=pc;machine.extra_advance=0;machine.exit=ABC_SYM_EXIT_BLOCK;
    uint32_t base=x->n[JS_A]-effect->pops;abc_symbolic_dynamic leaf=*effect;
    if(!abc_symbolic_scalar_arm(&machine,&leaf,tag,&leaf.result[0]))return machine.exit==ABC_SYM_EXIT_TERMINATED;
    x->n[JS_A]=base;
    for(unsigned i=0;i<leaf.pushes;i++)if(!push(x,JS_A,leaf.result[i]))return 0;
    uint32_t next=pc+abc_instruction_length(c->module->code+pc);
    return emit_jump(c,edge(c,pc,next,x));
}
static int native_emit_scalar_value(void *opaque,uint32_t pc,unsigned op,unsigned descriptor,
        JValue *value,JValue *other,JValue *result) {
    NativeSymbolicSink *sink=opaque;Compiler *c=sink->compiler;Context *x=sink->machine->context;c->current_pc=pc;
    if(op==ABC_SYM_SCALAR_DECODE)return decode_numeric(c,x,value);
    if(op==ABC_SYM_SCALAR_CANONICAL){int r=writable(c,x,value);return r>=0&&place(c,ABC_STENCIL_FLOAT_CANON(r),0,NULL);}
    if(op==ABC_SYM_SCALAR_MIXED_EQ||op==ABC_SYM_SCALAR_STRING_EQ){
        int rd=writable(c,x,value);if(rd<0)return 0;
        int rs=materialize_mask(c,x,other,1u<<(unsigned)rd);if(rs<0)return 0;
        unsigned stencil=op==ABC_SYM_SCALAR_MIXED_EQ?ABC_STENCIL_NONNEG_EQ(rd,rs):ABC_STENCIL_STRING_EQ(rd,rs);
        if(!place(c,stencil,0,NULL))return 0;*result=*value;abc_symbolic_forget_dynamic(result);return 1;
    }
    abc_any_layout layout=abc_any_descriptor_layout(&c->module->descriptors[descriptor]);
    if(op==ABC_SYM_SCALAR_TEST){
        uint16_t want=abc_symbolic_test_tags(c->module,descriptor);uint32_t next=pc+abc_instruction_length(c->module->code+pc);
        if(want&&next<c->module->code_size&&!c->block[next]&&(c->module->code[next]==OP_JZ_A||c->module->code[next]==OP_JNZ_A))return native_type_branch(sink,pc,want);
    }
    int reg=layout.exact_descriptor?native_object_test(c,x,value,layout.object_kind,descriptor):
        native_type_test(c,x,value,(uint16_t)(1u<<layout.tag));
    if(reg<0)return 0;
    uint32_t base=x->n[JS_A]-1;
    if(op==ABC_SYM_SCALAR_TEST){*result=reg_value((unsigned)reg,JS_A,(int32_t)base);return 1;}
    Fixup valid;
    if(!local_branch(c,ABC_STENCIL_JNZ(reg),&valid)||!place(c,ABC_STENCIL_ABORT,ABC_ABORT|(UINT64_C(6)<<8)|((uint64_t)pc<<16),NULL))return 0;
    bind_local(c,&valid);int source=writable(c,x,value);if(source<0)return 0;
    if(layout.cells==2){
        int length=free_reg_mask(c,x,1u<<(unsigned)source);
        if(length<0||!place(c,ABC_STENCIL_MOV(length,source),0,NULL)||
           !place(c,ABC_STENCIL_MEM_LOAD(layout.width[1]==4?ABC_JLOAD_U32:ABC_JLOAD_U64,length),layout.offset[1],NULL))return 0;
        result[1]=reg_value((unsigned)length,JS_A,(int32_t)base+1);
    }
    if(!place(c,layout.address?ABC_STENCIL_IMMEDIATE(ABC_JIMM_ADD,source):ABC_STENCIL_MEM_LOAD(ABC_JLOAD_U64,source),layout.offset[0],NULL))return 0;
    result[0]=reg_value((unsigned)source,JS_A,(int32_t)base);return 1;
}
