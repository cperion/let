#include "residual_builder.h"

#include "dynamic.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct build_block build_block;
typedef struct build_version build_version;
typedef struct build_function build_function;
typedef struct builder builder;

typedef struct {
    abc_residual_value *items;
    size_t count;
    size_t capacity;
} value_vector;

typedef struct {
    abc_residual_node *items;
    size_t count;
    size_t capacity;
} node_vector;

typedef struct {
    build_block **items;
    size_t count;
    size_t capacity;
} block_vector;

typedef struct {
    build_version **items;
    size_t count;
    size_t capacity;
    size_t head;
} version_vector;

typedef struct {
    abc_residual_call *items;
    size_t count;
    size_t capacity;
} call_vector;

typedef struct {
    uint8_t stack;
    int32_t home;
    abc_residual_id value;
} version_home;

typedef enum {
    VERSION_PRESERVE,
    VERSION_LOOP_ENTRY,
    VERSION_VIRTUAL_ENTRY,
    VERSION_RECURSIVE
} version_mode;

struct build_block {
    abc_residual_block ir;
    node_vector nodes;
    int terminated;
};

struct build_version {
    uint32_t pc;
    abc_symbolic_context key;
    abc_symbolic_context entry;
    build_block *block;
    version_home *homes;
    size_t home_count;
    int built;
};

struct build_function {
    abc_residual_function ir;
    block_vector blocks;
    version_vector versions;
    call_vector calls;
    size_t value_start;
    size_t value_end;
    unsigned supported;
};

struct abc_residual_bundle {
    abc_residual_arena *arena;
    abc_residual_program program;
    size_t source_function_count;
    abc_residual_source_function *source_functions;
};

struct builder {
    const abc_module *module;
    const abc_residual_build_options *options;
    const abc_residual_call_graph *graph;
    abc_residual_bundle *bundle;
    abc_residual_arena *arena;
    build_function *functions;
    abc_residual_id *function_ids;
    value_vector values;
    uint8_t *leaders;
    uint8_t *loop_headers;
    uint8_t *embedded;
    version_mode pending_edge_mode;
    uint32_t pending_edge_target;
    unsigned pending_edge;
    uint64_t next_id;
    uint32_t source_function;
    build_function *function;
    build_version *version;
    build_block *block;
    abc_symbolic_machine *machine;
    abc_residual_build_status status;
    abc_residual_build_diagnostic *diagnostic;
};

static int grow(void **items, size_t *capacity, size_t needed, size_t item_size) {
    size_t next;
    void *result;

    if (needed <= *capacity) return 1;
    next = *capacity ? *capacity * 2 : 8;
    while (next < needed) {
        if (next > SIZE_MAX / 2) {
            next = needed;
            break;
        }
        next *= 2;
    }
    if (item_size && next > SIZE_MAX / item_size) return 0;
    result = realloc(*items, next * item_size);
    if (!result) return 0;
    *items = result;
    *capacity = next;
    return 1;
}

static void diagnose(builder *b, abc_residual_build_status status,
                     uint32_t offset, const char *format, ...) {
    va_list arguments;

    if (b->status != ABC_RESIDUAL_BUILD_OK) return;
    b->status = status;
    if (!b->diagnostic) return;
    b->diagnostic->status = status;
    b->diagnostic->source_function = b->source_function;
    b->diagnostic->bytecode_offset = offset;
    va_start(arguments, format);
    vsnprintf(b->diagnostic->message, sizeof(b->diagnostic->message),
              format, arguments);
    va_end(arguments);
}

static int no_memory(builder *b, uint32_t offset) {
    diagnose(b, ABC_RESIDUAL_BUILD_NOMEM, offset,
             "residual builder allocation failed");
    if (b->machine) b->machine->exit = ABC_SYM_EXIT_FAILURE;
    return 0;
}

static int not_supported(builder *b, uint32_t offset,
                         const char *format, ...) {
    va_list arguments;

    if (b->status == ABC_RESIDUAL_BUILD_OK) {
        b->status = ABC_RESIDUAL_BUILD_UNSUPPORTED;
        if (b->diagnostic) {
            b->diagnostic->status = ABC_RESIDUAL_BUILD_UNSUPPORTED;
            b->diagnostic->source_function = b->source_function;
            b->diagnostic->bytecode_offset = offset;
            va_start(arguments, format);
            vsnprintf(b->diagnostic->message,
                      sizeof(b->diagnostic->message), format, arguments);
            va_end(arguments);
        }
    }
    if (b->machine) b->machine->exit = ABC_SYM_EXIT_BOUNDARY;
    return 0;
}

static int malformed(builder *b, uint32_t offset,
                     const char *format, ...) {
    va_list arguments;

    if (b->status == ABC_RESIDUAL_BUILD_OK) {
        b->status = ABC_RESIDUAL_BUILD_INVALID;
        if (b->diagnostic) {
            b->diagnostic->status = ABC_RESIDUAL_BUILD_INVALID;
            b->diagnostic->source_function = b->source_function;
            b->diagnostic->bytecode_offset = offset;
            va_start(arguments, format);
            vsnprintf(b->diagnostic->message,
                      sizeof(b->diagnostic->message), format, arguments);
            va_end(arguments);
        }
    }
    if (b->machine) b->machine->exit = ABC_SYM_EXIT_FAILURE;
    return 0;
}

static abc_residual_id next_id(builder *b) {
    abc_residual_id result = {0};

    if (b->next_id == UINT32_MAX) {
        diagnose(b, ABC_RESIDUAL_BUILD_NOMEM,
                 b->machine ? b->machine->pc : UINT32_MAX,
                 "residual id space exhausted");
        return result;
    }
    result.value = ++b->next_id;
    return result;
}

static abc_residual_origin make_origin(uint32_t offset) {
    abc_residual_origin result = {.offset = offset, .caller = NULL};
    return result;
}

static abc_residual_type kind_type(unsigned kind) {
    switch (kind) {
    case ABC_KIND_ADDR:
        return ABC_ASDL_RESIDUAL_TYPE_ADDRESS;
    case ABC_KIND_FLOAT:
        return ABC_ASDL_RESIDUAL_TYPE_F64;
    case ABC_KIND_ANY:
        return ABC_ASDL_RESIDUAL_TYPE_ANY;
    default:
        return ABC_ASDL_RESIDUAL_TYPE_CELL;
    }
}

static abc_residual_facts symbolic_facts(abc_symbolic_value value) {
    abc_residual_facts result = {
        .dynamic_tags = value.dynamic_tags,
        .dynamic_width = value.dynamic_width,
        .representation = (abc_residual_representation)value.dynamic_repr
    };
    return result;
}

static abc_residual_value *find_value(builder *b, uint64_t id) {
    size_t i;

    for (i = 0; i < b->values.count; i++)
        if (b->values.items[i].id.value == id)
            return &b->values.items[i];
    return NULL;
}

static int machine_cell_type(abc_residual_type type) {
    return type == ABC_ASDL_RESIDUAL_TYPE_CELL ||
           type == ABC_ASDL_RESIDUAL_TYPE_U32 ||
           type == ABC_ASDL_RESIDUAL_TYPE_I32 ||
           type == ABC_ASDL_RESIDUAL_TYPE_U64 ||
           type == ABC_ASDL_RESIDUAL_TYPE_I64 ||
           type == ABC_ASDL_RESIDUAL_TYPE_F64 ||
           type == ABC_ASDL_RESIDUAL_TYPE_ADDRESS ||
           type == ABC_ASDL_RESIDUAL_TYPE_ANY;
}

static int type_compatible(abc_residual_type actual,
                           abc_residual_type expected) {
    return actual == expected ||
           (expected == ABC_ASDL_RESIDUAL_TYPE_CELL &&
            machine_cell_type(actual));
}

static abc_residual_type symbolic_type(builder *b, abc_symbolic_value value,
                                       abc_residual_type fallback) {
    abc_residual_value *known;

    if (value.kind == ABC_SYM_BACKEND) {
        known = find_value(b, value.reg);
        if (known) return known->type;
    }
    if (value.kind == ABC_SYM_HOME) return fallback;
    if (value.dynamic_tags) return ABC_ASDL_RESIDUAL_TYPE_ANY;
    return fallback;
}

static abc_symbolic_value symbolic_result(abc_residual_id id, unsigned stack,
                                          abc_residual_facts facts) {
    abc_symbolic_value result =
        abc_symbolic_backend((uint32_t)id.value, stack, 0);

    result.dynamic_tags = (uint16_t)facts.dynamic_tags;
    result.dynamic_width = (uint8_t)facts.dynamic_width;
    result.dynamic_repr = (uint8_t)facts.representation;
    return result;
}

static int append_value(builder *b, abc_residual_value value) {
    if (!grow((void **)&b->values.items, &b->values.capacity,
              b->values.count + 1, sizeof(*b->values.items)))
        return no_memory(b, (uint32_t)value.origin.offset);
    b->values.items[b->values.count++] = value;
    return 1;
}

static int emit_operation(builder *b, abc_residual_operation operation,
                          abc_residual_effect effect,
                          const abc_residual_type *types,
                          const abc_residual_facts *facts,
                          size_t result_count, uint32_t origin,
                          abc_symbolic_value *results, unsigned stack);

static abc_residual_id add_constant(builder *b, abc_symbolic_value symbolic,
                                    abc_residual_type type, uint32_t origin) {
    abc_residual_id id = next_id(b);
    abc_residual_value value;

    if (!id.value) return id;
    memset(&value, 0, sizeof(value));
    value.id = id;
    value.type = type;
    value.facts = symbolic_facts(symbolic);
    value.definition.tag = ABC_ASDL_RESIDUAL_DEFINITION_CONSTANT;
    value.definition.value.constant.low = symbolic.constant;
    value.definition.value.constant.high = 0;
    value.origin = make_origin(origin);
    if (!append_value(b, value)) id.value = 0;
    return id;
}

static abc_residual_id value_id(builder *b, abc_symbolic_value value,
                                abc_residual_type type, uint32_t origin) {
    abc_residual_id result = {0};
    size_t i;

    if (value.kind == ABC_SYM_BACKEND) {
        result.value = value.reg;
        if (!find_value(b, result.value))
            malformed(b, origin, "symbolic value references unknown residual id");
        return result;
    }
    if (value.kind == ABC_SYM_CONST)
        return add_constant(b, value, type, origin);
    if (value.kind == ABC_SYM_HOME) {
        char mappings[128] = "-";
        size_t used = 0;

        if (b->version) {
            mappings[0] = '\0';
            for (i = 0; i < b->version->home_count; i++) {
                const version_home *home = &b->version->homes[i];

                if (home->stack == value.stack &&
                    home->home == value.home) {
                    if (!find_value(b, home->value.value))
                        malformed(b, origin,
                                  "symbolic home maps to unknown residual id");
                    return home->value;
                }
                if (i < 8) {
                    char item[48];
                    int length = snprintf(
                        item, sizeof(item), "%s%u:%d=%llu",
                        used ? "," : "", (unsigned)home->stack,
                        (int)home->home,
                        (unsigned long long)home->value.value);

                    if (length < 0 ||
                        (size_t)length >= sizeof(item) ||
                        (size_t)length >= sizeof(mappings) - used)
                        break;
                    memcpy(mappings + used, item, (size_t)length + 1);
                    used += (size_t)length;
                }
            }
            if (!used) memcpy(mappings, "-", 2);
        }
        if (value.stack == ABC_SYM_C && value.home >= 0) {
            abc_residual_operation address_operation = {0};
            abc_residual_operation load_operation = {0};
            abc_symbolic_value address_result, load_result;
            abc_residual_type address_type = ABC_ASDL_RESIDUAL_TYPE_ADDRESS;
            address_operation.tag = ABC_ASDL_RESIDUAL_OPERATION_FRAME_ADDRESS;
            address_operation.value.frame_address.offset =
                (uint64_t)(uint32_t)value.home * 8;
            if (!emit_operation(b, address_operation,
                    (abc_residual_effect){0}, &address_type, NULL, 1,
                    origin, &address_result, ABC_SYM_A))
                return result;
            load_operation.tag = ABC_ASDL_RESIDUAL_OPERATION_LOAD;
            load_operation.value.load.space =
                ABC_ASDL_RESIDUAL_ADDRESS_SPACE_FRAME;
            load_operation.value.load.address =
                (abc_residual_id){address_result.reg};
            load_operation.value.load.width = 8;
            load_operation.value.load.offset = 0;
            load_operation.value.load.signed_value = false;
            if (!emit_operation(b, load_operation,
                    (abc_residual_effect){.reads_memory = true},
                    &type, NULL, 1, origin, &load_result, ABC_SYM_A))
                return result;
            return (abc_residual_id){load_result.reg};
        }
        not_supported(
            b, origin,
            "unmapped HOME %u:%d pc=%u n=%zu map=%s",
            (unsigned)value.stack, (int)value.home,
            b->version ? b->version->pc : UINT32_MAX,
            b->version ? b->version->home_count : 0,
            mappings);
        return result;
    }
    malformed(b, origin,
              "symbolic value has no residual definition");
    return result;
}

static abc_residual_id *copy_ids(builder *b, const abc_residual_id *items,
                                 size_t count, uint32_t origin) {
    abc_residual_id *copy;

    if (!count) return NULL;
    copy = abc_residual_copy(b->arena, items, count, sizeof(*items));
    if (!copy) no_memory(b, origin);
    return copy;
}

static int append_node(builder *b, abc_residual_node node) {
    node_vector *nodes = &b->block->nodes;

    if (!grow((void **)&nodes->items, &nodes->capacity,
              nodes->count + 1, sizeof(*nodes->items)))
        return no_memory(b, (uint32_t)node.origin.offset);
    nodes->items[nodes->count++] = node;
    return 1;
}

