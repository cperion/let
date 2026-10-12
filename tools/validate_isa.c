/* Revision-6 encoding contracts; deliberately independent of VM execution. */
#include "opcodes.h"
#include <assert.h>
#include <stdio.h>

static abc_decoded_instruction decode(const uint8_t *code, size_t length) {
    abc_decoded_instruction instruction;
    assert(abc_decode_instruction(code, length, &instruction));
    return instruction;
}

int main(void) {
    assert(ABC_ISA_REVISION == 6 && OP_COUNT == 256 && EXT_COUNT == 14);
    assert(ABC_OPERATION_COUNT == 145);
    assert(OP_SUB_A == 0x22 && OP_SUB_B == 0x23);
    assert(OP_CALL_A == 0x86 && OP_RET_B == 0x8b);
    assert(OP_CALLI_A == 0xd4 && OP_TCALLI_B == 0xd7);
    assert(OP_EXT_A == 0xf8 && OP_EXT_B == 0xf9);
    assert(OP_CPOP == 0xfa && OP_ABORT == 0xff);

    for (unsigned opcode = 0; opcode < OP_EXT_A; opcode += 2) {
        const abc_instruction_metadata *a = &abc_core_instructions[opcode];
        const abc_instruction_metadata *b = &abc_core_instructions[opcode + 1];
        assert(a->operation == b->operation && a->kind == b->kind);
        assert(a->operand_layout == b->operand_layout);
        assert(a->encoded_length == b->encoded_length);
        assert(a->minimum_profile == b->minimum_profile);
        assert(a->stack_role == b->stack_role);
        assert(a->memory_action == b->memory_action);
        assert(a->memory_width == b->memory_width && a->sign_extend == b->sign_extend);
        assert(a->selected_stack == ABC_STACK_A && b->selected_stack == ABC_STACK_B);
    }
    for (unsigned opcode = OP_CPOP; opcode <= OP_ABORT; opcode++) {
        assert(abc_core_instructions[opcode].selected_stack == ABC_STACK_NONE);
        assert(abc_core_instructions[opcode].stack_role == ABC_STACK_ROLE_NONE);
    }
    assert(abc_core_instructions[OP_CGET0_B].stack_role == ABC_STACK_ROLE_RESULT);
    assert(abc_core_instructions[OP_CPUSH_B].stack_role == ABC_STACK_ROLE_SOURCE);
    assert(abc_core_instructions[OP_ST64_B].stack_role == ABC_STACK_ROLE_ADDRESS);
    assert(abc_core_instructions[OP_RET_B].stack_role == ABC_STACK_ROLE_RETURN_SOURCE);
    assert(abc_core_instructions[OP_CALLI_B].minimum_profile == 3);
    assert(abc_core_instructions[OP_FCALL_B].minimum_profile == 4);

    /* Bytes are copied from the design, not assembled through this manifest. */
    const uint8_t program[] = {0x02, 10, 0x03, 3, 0x23, 0x8b, 0, 1};
    const unsigned operations[] = {ABC_OPERATION_PUSH8, ABC_OPERATION_PUSH8,
        ABC_OPERATION_SUB, ABC_OPERATION_RET};
    const unsigned stacks[] = {ABC_STACK_A, ABC_STACK_B, ABC_STACK_B, ABC_STACK_B};
    const unsigned lengths[] = {2, 2, 1, 3};
    size_t offset = 0;
    for (unsigned index = 0; index < 4; index++) {
        abc_decoded_instruction instruction = decode(program + offset, sizeof program - offset);
        assert(instruction.metadata->operation == operations[index]);
        assert(instruction.selected_stack == stacks[index]);
        assert(instruction.length == lengths[index]);
        assert(instruction.operands == program + offset + 1);
        offset += instruction.length;
    }
    assert(offset == sizeof program);

    const uint8_t c_operand[] = {0xf9, 0x01, 2};
    abc_decoded_instruction instruction = decode(c_operand, sizeof c_operand);
    assert(instruction.metadata->operation == ABC_OPERATION_SUBC);
    assert(instruction.selected_stack == ABC_STACK_B && instruction.length == 3);
    assert(instruction.operands == c_operand + 2 && instruction.operands[0] == 2);
    const uint8_t immediate_branch[] = {0xf8, 0x08, 7, 0xff, 0xff};
    instruction = decode(immediate_branch, sizeof immediate_branch);
    assert(instruction.metadata->operation == ABC_OPERATION_BGTI);
    assert(instruction.selected_stack == ABC_STACK_A && instruction.length == 5);
    assert(instruction.operands == immediate_branch + 2);

    const uint8_t indirect_call[] = {0xd5, 2};
    instruction = decode(indirect_call, sizeof indirect_call);
    assert(instruction.length == 2 && instruction.selected_stack == ABC_STACK_B);
    const uint8_t indirect_tail[] = {0xd6, 3, 2};
    instruction = decode(indirect_tail, sizeof indirect_tail);
    assert(instruction.length == 3 && instruction.selected_stack == ABC_STACK_A);

    const uint8_t switch_table[] = {0x63, 2, 0, 0, 0, 0, 0, 0xff, 0xff, 0xff, 0xff};
    instruction = decode(switch_table, sizeof switch_table);
    assert(instruction.length == 11 && instruction.selected_stack == ABC_STACK_B);
    assert(!abc_decode_instruction(switch_table, sizeof switch_table - 1, &instruction));
    assert(!abc_decode_instruction(program, 1, &instruction));
    assert(!abc_decode_instruction(program, 0, &instruction));
    puts("revision-6 ISA metadata: byte map, mirror contracts, layouts and decoding passed");
    return 0;
}
