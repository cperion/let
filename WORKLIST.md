# Let project worklist

**Live project-management checklist.** This is the status authority for remaining
work; [REFACTOR.md](REFACTOR.md) retains architectural rationale and chronological
implementation evidence. Feature specs define semantics, not completion. Historical
checkboxes and O1–O9 packages are supporting records, not competing live task lists.

## Latest ownership decision — explicit Rc, copy retains

**Owner: coordinator. State: partial delivery; approved initial explicit-Rc slice
implemented and integration-tested (O01–O08/E01/E02); sanitizer qualification blocked.** The user explicitly chose `Rc(T)` ownership,
strictly borrowed `Ref(T)` and **copy retains**, to make ownership developer-visible
and typechecked and remove compiler inference complexity. No implicit promotion,
owner-capability recovery or hidden acquisition to rescue invalid borrows remains
in the target. Rc copies share the allocation; drops release. Proven moves may
eliminate count pairs without changing semantics. Borrow and actual strong-edge
cycle checks remain; the C owner core and six runtime bindings survive.

The interrupted implicit implementation is preserved separately at `4a9da5db`.
Its partial root/result binding is superseded, not an unfinished task to continue.
Older E/O paragraphs below record chronological evidence, not current directives to
finish automatic counted placement. No O/E item is closed by this decision.

**Current scope/files:** the initial binding (now `docs/owners-references-ids.md`
§2.2 and `docs/runtime-interfaces.md` §3) spans `frontend/ir.asdl`, generated
schema, `frontend/let/{schema,semantic,ir,check,analysis,access,ownership,program,
layout,placement,abc}.lua`, frontend ownership/borrow and affected feature tests,
`tools/validate_source_owners.c`, and narrow optimizer-boundary corrections in
`src/optimize.c` / `tools/validate_optimizer_isa.lua`. Documentation and qualification
evidence are recorded below. The implementation map binds these responsibilities.
Remove the implicit owner event channel, counted-selection solver, capability/
preservation policy, reuse promotion and inferred resource ABI; preserve borrow,
readonly/effect/callable and SCC algorithms with real remaining consumers.

**Approved dependencies:** the archived source-lifetime proposal's section 8 settled `Rc(value)`, `r.borrow()`, no
borrow-carrying payloads initially, one owner-address handle and caller-owned typed
owning-value slots for failure-safe private calls. Copy-retains is settled and must
not be reopened. Producers and consumers have been cut over together; outstanding
qualification and the next action are recorded below, not a request to reapprove §8.
Public/foreign, erasure, containers/tasks and `.let` migration remain their existing
separate gates, not silently enabled by a type name. No new sidecar or parallel
implementation is authorized.

**Prior specification evidence:** the original specification/removal-plan change
was not new runtime support.
Documentation diffs reviewed; `git diff --check` passed and 88 local Markdown file
targets across the ten changed documents resolved. Runtime tests were not rerun
for this documentation-only change. Explicit-Rc source acceptance and compiler/
code-size/count/storage/performance measurements remain outstanding. Preserve
existing raw experiments and historical `.slet` filenames.

### Historical explicit-Rc interruption: performance investigation

**Historical checkpoint: partial, unqualified; implementation was paused for
performance design review (O03–O08/E01/E02).** The working cutover changes
`frontend/ir.asdl`, generated `schema/ir.lua`, frontend schema/semantic/IR,
access/ownership/program/check/analysis, layout/placement/ABC and
`tests/{schemas,program,source_owners}.lua`. It removes the implicit solver and
adds initial declared-Rc lowering, but is not a completed or validated replacement.
The small raw/optimized Rc probe ran in four modes; schema checks and the program
boundary test (37 checks / 2 VM executions) passed. Broader test migration and
source-owner qualification remain incomplete.

The user stopped the broad run after 51.4 CPU seconds in the frontend and a long
optimizer run. Investigation-only, time-bounded probes then isolated two costs:
full-caller-state query proliferation in `access.lua` (3,258 contexts / 6,257
iterations in a profiled fixture compile), and path expansion plus linear DAG
lookups in the unchanged `src/optimize.c`. A 427-byte, Rc-free optimizer
reproduction exceeds a three-second limit; an isolated four-function frontend
loop produces 460 contexts and retains 44.5 MiB of Lua heap after collection.
These are diagnostic measurements, not acceptance or speedup claims.

**Next action at that checkpoint:** discuss a sound relevant-input/query-join design for borrowed and
strong-edge checking, plus bounded optimizer speculation and lookup costs, before
implementing fixes. Do not increase the full-suite timeout or disable checking/
optimization to hide the cost. No production code changed during this
investigation and no O/E deliverable closed. Logs, frozen fixture, bounded probes
and exact findings are in
[`explicit-rc-performance-investigation`](research/experiments/runtime-owners/explicit-rc-performance-investigation/README.md).

### Current explicit-Rc cutover and qualification

**Owner: coordinator; state: implemented initial slice, partially qualified;
O01–O08/E01/E02 remain open.** The requested architectural cut is implemented:
no whole-caller-state query identities, before/after publication, contents-version/
carrier dependency graph, loan-demand/capability solver, implicit preservation,
root binding or inferred reference-resource ABI remains. The unused `Lifetime`
schema is removed. Borrow checking uses the original IR CFG, sparse protection/
permission/tag/callable facts, joined call-site bindings and argument-reachable
contents. Private effects do not escape a function's contract. Scalar-only,
global-independent boundaries are checked once, including their private allocations.
Actual invocation environments and concrete strong-edge checks remain.

Declared Rc types drive one-cell handles, semantic retain-on-copy, cleanup-visible
private argument/result slots and actual-field/active-tag drops. Nonowning code
keeps ordinary transport; source diagnostics survive physical cloning. Named type
cells accompany the checked program so recursive ABI gates inspect real definitions.
The native fixture no longer expects an extra inferred preservation field.

The optimizer now enforces its existing frame-materialization boundary at nested
call/tail inlining too; already-unsupported multi-path non-call effects decline
before path expansion. No Rc-specific bypass or disabled optimization was added.
The unchanged 427-byte reproduction completes in 0.000791 CPU seconds under its
original three-second bound. Generic non-Rc regressions cover both corrections.

**Actual checks:** `make validate-source-owners` passes 1,718 checks / 560 VM
executions and 2,560,862 native checks: raw/optimized, all four modes, both lifecycle
banks, exact count/peak-owner measurements, every allocation/acquire failure,
partial construction, replacement, trap/stack/publication failure and iterative
100,001-object generated-C drains outside VM TLS. `make validate-slet` passes the
complete frontend target, including 172 borrow/effect checks / 120 executions,
55 ownership checks (including resolved named Rc payloads and unique allocation
identities), staging, source/optimizer and mirrored portable-C tests.
`make validate-optimizer-isa` passes 58 mirrored modules / 340 execution pairs;
C-entry, owner-core and collector-free targets pass independently.

**Measured costs:** the unchanged 79-function fixture compiles in 2.544576 CPU
seconds (access: 0.958663), with 281 bindings / 561 iterations and 9.189 MiB Lua heap
after collection. Raw/optimized images are 63,794 / 63,776 bytes. The expanded
fixture has 5,576 declared cleanup-frame bytes / 235 typed slots, largest frame
424 bytes; these are not peak stack measurements. Count traffic is not claimed
optimal: `variant_replace` has 47 holds and four allocations. The original profiling
conditions differ, so these are observations, not a controlled speedup claim.

**Remaining / next action:** focused ASan/UBSan/LSan compilation is blocked by
installed Clang 18 lacking the required `preserve_none` handler ABI. Do not disable
that ABI/check to get a pass; rerun the recorded script with a suitable compiler.
No top-level full `make validate`, clean-build, TSan, wasm/browser or general resource-
bound claim is made. Public/foreign/erased/owning-callable/task/container and `.let`
execution gates remain closed. Baseline copies retain; proven move elimination is
separate work, not a correctness dependency. No O/E box is closed here.

Evidence, commands, exact scope and logs:
[`explicit-rc-cutover`](research/experiments/runtime-owners/explicit-rc-cutover/README.md).
Production/document whitespace checks pass excluding the immutable diagnostic
`optimizer-trace.patch` context line; raw historical evidence was preserved.

## Guide and latest approved source conventions

`docs/designing-and-writing-let.md` is the design/style guide, not a claim of executable
coverage. It adopts PascalCase for all types/schemas, including built-ins and their
constructors, and snake_case for ordinary words, values, fields and alternatives.
Built-in bindings and canonical frontend descriptors now use capitalized names;
lowercase compatibility aliases are not retained. Case-sensitive binding lookup,
ABC encodings and C APIs are unchanged. Live-place context opening (X07) now executes within admitted typed contexts;
bounded `endall` closing sugar (Q12) is implemented and qualified. Updated tests replace
snapshot expectations; historical evidence remains unchanged. Module aggregate storage
and broader ownership/frozen-place qualification remain open.

Naming qualification: regenerated the canonical IR schema, migrated active frontend
consumers/tests/examples and source documentation, and added `tests/type_names.lua`
(44 checks/8 executions). It checks both constructor forms, removed lowercase
built-ins and binding-based grammar. Full validation passed; all 14 frontend examples
retain their pre-rename admission outcomes, including existing unsupported cases.
Evidence: `research/experiments/frontend-syntax/type-names/`. The naming pass did
not close S05/S06 or packed-float lowering; the subsequent higher-order correction
is recorded under S05 below.

## V — VM 3 isolated experiments

- [ ] **V01 — Copy the current VM into `next/` without changing semantics.**
  Owner: coding assistant (user assigned). State: partial (source copy complete;
  full-build qualification blocked by the installed toolchain). Dependency: fetched
  `master@origin` baseline `54b964dc5c40d5705b8686e4744a30d88271bac0`.
  Scope: independent regular-file copies of `src/`, `include/`, `gen/`, `schema/`,
  `tools/`, `frontend/`, `examples/`, `lab/`, `vendor/`, `Makefile`, `LICENSE` and
  `.gitignore`; add `next/README.md` and a source checksum manifest. Frontend and
  tooling are copied to preserve existing build/test consumers, not redesigned.
  Existing runtime/build paths remain unchanged; removal set: none. Exclude
  generated build output, VCS/agent state, research archives and upstream design
  experiments. Keep this root WORKLIST as the only live ledger.
  Outcome: 193 independent files match baseline bytes and `next/BASELINE.sha256`;
  no symlinks/shared source inodes. ISA metadata, execution-form checks and the
  copied collector-free audit pass. `next/build/` is ignored. The root dependency
  audit (`tools/validate_no_collector.lua`) now prunes `next/` to avoid treating
  experimental files/generated output and copied negative controls as production
  inputs; its run still fails on the fetched, unchanged
  `.ralphi/optimizer-residual-redesign/runs.jsonl` collector-reference text.
  `make -C next all` stops at the copied `gen/foreign.lua:9`: default LuaJIT rejects
  its bitwise `&` syntax. No generator/toolchain workaround was introduced; full
  runtime tests were not run. Evidence: `next/VALIDATION.log`.
  Next action: supply a compatible build toolchain, then finish isolated build and
  runtime qualification before V3 implementation. Integration boundary:
  `make -C next`; no root-build dependency, no VM 3 semantics or encoding change.

