# Remaining work — live checklist index

The authoritative project-management record is [WORKLIST.md](../WORKLIST.md).
It combines older unfinished VM/frontend work with newly specified features, using
stable checkbox IDs, dependencies, acceptance conditions and completion evidence.
Do not maintain a second status list here.

The checklist is grounded in a focused current-code audit at `06ec9dc` and a fresh
passing incremental `all validate` run. [Audit evidence](../research/experiments/project-state-audit/06ec9dc/README.md).
It explicitly distinguishes tested frontend foundations from their remaining gaps;
methods, keyed/static supply, nested words, pointers, extern/defer and block lambdas
must not be described as wholly absent. Full feature-matrix review remains F01.

| Workstream | Live IDs |
| --- | --- |
| Existing migration audit, safety and performance qualification | A |
| Caller-owned execution regions, distinct from source owners | R |
| Source values/places/demands, VM staging policy and snapshots | S |
| Specific frontend/ABI/module completion gaps | F |
| Shared primitive/holding/suspension ABI and concrete runtime integration | E |
| Collector-free proof, placement and release | O |
| Stores/ids and COW/frozen values | C |
| Dynamic execution and value tables | D |
| Text/format/pattern libraries | L |
| Independent capabilities and `.let`-only migration | U |
| Structured task semantics and suspension | T |
| Pthread scheduler and concurrency protocols | P |
| Task AOT and Emscripten deployment | W |
| Spread, packs and import sugar | X |
| Schema operators and trailing blocks; separate dynamic dispatch | Q |
| Deferred/excluded ideas, not active completion obligations | Z |

[REFACTOR.md](../REFACTOR.md) retains architecture and chronological evidence.
[frontend-completion-plan.md](frontend-completion-plan.md) is supporting dependency
rationale; feature specs remain semantic authorities, not implementation claims.
