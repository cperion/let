#include "symbolic.h"
#include "dynamic.h"
#include <stdio.h>
#include <math.h>

static int fail(const char *message) { fprintf(stderr,"symbolic validation: %s\n",message); return 1; }

static int emit_binary(void *sink,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        abc_symbolic_value left,abc_symbolic_value right,abc_symbolic_value *result) {
    unsigned *seen=sink;
    if(origin!=2||opcode!=OP_MUL_A||destination!=ABC_SYM_A||folded||
            left.kind!=ABC_SYM_HOME||right.kind!=ABC_SYM_HOME)return 0;
    (*seen)++; *result=abc_symbolic_backend(70001,ABC_SYM_A,0); return 1;
}

static int emit_control(void *sink,uint32_t origin,const abc_symbolic_control *control) {
    unsigned *seen=sink;
    if(origin!=2||control->kind!=ABC_SYM_CONTROL_ZERO||!control->known||!control->taken||
            control->target!=6||control->fallthrough!=5)return 0;
    (*seen)++; return 1;
}

typedef struct { unsigned seen; } effect_state;
static int emit_dynamic(void *sink,uint32_t origin,abc_symbolic_dynamic *dynamic) {
    effect_state *state=sink;if(state->seen||origin!=0||dynamic->selector!=EXT_ANY_BOX||dynamic->descriptor!=0||dynamic->pops!=1||dynamic->pushes!=1||
            dynamic->result[0].dynamic_tags!=(1u<<ABC_ANY_U32)||dynamic->result[0].dynamic_width!=32||dynamic->result[0].dynamic_repr!=ABC_SYM_REPR_ENCODED)return 0;
    state->seen++;return 1;
}
static int emit_memory(void *sink,uint32_t origin,abc_symbolic_memory *memory) {
    effect_state *state=sink;if(state->seen!=1||origin!=6||memory->opcode!=OP_CALLOC||memory->cells)return 0;
    state->seen++;return 1;
}

typedef struct { unsigned calls, returns, edges; uint32_t edge[2]; } call_state;
static int emit_call(void *sink,uint32_t origin,abc_symbolic_call *call) {
    call_state *state=sink;if(origin||call->target!=9||call->arguments!=1||call->results!=1||call->destination!=ABC_SYM_A||call->continuation.return_pc!=6)return 0;
    state->calls++;call->virtualize=1;return 1;
}
static int emit_return(void *sink,uint32_t origin,const abc_symbolic_return *effect) {
    call_state *state=sink;if((origin==10&&effect->terminal)||(origin==6&&!effect->terminal)||effect->results!=1)return 0;state->returns++;return 1;
}
static int emit_edge(void *sink,uint32_t origin,uint32_t target) {
    call_state *state=sink;if(state->edges>=2||(origin!=0&&origin!=10))return 0;state->edge[state->edges++]=target;return 1;
}

static int emit_fused(void *sink,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        abc_symbolic_value left,abc_symbolic_value right,abc_symbolic_value *result) {
    abc_symbolic_machine *m=sink;m->extra_advance=1;*result=abc_symbolic_backend(70002,destination,0);
    (void)origin;(void)opcode;(void)folded;(void)left;(void)right;return 1;
}
static int emit_fused_immediate(void *sink,uint32_t origin,unsigned opcode,unsigned stack,uint64_t immediate,
        int folded,abc_symbolic_value input,abc_symbolic_value *result) {
    return emit_fused(sink,origin,opcode,stack,folded,input,abc_symbolic_constant(immediate,stack,0),result);
}

