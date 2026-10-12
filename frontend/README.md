# Reused Let frontend

This directory is an intentional, self-contained snapshot of the reusable frontend from the former Wordlet compiler. It is the starting point for the complete ABC frontend. The project must adapt this code instead of rebuilding the language grammar and structured representations from scratch.

## Included

- `ast.asdl` and `ir.asdl`, with their generated Lua schema modules.
- The ASDL runtime and list implementation under `vendor/`.
- Diagnostics, lexer, parser and AST reflection.
- The explicit-profile compiler entry point in `let/compiler.lua`.
- Semantic type and structured-IR helpers, plus the reused structural/type verifier in `let/check.lua`.
- Schema-driven traversal, lexical capture resolution and typed-IR analysis.
- The production typed-IR backend in `let/abc.lua`. It lowers the implemented scalar boundary to verifier-accepted ABC instead of evaluating it in Lua.
- The in-process VM-backed static execution bridge in `let/stage.lua`. It assembles and verifies the same lowered artifact, owns VM/module sessions under an explicit host-selected policy, and returns exact scalar cells and supported pointer-free aggregate byte images. It does not execute source operations in Lua.
- Parser/schema/traversal/compiler/lowering/staging tests and the SLet source examples.

**Design direction:** [one collector-free Let](../docs/owners-references-ids.md)
replaces the proposed SLet-borrow/Let-GC semantic split. It is not implemented;
the API/profile descriptions below record the current typed checkpoint.

These suites are part of `make validate`. `let/compiler.lua` selects Let or SLet explicitly, builds the ASDL AST, enforces profile restrictions and indexes module declarations. `Compiler.typed` constructs verified semantic `Ir.Fn` for either language, including Let dynamic operations and captures. `Compiler.typedFile(path, options)` constructs a profile-checked import graph; required static demands can generate and execute verified ABC under `options.staticMode`; it returns `phase="typed-ir"`, the root `Unit`, dependency-inclusive `functions`, `foreigns` and `modules`, with deterministic private identities.

**Executable lowering currently supports SLet only.** `Compiler.compile` and `Compiler.compileFile` carry SLet IR through the shared revision-6 ABC backend. The latter consumes the same `typedFile` import graph; there is no second import pipeline. Let ABC lowering reports `dynamic-lowering` even for scalar-only Let programs—it does not silently reinterpret Let as SLet. The obsolete profile-5 text emitter, managed descriptors and A-only dynamic instruction emission have been removed. Parsing/typechecking/IR tests are not evidence of dynamic runtime support.

`build/abc compile/run` therefore execute `.slet`, not `.let`, at this checkpoint. `Compiler.stage` executes supported entries only through `abc_vm` under an explicit interpreted, threaded, eager or lazy policy; `Compiler.specialize` re-enters ordinary IR and the C optimizer with typed cells returned by staging. Cells, aborts, resource failures, source maps and optimizer provenance return to the compiler. Unsupported forms reject explicitly, rather than executing through Lua or another backend. The current full suite passes, but the access-proof batch remains incomplete; see its higher-order retention blocker below.

## Lambda signatures stated once

A capture-free lambda can take its types from context, or declare its parameter
types and infer its results from the body:

```let
let add: (U32, U32): U32 = do(a, b) = a + b
-- Alternatively:
let add = do(a, b: U32) = a + b
```

A typed callable parameter also supplies context for an unannotated lambda.
Nullary lambdas need no parameter annotations. In SLet, missing parameter types without
context reject; in Let, both named and literal words use the ordinary `Any` default.
Neither spelling guesses numeric types or implicit generics from operators.
Result inference uses the existing return-contract rules, including supported
block and multiple-result bodies. Explicit conflicting annotations still reject.

The same inference constructs Let semantic IR, but executable validation is SLet
only. Materialized captures remain conservatively rejected in SLet for both spellings;
direct known calls use ordinary frame transport. No Lua source evaluator or new callable
representation is introduced. Tests require equivalent annotations to emit identical assembly.

Named declarations and literal-do bindings now share one word contract/body elaborator,
including recursion, result inference and exports. `oneof { ... }` is reserved syntax;
other headed braces supply values, with `name(params) = body` as lambda-entry sugar.
See [word-bindings.md](../docs/word-bindings.md) for the precise contract, keyed-literal
grammar gap, capture limits and sum-handler code-size implications.

## Owned VM staging sessions

`require('let.stage').open{mode='interpreted', optimize=false}` creates a session;
`threaded`, `eager` and `lazy` select the other VM policies. `optimize` defaults to true;
false does not load or invoke `abc-opt`. The separate runtime binding loads
`build/libabc.so` (override with `ABC_RUNTIME_LIBRARY`), not the optimizer library.

