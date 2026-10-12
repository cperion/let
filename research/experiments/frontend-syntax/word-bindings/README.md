# Word/binding unification checkpoint

Scope: shared word contracts and elaboration; literal-do binding recursion,
inference and exports; conservative spelling-independent capture materialization;
reserved `oneof { ... }`; callable keyed-entry sugar and ordinary sum-handler
invocation. See `docs/word-bindings.md` and `WORKLIST.md` for limits.

## Integrated validation

`validation.log` records a successful run of:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-slet
```

It includes word bindings (106 checks, 84 four-mode executions), syntax batch
(106/48), compiler (280), lambdas (269/80), parser (232), lowering (100), optimizer
(118), staging (27), source demands (52), sessions (280), symmetric placement
(43 executions), lifetime (48), production frontend (112 executions plus two
static-demand diagnostics), and 12 portable-C cases. Schema generation is current.

This reused the existing build and rebuilt static archives/tools as recorded in
the log. It is not a clean-build, sanitizer or performance qualification.

During development, focused runs exposed a retired `_lambda_` test-name assumption,
an incorrect `Ir.Indirect` constructor call, and a negative fixture using an
unsupported computed sum head. Those were corrected before this successful run;
the final log is not a transcript of every development attempt.

## Measured structural cost

`size.lua` uses identical explicit-lambda source accepted by the syntax checkpoint
`2e82c27fa6d69bfc3ed5f17b41aa5cde6f671553` and the new implementation. Run it from
each checkout's `frontend` directory. The baseline frontend/tools were extracted
read-only with `git archive`; both runs used the same current runtime build.

| Measure | Baseline | Shared word elaborator |
| --- | ---: | ---: |
| IR functions | 2 | 4 |
| IR call sites | 1 | 3 |
| Callable views | 0 | 0 |
| Assembled module bytes | 222 | 290 |
| Assembly text bytes | 579 | 814 |

Both versions return 42 in interpreted, threaded, eager and lazy modes with
optimization disabled for execution. `size.log` records these results. The module
is 68 bytes larger (about 31%); the two expression handlers now have ordinary word
bodies and call sites instead of a separate inline elaboration path. This is a
real code-size regression for this fixture, not evidence of a timing regression
or improvement. Runtime and compilation/preparation timings were not measured.
No new source inliner was added to conceal this cost.

## Remaining boundaries

- Owned/escaping captures, general source-demand acceptance and dynamic runtime
  replacement remain unfinished.
- A literal spelling for named keyed requirements still needs a grammar decision;
  shared elaboration does not by itself establish complete surface-syntax sugar.
- `ctx...` vocabulary parameters are approved but intentionally deferred until
  ordinary binding-spread elaboration is implemented. Neither syntax support nor
  executable vocabulary expansion is claimed by this checkpoint.
- General pack/spread elaboration continues to reject explicitly.