- [x] **V02 — Ground the experimental VM 3 topology in a design document.**
  Owner: coding assistant (user assigned). State: documented (design only;
  unresolved contracts remain proposals, not approved implementation).
  Dependency: V01 source copy exists; its toolchain blocker does not block design
  documentation. Scope: `next/DESIGN.md`, linked from `next/README.md`, and the V
  section in `docs/implementation-map.md`. Record unified A/scalar B, ring `(R,T)`,
  demand-only backing reads and no eager refill even on return. Distinguish agreed
  topology, original-sketch proposals, unresolved contracts and measured evidence;
  identify cutover/removal boundaries without authorizing implementation.
  Removal set: duplicated topology prose in `next/README.md`; no runtime removal.
  Outcome: `next/DESIGN.md` records exact ring transitions/addressing, the no-refill
  return rule, B routing proposal, call-layout gaps, current-backend distinctions,
  cutover responsibilities and architectural/performance validation criteria.
  Reviewed scope/formulas and diff; local link-target and whitespace checks pass.
  All 193 copied files still match `next/BASELINE.sha256`. No runtime tests run
  for this documentation-only change. Next action: discuss the explicit contract
  gates before selecting implementation. Integration boundary: documentation only,
  no new ABI or encoding assignment and no VM 3 executable-support claim.

- [x] **V03 — Compare ring-cache refill policies in an isolated model.**
  Owner: coding assistant (user assigned). State: completed (model evidence only).
  Dependency: V02 topology;
  user approved a model experiment, not a production policy change or native timer.
  Scope: `next/experiments/refill/{model.py,test_model.py,README.md}` plus reproducible
  raw results. Compare demand-only, eager after a completed depth-reducing operation,
  and return-only refill at N=8 on identical traces. Verify every transition against
  an uncached oracle; count demand/refill loads, spills, refill usefulness, occupancy
  and state transitions. Include recursion, deep expressions, locals, oscillation,
  pop/drop streams and seeded mixed traffic. No new module/continuation ABI.
  Removal set: none. No runtime/source-baseline changes. Outcome: nine tests pass,
  including all ring rotations/occupancies at N=1,2,3,4,8, refill accounting,
  poisoned inactive slots, capture/return ordering and seeded differential checks.
  Six N=8 traces (123,645 events each policy) match the oracle after every event;
  a fresh rerun produces byte-identical JSON/CSV. Evidence reuse rejects. All 193
  baseline checksums remain unchanged. Evidence:
  `next/experiments/refill/runs/n8-001/{results.json,summary.csv,run.log,tests-final.log,provenance.json,checks.log}`.
  Eager halves modeled loads for expression/local-read traces, but increases
  Fibonacci loads from 1,970 to 11,151 (return-only: 7,964), and oscillation loads
  from zero to 4,120. Actual entry-state counts are recorded; these are neither
  hardware cache misses nor speed measurements. README states workload/ABI limits.
  Next action: discuss results before any native-timing slice or policy change.
  Integration boundary: isolated Python model; the documented no-refill rule stays
  unchanged. Full runtime builds and native timing were not run.

- [x] **V04 — Measure refill policies in real register-specialized execution.**
  Owner: coding assistant (user assigned). State: completed (isolated interpreter
  experiment). Dependency: V03 model;
  user approved the runtime experiment. Scope: `next/experiments/refill-native/`
  generator, C oracle/driver, runner, README and exclusive raw evidence. Generate
  x86-64 handlers using eight physical ring registers and scalar B, separate policy
  entry points, real branches and explicit stack continuations. Private benchmark
  records/call layout do not assign a V3 public ABI. Validate per-event state in a
  separate checked build, inspect normal assembly, then pin/warm/alternate repeated
  timings for recursion, expressions, locals and oscillation. No timing counters
  or oracle callbacks in the timed interpreter. Removal set: none. No production
  or copied runtime changes. Outcome: six policy-placement orders each passed
  15,504 checked policy/case runs and 884,808 instruction-entry checks; all 72 ring
  states covered per policy. Timed object inspection found zero host calls and
  three outer returns. Each layout measured 18 balanced samples per policy/workload
  on pinned CPU 0; raw timings, quartiles, checksums, environment/flags, assembly
  inspection and hashed source snapshots are under
  `next/experiments/refill-native/runs/n8-001` through `n8-006`, with aggregate
  `runs/comparison.json`. Eager was 28–44% slower on Fibonacci across placements;
  return-only was 9–13% slower. Eager also lost on the other three tested workloads.
  Nonreturning controls expose substantial layout/noise sensitivity; no hardware
  branch/cache counters were collected, so no causal prediction claim is made.
  User confirmed **no eager refill, including on return**, after reviewing evidence;
  `next/DESIGN.md` links the experiment without changing public ABI/encoding gates.
  Final artifact/link/whitespace checks pass; archived source hashes match their
  run metadata and all 193 copied baseline files retain their original checksums.
  Next action: resume the V3 contract/implementation discussion with this policy
  fixed; no more measurements in this slice. Boundary: baseline-interpreter refill
  comparison only, not V3 JIT qualification or a current-V2 speedup claim.

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
| E/O | `src/execution_emit.h`, `vm_internal.h`, `vm.c`, `residualize.c`, shared generators, verifier, source lowering | `src/owner.h/.c` (standalone core), `frontend/let/ownership.lua`; runtime binding removed |
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

  **Approved consolidation slice — owner: coordinator; state: complete (docs only).** Removed
  `docs/{remaining-work,frontend-completion-plan,frontend-gap-analysis,four_lane_fork_v3,
  actual-binding-access-conformance,staging-session-implementation,source-lifetime-lowering,
  module-image-copy,word-bindings}.md` from the active documentation. Preserved verbatim
  snapshots and the old runtime-interface catalog under
  `research/archive/docs-before-rc-consolidation/`. Moved surviving semantics to
  `docs/{owners-references-ids,syntax,application-sugar,spread}.md`, private ABI/checker
  contracts to `runtime-interfaces.md`, session/image-copy APIs to
  `source-compilation-api.md`, and retired-path mappings to `implementation-map.md`.
  Reconciled `runtime-primitives.md`, `architecture.md`, `slet-subset.md`,
  `source-{partial-evaluation,virtual-contract}.md`, `tagged-value-lowering.md`,
  `spec.md`, `designing-and-writing-let.md`, navigation, `AGENTS.md`, root/frontend
  READMEs and affected links. Removed the retired runtime catalog/header/release-cache
  instructions. Corrected stale Rc, higher-order access, optimizer, spread and staging
  claims without opening any interface or changing runtime behavior.

  **Outcome:** nine active pages removed; surviving word, ownership and session
  contracts have explicit owners, not replacement planning pages. The old O1–O9 plan
  obligations map to existing S/O/C/D/U/T/P/W/L/X work; inference-selected placement
  is superseded, not transferred. Historical reports/raw experiments are unchanged.
  Archive mapping/evidence: `research/archive/docs-before-rc-consolidation/README.md`.
  Active docs reduced from 38 to 29 files and 13,702 to 10,095 lines. Verified 262
  local links/anchors across 35 active/navigation documents, byte-identical snapshots
  against `b7b74276`, manifest hashes and whitespace; see the archive's `validation.log`. Runtime task/context/container sections 2/4/6/7/8 are
  byte-identical; section 5 only clarifies that operation metadata is a target, not
  the retired owner catalog. No runtime tests were run for documentation-only edits.
  **Next:** broader A02/F01 code-to-spec completeness review remains open; this slice
  does not close A02 or change O/E delivery status.
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
  **WIP bounded pointer-free batch:** shared `layout.lua` ABI metadata, exact aggregate
  `snapshot.lua` transport, durable `Ir.Bytes`, and module-root/data descriptors added.
  Aggregate qualification: 337 checks / 326 executions, including exact mixed-width,
  negative-zero/NaN and tagged byte roundtrips, known-value specialization, imports,
  repeated compilation, failed initialization and zero-width indexed bounds. Address-
  bearing transport stays unsupported; packed float kind transitions are corrected below.
  User approved rejecting unsupported frame-root escapes in both profiles; compiler
  and lowering tests now reject returned refs/slices, nested borrows and frame-backed
  callable environments rather than assuming managed retention. Access suite: 101
  checks / 64 executions; compiler270, receiver407/384 and lambda269/80 pass.
  Actual-place facts are state-indexed across branches/loops, preserve saved snapshots,
  and substitute direct store/retention summaries. **New blocker:** higher-order
  invocation loses the supplied callable's retention bounds. The retained local store
  rejects through a direct call but is incorrectly accepted through `apply(saved)`.
  Full validation passes after admission updates; that does not establish proof
  completeness. This is implementation drift under the existing live-place/unified
  callable contracts, not a missing language-design approval. Agent: active correction
  in `semantic.lua`, `source_state.lua`, `access.lua` and focused tests. Remove eager
  instance-alias snapshots and raw cross-context capture operands; preserve ABI/VM
  execution and reject unsupported ownership. Conformance findings (former proposal
  status withdrawn): `research/archive/docs-before-rc-consolidation/docs/actual-binding-access-conformance.md`.
  Current checker contract: `docs/runtime-interfaces.md` §9.
  **Conformance checkpoint:** concrete view holdings now freeze value provenance
  or retain qualified live routes; raw slot IR replay removed, callable facts indexed
  by component. Finite binding nodes avoid growing nested holding trees at loop
  fixed points; the cyclic IR control qualifies metadata convergence only, not runtime
  environment storage reuse. Access120/80 includes concrete opaque-result rejection;
  full validation passes (`validation-conformance-3.log`). **Historical checkpoint: the reproducer
  still accepted `apply(saved)` at that revision.** Next at that checkpoint: formal
  callable/result identities, ordered composition and target/owner audit;
  do not substitute callback effects after unrelated stores or snapshot live captures.
  Evidence: `research/experiments/frontend-syntax/module-aggregate-access/`.
  **Resumed correction — Owner: primary coding agent. State: implemented/qualified
  for the reproduced defect; broader acceptance remains partial. User approved.**
  Replace the formal-call unknown-effect shortcut with context-qualified callable
  identities, ordered invocation/state relations and result linkage in the existing
  access summaries. Canonical metadata: `frontend/ir.asdl`; implementation:
  `frontend/let/access.lua`, checker/schema consumers as required; regressions:
  `frontend/tests/access_proofs.lua` and the retained-store reproducer. Remove lost
  callable-result facts and loan-as-address assumptions, not sugar or the ordinary
  call path. No source-body replay, scalar evaluator, runtime/ABC change or blanket
  higher-order rejection. Validate unsafe/safe callbacks, forwarding/results, live
  versus saved captures, order, recursion and opaque contracts; measure analysis
  preparation/storage before claiming closure. Preserve unrelated WIP.
  **Outcome:** `saved()` and `apply(saved)` both reject `borrow-store`; forwarding,
  returned callables, components, recursive wrappers and block sugar also reject the
  unsafe store while safe callbacks execute. Live captures read at each invocation;
  saved snapshots and callback results survive interleaved stores. Replaced unordered
  transfer-only composition/opaque formal-call handling with provenance/state relations
  and a finite query worklist; callable result facts are preserved. Physical targets
  are Borrow.Target nodes, distinct from loan Sources; uncontracted opaque supplied
  borrows and unknown projected results reject. Access176/112, aggregate438/422,
  receiver407/384, compiler270, lambda269/80 and full validation pass. Evidence:
  `research/experiments/frontend-syntax/module-aggregate-access/ordered-composition/`.
  Cost regression on the 12-wrapper microfixture: seven-run median analysis CPU
  4.342→11.681ms, sampled peak Lua delta745.3→1588.6KiB; last retained delta94.0→124.3KiB.
  This does not close preparation efficiency, all recursive/alias/resource cases,
  clean/sanitizer/pre-packed isolation, counted ownership or the entire S05/S06 batch.
