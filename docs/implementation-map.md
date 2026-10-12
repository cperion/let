# Worklist implementation map

This is the file-level companion to [WORKLIST.md](../WORKLIST.md), not another status
ledger. IDs refer to its live checkboxes. **Existing** paths are inspection/change
anchors; **new** paths are proposed responsibility boundaries to create with their
first integrated implementation, not empty scaffolding. Do not change every listed
file mechanically: trace the affected contract and record the actual touched subset.

Before a chunk, append its exact files/removals and relevant tests to its worklist
item. Keep stable IDs when splitting tasks. Interface authority for runtime work:
[runtime-interfaces.md](runtime-interfaces.md), with algorithms in
[runtime-primitives.md](runtime-primitives.md). Source semantics remain in their
feature specs. Do not start a fresh architecture discussion for choices already made;
raise only concrete mismatches or the listed hard gates.

## A / R — Runtime audit and execution-region work

| IDs | Existing files to inspect/change | Required change / removal |
| --- | --- | --- |
| A01–A02 | `Makefile`, `gen/semantics.lua`, `gen/banked.lua`, `gen/symbolic.lua`, `src/residualize.c`, `src/symbolic.c`, `src/verify.c`, `docs/`, `REFACTOR.md` | Trace active graph, remove obsolete paths only after consumer audit; reconcile superseded GC/profile target prose |
| A03–A05 | `Makefile`, `tools/validate_execution_emit.c`, `tools/validate_backedges.c`, `tools/validate_capacity_frontiers.c`, `tools/validate_lifetime.c`, `tools/validate_cache.c`, `tools/validate.lua` | Clean/sanitizer and placement coverage at closure; do not convert every edit into a full validation gate |
| A06–A08 | `src/execution_emit.h`, `src/native_image.c`, `src/threaded_emit.c`, `src/residualize.c`, `research/experiments/threaded-residual/integration/` | Expose complete accounting; add new exclusive evidence runs without overwriting old logs |
| R01–R03 | `src/residualize.c` (`Version`, `Compiler`, context/version selection), `src/symbolic.h`, `src/symbolic.c`, `src/residualize.h` | Replace current version-owner/accounting logic with explicit caller-root realization ownership; internal labels are not new budgets |
| R04–R05 | `src/vm.c`, `src/vm_internal.h`, `src/native_image.c`, `src/threaded_emit.c`, `gen/execution_forms.lua`, `tools/validate_backedges.c`, `tools/validate_type_versions.lua`, `tools/validate_continuations.lua` | Preserve site identity and backend contracts; add cross-caller accounting/adversarial region fixtures |

New region tests: `tools/validate_regions.c` and associated assembly fixtures.
No separate native value IR or region allocator file is planned.

## S / F — Source architecture and actual frontend completion

| IDs | Existing files | Touch / replace |
| --- | --- | --- |
| S01–S03 | `frontend/let/semantic.lua`, `analysis.lua`, `resolve.lua`, `check.lua`, `ir.lua`, `schema/ir.lua`, `specialize.lua` | Introduce specified value/place/state/knowledge/demand identities into the authoritative semantic path; replace AST-kind staticness shortcuts, not the IR with another frontend |
| S04 | `frontend/let/compiler.lua`, `stage.lua`, `abi.lua`, `tools/abc`, `tools/slet_frontend.lua`, `src/cli.c` | Thread static policy/session through typed/compile/CLI APIs; keep parsing independent and runtime tier separate |
| S05–S06 | `frontend/let/stage.lua`, `abi.lua`, `compiler.lua`, `abc.lua`, `src/vm.c`, `src/memory_module.c`, `include/abc.h` | Add explicitly checked aggregate/state transport, persistent initializer images and cleanup; public ABI changes need review |
| S07–S08 | `frontend/tests/staging.lua`, `staging_sessions.lua`, `staging_no_optimizer.lua`, `compiler.lua`, `tools/validate_staging_abi.c`, `tools/validate_lifetime.c` | End-to-end demand/session/snapshot tests, removal of replaced orchestration, memory/time evidence |
| F01 | `docs/syntax.md`, `frontend/let/parse.lua`, `semantic.lua`, `abc.lua`, `check.lua`, all `frontend/tests/` | Build syntax→execution matrix from current acceptance/rejection sites; do not list tested methods/defer/etc. as absent |
| F02–F03 | `frontend/let/semantic.lua` partial/keyed/capture paths, `abc.lua` callable transport, `schema/ir.lua`, `check.lua` | Complete nested keyed partials and owned callables; remove profile-based retention bans only with O proofs |
| F04–F05 | `frontend/let/schema.lua`, `schema/ir.lua`, `semantic.lua`, `abc.lua`, `compiler.lua`, `src/verify.c` | Address-bearing sums, recursive/export ABI, borrowed export aliases, remaining result/inference contracts |
| F06–F07 | `frontend/let/compiler.lua`, `semantic.lua`, `diag.lua`, `abc.lua`, `tools/abc`, `frontend/tests/compiler.lua`, `lambdas.lua`, `tools/validate_slet_frontend.lua` | Module/program/foreign/defer completion and source diagnostics, not wholesale reimplementation of working paths |

