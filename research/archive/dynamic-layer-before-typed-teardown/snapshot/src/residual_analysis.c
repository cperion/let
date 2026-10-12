#include "residual_analysis.h"

void abc_residual_analysis_call_graph_free(abc_residual_call_graph *graph)
{
    free(graph->offsets);
    free(graph->edges);
    free(graph->component);
    free(graph->recursive);
    free(graph->nested_eligible);
    memset(graph, 0, sizeof *graph);
}

int abc_residual_analysis_direct_target(const abc_module *module, uint32_t pc,
    uint32_t *target)
{
    const uint8_t *p = module->code + pc;
    unsigned kind = op_kind[p[0]];
    if (kind != K_CALL && kind != K_TCALL) return 0;
    uint32_t length = abc_instruction_length(p);
    *target = (uint32_t)((int64_t)(pc + length) + abc_i32(p + 1));
    return 1;
}

int abc_residual_analysis_dynamic_target(const abc_module *module, uint32_t pc,
    uint32_t *target)
{
    const uint8_t *p = module->code + pc;
    if (p[0] != OP_EXT || (p[1] != EXT_WORD_DIRECT && p[1] != EXT_CLOSURE_NEW))
        return 0;
    *target = abc_u32(p + 2);
    return *target < module->function_count;
}

int abc_residual_analysis_build_call_graph(const abc_module *module,
    abc_residual_call_graph *graph)
{
    uint32_t n = module->function_count;
    uint32_t *cursor = NULL, *reverse_offsets = NULL, *reverse_edges = NULL;
    uint32_t *order = NULL, *stack = NULL, *next = NULL, *sizes = NULL;
    uint8_t *seen = NULL;

    graph->count = n;
    graph->offsets = calloc((size_t)n + 1, sizeof *graph->offsets);
    graph->component = malloc((size_t)n * sizeof *graph->component);
    graph->recursive = calloc(n ? n : 1, 1);
    graph->nested_eligible = calloc(n ? n : 1, 1);
    if (!graph->offsets || !graph->component || !graph->recursive ||
        !graph->nested_eligible)
        goto failed;

    for (uint32_t fi = 0; fi < n; fi++) {
        for (uint32_t pc = module->functions[fi].entry;
             pc < module->functions[fi].end;
             pc += abc_instruction_length(module->code + pc)) {
            uint32_t target;
            if (!abc_residual_analysis_direct_target(module, pc, &target))
                continue;
            if (abc_find_function(module, target) < 0) goto failed;
            graph->offsets[fi + 1]++;
        }
    }
    for (uint32_t i = 1; i <= n; i++)
        graph->offsets[i] += graph->offsets[i - 1];

    graph->edge_count = graph->offsets[n];
    graph->edges = malloc((size_t)(graph->edge_count ? graph->edge_count : 1) *
        sizeof *graph->edges);
    cursor = malloc((size_t)n * sizeof *cursor);
    if (!graph->edges || !cursor) goto failed;
    memcpy(cursor, graph->offsets, (size_t)n * sizeof *cursor);

    for (uint32_t fi = 0; fi < n; fi++) {
        for (uint32_t pc = module->functions[fi].entry;
             pc < module->functions[fi].end;
             pc += abc_instruction_length(module->code + pc)) {
            uint32_t target;
            if (abc_residual_analysis_direct_target(module, pc, &target))
                graph->edges[cursor[fi]++] =
                    (uint32_t)abc_find_function(module, target);
        }
    }

    reverse_offsets = calloc((size_t)n + 1, sizeof *reverse_offsets);
    reverse_edges = malloc((size_t)(graph->edge_count ? graph->edge_count : 1) *
        sizeof *reverse_edges);
    order = malloc((size_t)n * sizeof *order);
    stack = malloc((size_t)n * sizeof *stack);
    next = malloc((size_t)n * sizeof *next);
    seen = calloc(n ? n : 1, 1);
    if (!reverse_offsets || !reverse_edges || !order || !stack || !next || !seen)
        goto failed;

    for (uint32_t i = 0; i < graph->edge_count; i++)
        reverse_offsets[graph->edges[i] + 1]++;
    for (uint32_t i = 1; i <= n; i++)
        reverse_offsets[i] += reverse_offsets[i - 1];
    memcpy(cursor, reverse_offsets, (size_t)n * sizeof *cursor);
    for (uint32_t from = 0; from < n; from++)
        for (uint32_t i = graph->offsets[from]; i < graph->offsets[from + 1]; i++)
            reverse_edges[cursor[graph->edges[i]]++] = from;

    uint32_t order_count = 0;
    for (uint32_t start = 0; start < n; start++) {
        if (seen[start]) continue;
        uint32_t depth = 1;
        stack[0] = start;
        next[0] = graph->offsets[start];
        seen[start] = 1;
        while (depth) {
            uint32_t at = depth - 1, value = stack[at];
            if (next[at] < graph->offsets[value + 1]) {
                uint32_t to = graph->edges[next[at]++];
                if (!seen[to]) {
                    seen[to] = 1;
                    stack[depth] = to;
                    next[depth] = graph->offsets[to];
                    depth++;
                }
            } else {
                order[order_count++] = value;
                depth--;
            }
        }
    }

    for (uint32_t i = 0; i < n; i++) graph->component[i] = UINT32_MAX;
    uint32_t components = 0;
    for (uint32_t oi = order_count; oi; oi--) {
        uint32_t start = order[oi - 1];
        if (graph->component[start] != UINT32_MAX) continue;
        uint32_t depth = 1;
        stack[0] = start;
        graph->component[start] = components;
        while (depth) {
            uint32_t value = stack[--depth];
            for (uint32_t i = reverse_offsets[value];
                 i < reverse_offsets[value + 1]; i++) {
                uint32_t to = reverse_edges[i];
                if (graph->component[to] == UINT32_MAX) {
                    graph->component[to] = components;
                    stack[depth++] = to;
                }
            }
        }
        components++;
    }

    graph->component_count = components;
    sizes = calloc(components ? components : 1, sizeof *sizes);
    if (!sizes) goto failed;
    for (uint32_t i = 0; i < n; i++) sizes[graph->component[i]]++;

    uint8_t *component_nontail =
        calloc(components ? components : 1, 1);
    if (!component_nontail) goto failed;

    for (uint32_t from = 0; from < n; from++) {
        int self = 0;

        for (uint32_t i = graph->offsets[from];
             i < graph->offsets[from + 1]; i++)
            if (graph->component[graph->edges[i]] ==
                    graph->component[from] &&
                graph->edges[i] == from)
                self = 1;
        for (uint32_t pc = module->functions[from].entry;
             pc < module->functions[from].end;
             pc += abc_instruction_length(module->code + pc)) {
            uint32_t target;

            if (abc_residual_analysis_direct_target(
                    module, pc, &target) &&
                op_kind[module->code[pc]] == K_CALL) {
                int to = abc_find_function(module, target);

                if (to >= 0 &&
                    graph->component[to] ==
                        graph->component[from])
                    component_nontail[
                        graph->component[from]] = 1;
            }
        }
        graph->recursive[from] =
            (uint8_t)(sizes[graph->component[from]] > 1 || self);
    }
    for (uint32_t from = 0; from < n; from++)
        graph->nested_eligible[from] =
            (uint8_t)(graph->recursive[from] &&
                !component_nontail[graph->component[from]]);
    free(component_nontail);

    free(cursor);
    free(reverse_offsets);
    free(reverse_edges);
    free(order);
    free(stack);
    free(next);
    free(sizes);
    free(seen);
    return 1;

failed:
    free(cursor);
    free(reverse_offsets);
    free(reverse_edges);
    free(order);
    free(stack);
    free(next);
    free(sizes);
    free(seen);
    abc_residual_analysis_call_graph_free(graph);
    return 0;
}

