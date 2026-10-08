# Frontend completion plan

## Scope and ground rules

This is the active, specification-driven backlog following the read-only audit of
`restore/fast-jit` at `2356e7e`. All implementation items below are pending.
Stable IDs F01–F18 are authoritative within this plan; session task numbers are
only convenient links. These are work packages, not single-commit requirements.
Complete each package in small, independently validated changes.

- Language contract: `syntax.md`; authoritative VM contract: `spec.md`, with the
  applicable module, memory, callable, foreign and dynamic profile documents.
- Work directly and sequentially. No subagents.
- Preserve direct native symbolic execution and copy-and-patch stencil emission.
  The live symbolic context remains native allocation state. Do not revive the
  abandoned universal residual IR, residual-ID allocator or reconstruction layer.
- Keep the banked concrete interpreter and the existing frontend checked ASDL IR.
  Shared semantics do not require a shared target-independent backend value model.
- Execute represented source computation only as verified ABC through the VM.
  Lua may handle compiler metadata, not become another source evaluator.
- Do not add a `static` keyword, invent an export section, relax lifetime rules,
  or change language semantics to make implementation easier.
- SLet borrowing and Let managed reachability are different ownership contracts.
  Blanket rejection of valid SLet captures is not the intended solution.
- Portable C remains an SLet product. Dynamic portable-C expansion, quickening
  redesign and unrelated JIT optimization are not prerequisites for this backlog.
- No semantic instruction, recursion or specialization budget. Bounded harness
  commands are operational safeguards, not source-language acceptance rules.

## Evidence and baseline

Full validation passed during the audit: 232 parser, 276 compiler, 100 lowering,
127 optimizer and 23 staging checks, plus runtime/dynamic/cache/API suites.
The log was `/tmp/abc-frontend-assessment-validate.log`; temporary logs are not
durable evidence, so F01 must capture a reproducible checked-in test inventory.

The existing suites cover substantial runtime functionality. In particular,
open-word methods and runtime keyed supply for named words are already tested;
the older gap matrix understates that progress. Do not reimplement them.

Source probes confirmed these gaps:

| Probe | Observed result | Owner |
| --- | --- | --- |
| Named `add(x: u32) = x + 1` without a result annotation | `result-type` rejection | F03 |
| Let recursive word without a result contract | `result-type` rejection | F03 |
| `identity(t: type, x: t): t = x` | `type-required` rejection | F07 |
| Computed top-level scalar or frozen word | `semantic-todo` rejection | F11 |
| Partial supply from an immutable local literal binding | `static-required` rejection | F06 |
| Local, non-escaping SLet scalar-capturing lambda | blanket `slet-forbidden` rejection | F04 |
| Lambda checked against `(): ()` | zero-result `semantic-todo` rejection | F02 |
| Unannotated Let schema field | parse rejection | F03 |
| Multi-result call used in arithmetic | `result-arity` rejection | F02 |
| Open word assigned to a record annotation | compiles, then `type-mismatch` abort | F08 |
| `any` assigned to a callable signature | compiles, then generated-bytecode validation fails | F09 |

The last two failed under all three staging policies. Managed/address-bearing
sum call ABIs also have an explicit unsupported path in `frontend/let/abc.lua`.
Deep provenance/evidence completeness is unverified; do not claim that every
such shape fails or that existing passing cases prove soundness.

## Dependency and execution order

Dependencies are prerequisites for closing a package, not a ban on writing its
reproduction tests earlier. The numbered order is a reasonable sequential route;
independent correctness fixes may move forward after F01.

