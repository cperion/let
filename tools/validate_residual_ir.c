#include "residual_ir.h"
#include "residual_builder.h"

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

/* Exercise the actual symbolic-to-IR boundary, independently of the opcode
 * generator: revision-6 instruction bytes and expected operand roles are fixed. */
static abc_residual_bundle *build_checked(abc_module *module) {
    abc_error error;
    abc_residual_build_diagnostic build_error;
    abc_residual_diagnostic validation_error;
    abc_residual_bundle *bundle = NULL;
    check(abc_verify_module(module, &error) == ABC_OK, error.message);
    check(abc_residual_build(module, NULL, &bundle, &build_error) ==
          ABC_RESIDUAL_BUILD_OK, build_error.message);
    const abc_residual_source_function *sources =
        abc_residual_bundle_source_functions(bundle);
    for (unsigned i = 0; i < module->function_count; i++) {
        if (!sources[i].supported)
            fprintf(stderr,"declined fixture: function %u, initial bytes %02x %02x %02x\n",
                    i,module->code[0],module->code[1],module->code[2]);
        check(sources[i].supported, "builder unexpectedly declined a source function");
    }
    check(abc_residual_validate(abc_residual_bundle_program(bundle),
          &validation_error), validation_error.message);
    return bundle;
}

static const abc_residual_node *node_at(const abc_residual_function *function,
                                        unsigned origin) {
    for (size_t i = 0; i < function->blocks.count; i++) {
        const abc_residual_block *block = &function->blocks.items[i];
        for (size_t j = 0; j < block->nodes.count; j++)
            if (block->nodes.items[j].origin.offset == origin)
                return &block->nodes.items[j];
    }
    check(0, "missing residual operation at original PC");
    return NULL;
}

/* Straight-line fixtures may acquire entry/continuation block parameters.
 * Follow their explicit jump transport, rather than assuming raw IDs survive. */
static uint64_t transport_source(const abc_residual_function *function, uint64_t value) {
    for (size_t step=0;step<function->blocks.count;step++) {
        uint64_t previous=value;
        for (size_t i=0;i<function->blocks.count;i++) {
            const abc_residual_block *block=&function->blocks.items[i];
            for(size_t j=0;j<block->arguments.count;j++) if(block->arguments.items[j].value==value) {
                for(size_t k=0;k<function->blocks.count;k++) {
                    const abc_residual_terminator *term=&function->blocks.items[k].terminator;
                    if(term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_JUMP &&
                       term->value.jump.edge.target.value==block->id.value) {
                        value=term->value.jump.edge.arguments.items[j].value;
                        goto transported;
                    }
                }
            }
        }
transported:
        if(value==previous)break;
    }
    return value;
}
static int same_value(const abc_residual_function *function, abc_residual_id left, abc_residual_id right) {
    return transport_source(function,left.value)==transport_source(function,right.value);
}
static const abc_residual_terminator *terminator_at(const abc_residual_function *function,unsigned origin) {
    for(size_t i=0;i<function->blocks.count;i++) {
        const abc_residual_terminator *term=&function->blocks.items[i].terminator;
        if(term->origin.offset==origin && term->tag!=ABC_ASDL_RESIDUAL_TERMINATOR_JUMP)return term;
    }
    check(0,"missing residual terminator at original PC");return NULL;
}

