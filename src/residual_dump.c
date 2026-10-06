#include "residual_ir.h"

#include <inttypes.h>

static void print_id(FILE *output, abc_residual_id id) {
    fprintf(output, "v%" PRIu64, id.value);
}

static void print_ids(FILE *output, const abc_residual_id *items, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (i) fputs(", ", output);
        print_id(output, items[i]);
    }
}

static void print_edge(FILE *output, const abc_residual_edge *edge) {
    fprintf(output, "block_%" PRIu64 "(", edge->target.value);
    print_ids(output, edge->arguments.items, edge->arguments.count);
    fputc(')', output);
}

static void print_effects(FILE *output, const abc_residual_effect *effect) {
    if (!effect->may_trap && !effect->reads_memory && !effect->writes_memory && !effect->calls && !effect->safepoint) return;
    fputs(" [", output);
    const char *separator = "";
    #define EFFECT(FIELD, NAME) do { if (effect->FIELD) { fputs(separator, output); fputs((NAME), output); separator = ","; } } while (0)
    EFFECT(may_trap, "trap");
    EFFECT(reads_memory, "read");
    EFFECT(writes_memory, "write");
    EFFECT(calls, "call");
    EFFECT(safepoint, "safepoint");
    #undef EFFECT
    fputc(']', output);
}

