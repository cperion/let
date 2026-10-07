#include "abc_tool.h"
#include "residual_builder.h"
#include "internal.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *items;
    size_t count;
    size_t capacity;
} text_buffer;

typedef struct {
    const char *name;
    uint32_t arguments;
    uint32_t results;
    abc_residual_id function;
} c_export;

typedef struct {
    const abc_residual_program *program;
    const c_export *exports;
    size_t export_count;
    uint8_t *may_fail;
    uint8_t **u32_arguments;
    uint8_t *u32_results;
    size_t current_function;
    text_buffer output;
    abc_error *error;
} c_emitter;

static int reserve_text(text_buffer *buffer, size_t extra) {
    size_t needed;
    size_t capacity;
    char *items;

    if (extra > SIZE_MAX - buffer->count - 1) return 0;
    needed = buffer->count + extra + 1;
    if (needed <= buffer->capacity) return 1;
    capacity = buffer->capacity ? buffer->capacity * 2 : 4096;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2) {
            capacity = needed;
            break;
        }
        capacity *= 2;
    }
    items = realloc(buffer->items, capacity);
    if (!items) return 0;
    buffer->items = items;
    buffer->capacity = capacity;
    return 1;
}

static int append_text(text_buffer *buffer, const char *text, size_t size) {
    if (!reserve_text(buffer, size)) return 0;
    memcpy(buffer->items + buffer->count, text, size);
    buffer->count += size;
    buffer->items[buffer->count] = '\0';
    return 1;
}

static int append_format(text_buffer *buffer, const char *format, ...) {
    va_list arguments;
    va_list copy;
    int length;

    va_start(arguments, format);
    va_copy(copy, arguments);
    length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0 || !reserve_text(buffer, (size_t)length)) {
        va_end(arguments);
        return 0;
    }
    vsnprintf(buffer->items + buffer->count,
              buffer->capacity - buffer->count, format, arguments);
    va_end(arguments);
    buffer->count += (size_t)length;
    return 1;
}

static int emit_failure(c_emitter *emitter, uint64_t origin,
                        const char *format, ...) {
    va_list arguments;

    if (emitter->error && emitter->error->status == ABC_OK) {
        emitter->error->status = ABC_INVALID;
        emitter->error->offset =
            origin <= UINT32_MAX ? (uint32_t)origin : UINT32_MAX;
        va_start(arguments, format);
        vsnprintf(emitter->error->message,
                  sizeof(emitter->error->message), format, arguments);
        va_end(arguments);
    }
    return 0;
}

static int emit_out_of_memory(c_emitter *emitter) {
    return emit_failure(emitter, UINT32_MAX,
                        "portable C emitter allocation failed");
}

static int function_index(const abc_residual_program *program,
                          uint64_t id, size_t *index) {
    size_t i;

    for (i = 0; i < program->functions.count; i++)
        if (program->functions.items[i].id.value == id) {
            *index = i;
            return 1;
        }
    return 0;
}

static int scalar_function(const c_emitter *emitter,size_t index) {
    return index<emitter->program->functions.count&&!emitter->may_fail[index]&&
           emitter->program->functions.items[index].result_types.count==1;
}

static int failure_binary(abc_asdl_residual_binary_op operation) {
    return operation==ABC_ASDL_RESIDUAL_BINARY_OP_DIV_UNSIGNED||
           operation==ABC_ASDL_RESIDUAL_BINARY_OP_REM_UNSIGNED||
           operation==ABC_ASDL_RESIDUAL_BINARY_OP_DIV_SIGNED||
           operation==ABC_ASDL_RESIDUAL_BINARY_OP_REM_SIGNED||
           operation==ABC_ASDL_RESIDUAL_BINARY_OP_POW_SIGNED;
}

static int analyze_failures(c_emitter *emitter) {
    size_t count=emitter->program->functions.count;int changed=1;
    emitter->may_fail=calloc(count?count:1,1);if(!emitter->may_fail)return 0;
    while(changed){changed=0;for(size_t fi=0;fi<count;fi++){
        const abc_residual_function *function=&emitter->program->functions.items[fi];
        if(emitter->may_fail[fi])continue;
        for(size_t bi=0;bi<function->blocks.count&&!emitter->may_fail[fi];bi++){
            const abc_residual_block *block=&function->blocks.items[bi];
            for(size_t ni=0;ni<block->nodes.count;ni++){const abc_residual_operation *op=&block->nodes.items[ni].operation;
                if(op->tag==ABC_ASDL_RESIDUAL_OPERATION_CHECK||
                   (op->tag==ABC_ASDL_RESIDUAL_OPERATION_BINARY&&failure_binary(op->value.binary.operation)))
                    emitter->may_fail[fi]=1;
                else if(op->tag==ABC_ASDL_RESIDUAL_OPERATION_CALL){size_t target;
                    if(!function_index(emitter->program,op->value.call.target,&target)||emitter->may_fail[target])emitter->may_fail[fi]=1;
                }
            }
            const abc_residual_terminator *term=&block->terminator;
            if(term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_ABORT||term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_UNREACHABLE)emitter->may_fail[fi]=1;
            else if(term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL){size_t target;
                if(!function_index(emitter->program,term->value.tail_call.target,&target)||emitter->may_fail[target])emitter->may_fail[fi]=1;
            }
        }
        if(emitter->may_fail[fi])changed=1;
    }}return 1;
}

static const abc_residual_value *find_value(const c_emitter *emitter,abc_residual_id id){
    for(size_t i=0;i<emitter->program->values.count;i++)
        if(emitter->program->values.items[i].id.value==id.value)return &emitter->program->values.items[i];
    return NULL;
}

static int value_u32(const c_emitter *,size_t,abc_residual_id,size_t);
static int edge_value_u32(const c_emitter *emitter,size_t fi,const abc_residual_edge *edge,
                          uint64_t block,size_t argument,size_t depth){
    return edge->target.value!=block||argument>=edge->arguments.count||
           value_u32(emitter,fi,edge->arguments.items[argument],depth+1);
}

static int block_argument_u32(const c_emitter *emitter,size_t fi,uint64_t block,size_t argument,size_t depth){
    const abc_residual_function *function=&emitter->program->functions.items[fi];int found=0;
    for(size_t bi=0;bi<function->blocks.count;bi++){const abc_residual_terminator *term=&function->blocks.items[bi].terminator;
        switch(term->tag){
        case ABC_ASDL_RESIDUAL_TERMINATOR_JUMP:
            if(term->value.jump.edge.target.value==block)found=1;
            if(!edge_value_u32(emitter,fi,&term->value.jump.edge,block,argument,depth))return 0;
            break;
        case ABC_ASDL_RESIDUAL_TERMINATOR_BRANCH:
            if(term->value.branch.yes.target.value==block||term->value.branch.no.target.value==block)found=1;
            if(!edge_value_u32(emitter,fi,&term->value.branch.yes,block,argument,depth)||
               !edge_value_u32(emitter,fi,&term->value.branch.no,block,argument,depth))return 0;
            break;
        case ABC_ASDL_RESIDUAL_TERMINATOR_SWITCH:
            for(size_t ai=0;ai<term->value.switch_value.arms.count;ai++){
                const abc_residual_edge *edge=&term->value.switch_value.arms.items[ai].edge;
                if(edge->target.value==block)found=1;
                if(!edge_value_u32(emitter,fi,edge,block,argument,depth))return 0;
            }
            if(term->value.switch_value.fallback.target.value==block)found=1;
            if(!edge_value_u32(emitter,fi,&term->value.switch_value.fallback,block,argument,depth))return 0;
            break;
        default:break;
        }
    }
    return found;
}

