#include "symbolic.h"
#include "dynamic.h"

/* The ABC optimizer is the second symbolic-VM sink. It builds integer value
 * and ordered trap/check/abort DAGs, then canonically re-projects them to A/B/C
 * bytecode. Unsupported regions remain verified input functions, independently. */

typedef enum { N_INPUT, N_LOOP_HOME, N_BINARY, N_UNARY, N_CHECK, N_ABORT, N_EFFECT, N_MEMORY, N_DYNAMIC, N_FOREIGN, N_CALLABLE, N_DYNCALLABLE, N_CALL, N_TAIL, N_RESULT } NodeKind;
typedef struct {
    NodeKind kind;
    uint32_t origin, left, right;
    uint16_t opcode;
    uint8_t input;
    uint16_t ershov;
    uint8_t effect;
} Node;
typedef struct { uint32_t node, count; uint32_t *operands, *result_nodes; uint8_t results, destination, dead, direct_return; } EffectPayload;
typedef enum { FACT_UNREACHED, FACT_CONSTANT, FACT_UNKNOWN } FactKind;
typedef struct { FactKind kind; uint64_t constant; } ArgumentFact;
typedef struct { uint32_t target, arguments; ArgumentFact *facts; } ResidualCall;
typedef struct { uint32_t *offsets, *edges, *component; uint8_t *recursive, *nested_eligible; uint32_t count, edge_count, component_count; } CallGraph;

typedef struct {
    const abc_module *module; const CallGraph *graph; uint32_t root_function;
    abc_symbolic_machine *machine;
    Node *nodes;
    uint32_t count, capacity;
    EffectPayload *payloads; uint32_t payload_count, payload_capacity;
    abc_symbolic_value results[255];
    uint32_t result_count, control_target, root_entry, root_arguments, backedge_target, loop_target;
    int unsupported, follow_control, terminal_abort, unknown_control, callable_safe, dynamic_callable_safe, backedge, nested_backedge, loop_candidate, loop_captured, loop_stable; uint32_t pending_origin;
    abc_symbolic_context loop_initial; abc_symbolic_value loop_header[255]; uint32_t loop_home[255], loop_count;
    abc_symbolic_control pending_control; unsigned paths;
    ResidualCall *calls; uint32_t call_count, call_capacity; uint32_t terminal_tail;
} DagSink;
typedef struct DagTree {
    unsigned leaf, backedge, nested_backedge, tail; uint32_t origin, tail_node; abc_symbolic_control control; uint32_t result_count; abc_symbolic_value results[255];
    struct DagTree *fallthrough, *taken; struct DagTree **arms; uint32_t arm_count;
} DagTree;

typedef struct {
    uint8_t *code; uint32_t length; int optimized;
    abc_provenance *provenance; uint32_t provenance_count, provenance_capacity;
    ResidualCall *calls; uint32_t call_count;
} FunctionCode;
typedef struct { uint8_t *data; size_t size, capacity; FunctionCode *function; } Bytes;

static void free_call_graph(CallGraph *g){free(g->offsets);free(g->edges);free(g->component);free(g->recursive);free(g->nested_eligible);memset(g,0,sizeof *g);}
static int direct_target(const abc_module *m,uint32_t pc,uint32_t *target){
    const uint8_t *p=m->code+pc;unsigned kind=op_kind[p[0]];if(kind!=K_CALL&&kind!=K_TCALL)return 0;uint32_t length=abc_instruction_length(p);*target=(uint32_t)((int64_t)(pc+length)+abc_i32(p+1));return 1;
}
static int dynamic_callable_target(const abc_module *m,uint32_t pc,uint32_t *target){
    const uint8_t *p=m->code+pc;if(p[0]!=OP_EXT||(p[1]!=EXT_WORD_DIRECT&&p[1]!=EXT_CLOSURE_NEW))return 0;*target=abc_u32(p+2);return *target<m->function_count;
}
static int build_call_graph(const abc_module *m,CallGraph *g){
    uint32_t n=m->function_count;
    uint32_t *cursor=NULL,*reverse_offsets=NULL,*reverse_edges=NULL,*order=NULL,*stack=NULL,*next=NULL,*sizes=NULL;
    uint8_t *seen=NULL;
    g->count=n;
    g->offsets=calloc((size_t)n+1,sizeof *g->offsets);
    g->component=malloc((size_t)n*sizeof *g->component);
    g->recursive=calloc(n?n:1,1);
    g->nested_eligible=calloc(n?n:1,1);
    if(!g->offsets||!g->component||!g->recursive||!g->nested_eligible)goto failed;
    for(uint32_t fi=0;fi<n;fi++){
        for(uint32_t pc=m->functions[fi].entry;pc<m->functions[fi].end;pc+=abc_instruction_length(m->code+pc)){
            uint32_t target;if(!direct_target(m,pc,&target))continue;
            if(abc_find_function(m,target)<0)goto failed;
            g->offsets[fi+1]++;
        }
    }
    for(uint32_t i=1;i<=n;i++)g->offsets[i]+=g->offsets[i-1];
    g->edge_count=g->offsets[n];
    g->edges=malloc((size_t)(g->edge_count?g->edge_count:1)*sizeof *g->edges);
    cursor=malloc((size_t)n*sizeof *cursor);
    if(!g->edges||!cursor)goto failed;
    memcpy(cursor,g->offsets,(size_t)n*sizeof *cursor);
    for(uint32_t fi=0;fi<n;fi++){
        for(uint32_t pc=m->functions[fi].entry;pc<m->functions[fi].end;pc+=abc_instruction_length(m->code+pc)){
            uint32_t target;if(direct_target(m,pc,&target))g->edges[cursor[fi]++]=(uint32_t)abc_find_function(m,target);
        }
    }
    reverse_offsets=calloc((size_t)n+1,sizeof *reverse_offsets);
    reverse_edges=malloc((size_t)(g->edge_count?g->edge_count:1)*sizeof *reverse_edges);
    order=malloc((size_t)n*sizeof *order);stack=malloc((size_t)n*sizeof *stack);next=malloc((size_t)n*sizeof *next);seen=calloc(n?n:1,1);
    if(!reverse_offsets||!reverse_edges||!order||!stack||!next||!seen)goto failed;
    for(uint32_t i=0;i<g->edge_count;i++)reverse_offsets[g->edges[i]+1]++;
    for(uint32_t i=1;i<=n;i++)reverse_offsets[i]+=reverse_offsets[i-1];
    memcpy(cursor,reverse_offsets,(size_t)n*sizeof *cursor);
    for(uint32_t from=0;from<n;from++)for(uint32_t i=g->offsets[from];i<g->offsets[from+1];i++)reverse_edges[cursor[g->edges[i]]++]=from;
    uint32_t order_count=0;
    for(uint32_t start=0;start<n;start++)if(!seen[start]){
        uint32_t depth=1;stack[0]=start;next[0]=g->offsets[start];seen[start]=1;
        while(depth){uint32_t at=depth-1,v=stack[at];if(next[at]<g->offsets[v+1]){uint32_t to=g->edges[next[at]++];if(!seen[to]){seen[to]=1;stack[depth]=to;next[depth]=g->offsets[to];depth++;}}else{order[order_count++]=v;depth--;}}
    }
    for(uint32_t i=0;i<n;i++)g->component[i]=UINT32_MAX;
    uint32_t components=0;
    for(uint32_t oi=order_count;oi;oi--){
        uint32_t start=order[oi-1];if(g->component[start]!=UINT32_MAX)continue;
        uint32_t depth=1;stack[0]=start;g->component[start]=components;
        while(depth){uint32_t v=stack[--depth];for(uint32_t i=reverse_offsets[v];i<reverse_offsets[v+1];i++){uint32_t to=reverse_edges[i];if(g->component[to]==UINT32_MAX){g->component[to]=components;stack[depth++]=to;}}}
        components++;
    }
    g->component_count=components;sizes=calloc(components?components:1,sizeof *sizes);if(!sizes)goto failed;
    for(uint32_t i=0;i<n;i++)sizes[g->component[i]]++;
    for(uint32_t from=0;from<n;from++){
        int self=0,nontail=0;
        for(uint32_t i=g->offsets[from];i<g->offsets[from+1];i++)if(g->component[g->edges[i]]==g->component[from]&&g->edges[i]==from)self=1;
        for(uint32_t pc=m->functions[from].entry;pc<m->functions[from].end;pc+=abc_instruction_length(m->code+pc)){uint32_t target;if(direct_target(m,pc,&target)&&op_kind[m->code[pc]]==K_CALL){int to=abc_find_function(m,target);if(to>=0&&g->component[to]==g->component[from])nontail=1;}}
        g->recursive[from]=(uint8_t)(sizes[g->component[from]]>1||self);
        g->nested_eligible[from]=(uint8_t)(g->recursive[from]&&sizes[g->component[from]]==1&&!nontail);
    }
    free(cursor);free(reverse_offsets);free(reverse_edges);free(order);free(stack);free(next);free(sizes);free(seen);return 1;
failed:
    free(cursor);free(reverse_offsets);free(reverse_edges);free(order);free(stack);free(next);free(sizes);free(seen);free_call_graph(g);return 0;
}
static ArgumentFact argument_fact(abc_symbolic_value value){return value.kind==ABC_SYM_CONST?(ArgumentFact){FACT_CONSTANT,value.constant}:(ArgumentFact){FACT_UNKNOWN,0};}
static int record_call(DagSink *s,uint32_t target,unsigned count,const abc_symbolic_value *values){
    if(s->call_count==s->call_capacity){uint32_t capacity=s->call_capacity?s->call_capacity*2:4;ResidualCall *calls=realloc(s->calls,(size_t)capacity*sizeof *calls);if(!calls)return 0;s->calls=calls;s->call_capacity=capacity;}
    ResidualCall *call=&s->calls[s->call_count++];*call=(ResidualCall){.target=target,.arguments=count};call->facts=calloc(count?count:1,sizeof *call->facts);if(!call->facts)return 0;for(unsigned i=0;i<count;i++)call->facts[i]=argument_fact(values[i]);return 1;
}

static int grow_nodes(DagSink *s) {
    if (s->count < s->capacity) return 1;
    uint32_t capacity=s->capacity?s->capacity*2:32;
    Node *nodes=realloc(s->nodes,(size_t)capacity*sizeof *nodes);
    if(!nodes)return 0;s->nodes=nodes;s->capacity=capacity;return 1;
}
static uint32_t dag_value(DagSink *s,abc_symbolic_value value,uint32_t origin);
static EffectPayload *find_payload(const DagSink *s,uint32_t node_id){for(uint32_t i=0;i<s->payload_count;i++)if(s->payloads[i].node==node_id)return &s->payloads[i];return NULL;}
static int add_payload(DagSink *s,uint32_t node_id,unsigned count,const abc_symbolic_value *values,uint32_t origin,unsigned results){
    if(s->payload_count==s->payload_capacity){uint32_t capacity=s->payload_capacity?s->payload_capacity*2:8;EffectPayload *p=realloc(s->payloads,(size_t)capacity*sizeof *p);if(!p)return 0;s->payloads=p;s->payload_capacity=capacity;}
    EffectPayload *p=&s->payloads[s->payload_count++];*p=(EffectPayload){.node=node_id,.count=count,.results=(uint8_t)results};p->operands=calloc(count?count:1,sizeof *p->operands);if(!p->operands)return 0;
    for(unsigned i=0;i<count;i++){p->operands[i]=dag_value(s,values[i],origin);if(!p->operands[i])return 0;}return 1;
}
static int same_node(const Node *a,const Node *b) {
    if(a->effect||b->effect||a->kind!=b->kind||a->kind==N_TAIL)return 0;
    if(a->kind==N_INPUT||a->kind==N_LOOP_HOME)return a->input==b->input&&a->left==b->left&&a->right==b->right;
    if(a->kind==N_RESULT)return a->left==b->left&&a->input==b->input;
    if(a->opcode!=b->opcode||a->left!=b->left)return 0;
    return a->kind==N_UNARY||a->kind==N_CHECK||a->right==b->right;
}
static uint32_t node(DagSink *s,Node n) {
    for(uint32_t i=0;i<s->count;i++)if(same_node(&s->nodes[i],&n))return i+1;
    if(!grow_nodes(s))return 0;s->nodes[s->count]=n;return ++s->count;
}
static abc_symbolic_value backend(uint32_t id,unsigned stack,int32_t home) {
    return abc_symbolic_backend(id,stack,home);
}
static uint32_t dag_value(DagSink *s,abc_symbolic_value value,uint32_t origin) {
    if(value.kind==ABC_SYM_BACKEND)return value.reg;
    if(value.kind!=ABC_SYM_CONST)return 0;
    uint32_t id=node(s,(Node){N_INPUT,origin,(uint32_t)value.constant,(uint32_t)(value.constant>>32),0,255,0,0});
    return id;
}
static int pure_binary(unsigned opcode) {
    switch(opcode) {
    case OP_ADD_A: case OP_SUB_A: case OP_MUL_A: case OP_AND_A: case OP_OR_A: case OP_XOR_A:
    case OP_SHL_A: case OP_SHR_A: case OP_SAR_A: case OP_EQ_A: case OP_NE_A:
    case OP_LT_A: case OP_LE_A: case OP_LTU_A: case OP_LEU_A:return 1;
    default:return 0;
    }
}
static int trapping_binary(unsigned opcode) {
    return opcode==OP_DIVU_A||opcode==OP_DIVS_A||opcode==OP_REMU_A||opcode==OP_REMS_A;
}
/* A division/remainder traps only on a zero divisor; signed -1 is defined as
 * wrapping, so a known nonzero constant divisor cannot trap and is a pure op. */