static void print_operation(FILE *output, const abc_residual_operation *operation) {
    const char *name = abc_asdl_residual_operation_tag_name(operation->tag);
    fputs(name ? name : "<invalid-operation>", output);
    fputc('(', output);
    switch (operation->tag) {
    case ABC_ASDL_RESIDUAL_OPERATION_UNARY:
        fputs(abc_asdl_residual_unary_op_tag_name(operation->value.unary.operation), output);
        fputs(", ", output); print_id(output, operation->value.unary.input); break;
    case ABC_ASDL_RESIDUAL_OPERATION_BINARY:
        fputs(abc_asdl_residual_binary_op_tag_name(operation->value.binary.operation), output);
        fputs(", ", output); print_id(output, operation->value.binary.left);
        fputs(", ", output); print_id(output, operation->value.binary.right); break;
    case ABC_ASDL_RESIDUAL_OPERATION_CHECK:
        fputs(abc_asdl_residual_check_op_tag_name(operation->value.check.operation), output);
        fputs(", ", output); print_id(output, operation->value.check.input);
        fprintf(output, ", reason=%" PRIu64, operation->value.check.reason); break;
    case ABC_ASDL_RESIDUAL_OPERATION_CONVERT:
        fputs(abc_asdl_residual_convert_op_tag_name(operation->value.convert.operation), output);
        fputs(", ", output); print_id(output, operation->value.convert.input); break;
    case ABC_ASDL_RESIDUAL_OPERATION_LOAD:
        fputs(abc_asdl_residual_address_space_tag_name(operation->value.load.space), output);
        fprintf(output, ", width=%" PRIu64 ", ", operation->value.load.width);
        print_id(output, operation->value.load.address);
        fprintf(output, ", offset=%" PRIu64, operation->value.load.offset); break;
    case ABC_ASDL_RESIDUAL_OPERATION_STORE:
        fputs(abc_asdl_residual_address_space_tag_name(operation->value.store.space), output);
        fprintf(output, ", width=%" PRIu64 ", ", operation->value.store.width);
        print_id(output, operation->value.store.address); fputs(", ", output);
        print_id(output, operation->value.store.value); break;
    case ABC_ASDL_RESIDUAL_OPERATION_COPY_MEMORY:
        print_id(output, operation->value.copy_memory.destination); fputs(", ", output);
        print_id(output, operation->value.copy_memory.source);
        fprintf(output, ", bytes=%" PRIu64, operation->value.copy_memory.bytes); break;
    case ABC_ASDL_RESIDUAL_OPERATION_CLEAR_FRAME:
        fprintf(output, "first=%" PRIu64 ", cells=%" PRIu64, operation->value.clear_frame.first_cell, operation->value.clear_frame.cells); break;
    case ABC_ASDL_RESIDUAL_OPERATION_FRAME_ADDRESS:
        fprintf(output, "offset=%" PRIu64, operation->value.frame_address.offset); break;
    case ABC_ASDL_RESIDUAL_OPERATION_IMAGE_ADDRESS:
        fprintf(output, "offset=%" PRIu64, operation->value.image_address.offset); break;
    case ABC_ASDL_RESIDUAL_OPERATION_FUNCTION_REFERENCE:
        fputs("function=", output);
        print_id(output, operation->value.function_reference.function);
        break;
    case ABC_ASDL_RESIDUAL_OPERATION_CALLABLE_CONSTRUCTOR:
        fputs("target=", output);
        print_id(output, operation->value.callable_constructor.target);
        fprintf(output, ", signature=%" PRIu64 ", descriptor=%" PRIu64
                ", environment_cells=%" PRIu64,
                operation->value.callable_constructor.signature,
                operation->value.callable_constructor.descriptor,
                operation->value.callable_constructor.environment_cells);
        if (operation->value.callable_constructor.environment) {
            fputs(", environment=", output);
            print_id(
                output,
                *operation->value.callable_constructor.environment);
        }
        break;
    case ABC_ASDL_RESIDUAL_OPERATION_CALL:
        fputs(abc_asdl_residual_call_kind_tag_name(operation->value.call.kind), output);
        fprintf(output, ", target=%" PRIu64
                ", abi=%" PRIu64 "/%" PRIu64 "/%" PRIu64 "/%" PRIu64,
                operation->value.call.target,
                operation->value.call.abi.arguments,
                operation->value.call.abi.results,
                operation->value.call.abi.frame_cells,
                operation->value.call.abi.hidden_result_bytes);
        if (operation->value.call.callee) { fputs(", ", output); print_id(output, *operation->value.call.callee); }
        if (operation->value.call.arguments.count) { fputs(", args=[", output); print_ids(output, operation->value.call.arguments.items, operation->value.call.arguments.count); fputc(']', output); }
        break;
    case ABC_ASDL_RESIDUAL_OPERATION_MATERIALIZE:
        fputs(abc_asdl_residual_materialize_kind_tag_name(operation->value.materialize.kind), output);
        fputs(", ", output); print_id(output, operation->value.materialize.input); break;
    case ABC_ASDL_RESIDUAL_OPERATION_DYNAMIC_OPERATION:
        fprintf(output, "selector=%" PRIu64 ", descriptor=%" PRIu64,
                operation->value.dynamic_operation.selector,
                operation->value.dynamic_operation.descriptor);
        if (operation->value.dynamic_operation.literal) {
            const abc_asdl_residual_dynamic_literal *literal =
                operation->value.dynamic_operation.literal;
            fprintf(output, ", literal=%" PRIu64 "/%" PRIu64
                    "/0x%" PRIx64 "/0x%" PRIx64 ", reverse=%s",
                    literal->primitive, literal->flags,
                    literal->low, literal->high,
                    operation->value.dynamic_operation.reverse
                        ? "true" : "false");
        }
        fputs(", args=[", output);
        print_ids(output, operation->value.dynamic_operation.arguments.items, operation->value.dynamic_operation.arguments.count); fputc(']', output); break;
    case ABC_ASDL_RESIDUAL_OPERATION_DYNAMIC_CALL:
        fprintf(output, "abi=%" PRIu64 "/%" PRIu64 "/%" PRIu64
                "/%" PRIu64 ", adjustment=%" PRIu64 ", args=[",
                operation->value.dynamic_call.abi.arguments,
                operation->value.dynamic_call.abi.results,
                operation->value.dynamic_call.abi.frame_cells,
                operation->value.dynamic_call.abi.hidden_result_bytes,
                operation->value.dynamic_call.adjustment);
        print_ids(output, operation->value.dynamic_call.arguments.items,
                  operation->value.dynamic_call.arguments.count);
        fputc(']', output);
        break;
    case ABC_ASDL_RESIDUAL_OPERATION_MANAGED_WRITE:
        print_id(output, operation->value.managed_write.address);
        fprintf(output, ", offset=%" PRIu64 ", bytes=%" PRIu64, operation->value.managed_write.offset, operation->value.managed_write.bytes); break;
    default: break;
    }
    fputc(')', output);
}

