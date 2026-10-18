# Let frontend

The production frontend reuses the former Wordlet grammar and structured representations;
it is not a parallel bootstrap compiler. Build and validation use this repository only.

## Components and contracts

- `ast.asdl`, `ir.asdl` and generated schema modules define the shared structures.
- `let/compiler.lua` owns source/typed/compile entry points and profile-checked imports.
- `let/semantic.lua` and `source_state.lua` own source elaboration, shared word contracts,
  binding-resolved captures and request-local demands.
- `let/check.lua` validates structural types; `program.lua` owns the completed access/
  lifetime/strong-edge results without annotating shared functions with mutable proofs.
- `let/placement.lua` lowers declared Rc operations into typed owning slots and concrete
  drops. `layout.lua` owns scalar/physical layouts; `abc.lua` emits verified ABC.
- `let/stage.lua` runs verified ABC in owned VM sessions. `snapshot.lua` transports
  supported pointer-free byte images; no Lua source evaluator exists.

Read [syntax](../docs/syntax.md), [application](../docs/application-sugar.md) and
[spread](../docs/spread.md) for word/lambda/receiver semantics, not implementation-history
pages. Named definitions and literal-do bindings share checking, recursive visibility
and export eligibility; contextual lambda annotations need not be repeated. The
[architecture](../docs/architecture.md#source-compiler-responsibilities) identifies
the authoritative elaborator and capture boundaries.

## Current admission

`.slet` remains the executable typed source profile. `.let` parses/checks but ABC
lowering rejects `dynamic-lowering`, including scalar-only programs; it is not silently
compiled as SLet. The approved single-language `.let` migration is separate from the
implemented explicit-Rc cutover. Both profiles share an AST; profile choice is host/API
policy, not inferred by the parser.

Initial `Rc(value)`, named `r.borrow()`, owning copies, records/fixed arrays/sums and
private direct owning calls execute. Ref/Slice remain borrowed; local escapes and
invalidated protection reject instead of acquiring hidden holdings. Borrowed callable
forms remain admitted within their lifetime contracts. Public/foreign/erased Rc,
owning environments, persistent owning modules and task/container transport remain gated.
See [the current subset](../docs/slet-subset.md) and [ownership](../docs/owners-references-ids.md).

Methods, keyed/static supply, nested words, block/vector lambdas, raw pointers,
extern/defer and typed imported interfaces are not wholly missing features. The old
higher-order retained-store defect is corrected; broader proofs and ABI completion
remain tracked in [WORKLIST](../WORKLIST.md), not a blanket rejection of callbacks.

## Compilation and staging

[Source compilation and staging API](../docs/source-compilation-api.md) is the single
contract for `Compiler.typed`/`compile`, `staticMode`, `Stage.open`, prepared handles,
exact typed snapshots and `abc_vm_read_image`. Required static demands execute on the
same VM under an explicit interpreted/threaded/eager/lazy policy. Typing without a
required demand needs no VM policy. `tools/abc` supplies the interpreted static default.

Staging uses `build/libabc.so` (or `ABC_RUNTIME_LIBRARY`), not a runtime subprocess.
Optional optimization is separate; unoptimized execution needs no optimizer library.
Close sessions on all exits. Prepared image writes persist across calls and are not
rolled back by aborts. Pointer-free snapshots survive teardown; borrowed/owning/address
snapshots reject. Foreign effects, including lifetime bindings, cannot execute during
compilation. The runtime's unchecked-pointer boundary is not a sandbox.

Tests are wired into `make validate-slet` and `make validate`; Rc lifecycle execution
also uses `make validate-source-owners`. Current outcomes, failures and costs live in
WORKLIST and its evidence links, not repeated pass counts in this introduction.

## Provenance

- Source checkout: `../wordlet.lua`
- Base revision: `4a4cbc023a4325be8f633734cca1653f7833b010`
- Snapshot time: `2026-10-05T05:53:23Z`
- Intentionally included source-worktree modifications: `ir.asdl`, `tests/schemas.lua`, `tools/embed.lua`, `wordlet/analysis.lua`, and `wordlet/schema/ir.lua`.
- Subsequent reuse: the profile-neutral structural/type portion of `wordlet/check.lua` was ported as `let/check.lua`; its evaluator-coupled lifetime entry was not copied.

The copied files are authoritative here; the sibling checkout is not a build dependency.
See `LICENSE.wordlet` and `vendor/LICENSE`. The old Lua evaluator, direct source-to-C
backend and compiler facade are deliberately absent. Source computation, including
compile-time computation, lowers to verified ABC and executes through `abc_vm`.

## ASDL workflow

`ast.asdl` and `ir.asdl` are the sources of truth. After schema changes regenerate
embedded modules, then check the affected integrated frontend boundary:

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