static int add_results(builder *b, abc_residual_node *node,
                       const abc_residual_type *types,
                       const abc_residual_facts *facts, size_t count,
                       uint32_t origin, abc_symbolic_value *results,
                       unsigned stack) {
    abc_residual_id ids[255];
    size_t i;

    if (count > 255)
        return malformed(b, origin, "residual node has too many results");
    for (i = 0; i < count; i++) {
        abc_residual_value value;

        ids[i] = next_id(b);
        if (!ids[i].value) return 0;
        memset(&value, 0, sizeof(value));
        value.id = ids[i];
        value.type = types[i];
        if (facts) value.facts = facts[i];
        value.definition.tag =
            ABC_ASDL_RESIDUAL_DEFINITION_INSTRUCTION_RESULT;
        value.definition.value.instruction_result.instruction = node->id;
        value.definition.value.instruction_result.index = i;
        value.origin = make_origin(origin);
        if (!append_value(b, value)) return 0;
        if (results)
            results[i] = symbolic_result(ids[i], stack, value.facts);
    }
    node->results.count = count;
    node->results.items = copy_ids(b, ids, count, origin);
    return !count || node->results.items != NULL;
}

static int emit_operation(builder *b, abc_residual_operation operation,
                          abc_residual_effect effect,
                          const abc_residual_type *types,
                          const abc_residual_facts *facts,
                          size_t result_count, uint32_t origin,
                          abc_symbolic_value *results, unsigned stack) {
    abc_residual_node node;

    memset(&node, 0, sizeof(node));
    node.id = next_id(b);
    node.effect = effect;
    node.operation = operation;
    node.origin = make_origin(origin);
    if (!node.id.value ||
        !add_results(b, &node, types, facts, result_count,
                     origin, results, stack))
        return 0;
    return append_node(b, node);
}

static int set_terminator(builder *b,
                          abc_residual_terminator terminator) {
    if (b->block->terminated)
        return malformed(b, (uint32_t)terminator.origin.offset,
                         "block received more than one terminator");
    b->block->ir.terminator = terminator;
    b->block->terminated = 1;
    return 1;
}

static int integer_binary(unsigned opcode,
                          abc_asdl_residual_binary_op *operation) {
    switch (opcode) {
    case OP_ADD_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_ADD; return 1;
    case OP_SUB_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_SUB; return 1;
    case OP_MUL_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_MUL; return 1;
    case OP_DIVU_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_DIV_UNSIGNED; return 1;
    case OP_DIVS_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_DIV_SIGNED; return 1;
    case OP_REMU_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_REM_UNSIGNED; return 1;
    case OP_REMS_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_REM_SIGNED; return 1;
    case OP_AND_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_BIT_AND; return 1;
    case OP_OR_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_BIT_OR; return 1;
    case OP_XOR_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_BIT_XOR; return 1;
    case OP_SHL_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_SHIFT_LEFT; return 1;
    case OP_SHR_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_SHIFT_RIGHT; return 1;
    case OP_SAR_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_SHIFT_ARITHMETIC; return 1;
    case OP_EQ_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_EQUAL; return 1;
    case OP_NE_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_NOT_EQUAL; return 1;
    case OP_LT_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_LESS_SIGNED; return 1;
    case OP_LE_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_LESS_EQUAL_SIGNED; return 1;
    case OP_LTU_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_LESS_UNSIGNED; return 1;
    case OP_LEU_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_LESS_EQUAL_UNSIGNED; return 1;
    default: return 0;
    }
}

static int float_binary(unsigned opcode,
                        abc_asdl_residual_binary_op *operation) {
    switch (opcode) {
    case OP_FADD_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_ADD; return 1;
    case OP_FSUB_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_SUB; return 1;
    case OP_FMUL_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_MUL; return 1;
    case OP_FDIV_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_DIV; return 1;
    case OP_FLT_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_LESS; return 1;
    case OP_FLE_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_LESS_EQUAL; return 1;
    case OP_FEQ_A: *operation = ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_EQUAL; return 1;
    default: return 0;
    }
}

static int unary_operation(unsigned opcode,
                           abc_asdl_residual_unary_op *operation) {
    switch (opcode) {
    case OP_NEG_A: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_NEG; return 1;
    case OP_NOT_A: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_BIT_NOT; return 1;
    case OP_LNOT_A: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_LOGICAL_NOT; return 1;
    case OP_ZX32_A: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_ZERO_EXTEND32; return 1;
    case OP_SX32_A: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_SIGN_EXTEND32; return 1;
    case OP_FNEG: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_FLOAT_NEG; return 1;
    case OP_I2FS: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_SIGNED_TO_FLOAT; return 1;
    case OP_I2FU: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_UNSIGNED_TO_FLOAT; return 1;
    case OP_F2IS: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_FLOAT_TO_SIGNED; return 1;
    case OP_F2IU: *operation = ABC_ASDL_RESIDUAL_UNARY_OP_FLOAT_TO_UNSIGNED; return 1;
    default: return 0;
    }
}

static int check_operation(unsigned opcode,
                           abc_asdl_residual_check_op *operation) {
    switch (opcode) {
    case OP_CHKU8: *operation = ABC_ASDL_RESIDUAL_CHECK_OP_UNSIGNED8; return 1;
    case OP_CHKU16: *operation = ABC_ASDL_RESIDUAL_CHECK_OP_UNSIGNED16; return 1;
    case OP_CHKU32: *operation = ABC_ASDL_RESIDUAL_CHECK_OP_UNSIGNED32; return 1;
    case OP_CHKI32: *operation = ABC_ASDL_RESIDUAL_CHECK_OP_SIGNED32; return 1;
    case OP_CHKNN: *operation = ABC_ASDL_RESIDUAL_CHECK_OP_NONNEGATIVE; return 1;
    default: return 0;
    }
}

static unsigned immediate_base(unsigned opcode) {
    switch (opcode) {
    case OP_ADDI_A: return OP_ADD_A;
    case OP_SUBI_A: return OP_SUB_A;
    case OP_MULI_A: return OP_MUL_A;
    case OP_ANDI_A: return OP_AND_A;
    case OP_ORI_A: return OP_OR_A;
    case OP_XORI_A: return OP_XOR_A;
    case OP_SHLI_A: return OP_SHL_A;
    case OP_SHRI_A: return OP_SHR_A;
    case OP_SARI_A: return OP_SAR_A;
    default: return UINT_MAX;
    }
}

static unsigned c_operand_base(unsigned opcode) {
    switch (opcode) {
    case OP_ADDC_A: return OP_ADD_A;
    case OP_SUBC_A: return OP_SUB_A;
    case OP_MULC_A: return OP_MUL_A;
    case OP_XORC_A: return OP_XOR_A;
    default: return UINT_MAX;
    }
}

static int comparison_operation(abc_asdl_residual_binary_op operation) {
    return operation >= ABC_ASDL_RESIDUAL_BINARY_OP_EQUAL &&
           operation <= ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_EQUAL;
}

static int emit_binary(builder *b, uint32_t origin,
                       abc_asdl_residual_binary_op operation,
                       abc_symbolic_value left,
                       abc_symbolic_value right,
                       unsigned destination,
                       abc_symbolic_value *result,
                       abc_residual_type operand_type,
                       abc_residual_type result_type,
                       abc_residual_effect effect) {
    abc_residual_id left_id =
        value_id(b, left, operand_type, origin);
    abc_residual_id right_id =
        value_id(b, right, operand_type, origin);
    abc_residual_operation residual;

    if (!left_id.value || !right_id.value) return 0;
    memset(&residual, 0, sizeof(residual));
    residual.tag = ABC_ASDL_RESIDUAL_OPERATION_BINARY;
    residual.value.binary.operation = operation;
    residual.value.binary.left = left_id;
    residual.value.binary.right = right_id;
    return emit_operation(b, residual, effect, &result_type, NULL, 1,
                          origin, result, destination);
}

static int on_binary(void *opaque, uint32_t origin, unsigned opcode,
                     unsigned destination, int folded,
                     abc_symbolic_value left, abc_symbolic_value right,
                     abc_symbolic_value *result) {
    builder *b = opaque;
    abc_asdl_residual_binary_op operation;
    abc_residual_effect effect = {0};
    abc_residual_type type;

    if (folded) return 1;
    if (!integer_binary(opcode, &operation))
        return not_supported(b, origin, "unsupported integer operation %s",
                             op_name[opcode]);
    if (operation == ABC_ASDL_RESIDUAL_BINARY_OP_DIV_UNSIGNED ||
        operation == ABC_ASDL_RESIDUAL_BINARY_OP_DIV_SIGNED ||
        operation == ABC_ASDL_RESIDUAL_BINARY_OP_REM_UNSIGNED ||
        operation == ABC_ASDL_RESIDUAL_BINARY_OP_REM_SIGNED)
        effect.may_trap = true;
    type = comparison_operation(operation)
        ? ABC_ASDL_RESIDUAL_TYPE_CELL
        : symbolic_type(b, left, ABC_ASDL_RESIDUAL_TYPE_CELL);
    return emit_binary(b, origin, operation, left, right, destination,
                       result, ABC_ASDL_RESIDUAL_TYPE_CELL, type, effect);
}

static int on_float_binary(void *opaque, uint32_t origin, unsigned opcode,
                           unsigned destination, int folded,
                           abc_symbolic_value left,
                           abc_symbolic_value right,
                           abc_symbolic_value *result) {
    builder *b = opaque;
    abc_asdl_residual_binary_op operation;
    abc_residual_type type;

    if (folded) return 1;
    if (!float_binary(opcode, &operation))
        return not_supported(b, origin, "unsupported float operation %s",
                             op_name[opcode]);
    type = comparison_operation(operation)
        ? ABC_ASDL_RESIDUAL_TYPE_CELL
        : ABC_ASDL_RESIDUAL_TYPE_F64;
    return emit_binary(b, origin, operation, left, right, destination,
                       result, ABC_ASDL_RESIDUAL_TYPE_F64, type,
                       (abc_residual_effect){0});
}

static int on_unary(void *opaque, uint32_t origin, unsigned opcode,
                    unsigned stack, int folded,
                    abc_symbolic_value input,
                    abc_symbolic_value *result) {
    builder *b = opaque;
    abc_asdl_residual_unary_op operation;
    abc_residual_operation residual;
    abc_residual_type type = ABC_ASDL_RESIDUAL_TYPE_CELL;
    abc_residual_id input_id;

    if (folded) return 1;
    if (!unary_operation(opcode, &operation))
        return not_supported(b, origin, "unsupported unary operation %s",
                             op_name[opcode]);
    input_id = value_id(b, input, ABC_ASDL_RESIDUAL_TYPE_CELL, origin);
    if (!input_id.value) return 0;
    if (operation == ABC_ASDL_RESIDUAL_UNARY_OP_ZERO_EXTEND32)
        type = ABC_ASDL_RESIDUAL_TYPE_U32;
    else if (operation == ABC_ASDL_RESIDUAL_UNARY_OP_SIGN_EXTEND32)
        type = ABC_ASDL_RESIDUAL_TYPE_I32;
    memset(&residual, 0, sizeof(residual));
    residual.tag = ABC_ASDL_RESIDUAL_OPERATION_UNARY;
    residual.value.unary.operation = operation;
    residual.value.unary.input = input_id;
    return emit_operation(b, residual, (abc_residual_effect){0},
                          &type, NULL, 1, origin, result, stack);
}

static int on_float_unary(void *opaque, uint32_t origin, unsigned opcode,
                          int folded, int trapped,
                          abc_symbolic_value input,
                          abc_symbolic_value *result) {
    builder *b = opaque;
    abc_asdl_residual_unary_op operation;
    abc_residual_operation residual;
    abc_residual_effect effect = {0};
    abc_residual_type input_type;
    abc_residual_type result_type;
    abc_residual_id input_id;
    abc_residual_terminator terminator;

    if (!unary_operation(opcode, &operation))
        return not_supported(b, origin, "unsupported float operation %s",
                             op_name[opcode]);
    if (trapped) {
        memset(&terminator, 0, sizeof(terminator));
        terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_ABORT;
        terminator.value.abort.reason = 3;
        terminator.origin = make_origin(origin);
        return set_terminator(b, terminator);
    }
    if (folded) return 1;
    input_type = opcode == OP_I2FS || opcode == OP_I2FU
        ? ABC_ASDL_RESIDUAL_TYPE_CELL
        : ABC_ASDL_RESIDUAL_TYPE_F64;
    result_type = opcode == OP_FNEG || opcode == OP_I2FS ||
                          opcode == OP_I2FU
        ? ABC_ASDL_RESIDUAL_TYPE_F64
        : ABC_ASDL_RESIDUAL_TYPE_CELL;
    input_id = value_id(b, input, input_type, origin);
    if (!input_id.value) return 0;
    memset(&residual, 0, sizeof(residual));
    residual.tag = ABC_ASDL_RESIDUAL_OPERATION_UNARY;
    residual.value.unary.operation = operation;
    residual.value.unary.input = input_id;
    effect.may_trap = opcode == OP_F2IS || opcode == OP_F2IU;
    return emit_operation(b, residual, effect, &result_type, NULL, 1,
                          origin, result, ABC_SYM_A);
}

