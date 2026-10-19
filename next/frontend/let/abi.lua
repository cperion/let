-- FFI declarations for the public ABC ABI. No library loading or execution policy.
-- Keep layouts synchronized with include/abc.h; shared by runtime and tool bindings.
local ffi = require('ffi')
ffi.cdef [[
typedef struct abc_module abc_module;
typedef struct abc_vm abc_vm;
typedef struct {
    int status;
    uint32_t offset;
    uint8_t reason;
    char message[192];
} abc_error;
typedef struct { size_t stack_cells; int mode; } abc_limits;
typedef struct {
    uint32_t arguments, results, hidden_result_bytes;
    uint8_t argument_kinds[255], result_kinds[255];
} abc_signature;
int abc_module_load(const void *, size_t, abc_module **, abc_error *);
void abc_module_free(abc_module *);
int abc_module_export_signature(const abc_module *, const char *, abc_signature *, abc_error *);
int abc_vm_create(const abc_limits *, abc_vm **, abc_error *);
int abc_vm_load(abc_vm *, const abc_module *, abc_error *);
void abc_vm_free(abc_vm *);
int abc_vm_read_image(const abc_vm *, const abc_module *, size_t, void *, size_t, abc_error *);
int abc_vm_call(abc_vm *, const abc_module *, const char *, const uint64_t *, size_t,
                uint64_t *, size_t, size_t *, abc_error *);
const char *abc_status_name(int);
]]
return ffi
