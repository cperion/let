# Actual-binding access conformance — implementation findings

**Status: the reproduced higher-order retention defect is corrected and qualified;
broader ownership/access acceptance remains incomplete.** This document was incorrectly presented as a new design awaiting
approval. That proposal status is withdrawn. It records defects in the bounded
module/access batch, not a replacement language specification. It does not expand the
batch to counted owners, frozen values, address relocation or dynamic execution.

Contracts remain [owners/references](owners-references-ids.md) §§2–4,11 and
[source virtual values](source-virtual-contract.md) §§1,3,6. In particular, immutable
value definitions are context-qualified, mutable contents are state-indexed, and
higher-order calls cannot erase retained-store/owner bounds.

## Findings

1. `saved()` rejects a callback storing `Ref(local_point)` into an external Holder;
   `apply(saved)` incorrectly accepts the same operation. The generic summary marks
   unknown may-access effects but does not compose the supplied callable's stores
   and outlives bounds. Merely propagating an `unknown` bit is insufficient.
2. `let alias = original` at module scope demands a copied aggregate image and creates
   a second root. Ordinary instance aliases must retain the original root; field
   reads and function results remain value copies.
3. Current concrete-view summary bindings retain raw capture IR operands. Evaluating
   those operands under another function's value/storage ordinals is not a valid
   capture contract. Captures must carry the forming context and correct snapshot/
   place identities instead of being re-read in an unrelated context.

Reproducers/evidence:
`research/experiments/frontend-syntax/module-aggregate-access/`.

## Implemented checkpoint (not proof completion)

- Binding supplies now select actual instance identity before value reads. Local
  and top-level record/array aliases share storage; module aliases install no new
  image/root. Field reads (including opened fields) and call results remain copies.
- Concrete view facts hold qualified place routes or frozen value provenance,
  never raw capture IR operands. Callable code facts are component-indexed, and
  a captured callable is not confused with its enclosing callable's entry.
- Aggregate tests: 438 checks / 422 VM executions. Access tests: 120 checks /
  80 executions. Full validation exits0 (`validation-conformance-3.log`).
  Concrete opaque-view results reject with `borrow-proof`; the summary consumer
  now uses the declared IR result vector, not a nonexistent `stmt.signature` field.
  Loop holding metadata uses finite qualified binding nodes, not recursively copied
  environment trees. The cyclic checked-IR fixture qualifies analysis convergence
  only, not runtime environment storage reuse or lifetime safety.
- **Ordered-composition correction:** formal callable parameters/components and
  invocation results retain canonical Borrow code origins. The access pass builds
  provenance/state relations once from checked IR and composes those summaries via
  a finite query worklist. It no longer replaces a formal invocation with opaque
  may-writes or drops callable facts from results. Callback reads/writes/stores are
  composed at the original invocation state, including interleaved stores and saved
  results. No scalar operations, source elaboration, executable call bodies or
  native placement are replayed by the metadata queries.
- `saved()` and `apply(saved)` now both reject `borrow-store`. Forwarding, returned
  callable identities, record components, recursive wrappers and trailing-block
  sugar also retain that obligation. Safe callbacks execute in all four modes,
  optimized/unoptimized; live captures versus saved snapshots and callback-result
  stores/returns have positive and negative controls. Access176/112; the module
  alias control still returns42/one root. Evidence: `ordered-composition/` below.
- Physical targets now use canonical `Borrow.Target` nodes (`StorageRoot`,
  `InputTarget`, `OutputTarget`), separately from retained `Source` loans.
  `ValueInput` and `CallOutput` cannot be used as physical `Location.root`.
  Unknown dereferenced provenance and uncontracted opaque borrowed calls reject
  `borrow-proof`. This is not a complete counted-owner/rank/overlap proof.
- Cost qualification exposes a regression: on the 12-wrapper microfixture, median
  analysis CPU increased from 4.342ms to 11.681ms; median sampled peak Lua delta
  745.3→1588.6KiB, last-run retained delta 94.0→124.3KiB. Seven runs, one machine,
  same runtime; sampled allocation deltas are not process peaks or general bounds.
  Preparation/metadata efficiency remains open.

The correction preserves invocation point/state rather than applying callback
stores after unrelated effects or substituting entry snapshots for live captures.
Remaining acceptance includes broader recursive/alias/publication/resource cases,
pre-packed isolation, clean/sanitizer qualification and preparation efficiency.
Full counted/frozen ownership and a serialized/public summary ABI remain outside
this batch. The older findings and logs below are historical, not current failures.