static int value_u32(const c_emitter *emitter,size_t fi,abc_residual_id id,size_t depth){
    const abc_residual_value *value=find_value(emitter,id);const abc_residual_function *function=&emitter->program->functions.items[fi];
    if(!value)return 0;if(depth>emitter->program->values.count)return 1;
    if(value->type==ABC_ASDL_RESIDUAL_TYPE_U32)return 1;
    if(value->definition.tag==ABC_ASDL_RESIDUAL_DEFINITION_CONSTANT)
        return value->definition.value.constant.high==0&&value->definition.value.constant.low<=UINT32_MAX;
    if(value->definition.tag==ABC_ASDL_RESIDUAL_DEFINITION_FUNCTION_ARGUMENT){size_t index=value->definition.value.function_argument.index;
        return index<function->arguments.count&&emitter->u32_arguments[fi][index];
    }
    if(value->definition.tag==ABC_ASDL_RESIDUAL_DEFINITION_BLOCK_ARGUMENT)
        return block_argument_u32(emitter,fi,value->definition.value.block_argument.block.value,
                                  value->definition.value.block_argument.index,depth);
    if(value->definition.tag==ABC_ASDL_RESIDUAL_DEFINITION_INSTRUCTION_RESULT){
        for(size_t bi=0;bi<function->blocks.count;bi++)for(size_t ni=0;ni<function->blocks.items[bi].nodes.count;ni++){
            const abc_residual_node *node=&function->blocks.items[bi].nodes.items[ni];
            for(size_t ri=0;ri<node->results.count;ri++)if(node->results.items[ri].value==id.value&&node->operation.tag==ABC_ASDL_RESIDUAL_OPERATION_CALL){size_t target;
                return function_index(emitter->program,node->operation.value.call.target,&target)&&emitter->u32_results[target];
            }
        }
    }
    return 0;
}

static int function_exported(const c_emitter *emitter,size_t fi){
    uint64_t id=emitter->program->functions.items[fi].id.value;
    for(size_t i=0;i<emitter->export_count;i++)if(emitter->exports[i].function.value==id)return 1;return 0;
}

static void constrain_call_arguments(c_emitter *emitter,size_t caller,uint64_t target_id,
                                     size_t argument_count,const abc_residual_id *arguments,int *changed){
    size_t target;if(!function_index(emitter->program,target_id,&target))return;
    for(size_t i=0;i<argument_count&&i<emitter->program->functions.items[target].arguments.count;i++)
        if(emitter->u32_arguments[target][i]&&!value_u32(emitter,caller,arguments[i],0)){emitter->u32_arguments[target][i]=0;*changed=1;}
}

static int analyze_widths(c_emitter *emitter){
    size_t count=emitter->program->functions.count;int changed=1;
    emitter->u32_arguments=calloc(count?count:1,sizeof *emitter->u32_arguments);
    emitter->u32_results=calloc(count?count:1,1);if(!emitter->u32_arguments||!emitter->u32_results)return 0;
    for(size_t fi=0;fi<count;fi++){const abc_residual_function *function=&emitter->program->functions.items[fi];
        emitter->u32_arguments[fi]=calloc(function->arguments.count?function->arguments.count:1,1);if(!emitter->u32_arguments[fi])return 0;
        memset(emitter->u32_arguments[fi],function_exported(emitter,fi)?0:1,function->arguments.count);
        emitter->u32_results[fi]=(uint8_t)(function->result_types.count==1);
    }
    while(changed){changed=0;for(size_t fi=0;fi<count;fi++){const abc_residual_function *function=&emitter->program->functions.items[fi];
        for(size_t bi=0;bi<function->blocks.count;bi++){const abc_residual_block *block=&function->blocks.items[bi];
            for(size_t ni=0;ni<block->nodes.count;ni++)if(block->nodes.items[ni].operation.tag==ABC_ASDL_RESIDUAL_OPERATION_CALL)
                constrain_call_arguments(emitter,fi,block->nodes.items[ni].operation.value.call.target,
                                         block->nodes.items[ni].operation.value.call.arguments.count,
                                         block->nodes.items[ni].operation.value.call.arguments.items,&changed);
            const abc_residual_terminator *term=&block->terminator;
            if(term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL)
                constrain_call_arguments(emitter,fi,term->value.tail_call.target,term->value.tail_call.arguments.count,
                                         term->value.tail_call.arguments.items,&changed);
            if(emitter->u32_results[fi]&&term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_RETURN)
                for(size_t ri=0;ri<term->value.return_value.values.count;ri++)if(!value_u32(emitter,fi,term->value.return_value.values.items[ri],0)){emitter->u32_results[fi]=0;changed=1;}
        }
    }}return 1;
}

static int integer_type(abc_residual_type type) {
    return type == ABC_ASDL_RESIDUAL_TYPE_CELL ||
           type == ABC_ASDL_RESIDUAL_TYPE_U32 ||
           type == ABC_ASDL_RESIDUAL_TYPE_I32 ||
           type == ABC_ASDL_RESIDUAL_TYPE_U64 ||
           type == ABC_ASDL_RESIDUAL_TYPE_I64;
}

static const char *c_value_type(abc_residual_type type) {
    switch(type){
    case ABC_ASDL_RESIDUAL_TYPE_U32:return "uint32_t";
    case ABC_ASDL_RESIDUAL_TYPE_I32:return "int32_t";
    case ABC_ASDL_RESIDUAL_TYPE_I64:return "int64_t";
    default:return "uint64_t";
    }
}

