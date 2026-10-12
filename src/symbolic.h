#ifndef ABC_SYMBOLIC_H
#define ABC_SYMBOLIC_H
#include "vm_internal.h"

/* Policy knobs for independent sources of local analysis growth. Neither is a
   continuation-depth, module-code-size, or generated-output limit. */
enum {
    ABC_BLOCK_VERSION_LIMIT = 8,
    ABC_OPTIMIZER_PATH_LIMIT = 4096
};

enum { ABC_SYM_A, ABC_SYM_B, ABC_SYM_C };
enum { ABC_SYM_CONST, ABC_SYM_BACKEND, ABC_SYM_HOME };

/* `reg` is sink-owned: a native register or a sink-private DAG node ID. */
typedef struct {
    uint8_t kind, stack, dst_stack; uint32_t reg;
    int32_t home, dst_home; uint64_t constant;
} abc_symbolic_value;

typedef struct {
    uint32_t return_pc, target, abase, bbase, cbase;
    int32_t old_origin, old_bias; uint8_t dst;
} abc_symbolic_continuation;

typedef struct {
    abc_symbolic_value *s[3]; uint32_t n[3], cap[3], limit[3];
    int32_t c_origin, c_bias; uint32_t ncont, contcap;
    uint8_t generic; abc_symbolic_continuation *cont;
} abc_symbolic_context;

void abc_symbolic_context_free(abc_symbolic_context *context);
int abc_symbolic_context_copy(abc_symbolic_context *to, const abc_symbolic_context *from);
int abc_symbolic_vcont_equal(const abc_symbolic_continuation *a, const abc_symbolic_continuation *b);
int abc_symbolic_continuation_equal(const abc_symbolic_context *a, const abc_symbolic_context *b);
int abc_symbolic_context_equal(const abc_symbolic_context *a, const abc_symbolic_context *b);
int abc_symbolic_context_family_equal(const abc_symbolic_context *a, const abc_symbolic_context *b);
int abc_symbolic_generic_context_equal(const abc_symbolic_context *a, const abc_symbolic_context *b);
int abc_symbolic_push(abc_symbolic_context *context, unsigned stack, abc_symbolic_value value);
int abc_symbolic_push_continuation(abc_symbolic_context *context, abc_symbolic_continuation value);
abc_symbolic_value abc_symbolic_pop(abc_symbolic_context *context, unsigned stack);
abc_symbolic_value *abc_symbolic_top(abc_symbolic_context *context, unsigned stack, unsigned depth);
abc_symbolic_value abc_symbolic_home(unsigned stack, int32_t home);
abc_symbolic_value abc_symbolic_constant(uint64_t value, unsigned stack, int32_t home);
abc_symbolic_value abc_symbolic_backend(uint32_t backend, unsigned stack, int32_t home);
abc_symbolic_value abc_symbolic_rehome(abc_symbolic_value value, unsigned stack, int32_t home);

typedef enum {
    ABC_SYM_EXIT_BLOCK, ABC_SYM_EXIT_BOUNDARY, ABC_SYM_EXIT_CONTROL, ABC_SYM_EXIT_TERMINATED, ABC_SYM_EXIT_FAILURE
} abc_symbolic_exit;
enum { ABC_SYM_TRANSFER_STACK=1u, ABC_SYM_TRANSFER_VALUE=2u, ABC_SYM_TRANSFER_CONTROL=4u, ABC_SYM_TRANSFER_EFFECT=8u };

/* Capture a value before a stack transfer. Native HOME values are mutable
   storage reads; sinks whose inputs name immutable definitions need no binding.
   Constants/backend values already denote captured values and may rename. */
typedef int (*abc_symbolic_capture_fn)(void *sink, uint32_t origin, abc_symbolic_value *value);
/* Scalar/control opcode parameters carry ABC_OPERATION_* semantic identities,
   never serialized core bytes or EXT selectors.
   Binary callbacks receive selected-stack first, opposite-stack second.
   The selected stack is also the result destination; sinks must not reverse
   these inputs for B. This contract also applies to emit_float_binary. */
typedef int (*abc_symbolic_emit_binary_fn)(void *sink, uint32_t origin, unsigned opcode,
    unsigned destination, int folded, abc_symbolic_value left, abc_symbolic_value right,
    abc_symbolic_value *result);
typedef int (*abc_symbolic_emit_unary_fn)(void *sink, uint32_t origin, unsigned opcode,
    unsigned stack, int folded, abc_symbolic_value input, abc_symbolic_value *result);
typedef int (*abc_symbolic_emit_immediate_fn)(void *sink, uint32_t origin, unsigned opcode,
    unsigned stack, uint64_t immediate, int folded, abc_symbolic_value input, abc_symbolic_value *result);