```lua
local session = require('let.stage').open { mode = 'interpreted', optimize = false }
local ok, result = pcall(function()
    local program = session:prepare(artifact, functions)
    -- artifact is ordinary ABC.lower output; functions supply its checked types.
    return program:call { entry = 'main', arguments = {} }
end)
session:close() -- also on errors; closing twice is safe
if not ok then error(result, 0) end
```

Reuse a prepared program for persistent image state. Preparing identical bytes
again creates a distinct module identity; separate sessions also isolate images.
VM aborts reset stacks but **do not roll back prior image writes**. Use a disposable
session for speculative work. The bounded working-tree module extension publishes
compiler-owned root bytes only after successful result/image transport; it does not
make public VM calls transactional.

Program calls cannot change session policy, reenter the same VM, or close it from
a progress callback. Closed handles reject. `Compiler.stage` and `Stage.execute`
remain one-shot conveniences that prepare, call and close on every exit, using
this same service; their former subprocess path is removed. The obsolete `runtime`
executable option now rejects explicitly. VM errors retain structured status,
reason, bytecode/optimizer provenance and source spans without parsing CLI text.

Transport is exact integer/bool/f64 raw cells; unit has no physical cell. Float
arguments use IEEE-754 bit patterns, not host numeric conversion. Supported pointer-free
record/array/sum snapshots use `{type=Ty, image=bytes}` through the same existing ABI;
raw `cells` remain available. Borrowed-input/address-result and callable-environment
snapshot transport reject explicitly. See [the image-copy contract](../docs/module-image-copy.md). Foreign effects
remain unavailable. The VM's existing unchecked native-pointer rules still apply:
in-process staging is not a sandbox.

The scalar session bridge is implemented and validated, including defensive GC.
An exposed lazy-VM teardown use-after-free was corrected in the runtime: native
image state is freed before its retained module reference. Source-required scalar
demands and explicit `staticMode` policy are implemented; broader virtual-value
specialization and ownership remain incomplete. Pointer-free module initialization
has bounded working-tree qualification. Unsupported returned frame references,
slices and captured environments now reject in both profiles rather than assuming
managed retention. **The actual-root proof is not complete:** a callback's retained
store bounds are lost through a higher-order parameter even though direct invocation
rejects. No counted/owned escaping environment implementation is claimed. See
[the current evidence/blocker](../research/experiments/frontend-syntax/module-aggregate-access/README.md).
See [the source design](../docs/source-partial-evaluation.md) and
[session validation evidence](../research/experiments/source-partial-evaluation/staging-session/lifetime-fix/README.md).

## Deliberately excluded

The snapshot does **not** contain `wordlet/eval.lua`, `wordlet/value.lua`, `wordlet/cabi.lua`, `wordlet/lower.lua`, `wordlet/jit.lua`, or the old compiler facade. ABC does not retain the Lua evaluator or direct source-to-C backend. User-authored executable computation, including compile-time computation, must lower to verified ABC bytecode and run through `abc_vm`.

The current suite already covers typed recursive types, methods/full and static keyed
supply, nested words, block/vector lambdas, raw pointers, extern lowering and defer,
plus imported/exported typed interfaces. Do not treat those whole features as missing.
Remaining gaps include nested keyed partial supply, owned/escaping callable transport,
address-bearing sum/public ABIs, broader module initialization/storage and complete
source-demand/ownership verification. Legacy dynamic open-word IR still needs replacement
by the approved value-table design; semantic-IR checks are not runtime support.

[WORKLIST.md](../WORKLIST.md) records current evidence and specific open tasks, including
a full feature-matrix audit. The target integrates borrow/owner proofs in one source
model with acyclic counting and immutable DAGs, not profile-5 GC reachability. Current
profile checks remain honest until the implementation/ABI migration is complete.

## Provenance

- Source checkout: `../wordlet.lua`
- Base revision: `4a4cbc023a4325be8f633734cca1653f7833b010`
- Snapshot time: `2026-10-05T05:53:23Z`
- Intentionally included source-worktree modifications: `ir.asdl`, `tests/schemas.lua`, `tools/embed.lua`, `wordlet/analysis.lua`, and `wordlet/schema/ir.lua`.
- Subsequent reuse: the profile-neutral structural/type portion of `wordlet/check.lua` was ported as `let/check.lua`; its evaluator-coupled lifetime entry was not copied.

The copied files are authoritative inside this repository. Build and validation do not read the sibling checkout. See `LICENSE.wordlet` and `vendor/LICENSE` for the retained license notices.

## ASDL workflow

`ast.asdl` and `ir.asdl` are the sources of truth. After changing either schema, regenerate the embedded modules and run the tests:

```sh
cd frontend
luajit tools/embed.lua
luajit tests/schemas.lua
luajit tests/walk.lua
luajit tests/parse.lua
luajit tests/compiler.lua
luajit tests/lowering.lua
luajit tests/staging.lua
```

Use the same AST for `.slet` and `.let`. The host-selected source profile controls later typing, ownership and lowering; the parser does not infer a profile from a filename.

