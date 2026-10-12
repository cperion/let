# Phase 3 — selected-stack memory bindings

Status: memory transfer/binding source migration implemented; integration into the complete symbolic/native/optimizer pipeline remains unvalidated.

## Approved contracts

`docs/symmetric-isa.md` defines selected-address/opposite-value pointer stores, selected-base/opposite-index indexed operations, and selected-destination/opposite-source MEMCPY. MEMCPY has a u32 byte count and must be overlap-safe. No stack-capacity, allocation, continuation or GC policy change is part of this chunk.

## Changes

- `src/symbolic.c` / `src/symbolic.h`: memory transfers read authoritative instruction metadata at the current PC. Removed the redundant opcode argument from the helper and its generator call. The callback's first/second operands follow selected/opposite roles; indexed results replace the selected top and consume the opposite top. Neutral C allocation/free remain separate actions.
- `src/residualize.c`: replaced the removed memory descriptor with `abc_instruction_metadata`. Indexed-address allocation now uses the selected stack rather than A. Native MEMCPY now reads all four count bytes.
- `gen/stencils.lua` / `src/residualize.c`: removed the forward-only native copy loop. A dedicated relocation binding supplies the u32 count and the existing `memmove` address to the memory-copy stencil, matching the interpreter's execution mechanism. No separate copy algorithm, ABC repacking, allocator or return-layout change was introduced. The library call is not a recursive ABC call.
- `src/residual_builder.c`: memory IR construction uses authoritative action/width/sign/layout metadata; IDX results retain the selected destination rather than becoming A results. Its existing u32 copy count and ordered memory effects remain intact.
- `src/optimize.c`: memory nodes recognize relocated loads through semantic identity. Memory serialization places operands on selected/opposite stacks and chooses the paired output opcode for the requested result stack instead of retaining an incompatible original destination. Frame-allocation classification uses current metadata.
- The old `abc_memory_op`, `op_memory` and `.to_b` memory interfaces have no remaining references under `src/`, `gen/` or `tools/`.
- Portable C's existing integer/static-profile restriction is unchanged; this chunk does not enable memory-profile C output.

## Checks actually run

- Generated and compiled all 3,800 native stencils with the production stencil compiler flags; the normal extractor succeeded: 82,109 extracted code bytes and 3,096 tail jumps removed. These are current artifact sizes, not a final baseline/performance comparison.
- Expanded the direct native primitive validator from 19 to 27 cases. Eight new copy cases cover both register orientations, forward/backward overlap, identical pointers and disjoint ranges, using 65,539 bytes. Expected bytes come from a saved original image, not from another call to the same copy primitive. All untouched registers and stack pointers remain checked.
- Expanded the assembly/loader/verifier/interpreter check from 14 to 16 original/mirrored cases. The added overlap case moves a sentinel above offset 65,535, detecting truncated counts as well as forward-only copying.
- Both validators pass; see `phase-3-memory.log`.
- Added eight direct symbolic memory callback/placement cases to `tools/validate_symbolic.c`. **Not run yet:** the containing symbolic component and its dispatcher are still incomplete.
- A fresh syntax-only diagnostic of `src/symbolic.c` no longer reports the removed memory interface. It still fails on fourteen old scalar/EXT/control opcode-name references. This is a migration diagnostic, not successful compilation.
- `git diff --check` passed on changed implementation/test files.

## Reproduction

Generate, compile and extract stencils as in `phase-3-binary.md`. The expanded primitive test requires an absolute count hole:

```sh
check=/tmp/abc-symmetric-stencils
objcopy --localize-symbol=calloc "$check/stencils.o" "$check/test-stencils.o"
/tmp/clang20 -O2 -std=c11 -Wall -Wextra -Wpedantic -Werror \
  -fno-pie -no-pie -Wl,--gc-sections -Wl,--defsym=HOLE_IMM=65539 \
  tools/validate_stencil_operands.c "$check/test-stencils.o" \
  -o "$check/validate-operands"
"$check/validate-operands"
luajit tools/validate_symmetric_interpreter.lua \
  /tmp/abc-symmetric-isa-check/abc-runtime
```

The test defines the copy-function hole to call `memmove`. Production supplies that address through native relocation binding. The `calloc` symbol localization is only for linking a test object; production uses extracted stencil bytes.

## Remaining limitations

Native tests exercise the generated primitives, not `place_memory_copy` inside a compiled ABC function. Symbolic/native sink and optimizer/residual-builder memory integration still require a coherent full build and end-to-end tests. No complete JIT, optimizer, symbolic capture/continuation suite or performance comparison was run.

Next remains the approved phase-3 migration: replace remaining scalar/control operation interfaces and the shared dispatch generator, then complete call/return/site ownership and downstream tooling. Do not add old-opcode aliases just to compile the intermediate tree.