- [ ] **S06** Implement persistent module initialization and dependency ordering,
  once-per-session state, durable storage and initializer cycle diagnostics.
  **WIP:** pointer-free aggregate globals now have logical module roots, ordered VM
  initializer fragments and compiler-owned accepted image bytes. Opening projects
  persistent storage rather than per-call copies. The new public image-copy service
  binds transport only; revision-6 execution/continuations and allocation are unchanged.
  Probes include mutation across calls, chained local aliases, arrays, initializer
  effects, imports and fresh compilation state. `abc_vm_read_image` passes direct
  four-mode bounds/null/unloaded-image/output-preservation checks. Full validation
  exits0 (`validation-wip-2.log`); the earlier failure is preserved. The S05 correction
  above closes the reproduced higher-order hole, not all proof acceptance.
  Publication/resource breadth, clean-build/sanitizer and performance remain incomplete. A top-level `let alias = original` probe exposes
  another root-identity defect, now corrected: binding supplies select the actual
  instance before demanding bytes, shared by local and module bindings. The probe
  returns42 with one root; aggregate438/422 includes chained record/array module
  aliases, saved/opened-field and function-result copy controls, exact root identity
  and no eager local-alias reads. Full validation: `validation-conformance-3.log`.
  Historical result40/two-root evidence is retained.
  No counted/frozen-owner or complete S06 claim.
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
rest syntax was shared, but pack/spread elaboration rejected at that historical
checkpoint (now implemented/partially qualified under X02–X04). ABC,
continuations and allocation machinery are unchanged. Current contracts: `docs/syntax.md` §2.1, `docs/application-sugar.md` and `docs/spread.md`.
Focused checks after the cutover: word bindings 106 checks/84 four-mode executions;
compiler 280; lambdas 269/80 executions; source demands 52. Integrated `validate-slet`
passed, including 112 production executions, 2 static-demand diagnostics, 12 portable-C
cases, 43 symmetric executions and 48 lifetime cases. Log:
`research/experiments/frontend-syntax/word-bindings/validation.log`.
No clean/sanitizer/performance qualification is claimed.
**Composition investigation (no implementation change):** existing `abc-opt` already
virtualizes eligible acyclic calls. The sum fixture's main/dispatcher contain CALLOC,
which triggers its allocation exclusion: current 290→289 optimized bytes versus
baseline 222→222; a scalar control fixture is 109→81 in both revisions. Four-mode
optimized outputs agree. Investigate packed tagged-value representation versus forced
frame storage before adding another inliner; ABI, exact bits and resource semantics
need a concrete approved design. Evidence and proposed direction:
`research/experiments/frontend-syntax/word-bindings/composition-investigation.md`.
Approved design: `docs/tagged-value-lowering.md`; implementation is in progress.
User approved fresh-padding canonicalization and compiler-dependent resource footprint
changes without weakening runtime checks or changing bytecode encoding. The initial
packed-cell path exposed an integer/binary64 kind boundary and nested cross-cell
shift defect. Historical failed qualification remains in
`research/experiments/frontend-syntax/packed-tagged/{README.md,current.log,baseline.log}`.
The shift defect is corrected without an ISA workaround. The float boundary required
and received explicit user approval for the following additive extension.
**Packed-float correction — Owner: primary coding agent. State: implemented; focused/full incremental validation passed.**
Added explicit F2BITS/BITS2F selected-stack unary EXT selectors0E/0F, profile2+, as an
additive revision-6 extension. Bits, existing valid encodings, ABI/layout and real
storage remain unchanged; older engines reject the new selectors. No scratch-memory,
numeric conversion, verifier weakening, new allocator or scalar algorithm. Files:
`tools/opcodes.lua`, `gen/semantics.lua`, generated metadata/fold consumers,
`src/{verify,residualize,optimize,residual_builder,residual_validate}.c`, `schema/residual.asdl`,
`frontend/let/abc.lua`, ISA/tooling/packed tests and Makefile. Bind raw identity through
existing interpreter/unary and symbolic sink paths; native/threaded retain placement,
optimizer preserves typed bytecode casts, tooling publishes typed unary relations.
Missing packing/extraction kind transitions are replaced. Integrated packed suite:
1894 checks/496 executions, optimized/unoptimized in four modes; exact negative zero,
subnormals, infinities, quiet/signalling NaN payloads, float arithmetic, nested mixed
records/arrays, direct/indirect calls and real storage. ISA oracle:143 cases/1144
executions, all286 public forms; residual315 checks; cache2880 poisoned exact-state
handlers. Full incremental validation passed. Evidence:
`research/experiments/frontend-syntax/packed-tagged/float-bitcasts/`.
Paired runtime-input measurements against adapted9cfd7f65 lowering (same runtime/IR):
raw/optimized roundtrip145→144 bytes, arithmetic164→163; artificial CALLOC1→0.
Interpreted medians regress3–20%; threaded improve13–28%; native eager/lazy vary
−9% to+8%. These are tiny API-call-inclusive CPU samples, not universal performance
or preparation/code-image growth bounds. Separate preparation/first-call samples
are noisy. No hidden claim of a universal speedup. Broader padding/loop/resource
qualification remains open; separate optimizer frame-access defect is not included.
No second inliner or optimizer eligibility change has been introduced.
**Bitcast cost follow-up — investigated; approved fast-path prototypes NOT ADOPTED after measurements.**
Pinned paired same-runtime probes reproduce interpreted regression9–12%; threaded
improves24–31% in this run, native differences remain small/noisy. Verified raw
identity streams in both banks/four modes preserve signalling-NaN bits. Disassembly
shows EXT selector tail-dispatch followed by an identity handler's next-opcode
tail-dispatch, with no operand conversion, spill or runtime kind check. Current
240 cast-handler symbols total5520 symbol bytes, not a relative code-growth bound.
The metadata-driven transparent EXT binding was approved, implemented in two
execution-binding variants and validated, then withdrawn: long cast streams improve,
but ADDC128 regresses roughly15–23% and representative packed cases show no reliable
benefit. The selector candidate reduces shared-library text by16320 bytes; that gain
is not retained. A byte-identical dual-library control reveals substantial native/
threaded harness/load-placement bias; those timings cannot prove candidate effects.
No new encoding, predecode subsystem, global hot-dispatch check or opaque fallback.
`gen/banked.lua` and `gen/semantics.lua` restored byte-for-byte to the pre-experiment
working versions; stronger exact-state NaN/high-bit payload tests remain. Both
candidates and restored runtime pass full incremental validation. The interpreted
packed regression is characterized, NOT fixed. No clean/sanitizer/resource bound.
Initial investigation:
`research/experiments/frontend-syntax/packed-tagged/float-bitcasts/cost-investigation/`.
Candidate patches, exact reproduction/measurement limitations and decision:
`research/experiments/frontend-syntax/packed-tagged/float-bitcasts/transparent-ext/`.
The later E01 source cutover and D07 collector-removal slice are recorded below;
general ownership, independent optimizer/frame-access and higher-order frontend
efficiency remain separate.

**Remaining grammar gate:** named keyed-requirement declarations share the elaborator,
but no keyed `do` constructor spelling has been approved/added. Do not claim every
named declaration is literal syntax sugar until that gap is resolved. Legacy dynamic
open-word/runtime-keyed-supply paths remain D03, not new COW container support.

**Uniform application update — implemented; focused validation passed.** Every suffix
applies the preceding value; removed terminal literal/block restrictions and argument-list
reopening. Named `= do(...)` returns a lambda, including nullary `do()`; bare `= do`
remains the executed body. No endall, implicit returns or new capture support. Syntax
checks: 127 / 68 four-mode executions; parser 232; word bindings 105 / 84 executions.
Existing multi-argument callback fixture migrated to an explicit argument list.
Docs: syntax.md, application-sugar.md, operators-and-blocks.md and spread.md.
Chain-wide saturation is now implemented in the shared call path: runtime values can
remain pending across consecutive Apply suffixes; each suffix adjusts its own results,
and argument computations/receiver addresses are snapped before later effects. Grouping
and other expression boundaries close the chain. Tests cover typed indirect callees,
vector expansion, defer, over-application, snapshots, receiver retargeting and trap order.
Application chains: 122 checks / 112 optimized/unoptimized four-mode executions;
integrated validate-slet passed. Evidence:
`research/experiments/frontend-syntax/application-chains/{README.md,validation.log}`.
**Known unresolved failure:** an optimizer probe involving a frame-allocating callee
fails with invalid frame access on both current and baseline frontends. Preserved in
`research/experiments/frontend-syntax/word-bindings/chain-memory-probe.{lua,log}`.
The passing chain trap test isolates ordering with explicit IR traps; it does not
validate away that failure. Packed-value changes remain in progress and unqualified.
Lexical discarded-receiver-write checking awaits Q11; the returned-word hint remains open.