| ID / task | Work package | Prerequisites |
| --- | --- | --- |
| F01 / #27 | Conformance inventory, containment and baseline | none |
| F02 / #28 | Result adjustment and unit callables | F01 |
| F03 / #29 | Result inference and Let defaults | F02 |
| F04 / #30 | SLet captures and callable ownership | F02, F03 |
| F05 / #31 | Persistent transactional staging service | F01 |
| F06 / #32 | Source binding time and known execution | F03, F05 |
| F07 / #33 | Type parameters and generic specialization | F06 |
| F08 / #34 | Open-word-to-record conversion | F01 |
| F09 / #35 | Any-to-signature conversion | F02, F04 |
| F10 / #36 | Supply, identity and freezing | F06, F09 |
| F11 / #37 | Module initialization and storage | F05, F06, F07, F10 |
| F12 / #38 | Imports, interfaces and export closure | F07, F11 |
| F13 / #39 | Deep SLet provenance | F04, F12 |
| F14 / #40 | Deep Let ownership and roots | F08, F09, F11, F12 |
| F15 / #41 | Managed/address-bearing sum ABIs | F13, F14 |
| F16 / #42 | Standard modules and program integration | F07, F12, F15 |
| F17 / #43 | Staging progress, interruption and diagnostics | F05, F06, F11 |
| F18 / #44 | Final conformance and performance acceptance | F01–F17 |

## Detailed work packages

### F01 — Establish executable conformance evidence

Primary files: `frontend/tests/`, `tools/validate*.lua`, `docs/syntax.md`.

- [ ] Build a section-by-section requirements matrix, including required negative
  tests in §§14–15. Separate supported, partial, missing and unverified behavior.
- [ ] Turn every audit probe into a minimal reproducible fixture with expected
  spec behavior. Keep known gaps explicit rather than silently accepting failures
  as correct behavior or making the normal validation command permanently red.
- [ ] Until F08/F09 land, contain accepted-but-broken conversions with precise
  unsupported diagnostics. Preserve working boxed-record and callable cases.
- [ ] Inventory missing std.* / program support and other specification examples
  absent from current tests; add discovered requirements to their owning package.
- [ ] Record clean build/validation commands, optimizer fixpoints, engine/native
  image baselines, and representative source compile/startup/runtime measurements.

Done when each audited gap has an owner and reproduction, normal validation
passes, and later changes have reproducible correctness/performance comparisons.

### F02 — Complete results and unit callables (§§4–6)

Primary files: `frontend/let/semantic.lua`, `check.lua`, `abc.lua`, compiler tests.

- [ ] Apply first-result adjustment in scalar contexts and the specified expansion
  rules in argument, binding and return lists, including explicit parentheses.
- [ ] Discard surplus results only after evaluation; apply unit padding only
  where specified. Preserve side effects and traps in discarded computations.
- [ ] Represent `(): ()` as the source unit contract, distinct from its zero-cell
  runtime ABI. Accept unit-result lambdas, indirect calls and deferred actions.
- [ ] Preserve dynamic-call missing-result checks before terminal execution.

Acceptance: direct/keyed/indirect calls, nested arithmetic, multiple results,
unit bindings and zero-cell calls agree across modes; order/trap counters detect
duplicate or skipped evaluation. The audit's unit and scalar-result probes pass.

### F03 — Complete inference and progressive defaults (§§2,4,10,15.2)

Primary files: `parse.lua`, `semantic.lua`, `resolve.lua`, compiler/parser tests.

- [ ] Infer acyclic named-word result vectors and propagate expected signatures
  to lambdas and conditional arms without arbitrary body-based parameter inference.
- [ ] Analyze residual recursive dependencies: require complete SLet contracts;
  apply Let's one-any recursive default. Reconcile all result-table constraints.
- [ ] Default exactly the specified missing Let annotations to any, including
  schema fields. Keep local binding inference and strict SLet rejection.
- [ ] Preserve forward definitions, declaration diagnostics and stable spans.

Acceptance: annotated and inferred equivalents agree; forward/mutual recursion,
multi-result inference, conflicting contracts and profile-renaming cases are
covered. Existing block-handler result inference remains passing.

### F04 — Implement valid SLet callable lifetimes (§9)

Primary files: `semantic.lua`, `analysis.lua`, `check.lua`, callable lowering.

- [ ] Distinguish owned immutable value captures from receiver/place borrows.
- [ ] Permit local/non-retaining borrowed method and closure uses; allow owned
  captures only where the specified representation and lifetime permit them.
- [ ] Retain actual receiver places and local adapters; do not silently copy state.
- [ ] Check nested captures, caller-origin views, returns, stores and invalid
  ownership erasure. Complete conditional callable joins under the §9 contract.
