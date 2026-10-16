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
| S01–S03 | `frontend/let/semantic.lua`, `analysis.lua`, `source_state.lua`, `check.lua`, `ir.lua`, `schema/ir.lua`, `specialize.lua` | Introduce specified value/place/state/knowledge/demand identities into the authoritative semantic path; replace AST-kind staticness shortcuts, not the IR with another frontend |
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

**Removal checkpoint:** the v3 owner orchestration and subsequent large redesign
proposal remain removed. The connected replacement now uses checked source proofs,
concrete physical storage and six narrow C bindings over the small counting/queue core.
See WORKLIST E/O and `research/experiments/runtime-owners/source-cutover/` for exact
supported source execution, failure, full incremental and focused sanitizer evidence;
generalized owning public/foreign/container/task and erased contracts remain incomplete.

| IDs | Existing files | New files / concrete responsibility |
| --- | --- | --- |
| E01 | `tools/assembler.lua`, `src/internal.h`, `src/module.c`, `src/memory_module.c`, `src/verify.c`, `src/optimize.c`, `src/cli.c`, `gen/cold.lua`, `Makefile` | Revision-7/profile-4 section-10 C-entry metadata implemented; explicit `.centry`, typed entry-role validation, distinct optimizer roots/index rewriting and ABC target exclusion. `tools/validate_c_entries.lua`/`.c` cover format and fail-closed boundaries. `src/lifetime.h/.c` validates/binds six exact reserved source contracts. VM/residualizer/native-emitter prepare and publish real C lifecycle entries in all modes; tooling residual IR/portable C still reject. No new instruction/cell kind, primitive catalog or retired import fallback |
| E02, O04–O07 | `src/internal.h`, `src/vm_internal.h`, `gen/execution_forms.lua`, `gen/threaded.lua`, `gen/stencils.lua`, `frontend/let/abc.lua` | `src/owner.h/.c`: standalone C concrete-allocation/count/replacement/queue core; no stored payload offset, progress or traffic counters. `frontend/let/placement.lua` (new) consumes checked roots into concrete frames/payloads, direct holding copies/moves, caller result records and concrete C-entry field drops (including finite active-tag branches). Tagged payloads use canonical packed cells with ADDR2BITS/BITS2ADDR; compiler-only holding traversal never becomes runtime metadata. `layout.lua` selects source borrowed/owning contracts and describes the physical graph. `src/lifetime.h/.c` (new), owner/context/VM/residualizer/emitter and stencil bindings own allocation/cleanup delivery without scope slots, prefix, release cache, dispatcher or pinned register. Unresolved placement/representation and owning public/foreign contracts reject |
| E03, T03–T04 | `src/execution_emit.h`, `src/residualize.c/.h`, `src/symbolic.c/.h`, `src/vm.c`, `src/vm_internal.h`, `src/threaded.h`, `src/threaded_emit.c`, `src/native_image.c`, `gen/banked.lua`, `gen/cold.lua`, `gen/threaded.lua`, `gen/stencils.lua`, `gen/execution_forms.lua` | `src/execution_context.h`: persistent root/context-bound limits plus concrete activation chain/owner queue; no second cleanup execution context. Ownership SERVICE/resume snapshots remain removed; source entry returns packed status. `src/task.h/.c` and PARK/task scheduling remain pending |
| E04 | same E03 bindings plus P/T files below | Exact ticket/state/lock protocol in `task.c`, `channel.c`, `task_select.c`, `scheduler.c`; no generic concurrency facade |
| E05 | `src/native_image.c`, `src/native_emit.c/.h`, `src/execution_emit.h`, `src/residualize.c/.h`, `src/vm.c` | Fresh-page RX publication/atomic entry slots implemented; published bytes never reopen RW. Emitter region diagnostics replace contiguous-code views. Qualify fragmentation and broader image sharing/lifetime |
| E06, O08 | `Makefile`, `tools/validate_execution_emit.c`, `tools/validate_api.c`, `tools/validate_lifetime.c`, `frontend/tests/compiler.lua` | `tools/validate_owner_core.c` covers the standalone C core; `tools/validate_c_entries.lua`/`.c` cover format/ABC exclusion. New `frontend/tests/source_owners.lua` and `tools/validate_source_owners.c`, wired into `validate`, execute actual source success/failure and generated C cleanup in four modes, raw/optimized/both lifecycle banks, including tagged partial acquisition and active-case-only cleanup. `tools/opcodes.lua`, `gen/semantics.lua`, residualizer/optimizer and `schema/residual.asdl` bind the two raw address casts; ISA/oracle/residual/cache tests cover both banks and exact bits. Old v3 fixtures remain removed; task integration still pending |
| O01–O03 | `frontend/let/semantic.lua`, `source_state.lua`, `analysis.lua`, `access.lua`, `check.lua`, `frontend/ir.asdl`, generated `schema/ir.lua`; S metadata above | `frontend/let/program.lua` owns the completed graph and access/ownership results; `ownership.lua` retains the root/borrow/count/edge solver and iterative SCC diagnostics. `check.lua` is structural/type-only. Removed function proof annotations and checker-driven inference; semantic/compiler/demand/specialization producers now pass a checked program to ABC. `tests/program.lua` and `tests/ownership.lua` cover the boundary and proofs. Supported counted source executes through the separate physical materializer; broad precision/ABI/representation debt remains under WORKLIST O03–O08 |

Historical v1/v2/v3 evidence remains under `research/experiments/runtime-owners/`.
It describes removed bindings, not current execution. The subsequent minimal C-entry
format is tracked separately under E01 and `runtime-owners/c-entry-format/`; it does
not restore those bindings. The source-cutover evidence separately qualifies the new
concrete source path without a cleanup engine or release register reservation.
Ordinary ABC execution and immutable executable publication are retained.

