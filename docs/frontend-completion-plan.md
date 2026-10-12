# Frontend completion: one collector-free Let

**Live status: [WORKLIST.md](../WORKLIST.md).** This document is dependency/design
rationale, not a second checklist. The live record adds older source-demand/frontend
completion and VM qualification work omitted from the ownership-centered O packages.
Crosswalk: O1–O3 → O/S; O4–O5 → C; O6 → D; O7 → U; O8 → T/P/W/L; O9 → X.
Use current code and test evidence there rather than historical blanket gap labels.

**Status: approved direction, implementation plan not executed.** The authoritative
ownership target is [owners-references-ids.md](owners-references-ids.md), integrated
with [syntax.md](syntax.md), source virtual places/demands and VM-only evaluation.
There is no collector fallback and no filename-selected ownership language in the
target. **`.let` is the sole approved source extension; `.slet` is retired without
an alias.** Current typed `.slet` execution and `.let` lowering rejection still stand
until implementation.

The previous F01–F18 backlog assumed SLet borrows versus Let tracing GC and open-word
identity. It is preserved, including its probes and historical counts, in
[the archive](../research/archive/ownership-before-counted-design/docs/frontend-completion-plan.md).
Those packages are not automatically completed, nor is their GC work still authorized.

## Boundaries

- Source owner proofs extend existing value/place/retained-access metadata.
- Source computation still executes verified ABC through the VM, not Lua or an
  ownership-specific evaluator. Existing Ershov scheduling remains authoritative.
- Runtime symbolic cache state is still the allocator, not source ownership analysis.
- `abc-opt` remains optional build-time tooling; the runtime cannot depend on it.
- Source memory owners are not caller-owned compiled regions. The latter's separate
  version-budget design is not implemented by this work.
- Current runtime traps, continuations, stack limits, foreign effects and public ABI
  remain unchanged until a concrete implementation design is approved.

## Dependency order and deliverables

### O1 — Freeze the semantic oracles and remaining contracts

Write counterexamples and independent expected results for owner self-edges through
interior references, hidden closure captures, stored-borrow lifetimes, unioned branch
edges, COW self-insertion and task-world access. Settle the canonical document's open
inference/ABI/failure/library questions before their affected implementation slices.
Retain original proposal deviations explicitly rather than quietly weakening proofs.

### O2 — Owner/provenance summaries in the existing source model

Specify the concrete owner-root identity domain, independent borrow proofs, rank
constraints, world capabilities and destination-retention summaries. Show how
interprocedural/recursive inference terminates conservatively, how polymorphic
summaries instantiate, and what crosses separately compiled/callable boundaries.

Acceptance: interior references name actual aggregate owners; signatures cannot erase
capture bounds; contradictory or unknown required proofs reject without a runtime
cycle check. No physical placement or source computation occurs in metadata queries.

### O3 — Root placement and explicit release obligations

Select escaping root values before materialization, not whole counted activations.
Preserve addresses of roots and parts. Define counted reference/slice/environment
layouts, allocation failure, count overflow, partial construction and abort cleanup.
Specify the nonallocating intrusive release worklist and independent borrow elision.

Acceptance: local/parameter/part escapes, safe non-retaining calls, rejected cycles,
long release chains without host recursion and exact effects on all VM bindings.
No tracing maps, safepoints, weak references or GC dependency are introduced.

### O4 — Stores, stable slots and ids

Implement independent store copies, segmented slots, occupancy/generation checks and
slot-extent bounds. Long-lived links use ids. Element references are nonescaping
borrows; growth is safe, invalidating removal/replacement requires proof.

Acceptance: holes and reused slots, copied internal ids, collision/wrap limitations,
live-borrow invalidation, allocation-free try operations and exact release behavior.

### O5 — Immutable value construction and COW containers

Implement list/string buffers, immutable boxes and frozen values using the DAG
construction rule. Non-transferable buffers retain mutable-domain owner constraints.
Retain incoming values before uniqueness testing; account for hidden aliases on moves.

Acceptance: value copies versus local aliases, nested/direct self-insertion, snapshots,
substring retention/compact, immortal literals, write detachment and freeze with
outstanding addresses. Demonstrate rather than assume count/copy elision.

### O6 — Transferable any and value tables

