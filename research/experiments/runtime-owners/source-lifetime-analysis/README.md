# Source lifetime analysis checkpoint

This is partial implementation of the approved source-lifetime binding under
WORKLIST O03–O08/E01/E02, not qualification of the replacement materializer.
The original specification checkpoint is `ecb4271d`; approval and same-call loan
identity clarification are separate in `37e72bf0`.

## Implemented boundary

`Access.analyze` now returns program-owned original-site flow as its fourth result.
Its existing query worklist publishes the final local observations, original operand
and statement identities, call-context edges, reads/writes, retention destinations,
read-location/provenance alternatives and unresolved-call information. Query objects
are not exposed as call edges. The original source graph remains unchanged.

Reference contents have finite Entry/Written/Join identities and separate incoming
version edges. Every known-location write is an invalidation, including reuse at the
same static loop point. Raw pointer contents do not become checked lifetime loans.

`Program.analyze` passes the flow to `Ownership.analyze`, which produces explicitly
`loan-demand`-phase templates: backward carrier/contents demand, edge-specific join
version substitution, and containing-root demand for scalar place accesses. Same-call
results retain their original value-binding IDs. Direct address results demand their
root even without an intermediate SSA carrier. Scalar-only code needs no loan demand.
These templates are not protection witnesses or physical lifetime decisions.

The CFG now retains success edges of conditional traps (including constant false),
while constant-true traps terminate normal flow. A new regression verifies that a
false trap cannot hide a subsequent escaping source self-cycle.

## Checks

`check-final.log` records:

- Embedded schema freshness and schema construction: pass.
- Ownership: 168 checks, 56 VM executions.
- Access: 213 checks, 112 VM executions.
- Packed tags: 1894 checks, 496 VM executions (includes the reported integer subset).

New analysis regressions cover original-node/operand identity, saved reads across
replacement, branch and loop contents versions, per-edge demand, conditional traps,
post-trap cycle rejection, scalar referent accesses, direct root-address returns,
distinct results from one call, substituted call writes, dynamic index operands,
read alternatives tied to their own field locations, and untracked pointer transport.
`checks.log` preserves the earlier run before the final pointer-only regression.

The integration probes still FAIL, as recorded separately:

- `program.log`: `ownership-materialization` at `make`.
- `source-owners.log`: `ownership-materialization` at `self_replace`.

These are positive acceptance tests left intact; no expected-success case was changed
to accept rejection. No full suite, sanitizer run, new source-owner runtime execution,
allocation/count measurement or performance qualification is claimed.

## Remaining boundary

The materializer has not been restored or replaced. The existing executable admission
gate remains. No runtime ABI, owner implementation, allocator or backend was changed.

Still required before physical emission: guarded loan alternatives and enclosing tag
conditions; source loan dependencies through storage/results; normalized may-alias
invalidation and usable locator proofs; capability demands and preservation actions;
recursive private contract binding; concrete layouts/holding slots; consuming/offering
and result-slot transport; cleanup/transaction emission and end-to-end qualification.
Current version invalidations cover matching physical target roots and the existing
conservative Element class, not a completed bound alias proof or independent concrete
array-field holding layout. Do not use absent demand/edges as an ownership proof.

A targeted source probe also confirmed the pre-existing external-field contract gap:
`child(p: Ref(Box)): Ref(Point) = p.child` with `Box.child: Ref(Point)` still rejects
with `borrow-proof` when analyzed as an open formal template. The approved relative
field-content contracts must resolve that gap without guessing a counted ABI or
expanding recursive input paths without a finite binding discipline.
