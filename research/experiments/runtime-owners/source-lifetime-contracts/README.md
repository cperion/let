# Call-relative loan binding and capability requirements — partial

Continuation of `5c5b0815` under the approved O03–O08/E01/E02 replacement.
WORKLIST remains the delivery ledger. This is not completed source-to-physical lowering.

## Implemented

`frontend/let/ownership.lua`:

- `bindLoans(checked_program, entries)` creates a finite, entry-rooted graph of the
  existing source loan/contents dependencies. It never calls Access.analyze, changes
  checked IR, or evaluates scalar expressions. Original contexts, points and operands
  remain explicit. These contexts are not finalized machine-instance identities.
- A call retains its own argument-alternative substitution and callee entry/return/exit
  bindings, even when Access reused one query for two calls. Parameter guards are not
  flattened into an uncorrelated union of the callers. Join edges retain predecessors.
- `capabilities(contracts, requests, supplied)` computes finite recursive relative
  origin requirements. Input-origin results recover capabilities through the original
  caller argument, rather than demand a capability cell in a read-only identity ABI.
  Actual callee-local origins require a result/exit contract; they cannot be recovered
  from an expired activation. Supplied capability sources stop further propagation.
- Unresolved callable/entry obligations are retained, including behind multiple result
  boundaries. Empty origins/demand are not protection, ownership or null-capability
  proofs. The returned phases are `loan-contracts` and `capability-demands`, not completed
  bound instances. Supplied sources still require validation by the protection solver.
- Nested active-case requirements are ordered outermost first.

`frontend/let/access.lua`:

- Returned reachable aggregate construction publishes a possible contents write, even
  when a loop reuses the static source identity. The source worklist propagates these
  effects monotonically. It does not invent caller Entry contents for a freshly
  constructed returned object.
- Caller/callee contents-version domains close over external locations and relevant
  downstream projections. A forwarding function can bind a field it never directly
  reads; a caller's wildcard array projection can bind to the callee's construction.
- Materialized captures are constructed in the actual query's environment state and
  read at invocation through the original callable operand. Their code identities own
  capture shape only. Removed the code-global materialized capture-value union and its
  redundant transport path; it was both wrong for query-specific snapshots and caused
  excessive convergence feedback. Nonmaterialized source partial-application analysis
  remains separate and unchanged; no dynamic runtime engine was restored.
- InPlace root dependencies are explicit. Interior/place-address results can recover
  their capability from the caller instead of appearing to allocate in the callee.
- Canonical access-set unions reuse their existing keys. Immutable source identity
  serialization uses weak-key caching; neither changes identity or permission semantics.

`frontend/tests/access_proofs.lua` covers these boundaries, including distinct captures
in different queries sharing one code identity, recursive capability convergence,
callee-only field reads, wildcard returned contents, tagged condition order, unknown
call contracts, and absence of synthetic lifetime nodes for scalar-only binding.

## Checks and diagnostics

Final focused results in `check-verified.log`:

- Embedded schema freshness/construction: pass.
- Ownership: 168 checks, 56 VM executions.
- Access: 302 checks, 120 VM executions.
- Packed tags: 1894 checks, 496 VM executions (includes its integer/storage subset).

`checks.log` and `access-final.log` preserve earlier passing runs before the final
capture-isolation regression and convergence correction.

Integration is still incomplete:

- `program.log`: unchanged `ownership-materialization` rejection at `make`.
- `source-owners-bound-environments.log`: unchanged rejection at `self_replace`.

The intermediate source-owner attempt timed out in a combined 120-second command;
its `source-owners.log` is empty. Subsequent standalone 120-second attempts likewise
left `source-owners-final.log` and `source-owners-converged.log` empty. The diagnostic
hook logs (`source-owners-probe.log`, `source-owners-contexts.log`,
`source-owners-phase.log`) preserve stack/context samples and intentional diagnostic
CPU-limit failures. Those limits exist only in the diagnostic commands, not in the
compiler or its worklists.

For isolation, a read-only copy of the parent revision's access module was loaded in a
fresh Lua process against the same source-owner fixture/current remaining modules.
`source-owners-baseline.log` records reaching the gate in 37.74s wall / 35.79s user.
After removing code-global materialized capture state and correcting the actual
producer/consumers, the final probe reached it in 17.71s wall / 15.94s user. These are
single-run analysis diagnostics, not controlled compiler benchmarks or runtime
performance/owner-count results.

No positive acceptance tests were weakened. No new counted-source execution, full
suite, sanitizer, allocation/count traffic, cleanup-size, code-size or peak-owner-byte
qualification is claimed.

## Remaining boundary

These tested solver components do not replace Ownership.bind or Placement.program.
The compiler still needs concrete guard validity and alias proofs, preservation and
rebindings through joins/loop reuse, capability seeds/resolution from actual lifetime
actions, consume/offer/result-slot contracts, normalized recursive machine instances,
and physical emission/consumer migration. The six C bindings and ABC allocator are
unchanged, the blanket materializer stays removed, and counted-source admission stays
closed until integration. Source origin edges cannot stand in for those proofs.
