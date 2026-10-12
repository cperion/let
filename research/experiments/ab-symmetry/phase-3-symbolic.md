# Phase 3 — shared symbolic engine checkpoint

Status: the shared symbolic component now compiles and its focused validator passes. The entire migration is not complete. Native call/return/site binding, residual-builder/optimizer consumers and frontend integration remain outstanding.

## Implemented

- Replaced `gen/symbolic.lua` completely. It binds `gen/semantics.lua` transfers to both selected banks, including the actual typed EXT selector tables. Instruction-end offsets include prefixes and SWITCH tables. The old `semantics.symbolic` interface and reserved-EXT boundary implementation are gone.
- Scalar and control callbacks now receive `ABC_OPERATION_*` identities, not canonical A opcode bytes. Selected stack is explicit for float unary/conversion, power, checks, CPUSHN, SWITCH and HALT.
- Replaced hand-maintained integer/unary/float folding switches with `gen/fold.lua`, generated from the same scalar expressions and divisor-check property as the other bindings. Added normal/PIC build dependencies. No old-opcode compatibility aliases were added.
- Shared direct/indirect calls gather from the selected argument bank. CALL's destination also identifies its argument source; indirect tail effects distinguish argument source from continuation destination.
- Shared RET uses an explicit source stack, validates private A/B shapes independently, preserves both prefixes and transports ordered results to the continuation's destination. Tail calls retain the continuation destination.
- Captured tail arguments/return values stay in the symbolic allocation context until transport, rather than becoming a second residual-value structure or untracked temporary register list.
- Foreign effects carry their selected bank.
- Deleted the obsolete generic `emit_effect` interface and rewritten-opcode rejection callbacks from shared/native/optimizer/residual-builder code. Actual typed effects retain their explicit callbacks.
- Migrated native scalar bindings to the semantic identities and selected banks. C-operand native bindings decode the full EXT operand view. Scalar constant folds are no longer recomputed by those native bindings.

## Validation actually run

Compiled current `src/symbolic.c`, generated `symbolic_dispatch.c`, and generated `symbolic_fold.c` under Clang 20 with strict warnings, then linked them ahead of the preserved dependency library with current loader/verifier objects.

`tools/validate_symbolic.c` passes:

- eight selected integer/float binary constant/HOME contracts;
- eight selected-address memory callback/result contracts;
- eight CALL/RET combinations, with two ordered results, both live prefixes, and direct-tail variants preserving the original continuation destination;
- four mirrored scalar/EXT programs exercising selected POW, checks, float conversions, CPUSHN and SUBC;
- narrow unary folds and the existing context, control, fusion and version-limit regressions.

Output is retained in `phase-3-symbolic.log`. These tests execute the new shared engine and generator, not the old symbolic object from the preserved library.

A syntax-only check of `src/residualize.c` with current headers also passes. **This does not validate native call/return semantics:** several bindings still have the old A-only transport and private observation ownership. Full optimizer/residual-builder compilation is still pending. The full capture/continuation suite and performance comparison have not run.

## Native return protocol decision — subsequently approved

Inspection of `native_emit_call()` / `native_emit_return()` found the remaining general native protocol publishes result vectors in A; specialized single-result recursion uses r0. Its C continuation cell contains a resume address, not the interpreter's separate destination field. Simply canonicalizing every RET.B through A can require hidden A capacity when the caller's A prefix is live. Duplicating callee bodies by destination would violate the specified bank-independent function contract.

Proposed binding for discussion:

1. Keep the current continuation cell, its position, and all C-base/rebase rules.
2. Publish general result vectors in the RET-selected private bank, not an intermediate bank.
3. At return transfer only, use existing r2 as an explicit result-source tag. It is not reserved during execution and is not a bank-orientation mode. Keep existing r0 single-result and r1 continuation uses where applicable.
4. The call-site resume binding knows CALL's destination. It transports the vector directly when source and destination differ, then restores caller coordinates under the existing convention. No extra ABC cell is introduced.
5. Host-sentinel delivery handles either source explicitly; indirect calls use the same resume protocol and explicit ABC control transfer, never host-recursive ABC calls.

This changes the private return register protocol, although it preserves the physical C return-slot layout. The user explicitly approved it with “i a pprove !”. Implementation and validation are tracked separately; this earlier checkpoint does not establish either.

Required evidence for that binding: non-inlined/recursive multi-result calls across all four bank combinations, mixed RET sources in one callee, untouched full caller prefixes, exact capacity boundaries, tail/indirect preservation, escaped-address/capture regressions, and host delivery from either source. Benchmark any resulting extra branch/transport cost rather than claiming it is free.