static int on_immediate(void *opaque, uint32_t origin, unsigned opcode,
                        unsigned stack, uint64_t immediate, int folded,
                        abc_symbolic_value input,
                        abc_symbolic_value *result) {
    builder *b = opaque;
    abc_asdl_residual_binary_op operation;
    abc_symbolic_value constant;
    unsigned base = immediate_base(opcode);

    if (folded) return 1;
    if (base == UINT_MAX || !integer_binary(base, &operation))
        return not_supported(b, origin,
                             "unsupported immediate operation %s",
                             op_name[opcode]);
    constant = abc_symbolic_constant(immediate, stack, 0);
    return emit_binary(b, origin, operation, input, constant, stack,
                       result, ABC_ASDL_RESIDUAL_TYPE_CELL,
                       ABC_ASDL_RESIDUAL_TYPE_CELL,
                       (abc_residual_effect){0});
}

static int on_c_operand(void *opaque, uint32_t origin, unsigned opcode,
                        unsigned destination, int folded,
                        abc_symbolic_value left,
                        abc_symbolic_value right,
                        abc_symbolic_value *result) {
    builder *b = opaque;
    abc_asdl_residual_binary_op operation;
    unsigned base = c_operand_base(opcode);

    if (folded) return 1;
    if (base == UINT_MAX || !integer_binary(base, &operation))
        return not_supported(b, origin,
                             "unsupported C-operand operation %s",
                             op_name[opcode]);
    return emit_binary(b, origin, operation, left, right, destination,
                       result, ABC_ASDL_RESIDUAL_TYPE_CELL,
                       ABC_ASDL_RESIDUAL_TYPE_CELL,
                       (abc_residual_effect){0});
}

static int on_pow(void *opaque, uint32_t origin, unsigned opcode,
                  unsigned destination, int folded,
                  abc_symbolic_value left,
                  abc_symbolic_value right,
                  abc_symbolic_value *result) {
    builder *b = opaque;
    abc_asdl_residual_binary_op operation =
        opcode == OP_POW
            ? ABC_ASDL_RESIDUAL_BINARY_OP_POW_UNSIGNED
            : ABC_ASDL_RESIDUAL_BINARY_OP_POW_SIGNED;
    abc_residual_effect effect = {0};

    if (folded) return 1;
    effect.may_trap = opcode == OP_POWS;
    return emit_binary(b, origin, operation, left, right, destination,
                       result, ABC_ASDL_RESIDUAL_TYPE_CELL,
                       ABC_ASDL_RESIDUAL_TYPE_CELL, effect);
}

static int on_check(void *opaque, uint32_t origin, unsigned opcode,
                    int known, int trapped, abc_symbolic_value input) {
    builder *b = opaque;
    abc_asdl_residual_check_op operation;
    abc_residual_operation residual;
    abc_residual_id input_id;
    abc_residual_terminator terminator;

    if (!check_operation(opcode, &operation))
        return not_supported(b, origin, "unsupported check %s",
                             op_name[opcode]);
    if (trapped) {
        memset(&terminator, 0, sizeof(terminator));
        terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_ABORT;
        terminator.value.abort.reason = 3;
        terminator.origin = make_origin(origin);
        return set_terminator(b, terminator);
    }
    if (known) return 1;
    input_id = value_id(b, input, ABC_ASDL_RESIDUAL_TYPE_CELL, origin);
    if (!input_id.value) return 0;
    memset(&residual, 0, sizeof(residual));
    residual.tag = ABC_ASDL_RESIDUAL_OPERATION_CHECK;
    residual.value.check.operation = operation;
    residual.value.check.input = input_id;
    residual.value.check.reason = 3;
    return emit_operation(b, residual,
                          (abc_residual_effect){.may_trap = true},
                          NULL, NULL, 0, origin, NULL, ABC_SYM_A);
}

static int append_block(builder *b, build_block *block) {
    block_vector *blocks = &b->function->blocks;

    if (!grow((void **)&blocks->items, &blocks->capacity,
              blocks->count + 1, sizeof(*blocks->items)))
        return no_memory(b, block->ir.bytecode_offset);
    blocks->items[blocks->count++] = block;
    return 1;
}

static int append_version(builder *b, build_version *version) {
    version_vector *versions = &b->function->versions;

    if (!grow((void **)&versions->items, &versions->capacity,
              versions->count + 1, sizeof(*versions->items)))
        return no_memory(b, version->pc);
    versions->items[versions->count++] = version;
    return 1;
}

static void canonicalize(abc_symbolic_context *context,
                         int forget_constants) {
    unsigned stack;
    uint32_t i;

    context->generic = (uint8_t)forget_constants;
    for (stack = 0; stack < 3; stack++) {
        for (i = 0; i < context->n[stack]; i++) {
            abc_symbolic_value *value = &context->s[stack][i];
            uint8_t width;
            uint8_t representation;
            uint16_t tags;
            int32_t home;

            if (!forget_constants && value->kind == ABC_SYM_CONST)
                continue;
            width = value->dynamic_width;
            representation = value->dynamic_repr;
            tags = value->dynamic_tags;
            home = stack == ABC_SYM_C
                ? context->c_bias + (int32_t)i - context->c_origin
                : (int32_t)i;
            *value = abc_symbolic_home(stack, home);
            value->dynamic_width = width;
            value->dynamic_repr = representation;
            value->dynamic_tags = tags;
        }
    }
}

static int32_t logical_home(const abc_symbolic_context *context,
                            unsigned stack, uint32_t index) {
    return stack == ABC_SYM_C
        ? context->c_bias + (int32_t)index - context->c_origin
        : (int32_t)index;
}

static size_t parameter_count(const abc_symbolic_context *context) {
    size_t count = 0;
    unsigned stack;
    uint32_t i;

    for (stack = 0; stack < 3; stack++)
        for (i = 0; i < context->n[stack]; i++)
            if (context->s[stack][i].kind != ABC_SYM_CONST)
                count++;
    return count;
}

static void canonicalize_value(abc_symbolic_context *context,
                               unsigned stack, uint32_t index) {
    abc_symbolic_value *value = &context->s[stack][index];
    uint8_t width = value->dynamic_width;
    uint8_t representation = value->dynamic_repr;
    uint16_t tags = value->dynamic_tags;

    *value = abc_symbolic_home(
        stack, logical_home(context, stack, index));
    value->dynamic_width = width;
    value->dynamic_repr = representation;
    value->dynamic_tags = tags;
}

static void canonicalize_virtual_entry(builder *b, uint32_t pc,
                                       abc_symbolic_context *context) {
    int target = abc_find_function(b->module, pc);
    const abc_residual_argument_fact *facts = NULL;
    uint32_t arguments;
    uint32_t first;
    uint32_t i;

    canonicalize(context, 0);
    if (target < 0) return;
    arguments = b->module->functions[target].arguments;
    if (context->n[ABC_SYM_C] < arguments) return;
    if (b->options && b->options->argument_facts)
        facts = b->options->argument_facts[target];
    first = context->n[ABC_SYM_C] - arguments;

    for (i = 0; i < arguments; i++) {
        unsigned argument = arguments - 1 - i;
        abc_symbolic_value *value =
            &context->s[ABC_SYM_C][first + i];
        int make_home = facts &&
            (facts[argument].kind == ABC_RESIDUAL_FACT_UNKNOWN ||
             (facts[argument].kind ==
                  ABC_RESIDUAL_FACT_CONSTANT &&
              (value->kind != ABC_SYM_CONST ||
               value->constant != facts[argument].constant)));

        /*
         * An unreached fact has not converged yet. Preserve the incoming
         * constant for this build; propagate_calls will schedule a rebuild
         * once the recursive component supplies UNKNOWN/CONSTANT facts.
         */
        if (make_home)
            canonicalize_value(
                context, ABC_SYM_C, first + i);
    }
}

static void join_symbolic_facts(abc_symbolic_value *value,
                                abc_symbolic_value incoming) {
    if (!value->dynamic_tags || !incoming.dynamic_tags) {
        abc_symbolic_forget_dynamic(value);
        return;
    }
    value->dynamic_tags =
        (uint16_t)(value->dynamic_tags | incoming.dynamic_tags);
    if (value->dynamic_width != incoming.dynamic_width)
        value->dynamic_width = 0;
    if (value->dynamic_repr != incoming.dynamic_repr)
        value->dynamic_repr = ABC_SYM_REPR_UNKNOWN;
    value->zero_extended = value->zero_extended && incoming.zero_extended;
}

static void widen_recursive_key(build_function *function, uint32_t pc,
                                abc_symbolic_context *key) {
    size_t vi;
    unsigned stack;
    uint32_t i;

    for (vi = 0; vi < function->versions.count; vi++) {
        build_version *version = function->versions.items[vi];

        if (version->pc != pc ||
            !abc_symbolic_context_family_equal(
                &version->key, key))
            continue;
        for (stack = 0; stack < 3; stack++) {
            for (i = 0; i < key->n[stack]; i++) {
                abc_symbolic_value *value = &key->s[stack][i];
                abc_symbolic_value prior =
                    version->key.s[stack][i];
                uint8_t width = value->dynamic_width;
                uint8_t representation = value->dynamic_repr;
                uint16_t tags = value->dynamic_tags;

                join_symbolic_facts(value, prior);
                width = value->dynamic_width;
                representation = value->dynamic_repr;
                tags = value->dynamic_tags;
                if (value->kind == ABC_SYM_CONST &&
                    prior.kind == ABC_SYM_CONST &&
                    value->constant == prior.constant)
                    continue;
                *value = abc_symbolic_home(
                    stack, logical_home(key, stack, i));
                value->dynamic_width = width;
                value->dynamic_repr = representation;
                value->dynamic_tags = tags;
            }
        }
    }
}

static size_t family_count(build_function *function, uint32_t pc,
                           const abc_symbolic_context *key) {
    size_t i;
    size_t count = 0;

    for (i = 0; i < function->versions.count; i++) {
        build_version *version = function->versions.items[i];
        if (version->pc == pc &&
            abc_symbolic_context_family_equal(&version->key, key))
            count++;
    }
    return count;
}

static build_version *find_version(build_function *function, uint32_t pc,
                                   const abc_symbolic_context *key) {
    size_t i;

    for (i = 0; i < function->versions.count; i++) {
        build_version *version = function->versions.items[i];
        if (version->pc == pc &&
            abc_symbolic_context_equal(&version->key, key))
            return version;
    }
    return NULL;
}

static int create_version(builder *b, uint32_t pc,
                          const abc_symbolic_context *key,
                          build_version **out) {
    build_version *version = NULL;
    build_block *block = NULL;
    abc_residual_id *arguments = NULL;
    size_t count;
    size_t parameter = 0;
    unsigned stack;
    uint32_t i;

    version = calloc(1, sizeof(*version));
    block = calloc(1, sizeof(*block));
    if (!version || !block) {
        free(version);
        free(block);
        return no_memory(b, pc);
    }
    version->pc = pc;
    version->block = block;
    block->ir.id = next_id(b);
    block->ir.bytecode_offset = pc;
    if (!block->ir.id.value ||
        !abc_symbolic_context_copy(&version->key, key) ||
        !abc_symbolic_context_copy(&version->entry, key))
        goto failed;

    count = parameter_count(key);
    if (count) {
        arguments = abc_residual_allocate(
            b->arena, count, sizeof(*arguments));
        version->homes = calloc(count, sizeof(*version->homes));
        if (!arguments || !version->homes) goto failed;
    }
    version->home_count = count;

    for (stack = 0; stack < 3; stack++) {
        for (i = 0; i < key->n[stack]; i++) {
            abc_symbolic_value source = key->s[stack][i];
            abc_residual_value value;
            abc_residual_id id;
            abc_symbolic_value replacement;

            if (source.kind == ABC_SYM_CONST) continue;
            id = next_id(b);
            if (!id.value) goto failed;
            arguments[parameter] = id;
            memset(&value, 0, sizeof(value));
            value.id = id;
            value.type = symbolic_type(
                b, source, source.dynamic_tags
                    ? ABC_ASDL_RESIDUAL_TYPE_ANY
                    : ABC_ASDL_RESIDUAL_TYPE_CELL);
            value.facts = symbolic_facts(source);
            value.definition.tag =
                ABC_ASDL_RESIDUAL_DEFINITION_BLOCK_ARGUMENT;
            value.definition.value.block_argument.block = block->ir.id;
            value.definition.value.block_argument.index = parameter;
            value.origin = make_origin(pc);
            if (!append_value(b, value)) goto failed;
            version->homes[parameter] = (version_home){
                .stack = (uint8_t)stack,
                .home = logical_home(key, stack, i),
                .value = id
            };
            replacement = symbolic_result(id, stack, value.facts);
            replacement.dst_stack = source.dst_stack;
            replacement.dst_home = source.dst_home;
            version->entry.s[stack][i] = replacement;
            parameter++;
        }
    }

    block->ir.arguments.count = count;
    block->ir.arguments.items = arguments;
    if (!append_block(b, block) || !append_version(b, version))
        goto failed;
    *out = version;
    return 1;

failed:
    abc_symbolic_context_free(&version->key);
    abc_symbolic_context_free(&version->entry);
    free(version->homes);
    free(block);
    free(version);
    if (b->status == ABC_RESIDUAL_BUILD_OK) no_memory(b, pc);
    return 0;
}

