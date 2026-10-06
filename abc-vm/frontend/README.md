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
- The VM-backed static execution bridge in `let/stage.lua`. It assembles and verifies the same lowered artifact, invokes `abc_vm` under an explicit host-selected policy, and decodes exact result cells.
- Parser/schema/traversal/compiler/lowering/staging tests and the SLet source examples.

These suites are part of `make validate`. `let/compiler.lua` is the production compiler entry point: it selects Let or SLet explicitly, builds the ASDL AST, enforces profile restrictions and indexes module declarations. `Compiler.typed` resolves the production scalar slice—annotated words, parameters/results, literal module values, locals, scalar operators, short-circuit booleans, conversions, direct and multi-result calls, structured conditionals and recursive tail calls—into verified ASDL `Ir.Fn`; unsupported constructs reject with `semantic-todo` rather than executing in Lua. `Compiler.compileFile` resolves profile-checked imports with deterministic private function identities. `Compiler.compile` and `Compiler.compileFile` carry IR through the shared checked ABC lowering path, and `build/abc compile/run` use that path for both `.let` and `.slet`. `Compiler.stage` executes saturated scalar entries only through `abc_vm` under an explicit interpreted, eager or lazy policy. `Compiler.specialize` accepts typed cells returned by staging, builds an ordinary residual wrapper with those cells as constants, and invokes the same C optimizer; Lua never evaluates the user operation. Exact cells, language aborts, resource failures, source mappings and optimizer provenance return to the compiler. Aggregate layouts, borrows, views, indirect calls, sums, managed values and generic `any` remain explicit TODO diagnostics until their semantic and lowering stages land.

## Deliberately excluded

The snapshot does **not** contain `wordlet/eval.lua`, `wordlet/value.lua`, `wordlet/cabi.lua`, `wordlet/lower.lua`, `wordlet/jit.lua`, or the old compiler facade. ABC does not retain the Lua evaluator or direct source-to-C backend. User-authored executable computation, including compile-time computation, must lower to verified ABC bytecode and run through `abc_vm`.

The SLet borrow checker and the portions of semantic construction that were coupled to the old evaluator will be migrated separately. SLet borrow rules must not be applied to Let `.let`; Let uses profile-5 managed ownership and GC reachability.

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