static void check_builder_scalars(void) {
    static const struct {
        uint8_t opcode;
        abc_asdl_residual_binary_op operation;
        unsigned floating;
    } binary[] = {
        {0x22, ABC_ASDL_RESIDUAL_BINARY_OP_SUB, 0},
        {0x26, ABC_ASDL_RESIDUAL_BINARY_OP_DIV_UNSIGNED, 0},
        {0x34, ABC_ASDL_RESIDUAL_BINARY_OP_SHIFT_LEFT, 0},
        {0x54, ABC_ASDL_RESIDUAL_BINARY_OP_POW_UNSIGNED, 0},
        {0xdc, ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_SUB, 1}
    };
    for (unsigned bank = 0; bank < 2; bank++) {
        for (size_t i = 0; i < sizeof(binary)/sizeof(binary[0]); i++) {
            uint8_t code[] = {(uint8_t)(0x14+bank), (uint8_t)(0x16+(bank^1)),
                (uint8_t)(binary[i].opcode+bank), (uint8_t)(0x8a+bank), 2, 1};
            abc_function source = {.end=sizeof(code), .arguments=2, .results=1};
            if (binary[i].floating) {
                source.argument_kinds[0]=source.argument_kinds[1]=ABC_KIND_FLOAT;
                source.result_kinds[0]=ABC_KIND_FLOAT;
            }
            abc_module module = {.code=code, .code_size=sizeof(code),
                .functions=&source, .function_count=1, .memory_profile=binary[i].floating};
            abc_residual_bundle *bundle=build_checked(&module);
            const abc_residual_function *function=&abc_residual_bundle_program(bundle)->functions.items[0];
            const abc_residual_node *node=node_at(function,2);
            check(node->operation.tag==ABC_ASDL_RESIDUAL_OPERATION_BINARY &&
                  node->operation.value.binary.operation==binary[i].operation,
                  "scalar semantic identity was confused with its encoded byte");
            check(same_value(function,node->operation.value.binary.left,function->arguments.items[0]) &&
                  same_value(function,node->operation.value.binary.right,function->arguments.items[1]),
                  "selected-first operands reversed in residual IR");
            abc_residual_bundle_free(bundle);
        }
        for (unsigned width=0; width<2; width++) {
            uint8_t code[]={(uint8_t)(0x14+bank),(uint8_t)(0x50+2*width+bank),
                            (uint8_t)(0x8a+bank),1,1};
            abc_function source={.end=sizeof(code),.arguments=1,.results=1};
            abc_module module={.code=code,.code_size=sizeof(code),.functions=&source,.function_count=1};
            abc_residual_bundle *bundle=build_checked(&module);
            const abc_residual_program *program=abc_residual_bundle_program(bundle);
            const abc_residual_function *function=&program->functions.items[0];
            const abc_residual_node *node=node_at(function,1);
            check(node->operation.tag==ABC_ASDL_RESIDUAL_OPERATION_UNARY &&
                  node->operation.value.unary.operation==(width?ABC_ASDL_RESIDUAL_UNARY_OP_ZERO_EXTEND16:ABC_ASDL_RESIDUAL_UNARY_OP_ZERO_EXTEND8) &&
                  same_value(function,node->operation.value.unary.input,function->arguments.items[0]),
                  "narrow normalization identity/input changed");
            unsigned typed=0;
            for(size_t i=0;i<program->values.count;i++)
                if(program->values.items[i].id.value==node->results.items[0].value)
                    typed=program->values.items[i].type==ABC_ASDL_RESIDUAL_TYPE_U32;
            check(typed,"narrow normalization must use existing U32 representation");
            check(same_value(function,terminator_at(function,2)->value.return_value.values.items[0],node->results.items[0]),
                  "narrow normalization lost selected return source");
            abc_residual_bundle_free(bundle);
        }
        /* A C-operand EXT has one semantic identity, not the EXT prefix byte. */
        uint8_t extended[] = {(uint8_t)(0x14+bank), (uint8_t)(0xf8+bank), 1, 1,
                              (uint8_t)(0x8a+bank), 2, 1};
        abc_function source={.end=sizeof(extended), .arguments=2, .results=1};
        abc_module module={.code=extended, .code_size=sizeof(extended), .functions=&source, .function_count=1};
        abc_residual_bundle *bundle=build_checked(&module);
        const abc_residual_function *function=&abc_residual_bundle_program(bundle)->functions.items[0];
        const abc_residual_node *node=node_at(function,1);
        check(node->operation.value.binary.operation==ABC_ASDL_RESIDUAL_BINARY_OP_SUB &&
              same_value(function,node->operation.value.binary.left,function->arguments.items[0]) &&
              same_value(function,node->operation.value.binary.right,function->arguments.items[1]),
              "extended C operand lost semantic identity or operand order");
        abc_residual_bundle_free(bundle);

        uint8_t conversion[] = {(uint8_t)(0x14+bank), (uint8_t)(0xea+bank), (uint8_t)(0xee + bank),
                                (uint8_t)(0x58+bank), (uint8_t)(0x8a+bank), 1, 1};
        source=(abc_function){.end=sizeof(conversion), .arguments=1, .results=1};
        module.code=conversion;module.code_size=sizeof(conversion);module.memory_profile=1;
        bundle=build_checked(&module);
        function=&abc_residual_bundle_program(bundle)->functions.items[0];
        const abc_residual_node *to_float=node_at(function,1), *from_float=node_at(function,2);
        node=node_at(function,3);
        check(to_float->operation.value.unary.operation==ABC_ASDL_RESIDUAL_UNARY_OP_SIGNED_TO_FLOAT &&
              from_float->operation.value.unary.operation==ABC_ASDL_RESIDUAL_UNARY_OP_FLOAT_TO_SIGNED &&
              from_float->operation.value.unary.input.value==to_float->results.items[0].value,
              "selected conversion did not feed the next selected operation");
        check(node->operation.tag==ABC_ASDL_RESIDUAL_OPERATION_CHECK &&
              node->operation.value.check.input.value==from_float->results.items[0].value,
              "selected check did not consume its supplied value");
        abc_residual_bundle_free(bundle);
    }
}