abc_residual_argument_fact abc_residual_analysis_argument_fact(
    abc_symbolic_value value)
{
    return value.kind == ABC_SYM_CONST
        ? (abc_residual_argument_fact){
            ABC_RESIDUAL_FACT_CONSTANT, value.constant
        }
        : (abc_residual_argument_fact){ABC_RESIDUAL_FACT_UNKNOWN, 0};
}

int abc_residual_analysis_activate_facts(const abc_module *module,
    abc_residual_argument_fact **facts, uint8_t *needed, uint8_t *dirty,
    uint32_t function, int unknown)
{
    if (!facts[function]) {
        uint32_t count = module->functions[function].arguments;
        facts[function] = calloc(count ? count : 1, sizeof *facts[function]);
        if (!facts[function]) return 0;
        needed[function] = 1;
        dirty[function] = 1;
    }
    if (unknown)
        for (uint32_t i = 0; i < module->functions[function].arguments; i++)
            if (facts[function][i].kind != ABC_RESIDUAL_FACT_UNKNOWN) {
                facts[function][i].kind = ABC_RESIDUAL_FACT_UNKNOWN;
                dirty[function] = 1;
            }
    return 1;
}

int abc_residual_analysis_join_call_facts(const abc_module *module,
    abc_residual_argument_fact **facts, uint8_t *needed, uint8_t *dirty,
    const abc_residual_call *call)
{
    uint32_t function = call->target;
    if (call->arguments != module->functions[function].arguments ||
        !abc_residual_analysis_activate_facts(module, facts, needed, dirty,
            function, 0))
        return 0;
    for (uint32_t i = 0; i < call->arguments; i++) {
        abc_residual_argument_fact incoming = call->facts[i];
        abc_residual_argument_fact *header = &facts[function][i];
        abc_residual_argument_fact_kind old = header->kind;
        if (old == ABC_RESIDUAL_FACT_UNREACHED)
            *header = incoming;
        else if (old == ABC_RESIDUAL_FACT_CONSTANT &&
            (incoming.kind == ABC_RESIDUAL_FACT_UNKNOWN ||
             (incoming.kind == ABC_RESIDUAL_FACT_CONSTANT &&
              incoming.constant != header->constant))) {
            header->kind = ABC_RESIDUAL_FACT_UNKNOWN;
            header->constant = 0;
        }
        if (header->kind != old) dirty[function] = 1;
    }
    return 1;
}