static build_version *version_for(builder *b, uint32_t pc,
                                  const abc_symbolic_context *incoming,
                                  version_mode mode) {
    abc_symbolic_context key = {0};
    build_version *version;
    size_t versions;

    if (!abc_symbolic_context_copy(&key, incoming)) {
        no_memory(b, pc);
        return NULL;
    }
    if (mode == VERSION_LOOP_ENTRY) {
        canonicalize(&key, 1);
    } else if (mode == VERSION_VIRTUAL_ENTRY) {
        canonicalize_virtual_entry(b, pc, &key);
    } else {
        canonicalize(&key, 0);
    }
    version = find_version(b->function, pc, &key);
    if (version) {
        abc_symbolic_context_free(&key);
        return version;
    }
    if (mode == VERSION_RECURSIVE) {
        widen_recursive_key(b->function, pc, &key);
        version = find_version(b->function, pc, &key);
        if (version) {
            abc_symbolic_context_free(&key);
            return version;
        }
    }
    versions = family_count(b->function, pc, &key);
    if (versions >= ABC_BLOCK_VERSION_LIMIT - 1) {
        unsigned stack;
        uint32_t i;
        canonicalize(&key, 1);
        for (stack = 0; stack < 3; stack++)
            for (i = 0; i < key.n[stack]; i++)
                abc_symbolic_forget_dynamic(&key.s[stack][i]);
        version = find_version(b->function, pc, &key);
        if (version) {
            abc_symbolic_context_free(&key);
            return version;
        }
    }
    if (!create_version(b, pc, &key, &version))
        version = NULL;
    abc_symbolic_context_free(&key);
    return version;
}

static int make_edge(builder *b, uint32_t origin, uint32_t target_pc,
                     const abc_symbolic_context *incoming,
                     version_mode mode,
                     abc_residual_edge *edge) {
    build_version *target;
    abc_residual_id *arguments = NULL;
    size_t count;
    size_t at = 0;
    unsigned stack;
    uint32_t i;

    target = version_for(b, target_pc, incoming, mode);
    if (!target) return 0;
    count = parameter_count(&target->key);
    if (count) {
        arguments = abc_residual_allocate(
            b->arena, count, sizeof(*arguments));
        if (!arguments) return no_memory(b, origin);
    }

    for (stack = 0; stack < 3; stack++) {
        if (incoming->n[stack] != target->key.n[stack])
            return malformed(b, origin,
                             "edge stack shape differs from target");
        for (i = 0; i < incoming->n[stack]; i++) {
            abc_symbolic_value actual = incoming->s[stack][i];
            abc_symbolic_value formal = target->key.s[stack][i];
            abc_residual_type type;

            if (formal.kind == ABC_SYM_CONST) {
                if (actual.kind != ABC_SYM_CONST ||
                    actual.constant != formal.constant)
                    return malformed(b, origin,
                                     "constant version edge mismatch");
                continue;
            }
            type = symbolic_type(
                b, actual, actual.dynamic_tags
                    ? ABC_ASDL_RESIDUAL_TYPE_ANY
                    : ABC_ASDL_RESIDUAL_TYPE_CELL);
            if (actual.kind == ABC_SYM_CONST) {
                abc_residual_value *formal_value = find_value(
                    b, target->block->ir.arguments.items[at].value);
                if (formal_value) type = formal_value->type;
            }
            arguments[at] = value_id(b, actual, type, origin);
            if (!arguments[at].value) return 0;
            {
                abc_residual_value *actual_value =
                    find_value(b, arguments[at].value);
                abc_residual_value *formal_value =
                    find_value(
                        b, target->block->ir.arguments.items[at].value);

                if (!actual_value || !formal_value)
                    return malformed(
                        b, origin,
                        "edge references an unknown residual value");
                if (!type_compatible(
                        actual_value->type, formal_value->type))
                    return not_supported(
                        b, origin,
                        "edge argument %zu has incompatible residual type %u -> %u",
                        at, (unsigned)actual_value->type,
                        (unsigned)formal_value->type);
            }
            at++;
        }
    }

    edge->target = target->block->ir.id;
    edge->arguments.count = count;
    edge->arguments.items = arguments;
    return 1;
}

static version_mode edge_version_mode(const builder *b,
                                      uint32_t origin,
                                      uint32_t target) {
    if (target <= origin) return VERSION_RECURSIVE;
    if (target < b->module->code_size &&
        b->loop_headers[target])
        return VERSION_LOOP_ENTRY;
    return VERSION_PRESERVE;
}

static int on_control(void *opaque, uint32_t origin,
                      const abc_symbolic_control *control) {
    builder *b = opaque;
    abc_residual_terminator terminator;
    uint32_t target;

    memset(&terminator, 0, sizeof(terminator));
    terminator.origin = make_origin(origin);

    if (control->known ||
        control->kind == ABC_SYM_CONTROL_JUMP) {
        target = control->kind == ABC_SYM_CONTROL_JUMP ||
                         control->taken
            ? control->target
            : control->fallthrough;
        terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_JUMP;
        if (!make_edge(
                b, origin, target, b->machine->context,
                edge_version_mode(b, origin, target),
                &terminator.value.jump.edge))
            return 0;
        return set_terminator(b, terminator);
    }

    if (control->kind == ABC_SYM_CONTROL_SWITCH) {
        const uint8_t *p = b->module->code + origin;
        uint32_t i;

        terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_SWITCH;
        terminator.value.switch_value.value =
            value_id(b, control->left,
                     ABC_ASDL_RESIDUAL_TYPE_CELL, origin);
        if (!terminator.value.switch_value.value.value) return 0;
        terminator.value.switch_value.arms.count = control->count;
        if (control->count) {
            terminator.value.switch_value.arms.items =
                abc_residual_allocate(
                    b->arena, control->count,
                    sizeof(*terminator.value.switch_value.arms.items));
            if (!terminator.value.switch_value.arms.items)
                return no_memory(b, origin);
        }
        if (!make_edge(
                b, origin, control->fallthrough,
                b->machine->context,
                edge_version_mode(
                    b, origin, control->fallthrough),
                &terminator.value.switch_value.fallback))
            return 0;
        for (i = 0; i < control->count; i++) {
            abc_residual_switch_arm *arm =
                &terminator.value.switch_value.arms.items[i];
            uint32_t arm_target = (uint32_t)(
                (int64_t)control->fallthrough +
                abc_i32(p + 3 + 4 * i));

            arm->value_low = i;
            arm->value_high = i;
            if (!make_edge(
                    b, origin, arm_target,
                    b->machine->context,
                    edge_version_mode(b, origin, arm_target),
                    &arm->edge))
                return 0;
        }
        return set_terminator(b, terminator);
    }

    terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_BRANCH;
    switch (control->relation) {
    case ABC_SYM_EQ:
        terminator.value.branch.relation =
            control->kind == ABC_SYM_CONTROL_FLOAT
                ? ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_EQUAL
                : ABC_ASDL_RESIDUAL_BINARY_OP_EQUAL;
        break;
    case ABC_SYM_NE:
        terminator.value.branch.relation =
            ABC_ASDL_RESIDUAL_BINARY_OP_NOT_EQUAL;
        break;
    case ABC_SYM_LT:
        terminator.value.branch.relation =
            control->kind == ABC_SYM_CONTROL_FLOAT
                ? ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_LESS
                : ABC_ASDL_RESIDUAL_BINARY_OP_LESS_SIGNED;
        break;
    case ABC_SYM_LE:
        terminator.value.branch.relation =
            control->kind == ABC_SYM_CONTROL_FLOAT
                ? ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_LESS_EQUAL
                : ABC_ASDL_RESIDUAL_BINARY_OP_LESS_EQUAL_SIGNED;
        break;
    case ABC_SYM_LTU:
        terminator.value.branch.relation =
            ABC_ASDL_RESIDUAL_BINARY_OP_LESS_UNSIGNED;
        break;
    case ABC_SYM_LEU:
        terminator.value.branch.relation =
            ABC_ASDL_RESIDUAL_BINARY_OP_LESS_EQUAL_UNSIGNED;
        break;
    default:
        return malformed(b, origin, "invalid branch relation");
    }

    {
        abc_symbolic_value left = control->left;
        abc_symbolic_value right = control->right;
        abc_residual_type type =
            control->kind == ABC_SYM_CONTROL_FLOAT
                ? ABC_ASDL_RESIDUAL_TYPE_F64
                : ABC_ASDL_RESIDUAL_TYPE_CELL;

        if (control->kind == ABC_SYM_CONTROL_ZERO)
            right = abc_symbolic_constant(0, ABC_SYM_A, 0);
        if (control->reverse) {
            abc_symbolic_value swap = left;
            left = right;
            right = swap;
        }
        terminator.value.branch.left =
            value_id(b, left, type, origin);
        terminator.value.branch.right =
            value_id(b, right, type, origin);
    }
    if (!terminator.value.branch.left.value ||
        !terminator.value.branch.right.value)
        return 0;
    if (!make_edge(
            b, origin, control->target,
            b->machine->context,
            edge_version_mode(b, origin, control->target),
            &terminator.value.branch.yes) ||
        !make_edge(
            b, origin, control->fallthrough,
            b->machine->context,
            edge_version_mode(
                b, origin, control->fallthrough),
            &terminator.value.branch.no))
        return 0;
    return set_terminator(b, terminator);
}

static int on_abort(void *opaque, uint32_t origin, unsigned reason) {
    builder *b = opaque;
    abc_residual_terminator terminator;

    memset(&terminator, 0, sizeof(terminator));
    terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_ABORT;
    terminator.value.abort.reason = reason;
    terminator.origin = make_origin(origin);
    return set_terminator(b, terminator);
}

static int on_halt(void *opaque, uint32_t origin, unsigned unused) {
    builder *b = opaque;
    abc_symbolic_context *context = b->machine->context;
    abc_residual_id values[255];
    abc_residual_terminator terminator;
    uint32_t i;

    if (context->n[ABC_SYM_A] > 255)
        return malformed(b, origin, "HALT has too many result cells");
    for (i = 0; i < context->n[ABC_SYM_A]; i++) {
        abc_symbolic_value value = context->s[ABC_SYM_A][i];

        values[i] = value_id(
            b, value,
            symbolic_type(b, value, ABC_ASDL_RESIDUAL_TYPE_CELL),
            origin);
        if (!values[i].value) return 0;
    }
    memset(&terminator, 0, sizeof(terminator));
    terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_HALT;
    terminator.value.halt.values.count = context->n[ABC_SYM_A];
    terminator.value.halt.values.items =
        copy_ids(b, values, context->n[ABC_SYM_A], origin);
    terminator.origin = make_origin(origin);
    if (context->n[ABC_SYM_A] &&
        !terminator.value.halt.values.items)
        return 0;
    (void)unused;
    return set_terminator(b, terminator);
}

static int on_effect(void *opaque, uint32_t origin, unsigned opcode) {
    builder *b = opaque;

    return not_supported(
        b, origin,
        "internal rewritten opcode %s cannot enter persistent residual IR",
        op_name[opcode]);
}

static abc_residual_id emit_address(builder *b,
                                    abc_asdl_residual_operation_tag tag,
                                    uint64_t offset, uint32_t origin,
                                    abc_symbolic_value *symbolic) {
    abc_residual_operation operation;
    abc_residual_type type = ABC_ASDL_RESIDUAL_TYPE_ADDRESS;

    memset(&operation, 0, sizeof(operation));
    operation.tag = tag;
    if (tag == ABC_ASDL_RESIDUAL_OPERATION_FRAME_ADDRESS)
        operation.value.frame_address.offset = offset;
    else
        operation.value.image_address.offset = offset;
    if (!emit_operation(b, operation, (abc_residual_effect){0},
                        &type, NULL, 1, origin, symbolic, ABC_SYM_A))
        return (abc_residual_id){0};
    return (abc_residual_id){.value = symbolic->reg};
}

static abc_residual_type load_type(builder *b, uint32_t origin,
                                   unsigned width, unsigned sign) {
    if (b->module->load_kinds &&
        b->module->load_kinds[origin])
        return kind_type(b->module->load_kinds[origin] - 1);
    if (width == 4)
        return sign ? ABC_ASDL_RESIDUAL_TYPE_I32
                    : ABC_ASDL_RESIDUAL_TYPE_U32;
    return ABC_ASDL_RESIDUAL_TYPE_CELL;
}

static abc_residual_id emit_index(builder *b, uint32_t origin,
                                  abc_symbolic_value base,
                                  abc_symbolic_value index,
                                  uint64_t scale) {
    abc_symbolic_value scale_value =
        abc_symbolic_constant(scale, ABC_SYM_B, 0);
    abc_symbolic_value scaled;
    abc_symbolic_value address;

    if (!emit_binary(b, origin, ABC_ASDL_RESIDUAL_BINARY_OP_MUL,
                     index, scale_value, ABC_SYM_A, &scaled,
                     ABC_ASDL_RESIDUAL_TYPE_CELL,
                     ABC_ASDL_RESIDUAL_TYPE_CELL,
                     (abc_residual_effect){0}))
        return (abc_residual_id){0};
    if (!emit_binary(b, origin, ABC_ASDL_RESIDUAL_BINARY_OP_ADD,
                     base, scaled, ABC_SYM_A, &address,
                     ABC_ASDL_RESIDUAL_TYPE_CELL,
                     ABC_ASDL_RESIDUAL_TYPE_ADDRESS,
                     (abc_residual_effect){0}))
        return (abc_residual_id){0};
    return (abc_residual_id){.value = address.reg};
}

static int relocation_function(const abc_module *module, uint32_t offset) {
    uint32_t i;

    for (i = 0; i < module->reloc_count; i++)
        if (module->relocs[i].offset == offset)
            return (int)module->relocs[i].function;
    return -1;
}

