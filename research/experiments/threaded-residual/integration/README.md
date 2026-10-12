# Threaded integration checkpoints

**Current:** the capacity-frontier bug is fixed at the shared proof boundary;
expanded four-mode validation passes. See
[capacity-frontier/README.md](capacity-frontier/README.md) for the correction,
360 boundary regressions and post-fix performance caveats.

[completed-backend.md](completed-backend.md) preserves the earlier, narrower
passing checkpoint, clean-build validation and short performance pilot
(including the Fibonacci regression).

The following records the earlier catalog checkpoint; the subsequent
[native-emitter checkpoint](native-emitter-checkpoint.md) is also historical.

Implemented: authoritative `gen/execution_forms.lua`, independent header emission,
native generator coverage/order checks, migration to `ABC_FORM_*` addressing and
exhaustive catalog/C-index validation. 3,770 native forms; 2,950 eligible for the
seven-register threaded binding. Eligibility is not executable threaded support.

`forms-full-validation.log`: `make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20
WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' all validate`
passes, including 113 independent oracle cases / 678 mirrored three-mode
executions and 495 continuation executions. The new catalog checks and compiled
static assertions pass (`forms-validation.log`). No fourth-mode tests exist yet.

`forms-equivalence.txt` and `.sha256`: native generated C, order, extracted stencil
bytes and debug-stripped residualizer object are exactly unchanged. Baseline
sources, generated artifacts and stripped object are frozen in
`research/archive/threaded-residual/form-catalog-before.tar.gz`; working baseline
was `/tmp/abc-threaded-forms-before`. No new native performance claim is needed
for this byte-identical checkpoint. These checks do not validate threaded scalar
semantics or runtime integration, which are not implemented.

Outstanding work and approved contracts: `docs/threaded-execution.md`.
Native emitter separation, seven-register allocator parameterization, tape
emission/handlers and VM/API/CLI/staging wiring remain pending. No compatibility
aliases for old form macros, runtime fallback, second allocator or value IR were
introduced. Existing unrelated work was preserved.
