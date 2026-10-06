#include "residual_ir.h"

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

typedef enum { ENTITY_VALUE, ENTITY_FUNCTION, ENTITY_BLOCK, ENTITY_NODE } entity_kind;

typedef struct {
    uint64_t id;
    entity_kind kind;
    const void *object;
    const abc_residual_function *function;
    const abc_residual_block *block;
    size_t ordinal;
} entity;

typedef enum { VALUE_NOWHERE, VALUE_CONSTANT, VALUE_FUNCTION_ARGUMENT, VALUE_BLOCK_ARGUMENT, VALUE_NODE_RESULT } value_place_kind;

typedef struct {
    value_place_kind kind;
    const abc_residual_function *function;
    const abc_residual_block *block;
    const abc_residual_node *node;
    size_t ordinal;
    size_t node_ordinal;
} value_place;

typedef struct {
    const abc_residual_program *program;
    entity *entities;
    size_t entity_count;
    value_place *places;
    abc_residual_diagnostic *diagnostic;
} validator;

static int fail(validator *v, uint64_t id, uint64_t origin, const char *format, ...) {
    v->diagnostic->id = id;
    v->diagnostic->origin = origin;
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(v->diagnostic->message, sizeof(v->diagnostic->message), format, arguments);
    va_end(arguments);
    return 0;
}

static int valid_tag(validator *v, const char *name, uint64_t id, uint64_t origin, const char *role) {
    return name != NULL || fail(v, id, origin, "%s has an invalid tag", role);
}

static int add_size(size_t *total, size_t amount) {
    if (amount > SIZE_MAX - *total) return 0;
    *total += amount;
    return 1;
}

static int entity_compare(const void *left, const void *right) {
    const entity *a = left, *b = right;
    return a->id < b->id ? -1 : a->id > b->id;
}

static const entity *find_entity(const validator *v, uint64_t id) {
    entity key = {.id = id};
    return bsearch(&key, v->entities, v->entity_count, sizeof(*v->entities), entity_compare);
}

static const entity *require_entity(validator *v, abc_residual_id id, entity_kind kind,
                                    uint64_t owner_id, uint64_t origin, const char *role) {
    const entity *found = find_entity(v, id.value);
    if (!found || found->kind != kind) {
        fail(v, owner_id, origin, "%s references invalid id %llu", role, (unsigned long long)id.value);
        return NULL;
    }
    return found;
}

static size_t value_index(const validator *v, const abc_residual_value *value) {
    return (size_t)(value - v->program->values.items);
}