static int validate_subset(c_emitter *emitter) {
    const abc_residual_program *program = emitter->program;
    size_t i;
    size_t fi;
    size_t bi;
    size_t ni;

    for (i = 0; i < program->values.count; i++)
        if (!integer_type(program->values.items[i].type))
            return emit_failure(
                emitter, program->values.items[i].origin.offset,
                "portable C does not support residual type %s",
                abc_asdl_residual_type_tag_name(
                    program->values.items[i].type));

    for (fi = 0; fi < program->functions.count; fi++) {
        const abc_residual_function *function =
            &program->functions.items[fi];

        for (i = 0; i < function->argument_types.count; i++)
            if (!integer_type(function->argument_types.items[i]))
                return emit_failure(
                    emitter, 0,
                    "portable C supports only integer function arguments");
        for (i = 0; i < function->result_types.count; i++)
            if (!integer_type(function->result_types.items[i]))
                return emit_failure(
                    emitter, 0,
                    "portable C supports only integer function results");

        for (bi = 0; bi < function->blocks.count; bi++) {
            const abc_residual_block *block =
                &function->blocks.items[bi];

            for (ni = 0; ni < block->nodes.count; ni++) {
                const abc_residual_node *node =
                    &block->nodes.items[ni];
                const abc_residual_operation *operation =
                    &node->operation;

                switch (operation->tag) {
                case ABC_ASDL_RESIDUAL_OPERATION_UNARY:
                    if (operation->value.unary.operation >
                        ABC_ASDL_RESIDUAL_UNARY_OP_SIGN_EXTEND32)
                        return emit_failure(
                            emitter, node->origin.offset,
                            "portable C does not support float unary operations");
                    break;
                case ABC_ASDL_RESIDUAL_OPERATION_BINARY:
                    if (operation->value.binary.operation >
                        ABC_ASDL_RESIDUAL_BINARY_OP_LESS_EQUAL_UNSIGNED)
                        return emit_failure(
                            emitter, node->origin.offset,
                            "portable C does not support float binary operations");
                    break;
                case ABC_ASDL_RESIDUAL_OPERATION_CHECK:
                    break;
                case ABC_ASDL_RESIDUAL_OPERATION_CALL:
                    if (operation->value.call.kind !=
                        ABC_ASDL_RESIDUAL_CALL_KIND_DIRECT)
                        return emit_failure(
                            emitter, node->origin.offset,
                            "portable C supports only direct residual calls");
                    break;
                default:
                    return emit_failure(
                        emitter, node->origin.offset,
                        "portable C does not support residual operation %s",
                        abc_asdl_residual_operation_tag_name(
                            operation->tag));
                }
            }

            switch (block->terminator.tag) {
            case ABC_ASDL_RESIDUAL_TERMINATOR_JUMP:
            case ABC_ASDL_RESIDUAL_TERMINATOR_BRANCH:
            case ABC_ASDL_RESIDUAL_TERMINATOR_SWITCH:
            case ABC_ASDL_RESIDUAL_TERMINATOR_RETURN:
            case ABC_ASDL_RESIDUAL_TERMINATOR_ABORT:
            case ABC_ASDL_RESIDUAL_TERMINATOR_UNREACHABLE:
                break;
            case ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL:
                if (block->terminator.value.tail_call.kind !=
                    ABC_ASDL_RESIDUAL_CALL_KIND_DIRECT)
                    return emit_failure(
                        emitter, block->terminator.origin.offset,
                        "portable C supports only direct tail calls");
                break;
            default:
                return emit_failure(
                    emitter, block->terminator.origin.offset,
                    "portable C encountered an invalid terminator");
            }
        }
    }
    return 1;
}

static int emit_runtime(c_emitter *emitter) {
    static const char runtime[] =
        "/* generated from validated ABC residual IR */\n"
        "#include <stddef.h>\n"
        "#include <stdint.h>\n"
        "#include <limits.h>\n"
        "#include <string.h>\n"
        "\n"
        "#ifndef ABC_AOT_ABI_DEFINED\n"
        "#define ABC_AOT_ABI_DEFINED\n"
        "typedef struct { uint32_t status; uint32_t offset; uint8_t reason; } abc_aot_error;\n"
        "typedef int (*abc_aot_entry)(const uint64_t *, size_t, uint64_t *, size_t, abc_aot_error *);\n"
        "typedef struct { const char *name; uint32_t arguments; uint32_t results; abc_aot_entry entry; } abc_aot_export;\n"
        "#endif\n"
        "\n"
        "enum { ABC_AOT_OK=0, ABC_AOT_INVALID=1, ABC_AOT_ARGUMENTS=5, ABC_AOT_ABORT=6, ABC_AOT_RESULTS=8 };\n"
        "static inline int64_t abc_aot_signed(uint64_t x) {\n"
        "  return x<=INT64_MAX ? (int64_t)x : -1-(int64_t)(UINT64_MAX-x);\n"
        "}\n"
        "static inline uint64_t abc_aot_sar(uint64_t x,uint64_t n) {\n"
        "  if(n>=64)return x>>63?UINT64_MAX:0;\n"
        "  if(!n)return x;\n"
        "  return x>>n | (x>>63 ? UINT64_MAX<<(64-n) : 0);\n"
        "}\n"
        "static inline uint64_t abc_aot_pow(uint64_t x,uint64_t n) {\n"
        "  uint64_t r=1; while(n){if(n&1)r*=x;x*=x;n>>=1;} return r;\n"
        "}\n"
        "static inline uint64_t abc_aot_signed_div(uint64_t x,uint64_t y) {\n"
        "  return y==UINT64_MAX ? 0-x : (uint64_t)(abc_aot_signed(x)/abc_aot_signed(y));\n"
        "}\n"
        "static inline uint64_t abc_aot_signed_rem(uint64_t x,uint64_t y) {\n"
        "  return y==UINT64_MAX ? 0 : (uint64_t)(abc_aot_signed(x)%abc_aot_signed(y));\n"
        "}\n"
        "static inline int abc_aot_fail(abc_aot_error *e,uint8_t reason,uint32_t offset) {\n"
        "  if(e){e->status=ABC_AOT_ABORT;e->offset=offset;e->reason=reason;} return ABC_AOT_ABORT;\n"
        "}\n"
        "static inline void abc_aot_clear(abc_aot_error *e) {\n"
        "  if(e){e->status=ABC_AOT_OK;e->offset=UINT32_MAX;e->reason=0;}\n"
        "}\n"
        "\n";

    return append_text(&emitter->output, runtime, sizeof(runtime) - 1) ||
           emit_out_of_memory(emitter);
}

static int emit_value_name(c_emitter *emitter, abc_residual_id id) {
    return append_format(&emitter->output, "v_%llu",
                         (unsigned long long)id.value) ||
           emit_out_of_memory(emitter);
}

static int emit_edge(c_emitter *emitter,
                     const abc_residual_function *function,
                     const abc_residual_edge *edge,
                     uint64_t origin) {
    const abc_residual_block *target = NULL;
    size_t bi;
    size_t i;

    for (bi = 0; bi < function->blocks.count; bi++)
        if (function->blocks.items[bi].id.value ==
            edge->target.value) {
            target = &function->blocks.items[bi];
            break;
        }
    if (!target || target->arguments.count != edge->arguments.count)
        return emit_failure(emitter, origin,
                            "portable C edge target is invalid");

    if (!append_text(&emitter->output, "  {\n", 4))
        return emit_out_of_memory(emitter);
    for (i = 0; i < edge->arguments.count; i++) {
        if (!append_format(&emitter->output,
                           "    uint64_t edge_%zu=", i) ||
            !emit_value_name(emitter, edge->arguments.items[i]) ||
            !append_text(&emitter->output, ";\n", 2))
            return emit_out_of_memory(emitter);
    }
    for (i = 0; i < edge->arguments.count; i++) {
        if (!append_text(&emitter->output, "    ", 4) ||
            !emit_value_name(emitter, target->arguments.items[i]) ||
            !append_format(&emitter->output,
                           "=edge_%zu;\n", i))
            return emit_out_of_memory(emitter);
    }
    if (!append_format(&emitter->output,
                       "    goto block_%llu;\n  }\n",
                       (unsigned long long)edge->target.value))
        return emit_out_of_memory(emitter);
    return 1;
}