New source infrastructure files: `frontend/let/source_state.lua` for identity/state
storage and `frontend/let/demand.lua` for query dependencies/work scheduling. These
are metadata mechanisms used by `semantic.lua`, not independently executable evaluators.
New tests: `frontend/tests/source_demands.lua`, `source_snapshots.lua`; wire them in
`Makefile` only with the integrated paths. F01 matrix belongs in
`docs/frontend-implementation-matrix.md` when audited, not a speculative filled table.

## E / O — Primitive contracts, ownership and execution state

| IDs | Existing files | New files / concrete responsibility |
| --- | --- | --- |
| E01 | `tools/opcodes.lua`, `tools/gen_opcodes.lua`, `gen/semantics.lua`, `gen/banked.lua`, `gen/symbolic.lua`, `frontend/let/abc.lua`, `src/verify.c`, `Makefile` | `gen/runtime_primitives.lua`: authoritative effect/holding/layout catalog; generated `build/generated/runtime_primitives.h` and frontend metadata, never hand-edited |
| E02, O04–O07 | `src/internal.h`, `src/vm_internal.h`, `gen/execution_forms.lua`, `gen/threaded.lua`, `gen/stencils.lua`, `frontend/let/abc.lua` | `src/owner.h/.c`, `src/type_ops.h`, `gen/type_ops.lua`: owner/count/iterative release ABI; generated type holding operations bind without recursive VM calls |
| E03, T03–T04 | `src/execution_emit.h`, `src/residualize.c/.h`, `src/symbolic.c/.h`, `src/vm.c`, `src/vm_internal.h`, `src/threaded.h`, `src/threaded_emit.c`, `src/native_image.c`, `gen/banked.lua`, `gen/cold.lua`, `gen/threaded.lua`, `gen/stencils.lua`, `gen/execution_forms.lua` | `src/task.h/.c`: task-owned state; extend emitter entry/resume contract, generate save/restore from existing placement, remove task stack addresses from shared image constants |
| E04 | same E03 bindings plus P/T files below | Exact ticket/state/lock protocol in `task.c`, `channel.c`, `task_select.c`, `scheduler.c`; no generic concurrency facade |
| E05 | `src/native_image.c`, `src/native_emit.c/.h`, `src/execution_emit.h`, `src/residualize.c/.h`, `src/vm.c` | Immutable per-realization publication/entry slots; remove whole-image lazy RW/RX reopening. Preserve emitter-owned relocations/W^X |
| E06, O08 | `Makefile`, `tools/validate_execution_emit.c`, `tools/validate_api.c`, `tools/validate_lifetime.c`, `frontend/tests/compiler.lua` | New `tools/validate_owners.c`, `tools/validate_task_resume.c`; integrate typed owner/suspension fixtures across modes |
| O01–O03 | `frontend/let/semantic.lua`, `analysis.lua`, `check.lua`, `schema/ir.lua`; S metadata above | `frontend/let/ownership.lua`: root/borrow/strict-edge summaries, SCC solving and diagnostics; `frontend/tests/ownership.lua`: rejected cycles and retained-access cases |

`src/dynamic.c`, `src/dynamic.h`, `src/whippet_types.h` and archived tracing engines
are not runtime prerequisites. Audit their references before removal; do not add them
to Makefile object lists to obtain an allocator or descriptor implementation.

