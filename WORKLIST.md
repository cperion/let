# Let project worklist

**Live project-management checklist.** This is the status authority for remaining
work; [REFACTOR.md](REFACTOR.md) retains architectural rationale and chronological
implementation evidence. Feature specs define semantics, not completion. Historical
checkboxes and O1–O9 packages are supporting records, not competing live task lists.

## How to maintain this record

- Stable item IDs survive reordering. `[x]` means that exact deliverable has evidence;
  `[ ]` means open, including partial, blocked or design-only work.
- For an active item append `Owner`, `State` (design/active/blocked/partial), concrete
  scope, dependency/blocker and next action. Do not claim an owner before assignment.
  All currently open items are unassigned; dependencies below are scheduling gates.
- Before implementation, inspect code/contracts/tests and obtain approval for the
  concrete interfaces. Feature-direction approval is not approval of an unseen ABI.
- On completion record changed files, removed paths, exact checks/results and evidence
  location; distinguish fresh runs from historical results and measurements.
- Split an item if only part can close. Do not check an implementation box for docs,
  a parser-only feature, a passing output test or an unsupported-path rejection.
- Keep archive/evidence immutable. Preserve unrelated work. No subagents or internal
  plan sidecars are authorized by this file.

## Execution policy: substantial changes, boundary validation

The goal is to implement the approved architecture, not keep every intermediate
edit green. Checklist items track responsibilities; they are NOT mandatory tiny
patches or individual test gates.

- After design approval, change the authoritative contract and affected producers,
  consumers and tests together in a substantial coherent implementation chunk.
  Remove the replaced paths rather than adding temporary compatibility scaffolding.
- Combine related checklist items when that makes the replacement coherent. Do not
  stop after every file, function or checkbox to build, test or report progress.
- Temporary compile/test failures during a coordinated replacement are acceptable.
  Record them honestly when handing off; do not repair obsolete behavior merely to
  make an intermediate state green.
- Inspect enough code to understand the change, then implement. Avoid repeated
  baseline runs, broad rediscovery and documentation churn between coding steps.
- Run focused checks once the changed responsibility is integrated. Use targeted
  probes earlier only to resolve a concrete uncertainty that blocks implementation.
- Run the full suite at substantial integration/milestone boundaries, not after
  every local fix. After a failure, diagnose and batch the related corrections
  before rerunning; do not repeat unchanged broad checks mechanically.
- Sanitizers, performance experiments and full clean builds are explicit acceptance
  work for relevant milestones, not a ritual attached to every patch.
- Completion still requires appropriate evidence. A temporarily broken chunk is
  work in progress, not a completed deliverable. Material design changes still
  require discussion; this policy does not authorize unrelated rewrites.

## Audited baseline and corrections

Audit source: **06ec9dc**, initially clean working tree. Fresh incremental
`all validate` passed using `/tmp/clang20`, `/tmp/lua-compat` and strict warnings.
[Audit record and raw output](research/experiments/project-state-audit/06ec9dc/README.md).
This was not a new clean-room, sanitizer, race or performance run.

- [x] **B01** Revision-6 typed profiles 1–4 and four execution modes have a passing
  active suite: 113 oracles / 904 mirrored executions; all 282 public forms;
  660 continuations; 360 capacity-frontier cases. Evidence: audit `validation.log`.
- [x] **B02** Shared residualizer/emitter boundary and seven-register threaded tape
  are implemented (`src/residualize.c`, `execution_emit.h`, native/threaded emitters).
  Emitter and backedge tests pass. This is not concurrent execution support.
- [x] **B03** Scalar persistent staging is implemented (`frontend/let/stage.lua`):
  280 session checks, 27 staging checks and 48 module/VM lifetime cases pass.
  Aggregate transport and source-demand elaboration are NOT included.
- [x] **B04** Preserve tested typed frontend foundations: methods, full/static keyed
  supply, nested recursive words, recursive indirect types, raw pointers, extern
  lowering, defer order, import/export aliases/types and block/vector lambdas.
  Evidence: `frontend/tests/compiler.lua` (275 checks), `lambdas.lua` (269 checks,
  80 executions). Do not list these entire features as absent again.
- [x] **B05** Restricted integer/control/direct-call portable C is exercised by 12
  mirrored cases. This does NOT establish general float/indirect/dynamic/task AOT.

Code facts verified in this audit:

| Boundary | Current code evidence | Meaning for the plan |
| --- | --- | --- |
| Source profiles/imports | `frontend/let/compiler.lua`: `PROFILES`, `profileForPath`, `importPath`, `typedFile` | Both extensions/profile policies still active; U work required |
| Dynamic lowering | `frontend/let/abc.lua`: `M.lower` rejects `dynamic-lowering` | Let IR checks are not dynamic execution |
| Legacy dynamic design | `semantic.lua` emits `WordMethod`, `WordGet/Set`, runtime keyed supply; compiler tests assert it | Replace these producers/consumers/tests, not just the runtime |
| Top-level evaluation | `Semantic.build` accepts only literal top-level values, otherwise `semantic-todo` | Persistent source initialization still missing |
| Staging transport | `stage.lua:scalarTypes` rejects borrowed/non-scalar transport | VM sessions are a foundation, not aggregate staging |
| Remaining callable gaps | `semantic.lua` rejects partial keyed nested words; `abc.lua` rejects unknown/escaping owned callables and address-bearing sum ABIs | Specific gaps, not blanket missing methods/lambdas |
| Version ownership | `residualize.c`: `Version`, `version`, threshold checks remain current compiler/PC policy | No caller-owned region realization accounting yet |
| Native publication | `native_image.c` lazy preparation changes mapping RW then RX | Concurrent execution needs a real replacement protocol |
| Threads/owners/spread | Active runtime object graph has no task/owner subsystem; parser/schema have no spread/rest forms | Approved docs are not implemented features; pthread linkage in tests is not a task scheduler |

