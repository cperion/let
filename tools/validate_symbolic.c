#include "symbolic.h"
#include <stdio.h>
#include <math.h>

static int fail(const char *message) { fprintf(stderr,"symbolic validation: %s\n",message); return 1; }

static int emit_binary(void *sink,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        abc_symbolic_value left,abc_symbolic_value right,abc_symbolic_value *result) {
    unsigned *seen=sink;
    if(origin!=2||opcode!=ABC_OPERATION_MUL||destination!=ABC_SYM_A||folded||
            left.kind!=ABC_SYM_HOME||right.kind!=ABC_SYM_HOME)return 0;
    (*seen)++; *result=abc_symbolic_backend(70001,ABC_SYM_A,0); return 1;
}

static int emit_control(void *sink,uint32_t origin,const abc_symbolic_control *control) {
    unsigned *seen=sink;
    if(origin!=2||control->kind!=ABC_SYM_CONTROL_ZERO||!control->known||!control->taken||
            control->target!=8||control->fallthrough!=5)return 0;
    (*seen)++; return 1;
}

typedef struct { unsigned seen; } effect_state;
static int emit_memory(void *sink,uint32_t origin,abc_symbolic_memory *memory) {
    effect_state *state=sink;if(state->seen||origin!=0||memory->opcode!=OP_CALLOC||memory->cells)return 0;
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

typedef struct { unsigned selected_stack, floating, folded, seen; } binary_contract;
static int selected_binary(void *opaque,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        abc_symbolic_value left,abc_symbolic_value right,abc_symbolic_value *result) {
    binary_contract *contract=opaque;
    unsigned opposite_stack=destination==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A;
    if(origin!=0||destination!=contract->selected_stack||folded!=(int)contract->folded||
       opcode!=(contract->floating?ABC_OPERATION_FSUB:ABC_OPERATION_SUB))return 0;
    if(left.dst_stack!=destination||right.dst_stack!=opposite_stack||left.dst_home!=1||right.dst_home!=1)return 0;
    if(!folded) {
        if(left.kind!=ABC_SYM_HOME||right.kind!=ABC_SYM_HOME||left.stack!=destination||right.stack!=opposite_stack)return 0;
        *result=abc_symbolic_backend(70003,destination,1);
    }
    contract->seen++;return 1;
}
static int selected_binary_contracts(void) {
    for(unsigned floating=0;floating<2;floating++)for(unsigned selected=0;selected<2;selected++)for(unsigned folded=0;folded<2;folded++) {
        abc_symbolic_context context={0};binary_contract contract={selected,floating,folded,0};
        for(unsigned stack=0;stack<2;stack++) {
            uint64_t value=floating?vm_float_bits(stack?3.0:10.0):(stack?3:10);
            if(!abc_symbolic_push(&context,stack,abc_symbolic_constant(111+stack,stack,0))||
               !abc_symbolic_push(&context,stack,folded?abc_symbolic_constant(value,stack,1):abc_symbolic_home(stack,1)))
                return fail("selected binary context allocation");
        }
        abc_symbolic_machine machine={.context=&context,.sink=&contract,
            .emit_binary=selected_binary,.emit_float_binary=selected_binary};
        int success=floating?abc_symbolic_machine_float_binary(&machine,ABC_OPERATION_FSUB,selected):
                             abc_symbolic_machine_binary(&machine,ABC_OPERATION_SUB,selected);
        unsigned opposite=selected==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A;
        if(!success||contract.seen!=1||context.n[selected]!=2||context.n[opposite]!=1||
           context.s[ABC_SYM_A][0].constant!=111||context.s[ABC_SYM_B][0].constant!=112)
            return fail("selected-first binary callback or live-prefix preservation");
        abc_symbolic_value result=context.s[selected][1];
        if(folded) {
            uint64_t expected=floating?vm_float_bits(selected?-7.0:7.0):(selected?UINT64_MAX-6:7);
            if(result.kind!=ABC_SYM_CONST||result.constant!=expected)return fail("selected-first constant fold");
        } else if(result.kind!=ABC_SYM_BACKEND||result.reg!=70003)return fail("selected-first residual result");
        abc_symbolic_context_free(&context);
    }
    return 0;
}

typedef struct {
    unsigned selected, operation, relation, folded, taken, seen;
    uint64_t left, right;
} float_branch_contract;
static int selected_float_branch(void *opaque,uint32_t origin,const abc_symbolic_control *control) {
    float_branch_contract *c=opaque;
    if(origin||control->kind!=ABC_SYM_CONTROL_FLOAT||control->opcode!=c->operation||
       control->relation!=c->relation||control->reverse||control->known!=c->folded||
       control->target!=5||control->fallthrough!=3)return 0;
    if(c->folded) {
        if(control->taken!=c->taken||control->left.constant!=c->left||control->right.constant!=c->right)return 0;
    } else if(control->left.kind!=ABC_SYM_HOME||control->right.kind!=ABC_SYM_HOME||
              control->left.stack!=c->selected||control->right.stack!=(c->selected^1)||
              control->left.home!=1||control->right.home!=1)return 0;
    c->seen++;return 1;
}
static int float_branch_contracts(void) {
    const struct { double left,right; unsigned truth[3]; } cases[]={
        {1.5,2.0,{1,1,0}}, {2.0,2.0,{0,1,1}}, {3.5,2.0,{0,0,0}},
        {NAN,2.0,{0,0,0}}, {2.0,NAN,{0,0,0}}, {-0.0,0.0,{0,1,1}},
        {0.0,-0.0,{0,1,1}}, {-INFINITY,INFINITY,{1,1,0}}
    };
    const unsigned opcodes[]={OP_FBLT_A,OP_FBLE_A,OP_FBEQ_A};
    const unsigned operations[]={ABC_OPERATION_FBLT,ABC_OPERATION_FBLE,ABC_OPERATION_FBEQ};
    const unsigned relations[]={ABC_SYM_LT,ABC_SYM_LE,ABC_SYM_EQ};
    for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);i++)
    for(unsigned op=0;op<3;op++)for(unsigned bank=0;bank<2;bank++)for(unsigned folded=0;folded<2;folded++) {
        uint8_t code[]={(uint8_t)(opcodes[op]+bank),2,0,0,0,0};
        float_branch_contract contract={bank,operations[op],relations[op],folded,cases[i].truth[op],0,
            vm_float_bits(cases[i].left),vm_float_bits(cases[i].right)};
        abc_symbolic_context context={0};
        for(unsigned stack=0;stack<2;stack++) {
            uint64_t bits=stack==bank?contract.left:contract.right;
            if(!abc_symbolic_push(&context,stack,abc_symbolic_constant(111+stack,stack,0))||
               !abc_symbolic_push(&context,stack,folded?abc_symbolic_constant(bits,stack,1):abc_symbolic_home(stack,1)))
                return fail("float branch context allocation");
        }
        abc_error error;
        abc_symbolic_machine machine={.context=&context,.code=code,.end=sizeof(code),.sink=&contract,
            .error=&error,.emit_control=selected_float_branch};
        if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL||contract.seen!=1||
           context.n[0]!=1||context.n[1]!=1||context.s[0][0].constant!=111||context.s[1][0].constant!=112)
            return fail("generated float relation, constant fold, operand order or prefix preservation");
        abc_symbolic_context_free(&context);
    }
    return 0;
}

