# Executable typed source subset

This page is an admission guide, not a second language specification or status ledger.
The approved target is [one collector-free Let](owners-references-ids.md); the current
`.slet` execution / `.let` lowering-rejection boundary remains until WORKLIST U is
implemented. Changing a filename does not open dynamic or owning interfaces.

`build/abc compile file.slet -o file.abc` and `build/abc run file.slet` use the production
`frontend/let/compiler.lua` / `semantic.lua` pipeline, checked ASDL IR and verified ABC.
The retired bootstrap compiler is not a fallback. Interpreted/threaded/eager/lazy are
host execution policies; no source computation executes in Lua.

## Admitted paths

- Typed words, contextual or explicit lambda signatures, direct/indirect calls,
  multiple results, structured conditions, recursion and explicit ABC continuations.
- Integer widths, F64, Bool, Unit and checked conversions; records, fixed arrays,
  sums, borrowed references/slices, strings, raw pointers and checked callable views.
- Literals, fields, addressable parts, checked indexing, aliases, assignment and
  compound assignment; schema methods, keyed matching and supported borrowed captures.
- Deterministic typed imports, source-only rest/templates, supplies/spread and
  live-place vocabulary/receiver scopes. Existing profile-direction restrictions
  remain: SLet imports `.slet`; Let can import SLet.
- Explicit `Rc(value)` and named `r.borrow()`, retain-on-copy, nested owning fields,
  fixed arrays/active sum cases and private direct owning inputs/results. Invalid
  Ref escape or loss of protection rejects; borrowed fields never become holdings.
- Ordinary nonowning aggregates retain their flattened/packed ABI. Owning private
  values use cleanup-visible typed slots. Tags/aligned unions and address-bit casts
  remain canonical; no alternative sum representation or runtime layout interpreter.
- Required static demands under explicit host policy and supported pointer-free
  aggregate/module snapshots through the VM staging service.

Exact semantics are in [syntax](syntax.md) and [ownership](owners-references-ids.md);
private representation is in [runtime interfaces](runtime-interfaces.md#3-explicit-rc-layout-and-private-handoff).
The source/native ownership suite exercises admitted Rc scenarios rather than
expecting the removed implicit-promotion materializer to run.

## Closed boundaries

Owning public/foreign/erased transport, owning callable environments/results,
persistent owning modules, task/container ownership and public packed-address sum
ABIs remain gated. Rc payloads initially exclude stored Ref/Slice, callable and
erased values. Borrows cannot become safe merely by being placed inside Rc.

`.let` executable lowering still reports `dynamic-lowering`. Staging rejects foreign
execution, including lifetime bindings; runtime Rc support is not owning snapshot or
compile-time Rc allocation support. Address-bearing snapshots require real lifetime/
relocation contracts, not copying pointer bits. See [source compilation API](source-compilation-api.md).

Ordinary saturated calls are not automatically executed merely because they are pure.
Optional evaluation must preserve errors/effects and requires the approved proof;
required static demands must actually succeed. No source instruction fuel, timeout,
specialization-count or logical-allocation budget is introduced.

[WORKLIST](../WORKLIST.md) records qualification, costs and remaining interfaces.
Unsupported source/IR rejects explicitly, not through an alternate backend. The VM
and module API remain frontend-independent: `asm` accepts supported ABC instructions
whether or not this source subset emits them.
