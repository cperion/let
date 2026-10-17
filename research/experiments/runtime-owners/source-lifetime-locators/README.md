# Temporal locators, snapshot demands and allocation-site reuse — partial

Continuation of `e52f9837`, within the approved O03–O08/E01/E02 scope. WORKLIST is
still the delivery ledger. This does not complete source-to-physical lifetime lowering.

## Implemented boundary

`frontend/let/ownership.lua`:

- Bound loan contexts now have normal-CFG predecessor and SCC information. No source
  scalar expressions are evaluated, no checked IR is changed, and no depth/iteration
  budget is introduced.
- `locators(contracts)` retains the original operand/component, pointer-load and index
  definition dependencies, and separate contents witnesses for each read alternative.
  Must availability meets predecessor paths; may availability finds possible losses.
  A source read repeating in an SCC remains distinct from its previous occurrence even
  when both old operand/contents availability have already been killed.
- `sameLocator` proves a temporal equality prerequisite for a direct destination,
  after its operands/checks have been evaluated. It does not prove an actual holding,
  a live containing allocation, permission to consume a field, or identity with an
  older loop-carried occurrence. Captured addresses are not permission to reread a
  changed index/base or a cleared owner slot. Environment locators needing a bound
  layout remain unresolved.
- `snapshotDemands` follows original carrier/contents dependencies and input-relative
  call substitutions to intersect possible snapshot losses with live-out loans. It
  keeps logical bindings distinct at source-site reexecution. Calls never offer an
  exact pre-entry field move merely because they publish a write. Unknown effects
  propagate through known wrappers; missing writes are not a no-mutation proof.
- These are `source-locators` and `snapshot-demands`, not completed guard certificates
  or executable Acquire/Transfer decisions. An independent existing holding can still
  discharge a demand; a source cell need not contain a holding at all.
- `reuseRequirements` finds carriers still observable after reinitialization of their
  allocation site. Such frame addresses cannot be repaired by retaining after reuse:
  their roots require counted placement from creation. Positive-length CFG reachability
  and original carrier demand distinguish this from ordinary current-iteration access.
- Strengthened requirements go through the existing ownership solver. Counting an
  aggregate revisits its retained targets and can invalidate former frame-only cycle
  proofs. The original checked summaries remain unchanged. Result-site reuse records
  obligations, not invented resource slots; borrowed identity results have none.
- Unresolved reference/InPlace/erased callable interfaces remain obligations instead of
  invented placement decisions. Scalar-only callback signatures do not invent an
  owning interface. Bound input substitution is shared with capability propagation.

`frontend/let/layout.lua` now delegates temporary borrowed admission to
`Ownership.requireBorrowed`. Removed the old count-only admission loop from layout.
Newly required counted roots and unresolved reuse bindings cannot silently compile as
borrowed frame storage. Admission also considers affected callers, so counting a
callee's object cannot conceal a newly exposed caller cycle. Ordinary current-iteration
frame access remains admitted. The existing broad counted-source gate remains closed;
this is not the final rooted instance-selection/materialization implementation.

## Evidence

`check-verified.log` records the final production-code focused run:

- Embedded schema freshness and schema construction: pass.
- Ownership: 168 checks, 56 VM executions.
- Access: 354 checks, 120 VM executions.
- Packed tags: 1894 checks, 496 VM executions, including its integer/storage subset.

`access-final.log` adds the final caller-cycle regression: **356 checks, 120 VM
executions**. Only tests/documentation changed after the full focused run. `checks.log`
and `check-integrated.log` preserve earlier passing checkpoints of this continuation.
`git diff --check` also passed.

Coverage includes direct/dead snapshots, branch meets, separate read alternatives,
mutating helpers and unresolved callback wrappers, static/wildcard array overlap,
distinct dynamic indices, captured indices versus reexecuted index definitions,
changed bases, false traps, loop-carried snapshots, input-relative identity forwarding,
a counted saved-child source fixture, frame-address promotion, retained-target
propagation, concrete self/caller cycles, result-slot reuse obligations and unchanged
ordinary frame/scalar-callback admission. Tests distinguish original operands when a
single statement contains multiple nested reads.

Integration probes still fail at the existing boundary:

- `program.log`: `ownership-materialization`, function `make`.
- `source-owners.log`: `ownership-materialization`, function `self_replace`.

The rejection now passes through ownership's admission check. No positive execution
acceptance fixture was weakened or changed into an expected rejection.

## Not completed

Actual independent guard/holding selection and containing-root protection; preservation
and rebinding actions across joins/reuse; normalized consume/offer/result-slot and
call-effect contracts; concrete recursive instances/layouts; physical emission and
consumer migration; end-to-end counted-source qualification.

No new source-owner execution, full suite, sanitizer, exact count traffic, cleanup/code
size, peak-owner-byte or performance qualification is claimed. The six C bindings,
allocator/backends and packed representation are unchanged. No blanket ownership
materializer, runtime registry or compatibility dispatch was restored.