static int emit_binary_expression(
    c_emitter *emitter,
    abc_asdl_residual_binary_op operation,
    abc_residual_id left, abc_residual_id right,
    abc_residual_id result, uint64_t origin) {
    const char *infix = NULL;

    switch (operation) {
    case ABC_ASDL_RESIDUAL_BINARY_OP_ADD: infix = "+"; break;
    case ABC_ASDL_RESIDUAL_BINARY_OP_SUB: infix = "-"; break;
    case ABC_ASDL_RESIDUAL_BINARY_OP_MUL: infix = "*"; break;
    case ABC_ASDL_RESIDUAL_BINARY_OP_BIT_AND: infix = "&"; break;
    case ABC_ASDL_RESIDUAL_BINARY_OP_BIT_OR: infix = "|"; break;
    case ABC_ASDL_RESIDUAL_BINARY_OP_BIT_XOR: infix = "^"; break;
    case ABC_ASDL_RESIDUAL_BINARY_OP_EQUAL: infix = "=="; break;
    case ABC_ASDL_RESIDUAL_BINARY_OP_NOT_EQUAL: infix = "!="; break;
    case ABC_ASDL_RESIDUAL_BINARY_OP_LESS_UNSIGNED: infix = "<"; break;
    case ABC_ASDL_RESIDUAL_BINARY_OP_LESS_EQUAL_UNSIGNED: infix = "<="; break;
    default: break;
    }

    if (!append_text(&emitter->output, "  ", 2) ||
        !emit_value_name(emitter, result) ||
        !append_text(&emitter->output, "=", 1))
        return emit_out_of_memory(emitter);

    if (infix) {
        if (!emit_value_name(emitter, left) ||
            !append_format(&emitter->output, "%s", infix) ||
            !emit_value_name(emitter, right) ||
            !append_text(&emitter->output, ";\n", 2))
            return emit_out_of_memory(emitter);
        return 1;
    }

    switch (operation) {
    case ABC_ASDL_RESIDUAL_BINARY_OP_DIV_UNSIGNED:
    case ABC_ASDL_RESIDUAL_BINARY_OP_REM_UNSIGNED:
    case ABC_ASDL_RESIDUAL_BINARY_OP_DIV_SIGNED:
    case ABC_ASDL_RESIDUAL_BINARY_OP_REM_SIGNED:
        if (!append_text(&emitter->output, "0;\n  if(!", 9) ||
            !emit_value_name(emitter, right) ||
            !append_format(&emitter->output,
                           ")return abc_aot_fail(error,1,%llu);\n  ",
                           (unsigned long long)origin) ||
            !emit_value_name(emitter, result) ||
            !append_text(&emitter->output, "=", 1))
            return emit_out_of_memory(emitter);
        if (operation == ABC_ASDL_RESIDUAL_BINARY_OP_DIV_UNSIGNED ||
            operation == ABC_ASDL_RESIDUAL_BINARY_OP_REM_UNSIGNED) {
            if (!emit_value_name(emitter, left) ||
                !append_text(
                    &emitter->output,
                    operation == ABC_ASDL_RESIDUAL_BINARY_OP_DIV_UNSIGNED
                        ? "/" : "%", 1) ||
                !emit_value_name(emitter, right))
                return emit_out_of_memory(emitter);
        } else {
            if (!append_text(&emitter->output,
                             operation ==
                                     ABC_ASDL_RESIDUAL_BINARY_OP_DIV_SIGNED
                                 ? "abc_aot_signed_div("
                                 : "abc_aot_signed_rem(",
                             operation ==
                                     ABC_ASDL_RESIDUAL_BINARY_OP_DIV_SIGNED
                                 ? 19 : 19) ||
                !emit_value_name(emitter, left) ||
                !append_text(&emitter->output, ",", 1) ||
                !emit_value_name(emitter, right) ||
                !append_text(&emitter->output, ")", 1))
                return emit_out_of_memory(emitter);
        }
        return append_text(&emitter->output, ";\n", 2) ||
               emit_out_of_memory(emitter);

    case ABC_ASDL_RESIDUAL_BINARY_OP_SHIFT_LEFT:
    case ABC_ASDL_RESIDUAL_BINARY_OP_SHIFT_RIGHT:
        if (!append_text(&emitter->output, "(", 1) ||
            !emit_value_name(emitter, right) ||
            !append_text(&emitter->output, ">=64?0:", 7) ||
            !emit_value_name(emitter, left) ||
            !append_text(
                &emitter->output,
                operation == ABC_ASDL_RESIDUAL_BINARY_OP_SHIFT_LEFT
                    ? "<<" : ">>", 2) ||
            !emit_value_name(emitter, right) ||
            !append_text(&emitter->output, ");\n", 3))
            return emit_out_of_memory(emitter);
        return 1;

    case ABC_ASDL_RESIDUAL_BINARY_OP_SHIFT_ARITHMETIC:
        if (!append_text(&emitter->output, "abc_aot_sar(", 12) ||
            !emit_value_name(emitter, left) ||
            !append_text(&emitter->output, ",", 1) ||
            !emit_value_name(emitter, right) ||
            !append_text(&emitter->output, ");\n", 3))
            return emit_out_of_memory(emitter);
        return 1;

    case ABC_ASDL_RESIDUAL_BINARY_OP_POW_UNSIGNED:
    case ABC_ASDL_RESIDUAL_BINARY_OP_POW_SIGNED:
        if (operation == ABC_ASDL_RESIDUAL_BINARY_OP_POW_SIGNED) {
            if (!append_text(&emitter->output, "0;\n  if(", 8) ||
                !emit_value_name(emitter, right) ||
                !append_format(
                    &emitter->output,
                    ">>63)return abc_aot_fail(error,4,%llu);\n  ",
                    (unsigned long long)origin) ||
                !emit_value_name(emitter, result) ||
                !append_text(&emitter->output, "=", 1))
                return emit_out_of_memory(emitter);
        }
        if (!append_text(&emitter->output, "abc_aot_pow(", 12) ||
            !emit_value_name(emitter, left) ||
            !append_text(&emitter->output, ",", 1) ||
            !emit_value_name(emitter, right) ||
            !append_text(&emitter->output, ");\n", 3))
            return emit_out_of_memory(emitter);
        return 1;

    case ABC_ASDL_RESIDUAL_BINARY_OP_LESS_SIGNED:
    case ABC_ASDL_RESIDUAL_BINARY_OP_LESS_EQUAL_SIGNED:
        if (!append_text(&emitter->output, "abc_aot_signed(", 15) ||
            !emit_value_name(emitter, left) ||
            !append_text(&emitter->output,
                         operation ==
                                 ABC_ASDL_RESIDUAL_BINARY_OP_LESS_SIGNED
                             ? ")<abc_aot_signed("
                             : ")<=abc_aot_signed(",
                         operation ==
                                 ABC_ASDL_RESIDUAL_BINARY_OP_LESS_SIGNED
                             ? 18 : 19) ||
            !emit_value_name(emitter, right) ||
            !append_text(&emitter->output, ");\n", 3))
            return emit_out_of_memory(emitter);
        return 1;

    default:
        return emit_failure(emitter, origin,
                            "portable C cannot emit binary operation");
    }
}

