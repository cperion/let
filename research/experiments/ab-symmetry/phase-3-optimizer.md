# Phase 3 — optimizer semantic identities and selected-bank ABC output

## Scope

Migrate the existing build-time DAG optimizer's producers and ABC emitter together. Keep its DAG, classical Ershov scheduling, effect ordering, call-graph policy, loop policy, supported subset and original-function retention. Do not add a native IR, allocator, compatibility engine, runtime optimizer dependency or new scheduling optimization.

## Implemented

`src/optimize.c`:

- Scalar/check nodes consume semantic operation identities. Removed canonical A opcode assumptions and arithmetic on encoded opcode ranges when selecting immediate/C forms.
- Emission binds semantic operations and selected banks through the authoritative generated metadata, including complete core/EXT encodings. The lookup is build-time only; it is not a runtime decoding layer. Compilation-time lookup cost has not been benchmarked.
- Binary expressions emit the left operand on the requested bank and the right on its opposite, retaining the existing Ershov order. Same-value binary expressions use the selected COPY form, not an A-only orientation workaround.
- Calls/foreign calls capture arguments from their declared bank; real calls publish on their selected channel. Real tails preserve their selected argument source. Necessary result transport remains distinct from arithmetic orientation repair.
- RET captures/emits its selected source. Joined result handling retains a source-selected result bank instead of blindly gathering every result through A. The existing C join slots remain; no new transport scheduler was introduced.
- HALT has an explicit callback and leaf kind. Result capture precedes release of residual C homes, and output remains HALT rather than silently becoming a callable RET.
- One control-prefix emitter replaces duplicated ordinary/phi-tree control lowering. It binds selected-first operands, preserves the source bank, emits an EXT selector when required, and measures displacement from the complete instruction end.
- Direct-call relocation uses decoded instruction metadata, not the removed opcode-kind table. Speculative shortcut rollback restores both code length and provenance count.

No VM, native emitter, interpreter cache or runtime continuation changes.

## Defects exposed and corrected

1. EXT selector metadata is bank-neutral. An initial source-bank lookup through that metadata turned mirrored EXT.A branches into EXT.B. Results happened to remain correct after reprojection, but the independent bank-encoding assertion caught the mismatch. Source bank selection now comes from the original core/prefix metadata.
2. Existing pure-address deduplication ignored encoded image offsets: GADDR at offsets 0 and 8 could become one node, producing `77 0` instead of `7 77`. Node equality now includes the immutable encoded memory operands. This corrects the address identity at its producer, rather than repairing loads or adding alias fallbacks. The failing check is preserved in `phase-3-optimizer-memory-before.log`.

## Validation

Normal Makefile targets now build: `all`, static/shared tooling libraries, `abc-opt`, and the focused validators. This is a normal dependency-driven build, **not a clean-from-empty whole-tree rebuild or a full validation-suite pass**.

New `validate-optimizer-isa` target is included in `validate` and runs:

- **48 original/mirrored modules**, **228 original-versus-optimized execution pairs** across interpreter/eager/lazy (456 executions).
- Noncommutative arithmetic, nested B computations without orientation-repair MOVE, normalization, C replacement capture, both branch outcomes, switch boundaries, multi-result joins, all CALL/RET bank combinations, recursion, tail recursion, selected HALT including arguments, distinct image addresses, and zero/one-result foreign effects with live prefixes.
- Explicit selected EXT encoding and instruction-boundary provenance assertions; trap status, diagnostic and mapped original PC checks.
- Foreign host bindings check argument order, ordered results, preserved caller values and exactly one effect in each original/optimized execution.
- Fixtures must demonstrate real optimizer emission, rather than silently passing through function retention. Canonical inputs may re-emit identical bytes; their non-identity provenance coverage distinguishes emission from the identity map used for retained functions.

Additional final-output checks: twelve existing pre-tooling modules, 36 mode executions. Only fib28 rewrites; the other eleven retain original code under the existing optimizer eligibility policy. These passes do **not** establish optimized coverage for those retained workloads.

Focused regressions pass:

- revision-6 ISA metadata validator;
- 36 banked/call contracts;
- 28 symbolic selected-bank contracts and existing regressions;
- 235 residual-builder/IR checks;
- 120 return/indirect interpreter/eager/lazy checks;
- 16 mirrored assembly/interpreter contracts;
- 14 capture ordering/failure/identity contracts;
- 26 mirrored portable-C execution cases, now linked against the normal tooling archive.

Strict Clang 20 warnings were used. Generated portable C keeps its previously documented unused-generic-helper warning exception. `git diff --check` passes for the changed tracked implementation/test/build files.

## Evidence and commands

Logs: `phase-3-optimizer-{tool-build,all-build,build,regressions,c,workloads}.log`.

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
 WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' \
 all validate-optimizer-isa build/validate-residual-ir build/validate-capture
build/validate-residual-ir
build/validate-capture
```

`tools/validate_optimizer_isa.lua` invokes the existing public optimizer binding, assembler and actual runtime. `tools/validate_optimizer_foreign.c` supplies host bindings for its foreign fixtures. No frontend lowering is used.

## Remaining boundaries

- Frontend lowering and many historical full-suite fixtures are still unmigrated. For example, `tools/validate_continuations.lua` still contains old RET/TCALL and MOVE spellings; its historical 243-case pass is not new-ISA evidence.
- Broader continuation, escaped-storage and resource integration remains before closing phase 3.
- The existing residual-builder/portable-C ZX8/ZX16 support gap remains separate from the optimizer's now-tested direct ABC normalization emission.
- No change to optimizer eligibility, whole-module error-retention policy, region budgets or dynamic support is claimed.
- No performance rerun or improvement claim. The pre-tooling current-VM checkpoint and historical fixed baseline remain preserved for the appropriate later comparisons.
