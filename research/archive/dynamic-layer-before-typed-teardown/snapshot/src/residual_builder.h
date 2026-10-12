#ifndef ABC_RESIDUAL_BUILDER_H
#define ABC_RESIDUAL_BUILDER_H

#include "residual_analysis.h"
#include "residual_ir.h"

typedef enum {
    ABC_RESIDUAL_BUILD_OK,
    ABC_RESIDUAL_BUILD_UNSUPPORTED,
    ABC_RESIDUAL_BUILD_NOMEM,
    ABC_RESIDUAL_BUILD_INVALID
} abc_residual_build_status;

/*
 * Optional source-function entry facts. Each non-null per-function table has
 * module->functions[function].arguments entries.
 */
typedef struct {
    const abc_residual_argument_fact *const *argument_facts;
} abc_residual_build_options;

typedef struct {
    uint32_t source_function;
    uint32_t source_entry;
    uint32_t fallback_source_entry;
    uint32_t fallback_source_size;
    abc_residual_id residual_function;
    unsigned supported;
    unsigned recursive;
    uint32_t max_a;
    uint32_t max_b;
    uint32_t max_c;
    size_t call_count;
    const abc_residual_call *calls;
} abc_residual_source_function;

typedef struct {
    abc_residual_build_status status;
    uint32_t source_function;
    uint32_t bytecode_offset;
    char message[192];
} abc_residual_build_diagnostic;

typedef struct abc_residual_bundle abc_residual_bundle;

/*
 * Unsupported source functions are recorded in the returned bundle for
 * per-function byte-copy fallback. The aggregate build remains successful;
 * allocation failure and malformed symbolic state remain fatal.
 */
abc_residual_build_status abc_residual_build(
    const abc_module *module,
    const abc_residual_build_options *options,
    abc_residual_bundle **out,
    abc_residual_build_diagnostic *diagnostic);

void abc_residual_bundle_free(abc_residual_bundle *bundle);

const abc_residual_program *abc_residual_bundle_program(
    const abc_residual_bundle *bundle);

size_t abc_residual_bundle_source_function_count(
    const abc_residual_bundle *bundle);

const abc_residual_source_function *abc_residual_bundle_source_functions(
    const abc_residual_bundle *bundle);

#endif