static int emit_node(c_emitter *emitter,
                     const abc_residual_node *node) {
    const abc_residual_operation *operation = &node->operation;
    abc_residual_id result =
        node->results.count ? node->results.items[0]
                            : (abc_residual_id){0};
    uint64_t origin = node->origin.offset;
    size_t target;
    size_t i;

    switch (operation->tag) {
    case ABC_ASDL_RESIDUAL_OPERATION_UNARY:
        if (!append_text(&emitter->output, "  ", 2) ||
            !emit_value_name(emitter, result) ||
            !append_text(&emitter->output, "=", 1))
            return emit_out_of_memory(emitter);
        switch (operation->value.unary.operation) {
        case ABC_ASDL_RESIDUAL_UNARY_OP_NEG:
            if (!append_text(&emitter->output, "0-", 2)) return 0;
            break;
        case ABC_ASDL_RESIDUAL_UNARY_OP_BIT_NOT:
            if (!append_text(&emitter->output, "~", 1)) return 0;
            break;
        case ABC_ASDL_RESIDUAL_UNARY_OP_LOGICAL_NOT:
            if (!append_text(&emitter->output, "(", 1)) return 0;
            if (!emit_value_name(
                    emitter, operation->value.unary.input) ||
                !append_text(&emitter->output, "^UINT64_C(1));\n", 16))
                return emit_out_of_memory(emitter);
            return 1;
        case ABC_ASDL_RESIDUAL_UNARY_OP_ZERO_EXTEND32:
            if (!append_text(&emitter->output, "(uint32_t)", 10)) return 0;
            break;
        case ABC_ASDL_RESIDUAL_UNARY_OP_SIGN_EXTEND32:
            if (!append_text(
                    &emitter->output,
                    "(uint64_t)(int64_t)(int32_t)", 28))
                return 0;
            break;
        default:
            return emit_failure(emitter, origin,
                                "portable C cannot emit unary operation");
        }
        if (!emit_value_name(
                emitter, operation->value.unary.input) ||
            !append_text(&emitter->output, ";\n", 2))
            return emit_out_of_memory(emitter);
        return 1;

    case ABC_ASDL_RESIDUAL_OPERATION_BINARY:
        return emit_binary_expression(
            emitter, operation->value.binary.operation,
            operation->value.binary.left,
            operation->value.binary.right, result, origin);

    case ABC_ASDL_RESIDUAL_OPERATION_CHECK:
        if (!append_text(&emitter->output, "  if(", 5))
            return emit_out_of_memory(emitter);
        switch (operation->value.check.operation) {
        case ABC_ASDL_RESIDUAL_CHECK_OP_UNSIGNED8:
            if (!emit_value_name(
                    emitter, operation->value.check.input) ||
                !append_text(&emitter->output, ">UINT8_MAX", 10))
                return emit_out_of_memory(emitter);
            break;
        case ABC_ASDL_RESIDUAL_CHECK_OP_UNSIGNED16:
            if (!emit_value_name(
                    emitter, operation->value.check.input) ||
                !append_text(&emitter->output, ">UINT16_MAX", 11))
                return emit_out_of_memory(emitter);
            break;
        case ABC_ASDL_RESIDUAL_CHECK_OP_UNSIGNED32:
            if (!emit_value_name(
                    emitter, operation->value.check.input) ||
                !append_text(&emitter->output, ">UINT32_MAX", 11))
                return emit_out_of_memory(emitter);
            break;
        case ABC_ASDL_RESIDUAL_CHECK_OP_SIGNED32:
            if (!append_text(&emitter->output, "abc_aot_signed(", 15) ||
                !emit_value_name(
                    emitter, operation->value.check.input) ||
                !append_text(
                    &emitter->output,
                    ")<INT32_MIN||abc_aot_signed(", 29) ||
                !emit_value_name(
                    emitter, operation->value.check.input) ||
                !append_text(&emitter->output, ")>INT32_MAX", 11))
                return emit_out_of_memory(emitter);
            break;
        case ABC_ASDL_RESIDUAL_CHECK_OP_NONNEGATIVE:
            if (!emit_value_name(
                    emitter, operation->value.check.input) ||
                !append_text(&emitter->output, ">>63", 4))
                return emit_out_of_memory(emitter);
            break;
        default:
            return emit_failure(emitter, origin,
                                "portable C cannot emit check");
        }
        return append_format(
                   &emitter->output,
                   ")return abc_aot_fail(error,%llu,%llu);\n",
                   (unsigned long long)operation->value.check.reason,
                   (unsigned long long)origin) ||
               emit_out_of_memory(emitter);

    case ABC_ASDL_RESIDUAL_OPERATION_CALL:
        if (!function_index(
                emitter->program,
                operation->value.call.target, &target))
            return emit_failure(emitter, origin,
                                "portable C direct target is invalid");
        if(scalar_function(emitter,target)){
            if(node->results.count!=1||!append_text(&emitter->output,"  ",2)||
               !emit_value_name(emitter,node->results.items[0])||
               !append_format(&emitter->output,"=abc_aot_function_%zu(",target))return emit_out_of_memory(emitter);
            for(i=0;i<operation->value.call.arguments.count;i++){
                if(i&&!append_text(&emitter->output,",",1))return emit_out_of_memory(emitter);
                if(!emit_value_name(emitter,operation->value.call.arguments.items[i]))return 0;
            }
            return append_text(&emitter->output,");\n",3)||emit_out_of_memory(emitter);
        }
        if (!append_format(&emitter->output,
                           "  {\n    uint64_t call_args_%llu[%zu];\n",
                           (unsigned long long)node->id.value,
                           operation->value.call.arguments.count
                               ? operation->value.call.arguments.count : 1))
            return emit_out_of_memory(emitter);
        for (i = 0; i < operation->value.call.arguments.count; i++) {
            if (!append_format(
                    &emitter->output,
                    "    call_args_%llu[%zu]=",
                    (unsigned long long)node->id.value, i) ||
                !emit_value_name(
                    emitter,
                    operation->value.call.arguments.items[i]) ||
                !append_text(&emitter->output, ";\n", 2))
                return emit_out_of_memory(emitter);
        }
        if (!append_format(
                &emitter->output,
                "    uint64_t call_results_%llu[%zu];\n"
                "    int call_status_%llu=abc_aot_function_%zu(call_args_%llu,call_results_%llu,error);\n"
                "    if(call_status_%llu)return call_status_%llu;\n",
                (unsigned long long)node->id.value,
                node->results.count ? node->results.count : 1,
                (unsigned long long)node->id.value, target,
                (unsigned long long)node->id.value,
                (unsigned long long)node->id.value,
                (unsigned long long)node->id.value,
                (unsigned long long)node->id.value))
            return emit_out_of_memory(emitter);
        for (i = 0; i < node->results.count; i++) {
            if (!append_text(&emitter->output, "    ", 4) ||
                !emit_value_name(emitter, node->results.items[i]) ||
                !append_format(
                    &emitter->output,
                    "=call_results_%llu[%zu];\n",
                    (unsigned long long)node->id.value, i))
                return emit_out_of_memory(emitter);
        }
        return append_text(&emitter->output, "  }\n", 4) ||
               emit_out_of_memory(emitter);

    default:
        return emit_failure(emitter, origin,
                            "portable C encountered unsupported node");
    }
}

