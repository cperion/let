#ifndef ABC_HANDLER_ABI_H
#define ABC_HANDLER_ABI_H
#include <stdint.h>

/* docs/spec.md: 11 carried values; state is selected by the dispatch table,
 * never passed as a runtime cache descriptor. Clang's preserve_none keeps the
 * bank and stack frontiers in the handler calling convention. */
typedef uint64_t abc_value;
#define ABC_HANDLER_CC __attribute__((preserve_none))
#define ABC_HANDLER_ARGS const uint8_t *ip, abc_value *asp, abc_value *bsp, abc_value *csp, \
    abc_value h0, abc_value h1, abc_value h2, abc_value h3, \
    abc_value c0, abc_value c1, abc_value c2
#define ABC_HANDLER_PASS ip, asp, bsp, csp, h0, h1, h2, h3, c0, c1, c2
#define ABC_HANDLER_TAIL __attribute__((musttail))
typedef ABC_HANDLER_CC abc_value (*abc_handler)(ABC_HANDLER_ARGS);

#endif