static int emit_managed_write(builder *b, uint32_t origin,
                              abc_residual_id address,
                              uint64_t offset, uint64_t bytes) {
    abc_residual_operation operation;

    if (!b->module->dynamic_profile || !bytes) return 1;
    memset(&operation, 0, sizeof(operation));
    operation.tag = ABC_ASDL_RESIDUAL_OPERATION_MANAGED_WRITE;
    operation.value.managed_write.address = address;
    operation.value.managed_write.offset = offset;
    operation.value.managed_write.bytes = bytes;
    return emit_operation(
        b, operation,
        (abc_residual_effect){.writes_memory = true},
        NULL, NULL, 0, origin, NULL, ABC_SYM_A);
}

static int on_memory(void *opaque, uint32_t origin,
                     abc_symbolic_memory *memory) {
    builder *b = opaque;
    abc_memory_op metadata = op_memory[memory->opcode];
    const uint8_t *p = b->module->code + origin;
    uint64_t offset = op_len[memory->opcode] == 5
        ? abc_u32(p + 1)
        : op_len[memory->opcode] == 3
            ? abc_u16(p + 1)
            : 0;
    abc_residual_operation operation;
    abc_residual_id address = {0};
    abc_symbolic_value address_value;
    abc_symbolic_value result;
    abc_residual_type type;
    abc_asdl_residual_address_space space;

    if (metadata.action == M_ALLOC) {
        int32_t first =
            b->machine->context->c_bias +
            (int32_t)b->machine->context->n[ABC_SYM_C] -
            b->machine->context->c_origin;

        memset(&operation, 0, sizeof(operation));
        operation.tag = ABC_ASDL_RESIDUAL_OPERATION_CLEAR_FRAME;
        operation.value.clear_frame.first_cell =
            first < 0 ? 0 : (uint64_t)first;
        operation.value.clear_frame.cells = memory->cells;
        return emit_operation(
            b, operation,
            (abc_residual_effect){.writes_memory = true},
            NULL, NULL, 0, origin, NULL, ABC_SYM_C);
    }
    if (metadata.action == M_FREE) return 1;

    if (metadata.action == M_GLOAD &&
        metadata.width == 8) {
        int function = relocation_function(b->module, (uint32_t)offset);

        if (function >= 0) {
            memset(&operation, 0, sizeof(operation));
            operation.tag =
                ABC_ASDL_RESIDUAL_OPERATION_FUNCTION_REFERENCE;
            operation.value.function_reference.function =
                b->function_ids[function];
            type = ABC_ASDL_RESIDUAL_TYPE_ADDRESS;
            if (!emit_operation(
                    b, operation, (abc_residual_effect){0},
                    &type, NULL, 1, origin, &result, memory->stack))
                return 0;
            memory->result = result;
            return 1;
        }
    }

    if (metadata.action == M_FLOAD ||
        metadata.action == M_FSTORE ||
        metadata.action == M_FADDR) {
        int64_t frame_top = (
            b->machine->context->c_bias +
            (int32_t)b->machine->context->n[ABC_SYM_C] -
            b->machine->context->c_origin) * 8;
        uint64_t frame_offset = (uint64_t)(
            frame_top - (int64_t)offset);
        address = emit_address(
            b, ABC_ASDL_RESIDUAL_OPERATION_FRAME_ADDRESS,
            frame_offset, origin, &address_value);
    } else if (metadata.action == M_GLOAD ||
               metadata.action == M_GSTORE ||
               metadata.action == M_GADDR) {
        address = emit_address(
            b, ABC_ASDL_RESIDUAL_OPERATION_IMAGE_ADDRESS,
            offset, origin, &address_value);
    } else if (metadata.action == M_PLOAD ||
               metadata.action == M_PSTORE) {
        address = value_id(
            b, memory->first,
            ABC_ASDL_RESIDUAL_TYPE_ADDRESS, origin);
    } else if (metadata.action == M_XLOAD ||
               metadata.action == M_INDEX) {
        uint64_t scale = metadata.action == M_INDEX
            ? abc_u16(p + 1)
            : metadata.width;
        address = emit_index(
            b, origin, memory->first, memory->second, scale);
    } else if (metadata.action == M_COPY) {
        abc_residual_id destination = value_id(
            b, memory->first, ABC_ASDL_RESIDUAL_TYPE_ADDRESS, origin);
        abc_residual_id source = value_id(
            b, memory->second, ABC_ASDL_RESIDUAL_TYPE_ADDRESS, origin);
        uint64_t bytes = abc_u32(p + 1);

        if (!destination.value || !source.value) return 0;
        memset(&operation, 0, sizeof(operation));
        operation.tag = ABC_ASDL_RESIDUAL_OPERATION_COPY_MEMORY;
        operation.value.copy_memory.destination = destination;
        operation.value.copy_memory.source = source;
        operation.value.copy_memory.bytes = bytes;
        if (!emit_operation(
                b, operation,
                (abc_residual_effect){
                    .reads_memory = true,
                    .writes_memory = true
                },
                NULL, NULL, 0, origin, NULL, ABC_SYM_A))
            return 0;
        return emit_managed_write(b, origin, destination, 0, bytes);
    } else {
        return malformed(b, origin, "unknown memory action");
    }

    if (!address.value) return 0;
    if (metadata.action == M_FADDR ||
        metadata.action == M_GADDR ||
        metadata.action == M_INDEX) {
        memory->result = symbolic_result(
            address,
            metadata.action == M_INDEX ? ABC_SYM_A : memory->stack,
            (abc_residual_facts){0});
        return 1;
    }

    space = metadata.action == M_FLOAD ||
                    metadata.action == M_FSTORE
        ? ABC_ASDL_RESIDUAL_ADDRESS_SPACE_FRAME
        : metadata.action == M_GLOAD ||
                  metadata.action == M_GSTORE
            ? ABC_ASDL_RESIDUAL_ADDRESS_SPACE_IMAGE
            : ABC_ASDL_RESIDUAL_ADDRESS_SPACE_POINTER;

    if (metadata.action == M_FLOAD ||
        metadata.action == M_GLOAD ||
        metadata.action == M_PLOAD ||
        metadata.action == M_XLOAD) {
        memset(&operation, 0, sizeof(operation));
        operation.tag = ABC_ASDL_RESIDUAL_OPERATION_LOAD;
        operation.value.load.space = space;
        operation.value.load.width = metadata.width;
        operation.value.load.signed_value = metadata.sign != 0;
        operation.value.load.address = address;
        operation.value.load.offset =
            metadata.action == M_PLOAD ? offset : 0;
        type = load_type(b, origin, metadata.width, metadata.sign);
        if (!emit_operation(
                b, operation,
                (abc_residual_effect){.reads_memory = true},
                &type, NULL, 1, origin, &result, memory->stack))
            return 0;
        memory->result = result;
        return 1;
    }

    {
        abc_symbolic_value stored =
            metadata.action == M_PSTORE
                ? memory->second
                : memory->first;
        abc_residual_id stored_id = value_id(
            b, stored,
            symbolic_type(b, stored, ABC_ASDL_RESIDUAL_TYPE_CELL),
            origin);
        uint64_t store_offset =
            metadata.action == M_PSTORE ? offset : 0;

        if (!stored_id.value) return 0;
        memset(&operation, 0, sizeof(operation));
        operation.tag = ABC_ASDL_RESIDUAL_OPERATION_STORE;
        operation.value.store.space = space;
        operation.value.store.width = metadata.width;
        operation.value.store.address = address;
        operation.value.store.offset = store_offset;
        operation.value.store.value = stored_id;
        if (!emit_operation(
                b, operation,
                (abc_residual_effect){.writes_memory = true},
                NULL, NULL, 0, origin, NULL, ABC_SYM_A))
            return 0;
        if (metadata.action == M_PSTORE)
            return emit_managed_write(
                b, origin, address, store_offset, metadata.width);
        return 1;
    }
}

static abc_residual_type dynamic_result_type(
    builder *b, const abc_symbolic_dynamic *dynamic, unsigned index) {
    unsigned selector = dynamic->selector;

    if (selector == EXT_ANY_CAST) {
        const abc_descriptor *descriptor =
            &b->module->descriptors[dynamic->descriptor];

        if (descriptor->tag == ABC_DESC_PRIMITIVE) {
            unsigned primitive = descriptor->payload[0];
            if (primitive == ABC_PRIM_F64)
                return ABC_ASDL_RESIDUAL_TYPE_F64;
            if (primitive == ABC_PRIM_ANY ||
                primitive == ABC_PRIM_WORD)
                return ABC_ASDL_RESIDUAL_TYPE_ANY;
            if (primitive == ABC_PRIM_STRING)
                return index
                    ? ABC_ASDL_RESIDUAL_TYPE_CELL
                    : ABC_ASDL_RESIDUAL_TYPE_ADDRESS;
            return ABC_ASDL_RESIDUAL_TYPE_CELL;
        }
        if (descriptor->tag == ABC_DESC_SLICE)
            return index
                ? ABC_ASDL_RESIDUAL_TYPE_CELL
                : ABC_ASDL_RESIDUAL_TYPE_ADDRESS;
        return ABC_ASDL_RESIDUAL_TYPE_ADDRESS;
    }
    if (selector == EXT_ANY_IS ||
        selector == EXT_DEQ || selector == EXT_DNE ||
        selector == EXT_DLT || selector == EXT_DLE ||
        selector == EXT_DREQUIRE_BOOL ||
        selector == EXT_WORD_HAS ||
        selector == EXT_WORD_COUNT)
        return ABC_ASDL_RESIDUAL_TYPE_CELL;
    if (selector == EXT_MANAGED_NEW ||
        selector == EXT_MANAGED_COPY)
        return ABC_ASDL_RESIDUAL_TYPE_ADDRESS;
    return ABC_ASDL_RESIDUAL_TYPE_ANY;
}

static int on_dynamic(void *opaque, uint32_t origin,
                      abc_symbolic_dynamic *dynamic) {
    builder *b = opaque;
    abc_symbolic_context *context = b->machine->context;
    const uint8_t *instruction = b->module->code + origin;
    abc_residual_id arguments[255];
    abc_residual_type types[255];
    abc_residual_facts facts[255];
    abc_residual_operation operation;
    abc_residual_terminator terminator;
    uint32_t base;
    unsigned i;

    if (context->n[ABC_SYM_A] < dynamic->pops)
        return malformed(b, origin,
                         "dynamic operation underflows symbolic A");
    base = context->n[ABC_SYM_A] - dynamic->pops;
    for (i = 0; i < dynamic->pops; i++) {
        abc_symbolic_value value = context->s[ABC_SYM_A][base + i];
        arguments[i] = value_id(
            b, value, symbolic_type(
                b, value, ABC_ASDL_RESIDUAL_TYPE_ANY), origin);
        if (!arguments[i].value) return 0;
    }
    for (i = 0; i < dynamic->pushes; i++) {
        types[i] = dynamic_result_type(b, dynamic, i);
        facts[i] = symbolic_facts(dynamic->result[i]);
    }

    if (dynamic->selector == EXT_WORD_DIRECT ||
        dynamic->selector == EXT_CLOSURE_NEW) {
        uint32_t target_entry = abc_u32(instruction + 2);
        int target_function = target_entry < b->module->function_count
            ? (int)target_entry : abc_find_function(b->module, target_entry);
        uint32_t target;
        uint32_t descriptor = dynamic->descriptor;
        uint32_t signature = descriptor;
        abc_residual_id *environment = NULL;

        if (target_function < 0) goto generic_dynamic;
        target = (uint32_t)target_function;
        if (dynamic->selector == EXT_CLOSURE_NEW) {
            const abc_descriptor *closure =
                &b->module->descriptors[descriptor];

            if (closure->tag != ABC_DESC_CLOSURE ||
                dynamic->pops != 1)
                goto generic_dynamic;
            signature = abc_u32(closure->payload);
            environment = abc_residual_allocate(
                b->arena, 1, sizeof(*environment));
            if (!environment) return no_memory(b, origin);
            *environment = arguments[0];
        } else if (dynamic->direct_environment || dynamic->pops) {
            goto generic_dynamic;
        }

        memset(&operation, 0, sizeof(operation));
        operation.tag =
            ABC_ASDL_RESIDUAL_OPERATION_CALLABLE_CONSTRUCTOR;
        operation.value.callable_constructor.target =
            b->function_ids[target];
        operation.value.callable_constructor.signature = signature;
        operation.value.callable_constructor.descriptor = descriptor;
        operation.value.callable_constructor.environment_cells =
            dynamic->selector == EXT_CLOSURE_NEW ? 1 : 0;
        operation.value.callable_constructor.environment = environment;
        return emit_operation(
            b, operation,
            (abc_residual_effect){.safepoint = true},
            types, facts, dynamic->pushes, origin,
            dynamic->result, ABC_SYM_A);
    }

    if (dynamic->selector == EXT_DCALL ||
        dynamic->selector == EXT_DTCALL) {
        abc_asdl_residual_call_abi abi = {
            .arguments = instruction[2],
            .results = instruction[3],
            .frame_cells = 0,
            .hidden_result_bytes = 0
        };
        uint64_t adjustment = instruction[4];

        if (dynamic->pops != abi.arguments + 1)
            return malformed(b, origin,
                             "dynamic call metadata disagrees with its operands");
        if (dynamic->tail) {
            memset(&terminator, 0, sizeof(terminator));
            terminator.tag =
                ABC_ASDL_RESIDUAL_TERMINATOR_DYNAMIC_TAIL_CALL;
            terminator.value.dynamic_tail_call.abi = abi;
            terminator.value.dynamic_tail_call.adjustment = adjustment;
            terminator.value.dynamic_tail_call.arguments.count =
                dynamic->pops;
            terminator.value.dynamic_tail_call.arguments.items =
                copy_ids(b, arguments, dynamic->pops, origin);
            terminator.origin = make_origin(origin);
            if (dynamic->pops &&
                !terminator.value.dynamic_tail_call.arguments.items)
                return 0;
            return set_terminator(b, terminator);
        }

        memset(&operation, 0, sizeof(operation));
        operation.tag = ABC_ASDL_RESIDUAL_OPERATION_DYNAMIC_CALL;
        operation.value.dynamic_call.abi = abi;
        operation.value.dynamic_call.adjustment = adjustment;
        operation.value.dynamic_call.arguments.count = dynamic->pops;
        operation.value.dynamic_call.arguments.items =
            copy_ids(b, arguments, dynamic->pops, origin);
        if (dynamic->pops &&
            !operation.value.dynamic_call.arguments.items)
            return 0;
        return emit_operation(
            b, operation,
            (abc_residual_effect){
                .may_trap = true,
                .calls = true,
                .safepoint = true
            },
            types, facts, dynamic->pushes, origin,
            dynamic->result, ABC_SYM_A);
    }

generic_dynamic:
    memset(&operation, 0, sizeof(operation));
    operation.tag = ABC_ASDL_RESIDUAL_OPERATION_DYNAMIC_OPERATION;
    operation.value.dynamic_operation.selector = dynamic->selector;
    operation.value.dynamic_operation.descriptor = dynamic->descriptor;
    if (dynamic->selector >= EXT_DADDL &&
        dynamic->selector <= EXT_DXORL) {
        uint32_t constant_index = abc_u32(instruction + 2);
        const abc_dynamic_constant *constant;
        abc_asdl_residual_dynamic_literal *literal;
        size_t low_bytes;
        size_t high_bytes;

        if (constant_index >= b->module->dynamic_constant_count)
            return malformed(b, origin,
                             "dynamic literal index is invalid");
        constant = &b->module->dynamic_constants[constant_index];
        literal = abc_residual_allocate(
            b->arena, 1, sizeof(*literal));
        if (!literal) return no_memory(b, origin);
        memset(literal, 0, sizeof(*literal));
        literal->primitive = constant->kind;
        literal->flags = constant->flags;
        low_bytes = constant->length < 8 ? constant->length : 8;
        high_bytes = constant->length > 8
            ? constant->length - 8 : 0;
        if (high_bytes > 8) high_bytes = 8;
        if (low_bytes)
            memcpy(&literal->low, constant->payload, low_bytes);
        if (high_bytes)
            memcpy(&literal->high, constant->payload + 8, high_bytes);
        operation.value.dynamic_operation.literal = literal;
        operation.value.dynamic_operation.reverse =
            instruction[6] != 0;
    }
    operation.value.dynamic_operation.arguments.count = dynamic->pops;
    operation.value.dynamic_operation.arguments.items =
        copy_ids(b, arguments, dynamic->pops, origin);
    if (dynamic->pops &&
        !operation.value.dynamic_operation.arguments.items)
        return 0;
    return emit_operation(
        b, operation,
        (abc_residual_effect){
            .may_trap = true,
            .calls = true,
            .safepoint = true
        },
        types, facts, dynamic->pushes, origin,
        dynamic->result, ABC_SYM_A);
}

