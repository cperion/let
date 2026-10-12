# Project instructions for coding agents

## Authoritative documents and project management

Start from the current code and the selected work item, not an old conversation summary or historical gap list.

- **`WORKLIST.md` is the single live project-management ledger.** Use its stable IDs, dependencies, status/evidence rules and execution policy. Do not create a competing checklist or treat historical checkboxes as current status.
- **`docs/implementation-map.md` maps work IDs to existing/new files, consumers, tests and removals.** Read the relevant rows before selecting implementation files. Proposed new paths are not evidence that those components exist.
- **`docs/runtime-interfaces.md` defines target private interfaces, layouts, ownership transfers, state transitions and lock/memory-order protocols.** `docs/runtime-primitives.md` defines the selected runtime algorithms. Implement these contracts, not a fresh per-backend design or generic helper facade.
- **Feature specifications define intended semantics:** `docs/syntax.md`, `docs/owners-references-ids.md`, `docs/tasks.md`, `docs/spread.md`, `docs/operators-and-blocks.md`, and `docs/application-sugar.md`. `docs/stdlib.md` owns the target library inventory and explicit API gates. Machine/encoding authorities are `docs/spec.md`, `docs/symmetric-isa.md` and `docs/module-format.md`; `docs/architecture.md` distinguishes current implementation from targets.
- **`REFACTOR.md` retains architectural rationale and chronological implementation evidence.** Its historical failures, checkboxes and superseded GC/open-word passages are not a second active backlog or permission to restore retired designs. `docs/frontend-completion-plan.md` is supporting dependency rationale; live status belongs in WORKLIST.
- Distinguish approved target, current implementation and measured evidence. If authorities conflict, identify the exact conflict and resolve it with the user; do not silently choose convenient existing behavior or old prose.

For each implementation chunk:

1. Identify its worklist IDs and actual dependencies. Inspect their current producers/consumers/tests; existing documented evidence is a starting point, not a fresh audit.
2. Record owner, state (design/active/blocked/partial), concrete scope, actual files to touch/create, obsolete paths to remove, next action and expected integration boundary. Do not claim another agent's work or mark an unassigned task active speculatively.
3. Reuse approved interfaces and algorithms. Present the concrete slice for approval without reopening settled choices. Raise genuinely unresolved language/encoding gates or material mismatches explicitly.
4. Implement a coherent cross-file replacement. Checklist items are responsibilities, not mandatory tiny patches; combine related IDs where appropriate.
5. Update WORKLIST with actual outcomes, checks run, remaining failures/blockers and evidence paths. Check off only the specific completed deliverable; split partially completed work rather than hiding it. Append durable architectural evidence to REFACTOR when useful, without duplicating live status.

Preserve immutable archives/raw experiment logs. Do not rename historical `.slet` evidence during active `.let` migration. Preserve unrelated user work and avoid opportunistic cleanup.

## Design together before coding — mandatory

Before every coherent implementation chunk (not each individual edit within an approved chunk):

1. **Inspect the existing code and the intended specification.** Trace the relevant producers, contracts, consumers, and tests. Existing implementation behavior is not automatically the intended design; it may already contain drift.
2. **Present a concrete solution design to the user before editing implementation files.** Explain:
   - the problem and the intended architectural invariants;
   - the proposed end-to-end data flow, control flow, and interfaces;
   - which components and files must change;
   - what existing abstractions, assumptions, and code will be removed or replaced;
   - effects on semantics, representation, placement, continuations, ownership/reclamation and concurrency where relevant;
   - encoding/API compatibility decisions, alternatives, and unresolved questions;
   - how correctness and architectural conformance will be tested, and how performance will be measured when relevant.
3. **Wait for explicit user approval of that design before implementing it.** An instruction to fix a problem starts the design discussion; it does not waive this gate. Approval to investigate or discuss is not approval to code. Do not make a “small first patch” while the design is still being discussed.
4. **If implementation reveals a material design change, stop and discuss it.** Do not silently add a workaround, fallback, compatibility layer, or new subsystem.