static void print_terminator(FILE *output, const abc_residual_terminator *terminator) {
    switch (terminator->tag) {
    case ABC_ASDL_RESIDUAL_TERMINATOR_JUMP:
        fputs("jump ", output); print_edge(output, &terminator->value.jump.edge); break;
    case ABC_ASDL_RESIDUAL_TERMINATOR_BRANCH:
        fputs("branch ", output);
        fputs(abc_asdl_residual_binary_op_tag_name(terminator->value.branch.relation), output);
        fputc(' ', output); print_id(output, terminator->value.branch.left);
        fputs(", ", output); print_id(output, terminator->value.branch.right);
        fputs(" ? ", output); print_edge(output, &terminator->value.branch.yes);
        fputs(" : ", output); print_edge(output, &terminator->value.branch.no); break;
    case ABC_ASDL_RESIDUAL_TERMINATOR_SWITCH:
        fputs("switch ", output); print_id(output, terminator->value.switch_value.value);
        for (size_t i = 0; i < terminator->value.switch_value.arms.count; i++) {
            const abc_residual_switch_arm *arm = &terminator->value.switch_value.arms.items[i];
            fprintf(output, " [%" PRIu64 "..%" PRIu64 ": ", arm->value_low, arm->value_high);
            print_edge(output, &arm->edge); fputc(']', output);
        }
        fputs(" default ", output); print_edge(output, &terminator->value.switch_value.fallback); break;
    case ABC_ASDL_RESIDUAL_TERMINATOR_RETURN:
        fprintf(output, "return abi=%" PRIu64 "/%" PRIu64 "/%" PRIu64
                "/%" PRIu64 " ",
                terminator->value.return_value.abi.arguments,
                terminator->value.return_value.abi.results,
                terminator->value.return_value.abi.frame_cells,
                terminator->value.return_value.abi.hidden_result_bytes);
        print_ids(output, terminator->value.return_value.values.items,
                  terminator->value.return_value.values.count);
        break;
    case ABC_ASDL_RESIDUAL_TERMINATOR_HALT:
        fputs("halt ", output);
        print_ids(output, terminator->value.halt.values.items,
                  terminator->value.halt.values.count);
        break;
    case ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL:
        fputs("tail ", output); fputs(abc_asdl_residual_call_kind_tag_name(terminator->value.tail_call.kind), output);
        fprintf(output, " target=%" PRIu64
                " abi=%" PRIu64 "/%" PRIu64 "/%" PRIu64 "/%" PRIu64
                "(", terminator->value.tail_call.target,
                terminator->value.tail_call.abi.arguments,
                terminator->value.tail_call.abi.results,
                terminator->value.tail_call.abi.frame_cells,
                terminator->value.tail_call.abi.hidden_result_bytes);
        print_ids(output, terminator->value.tail_call.arguments.items, terminator->value.tail_call.arguments.count); fputc(')', output); break;
    case ABC_ASDL_RESIDUAL_TERMINATOR_DYNAMIC_TAIL_CALL:
        fprintf(output, "dynamic-tail abi=%" PRIu64 "/%" PRIu64
                "/%" PRIu64 "/%" PRIu64 ", adjustment=%" PRIu64
                " (",
                terminator->value.dynamic_tail_call.abi.arguments,
                terminator->value.dynamic_tail_call.abi.results,
                terminator->value.dynamic_tail_call.abi.frame_cells,
                terminator->value.dynamic_tail_call.abi.hidden_result_bytes,
                terminator->value.dynamic_tail_call.adjustment);
        print_ids(output,
                  terminator->value.dynamic_tail_call.arguments.items,
                  terminator->value.dynamic_tail_call.arguments.count);
        fputc(')', output);
        break;
    case ABC_ASDL_RESIDUAL_TERMINATOR_ABORT:
        fprintf(output, "abort reason=%" PRIu64, terminator->value.abort.reason); break;
    case ABC_ASDL_RESIDUAL_TERMINATOR_UNREACHABLE:
        fputs("unreachable", output); break;
    default: fputs("<invalid-terminator>", output); break;
    }
}

int abc_residual_dump(FILE *output, const abc_residual_program *program) {
    if (!output || !program) return 0;
    for (size_t fi = 0; fi < program->functions.count; fi++) {
        const abc_residual_function *function = &program->functions.items[fi];
        fputs("function ", output);
        fwrite(function->name.data, 1, function->name.length, output);
        fprintf(output, " #%" PRIu64 "(", function->id.value);
        print_ids(output, function->arguments.items, function->arguments.count);
        fprintf(output, ") hidden_result_bytes=%" PRIu64 " {\n",
                function->hidden_result_bytes);
        for (size_t bi = 0; bi < function->blocks.count; bi++) {
            const abc_residual_block *block = &function->blocks.items[bi];
            fprintf(output, "  block_%" PRIu64 "(", block->id.value);
            print_ids(output, block->arguments.items, block->arguments.count);
            fprintf(output, "):  # bytecode 0x%" PRIx64 "\n", block->bytecode_offset);
            for (size_t ni = 0; ni < block->nodes.count; ni++) {
                const abc_residual_node *node = &block->nodes.items[ni];
                fputs("    ", output);
                if (node->results.count) { print_ids(output, node->results.items, node->results.count); fputs(" = ", output); }
                print_operation(output, &node->operation);
                print_effects(output, &node->effect);
                fprintf(output, "  # node %" PRIu64 ", bytecode 0x%" PRIx64 "\n", node->id.value, node->origin.offset);
            }
            fputs("    ", output); print_terminator(output, &block->terminator);
            fprintf(output, "  # bytecode 0x%" PRIx64 "\n", block->terminator.origin.offset);
        }
        fputs("}\n", output);
    }
    return !ferror(output);
}