static void check_builder_float_branches(void) {
    const abc_asdl_residual_binary_op relations[]={ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_LESS,
        ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_LESS_EQUAL,ABC_ASDL_RESIDUAL_BINARY_OP_FLOAT_EQUAL};
    for(unsigned operation=0;operation<3;operation++)for(unsigned bank=0;bank<2;bank++) {
        /* Independent revision-6 bytes: CGET0.X, CGET1.Y, FB*.X, two returns. */
        uint8_t code[]={(uint8_t)(0x14+bank),(uint8_t)(0x16+(bank^1)),
            (uint8_t)(0xf2+2*operation+bank),5,0,
            (uint8_t)(0x02+bank),0,(uint8_t)(0x8a+bank),2,1,
            (uint8_t)(0x02+bank),1,(uint8_t)(0x8a+bank),2,1};
        abc_function source={.end=sizeof(code),.arguments=2,.results=1};
        source.argument_kinds[0]=source.argument_kinds[1]=ABC_KIND_FLOAT;
        abc_module module={.code=code,.code_size=sizeof(code),.functions=&source,.function_count=1,.memory_profile=1};
        abc_residual_bundle *bundle=build_checked(&module);
        const abc_residual_function *function=&abc_residual_bundle_program(bundle)->functions.items[0];
        const abc_residual_terminator *term=terminator_at(function,2);
        check(term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_BRANCH &&
              term->value.branch.relation==relations[operation],"floating branch relation lost in residual IR");
        check(same_value(function,term->value.branch.left,function->arguments.items[0]) &&
              same_value(function,term->value.branch.right,function->arguments.items[1]),
              "floating branch selected-first operand order lost in residual IR");
        abc_residual_bundle_free(bundle);
    }
}

static void check_builder_calls(void) {
    for (unsigned bank=0;bank<2;bank++) for(unsigned result_bank=0;result_bank<2;result_bank++) {
        /* Both caller banks have a live prefix; only the chosen bank passes arg2. */
        uint8_t code[]={0x14,0x17,(uint8_t)(0x18+bank),2,
            (uint8_t)(0x86+bank),4,0,0,0,1,(uint8_t)(0x0e + (bank^1)),
            (uint8_t)(0x8a+bank),3,3,(uint8_t)(0x14+result_bank),
            (uint8_t)(0x8a+result_bank),1,1};
        abc_function sources[]={{.entry=0,.end=14,.arguments=3,.results=3},
                                {.entry=14,.end=sizeof(code),.arguments=1,.results=1}};
        abc_module module={.code=code,.code_size=sizeof(code),.functions=sources,.function_count=2};
        abc_residual_bundle *bundle=build_checked(&module);
        const abc_residual_program *program=abc_residual_bundle_program(bundle);
        const abc_residual_function *function=&program->functions.items[0];
        const abc_residual_node *call=node_at(function,4);
        check(call->operation.tag==ABC_ASDL_RESIDUAL_OPERATION_CALL &&
              same_value(function,call->operation.value.call.arguments.items[0],function->arguments.items[2]),
              "CALL gathered from the wrong bank");
        const abc_residual_terminator *returned=terminator_at(function,11);
        check(returned->tag==ABC_ASDL_RESIDUAL_TERMINATOR_RETURN &&
              returned->value.return_value.values.count==3 &&
              same_value(function,returned->value.return_value.values.items[0],function->arguments.items[bank]) &&
              same_value(function,returned->value.return_value.values.items[1],call->results.items[0]) &&
              same_value(function,returned->value.return_value.values.items[2],function->arguments.items[bank^1]),
              "CALL result destination or ordered RET vector damaged a live prefix");
        const abc_residual_function *callee=&program->functions.items[1];
        check(same_value(callee,terminator_at(callee,15)->value.return_value.values.items[0],callee->arguments.items[0]),
              "callee RET source depends on its caller's destination");
        abc_residual_bundle_free(bundle);
    }
    for(unsigned bank=0;bank<2;bank++) for(unsigned tail=0;tail<2;tail++) {
        uint8_t code[]={(uint8_t)(0x14+bank),(uint8_t)(0x16+bank),
            (uint8_t)(0x18+(bank^1)),2,(uint8_t)((tail?0xd6:0xd4)+bank),
            (uint8_t)(tail?3:2),2,(uint8_t)(0x8a+bank),3,1};
        if(!tail) {code[6]=(uint8_t)(0x8a+bank);code[7]=3;code[8]=1;}
        unsigned length=tail?7:9;
        abc_function source={.end=length,.arguments=3,.results=1,
                             .argument_kinds={ABC_KIND_ADDR,ABC_KIND_INT,ABC_KIND_ADDR}};
        abc_function site={.entry=4,.arguments=2,.results=1,.argument_kinds={ABC_KIND_ADDR,ABC_KIND_INT}};
        abc_module module={.code=code,.code_size=length,.functions=&source,.function_count=1,
                           .memory_profile=1,.callable_profile=1,.sites=&site,.site_count=1};
        abc_residual_bundle *bundle=build_checked(&module);
        const abc_residual_function *function=&abc_residual_bundle_program(bundle)->functions.items[0];
        const abc_residual_id *arguments;
        abc_residual_id callee;
        if(tail) {
            const abc_residual_terminator *term=terminator_at(function,4);
            check(term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL,"indirect tail lost explicit transfer");
            arguments=term->value.tail_call.arguments.items;callee=*term->value.tail_call.callee;
        } else {
            const abc_residual_node *call=node_at(function,4);
            arguments=call->operation.value.call.arguments.items;callee=*call->operation.value.call.callee;
        }
        check(same_value(function,arguments[0],function->arguments.items[0]) &&
              same_value(function,arguments[1],function->arguments.items[1]) &&
              same_value(function,callee,function->arguments.items[2]),
              "indirect call/tail argument bank, order or opposite target changed");
        abc_residual_bundle_free(bundle);
    }
}