- [ ] Keep Let managed closure behavior separate and allocation-free SLet paths
  free of implicit managed allocation.

Acceptance: positive local/owned capture fixtures paired with escaping-borrow
and callable-erase negatives; receiver mutation remains visible through aliases.

### F05 — Establish a minimal persistent staging service

Primary files: `stage.lua`, `specialize.lua`, existing runtime host API.

- [ ] Replace per-evaluation runtime processes with explicit module/VM ownership
  and deterministic caches for verified modules and eager/lazy preparation.
- [ ] Preserve module-private images across accepted initialization steps.
- [ ] Provide disposable evaluation or rollback for speculative folds; refused
  folds must not leak writes, allocations or changed compiler-visible state.
- [ ] Encode/decode values through type/layout metadata. Preserve exact 64-bit
  bits and identities; reject nonserializable VM-local pointers and foreign effects.
- [ ] Expose only the minimal snapshot/host support required; do not build a
  second interpreter or a general allocation/reconstruction framework.

Acceptance: isolation, resource cleanup, cache reuse and state snapshots tested;
all three policies agree; compile/startup costs are measured against the bridge.
Progress/interruption polish belongs to F17, not an excuse to defer correctness.

### F06 — Connect source binding time to verified execution (§§2–4,10)

Primary files: `semantic.lua`, `specialize.lua`, `stage.lua`.

- [ ] Track known immutable values through aliases, captures and supplied
  requirements instead of recognizing only literal AST shapes.
- [ ] Distinguish mutable receiver/storage state from immutable static values.
- [ ] Route source-required known execution and selected-path checking through
  verified staging ABC; emit residual calls for runtime inputs.
- [ ] Keep optional speculative folding separate from required evaluation;
  preserve effects/traps and decline folds safely when facts are insufficient.
- [ ] Make static partial and saturated known supply share deterministic keys;
  reserve recursive specializations without semantic depth/count cutoffs.

Acceptance: local known partial supply succeeds; mutable/runtime supply follows
the correct profile rules; selected-arm diagnostics and effect order match the
spec. Artifacts are byte-identical across staging policies. No new source syntax.

### F07 — Implement generic type demands and static results (§10)

Primary files: type construction and specialization in `semantic.lua`.

- [ ] Represent `type` values as compiler metadata, never runtime ABI cells.
- [ ] Check dependent requirements left-to-right using explicit type arguments.
- [ ] Support type-producing private helpers and generic record/array/schema
  construction; execute represented computations demanded by types through F06.
- [ ] Preserve schema/callable identity and all applicable code/signature result
  contracts in specialization keys, aliases and recursive construction.

Acceptance: `identity(t: type, x: t)`, higher-order generic combinators, partial
type supply and type-producing helpers work; runtime type supply and unclosed
public ABIs reject. Equivalent specialization paths do not duplicate semantics.

### F08 — Implement structural record conversion (§15.6)

Primary files: `semantic.lua`, `abc.lua`, dynamic descriptors/runtime as needed.

- [ ] Distinguish exact boxed-record extraction from open-word structural copying.
- [ ] Resolve required fields and convert each to its declared type in the
  specified order, producing fresh record value storage.
- [ ] Support annotated bindings/parameters and type-application syntax, nested
  aggregates and managed field owners without exposing unowned borrows.

Acceptance: successful copies, missing fields, numeric/type failures and nested
managed fields across modes; later word mutation does not mutate the copied
record. Existing aggregate any round-trips remain correct.

### F09 — Implement managed typed callable conversion (§15.6)

Primary files: `semantic.lua`, `abc.lua`, callable metadata and dynamic runtime.

- [ ] Check callable/signature compatibility and produce verified adapters or
  handles rather than raw code/environment cells with invalid metadata.
- [ ] Retain Let environments through return, store and capture; lend them only
  within the non-retaining SLet call boundary.
- [ ] Preserve callable identity and check mismatches at the specified time.

