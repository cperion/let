#ifndef ABC_RESIDUAL_IR_H
#define ABC_RESIDUAL_IR_H

#include "generated/residual_ir.h"

#include <stdio.h>

typedef abc_asdl_residual_id abc_residual_id;
typedef abc_asdl_residual_origin abc_residual_origin;
typedef abc_asdl_residual_type abc_residual_type;
typedef abc_asdl_residual_representation abc_residual_representation;
typedef abc_asdl_residual_facts abc_residual_facts;
typedef abc_asdl_residual_definition abc_residual_definition;
typedef abc_asdl_residual_value abc_residual_value;
typedef abc_asdl_residual_effect abc_residual_effect;
typedef abc_asdl_residual_operation abc_residual_operation;
typedef abc_asdl_residual_node abc_residual_node;
typedef abc_asdl_residual_edge abc_residual_edge;
typedef abc_asdl_residual_switch_arm abc_residual_switch_arm;
typedef abc_asdl_residual_terminator abc_residual_terminator;
typedef abc_asdl_residual_block abc_residual_block;
typedef abc_asdl_residual_function abc_residual_function;
typedef abc_asdl_residual_program abc_residual_program;

typedef struct abc_residual_arena abc_residual_arena;

typedef struct {
    uint64_t id;
    uint64_t origin;
    char message[192];
} abc_residual_diagnostic;

abc_residual_arena *abc_residual_arena_create(void);
void abc_residual_arena_free(abc_residual_arena *arena);
void *abc_residual_allocate(abc_residual_arena *arena, size_t count, size_t element_size);
void *abc_residual_copy(abc_residual_arena *arena, const void *items, size_t count, size_t element_size);
abc_asdl_string abc_residual_string(abc_residual_arena *arena, const char *text);
abc_residual_id abc_residual_new_id(abc_residual_arena *arena);
abc_residual_origin abc_residual_make_origin(abc_residual_arena *arena, uint64_t offset,
                                                 const abc_residual_origin *caller);

int abc_residual_validate(const abc_residual_program *program, abc_residual_diagnostic *diagnostic);
int abc_residual_dump(FILE *output, const abc_residual_program *program);

static inline int abc_residual_id_equal(abc_residual_id left, abc_residual_id right) {
    return left.value == right.value;
}

#endif