static uint64_t constant_bits(const abc_residual_program *program,abc_residual_id id) {
    for(size_t i=0;i<program->values.count;i++) {
        const abc_residual_value *value=&program->values.items[i];
        if(value->id.value==id.value) {
            check(value->definition.tag==ABC_ASDL_RESIDUAL_DEFINITION_CONSTANT,"expected an explicit residual constant");
            return value->definition.value.constant.low;
        }
    }
    check(0,"missing constant definition");return 0;
}

static void check_builder_transfers(void) {
    for(unsigned bank=0;bank<2;bank++) {
        uint8_t capture[]={(uint8_t)(0x18+(bank^1)),2,(uint8_t)(0x14+bank),
            (uint8_t)(0x16+(bank^1)),(uint8_t)(0x1c+(bank^1)),(uint8_t)(0x14+(bank^1)),
            (uint8_t)(0x22+bank),(uint8_t)(0x0e + (bank^1)),(uint8_t)(0x8a+bank),3,2};
        abc_function source={.end=sizeof(capture),.arguments=3,.results=2};
        abc_module module={.code=capture,.code_size=sizeof(capture),.functions=&source,.function_count=1};
        abc_residual_bundle *bundle=build_checked(&module);
        const abc_residual_program *program=abc_residual_bundle_program(bundle);
        const abc_residual_function *function=&program->functions.items[0];
        const abc_residual_node *node=node_at(function,6);
        const abc_residual_terminator *term=terminator_at(function,8);
        check(same_value(function,node->operation.value.binary.left,function->arguments.items[0]) &&
              same_value(function,node->operation.value.binary.right,function->arguments.items[1]) &&
              same_value(function,term->value.return_value.values.items[0],node->results.items[0]) &&
              same_value(function,term->value.return_value.values.items[1],function->arguments.items[2]),
              "C replacement lost the captured value or the opposite live prefix");
        abc_residual_bundle_free(bundle);

        uint8_t immediate[]={(uint8_t)(0x14+bank),(uint8_t)(0x76+bank),3,
                             (uint8_t)(0x4a+bank),(uint8_t)(0x8a+bank),1,1};
        source=(abc_function){.end=sizeof(immediate),.arguments=1,.results=1};
        module.code=immediate;module.code_size=sizeof(immediate);
        bundle=build_checked(&module);program=abc_residual_bundle_program(bundle);function=&program->functions.items[0];
        node=node_at(function,1);
        check(node->operation.value.binary.operation==ABC_ASDL_RESIDUAL_BINARY_OP_SUB &&
              same_value(function,node->operation.value.binary.left,function->arguments.items[0]) &&
              constant_bits(program,node->operation.value.binary.right)==3 &&
              node_at(function,3)->operation.value.unary.operation==ABC_ASDL_RESIDUAL_UNARY_OP_LOGICAL_NOT,
              "immediate or unary semantic identity changed");
        abc_residual_bundle_free(bundle);

        uint8_t foreign[]={(uint8_t)(0x14+(bank^1)),(uint8_t)(0x14+bank),(uint8_t)(0x16+bank),
            (uint8_t)(0xd8+bank),0,0,(uint8_t)(0x0e + (bank^1)),(uint8_t)(0x8a+bank),2,2};
        abc_extern external={.name="test_foreign",.arguments=2,.results=1};
        source=(abc_function){.end=sizeof(foreign),.arguments=2,.results=2};
        module=(abc_module){.code=foreign,.code_size=sizeof(foreign),.functions=&source,.function_count=1,
            .memory_profile=1,.callable_profile=1,.foreign_profile=1,.externs=&external,.extern_count=1};
        bundle=build_checked(&module);function=&abc_residual_bundle_program(bundle)->functions.items[0];
        node=node_at(function,3);term=terminator_at(function,7);
        check(node->operation.value.call.kind==ABC_ASDL_RESIDUAL_CALL_KIND_FOREIGN &&
              same_value(function,node->operation.value.call.arguments.items[0],function->arguments.items[0]) &&
              same_value(function,node->operation.value.call.arguments.items[1],function->arguments.items[1]) &&
              same_value(function,term->value.return_value.values.items[0],node->results.items[0]) &&
              same_value(function,term->value.return_value.values.items[1],function->arguments.items[0]),
              "foreign selected arguments/results damaged the opposite prefix");
        abc_residual_bundle_free(bundle);

        uint8_t halt[]={(uint8_t)(2+bank),5,(uint8_t)(2+bank),6,(uint8_t)bank};
        source=(abc_function){.end=sizeof(halt),.results=2};
        module=(abc_module){.code=halt,.code_size=sizeof(halt),.functions=&source,.function_count=1};
        bundle=build_checked(&module);program=abc_residual_bundle_program(bundle);function=&program->functions.items[0];
        term=terminator_at(function,4);
        check(term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_HALT && term->value.halt.values.count==2 &&
              constant_bits(program,term->value.halt.values.items[0])==5 &&
              constant_bits(program,term->value.halt.values.items[1])==6,"HALT result source/order changed");
        abc_residual_bundle_free(bundle);

        uint8_t tail[]={(uint8_t)(0x14+bank),(uint8_t)(0x16+bank),(uint8_t)(0x88+bank),0,0,0,0,2,2,
            (uint8_t)(0x14+(bank^1)),(uint8_t)(0x16+(bank^1)),(uint8_t)(0x8a+(bank^1)),2,2};
        abc_function sources[]={{.end=9,.arguments=2,.results=2},
            {.entry=9,.end=sizeof(tail),.arguments=2,.results=2}};
        module=(abc_module){.code=tail,.code_size=sizeof(tail),.functions=sources,.function_count=2};
        bundle=build_checked(&module);function=&abc_residual_bundle_program(bundle)->functions.items[0];
        term=terminator_at(function,11);
        check(same_value(function,term->value.return_value.values.items[0],function->arguments.items[0]) &&
              same_value(function,term->value.return_value.values.items[1],function->arguments.items[1]),
              "virtual tail changed selected argument order or result continuation");
        abc_residual_bundle_free(bundle);

        /* Mutual recursion retains real residual tail transfers. No execution
         * is needed to verify their ordered argument vectors. */
        uint8_t mutual[]={(uint8_t)(0x14+bank),(uint8_t)(0x16+bank),(uint8_t)(0x88+bank),0,0,0,0,2,2,
            (uint8_t)(0x14+(bank^1)),(uint8_t)(0x16+(bank^1)),(uint8_t)(0x88+(bank^1)),0xee,0xff,0xff,0xff,2,2};
        sources[0]=(abc_function){.end=9,.arguments=2,.results=1};
        sources[1]=(abc_function){.entry=9,.end=sizeof(mutual),.arguments=2,.results=1};
        module.code=mutual;module.code_size=sizeof(mutual);
        bundle=build_checked(&module);program=abc_residual_bundle_program(bundle);function=&program->functions.items[0];
        term=terminator_at(function,2);
        check(term->tag==ABC_ASDL_RESIDUAL_TERMINATOR_TAIL_CALL &&
              term->value.tail_call.kind==ABC_ASDL_RESIDUAL_CALL_KIND_DIRECT &&
              term->value.tail_call.target==program->functions.items[1].id.value &&
              same_value(function,term->value.tail_call.arguments.items[0],function->arguments.items[0]) &&
              same_value(function,term->value.tail_call.arguments.items[1],function->arguments.items[1]),
              "real tail changed selected argument source/order or target");
        abc_residual_bundle_free(bundle);
    }
}

int main(void) {
    check_builder_scalars();
    check_builder_float_branches();
    check_builder_calls();
    check_builder_transfers();
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
