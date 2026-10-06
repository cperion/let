#ifndef ABC_RESIDUAL_ANALYSIS_H
#define ABC_RESIDUAL_ANALYSIS_H

#include "symbolic.h"

typedef enum {
    ABC_RESIDUAL_FACT_UNREACHED,
    ABC_RESIDUAL_FACT_CONSTANT,
    ABC_RESIDUAL_FACT_UNKNOWN
} abc_residual_argument_fact_kind;

typedef struct {
    abc_residual_argument_fact_kind kind;
    uint64_t constant;
} abc_residual_argument_fact;

/* The owner of a call owns facts and must release it with free(). */
typedef struct {
    uint32_t target, arguments;
    abc_residual_argument_fact *facts;
} abc_residual_call;

/*
 * A successfully built graph owns all pointer members. Initialize it to zero
 * before building and release it with abc_residual_analysis_call_graph_free().
 */
typedef struct {
    uint32_t *offsets, *edges, *component;
    uint8_t *recursive, *nested_eligible;
    uint32_t count, edge_count, component_count;
} abc_residual_call_graph;

void abc_residual_analysis_call_graph_free(abc_residual_call_graph *graph);
int abc_residual_analysis_direct_target(const abc_module *module, uint32_t pc, uint32_t *target);
int abc_residual_analysis_dynamic_target(const abc_module *module, uint32_t pc, uint32_t *target);
int abc_residual_analysis_build_call_graph(const abc_module *module, abc_residual_call_graph *graph);

abc_residual_argument_fact abc_residual_analysis_argument_fact(abc_symbolic_value value);

/*
 * The caller owns the facts table and each per-function allocation created by
 * these helpers. needed and dirty each have module->function_count entries.
 */
int abc_residual_analysis_activate_facts(const abc_module *module,
    abc_residual_argument_fact **facts, uint8_t *needed, uint8_t *dirty,
    uint32_t function, int unknown);
int abc_residual_analysis_join_call_facts(const abc_module *module,
    abc_residual_argument_fact **facts, uint8_t *needed, uint8_t *dirty,
    const abc_residual_call *call);

#endif