Absence searches are supporting evidence, not a proof that every path was audited.
Remaining frontend acceptance details are explicitly assigned to F01 below.

## Priority and dependencies

1. A: finish audit/qualification; S/F: complete source architecture and precise gap map.
2. O: ownership proofs and release; C/D: containers and dynamic execution.
3. U: unify `.let` once supported behavior/capabilities are coherent.
4. T: task source proofs and suspension; P: pthread scheduler/concurrency; W: task AOT/Wasm.
5. X: static spread may proceed alongside S/F after its elaboration design is approved.

R (caller-owned execution regions) is a separate runtime track, not a prerequisite
for source memory ownership. Do not confuse the two meanings of owner. Independent
items may be scheduled without waiting for an entire lettered package; each chunk
must state its actual dependencies. No dates or percentage-complete estimates are
asserted without sizing the concrete work.

## File ownership and implementation instructions

[docs/implementation-map.md](docs/implementation-map.md) maps **every workstream's
IDs to existing files, new files, consumers, tests and required removals**. Read its
row for the selected ID before implementation. New paths are targets, not existing
support. [docs/runtime-interfaces.md](docs/runtime-interfaces.md) supplies concrete
private C signatures, field layouts, ownership transfers, scheduling transitions,
lock hierarchy and generator responsibilities. Runtime algorithms are in
[docs/runtime-primitives.md](docs/runtime-primitives.md). Do not invent another ABI
or helper layer because an existing implementation file is inconvenient.

| IDs | Main existing files to touch | New responsibility files |
| --- | --- | --- |
| A/R | `src/residualize.c`, `symbolic.c`, emitter/image files, `tools/validate*`, `Makefile` | region fixtures; no second allocator |
| S/F | `frontend/let/semantic.lua`, `compiler.lua`, `stage.lua`, `abc.lua`, `check.lua`, schemas, `frontend/tests/` | `source_state.lua`, `demand.lua`, feature matrix and targeted tests |
| E/O | `src/execution_emit.h`, `vm_internal.h`, `vm.c`, `residualize.c`, shared generators, verifier, source lowering | `gen/runtime_primitives.lua`, `src/owner.h/.c`, `type_ops.h`, `frontend/let/ownership.lua` |
| C/D/L | source schemas/lowering, module/verifier metadata, scalar bindings, standard module discovery | `src/store.h/.c`, `value_buffer.h/.c`, `value_table.h/.c`, `std/text.let`, `fmt.let`, `pattern.let` |
| U | `frontend/let/compiler.lua`, `semantic.lua`, `tools/abc`, `Makefile`, active source fixtures/docs | `frontend/let/effects.lua`; retire profile dispatch, not archive names |
| T/P | task entry and all execution generators, native publication, foreign generator, module lifetime | `src/task.h/.c`, `task_group.h/.c`, `channel.h/.c`, `task_select.c`, `scheduler.h/.c`, `thread_platform.h/.c`, `std/task.let` |
| W | `src/residual_c.c`, residual builder/schema, `tools/validate_c_aot.lua`, `Makefile` | Emscripten task fixtures after resumable C exists |
| X/Q | `frontend/let/lex.lua`, `parse.lua`, AST/IR schemas, `semantic.lua`, `check.lua`, `compiler.lua` | `frontend/tests/spread.lua`, `operators.lua`, `trailing_blocks.lua` |

Before coding, record the actual chunk's file subset and removed old paths under its
ID. Paths above do not authorize unrelated cleanup or changing every file by rote.
Hard language/encoding gates remain explicit; completing a private header does not
complete its producer/consumer integration.

## A — Close existing migration and qualification

Sources: REFACTOR Phase 5; threaded and A/B experiment records. Dependency: B baseline.

- [ ] **A01** Review the complete implementation diff and active build graph for old
  A-only assumptions, quickening/reverse remnants, duplicated scalar algorithms,
  hidden adapters and dead paths; record findings, not just search counts.
- [ ] **A02** Reconcile active docs with current code and newer ownership/task specs;
  explicitly retire obsolete GC/open-word obligations while retaining history.
- [ ] **A03** Rerun clean isolated build/validation at final closure; archive source
  identity, commands and artifacts separately from this incremental audit.
- [ ] **A04** Run fresh whole-runtime sanitizer coverage and lifetime/error-path probes;
  prior partial ASan evidence is not whole-runtime coverage.
- [ ] **A05** Extend threaded placement/effect coverage beyond current handler catalog
  and focused emitter tests; include poisoned live/dead state and failure PCs.
- [ ] **A06** Account for shared handlers/tables/unwind, per-image metadata, lazy stubs,
  tape capacities, preparation peaks and retained modules—not native body bytes only.
- [ ] **A07** Repeat controlled four-mode performance measurements; report preparation,
  first/steady execution, noise and >~10% regressions. Preserve historical fib and
  threshold-16 regressions; accept or address them explicitly, not by narrative.
- [ ] **A08** Close migration only after A01–A07 evidence and outstanding deviations
  receive review. No universal speedup or completion claim from the passing suite.

## R — Caller-owned execution regions (separate architectural track)

Source: REFACTOR architectural target §§4–5, 11–12. Existing threshold 16 is NOT this.

- [ ] **R01** Approve concrete region-root/realization identities, owner scope and
  budget policy; reconcile illustrative eight-slot target with current threshold 16.
- [ ] **R02** Replace per-helper/PC competition with caller-owned realization accounting;
  virtual calls/returns stay in their caller owner, real calls have explicit boundaries.