typedef int (*abc_symbolic_emit_float_unary_fn)(void *sink, uint32_t origin, unsigned opcode,
    unsigned selected_stack, int folded, int trapped, abc_symbolic_value input, abc_symbolic_value *result);
typedef int (*abc_symbolic_emit_check_fn)(void *sink, uint32_t origin, unsigned opcode,
    unsigned selected_stack, int known, int trapped, abc_symbolic_value input);
typedef enum { ABC_SYM_CONTROL_JUMP, ABC_SYM_CONTROL_ZERO, ABC_SYM_CONTROL_INTEGER,
    ABC_SYM_CONTROL_FLOAT, ABC_SYM_CONTROL_IMMEDIATE, ABC_SYM_CONTROL_SWITCH } abc_symbolic_control_kind;
typedef struct {
    /* relation is an abc_symbolic_relation for integer AND floating controls;
       it is never a float-stencil index or an encoded opcode. */
    abc_symbolic_control_kind kind; unsigned opcode, relation, reverse, known, taken;
    uint32_t target, fallthrough, count; abc_symbolic_value left, right;
} abc_symbolic_control;
typedef int (*abc_symbolic_emit_control_fn)(void *sink, uint32_t origin, const abc_symbolic_control *control);
typedef int (*abc_symbolic_emit_abort_fn)(void *sink, uint32_t origin, unsigned reason);
typedef struct { unsigned index, arguments, results, selected_stack; abc_symbolic_value result[1]; } abc_symbolic_foreign;
typedef int (*abc_symbolic_emit_foreign_fn)(void *sink, uint32_t origin, abc_symbolic_foreign *foreign);
typedef int (*abc_symbolic_emit_edge_fn)(void *sink, uint32_t origin, uint32_t target);
/* stack is the selected address/source/result bank (NONE for C allocation).
   Binary memory forms pass first=selected address, second=opposite value/index
   or source address. opcode is the original encoded instruction for ABC output. */
typedef struct {
    unsigned opcode, action, stack; uint32_t cells;
    abc_symbolic_value first, second, result;
} abc_symbolic_memory;
typedef int (*abc_symbolic_emit_memory_fn)(void *sink, uint32_t origin, abc_symbolic_memory *memory);
typedef struct { unsigned frame_cells, results, terminal, source_stack; } abc_symbolic_return;
typedef int (*abc_symbolic_emit_return_fn)(void *sink, uint32_t origin, const abc_symbolic_return *result);
typedef struct {
    uint32_t target; unsigned arguments, results, destination, virtualize;
    abc_symbolic_continuation continuation; abc_symbolic_value result[255];
} abc_symbolic_call;
typedef int (*abc_symbolic_emit_call_fn)(void *sink, uint32_t origin, abc_symbolic_call *call);
typedef struct {
    unsigned frame_cells, arguments, results, destination, argument_stack, tail, direct; uint32_t direct_target;
    abc_symbolic_value target, result[255];
} abc_symbolic_indirect;
typedef int (*abc_symbolic_emit_indirect_fn)(void *sink, uint32_t origin, abc_symbolic_indirect *call);
typedef struct { uint32_t target; unsigned frame_cells, arguments, argument_stack; int residualize; } abc_symbolic_tail;
typedef int (*abc_symbolic_emit_tail_fn)(void *sink, uint32_t origin, abc_symbolic_tail *tail);

typedef struct abc_symbolic_machine {
    const abc_module *module; const uint8_t *code, *blocks; uint32_t pc, end, extra_advance; unsigned opcode, transfer_mask;
    abc_symbolic_context *context; void *sink; abc_symbolic_capture_fn capture; abc_symbolic_emit_binary_fn emit_binary;
    abc_symbolic_emit_binary_fn emit_float_binary, emit_c_operand, emit_pow;
    abc_symbolic_emit_unary_fn emit_unary; abc_symbolic_emit_immediate_fn emit_immediate;
    abc_symbolic_emit_float_unary_fn emit_float_unary; abc_symbolic_emit_check_fn emit_check;
    abc_symbolic_emit_control_fn emit_control; abc_symbolic_emit_abort_fn emit_abort, emit_halt;
    abc_symbolic_emit_memory_fn emit_memory; abc_symbolic_emit_return_fn emit_return; abc_symbolic_emit_call_fn emit_call; abc_symbolic_emit_indirect_fn emit_indirect; abc_symbolic_emit_tail_fn emit_tail;
    abc_symbolic_emit_foreign_fn emit_foreign; abc_symbolic_emit_edge_fn emit_edge;
    abc_error *error; abc_symbolic_exit exit;
} abc_symbolic_machine;

