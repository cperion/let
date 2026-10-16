# Production SLet source subset — implementation checkpoint

The approved target is [one collector-free Let](owners-references-ids.md), with
independent count/allocation/type facts rather than a language-level SLet/Let split.
This page records the still-current typed implementation, not the target ownership
rules. No extension compatibility or dynamic execution is implemented by changing
the design docs.

`build/abc compile file.slet -o file.abc` parses ordinary SLet source, constructs checked
ASDL `Ir.Fn`, lowers it to verified ABC, and emits a module. `build/abc run file.slet` uses
the same frontend and optimizer before execution. The filename selects the source profile only;
interpreted, eager, and lazy VM execution remain host policy.

The production path is `frontend/let/compiler.lua` and `frontend/let/semantic.lua`.
The separate bootstrap parser/typechecker/emitter has been
[retired and archived](../research/archive/bootstrap-slet-before-retirement/README.md),
not updated or wrapped as a fallback. Active source execution tests use only the production pipeline.
No source computation executes in Lua.

## Supported source paths

- Annotated words, explicit scalar or callable result contracts, direct and indirect calls,
  multiple scalar results, structured conditions, recursion, and continuation-directed tail calls.
- `U8`, `U16`, `U32`, `U64`, `I32`, `I64`, `F64`, `Bool`, `Unit`, and checked conversions.
- Named record schemas, fixed arrays, aggregate-payload sums, references, slices, strings, and
  signature/view types. Local records and arrays use checked frame storage.
- Record and array literals, field selection, nested addressable places, indexing with bounds
  checks, aliases, assignment, and compound assignment.
- Record and array arguments/results use a deterministic recursively flattened ABC call ABI.
  Pointer-free sums use their fixed packed layout across calls, including aggregate payloads.
  Materialized private owning sums now use that same tag/aligned-union layout, explicit
  address-bit casts and active-case holdings. Public/foreign packed-address sum ABIs remain closed.
- `Ref(place)`, `Slice(Array)`, slice/string indexing, and `.length`. Proven borrowed
  references use target-only transport; retained references carry data/root-owner,
  and retained slices add length. Callable transport keeps code/environment and its
  retention bound.
- Sum constructors and exhaustive keyed matching with expression-lambda handlers.
- Capture-free typed lambdas. Parameter types can come from an expected signature,
  or be written on the lambda with results inferred from its body; repeating both
  annotations is unnecessary. They lower to exact callable views and can be called
  indirectly without managed allocation. An untyped standalone lambda still rejects.
- Deterministic profile-checked imports. SLet can import only `.slet`; Let can import SLet.
- Interpreted, eager, and lazy staging produce equal results and byte-identical optimized modules
  for the covered scalar, aggregate, sum, slice, reference, and callable fixtures.

The former count-free-only restriction is superseded by the connected source ownership
binding. Supported `.slet` factories, captures, known typed partials, returned references/
slices and owning tagged payloads execute with counted concrete storage and failure cleanup.
There is no tracing collector. Counted roots allocate from creation, not by late promotion.
Unsafe access and strong cycles reject during analysis; unresolved physical contracts still
reject during materialization. `.let` executable lowering remains `dynamic-lowering`, even
where its checked source semantics are shared. See [runtime interfaces](runtime-interfaces.md#current-concrete-source-binding)
and the source-cutover/tagged-values evidence for the qualified boundary.

## Deliberate limits

Known typed runtime partials and keyed captures are qualified by `source_owners.lua`;
this does not imply every historical example or erased/dynamic callable is supported.
Persistent owning module initialization and owning public/foreign/task transport remain
closed, along with unresolved context-dependent physical instances.

This subset is not an implicit partial evaluator. Ordinary saturated calls remain residual.
`Compiler.stage` is an explicit host-selected static boundary. Automatic evaluation requires a
sound proof of totality, effect-freedom, and no language abort; purity alone is insufficient.
There is no fuel, timeout, instruction, specialization-count, or logical-allocation budget.

The live remaining work and dependencies are in [WORKLIST.md](../WORKLIST.md), not
this page's historical gap list. Generalized ownership precision, erasure/containers,
module/public/foreign/task boundaries and unified `.let` execution remain incomplete.
Unsupported checked-IR lowering reports `abc-lowering`; unsupported source construction reports
a stable source diagnostic instead of invoking another backend.

The VM and module API remain frontend-independent. `asm` accepts every instruction supported by
the selected ABC profile even when this source subset does not generate that instruction.