**D07 is mandatory removal, not permanent exclusion from linking:** delete
`vendor/whippet` and `src/whippet_types.h`, and remove active Whippet integration
from Makefile, CI/dependency metadata, tracing adapters/descriptors, root registration,
collection safepoints and obsolete tests/examples. Audit `src/dynamic.c/.h` and
`src/any_repr.h` for remaining dependencies without deleting unrelated scalar/value
contracts. Preserve replacement lifetime/error/foreign synchronization guarantees.
Historical archives may retain original sources/references but never feed an active
build. The exit criterion is no active Whippet dependency or dormant collector path.

## C / D / L — Containers, dynamic values and library

| IDs | Existing files | New files / touch |
| --- | --- | --- |
| C01–C02 | `frontend/let/schema.lua`, `semantic.lua`, `abc.lua`, `src/internal.h` | `src/store.h/.c`, `frontend/tests/stores.lua`, `tools/validate_store.c`: stable segments, slot checks, transactional copy, safe borrows |
| C03–C07 | `frontend/let/schema.lua`, `semantic.lua`, `abc.lua`, primitive catalog and owner binding | `src/value_buffer.h/.c`, `frontend/tests/value_buffers.lua`, `tools/validate_value_buffers.c`: list/string layout, copy/detach, freeze, self-insertion and allocation failure |
| D01–D02 | `src/any_repr.h`, `src/module.c`, `src/memory_module.c`, `src/verify.c`, `gen/semantics.lua`, `gen/scalar.lua`, `gen/scalar_semantics.lua`, shared execution generators, `frontend/let/abc.lua` | New checked dynamic layout metadata only after representation decision. Audit existing `any_repr.h` before reuse; do not assume its historical bits match the new contract |
| D03 | `frontend/let/semantic.lua`, `schema/ir.lua`, `check.lua`, `abc.lua`, `frontend/tests/compiler.lua` | Remove/replace legacy `WordGet/Set/Method` and mutable-open-word supply expectations coherently; no new facade over them |
| D04–D06 | dynamic bindings above, `src/vm_internal.h`, `src/residualize.c`, `frontend/let/compiler.lua` | `src/value_table.h/.c`, `frontend/tests/value_tables.lua`, `tools/validate_value_tables.c`: ordered COW map/dense storage and non-owning shape facts. Table physical design is still D04's explicit gate |
| L01–L05 | `docs/owners-references-ids.md`, `frontend/let/lex.lua`, `parse.lua`, `semantic.lua`, `abc.lua`, standard module discovery | Proposed implementation files `std/text.let`, `std/fmt.let`, `std/pattern.let` and corresponding tests after module loading exists. These filenames do not approve public `std.fmt`/`std.pattern` namespaces; `docs/stdlib.md` owns the inventory and L01 settles export placement. Bind byte primitives through catalog, not Lua source execution |

Public module metadata changes also touch `docs/module-format.md`, `schema/module.asdl`,
assembler/disassembler and verifier tests. Assign revision/profile decisions before
serializing; filenames in this table do not authorize an implicit format extension.

## U / X / Q — Language unification and syntax elaboration