## Required data and control flow under the existing contracts

### One actual callable/provenance contract

Extend the existing source callable/Borrow metadata, not executable IR or native
placement. A callable fact carries its canonical word identity (or formal callable
component), environment bounds and complete ordered holding facts:

- Value holdings freeze their provenance at formation. Later writes do not change
  that captured reference/value snapshot.
- Place holdings freeze the actual context-qualified root/path identity. Contents
  are queried at the invocation's state, so live opening remains live.
- Value/place ids include the defining context; equal ordinals from different
  functions cannot collide. Aliases preserve the original word identity.

Replace the raw `View`-slot-expression convention in the access pass. Do not keep
it underneath another adapter or replay it under the consumer's frame.

### Formal invocation obligations

When a checked body invokes a callable parameter, retain a symbolic invocation
obligation in its access summary: selected callable component, ordered argument
provenance/place holdings, point/state and result linkage. Use canonical Borrow
metadata in `frontend/ir.asdl` where new record shapes are needed; regenerate schemas.
This is an analysis relation, **not** a new runtime call instruction or residual IR.

At a source-known caller, bind the actual callable description and instantiate its
already-computed read/write/capability/retained-store/result/bounds summary. Apply
those obligations to the caller's current source state. This must reject the same
local-to-external Holder store as direct invocation, while accepting a genuinely
nonretaining callback. Results preserve callable identity and environment bounds
through ordinary parameter/return composition.

Reserve identities before recursive composition. Iterate monotone obligations over
finite context-qualified roots, typed paths and callable bindings; unresolved proof
cycles reject explicitly. Do not recursively execute/elaborate source bodies, unroll
calls, impose an arbitrary iteration budget or involve `abc-opt`.

Opaque/erased code without a sufficient contract remains unproven. Borrowed accesses
cannot cross a potentially retaining opaque boundary under an assumed harmless
signature. Reject the missing contract; do not invent retention, widen cell layouts,
run an opaque scalar algorithm or silently add a runtime ownership fallback.
Serialized/public owner-summary ABI design remains a separate gate; source imports
in this batch use their checked definitions and summaries.

### Module instance aliases

Resolve initializer bindings through the same actual-binding/instance contract used
by ordinary aliases before requesting a VM value snapshot. An alias of an existing
module instance publishes another binding to its existing logical root, not another
root/image. Preserve declaration ordering, initialization/cycle state and interface
selection. Never infer aliasing from equal bytes or a name-shaped AST alone.

A saved field read or ordinary function result remains a copied value; if it becomes
new module storage, VM computation and durable byte publication stay unchanged.
No runtime namespace, new initializer evaluator or compatibility alias mode is added.

## Components and removals

- `source_state.lua`, `semantic.lua`: authoritative context-qualified callable/holding
  facts and root-preserving global alias resolution.
- `frontend/ir.asdl` and generated schema: shared invocation/provenance summary records,
  not an alternative execution representation.
- `access.lua`, `check.lua`: summary construction/composition, state/result linkage,
  required outlives checks; remove raw cross-context slot replay and the unknown-bit
  shortcut that loses retention obligations.
- Existing module/session/layout/ABC execution remain the mechanisms. No new scalar
  evaluator/inliner, physical allocator, register placement pass, ISA/ABI reinterpretation,
  host recursion, cleanup policy or GC/counting machinery.

## Acceptance and cost evidence

- Direct and higher-order versions of the external Holder store both reject.
- Pure/nonretaining callback controls remain admitted; unknown contracts reject with
  the missing requirement rather than presumed ownership.
- Capture-before-write reference snapshots; opened live-place captures after writes;
  intervening/recursive transport; same ordinals in different contexts.
- Callable returns/aliases retain bounds; recursive invocation composition converges
  or reports an explicit unresolved proof.
- Module aliases share one root and return42 after the alias write; saved fields and
  function-return copies remain independent. Imports, repeated sessions, initializer
  cycles and failure publication preserve current behavior.
- Rerun focused and full validation in all four modes/optimized and unoptimized;
  qualify with pre-packed lowering and retain the packed float limitation explicitly.
- Measure preparation, summary/retained bytes and code/image growth. Separate measured
  costs from structural expectations; do not claim proof completion from green outputs.

The existing live-place/callable contracts govern this correction. Conservatively
rejecting all higher-order borrowed invocations would be a separate admission change,
not a substitute for implementing those contracts. No such fallback is authorized.