static const char *relation_operator(
    abc_asdl_residual_binary_op relation) {
    switch (relation) {
    case ABC_ASDL_RESIDUAL_BINARY_OP_EQUAL: return "==";
    case ABC_ASDL_RESIDUAL_BINARY_OP_NOT_EQUAL: return "!=";
    case ABC_ASDL_RESIDUAL_BINARY_OP_LESS_UNSIGNED: return "<";
    case ABC_ASDL_RESIDUAL_BINARY_OP_LESS_EQUAL_UNSIGNED: return "<=";
    default: return NULL;
    }
}

static int emit_terminator(
    c_emitter *emitter,
    const abc_residual_function *function,
    const abc_residual_terminator *terminator) {
    uint64_t origin = terminator->origin.offset;
    const char *relation;
    size_t target;
    size_t i;

    switch (terminator->tag) {
    case ABC_ASDL_RESIDUAL_TERMINATOR_JUMP:
        return emit_edge(
            emitter, function, &terminator->value.jump.edge, origin);

    case ABC_ASDL_RESIDUAL_TERMINATOR_BRANCH:
        relation = relation_operator(
            terminator->value.branch.relation);
        if (!append_text(&emitter->output, "  if(", 5))
            return emit_out_of_memory(emitter);
        if (relation) {
            if (!emit_value_name(
                    emitter, terminator->value.branch.left) ||
                !append_format(&emitter->output, "%s", relation) ||
                !emit_value_name(
                    emitter, terminator->value.branch.right))
                return emit_out_of_memory(emitter);
        } else if (terminator->value.branch.relation ==
                       ABC_ASDL_RESIDUAL_BINARY_OP_LESS_SIGNED ||
                   terminator->value.branch.relation ==
                       ABC_ASDL_RESIDUAL_BINARY_OP_LESS_EQUAL_SIGNED) {
            if (!append_text(&emitter->output, "abc_aot_signed(", 15) ||
                !emit_value_name(
                    emitter, terminator->value.branch.left) ||
                !append_text(
                    &emitter->output,
                    terminator->value.branch.relation ==
                            ABC_ASDL_RESIDUAL_BINARY_OP_LESS_SIGNED
                        ? ")<abc_aot_signed("
                        : ")<=abc_aot_signed(",
                    terminator->value.branch.relation ==
                            ABC_ASDL_RESIDUAL_BINARY_OP_LESS_SIGNED
                        ? 18 : 19) ||
                !emit_value_name(
                    emitter, terminator->value.branch.right) ||
                !append_text(&emitter->output, ")", 1))
                return emit_out_of_memory(emitter);
        } else {
            return emit_failure(emitter, origin,
                                "portable C cannot emit branch relation");
        }
        if (!append_text(&emitter->output, "){\n", 3) ||
            !emit_edge(
                emitter, function,
                &terminator->value.branch.yes, origin) ||
            !append_text(&emitter->output, "  }\n", 4))
            return emit_out_of_memory(emitter);
        return emit_edge(
            emitter, function,
            &terminator->value.branch.no, origin);

    case ABC_ASDL_RESIDUAL_TERMINATOR_SWITCH:
        for (i = 0;
             i < terminator->value.switch_value.arms.count; i++) {
            const abc_residual_switch_arm *arm =
                &terminator->value.switch_value.arms.items[i];

            if (!append_text(&emitter->output, "  if(", 5) ||
                !emit_value_name(
                    emitter,
                    terminator->value.switch_value.value) ||
                !append_format(
                    &emitter->output,
                    ">=%llu&&",
                    (unsigned long long)arm->value_low) ||
                !emit_value_name(
                    emitter,
                    terminator->value.switch_value.value) ||
                !append_format(
                    &emitter->output,
                    "<=%llu){\n",
                    (unsigned long long)arm->value_high) ||
                !emit_edge(emitter, function, &arm->edge, origin) ||
                !append_text(&emitter->output, "  }\n", 4))
                return emit_out_of_memory(emitter);
        }
        return emit_edge(
            emitter, function,
            &terminator->value.switch_value.fallback, origin);

    case ABC_ASDL_RESIDUAL_TERMINATOR_RETURN:
        if(scalar_function(emitter,emitter->current_function)){
            if(terminator->value.return_value.values.count!=1||
               !append_text(&emitter->output,"  return ",9)||
               !emit_value_name(emitter,terminator->value.return_value.values.items[0])||
               !append_text(&emitter->output,";\n",2))return emit_out_of_memory(emitter);
            return 1;
        }
        for (i = 0;
             i < terminator->value.return_value.values.count; i++) {
            if (!append_format(&emitter->output,
                               "  results[%zu]=", i) ||
                !emit_value_name(
                    emitter,
                    terminator->value.return_value.values.items[i]) ||
                !append_text(&emitter->output, ";\n", 2))
                return emit_out_of_memory(emitter);
        }
        return append_text(&emitter->output,
                           "  return ABC_AOT_OK;\n", 21) ||
               emit_out_of_memory(emitter);

    case ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL:
        if (!function_index(
                emitter->program,
                terminator->value.tail_call.target, &target))
            return emit_failure(emitter, origin,
                                "portable C tail target is invalid");
        if(scalar_function(emitter,target)){
            int current_scalar=scalar_function(emitter,emitter->current_function);
            if(!append_format(&emitter->output,current_scalar?"  return abc_aot_function_%zu(":"  results[0]=abc_aot_function_%zu(",target))return emit_out_of_memory(emitter);
            for(i=0;i<terminator->value.tail_call.arguments.count;i++){
                if(i&&!append_text(&emitter->output,",",1))return emit_out_of_memory(emitter);
                if(!emit_value_name(emitter,terminator->value.tail_call.arguments.items[i]))return 0;
            }
            if(!append_text(&emitter->output,");\n",3))return emit_out_of_memory(emitter);
            return current_scalar?1:(append_text(&emitter->output,"  return ABC_AOT_OK;\n",21)||emit_out_of_memory(emitter));
        }
        if (!append_format(
                &emitter->output,
                "  {\n    uint64_t tail_args[%zu];\n",
                terminator->value.tail_call.arguments.count
                    ? terminator->value.tail_call.arguments.count : 1))
            return emit_out_of_memory(emitter);
        for (i = 0;
             i < terminator->value.tail_call.arguments.count; i++) {
            if (!append_format(&emitter->output,
                               "    tail_args[%zu]=", i) ||
                !emit_value_name(
                    emitter,
                    terminator->value.tail_call.arguments.items[i]) ||
                !append_text(&emitter->output, ";\n", 2))
                return emit_out_of_memory(emitter);
        }
        return append_format(
                   &emitter->output,
                   "    return abc_aot_function_%zu(tail_args,results,error);\n"
                   "  }\n",
                   target) ||
               emit_out_of_memory(emitter);

    case ABC_ASDL_RESIDUAL_TERMINATOR_ABORT:
        return append_format(
                   &emitter->output,
                   "  return abc_aot_fail(error,%llu,%llu);\n",
                   (unsigned long long)
                       terminator->value.abort.reason,
                   (unsigned long long)origin) ||
               emit_out_of_memory(emitter);

    case ABC_ASDL_RESIDUAL_TERMINATOR_UNREACHABLE:
        return append_format(
                   &emitter->output,
                   "  return abc_aot_fail(error,5,%llu);\n",
                   (unsigned long long)origin) ||
               emit_out_of_memory(emitter);

    default:
        return emit_failure(emitter, origin,
                            "portable C encountered invalid terminator");
    }
}