static int trapping_op(unsigned opcode,const Node *divisor) {
    if(!trapping_binary(opcode))return 0;
    if(divisor->kind==N_INPUT&&divisor->input==255&&((uint64_t)divisor->left|((uint64_t)divisor->right<<32)))return 0;
    return 1;
}
static int dag_check(void *opaque,uint32_t origin,unsigned opcode,int known,int trapped,abc_symbolic_value input) {
    DagSink *s=opaque;if(known&&!trapped)return 1;uint32_t value=dag_value(s,input,origin);if(!value)return 0;
    if(trapped)s->terminal_abort=1;return node(s,(Node){N_CHECK,origin,value,0,(uint16_t)opcode,0,0,1})!=0;
}
static int dag_binary(void *opaque,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        abc_symbolic_value left,abc_symbolic_value right,abc_symbolic_value *result) {
    DagSink *s=opaque;if(folded)return 1;if(!pure_binary(opcode)&&!trapping_binary(opcode)){s->unsupported=1;s->machine->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    uint32_t l=dag_value(s,left,origin),r=dag_value(s,right,origin);if(!l||!r)return 0;
    Node n={N_BINARY,origin,l,r,(uint16_t)opcode,0,0,0};n.effect=(uint8_t)trapping_op(opcode,&s->nodes[r-1]);uint32_t id=node(s,n);
    if(!id)return 0;*result=backend(id,destination,0);return 1;
}
static int dag_unary(void *opaque,uint32_t origin,unsigned opcode,unsigned stack,int folded,
        abc_symbolic_value input,abc_symbolic_value *result) {
    DagSink *s=opaque;if(folded)return 1;uint32_t value=dag_value(s,input,origin);if(!value)return 0;
    uint32_t id=node(s,(Node){N_UNARY,origin,value,0,(uint16_t)opcode,0,0,0});
    if(!id)return 0;*result=backend(id,stack,0);return 1;
}
static int dag_immediate(void *opaque,uint32_t origin,unsigned opcode,unsigned stack,uint64_t immediate,
        int folded,abc_symbolic_value input,abc_symbolic_value *result) {
    static const uint8_t imm_base[]={OP_ADD_A,OP_SUB_A,OP_MUL_A,OP_AND_A,OP_OR_A,OP_XOR_A,OP_SHL_A,OP_SHR_A,OP_SAR_A};
    DagSink *s=opaque;if(folded)return 1;unsigned index=(opcode-OP_ADDI_A)/2;
    if(index>=sizeof imm_base/sizeof imm_base[0]){s->unsupported=1;s->machine->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    unsigned base=imm_base[index];
    if(!pure_binary(base)){s->unsupported=1;s->machine->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    uint32_t value=dag_value(s,input,origin);if(!value)return 0;
    uint32_t constant=node(s,(Node){N_INPUT,origin,(uint32_t)immediate,(uint32_t)(immediate>>32),0,255,0,0});
    if(!constant)return 0;uint32_t id=node(s,(Node){N_BINARY,origin,value,constant,(uint16_t)base,0,0,0});
    if(!id)return 0;*result=backend(id,stack,0);return 1;
}
static int dag_c_operand(void *opaque,uint32_t origin,unsigned opcode,unsigned destination,int folded,
        abc_symbolic_value left,abc_symbolic_value right,abc_symbolic_value *result) {
    static const unsigned base[]={OP_ADD_A,OP_SUB_A,OP_MUL_A,OP_XOR_A};
    DagSink *s=opaque;if(folded)return 1;unsigned index=(opcode-OP_ADDC_A)/2;
    if(index>=4){s->unsupported=1;s->machine->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    uint32_t l=dag_value(s,left,origin),r=dag_value(s,right,origin);if(!l||!r)return 0;
    uint32_t id=node(s,(Node){N_BINARY,origin,l,r,(uint16_t)base[index],0,0,0});
    if(!id)return 0;*result=backend(id,destination,0);return 1;
}
static int dag_abort(void *opaque,uint32_t origin,unsigned reason) {
    DagSink *s=opaque;uint32_t id=node(s,(Node){N_ABORT,origin,0,0,0,(uint8_t)reason,0,1});if(!id)return 0;s->terminal_abort=1;return 1;
}
static int memory_result(unsigned action){return action==M_FLOAD||action==M_FADDR||action==M_GLOAD||action==M_GADDR||action==M_PLOAD||action==M_XLOAD||action==M_INDEX;}
static int callable_module_safe(const abc_module *m){
    if(!m->callable_profile||m->foreign_profile||m->dynamic_profile)return 0;for(uint32_t i=0;i<m->function_count;i++)for(uint32_t j=0;j<m->functions[i].results;j++)if(m->functions[i].result_kinds[j]==ABC_KIND_ADDR)return 0;
    for(uint32_t pc=0;pc<m->code_size;pc+=abc_instruction_length(m->code+pc)){unsigned op=m->code[pc],action=op_memory[op].action;if(action==M_ALLOC||action==M_FREE||action==M_GSTORE||action==M_PSTORE||action==M_COPY||op==OP_FCALL)return 0;}return 1;
}
static int dynamic_callable_module_safe(const abc_module *m){
    if(!m->dynamic_profile||m->foreign_profile)return 0;for(uint32_t pc=0;pc<m->code_size;pc+=abc_instruction_length(m->code+pc)){unsigned action=op_memory[m->code[pc]].action;if(action==M_FSTORE||action==M_GSTORE||action==M_PSTORE||action==M_COPY)return 0;}return 1;
}
static int dag_memory(void *opaque,uint32_t origin,abc_symbolic_memory *memory) {
    DagSink *s=opaque;if(s->callable_safe&&memory->action==M_GLOAD&&memory->opcode==OP_GLD64){uint32_t offset=abc_u32(s->module->code+origin+1);for(uint32_t i=0;i<s->module->reloc_count;i++)if(s->module->relocs[i].offset==offset){uint32_t id=node(s,(Node){N_CALLABLE,origin,s->module->relocs[i].function,0,0,0,0,0});if(!id)return 0;memory->result=backend(id,memory->stack,0);return 1;}}
    if(memory->action==M_ALLOC||memory->action==M_FREE)return node(s,(Node){N_EFFECT,origin,0,0,(uint16_t)memory->opcode,0,0,1})!=0;
    uint32_t first=0,second=0;
    if(memory->action==M_FSTORE||memory->action==M_GSTORE||memory->action==M_PLOAD||memory->action==M_PSTORE||memory->action==M_XLOAD||memory->action==M_INDEX||memory->action==M_COPY){first=dag_value(s,memory->first,origin);if(!first)return 0;}
    if(memory->action==M_PSTORE||memory->action==M_XLOAD||memory->action==M_INDEX||memory->action==M_COPY){second=dag_value(s,memory->second,origin);if(!second)return 0;}
    unsigned ordered=memory->action!=M_GADDR;uint32_t id=node(s,(Node){N_MEMORY,origin,first,second,(uint16_t)memory->opcode,(uint8_t)memory->action,0,(uint8_t)ordered});if(!id)return 0;
    if(memory_result(memory->action))memory->result=backend(id,memory->stack,0);return 1;
}
static int dag_dynamic(void *opaque,uint32_t origin,abc_symbolic_dynamic *effect){
    DagSink *s=opaque;if(effect->tail||effect->pushes>1){s->unsupported=1;s->machine->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}abc_symbolic_context *x=s->machine->context;uint32_t base=x->n[ABC_SYM_A]-effect->pops;
    if(effect->selector==EXT_ANY_BOX&&effect->pops==1&&effect->pushes==1&&abc_symbolic_dynamic_box_specialization(s->module,effect->descriptor,x->s[ABC_SYM_A][base])){
        abc_symbolic_value fact=effect->result[0];effect->result[0]=x->s[ABC_SYM_A][base];effect->result[0].dynamic_tags=fact.dynamic_tags;effect->result[0].dynamic_width=fact.dynamic_width;effect->result[0].dynamic_repr=ABC_SYM_REPR_RAW;return 1;
    }
    if(effect->selector==EXT_ANY_CAST&&effect->pops==1&&effect->pushes==1&&abc_symbolic_dynamic_cast_matches(s->module,effect->descriptor,x->s[ABC_SYM_A][base])){
        effect->result[0]=x->s[ABC_SYM_A][base];abc_symbolic_forget_dynamic(&effect->result[0]);return 1;
    }
    unsigned opcode;if(effect->pops==2&&effect->pushes==1&&abc_symbolic_dynamic_binary_specialization(effect->selector,x->s[ABC_SYM_A][base],x->s[ABC_SYM_A][base+1],&opcode)){
        abc_symbolic_value left=x->s[ABC_SYM_A][base],right=x->s[ABC_SYM_A][base+1],result=left;uint32_t id;unsigned unary=left.dynamic_tags==(uint16_t)(1u<<ABC_ANY_I32)?OP_SX32_A:OP_ZX32_A;
        if(left.kind==ABC_SYM_CONST&&right.kind==ABC_SYM_CONST){int ok=0;result.constant=abc_symbolic_fold_binary(opcode,left.constant,right.constant,&ok);if(!ok)return 0;if(left.dynamic_width==32)result.constant=abc_symbolic_fold_unary(unary,result.constant);effect->result[0]=result;return 1;}
        uint32_t l=dag_value(s,left,origin),r=dag_value(s,right,origin);id=l&&r?node(s,(Node){N_BINARY,origin,l,r,(uint16_t)opcode,0,0,0}):0;id=id?node(s,(Node){N_UNARY,origin,id,0,(uint16_t)unary,0,0,0}):0;if(!id)return 0;effect->result[0]=backend(id,ABC_SYM_A,0);effect->result[0].dynamic_tags=left.dynamic_tags;effect->result[0].dynamic_width=left.dynamic_width;effect->result[0].dynamic_repr=ABC_SYM_REPR_RAW;return 1;
    }
    for(uint32_t i=0;i<effect->pops;i++)if(x->s[ABC_SYM_A][base+i].dynamic_repr==ABC_SYM_REPR_RAW){s->unsupported=1;s->machine->exit=ABC_SYM_EXIT_BOUNDARY;return 0;}
    uint32_t id=node(s,(Node){N_DYNAMIC,origin,0,0,(uint16_t)effect->selector,(uint8_t)effect->pops,0,1});if(!id||!add_payload(s,id,effect->pops,x->s[ABC_SYM_A]+base,origin,effect->pushes))return 0;if(effect->pushes)effect->result[0]=backend(id,ABC_SYM_A,0);return 1;
}
static int dag_foreign(void *opaque,uint32_t origin,abc_symbolic_foreign *effect){
    DagSink *s=opaque;abc_symbolic_context *x=s->machine->context;uint32_t base=x->n[ABC_SYM_A]-effect->arguments;uint32_t id=node(s,(Node){N_FOREIGN,origin,0,0,(uint16_t)effect->index,(uint8_t)effect->arguments,0,1});
    if(!id||!add_payload(s,id,effect->arguments,x->s[ABC_SYM_A]+base,origin,effect->results))return 0;if(effect->results)effect->result[0]=backend(id,ABC_SYM_A,0);return 1;
}
static void unsupported(DagSink *s) { s->unsupported=1;s->machine->exit=ABC_SYM_EXIT_BOUNDARY; }
static int same_dynamic_fact(abc_symbolic_value a,abc_symbolic_value b){return a.dynamic_tags==b.dynamic_tags&&a.dynamic_width==b.dynamic_width&&a.dynamic_repr==b.dynamic_repr;}
static void join_dynamic_fact(abc_symbolic_value *out,abc_symbolic_value a,abc_symbolic_value b){
    if(!a.dynamic_tags||!b.dynamic_tags){abc_symbolic_forget_dynamic(out);return;}
    out->dynamic_tags=(uint16_t)(a.dynamic_tags|b.dynamic_tags);out->dynamic_width=a.dynamic_width==b.dynamic_width?a.dynamic_width:0;
    out->dynamic_repr=a.dynamic_repr==b.dynamic_repr?a.dynamic_repr:ABC_SYM_REPR_UNKNOWN;
}
static int same_value(abc_symbolic_value a,abc_symbolic_value b){
    if(!same_dynamic_fact(a,b)||a.kind!=b.kind)return 0;if(a.kind==ABC_SYM_CONST)return a.constant==b.constant;
    if(a.kind==ABC_SYM_BACKEND)return a.reg==b.reg;return a.home==b.home&&a.dst_stack==b.dst_stack&&a.dst_home==b.dst_home;
}
static int dag_control(void *opaque,uint32_t origin,const abc_symbolic_control *control) {
    DagSink *s=opaque;if(!control->known){
        int supported=control->kind==ABC_SYM_CONTROL_ZERO||control->kind==ABC_SYM_CONTROL_INTEGER||control->kind==ABC_SYM_CONTROL_IMMEDIATE||control->kind==ABC_SYM_CONTROL_SWITCH;
        if(!supported||control->fallthrough<=origin){s->unsupported=1;return 1;}
        if(control->kind==ABC_SYM_CONTROL_SWITCH){const uint8_t *p=s->module->code+origin;for(uint32_t i=0;i<control->count;i++)if((uint32_t)((int64_t)control->fallthrough+abc_i32(p+3+4*i))<=origin){s->unsupported=1;return 1;}}
        else if(control->target<=origin){s->unsupported=1;return 1;}
        s->pending_control=*control;s->pending_origin=origin;s->unknown_control=1;return 1;
    }
    uint32_t target=control->kind==ABC_SYM_CONTROL_JUMP||control->taken?control->target:control->fallthrough;
    if(target<=origin){s->unsupported=1;return 1;}s->control_target=target;s->follow_control=1;return 1;
}

static int dag_effect(void *opaque,uint32_t origin,unsigned opcode) {
    DagSink *s=opaque;(void)origin;(void)opcode;unsupported(s);return 0;
}

static int dag_call(void *opaque,uint32_t origin,abc_symbolic_call *effect) {
    DagSink *s=opaque;int fi=abc_find_function(s->module,effect->target);if(fi<0||s->module->functions[fi].hidden_bytes){unsupported(s);return 0;}int recursive=s->graph->recursive[fi];
    if(recursive&&effect->target!=s->root_entry&&s->graph->nested_eligible[fi]&&!s->loop_candidate){s->loop_candidate=1;s->loop_target=effect->target;effect->virtualize=1;return 1;}
    if(recursive){abc_symbolic_context *x=s->machine->context;uint32_t base=x->n[ABC_SYM_A]-effect->arguments;if(!record_call(s,(uint32_t)fi,effect->arguments,x->s[ABC_SYM_A]+base))return 0;uint32_t call=node(s,(Node){N_CALL,origin,(uint32_t)fi,0,(uint16_t)s->module->code[origin],(uint8_t)effect->destination,0,1});if(!call||!add_payload(s,call,effect->arguments,x->s[ABC_SYM_A]+base,origin,effect->results))return 0;EffectPayload *p=find_payload(s,call);p->destination=(uint8_t)effect->destination;p->result_nodes=calloc(effect->results?effect->results:1,sizeof *p->result_nodes);if(!p->result_nodes)return 0;for(unsigned i=0;i<effect->results;i++){uint32_t result=node(s,(Node){N_RESULT,origin,call,0,0,(uint8_t)i,0,0});if(!result)return 0;p->result_nodes[i]=result;effect->result[i]=backend(result,effect->destination,0);}return 1;}effect->virtualize=1;return 1;
}

static int dag_indirect(void *opaque,uint32_t origin,abc_symbolic_indirect *effect) {
    DagSink *s=opaque;(void)origin;if(effect->target.kind==ABC_SYM_BACKEND&&effect->target.reg&&effect->target.reg<=s->count){Node *target=&s->nodes[effect->target.reg-1];if(target->kind==N_CALLABLE&&target->left<s->module->function_count){effect->direct=1;effect->direct_target=s->module->functions[target->left].entry;return 1;}}unsupported(s);return 0;
}

static int dag_tail(void *opaque,uint32_t origin,abc_symbolic_tail *effect) {
    DagSink *s=opaque;int fi=abc_find_function(s->module,effect->target);if(fi<0||s->module->functions[fi].hidden_bytes){unsupported(s);return 0;}int recursive=s->graph->recursive[fi];
    if(effect->target!=s->root_entry){
        if(s->loop_candidate&&effect->target==s->loop_target)return 1;
        if(recursive&&s->graph->nested_eligible[fi]&&!s->loop_candidate){s->loop_candidate=1;s->loop_target=effect->target;return 1;}
        if(recursive){abc_symbolic_context *x=s->machine->context;uint32_t base=x->n[ABC_SYM_A]-effect->arguments;if(!record_call(s,(uint32_t)fi,effect->arguments,x->s[ABC_SYM_A]+base))return 0;uint32_t tail=node(s,(Node){N_TAIL,origin,(uint32_t)fi,0,(uint16_t)s->module->code[origin],0,0,0});if(!tail||!add_payload(s,tail,effect->arguments,x->s[ABC_SYM_A]+base,origin,0))return 0;s->terminal_tail=tail;s->pending_origin=origin;effect->residualize=1;return 1;}
    }
    if(recursive&&effect->target==s->root_entry){abc_symbolic_context *x=s->machine->context;uint32_t base=x->n[ABC_SYM_A]-effect->arguments;if(!record_call(s,(uint32_t)fi,effect->arguments,x->s[ABC_SYM_A]+base))return 0;}
    return 1;
}

static int dag_return(void *opaque,uint32_t origin,const abc_symbolic_return *effect) {
    DagSink *s=opaque;(void)origin;if(!effect->terminal)return 1;abc_symbolic_context *x=s->machine->context;
    s->result_count=effect->results;for(unsigned i=0;i<effect->results;i++)s->results[i]=x->s[ABC_SYM_A][i];return 1;
}
static int dag_edge(void *opaque,uint32_t origin,uint32_t target) {
    DagSink *s=opaque;abc_symbolic_context *x=s->machine->context;
    if(s->loop_candidate&&target==s->loop_target){
        if(!s->loop_captured){if(x->n[ABC_SYM_A]||x->n[ABC_SYM_B]||x->n[ABC_SYM_C]>255||!abc_symbolic_context_copy(&s->loop_initial,x)){unsupported(s);return 0;}s->loop_captured=1;s->loop_count=x->n[ABC_SYM_C];s->control_target=target;s->follow_control=1;return 1;}
        if(target>origin||x->n[ABC_SYM_A]||x->n[ABC_SYM_B]||x->n[ABC_SYM_C]!=s->loop_count){unsupported(s);return 0;}
        if(!s->loop_stable){
            for(uint32_t depth=0;depth<s->loop_count;depth++){abc_symbolic_value initial=*abc_symbolic_top(&s->loop_initial,ABC_SYM_C,depth),current=*abc_symbolic_top(x,ABC_SYM_C,depth);
                if(same_value(initial,current)){s->loop_header[depth]=initial;continue;}uint32_t value=dag_value(s,initial,origin);uint32_t home=value?node(s,(Node){N_LOOP_HOME,origin,value,0,0,(uint8_t)depth,0,0}):0;if(!home){unsupported(s);return 0;}s->loop_home[depth]=home;s->loop_header[depth]=backend(home,ABC_SYM_C,0);join_dynamic_fact(&s->loop_header[depth],initial,current);
            }
            for(uint32_t depth=0;depth<s->loop_count;depth++)*abc_symbolic_top(x,ABC_SYM_C,depth)=s->loop_header[depth];
            s->loop_stable=1;s->control_target=target;s->follow_control=1;return 1;
        }
        for(uint32_t depth=0;depth<s->loop_count;depth++)if(!s->loop_home[depth]&&!same_value(*abc_symbolic_top(x,ABC_SYM_C,depth),s->loop_header[depth])){unsupported(s);return 0;}
        s->backedge=1;s->nested_backedge=1;s->backedge_target=target;s->pending_origin=origin;return 1;
    }
    if(target==s->root_entry&&target<=origin){if(x->n[ABC_SYM_A]||x->n[ABC_SYM_B]||x->n[ABC_SYM_C]!=s->root_arguments){unsupported(s);return 0;}s->backedge=1;s->nested_backedge=0;s->backedge_target=target;s->pending_origin=origin;return 1;}s->control_target=target;s->follow_control=1;return 1;
}

static void free_tree(DagTree *tree) {
    if(!tree)return;free_tree(tree->fallthrough);free_tree(tree->taken);for(uint32_t i=0;i<tree->arm_count;i++)free_tree(tree->arms[i]);free(tree->arms);free(tree);
}
static int tree_arity(const DagTree *tree,uint32_t results) {
    if(!tree)return 0;if(tree->leaf)return tree->backedge||tree->tail||tree->result_count==results;if(!tree_arity(tree->fallthrough,results))return 0;
    if(tree->control.kind==ABC_SYM_CONTROL_SWITCH){for(uint32_t i=0;i<tree->arm_count;i++)if(!tree_arity(tree->arms[i],results))return 0;return 1;}
    return tree_arity(tree->taken,results);
}
static int tree_has_backedge(const DagTree *tree){if(!tree)return 0;if(tree->backedge)return 1;if(tree_has_backedge(tree->fallthrough)||tree_has_backedge(tree->taken))return 1;for(uint32_t i=0;i<tree->arm_count;i++)if(tree_has_backedge(tree->arms[i]))return 1;return 0;}
static int tree_has_tail(const DagTree *tree){if(!tree)return 0;if(tree->tail)return 1;if(tree_has_tail(tree->fallthrough)||tree_has_tail(tree->taken))return 1;for(uint32_t i=0;i<tree->arm_count;i++)if(tree_has_tail(tree->arms[i]))return 1;return 0;
}
static int simulate_tree(DagSink *sink,abc_symbolic_machine *machine,abc_symbolic_context *context,uint32_t pc,DagTree **out) {
    machine->context=context;machine->pc=pc;
    for(;;){
        sink->follow_control=0;sink->unknown_control=0;sink->backedge=0;sink->terminal_tail=0;abc_symbolic_exit exit=abc_symbolic_dispatch(machine);
        if(sink->unsupported||exit==ABC_SYM_EXIT_FAILURE||exit==ABC_SYM_EXIT_BOUNDARY||exit==ABC_SYM_EXIT_BLOCK)return 0;
        if(exit==ABC_SYM_EXIT_TERMINATED){
            if(++sink->paths>ABC_SYMBOLIC_VERSION_CAP)return 0;DagTree *leaf=calloc(1,sizeof *leaf);if(!leaf)return 0;leaf->leaf=1;leaf->tail=sink->terminal_tail!=0;leaf->tail_node=sink->terminal_tail;leaf->origin=sink->pending_origin;leaf->result_count=sink->result_count;
            for(uint32_t i=0;i<leaf->result_count;i++)leaf->results[i]=sink->results[i];*out=leaf;return 1;
        }
        if(exit!=ABC_SYM_EXIT_CONTROL)return 0;
        if(sink->backedge){if(++sink->paths>ABC_SYMBOLIC_VERSION_CAP||context->n[ABC_SYM_C]>255)return 0;DagTree *leaf=calloc(1,sizeof *leaf);if(!leaf)return 0;leaf->leaf=1;leaf->backedge=1;leaf->nested_backedge=(unsigned)sink->nested_backedge;leaf->origin=sink->pending_origin;leaf->result_count=context->n[ABC_SYM_C];for(uint32_t i=0;i<leaf->result_count;i++)leaf->results[i]=*abc_symbolic_top(context,ABC_SYM_C,i);*out=leaf;return 1;}
        if(sink->unknown_control){
            if(sink->loop_captured&&!sink->loop_stable)return 0;
            abc_symbolic_control control=sink->pending_control;abc_symbolic_context fallthrough={0};DagTree *tree=calloc(1,sizeof *tree);if(!tree)return 0;tree->origin=sink->pending_origin;tree->control=control;
            if(!abc_symbolic_context_copy(&fallthrough,context)){free(tree);return 0;}
            if(!simulate_tree(sink,machine,&fallthrough,control.fallthrough,&tree->fallthrough)){abc_symbolic_context_free(&fallthrough);free_tree(tree);return 0;}abc_symbolic_context_free(&fallthrough);
            if(control.kind==ABC_SYM_CONTROL_SWITCH){
                tree->arm_count=control.count;tree->arms=calloc(control.count,sizeof *tree->arms);if(control.count&&!tree->arms){free_tree(tree);return 0;}const uint8_t *p=sink->module->code+tree->origin;
                for(uint32_t i=0;i<control.count;i++){abc_symbolic_context arm={0};uint32_t target=(uint32_t)((int64_t)control.fallthrough+abc_i32(p+3+4*i));
                    if(!abc_symbolic_context_copy(&arm,context)||!simulate_tree(sink,machine,&arm,target,&tree->arms[i])){abc_symbolic_context_free(&arm);free_tree(tree);return 0;}abc_symbolic_context_free(&arm);
                }
            } else {abc_symbolic_context taken={0};if(!abc_symbolic_context_copy(&taken,context)||!simulate_tree(sink,machine,&taken,control.target,&tree->taken)){abc_symbolic_context_free(&taken);free_tree(tree);return 0;}abc_symbolic_context_free(&taken);}
            *out=tree;return 1;
        }
        if(!sink->follow_control)return 0;machine->pc=sink->control_target;
    }
}

static int bytes_reserve(Bytes *b,size_t extra) {
    if(extra>SIZE_MAX-b->size)return 0;size_t need=b->size+extra;if(need<=b->capacity)return 1;
    size_t capacity=b->capacity?b->capacity*2:128;while(capacity<need){if(capacity>SIZE_MAX/2){capacity=need;break;}capacity*=2;}
    uint8_t *data=realloc(b->data,capacity);if(!data)return 0;b->data=data;b->capacity=capacity;return 1;
}
static int emit8(Bytes *b,uint8_t x){if(!bytes_reserve(b,1))return 0;b->data[b->size++]=x;return 1;}
static int emit32(Bytes *b,uint32_t x){if(!bytes_reserve(b,4))return 0;for(unsigned i=0;i<4;i++)b->data[b->size++]=(uint8_t)(x>>(8*i));return 1;}
static int emit64(Bytes *b,uint64_t x){return emit32(b,(uint32_t)x)&&emit32(b,(uint32_t)(x>>32));}
static int record_origin(Bytes *b,uint32_t origin) {
    FunctionCode *f=b->function;if(!f)return 1;if(f->provenance_count==f->provenance_capacity){uint32_t capacity=f->provenance_capacity?f->provenance_capacity*2:16;abc_provenance *p=realloc(f->provenance,(size_t)capacity*sizeof *p);if(!p)return 0;f->provenance=p;f->provenance_capacity=capacity;}
    f->provenance[f->provenance_count++]=(abc_provenance){(uint32_t)b->size,origin};return 1;
}
static int emit_origin_opcode(Bytes *b,uint32_t origin,unsigned opcode){return record_origin(b,origin)&&emit8(b,(uint8_t)opcode);}
static int signed8(uint64_t x){return abc_imm8((uint8_t)x)==x;}
static int signed32(uint64_t x){return (uint64_t)(int64_t)(int32_t)x==x;}
static int emit_constant(Bytes *b,unsigned stack,uint64_t value) {
    if(signed8(value))return emit8(b,(uint8_t)(stack==ABC_SYM_A?OP_PUSH8_A:OP_PUSH8_B))&&emit8(b,(uint8_t)value);
    if(signed32(value))return emit8(b,(uint8_t)(stack==ABC_SYM_A?OP_PUSH32_A:OP_PUSH32_B))&&emit32(b,(uint32_t)value);
    return emit8(b,(uint8_t)(stack==ABC_SYM_A?OP_PUSH64_A:OP_PUSH64_B))&&emit64(b,value);
}
static int emit_cget(Bytes *b,unsigned stack,unsigned depth) {
    if(depth==0)return emit8(b,(uint8_t)(stack==ABC_SYM_A?OP_CGET0_A:OP_CGET0_B));
    if(depth==1)return emit8(b,(uint8_t)(stack==ABC_SYM_A?OP_CGET1_A:OP_CGET1_B));
    return depth<=255&&emit8(b,(uint8_t)(stack==ABC_SYM_A?OP_CGETN_A:OP_CGETN_B))&&emit8(b,(uint8_t)depth);
}
static int emit_cset(Bytes *b,unsigned stack,unsigned depth) {
    if(depth==0)return emit8(b,(uint8_t)(stack==ABC_SYM_A?OP_CSET0_A:OP_CSET0_B));
    return depth<=255&&emit8(b,(uint8_t)(stack==ABC_SYM_A?OP_CSETN_A:OP_CSETN_B))&&emit8(b,(uint8_t)depth);
}
static int immediate_opcode(unsigned base,unsigned stack) {
    switch(base) {
    case OP_ADD_A:return stack==ABC_SYM_A?OP_ADDI_A:OP_ADDI_B;
    case OP_SUB_A:return stack==ABC_SYM_A?OP_SUBI_A:OP_SUBI_B;
    case OP_MUL_A:return stack==ABC_SYM_A?OP_MULI_A:OP_MULI_B;
    case OP_AND_A:return stack==ABC_SYM_A?OP_ANDI_A:OP_ANDI_B;
    case OP_OR_A:return stack==ABC_SYM_A?OP_ORI_A:OP_ORI_B;
    case OP_XOR_A:return stack==ABC_SYM_A?OP_XORI_A:OP_XORI_B;
    case OP_SHL_A:return stack==ABC_SYM_A?OP_SHLI_A:OP_SHLI_B;
    case OP_SHR_A:return stack==ABC_SYM_A?OP_SHRI_A:OP_SHRI_B;
    case OP_SAR_A:return stack==ABC_SYM_A?OP_SARI_A:OP_SARI_B;
    default:return -1;
    }
}
static int branch_immediate_opcode(unsigned base){
    switch(base){case OP_BEQ:return OP_BEQI;case OP_BNE:return OP_BNEI;case OP_BLT:return OP_BLTI;case OP_BLE:return OP_BLEI;case OP_BLTU:return OP_BLTUI;case OP_BLEU:return OP_BLEUI;default:return -1;}
    }
static int c_opcode(unsigned base,unsigned stack) {
    switch(base) {
    case OP_ADD_A:return stack==ABC_SYM_A?OP_ADDC_A:OP_ADDC_B;
    case OP_SUB_A:return stack==ABC_SYM_A?OP_SUBC_A:OP_SUBC_B;
    case OP_MUL_A:return stack==ABC_SYM_A?OP_MULC_A:OP_MULC_B;
    case OP_XOR_A:return stack==ABC_SYM_A?OP_XORC_A:OP_XORC_B;
    default:return -1;
    }
}
static uint16_t compute_ershov(DagSink *s,uint32_t id) {
    if(!id||id>s->count)return 0;Node *n=&s->nodes[id-1];if(n->ershov)return n->ershov;
    if(n->kind==N_ABORT||n->kind==N_EFFECT)return n->ershov=1;
    if(n->kind==N_MEMORY){uint16_t left=n->left?compute_ershov(s,n->left):1,right=n->right?compute_ershov(s,n->right):1;return n->ershov=left==right?(uint16_t)(left+1):(left>right?left:right);}
    if(n->kind==N_DYNAMIC||n->kind==N_FOREIGN||n->kind==N_CALL||n->kind==N_TAIL){EffectPayload *p=find_payload(s,id);uint16_t max=1;if(!p)return 0;for(uint32_t i=0;i<p->count;i++){uint16_t e=compute_ershov(s,p->operands[i]);if(!e)return 0;if(e>max)max=e;}return n->ershov=max;}
    if(n->kind==N_RESULT)return compute_ershov(s,n->left)?(n->ershov=1):0;
    if(n->kind==N_INPUT||n->kind==N_CALLABLE)return n->ershov=1;uint16_t left=compute_ershov(s,n->left);
    if(n->kind==N_LOOP_HOME||n->kind==N_CHECK)return n->ershov=left;
    if(n->kind==N_UNARY)return n->ershov=left;uint16_t right=compute_ershov(s,n->right);
    return n->ershov=left==right?(uint16_t)(left+1):(left>right?left:right);
}
typedef struct { const DagSink *sink; int32_t *homes; uint32_t temps, loop_temps, suffix; size_t loop_prologue, loop_header; } Schedule;

static int mark_uses(const DagSink *sink,uint32_t id,uint32_t *uses,uint8_t *expanded) {
    if(!id||id>sink->count)return 0;uses[id-1]++;if(expanded[id-1])return 1;expanded[id-1]=1;const Node *n=&sink->nodes[id-1];
    if(n->kind==N_INPUT||n->kind==N_CALLABLE||n->kind==N_ABORT||n->kind==N_EFFECT)return 1;
    if(n->kind==N_DYNAMIC||n->kind==N_FOREIGN||n->kind==N_CALL||n->kind==N_TAIL){EffectPayload *p=find_payload(sink,id);if(!p)return 0;for(uint32_t i=0;i<p->count;i++)if(!mark_uses(sink,p->operands[i],uses,expanded))return 0;return 1;}
    if(n->left&&!mark_uses(sink,n->left,uses,expanded))return 0;
    if(n->kind==N_MEMORY)return !n->right||mark_uses(sink,n->right,uses,expanded);
    if(n->kind==N_RESULT)return mark_uses(sink,n->left,uses,expanded);
    return n->kind==N_LOOP_HOME||n->kind==N_UNARY||n->kind==N_CHECK||mark_uses(sink,n->right,uses,expanded);
}
static int mark_value(DagSink *sink,abc_symbolic_value value,uint32_t *uses,uint8_t *expanded) {
    return value.kind!=ABC_SYM_BACKEND||(compute_ershov(sink,value.reg)&&mark_uses(sink,value.reg,uses,expanded));
}
static int mark_tree(DagSink *sink,const DagTree *tree,uint32_t *uses,uint8_t *expanded) {
    if(tree->leaf){if(tree->tail)return mark_uses(sink,tree->tail_node,uses,expanded);for(uint32_t i=0;i<tree->result_count;i++)if(!mark_value(sink,tree->results[i],uses,expanded))return 0;return 1;}
    if(!mark_value(sink,tree->control.left,uses,expanded))return 0;
    if(tree->control.kind==ABC_SYM_CONTROL_INTEGER&&!mark_value(sink,tree->control.right,uses,expanded))return 0;
    if(!mark_tree(sink,tree->fallthrough,uses,expanded))return 0;
    if(tree->control.kind==ABC_SYM_CONTROL_SWITCH){for(uint32_t i=0;i<tree->arm_count;i++)if(!mark_tree(sink,tree->arms[i],uses,expanded))return 0;return 1;}
    return mark_tree(sink,tree->taken,uses,expanded);
}
static int mark_path_node(const DagSink *sink,uint32_t id,uint32_t *counts,uint8_t *expanded){
    if(!id||id>sink->count)return 0;counts[id-1]++;if(expanded[id-1])return 1;expanded[id-1]=1;const Node *n=&sink->nodes[id-1];
    if(n->kind==N_INPUT||n->kind==N_CALLABLE||n->kind==N_ABORT||n->kind==N_EFFECT)return 1;
    if(n->kind==N_DYNAMIC||n->kind==N_FOREIGN||n->kind==N_CALL||n->kind==N_TAIL){EffectPayload *p=find_payload(sink,id);if(!p)return 0;for(uint32_t i=0;i<p->count;i++)if(!mark_path_node(sink,p->operands[i],counts,expanded))return 0;return 1;}
    if(n->left&&!mark_path_node(sink,n->left,counts,expanded))return 0;
    if(n->kind==N_MEMORY)return !n->right||mark_path_node(sink,n->right,counts,expanded);
    if(n->kind==N_RESULT)return mark_path_node(sink,n->left,counts,expanded);
    return n->kind==N_LOOP_HOME||n->kind==N_UNARY||n->kind==N_CHECK||mark_path_node(sink,n->right,counts,expanded);
}
static int mark_path_value(const DagSink *sink,abc_symbolic_value value,uint32_t *counts,uint8_t *expanded){
    return value.kind!=ABC_SYM_BACKEND||mark_path_node(sink,value.reg,counts,expanded);
}
static int mark_path_tree(const DagSink *sink,const DagTree *tree,uint32_t *counts,uint8_t *expanded,uint32_t *maximum){
    if(tree->leaf){if(tree->tail){if(!mark_path_node(sink,tree->tail_node,counts,expanded))return 0;}else for(uint32_t i=0;i<tree->result_count;i++)if(!mark_path_value(sink,tree->results[i],counts,expanded))return 0;for(uint32_t i=0;i<sink->count;i++)if(counts[i]>maximum[i])maximum[i]=counts[i];return 1;}
    if(!mark_path_value(sink,tree->control.left,counts,expanded))return 0;if(tree->control.kind==ABC_SYM_CONTROL_INTEGER&&!mark_path_value(sink,tree->control.right,counts,expanded))return 0;
    uint32_t children=1+(tree->control.kind==ABC_SYM_CONTROL_SWITCH?tree->arm_count:1);for(uint32_t child=0;child<children;child++){const DagTree *next=child==0?tree->fallthrough:tree->control.kind==ABC_SYM_CONTROL_SWITCH?tree->arms[child-1]:tree->taken;
        uint32_t *child_counts=malloc((size_t)sink->count*sizeof *child_counts);uint8_t *child_expanded=malloc(sink->count?sink->count:1);if(!child_counts||!child_expanded){free(child_counts);free(child_expanded);return 0;}memcpy(child_counts,counts,(size_t)sink->count*sizeof *counts);memcpy(child_expanded,expanded,sink->count);int ok=mark_path_tree(sink,next,child_counts,child_expanded,maximum);free(child_counts);free(child_expanded);if(!ok)return 0;}return 1;
}
static unsigned rematerialization_cost(const DagSink *sink,uint32_t id){
    if(!id||id>sink->count)return UINT_MAX;const Node *n=&sink->nodes[id-1];if(n->effect)return UINT_MAX;if(n->kind==N_INPUT||n->kind==N_LOOP_HOME)return 0;
    if(n->kind==N_UNARY){unsigned left=rematerialization_cost(sink,n->left),cost=n->opcode==OP_ZX32_A||n->opcode==OP_SX32_A?0u:1u;return left==UINT_MAX||left+cost>1?UINT_MAX:left+cost;}
    if(n->kind==N_BINARY){unsigned left=rematerialization_cost(sink,n->left),right=rematerialization_cost(sink,n->right);return left==UINT_MAX||right==UINT_MAX||left+right>=2?UINT_MAX:left+right+1;}return UINT_MAX;
}
static int branch_rematerializable(const DagSink *sink,uint32_t id,const uint32_t *uses,const uint32_t *path_uses){
    return sink->paths>1&&uses[id-1]>1&&path_uses[id-1]==1&&rematerialization_cost(sink,id)<=1;
}
static int branch_local_call(const DagSink *sink,uint32_t id,const uint32_t *uses){
    const Node *n=&sink->nodes[id-1];EffectPayload *p=find_payload(sink,id);return sink->paths>1&&n->kind==N_CALL&&p&&p->results==1&&p->result_nodes&&uses[p->result_nodes[0]-1]==1;
}
static int c_reference(const Schedule *schedule,uint32_t id,unsigned *depth) {
    const Node *n=&schedule->sink->nodes[id-1];
    if(n->kind==N_INPUT&&n->input!=255){*depth=schedule->temps+schedule->suffix+n->input;return *depth<=255;}
    if(schedule->homes[id-1]>=0&&(uint32_t)schedule->homes[id-1]<schedule->temps){*depth=schedule->temps+schedule->suffix-1u-(uint32_t)schedule->homes[id-1];return *depth<=255;}
    return 0;
}
static int emit_node(Bytes *b,const Schedule *schedule,uint32_t id,unsigned stack);
static int emit_operand_shortcut(Bytes *b,const Schedule *schedule,const Node *n,unsigned stack) {
    const DagSink *s=schedule->sink;const Node *right=&s->nodes[n->right-1];int op;unsigned depth;
    if(c_reference(schedule,n->right,&depth)&&(op=c_opcode(n->opcode,stack))>=0)
        return emit_node(b,schedule,n->left,stack)&&emit_origin_opcode(b,n->origin,(unsigned)op)&&emit8(b,(uint8_t)depth);
    if(right->kind==N_INPUT&&right->input==255) {
        uint64_t value=(uint64_t)right->left|((uint64_t)right->right<<32);op=immediate_opcode(n->opcode,stack);
        if(op>=0&&signed8(value))return emit_node(b,schedule,n->left,stack)&&emit_origin_opcode(b,n->origin,(unsigned)op)&&emit8(b,(uint8_t)value);
    }
    return 0;
}
static int same_operand_binary(const DagSink *sink,uint32_t id){
    if(!id||id>sink->count)return 0;const Node *n=&sink->nodes[id-1];return n->kind==N_BINARY&&n->left==n->right;
}
static int duplicated_operand_only(const DagSink *sink,uint32_t id,const uint32_t *uses){
    if(!id||id>sink->count||uses[id-1]!=2||sink->nodes[id-1].effect)return 0;
    for(uint32_t parent=1;parent<=sink->count;parent++)if(same_operand_binary(sink,parent)&&sink->nodes[parent-1].left==id)return 1;
    return 0;
}
static int emit_node(Bytes *b,const Schedule *schedule,uint32_t id,unsigned stack) {
    const DagSink *s=schedule->sink;if(!id||id>s->count)return 0;const Node *n=&s->nodes[id-1];unsigned depth;
    if(n->kind==N_EFFECT){const uint8_t *p=s->module->code+n->origin;uint32_t length=abc_instruction_length(p);if(!record_origin(b,n->origin))return 0;for(uint32_t i=0;i<length;i++)if(!emit8(b,p[i]))return 0;return 1;}
    if(n->kind==N_ABORT)return emit_origin_opcode(b,n->origin,OP_ABORT)&&emit8(b,n->input);
    if(n->kind==N_MEMORY){
        if(memory_result(n->input)&&c_reference(schedule,id,&depth))return emit_cget(b,stack,depth);
        unsigned action=n->input,operand_stack=op_memory[n->opcode].to_b?ABC_SYM_B:ABC_SYM_A;
        if((action==M_FSTORE||action==M_GSTORE||action==M_PLOAD)&&!emit_node(b,schedule,n->left,operand_stack))return 0;
        if((action==M_PSTORE||action==M_XLOAD||action==M_INDEX||action==M_COPY)&&(!emit_node(b,schedule,n->left,ABC_SYM_A)||!emit_node(b,schedule,n->right,ABC_SYM_B)))return 0;
        const uint8_t *p=s->module->code+n->origin;uint32_t length=abc_instruction_length(p);if(!record_origin(b,n->origin))return 0;for(uint32_t i=0;i<length;i++)if(!emit8(b,p[i]))return 0;return 1;
    }
    if(n->kind==N_DYNAMIC||n->kind==N_FOREIGN){
        EffectPayload *payload=find_payload(s,id);if(!payload)return 0;if(payload->results&&c_reference(schedule,id,&depth))return emit_cget(b,stack,depth);
        for(uint32_t i=0;i<payload->count;i++)if(!emit_node(b,schedule,payload->operands[i],ABC_SYM_A))return 0;
        const uint8_t *p=s->module->code+n->origin;uint32_t length=abc_instruction_length(p);if(!record_origin(b,n->origin))return 0;for(uint32_t i=0;i<length;i++)if(!emit8(b,p[i]))return 0;return 1;
    }
    if(n->kind==N_CALL){EffectPayload *payload=find_payload(s,id);if(!payload)return 0;for(uint32_t i=0;i<payload->count;i++)if(!emit_node(b,schedule,payload->operands[i],ABC_SYM_A))return 0;const uint8_t *p=s->module->code+n->origin;uint32_t length=abc_instruction_length(p);if(!record_origin(b,n->origin))return 0;for(uint32_t i=0;i<length;i++)if(!emit8(b,p[i]))return 0;return 1;}
    if(n->kind==N_RESULT){if(c_reference(schedule,id,&depth))return emit_cget(b,stack,depth);EffectPayload *payload=find_payload(s,n->left);if(!payload||payload->results!=1||n->input||!emit_node(b,schedule,n->left,payload->destination))return 0;return payload->destination==stack||emit8(b,(uint8_t)(payload->destination==ABC_SYM_A?OP_MOVE_AB:OP_MOVE_BA));}
    if(c_reference(schedule,id,&depth))return emit_cget(b,stack,depth);
    if(n->kind==N_LOOP_HOME)return emit_node(b,schedule,n->left,stack);
    if(n->kind==N_INPUT) {
        if(n->input==255)return emit_constant(b,stack,(uint64_t)n->left|((uint64_t)n->right<<32));
        return 0;
    }
    if(n->kind==N_CALLABLE)return 0;
    if(n->kind==N_CHECK)return emit_node(b,schedule,n->left,stack)&&emit_origin_opcode(b,n->origin,n->opcode);
    if(n->kind==N_UNARY)return emit_node(b,schedule,n->left,stack)&&emit_origin_opcode(b,n->origin,n->opcode+(stack==ABC_SYM_B));
    if(same_operand_binary(s,id)&&!c_reference(schedule,n->left,&depth))return emit_node(b,schedule,n->left,ABC_SYM_A)&&emit8(b,OP_COPY_AB)&&emit_origin_opcode(b,n->origin,n->opcode+(stack==ABC_SYM_B));
    size_t before=b->size;if(emit_operand_shortcut(b,schedule,n,stack))return 1;b->size=before;
    if(s->nodes[n->right-1].ershov>s->nodes[n->left-1].ershov)
        return emit_node(b,schedule,n->right,ABC_SYM_B)&&emit_node(b,schedule,n->left,ABC_SYM_A)&&emit_origin_opcode(b,n->origin,n->opcode+(stack==ABC_SYM_B));
    return emit_node(b,schedule,n->left,ABC_SYM_A)&&emit_node(b,schedule,n->right,ABC_SYM_B)&&emit_origin_opcode(b,n->origin,n->opcode+(stack==ABC_SYM_B));
}

static int emit_value(Bytes *b,const Schedule *schedule,abc_symbolic_value value,unsigned stack) {
    if(value.kind==ABC_SYM_CONST)return emit_constant(b,stack,value.constant);
    return value.kind==ABC_SYM_BACKEND&&emit_node(b,schedule,value.reg,stack);
}
static int emit_tail_transfer(Bytes *b,const Schedule *schedule,const abc_function *f,uint32_t id){
    const Node *n=&schedule->sink->nodes[id-1];EffectPayload *payload=find_payload(schedule->sink,id);
    if(!payload||(uint32_t)f->arguments+schedule->temps>255)return 0;
    for(uint32_t i=0;i<payload->count;i++)if(!emit_node(b,schedule,payload->operands[i],ABC_SYM_A))return 0;
    const uint8_t *p=schedule->sink->module->code+n->origin;uint32_t length=abc_instruction_length(p);
    if(length<5||!record_origin(b,n->origin)||!emit8(b,OP_TCALL))return 0;
    for(uint32_t i=1;i<5;i++)if(!emit8(b,p[i]))return 0;
    return emit8(b,(uint8_t)(f->arguments+schedule->temps))&&emit8(b,(uint8_t)payload->count);
}
static int emit_root_backedge_operands(Bytes *b,const Schedule *schedule,const abc_function *f,const EffectPayload *payload,uint32_t origin){
    if(!payload||payload->count!=f->arguments)return 0;uint8_t changed[255]={0};
    for(uint32_t depth=payload->count;depth;depth--){uint32_t d=depth-1,id=payload->operands[d];const Node *n=&schedule->sink->nodes[id-1];
        if(n->kind!=N_INPUT||n->input!=d){changed[d]=1;if(!emit_node(b,schedule,id,ABC_SYM_A))return 0;}}
    uint32_t offset=schedule->temps+schedule->suffix;for(uint32_t depth=0;depth<payload->count;depth++)if(changed[depth]&&!emit_cset(b,ABC_SYM_A,offset+depth))return 0;
    for(uint32_t i=0;i<offset;i++)if(!emit8(b,OP_CPOP))return 0;int64_t relative=-(int64_t)(b->size+3);
    return relative>=INT16_MIN&&emit_origin_opcode(b,origin,OP_JMP)&&emit8(b,(uint8_t)(uint16_t)relative)&&emit8(b,(uint8_t)((uint16_t)relative>>8));
}
static uint32_t direct_return_call(const DagSink *sink,const DagTree *tree){if(!tree||!tree->leaf||tree->backedge||!tree->result_count)return 0;uint32_t call=0;for(uint32_t i=0;i<tree->result_count;i++){abc_symbolic_value value=tree->results[i];if(value.kind!=ABC_SYM_BACKEND||!value.reg||value.reg>sink->count)return 0;const Node *result=&sink->nodes[value.reg-1];if(result->kind!=N_RESULT||result->input!=i)return 0;if(!call)call=result->left;else if(call!=result->left)return 0;}EffectPayload *p=find_payload(sink,call);return p&&p->results==tree->result_count?call:0;}
static int fused_boolean_control(const Schedule *schedule,const abc_symbolic_control *input,abc_symbolic_control *output){
    if(input->kind!=ABC_SYM_CONTROL_ZERO||input->left.kind!=ABC_SYM_BACKEND||!input->left.reg||input->left.reg>schedule->sink->count||schedule->homes[input->left.reg-1]>=0)return 0;
    const Node *n=&schedule->sink->nodes[input->left.reg-1];if(n->kind!=N_BINARY)return 0;unsigned opcode=n->opcode;int truth=input->opcode==OP_JNZ_A||input->opcode==OP_JNZ_B,swap=0;
    if(truth){switch(opcode){case OP_EQ_A:opcode=OP_BEQ;break;case OP_NE_A:opcode=OP_BNE;break;case OP_LT_A:opcode=OP_BLT;break;case OP_LE_A:opcode=OP_BLE;break;case OP_LTU_A:opcode=OP_BLTU;break;case OP_LEU_A:opcode=OP_BLEU;break;default:return 0;}}
    else {switch(opcode){case OP_EQ_A:opcode=OP_BNE;break;case OP_NE_A:opcode=OP_BEQ;break;case OP_LT_A:opcode=OP_BLE;swap=1;break;case OP_LE_A:opcode=OP_BLT;swap=1;break;case OP_LTU_A:opcode=OP_BLEU;swap=1;break;case OP_LEU_A:opcode=OP_BLTU;swap=1;break;default:return 0;}}
    uint32_t left=swap?n->right:n->left,right=swap?n->left:n->right;*output=*input;output->kind=ABC_SYM_CONTROL_INTEGER;output->opcode=opcode;output->left=backend(left,ABC_SYM_A,0);const Node *r=&schedule->sink->nodes[right-1];output->right=r->kind==N_INPUT&&r->input==255?abc_symbolic_constant((uint64_t)r->left|((uint64_t)r->right<<32),ABC_SYM_B,0):backend(right,ABC_SYM_B,0);return 1;
}
static int append(Bytes *b,const void *data,size_t size);
static int descriptor_operand(const uint8_t *p,uint32_t *offset,uint32_t *index){
    if(p[0]!=OP_EXT)return 0;switch(p[1]){
    case EXT_ANY_BOX:case EXT_ANY_CAST:case EXT_ANY_IS:case EXT_WORD_NEW:case EXT_MANAGED_NEW:case EXT_MANAGED_COPY:*offset=2;break;
    case EXT_WORD_DIRECT:case EXT_CLOSURE_NEW:*offset=6;break;default:return 0;}*index=abc_u32(p+*offset);return 1;
}
static int mark_descriptor(const abc_module *m,uint32_t index,uint8_t *live){
    if(index>=m->descriptor_count)return 0;if(live[index])return 1;live[index]=1;const abc_descriptor *d=&m->descriptors[index];const uint8_t *p=d->payload;
    if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_SLICE)return mark_descriptor(m,abc_u32(p+4),live);
    if(d->tag==ABC_DESC_SIGNATURE){unsigned n=(unsigned)p[0]+p[1];for(unsigned i=0;i<n;i++)if(!mark_descriptor(m,abc_u32(p+2+4*i),live))return 0;}
    else if(d->tag==ABC_DESC_RECORD){for(uint32_t i=0;i<abc_u32(p+4);i++)if(!mark_descriptor(m,abc_u32(p+8+16*i+12),live))return 0;}
    else if(d->tag==ABC_DESC_ARRAY){if(!mark_descriptor(m,abc_u32(p+8),live))return 0;}
    else if(d->tag==ABC_DESC_SUM){for(unsigned i=0;i<p[9];i++)if(!mark_descriptor(m,abc_u32(p+12+16*i+12),live))return 0;}
    else if(d->tag==ABC_DESC_CLOSURE){if(!mark_descriptor(m,abc_u32(p),live)||!mark_descriptor(m,abc_u32(p+4),live))return 0;}return 1;
}
static void rewrite_u32(uint8_t *p,uint32_t value){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(value>>(8*i));}
static int rewrite_descriptor_table(Bytes *out,const abc_module *m,const uint8_t *live,const uint32_t *new_index,uint32_t live_count){
    if(!emit32(out,live_count))return 0;
    for(uint32_t i=0;i<m->descriptor_count;i++){
        if(!live[i])continue;const abc_descriptor *d=&m->descriptors[i];uint8_t *payload=malloc(d->length?d->length:1);if(!payload)return 0;memcpy(payload,d->payload,d->length);
        if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_SLICE)rewrite_u32(payload+4,new_index[abc_u32(payload+4)]);
        else if(d->tag==ABC_DESC_SIGNATURE){unsigned n=(unsigned)payload[0]+payload[1];for(unsigned j=0;j<n;j++)rewrite_u32(payload+2+4*j,new_index[abc_u32(payload+2+4*j)]);}
        else if(d->tag==ABC_DESC_RECORD){for(uint32_t j=0;j<abc_u32(payload+4);j++)rewrite_u32(payload+8+16*j+12,new_index[abc_u32(payload+8+16*j+12)]);}
        else if(d->tag==ABC_DESC_ARRAY)rewrite_u32(payload+8,new_index[abc_u32(payload+8)]);
        else if(d->tag==ABC_DESC_SUM){for(unsigned j=0;j<payload[9];j++)rewrite_u32(payload+12+16*j+12,new_index[abc_u32(payload+12+16*j+12)]);}
        else if(d->tag==ABC_DESC_CLOSURE){rewrite_u32(payload,new_index[abc_u32(payload)]);rewrite_u32(payload+4,new_index[abc_u32(payload+4)]);}
        int ok=emit8(out,d->tag)&&emit8(out,d->flags)&&emit8(out,(uint8_t)d->length)&&emit8(out,(uint8_t)(d->length>>8))&&append(out,payload,d->length);free(payload);if(!ok)return 0;
    }
    return 1;
}
static int rewrite_gc_roots(Bytes *out,const abc_module *m,const uint32_t *new_index){
    if(!emit32(out,m->gc_root_count))return 0;for(uint32_t i=0;i<m->gc_root_count;i++)if(!emit32(out,m->gc_roots[i].offset)||!emit32(out,new_index[m->gc_roots[i].descriptor]))return 0;return 1;
}
static int descriptor_dce_sections_safe(const void *input,size_t input_size){
    const uint8_t *bytes=input;if(input_size<16)return 0;uint32_t count=abc_u32(bytes+8);size_t at=16;for(uint32_t i=0;i<count;i++){if(at+8>input_size)return 0;uint32_t tag=abc_u32(bytes+at),length=abc_u32(bytes+at+4);if(tag<1||tag>12||length>input_size-at-8)return 0;at+=8+length;}return at==input_size;
}
static int emit_tree(Bytes *b,const Schedule *schedule,const abc_function *f,const DagTree *tree) {
    if(tree->backedge){
        uint8_t changed[255]={0};
        if(tree->nested_backedge){
            for(uint32_t depth=tree->result_count;depth;depth--){uint32_t d=depth-1;abc_symbolic_value value=tree->results[d];if(!same_value(value,schedule->sink->loop_header[d])){if(!schedule->sink->loop_home[d])return 0;changed[d]=1;if(!emit_value(b,schedule,value,ABC_SYM_A))return 0;}}
            for(uint32_t depth=0;depth<tree->result_count;depth++)if(changed[depth]){unsigned target;if(!c_reference(schedule,schedule->sink->loop_home[depth],&target)||!emit_cset(b,ABC_SYM_A,target))return 0;}
            for(uint32_t i=schedule->loop_temps;i<schedule->temps;i++)if(!emit8(b,OP_CPOP))return 0;
            int64_t relative=(int64_t)schedule->loop_prologue-(int64_t)(b->size+3);return relative>=INT16_MIN&&relative<=INT16_MAX&&emit_origin_opcode(b,tree->origin,OP_JMP)&&emit8(b,(uint8_t)(uint16_t)relative)&&emit8(b,(uint8_t)((uint16_t)relative>>8));
        }
        for(uint32_t depth=tree->result_count;depth;depth--){uint32_t d=depth-1;abc_symbolic_value value=tree->results[d];int unchanged=0;if(value.kind==ABC_SYM_BACKEND&&value.reg&&value.reg<=schedule->sink->count){const Node *n=&schedule->sink->nodes[value.reg-1];unchanged=n->kind==N_INPUT&&n->input==d;}if(!unchanged){changed[d]=1;if(!emit_value(b,schedule,value,ABC_SYM_A))return 0;}}
        uint32_t offset=schedule->temps+schedule->suffix;for(uint32_t depth=0;depth<tree->result_count;depth++)if(changed[depth]&&!emit_cset(b,ABC_SYM_A,offset+depth))return 0;for(uint32_t i=0;i<offset;i++)if(!emit8(b,OP_CPOP))return 0;int64_t relative=-(int64_t)(b->size+3);return relative>=INT16_MIN&&emit_origin_opcode(b,tree->origin,OP_JMP)&&emit8(b,(uint8_t)(uint16_t)relative)&&emit8(b,(uint8_t)((uint16_t)relative>>8));
    }
    if(tree->leaf){
        if(tree->tail)return emit_tail_transfer(b,schedule,f,tree->tail_node);
        uint32_t direct=direct_return_call(schedule->sink,tree);if(direct){const Node *call=&schedule->sink->nodes[direct-1];EffectPayload *payload=find_payload(schedule->sink,direct);if(call->left==schedule->sink->root_function)return emit_root_backedge_operands(b,schedule,f,payload,call->origin);return emit_tail_transfer(b,schedule,f,direct);}
        for(uint32_t i=0;i<tree->result_count;i++)if(!emit_value(b,schedule,tree->results[i],ABC_SYM_A))return 0;
        return (uint32_t)f->arguments+schedule->temps<=255&&tree->result_count<=255&&emit8(b,OP_RET)&&emit8(b,(uint8_t)(f->arguments+schedule->temps))&&emit8(b,(uint8_t)tree->result_count);
    }
    abc_symbolic_control fused;const abc_symbolic_control *c=fused_boolean_control(schedule,&tree->control,&fused)?&fused:&tree->control;unsigned stack=(c->opcode==OP_JZ_B||c->opcode==OP_JNZ_B)?ABC_SYM_B:ABC_SYM_A;
    if(!emit_value(b,schedule,c->left,stack))return 0;
    if(c->kind==ABC_SYM_CONTROL_SWITCH){
        if(c->count>UINT16_MAX||!emit_origin_opcode(b,tree->origin,OP_SWITCH)||!emit8(b,(uint8_t)c->count)||!emit8(b,(uint8_t)(c->count>>8)))return 0;size_t table=b->size;
        for(uint32_t i=0;i<c->count;i++)if(!emit32(b,0))return 0;size_t next=b->size;if(!emit_tree(b,schedule,f,tree->fallthrough))return 0;
        for(uint32_t i=0;i<c->count;i++){int64_t relative=(int64_t)b->size-(int64_t)next;if(relative<INT32_MIN||relative>INT32_MAX)return 0;for(unsigned j=0;j<4;j++)b->data[table+4*i+j]=(uint8_t)((uint32_t)(int32_t)relative>>(8*j));if(!emit_tree(b,schedule,f,tree->arms[i]))return 0;}return 1;
    }
    int branch_opcode=(int)c->opcode,branch_immediate=0;
    if(c->kind==ABC_SYM_CONTROL_INTEGER&&c->right.kind==ABC_SYM_CONST&&signed8(c->right.constant)){int op=branch_immediate_opcode(c->opcode);if(op>=0){branch_opcode=op;branch_immediate=1;}}
    if(c->kind==ABC_SYM_CONTROL_INTEGER&&!branch_immediate&&!emit_value(b,schedule,c->right,ABC_SYM_B))return 0;
    if(!emit_origin_opcode(b,tree->origin,(unsigned)branch_opcode))return 0;if((c->kind==ABC_SYM_CONTROL_IMMEDIATE||branch_immediate)&&!emit8(b,(uint8_t)c->right.constant))return 0;
    size_t displacement=b->size;if(!emit8(b,0)||!emit8(b,0))return 0;size_t next=b->size;
    if(!emit_tree(b,schedule,f,tree->fallthrough))return 0;int64_t relative=(int64_t)b->size-(int64_t)next;if(relative<INT16_MIN||relative>INT16_MAX)return 0;
    b->data[displacement]=(uint8_t)(uint16_t)relative;b->data[displacement+1]=(uint8_t)((uint16_t)relative>>8);
    return emit_tree(b,schedule,f,tree->taken);
}

typedef struct { size_t at[ABC_SYMBOLIC_VERSION_CAP]; uint32_t count; } PhiPatches;
static int emit_phi_tree(Bytes *b,const Schedule *schedule,const DagTree *tree,uint32_t results,PhiPatches *patches) {
    if(tree->leaf){
        if(tree->result_count!=results)return 0;for(uint32_t i=0;i<results;i++)if(!emit_value(b,schedule,tree->results[i],ABC_SYM_A)||!emit_cset(b,ABC_SYM_A,results-1-i))return 0;
        if(patches->count>=ABC_SYMBOLIC_VERSION_CAP||!emit8(b,OP_JMP32))return 0;patches->at[patches->count++]=b->size;return emit32(b,0);
    }
    abc_symbolic_control fused;const abc_symbolic_control *c=fused_boolean_control(schedule,&tree->control,&fused)?&fused:&tree->control;unsigned stack=(c->opcode==OP_JZ_B||c->opcode==OP_JNZ_B)?ABC_SYM_B:ABC_SYM_A;if(!emit_value(b,schedule,c->left,stack))return 0;
    if(c->kind==ABC_SYM_CONTROL_SWITCH){
        if(!emit_origin_opcode(b,tree->origin,OP_SWITCH)||!emit8(b,(uint8_t)c->count)||!emit8(b,(uint8_t)(c->count>>8)))return 0;size_t table=b->size;for(uint32_t i=0;i<c->count;i++)if(!emit32(b,0))return 0;size_t next=b->size;
        if(!emit_phi_tree(b,schedule,tree->fallthrough,results,patches))return 0;for(uint32_t i=0;i<c->count;i++){int64_t relative=(int64_t)b->size-(int64_t)next;if(relative<INT32_MIN||relative>INT32_MAX)return 0;for(unsigned j=0;j<4;j++)b->data[table+4*i+j]=(uint8_t)((uint32_t)(int32_t)relative>>(8*j));if(!emit_phi_tree(b,schedule,tree->arms[i],results,patches))return 0;}return 1;
    }
    int branch_opcode=(int)c->opcode,branch_immediate=0;if(c->kind==ABC_SYM_CONTROL_INTEGER&&c->right.kind==ABC_SYM_CONST&&signed8(c->right.constant)){int op=branch_immediate_opcode(c->opcode);if(op>=0){branch_opcode=op;branch_immediate=1;}}
    if(c->kind==ABC_SYM_CONTROL_INTEGER&&!branch_immediate&&!emit_value(b,schedule,c->right,ABC_SYM_B))return 0;if(!emit_origin_opcode(b,tree->origin,(unsigned)branch_opcode))return 0;if((c->kind==ABC_SYM_CONTROL_IMMEDIATE||branch_immediate)&&!emit8(b,(uint8_t)c->right.constant))return 0;
    size_t displacement=b->size;if(!emit8(b,0)||!emit8(b,0))return 0;size_t next=b->size;if(!emit_phi_tree(b,schedule,tree->fallthrough,results,patches))return 0;int64_t relative=(int64_t)b->size-(int64_t)next;if(relative<INT16_MIN||relative>INT16_MAX)return 0;
    b->data[displacement]=(uint8_t)(uint16_t)relative;b->data[displacement+1]=(uint8_t)((uint16_t)relative>>8);return emit_phi_tree(b,schedule,tree->taken,results,patches);
}

static int residualize_function(const abc_module *m,const CallGraph *graph,uint32_t fi,const ArgumentFact *facts,FunctionCode *out) {
    const abc_function *f=&m->functions[fi];if(f->hidden_bytes)return 0;
    for(uint32_t pc=f->entry;pc<f->end;pc+=abc_instruction_length(m->code+pc)){unsigned action=op_memory[m->code[pc]].action;if(action==M_ALLOC||action==M_FREE)return 0;}
    if(m->memory_profile){for(uint32_t i=0;i<f->arguments;i++)if(f->argument_kinds[i]!=ABC_KIND_INT)return 0;for(uint32_t i=0;i<f->results;i++)if(f->result_kinds[i]!=ABC_KIND_INT)return 0;}
    DagSink sink={.module=m,.graph=graph,.root_function=fi,.root_entry=f->entry,.root_arguments=f->arguments,.callable_safe=callable_module_safe(m),.dynamic_callable_safe=dynamic_callable_module_safe(m)};abc_symbolic_context context={0};
    uint32_t *uses=NULL,*path_uses=NULL;int32_t *homes=NULL;uint8_t *expanded=NULL;Bytes code={.function=out};DagTree *tree=NULL;
    for(uint32_t i=0;i<f->arguments;i++) {
        abc_symbolic_value value;if(facts&&facts[i].kind==FACT_CONSTANT)value=abc_symbolic_constant(facts[i].constant,ABC_SYM_C,-1-(int32_t)i);else {uint32_t id=node(&sink,(Node){N_INPUT,f->entry,0,0,0,(uint8_t)i,0,0});if(!id)goto failed;value=backend(id,ABC_SYM_C,-1-(int32_t)i);}
        if(!abc_symbolic_push(&context,ABC_SYM_C,value))goto failed;
    }
    /* Arguments are stored deepest-last so C depth i names source argument i. */
    for(uint32_t i=0;i<f->arguments/2;i++){abc_symbolic_value q=context.s[ABC_SYM_C][i];context.s[ABC_SYM_C][i]=context.s[ABC_SYM_C][f->arguments-1-i];context.s[ABC_SYM_C][f->arguments-1-i]=q;}
    context.c_origin=(int32_t)f->arguments;
    abc_error error;abc_symbolic_machine machine={.module=m,.code=m->code,.pc=f->entry,.end=(uint32_t)m->code_size,
        .context=&context,.sink=&sink,.error=&error,
        .transfer_mask=ABC_SYM_TRANSFER_STACK|ABC_SYM_TRANSFER_VALUE|ABC_SYM_TRANSFER_CONTROL|ABC_SYM_TRANSFER_EFFECT};
    sink.machine=&machine;machine.emit_binary=dag_binary;machine.emit_unary=dag_unary;machine.emit_check=dag_check;
    machine.emit_immediate=dag_immediate;machine.emit_c_operand=dag_c_operand;machine.emit_effect=dag_effect;machine.emit_memory=dag_memory;machine.emit_control=dag_control;machine.emit_abort=dag_abort;
    machine.emit_return=dag_return;machine.emit_call=dag_call;machine.emit_indirect=dag_indirect;machine.emit_tail=dag_tail;machine.emit_dynamic=dag_dynamic;machine.emit_foreign=dag_foreign;machine.emit_edge=dag_edge;
    if(!simulate_tree(&sink,&machine,&context,f->entry,&tree)||sink.unsupported||(!sink.terminal_abort&&!tree_arity(tree,f->results)))goto failed;
    if(sink.count){uses=calloc(sink.count,sizeof *uses);path_uses=calloc(sink.count,sizeof *path_uses);homes=malloc((size_t)sink.count*sizeof *homes);expanded=calloc(sink.count,1);if(!uses||!path_uses||!homes||!expanded)goto failed;for(uint32_t i=0;i<sink.count;i++)homes[i]=-1;}
    for(uint32_t id=1;id<=sink.count;id++)if(sink.nodes[id-1].effect){EffectPayload *p=find_payload(&sink,id);if((!p||!p->results)&&(!compute_ershov(&sink,id)||!mark_uses(&sink,id,uses,expanded)))goto failed;}
    if(!sink.terminal_abort&&!mark_tree(&sink,tree,uses,expanded))goto failed;
    if(sink.paths>1)for(uint32_t id=1;id<=sink.count;id++)if(sink.nodes[id-1].effect&&!branch_local_call(&sink,id,uses))goto failed;
    for(uint32_t id=1;id<=sink.count;id++){EffectPayload *p=find_payload(&sink,id);if(p&&sink.nodes[id-1].kind==N_CALL){if(!uses[id-1]&&(!compute_ershov(&sink,id)||!mark_uses(&sink,id,uses,expanded)))goto failed;continue;}if(p&&p->results){if(uses[id-1]>1)goto failed;if(!uses[id-1]){p->dead=1;if(!compute_ershov(&sink,id)||!mark_uses(&sink,id,uses,expanded))goto failed;}}}
    if(!sink.terminal_abort){uint32_t *path_counts=calloc(sink.count?sink.count:1,sizeof *path_counts);uint8_t *path_expanded=calloc(sink.count?sink.count:1,1);if(!path_counts||!path_expanded||!mark_path_tree(&sink,tree,path_counts,path_expanded,path_uses)){free(path_counts);free(path_expanded);goto failed;}free(path_counts);free(path_expanded);}
    uint32_t direct_return=direct_return_call(&sink,tree);if(direct_return){EffectPayload *p=find_payload(&sink,direct_return);if(p)p->direct_return=1;}
    Schedule schedule={.sink=&sink,.homes=homes};
    for(uint32_t id=1;id<=sink.count;id++)if(sink.nodes[id-1].kind==N_LOOP_HOME){
        if((uint32_t)f->arguments+schedule.temps>=255||!emit_node(&code,&schedule,id,ABC_SYM_A)||!emit8(&code,OP_CPUSH_A))goto emit_failed;homes[id-1]=(int32_t)schedule.temps++;
    }
    schedule.loop_temps=schedule.temps;schedule.loop_prologue=code.size;
    for(uint32_t id=1;id<=sink.count;id++)if((sink.nodes[id-1].effect||uses[id-1]>1)&&!branch_rematerializable(&sink,id,uses,path_uses)&&!duplicated_operand_only(&sink,id,uses)&&!branch_local_call(&sink,id,uses)&&sink.nodes[id-1].kind!=N_INPUT&&sink.nodes[id-1].kind!=N_LOOP_HOME) {
        Node *scheduled=&sink.nodes[id-1];EffectPayload *payload=(scheduled->kind==N_DYNAMIC||scheduled->kind==N_FOREIGN||scheduled->kind==N_CALL)?find_payload(&sink,id):NULL;
        if(scheduled->kind==N_CALL){if(payload&&payload->direct_return)continue;if(!payload||!emit_node(&code,&schedule,id,ABC_SYM_A))goto emit_failed;int live=0;for(uint32_t i=0;i<payload->results;i++)if(uses[payload->result_nodes[i]-1])live=1;if(live){if((uint32_t)f->arguments+schedule.temps+payload->results>255)goto emit_failed;for(uint32_t i=payload->results;i;i--){uint32_t result=payload->result_nodes[i-1];if(!emit8(&code,payload->destination==ABC_SYM_A?OP_CPUSH_A:OP_CPUSH_B))goto emit_failed;homes[result-1]=(int32_t)schedule.temps++;}}else for(uint32_t i=0;i<payload->results;i++)if(!emit8(&code,payload->destination==ABC_SYM_A?OP_DROP_A:OP_DROP_B))goto emit_failed;continue;}
        if(payload&&payload->results&&!payload->dead)continue;
        if(scheduled->kind==N_ABORT||scheduled->kind==N_EFFECT||(scheduled->kind==N_MEMORY&&!memory_result(scheduled->input))||(payload&&!payload->results)){if(!emit_node(&code,&schedule,id,ABC_SYM_A))goto emit_failed;continue;}
        if(payload&&payload->dead){if(!emit_node(&code,&schedule,id,ABC_SYM_A)||!emit8(&code,OP_DROP_A))goto emit_failed;continue;}
        if((uint32_t)f->arguments+schedule.temps>=255||!emit_node(&code,&schedule,id,ABC_SYM_A)||!emit8(&code,OP_CPUSH_A))goto emit_failed;
        homes[id-1]=(int32_t)schedule.temps++;
    }
    schedule.loop_header=code.size;
    if(!sink.terminal_abort&&sink.paths>1&&f->results>1&&!tree_has_backedge(tree)&&!tree_has_tail(tree)){
        if((uint32_t)f->arguments+schedule.temps+f->results>255)goto emit_failed;
        for(uint32_t i=0;i<f->results;i++)if(!emit_constant(&code,ABC_SYM_A,0)||!emit8(&code,OP_CPUSH_A))goto emit_failed;
        schedule.suffix=f->results;PhiPatches patches={0};if(!emit_phi_tree(&code,&schedule,tree,f->results,&patches))goto emit_failed;size_t join=code.size;
        for(uint32_t i=0;i<patches.count;i++){int64_t relative=(int64_t)join-(int64_t)(patches.at[i]+4);if(relative<INT32_MIN||relative>INT32_MAX)goto emit_failed;for(unsigned j=0;j<4;j++)code.data[patches.at[i]+j]=(uint8_t)((uint32_t)(int32_t)relative>>(8*j));}
        for(uint32_t i=0;i<f->results;i++)if(!emit_cget(&code,ABC_SYM_A,f->results-1-i))goto emit_failed;
        if(!emit8(&code,OP_RET)||!emit8(&code,(uint8_t)(f->arguments+schedule.temps+f->results))||!emit8(&code,(uint8_t)f->results))goto emit_failed;
    } else if(!sink.terminal_abort&&!emit_tree(&code,&schedule,f,tree))goto emit_failed;
    out->code=code.data;out->length=(uint32_t)code.size;out->optimized=1;out->calls=sink.calls;out->call_count=sink.call_count;sink.calls=NULL;sink.call_count=0;abc_symbolic_context_free(&context);abc_symbolic_context_free(&sink.loop_initial);free_tree(tree);for(uint32_t i=0;i<sink.payload_count;i++){free(sink.payloads[i].operands);free(sink.payloads[i].result_nodes);}free(sink.payloads);free(sink.nodes);free(uses);free(path_uses);free(homes);free(expanded);return 1;
emit_failed:free(code.data);
failed:abc_symbolic_context_free(&context);abc_symbolic_context_free(&sink.loop_initial);free_tree(tree);for(uint32_t i=0;i<sink.payload_count;i++){free(sink.payloads[i].operands);free(sink.payloads[i].result_nodes);}for(uint32_t i=0;i<sink.call_count;i++)free(sink.calls[i].facts);free(sink.calls);free(sink.payloads);free(sink.nodes);free(uses);free(path_uses);free(homes);free(expanded);return 0;
}
static void clear_function_code(FunctionCode *f){free(f->code);free(f->provenance);for(uint32_t i=0;i<f->call_count;i++)free(f->calls[i].facts);free(f->calls);memset(f,0,sizeof *f);}
static int append_unknown_call(FunctionCode *out,uint32_t target,uint32_t arguments){ResidualCall *calls=realloc(out->calls,(size_t)(out->call_count+1)*sizeof *calls);if(!calls)return 0;out->calls=calls;ResidualCall *call=&out->calls[out->call_count++];*call=(ResidualCall){.target=target,.arguments=arguments};call->facts=calloc(arguments?arguments:1,sizeof *call->facts);if(!call->facts)return 0;for(uint32_t i=0;i<arguments;i++)call->facts[i].kind=FACT_UNKNOWN;return 1;}
static int retain_function(const abc_module *m,uint32_t fi,FunctionCode *out){
    uint32_t length=m->functions[fi].end-m->functions[fi].entry;out->code=malloc(length?length:1);if(!out->code)return 0;memcpy(out->code,m->code+m->functions[fi].entry,length);out->length=length;out->optimized=0;
    for(uint32_t pc=m->functions[fi].entry;pc<m->functions[fi].end;pc+=abc_instruction_length(m->code+pc)){
        uint32_t target;if(direct_target(m,pc,&target)){int to=abc_find_function(m,target);if(to<0||!append_unknown_call(out,(uint32_t)to,m->functions[to].arguments))return 0;}
        else if(dynamic_callable_target(m,pc,&target)&&!append_unknown_call(out,target,m->functions[target].arguments))return 0;
    }return 1;
}

static int append(Bytes *b,const void *data,size_t size){if(!bytes_reserve(b,size))return 0;memcpy(b->data+b->size,data,size);b->size+=size;return 1;}
static int section(Bytes *b,uint32_t tag,const void *data,uint32_t size){return emit32(b,tag)&&emit32(b,size)&&append(b,data,size);}
static int relocate_pc(const abc_module *m,const FunctionCode *functions,const uint32_t *entries,const uint8_t *live,uint32_t old,uint32_t *out) {
    for(uint32_t i=0;i<m->function_count;i++)if(old>=m->functions[i].entry&&old<m->functions[i].end) {
        if(!live[i])return 0;
        if(functions[i].optimized){for(uint32_t j=0;j<functions[i].provenance_count;j++)if(functions[i].provenance[j].input_offset==old){*out=entries[i]+functions[i].provenance[j].output_offset;return 1;}return 0;}
        *out=entries[i]+old-m->functions[i].entry;return 1;
    }
    return 0;
}
static int rewrite_pc_section(Bytes *out,uint32_t tag,const uint8_t *p,uint32_t size,const abc_module *m,const FunctionCode *functions,const uint32_t *entries,const uint8_t *live) {
    if(size<4)return 0;uint32_t count=abc_u32(p),at=4,written=0;size_t count_at=out->size;if(!emit32(out,0))return 0;
    for(uint32_t i=0;i<count;i++) {
        if(at+4>size)return 0;uint32_t old=abc_u32(p+at),relocated;at+=4;
        uint32_t rest;if(tag==6)rest=1;else { if(at+12>size)return 0;uint32_t arguments=abc_u32(p+at),results=abc_u32(p+at+4);rest=12+arguments+results; }
        if(at+rest>size)return 0;if(relocate_pc(m,functions,entries,live,old,&relocated)){if(!emit32(out,relocated)||!append(out,p+at,rest))return 0;written++;}at+=rest;
    }
    for(unsigned i=0;i<4;i++)out->data[count_at+i]=(uint8_t)(written>>(8*i));return at==size;
}
static int emitted_origin(const abc_module *m,const FunctionCode *functions,uint32_t fi,uint32_t pc,uint32_t *origin){if(!functions[fi].optimized){*origin=m->functions[fi].entry+pc;return 1;}for(uint32_t j=0;j<functions[fi].provenance_count;j++)if(functions[fi].provenance[j].output_offset==pc){*origin=functions[fi].provenance[j].input_offset;return 1;}return 0;}
static int mark_residual_callees(const abc_module *m,const FunctionCode *functions,uint32_t fi,uint8_t *live,int *changed){
    (void)m;for(uint32_t i=0;i<functions[fi].call_count;i++){uint32_t target=functions[fi].calls[i].target;if(!live[target]){live[target]=1;*changed=1;}}return 1;
}
static int mark_live_functions(const abc_module *m,const FunctionCode *functions,uint8_t *live){
    for(uint32_t i=0;i<m->export_count;i++)live[m->exports[i].function]=1;for(uint32_t i=0;i<m->reloc_count;i++)live[m->relocs[i].function]=1;int changed=1;while(changed){changed=0;for(uint32_t fi=0;fi<m->function_count;fi++)if(live[fi]&&!mark_residual_callees(m,functions,fi,live,&changed))return 0;}return 1;
}
static int rewrite_code_relocs(Bytes *out,const abc_module *m,const uint32_t *new_index,const uint8_t *p,uint32_t size){
    if(size!=4u+8u*m->reloc_count||abc_u32(p)!=m->reloc_count||!emit32(out,m->reloc_count))return 0;for(uint32_t i=0;i<m->reloc_count;i++){uint32_t at=4+8*i;if(abc_u32(p+at)!=m->relocs[i].offset||abc_u32(p+at+4)!=m->relocs[i].function||!emit32(out,m->relocs[i].offset)||!emit32(out,new_index[m->relocs[i].function]))return 0;}return 1;
}
static int write_module(const abc_module *m,FunctionCode *functions,const void *input,size_t input_size,void **out,size_t *out_size,abc_provenance **provenance,size_t *provenance_count) {
    Bytes code={0},ft={0},xt={0},module={0};abc_provenance *map=NULL;size_t map_count=0,map_at=0;uint32_t live_count=0,descriptor_live_count=0;
    uint32_t *entries=calloc(m->function_count,sizeof *entries),*new_index=calloc(m->function_count,sizeof *new_index),*descriptor_index=NULL;uint8_t *live=calloc(m->function_count,1),*descriptor_live=NULL;int descriptor_dce=m->dynamic_profile&&descriptor_dce_sections_safe(input,input_size);
    if(m->dynamic_profile){descriptor_index=calloc(m->descriptor_count?m->descriptor_count:1,sizeof *descriptor_index);descriptor_live=calloc(m->descriptor_count?m->descriptor_count:1,1);}if(!entries||!new_index||!live||(m->dynamic_profile&&(!descriptor_index||!descriptor_live)))goto failed;
    if(m->export_count||m->reloc_count){if(!mark_live_functions(m,functions,live))goto failed;}else memset(live,1,m->function_count);for(uint32_t i=0;i<m->function_count;i++)if(live[i]){new_index[i]=live_count++;entries[i]=(uint32_t)code.size;if(!append(&code,functions[i].code,functions[i].length))goto failed;}
    if(provenance){for(uint32_t i=0;i<m->function_count;i++)if(live[i]){if(functions[i].optimized)map_count+=functions[i].provenance_count;else for(uint32_t pc=m->functions[i].entry;pc<m->functions[i].end;pc+=abc_instruction_length(m->code+pc))map_count++;}map=calloc(map_count?map_count:1,sizeof *map);if(!map)goto failed;
        for(uint32_t i=0;i<m->function_count;i++)if(live[i]){if(functions[i].optimized){for(uint32_t j=0;j<functions[i].provenance_count;j++)map[map_at++]=(abc_provenance){entries[i]+functions[i].provenance[j].output_offset,functions[i].provenance[j].input_offset};}else for(uint32_t pc=m->functions[i].entry;pc<m->functions[i].end;pc+=abc_instruction_length(m->code+pc))map[map_at++]=(abc_provenance){entries[i]+pc-m->functions[i].entry,pc};}
    }
    for(uint32_t i=0;i<m->function_count;i++)if(live[i])for(uint32_t pc=0;pc<functions[i].length;){
        const uint8_t *p=functions[i].code+pc;uint32_t length=abc_instruction_length(p);unsigned kind=op_kind[p[0]];if(kind==K_CALL||kind==K_TCALL){uint32_t origin;if(!emitted_origin(m,functions,i,pc,&origin))goto failed;const uint8_t *old=m->code+origin;uint32_t old_length=abc_instruction_length(old),old_target=(uint32_t)((int64_t)(origin+old_length)+abc_i32(old+1));int target=abc_find_function(m,old_target);if(target<0||!live[target])goto failed;uint32_t at=entries[i]+pc+1,next=entries[i]+pc+length;int64_t delta=(int64_t)entries[target]-next;if(delta<INT32_MIN||delta>INT32_MAX)goto failed;int32_t relative=(int32_t)delta;for(unsigned j=0;j<4;j++)code.data[at+j]=(uint8_t)((uint32_t)relative>>(8*j));}
        else if(p[0]==OP_EXT&&(p[1]==EXT_WORD_DIRECT||p[1]==EXT_CLOSURE_NEW)){uint32_t origin,target;if(!emitted_origin(m,functions,i,pc,&origin)||!dynamic_callable_target(m,origin,&target)||!live[target])goto failed;uint32_t mapped=new_index[target],at=entries[i]+pc+2;for(unsigned j=0;j<4;j++)code.data[at+j]=(uint8_t)(mapped>>(8*j));}pc+=length;
    }
    if(descriptor_dce){
        for(uint32_t pc=0;pc<code.size;pc+=abc_instruction_length(code.data+pc)){uint32_t offset,index;if(descriptor_operand(code.data+pc,&offset,&index)&&!mark_descriptor(m,index,descriptor_live))goto failed;}
        for(uint32_t i=0;i<m->gc_root_count;i++)if(!mark_descriptor(m,m->gc_roots[i].descriptor,descriptor_live))goto failed;
        for(uint32_t i=0;i<m->descriptor_count;i++)if(descriptor_live[i])descriptor_index[i]=descriptor_live_count++;
        for(uint32_t pc=0;pc<code.size;pc+=abc_instruction_length(code.data+pc)){uint32_t offset,index;if(descriptor_operand(code.data+pc,&offset,&index))rewrite_u32(code.data+pc+offset,descriptor_index[index]);}
    }
    if(!emit32(&ft,live_count))goto failed;for(uint32_t i=0;i<m->function_count;i++)if(live[i]){const abc_function *f=&m->functions[i];if(!emit32(&ft,entries[i])||!emit32(&ft,f->arguments)||!emit32(&ft,f->results)||!emit32(&ft,f->hidden_bytes))goto failed;if(m->memory_profile&&(!append(&ft,f->argument_kinds,f->arguments)||!append(&ft,f->result_kinds,f->results)))goto failed;}
    if(!emit32(&xt,m->export_count))goto failed;for(uint32_t i=0;i<m->export_count;i++){size_t n=strlen(m->exports[i].name);if(n>UINT16_MAX||!emit32(&xt,new_index[m->exports[i].function])||!emit8(&xt,(uint8_t)n)||!emit8(&xt,(uint8_t)(n>>8))||!append(&xt,m->exports[i].name,n))goto failed;}
    const uint8_t *bytes=input;if(input_size<16||!append(&module,bytes,16))goto failed;uint32_t section_count=abc_u32(bytes+8);size_t at=16;for(uint32_t i=0;i<section_count;i++){if(at+8>input_size)goto failed;uint32_t tag=abc_u32(bytes+at),length=abc_u32(bytes+at+4);at+=8;if(at+length>input_size)goto failed;
        if(tag==1){if(!section(&module,tag,ft.data,(uint32_t)ft.size))goto failed;}else if(tag==2){if(!section(&module,tag,code.data,(uint32_t)code.size))goto failed;}else if(tag==3){if(!section(&module,tag,xt.data,(uint32_t)xt.size))goto failed;}
        else if((tag==6&&m->memory_profile)||(tag==7&&m->callable_profile)){Bytes rewritten={0};if(!rewrite_pc_section(&rewritten,tag,bytes+at,length,m,functions,entries,live)||!section(&module,tag,rewritten.data,(uint32_t)rewritten.size)){free(rewritten.data);goto failed;}free(rewritten.data);}
        else if(tag==8&&m->callable_profile){Bytes rewritten={0};if(!rewrite_code_relocs(&rewritten,m,new_index,bytes+at,length)||!section(&module,tag,rewritten.data,(uint32_t)rewritten.size)){free(rewritten.data);goto failed;}free(rewritten.data);}
        else if(tag==10&&descriptor_dce){Bytes rewritten={0};if(!rewrite_descriptor_table(&rewritten,m,descriptor_live,descriptor_index,descriptor_live_count)||!section(&module,tag,rewritten.data,(uint32_t)rewritten.size)){free(rewritten.data);goto failed;}free(rewritten.data);}
        else if(tag==12&&descriptor_dce){Bytes rewritten={0};if(!rewrite_gc_roots(&rewritten,m,descriptor_index)||!section(&module,tag,rewritten.data,(uint32_t)rewritten.size)){free(rewritten.data);goto failed;}free(rewritten.data);}
        else if(!section(&module,tag,bytes+at,length))goto failed;at+=length;
    }
    if(at!=input_size)goto failed;*out=module.data;*out_size=module.size;if(provenance){*provenance=map;*provenance_count=map_at;}free(entries);free(new_index);free(live);free(descriptor_index);free(descriptor_live);free(code.data);free(ft.data);free(xt.data);return 1;
failed:free(entries);free(new_index);free(live);free(descriptor_index);free(descriptor_live);free(code.data);free(ft.data);free(xt.data);free(module.data);free(map);return 0;
}

static int activate_function_facts(const abc_module *m,ArgumentFact **facts,uint8_t *needed,uint8_t *dirty,uint32_t fi,int unknown){
    if(!facts[fi]){uint32_t n=m->functions[fi].arguments;facts[fi]=calloc(n?n:1,sizeof *facts[fi]);if(!facts[fi])return 0;needed[fi]=1;dirty[fi]=1;}if(unknown)for(uint32_t i=0;i<m->functions[fi].arguments;i++)if(facts[fi][i].kind!=FACT_UNKNOWN){facts[fi][i].kind=FACT_UNKNOWN;dirty[fi]=1;}return 1;
}
static int join_call_facts(const abc_module *m,ArgumentFact **facts,uint8_t *needed,uint8_t *dirty,const ResidualCall *call){
    uint32_t fi=call->target;if(call->arguments!=m->functions[fi].arguments||!activate_function_facts(m,facts,needed,dirty,fi,0))return 0;for(uint32_t i=0;i<call->arguments;i++){ArgumentFact incoming=call->facts[i],*header=&facts[fi][i];FactKind old=header->kind;if(old==FACT_UNREACHED)*header=incoming;else if(old==FACT_CONSTANT&&(incoming.kind==FACT_UNKNOWN||(incoming.kind==FACT_CONSTANT&&incoming.constant!=header->constant))){header->kind=FACT_UNKNOWN;header->constant=0;}if(header->kind!=old)dirty[fi]=1;}return 1;
}

static abc_status optimize_impl(const void *input,size_t input_size,void **output,size_t *output_size,abc_provenance **provenance,size_t *provenance_count,abc_error *error) {
    abc_clear(error);if(output)*output=NULL;if(output_size)*output_size=0;if(provenance)*provenance=NULL;if(provenance_count)*provenance_count=0;
    if(!input||!output||!output_size||(provenance&&!provenance_count))return abc_fail(error,ABC_INVALID,UINT32_MAX,"invalid optimizer input");
    abc_module *m=NULL;abc_status status=abc_module_load(input,input_size,&m,error);if(status!=ABC_OK)return status;
    void *bytes=NULL;size_t size=0;abc_provenance *map=NULL;size_t map_count=0;int optimized=0;
    CallGraph graph={0};FunctionCode *functions=calloc(m->function_count,sizeof *functions);uint8_t *needed=calloc(m->function_count,1),*dirty=calloc(m->function_count,1);ArgumentFact **facts=calloc(m->function_count,sizeof *facts);
    if(!functions||!needed||!dirty||!facts||!build_call_graph(m,&graph)){free(functions);free(needed);free(dirty);free(facts);free_call_graph(&graph);status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"optimizer allocation failed");goto done;}
    int roots=m->export_count||m->reloc_count;if(roots){for(uint32_t i=0;i<m->export_count;i++)if(!activate_function_facts(m,facts,needed,dirty,m->exports[i].function,1))goto optimize_failed;for(uint32_t i=0;i<m->reloc_count;i++)if(!activate_function_facts(m,facts,needed,dirty,m->relocs[i].function,1))goto optimize_failed;}else for(uint32_t i=0;i<m->function_count;i++)if(!activate_function_facts(m,facts,needed,dirty,i,1))goto optimize_failed;
    optimized=1;for(;;){uint32_t i=0;while(i<m->function_count&&!dirty[i])i++;if(i==m->function_count)break;dirty[i]=0;clear_function_code(&functions[i]);
        if(!residualize_function(m,&graph,i,facts[i],&functions[i])){clear_function_code(&functions[i]);if(!retain_function(m,i,&functions[i])){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"optimizer allocation failed");optimized=0;break;}}
        for(uint32_t j=0;j<functions[i].call_count;j++)if(!join_call_facts(m,facts,needed,dirty,&functions[i].calls[j])){status=abc_fail(error,ABC_INVALID,UINT32_MAX,"optimizer residual call facts are invalid");optimized=0;break;}if(!optimized)break;
    }
    if(optimized&&!write_module(m,functions,input,input_size,&bytes,&size,provenance?&map:NULL,&map_count)){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"optimizer emission failed");optimized=0;}
    goto optimize_cleanup;
