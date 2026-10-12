# Live opening and `endall` qualification

This checkpoint replaces record-opening snapshots with live field places within the
frontend's admitted typed contexts, and implements bounded `endall` expansion.
Historical receiver/vocabulary evidence directories are unchanged.

## Implementation

- `semantic.lua:expandBinding` retains a receiver once and installs projected field
  places instead of eagerly reading/copying fields. Namespace/sum aliases are unchanged.
- Opened-field identity survives binding-resolved capture transport, including scalar,
  callable and reference fields, through existing `InPlace`/`PlaceParam` contracts.
  Ordinary saved values retain ordinary value semantics; saved aggregate field reads
  are not converted into local record aliases when their source projection is captured.
- Module aggregate storage remains outside current source-demand admission. The old
  module field-snapshot branch is removed, not retained as an alternate opening mode.
- `lex.lua` reserves `endall`; `parse.lua` tracks block and delimiter boundaries and
  expands eligible trailing-lambda closers to ordinary `end` tokens with the original
  source span. Parser input tokens are copied before expansion. There is no new AST,
  IR, runtime instruction, calling convention, return or cleanup mechanism.

## Results

`qualification.log`:

- Vocabulary: **92 checks / 64 executions**, with old snapshot expectations updated.
- Receiver scopes: **407 checks / 384 executions**, four engines × optimized/unoptimized.
- `endall`: **57 checks / 16 executions**, including AST equivalence, origin retention,
  one/multiple callbacks, `if`, grouping, explicit arguments, arrays, keyed supplies,
  separately bound and expression lambdas, invalid contexts and repeat parsing.
  Execution compares explicit/abbreviated return and defer behavior in all eight modes.

Live-opening cases cover qualified/opened mutation visibility, explicit saved scalar
and aggregate values, scalar capture transport, intervening/recursive words, copied
versus referenced parameters, and callable/reference field replacement after capture.
Existing collision, member-priority, once-only initialization and escape-rejection
coverage remains integrated. The `endall` execution fixture uses existing nonescaping
managed-frontend capture admission and entirely typed executable IR; it does not add
owned escaping closure support.

Structural cost checks compare emitted ABC: an opened-field write is identical to its
qualified counterpart, and an unused opening emits no field reads or copies. These
are representation checks, **not timing or broad allocation/retention benchmarks**.
Lexer/parser source growth against `9cfd7f65` is 47 added / 6 removed lines (net +41);
there is no runtime source growth in this batch.

`full-validation.log` records successful:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

`isolation.log` records the same focused suites against a copy of the current frontend
with only `frontend/let/abc.lua` restored from `9cfd7f65`. It shares the current built
runtime, including the earlier shift correction. This isolates the new frontend work
from uncommitted packed lowering; it is **not** a clean baseline build.

No clean-build, sanitizer or timing qualification is claimed. Broader frozen/readonly
proof, module aggregate staging, collection-interface propagation and owned escaping
captures remain outside this checkpoint. X07 remains partial for that broader
acceptance; Q12 is complete. Packed float lowering remains paused.
