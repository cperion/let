# Phase 4 — frontend optimizer fixtures and API examples

## Scope and exit condition

Resume the approved semantic fixture migration, beginning with `frontend/tests/optimize.lua` and the callable example it consumes. Preserve independent results, ordered vectors, noncommutative operands, effects and provenance. Validate the migrated callable/virtual/foreign examples through the API suite. No runtime implementation change or compatibility translation is in scope.

## Implemented

- Migrated the optimizer fixtures to explicit selected RET, tail, branch, check, memory and foreign forms. MOVE selects its source. Indirect code-address loads now go directly to the opposite stack instead of loading on A and repairing placement with a MOVE.
- Preserved the counter's ordered `56 8` result and its bump/caller transfer sequence. Updated selected EXT/RET disassembly expectations; retained fixpoint, provenance, ordered-error, recursion, callable-root, frame-barrier and independent arithmetic expectations. Added explicit `14`, `0`, `42` oracles to the memory-profile original/optimized comparison.
- Migrated `examples/callables.abcasm`, `virtual.abcasm` and `foreign.abcasm`. `invoke_b` gathers arguments on B, target on A, receives its independent callee result on B, then returns from B. No mirrored function implementation or A-only adapter was introduced.
- Replaced stale API expectations that native indirect calls produce no observations. The approved common site contract now checks invalid-first/unseen, monomorphic, repeated monomorphic, mismatch/final-generic and failed-final behavior. Nine entry/mode histories cover A, B and tail calls in interpreter/eager/lazy, with independent noncommutative results and unchanged failure output sentinels. Eager preparation must not compile additional versions during these calls. Existing virtual/lazy-reuse and foreign tests remain.
- Added the now-migrated optimizer suite to `validate-slet`. Moved existing API/example checks earlier in `make validate` so the legacy general-validator failure cannot hide their results. No suite was removed or skipped.

## Evidence

Normal strict build and the migrated suites pass:

- **105** frontend optimizer/FFI checks;
- API observation histories, explicit B argument/return transport, tails, virtual execution/lazy reuse, and mixed/wide/void foreign calls;
- **259** compiler checks, **81** lowering checks, **24** staging checks and **33** symmetric execution processes;
- the existing optimizer ISA, metadata, symbolic, IR, capture and **495** continuation checks reached before the general validator.

Reproduction:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
 WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

**This is still not a full validation pass.** `tools/validate.lua` remains unmigrated and fails at historical `MOVE_BA`. Its opcode-coverage walker also assumes the old manifest and does not decode EXT correctly. Its binary destination fixtures, B calls, bare selected memory/control forms and indirect-call failure offsets need coordinated semantic migration. Cache fixtures and other active examples still need their own audit. No benchmark rerun or phase completion is claimed.

Logs: `phase-4-fixtures-{optimizer,api,full-validate}.log`. The full-validation log is the final integrated evidence; earlier logs record the focused checks.
