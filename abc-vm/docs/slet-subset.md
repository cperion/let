# Scalar SLet frontend (first subset)

`build/abc compile file.slet -o file.abc` produces a verified integer ABC2
module. `build/abc run file.slet` compiles to a temporary module and executes
it. `--emit-asm` writes verified diagnostic assembly. `--export word` adds
an export; `main` is always exported and must have no parameters. Running
source with an explicit export also makes that word public for that run.

The frontend, assembler and tests use LuaJIT. Exact integer processing uses
LuaJIT FFI uint64/int64 arithmetic and its 64-bit bit operations; decimal
parsing never rounds through a double. The C embedding library needs no Lua.

## Supported

- Named words with annotated scalar parameters and **explicit result contracts**.
  Parameter groups such as `(a, b: u32)` are supported. Mutual/direct recursion
  uses direct VM calls; compatible tail calls use `TCALL` without native recursion.
- `u8`, `u16`, `u32`, `u64`, `i32`, `i64`, `bool`, and erased `unit`.
- Immutable local/module bindings, forward module references, lexical shadowing
  in child scopes, blocks with explicit returns, expression/statement conditionals.
- Ordered multi-results. Scalar contexts select the first result; only the last
  result-list expression expands. Grouping forces scalar adjustment. Binding
  surplus results are discarded; missing bindings receive unit. Unit has no cell.
- Wrapping arithmetic, integer comparisons/bitwise operations, power, u32 shift
  amounts, checked conversions, and strictly boolean short-circuit `and/or/not`.
  Instruction selection uses the adopted immediate (`OPI`), C-cell (`OPC`), fused
  immediate-branch (`BxxI`), and direct two-stack branch forms when applicable.
- Decimal/hex/binary literals with digit separators, line and long-bracket comments.
- Directly negated literals follow spec Decision 8: signed, adopting a typed
  operand/slot when appropriate, otherwise i64. Other negation is modular.
- Same-width 32-bit signedness casts reinterpret bits. Per spec Decision 7,
  i64/u64 conversions require a clear top bit and reject/abort otherwise.
- Known scalar operations and immutable constants fold. Known branches evaluate
  only the selected arm, but both arms are parsed and names are resolved.
  Known zero divisors/negative exponents reject during compilation.
- Incomplete **module-level static supply**, e.g. `let next32 = xorshift(13,17,5)`,
  creates a direct specialized word with bound constants, not a heap closure.
- **Lexical local runtime supply** of a known word, e.g. `let p = add(seed())`.
  Captures copy scalar values into a C byte block; calls use a code/environment
  view and CALLI. Captures cannot escape; adapters can tail-call only after loading
  them. See [callable-profile.md](callable-profile.md) for the exact subset.

## Deliberate limits

This is not the full Let compiler or an implicit partial evaluator. Ordinary saturated calls run on the VM even with known arguments; normal source compilation does not execute them. `Compiler.stage` is an explicit host-selected static-execution boundary, and `Compiler.specialize` only constructs residual wrappers from typed values that such VM execution has already produced. Future automatic evaluation requires a sound proof that the invocation is total, effect-free, and cannot language-abort; purity alone is not sufficient because a pure call can diverge. No speculative fuel, timeout, instruction, specialization-count, or logical-allocation budget may be used to guess termination.
Module initializers cannot invoke saturated words. Optional result inference,
general higher-order callable values/contracts, dependent/type-valued requirements,
records, arrays, pointers, strings, floats, matches, mutation, defer and externs
are not implemented. Source functions needed by exports/calls are compiled; all
module bodies are parsed and names resolved, including unselected paths.

The VM and module API remain independent of this frontend. `asm` accepts any
supported VM instruction, even if the frontend does not generate it.
Host calls to additional typed exports must supply normalized cell bits for
their declared source types; the integer module API does not encode widths.
CLI results are displayed as signed 64-bit integers, including raw u64 results.

Examples: `examples/fibonacci.slet`, `countdown.slet`, `partial.slet`, and `closures.slet`.

