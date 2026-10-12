# Phase 3 — residual-builder callback boundary

## Scope and exit

Consume the approved symbolic semantic-operation and selected-bank contracts in the existing build-time residual IR producer. Preserve its SSA/block transport, source origins, capture, effect ordering, recursion policy and supported-subset behavior. This is one component boundary, not completion of phase 3 or the whole tooling pipeline.

## Implemented

- `src/residual_builder.c`: scalar callback mappings now consume `ABC_OPERATION_*`, not canonical A opcode bytes; diagnostic messages no longer index bytecode names with semantic identities.
- Conversion/check signatures match the shared symbolic callbacks. Conversion results use the selected stack; check inputs are the already captured selected values supplied by the shared engine.
- Direct calls read their selected argument/result channel; indirect and tail calls use their explicit argument stack, independently of the preserved continuation destination. Foreign argument/result transport is selected-bank aware.
- RET and HALT capture their declared result source. Ordered vectors and live opposite prefixes are retained without A-only gathering or orientation repair.
- Corrected an exposed classification bug: the old comparison enum range included floating arithmetic, causing floating subtraction to be assigned integer result type and declined at return. Comparison classification now names the actual integer and floating relations explicitly.
- No runtime/native changes, new IR, allocation algorithm, compatibility path or change to GC/continuation layout.

## Checks

`tools/validate_residual_ir.c` now includes 34 mirrored builder fixtures alongside its original arena/IR tests: **235 checks pass**. Inputs use fixed revision-6 bytes, independent of the opcode generator. Tests validate semantic operation identity, selected-first subtraction/division/shift/power/float subtraction, EXT C operands, immediate/unary forms, float conversions/checks, all four CALL/RET combinations, ordered multi-results with live prefixes, indirect calls/tails, foreign calls, HALT, captured C values across replacement, and real/virtual direct tails.

Assertions follow the IR's explicit entry/continuation block-parameter transport rather than assuming source argument IDs survive unchanged. The initial test harness made that incorrect ID assumption; corrected before recording the pass.

All builder, IR, analysis, validator, dump and C-emitter components compile under strict Clang 20 warnings. The focused link uses these freshly compiled objects, newly generated ASDL objects and the fully rebuilt current revision-6 runtime from the preserved benchmark snapshot; it does not use the old pre-migration runtime library. `Makefile` records the validator's new builder-header dependency. The ordinary tooling archive target still awaits optimizer migration.

## Portable-C boundary: initially exposed failure

`builder-emit-c.c` links the public `abc_emit_c` API without the still-unmigrated ABC optimizer. `check-builder-c.lua` compiles and executes original/mirrored integer modules. The two warm-C-read cases pass with expected 104000000 results. The next case, post-call-top, emits invalid C: a scalar/no-failure caller invokes a zero-result general-ABI helper using an undeclared `error` parameter. The zero-result helper also leaves its `results` parameter unused. Later cases have not run because the check stops at this failure.

This is a C binding issue, not evidence of incorrect residual call vectors: the IR builder tests and validator pass. `scalar_function()` selects the single-result fast C ABI using failure facts and result count, while call emission currently assumes every general-ABI callee implies a caller error channel. These are distinct properties. Do not hide this by falsifying failure facts or adding an A-only adapter.

Before changing that C call interface, discuss the proposed binding: retain the existing scalar/vector ABIs and failure analysis; use the general vector call without an error/status propagation path when the callee is proved non-failing, and retain the existing error channel/status propagation when it may fail. Explicitly account for unused zero-result output parameters. Test zero/multi-result no-failure callees and genuinely failing callees. No new analysis or execution subsystem is proposed.

Generated C currently includes unused generic runtime helpers; the focused compile suppresses only `-Wunused-function`. Runtime/component compilation retains all strict warnings. The undeclared error channel and unused parameter remain recorded failures, not suppressed successes.

Logs: `phase-3-builder.log`, `phase-3-builder-c.log`. Existing ZX8/ZX16 residual-IR support gaps were not expanded here; portable C remains its declared integer/static subset. Optimizer/ABC emission and broader integration remain incomplete.

## Reproduce the component check

```sh
base=/tmp/abc-eager-c.trOsXI/current
check=/tmp/abc-phase3-builder
mkdir -p "$check"
make -C "$base" CC=/tmp/clang20 build/generated/residual_ir.o
for file in residual_builder residual_ir residual_analysis residual_validate residual_dump residual_c; do
 /tmp/clang20 -O2 -g -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
  -I"$base/build" -Iinclude -Isrc -c "src/$file.c" -o "$check/$file.o"
done
/tmp/clang20 -O2 -g -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
 -I"$base/build" -Iinclude -Isrc tools/validate_residual_ir.c \
 "$check"/{residual_builder,residual_ir,residual_analysis,residual_validate,residual_dump}.o \
 "$base/build/generated/residual_ir.o" "$base/build/libabc.a" -lm -o "$check/validate-residual-ir"
"$check/validate-residual-ir"
```

Link `builder-emit-c.c` against the same objects, substituting `residual_c.o` for `residual_dump.o`, then run:

```sh
luajit research/experiments/ab-symmetry/check-builder-c.lua \
 "$check/emit-c" /tmp/clang20 "$check/aot"
```

At this checkpoint the latter failed as documented. The subsequently approved correction now passes 26 mirrored execution cases; see `phase-3-c-binding.md` and `phase-3-c-binding.log`. The original failure log remains historical evidence. No benchmark rerun or performance improvement claim is warranted from these producer-only changes.
