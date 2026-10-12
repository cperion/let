# Phase 3 — approved native return-source binding

Status: implemented and checked for direct calls, direct tails, host returns/HALT and selected-bank foreign calls. Native indirect calls/shared observation remain unmigrated. This is not completion of phase 3 or the ISA migration.

The user approved the r2 return-source protocol with “i a pprove !”. No additional physical continuation cell, frame-layout change or permanently reserved register was introduced.

## Implemented

- `native_emit_call()` now computes both caller-prefix bases from the shared continuation and gathers arguments from CALL's selected bank. Existing recursive argument-register specialization is retained without assuming an A source.
- Real general returns publish vectors in the RET-selected private bank. After publication, r1 loads the existing C continuation and r2 carries the explicit source selector. The existing specialized single-result r0 ABI remains in use.
- A caller resume knows its destination, tests r2, and transports results directly between private banks only when necessary. It then restores the existing caller coordinates. There is no canonical-A scratch vector.
- Host-sentinel detection now belongs to the return binding. The generic CONTINUE stencils perform only explicit control transfer; they no longer independently interpret the sentinel. Host delivery from RET.B and HALT.B reaches the existing A output buffer, where host entry has no live operand prefixes.
- Direct-tail capacity checks use the selected argument source while preserving the original continuation and C-base convention.
- Foreign generation now emits selected-bank zero/one-result bindings from one definition. The native foreign sink saves and gathers the selected argument vector, and the bridge publishes on that same bank. The opposite live prefix is retained.

## Validation actually run

Freshly generated and compiled all 3,802 stencils, then ran the ordinary extractor: 82,332 extracted code bytes, 3,098 tail jumps removed. These are intermediate artifact sizes, not final performance measurements.

Compiled current `src/residualize.c` with strict Clang 20 warnings and linked it with the new VM, loaders/verifier, symbolic engine/dispatch/folds and banked handlers. Remaining dependency objects came from the preserved library; the old native residualizer was not used.

`tools/validate_native_returns.lua` passes **33 checks** across interpreted, eager and lazy execution:

- all four CALL/RET bank combinations with ordered two-result vectors and both caller prefixes;
- real recursive calls, deliberately preventing the tests from validating only inlining;
- one callee with both A and B return paths;
- an entirely full A prefix during a B-only two-result call at eight cells, plus rejection at seven cells;
- the existing single-result register path using B;
- tail calls that change the argument count/C extent without replacing the caller's destination;
- host RET.B and HALT.B delivery.

The existing banked/call C validator now passes **27 cases**. Its foreign cases cover A/B and zero/one result in all three modes, with an untouched opposite prefix and a checked host side effect for void returns. Other cases in that validator, including indirect observation history, remain interpreted checks—not native indirect evidence.

Output: `phase-3-native-returns.log`. Both validators are registered for eventual integrated `make validate`. `git diff --check` passed on changed files.

## Isolated build reproduction

Generated stencils: `/tmp/abc-symmetric-stencils`, using the generator/compiler/extractor commands recorded in `phase-3-binary.md`. Current generated native include paths are linked under `/tmp/abc-symmetric-native-include/generated`.

Compile `src/residualize.c` with:

```sh
/tmp/clang20 -O1 -std=c11 -Wall -Wextra -Wpedantic -Werror \
  -Wno-newline-eof -I/tmp/abc-symmetric-isa-check \
  -I/tmp/abc-symmetric-native-include -Iinclude -Isrc \
  -c src/residualize.c -o /tmp/abc-symmetric-isa-check/residualize.o
```

Link `src/cli.c` or `tools/validate_banked_isa.c` with the isolated new objects:

```text
vm.o module.o memory_module.o verify.o
symbolic.o symbolic_dispatch.o symbolic_fold.o residualize.o
banked_0.o ... banked_7.o
build/libabc.a -lm -lpthread
```

Then run:

```sh
/tmp/abc-symmetric-isa-check/validate_banked_isa-native
luajit tools/validate_native_returns.lua /tmp/abc-symmetric-isa-check/cli-native
```

## Remaining boundaries

- Native indirect handling still contains its old private site/phase-patching ownership and host-recursive helpers. It must be replaced by shared checked resolution, explicit frame transport and explicit transfer using the same resume contract. Do not use the isolated runtime's native indirect paths as conforming implementations.
- Full capture/escaped-address, deep continuation, resource-limit and foreign-ABI suites have not run against this build.
- Optimizer/residual-builder scalar and calling consumers, frontend migration, the whole-tree clean build, full validation and fixed performance comparison remain unfinished.
