# Phase 4 — general validator migration, blocked by floating branch contract

## Scope and implemented test changes

The approved fixture migration resumed in `tools/validate.lua`. The runner now constructs revision-6 programs directly, selects the primary operand bank for both destinations, fixes B call argument gathering, and mirrors complete valid programs. It retains the previous independent numeric/vector/branch expectations and exact trap/resource diagnostics. Indirect targets load directly to the opposite bank; their capacity-failure origins move from byte 0xb to 0xa because the old repair MOVE is removed.

The coverage walker now decodes complete core, EXT and SWITCH instructions, distinguishes both EXT banks and requires all 282 public selected/neutral instruction forms. This measures assembled forms, not a claim that every branch executes. Bound foreign execution remains in the API validator. Process status comes from an explicit shell exit marker, not LuaJIT popen-close behavior. Existing bootstrap-oracle calls are retained and clearly separate from production compilation; their old instruction emission remains a subsequent dependency to resolve.

**This migration is not validated or complete.** Integer arithmetic original/mirror executions pass all three tiers, then the float fixture passes interpreted execution and fails eager preparation at FBLE. Later fixtures, coverage completion and the bootstrap calls have not run in this new validator. No runtime files were changed.

## Reproduced runtime defect

Six minimal modules test FBLT, FBLE and FBEQ in both banks, using runtime float arguments and returning a scalar boolean. Each selected predicate should be true:

- FBLT/FBLE: 1.5 compared with 2.0;
- FBEQ: 2.0 compared with 2.0.

All six interpreter runs return 1. Eight eager/lazy FBLT/FBEQ runs incorrectly return 0 with success status. Four eager/lazy FBLE runs fail compilation. Eager reports `out-of-memory at byte 0x2: symbolic control emission failed`; lazy reports a compiled-execution failure at byte 0. This is not evidence of actual memory exhaustion.

Producer/consumer trace:

- `gen/symbolic.lua`: FBLT=0, FBLE=1, FBEQ=2.
- `src/symbolic.c`, `abc_symbolic_machine_control`: constant folding interprets those float-specific ordinals as LT, LE, EQ.
- `src/symbolic.h`: the shared relation enum is EQ=0, NE=1, LT=2, LE=3, LTU=4, LEU=5.
- `src/residualize.c`, `native_emit_control`: float controls expect the shared relation enum. Thus LT becomes EQ, EQ becomes LT, and ordinal 1 is rejected.
- `src/residual_builder.c`: also consumes the shared enum for float branch relations.
- `src/optimize.c`: unknown float control remains outside its supported rewrite subset; known control consumes the shared folder's decision. Its eligibility policy must not be expanded as part of this correction.

## Proposed correction — approval pending

Use the existing shared relation enum end to end, rather than adapting sinks to the wrong float-only numbering:

1. Emit symbolic enum names for branch relations in `gen/symbolic.lua`, including FBLT→ABC_SYM_LT, FBLE→ABC_SYM_LE and FBEQ→ABC_SYM_EQ.
2. Make float constant folding in `src/symbolic.c` interpret those same named relations; document the callback relation invariant in `src/symbolic.h`.
3. Keep native stencil selection and residual-IR mappings on the shared enum; no new scalar algorithm, compatibility mapping, encoded byte change or backend fallback.
4. Add generated-dispatch/fold relation assertions and residual-IR branch checks; execute both banks in all modes on ordered, equal, unordered/NaN and signed-zero cases. Check constant-folded and runtime-input paths agree, preserving live prefixes.
5. Rerun the general validator, symbolic/IR regressions, optimizer and SLet suites. Any later fixture/runtime failures remain explicit, not bypassed.

No representation, calling convention, placement, continuation, GC, stack-limit or optimizer eligibility change is proposed. No benchmark rerun is needed for this focused correctness correction. The recent scalar-u32 benchmark contains no floating workloads and does not establish float correctness.

Evidence: `phase-4-general-blocker.log`, `phase-4-float-branches.log`, and the minimal source/probe snapshot in `phase-4-float-branches/`.
