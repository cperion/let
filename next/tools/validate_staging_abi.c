/* The Lua binding compares these public-header facts with its FFI declarations. */
#include "abc.h"
#include <stddef.h>
#include <stdio.h>
#define SIZE(T) printf(#T " %zu\n", sizeof(T))
#define FIELD(T, F) printf(#T "." #F " %zu\n", offsetof(T, F))
int main(void) {
    SIZE(abc_error); FIELD(abc_error, status); FIELD(abc_error, offset);
    FIELD(abc_error, reason); FIELD(abc_error, message);
    SIZE(abc_limits); FIELD(abc_limits, stack_cells); FIELD(abc_limits, mode);
    SIZE(abc_signature); FIELD(abc_signature, arguments); FIELD(abc_signature, results);
    FIELD(abc_signature, hidden_result_bytes); FIELD(abc_signature, argument_kinds);
    FIELD(abc_signature, result_kinds);
    printf("ABC_OK %d\nABC_EXEC_INTERPRETED %d\nABC_EXEC_COMPILED %d\nABC_EXEC_LAZY %d\nABC_EXEC_THREADED %d\n",
           ABC_OK, ABC_EXEC_INTERPRETED, ABC_EXEC_COMPILED, ABC_EXEC_LAZY, ABC_EXEC_THREADED);
    printf("ABC_INTEGER %d\nABC_ADDRESS %d\nABC_FLOAT %d\n", ABC_INTEGER, ABC_ADDRESS, ABC_FLOAT);
    return 0;
}
