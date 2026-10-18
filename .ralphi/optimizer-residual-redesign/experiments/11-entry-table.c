/* Round-11 probe (experiment, not project tooling): which functions does the
 * native runtime image install an entry for?  The design must define the
 * residual-function set before it can create all entry versions; the incumbent's
 * native residualizer loops over every module function
 * (src/residualize.c residualize(): `for f < function_count`), while abc-opt
 * emits only the root closure (src/optimize.c mark_live_functions).
 *
 * This probe loads an already-optimized module and prints, per function index,
 * whether the native execution image has a non-null entry.  A function with an
 * entry but no export, no code-address relocation and no caller in the emitted
 * module is compiled "for free" by the incumbent: that is the native root set.
 * It does not change code. */
#include "abc.h"
#include "vm_internal.h"
#include "residualize.h"
#include <stdio.h>

static int probe(const char *path) {
    abc_error e = {0};
    abc_module *m = NULL;
    if (abc_module_read(path, &m, &e) != ABC_OK) { fprintf(stderr, "read %s: %s\n", path, e.message); return 1; }
    abc_limits limits = {.stack_cells = 64, .mode = ABC_EXEC_COMPILED};
    abc_vm *vm = NULL;
    if (abc_vm_create(&limits, &vm, &e) != ABC_OK) { fprintf(stderr, "create: %s\n", e.message); return 1; }
    if (abc_vm_load(vm, m, &e) != ABC_OK) { fprintf(stderr, "load: %s\n", e.message); return 1; }
    abc_execution_image *img = vm->images->execution;
    abc_execution_image *life = vm->images->lifecycle;
    size_t nulls = 0;
    printf("%s\n  functions=%u exports=%u relocs=%u c_entries=%u compiled_versions=%zu\n",
        path, m->function_count, m->export_count, m->reloc_count, m->c_entry_count,
        img ? img->compiled_versions : 0);
    for (uint32_t i = 0; i < m->function_count; i++)
        if (!img || !img->entries || !img->entries[i]) nulls++;
    if (img) printf("  bodies=%zu virtual_calls=%zu real_calls=%zu virtual_returns=%zu virtual_tails=%zu\n",
        img->compiled_versions, img->virtual_calls, img->real_calls, img->virtual_returns, img->virtual_tails);
    printf("  execution entries: %s (%zu null of %u)\n",
        nulls == 0 ? "every function has one" : "SOME FUNCTIONS MISSING", nulls, m->function_count);
    if (life) {
        size_t lifecycle_entries = 0;
        for (uint32_t i = 0; i < m->function_count; i++)
            if (life->entries && life->entries[i]) lifecycle_entries++;
        printf("  lifecycle image entries: %zu (c_entry functions=%u)\n", lifecycle_entries, m->c_entry_count);
    } else {
        printf("  lifecycle image: none (no c_entry functions)\n");
    }
    abc_vm_free(vm);
    abc_module_free(m);
    return 0;
}

int main(int argc, char **argv) {
    int failures = 0;
    for (int i = 1; i < argc; i++) failures += probe(argv[i]);
    return failures;
}