- [ ] **R03** Define and implement entry-proof conformance, internal joins/loop widening
  and general realization selection with no unbudgeted internal version families.
- [ ] **R04** Integrate observing sites and eager/lazy/threaded policies without changing
  public callable identity, continuation transport or introducing an opaque fallback.
- [ ] **R05** Validate cross-caller isolation, recursion, saturation, bounded growth,
  failure/PC preservation and measure preparation/code/metadata/runtime costs.

Lazy bytecode is a proposed peer target, not completed by threaded tape (see Z).
The historical per-location cap violation remains evidence of old policy; do not
implement the superseded per-callee budget merely to check a legacy audit box.

## S — Source values, demands and VM-only evaluation

**Checkpoint — Owner: primary coding agent. State: partial (design approved).**
Initial S01/S02/S04/S08 application/static-demand cutover, with relevant F01/F02
and return/defer acceptance. Replace AST-shape static supply, premature callable
materialization and separate keyed static adapter orchestration with shared source
knowledge/callable records; connect required scalar demands to the existing VM
session. Preserve dynamic D03 boundaries rather than extending open-word semantics.
Files: `frontend/let/semantic.lua`, new `source_state.lua`/`demand.lua`, `compiler.lua`,
`stage.lua`, `specialize.lua`, affected IR/checker/lowering consumers, `tools/abc`,
frontend tests, Makefile and API docs. Schema changes start in `frontend/ir.asdl`.
Acceptance: aliases/computed supplies, direct/keyed/partial equivalence, runtime
rejections, exact scalar bits, returns across defer, all static modes including
optimizer-disabled execution, policy/session cleanup and unchanged failed outputs.
Aggregate snapshots, counted escapes and full persistent module images remain O/S05
and S06 dependencies, not completed by this scalar boundary.
Checkpoint evidence: `frontend/tests/source_demands.lua` passed 52 checks;
`compiler.lua` 276 checks; `lambdas.lua` 269 checks/80 VM executions;
`staging.lua` 27 checks; `staging_sessions.lua` 280 checks plus optimizer-disabled
four-mode staging. These are focused checks, not full acceptance. API documentation,
CLI/import/failure-publication validation, preparation measurements and review of
ordered effect/trap obligations in demand fragments remain outstanding. No S item
is checked off. Preserve this partial change while the approved syntax batch migrates
its active source fixtures once.

Sources: `docs/source-partial-evaluation.md`, `source-virtual-contract.md`,
`source-compilation-api.md`. B03 supplies the scalar session, not this machinery.

- [ ] **S01** Approve concrete value/place/context/state identities, knowledge/demand
  queries, recursion keys, canonicalization and ordered effect obligations in existing IR.
- [ ] **S02** Implement backward demands/forward knowledge with a real vertical slice:
  source-required static value → verified VM execution → returned knowledge → residual IR.
- [ ] **S03** Implement delayed materialization of source places and captures; preserve
  aliases, initialization, observable writes and original effect/error ordering.
- [ ] **S04** Integrate `staticMode`/CLI and owned compilation-session policy through
  typed/typedFile/compile/source-run APIs. Required demand without policy must diagnose;
  optional fold may remain residual; parsing stays backend-independent.
- [ ] **S05** Design and implement aggregate/borrow/address-bearing snapshot transport
  with ownership provenance, exact bits and failure rollback. Depends on O contracts.
- [ ] **S06** Implement persistent module initialization and dependency ordering,
  once-per-session state, durable storage and initializer cycle diagnostics.
- [ ] **S07** Validate imports/repeated compilation, required versus optional demands,
  recursive specialization, all staging modes and cleanup without partial publication.
- [ ] **S08** Remove replaced eager/AST-only staticness assumptions; retain VM-only
  computation, existing Ershov scheduling, one semantic builder and runtime independence
  from `abc-opt`. Measure specialization/preparation and snapshot retention.

## F — Finish actual frontend gaps, not already tested foundations

**Word/binding unification — Owner: primary coding agent. State: scoped implementation; integrated validation passed, remaining gates open.**
Approved reserved `oneof { ... }` and named callable entries in other headed supplies.
`Source.word`, `wordContract` and `elaborateWord` now own requirements, captures, parameter
storage, body checking and ordinary Fn emission for module/local words, lambdas and
methods. Removed separate named/lambda builders, obsolete AST result annotations,
name-shape alias reconstruction and lambda-only materialization permissions. Literal-do
bindings (including grouped literals) share recursive visibility, inference and exports
with ordered named sugar; ordinary initializers remain nonrecursive. Aliases preserve
source identity; captures materialize under the same conservative restrictions.
Sum handlers now use ordinary word elaboration and direct/indirect calls, rather than
an expression-body inline path. Supplies are constructed in written order before
selection; annotations are checked, and ordinary callable handler values are accepted.
Measured on the two-handler fixture: functions 2→4, call sites 1→3, views 0→0,
assembled bytes 222→290 (+68, about 31%). Both versions return 42 in all four modes.
This is a code-size regression; timing/preparation costs are unmeasured. Evidence:
`research/experiments/frontend-syntax/word-bindings/{README.md,size.lua,size.log}`.
Canonical AST/parser changes add SumSchema and desugar callable entries to Lambda;
rest syntax is shared, but pack/spread elaboration still rejects explicitly. ABC,
continuations and allocation machinery are unchanged. Documentation: `docs/word-bindings.md`.
Focused checks after the cutover: word bindings 106 checks/84 four-mode executions;
compiler 280; lambdas 269/80 executions; source demands 52. Integrated `validate-slet`
passed, including 112 production executions, 2 static-demand diagnostics, 12 portable-C
cases, 43 symmetric executions and 48 lifetime cases. Log:
`research/experiments/frontend-syntax/word-bindings/validation.log`.
No clean/sanitizer/performance qualification is claimed.
**Remaining grammar gate:** named keyed-requirement declarations share the elaborator,
but no keyed `do` constructor spelling has been approved/added. Do not claim every
named declaration is literal syntax sugar until that gap is resolved. Legacy dynamic
open-word/runtime-keyed-supply paths remain D03, not new COW container support.

