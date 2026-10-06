#ifndef ABC_H
#define ABC_H
#include <stddef.h>
#include <stdint.h>

/* ABC2 integer, memory and callable profiles. Modules are immutable and may
 * be shared by VMs. Each VM owns its stacks, persistent images and execution copies.
 * A VM must not be used concurrently with itself. Cells are raw 64-bit bits.
 * Native pointers are unchecked; see docs/memory-profile.md. */
typedef struct abc_module abc_module;
typedef struct abc_vm abc_vm;
typedef void (*abc_foreign_address)(void);
typedef enum { ABC_INTEGER, ABC_ADDRESS, ABC_FLOAT, ABC_ANY } abc_cell_kind;
typedef struct {
    uint32_t arguments, results, hidden_result_bytes;
    uint8_t argument_kinds[255], result_kinds[255]; /* abc_cell_kind values */
} abc_signature;
typedef struct {
    uint32_t generic, specific, final_generic;
    uint64_t transitions; /* knowledge changes, not executions */
} abc_site_stats;
typedef enum {
    ABC_OK, ABC_INVALID, ABC_IO, ABC_NOMEM, ABC_NOT_FOUND, ABC_ARGUMENTS,
    ABC_ABORT, ABC_STACK, ABC_RESULTS
} abc_status;
typedef struct {
    abc_status status;
    uint32_t offset;             /* bytecode offset, UINT32_MAX when unavailable */
    uint8_t reason;              /* language abort reason; zero for host errors */
    char message[192];
} abc_error;

/* Stable ABI implemented by portable C emitted from residual IR. */
#ifndef ABC_AOT_ABI_DEFINED
#define ABC_AOT_ABI_DEFINED
typedef struct {
    uint32_t status;
    uint32_t offset;
    uint8_t reason;
} abc_aot_error;
typedef int (*abc_aot_entry)(
    const uint64_t *arguments, size_t argument_count,
    uint64_t *results, size_t result_capacity,
    abc_aot_error *error);
typedef struct {
    const char *name;
    uint32_t arguments;
    uint32_t results;
    abc_aot_entry entry;
} abc_aot_export;
#endif
typedef enum { ABC_EXEC_INTERPRETED, ABC_EXEC_COMPILED, ABC_EXEC_LAZY } abc_execution_mode;
typedef struct {
    size_t stack_cells;          /* limit per stack; zero selects 65,536 */
    abc_execution_mode mode;     /* interpreted by default; compiled is eager, lazy compiles on first context arrival */
} abc_limits;

abc_status abc_module_load(const void *bytes, size_t size, abc_module **out, abc_error *error);
abc_status abc_module_read(const char *path, abc_module **out, abc_error *error);
void abc_module_free(abc_module *module);
/* Residualize verified ABC through the shared symbolic VM and canonical ABC sink.
 * The returned allocation is owned by the caller and released with abc_optimized_free.
 * Unsupported regions are preserved conservatively; successful output is always reverified. */
typedef struct { uint32_t output_offset, input_offset; } abc_provenance;
abc_status abc_optimize(const void *bytes, size_t size, void **output, size_t *output_size, abc_error *error);
abc_status abc_optimize_mapped(const void *bytes, size_t size, void **output, size_t *output_size,
                               abc_provenance **provenance, size_t *provenance_count, abc_error *error);
void abc_optimized_free(void *bytes);

/* Emit a self-contained C11 translation unit from verified integer/static ABC.
 * The returned text is NUL-terminated; source_size excludes that terminator. */
abc_status abc_emit_c(const void *bytes, size_t size,
                      char **source, size_t *source_size,
                      abc_error *error);
void abc_emitted_c_free(char *source);
abc_status abc_module_export(const abc_module *module, const char *name,
                             uint32_t *arguments, uint32_t *results, abc_error *error);
/* Copied signature; no output changes on failure. Integer modules report integer kinds. */
abc_status abc_module_export_signature(const abc_module *module, const char *name,
                                       abc_signature *signature, abc_error *error);
/* Opaque same-module callable address, valid while the module is retained.
 * Not a data pointer or a host C function pointer. No output changes on failure. */
abc_status abc_module_export_address(const abc_module *module, const char *name,
                                     uint64_t *address, abc_error *error);
abc_status abc_vm_site_stats(const abc_vm *vm, const abc_module *module,
                             abc_site_stats *stats, abc_error *error);
abc_status abc_vm_create(const abc_limits *limits, abc_vm **out, abc_error *error);
/* Bind a named module extern before loading modules into this VM. Bindings are
 * VM-local; the function's C signature must match the module extern signature. */
abc_status abc_vm_bind_foreign(abc_vm *vm, const char *name,
                               abc_foreign_address address, abc_error *error);
/* Associate a module with a VM. Eager compiled VMs residualize the module here.
 * Lazy VMs install stable entry stubs and compile reached contexts during calls. */
abc_status abc_vm_load(abc_vm *vm, const abc_module *module, abc_error *error);
/* Request collection at the next profile-5 allocating or generic safepoint. */
abc_status abc_vm_request_collection(abc_vm *vm, abc_error *error);
void abc_vm_free(abc_vm *vm);
/* Results are copied in source order. A call resets stacks, even after failure;
 * memory image writes persist. Output capacity is checked before execution.
 * No result is published on failure. Images retain modules until VM destruction.
 * Address arguments/results are native pointer bits with caller-managed lifetime. */
abc_status abc_vm_call(abc_vm *vm, const abc_module *module, const char *export_name,
                       const uint64_t *arguments, size_t argument_count,
                       uint64_t *results, size_t result_capacity, size_t *result_count,
                       abc_error *error);
const char *abc_status_name(abc_status status);
#endif

