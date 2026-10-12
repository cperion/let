# Capitalized source types and constructors

Approved naming migration: PascalCase types/schemas and constructors, including
built-ins; snake_case ordinary words, values, fields, alternatives and modules.
Constructor type/value forms share spelling (`Ref(Point)` / `Ref(p)`). No lowercase
builtin compatibility aliases. Capitalization does not classify user bindings.
ABC encodings, C APIs, Lua host primitives and historical evidence are unchanged.

Canonical `frontend/ir.asdl` and its embedded schema were regenerated together;
frontend descriptors, producers, consumers, active tests/examples and source docs
were migrated. The generic lowering reference counter now qualifies `Ir.Ref`
by class, avoiding the newly same-named `Ty.Ref` constructor.

## Evidence

- `full-validation.log`: full validation exit 0, including the new naming suite
  (44 checks / 8 optimized/unoptimized four-mode VM executions).
- `validation-attempt-1.log`: initial full run failed on lowercase `cell` references
  in assembled source fragments; retained rather than hiding that failed attempt.
- `focused.log`: final naming/lambda regressions, module alias 42/one root, and
  the deliberately still-reproduced higher-order retention hole.
- `example-admission.log`: all 14 frontend examples compared with the pre-rename
  working snapshot `a73e4e65`, using the same runtime. Admission outcomes match;
  nine existing unsupported/rejected examples are not claimed as executable.

Invocation:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

No clean-build, sanitizer or performance claim. S05/S06 higher-order proof and
packed-float lowering remain incomplete. No publication/push performed.