The purpose is to think together and prevent architectural drift. A checklist of edits or a promise to “fix it end to end” is not a substitute for explaining the design.

Explicitly requested instruction/documentation edits, such as creating this file, may be made as requested; they do not authorize runtime implementation work.

## Replace responsibilities directly — cut over, do not wrap

**Default working method: understand the target, cut out the obsolete organizing path,
implement the correct contract directly, migrate its consumers, then validate the
integrated replacement.** Optimize for simple, efficient, correct architecture—not
minimum diff size or uninterrupted green builds.

### Before writing replacement code

- Identify the single authoritative owner of the responsibility and its target interface.
- Name the old entry points, representations, dispatch branches, conversion layers and
  build dependencies that the approved change retires. Record this removal set with
  the work item, alongside correct algorithms and unrelated code that must survive.
- Trace every affected producer and consumer. Plan the actual cutover, not a new API
  whose implementation forwards to the old subsystem indefinitely.

### Implement the target directly

- Remove or disconnect the superseded path from active execution first within the
  approved chunk, then rebuild the responsibility around its correct contract.
  Temporary compile failures expose consumers to migrate; they are not a reason to
  insert an adapter. Do not delete unrelated code or user work to accelerate the cut.
- Change producers to emit the right representation and consumers to accept it.
  Fix the definition at its source instead of translating wrong data downstream.
- Preserve sound algorithms by moving/updating them under the new responsibility.
  Cutting an obsolete abstraction does not mean gratuitously rewriting correct code.
- Use the documented concrete structures and algorithms. Prefer direct data flow,
  explicit ownership, ordinary calls and one canonical representation per boundary.
- Remove superseded branches, flags, aliases, wrappers, tests and build wiring in the
  same coherent chunk. Update tests to the intended contract; retain independent
  regression evidence rather than preserving obsolete semantics to satisfy old tests.
- If completing the cutover reveals a material design gap, report the exact blocker.
  Do not hide it behind a fallback, catch-all helper or temporary compatibility engine.

### Recognize and avoid shim-driven refactoring

Do not introduce these merely to avoid migrating callers:

- a new facade over an obsolete implementation;
- old-to-new-to-old representation round trips or post-hoc normalization passes;
- duplicated old/new state with synchronization glue;
- dispatch flags choosing between legacy and replacement semantics;
- a generic helper/interpreter that hides operations the target architecture must own;
- “temporary” forwarding aliases or compatibility layers with no approved external need.

A real boundary binding is different: documented native/threaded emitter bindings,
pthread platform wrappers and explicit foreign ABI marshaling connect genuinely
separate mechanisms. Keep them narrow; they must not preserve wrong semantics or
reimplement the authoritative computation. Compatibility requires an explicit user
requirement and approved scope/removal policy, not a desire to keep intermediate code
working. Never silently reinterpret old bytecode.

### Completion review

Ask: **Does the new owner actually own the responsibility? Can the retired path be
reached or built? Are callers still converting through its representation? Did we add
indirection, copying, allocation or dispatch solely to avoid changing them?**

Close the work item only when the approved removal set and end-to-end contract are
implemented and the relevant boundary is validated. Report residual legacy paths,
performance costs and incomplete work plainly. Preserve the distinction between
proposed, approved, implemented and validated behavior. Stay within the approved
scope; this policy is not permission for unrelated rewrites.

## Preserve the ABC machine design