static int emit_function(c_emitter *emitter, size_t index) {
    const abc_residual_function *function =
        &emitter->program->functions.items[index];
    size_t i;
    size_t bi;
    size_t ni;
    emitter->current_function=index;
    if(scalar_function(emitter,index)){
        if(!append_format(&emitter->output,"static inline %s abc_aot_function_%zu(",
                          emitter->u32_results[index]?"uint32_t":"uint64_t",index))return emit_out_of_memory(emitter);
        if(!function->argument_types.count&&!append_text(&emitter->output,"void",4))return emit_out_of_memory(emitter);
        for(i=0;i<function->argument_types.count;i++){
            if(i&&!append_text(&emitter->output,",",1))return emit_out_of_memory(emitter);
            if(!append_format(&emitter->output,"%s argument_%zu",
                              emitter->u32_arguments[index][i]?"uint32_t":"uint64_t",i))return emit_out_of_memory(emitter);
        }
        if(!append_text(&emitter->output,") {\n",4))return emit_out_of_memory(emitter);
    }else if(!append_format(&emitter->output,
            "static inline int abc_aot_function_%zu(const uint64_t *arguments,"
            "uint64_t *results,abc_aot_error *error) {\n",index))
        return emit_out_of_memory(emitter);

    for(i=0;i<emitter->program->values.count;i++)
        if(!append_format(&emitter->output,"  %s v_%llu=0; (void)v_%llu;\n",
                          c_value_type(emitter->program->values.items[i].type),
                          (unsigned long long)emitter->program->values.items[i].id.value,
                          (unsigned long long)emitter->program->values.items[i].id.value))
            return emit_out_of_memory(emitter);
    if(!scalar_function(emitter,index)&&
       !append_format(&emitter->output,"  (void)arguments; (void)error;\n"))
        return emit_out_of_memory(emitter);
    for (i = 0; i < emitter->program->values.count; i++) {
        const abc_residual_value *value =
            &emitter->program->values.items[i];

        if (value->definition.tag ==
            ABC_ASDL_RESIDUAL_DEFINITION_CONSTANT &&
            !append_format(
                &emitter->output,
                "  v_%llu=UINT64_C(0x%016llx);\n",
                (unsigned long long)value->id.value,
                (unsigned long long)value->definition.value.constant.low))
            return emit_out_of_memory(emitter);
    }
    for (i = 0; i < function->arguments.count; i++) {
        if (!append_text(&emitter->output, "  ", 2) ||
            !emit_value_name(emitter, function->arguments.items[i]) ||
            !append_format(&emitter->output,scalar_function(emitter,index)?
                           "=argument_%zu;\n":"=arguments[%zu];\n",i))
            return emit_out_of_memory(emitter);
    }
    if (!append_format(
            &emitter->output, "  goto block_%llu;\n",
            (unsigned long long)function->entry.value))
        return emit_out_of_memory(emitter);

    for (bi = 0; bi < function->blocks.count; bi++) {
        const abc_residual_block *block =
            &function->blocks.items[bi];

        if (!append_format(
                &emitter->output,
                "block_%llu: ;\n",
                (unsigned long long)block->id.value))
            return emit_out_of_memory(emitter);
        for (ni = 0; ni < block->nodes.count; ni++)
            if (!emit_node(emitter, &block->nodes.items[ni]))
                return 0;
        if (!emit_terminator(
                emitter, function, &block->terminator))
            return 0;
    }
    return append_text(&emitter->output, "}\n\n", 3) ||
           emit_out_of_memory(emitter);
}

static int emit_wrappers(c_emitter *emitter) {
    size_t i;
    size_t target;

    for (i = 0; i < emitter->export_count; i++) {
        const c_export *exported = &emitter->exports[i];

        if (!function_index(
                emitter->program,
                exported->function.value, &target))
            return emit_failure(
                emitter, 0,
                "export '%s' has no residual function",
                exported->name);
        if(scalar_function(emitter,target)){
            if(!append_format(&emitter->output,
                "int abc_export_%s(const uint64_t *arguments,size_t argument_count,uint64_t *results,size_t result_capacity,abc_aot_error *error) {\n"
                "  abc_aot_clear(error);\n"
                "  if(argument_count!=%u)return ABC_AOT_ARGUMENTS;\n"
                "  if(result_capacity<1)return ABC_AOT_RESULTS;\n"
                "  if(%u&&!arguments)return ABC_AOT_ARGUMENTS;\n"
                "  if(!results)return ABC_AOT_RESULTS;\n"
                "  results[0]=abc_aot_function_%zu(",
                exported->name,exported->arguments,exported->arguments,target))return emit_out_of_memory(emitter);
            for(size_t ai=0;ai<exported->arguments;ai++){
                if(ai&&!append_text(&emitter->output,",",1))return emit_out_of_memory(emitter);
                if(!append_format(&emitter->output,"arguments[%zu]",ai))return emit_out_of_memory(emitter);
            }
            if(!append_format(&emitter->output,"%s",");\n  return ABC_AOT_OK;\n}\n\n"))return emit_out_of_memory(emitter);
            continue;
        }
        if (!append_format(
                &emitter->output,
                "int abc_export_%s(const uint64_t *arguments,size_t argument_count,"
                "uint64_t *results,size_t result_capacity,abc_aot_error *error) {\n"
                "  abc_aot_clear(error);\n"
                "  if(argument_count!=%u)return ABC_AOT_ARGUMENTS;\n"
                "  if(result_capacity<%u)return ABC_AOT_RESULTS;\n"
                "  if(%u&&!arguments)return ABC_AOT_ARGUMENTS;\n"
                "  if(%u&&!results)return ABC_AOT_RESULTS;\n"
                "  return abc_aot_function_%zu(arguments,results,error);\n"
                "}\n\n",
                exported->name, exported->arguments,
                exported->results, exported->arguments,
                exported->results, target))
            return emit_out_of_memory(emitter);
    }

    if (!append_text(
            &emitter->output,
            "const abc_aot_export abc_aot_exports[] = {\n",
            43))
        return emit_out_of_memory(emitter);
    for (i = 0; i < emitter->export_count; i++) {
        const c_export *exported = &emitter->exports[i];

        if (!append_format(
                &emitter->output,
                "  {\"%s\",%u,%u,abc_export_%s},\n",
                exported->name, exported->arguments,
                exported->results, exported->name))
            return emit_out_of_memory(emitter);
    }
    if (!append_format(
            &emitter->output,
            "};\n"
            "const size_t abc_aot_export_count=%zu;\n"
            "const abc_aot_export *abc_aot_find(const char *name) {\n"
            "  size_t i; if(!name)return NULL;\n"
            "  for(i=0;i<abc_aot_export_count;i++)"
            "if(!strcmp(name,abc_aot_exports[i].name))return &abc_aot_exports[i];\n"
            "  return NULL;\n"
            "}\n",
            emitter->export_count))
        return emit_out_of_memory(emitter);
    return 1;
}

