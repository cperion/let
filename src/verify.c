#include "internal.h"

/* Canonical persistent stack shapes. C includes indivisible padded byte blocks.
   This is the existing kind/layout verifier, shared by every typed profile. */
typedef struct { uint32_t prev,span,bytes,depth; unsigned kind; } Node;
typedef struct { Node *nodes; uint32_t *hash; uint32_t count,capacity,hash_size; abc_status error; } Pool;
typedef struct { uint32_t a,b,c; unsigned seen; } Shape;
enum { MAX_NODES=1048576 };
static uint32_t hash_node(Node n) {return n.prev*UINT32_C(2654435761)^n.span*UINT32_C(2246822519)^n.bytes*UINT32_C(3266489917)^n.kind;}
static int same_node(Node a,Node b) {return a.prev==b.prev&&a.span==b.span&&a.bytes==b.bytes&&a.kind==b.kind;}
static uint32_t intern(Pool *pool,uint32_t previous,unsigned kind,uint32_t span,uint32_t bytes) {
    if(pool->error)return 0;
    Node node={previous,span,bytes,pool->nodes[previous].depth+span,kind};
    if(node.depth>ABC_MAX_FILE){pool->error=ABC_INVALID;return 0;}
    uint32_t slot=hash_node(node)&(pool->hash_size-1);
    while(pool->hash[slot]) {
        uint32_t index=pool->hash[slot];if(same_node(node,pool->nodes[index]))return index;
        slot=(slot+1)&(pool->hash_size-1);
    }
    if(pool->count==MAX_NODES){pool->error=ABC_INVALID;return 0;}
    if(pool->count==pool->capacity) {
        uint32_t capacity=pool->capacity*2;Node *nodes=realloc(pool->nodes,(size_t)capacity*sizeof *nodes);
        if(!nodes){pool->error=ABC_NOMEM;return 0;}pool->nodes=nodes;pool->capacity=capacity;
    }
    uint32_t index=pool->count++;pool->nodes[index]=node;pool->hash[slot]=index;
    if((uint64_t)pool->count*4>pool->hash_size*3) {
        uint32_t size=pool->hash_size*2;uint32_t *table=calloc(size,sizeof *table);
        if(!table){pool->error=ABC_NOMEM;return 0;}
        for(uint32_t i=1;i<pool->count;i++) {
            uint32_t at=hash_node(pool->nodes[i])&(size-1);while(table[at])at=(at+1)&(size-1);table[at]=i;
        }
        free(pool->hash);pool->hash=table;pool->hash_size=size;
    }
    return index;
}
static uint32_t push(Pool *pool,uint32_t stack,unsigned kind) {return intern(pool,stack,kind,1,0);}
static uint32_t cslot(const Pool *pool,uint32_t stack,uint32_t depth) {
    while(stack){Node node=pool->nodes[stack];if(depth<node.span)return node.kind==ABC_KIND_BLOCK?0:stack;depth-=node.span;stack=node.prev;}return 0;
}
static uint32_t cset(Pool *pool,uint32_t stack,uint32_t depth,unsigned kind) {
    uint32_t prefix[256],count=0,cursor=stack;
    while(depth>=pool->nodes[cursor].span){prefix[count++]=cursor;depth-=pool->nodes[cursor].span;cursor=pool->nodes[cursor].prev;}
    if(pool->nodes[cursor].kind==kind)return stack;
    uint32_t result=push(pool,pool->nodes[cursor].prev,kind);
    while(count){Node node=pool->nodes[prefix[--count]];result=intern(pool,result,node.kind,node.span,node.bytes);}
    return result;
}
static int frame_access(const Pool *pool,uint32_t stack,uint32_t offset,unsigned width) {
    uint32_t above=0;
    while(stack) {
        Node node=pool->nodes[stack];uint32_t extent=node.span*8;
        if(offset>above&&offset<=above+extent){uint32_t index=above+extent-offset;return node.kind==ABC_KIND_BLOCK&&index<node.bytes&&width<=node.bytes-index;}
        above+=extent;stack=node.prev;
    }
    return 0;
}
static int result_shape(const Pool *pool,uint32_t stack,const abc_function *function) {
    for(uint32_t index=function->results;index;index--){if(!stack||pool->nodes[stack].kind!=function->result_kinds[index-1])return 0;stack=pool->nodes[stack].prev;}return !stack;
}
static int matching_results(const abc_function *a,const abc_function *b) {
    return a->results==b->results&&a->hidden_bytes==b->hidden_bytes&&!memcmp(a->result_kinds,b->result_kinds,a->results);
}
static int load64(const abc_instruction_metadata *instruction) {
    unsigned action=instruction->memory_action;
    return instruction->memory_width==8&&(action==M_FLOAD||action==M_GLOAD||action==M_PLOAD||action==M_XLOAD);
}
static int64_t branch_displacement(const abc_decoded_instruction *instruction) {
    if(instruction->metadata->kind==K_JMP32)return abc_i32(instruction->operands);
    return abc_i16(instruction->operands+(instruction->metadata->kind==K_BRI?1:0));
}
abc_status abc_verify_module(abc_module *module,abc_error *error) {
    uint8_t *starts=calloc(module->code_size,1);
    Shape *shapes=calloc(module->code_size,sizeof *shapes);
    uint32_t *work=malloc(module->code_size*sizeof *work);
    Pool pool={.capacity=1024,.hash_size=2048,.count=1};
    pool.nodes=calloc(pool.capacity,sizeof *pool.nodes);pool.hash=calloc(pool.hash_size,sizeof *pool.hash);
    unsigned profile=module->foreign_profile?4:module->callable_profile?3:module->memory_profile?2:1;
    abc_status status=ABC_OK;uint32_t pc=0;
#define BAD(...) do{status=abc_fail(error,ABC_INVALID,pc,__VA_ARGS__);goto done;}while(0)
#define POOL_CHECK() do{if(pool.error){status=abc_fail(error,pool.error,pc,"verifier state allocation/complexity limit reached");goto done;}}while(0)
    if(!starts||!shapes||!work||!pool.nodes||!pool.hash){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"verifier allocation failed");goto done;}
    for(uint32_t index=0;index<module->function_count;index++) {
        abc_function *function=&module->functions[index];function->has_halt=0;
        for(pc=function->entry;pc<function->end;) {
            abc_decoded_instruction instruction;
            if(!abc_decode_instruction(module->code+pc,function->end-pc,&instruction))BAD("invalid or truncated instruction");
            if(instruction.metadata->minimum_profile>profile)BAD("instruction requires a higher capability profile");
            if(instruction.metadata->kind==K_HALT)function->has_halt=1;
            if(instruction.metadata->kind==K_ABORT&&!instruction.operands[0])BAD("ABORT reason must be nonzero");
            starts[pc]=1;pc+=instruction.length;
        }
    }
    if(module->load_kinds)for(pc=0;pc<module->code_size;pc++)if(module->load_kinds[pc]) {
        if(!starts[pc]||!load64(abc_instruction_info(module->code+pc)))BAD("load kind annotation requires a 64-bit memory load");
    }
    for(uint32_t index=0;index<module->site_count;index++) {
        pc=module->sites[index].entry;
        if(!starts[pc])BAD("indirect signature is not at an instruction start");
        unsigned kind=abc_instruction_info(module->code+pc)->kind;
        if(kind!=K_ICALL&&kind!=K_ITCALL)BAD("indirect signature is not on an indirect call");
    }
    for(uint32_t index=0;index<module->reloc_count;index++)if(module->functions[module->relocs[index].function].has_halt)BAD("code relocation names a HALT function");
    /* Edges, metadata and statically addressed image accesses are checked even in unreachable code. */
    for(uint32_t index=0;index<module->function_count;index++) {
        const abc_function *function=&module->functions[index];
        for(pc=function->entry;pc<function->end;) {
            abc_decoded_instruction instruction;abc_decode_instruction(module->code+pc,function->end-pc,&instruction);
            const abc_instruction_metadata *metadata=instruction.metadata;const uint8_t *operand=instruction.operands;
            uint32_t next=pc+instruction.length;unsigned kind=metadata->kind;
            if(kind==K_BRANCH||kind==K_BRI||kind==K_JMP32) {
                int64_t target=(int64_t)next+branch_displacement(&instruction);
                if(target<function->entry||target>=function->end||!starts[target])BAD("branch target is not an instruction in this function");
            }
            if(kind==K_SWITCH)for(unsigned entry=0;entry<abc_u16(operand);entry++) {
                int64_t target=(int64_t)next+abc_i32(operand+2+4*entry);
                if(target<function->entry||target>=function->end||!starts[target])BAD("SWITCH target is not an instruction in this function");
            }
            const abc_function *callee=NULL;
            if(kind==K_CALL||kind==K_TCALL) {
                int64_t target=(int64_t)next+abc_i32(operand);
                if(target>=0&&target<=UINT32_MAX)callee=abc_function_entry(module,(uint32_t)target);
                if(!callee)BAD("call target is not a function entry");
                if(callee->has_halt)BAD("a function containing HALT is host-entry-only");
                if(operand[kind==K_CALL?4:5]!=callee->arguments)BAD("call argument count disagrees with function table");
            } else if(kind==K_ICALL||kind==K_ITCALL) {
                callee=abc_find_site(module,pc);
                if(!callee)BAD("indirect call lacks its signature");
                if(operand[kind==K_ICALL?0:1]!=callee->arguments)BAD("indirect argument count disagrees with signature");
            }
            if((kind==K_TCALL||kind==K_ITCALL)&&!matching_results(function,callee))BAD("tail call result contract disagrees");
            if(kind==K_FCALL&&abc_u16(operand)>=module->extern_count)BAD("invalid foreign-call index");
            uint32_t offset=metadata->operand_layout==ABC_LAYOUT_U32?abc_u32(operand):metadata->operand_layout==ABC_LAYOUT_U16?abc_u16(operand):0;
            if(metadata->memory_action==M_GLOAD&&(uint64_t)offset+metadata->memory_width>module->image_size)BAD("image load outside image");
            if(metadata->memory_action==M_GSTORE&&(uint64_t)offset+metadata->memory_width>module->data_size)BAD("image store outside writable prefix");
            if(metadata->memory_action==M_GADDR&&offset>=module->image_size)BAD("image address outside image");
            pc=next;
        }
    }
    for(uint32_t index=0;index<module->function_count;index++) {
        abc_function *function=&module->functions[index];uint32_t context=0;size_t pending=0;
        for(uint32_t argument=function->arguments;argument;argument--)context=push(&pool,context,function->argument_kinds[argument-1]);
        POOL_CHECK();function->max_a=function->max_b=0;function->max_c=function->arguments;
        shapes[function->entry]=(Shape){0,0,context,1};work[pending++]=function->entry;
        while(pending) {
            pc=work[--pending];abc_decoded_instruction instruction;
            abc_decode_instruction(module->code+pc,function->end-pc,&instruction);
            const abc_instruction_metadata *metadata=instruction.metadata;const uint8_t *operand=instruction.operands;
            unsigned operation=metadata->operation,kind=metadata->kind;
            Shape shape=shapes[pc];uint32_t next=pc+instruction.length;
            uint32_t *selected=instruction.selected_stack==ABC_STACK_B?&shape.b:&shape.a;
            uint32_t *other=instruction.selected_stack==ABC_STACK_B?&shape.a:&shape.b;
            int terminal=0,branch=0;
#define DEPTH(STACK) (pool.nodes[(STACK)].depth)
#define REQUIRE(STACK,COUNT) do{if(DEPTH(STACK)<(uint32_t)(COUNT))BAD("stack underflow or access outside private frame");}while(0)
#define REQUIRE_KIND(STACK,KIND) do{REQUIRE(STACK,1);if(pool.nodes[(STACK)].kind!=(KIND))BAD("instruction operand kind mismatch");}while(0)
#define POP(STACK) ((STACK)=pool.nodes[(STACK)].prev)
            switch(metadata->transfer_kind) {
            case ABC_TRANSFER_PUSH:*selected=push(&pool,*selected,ABC_KIND_INT);break;
            case ABC_TRANSFER_DUP:REQUIRE(*selected,1);*selected=push(&pool,*selected,pool.nodes[*selected].kind);break;
            case ABC_TRANSFER_DROP:REQUIRE(*selected,1);POP(*selected);break;
            case ABC_TRANSFER_COPY:case ABC_TRANSFER_MOVE:
                REQUIRE(*selected,1);*other=push(&pool,*other,pool.nodes[*selected].kind);
                if(operation==ABC_OPERATION_MOVE)POP(*selected);break;
            case ABC_TRANSFER_CPUSH:case ABC_TRANSFER_CPUSHN: {
                unsigned count=operation==ABC_OPERATION_CPUSH?1:operand[0];REQUIRE(*selected,count);
                while(count--){shape.c=push(&pool,shape.c,pool.nodes[*selected].kind);POP(*selected);}break;
            }
            case ABC_TRANSFER_CPOP:REQUIRE(shape.c,1);if(pool.nodes[shape.c].kind==ABC_KIND_BLOCK)BAD("CPOP cannot split a frame block");POP(shape.c);break;
            case ABC_TRANSFER_CGET:case ABC_TRANSFER_CGETR: {
                unsigned depth=operation==ABC_OPERATION_CGET0?0:operation==ABC_OPERATION_CGET1?1:operand[0];
                unsigned count=operation==ABC_OPERATION_CGETR?operand[1]:1;
                for(unsigned cell=0;cell<count;cell++){uint32_t slot=cslot(&pool,shape.c,depth+cell);if(!slot)BAD("CGET outside a scalar frame cell");*selected=push(&pool,*selected,pool.nodes[slot].kind);}break;
            }
            case ABC_TRANSFER_CSET: {
                unsigned depth=operation==ABC_OPERATION_CSET0?0:operand[0];REQUIRE(*selected,1);
                if(!cslot(&pool,shape.c,depth))BAD("CSET outside a scalar frame cell");
                shape.c=cset(&pool,shape.c,depth,pool.nodes[*selected].kind);POP(*selected);break;
            }
            case ABC_TRANSFER_BINARY:case ABC_TRANSFER_POWER:case ABC_TRANSFER_BRANCH: {
                REQUIRE(*selected,1);REQUIRE(*other,1);
                int identity=operation==ABC_OPERATION_EQ||operation==ABC_OPERATION_NE||operation==ABC_OPERATION_BEQ||operation==ABC_OPERATION_BNE;
                if(!(identity&&pool.nodes[*selected].kind==ABC_KIND_ADDR&&pool.nodes[*other].kind==ABC_KIND_ADDR)) {
                    REQUIRE_KIND(*selected,ABC_KIND_INT);REQUIRE_KIND(*other,ABC_KIND_INT);
                }
                POP(*selected);POP(*other);
                if(metadata->transfer_kind==ABC_TRANSFER_BRANCH)branch=1;
                else *selected=push(&pool,*selected,ABC_KIND_INT);break;
            }
            case ABC_TRANSFER_UNARY:case ABC_TRANSFER_CHECK:case ABC_TRANSFER_IMMEDIATE:
                REQUIRE_KIND(*selected,ABC_KIND_INT);break;
            case ABC_TRANSFER_C_OPERAND: {
                REQUIRE_KIND(*selected,ABC_KIND_INT);uint32_t slot=cslot(&pool,shape.c,operand[0]);
                if(!slot||pool.nodes[slot].kind!=ABC_KIND_INT)BAD("C operand requires a scalar integer");break;
            }
            case ABC_TRANSFER_FLOAT_BINARY:case ABC_TRANSFER_FLOAT_BRANCH:
                REQUIRE_KIND(*selected,ABC_KIND_FLOAT);REQUIRE_KIND(*other,ABC_KIND_FLOAT);POP(*selected);POP(*other);
                if(metadata->transfer_kind==ABC_TRANSFER_FLOAT_BRANCH)branch=1;
                else *selected=push(&pool,*selected,(operation==ABC_OPERATION_FLT||operation==ABC_OPERATION_FLE||operation==ABC_OPERATION_FEQ)?ABC_KIND_INT:ABC_KIND_FLOAT);
                break;
            case ABC_TRANSFER_FLOAT_UNARY: {
                int from_integer=operation==ABC_OPERATION_I2FS||operation==ABC_OPERATION_I2FU;
                REQUIRE_KIND(*selected,from_integer?ABC_KIND_INT:ABC_KIND_FLOAT);POP(*selected);
                *selected=push(&pool,*selected,(operation==ABC_OPERATION_F2IS||operation==ABC_OPERATION_F2IU)?ABC_KIND_INT:ABC_KIND_FLOAT);break;
            }
            case ABC_TRANSFER_JUMP:branch=terminal=1;break;
            case ABC_TRANSFER_ZERO_BRANCH:case ABC_TRANSFER_IMMEDIATE_BRANCH:
                REQUIRE_KIND(*selected,ABC_KIND_INT);POP(*selected);branch=1;break;
            case ABC_TRANSFER_SWITCH:REQUIRE_KIND(*selected,ABC_KIND_INT);POP(*selected);branch=2;break;
            case ABC_TRANSFER_ALLOCATE: {
                unsigned bytes=abc_u16(operand);if(bytes)shape.c=intern(&pool,shape.c,ABC_KIND_BLOCK,(bytes+7)/8,bytes);break;
            }
            case ABC_TRANSFER_FREE: {
                unsigned bytes=abc_u16(operand);
                if(bytes){if(!shape.c||pool.nodes[shape.c].kind!=ABC_KIND_BLOCK||pool.nodes[shape.c].bytes!=bytes)BAD("CFREE must release the complete top frame block");POP(shape.c);}break;
            }
            case ABC_TRANSFER_MEMORY: {
                unsigned action=metadata->memory_action,width=metadata->memory_width;
                uint32_t offset=metadata->operand_layout==ABC_LAYOUT_U32?abc_u32(operand):metadata->operand_layout==ABC_LAYOUT_U16?abc_u16(operand):0;
                unsigned loaded=module->load_kinds&&module->load_kinds[pc]?module->load_kinds[pc]-1:ABC_KIND_INT;
                if(action==M_FLOAD||action==M_FSTORE||action==M_FADDR) {
                    if(!frame_access(&pool,shape.c,offset,width))BAD("frame access outside a live byte block");
                    if(action==M_FSTORE){REQUIRE(*selected,1);if(width<8)REQUIRE_KIND(*selected,ABC_KIND_INT);POP(*selected);}
                    else *selected=push(&pool,*selected,action==M_FADDR?ABC_KIND_ADDR:loaded);
                } else if(action==M_GLOAD||action==M_GADDR)*selected=push(&pool,*selected,action==M_GADDR?ABC_KIND_ADDR:loaded);
                else if(action==M_GSTORE){REQUIRE(*selected,1);if(width<8)REQUIRE_KIND(*selected,ABC_KIND_INT);POP(*selected);}
                else if(action==M_PLOAD){REQUIRE_KIND(*selected,ABC_KIND_ADDR);POP(*selected);*selected=push(&pool,*selected,loaded);}
                else if(action==M_PSTORE){REQUIRE_KIND(*selected,ABC_KIND_ADDR);REQUIRE(*other,1);if(width<8)REQUIRE_KIND(*other,ABC_KIND_INT);POP(*selected);POP(*other);}
                else if(action==M_XLOAD||action==M_INDEX){REQUIRE_KIND(*selected,ABC_KIND_ADDR);REQUIRE_KIND(*other,ABC_KIND_INT);POP(*other);if(action==M_XLOAD){POP(*selected);*selected=push(&pool,*selected,loaded);}}
                else {REQUIRE_KIND(*selected,ABC_KIND_ADDR);REQUIRE_KIND(*other,ABC_KIND_ADDR);POP(*selected);POP(*other);}
                break;
            }
            case ABC_TRANSFER_CALL:case ABC_TRANSFER_TCALL:case ABC_TRANSFER_CALLI:case ABC_TRANSFER_TCALLI: {
                int indirect=kind==K_ICALL||kind==K_ITCALL,tail=kind==K_TCALL||kind==K_ITCALL;
                const abc_function *callee=indirect?abc_find_site(module,pc):abc_function_entry(module,(uint32_t)((int64_t)next+abc_i32(operand)));
                if(indirect){REQUIRE_KIND(*other,ABC_KIND_ADDR);POP(*other);}
                REQUIRE(*selected,callee->arguments);
                if(tail&&(DEPTH(*selected)!=callee->arguments||*other||DEPTH(shape.c)!=operand[indirect?0:4]))BAD("tail call must replace complete frame and private operands");
                for(uint32_t argument=callee->arguments;argument;argument--){if(pool.nodes[*selected].kind!=callee->argument_kinds[argument-1])BAD("call argument kind disagrees with signature");POP(*selected);}
                if(tail)terminal=1;else for(uint32_t result=0;result<callee->results;result++)*selected=push(&pool,*selected,callee->result_kinds[result]);
                break;
            }
            case ABC_TRANSFER_FCALL: {
                const abc_extern *signature=&module->externs[abc_u16(operand)];REQUIRE(*selected,signature->arguments);
                for(unsigned argument=signature->arguments;argument;argument--){if(pool.nodes[*selected].kind!=signature->argument_kinds[argument-1])BAD("foreign argument kind disagrees with signature");POP(*selected);}
                if(signature->results)*selected=push(&pool,*selected,signature->result_kinds[0]);break;
            }
            case ABC_TRANSFER_RET:
                if(DEPTH(shape.c)!=operand[0]||*other||operand[1]!=function->results||!result_shape(&pool,*selected,function))BAD("RET disagrees with frame or result contract");terminal=1;break;
            case ABC_TRANSFER_HALT:
                if(shape.c||*other||!result_shape(&pool,*selected,function))BAD("HALT must leave only declared results and an empty frame");terminal=1;break;
            case ABC_TRANSFER_ABORT:terminal=1;break;
            default:BAD("instruction lacks a verification transfer");
            }
            POOL_CHECK();
            if(DEPTH(shape.a)>function->max_a)function->max_a=DEPTH(shape.a);
            if(DEPTH(shape.b)>function->max_b)function->max_b=DEPTH(shape.b);
            if(DEPTH(shape.c)>function->max_c)function->max_c=DEPTH(shape.c);
            unsigned edge_count=branch==2?(unsigned)abc_u16(operand)+1:(branch?1u:0u)+(!terminal?1u:0u);
            for(unsigned edge_index=0;edge_index<edge_count;edge_index++) {
                uint32_t edge=next;
                if(branch==2){if(edge_index<abc_u16(operand))edge=(uint32_t)((int64_t)next+abc_i32(operand+2+4*edge_index));}
                else if(branch&&edge_index==0)edge=(uint32_t)((int64_t)next+branch_displacement(&instruction));
                if(edge>=function->end)BAD("execution falls out of function");
                Shape *previous=&shapes[edge];
                if(previous->seen){if(previous->a!=shape.a||previous->b!=shape.b||previous->c!=shape.c)BAD("incompatible stack kinds or C layouts at join");}
                else {*previous=shape;previous->seen=1;work[pending++]=edge;}
            }
#undef DEPTH
#undef REQUIRE
#undef REQUIRE_KIND
#undef POP
        }
    }
done:
    free(starts);free(shapes);free(work);free(pool.nodes);free(pool.hash);return status;
#undef BAD
#undef POOL_CHECK
}