static int append_call_fact(builder *b, uint32_t target, unsigned count,
                            const abc_symbolic_value *values,
                            uint32_t origin) {
    call_vector *calls = &b->function->calls;
    abc_residual_argument_fact *facts = NULL;
    unsigned i;

    if (!grow((void **)&calls->items, &calls->capacity,
              calls->count + 1, sizeof(*calls->items)))
        return no_memory(b, origin);
    if (count) {
        facts = abc_residual_allocate(
            b->arena, count, sizeof(*facts));
        if (!facts) return no_memory(b, origin);
    }
    for (i = 0; i < count; i++)
        facts[i] = abc_residual_analysis_argument_fact(values[i]);
    calls->items[calls->count++] = (abc_residual_call){
        .target = target,
        .arguments = count,
        .facts = facts
    };
    return 1;
}

static int on_foreign(void *opaque, uint32_t origin,
                      abc_symbolic_foreign *foreign) {
    builder *b = opaque;
    abc_symbolic_context *context = b->machine->context;
    const abc_extern *external =
        &b->module->externs[foreign->index];
    abc_residual_id arguments[255];
    abc_residual_operation operation;
    abc_residual_type type;
    uint32_t base = context->n[ABC_SYM_A] - foreign->arguments;
    unsigned i;

    for (i = 0; i < foreign->arguments; i++) {
        arguments[i] = value_id(
            b, context->s[ABC_SYM_A][base + i],
            kind_type(external->argument_kinds[i]), origin);
        if (!arguments[i].value) return 0;
    }
    memset(&operation, 0, sizeof(operation));
    operation.tag = ABC_ASDL_RESIDUAL_OPERATION_CALL;
    operation.value.call.kind =
        ABC_ASDL_RESIDUAL_CALL_KIND_FOREIGN;
    operation.value.call.target = foreign->index;
    operation.value.call.abi = (abc_asdl_residual_call_abi){
        .arguments = foreign->arguments,
        .results = foreign->results,
        .frame_cells = 0,
        .hidden_result_bytes = 0
    };
    operation.value.call.arguments.count = foreign->arguments;
    operation.value.call.arguments.items =
        copy_ids(b, arguments, foreign->arguments, origin);
    if (foreign->arguments &&
        !operation.value.call.arguments.items)
        return 0;
    type = foreign->results
        ? kind_type(external->result_kinds[0])
        : ABC_ASDL_RESIDUAL_TYPE_CELL;
    return emit_operation(
        b, operation,
        (abc_residual_effect){.calls = true, .safepoint = true},
        foreign->results ? &type : NULL, NULL,
        foreign->results, origin, foreign->result, ABC_SYM_A);
}

static int on_call(void *opaque, uint32_t origin,
                   abc_symbolic_call *call) {
    builder *b = opaque;
    abc_symbolic_context *context = b->machine->context;
    int target_index = abc_find_function(b->module, call->target);
    const abc_function *target;
    abc_residual_id arguments[255];
    abc_residual_type types[255];
    abc_residual_operation operation;
    uint32_t base;
    unsigned i;

    if (target_index < 0)
        return malformed(b, origin,
                         "direct call target is not a source function");
    target = &b->module->functions[target_index];
    base = context->n[ABC_SYM_A] - call->arguments;
    for (i = 0; i < call->arguments; i++) {
        arguments[i] = value_id(
            b, context->s[ABC_SYM_A][base + i],
            kind_type(target->argument_kinds[i]), origin);
        if (!arguments[i].value) return 0;
    }
    for (i = 0; i < call->results; i++)
        types[i] = kind_type(target->result_kinds[i]);
    if (!append_call_fact(
            b, (uint32_t)target_index, call->arguments,
            context->s[ABC_SYM_A] + base, origin))
        return 0;

    memset(&operation, 0, sizeof(operation));
    operation.tag = ABC_ASDL_RESIDUAL_OPERATION_CALL;
    operation.value.call.kind =
        ABC_ASDL_RESIDUAL_CALL_KIND_DIRECT;
    operation.value.call.target =
        b->function_ids[target_index].value;
    operation.value.call.abi = (abc_asdl_residual_call_abi){
        .arguments = call->arguments,
        .results = call->results,
        .frame_cells = (uint64_t)(b->machine->context->c_bias +
            (int32_t)b->machine->context->n[ABC_SYM_C] -
            b->machine->context->c_origin),
        .hidden_result_bytes = target->hidden_bytes
    };
    operation.value.call.arguments.count = call->arguments;
    operation.value.call.arguments.items =
        copy_ids(b, arguments, call->arguments, origin);
    if (call->arguments &&
        !operation.value.call.arguments.items)
        return 0;

    call->virtualize = 0;
    return emit_operation(
        b, operation,
        (abc_residual_effect){
            .calls = true,
            .safepoint = !target->allocation_free
        },
        types, NULL, call->results, origin,
        call->result, call->destination);
}

static int on_indirect(void *opaque, uint32_t origin,
                       abc_symbolic_indirect *call) {
    builder *b = opaque;
    abc_symbolic_context *context = b->machine->context;
    const abc_function *site = abc_find_site(b->module, origin);
    abc_residual_id arguments[255];
    abc_residual_type types[255];
    abc_residual_id callee;
    abc_residual_id *callee_slot;
    abc_residual_operation operation;
    abc_residual_terminator terminator;
    uint32_t base;
    unsigned i;

    if (!site)
        return malformed(b, origin,
                         "indirect call lacks site metadata");
    base = context->n[ABC_SYM_A] - call->arguments;
    for (i = 0; i < call->arguments; i++) {
        arguments[i] = value_id(
            b, context->s[ABC_SYM_A][base + i],
            kind_type(site->argument_kinds[i]), origin);
        if (!arguments[i].value) return 0;
    }
    for (i = 0; i < call->results; i++)
        types[i] = kind_type(site->result_kinds[i]);
    callee = value_id(
        b, call->target, ABC_ASDL_RESIDUAL_TYPE_ADDRESS, origin);
    if (!callee.value) return 0;
    callee_slot = abc_residual_allocate(
        b->arena, 1, sizeof(*callee_slot));
    if (!callee_slot) return no_memory(b, origin);
    *callee_slot = callee;

    if (call->tail) {
        memset(&terminator, 0, sizeof(terminator));
        terminator.tag =
            ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL;
        terminator.value.tail_call.kind =
            ABC_ASDL_RESIDUAL_CALL_KIND_INDIRECT;
        terminator.value.tail_call.callee = callee_slot;
        terminator.value.tail_call.abi =
            (abc_asdl_residual_call_abi){
                .arguments = call->arguments,
                .results = call->results,
                .frame_cells = call->frame_cells,
                .hidden_result_bytes = site->hidden_bytes
            };
        terminator.value.tail_call.arguments.count = call->arguments;
        terminator.value.tail_call.arguments.items =
            copy_ids(b, arguments, call->arguments, origin);
        terminator.origin = make_origin(origin);
        if (call->arguments &&
            !terminator.value.tail_call.arguments.items)
            return 0;
        return set_terminator(b, terminator);
    }

    memset(&operation, 0, sizeof(operation));
    operation.tag = ABC_ASDL_RESIDUAL_OPERATION_CALL;
    operation.value.call.kind =
        ABC_ASDL_RESIDUAL_CALL_KIND_INDIRECT;
    operation.value.call.callee = callee_slot;
    operation.value.call.abi = (abc_asdl_residual_call_abi){
        .arguments = call->arguments,
        .results = call->results,
        .frame_cells = (uint64_t)(b->machine->context->c_bias +
            (int32_t)b->machine->context->n[ABC_SYM_C] -
            b->machine->context->c_origin),
        .hidden_result_bytes = site->hidden_bytes
    };
    operation.value.call.arguments.count = call->arguments;
    operation.value.call.arguments.items =
        copy_ids(b, arguments, call->arguments, origin);
    if (call->arguments &&
        !operation.value.call.arguments.items)
        return 0;
    return emit_operation(
        b, operation,
        (abc_residual_effect){.calls = true, .safepoint = true},
        types, NULL, call->results, origin,
        call->result, call->destination);
}

static void mark_embedded_component(builder *b, uint32_t member) {
    uint32_t component = b->graph->component[member];
    uint32_t i;

    for (i = 0; i < b->module->function_count; i++)
        if (b->graph->component[i] == component)
            b->embedded[i] = 1;
}

static int component_is_mutual(
    const builder *b, uint32_t function) {
    uint32_t component = b->graph->component[function];
    size_t count = 0;
    size_t i;

    for (i = 0; i < b->module->function_count; i++)
        if (b->graph->component[i] == component) count++;
    return count > 1;
}

static int on_tail(void *opaque, uint32_t origin,
                   abc_symbolic_tail *tail) {
    builder *b = opaque;
    abc_symbolic_context *context = b->machine->context;
    int target_index = abc_find_function(b->module, tail->target);
    const abc_function *target;
    abc_residual_id arguments[255];
    abc_residual_terminator terminator;
    uint32_t base;
    unsigned i;

    if (target_index < 0)
        return malformed(b, origin,
                         "tail target is not a source function");

    target = &b->module->functions[target_index];
    base = context->n[ABC_SYM_A] - tail->arguments;
    if (!target->hidden_bytes) {
        int first_arrival = !b->embedded[target_index];

        if (first_arrival &&
            (!b->graph->recursive[target_index] ||
             b->graph->nested_eligible[target_index]) &&
            !component_is_mutual(b, (uint32_t)target_index))
            mark_embedded_component(
                b, (uint32_t)target_index);
        if (b->embedded[target_index]) {
            abc_residual_source_function *metadata =
                &b->bundle->source_functions[b->source_function];
            if (target->max_a > metadata->max_a) metadata->max_a = target->max_a;
            if (target->max_b > metadata->max_b) metadata->max_b = target->max_b;
            if (target->max_c > metadata->max_c) metadata->max_c = target->max_c;
            if (!append_call_fact(
                    b, (uint32_t)target_index, tail->arguments,
                    context->s[ABC_SYM_A] + base, origin))
                return 0;
            b->pending_edge = 1;
            b->pending_edge_target = tail->target;
            b->pending_edge_mode = first_arrival
                ? VERSION_VIRTUAL_ENTRY : VERSION_RECURSIVE;
            tail->residualize = 0;
            return 1;
        }
    }
    for (i = 0; i < tail->arguments; i++) {
        arguments[i] = value_id(
            b, context->s[ABC_SYM_A][base + i],
            kind_type(target->argument_kinds[i]), origin);
        if (!arguments[i].value) return 0;
    }
    if (!append_call_fact(
            b, (uint32_t)target_index, tail->arguments,
            context->s[ABC_SYM_A] + base, origin))
        return 0;

    memset(&terminator, 0, sizeof(terminator));
    terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL;
    terminator.value.tail_call.kind =
        ABC_ASDL_RESIDUAL_CALL_KIND_DIRECT;
    terminator.value.tail_call.target =
        b->function_ids[target_index].value;
    terminator.value.tail_call.abi =
        (abc_asdl_residual_call_abi){
            .arguments = tail->arguments,
            .results = target->results,
            .frame_cells = tail->frame_cells,
            .hidden_result_bytes = target->hidden_bytes
        };
    terminator.value.tail_call.arguments.count = tail->arguments;
    terminator.value.tail_call.arguments.items =
        copy_ids(b, arguments, tail->arguments, origin);
    terminator.origin = make_origin(origin);
    if (tail->arguments &&
        !terminator.value.tail_call.arguments.items)
        return 0;
    if (!set_terminator(b, terminator)) return 0;
    tail->residualize = 1;
    return 1;
}

