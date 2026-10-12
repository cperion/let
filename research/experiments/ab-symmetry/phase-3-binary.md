# Phase 3 — binary operand orientation chunk

Status: historical binary-chunk evidence within partial phase 3. Native primitives were checked; the complete symbolic/native pipeline was not built or validated. The primitive validator has since gained memory cases; see `phase-3-memory.md` for current counts and results.

## Contract and changes

Following `REFACTOR.md` phase 3, binary integer and float inputs are selected-stack first and opposite-stack second. Destination B does not reverse the operation.

- `src/symbolic.c`: both binary transfer functions now select their left input from the result/selected stack. Constant folding and callbacks receive that same order. Existing consumed-stack effects and prefix preservation remain in place.
- `src/symbolic.h`: documents the callback operand-order contract.
- `src/residualize.c`: integer and float binary emission bind the existing selected writable register and opposite register directly to ordinary stencils. Removed the B-subtraction exclusion from narrow-result fusion and used the new instruction-length interface in this binary path. No new allocator, residual-value representation or orientation repair was added.
- `gen/stencils.lua`: deleted integer, narrow-integer and float reverse families (2,048 generated variants). Rebased subsequent layout sections. Corrected the unary section size to use the shared unary list, which now includes ZX8 and ZX16. Divisor guards use the shared transfer's `check_zero` property; generated C is byte-identical to the preceding guard spelling.
- `tools/validate_symbolic.c`: added eight direct symbolic integer/float, A/B, constant/HOME callback contracts, including untouched prefixes. **These new symbolic cases have not run:** the whole symbolic component still has unmigrated instruction/control/call interfaces.
- `tools/validate_stencil_operands.c`: direct native primitive ABI checks, registered in the full Makefile. These do not claim to exercise symbolic allocation or a complete compiled ABC function.

## Validation actually run

In `/tmp/abc-symmetric-stencils`:

1. Generated all 3,800 remaining stencils.
2. Compiled the complete generated stencil C object using the production stencil compiler flags.
3. Ran the normal extractor successfully: 3,800 stencils, 98,202 extracted code bytes, 3,096 tail jumps removed. These are current artifact measurements, **not** a baseline/final performance comparison.
4. Compiled 17 independent layout-to-order assertions across the changed sections and later boundaries, through the final lazy-entry stencil. Confirmed no reverse family names remain.
5. Executed 19 native primitive contracts: selected-first subtraction, division and divisor traps; narrow subtraction in both register orientations; floating subtraction/division/comparison and NaNs. Every successful case checks all untouched registers and all three stack pointers.
6. `git diff --check` passed for the changed implementation/test files.

The test linker needs a copy of the generated object with its `calloc` symbol localized: that name is a stencil label and must not interpose on libc's allocator. Production extracts bytes and does not use this direct object link. No production compatibility path was added.

```sh
check=/tmp/abc-symmetric-stencils
mkdir -p "$check"
luajit gen/stencils.lua "$check"
/tmp/clang20 -O2 -std=c2x -w -fno-builtin -fno-pic -fno-pie \
  -fcf-protection=none -fno-asynchronous-unwind-tables \
  -ffunction-sections -fno-stack-protector \
  -c "$check/stencils.c" -o "$check/stencils.o"
luajit tools/extract_stencils.lua "$check/stencils.o" \
  "$check/stencils.order" "$check/stencils.h"
objcopy --localize-symbol=calloc "$check/stencils.o" "$check/test-stencils.o"
/tmp/clang20 -O2 -std=c11 -Wall -Wextra -Wpedantic -Werror \
  -fno-pie -no-pie -Wl,--gc-sections -Wl,--defsym=HOLE_IMM=65539 \
  tools/validate_stencil_operands.c \
  "$check/test-stencils.o" -o "$check/validate-operands"
"$check/validate-operands"
```

Output at this checkpoint: `native selected-first primitives: 19 contracts, other registers preserved`. The commands above include the count-hole binding required by the subsequently expanded validator.

## Still pending

The shared dispatch generator, remaining symbolic selected-stack forms, operation-identity migration, native call/return transport and common observing-site ownership remain unfinished. Existing native host-recursive indirect helpers and phase-patching paths still require replacement under the approved plan. Optimizer/residual ABC/C consumers, frontend lowering and full integration remain pending too.

The changed symbolic and native sink functions have not yet been compiled as part of a coherent current-source runtime. No whole-program eager/lazy execution, continuation/capture regression suite or final performance comparison was run for this chunk. Do not mark phase 3 complete based on the primitive tests.
