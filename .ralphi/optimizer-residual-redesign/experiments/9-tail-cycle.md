# Round 9 — a canonical fixture pins what a generic residual entry cannot carry

**Mode:** experiment (a measured oracle on a live in-repo fixture).
**Probe:** `experiments/9-tail-cycle.lua`, artifacts in `experiments/9-tail-cycle-out/`
(`monomorphic.{opt,raw}.{abc,dis}`, `two-callers.{opt,raw}.abc`, `*.c`).

Candidate questions, ranked by materiality (could the answer change correctness,
the data representation, the number of concepts, or violate a requirement?):

| # | Question | Why this rank |
|---|----------|----------------|
| A | A canonical fixture (`frontend/tests/compiler.lua:790-804`, `docs/abc-opt.md:100`) pins **residual-entry invariant specialization** for a mutual tail-recursive SCC. The design's residual entry is the generic all-location key (Q7). Is that documented precision recoverable by any key rule — and what does the design's inline rule for cross-function tail cycles (Q14) have to say? | Decides whether an in-repo, currently passing assertion survives, whether Q7's stated justification ("lost constants are recoverable at virtual entries") is true, and whether a module-wide cycle fact (the only cross-function loop fact) is needed. It also *forces* Q14 instead of leaving it open. |
| B | Q2's scope: is "total versions per pc" enforceable by a one-pass driver? | Material (a hard gate), but the answer turned out to be a corollary of round-7 reasoning (a new *family* at a pc arrives on a call edge; a join can only add a value key inside an existing family), so no new measurement was needed and the design-side answer is already recorded. |
| C | Q12's fact ownership (heights/CSET/cycle-body pass). | Medium: compile-cost and one-owner tidy-up; no representation or correctness change beyond what round 6 fixed. |

## What was read

- `frontend/tests/compiler.lua:790-804`: the mutual `even`/`odd` fixture, staged with
  the **default** `optimize=true`, so the module it disassembles is `abc-opt`
  output. It asserts exactly 3 functions, a `TCALL`, and both `PUSH8_A 9` and
  `PUSH8_A 10`. It is part of a live target (`Makefile:212`; the suite passes with
  268 checks).
- `docs/abc-opt.md:100`: "mutual or genuinely non-tail SCC transfers remain
  explicit `CALL`/`TCALL` operations while invariant arguments still specialize."
- `src/optimize.c:108-114` (`nested_eligible = recursive && component size == 1 &&
  !nontail`), `:299-318` (`dag_call`/`dag_tail`: only a same-function self-tail
  cycle is inlined; every other recursive call becomes `N_CALL`/`N_TAIL`),
  `:850-873` (the per-argument entry-fact join and dirty rebuild).
- `docs/spec.md:167-170`: `CALL.X f n` gathers argument zero at `C0`; a callee has
  empty private A/B stacks. So an ABC residual entry's frame *is* the
  all-location form — the entry rule is expressible, with no entry prologue. That
  was a side check, not a question.

## Measured

The probe reproduces the fixture verbatim and additionally stages it with
`optimize=false`, and compiles a two-caller variant (`even(4,9) + even(4,7)`) where
the incumbent's entry join must widen `marker`.

1. **The fold is abc-opt's entry facts, not frontend lowering.**
   - pre-optimizer: 48 instructions; callee bodies read the parameter
     (`CGETN_A 4` / `CGETN_A 3`) and add; the only `PUSH8_A 9` is `main`'s argument.
   - abc-opt: 21 instructions; `even` returns `PUSH8_A 9` and passes `PUSH8_A 9` to
     `odd`; `odd` returns `PUSH8_A 10` (folded `marker + 1`) and passes `PUSH8_A 9`.
     Four `PUSH8_A 9`, one `PUSH8_A 10`, zero `ADD`, three `TCALL`, three functions.
   - Value 9 in off/threaded/eager/lazy; `opt` is a byte-identical fixpoint.
