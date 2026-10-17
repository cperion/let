# Source lifetime dependencies — partial continuation

Continuation of `bdec6043` under the approved O03–O08/E01/E02 scope.
This checkpoint does not implement or qualify the complete materializer.

## Changed responsibility

The existing access worklist now publishes component dependencies between original
carrier definitions, contents reads/writes, addresses, arguments, results and returns.
Dependencies are compiler records, separate from abstract query values and query keys;
there is no second source evaluator or new executable instruction. Ownership demand
templates contain these finite definition/Written/Join relations. Call arguments retain
separate alternatives; result and call-written contents edges retain their source call
identity for later contract binding. Place dependencies include the carrier protecting
the containing object, and tagged uses retain their enclosing case paths.

Open-template field reads now produce finite `ContentsInput` obligations. Their read
point, original operand and component distinguish nested reads even at one statement.
The original external activation remains attached; recursive pointee paths are not
expanded. Actual closed queries read the caller's concrete contents instead. A partial
write into an external object does not erase untouched field obligations. These names
are not proofs that repeated dynamic reads identify the same allocation or holding.

Static array components now use distinct `Borrow.Index` paths. Dynamic `Element`
locations overlap every index at that boundary. Wildcard projections merge all matching
alternatives; exact writes do not discard possibly unrelated wildcard contents. The
memory-dependency graph preserves predecessor dependencies for possibly untouched cells.
Two independently replaceable fields containing the same root remain separate source
retentions. This is not yet a concrete runtime holding layout.

Review/testing also found and corrected an existing original-definition bug: the source
builder puts memo IDs on expressions, so testing `Store.value.id` as if it were an SSA
result could overwrite a real Read definition. Definitions are now enumerated by their
actual statement kinds. Empty callable environments have explicit empty dependency
relations rather than missing definitions.

Actual implementation files: `frontend/ir.asdl`, generated
`frontend/let/schema/ir.lua`, `frontend/let/access.lua`,
`frontend/let/ownership.lua`, `frontend/tests/access_proofs.lua`.

## Validation

`check-verified.log` records the final focused checks:

- Embedded schema freshness and schema construction: pass.
- Ownership: 168 checks, 56 VM executions.
- Access: 249 checks, 120 VM executions.
- Packed tags: 1894 checks, 496 VM executions (including the reported integer subset).

The additional borrowed getter fixture executes raw and optimized in all four modes.
It saves a child, replaces the parent's field, and reads both old and current values;
all referents in that fixture remain frame-backed. This is not counted-owner execution.
New structural regressions cover external/nested/recursive field contracts, untouched
external fields after a partial write, distinct array fields sharing one root, dynamic
index invalidation and aggregate snapshots, original SSA identity, tagged component
conditions, empty environments, and argument/result dependency identities.

The two integration probes still fail at the unchanged admission gate:

- `program.log`: `ownership-materialization` at `make`.
- `source-owners.log`: `ownership-materialization` at `self_replace`.

`checks.log` preserves the earlier missing-definition-type failure. `check-final.log`
preserves the intermediate passing run before the final wildcard-snapshot regression.
No positive acceptance tests were weakened. No full suite, sanitizer, owner-count,
cleanup-storage, code-size or performance qualification is claimed.

## Still unimplemented

The dependency records are not protection certificates or lifetime actions. In
particular, `Result` and `CallContents` are edges requiring bound return/effect contracts,
not guessed guards. Guard validity, normalized alias relations, preservation/rebinding
across joins and loop reuse, capability propagation, consuming/offering/resource-slot
contracts, instance binding and physical emission still require implementation. The
six runtime bindings, ABC allocation and concrete drop generator are unchanged; the
retired blanket materializer remains removed. Live delivery status is in WORKLIST.