| IDs | Existing files | Touch / new tests |
| --- | --- | --- |
| U01–U02 | `frontend/let/compiler.lua`, `semantic.lua`, `analysis.lua`, `check.lua`, `schema/ir.lua`, `abc.lua` | Replace `PROFILES` semantic switches and `.managed/.dynamic` ownership assumptions with checked capabilities; new `frontend/let/effects.lua` for summaries, not another evaluator |
| U03–U05 | `frontend/let/compiler.lua`, `tools/abc`, `tools/slet_frontend.lua`, `src/cli.c`, `Makefile`, `examples/`, `frontend/tests/`, `tools/validate_slet_frontend.lua`, active docs; editor configs if found | Rename active `.slet` fixtures/entry tools and remove dual discovery/ambiguity logic. Archive names stay intact; no `.slet` alias |
| X01–X03 | `frontend/let/lex.lua`, `parse.lua`, `schema/ast.lua`, `ast.lua`, `semantic.lua`, `check.lua`, S metadata | Add explicit spread/rest nodes and second-class pack elaboration; no runtime pack tag. New `frontend/tests/spread.lua` |
| X04–X06 | same plus `compiler.lua:indexDeclarations/typedFile` and `resolve.lua` | Keyed override/name-introduction/import-sugar checks; preserve declaration visibility and one module initialization |
| Q01–Q04 | `frontend/let/schema.lua`, `semantic.lua`, `check.lua`, `schema/ir.lua`, `abc.lua` | Preserve schema operator authority, resolve ordinary methods, index place-aware read/modify/write; new `frontend/tests/operators.lua` |
| Q05–Q06 | `frontend/let/parse.lua`, `schema/ast.lua`, `semantic.lua`, `frontend/tests/lambdas.lua` | Desugar one literal-led argument (literal plus member/index/explicit-call chain), block-only application and trailing blocks before argument adjustment; preserve contextual types/captures/return, minus, indexing and keyed supplies. No signature-aware parsing. New `frontend/tests/trailing_blocks.lua` and literal-call cases |
| Q07 | Q static files plus D type descriptors and callable lowering | Dynamic descriptor dispatch calls ordinary implementations; no per-instance tables or backend scalar copies |
| Q08 | `frontend/let/semantic.lua` result inference, method/lambda builders, `Function:build` and defer scopes; `check.lua`, `schema/ir.lua`, `abc.lua`, `frontend/tests/compiler.lua`, `lambdas.lua`, operator tests | Unit fallthrough uses ordinary bare-return cleanup. Add §10's conservative resolved-SCC unit classification before any defaults, excluding nested callable returns and respecting non-unit contracts. Preserve inner-block flow; no last-expression value return |

Q09 touches `frontend/let/lex.lua` (remove `->` token), `parse.lua:lambda` (unified
`do(parameters)` with expression/block bodies), `frontend/ast.asdl` (optional lambda
result annotation), semantic result/context checking, active tests/examples and source
emitters. Remove prefix-pipe parsing and closing-pipe annotation state; `|` remains an
infix operator. Explicit nullary parentheses are required for expression lambdas.
No VM node, old spelling alias or migration-specific arrow diagnostic is added.
Retain historical archives and label old probe output as pre-migration evidence.

Q10 touches `frontend/let/parse.lua:primary/lambda/body`, `schema/ast.lua`, traversal
consumers, `semantic.lua` callable/capture/result and top-level value construction,
`compiler.lua:indexDeclarations/typedFile` callable-binding exports, and CLI main
entry discovery where it relies on direct named words. Normalize a standalone block
and a trailing block to the same ordinary lambda representation; do not add an eager
block-expression evaluator. Update `frontend/tests/lambdas.lua`, `compiler.lua`, parser
and trailing-block fixtures. Cross-reference S06/F04/F06 for module/ABI lifetime work.
A lambda's `=` permits nested lambdas without grouping. Named-definition `= do`
remains an executed body and rejects `do(...)`; group a lambda returned from a named
expression body. Test explicit/contextual result agreement and main's unchanged u32 ABI.
An ungrouped block-lambda atom cannot accept postfix/self-delimited continuation;
Q10 must test post-end newlines, explicit grouping and unchanged infix continuation.

Q11 touches `frontend/let/semantic.lua` invoked-member/call resolution,
`resolve.lua`, `schema.lua`, `check.lua` and ordinary IR consumers. Existing member
wins; a closed interface without it enables lexical receiver insertion. Keep table/any
and namespace paths separate. Resolve generics in definition scope, retain copy/ref
semantics and add `frontend/tests/receiver_calls.lua` for priorities, imports, failure,
copy-transform/ref-mutation and effect order. No runtime dispatch node or member table
is needed solely for this sugar. `fmt` remains the existing lexical operation.

Q03 lexical operator fallback uses existing interface/name resolution in
`semantic.lua` and ordinary operator elaboration/checking; extend
`frontend/tests/operators.lua` for primitive > left member > right member > lexical
function, import-spread opt-in, generic definition scope and typed failures without
fallback. Do not reuse a left receiver-call rewrite that bypasses the right member.
No operator registry/descriptor mutation or dynamic missing-key fallback is needed.

Do not modify runtime arithmetic to implement static `op_add`; it is an ordinary
resolved method. Do not expand all argument lists in the VM to implement source packs.