- A and B are symmetric operand stacks. For `.X`, X is the selected stack and Y its opposite: binary scalar operations compute **X0 op Y0**, consume both tops and place the result on X. In particular, `SUB.B` computes **B0 - A0**, not A0 - B0.
- Dynamic scalar operations must follow that same model, not a separate two-operands-on-A convention with internal repacking.
- Unary, literal, boxing, cast, and test forms operate on the selected stack under their declared layout contracts.
- C holds structured state and is accessed explicitly. Call argument gathering is a separate calling convention, not a reason to make scalar arithmetic A-only.
- Existing A-only dynamic scalar implementations are a known deviation to correct, not a compatibility invariant to preserve by default.
- One authoritative scalar computation owns checks, branches, representation decisions, errors, and composition of existing typed operations. Backends bind execution mechanisms; they must not independently implement scalar algorithms.
- Symbolic cache state is register allocation. Do not introduce a separate native residual-value IR, second allocator, or placement-reconstruction pass.
- Keep runtime execution independent of the build-time `abc-opt` pipeline.
- Allocation is an effect; “dynamic” is not an effect. Unknown types and version saturation are not excuses for opaque scalar execution fallbacks.
- Preserve explicit ABC continuations and separate frame transport from control transfer. Do not implement ABC recursion through recursive host execution.
- Preserve current effect synchronization, retained-access liveness, traps and stack-limit behavior unless a policy change is explicitly approved. The collector-free target has no tracing roots or GC safepoints; that does not remove ownership, suspension or foreign-boundary synchronization obligations.

## Implement substantial chunks; validate at boundaries

- The goal is to write the approved architecture, not keep every intermediate edit green. Batch changes across authoritative definitions, producers, consumers and tests.
- Temporary build/test breakage during a coordinated replacement is acceptable. Do not preserve obsolete machinery or add compatibility scaffolding to make intermediate states green.
- Do not stop after each file, function or checkbox to build, test, seek renewed approval or narrate progress. Approval covers the agreed coherent chunk; material design changes still require discussion.
- Run focused checks after the changed responsibility is integrated. Use earlier targeted probes only to resolve a concrete implementation blocker.
- Reserve full suites, clean builds, sanitizers and performance experiments for relevant integration/acceptance milestones. Do not repeatedly rerun a known baseline or turn every local correction into a broad validation cycle.
- Diagnose failures, batch related corrections, then rerun the relevant checks. Record incomplete/broken state honestly at handoff; temporary breakage is not completion evidence.
- Avoid repeated rediscovery, speculative scaffolding and documentation churn as substitutes for implementation. Documentation-only changes do not require runtime test runs.

## Approved target constraints

- One collector-free Let language, `.let` only in the target; no `.slet` compatibility alias. Current profile restrictions remain implementation facts until coherently migrated, not instructions to rename files prematurely.
- **Whippet must be completely removed from the active project as a completion criterion.** Remove `vendor/whippet`, Whippet-specific headers, dependency/build/link integration, tracing descriptors/adapters, GC root registration and collection safepoints, and retire or replace obsolete GC tests/examples. No dormant collector fallback remains. Historical archives may retain original evidence, never active dependencies. Preserve lifetime, error, stack-limit and foreign-boundary guarantees through the replacement contracts; do not delete generic synchronization merely because it once served GC.
- No tracing collector, runtime cycle-detector fallback or restored archived dynamic engine. Owner proofs, semantic holdings and immutable construction enforce lifetime safety; register transport is not ownership traffic.
- Tasks use explicit ABC suspension/continuations, task-owned state and pthread workers under the documented protocols. No retained worker-host-stack execution dependency, second allocator or direct JS-worker backend.
- Emscripten supplies pthread adaptation for task-capable AOT C; browser support is unvalidated until tested. Emscripten does not supply Let continuations.
- Spread/packs/import sugar and static operator dispatch elaborate through ordinary source/IR mechanisms. Do not add runtime pack objects, backend-specific operator algorithms or guaranteed-zero-cost claims.
- Do not silently assign public encoding, dynamic interface identity, polymorphic owner rules or foreign/abort semantics where the interface documents identify a hard gate.

## Validation and reporting

- Test the architectural contract as well as outputs: operand placement, both destinations, noncommutative operand order, untouched live values, and relevant effect boundaries.
- Passing tests alone does not establish architectural cleanliness or acceptable performance.
- Distinguish measured results from structural expectations. Report regressions, code growth, incomplete work, and untested paths plainly.
- Do not report a manifest edit, partial migration, or unvalidated change as a completed fix.
- Preserve existing user work and unrelated uncommitted changes.
- Do not use subagents or modify internal edit-plan sidecars unless the user explicitly requests it.