Acceptance: direct, captured, open and frozen callable conversions work; bad
arity/types/results reject or abort correctly; forced collection retains owners.
Every accepted artifact passes verification before optimization and execution.

### F10 — Complete supply, identity and freezing (§§3,8,15.4–15.7)

Primary files: `semantic.lua`, `abc.lua`, existing open-word operations.

- [ ] Extend runtime keyed supply to typed indirect callables, nested words
  and methods while preserving environments and receivers.
- [ ] Verify full/partial/empty supply and saturation behavior, positional versus
  keyed requirements, extra fields, duplicate keys and source evaluation order.
- [ ] Preserve readable, non-writable supplied fields of closed words and their
  identity; runtime partial supply opens a word rather than claiming staticness.
- [ ] Make open-word supply a shallow copy with no mutation or delegation to
  its source. Preserve terminal/method receiver semantics after copying.
- [ ] Test deep/cyclic freezing, repeated freeze, readonly-field, frozen-store,
  no-terminal, key equality/order, removal/reinsertion and bounded live storage.

Acceptance: extend existing named-word/method tests rather than replacing them;
same behavior, roots and deterministic order under all runtime policies.

### F11 — Implement module initialization and durable storage (§11,15.10)

Primary files: `compiler.lua`, `semantic.lua`, `stage.lua`, module emission.

- [ ] Evaluate initializers once, eagerly in declaration order, with early
  forward demands, value-cycle diagnostics and nonexecuting word construction.
- [ ] Preserve writes made during initialization and shared imported identities.
- [ ] Emit runtime mutable module storage, relocations and trace metadata for
  typed instances and open words; serialize frozen constants safely.
- [ ] Materialize accepted initialization state without embedding host addresses.
- [ ] Reconcile source let_init/program contracts with the VM's initialized
  private image: define each boundary explicitly and avoid double initialization.

Acceptance: ordered effects, early-demand/cycle fixtures, repeated/diamond
imports, module mutation, frozen constants, GC roots and independent VM images.
Snapshots/artifacts remain deterministic across staging modes.

### F12 — Complete interfaces, exports and public ABI closure (§§8,10–11)

Primary files: `compiler.lua`, `semantic.lua`, schema/evidence metadata.

- [ ] Carry nominal schema identity, canonical requirement keys, supplied
  evidence, callable identity and binding time through aliases and imports.
- [ ] Support specified export expressions: partial selections, qualified
  aliases and receiver-bearing method entries, with all result contracts.
- [ ] Preserve initialized values needed by exported code without inventing
  new value-export syntax or implicit mutable C globals.
- [ ] Close public C ABIs; reject any and naked managed environments/addresses
  there without incorrectly banning supported dynamic VM exports.
- [ ] Retain profile direction, ambiguity/cycle errors and deterministic IDs.

Acceptance: imported nested schemas/methods and specialization contracts work;
structurally similar but nominally distinct evidence is never conflated.
Deep mutation/provenance interactions finish in F13/F14.

### F13 — Close deep SLet provenance (§§8–9,14)

Primary files: `analysis.lua`, `check.lua`, semantic evidence propagation.

- [ ] Track occurrence-sensitive owners through nested records, arrays, sums,
  stores, matches, aliases, captures, returned caller views and module storage.
- [ ] Invalidate old evidence on mutation; do not let aliases hide retention.
- [ ] Preserve valid caller-origin returns and local/non-retaining borrowing.
- [ ] Keep raw ptr host contracts distinct from checked borrow lifetimes.

Acceptance: every ownership route has a valid and invalid source fixture with
stable diagnostics; imports and mutation cannot bypass checks. Conservative
rejection of unproved cases must remain explicit in the conformance matrix.

### F14 — Close deep Let ownership and roots (§15.8–15.10)

Primary files: semantic provenance, aggregate descriptors, GC integration.

- [ ] Preserve owners through nested aggregates/sums, any, open words, closures,
  overwritten fields, calls, imports and module storage.
- [ ] Promote storage before publishing addresses and retain interior views.
- [ ] Copy/promote or reject unowned SLet/foreign returns; enforce ptr-collected.
- [ ] Audit descriptor roots: trace managed addresses/environments, not code
  pointers or raw ptr payloads. Preserve allocating-call root visibility.