**Vocabulary syntax checkpoint — suffix migration implemented; then parser-only.**
Approved forms now parse: `use module...`, `let ctx...`, `let ctx... = expression`,
and `do(ctx...)` / named block parameters. The initialized form evaluates once and
retains its explicit context under the approved semantics; the uninitialized form
expands an existing binding. Prefix binding/import spellings reject. `...args` stays
rest, and prefix supply expansion is unchanged. Canonical AST has VocabularyParam
and name/optional-initializer spread declarations/statements; module indexing and
syntactic capture discovery account for the explicit context binding.
Block-only/one-marker/foreign restrictions have parser tests. Syntax batch: 149 checks,
68 VM executions; at that checkpoint expansion still rejected `spread-unimplemented`
and had no execution coverage. Integrated validate-slet passed; raw evidence and scope are in
`research/experiments/frontend-syntax/vocabulary-syntax/{README.md,validation.log}`.
The syntax checkpoint alone did not complete the DSL feature.

**Vocabulary semantics — scoped implementation and integrated validation complete.**
Shared record snapshots and parameter expansion now
execute; namespace bindings replace flattened import lookup; module/type/constructor
aliases, declaration-position visibility and semantic capture selection are connected.
No receiver detachment or runtime namespace transport. Dependency foreign ABI symbols
are not implicit source imports; explicit public aliases retain their foreign contracts.
Vocabulary: 92 checks / 64
unoptimized four-mode executions; integrated validate-slet passes. Evidence and limits:
`research/experiments/frontend-syntax/vocabulary/{README.md,validation.log}`.
**Approved compatibility change:** type/function exports share one public namespace;
repeated public names reject across sections, before resolving this module's aliases or
initializers. Regression tests cover both section orders, bare/aliased names, within-section
duplicates and valid distinct/private-to-public aliases. Baseline acceptance and tightened rejection are
preserved in `export-name-probe.{lua,log}`. Isolated pre-packed lowering passes vocabulary,
compiler, word-binding, chain, demand and lambda suites (`isolation.log`). Composition
probe with the same pending packed lowering: sum raw bytes 275→306, optimized 108→108;
scalar 109→109, optimized 81→81. This is code-size evidence, not timing evidence.
Existing aggregate staging, capture ownership and optimizer/frame-allocation limitations
remain; no clean/sanitizer or timing qualification. See `docs/syntax.md` §2.1 and
`docs/spread.md`.

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

**Ownership binding removed; standalone core validated, integration pending.** User authorized cutting
out the ownership orchestration before adding replacement code, with no builds/tests.
Coordinator removed the v3 runtime dispatch/catalog, release-binding/cache/compiler,
ownership-specific execution forms, scope/slot/prefix machinery and generated holding
client/fixtures/build wiring. The large revision7/v4 proposal is withdrawn and deleted,
not an implementation target. Reserved runtime imports now reject; there is no host
foreign fallback. That removal checkpoint did not open counted admission; the later
connected source slice is tracked under E01/E02/O04–O08 below.

Retained: standalone C allocation/checked-count/replacement/iterative-queue algorithms,
source ownership proofs, ordinary ABC contexts/continuations and immutable executable
publication. That removal added no replacement layout, cleanup ABI, module format or
task system. The subsequent minimal C-entry encoding is tracked under E01 below.
The removal and core edits were initially untested as requested. Subsequently authorized
validation now passes: incremental build/full `validate`, standalone owner113 checks,
focused ASan/UBSan/LSan and a128KiB host-stack run. Evidence is under
`research/experiments/runtime-owners/core/`; this does not restore the removed source
binding or establish performance. The later source integration below replaces that
removed binding directly. Unrelated task protocols are unchanged.

- [ ] **E01** Define and bind explicit runtime-operation contracts to source lowering,
  verification and shared execution: cell/holding layouts, effects, clobbers, failure
  and completion/suspension. The old catalog path is removed, not a requirement to
  recreate that organizing layer. Any future encoding change requires approval.
  **Owner: coordinator; state: partial (supported source slice integrated).** Completed
  the approved connected owning-source cutover: checked placement → concrete storage/holding operations → appended result
  storage → prepared C lifecycle entries → normal/failure cleanup. Files include
  `frontend/let/placement.lua` (new), existing layout/ABC/IR/check/compiler consumers,
  `src/lifetime.h/.c` (new narrow bindings), owner/context/VM/residualizer/native emitter
  definitions, stencil/form generators and integrated source/runtime tests. No scope-slot
  registry, release cache, field-plan interpreter or pinned release register returns.
  Counted admission opens only for integrated contracts; public owned exports/FFI,
  persistent owning modules and staging remain rejected. The minimal revision-7/profile-4
  encoding is independent of the withdrawn larger design. Six exact reserved lifetime
  imports now bind directly; retired names/wrong signatures/host rebinding reject.
  v1/v2/v3 evidence remains historical. Next integration boundary: context-specific
  physical instances, erased/variant/container layouts and explicit public/foreign/task
  transport contracts—not implicit borrowed fallbacks.
  - [x] **Connected source execution/cleanup:** real factories, parent/child replacement
    with saved access, recursive/loop allocation, reference arrays/slices/interior access,
    closure/opened/keyed/partial captures, direct/indirect owning and multi-result returns.
    Concrete storage is the holding inventory; per-acquire scratch is cleanup-visible;
    owning results use appended caller records. Proven borrowed calls keep `InPlace`
    physical lifetimes (including a local-address tail-call regression). Actual native
    C entries are prepared before execution in all modes; no release cache, allocator,
    pinned register, slot registry or cleanup interpreter was introduced.
    Source tests1110 checks/352 calls across four modes, original/optimized and both
    lifecycle banks; C1043242 checks cover every allocation/acquire boundary in the
    factory/closure/array/slice/callable fixtures plus late chain failure, retain overflow,
    partial construction,
    self-replacement, zero-width allocation, traps, stack exhaustion, persistent ordinary
    writes, RX publication failure/retry and reuse. Real source builds a25-environment
    chain. Separately, C builds a100001-owner graph and invokes the source-generated C
    callback on a128KiB pthread stack with no source TLS or drain allocation.
    Full incremental `make validate` passes (`validate-final.log`). Focused ASan/UBSan/LSan
    on seven runtime units plus the C harness passes with function-type checks disabled
    for generated JIT entries; other runtime/generated bodies are not instrumented.
    No clean-build, whole-project sanitizer/TSan/race, task/browser or performance claim.
    Evidence and exact exclusions: `research/experiments/runtime-owners/source-cutover/`.
  - [x] **C-entry encoding boundary:** `.centry` selects revision 7/profile 4 and
    section 10; ordinary revision-6 assembly and `.codeaddr` meanings are unchanged.
    Loader/verifier check table extent/order, overlap within/across relocation tables,
    two-address/no-result/no-hidden-storage signatures and ABC-call/export exclusion.
    Optimizer retains C entries as independent roots and remaps their indices after
    pruning. At this format-only checkpoint delivery rejected in all four modes;
    the connected slice above now delivers native C entries. Tooling residual IR and
    portable C still reject the unsupported ABI.
    Files: `tools/assembler.lua`, module/internal/verifier/optimizer/CLI files,
    `gen/cold.lua`, VM/residualizer/residual-builder/portable-C consumers, and
    `Makefile` (including missing private-header dependencies for generated/PIC code).
    `tools/validate_c_entries.lua`/`.c`: 180 format/optimizer checks and 193 resolver,
    rejection/publication and ordinary-execution checks. Incremental `all` and focused
    integration pass; revision-6 oracle143/1144 executions, optimizer50/308 pairs,
    symmetric24, residual315, API/ISA, portable-C12, program37/1 and ownership170/56
    regressions pass. No lifecycle body executed, no source ownership completion,
    full-suite/clean-build/sanitizer/performance claim. Evidence:
    `research/experiments/runtime-owners/c-entry-format/`.

- [ ] **E02** Bind allocation release, direct known-type copy and localized erased
  operations per runtime-interfaces §3; checked local/shared counts, holding transfers
  and iterative release across all source execution backends.
  **Standalone C core implemented and tested:** `src/owner.h/.c` now takes
  complete concrete allocation size/alignment; the owner is its first member. No
  stored payload offset, descriptor, progress word or production traffic counters.
  Header contains count, immutable local/shared policy, optional C field-drop callback
  and dead-queue link. Retain preserves overflow/no-resurrection rules; shared counts
  preserve CAS/release/acquire ordering. Release enqueues; drain calls field drops and
  frees iteratively. Retain-before-replace remains failure-safe. Static immortal
  owners remain no-ops. The later connected source binding under E01 now implements
  local source placement, VM code delivery and constructor/failure cleanup; generalized
  erased/container/shared-source/task transport remains incomplete. `tools/validate_owner_core.c`113 checks cover
  allocation/extent/alignment/failure outputs, local/shared counts, overflow, zero-count
  rejection, replacement, branching and100001-object queues, and cross-thread final
  release. Native header measured32 bytes. Wrappers observe no allocation attempts
  during drain. Full incremental `validate`, focused ASan/UBSan/LSan on the core/test
  and a128KiB host-stack run pass. No clean-build, TSan/race proof, source integration
  or performance claim. Evidence: `research/experiments/runtime-owners/core/README.md`.
- [ ] **E03** Change `vm_internal.h`, `execution_emit.h`, `vm.c`, residualizer and
  both emitter/generator bindings per runtime-interfaces §§2,5,8; bind task context,
  allocator-generated spill/resume entries, result
  transport and PARK disposition to current entry/return/error ABIs. No hidden C cells,
  extra allocator or suspended worker-host-stack dependency.
  **Partial:** persistent root contexts and context-based bounds remain implemented.
  Ownership SERVICE and physical resume snapshots remain deleted; the synchronous
  root now owns a concrete activation chain/release queue, not a second execution
  context. Normal entry returns packed status. PARK/resume, tasks and scheduling remain unimplemented.
- [ ] **E04** Implement/check runtime-interfaces §§6–7 memory orders and lock hierarchy
  in task/channel/select/group/scheduler code, implementing the approved
  PARKING/PARKED/NOTIFIED handshake, channel/select registration, group cancellation,
  timer completion and runnable publication. Test adversarial interleavings at integration.
