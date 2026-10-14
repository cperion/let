#ifndef ABC_EXECUTION_CONTEXT_H
#define ABC_EXECUTION_CONTEXT_H
#include "internal.h"
#include "owner.h"

typedef struct { uint32_t return_pc; unsigned result_destination_stack; } abc_frame;
typedef enum { ABC_EXEC_RETURNED, ABC_EXEC_SERVICE } abc_exec_disposition;
typedef struct {
    uintptr_t entry;
    uint64_t *stack[3];
    uint64_t value_register[8];
} abc_resume_state;
typedef struct {
    abc_exec_disposition disposition;
    uint64_t packed_error;
} abc_exec_exit;
struct abc_image;
struct abc_worker;
typedef struct abc_exec_context {
    uint64_t *a,*b,*c;
    size_t na,nb,nc,capacity,nf;
    uint64_t h[4],cr[3];unsigned ca,cb,cc;
    abc_frame *frames;
    abc_owner_scope *scopes;
    abc_vm *session;
    struct abc_worker *worker;
    const abc_module *m;
    struct abc_image *image;
    const uint8_t *code;
    abc_error error;
    uint32_t pc;unsigned done;
    abc_exec_disposition disposition;
    abc_resume_state resume;
    unsigned reclaiming;
    abc_type_ops *pending_type;
    uint32_t operation_pc;
} abc_exec_context;
typedef struct abc_worker {
    abc_owner_context owners;
    abc_exec_context cleanup;
    size_t service_exits,release_entries;
} abc_worker;
extern _Thread_local abc_exec_context *abc_active_context;
uint64_t *abc_execution_limit(unsigned stack);
/* Called only at a generated, synchronized boundary. No source computation. */
int abc_execution_service(uintptr_t continuation,uint64_t *,uint64_t *,uint64_t *,const uint64_t registers[8],uint32_t original_pc);
#endif