**Vocabulary parameters — approved, deliberately deferred until binding-spread work.** `do(ctx...)` and named block
parameters use one ordinary parameter followed by implicit `let ...ctx`; prefix
`...args` remains rest. Block bodies only, at most one marked parameter, existing
spread-shadow/snapshot/definition-alias/capture rules, no dynamic discovery or
receiver detachment. See `docs/word-bindings.md`. Current `SpreadStmt` elaboration
still rejects; the user chose to continue the existing work and return to this feature
when its foundation is reached. Implement shared binding-spread rather than a
callback-specific expansion path. Module-valued parameter transport must not be
invented implicitly.

Dependency: audit baseline; S/O as needed for individual paths.

- [ ] **F01** Produce a current syntax-to-parser/checker/IR/lowering/execution matrix.
  Catalogue all `semantic-todo`/lowering rejections and uncovered promised paths;
  separate accepted-but-legacy behavior from intended semantics. Include tests per row.
- [ ] **F02** Complete nested keyed static partial supply and other confirmed typed
  callable gaps; preserve already-working full keyed calls, methods and nested recursion.
- [ ] **F03** Complete owned/escaping callable captures and retained method receivers
  under O/S contracts; remove profile-based retention prohibitions only when proved safe.
- [ ] **F04** Specify/implement address-bearing sums, recursive exported layouts,
  borrowed-input export aliases and remaining closed public/foreign ABI checks.
  Preserve current recursive-type/export support rather than rebuilding it wholesale.
- [ ] **F05** Close remaining result/unit/lambda/generic-demand paths from F01, including
  progressive defaults and recursive contracts; existing block/vector lambdas stay tested.
  Concrete gap reproduced by the arity probe: `take((pair()))` rejects `result-arity`
  for a two-result pair instead of applying the target scalar adjustment. Trace
  grouping erasure in `parse.lua` and scalar call construction in `semantic.lua`;
  fix through the ordinary result contract, independently of adopting bare syntax.
- [ ] **F06** Complete module/program/library integration and foreign/defer effect and
  lifetime boundaries beyond current tested paths; finalize `docs/stdlib.md` resource,
  byte/stream and program signatures instead of relying on a nonexistent library README.
  Foreign static execution stays forbidden
  unless a separately approved policy changes it.
- [ ] **F07** Complete diagnostic/source-position/interruption coverage and end-to-end
  acceptance for F02–F06; narrow unsupported diagnostics instead of claiming all frontend done.

## E — Shared runtime primitive and suspension engineering

Authority: `docs/runtime-primitives.md`. Concrete algorithms approved; not implemented.
This coordinates O/C/D/T/P/W, not a new parallel runtime. Locked channel rings and
worker deques, select arbitration, task-owned spill/wait records, intrusive release
and immutable per-realization publication are selected—not open-ended alternatives.

- [ ] **E01** Implement the catalog contract in `gen/runtime_primitives.lua` and its
  generated frontend/C metadata (runtime-interfaces §1); bind to source lowering, verifier,
  shared computation and emitter consumers: cell/holding layouts, effects, clobbers,
  failure and completion/suspension. Specify required encoding changes explicitly.
- [ ] **E02** Implement `src/owner.h/.c` and `type_ops.h` per runtime-interfaces §3;
  bind owner/TypeOps layouts and semantic holding transfers, plain versus
  atomic implementations and iterative release operations across execution backends.
- [ ] **E03** Change `vm_internal.h`, `execution_emit.h`, `vm.c`, residualizer and
  both emitter/generator bindings per runtime-interfaces §§2,5,8; bind task context,
  allocator-generated spill/resume entries, result
  transport and PARK disposition to current entry/return/error ABIs. No hidden C cells,
  extra allocator or suspended worker-host-stack dependency.
- [ ] **E04** Implement/check runtime-interfaces §§6–7 memory orders and lock hierarchy
  in task/channel/select/group/scheduler code, implementing the approved
  PARKING/PARKED/NOTIFIED handshake, channel/select registration, group cancellation,
  timer completion and runnable publication. Test adversarial interleavings at integration.
- [ ] **E05** Replace native whole-image lazy reprotection with private per-realization
  publication and atomic entry slots; retain code until image destruction. Audit all
  embedded task/worker-local addresses and account for code-allocation fragmentation.
- [ ] **E06** Integrate concrete data structures through the linked O/C/T/P items in
  substantial slices, then W AOT. Measure fast completion versus parking, copy/count
  traffic, contention and retained memory; do not substitute a helper facade for semantics.

## O — Collector-free proofs, placement and reclamation

Authority: `docs/owners-references-ids.md`; corresponds to O1–O3 in frontend plan.

- [ ] **O01** Freeze adversarial proof tests: self/interior edges, closure cycles,
  stored borrows, branch joins, COW self-insertion and hidden module access.
- [ ] **O02** Specify actual-root provenance, independent borrow extents and strict
  owning-edge inference; recursive fixed points, polymorphism and separate-compilation
  summaries must preserve bounds without runtime cycle detection.
- [ ] **O03** Implement these proofs in the existing source place/state model and
  reject unprovable cycles. No second native value IR or placement reconstruction.
- [ ] **O04** Specify owner/reference/slice/environment layouts and escape placement;
  allocate escaping roots separately from activations before publishing any address.