optimize_failed:status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"optimizer allocation failed");optimized=0;
optimize_cleanup:for(uint32_t i=0;i<m->function_count;i++){clear_function_code(&functions[i]);free(facts[i]);}free(functions);free(needed);free(dirty);free(facts);free_call_graph(&graph);
    if(!optimized) { bytes=malloc(input_size);if(!bytes){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"optimizer allocation failed");goto done;}memcpy(bytes,input,input_size);size=input_size;
        if(provenance){for(uint32_t pc=0;pc<m->code_size;pc+=abc_instruction_length(m->code+pc))map_count++;map=calloc(map_count?map_count:1,sizeof *map);if(!map){free(bytes);bytes=NULL;status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"provenance allocation failed");goto done;}size_t j=0;for(uint32_t pc=0;pc<m->code_size;pc+=abc_instruction_length(m->code+pc))map[j++]=(abc_provenance){pc,pc};}
    }
    abc_module *verified=NULL;status=abc_module_load(bytes,size,&verified,error);if(status!=ABC_OK){free(bytes);free(map);bytes=NULL;size=0;goto done;}abc_module_free(verified);
    *output=bytes;*output_size=size;if(provenance){*provenance=map;*provenance_count=map_count;}status=ABC_OK;
done:abc_module_free(m);return status;
}
abc_status abc_optimize(const void *input,size_t input_size,void **output,size_t *output_size,abc_error *error) {
    return optimize_impl(input,input_size,output,output_size,NULL,NULL,error);
}
abc_status abc_optimize_mapped(const void *input,size_t input_size,void **output,size_t *output_size,abc_provenance **provenance,size_t *provenance_count,abc_error *error) {
    return optimize_impl(input,input_size,output,output_size,provenance,provenance_count,error);
}
void abc_optimized_free(void *bytes){free(bytes);}