Acceptance: collection-pressure and host-request tests exercise every deep
ownership route in all modes, including aliases, mutation and cross-profile calls.
Allocation-free regions keep their existing collection-boundary contract.

### F15 — Complete managed/address-bearing sum ABIs

Primary files: `abc.lua`, checked layouts, verifier/runtime metadata if needed.

- [ ] Replace the explicit unsupported aggregate-sum ABI with defined argument,
  return and copy layouts carrying tags, owners and trace information.
- [ ] Cover nested sum/record/array payloads containing refs, slices and callables.
- [ ] Support direct/indirect/tail calls, multiple results, joins and mutation.
- [ ] Extend only necessary backend metadata/operations. Preserve direct native
  emission and avoid detached native allocation or generic value reconstruction.

Acceptance: all alternatives, nested copies, returns and forced collections
agree across policies; malformed metadata fails verification; optimizer output
is stable and supported SLet portable-C cases remain correct.

### F16 — Close standard-module and program integration (§§8.7,11)

Primary files: source module resolver, CLI, bundled source modules and tests.

This is a specification integration inventory as well as implementation work:
the audit found std.* and program requirements in the contract but did not
establish a complete implementation. Reuse working support where present.

- [ ] Inventory std.bytes, memory, text, stream, file, terminal and program.
- [ ] Resolve the reserved namespace deterministically; no relative-file fallback.
- [ ] Compile standard source through the production frontend and VM staging.
  Migrate appropriate reference fixtures, never the legacy Lua evaluator.
- [ ] Implement specified program startup/main ABI and initialization hooks.
- [ ] Test checked scoped-resource interfaces, normal-completion cleanup,
  error precedence and non-unwinding aborts without introducing ownership types.

Acceptance: documented source examples compile/run with fixed results, both
profiles respect import/ownership boundaries, and CLI/library emission agree.

### F17 — Complete staging diagnostics and interruption (§10)

Primary files: `stage.lua`, host integration, source/provenance mapping.

- [ ] Report delayed progress with active binding and source position.
- [ ] Report externally interrupted static call stacks with source positions.
- [ ] Preserve provenance through optimization, specialization and imports.
- [ ] Distinguish source aborts, actual resource exhaustion and compiler bugs.
- [ ] Clean up cancelled VM/cache state; refused folds never leak writes.

Acceptance: deterministic diagnostic codes/spans, abort and foreign-effect
tests, controlled interruption tests, and no semantic fuel/time budget.

### F18 — Final acceptance and documentation closure

- [ ] Close all required conformance rows; record unresolved blockers explicitly.
- [ ] Run clean builds and whole-system validation, not only frontend unit tests.
- [ ] Compare all three staging policies and all three residual runtime policies
  for representative new families: results, traps, effects and byte-identical
  artifacts. Keep optimizer growth/fallback/fixpoint checks.
- [ ] Run supported portable-C fixtures and real source/standard-library examples.
- [ ] Measure engine runtime, compilation/startup, image size and source workloads
  against F01 with repeated trials; investigate regressions rather than hiding
  them in noise or accepting correctness as sufficient.
- [ ] Update `slet-subset.md`, `frontend-gap-analysis.md`, `remaining-work.md`,
  examples and user-facing claims; leave language contracts unchanged unless a
  separately approved language decision requires it.

## Definition of done for every implementation package

1. Spec-linked positive and negative fixtures, including effects and traps.
2. Independent verification of every accepted generated module.
3. Correct profile-specific lifetime/GC/ABI behavior; no hidden raw roots.
4. Deterministic output and optimizer fixpoints; relevant cross-mode checks.
5. Full validation passes; clean milestone build and benchmark comparison.
6. No unexplained native runtime, emission or compilation regressions.
7. Updated conformance/status docs and a small, reviewable implementation diff.

Planning does not mark any feature complete. If a prerequisite reveals another
semantic gap, add a bounded child task under its owner instead of silently
expanding the native backend architecture or lowering the acceptance bar.