- [ ] **O05** Implement retain/release obligations, borrow elision and alias-aware moves
  through assignments, calls, returns, sums, containers and erased callables.
- [ ] **O06** Specify overflow, allocation failure, partial construction, abort/teardown
  and FFI retention/handle policies; no wrapping counts or implicit unsafe pointer proof.
- [ ] **O07** Implement generated allocation-free iterative release and failure cleanup;
  no host-recursive destruction, user finalizers, tracing or collector fallback.
- [ ] **O08** Validate long graphs, rejected cycles, independent borrows, captures,
  exact lifetimes and all execution bindings; measure count traffic and owner retention.

## C — Stores, ids and immutable/COW values

Dependency: O proofs/layouts/release; source transport from S where staged.

- [ ] **C01** Implement segmented stores with slot occupancy/extent/generation validation,
  independent copies and stable growth; specify generation wrap and id limitations.
- [ ] **C02** Implement temporary slot borrows and prove removal/replacement safety;
  test holes, reuse, copied internal ids and allocation-free try operations.
- [ ] **C03** Implement COW lists and copy-in/out APIs; settle reentrant mutation rules
  and prevent escaped element references. Nontransferable contents retain owner bounds.
- [ ] **C04** Implement COW byte strings, immortal literals, packed offset/length,
  shared substrings, compact and immutable snapshot views; replace old slice assumptions.
- [ ] **C05** Implement immutable construction DAGs, boxes and freeze via copy/proven
  move; retain incoming values before uniqueness checks and account for surviving aliases.
- [ ] **C06** Specify atomic-from-creation shareable counts and uniqueness/borrow protocol;
  implement basic sharing without live counter-mode promotion. Concurrency testing in P.
- [ ] **C07** Validate nested self-insertion, detach/snapshot semantics, substring retention,
  freeze with live aliases, failure cleanup and memory/copy/count costs.

## D — Dynamic execution and value tables

Dependency: O/C and explicit representation/encoding approval; not archived profile 5.

- [ ] **D01** Approve dynamic cell/box/type-witness ABI and bytecode/profile revision
  decisions. Do not reinterpret old tracing metadata or assume new instructions unnecessary.
- [ ] **D02** Implement transferable-only `any`, exact numeric bits/conversions and
  immutable boxing through the single shared scalar computation and all execution bindings.
- [ ] **D03** Replace legacy open-word IR producers/consumers/tests (`WordGet/Set/Method`,
  mutable-terminal/runtime-supply assumptions) with the approved value-table contract.
  Preserve any still-required callable feature only through an explicitly approved design.
- [ ] **D04** Implement COW tables, dense integer part, kinds, named layout tokens,
  ordered iteration, method receiver borrows and checked access/conversion behavior.
- [ ] **D05** Keep shape/kind facts distinct and tokens non-owning; validate mutations,
  copies, unknown types, errors, selected-first banks and untouched live values.
- [ ] **D06** Enable executable dynamic lowering only when the producer/VM/ABI chain is
  coherent; replace the blanket rejection with accurate per-capability support checks.

- [ ] **D07** Remove Whippet completely from the active project after replacing
  required ownership/effect responsibilities: delete `vendor/whippet` and
  `src/whippet_types.h`; remove all remaining dependency/build/link integration,
  tracing descriptors/adapters, GC root registration and collection safepoints.
  Retire or replace obsolete GC tests/examples and active setup/documentation claims.
  Inspect `src/dynamic.c/.h`, `src/any_repr.h`, Makefile, CI and dependency metadata
  for actual references; preserve unrelated scalar/value contracts, not dead GC code.
  No dormant fallback remains. Historical archives retain evidence only and must
  not enter the active build. Completion requires an active-dependency/reference
  audit and integrated validation of replacement lifetime/error/foreign boundaries.
  **Whippet absence is a release criterion, not optional cleanup.**

## L — Text and library contracts

Dependency: C strings/lists and S static demands; X packs where used by formatting.

- [ ] **L01** Complete `docs/stdlib.md` API gates: exact module exports/receiver forms,
  formatting indices/type rules, parse grammar, pattern position-capture/empty-match
  rules, callback mutation, table count/member collisions and insertion history.
  Preserve byte/ASCII semantics; implementation filenames do not authorize new public
  module names. F06 owns resource/program signatures and task details stay in T.
- [ ] **L02** Implement concatenation/compound assignment and text operations with
  correct left-to-right effects; measure rather than assume one-allocation chains.
- [ ] **L03** Implement format parsing/checking and runtime-format errors; static
  specialization must use normal VM-backed computation, not compiler magic or Lua evaluation.
- [ ] **L04** Implement specified Lua-style byte patterns and literal specialization;
  validate classes, captures, balanced/frontier patterns, malformed input and resource use.
- [ ] **L05** Validate standard module APIs and library diagnostics end to end; report
  allocation, retained buffers, count traffic and code growth.

## U — Capabilities and one `.let` language

Dependency: O/D semantics and F/S API integration; migration must preserve honest support.

- [ ] **U01** Specify requirement syntax/summary encoding and infer independent type,
  allocation, counting, suspension, transferability, mutable-world and foreign facts.
- [ ] **U02** Replace compiler semantic profile dispatch and old GC/borrow split with
  one language; remove obsolete restrictions only with their replacement proofs.
- [ ] **U03** Make `.let` the only extension; remove `.slet` discovery/fallback, dual
  ambiguity and directional-import rules. Diagnose obsolete extension, no alias.
- [ ] **U04** Migrate active examples/tests, APIs, CLI/build scripts, editor integration
  where present and runnable docs together. Leave archive paths/evidence intact.