static void free_widths(c_emitter *emitter){
    if(emitter->u32_arguments)for(size_t i=0;i<emitter->program->functions.count;i++)free(emitter->u32_arguments[i]);
    free(emitter->u32_arguments);free(emitter->u32_results);
}

static abc_status emit_program_c(
    const abc_residual_program *program,
    const c_export *exports, size_t export_count,
    char **source, size_t *source_size, abc_error *error) {
    abc_residual_diagnostic diagnostic;
    c_emitter emitter;
    size_t i;

    memset(&emitter, 0, sizeof(emitter));
    emitter.program = program;
    emitter.exports = exports;
    emitter.export_count = export_count;
    emitter.error = error;

    if (!abc_residual_validate(program, &diagnostic))
        return abc_fail(
            error, ABC_INVALID,
            diagnostic.origin <= UINT32_MAX
                ? (uint32_t)diagnostic.origin : UINT32_MAX,
            "portable C input residual IR is invalid: %s",
            diagnostic.message);
    if (!validate_subset(&emitter) ||
        !analyze_failures(&emitter) ||
        !analyze_widths(&emitter) ||
        !emit_runtime(&emitter))
        goto failed;

    for (i = 0; i < program->functions.count; i++) {
        if(scalar_function(&emitter,i)){
            const abc_residual_function *function=&program->functions.items[i];
            if(!append_format(&emitter.output,"static inline %s abc_aot_function_%zu(",
                              emitter.u32_results[i]?"uint32_t":"uint64_t",i))goto no_memory;
            if(!function->argument_types.count&&!append_text(&emitter.output,"void",4))goto no_memory;
            for(size_t ai=0;ai<function->argument_types.count;ai++){
                if(ai&&!append_text(&emitter.output,",",1))goto no_memory;
                if(!append_format(&emitter.output,"%s",emitter.u32_arguments[i][ai]?"uint32_t":"uint64_t"))goto no_memory;
            }
            if(!append_text(&emitter.output,");\n",3))goto no_memory;
        }else if(!append_format(&emitter.output,
                "static inline int abc_aot_function_%zu(const uint64_t *,uint64_t *,abc_aot_error *);\n",i))
            goto no_memory;
    }
    if (!append_text(&emitter.output, "\n", 1))
        goto no_memory;

    for (i = 0; i < program->functions.count; i++)
        if (!emit_function(&emitter, i))
            goto failed;
    if (!emit_wrappers(&emitter))
        goto failed;

    *source = emitter.output.items;
    *source_size = emitter.output.count;
    free(emitter.may_fail);free_widths(&emitter);
    return ABC_OK;

no_memory:
    emit_out_of_memory(&emitter);
failed:
    free(emitter.may_fail);free_widths(&emitter);
    free(emitter.output.items);
    return error && error->status == ABC_NOMEM
        ? ABC_NOMEM : ABC_INVALID;
}

abc_status abc_emit_c(const void *bytes, size_t size,
                      char **source, size_t *source_size,
                      abc_error *error) {
    abc_module *module = NULL;
    abc_residual_bundle *bundle = NULL;
    abc_residual_build_diagnostic diagnostic;
    abc_residual_build_status build_status;
    const abc_residual_source_function *metadata;
    const abc_residual_program *program;
    c_export *exports = NULL;
    abc_status status;
    uint32_t i;

    abc_clear(error);
    if (source) *source = NULL;
    if (source_size) *source_size = 0;
    if (!bytes || !source || !source_size)
        return abc_fail(error, ABC_INVALID, UINT32_MAX,
                        "invalid portable C emission input");

    status = abc_module_load(bytes, size, &module, error);
    if (status != ABC_OK) return status;
    if (module->memory_profile) {
        status = abc_fail(
            error, ABC_INVALID, UINT32_MAX,
            "portable C currently supports only the integer/static profile");
        goto done;
    }

    build_status = abc_residual_build(
        module, NULL, &bundle, &diagnostic);
    if (build_status != ABC_RESIDUAL_BUILD_OK) {
        status = abc_fail(
            error,
            build_status == ABC_RESIDUAL_BUILD_NOMEM
                ? ABC_NOMEM : ABC_INVALID,
            diagnostic.bytecode_offset,
            "portable C residual builder failed in function %u: %s",
            diagnostic.source_function, diagnostic.message);
        goto done;
    }

    metadata = abc_residual_bundle_source_functions(bundle);
    program = abc_residual_bundle_program(bundle);
    if (module->export_count) {
        exports = calloc(module->export_count, sizeof(*exports));
        if (!exports) {
            status = abc_fail(
                error, ABC_NOMEM, UINT32_MAX,
                "portable C export allocation failed");
            goto done;
        }
    }
    for (i = 0; i < module->export_count; i++) {
        uint32_t function = module->exports[i].function;

        if (!metadata[function].supported) {
            status = abc_fail(
                error, ABC_INVALID,
                module->functions[function].entry,
                "portable C export '%s' uses unsupported residual operations",
                module->exports[i].name);
            goto done;
        }
        exports[i].name = module->exports[i].name;
        exports[i].arguments = module->functions[function].arguments;
        exports[i].results = module->functions[function].results;
        exports[i].function = metadata[function].residual_function;
    }

    status = emit_program_c(
        program, exports, module->export_count,
        source, source_size, error);

done:
    free(exports);
    abc_residual_bundle_free(bundle);
    abc_module_free(module);
    return status;
}

void abc_emitted_c_free(char *source) {
    free(source);
}