static int sequence_present(size_t count, const void *items) {
    return !count || items != NULL;
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

static int facts_compatible(const abc_residual_value *actual,
                            const abc_residual_value *expected) {
    uint64_t actual_tags = actual->facts.dynamic_tags;
    uint64_t expected_tags = expected->facts.dynamic_tags;
    int facts_are_compatible =
        expected_tags == 0 ||
        (actual_tags != 0 &&
         (actual_tags & ~expected_tags) == 0 &&
         (expected->facts.dynamic_width == 0 ||
          actual->facts.dynamic_width ==
              expected->facts.dynamic_width) &&
         (expected->facts.representation ==
              ABC_ASDL_RESIDUAL_REPRESENTATION_UNKNOWN ||
          actual->facts.representation ==
              expected->facts.representation));

    return type_compatible(actual->type, expected->type) &&
           facts_are_compatible;
}

static int record_place(validator *v, const entity *value_entity, value_place place,
                        uint64_t owner_id, uint64_t origin) {
    size_t index = value_index(v, value_entity->object);
    if (v->places[index].kind != VALUE_NOWHERE)
        return fail(v, owner_id, origin, "value %llu has more than one definition site",
                    (unsigned long long)value_entity->id);
    v->places[index] = place;
    return 1;
}

static int validate_shape(validator *v) {
    if (!sequence_present(v->program->values.count, v->program->values.items) ||
        !sequence_present(v->program->functions.count, v->program->functions.items))
        return fail(v, 0, 0, "program has a missing sequence");
    for (size_t fi = 0; fi < v->program->functions.count; fi++) {
        const abc_residual_function *function = &v->program->functions.items[fi];
        if (!sequence_present(function->argument_types.count, function->argument_types.items) ||
            !sequence_present(function->result_types.count, function->result_types.items) ||
            !sequence_present(function->arguments.count, function->arguments.items) ||
            !sequence_present(function->blocks.count, function->blocks.items))
            return fail(v, function->id.value, 0, "function has a missing sequence");
        for (size_t bi = 0; bi < function->blocks.count; bi++) {
            const abc_residual_block *block = &function->blocks.items[bi];
            if (!sequence_present(block->arguments.count, block->arguments.items) ||
                !sequence_present(block->nodes.count, block->nodes.items))
                return fail(v, block->id.value, block->bytecode_offset, "block has a missing sequence");
            for (size_t ni = 0; ni < block->nodes.count; ni++) {
                const abc_residual_node *node = &block->nodes.items[ni];
                if (!sequence_present(node->results.count, node->results.items))
                    return fail(v, node->id.value, node->origin.offset, "node has a missing result sequence");
            }
        }
    }
    return 1;
}

static int collect_entities(validator *v) {
    size_t count = v->program->values.count + v->program->functions.count;
    if (count < v->program->values.count) return fail(v, 0, 0, "entity count overflows");
    for (size_t fi = 0; fi < v->program->functions.count; fi++) {
        const abc_residual_function *function = &v->program->functions.items[fi];
        if (!add_size(&count, function->blocks.count)) return fail(v, 0, 0, "entity count overflows");
        for (size_t bi = 0; bi < function->blocks.count; bi++)
            if (!add_size(&count, function->blocks.items[bi].nodes.count))
                return fail(v, 0, 0, "entity count overflows");
    }
    v->entities = calloc(count ? count : 1, sizeof(*v->entities));
    v->places = calloc(v->program->values.count ? v->program->values.count : 1, sizeof(*v->places));
    if (!v->entities || !v->places) return fail(v, 0, 0, "validator allocation failed");

    size_t at = 0;
    for (size_t i = 0; i < v->program->values.count; i++) {
        const abc_residual_value *value = &v->program->values.items[i];
        v->entities[at++] = (entity){value->id.value, ENTITY_VALUE, value, NULL, NULL, i};
        if (value->definition.tag == ABC_ASDL_RESIDUAL_DEFINITION_CONSTANT)
            v->places[i].kind = VALUE_CONSTANT;
    }
    for (size_t fi = 0; fi < v->program->functions.count; fi++) {
        const abc_residual_function *function = &v->program->functions.items[fi];
        v->entities[at++] = (entity){function->id.value, ENTITY_FUNCTION, function, function, NULL, fi};
        for (size_t bi = 0; bi < function->blocks.count; bi++) {
            const abc_residual_block *block = &function->blocks.items[bi];
            v->entities[at++] = (entity){block->id.value, ENTITY_BLOCK, block, function, block, bi};
            for (size_t ni = 0; ni < block->nodes.count; ni++) {
                const abc_residual_node *node = &block->nodes.items[ni];
                v->entities[at++] = (entity){node->id.value, ENTITY_NODE, node, function, block, ni};
            }
        }
    }
    v->entity_count = at;
    qsort(v->entities, v->entity_count, sizeof(*v->entities), entity_compare);
    for (size_t i = 0; i < v->entity_count; i++) {
        if (!v->entities[i].id) return fail(v, 0, 0, "id zero is reserved");
        if (i && v->entities[i - 1].id == v->entities[i].id)
            return fail(v, v->entities[i].id, 0, "duplicate id %llu",
                        (unsigned long long)v->entities[i].id);
    }
    return 1;
}

static int collect_value_places(validator *v) {
    for (size_t fi = 0; fi < v->program->functions.count; fi++) {
        const abc_residual_function *function = &v->program->functions.items[fi];
        for (size_t i = 0; i < function->arguments.count; i++) {
            const entity *value = require_entity(v, function->arguments.items[i], ENTITY_VALUE,
                                                 function->id.value, 0, "function argument");
            if (!value || !record_place(v, value, (value_place){VALUE_FUNCTION_ARGUMENT, function, NULL, NULL, i, 0}, function->id.value, 0)) return 0;
        }
        for (size_t bi = 0; bi < function->blocks.count; bi++) {
            const abc_residual_block *block = &function->blocks.items[bi];
            for (size_t i = 0; i < block->arguments.count; i++) {
                const entity *value = require_entity(v, block->arguments.items[i], ENTITY_VALUE,
                                                     block->id.value, block->bytecode_offset, "block argument");
                if (!value || !record_place(v, value, (value_place){VALUE_BLOCK_ARGUMENT, function, block, NULL, i, 0}, block->id.value, block->bytecode_offset)) return 0;
            }
            for (size_t ni = 0; ni < block->nodes.count; ni++) {
                const abc_residual_node *node = &block->nodes.items[ni];
                for (size_t i = 0; i < node->results.count; i++) {
                    const entity *value = require_entity(v, node->results.items[i], ENTITY_VALUE,
                                                         node->id.value, node->origin.offset, "node result");
                    if (!value || !record_place(v, value, (value_place){VALUE_NODE_RESULT, function, block, node, i, ni}, node->id.value, node->origin.offset)) return 0;
                }
            }
        }
    }
    return 1;
}

static int validate_value_definitions(validator *v) {
    for (size_t i = 0; i < v->program->values.count; i++) {
        const abc_residual_value *value = &v->program->values.items[i];
        const value_place *place = &v->places[i];
        if (!abc_asdl_residual_type_tag_name(value->type))
            return fail(v, value->id.value, value->origin.offset, "value has invalid type tag");
        if (!abc_asdl_residual_representation_tag_name(value->facts.representation))
            return fail(v, value->id.value, value->origin.offset, "value has invalid representation tag");
        if (!abc_asdl_residual_definition_tag_name(value->definition.tag))
            return fail(v, value->id.value, value->origin.offset, "value has invalid definition tag");
        switch (value->definition.tag) {
        case ABC_ASDL_RESIDUAL_DEFINITION_CONSTANT:
            if (place->kind != VALUE_CONSTANT)
                return fail(v, value->id.value, value->origin.offset, "constant is also defined by control flow");
            break;
        case ABC_ASDL_RESIDUAL_DEFINITION_FUNCTION_ARGUMENT:
            if (place->kind != VALUE_FUNCTION_ARGUMENT || value->definition.value.function_argument.index != place->ordinal)
                return fail(v, value->id.value, value->origin.offset, "function-argument definition does not match its function");
            break;
        case ABC_ASDL_RESIDUAL_DEFINITION_BLOCK_ARGUMENT:
            if (place->kind != VALUE_BLOCK_ARGUMENT ||
                value->definition.value.block_argument.block.value != place->block->id.value ||
                value->definition.value.block_argument.index != place->ordinal)
                return fail(v, value->id.value, value->origin.offset, "block-argument definition does not match its block");
            break;
        case ABC_ASDL_RESIDUAL_DEFINITION_INSTRUCTION_RESULT:
            if (place->kind != VALUE_NODE_RESULT ||
                value->definition.value.instruction_result.instruction.value != place->node->id.value ||
                value->definition.value.instruction_result.index != place->ordinal)
                return fail(v, value->id.value, value->origin.offset, "instruction-result definition does not match its node");
            break;
        default: return 0;
        }
    }
    return 1;
}

static const abc_residual_value *validate_value_use(validator *v, abc_residual_id id,
                                                     const abc_residual_function *function,
                                                     const abc_residual_block *block, size_t node_ordinal,
                                                     uint64_t owner_id, uint64_t origin, const char *role) {
    const entity *found = require_entity(v, id, ENTITY_VALUE, owner_id, origin, role);
    if (!found) return NULL;
    const abc_residual_value *value = found->object;
    const value_place *place = &v->places[value_index(v, value)];
    if (place->kind == VALUE_CONSTANT) return value;
    if (place->function != function) {
        fail(v, owner_id, origin, "%s uses value %llu from another function", role, (unsigned long long)id.value);
        return NULL;
    }
    if (place->kind == VALUE_FUNCTION_ARGUMENT) return value;
    if (place->block != block) {
        fail(v, owner_id, origin, "%s uses non-parameter value %llu across a block boundary", role,
             (unsigned long long)id.value);
        return NULL;
    }
    if (place->kind == VALUE_NODE_RESULT && place->node_ordinal >= node_ordinal) {
        fail(v, owner_id, origin, "%s uses value %llu before its definition", role, (unsigned long long)id.value);
        return NULL;
    }
    return value;
}

static int validate_id_list(validator *v, const abc_residual_id *items, size_t count,
                            const abc_residual_function *function, const abc_residual_block *block,
                            size_t node_ordinal, uint64_t owner_id, uint64_t origin, const char *role) {
    if (!sequence_present(count, items)) return fail(v, owner_id, origin, "%s has a missing sequence", role);
    for (size_t i = 0; i < count; i++)
        if (!validate_value_use(v, items[i], function, block, node_ordinal, owner_id, origin, role)) return 0;
    return 1;
}

static int valid_memory_width(uint64_t width) {
    return width == 1 || width == 2 || width == 4 || width == 8;
}

static int validate_call_abi(
    validator *v, const abc_asdl_residual_call_abi *abi,
    size_t arguments, size_t results,
    uint64_t owner_id, uint64_t origin, const char *role) {
    if (abi->arguments != arguments || abi->results != results)
        return fail(v, owner_id, origin,
                    "%s ABI does not match its value arity", role);
    if (abi->hidden_result_bytes > UINT32_MAX ||
        abi->frame_cells > UINT32_MAX)
        return fail(v, owner_id, origin,
                    "%s ABI exceeds the VM format", role);
    return 1;
}

static int validate_operation(validator *v, const abc_residual_function *function,
                              const abc_residual_block *block, const abc_residual_node *node, size_t node_ordinal) {
    const abc_residual_operation *operation = &node->operation;
    uint64_t id = node->id.value, origin = node->origin.offset;
    if (!abc_asdl_residual_operation_tag_name(operation->tag))
        return fail(v, id, origin, "node has invalid operation tag");
    #define USE(VALUE, ROLE) (validate_value_use(v, (VALUE), function, block, node_ordinal, id, origin, (ROLE)) != NULL)
    switch (operation->tag) {
    case ABC_ASDL_RESIDUAL_OPERATION_UNARY:
        return valid_tag(v, abc_asdl_residual_unary_op_tag_name(operation->value.unary.operation), id, origin, "unary operation") &&
               USE(operation->value.unary.input, "unary operand");
    case ABC_ASDL_RESIDUAL_OPERATION_BINARY:
        return valid_tag(v, abc_asdl_residual_binary_op_tag_name(operation->value.binary.operation), id, origin, "binary operation") &&
               USE(operation->value.binary.left, "binary left operand") && USE(operation->value.binary.right, "binary right operand");
    case ABC_ASDL_RESIDUAL_OPERATION_CHECK:
        return valid_tag(v, abc_asdl_residual_check_op_tag_name(operation->value.check.operation), id, origin, "check operation") &&
               node->effect.may_trap && USE(operation->value.check.input, "check operand");
    case ABC_ASDL_RESIDUAL_OPERATION_CONVERT:
        return valid_tag(v, abc_asdl_residual_convert_op_tag_name(operation->value.convert.operation), id, origin, "conversion operation") &&
               USE(operation->value.convert.input, "conversion operand");
    case ABC_ASDL_RESIDUAL_OPERATION_LOAD:
        if (!node->effect.reads_memory || !valid_memory_width(operation->value.load.width) ||
            !abc_asdl_residual_address_space_tag_name(operation->value.load.space))
            return fail(v, id, origin, "load lacks its read effect or has an invalid width/address space");
        return USE(operation->value.load.address, "load address");
    case ABC_ASDL_RESIDUAL_OPERATION_STORE:
        if (!node->effect.writes_memory || !valid_memory_width(operation->value.store.width) ||
            !abc_asdl_residual_address_space_tag_name(operation->value.store.space))
            return fail(v, id, origin, "store lacks its write effect or has an invalid width/address space");
        return USE(operation->value.store.address, "store address") && USE(operation->value.store.value, "stored value");
    case ABC_ASDL_RESIDUAL_OPERATION_COPY_MEMORY:
        if (!node->effect.reads_memory || !node->effect.writes_memory) return fail(v, id, origin, "memory copy lacks read/write effects");
        return USE(operation->value.copy_memory.destination, "copy destination") && USE(operation->value.copy_memory.source, "copy source");
    case ABC_ASDL_RESIDUAL_OPERATION_CLEAR_FRAME:
        return node->effect.writes_memory || fail(v, id, origin, "frame clear lacks its write effect");
    case ABC_ASDL_RESIDUAL_OPERATION_FRAME_ADDRESS:
    case ABC_ASDL_RESIDUAL_OPERATION_IMAGE_ADDRESS:
        return 1;
    case ABC_ASDL_RESIDUAL_OPERATION_FUNCTION_REFERENCE: {
        const entity *target = require_entity(v, operation->value.function_reference.function,
                                              ENTITY_FUNCTION, id, origin,
                                              "function-reference target");
        if (!target) return 0;
        if (node->results.count != 1)
            return fail(v, id, origin, "function reference must have one result");
        const entity *result = require_entity(v, node->results.items[0], ENTITY_VALUE,
                                              id, origin, "function-reference result");
        if (!result) return 0;
        if (((const abc_residual_value *)result->object)->type != ABC_ASDL_RESIDUAL_TYPE_ADDRESS)
            return fail(v, id, origin, "function-reference result must have address type");
        return 1;
    }
    case ABC_ASDL_RESIDUAL_OPERATION_CALLABLE_CONSTRUCTOR: {
        const entity *target = require_entity(
            v, operation->value.callable_constructor.target,
            ENTITY_FUNCTION, id, origin,
            "callable-constructor target");
        const abc_residual_id *environment =
            operation->value.callable_constructor.environment;

        if (!target)
            return 0;
        if ((operation->value.callable_constructor.environment_cells != 0) !=
            (environment != NULL))
            return fail(v, id, origin,
                        "callable constructor has inconsistent environment metadata");
        if (environment &&
            !USE(*environment, "callable-constructor environment"))
            return 0;
        if (node->results.count != 1)
            return fail(v, id, origin,
                        "callable constructor must have one result");
        {
            const entity *result = require_entity(
                v, node->results.items[0], ENTITY_VALUE,
                id, origin, "callable-constructor result");
            if (!result ||
                ((const abc_residual_value *)result->object)->type !=
                    ABC_ASDL_RESIDUAL_TYPE_ANY)
                return fail(v, id, origin,
                            "callable-constructor result must have Any type");
        }
        return 1;
    }
    case ABC_ASDL_RESIDUAL_OPERATION_CALL: {
        if (!node->effect.calls || !abc_asdl_residual_call_kind_tag_name(operation->value.call.kind))
            return fail(v, id, origin, "call lacks its call effect or has an invalid kind");
        const entity *direct_target = NULL;
        if (operation->value.call.kind == ABC_ASDL_RESIDUAL_CALL_KIND_DIRECT) {
            direct_target = require_entity(v, (abc_residual_id){operation->value.call.target},
                                           ENTITY_FUNCTION, id, origin, "direct-call target");
            if (!direct_target) return 0;
        }
        if (operation->value.call.kind == ABC_ASDL_RESIDUAL_CALL_KIND_INDIRECT) {
            if (!operation->value.call.callee || !USE(*operation->value.call.callee, "indirect callee"))
                return fail(v, id, origin, "indirect call has no valid callee");
        } else if (operation->value.call.callee) {
            return fail(v, id, origin, "non-indirect call unexpectedly has a callee value");
        }
        if (!validate_id_list(v, operation->value.call.arguments.items,
                              operation->value.call.arguments.count, function, block,
                              node_ordinal, id, origin, "call argument") ||
            !validate_call_abi(
                v, &operation->value.call.abi,
                operation->value.call.arguments.count,
                node->results.count, id, origin, "call"))
            return 0;
        if (!direct_target) return 1;
        const abc_residual_function *callee = direct_target->object;
        if (operation->value.call.arguments.count != callee->argument_types.count ||
            node->results.count != callee->result_types.count)
            return fail(v, id, origin, "direct call does not match its target arity");
        for (size_t i = 0; i < operation->value.call.arguments.count; i++) {
            const entity *argument = find_entity(v, operation->value.call.arguments.items[i].value);
            if (!type_compatible(
                    ((const abc_residual_value *)argument->object)->type,
                    callee->argument_types.items[i]))
                return fail(v, id, origin, "direct-call argument %zu has the wrong type", i);
        }
        for (size_t i = 0; i < node->results.count; i++) {
            const entity *result = find_entity(v, node->results.items[i].value);
            if (!type_compatible(
                    ((const abc_residual_value *)result->object)->type,
                    callee->result_types.items[i]))
                return fail(v, id, origin, "direct-call result %zu has the wrong type", i);
        }
        return 1;
    }
    case ABC_ASDL_RESIDUAL_OPERATION_MATERIALIZE:
        return valid_tag(v, abc_asdl_residual_materialize_kind_tag_name(operation->value.materialize.kind), id, origin, "materialization operation") &&
               USE(operation->value.materialize.input, "materialized value");
    case ABC_ASDL_RESIDUAL_OPERATION_DYNAMIC_OPERATION:
        if (!node->effect.calls)
            return fail(v, id, origin,
                        "dynamic operation lacks its call effect");
        if (!operation->value.dynamic_operation.literal &&
            operation->value.dynamic_operation.reverse)
            return fail(v, id, origin,
                        "dynamic operation reverses a missing literal");
        return validate_id_list(
            v, operation->value.dynamic_operation.arguments.items,
            operation->value.dynamic_operation.arguments.count,
            function, block, node_ordinal, id, origin,
            "dynamic argument");
    case ABC_ASDL_RESIDUAL_OPERATION_DYNAMIC_CALL:
        if (!node->effect.calls || !node->effect.may_trap)
            return fail(v, id, origin,
                        "dynamic call lacks its call/trap effects");
        if (operation->value.dynamic_call.arguments.count !=
            operation->value.dynamic_call.abi.arguments + 1)
            return fail(v, id, origin,
                        "dynamic call lacks its callable operand");
        if (!validate_call_abi(
                v, &operation->value.dynamic_call.abi,
                operation->value.dynamic_call.abi.arguments,
                node->results.count, id, origin, "dynamic call"))
            return 0;
        return validate_id_list(
            v, operation->value.dynamic_call.arguments.items,
            operation->value.dynamic_call.arguments.count,
            function, block, node_ordinal, id, origin,
            "dynamic-call argument");
    case ABC_ASDL_RESIDUAL_OPERATION_MANAGED_WRITE:
        if (!node->effect.writes_memory) return fail(v, id, origin, "managed write lacks its write effect");
        return USE(operation->value.managed_write.address, "managed-write address");
    default: return 0;
    }
    #undef USE
}

static int is_comparison(abc_asdl_residual_binary_op operation) {
    return operation >= ABC_ASDL_RESIDUAL_BINARY_OP_EQUAL &&
           operation <= ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_EQUAL;
}

static int validate_edge(validator *v, const abc_residual_function *function,
                         const abc_residual_block *source, const abc_residual_edge *edge, uint64_t owner_id, uint64_t origin) {
    const entity *target_entity = require_entity(v, edge->target, ENTITY_BLOCK, owner_id, origin, "edge target");
    if (!target_entity || target_entity->function != function) return target_entity ? fail(v, owner_id, origin, "edge leaves its function") : 0;
    const abc_residual_block *target = target_entity->object;
    if (edge->arguments.count != target->arguments.count || !sequence_present(edge->arguments.count, edge->arguments.items))
        return fail(v, owner_id, origin, "edge to block %llu has the wrong argument count", (unsigned long long)edge->target.value);
    for (size_t i = 0; i < edge->arguments.count; i++) {
        const abc_residual_value *actual = validate_value_use(v, edge->arguments.items[i], function, source, source->nodes.count, owner_id, origin, "edge argument");
        const entity *formal_entity = require_entity(v, target->arguments.items[i], ENTITY_VALUE, owner_id, origin, "edge parameter");
        if (!actual || !formal_entity) return 0;
        const abc_residual_value *expected = formal_entity->object;
        if (!facts_compatible(actual, expected))
            return fail(
                v, owner_id, origin,
                "edge arg %zu incompatible: actual=%s/%llu/%llu/%s expected=%s/%llu/%llu/%s",
                i,
                abc_asdl_residual_type_tag_name(actual->type),
                (unsigned long long)actual->facts.dynamic_tags,
                (unsigned long long)actual->facts.dynamic_width,
                abc_asdl_residual_representation_tag_name(actual->facts.representation),
                abc_asdl_residual_type_tag_name(expected->type),
                (unsigned long long)expected->facts.dynamic_tags,
                (unsigned long long)expected->facts.dynamic_width,
                abc_asdl_residual_representation_tag_name(expected->facts.representation));
    }
    return 1;
}

static int validate_terminator(validator *v, const abc_residual_function *function, const abc_residual_block *block) {
    const abc_residual_terminator *terminator = &block->terminator;
    uint64_t id = block->id.value, origin = terminator->origin.offset;
    if (!abc_asdl_residual_terminator_tag_name(terminator->tag)) return fail(v, id, origin, "block has invalid terminator tag");
    switch (terminator->tag) {
    case ABC_ASDL_RESIDUAL_TERMINATOR_JUMP:
        return validate_edge(v, function, block, &terminator->value.jump.edge, id, origin);
    case ABC_ASDL_RESIDUAL_TERMINATOR_BRANCH:
        if (!is_comparison(terminator->value.branch.relation)) return fail(v, id, origin, "branch has a non-comparison relation");
        return validate_value_use(v, terminator->value.branch.left, function, block, block->nodes.count, id, origin, "branch left operand") &&
               validate_value_use(v, terminator->value.branch.right, function, block, block->nodes.count, id, origin, "branch right operand") &&
               validate_edge(v, function, block, &terminator->value.branch.yes, id, origin) &&
               validate_edge(v, function, block, &terminator->value.branch.no, id, origin);
    case ABC_ASDL_RESIDUAL_TERMINATOR_SWITCH:
        if (!validate_value_use(v, terminator->value.switch_value.value, function, block, block->nodes.count, id, origin, "switch value") ||
            !sequence_present(terminator->value.switch_value.arms.count, terminator->value.switch_value.arms.items)) return 0;
        for (size_t i = 0; i < terminator->value.switch_value.arms.count; i++) {
            const abc_residual_switch_arm *arm = &terminator->value.switch_value.arms.items[i];
            if (arm->value_low > arm->value_high) return fail(v, id, origin, "switch arm has an inverted range");
            for (size_t j = 0; j < i; j++) {
                const abc_residual_switch_arm *prior = &terminator->value.switch_value.arms.items[j];
                if (arm->value_low <= prior->value_high && prior->value_low <= arm->value_high) return fail(v, id, origin, "switch arms overlap");
            }
            if (!validate_edge(v, function, block, &arm->edge, id, origin)) return 0;
        }
        return validate_edge(v, function, block, &terminator->value.switch_value.fallback, id, origin);
    case ABC_ASDL_RESIDUAL_TERMINATOR_RETURN:
        if (terminator->value.return_value.values.count != function->result_types.count) return fail(v, id, origin, "return has the wrong result count");
        if (!validate_call_abi(
                v, &terminator->value.return_value.abi,
                function->argument_types.count,
                terminator->value.return_value.values.count,
                id, origin, "return") ||
            terminator->value.return_value.abi.hidden_result_bytes !=
                function->hidden_result_bytes)
            return fail(v, id, origin,
                        "return ABI does not match its function");
        if (!validate_id_list(v, terminator->value.return_value.values.items, terminator->value.return_value.values.count, function, block, block->nodes.count, id, origin, "return value")) return 0;
        for (size_t i = 0; i < function->result_types.count; i++) {
            const entity *result = find_entity(v, terminator->value.return_value.values.items[i].value);
            if (!type_compatible(
                    ((const abc_residual_value *)result->object)->type,
                    function->result_types.items[i]))
                return fail(v, id, origin, "return value %zu has the wrong type", i);
        }
        return 1;
    case ABC_ASDL_RESIDUAL_TERMINATOR_HALT:
        return validate_id_list(
            v, terminator->value.halt.values.items,
            terminator->value.halt.values.count,
            function, block, block->nodes.count,
            id, origin, "halt value");
    case ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL: {
        if (!abc_asdl_residual_call_kind_tag_name(terminator->value.tail_call.kind))
            return fail(v, id, origin, "tail call has invalid kind");
        const entity *direct_target = NULL;
        if (terminator->value.tail_call.kind == ABC_ASDL_RESIDUAL_CALL_KIND_DIRECT) {
            direct_target = require_entity(v, (abc_residual_id){terminator->value.tail_call.target},
                                           ENTITY_FUNCTION, id, origin, "direct-tail target");
            if (!direct_target) return 0;
        }
        if (terminator->value.tail_call.kind == ABC_ASDL_RESIDUAL_CALL_KIND_INDIRECT) {
            if (!terminator->value.tail_call.callee ||
                !validate_value_use(v, *terminator->value.tail_call.callee, function, block,
                                    block->nodes.count, id, origin, "tail callee"))
                return fail(v, id, origin, "indirect tail call has no valid callee");
        } else if (terminator->value.tail_call.callee) {
            return fail(v, id, origin, "non-indirect tail call unexpectedly has a callee value");
        }
        if (!validate_id_list(v, terminator->value.tail_call.arguments.items,
                              terminator->value.tail_call.arguments.count, function, block,
                              block->nodes.count, id, origin, "tail argument") ||
            !validate_call_abi(
                v, &terminator->value.tail_call.abi,
                terminator->value.tail_call.arguments.count,
                function->result_types.count,
                id, origin, "tail call"))
            return 0;
        if (!direct_target) return 1;
        const abc_residual_function *callee = direct_target->object;
        if (terminator->value.tail_call.arguments.count != callee->argument_types.count ||
            function->result_types.count != callee->result_types.count)
            return fail(v, id, origin, "direct tail call does not match its target arity");
        for (size_t i = 0; i < terminator->value.tail_call.arguments.count; i++) {
            const entity *argument = find_entity(v, terminator->value.tail_call.arguments.items[i].value);
            if (!type_compatible(
                    ((const abc_residual_value *)argument->object)->type,
                    callee->argument_types.items[i]))
                return fail(v, id, origin, "direct-tail argument %zu has the wrong type", i);
        }
        for (size_t i = 0; i < function->result_types.count; i++)
            if (!type_compatible(
                    callee->result_types.items[i],
                    function->result_types.items[i]))
                return fail(v, id, origin, "direct-tail result %zu has the wrong type", i);
        if (terminator->value.tail_call.abi.hidden_result_bytes !=
            callee->hidden_result_bytes)
            return fail(v, id, origin,
                        "direct-tail ABI has the wrong hidden-result size");
        return 1;
    }
    case ABC_ASDL_RESIDUAL_TERMINATOR_DYNAMIC_TAIL_CALL:
        if (terminator->value.dynamic_tail_call.arguments.count !=
            terminator->value.dynamic_tail_call.abi.arguments + 1)
            return fail(v, id, origin,
                        "dynamic tail call lacks its callable operand");
        if (!validate_call_abi(
                v, &terminator->value.dynamic_tail_call.abi,
                terminator->value.dynamic_tail_call.abi.arguments,
                function->result_types.count,
                id, origin, "dynamic tail call"))
            return 0;
        return validate_id_list(
            v, terminator->value.dynamic_tail_call.arguments.items,
            terminator->value.dynamic_tail_call.arguments.count,
            function, block, block->nodes.count,
            id, origin, "dynamic-tail argument");
    case ABC_ASDL_RESIDUAL_TERMINATOR_ABORT:
    case ABC_ASDL_RESIDUAL_TERMINATOR_UNREACHABLE:
        return 1;
    default: return 0;
    }
}

static int validate_functions(validator *v) {
    if (!sequence_present(v->program->functions.count, v->program->functions.items) ||
        !sequence_present(v->program->values.count, v->program->values.items)) return fail(v, 0, 0, "program has a missing sequence");
    for (size_t fi = 0; fi < v->program->functions.count; fi++) {
        const abc_residual_function *function = &v->program->functions.items[fi];
        if (!function->name.data || !sequence_present(function->argument_types.count, function->argument_types.items) ||
            !sequence_present(function->result_types.count, function->result_types.items) ||
            !sequence_present(function->arguments.count, function->arguments.items) ||
            !sequence_present(function->blocks.count, function->blocks.items)) return fail(v, function->id.value, 0, "function has a missing name or sequence");
        if (function->arguments.count != function->argument_types.count) return fail(v, function->id.value, 0, "function argument/type counts differ");
        const entity *entry = require_entity(v, function->entry, ENTITY_BLOCK, function->id.value, 0, "function entry");
        if (!entry || entry->function != function) return entry ? fail(v, function->id.value, 0, "function entry belongs to another function") : 0;
        for (size_t i = 0; i < function->argument_types.count; i++) {
            if (!abc_asdl_residual_type_tag_name(function->argument_types.items[i])) return fail(v, function->id.value, 0, "function has invalid argument type");
            const entity *argument = find_entity(v, function->arguments.items[i].value);
            if (((const abc_residual_value *)argument->object)->type != function->argument_types.items[i]) return fail(v, function->id.value, 0, "function argument %zu has the wrong type", i);
        }
        for (size_t i = 0; i < function->result_types.count; i++)
            if (!abc_asdl_residual_type_tag_name(function->result_types.items[i])) return fail(v, function->id.value, 0, "function has invalid result type");
        for (size_t bi = 0; bi < function->blocks.count; bi++) {
            const abc_residual_block *block = &function->blocks.items[bi];
            if (!sequence_present(block->arguments.count, block->arguments.items) || !sequence_present(block->nodes.count, block->nodes.items)) return fail(v, block->id.value, block->bytecode_offset, "block has a missing sequence");
            for (size_t ni = 0; ni < block->nodes.count; ni++) {
                const abc_residual_node *node = &block->nodes.items[ni];
                if (!sequence_present(node->results.count, node->results.items) || !validate_operation(v, function, block, node, ni)) return 0;
            }
            if (!validate_terminator(v, function, block)) return 0;
        }
    }
    return 1;
}

int abc_residual_validate(const abc_residual_program *program, abc_residual_diagnostic *diagnostic) {
    if (!diagnostic) return 0;
    memset(diagnostic, 0, sizeof(*diagnostic));
    if (!program) { snprintf(diagnostic->message, sizeof(diagnostic->message), "program is null"); return 0; }
    validator v = {.program = program, .diagnostic = diagnostic};
    int valid = validate_shape(&v) && collect_entities(&v) && collect_value_places(&v) &&
                validate_value_definitions(&v) && validate_functions(&v);
    free(v.entities);
    free(v.places);
    return valid;
}