- [ ] **U05** Validate mixed typed/dynamic modules, imports and static/runtime policies;
  audit surviving SLet dispatch/adapters and capability failures in all four modes.

## T — Task language, lifetimes and suspension

Authority: `docs/tasks.md`; depends on O/C/U contracts. No task runtime currently exists.

- [ ] **T01** Implement group-bound capability summaries separate from unrestricted
  transferability; reject `any`/frozen erasure and child capabilities in ancestor queues
  or longer-lived results, including wrappers and closures.
- [ ] **T02** Implement transitive mutable-world read/write exclusion and foreign
  concurrent/blocking/affinity effects; allocation-free must not imply no suspension.
- [ ] **T03** Approve complete parking/resumption ABI and task stack/capacity policy for
  interpreted/threaded/native eager/lazy modes, without worker-host-stack dependence.
- [ ] **T04** Implement explicit continuation transport and worker migration in those
  bindings; preserve original errors/PCs, stack limits, live values and frame semantics.
- [ ] **T05** Implement group/spawn/repeated-join semantics and retained result copies;
  group teardown joins unobserved children and releases structurally owned records.
- [ ] **T06** Implement mutex-protected ring-buffer/rendezvous channels with intrusive
  task-owned FIFO wait nodes, synchronized commit FIFO, close/drain
  and scoped-capability payload rules; include failed send/copy cleanup.
- [ ] **T07** Implement scoped select using select-arbitration-before-channel lock order,
  task-owned registrations, source-order evaluation, exactly-once commit,
  no self-rendezvous, loser deregistration and selecting-task handlers; specify timer limits.
- [ ] **T08** Implement cancellation/creation synchronization and descendant inheritance,
  new closed channels, cooperative completion, yield and ancestor-channel limitations.
- [ ] **T09** Validate lifetimes, effects, protocols and all four execution bindings;
  do not promise forced completion, starvation freedom or blanket allocation-free messaging.

## P — Pthread scheduler and concurrent runtime

Dependency: T03 and C06 protocol designs; implementation proceeds with T operations.

- [ ] **P01** Specify narrow pthread lifecycle/synchronization wrapper, partial-start
  failure, shutdown and lost-wakeup-safe idle protocol; no general host scheduler facade.
- [ ] **P02** Implement mutex-protected work-stealing deques, parking/wakeup and a
  mutex-protected monotonic timer heap; generation/condition-variable idle protocol;
  retain explicit yield and document non-yielding-worker starvation limits.
- [ ] **P03** Replace lazy RW/RX mutation during execution with immutable published code,
  synchronized version creation and atomic entry indirection. Audit observing sites,
  image/module lifetime and memory-order/reclamation protocols end to end.
- [ ] **P04** Implement safe cross-worker last release and sharing publication;
  initial allocator binding uses thread-safe platform free on the releasing worker,
  not worker caches/remote-free infrastructure (runtime-interfaces §3);
  test atomic counts, borrowed readers and COW uniqueness under races.
- [ ] **P05** Specify/implement blocking/affine foreign integration, recoverable failure,
  program-abort reporting, coordinated worker shutdown and embedding behavior.
- [ ] **P06** Build controlled clock/seed/event tests and race/lifecycle stress coverage;
  single worker plus seed alone is not deterministic real-time/I/O execution.
- [ ] **P07** Measure scheduling/communication contention, atomic/copy costs, queues,
  retained join results, stacks and code; qualify regressions before performance claims.

## W — Task AOT and Emscripten deployment

Dependency: T/P semantics and explicit portable-C scope/ABI approval.

- [ ] **W01** Inventory current C subset versus task/library needs; specify missing
  operations and explicit suspension/resumption/runtime linkage without a second evaluator.
- [ ] **W02** Implement task-capable AOT C and native-host differential tests; current
  direct-call scalar C emitter is not task-capable and Emscripten does not supply continuations.
- [ ] **W03** Build generated C plus runtime with Emscripten pthreads; document application-
  owned flags, worker pools, shared-memory/isolation hosting and JS integration.
- [ ] **W04** Validate off-main-thread scheduler startup, parking, channels, release,
  foreign/proxying restrictions and shutdown in a concrete browser configuration.
  Until then browser support remains unvalidated. No direct JS-worker backend/fallback.

## X — Static spread, packs and import sugar

**Active syntax batch — Owner: primary coding agent. State: partial; entry-policy gate resolved.**
Coordinate X01–X05 syntax, Q05/Q09/Q10 and F05 grouping in one AST/parser/elaboration
cutover. Authoritative schema: `frontend/ast.asdl`; regenerate `let/schema/ast.lua`.
Touch lexer/parser, structural/scoping consumers, semantic result adjustment and
callable export/entry discovery, active fixtures/examples/source generators, tests
and syntax/API support notes. Preserve grouping explicitly; ordinary Lambda/Apply
nodes own block/literal sugar. Add context-restricted spread/rest forms; unfinished
pack/name-expansion paths diagnose explicitly, without a runtime pack or open-word
fallback. Remove arrow tokens/branches and erased-group assumptions. Archives remain
unchanged. Unit completion, receiver/operator resolution, full generic specialization
and ownership are separate semantic obligations, not automatically completed here.
Approved refinement: unify lambdas as `do(parameters)` with optional result
annotations and expression/block bodies; remove pipe lambdas and pipe-specific
annotation parsing, not just arrows. Existing captures/ownership and VM ABI remain.
Acceptance: AST boundaries, literal postfix precedence, trailing-block adjustment,
block nonexecution/grouping, scalar versus vector results, valid callable entries,
spread/rest placement and unsupported diagnostics, active-source migration and
integrated frontend execution. Unified do-lambda replacement is implemented. User
approved preserving current entry behavior: removed the new u32-only main restriction
and its AST flag; typed callable/noncallable export checks remain. Syntax suite now
passes 106 checks/48 VM executions, including named and anonymous i64 entries and
unit entry discovery. Updated obsolete production-validator rejections to positive
static-partial/computed-supply cases, retaining genuine runtime-supply/missing-policy
rejections; validator passes 112 executions and two diagnostics. Other frontend
constituents passed in the preceding aggregate run; the complete make target was
not rerun after the final validator publishing correction. Evidence:
`research/experiments/frontend-syntax/do-lambdas/README.md`. No performance, full
S-source acceptance or complete Q10/X elaboration claim is made.