Explicit-requirement adapters (`logged(t: type, f: t, ...args)`) use `semantic.lua`,
`specialize.lua`, source demand/value-place elaboration and `check.lua`, not implicit
parameter generics or a dynamic-any adapter. In `frontend/tests/spread.lua`, validate
static type-only partial supply before rest saturation and direct/typed-indirect
callee paths. Return/defer lowering in `abc.lua` must preserve arbitrary known result
vectors across post-call actions: extend frontend return/defer execution fixtures for
live holdings, clobbers, effects and ordinary continuations. No new runtime pack,
decorator dispatcher, result tuple or callback evaluator. See `docs/spread.md` §3.

## T / P / W — Tasks, pthreads and AOT

| IDs | Existing files | New files / concrete responsibility |
| --- | --- | --- |
| T01–T02 | source ownership/effect files above, `semantic.lua`, `check.lua`, `compiler.lua`, `gen/foreign.lua`, `build/generated/foreign.c` (generated output only) | Scoped capability/world/foreign summaries and ABI checks; new `frontend/tests/tasks.lua` |
| T03–T04 | E03 files | Suspension integration, not a second task interpreter |
| T05 | owner/task/context bindings above | `src/task_group.h/.c`: structural registry, join results and cancellation registration; explicit error/shutdown contracts |
| T06 | task and TypeOps interfaces | `src/channel.h/.c`: ring/FIFO wait registration, holding transfer and close/drain |
| T07 | channel/task interfaces | `src/task_select.c`: arbitration, multi-registration, winner/loser ownership and timer interactions |
| T08–T09 | group/channel/select + generated execution bindings | New `tools/validate_tasks.c` and `tools/validate_task_resume.c`; cooperative cancellation, inherited state and all-mode transport |
| P01 | `Makefile`, task/scheduler clients | `src/thread_platform.h/.c`: narrow pthread mutex/cond/thread/monotonic-clock wrapper, startup failure and shutdown |
| P02 | task/context files | `src/scheduler.h/.c`: locked deques, steals, idle generation, worker lifecycle and timer heap |
| P03 | E05 files, `src/vm.c`, `src/vm_internal.h`, `src/module.c` | Concurrent site/image publication and lifetime; remove task-bound image constants |
| P04 | owner files and allocator call sites | Direct thread-safe platform frees first; any later cached allocator needs separately measured/approved remote-free binding |
| P05–P07 | `include/abc.h` only for approved embedding changes, `src/vm.c`, `gen/foreign.lua`, task/scheduler code | Foreign affinity/blocking, abort and shutdown; new `tools/validate_scheduler.c`, exclusive performance/race evidence directories |
| W01–W02 | `src/residual_c.c`, `src/residual_ir.c/.h`, `src/residual_builder.c/.h`, `schema/residual.asdl`, `include/abc_tool.h`, `tools/abc_opt.c`, `tools/validate_c_aot.lua` | Extend checked C subset with explicit resumable task state, not recursive host suspension. Reuse logical task contract without feeding a new IR into runtime JIT |
| W03–W04 | `Makefile`, runtime source lists, generated C integration tests | New `tools/validate_wasm_tasks.*` and documented Emscripten configuration once task AOT exists; no direct JS worker engine |

Makefile generates `build/generated/foreign.c` from `gen/foreign.lua`; edit the
generator, not that disposable output. The static and PIC foreign objects consume it.
Standard task source facade target: new `std/task.let`, exposing ordinary typed words
backed by the checked primitive contracts; not a runtime-only untyped binding layer.

## Evidence and removals required with implementation

Each implementing chunk records: changed responsibility, actual files, removed old
paths, focused integrated checks, known failures and cost observations. Examples:

- E03 removes host-only completion assumptions, not existing explicit continuations.
- E05 removes lazy whole-mapping reopen, not W^X or original callable identity.
- U removes filename semantic profiles, not unsupported-feature checks before support.
- D03 removes legacy open-word semantics, not unrelated typed method support.
- X/Q remove no existing evaluation-order rule; additions elaborate through that rule.

No fixture or baseline result is overwritten to make a change appear green. No
full-suite run is required merely for editing this planning map.
