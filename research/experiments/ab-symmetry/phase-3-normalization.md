# Phase 3 — approved normalization and continuation integration

## Implemented

- Added explicit `ZeroExtend8`/`ZeroExtend16` unary operations at the authoritative residual schema, alongside existing `ZeroExtend32`. The builder maps ZX8/ZX16 directly and uses the existing U32 result representation. Portable C emits unsigned `uint8_t`/`uint16_t` casts. Generated tag names, validation and dumps follow the schema; the existing integer-subset bound includes these operations.
- No bytecode revision, runtime scalar algorithm, GC policy, native continuation layout, compatibility adapter or new residual type changed. Generated internal unary tag ordinals change; these are not a persisted bytecode encoding or public tooling API.
- Migrated `tools/validate_continuations.lua` semantically: CALL arguments are gathered on its selected bank; RET source is independently varied. Wide vectors return directly from the chosen bank rather than reproducing the old cross-stack reversal. Necessary scalar MOVE transport remains explicit.
- Expanded continuation coverage to warm frame reads followed by escaped-caller writes, partial pointer stores observed through both pointer and frame reads, overlap-safe frame copies, and callee traps with live prefixes. Mirrored cases execute in all three VM modes.
- Corrected the call-graph validator's Makefile dependency/link to the tooling archive, where call-graph analysis belongs. Runtime remains independent of tooling. The migrated continuation suite now runs before legacy/frontend fixtures in `make validate`.

## Checked

Strict Clang 20 normal Makefile build succeeds. Component evidence:

- **263** residual-builder/IR checks, including fixed-byte ZX8/ZX16 tests for semantic identity, selected return transport and U32 representation.
- **32** mirrored portable-C execution cases. Six normalization modules (ZX8/16/32, A/B) each test eight boundary/full-width inputs with an untouched copy in the ordered result vector. Inputs are unknown to the residual builder, exercising parameterized narrowing rather than ABC-side literal folding; the host C compiler may optimize the test driver. Generated C compiles with strict warnings and only the existing unused-generic-helper exception.
- **495** continuation executions: independent CALL/RET banks, argument counts 0/1/2/9/12, zero/single/vector results, live caller values, recursion, mutual tails, HOME capture, stack exhaustion, escaped/partial/overlapping storage and callee traps. This replaces the old 243-execution historical evidence for this suite.
- Optimizer suite remains **48 mirrored modules / 228 original-versus-optimized execution pairs**.
- Full `make validate` now links the call-graph validator and passes the early ISA/native/ASDL/IR/symbolic/capture checks, but **does not pass overall**: `tools/validate.lua` still emits historical `MOVE_BA` and the assembler rejects it. The continuation suite now runs and passes before that failure boundary. Portable-C execution checks above were run separately.

Logs are `phase-3-normalization-{build,ir,c,continuations,optimizer,full-validate}.log`.

Reproduction:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
 WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' \
 all build/validate-residual-ir validate-optimizer-isa
build/validate-residual-ir
luajit tools/validate_continuations.lua
/tmp/clang20 -O2 -std=c11 -Wall -Wextra -Wpedantic -Werror \
 -Wno-newline-eof -Iinclude \
 research/experiments/ab-symmetry/builder-emit-c.c build/libabc-tool.a -lm \
 -o /tmp/abc-phase3-normalization/emit-c
luajit research/experiments/ab-symmetry/check-builder-c.lua \
 /tmp/abc-phase3-normalization/emit-c /tmp/clang20 /tmp/abc-phase3-normalization/aot
```

The temporary missing-newline failure in the new C test driver was fixed in the harness without suppressing that warning. No implementation test failures remained in these focused suites.

## Benchmark checkpoint

See `phase-3-tooling-bench/README.md`. Baseline measurements were preserved, with a new interleaved run of frozen/current runtime and optimizer output. This is not the final old/new ISA or frontend benchmark. Broader legacy fixtures/frontend migration and full-suite validation remain open.
