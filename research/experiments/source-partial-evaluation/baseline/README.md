# Before source partial-evaluator implementation

This is a focused frontend baseline, not a completed partial-evaluator migration
or a full `make validate` result. No runtime/compiler implementation changed while
recording this baseline. `SHA256SUMS` identifies relevant current source/test files;
it is not a complete build-input manifest or a frozen-source archive.

Command (repository root):

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' \
  validate-slet
```

Exit status: 0. Raw output: `validate-slet.log`.

- Schema generation consistency and schema construction pass.
- Walker: 4 checks; parser: 232 checks.
- Compiler ingestion/semantic IR: 259 checks.
- Checked-IR lowering: 81 checks.
- Shared C optimizer/FFI: 105 checks.
- Explicit VM-backed staging: 24 checks.
- Replacement production frontend integration: 78 executions plus 2 rejection checks.
- Portable C: 12 mirrored cases.

The two source diagnostics in the replacement integration test still reject a
module-level static partial initializer and the historical runtime-partial SLet
program. Both are observed current implementation rejections, not permanent language
judgments about these programs. The historical closure example uses pure
`seed(40)`/`seed(41)` calls: if authorized VM evaluation establishes their values,
the later supplies are static. A negative test of SLet's runtime-partial rule must
use an actual runtime parameter, not assume those calls remain opaque. Valid
explicit lambda captures need separate positive runtime-parameter coverage.

The baseline does not establish persistent VM staging, source demand-driven
execution, virtual source objects, complete provenance, owned escaping closure
representation or executable managed Let support. It contains no timing benchmark.

The design is tracked in `docs/source-partial-evaluation.md`. ABC optimization and
native residualization are separate existing components, not implementations of
that source model.