**D07 collector removal:** `vendor/whippet` has been deleted. The old
`src/dynamic.c/.h`, `src/any_repr.h` and `src/whippet_types.h` were already absent;
no active build/CI dependency, tracing adapter, root registration, collection hook or
obsolete GC fixture remained to remove. `tools/validate_no_collector.lua`, wired into
`make validate`, guards active paths, collector APIs/link flags and archive imports,
with negative controls. Historical archives/raw evidence remain unchanged and must
not feed active builds. The existing residual `safepoint` effect bit is conservative
call synchronization, not a collection mechanism; this removal preserves it.

The supported source lifetime/error/foreign boundaries are validated separately in
E/O. Removing the dormant collector does not implement owning public/foreign transport,
persistent owning modules, generalized ownership or tasks. Current removal evidence:
`research/experiments/runtime-owners/collector-removal/`.

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
| X01–X03 | `frontend/ast.asdl`, `frontend/let/lex.lua`, `parse.lua`, `schema/ast.lua`, `source_state.lua`, `compiler.lua`, `semantic.lua`, `check.lua`, S metadata | Spread/rest syntax and suffix vocabulary nodes now parse, including initialized contexts; shared ordered/keyed supplies and second-class rest packs execute through source-only templates. `source_state.lua` owns qualified formation anchors; `semantic.lua` builds typed component recipes and invokes the same word elaborator once per specialization. `tests/spread.lua` and `tests/rest_templates.lua` cover admission and execution; templates have no erased variadic ABC entries. Shared vocabulary binding, namespace lookup and capture integration execute through `source_state.lua`/`semantic.lua`; semantic coverage: `frontend/tests/vocabulary.lua`. Type/function exports share one public namespace. No runtime pack or namespace tag. Syntax tests: `frontend/tests/syntax_batch.lua`. |
| X04–X06 | same plus `compiler.lua:indexDeclarations/typedFile` and binding-resolved semantic lookup | Keyed override/name-introduction/import-sugar checks; preserve declaration visibility and one module initialization |
| X07 | `frontend/ast.asdl`, `parse.lua`, generated `schema/ast.lua`; `frontend/let/semantic.lua` parameter bindings, opening, reads/stores and capture transport; `source_state.lua` place/value metadata; `check.lua`; `frontend/tests/vocabulary.lua`, `receiver_scopes.lua`, `anonymous_context.lua` | Implemented within admitted typed contexts: eager field snapshots removed; field places of one retained receiver introduced. Optional-name VocabularyParam and CurrentContext support anonymous home, checked-context type, explicit `(...)` reads and expression bodies. One opening, first runtime requirement after leading Type inputs; no whole-home rebinding or public reference holder. Parameters and template recipes return bindings to shared expansion, without fabricated names. Preserve projections, permissions, lifetime/interface information and explicit saved-value reads. No new capture permission, runtime namespace or physical-C0 contract. |
| Q01–Q04 | `frontend/let/schema.lua`, `semantic.lua`, `check.lua`, `schema/ir.lua`, `abc.lua` | Preserve schema operator authority, resolve ordinary methods, index place-aware read/modify/write; new `frontend/tests/operators.lua` |
| Q05–Q06 | `frontend/let/parse.lua`, `schema/ast.lua`, `semantic.lua`, `frontend/tests/lambdas.lua` | Desugar one literal-led argument (literal plus member/index/explicit-call chain), block-only application and trailing blocks before argument adjustment; preserve contextual types/captures/return, minus, indexing and keyed supplies. No signature-aware parsing. New `frontend/tests/trailing_blocks.lua` and literal-call cases |
| Q07 | Q static files plus D type descriptors and callable lowering | Dynamic descriptor dispatch calls ordinary implementations; no per-instance tables or backend scalar copies |
| Q12 | `frontend/let/lex.lua`, `parse.lua` block/delimiter context; parser/syntax tests and documentation | Implemented `endall`: expand only a bounded trailing-callback spine to ordinary closers; `frontend/tests/endall.lua` qualifies boundaries and execution. Preserve origins, reject other contexts, and prove AST/execution equivalence. No new semantic AST/control node or runtime instruction. |
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
remains an executed body without a parameter list; `= do(...)`, including `do()`,
returns a lambda. Application suffixes always compose left, never reopen arguments.
Test explicit/contextual result agreement and the existing entry ABI policy.
An ungrouped block-lambda atom cannot accept postfix/self-delimited continuation;
Q10 must test post-end newlines, explicit grouping and unchanged infix continuation.

Q11 uses `frontend/let/semantic.lua` invoked-member/call resolution and actual-binding
capture registration, plus `source_state.lua` word/capture completion. The syntactic
`resolve.lua` capture pass is removed. Existing members win; closed-interface lexical
calls supply a copied value or borrow a writable place according to the first parameter.
Opening retains an innermost lexical receiver. X07 now replaces snapshots with live
field places, including scalar captures. Updated tests pass; broader frozen/readonly
proof remains incomplete. Pointer-free module-root storage has working-tree
qualification, but higher-order retention bounds are an explicit S05/S06 blocker;
see `research/experiments/frontend-syntax/module-aggregate-access/`.
Keep table/any and namespace paths separate. `frontend/tests/receiver_scopes.lua` covers
priorities, imports, copy/ref effects, recursive captures and noncaptures. Broader generic,
frozen-place and discarded-copy-write qualification remains open. No new runtime dispatch
node, member table, ABI or allocator is introduced. `fmt` remains the lexical operation.

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
| T06 | task and localized erased-transport interfaces | `src/channel.h/.c`: ring/FIFO wait registration, holding transfer and close/drain |
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
