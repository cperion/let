# Worklist baseline audit: 06ec9dc

Purpose: distinguish current implementation/test coverage from historical backlog
and recently approved, unimplemented ownership/task/spread designs before creating
`WORKLIST.md`. The working tree was clean at the start; `commit.txt` records full SHA.
No runtime source was changed for this audit.

## Fresh validation

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' all validate
```

Exit status **0**. Full stdout/stderr is `validation.log`, copied from exclusive
`mktemp` directory `/tmp/let-plan-audit.iQtp3V/`. This is an incremental build/test
run, NOT clean-room, sanitizer, thread-race or new performance evidence.

## Source/consumer checks

- `Makefile` runtime and PIC object lists, generation dependencies and validation targets.
- `frontend/let/compiler.lua` profiles, ingestion/indexing, typed/compile paths and import discovery.
- `frontend/let/semantic.lua` methods, partial supply, captures, defer and top-level initialization restrictions.
- `frontend/let/abc.lua` dynamic rejection, escaping callable/address-bearing aggregate restrictions.
- `frontend/let/stage.lua` session operations and scalar-only input/result transport.
- `frontend/tests/compiler.lua`, `lambdas.lua` and executed validation output: tested methods,
  keyed calls, nested recursion, recursive types, pointers, extern, defer, imports/exports and lambdas.
- `frontend/let/lex.lua`, `parse.lua`, schema and active-source searches for proposed spread/rest/task/proof interfaces.
- `src/module.c` profile restriction; `src/residualize.c` version limits/frontiers;
  `src/native_image.c` publication/lazy reprotection; `src/residual_c.c` subset validation.

This was a focused planning audit, not a complete proof of implementation correctness.
Negative symbol searches do not prove absence of every equivalent implementation.
The live checklist keeps F01 for a complete syntax-to-execution gap matrix and A01
for the whole-diff/dead-path review. Historic source/frontend gap documents overstated
missing features; preserve working tested paths and close their actual remaining gaps.
