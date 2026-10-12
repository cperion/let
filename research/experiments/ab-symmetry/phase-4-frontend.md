# Phase 4 — typed frontend lowering, first checked implementation

Approved design: destination-parametric lowering, selected-first operands, left-to-right evaluation, independent call/return banks, no new scheduling/allocator/GC/continuation policy. This checkpoint is **partial phase 4**, not full frontend migration.

## Implemented

`frontend/let/abc.lua` now threads a destination through typed expressions, literals, references, aggregate frame loads, addresses/indexing, unary operations, normalization, conversions/checks, stores, argument gathering and call/tail/indirect helpers.

- Binary left/right expressions target selected/opposite stacks directly; removed the old two-on-A plus operand MOVE path.
- Greater/greater-equal still evaluate the left expression first. The comparison selects the opposite bank to implement right-less-than-left, then transports the boolean result. Floating comparisons do not substitute negated ordered comparisons, preserving NaN behavior.
- Memory stores leave the value on its bank and compute the address on the opposite bank, removing the old value-repacking MOVE. Existing frame layout and aggregate component order remain.
- Numeric checks/conversions and memory instructions use explicit revision-6 suffixes. Typed callable adapters use explicit tail forms.
- ANF statement boundaries still default to A; no new bank-selection cost model was introduced. Functions retain one body and an explicit RET.A source. A hand-assembled CALL.B consumer of a generated function independently verifies vector return transport with live prefixes on both stacks.
- Dynamic scalar operations deliberately do not regain an A-only implementation. Their unavailable runtime lowering now reports an unsupported diagnostic. Broader legacy profile-5 frontend-only emission remains unresolved below; it has not been removed or reported migrated.

## Optimizer defect found by frontend evaluation-order tests

A known-failing numeric check set `terminal_abort` but emitted a nonterminal CHECK, leaving invalid bytecode ending without a terminator. It now emits the numeric-range ABORT already used by the residual-IR binding, at the original check PC. Earlier effects remain before it. No fallback or scalar check algorithm was added.

New mirrored constant-check tests validate status/diagnostic/provenance. Frontend tests place a division-by-zero before a failing conversion inside > and >=: both original and optimized execution must report the earlier division error. Portable C additionally checks reason 1, original offset 4 and unchanged failed outputs.

## Validation

- Normal strict build succeeds.
- New `make validate-frontend-symmetric`: **33 execution processes** covering nested B subtraction/division, live prefixes, independent CALL.B/RET.A vector transport, NaN comparisons in both expression destinations, and competing-trap evaluation order. Original and optimized ABC run interpreted/eager/lazy; the applicable integer fixtures also execute generated portable C. The float fixture is not claimed as portable-C coverage.
- Assembly assertions require B arithmetic and exactly one MOVE for the reversed comparison result, ruling out general operand-orientation repair.
- Existing lowering suite: **78 checks**. Some are historical managed assembly-only assertions; these do not validate any dynamic runtime.
- Existing staging suite: **24 checks**.
- Optimizer suite: **50 mirrored modules / 234 original-versus-optimized execution pairs** after the known-check regression addition.
- Builder/IR: **263 checks**; continuation suite: **495 executions**.

Logs: `phase-4-frontend-{build,symmetric,regressions}.log`, `phase-4-runtime-regressions.log`.

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
 WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' \
 all validate-frontend-symmetric validate-optimizer-isa
(cd frontend && luajit tests/lowering.lua && luajit tests/staging.lua)
```

No benchmark rerun or performance claim for this change.

## Remaining integration and decision boundary

- `frontend/tests/optimize.lua` still constructs old-ISA fixtures; its first assembly fails on bare RET. Main `tools/validate.lua` retains old instruction spellings and operand assumptions. These remain unmigrated, not bypassed.
- `frontend/tests/compiler.lua` reaches a legacy dynamic word/binary example and expects successful profile-5 **assembly-only** output. It now encounters the intentional unsupported dynamic-binary diagnostic. Earlier foreign assertions were updated to FCALL.A, but the full compiler suite does not pass. Failure evidence: `phase-4-compiler-blocker.log`, `phase-4-optimizer-fixtures-blocker.log`.
- The existing API distinguished unsupported *execution* from producing obsolete profile-5 text. Removing that text backend entirely would change an existing frontend-only artifact contract. Proposed next decision: retain Let parsing/typechecking/IR construction, but reject dynamic ABC lowering explicitly until reintegration, replacing obsolete assembly assertions with IR/diagnostic checks. This broader boundary change is **proposed, not approved or implemented** here.
- Remaining active fixtures/examples and the full source/optimizer/API suite still need migration. No phase-4 completion claim.
