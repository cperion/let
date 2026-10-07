#ifndef ABC_TOOL_H
#define ABC_TOOL_H

#include "abc.h"

/* Build-time ABC-to-ABC optimization. The runtime does not invoke this API.
 * Returned allocations are owned by the caller. */
typedef struct { uint32_t output_offset, input_offset; } abc_provenance;
abc_status abc_optimize(const void *bytes, size_t size,
                        void **output, size_t *output_size,
                        abc_error *error);
abc_status abc_optimize_mapped(const void *bytes, size_t size,
                               void **output, size_t *output_size,
                               abc_provenance **provenance,
                               size_t *provenance_count,
                               abc_error *error);
void abc_optimized_free(void *bytes);

/* Emit a self-contained C11 translation unit from verified integer/static ABC.
 * The returned text is NUL-terminated; source_size excludes that terminator. */
abc_status abc_emit_c(const void *bytes, size_t size,
                      char **source, size_t *source_size,
                      abc_error *error);
void abc_emitted_c_free(char *source);

#endif