typedef struct { unsigned selected_stack, action, seen; } memory_contract;
static int selected_memory(void *opaque,uint32_t origin,abc_symbolic_memory *memory) {
    memory_contract *contract=opaque;
    unsigned selected=contract->selected_stack,opposite=selected==ABC_SYM_A?ABC_SYM_B:ABC_SYM_A;
    if(origin||memory->stack!=selected||memory->action!=contract->action||
       memory->first.kind!=ABC_SYM_HOME||memory->first.stack!=selected||memory->first.home!=1||
       memory->second.kind!=ABC_SYM_HOME||memory->second.stack!=opposite||memory->second.home!=1)return 0;
    memory->result=abc_symbolic_backend(70004,selected,1);contract->seen++;return 1;
}
static int selected_memory_contracts(void) {
    const unsigned opcodes[]={OP_ST64_A,OP_LDX64_A,OP_IDX_A,OP_MEMCPY_A};
    const unsigned actions[]={M_PSTORE,M_XLOAD,M_INDEX,M_COPY};
    for(unsigned operation=0;operation<4;operation++)for(unsigned selected=0;selected<2;selected++) {
        uint8_t code[]={(uint8_t)(opcodes[operation]+selected),8,0,0,0};
        abc_symbolic_context context={0};memory_contract contract={selected,actions[operation],0};
        for(unsigned stack=0;stack<2;stack++)
            if(!abc_symbolic_push(&context,stack,abc_symbolic_constant(111+stack,stack,0))||
               !abc_symbolic_push(&context,stack,abc_symbolic_home(stack,1)))return fail("memory context allocation");
        abc_symbolic_machine machine={.code=code,.end=sizeof code,.context=&context,
            .sink=&contract,.emit_memory=selected_memory};
        unsigned result=actions[operation]==M_XLOAD||actions[operation]==M_INDEX;
        if(!abc_symbolic_machine_memory(&machine)||contract.seen!=1||context.n[selected]!=1+result||
           context.n[1-selected]!=1||context.s[ABC_SYM_A][0].constant!=111||context.s[ABC_SYM_B][0].constant!=112)
            return fail("selected-address memory transfer or live-prefix preservation");
        if(result&&(context.s[selected][1].kind!=ABC_SYM_BACKEND||context.s[selected][1].reg!=70004||
                    context.s[selected][1].dst_stack!=selected||context.s[selected][1].dst_home!=1))
            return fail("selected memory result placement");
        abc_symbolic_context_free(&context);
    }
    return 0;
}