Authority: `docs/spread.md`; dependency: S/F specialization interfaces, O/U bounds.
Can start before task runtime; must preserve group bounds when those become available.

- [ ] **X01** Approve lexer/parser/schema/elaboration interfaces and unresolved generic
  forwarding details; distinguish `...`, `..`, `.` and numeric literal edges.
- [ ] **X02** Implement one-time ordered nonrecursive expansion of result vectors/fixed
  arrays, including return/binding lists; preserve unmarked final-result adjustment.
- [ ] **X03** Implement final ordered static-shape rest packs, static index/length and
  saturation rules without runtime pack objects or first-class erasure. Integrate
  `logged(t: type, f: t, ...args)` through existing explicit type demands: type-only
  partial supply leaves f outstanding; known f specializes directly, runtime f uses
  its fixed-signature indirect ABI. No implicit generics or special treatment of any.
- [ ] **X04** Implement keyed record expansion, explicit override, overlap/unknown-key
  checks, readonly/static protections and effects of overridden contributions.
- [ ] **X05** Implement module/record/sum name binding, no-shadow and file-scope visibility
  rules; add `use ...module` sugar without duplicate initialization or automatic re-export.
- [ ] **X06** Validate diagnostics, copies/owner bounds, lexical resolution, sugar
  equivalence and all applicable modes; measure specialization/copy/retention growth.
  Include explicit-requirement adapters with heterogeneous runtime packs and exact
  unit/single/multiple results; defer-based post-call work must preserve live results
  and holdings across clobbers/allocation/suspension where supported. Test type-only
  partial supply, typed indirect f, signature failures, effects/abort order and
  scoped captures. This is source/compiler acceptance, not a new runtime adapter engine.

## Q — Schema operators and trailing blocks

Authority: `docs/operators-and-blocks.md`; approved direction, not implemented.
Dependency: F/S method/call elaboration; O/U ownership/effects. Dynamic slice also
requires D descriptor/box contracts. Initial scope is static operators and block sugar.

- [ ] **Q01** Specify schema-interface authority through structural conversions,
  generics, joins and erasure using the ordinary method model, not accidental nominal
  typing. Settle comparison result/unordered and reverse comparison dispatch contracts.
- [ ] **Q02** Approve protocol signature checking and parser/elaboration interfaces;
  one signature per name, no conversion/candidate search or runtime applicability probes.
- [ ] **Q03** Implement static primitive/left/right dispatch, unary and comparison
  protocols with source-order operands and normal effects. An ill-typed selected
  method errors rather than falling back. Preserve primitive/boolean contracts.
  Arithmetic/bitwise/concatenation add lexical op_name(left,right) only after BOTH
  member routes are absent and both operand interfaces are closed. Unary negation/
  bitwise-not similarly allow lexical fallback. No lexical _right search, automatic
  ref or type-candidate search. Keep generic lookup definition-scoped and report the
  failing specialization; table/any never try runtime lexical hooks. Comparison and
  index/call lexical-extension details remain explicit gates, not implied by names.
  Test right-member priority over lexical functions, primitive immunity, import-spread
  opt-in/collisions, malformed selected members, copy/ref and once-only effect order.
- [ ] **Q04** Implement index read/set and call protocols, value-index ref rejection,
  writable receiver checks and single-evaluation compound stores through ordinary IR.
- [ ] **Q05** Implement self-delimiting one-argument application for literal-led
  arguments (integer/float/byte/string/long-string/bool plus member/index/explicit-call
  postfix chain) and block-only `f do ... end`, plus
  trailing blocks appended to explicit argument lists before result adjustment.
  Preserve contextual literal/lambda typing, captures and local return. No arity lookup,
  newline rule, general `f x`, multi-literal supply or array/braces reinterpretation.
  Unit fallthrough is a separate approved semantic change in Q08. Touch `parse.lua`,
  AST/semantic consumers and focused
  literal/block fixtures; minus remains an operator, so negative arguments use `f(-1)`.
- [ ] **Q06** Validate equal-layout schema authority, dispatch/effect/place ordering,
  explicit-lambda equivalence, captures, spread interaction and applicable execution
  modes at an integrated boundary; measure costs rather than promise free inlining.
- [ ] **Q07** Separately specify and implement `any` operator dispatch preserving
  schema identity and frozen/value semantics through descriptor-based ordinary calls;
  no per-record method table, table metatables or second dynamic scalar engine.
- [ ] **Q08** Implement unit fallthrough uniformly for named words, methods and lambdas:
  annotations/context or unconstrained acyclic no-value-return inference establish unit.
  Before recursive `any` defaults, infer unit for unconstrained members of resolved SCCs
  whose members all have block bodies, only own bare returns/fallthrough, discarded
  intra-SCC calls and no non-unit explicit/expected/export contract. Exclude nested
  callable returns; no result-type fixpoint. Valued returns remain outside this shortcut.
  Established contracts stay authoritative. Value-returning/mixed paths still
  reject. Lower implicit completion through ordinary bare-return cleanup, not a last-
  expression rule. Touch `frontend/let/semantic.lua` result inference/body completion,
  `check.lua` flow/result checks and relevant IR/lowering consumers; inspect `Function:build`,
  method/lambda builders and defer scopes together. Add compiler/lambda/operator tests
  for discarded final results, inner-block continuation, defer order, ownership cleanup
  and task-scope completion as those subsystems land. Current support must be checked
  per path; documentation approval is not a completed implementation.