- [ ] **E05** Replace native whole-image lazy reprotection with private per-realization
  publication and atomic entry slots; retain code until image destruction. Audit all
  embedded task/worker-local addresses and account for code-allocation fragmentation.
  **Partial:** fresh page construction, RX sealing, atomic entry acquire/release,
  immutable published bytes, preparation mutex and multi-region emitter diagnostics
  retained. Stack bounds are context-bound; session module/foreign bindings still
  prevent claiming fully shareable images. Historical fragmentation measurements
  remain under `research/experiments/runtime-owners/c-release/`; no fresh measurement
  or performance acceptance is claimed for the removal checkpoint.
- [ ] **E06** Integrate concrete data structures through the linked O/C/T/P items in
  substantial slices, then W AOT. Measure fast completion versus parking, copy/count
  traffic, contention and retained memory; do not substitute a helper facade for semantics.

## O — Collector-free proofs, placement and reclamation

Authority: `docs/owners-references-ids.md` (semantics), `docs/runtime-interfaces.md`
§§1/3/9 (private ABI/checking) and `docs/implementation-map.md` (files/removals).
**Current target is explicit Rc/copy-retains. Historical implementation paragraphs
below do not authorize implicit Ref promotion or capability/resource inference.**

**Structural cut completed — coordinator, O03–O05/E01 remain partial:**
`frontend/let/program.lua` now owns checked functions/declarations and program-local
access/ownership results. Removed inference from `Check.program`, mutable function
proof annotations and the old implicit layout APIs. Semantic construction, source
compilation/imports, demand execution, specialization, lowering and snapshot/staging
consumers use the new boundary. `layout.lua` selects the explicit borrowed contract
only after rejecting counted requirements; ABC uses it for cells, widths and offsets.
Proof algorithms and ordinary ABC remain. Typed counted programs can be analyzed,
but cannot execute. IR nodes are frozen by caller contract, not a deep-copy/proxy
mechanism; transformations create and analyze a new graph. No owning ABI/runtime
binding or cleanup mechanism was added. `validate-slet` passes after two migration
errors were fixed; final program/ownership/access/lowering/lambda checks pass after
review cleanup. New boundary coverage:37 checks/1 VM execution. Evidence:
`research/experiments/frontend-syntax/program-boundary/README.md`.
Historical next step was per-root implicit materialization. It is superseded by
explicit Rc typing/lowering; see the latest ownership decision above.

- [ ] **O01** Freeze explicit-Rc tests: retain-on-copy/drop, invalid Ref escape and
  invalidation, strong self/closure cycles, stored borrows, joins, COW self-insertion
  and hidden module access. Preserve positive owning execution coverage with Rc.
- [ ] **O02** Specify actual strong-root constraints and independent borrow validity
  for declared ownership types; preserve recursive/polymorphic/separate-compilation
  bounds without runtime cycle detection. Remove automatic ownership selection.
- [ ] **O03** Implement explicit Rc typing/semantic operations and these checks in
  the existing source place/state model. Remove implicit counted/capability/resource
  inference and its producers/consumers; reject invalid borrows instead of repairing
  them. No second native value IR or placement reconstruction.
  **Implemented source-inference chunk (O01–O03 remain partial):** canonical
  `Ownership` metadata in `frontend/ir.asdl`, `frontend/let/ownership.lua`, and the
  existing access worklist now infer formal/fresh/module/deferred roots, counted
  requirements, independent activation borrows and strict holding edges. Calls
  distinguish fresh allocations through nested wrappers; aliases/interior refs
  preserve roots. Initializers, replacement stores, record copies, environments,
  returns and joins contribute obligations. Iterative SCC checking rejects concrete
  cycles with actual-root/source-point witnesses. Formal inequalities remain
  conditional on actual borrowing/owning bindings; recursive call families fold
  finitely without treating convergence/equal family names as lifetime evidence.
  Replaced the hardcoded frame-return/store checks with these inferred requirements;
  `program.lua` owns the analysis rather than attaching it to functions; the later
  `placement.lua` consumes counted facts for the supported physical slice. That source-inference
  chunk alone made no counted ABI, allocation, retain/release, reclamation or GC-removal
  claim; the later limited runtime binding is tracked separately under E01/E02/O07/O08.
  **Validation:** ownership170 checks/56 bounded VM executions (four modes,
  optimized/unoptimized), existing access176/112 and receiver407/384 pass; full
  incremental `validate` passed after the first recursive-local-environment proof
  failure was corrected, including the final source/schema binding. Source cases cover interior/self, environment/object,
  mutually exclusive joined cycles, nested factories, copied holdings, conditional
  formal self bounds, recursive forwarding/growing chains, modules and raw-pointer
  exclusion; checked-IR result-state transport and a 1200-root graph are also tested.
  **Cost/limits:** seven-trial probes show added scalar/callback analysis cost;
  the final 40-wrapper analysis sample is 3.452ms versus baseline1.008ms. Separate
  processes/uncontrolled host scheduling do not establish a precise slowdown; timings
  vary materially across runs. Scalar query counts stay unchanged; sampled callback queries increase by one.
  No performance acceptance, peak/RSS bound, clean build or sanitizer claim. Broader
  recursive borrow precision, COW/containers, erased/dynamic and separate-compilation
  contracts, finalized rank/placement and lifetime execution remain open. Evidence:
  `research/experiments/frontend-syntax/ownership-inference/README.md`.
**Owning-tagged functional qualification complete; lifetime-lowering architectural
acceptance reopened — coordinator (O04–O08/E01/E02 remain partial):**
user-approved EXT10/11 ADDR2BITS/BITS2ADDR use shared raw-identity computation, both
banks and unchanged native/threaded placement (no added stencil or cell kind).
`placement.lua`, `layout.lua`, `abc.lua`, opcode/tooling definitions and tests now
integrate packed tag/aligned-union values, active-case acquisition/move/drop, and
cleanup-visible partial construction. Removed blanket physical variant rejection and
flat-offset-only cleanup. Public/foreign address-bearing tag ABIs remain closed.
Bounded tagged references need no heap promotion; unchanged proven borrowed bodies
retain ordinary slot selection. Duplicate carrier captures and whole-payload reads
just to clear moved owners were eliminated after exposing the existing u8 C-index limit.
Full incremental `tagged-values/validate-reviewed.log`: source1763 checks/568 calls, C2508342 checks,
four modes/raw+optimized/both lifecycle banks; existing packed-value1894/496 and
machine/tooling/collector guards pass. Focused ASan/UBSan/leaks pass on seven runtime
units plus the harness (generated code uninstrumented, function checks disabled).
Source recursion/failure cleanup and separate C-built100001-node tagged release on a
128KiB pthread stack are qualified, not task/race support. Expanded fixture:92 C
entries,131788 native body bytes (A) versus134113 (B), maximum callback homes48 bytes;
nested variant(2) uses3 owners/35 non-null acquires/120 peak owner bytes. These are
storage/traffic measurements, not timing or a like-for-like speedup comparison.
Evidence: `research/experiments/runtime-owners/tagged-values/`. These passing checks
qualify cleanup of the generated holdings, not the necessity of those holdings.
The lifetime-lowering correction below supersedes the next-step recommendation.
Persistent modules, erasure/containers and public/foreign/task transport remain
separate approval/integration boundaries.

**Lifetime-lowering correction — Owner: coordinator; State: partial, removal checkpoint
(O03–O08/E01/E02).** User approved the concrete cutover and explicitly requested
removal of the obsolete lowering before implementing its replacement. User rejected
counting as the default lowering model. The defect
predates tagged support: `layout.lua` chooses a program-wide owning representation;
`placement.lua` reads counted requirements but does not consume individual borrow
proofs. Its whole-function `borrowing` gate, type-based `describe`/`resultRecord`,
`publish` and `copy` turn access-containing values into holdings and scratch copies.
An empty non-borrowed activation even gets an empty C cleanup entry. The generated
`leaf` retains its new root into return storage before releasing the local root;
that should transfer the existing holding, not acquire another one.

Approved integration boundary: source proof production through private function
contracts, concrete storage and generated cleanup, not a later peephole pass. Extend
existing ordered access facts with protection/last-use information; make ownership
summaries distinguish borrowed transport, transfer and independent acquisition at
actual source sites. Instantiate private call contracts before physical layout.
Borrowed results preserve their input/root provenance; consumed holdings identify
actual source storage so transfer clears the source before any failing call boundary.
Emit ordinary ABC value transport for borrows; generate cleanup storage only for
real holdings. Keep real acquisition failure transactions, root identity, source
value-copy semantics, cycle proofs, continuations and iterative reclamation.

Removal set: the program-wide reference-width decision, whole-function ownership
switch, type-implies-holding publication/result policy, unconditional scratch copies,
single-use-count-only move policy, and empty cleanup frames/entries. Preserve the
address casts, packed tagged layout, concrete active-case drops, counting/queue core
and lifetime error guarantees. No legacy/new dispatcher or runtime ownership plan.
Actual files: `frontend/ir.asdl`, `frontend/let/{access,ownership,program,compiler,
layout,placement,check,abc}.lua`, regenerated schema, affected source proof/call/ownership
tests and `tools/validate_source_owners.c`; align the interface/ownership documents
and implementation map with the approved boundary. No runtime replacement or new
heap ABI has been approved.

Acceptance targets, not current results: zero count traffic for local borrows,
borrowed returns and read-only matching even in a program with escaping allocations;
zero extra retains for a fresh-root return or constructor/result forwarding; the
three-root nested fixture must not manufacture intermediate holdings. Assert exact
traffic, frame/cleanup absence and unchanged values across calls, branches/loops,
mutation and failure; keep positive independent-sharing and partial-acquire tests.
Measure code bytes, cleanup storage and peak retained bytes, not just final outputs.

Approved policy boundary: ownership §2.1 specifies a separately counted escaping
root from creation; §3 and runtime-primitives §2 require count-free protected borrows
and transfers. The repair retains that escaping-root allocation policy but stops
treating every alias as another holding. The assistant's earlier suggestion of
uncounted escaping heap objects was not an approved private allocation contract and
must not be slipped into this cutover. Approved design is recorded separately at
`fd81f206`. No new runtime ABI or uncounted heap policy is part of this correction.

**Removal checkpoint completed, replacement not implemented:** removed the entire
source-to-physical orchestrator from `placement.lua`; only its concrete field-drop
emitter remains. Removed program-wide owning reference widths, whole-function
borrowing/holding switches, type-based result/publication/copy policy, blanket scratch,
single-use-only moves, empty cleanup frames and the ABC dispatch into that path.
There is no forwarding alias or alternative owning engine. `layout.lua` explicitly
rejects counted requirements until replacement; borrowed tagged accesses also remain
unavailable. Source proofs, packed cells/address casts, C core and runtime/lifecycle
bindings are unchanged. Proof tests no longer assert a global fat-reference layout;
positive source integration tests remain enabled, not rewritten to accept the gap.