static int on_return(void *opaque, uint32_t origin,
                     const abc_symbolic_return *returned) {
    builder *b = opaque;
    abc_symbolic_context *context = b->machine->context;
    const abc_function *source =
        &b->module->functions[b->source_function];
    abc_residual_id values[255];
    abc_residual_terminator terminator;
    unsigned i;

    if (!returned->terminal)
        return malformed(
            b, origin,
            "nonterminal return reached nonvirtual residual call lowering");
    for (i = 0; i < returned->results; i++) {
        abc_residual_type expected =
            kind_type(source->result_kinds[i]);
        abc_residual_value *actual;

        values[i] = value_id(
            b, context->s[ABC_SYM_A][i], expected, origin);
        if (!values[i].value) return 0;
        actual = find_value(b, values[i].value);
        if (actual && actual->type == ABC_ASDL_RESIDUAL_TYPE_CELL &&
            expected == ABC_ASDL_RESIDUAL_TYPE_ADDRESS) {
            abc_symbolic_value zero = abc_symbolic_constant(0, ABC_SYM_B, 0);
            abc_residual_id zero_id = add_constant(
                b, zero, ABC_ASDL_RESIDUAL_TYPE_CELL, origin);
            abc_residual_operation cast = {0};
            abc_symbolic_value cast_result;
            if (!zero_id.value) return 0;
            cast.tag = ABC_ASDL_RESIDUAL_OPERATION_BINARY;
            cast.value.binary.operation = ABC_ASDL_RESIDUAL_BINARY_OP_ADD;
            cast.value.binary.left = values[i];
            cast.value.binary.right = zero_id;
            if (!emit_operation(b, cast, (abc_residual_effect){0},
                    &expected, NULL, 1, origin, &cast_result, ABC_SYM_A))
                return 0;
            values[i] = (abc_residual_id){cast_result.reg};
            actual = find_value(b, values[i].value);
        }
        if (!actual || !type_compatible(actual->type, expected))
            return not_supported(
                b, origin,
                "return value %u has incompatible residual type %u -> %u", i,
                actual ? (unsigned)actual->type : UINT_MAX,
                (unsigned)expected);
    }
    memset(&terminator, 0, sizeof(terminator));
    terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_RETURN;
    terminator.value.return_value.abi =
        (abc_asdl_residual_call_abi){
            .arguments = source->arguments,
            .results = returned->results,
            .frame_cells = returned->frame_cells,
            .hidden_result_bytes = source->hidden_bytes
        };
    terminator.value.return_value.values.count = returned->results;
    terminator.value.return_value.values.items =
        copy_ids(b, values, returned->results, origin);
    terminator.origin = make_origin(origin);
    if (returned->results &&
        !terminator.value.return_value.values.items)
        return 0;
    return set_terminator(b, terminator);
}

static int on_edge(void *opaque, uint32_t origin, uint32_t target) {
    builder *b = opaque;
    abc_residual_terminator terminator;
    version_mode mode =
        edge_version_mode(b, origin, target);

    if (b->pending_edge) {
        if (target != b->pending_edge_target)
            return malformed(
                b, origin,
                "virtual tail edge target does not match its transfer");
        mode = b->pending_edge_mode;
        b->pending_edge = 0;
    }

    memset(&terminator, 0, sizeof(terminator));
    terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_JUMP;
    terminator.origin = make_origin(origin);
    if (!make_edge(
            b, origin, target, b->machine->context, mode,
            &terminator.value.jump.edge))
        return 0;
    return set_terminator(b, terminator);
}

static int source_function_containing(
    const abc_module *module, uint32_t pc) {
    uint32_t i;

    for (i = 0; i < module->function_count; i++)
        if (pc >= module->functions[i].entry &&
            pc < module->functions[i].end)
            return (int)i;
    return -1;
}

static int discover_leaders(builder *b) {
    uint32_t fi;

    b->leaders = calloc(
        b->module->code_size ? b->module->code_size : 1, 1);
    b->loop_headers = calloc(
        b->module->code_size ? b->module->code_size : 1, 1);
    if (!b->leaders || !b->loop_headers)
        return no_memory(b, UINT32_MAX);

    for (fi = 0; fi < b->module->function_count; fi++) {
        const abc_function *function = &b->module->functions[fi];
        uint32_t pc;

        b->leaders[function->entry] = 1;
        for (pc = function->entry; pc < function->end;) {
            const uint8_t *p = b->module->code + pc;
            unsigned kind = op_kind[p[0]];
            uint32_t next = pc + abc_instruction_length(p);

            if (kind == K_BRANCH || kind == K_BRI ||
                kind == K_JMP32) {
                int32_t displacement = kind == K_JMP32
                    ? abc_i32(p + 1)
                    : abc_i16(p + (kind == K_BRI ? 2 : 1));
                uint32_t target =
                    (uint32_t)((int64_t)next + displacement);
                b->leaders[target] = 1;
                if (target <= pc)
                    b->loop_headers[target] = 1;
                if (p[0] != OP_JMP && p[0] != OP_JMP32 &&
                    next < function->end)
                    b->leaders[next] = 1;
            } else if (kind == K_SWITCH) {
                unsigned count = abc_u16(p + 1);
                unsigned i;

                for (i = 0; i < count; i++) {
                    uint32_t target = (uint32_t)(
                        (int64_t)next +
                        abc_i32(p + 3 + 4 * i));
                    b->leaders[target] = 1;
                    if (target <= pc)
                        b->loop_headers[target] = 1;
                }
                if (next < function->end)
                    b->leaders[next] = 1;
            } else if (kind == K_TCALL) {
                uint32_t target;
                int target_function;

                if (abc_residual_analysis_direct_target(
                        b->module, pc, &target)) {
                    target_function =
                        abc_find_function(b->module, target);
                    if (target_function == (int)fi &&
                        target <= pc)
                        b->loop_headers[target] = 1;
                }
            }
            pc = next;
        }
    }
    return 1;
}

static int initialize_function(builder *b, uint32_t fi) {
    build_function *function = &b->functions[fi];
    const abc_function *source = &b->module->functions[fi];
    char name[32];
    uint32_t i;

    memset(function, 0, sizeof(*function));
    function->value_start = b->values.count;
    function->ir.id = b->function_ids[fi];
    snprintf(name, sizeof(name), "function_%u", fi);
    function->ir.name = abc_residual_string(b->arena, name);
    if (!function->ir.name.data) return no_memory(b, source->entry);

    function->ir.argument_types.count = source->arguments;
    function->ir.result_types.count = source->results;
    function->ir.hidden_result_bytes = source->hidden_bytes;
    function->ir.arguments.count = source->arguments;
    if (source->arguments) {
        function->ir.argument_types.items = abc_residual_allocate(
            b->arena, source->arguments,
            sizeof(*function->ir.argument_types.items));
        function->ir.arguments.items = abc_residual_allocate(
            b->arena, source->arguments,
            sizeof(*function->ir.arguments.items));
        if (!function->ir.argument_types.items ||
            !function->ir.arguments.items)
            return no_memory(b, source->entry);
    }
    if (source->results) {
        function->ir.result_types.items = abc_residual_allocate(
            b->arena, source->results,
            sizeof(*function->ir.result_types.items));
        if (!function->ir.result_types.items)
            return no_memory(b, source->entry);
    }

    for (i = 0; i < source->arguments; i++) {
        abc_residual_value value;
        abc_residual_id id = next_id(b);

        if (!id.value) return 0;
        function->ir.argument_types.items[i] =
            kind_type(source->argument_kinds[i]);
        function->ir.arguments.items[i] = id;
        memset(&value, 0, sizeof(value));
        value.id = id;
        value.type = function->ir.argument_types.items[i];
        value.definition.tag =
            ABC_ASDL_RESIDUAL_DEFINITION_FUNCTION_ARGUMENT;
        value.definition.value.function_argument.index = i;
        value.origin = make_origin(source->entry);
        if (!append_value(b, value)) return 0;
    }
    for (i = 0; i < source->results; i++)
        function->ir.result_types.items[i] =
            kind_type(source->result_kinds[i]);
    return 1;
}

static int initial_context(builder *b, uint32_t fi,
                           abc_symbolic_context *context) {
    const abc_function *source = &b->module->functions[fi];
    const abc_residual_argument_fact *facts = NULL;
    uint32_t i;

    if (b->options && b->options->argument_facts)
        facts = b->options->argument_facts[fi];
    context->c_origin = (int32_t)source->arguments;

    for (i = 0; i < source->arguments; i++) {
        abc_symbolic_value value;

        if (facts &&
            facts[i].kind == ABC_RESIDUAL_FACT_CONSTANT) {
            value = abc_symbolic_constant(
                facts[i].constant, ABC_SYM_C,
                -1 - (int32_t)i);
        } else {
            value = abc_symbolic_backend(
                (uint32_t)b->function->ir.arguments.items[i].value,
                ABC_SYM_C, -1 - (int32_t)i);
        }
        if (!abc_symbolic_push(context, ABC_SYM_C, value))
            return no_memory(b, source->entry);
    }
    for (i = 0; i < source->arguments / 2; i++) {
        abc_symbolic_value swap = context->s[ABC_SYM_C][i];
        context->s[ABC_SYM_C][i] =
            context->s[ABC_SYM_C][source->arguments - 1 - i];
        context->s[ABC_SYM_C][source->arguments - 1 - i] = swap;
    }
    return 1;
}

static int make_entry(builder *b, abc_symbolic_context *context) {
    const abc_function *source =
        &b->module->functions[b->source_function];
    build_block *entry = calloc(1, sizeof(*entry));
    build_version *target;
    abc_residual_terminator terminator;

    if (!entry) return no_memory(b, source->entry);
    entry->ir.id = next_id(b);
    entry->ir.bytecode_offset = source->entry;
    if (!entry->ir.id.value) {
        free(entry);
        return 0;
    }
    if (!append_block(b, entry)) {
        free(entry);
        return 0;
    }
    b->function->ir.entry = entry->ir.id;
    target = version_for(
        b, source->entry, context, VERSION_PRESERVE);
    if (!target) return 0;

    b->block = entry;
    memset(&terminator, 0, sizeof(terminator));
    terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_JUMP;
    terminator.origin = make_origin(source->entry);
    if (!make_edge(
            b, source->entry, source->entry, context,
            VERSION_PRESERVE,
            &terminator.value.jump.edge))
        return 0;
    return set_terminator(b, terminator);
}

static void configure_machine(builder *b, abc_symbolic_machine *machine,
                              abc_symbolic_context *context, uint32_t pc,
                              uint32_t end) {
    memset(machine, 0, sizeof(*machine));
    machine->module = b->module;
    machine->code = b->module->code;
    machine->blocks = b->leaders;
    machine->pc = pc;
    machine->end = end;
    machine->context = context;
    machine->sink = b;
    machine->transfer_mask =
        ABC_SYM_TRANSFER_STACK |
        ABC_SYM_TRANSFER_VALUE |
        ABC_SYM_TRANSFER_CONTROL |
        ABC_SYM_TRANSFER_EFFECT;
    machine->emit_binary = on_binary;
    machine->emit_float_binary = on_float_binary;
    machine->emit_c_operand = on_c_operand;
    machine->emit_pow = on_pow;
    machine->emit_unary = on_unary;
    machine->emit_immediate = on_immediate;
    machine->emit_float_unary = on_float_unary;
    machine->emit_check = on_check;
    machine->emit_control = on_control;
    machine->emit_abort = on_abort;
    machine->emit_halt = on_halt;
    machine->emit_effect = on_effect;
    machine->emit_memory = on_memory;
    machine->emit_return = on_return;
    machine->emit_call = on_call;
    machine->emit_indirect = on_indirect;
    machine->emit_tail = on_tail;
    machine->emit_dynamic = on_dynamic;
    machine->emit_foreign = on_foreign;
    machine->emit_edge = on_edge;
}