2. **The two-caller variant is the measured oracle for the design's entry policy.**
   When callers disagree, the incumbent widens `marker` and emits exactly the body
   a *generic* entry must have: `even` = `CGET1_A` in both places (9 instructions,
   unchanged), `odd` = `CGET1_A; ADDI_A 1; ZX32_A` where the monomorphic body has
   `PUSH8_A 10` (9 → 11 instructions). Value 16 in all four modes. So the design's
   residual entry does not invent a new code shape; it is the incumbent's existing
   shape for the disagreeing-caller case, applied to every caller.
3. **The design's delta on the canonical source is +2 instructions**, module
   21 → 23 (odd's body 9 → 11); the function count and the three `TCALL`s are
   preserved; both `PUSH8_A 9` and `PUSH8_A 10` disappear from the callee bodies.
   The two assertions at `compiler.lua:803` are exactly what stops holding.

## Why no key rule can fix it

A key is content: constants, locations, frame coordinates, the continuation chain.
A residual call's callee is entered through the ABC call ABI, which places
arguments in **locations** (`docs/spec.md:167-170`), and the callee's body is
shared by every caller. So at a residual entry there is no constant to keep, at
*any* pc of the entry version — and the loop rule cannot create one either: it
preserves constants **already present in the key**, so on an all-location entry
key it is a no-op (round 8's fixed-point observation). This kills the round-8
suggestion that a module-wide cycle body would preserve a mutual SCC's invariant
arguments. The only mechanisms that can carry a caller constant into a callee body
are (i) the incumbent's per-argument entry join (with its discard/rebuild), and
(ii) inlining, which makes the callee a virtual entry.

## The three policies for a cross-function recursive call (Q14)

| Policy | Constants at the callee | Documented shape (`3 functions`, `TCALL`) | Concept cost |
|--------|------------------------|------------------------------------------|--------------|
| (a) residualize (incumbent's `nested_eligible`, derived) | no: +2 instructions measured on the fixture | preserved | none: one clause over existing module facts |
| (b) inline the tail-only SCC as a version cycle | yes while exact keys exist at the header; the all-location budget slot widens `marker` too unless a cross-function cycle body exists | broken (1 function, no `TCALL`) and the cycle is duplicated per call site | a module-wide cycle body + a cross-function transport relation (Q14's rejected cost), plus export/address-taken exclusions |
| (c) keep the per-argument entry lattice | yes (21 instructions) | preserved | a second worklist level and whole-function rebuild; violates "each version body executed once" (`optimize.c:850-873`) |

(b)'s constant recovery is a projection, not a measurement: the exact-prefix part
follows round 5's measured exact-key loop (7 folded header versions + a generic
tail, 29 instructions vs 16) and the all-location slot is total inside a family.
Only (a) and (c) preserve the documented shape; (c) is the mechanism Q7 deleted on
the grounds that the lost constants are "recoverable at virtual entries" — true for
acyclic and self-tail inlining, **false for a residual recursive call**.

## Decision

**(a).** The core's inline rule inlines a direct call only when it is (i) acyclic,
or (ii) a tail call to the owning function's own entry in a tail-only component of
size 1 — the incumbent's derived `nested_eligible` case. Every other recursive
call, tail or not, same-function or mutual, is a residual call at the callee's
generic entry; the loop rule therefore applies only to a self-tail cycle inlined
into its caller. No module-wide cycle body, no cross-function transport fact, and
the residual-entry specialization documented at `docs/abc-opt.md:100` and pinned at
`compiler.lua:803` is **surrendered** as part of Q1/Q7's already-raised output
gate, at the measured price of 2 instructions on that fixture. The binding may
*narrow* eligibility (frame materialization, effects, hidden results); it may not
widen it back to a cross-function cycle, because that would need the cross-function
key form this round rejects.

## Not established

- Corpus-wide cost of deleting the entry lattice: the canonical witness is +2
  instructions, and round 4 measured larger folds on hand-built mutual fixtures
  (`100-7`, `200-7`). No corpus scan counts residual-entry invariants.
- Whether the frontend test should be rewritten to assert the *values* (it already
  does) and the shape only, or whether the user prefers policy (c) for
  `docs/abc-opt.md:100` compatibility. This is Q1's gate, not a new question.
- Policy (b)'s code size on a non-constant trip count (projection only).