Actual removal files: `frontend/let/{placement,layout,abc}.lua`,
`frontend/tests/{program,ownership,access_proofs,anonymous_context,rest_templates,
receiver_scopes,spread}.lua`; current-status/interface documents and
`research/experiments/runtime-owners/lifetime-lowering-removal/`.
Focused checks pass: ownership168/56 executions, access176/112, packed tagged1894/496;
C owner core113, C-entry format180/boundary193, collector guard234 files/17 probes.
The retained drop emitter reproduces396 descriptor uses/87 concrete callbacks against
an immutable pre-removal oracle. An ordinary borrowed source call executes42 without
lifetime imports or C entries; counted checked/raw source and borrowed tagged source
reject explicitly. `validate-source-owners` deliberately fails at executable admission;
full validation, new source lifecycle execution, sanitizers and performance have NOT
passed for this checkpoint. Historical generated images are not fresh source evidence.
Evidence: `runtime-owners/lifetime-lowering-removal/README.md` and its logs.
Removal checkpoint: `2b46dd89`. The user subsequently required an actual data-structure
and algorithm specification, not the earlier responsibilities outline.
**Detailed binding — Owner: coordinator; State: partial implementation (O03–O08/E01/E02).**
The user explicitly approved the concrete cross-file implementation scope before coding.
Implementation is separate from the specification checkpoint `ecb4271d`.
Current scope: publish converged source-site CFG/use/version/call facts, solve
liveness/protection and capability demands, bind concrete private contracts, then
replace physical lowering and migrate its consumers/tests. Approved file set:
`frontend/ir.asdl`, generated `frontend/let/schema/ir.lua`,
`frontend/let/{schema,access,ownership,program,compiler,layout,placement,check,abc}.lua`,
`frontend/tests/{ownership,access_proofs,program,source_owners}.lua` and
`tools/validate_source_owners.c`. The obsolete materializer remains removed; the
remaining temporary admission gates are removed only with the integrated replacement.
Preserve the runtime C bindings, cycle checker, packed tags and ABC allocator.
The first checkpoint below integrates original-site facts into the existing analysis
worklist; acceptance remains the complete source-to-physical boundary and §10 cases,
not a metadata-only checkpoint.

**Source-flow/loan-demand checkpoint (O03 deliverable partial, no item closed):**
The existing access worklist now publishes final per-site observations and original
statement/operand identities, bound call edges/effects, reference-contents versions,
read-location/provenance alternatives, and retention destinations. The checked program
owns these facts. Ownership computes backward carrier/contents and containing-root
demand, with predecessor-specific join versions. Loop writes remain invalidations
regardless of equal static IDs. Conditional traps retain normal-success edges; a
post-false-trap source-cycle regression rejects correctly. Loan IDs include the original
value binding so two results of one call cannot collapse. Approval/identity clarification
is separate in `37e72bf0`.
Actual checkpoint files: `frontend/ir.asdl`, generated `frontend/let/schema/ir.lua`,
`frontend/let/{schema,access,ownership,program}.lua`, `frontend/tests/access_proofs.lua`.
These are explicitly `loan-demand` templates, **not** validated guard witnesses,
capability/transfer decisions or concrete private contracts. The materializer and
counted admission gate are unchanged; no obsolete owning path was restored.
Checks: schema freshness/construction pass; ownership168/56 VM executions,
access213/112, packed tags1894/496. `tests/program.lua` and `tests/source_owners.lua`
still fail at `ownership-materialization` (`make` and `self_replace`, respectively);
the positive acceptance tests remain intact. Evidence:
`research/experiments/runtime-owners/source-lifetime-analysis/`.
No full suite, sanitizer, new source-owner runtime qualification or performance result.
That checkpoint still rejected the open-formal getter and merged static array fields;
those producer gaps are addressed by the continuation below. Neither checkpoint is a
completed transfer/protection proof. Integration boundary remains §10 execution, exact
traffic, cleanup/failure tests and measured storage/code costs.

**Dependency/relative-contents continuation (same owner, O03 partial; no item closed):**
Implemented original carrier/read/address/store/call-result/return dependencies in the
existing access worklist and finite definition/Written/Join relations in ownership
liveness templates. Arguments retain their call alternatives and tagged uses retain
case conditions. External field reads now carry finite read/operand/component obligations;
closed queries substitute actual caller contents. The formerly rejected open getter is
checked, and a frame-borrowed saved-child fixture executes raw/optimized in all four
modes. Recursive and nested external reads remain finite and distinct. `ContentsInput`
identifies an obligation, never dynamic allocation equality or an invented owning ABI.
Static array fields now have distinct `Borrow.Index` paths, including two fields holding
one identical root; dynamic Element aliases conservatively overlap them. Snapshot
relations include wildcard writes and possibly untouched preceding cells. Corrected a
source-definition bug where `Store.value` expression memo IDs overwrote real SSA Read
origins. Actual code files: `frontend/ir.asdl`, generated `frontend/let/schema/ir.lua`,
`frontend/let/{access,ownership}.lua`, `frontend/tests/access_proofs.lua`.
Checks: schema freshness/construction pass; ownership168/56 VM executions,
access249/120, packed tags1894/496. Program/source-owner integration probes still fail
at the unchanged `ownership-materialization` gate (`make`/`self_replace`). Evidence:
`research/experiments/runtime-owners/source-lifetime-dependencies/` (including the
intermediate failure and final passing focused run). No runtime count, cleanup-size,
code-size, sanitizer or performance qualification; no acceptance test weakened.
At that checkpoint Result/CallContents edges still required binding. The continuation
below supplies source-relative binding, not completed guard witnesses or a runtime ABI.

**Call-relative binding/capability continuation (same owner; partial, no item closed):**
Actual files: `frontend/let/{access,ownership}.lua`, `frontend/tests/access_proofs.lua`.
`Ownership.bindLoans(checked_program, entries)` now builds an entry-rooted finite loan
contract graph from existing queries, preserving separate invocation/argument bindings,
predecessor-selected joins, relative entry contents and callee exit/return edges.
`Ownership.capabilities` solves recursive source-origin/capability requirements. Known
input-origin results recover capabilities from captured caller arguments rather than
widening an identity ABI. Unknown callable obligations survive forwarding. These APIs
return `loan-contracts` / `capability-demands`, **not** completed bound instances, guard
certificates, concrete result resources or executable lifetime actions. They are tested
solver components; `Ownership.bind`/physical emission are still unimplemented.
Access now publishes construction of reachable returned contents as writes (including
repeated static sites), and closes caller/callee memory-version domains for forwarding
and downstream array projections. Materialized callable captures now live in actual
per-query environment contents. Invocation reads those fields rather than expired
creator SSA; code identities share capture shape only, not a global captured-value
union. The legacy materialized-code capture union and its transport path were removed;
nonmaterialized source partial-application analysis is unchanged. InPlace root loans
are explicit, and nested active-case conditions are ordered outermost first.
A source-owner integration probe exposed a serious intermediate analysis slowdown
(120-second timeouts). Diagnosed and removed the code-global capture feedback, preserved
monotone construction effects, and reused canonical access-set/immutable identity keys.
The final source-owner probe again reaches the unchanged `self_replace` admission gate;
one diagnostic run took 17.71s versus 37.74s with the parent access module. These are
single-run analysis diagnostics, not runtime performance qualification.
Final checks: schema freshness/construction pass; ownership168/56 VM executions,
access302/120, packed tags1894/496. Program integration still rejects `make`; counted
source-owner execution is still not admitted. Evidence (including intermediate probes):
`research/experiments/runtime-owners/source-lifetime-contracts/`.
**Locator/reuse continuation — coordinator, O03/O04 partial; no item closed.**
Actual files: `frontend/let/{ownership,layout}.lua`, `frontend/tests/access_proofs.lua`.
Ownership now computes normal-CFG SCCs, temporal locator equality and per-alternative
contents survival. Must availability meets predecessor witnesses; may availability
identifies possible losses. Evaluated index/base dependencies, replacement, calls and
allocation-site reexecution remain distinct. Dynamic alias classes do not prove equal
indices. Snapshot demands follow original definitions, contents and input-relative
returns; they retain logical loop-carried bindings and unresolved return/effect
boundaries. A call's write is never permission to clear its field before entry.
These are `source-locators` / `snapshot-demands`, not actual holding or container-lifetime
certificates. Exact locator prerequisites do not yet select Transfer versus Acquire.
`reuseRequirements` additionally finds carriers surviving an allocation site's reuse,
requires those roots counted **from creation**, and records old-result reuse obligations
without inventing result slots. It feeds strengthened requirements through the existing
retention/count/cycle solver, including retained targets and caller cycles. Original
checked summaries remain unchanged. Unknown reference/InPlace/erased call contracts
remain obligations; scalar-only callback signatures do not invent owning contracts.
`layout.lua` now delegates temporary borrowed admission to ownership. The old count-only
gate was removed there: new reuse requirements and unresolved bindings cannot fall
through to borrowed frame emission. Ordinary current-iteration frame use remains admitted.
Checks/evidence are under `research/experiments/runtime-owners/source-lifetime-locators/`:
schema freshness/construction, ownership168/56 VM executions, access356/120, packed
tags1894/496. Program/source-owner probes still fail at the unchanged materialization
boundary (`make`/`self_replace`); successful-execution acceptance tests remain intact.
No source-owner execution, full suite, sanitizer, count/storage/code-size or performance
qualification is claimed. The integration boundary remains concrete binding plus
physical lowering, not the new prerequisite proofs or the strengthened admission gate.

**Interrupted implicit-ownership cutover — coordinator, O03–O08/E01/E02;
partial, superseded by the user's explicit-Rc decision.**
Checkpoint contains entry-rooted `Ownership.bind`, incomplete `rootBindings`,
`Placement.program` and the ABC physical boundary in
`frontend/let/{ownership,placement,abc}.lua`; `frontend/tests/program.lua` now checks
that an unrequested owning template does not contaminate a pure entry, while actual
foreign execution still rejects during staging. A private pointer-free `leaf`
allocated directly into a caller result slot and executed in a temporary probe
(raw/optimized, four modes). Focused program36/2, ownership168/56 and access356/120
checks passed. This is not full source-lifetime qualification: outgoing holdings,
receiving bindings, preservation, normalized variants and owning callable/public
contracts remain unresolved. No full suite, sanitizer, count-traffic or performance
qualification was run. The user stopped this implementation and selected explicit
`Rc(T)` with retain-on-copy; do not continue completing this implicit-resource solver.

