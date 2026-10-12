# Phase 3 — approved portable-C call binding correction

Implemented following explicit user approval. This closes the specific invalid-C boundary exposed by the residual-builder tests; it does not complete optimizer/ABC emission or the ISA migration.

## Contract and implementation

`src/residual_c.c` retains both existing C ABIs and the existing failure analysis. A one-result non-failing function still uses the scalar ABI. Zero/multiple-result functions still use the vector ABI; their result shape does not imply that they can fail.

For ordinary vector calls, emission now distinguishes:

- Proven non-failing callee: invoke with `NULL` error channel and discard the guaranteed-success status. Copy the ordered result vector as before. This is valid inside a scalar caller, which has no error parameter or status return.
- Potentially failing callee: pass the existing error channel and return a nonzero status before copying results, as before.

General-ABI function definitions explicitly mark the output pointer used, including zero-result functions. No failure facts were fabricated; no new analysis, ABI adapter, runtime fallback, allocator or semantic engine was added. Scalar call bindings and tail bindings remain unchanged. The latter already have valid channels: a non-failing general tail target has zero/multiple results, so its same-result-count caller uses the general ABI; a potentially failing target propagates failure eligibility to its caller.

## Validation

`check-builder-c.lua` now passes **26 original/mirrored portable-C execution cases**:

- All twelve previously planned read/call/control/fib28 cases, including the previously failing zero-result helper workloads.
- Fourteen focused cases: zero-result and empty-vector callees, multi-result callees with scalar and vector callers, and potentially failing callees with zero/one/multiple results.
- The focused tests inspect generated call sites for `NULL` plus omitted status propagation versus the real error channel plus status propagation. They also check that non-failing single-result callers retain the scalar ABI.
- Failure tests execute successful and failing calls through the same artifact, check exact status, reason, original instruction offset and unchanged caller output, then repeat failure with a null public error pointer.
- C emission is linked directly through `abc_emit_c`, without the still-migrating ABC optimizer. Existing residual-builder/IR/analysis components and the fresh revision-6 runtime supply the dependencies.

The modified emitter compiles with Clang 20 `-O2 -g` and strict warnings. Generated C compiles with `-O2 -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-unused-function`; the last flag permits the existing unused generic runtime helpers. Unused parameters are not suppressed. `git diff --check` passes for the changed tracked files.

Evidence: `phase-3-c-binding.log`. The earlier `phase-3-builder-c.log` is retained as historical failure evidence. The 235 builder/IR checks predate this C-only change and are not reported as a new execution of that suite.

## Reproduction

Using the component objects prepared in `phase-3-builder.md`:

```sh
base=/tmp/abc-eager-c.trOsXI/current
check=/tmp/abc-phase3-builder
/tmp/clang20 -O2 -g -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
 -I"$base/build" -Iinclude -Isrc -c src/residual_c.c -o "$check/residual_c.o"
/tmp/clang20 -O2 -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
 -Iinclude research/experiments/ab-symmetry/builder-emit-c.c \
 "$check"/{residual_builder,residual_ir,residual_analysis,residual_validate,residual_c}.o \
 "$base/build/generated/residual_ir.o" "$base/build/libabc.a" -lm -o "$check/emit-c"
luajit research/experiments/ab-symmetry/check-builder-c.lua \
 "$check/emit-c" /tmp/clang20 "$check/aot"
```

The VM/native source and benchmark checkpoint are unchanged. No performance claim is made. Next: optimizer semantic-operation consumption and selected-bank ABC emission, then whole-tooling integration. Portable C remains its existing integer/static subset.