int main(void) {
    int ok=0;
    if(ABC_BLOCK_VERSION_LIMIT!=8) return fail("block version limit changed");
    if(ABC_OPTIMIZER_PATH_LIMIT!=4096) return fail("optimizer path limit changed");
    uint8_t constant_code[]={OP_PUSH8_A,40,OP_PUSH8_B,2,OP_ADD_A,OP_NEG_A,OP_NOT_A,OP_RET,0,1};
    abc_symbolic_context dispatched={0};
    abc_symbolic_machine machine={.code=constant_code,.pc=0,.end=sizeof constant_code,.context=&dispatched};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BOUNDARY||machine.pc!=7||
            dispatched.n[ABC_SYM_A]!=1||dispatched.n[ABC_SYM_B]!=0||
            dispatched.s[ABC_SYM_A][0].kind!=ABC_SYM_CONST||dispatched.s[ABC_SYM_A][0].constant!=41)
        return fail("generated constant tail dispatch");
    abc_symbolic_context_free(&dispatched);

    uint8_t operand_code[]={OP_PUSH8_A,5,OP_ADDI_A,3,OP_CPUSH_A,OP_PUSH8_A,7,OP_ADDC_A,0,OP_RET,1,1};
    abc_symbolic_context operands={0};
    machine=(abc_symbolic_machine){.code=operand_code,.pc=0,.end=sizeof operand_code,.context=&operands};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BOUNDARY||machine.pc!=9||
            operands.n[ABC_SYM_A]!=1||operands.n[ABC_SYM_C]!=1||
            operands.s[ABC_SYM_A][0].kind!=ABC_SYM_CONST||operands.s[ABC_SYM_A][0].constant!=15)
        return fail("generated immediate/C-operand tail dispatch");
    abc_symbolic_context_free(&operands);

    uint8_t control_code[]={OP_PUSH8_A,0,OP_JZ_A,1,0,OP_RET,OP_RET};
    abc_symbolic_context controlled={0}; unsigned controls=0;
    machine=(abc_symbolic_machine){.code=control_code,.pc=0,.end=sizeof control_code,
.context=&controlled,.sink=&controls,.emit_control=emit_control};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL||machine.pc!=2||controls!=1||
            controlled.n[ABC_SYM_A]!=0)return fail("generated control tail dispatch");
    abc_symbolic_context_free(&controlled);

    uint8_t effect_code[]={OP_EXT,EXT_ANY_BOX,0,0,0,0,OP_CALLOC,0,0};
    uint8_t primitive=ABC_PRIM_U32;abc_descriptor descriptor={.tag=ABC_DESC_PRIMITIVE,.length=1,.payload=&primitive};
    abc_module effect_module={.descriptors=&descriptor,.descriptor_count=1};
    abc_symbolic_context effected={0};effect_state effects={0};
    if(!abc_symbolic_push(&effected,ABC_SYM_A,abc_symbolic_constant(7,ABC_SYM_A,0)))return fail("dynamic test allocation");
    machine=(abc_symbolic_machine){.module=&effect_module,.code=effect_code,.pc=0,.end=sizeof effect_code,
        .context=&effected,.sink=&effects,.emit_dynamic=emit_dynamic,.emit_memory=emit_memory};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BLOCK||machine.pc!=9||effects.seen!=2||effected.n[ABC_SYM_A]!=1||
            effected.s[ABC_SYM_A][0].dynamic_tags!=(1u<<ABC_ANY_U32)||effected.s[ABC_SYM_A][0].dynamic_width!=32||effected.s[ABC_SYM_A][0].dynamic_repr!=ABC_SYM_REPR_ENCODED)
        return fail("generated dynamic fact propagation and variable EXT length");
    abc_symbolic_context_free(&effected);

    uint8_t call_code[]={OP_CALL_A,3,0,0,0,1,OP_RET,1,1,OP_CGET0_A,OP_RET,1,1};
    abc_function call_functions[2]={{.entry=0,.end=9,.arguments=1,.results=1},{.entry=9,.end=13,.arguments=1,.results=1}};
    abc_module call_module={.code=call_code,.code_size=sizeof call_code,.functions=call_functions,.function_count=2};
    abc_symbolic_context called={0};call_state calls={0};
    if(!abc_symbolic_push(&called,ABC_SYM_C,abc_symbolic_home(ABC_SYM_C,-1))||!abc_symbolic_push(&called,ABC_SYM_A,abc_symbolic_constant(42,ABC_SYM_A,0)))return fail("call context allocation");
    called.c_origin=1;machine=(abc_symbolic_machine){.module=&call_module,.code=call_code,.pc=0,.end=sizeof call_code,.context=&called,.sink=&calls,.emit_call=emit_call,.emit_return=emit_return,.emit_edge=emit_edge};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL||calls.calls!=1||calls.edges!=1||calls.edge[0]!=9||called.ncont!=1||called.n[ABC_SYM_A]||called.n[ABC_SYM_C]!=2)return fail("shared direct-call transition");
    machine.pc=9;if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL||calls.returns!=1||calls.edges!=2||calls.edge[1]!=6||called.ncont||called.n[ABC_SYM_A]!=1||called.n[ABC_SYM_C]!=1)return fail("shared virtual-return transition");
    machine.pc=6;if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_TERMINATED||calls.returns!=2)return fail("shared terminal-return transition");
    abc_symbolic_context_free(&called);

    uint8_t residual_code[]={OP_CGET0_A,OP_CGET0_B,OP_MUL_A,OP_RET,1,1};
    abc_symbolic_context residual={0}; unsigned emitted=0;
    if(!abc_symbolic_push(&residual,ABC_SYM_C,abc_symbolic_home(ABC_SYM_C,0)))
        return fail("residual context allocation");
    machine=(abc_symbolic_machine){.code=residual_code,.pc=0,.end=sizeof residual_code,
        .context=&residual,.sink=&emitted,.emit_binary=emit_binary};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BOUNDARY||machine.pc!=3||emitted!=1||
            residual.n[ABC_SYM_A]!=1||residual.n[ABC_SYM_B]!=0||
            residual.s[ABC_SYM_A][0].kind!=ABC_SYM_BACKEND||residual.s[ABC_SYM_A][0].reg!=70001)
        return fail("generated residual-node tail dispatch");
    abc_symbolic_context_free(&residual);
    uint8_t fused_code[3][6]={{OP_ADD_A,OP_ZX32_A,OP_RET,0,1,0},
        {OP_ADDI_A,1,OP_ZX32_A,OP_RET,0,1},{OP_ADDC_A,0,OP_ZX32_A,OP_RET,1,1}};
    for(unsigned i=0;i<3;i++) {
        abc_symbolic_context fused={0};
        for(unsigned s=0;s<3;s++)if(!abc_symbolic_push(&fused,s,abc_symbolic_home(s,0)))return fail("fused context allocation");
        machine=(abc_symbolic_machine){.code=fused_code[i],.end=i?6:5,.context=&fused,.transfer_mask=ABC_SYM_TRANSFER_VALUE,
            .emit_binary=emit_fused,.emit_immediate=emit_fused_immediate,.emit_c_operand=emit_fused};
        machine.sink=&machine;
        if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BOUNDARY||machine.pc!=(i?3u:2u)||
           fused.s[ABC_SYM_A][0].dynamic_width!=32||!fused.s[ABC_SYM_A][0].zero_extended||fused.s[ABC_SYM_A][0].dynamic_tags||
           fused.s[ABC_SYM_A][0].dynamic_repr!=ABC_SYM_REPR_NONE)return fail("fused normalization lost width postcondition");
        abc_symbolic_context_free(&fused);
    }
    abc_symbolic_value unknown=abc_symbolic_home(ABC_SYM_A,0),wide=unknown,narrow=unknown;int certain=0,matches=0;
    abc_symbolic_numeric_fact(&wide,(uint16_t)(1u<<ABC_ANY_U64));
    abc_symbolic_numeric_fact(&narrow,(uint16_t)(1u<<ABC_ANY_U32));
    if(abc_symbolic_numeric_results(EXT_DADD,unknown,wide,&certain)!=(1u<<ABC_ANY_U64)||certain)
        return fail("numeric successful postcondition is not an entry proof");
    if(abc_symbolic_numeric_results(EXT_DADD,narrow,narrow,&certain)!=(1u<<ABC_ANY_U32)||!certain)
        return fail("numeric entry proof");
    if(!abc_symbolic_dynamic_test(&effect_module,0,narrow,&matches)||!matches||
       !abc_symbolic_dynamic_test(&effect_module,0,wide,&matches)||matches||
       abc_symbolic_dynamic_test(&effect_module,0,unknown,&matches))return fail("primitive type test folding");
    unknown.dynamic_tags=(uint16_t)~(1u<<ABC_ANY_U32);
    if(!abc_symbolic_dynamic_test(&effect_module,0,unknown,&matches)||matches)return fail("negative type test fact");
    abc_symbolic_value normalized=abc_symbolic_home(ABC_SYM_A,0);normalized.dynamic_width=32;
    if(abc_symbolic_dynamic_box_specialization(&effect_module,0,normalized))return fail("signed normalization is not unsigned range proof");
    normalized.zero_extended=1;
    if(!abc_symbolic_dynamic_box_specialization(&effect_module,0,normalized))return fail("zero extension proves immediate boxing range");
    narrow.dynamic_repr=ABC_SYM_REPR_RAW;
    if(!abc_symbolic_dynamic_cast_matches(&effect_module,0,narrow))return fail("exact raw cast");
    narrow.dynamic_repr=ABC_SYM_REPR_ENCODED;
    if(abc_symbolic_dynamic_cast_matches(&effect_module,0,narrow))return fail("a tag alone does not prove raw representation");
    abc_symbolic_context context={0},copy={0};
    abc_symbolic_value input=abc_symbolic_home(ABC_SYM_C,-1);
    abc_symbolic_value node=abc_symbolic_backend(70000,ABC_SYM_A,0);
    abc_symbolic_continuation continuation={12,24,1,2,3,-4,5,ABC_SYM_A};
    if(!abc_symbolic_push(&context,ABC_SYM_C,input)||!abc_symbolic_push(&context,ABC_SYM_A,node)||
            !abc_symbolic_push_continuation(&context,continuation)||!abc_symbolic_context_copy(&copy,&context))
        return fail("context allocation/copy");
    if(!abc_symbolic_context_equal(&context,&copy)||copy.s[ABC_SYM_A][0].reg!=70000)
        return fail("context equality or sink payload");
    copy.generic=1;
    if(abc_symbolic_context_equal(&context,&copy)||!abc_symbolic_context_family_equal(&context,&copy))
        return fail("context family equality");
    abc_symbolic_value popped=abc_symbolic_pop(&copy,ABC_SYM_A);
    if(popped.reg!=70000||copy.n[ABC_SYM_A]!=0) return fail("symbolic stack pop");
    abc_symbolic_context_free(&context); abc_symbolic_context_free(&copy);
    if(abc_symbolic_fold_binary(OP_ADD_A,40,2,&ok)!=42 || !ok) return fail("integer addition fold");
    if(abc_symbolic_fold_binary(OP_MUL_A,6,7,&ok)!=42 || !ok) return fail("integer multiplication fold");
    (void)abc_symbolic_fold_binary(OP_DIVU_A,1,0,&ok);
    if(ok) return fail("zero divisor must not fold");
    if(abc_symbolic_fold_binary(OP_DIVS_A,UINT64_C(0x8000000000000000),UINT64_MAX,&ok)
            !=UINT64_C(0x8000000000000000) || !ok) return fail("signed overflow semantics");
    if(abc_symbolic_fold_binary(OP_SHL_A,1,64,&ok)!=0 || !ok) return fail("wide shift semantics");
    if(!abc_symbolic_branch(ABC_SYM_LT,UINT64_MAX,1)) return fail("signed branch");
    if(abc_symbolic_branch(ABC_SYM_LTU,UINT64_MAX,1)) return fail("unsigned branch");
    uint64_t one=vm_float_bits(1.0),two=vm_float_bits(2.0);
    if(abc_symbolic_fold_float(OP_FADD_A,one,two)!=vm_float_bits(3.0)) return fail("float addition fold");
    uint64_t nan=vm_float_bits(NAN);
    if(abc_symbolic_fold_float(OP_FEQ_A,nan,nan)!=0) return fail("NaN comparison semantics");
    puts("validated generated symbolic dispatch, call/return transitions, effects, shared contexts, folding, branches, and local block-version limit");
    return 0;
}