Superseded next action (historical, **do not execute**): finish guard selection,
capability requirements, preservation and consume/offer/result-slot inference.
The explicit-Rc cutover removes that responsibility rather than completing it.
Retained runtime code/evidence is not full Rc source qualification.

Historical specification checkpoint (before explicit-Rc supersession):
`4a9da5db:docs/source-lifetime-lowering.md` proposed concrete loan/guard/version records,
CFG liveness and invalidation rules, conditional/join/loop decisions, private consuming
inputs and mixed borrowed/fresh outputs, instance binding, move/failure sequencing,
compiler APIs and exact acceptance cases. In particular, result data stays in ABC
cells; only actual result holdings use appended `InPlace` slot arguments. This is a
proposed private ABI refinement, not a newly approved runtime/public ABI or a tested
implementation. The specification is kept in a separate jj change from removal.
The subsequent explicit implementation approval is recorded above. All executable
admission failures above describe that historical checkpoint, not current explicit-Rc
admission; the current qualification is recorded at the top of this ledger.

- [ ] **O04** Specify explicit Rc handle/payload and failure-safe call transport;
  Ref/Slice remain borrowed with fixed roles. Allocate only declared Rc roots and
  owning library/environment storage, never escape-promoted locals. Concrete
  construction/borrow/payload/private transport binding is settled for the initial
  Rc slice; owning environment/snapshot and broader transport gates remain open.
  **Partial implemented:** `placement.lua` selects checked counted local roots from
  creation, materializes root-preserving refs/slices/arrays/callable environments and
  appended owning-result storage, and structurally checks a separate physical graph.
  Borrowed pointer-free-reference functions retain one-address contracts without counts.
  Tagged alternatives now share canonical packed transport and active-case holdings.
  Context-dependent unresolved instances, persistent owning modules, erasure
  and owning public/foreign/task ABI remain closed. See E01 source-cutover evidence.
- [ ] **O05** Implement Rc retain-on-copy/release and proven move optimizations
  through value bindings, reads, assignments, calls, returns, captures and active
  sums; extend containers/erasure only under their contracts. Ref transport has no
  RC traffic or hidden preservation acquisitions.
  **Partial:** concrete copy retains into cleanup-visible scratch before replacement;
  single-use same-loop moves clear sources. Borrowed-function specialization avoids
  owner traffic. Active tagged payloads are now integrated; containers/erased paths
  and generalized context cloning remain open.
- [ ] **O06** Specify overflow, allocation failure, partial construction, abort/teardown
  and FFI retention/handle policies; no wrapping counts or implicit unsafe pointer proof.
  **Partial:** local source allocation/overflow/partial construction/trap/stack failures
  unwind before reset without result publication or ordinary effect rollback; tested
  at actual acquisition boundaries. Public/foreign retention and interruption policies
  remain unsupported, not inferred from raw pointers.
- [ ] **O07** Implement generated allocation-free iterative release and failure cleanup;
  no host-recursive destruction, user finalizers, tracing or collector fallback.
  **Supported slice implemented:** concrete source-generated field drops, including
  finite active-tag branches, execute
  through genuine C entries and enqueue only; the C core drains iteratively without
  allocation. Concrete activation records release actual established holdings on
  normal/failing exits. Exact current coverage is under E01; generalized representation,
  task/foreign teardown and resource qualification remain open.
- [ ] **O08** Validate long graphs, rejected cycles, independent borrows, captures,
  exact lifetimes and all execution bindings; measure count traffic and owner retention.
  **Current source evidence:** E01 and `runtime-owners/source-cutover/` qualify the
  supported connected slice, including source25-environment versus C-built100001-owner
  graphs. `runtime-owners/tagged-values/` extends source/tagged cleanup, exact owner
  traffic and peak owner-byte measurements. No current timing/performance or generalized
  concurrency acceptance.
  **Historical C-release evidence at `c16666c8`, not the removal checkpoint:**
  the now-retired `frontend/tests/runtime_owners.lua`84 checks/80 VM
  executions; C4304 checks. Both banks/raw+optimized/four modes; live banks/C,
  exact copy/count traffic, committed-prefix/partial-copy cleanup, 100001-owner graphs,
  branch/element-loop release, inaccessible zero-prefix payload, source exhaustion, allocation/RX failures,
  original PCs, successful retry, callback reentry and VM reuse. The full C validator
  also passes with a128KiB host stack. Native callbacks run with source TLS unset and
  leave the VM context unchanged; shared parents/children free through prepared native
  glue on another pthread. Wrappers find no release allocations. Cross-thread core/native
  tests are not task integration.
  Full incremental validation and focused ASan/UBSan/LSan pass; instrumentation covers
  owner/release/VM and execution-image/residualizer C, not all objects, generated engines,
  native machine code or frontend. No clean-build, TSan, race, wasm or general source
  lifetime qualification. Uncontrolled API-inclusive medians: scalar41–60ns, normal
  581–808ns, parent-child1038–1340ns, copied pair2258–3079ns. Repeated samples vary
  materially; some are worse. No controlled speedup or performance acceptance.
  First normal call113–339us includes release preparation;
  image/per-routine fragmentation remains substantial. Native owner header48 bytes
  versus the old24+8-byte header/prefix:16 extra bytes per allocation. ELF
  text3616285/data362224/bss16; smaller text is not speed/RSS. Earlier v1/v2 evidence
  remains historical. Evidence: `research/experiments/runtime-owners/c-release/README.md`.

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
- [ ] **D02** Implement transferable-only `Any`, exact numeric bits/conversions and
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
  **Owner: coordinator; state: partial (collector-removal deliverable complete).**
  - [x] Delete the81 tracked files under `vendor/whippet` (no dormant vendor fallback).
    The old dynamic/any/Whippet headers were already absent. No additional active
    dependency/build/CI integration, tracing adapter, GC root/collection call or obsolete
    GC example/test remained. Archives and raw experiment logs are unchanged.
  - [x] Add `tools/validate_no_collector.lua` and `make validate-no-collector`, included
    in `validate`: active-file/API/link/archive-reference audit and17 guard probes.
    Eight filesystem controls additionally cover reintroduced empty vendor directories,
    APIs/link dependencies, archive imports/symlinks and preserved generic barriers.
    The existing residual effect field named `safepoint` is call synchronization,
    not collection; owner/lifetime code, foreign synchronization/traps/limits are unchanged.
  - [x] Full incremental `make validate` passes, including1110 source checks/352 calls,
    C1043242 cleanup checks,48 module/VM lifetime cases and four-mode foreign/API tests.
    Built runtime/tooling symbol and dynamic-link audits find no collector dependency.
    No clean rebuild, new sanitizer, performance or concurrency qualification claimed.
    Evidence: `research/experiments/runtime-owners/collector-removal/`.
  Remaining prerequisite work is broader replacement ownership, owning public/FFI and
  persistent module-owner boundaries under O/E/C/T—not a surviving collector path.
  Next: design the next generalized concrete-ownership slice before implementation.

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
  transferability; reject `Any`/frozen erasure and child capabilities in ancestor queues
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
  **Owner: primary coding agent. State: active; concrete spread design approved.**
  Priority: X02/X04 ordered/keyed expansion, then X03 rest-template specialization;
  bitcast cost and collector-free GC removal follow. Preserve one-time source ordering,
  result adjustment, ordinary component provenance/captures, and fixed ABC calls.
  Extend pure Get with static array-element selection (no unpacking scratch storage).
  Module binding vectors share one initializer execution/publication. Packs/templates
  are source metadata only; templates use the sole word elaborator once per concrete
  instance, never replay checked bodies. Source-only templates may be imported/exported,
  but cannot become erased variadic ABC entries. Remove blanket spread/rest rejection
  and fixed-signature assumptions only as their replacements are qualified. No new
  evaluator/inliner, runtime pack, ABI/ISA, allocator or lifetime/GC policy.
- [ ] **X02** Implement one-time ordered nonrecursive expansion of result vectors/fixed
  arrays, including return/binding lists; preserve unmarked final-result adjustment.
  **Owner: primary coding agent. State: partial — implemented, qualification recorded.**
  Shared supplies handle marked/nonfinal expansion, sole arrays, nonrecursive multi-results,
  grouping/final forwarding, arrays and binding/return adjustment. Ordinary Get gains
  checked static Element selection; access provenance retains conservative element loans;
  ABC projects existing components without unpacking storage. Source lists snapshot
  computations before later effects; zero-width values retain no artificial slots.
  Module binding vectors replace per-binder initialization with one VM request/publication.
  `tests/spread.lua --unoptimized` is integrated:379 checks/108 four-mode executions.
  Extended qualification:719 checks/208 executions, eight optimized configurations
  BLOCKED by the pre-existing frame-access optimizer defect. Baseline/no-spread control
  confirms that defect at the same byte0xd. Full incremental validation including
  the integrated unoptimized boundary and final selector/trap tests passed;
  `git diff --check` is clean.
  No rest-pack, source-only template export or general ownership/ABI admission is claimed.
- [ ] **X03** Implement final ordered static-shape rest packs, static index/length and
  saturation rules without runtime pack objects or first-class erasure. Integrate
  `logged(T: Type, f: T, ...args)` through existing explicit type demands: type-only
  partial supply leaves f outstanding; known f specializes directly, runtime f uses
  its fixed-signature indirect ABI. No implicit generics or special treatment of any.
  **Owner: primary coding agent. State: partial — implemented, qualification recorded.**
  Formation anchors were explicitly approved and added to source_state.Context: qualified
  context/ordinal points splice selected ordinary captures at definition boundaries,
  share snapshots across instances and update copied structured-body lists. Unused
  captures emit nothing; opened places remain live. No placeholder reaches checked IR.
  Replaced fixed-signature-before-body assumptions for rest/explicit Type source templates.
  Static type arguments, code identity, component types and qualified faces key instances;
  one ordinary word elaboration builds each concrete body. Known callable holdings use
  typed parameter recipes and existing capture streams (including late recursive growth),
  not erased views or runtime packs; unknown implementations use the fixed indirect ABI.
  Packs support length, VM-demanded static index, expansion and normal component captures;
  ordinary binding/storage/erasure rejects. Consecutive suffixes preserve pending fixed
  requirements; once those are met rest saturates, including zero components.
  Public templates retain source definitions but create no erased variadic ABC export.
  Integrated rest suite:616 checks/276 executions; final full incremental validation
  passed (`full-validation-final.log`), with a clean `git diff --check`.
  Absolute growth samples:32 same-shape calls reuse one instance (643 raw module bytes);
  32 distinct lengths produce32 instances/2255 bytes/5244 IR nodes. No speedup/resource
  bound, clean-build/sanitizer or complete general specialization/ownership claim.
  Keyed static Type templates, general SCC/result inference, broader recursion/resources,
  module publication failure cleanup and the existing optimizer frame defect remain open.
  Evidence: `research/experiments/frontend-syntax/spread/rest-templates/README.md`.
