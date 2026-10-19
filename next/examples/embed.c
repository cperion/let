#include "abc.h"
#include <inttypes.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    abc_module *module = NULL; abc_vm *vm = NULL; abc_error error;
    abc_limits limits = {.stack_cells = 1024, .mode = ABC_EXEC_INTERPRETED};
    uint64_t arguments[] = {17, 5}, results[2]; size_t count = 0;
    abc_status status = abc_module_read(argv[1], &module, &error);
    if (status == ABC_OK) status = abc_vm_create(&limits, &vm, &error);
    if (status == ABC_OK) status = abc_vm_load(vm, module, &error);
    if (status == ABC_OK) status = abc_vm_call(vm, module, "divmod", arguments, 2, results, 2, &count, &error);
    if (status == ABC_OK && count == 2) printf("%" PRIu64 " %" PRIu64 "\n", results[0], results[1]);
    else fprintf(stderr, "%s: %s\n", abc_status_name(status), error.message);
    abc_vm_free(vm); abc_module_free(module);
    return status == ABC_OK && count == 2 ? 0 : 1;
}

