# Pointer-free module aggregates and access proofs — WIP

Approved bounded batch; **not a completed ownership/access-proof fix**. All work
remains local. Counted/frozen owners, address relocation and collector retirement
are separate incomplete work. Packed float arithmetic remains paused/unresolved.

## Working implementation

- `layout.lua` is the shared existing layout/ABI definition; `snapshot.lua` copies
  pointer-free ABI products to/from durable byte strings. Source computations run
  only in the VM. Narrow sign extension here is representation transport.
- Canonical ASDL supplies durable `Ir.Bytes`, module roots/data and explicit address
  access permissions. Regenerated schema output accompanies the definitions.
- Module initialization uses ordered VM fragments and accepted compiler-owned root
  bytes. Residual modules receive those bytes. Opening and chained aliases project
  the same root. Failed calls/results/image copies publish no accepted state.
- `abc_vm_read_image` copies an established loaded image, without executing, loading,
  relocating pointers or creating source owners. Four-mode API checks cover exact
  copies/guards, null arguments, bounds/overflow, end-of-image zero length, unloaded
  identity and output preservation on failure.
- User approved rejecting unsupported frame-root escapes in both profiles. Tests
  no longer use presumed managed retention to justify returned local references,
  slices, aggregate-wrapped borrows, methods or frame-backed environments.
- Access facts use existing Borrow nodes. Structured state joins/loop fixed points
  preserve saved reads; direct calls substitute permissions, effects, retained-store
  relations and outlives bounds. Opaque outputs cannot manufacture borrow provenance.
- Aggregate-only float signatures now select their correct existing ABI profile.
  Zero-width unit reads/stores preserve index checks through the shared bounds guard.
  Module roots reserve a distinct addressable byte even when their value is zero
  width; this is persistent root storage, not operand scratch or a new allocator.

## Current evidence

`validation-wip-2.log`: full command exits0:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

- Aggregate staging: **337 checks /326 executions**. Four static modes × four
  execution modes × optimized/unoptimized for source roots; exact typed snapshot
  argument/output/specialization roundtrips cover mixed widths, signed cells, unit,
  negative zero, NaN payloads, arrays and integer-/floating-payload tagged bytes.
  Raw tagged-byte roundtrips are not packed float extraction/arithmetic validation.
- Access proofs: **101 checks /64 executions**. Escapes, transitive stores, branch
  joins, saved reference snapshots, module/parameter controls, readonly acquisition,
  lexical receivers, schema methods, opaque results and unchecked recursive pointers.
- Compiler270, receiver407/384, lambda269/80; demand52 and session280 regressions pass.
- `tools/validate_api.c` image-copy checks run in all four execution modes.
- Both new focused suites are integrated into `Makefile`.

`validation-wip.log` preserves the initial lowering-suite failure: an old positive
managed-IR fixture returned a frame-backed adapter. It is now an explicit
`borrow-return` negative control; independent nonescaping dynamic IR still checks
and rejects at its existing `dynamic-lowering` boundary.

`focused-wip.log` and `admission-blocker.log` are earlier evidence (128/128 aggregate
probes and the originally positive local-reference fixture failure), not current
acceptance claims. Do not overwrite them to make historical evidence look green.

## Architectural blocker despite green validation

`higher-order-retention.lua` / `.log` reproduce a real admission hole:

```
saved()       REJECT [borrow-store]
apply(saved)  ACCEPTED (missing retention proof)
```

The callback stores a reference to the caller's local Point into an externally
borrowed Holder. Direct substitution catches it. The generic `apply` summary marks
unknown may-access effects but loses the supplied callback's retained-store bounds.
Unknown effects are therefore not a sufficient lifetime contract. This batch must
not be called complete or safe merely because the current full suite passes.

`module-alias.lua` / `.log` expose a second producer/contract defect: top-level
`let alias = original` creates two module roots, returning40 rather than42 after
an alias write. Passing *local* alias controls do not qualify module initializer
aliases. The global initializer currently demands copied aggregate bytes before
preserving the original binding's instance identity. Root aliases must be resolved
at the binding/value contract; field reads and function returns remain value copies.

These are conformance defects under the already documented live-place, shared-root
and callable-environment contracts, not missing language-design approval.
[The findings](../../../../docs/actual-binding-access-conformance.md) retain the defect
analysis; their former new-proposal status is withdrawn. Correction is in progress:
preserve formal invocation obligations and instantiate the actual
word's complete capture/retention summary at the calling site, with context-qualified
identities and frozen value captures versus retained live places. No source-body
replay, new evaluator/inliner, fake retention, runtime fallback or counted-owner
scope expansion is justified. Conservative rejection of all such unknown calls is
an alternative admission change to discuss, not a silent compatibility policy.

## Subsequent conformance checkpoint

`focused-conformance-3.log` records aggregate438/422 and access120/80. The preceding
conformance-2 run also records receiver407/384, vocabulary92/64, compiler270,
lambda269/80, demand52 and session280.
`validation-conformance-3.log` is full validation, exit0. Earlier conformance logs
remain historical checkpoints. The final access fixture covers an opaque concrete
view result: `borrow-proof`, not a crash accessing nonexistent `stmt.signature`. Module aliases now return42
with one root. The integrated tests assert root identity and preserve field/return
copies and zero eager local-alias reads. Concrete view holdings contain qualified
place routes or frozen value facts, not raw cross-context IR slots; code identities
are component-indexed. Saved reference and live opened reference controls execute
in all four modes with optimization enabled/disabled. A cyclic checked-IR fixture
qualifies finite holding-graph analysis; it does not execute loop-carried frame-backed
environments or establish their storage-reuse/lifetime safety.

At that historical checkpoint, the reproducer **still accepted `apply(saved)`**. That checkpoint does
not close formal callable/result transport, ordered invocation-state composition or
the physical-target/retained-owner domain audit. No new design approval is being
requested for the already settled live-place semantics. No timing, clean-build,
sanitizer or complete-proof claim.

Initial new test-fixture runs failed on an ungrouped nullary word within an opened
receiver scope, inspection of a nonexistent `unit.globals` API, and use of unavailable
Let dynamic lowering. Fixtures were corrected to grouped invocation, structural IR
inspection and the existing typed SLet ABC execution binding, respectively. A draft
cyclic fixture used unsupported `while` syntax; it was replaced with the existing
structured IR loop, without adding or claiming source grammar support.

## Ordered-composition correction

The user-approved correction now makes `saved()` and `apply(saved)` both reject
`borrow-store`, including forwarding, returned callable identities, components,
recursive wrappers and trailing-block sugar. Safe callbacks still execute; live
invocations between stores and frozen snapshots have opposing controls. Physical
targets are separate from retained loans; opaque missing contracts reject.
Access176/112 and full validation pass. See
[ordered-composition evidence](ordered-composition/README.md) for exact scope,
failed attempts and the measured analysis CPU/allocation regression.

Remaining: broader recursive/alias/unknown-contract acceptance, publication/resource
qualification, preparation efficiency, clean/sanitizer and pre-packed isolation.
No complete ownership-runtime or pushed-change claim is made.