static int build_version_body(builder *b, build_version *version) {
    int source_index =
        source_function_containing(b->module, version->pc);
    const abc_function *source;
    abc_symbolic_context context = {0};
    abc_symbolic_machine machine;
    abc_symbolic_exit exit;

    if (source_index < 0)
        return malformed(
            b, version->pc,
            "residual version is outside every source function");
    source = &b->module->functions[source_index];
    if (version->built) return 1;
    if (!abc_symbolic_context_copy(&context, &version->entry))
        return no_memory(b, version->pc);

    b->version = version;
    b->block = version->block;
    configure_machine(b, &machine, &context, version->pc, source->end);
    b->machine = &machine;
    exit = abc_symbolic_dispatch(&machine);
    b->machine = NULL;

    if (b->status != ABC_RESIDUAL_BUILD_OK) {
        b->version = NULL;
        abc_symbolic_context_free(&context);
        return 0;
    }

    if (exit == ABC_SYM_EXIT_BLOCK) {
        abc_residual_terminator terminator;

        memset(&terminator, 0, sizeof(terminator));
        terminator.tag = ABC_ASDL_RESIDUAL_TERMINATOR_JUMP;
        terminator.origin = make_origin(machine.pc);
        if (!make_edge(
                b, machine.pc, machine.pc, &context,
                edge_version_mode(
                    b, version->pc, machine.pc),
                &terminator.value.jump.edge) ||
            !set_terminator(b, terminator)) {
            b->version = NULL;
            abc_symbolic_context_free(&context);
            return 0;
        }
    } else if (exit == ABC_SYM_EXIT_BOUNDARY) {
        b->version = NULL;
        abc_symbolic_context_free(&context);
        return not_supported(
            b, machine.pc,
            "symbolic transfer reached an unsupported boundary");
    } else if (exit == ABC_SYM_EXIT_FAILURE) {
        b->version = NULL;
        abc_symbolic_context_free(&context);
        return malformed(
            b, machine.pc,
            "symbolic transfer failed while building residual IR");
    } else if (!b->block->terminated) {
        b->version = NULL;
        abc_symbolic_context_free(&context);
        return malformed(
            b, machine.pc,
            "symbolic control exit did not produce a terminator");
    }

    version->built = 1;
    b->version = NULL;
    abc_symbolic_context_free(&context);
    return 1;
}

static int finalize_function(builder *b, uint32_t fi) {
    build_function *function = &b->functions[fi];
    abc_residual_block *blocks;
    abc_residual_call *calls = NULL;
    size_t i;

    if (function->blocks.count) {
        blocks = abc_residual_allocate(
            b->arena, function->blocks.count, sizeof(*blocks));
        if (!blocks)
            return no_memory(b, b->module->functions[fi].entry);
    } else {
        blocks = NULL;
    }

    for (i = 0; i < function->blocks.count; i++) {
        build_block *source = function->blocks.items[i];

        if (!source->terminated)
            return malformed(
                b, source->ir.bytecode_offset,
                "residual block has no terminator");
        source->ir.nodes.count = source->nodes.count;
        if (source->nodes.count) {
            source->ir.nodes.items = abc_residual_copy(
                b->arena, source->nodes.items,
                source->nodes.count, sizeof(*source->nodes.items));
            if (!source->ir.nodes.items)
                return no_memory(b, source->ir.bytecode_offset);
        }
        blocks[i] = source->ir;
    }

    if (function->calls.count) {
        calls = abc_residual_copy(
            b->arena, function->calls.items,
            function->calls.count, sizeof(*calls));
        if (!calls)
            return no_memory(b, b->module->functions[fi].entry);
    }

    function->ir.blocks.count = function->blocks.count;
    function->ir.blocks.items = blocks;
    function->value_end = b->values.count;
    function->supported = 1;
    b->bundle->source_functions[fi].supported = 1;
    b->bundle->source_functions[fi].call_count =
        function->calls.count;
    b->bundle->source_functions[fi].calls = calls;
    return 1;
}

static void free_build_function(build_function *function) {
    size_t i;

    for (i = 0; i < function->versions.count; i++) {
        build_version *version = function->versions.items[i];
        abc_symbolic_context_free(&version->key);
        abc_symbolic_context_free(&version->entry);
        free(version->homes);
        free(version);
    }
    for (i = 0; i < function->blocks.count; i++) {
        free(function->blocks.items[i]->nodes.items);
        free(function->blocks.items[i]);
    }
    free(function->versions.items);
    free(function->blocks.items);
    free(function->calls.items);
    memset(function, 0, sizeof(*function));
}

static int build_function_ir(builder *b, uint32_t fi) {
    abc_symbolic_context context = {0};

    b->source_function = fi;
    b->function = &b->functions[fi];
    b->version = NULL;
    b->pending_edge = 0;
    memset(b->embedded, 0, b->module->function_count);
    b->embedded[fi] = 1;
    if (!initial_context(b, fi, &context)) {
        abc_symbolic_context_free(&context);
        return 0;
    }
    if (!make_entry(b, &context)) {
        abc_symbolic_context_free(&context);
        return 0;
    }
    abc_symbolic_context_free(&context);

    while (b->function->versions.head <
           b->function->versions.count) {
        build_version *version =
            b->function->versions.items[
                b->function->versions.head++];
        if (!build_version_body(b, version)) return 0;
    }
    return finalize_function(b, fi);
}

static int source_index_for_residual_id(
    const builder *b, abc_residual_id id, uint32_t *index) {
    uint32_t i;

    for (i = 0; i < b->module->function_count; i++) {
        if (b->function_ids[i].value == id.value) {
            *index = i;
            return 1;
        }
    }
    return 0;
}

static int function_references_unsupported(
    const builder *b, const build_function *function) {
    size_t bi;
    size_t ni;
    size_t ci;

    for (ci = 0; ci < function->calls.count; ci++) {
        uint32_t target = function->calls.items[ci].target;
        if (target < b->module->function_count &&
            !b->functions[target].supported)
            return 1;
    }
    for (bi = 0; bi < function->ir.blocks.count; bi++) {
        const abc_residual_block *block =
            &function->ir.blocks.items[bi];

        for (ni = 0; ni < block->nodes.count; ni++) {
            const abc_residual_operation *operation =
                &block->nodes.items[ni].operation;
            uint32_t target;

            if (operation->tag ==
                    ABC_ASDL_RESIDUAL_OPERATION_FUNCTION_REFERENCE &&
                source_index_for_residual_id(
                    b, operation->value.function_reference.function,
                    &target) &&
                !b->functions[target].supported)
                return 1;
        }
    }
    return 0;
}

static void remove_unsupported_dependencies(builder *b) {
    int changed;
    uint32_t i;

    do {
        changed = 0;
        for (i = 0; i < b->module->function_count; i++) {
            build_function *function = &b->functions[i];

            if (function->supported &&
                function_references_unsupported(b, function)) {
                function->supported = 0;
                b->bundle->source_functions[i].supported = 0;
                b->bundle->source_functions[i].call_count = 0;
                b->bundle->source_functions[i].calls = NULL;
                changed = 1;
            }
        }
    } while (changed);
}

static int finalize_program(builder *b) {
    abc_residual_function *functions = NULL;
    abc_residual_value *values = NULL;
    abc_residual_diagnostic diagnostic;
    size_t function_count = 0;
    size_t value_count = 0;
    size_t function_at = 0;
    size_t value_at = 0;
    uint32_t i;

    remove_unsupported_dependencies(b);
    for (i = 0; i < b->module->function_count; i++) {
        const build_function *function = &b->functions[i];

        if (!function->supported) continue;
        function_count++;
        value_count += function->value_end -
                       function->value_start;
    }

    if (function_count) {
        functions = abc_residual_allocate(
            b->arena, function_count, sizeof(*functions));
        if (!functions)
            return no_memory(b, UINT32_MAX);
    }
    if (value_count) {
        values = abc_residual_allocate(
            b->arena, value_count, sizeof(*values));
        if (!values)
            return no_memory(b, UINT32_MAX);
    }

    for (i = 0; i < b->module->function_count; i++) {
        const build_function *function = &b->functions[i];
        size_t count;

        if (!function->supported) continue;
        functions[function_at++] = function->ir;
        count = function->value_end - function->value_start;
        if (count) {
            memcpy(values + value_at,
                   b->values.items + function->value_start,
                   count * sizeof(*values));
            value_at += count;
        }
    }

    b->bundle->program.functions.count = function_count;
    b->bundle->program.functions.items = functions;
    b->bundle->program.values.count = value_count;
    b->bundle->program.values.items = values;

    if (!abc_residual_validate(&b->bundle->program, &diagnostic)) {
        diagnose(b, ABC_RESIDUAL_BUILD_INVALID,
                 diagnostic.origin > UINT32_MAX
                     ? UINT32_MAX
                     : (uint32_t)diagnostic.origin,
                 "constructed residual IR is invalid: %s",
                 diagnostic.message);
        return 0;
    }
    return 1;
}

abc_residual_build_status abc_residual_build(
    const abc_module *module,
    const abc_residual_build_options *options,
    abc_residual_bundle **out,
    abc_residual_build_diagnostic *diagnostic) {
    builder b;
    abc_residual_bundle *bundle = NULL;
    abc_residual_call_graph graph = {0};
    uint32_t i;

    if (out) *out = NULL;
    if (diagnostic) {
        memset(diagnostic, 0, sizeof(*diagnostic));
        diagnostic->bytecode_offset = UINT32_MAX;
    }
    if (!module || !out) {
        if (diagnostic) {
            diagnostic->status = ABC_RESIDUAL_BUILD_INVALID;
            snprintf(diagnostic->message, sizeof(diagnostic->message),
                     "invalid residual builder input");
        }
        return ABC_RESIDUAL_BUILD_INVALID;
    }

    memset(&b, 0, sizeof(b));
    b.module = module;
    b.options = options;
    b.status = ABC_RESIDUAL_BUILD_OK;
    b.diagnostic = diagnostic;

    bundle = calloc(1, sizeof(*bundle));
    if (!bundle) {
        if (diagnostic) {
            diagnostic->status = ABC_RESIDUAL_BUILD_NOMEM;
            snprintf(diagnostic->message, sizeof(diagnostic->message),
                     "residual bundle allocation failed");
        }
        return ABC_RESIDUAL_BUILD_NOMEM;
    }
    bundle->arena = abc_residual_arena_create();
    if (!bundle->arena) {
        free(bundle);
        if (diagnostic) {
            diagnostic->status = ABC_RESIDUAL_BUILD_NOMEM;
            snprintf(diagnostic->message, sizeof(diagnostic->message),
                     "residual arena allocation failed");
        }
        return ABC_RESIDUAL_BUILD_NOMEM;
    }

    b.bundle = bundle;
    b.arena = bundle->arena;
    if (!abc_residual_analysis_build_call_graph(module, &graph)) {
        no_memory(&b, UINT32_MAX);
        goto done;
    }
    b.graph = &graph;
    b.functions = calloc(
        module->function_count ? module->function_count : 1,
        sizeof(*b.functions));
    b.function_ids = calloc(
        module->function_count ? module->function_count : 1,
        sizeof(*b.function_ids));
    b.embedded = calloc(
        module->function_count ? module->function_count : 1, 1);
    bundle->source_function_count = module->function_count;
    bundle->source_functions = abc_residual_allocate(
        bundle->arena,
        module->function_count ? module->function_count : 1,
        sizeof(*bundle->source_functions));
    if (!b.functions || !b.function_ids || !b.embedded ||
        !bundle->source_functions) {
        no_memory(&b, UINT32_MAX);
        goto done;
    }

    for (i = 0; i < module->function_count; i++) {
        const abc_function *source = &module->functions[i];
        uint8_t *unknown_seen = calloc(
            module->function_count ? module->function_count : 1, 1);
        unsigned native_recursive;

        if (!unknown_seen) {
            no_memory(&b, source->entry);
            goto done;
        }
        native_recursive = graph.recursive[i] ||
            abc_symbolic_has_unknown_call(module, (int)i, unknown_seen);
        free(unknown_seen);
        b.function_ids[i] = next_id(&b);
        if (!b.function_ids[i].value) goto done;
        bundle->source_functions[i] =
            (abc_residual_source_function){
                .source_function = i,
                .source_entry = source->entry,
                .fallback_source_entry = source->entry,
                .fallback_source_size = source->end - source->entry,
                .residual_function = b.function_ids[i],
                .recursive = native_recursive,
                .max_a = source->max_a,
                .max_b = source->max_b,
                .max_c = source->max_c
            };
    }
    if (!discover_leaders(&b)) goto done;
    for (i = 0; i < module->function_count; i++) {
        size_t value_start = b.values.count;

        if (!initialize_function(&b, i) ||
            !build_function_ir(&b, i)) {
            if (b.status != ABC_RESIDUAL_BUILD_UNSUPPORTED)
                goto done;
            b.values.count = value_start;
            free_build_function(&b.functions[i]);
            b.status = ABC_RESIDUAL_BUILD_OK;
        }
    }
    if (!finalize_program(&b)) goto done;
    if (diagnostic) {
        memset(diagnostic, 0, sizeof(*diagnostic));
        diagnostic->bytecode_offset = UINT32_MAX;
    }

done:
    for (i = 0; b.functions && i < module->function_count; i++)
        free_build_function(&b.functions[i]);
    free(b.functions);
    free(b.function_ids);
    free(b.embedded);
    free(b.values.items);
    free(b.leaders);
    free(b.loop_headers);
    abc_residual_analysis_call_graph_free(&graph);

    if (b.status == ABC_RESIDUAL_BUILD_OK) {
        *out = bundle;
    } else {
        abc_residual_bundle_free(bundle);
    }
    return b.status;
}

void abc_residual_bundle_free(abc_residual_bundle *bundle) {
    if (!bundle) return;
    abc_residual_arena_free(bundle->arena);
    free(bundle);
}

const abc_residual_program *abc_residual_bundle_program(
    const abc_residual_bundle *bundle) {
    return bundle ? &bundle->program : NULL;
}

size_t abc_residual_bundle_source_function_count(
    const abc_residual_bundle *bundle) {
    return bundle ? bundle->source_function_count : 0;
}

const abc_residual_source_function *
abc_residual_bundle_source_functions(
    const abc_residual_bundle *bundle) {
    return bundle ? bundle->source_functions : NULL;
}
