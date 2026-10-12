#include "residual_ir.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int checks;

static void check(int condition, const char *message) {
    checks++;
    if (condition) return;
    fprintf(stderr, "residual IR validation: %s\n", message);
    exit(1);
}

static abc_residual_program make_program(abc_residual_arena *arena) {
    abc_residual_id argument_id = abc_residual_new_id(arena);
    abc_residual_id constant_id = abc_residual_new_id(arena);
    abc_residual_id result_id = abc_residual_new_id(arena);
    abc_residual_id callable_id = abc_residual_new_id(arena);
    abc_residual_id function_id = abc_residual_new_id(arena);
    abc_residual_id block_id = abc_residual_new_id(arena);
    abc_residual_id callable_node_id = abc_residual_new_id(arena);
    abc_residual_id node_id = abc_residual_new_id(arena);

    abc_residual_value values[] = {
        {
            .id = argument_id, .type = ABC_ASDL_RESIDUAL_TYPE_U64,
            .facts = {.representation = ABC_ASDL_RESIDUAL_REPRESENTATION_RAW},
            .definition = {.tag = ABC_ASDL_RESIDUAL_DEFINITION_FUNCTION_ARGUMENT,
                           .value.function_argument = {.index = 0}},
            .origin = {.offset = 0x10}
        },
        {
            .id = constant_id, .type = ABC_ASDL_RESIDUAL_TYPE_U64,
            .facts = {.representation = ABC_ASDL_RESIDUAL_REPRESENTATION_RAW},
            .definition = {.tag = ABC_ASDL_RESIDUAL_DEFINITION_CONSTANT,
                           .value.constant = {.low = 1, .high = 0}},
            .origin = {.offset = 0x10}
        },
        {
            .id = result_id, .type = ABC_ASDL_RESIDUAL_TYPE_U64,
            .facts = {.representation = ABC_ASDL_RESIDUAL_REPRESENTATION_RAW},
            .definition = {.tag = ABC_ASDL_RESIDUAL_DEFINITION_INSTRUCTION_RESULT,
                           .value.instruction_result = {.instruction = node_id, .index = 0}},
            .origin = {.offset = 0x11}
        },
        {
            .id = callable_id, .type = ABC_ASDL_RESIDUAL_TYPE_ADDRESS,
            .facts = {.representation = ABC_ASDL_RESIDUAL_REPRESENTATION_RAW},
            .definition = {.tag = ABC_ASDL_RESIDUAL_DEFINITION_INSTRUCTION_RESULT,
                           .value.instruction_result = {.instruction = callable_node_id, .index = 0}},
            .origin = {.offset = 0x10}
        }
    };

    abc_residual_id operands[] = {argument_id, constant_id};
    abc_residual_id callable_results[] = {callable_id};
    abc_residual_node callable_node = {
        .id = callable_node_id,
        .results = {
            .count = 1,
            .items = abc_residual_copy(arena, callable_results, 1, sizeof(*callable_results))
        },
        .operation = {
            .tag = ABC_ASDL_RESIDUAL_OPERATION_FUNCTION_REFERENCE,
            .value.function_reference = {.function = function_id}
        },
        .origin = {.offset = 0x10}
    };
    abc_residual_id node_results[] = {result_id};
    abc_residual_node node = {
        .id = node_id,
        .results = {.count = 1, .items = abc_residual_copy(arena, node_results, 1, sizeof(*node_results))},
        .operation = {
            .tag = ABC_ASDL_RESIDUAL_OPERATION_BINARY,
            .value.binary = {.operation = ABC_ASDL_RESIDUAL_BINARY_OP_ADD,
                             .left = operands[0], .right = operands[1]}
        },
        .origin = {.offset = 0x11}
    };
    abc_residual_node nodes[] = {callable_node, node};

    abc_residual_id returned[] = {result_id};
    abc_residual_block block = {
        .id = block_id,
        .bytecode_offset = 0x10,
        .nodes = {.count = 2, .items = abc_residual_copy(arena, nodes, 2, sizeof(*nodes))},
        .terminator = {
            .tag = ABC_ASDL_RESIDUAL_TERMINATOR_RETURN,
            .value.return_value.abi = {
                .arguments = 1, .results = 1
            },
            .value.return_value.values = {
                .count = 1, .items = abc_residual_copy(arena, returned, 1, sizeof(*returned))
            },
            .origin = {.offset = 0x12}
        }
    };

    abc_residual_type argument_types[] = {ABC_ASDL_RESIDUAL_TYPE_U64};
    abc_residual_type result_types[] = {ABC_ASDL_RESIDUAL_TYPE_U64};
    abc_residual_id arguments[] = {argument_id};
    abc_residual_function function = {
        .id = function_id,
        .name = abc_residual_string(arena, "increment"),
        .argument_types = {.count = 1, .items = abc_residual_copy(arena, argument_types, 1, sizeof(*argument_types))},
        .result_types = {.count = 1, .items = abc_residual_copy(arena, result_types, 1, sizeof(*result_types))},
        .arguments = {.count = 1, .items = abc_residual_copy(arena, arguments, 1, sizeof(*arguments))},
        .entry = block_id,
        .blocks = {.count = 1, .items = abc_residual_copy(arena, &block, 1, sizeof(block))}
    };

    return (abc_residual_program){
        .functions = {.count = 1, .items = abc_residual_copy(arena, &function, 1, sizeof(function))},
        .values = {.count = 4, .items = abc_residual_copy(arena, values, 4, sizeof(*values))}
    };
}

