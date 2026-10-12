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

These suites are part of `make validate`. `let/compiler.lua` is the production compiler entry point: it selects Let or SLet explicitly, builds the ASDL AST, enforces profile restrictions and indexes module declarations. `Compiler.typed` resolves annotated words, parameters/results, module literals, locals, scalar and generic operators, records, arrays, sums, references, slices, strings, typed lambdas/captures, direct/indirect/dynamic calls, structured control and recursion into verified ASDL `Ir.Fn`. `Compiler.compileFile` resolves profile-checked imports with deterministic private identities. `Compiler.compile` and `Compiler.compileFile` carry IR through the shared checked ABC lowering path, and `build/abc compile/run` use that path for both `.let` and `.slet`. `Compiler.stage` executes entries only through `abc_vm` under an explicit interpreted, eager or lazy policy; `Compiler.specialize` re-enters ordinary IR and the C optimizer with typed cells returned by staging. Exact cells, language aborts, resource failures, source mappings and optimizer provenance return to the compiler. Remaining unsupported forms reject with stable diagnostics rather than executing through Lua or another backend.

## Deliberately excluded

The snapshot does **not** contain `wordlet/eval.lua`, `wordlet/value.lua`, `wordlet/cabi.lua`, `wordlet/lower.lua`, `wordlet/jit.lua`, or the old compiler facade. ABC does not retain the Lua evaluator or direct source-to-C backend. User-authored executable computation, including compile-time computation, must lower to verified ABC bytecode and run through `abc_vm`.

Remaining frontend work includes recursive/exported types, methods and keyed supply, nested words, general block-bodied lambdas, raw-pointer source operations, `extern`/`defer`, module initialization/storage, managed/address-bearing sum ABIs, and completed-program ownership/provenance verification. SLet borrow proofs must remain separate from Let profile-5 GC reachability.

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

