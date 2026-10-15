#ifndef ABC_EXECUTION_CONTEXT_H
#define ABC_EXECUTION_CONTEXT_H
#include "internal.h"
#include "lifetime.h"

typedef struct { uint32_t return_pc; unsigned result_destination_stack; } abc_frame;
struct abc_image;
typedef struct abc_exec_context {
    uint64_t *a,*b,*c;
    size_t na,nb,nc,capacity,nf;
    uint64_t h[4],cr[3];unsigned ca,cb,cc;
    abc_frame *frames;
    abc_cleanup_frame *cleanup;
    abc_owner_context owners;
    abc_vm *session;
    const abc_module *m;
    struct abc_image *image;
    const uint8_t *code;
    abc_error error;
    uint32_t pc;unsigned done;
} abc_exec_context;
extern _Thread_local abc_exec_context *abc_active_context;
uint64_t *abc_execution_limit(unsigned stack);
#endif
