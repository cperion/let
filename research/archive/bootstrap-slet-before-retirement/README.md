# Retired bootstrap SLet compiler

Historical snapshot taken during the revision-6 ISA migration. The user approved
retirement rather than porting this second parser/typechecker/direct assembly
emitter. `SHA256SUMS` records the exact pre-retirement sources.

- `tools/slet_frontend.lua`: old standalone Lua bootstrap, including Lua-side
  constant computation and old-ISA emission. Not a production compiler or fallback.
- `tools/validate_slet_frontend.lua`: its former assembly-string assertions.
  Passing those assertions never established executable revision-6 coverage.
- `examples/`: unchanged historical inputs. Fibonacci's old oracle was `55`,
  partial's `270369 67634689`, closures' `42 43`; countdown computes `5000050000`.
  These are historical expectations, not results measured on the retired compiler
  after the ISA migration. Its generated assembly is incompatible with revision 6.

The active `tools/validate_slet_frontend.lua` now uses only the production ASDL
frontend, shared C optimizer and VM. It checks independent outputs before/after
optimization in all three modes, plus actual Fibonacci/countdown source-file CLI
execution. Signed constants in its operand-form source are explicitly typed for
production's signed/unsigned contract; the bootstrap's literal adoption and exact
assembly scheduling are not retained as language/placement requirements.

`examples/fibonacci.slet` and `examples/countdown.slet` remain active production
examples. The bootstrap-only `partial.slet` and `closures.slet` were removed from
the active example directory. Their source capabilities are **not implemented**:
active tests require `semantic-todo` for the top-level partial initializer and
`static-required` for runtime partial application. No alternative successful
program is presented as implementation of either source feature.

Existing typed indirect-call tests and `examples/callables.abcasm` continue to
exercise the runtime callable ABI; retiring this source compiler does not remove
that runtime capability or alter VM/ABI/continuation/GC policy. Adding the missing
production source features is separate work.

This archive is evidence only: it is not copied into `build/`, required by active
validation, or supported by the production CLI.