static char *dump_program(const abc_residual_program *program) {
    FILE *file = tmpfile();
    check(file != NULL, "cannot create dump stream");
    check(abc_residual_dump(file, program), "dump failed");
    check(fflush(file) == 0 && fseek(file, 0, SEEK_END) == 0, "cannot measure dump");
    long length = ftell(file);
    check(length >= 0 && fseek(file, 0, SEEK_SET) == 0, "cannot seek dump");
    char *text = malloc((size_t)length + 1);
    check(text != NULL, "cannot allocate dump copy");
    check(fread(text, 1, (size_t)length, file) == (size_t)length, "cannot read dump");
    text[length] = '\0';
    fclose(file);
    return text;
}

int main(void) {
    abc_residual_arena *arena = abc_residual_arena_create();
    check(arena != NULL, "arena allocation failed");
    abc_residual_program program = make_program(arena);
    abc_residual_diagnostic diagnostic;
    check(abc_residual_validate(&program, &diagnostic), diagnostic.message);

    char *dump = dump_program(&program);
    check(strstr(dump, "function increment") != NULL, "dump omits function name");
    check(strstr(dump, "Binary(Add, v1, v2)") != NULL, "dump omits binary operation");
    check(strstr(dump, "FunctionReference(function=v5)") != NULL, "dump omits function reference");
    check(strstr(dump, "return abi=1/1/0/0 v3") != NULL,
          "dump omits return ABI or value");
    check(strstr(dump, "# bytecode 0x12") != NULL, "dump omits terminator provenance");
    free(dump);

    abc_residual_value *result = &program.values.items[2];
    result->definition.value.instruction_result.instruction = (abc_residual_id){999};
    check(!abc_residual_validate(&program, &diagnostic), "mismatched result definition was accepted");
    check(strstr(diagnostic.message, "does not match") != NULL, "mismatched result diagnostic is unclear");
    result->definition.value.instruction_result.instruction =
        program.functions.items[0].blocks.items[0].nodes.items[1].id;

    abc_residual_node *node = &program.functions.items[0].blocks.items[0].nodes.items[1];
    abc_residual_id saved = node->operation.value.binary.left;
    node->operation.value.binary.left = result->id;
    check(!abc_residual_validate(&program, &diagnostic), "use before definition was accepted");
    check(strstr(diagnostic.message, "before its definition") != NULL, "use-before-definition diagnostic is unclear");
    node->operation.value.binary.left = saved;

    abc_residual_id *saved_results = node->results.items;
    node->results.items = NULL;
    check(!abc_residual_validate(&program, &diagnostic), "missing result sequence was accepted");
    check(strstr(diagnostic.message, "missing result sequence") != NULL, "missing-sequence diagnostic is unclear");
    node->results.items = saved_results;

    abc_residual_node *callable = &program.functions.items[0].blocks.items[0].nodes.items[0];
    abc_residual_id saved_function = callable->operation.value.function_reference.function;
    callable->operation.value.function_reference.function = (abc_residual_id){999};
    check(!abc_residual_validate(&program, &diagnostic), "invalid function reference was accepted");
    check(strstr(diagnostic.message, "function-reference target") != NULL,
          "invalid function-reference diagnostic is unclear");
    callable->operation.value.function_reference.function = saved_function;

    abc_residual_type saved_callable_type = program.values.items[3].type;
    program.values.items[3].type = ABC_ASDL_RESIDUAL_TYPE_U64;
    check(!abc_residual_validate(&program, &diagnostic), "non-address function reference was accepted");
    check(strstr(diagnostic.message, "address type") != NULL,
          "function-reference result diagnostic is unclear");
    program.values.items[3].type = saved_callable_type;

    abc_residual_origin terminator_caller = {.offset = 0x20};
    program.functions.items[0].blocks.items[0].terminator.origin =
        abc_residual_make_origin(arena, 0x12, &terminator_caller);
    check(abc_residual_validate(&program, &diagnostic), diagnostic.message);
    check(program.functions.items[0].blocks.items[0].terminator.origin.caller &&
          program.functions.items[0].blocks.items[0].terminator.origin.caller->offset == 0x20,
          "terminator origin chain was not copied");

    program.functions.items[0].arguments.items[0] = program.values.items[1].id;
    check(!abc_residual_validate(&program, &diagnostic), "constant function argument was accepted");
    check(strstr(diagnostic.message, "more than one definition site") != NULL ||
          strstr(diagnostic.message, "does not match") != NULL, "constant argument diagnostic is unclear");

    abc_residual_origin caller = {.offset = 7};
    abc_residual_origin nested = abc_residual_make_origin(arena, 9, &caller);
    check(nested.caller && nested.caller->offset == 7, "origin chain was not copied");
    check(abc_residual_allocate(arena, SIZE_MAX, 2) == NULL, "overflowing arena allocation succeeded");

    abc_residual_arena_free(arena);
    printf("validated residual arena, IDs, whole-program invariants, and readable dumps (%d checks)\n", checks);
    return 0;
}
