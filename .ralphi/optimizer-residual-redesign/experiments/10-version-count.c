/* Round-10 probe (experiment, not project tooling): how many version bodies does
 * the native residualizer compile for a fixture whose only calls are residual
 * (non-inlinable) direct calls?  Native marks every call-return pc a block
 * (src/residualize.c discover_blocks) and compile_version ends the body at any
 * block, so a residual call should cost one extra post-call version body on top
 * of the function entries.  This measures that count; it does not change code. */
#include "abc.h"
#include "vm_internal.h"
#include "residualize.h"
#include <stdio.h>

static int run(const char *path, abc_execution_mode mode) {
    abc_error e = {0};
    abc_module *m = NULL;
    if (abc_module_read(path, &m, &e) != ABC_OK) { fprintf(stderr, "read: %s\n", e.message); return 1; }
    abc_limits limits = {.stack_cells = 64, .mode = mode};
    abc_vm *vm = NULL;
    if (abc_vm_create(&limits, &vm, &e) != ABC_OK) { fprintf(stderr, "create: %s\n", e.message); return 1; }
    if (abc_vm_load(vm, m, &e) != ABC_OK) { fprintf(stderr, "load: %s\n", e.message); return 1; }
    uint64_t result = 0;
    size_t n = 0;
    if (abc_vm_call(vm, m, "main", NULL, 0, &result, 1, &n, &e) != ABC_OK) { fprintf(stderr, "call: %s\n", e.message); return 1; }
    abc_execution_image *img = vm->images->execution;
    printf("%-28s mode=%d value=%llu compiled_versions=%zu real_calls=%zu virtual_calls=%zu\n",
        path, (int)mode, (unsigned long long)result,
        img->compiled_versions, img->real_calls, img->virtual_calls);
    abc_vm_free(vm);
    abc_module_free(m);
    return 0;
}

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) { run(argv[i], ABC_EXEC_COMPILED); run(argv[i], ABC_EXEC_LAZY); }
    return 0;
}