- [ ] **Q09** Replace pipe/arrow lambdas with unified anonymous definitions:
  `do(parameters): result = expression` or `do(parameters): result ... end`;
  result annotations are optional and nullary blocks may omit parentheses. Expression
  lambdas require parentheses, including `do() = expression`; bare `do =` rejects.
  Share named parameter grouping/annotations; explicit lambda results must agree with
  context. `|` is infix-only; remove closing-pipe state and both old lambda spellings.
  Neither arrows nor pipes have compatibility aliases. Preserve `--` comments and
  archived evidence. Active parser/schema/semantic/test/example migration is implemented;
  current focused evidence: syntax batch 98 checks/40 VM executions, parser 232,
  compiler 276, lambda 269/80 VM executions and source demands 52. Wider boundary
  validation and final review remain before closure.

- [ ] **Q10** Implement standalone block-lambda expressions: `let f = do ... end`
  constructs a callable, not an eagerly executed block. An ungrouped block-lambda
  atom takes no postfix/self-delimited suffix: immediate invocation/access requires
  grouping; test the post-end newline hazard. Parameterized blocks use
  `do(p) ... end`; expression lambdas use `do(p) = expression`. A lambda's `=`
  permits ungrouped nesting (`do(x) = do(y) = x + y`). Named-definition direct `= do`
  remains an executed body and rejects a following parameter list; returning a lambda
  there requires grouping (`let make(x: u32) = (do() = x)`). Unify trailing-block desugaring with ordinary block-lambda
  construction. Touch parser primary/body/lambda paths, AST/semantic capture and result
  handling, compiler callable-binding exports and main discovery; see implementation map.
  Preserve local recursion, unit/value returns, capture/group bounds and main():u32.
  Validate nonexecution at binding, grouping, normal invocation, export/entry rejection
  and owned/borrowed captures. Coordinate with S06/F04/F06: current literal-only module
  initialization/direct-word export paths are insufficient. No implicit exit-code coercion.

- [ ] **Q11** Implement lexical receiver-call sugar per `docs/application-sugar.md`:
  existing member wins; only a closed interface lacking that member falls back to
  lexical `name(receiver,args)`. Bad signatures/noncallable fields never fall back.
  Table/any calls stay dynamic member calls; module qualification stays namespace lookup.
  Generic resolution is per specialization in definition-site lexical scope, with
  instantiation diagnostics. Preserve ordinary copy/ref semantics, including valid
  copy-writing transforms; no implicit ref, write-back, overload search, extension
  registry or lexical bound closure from an uninvoked field. Touch `semantic.lua`
  call/member resolution, `resolve.lua`, `schema.lua`, `check.lua` and ordinary IR
  consumers; add `frontend/tests/receiver_calls.lua`. Test builtin remove/has collisions,
  import-spread opt-in, formatting through lexical fmt, member priority, typed failure,
  dynamic no-fallback and exactly-once receiver evaluation. Q05 parses literal chains;
  Q11 resolves their calls without backend-specific operations.

## Z — Deferred or excluded: do not silently turn into active implementation

These are not completion obligations for the current slices. Reopen only by explicit
scope/design decision, then assign concrete tasks/dependencies above.

- Lazy bytecode peer target: proposed, distinct from eager threaded tape; not scheduled.
- Hybrid eager C-top cache and experimental physical return layout: parked/unadopted.
- Blanket dead-slot zeroing: measured and rejected, not an unfinished optimization.
- New pressure-driven source reordering: separate approval; existing Ershov remains.
- Runtime list/table call spread, spread into `..`, erased variadic ABIs (literal-do rest syntax is accepted, elaboration still pending):
  outside initial X scope. No destructuring or first-class packs.
- Pipeline `.par()` semantics/integration: separate design, not implied by task workers.
- Direct JS-worker backend/general host scheduler abstraction: out of scope; pthreads
  and Emscripten adaptation are the approved boundary.
- Tracing GC, cycle-detector fallback, public shared-mutable-reference concurrency,
  `.slet` compatibility alias and restoring the archived engine: not target features.

## Syntax experiment (not target syntax)

- [x] **XP01** Build isolated fixed-arity bare-application probe with an explicit
  signature environment and exact desugaring cases. Evidence:
  `research/experiments/arity-application/README.md` and `evidence/results.log`:
  40 parser/ambiguity checks, 20 production VM executions of supported desugared
  scalar cases; one frontend scalar-adjustment gap explicitly recorded, not passed.
  No production parser/runtime changes. Builder examples are parsing-only fixtures.
- [x] **XP02** Decision: arity-driven application is **not adopted**. User approved
  self-delimiting atomic-literal/block sugar instead; see Q05 and syntax.md §12.
  Preserve probe evidence; do not integrate its signature-aware parser. Receiver-method
  spread and general command syntax remain unapproved. Unit fallthrough was subsequently
  approved independently and is tracked in Q08.

## Next executable planning actions

- [ ] **N01** Review this audited inventory with the user; prioritize a concrete S01/S02
  or A01 slice and obtain implementation-interface approval before editing code.
- [ ] **N02** Complete F01 so remaining partially implemented source features get exact
  acceptance tests rather than blanket historical “missing feature” labels.
- [ ] **N03** For the chosen slice record owner/state, files, dependencies, expected
  removals, architectural acceptance and measurements here; update evidence on completion.