typedef struct { unsigned caller, source, tail, calls, returns, edges; } transport_contract;
static int transport_call(void *opaque,uint32_t origin,abc_symbolic_call *call) {
    transport_contract *contract=opaque;
    if(origin||call->destination!=contract->caller||call->arguments!=2||call->results!=2||
       call->continuation.abase!=1||call->continuation.bbase!=1)return 0;
    call->virtualize=1;contract->calls++;return 1;
}
static int transport_tail(void *opaque,uint32_t origin,abc_symbolic_tail *tail) {
    transport_contract *contract=opaque;
    return origin==12&&tail->argument_stack==1-contract->caller&&tail->arguments==2&&tail->frame_cells==2;
}
static int transport_return(void *opaque,uint32_t origin,const abc_symbolic_return *result) {
    transport_contract *contract=opaque;
    if(origin!=(contract->tail?22u:12u)||result->terminal||result->results!=2||result->source_stack!=contract->source)return 0;
    contract->returns++;return 1;
}
static int transport_edge(void *opaque,uint32_t origin,uint32_t target) {
    transport_contract *contract=opaque;
    unsigned expected=contract->edges==0?9:contract->tail&&contract->edges==1?19:6;
    (void)origin;if(target!=expected)return 0;contract->edges++;return 1;
}
static int transport_contracts(void) {
    for(unsigned caller=0;caller<2;caller++)for(unsigned source=0;source<2;source++)for(unsigned tail=0;tail<2;tail++) {
        uint8_t code[25]={(uint8_t)(OP_CALL_A+caller),3,0,0,0,2,OP_RET_A,0,0};
        unsigned argument_stack=tail?1-caller:source;
        code[9]=(uint8_t)(OP_CGETR_A+argument_stack);code[10]=0;code[11]=2;
        if(tail){code[12]=(uint8_t)(OP_TCALL_A+argument_stack);code[17]=2;code[18]=2;
            code[19]=(uint8_t)(OP_CGETR_A+source);code[20]=0;code[21]=2;}
        unsigned end=tail?25:15,ret=end-3;
        code[ret]=(uint8_t)(OP_RET_A+source);code[ret+1]=2;code[ret+2]=2;
        abc_function functions[]={{.entry=0,.end=9},{.entry=9,.end=tail?19:15,.arguments=2,.results=2},
            {.entry=19,.end=25,.arguments=2,.results=2}};
        abc_module module={.code=code,.code_size=end,.functions=functions,.function_count=tail?3:2};
        abc_symbolic_context context={0};transport_contract contract={caller,source,tail,0,0,0};
        for(unsigned stack=0;stack<2;stack++)if(!abc_symbolic_push(&context,stack,abc_symbolic_constant(111+stack,stack,0)))return fail("transport prefix allocation");
        if(!abc_symbolic_push(&context,caller,abc_symbolic_constant(7,caller,1))||
           !abc_symbolic_push(&context,caller,abc_symbolic_constant(3,caller,2)))return fail("transport argument allocation");
        abc_symbolic_machine machine={.module=&module,.code=code,.end=end,.context=&context,.sink=&contract,
            .emit_call=transport_call,.emit_return=transport_return,.emit_tail=transport_tail,.emit_edge=transport_edge};
        if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL||context.ncont!=1)return fail("selected virtual call");
        machine.pc=9;
        if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL)return fail("selected callee transport");
        if(tail){if(context.ncont!=1)return fail("tail replaced continuation");machine.pc=19;
            if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL)return fail("selected tail return");}
        if(contract.calls!=1||contract.returns!=1||contract.edges!=2+tail||context.ncont||context.n[ABC_SYM_C]||
           context.n[caller]!=3||context.n[1-caller]!=1||context.s[caller][1].constant!=7||context.s[caller][2].constant!=3||
           context.s[ABC_SYM_A][0].constant!=111||context.s[ABC_SYM_B][0].constant!=112)return fail("independent CALL/RET vector contract");
        abc_symbolic_context_free(&context);
    }
    return 0;
}
static int selected_scalar_forms(void) {
    for(unsigned selected=0;selected<2;selected++)for(unsigned extended=0;extended<2;extended++) {
        uint8_t scalar[]={(uint8_t)(OP_PUSH8_A+selected),3,(uint8_t)(OP_PUSH8_A+1-selected),2,
            (uint8_t)(OP_POW_A+selected),(uint8_t)(OP_CHKU8_A+selected),(uint8_t)(OP_I2FU_A+selected),
            (uint8_t)(OP_FNEG_A+selected),(uint8_t)(OP_FNEG_A+selected),(uint8_t)(OP_F2IU_A+selected),
            (uint8_t)(OP_RET_A+selected),0,1};
        uint8_t context_operand[]={(uint8_t)(OP_PUSH8_A+selected),3,(uint8_t)(OP_CPUSHN_A+selected),1,
            (uint8_t)(OP_PUSH8_A+selected),10,(uint8_t)(OP_EXT_A+selected),EXT_SUBC,0,OP_CPOP,
            (uint8_t)(OP_RET_A+selected),0,1};
        abc_symbolic_context context={0};
        abc_symbolic_machine machine={.code=extended?context_operand:scalar,.end=sizeof scalar,.context=&context};
        if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BOUNDARY||machine.pc!=10||context.n[selected]!=1||
           context.n[1-selected]||context.n[ABC_SYM_C]||context.s[selected][0].kind!=ABC_SYM_CONST||
           context.s[selected][0].constant!=(extended?7u:9u))return fail("selected scalar/EXT dispatch");
        abc_symbolic_context_free(&context);
    }
    if(abc_symbolic_fold_unary(ABC_OPERATION_ZX8,UINT64_MAX)!=255||
       abc_symbolic_fold_unary(ABC_OPERATION_ZX16,UINT64_MAX)!=65535)return fail("shared narrow unary folds");
    return 0;
}
int main(void) {
    int ok=0;
    if(selected_binary_contracts()||float_branch_contracts()||selected_memory_contracts()||transport_contracts()||selected_scalar_forms())return 1;
    if(ABC_BLOCK_VERSION_LIMIT!=8) return fail("block version limit changed");
    if(ABC_OPTIMIZER_PATH_LIMIT!=4096) return fail("optimizer path limit changed");
    uint8_t constant_code[]={OP_PUSH8_A,40,OP_PUSH8_B,2,OP_ADD_A,OP_NEG_A,OP_NOT_A,OP_RET_A,0,1};
    abc_symbolic_context dispatched={0};
    abc_symbolic_machine machine={.code=constant_code,.pc=0,.end=sizeof constant_code,.context=&dispatched};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BOUNDARY||machine.pc!=7||
            dispatched.n[ABC_SYM_A]!=1||dispatched.n[ABC_SYM_B]!=0||
            dispatched.s[ABC_SYM_A][0].kind!=ABC_SYM_CONST||dispatched.s[ABC_SYM_A][0].constant!=41)
        return fail("generated constant tail dispatch");
    abc_symbolic_context_free(&dispatched);

    uint8_t operand_code[]={OP_PUSH8_A,5,OP_ADDI_A,3,OP_CPUSH_A,OP_PUSH8_A,7,OP_EXT_A,EXT_ADDC,0,OP_RET_A,1,1};
    abc_symbolic_context operands={0};
    machine=(abc_symbolic_machine){.code=operand_code,.pc=0,.end=sizeof operand_code,.context=&operands};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BOUNDARY||machine.pc!=10||
            operands.n[ABC_SYM_A]!=1||operands.n[ABC_SYM_C]!=1||
            operands.s[ABC_SYM_A][0].kind!=ABC_SYM_CONST||operands.s[ABC_SYM_A][0].constant!=15)
        return fail("generated immediate/C-operand tail dispatch");
    abc_symbolic_context_free(&operands);

    uint8_t control_code[]={OP_PUSH8_A,0,OP_JZ_A,3,0,OP_RET_A,0,0,OP_RET_A,0,0};
    abc_symbolic_context controlled={0}; unsigned controls=0;
    machine=(abc_symbolic_machine){.code=control_code,.pc=0,.end=sizeof control_code,
.context=&controlled,.sink=&controls,.emit_control=emit_control};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL||machine.pc!=2||controls!=1||
            controlled.n[ABC_SYM_A]!=0)return fail("generated control tail dispatch");
    abc_symbolic_context_free(&controlled);

    uint8_t effect_code[]={OP_CALLOC,0,0};
    abc_symbolic_context effected={0};effect_state effects={0};
    if(!abc_symbolic_push(&effected,ABC_SYM_A,abc_symbolic_constant(7,ABC_SYM_A,0)))return fail("memory test allocation");
    machine=(abc_symbolic_machine){.code=effect_code,.pc=0,.end=sizeof effect_code,
        .context=&effected,.sink=&effects,.emit_memory=emit_memory};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BLOCK||machine.pc!=3||effects.seen!=1||effected.n[ABC_SYM_A]!=1||
            effected.s[ABC_SYM_A][0].kind!=ABC_SYM_CONST||effected.s[ABC_SYM_A][0].constant!=7)
        return fail("generated memory effect preserves live operand");
    abc_symbolic_context_free(&effected);

    uint8_t call_code[]={OP_CALL_A,3,0,0,0,1,OP_RET_A,1,1,OP_CGET0_A,OP_RET_A,1,1};
    abc_function call_functions[2]={{.entry=0,.end=9,.arguments=1,.results=1},{.entry=9,.end=13,.arguments=1,.results=1}};
    abc_module call_module={.code=call_code,.code_size=sizeof call_code,.functions=call_functions,.function_count=2};
    abc_symbolic_context called={0};call_state calls={0};
    if(!abc_symbolic_push(&called,ABC_SYM_C,abc_symbolic_home(ABC_SYM_C,-1))||!abc_symbolic_push(&called,ABC_SYM_A,abc_symbolic_constant(42,ABC_SYM_A,0)))return fail("call context allocation");
    called.c_origin=1;machine=(abc_symbolic_machine){.module=&call_module,.code=call_code,.pc=0,.end=sizeof call_code,.context=&called,.sink=&calls,.emit_call=emit_call,.emit_return=emit_return,.emit_edge=emit_edge};
    if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL||calls.calls!=1||calls.edges!=1||calls.edge[0]!=9||called.ncont!=1||called.n[ABC_SYM_A]||called.n[ABC_SYM_C]!=2)return fail("shared direct-call transition");
    machine.pc=9;if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_CONTROL||calls.returns!=1||calls.edges!=2||calls.edge[1]!=6||called.ncont||called.n[ABC_SYM_A]!=1||called.n[ABC_SYM_C]!=1)return fail("shared virtual-return transition");
    machine.pc=6;if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_TERMINATED||calls.returns!=2)return fail("shared terminal-return transition");
    abc_symbolic_context_free(&called);

    uint8_t residual_code[]={OP_CGET0_A,OP_CGET0_B,OP_MUL_A,OP_RET_A,1,1};
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
    uint8_t fused_code[3][7]={{OP_ADD_A,OP_ZX32_A,OP_RET_A,0,1},
        {OP_ADDI_A,1,OP_ZX32_A,OP_RET_A,0,1},{OP_EXT_A,EXT_ADDC,0,OP_ZX32_A,OP_RET_A,1,1}};
    for(unsigned i=0;i<3;i++) {
        abc_symbolic_context fused={0};
        for(unsigned s=0;s<3;s++)if(!abc_symbolic_push(&fused,s,abc_symbolic_home(s,0)))return fail("fused context allocation");
        machine=(abc_symbolic_machine){.code=fused_code[i],.end=5+i,.context=&fused,.transfer_mask=ABC_SYM_TRANSFER_VALUE,
            .emit_binary=emit_fused,.emit_immediate=emit_fused_immediate,.emit_c_operand=emit_fused};
        machine.sink=&machine;
        if(abc_symbolic_dispatch(&machine)!=ABC_SYM_EXIT_BOUNDARY||machine.pc!=i+2||
           fused.s[ABC_SYM_A][0].kind!=ABC_SYM_BACKEND||fused.s[ABC_SYM_A][0].reg!=70002)
            return fail("fused transfer lost its result or source advance");
        abc_symbolic_context_free(&fused);
    }
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
    if(abc_symbolic_fold_binary(ABC_OPERATION_ADD,40,2,&ok)!=42 || !ok) return fail("integer addition fold");
    if(abc_symbolic_fold_binary(ABC_OPERATION_MUL,6,7,&ok)!=42 || !ok) return fail("integer multiplication fold");
    (void)abc_symbolic_fold_binary(ABC_OPERATION_DIVU,1,0,&ok);
    if(ok) return fail("zero divisor must not fold");
    if(abc_symbolic_fold_binary(ABC_OPERATION_DIVS,UINT64_C(0x8000000000000000),UINT64_MAX,&ok)
            !=UINT64_C(0x8000000000000000) || !ok) return fail("signed overflow semantics");
    if(abc_symbolic_fold_binary(ABC_OPERATION_SHL,1,64,&ok)!=0 || !ok) return fail("wide shift semantics");
    if(!abc_symbolic_branch(ABC_SYM_LT,UINT64_MAX,1)) return fail("signed branch");
    if(abc_symbolic_branch(ABC_SYM_LTU,UINT64_MAX,1)) return fail("unsigned branch");
    uint64_t one=vm_float_bits(1.0),two=vm_float_bits(2.0);
    if(abc_symbolic_fold_float(ABC_OPERATION_FADD,one,two)!=vm_float_bits(3.0)) return fail("float addition fold");
    uint64_t nan=vm_float_bits(NAN);
    if(abc_symbolic_fold_float(ABC_OPERATION_FEQ,nan,nan)!=0) return fail("NaN comparison semantics");
    puts("validated revision-6 symbolic dispatch: 28 selected-bank contracts, 96 float branch dispatch/fold contracts, narrow folds, existing control/context/fusion regressions");
    return 0;
}

