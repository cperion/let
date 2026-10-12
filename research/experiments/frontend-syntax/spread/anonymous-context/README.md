# Unnamed opened homes

State: implemented within admitted typed contexts; focused and full incremental
validation passed. No clean build, sanitizer, frontend timing, native-image growth,
frozen/counting ownership completeness or unrelated optimizer correction is claimed.
No publication/push performed.

## Contract

- `...: T` receives one ordinary parameter and opens it without a source name.
- `ctx...: T` uses the same parameter/opening path and keeps its ordinary binding.
- A checked callback signature can supply the type in `do(...)`; no anonymous Any
  default, type-search, argument-count inference or runtime pack is introduced.
- One opening per signature, first runtime requirement after leading static Type
  parameters. Body elaboration opens at entry, for expression and block bodies.
- Bare `...`, normally grouped as `(...)`, reads the retained runtime receiver.
  `(f)(..., role)` explicitly passes it without implicit receiver insertion;
  ordinary local-callable/recursive-binding exceptions are unchanged.
- Prefix `...expression` still expands supplies; prefix `...args` in parameters
  remains named final rest. Bare `...` before an expression-start token needs
  grouping or a separator. Newlines are not separators. After definition `= do`,
  `(` still starts a returned lambda, not a grouped first block statement.
- Whole-home assignment rejects `context-use`. Ref/Ptr of a reference home's
  hidden holder rejects `not-a-place`; use the established reference value or
  a field place. Ref of a by-value record home is a normal checked parameter
  borrow. No opaque address reconstruction or new readonly subsystem.
- Fields stay live, explicit reads snapshot under ordinary value rules, and
  captures preserve actual qualified routes/holdings. Lifetime rejection is
  unchanged. No field copies just to open names; no user-visible synthetic name,
  new runtime operation, ownership permission or physical C0 address guarantee.

Authoritative docs: `docs/spread.md` §5, `docs/word-bindings.md`,
`docs/application-sugar.md` §3.1. Home identity is its qualified argument/place;
its type determines available operations, not which same-typed object is chosen.

## Implementation

`frontend/ast.asdl`: optional-name VocabularyParam, CurrentContext; generated
`frontend/let/schema/ast.lua` via `frontend/tools/embed.lua`.

`parse.lua`: grammatical bare/prefix distinction, anonymous requirements,
removed block-only vocabularyBody guard. Foreign and multiple openings still
reject. `semantic.lua`: wordContract checks type-prefix placement and known type;
wordParameter returns its binding as well as argument, installed in lexical scope
only when named. Standard and source-template producers retain bindings directly.
Template contracts carry original opening requirements; pack components no longer
use fabricated temporary lexical keys. expandContext is the shared authoritative
opening path; expandBinding only resolves the ordinary named source. CurrentContext
reads/captures existing receiver bindings. No body replay or alternative elaborator.

## Qualification

```sh
cd frontend
/tmp/lua-compat tests/anonymous_context.lua
/tmp/lua-compat tests/syntax_batch.lua
```

Integrated in Makefile. Final focused result: **221 checks /192 VM executions**.
Most probes run optimized/unoptimized in interpreted, threaded, eager and lazy modes;
**four aggregate/capture/interface probes deliberately run unoptimized only** under
the established independent frame-access optimizer qualification boundary.

Coverage: original user's snippet AST (two inputs, no name), ordinary ABI order,
copy versus borrowed referent, whole-reference identity, callback contextual types,
named/anonymous expression bodies, Type+rest templates, unchanged named openings,
global receiver recursion, explicit local recursion, defer, nested homes, definition
captures, replacing original named reference after opening, saved aggregate reads,
member precedence, callable-field invocation, no context without lexical opening,
type/position/collision/foreign/rest diagnostics, home-rebinding/holder-address
rejection, borrow-return and borrow-store in both profiles. Identical executable IR
for named/unnamed field activity and no scalar reads for unused opening.

`focused-attempt-1.log` records the first approved core (147 checks/128 executions).
`focused-attempt-2.log` retains a final-rule fixture failure: beginning a `= do` body
with grouped `(...)` selects the existing returned-lambda grammar. The corrected
fixture begins with an ordinary let; production parsing policy was not changed.
`focused-before-shadow-check.log` preserves205/176 before the last conformance
check. Type-prefix classification must resolve a dependent formal rather than a
same-spelled global metatype; the corrected classifier and added shadow probe
are included in `focused-final.log`, the final221/192 run, including a by-value
F64 Point expression-body probe in all eight execution configurations.

`full-validation-attempt-1.log` passed with the earlier core rules;
`full-validation-before-shadow-check.log` passed after expression-body/position/
holder refinements. `full-validation-before-float-point.log` passed including the
formal-shadowing conformance check; `full-validation-final.log` also includes the
F64 Point expression-body probe. All are incremental runs with:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

Existing syntax149/68, receiver407/384, rest616/276 and full runtime oracle143/1144,
cache2880/655 and other established suites pass. The original snippet's successful
parse is not executable admission of its unspecified Terminal/Editor APIs, nullary
reads, callback retention or missing return paths. Green suites are not complete
ownership/resource proof. Bitcast execution fast-path implementation was paused for
this user-selected language addition and has not been resumed here.
