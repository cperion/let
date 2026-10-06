# Production SLet source subset

`build/abc compile file.slet -o file.abc` parses ordinary SLet source, constructs checked
ASDL `Ir.Fn`, lowers it to verified ABC, and emits a module. `build/abc run file.slet` uses
the same frontend and optimizer before execution. The filename selects the source profile only;
interpreted, eager, and lazy VM execution remain host policy.

The production path is `frontend/let/compiler.lua` and `frontend/let/semantic.lua`.
`tools/slet_frontend.lua` remains a bootstrap validation oracle and is not a fallback.
No source computation executes in Lua.

## Supported source paths

- Annotated words, explicit scalar or callable result contracts, direct and indirect calls,
  multiple scalar results, structured conditions, recursion, and continuation-directed tail calls.
- `u8`, `u16`, `u32`, `u64`, `i32`, `i64`, `f64`, `bool`, `unit`, and checked conversions.
- Named record schemas, fixed arrays, aggregate-payload sums, references, slices, strings, and
  signature/view types. Local records and arrays use checked frame storage.
- Record and array literals, field selection, nested addressable places, indexing with bounds
  checks, aliases, assignment, and compound assignment.
- Record and array arguments/results use a deterministic recursively flattened ABC call ABI.
  GC-free sums use their fixed raw layout across calls, including aggregate payloads. Managed or
  address-bearing sum ABIs remain conservative rather than hiding roots in raw cells.
- `ref(place)`, `slice(array)`, slice/string indexing, and `.length`. References and views use
  the checked address-then-length ABI where applicable.
- Sum constructors and exhaustive keyed matching with expression-lambda handlers.
- Capture-free typed lambdas. They lower to exact callable views and can be called indirectly
  without managed allocation.
- Deterministic profile-checked imports. SLet can import only `.slet`; Let can import SLet.
- Interpreted, eager, and lazy staging produce equal results and byte-identical optimized modules
  for the covered scalar, aggregate, sum, slice, reference, and callable fixtures.

Every accepted SLet program is also accepted as Let with the same observable behavior. SLet
never permits `any`, a managed capture, managed allocation, or a GC root. A lambda that captures
a local value therefore rejects with `slet-forbidden`. Returning a reference or slice of current
invocation storage rejects with `borrow-return`; the corresponding Let source promotes the backing
record or array into managed storage.

## Deliberate limits

This subset is not an implicit partial evaluator. Ordinary saturated calls remain residual.
`Compiler.stage` is an explicit host-selected static boundary. Automatic evaluation requires a
sound proof of totality, effect-freedom, and no language abort; purity alone is insufficient.
There is no fuel, timeout, instruction, specialization-count, or logical-allocation budget.

The remaining source gaps are recursive type cells, schema methods, nested word declarations,
keyed word requirements/supply, raw-pointer constructors, `extern`, `defer`, general block-bodied
lambdas, managed/address-bearing sums across function boundaries, type exports, non-literal module
initialization, and complete source-level lifetime/provenance analysis.
Unsupported checked-IR lowering reports `abc-lowering`; unsupported source construction reports
a stable source diagnostic instead of invoking another backend.

The VM and module API remain frontend-independent. `asm` accepts every instruction supported by
the selected ABC profile even when this source subset does not generate that instruction.