abc_symbolic_exit abc_symbolic_dispatch(abc_symbolic_machine *machine);
int abc_symbolic_machine_push(abc_symbolic_machine *machine, unsigned stack, uint64_t value);
int abc_symbolic_machine_dup(abc_symbolic_machine *machine, unsigned stack);
int abc_symbolic_machine_drop(abc_symbolic_machine *machine, unsigned stack);
int abc_symbolic_machine_transfer(abc_symbolic_machine *machine, unsigned from, unsigned to, int consume);
int abc_symbolic_machine_cpush(abc_symbolic_machine *machine, unsigned from);
int abc_symbolic_machine_cpushn(abc_symbolic_machine *machine, unsigned selected_stack, unsigned count);
int abc_symbolic_machine_cpop(abc_symbolic_machine *machine);
int abc_symbolic_machine_cget(abc_symbolic_machine *machine, unsigned to, unsigned depth);
int abc_symbolic_machine_cget_range(abc_symbolic_machine *machine, unsigned to, unsigned depth, unsigned count);
int abc_symbolic_machine_cset(abc_symbolic_machine *machine, unsigned from, unsigned depth);
int abc_symbolic_machine_binary(abc_symbolic_machine *machine, unsigned opcode, unsigned destination);
int abc_symbolic_machine_float_binary(abc_symbolic_machine *machine, unsigned opcode, unsigned destination);
int abc_symbolic_machine_float_unary(abc_symbolic_machine *machine, unsigned opcode, unsigned selected_stack);
int abc_symbolic_machine_unary(abc_symbolic_machine *machine, unsigned opcode, unsigned stack);
int abc_symbolic_machine_immediate(abc_symbolic_machine *machine, unsigned opcode, unsigned stack, uint64_t immediate);
int abc_symbolic_machine_c_operand(abc_symbolic_machine *machine, unsigned opcode, unsigned stack, unsigned depth);
int abc_symbolic_machine_pow(abc_symbolic_machine *machine, unsigned opcode, unsigned selected_stack);
int abc_symbolic_machine_check(abc_symbolic_machine *machine, unsigned opcode, unsigned selected_stack);
int abc_symbolic_machine_control(abc_symbolic_machine *machine, abc_symbolic_control_kind kind,
    unsigned opcode, unsigned relation, unsigned reverse, unsigned stack,
    uint32_t target, uint32_t fallthrough, uint64_t immediate);
int abc_symbolic_machine_switch(abc_symbolic_machine *machine, unsigned selected_stack, unsigned count, uint32_t fallthrough);
int abc_symbolic_machine_abort(abc_symbolic_machine *machine, unsigned reason);
int abc_symbolic_machine_halt(abc_symbolic_machine *machine, unsigned selected_stack);
int abc_symbolic_machine_memory(abc_symbolic_machine *machine);
int abc_symbolic_machine_return(abc_symbolic_machine *machine, unsigned frame_cells, unsigned results, unsigned source_stack);
int abc_symbolic_machine_call(abc_symbolic_machine *machine, uint32_t target, unsigned arguments, unsigned destination, uint32_t return_pc);
int abc_symbolic_machine_indirect(abc_symbolic_machine *machine, unsigned frame_cells, unsigned arguments, unsigned destination, int tail);
int abc_symbolic_machine_tail(abc_symbolic_machine *machine, uint32_t target, unsigned frame_cells, unsigned arguments, unsigned argument_stack);
int abc_symbolic_machine_foreign(abc_symbolic_machine *machine, unsigned selected_stack);
abc_symbolic_exit abc_symbolic_machine_boundary(abc_symbolic_machine *machine);

/* Stable abstract branch relations, intentionally independent of either sink's IDs. */
typedef enum {
    ABC_SYM_EQ, ABC_SYM_NE, ABC_SYM_LT, ABC_SYM_LE, ABC_SYM_LTU, ABC_SYM_LEU
} abc_symbolic_relation;

uint64_t abc_symbolic_fold_binary(unsigned opcode, uint64_t left, uint64_t right, int *ok);
uint64_t abc_symbolic_fold_unary(unsigned opcode, uint64_t value);
uint64_t abc_symbolic_fold_float(unsigned opcode, uint64_t left, uint64_t right);
int abc_symbolic_branch(abc_symbolic_relation relation, uint64_t left, uint64_t right);

/* Conservative direct-call graph facts used by every symbolic sink. */
int abc_symbolic_reaches_function(const abc_module *module, int from, int goal, uint8_t *seen);
int abc_symbolic_has_unknown_call(const abc_module *module, int from, uint8_t *seen);

#endif