- [ ] **X04** Implement keyed record expansion, explicit override, overlap/unknown-key
  checks, readonly/static protections and effects of overridden contributions.
  **Owner: primary coding agent. State: partial — implemented with X02.**
  Shared contribution records serve record/sum constructors, keyed words and handlers.
  Written-order evaluation precedes effective supply selection; explicit override is
  position-independent, spreads overlap rejects, unknown fields remain checked, method
  fields are excluded, and existing outstanding requirement protections remain.
  Snapshot occurrences preserve overridden trapping work. No dynamic table-key expansion.
  Evidence/validation: `research/experiments/frontend-syntax/spread/` (see X02).
- [x] **X05** Implement module/record/sum name binding, no-shadow and file-scope visibility
  rules; add `use module...` sugar without duplicate initialization or automatic re-export.
  Implemented within existing source-value/capture admission; aggregate staging remains S05.
  This completed the earlier record-snapshot contract; X07 replaces that part.
  See the vocabulary evidence above; rest/supply expansion and broader X06 acceptance remain open.
- [ ] **X06** Validate diagnostics, copies/owner bounds, lexical resolution, sugar
  equivalence and all applicable modes; measure specialization/copy/retention growth.
  Include explicit-requirement adapters with heterogeneous runtime packs and exact
  unit/single/multiple results; defer-based post-call work must preserve live results
  and holdings across clobbers/allocation/suspension where supported. Test type-only
  partial supply, typed indirect f, signature failures, effects/abort order and
  scoped captures. This is source/compiler acceptance, not a new runtime adapter engine.

- [ ] **X07** Replace opened-record field snapshots with live field places.
  **State: partial — implemented and qualified within admitted typed contexts.**
  `semantic.lua` now introduces projected places, preserves opened-field capture identity
  even for scalars, and prevents explicit saved aggregate reads from turning into aliases.
  Eager snapshot expansion (including its module fallback) is removed. Module aggregate
  storage remains outside existing static-demand admission; no replacement storage
  subsystem or escape permission was added. Updated vocabulary: 92 checks / 64 executions;
  receiver suite: 407 checks / 384 executions across four modes, with/without optimization.
  Full validation and isolation with `9cfd7f65` lowering pass. Structural cost checks show
  identical ABC for opened/qualified writes and no reads/copies for an unused opening.
  No timing, clean-build, sanitizer or broader ownership qualification is claimed.
  Remaining: module aggregate admission, frozen/readonly proof and broader ownership
  acceptance. Evidence: `research/experiments/frontend-syntax/live-opening-endall/`.
  **Anonymous-home follow-up — implemented; focused/full incremental validation passed.**
  `VocabularyParam` now has an optional name; `CurrentContext` represents bare `...`.
  `...: T` receives one ordinary typed input; contextual `do(...)` uses a checked
  callback signature. Named/unnamed entry opening supports expression and block bodies,
  once per signature at the first runtime requirement after leading static Type inputs.
  `(...)` reads the retained runtime receiver; explicit `(f)(..., role)` bypasses
  receiver insertion. No type-search, fabricated identifier, pack/namespace object,
  new evaluator, runtime encoding or physical-C0 guarantee. Parameter construction
  returns qualified bindings; expansion consumes those bindings directly. Template
  recipes preserve opening parameters too; temporary fake pack-component names removed.
  Whole-home assignment rejects; a reference home's private pointer holder has no
  public Ref/Ptr address. Field/value borrows and snapshots retain normal lifetime rules.
  Integrated anonymous suite:221 checks/192 executions, four modes; four aggregate/
  capture/interface probes deliberately unoptimized only. Named/unnamed field activity
  has identical executable IR; unused opening has no scalar field reads. Original user
  snippet parses, not a claim that its omitted APIs/returns/closures execute unchanged.
  Full incremental validation passed before and after the final rule refinements;
  focused fixture grouping failure retained honestly. No clean/sanitizer, frontend
  timing, broader frozen/ownership or optimizer qualification. Evidence:
  `research/experiments/frontend-syntax/spread/anonymous-context/`.
  The bitcast runtime follow-up was subsequently prototyped/validated and withdrawn
  for measured generic-EXT regressions (see bitcast checkpoint above); collector-free
  cutover remains next.
  Authority: `docs/spread.md` §5 and
  `docs/application-sugar.md` §3.1. Use one opening path for `let context...`, initialized
  contexts and vocabulary parameters. Establish/retain the receiver once; introduce
  immutable names for its actual fields, not eagerly copied contents. Writes preserve
  existing writable/frozen/readonly permissions; module/sum definition aliases stay
  unchanged. Parameter passing still decides value copy versus borrowed referent.
  Binding-resolved captures must preserve opened projections as places even for scalar
  fields, while an explicit saved field-read value uses ordinary value semantics.
  Remove snapshot expansion rather than retaining it behind an adapter or alternate
  mode. Preserve interface identity, source locations, no-shadow, evaluation order,
  owner/lifetime/COW rules and existing escape restrictions. No new capture permissions.
  Update every producer/consumer and the vocabulary/receiver fixtures together. Validate
  qualified/opened read-write equivalence, mutation after opening and after nested-word
  formation, scalar/aggregate/callable fields, deliberate saved values, once-only
  initialization, copied parameters versus references, readonly rejection and escapes.
  The earlier 92/64 and 323/304 suites validate snapshots, not this replacement. Measure
  representation/copy/retention changes; a documentation edit does not complete X07.

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
  left-associated suffix chaining: `f 1 2` is `f(1)(2)` and `f(x) do ... end`
  applies `f(x)` to the lambda, never appending to its argument list. This supersedes
  the earlier append/terminal-suffix rules. Preserve contextual typing, captures and
  local return; no arity lookup, newline rule, general `f x` or array/braces reinterpretation.
  Unit fallthrough is a separate approved semantic change in Q08. Touch `parse.lua`,
  AST/semantic consumers and focused
  literal/block fixtures; minus remains an operator, so negative arguments use `f(-1)`.
- [ ] **Q06** Validate equal-layout schema authority, dispatch/effect/place ordering,
  explicit-lambda equivalence, captures, spread interaction and applicable execution
  modes at an integrated boundary; measure costs rather than promise free inlining.
- [ ] **Q07** Separately specify and implement `Any` operator dispatch preserving
  schema identity and frozen/value semantics through descriptor-based ordinary calls;
  no per-record method table, table metatables or second dynamic scalar engine.
- [ ] **Q08** Implement unit fallthrough uniformly for named words, methods and lambdas:
  annotations/context or unconstrained acyclic no-value-return inference establish unit.
  Before recursive `Any` defaults, infer unit for unconstrained members of resolved SCCs
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

- [ ] **Q11** Implement lexical receiver calls and receiver scopes per `docs/application-sugar.md`.
  **Implemented/qualified snapshot-field baseline within admitted typed interfaces:** receiver-only borrowing,
  record/ref-record scopes and binding-resolved captures pass 323 checks / 304 four-mode
  optimized/unoptimized executions. The suite is integrated; full validation and
  isolation with `abc.lua` from `9cfd7f65` pass. The tested lifted and explicitly
  referenced mutation produce identical ABC. Import-spread/captured lexical dot calls
  now work without capturing unrelated lexical words when a member wins.
  Removed the syntactic capture pass and receiver heuristic. Word completion closes
  finite capture dependencies and finalizes hidden inputs, recursive/deferred calls
  and view layouts together; capture-free words remain capture-free. Late captures
  do not bypass existing ownership rejection. Evidence and pre-fix failures:
  `research/experiments/frontend-syntax/receiver-scopes/`. Packed work stays paused.
  No timing claim or whole-Q11 completion claim: live-place opening (X07), frozen-place,
  discarded-copy-write, broader interfaces and generic qualification remain outstanding.
  Existing member wins; only a closed interface lacking that member falls back to
  lexical `name(receiver,args)`. Bad signatures/noncallable fields never fall back.
  Table/any calls stay dynamic member calls; module qualification stays namespace lookup.
  Generic resolution is per specialization in definition-site lexical scope, with
  instantiation diagnostics. Preserve ordinary copy/ref semantics, including valid
  copy-writing transforms. A receiver supplied to `Ref(T)` borrows its writable place;
  ordinary arguments remain explicit. Record openings establish an innermost lexical
  receiver, while local callable bindings and callable fields retain ordinary signatures.
  Function-value selection and namespace qualification bypass receiver insertion.
  No write-back, signature retry, overload search, extension registry or lexical bound
  closure from an uninvoked field. Touch `semantic.lua`
  call/member resolution, `source_state.lua`, `schema.lua`, `check.lua` and ordinary IR
  consumers; qualification lives in `frontend/tests/receiver_scopes.lua`. Test builtin remove/has collisions,
  import-spread opt-in, formatting through lexical fmt, member priority, typed failure,
  dynamic no-fallback and exactly-once receiver evaluation. Q05 parses literal chains;
  Q11 resolves their calls without backend-specific operations.

- [x] **Q12** Implement `endall` as bounded trailing-block closing sugar.
  **Implemented/qualified:** `lex.lua` reserves it; `parse.lua` tracks block/delimiter
  boundaries and expands ordinary closers without mutating caller tokens. New integrated
  `frontend/tests/endall.lua`: 57 checks / 16 executions, AST/source-origin/boundary
  checks and return/defer equivalence across four engines, optimized/unoptimized.
  Full validation and pre-packed-lowering isolation pass. No runtime/ABI/schema change.
  Evidence: `research/experiments/frontend-syntax/live-opening-endall/`.
  Authority: `docs/operators-and-blocks.md`
  §7. Close the current trailing-block lambda and enclosing trailing-block lambdas,
  stopping at any other block or explicit delimiter. The current closer must belong to
  a trailing callback; ordinary word bodies, separately bound/argument lambdas and `if`
  blocks do not close implicitly. Indentation, arity and types never choose the extent.
  Reserve the token and retain its origin on the expanded closers. Emit the same ordinary
  AST as explicit `end`s: no new semantic/control operation, invocation, return, cleanup
  or lifetime rule. Test one/multiple callbacks, enclosing main remaining open, `if`/
  argument/keyed/grouping boundaries, invalid contexts, comments/newlines, diagnostics
  and exact AST/execution equivalence including returns and defers. Update grammar and
  parser tooling consistently; formatter behavior is a separate implementation concern.

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
