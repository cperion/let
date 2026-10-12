# Phase 4 — approved shared floating-branch relation correction

The user approved correcting the producer/folder contract exposed by the general validator. This supersedes the pending proposal in `phase-4-general-blocker.md`; the historical failing evidence is preserved.

## Changed responsibility

- `gen/symbolic.lua` emits named shared `ABC_SYM_*` relations for all branch controls. In particular, FBLT uses LT, FBLE uses LE and FBEQ uses EQ. The separate float ordinal convention (0/1/2 meaning LT/LE/EQ) is removed.
- `src/symbolic.c` interprets those same named relations when folding constant floating branches, using the existing `vm_flt`/`vm_fle`/`vm_feq` semantics.
- `src/symbolic.h` documents that integer and float control callbacks carry the shared relation enum, not a stencil index or byte opcode.
- Native emission and residual-builder consumers remain unchanged: their existing shared-enum contract was correct. No compatibility translation, alternate scalar algorithm or backend fallback was added.

No bytecode encoding, public ABI, representation, placement, continuation, GC, stack-limit or optimizer eligibility change. Portable C remains its supported subset; residual float IR validation does not claim float C emission support.

## Regression coverage

- `tools/validate_symbolic.c`: **96** generated-dispatch contracts (three relations × two banks × folded/runtime-symbolic inputs × eight operand cases), plus the existing 28 selected-bank contracts and other regressions. Checks relation identity, constant truth, selected-first operands and untouched live prefixes.
- `tools/validate_residual_ir.c`: six independent encoded float-branch modules check residual relation and argument order. **299** total IR checks pass (previously 263).
- `tools/validate.lua`: independent LT/LE/EQ truth tables for less/equal/greater, NaN on either side, both signed-zero orientations and infinities. Runtime arguments and folded scalar producers run with both-bank live prefixes. The overall migrated core suite passes **92 oracle cases / 552 executions**, including **288** new float-branch executions, across interpreter/eager/lazy and A/B mirrors.
- All **282** public core/EXT forms are assembled and traversed by the complete-instruction coverage walker. This is assembly coverage, not a claim that every branch path executed.
- Updated the negative float-kind fixture to require the current unified verifier's nonzero status and exact FADD failure location, rather than an obsolete error-message phrase.
- The original 18 minimal probes now all return the expected boolean with success status, including FBLE in both native modes.

## Integrated validation

Normal strict build succeeds. `make validate` passes all early migrated suites: **50 optimizer modules / 234 execution pairs**, **259 compiler checks**, **81 lowering checks**, **105 frontend optimizer checks**, **24 staging checks**, **33 symmetric frontend execution processes**, **299 IR checks**, symbolic contracts, API examples/observations, capture and **495 continuation executions**.

It then passes the 552-execution general core suite and stops at the retained historical bootstrap frontend:

```
bootstrap-fibonacci: abc: line 3: unknown instruction BGEUI; selected forms require .A or .B
```

**Full validation remains incomplete.** The bootstrap boundary was not removed, skipped or silently redirected. Its producer/fixtures and later cache/example integration still need migration or an explicitly discussed retirement. No performance rerun or whole-phase completion is claimed.

Reproduction:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
 WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

Evidence: `phase-4-float-correction-{build,symbolic,ir,general,probes,full-validate}.log`. The full-validation log is the final integrated run. The prior wrong-answer/failure logs remain unchanged.