Specify dynamic encoding compatibility and implement one shared scalar computation,
transferability checks, immutable boxing, value maps and their dense array part.
Preserve named-layout versus array-kind proof separation. Do not restore the old
mutable-terminal/open-word engine underneath a new table API.

Acceptance: dynamic error/operand order, table copy isolation, dense/gapped length and
iteration, method receivers, COW, no escaped entry references and no profile-5
reinterpretation or bytecode quickening.

### O7 — Capabilities, module APIs and language unification

Infer count-free, allocation-free, dynamic-type and world-access facts independently
and transitively. Specify capability requirement syntax; the extension decision is
settled: `.let` only, no `.slet` alias or fallback. Remove filename-selected semantic
profiles and their compiler/API dispatch, rather than routing `.let` through a renamed
SLet implementation. Update parsing, checking, lowering, imports, exports, staging
and diagnostics together. Imports discover `.let` only; retire dual-extension
ambiguity rules and profile-direction restrictions.

Migrate active examples, fixtures, build/CLI tools, editor integrations where present,
and executable documentation to `.let`. Preserve historical archive filenames and
raw evidence. Diagnose obsolete `.slet` inputs rather than silently accepting an alias.
Do not report a removed profile flag or successful scalar Let example as unification.

Acceptance: typed and dynamic code coexist in `.let` with one semantics; restrictions
are actual capability/unsupported-feature diagnostics, not source profiles. Test
`.let` import graphs, obsolete-extension rejection, CLI/compiler/staging paths,
owned ABI checks and VM-only static execution with correct owner/snapshot transport.
Run the full suite in all four execution modes. Current unsupported behavior remains
explicit until each path is complete.

### O8 — Tasks and library coverage

Implement the approved [tasks.md](tasks.md) design: structured groups, explicit
`g.channel`, blocking tasks, select, yield and cancellation by marking/closing.
Workers use pthreads behind a narrow internal wrapper. Wasm adaptation is delegated
to Emscripten pthread support, with application-owned build/hosting configuration;
no direct JS-worker backend or general host scheduler API. Task-capable AOT C needs
explicit suspension/runtime integration before Emscripten validation can claim support.
Atomic shareable counts exist from creation. First specify scoped-capability
summaries (including queue/result retention bounds), independent suspension effects,
parking across all execution bindings, registration/cancellation/select races and
immutable-code publication. Foreign blocking/affinity and program-abort shutdown
remain concrete protocol gates, not unspecified alternative source semantics.
Implement text/format/pattern words only
after their result, mutation and failure contracts are complete.

Acceptance: transitive reads/writes of another task's mutable globals and mutable-backed
views reject; group capabilities cannot enter `any` or longer-lived queues/results.
Cover repeated join copies, all-child group teardown, close/draining, exactly-once
select, cancellation/creation races, cooperative completion and controlled-clock tests.
Validate parking/migration and publication/final-release races in all four execution
modes, ids without implicit store sharing, pattern reference behavior and
mutation-during-callback cases. No blanket allocation-free communication claim.

### O9 — Static supplies, packs and import-and-spread

Follow [spread.md](spread.md): ordered/keyed expansion, fixed arrays, static-shape
rest packs, no-shadow name binding and `use ...module`. Specify parser/elaboration
interfaces before coding; reuse existing source values/places and specialization.
Preserve implicit final-result forwarding, source-order effects, owner/group bounds,
static partial-supply and import initialization. Do not implement runtime packs or
runtime list/table argument dispatch. Validate the canonical diagnostic/effect/
visibility matrix and measure specialization growth and retained copies. This work
can be staged independently of task runtime construction, but cannot erase its
scoped-capability obligations when those are introduced.

## Validation and performance gates

For each slice, show design approval, implementation evidence and validation separately.
Test architecture as well as outputs: source identity, owner graph constraints,
no premature release, no hidden roots/cells, selected A/B placement, independent
CALL/RET banks, explicit continuations and relevant effect boundaries.

Measure count/atomic traffic, borrow elision, allocation/COW work, peak retained
memory (including substrings/owner roots), handler/library and program sizes,
preparation, first execution and steady execution. Include negative tests and
mutants that violate proof obligations. No generic speedup or leak-freedom claim
follows from a few successful examples or the existing typed validation suite.

No runtime implementation is authorized merely by this plan's existence; present
and approve concrete interfaces before each implementation change.
