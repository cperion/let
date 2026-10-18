# Round 6 — the loop may-write predicate: cycle body, backedge-as-join, and why it is a heuristic

**Question pursued (ranked first of three below):** round 5 answered Q11 with "the
loop-invariant key = the incoming key with every component the loop may write
replaced by a location", and sketched the may-write set concretely as an
*interval* plus a CALL/TCALL clause. That predicate now decides the compile cost,
the code size, and whether the documented counter keeps its invariants. Is it the
right static join — does it actually produce one body that keeps exactly the
components the loop does not change?

**Candidate questions and ranking (materiality first).**

| # | Question | Materiality | Verdict |
|---|----------|-------------|---------|
| A | What exactly is "the loop body", and is the backedge instruction (especially the self-tail transport that *rebuilds* the frame) part of it or the join? Round 5's interval + CALL/TCALL clause is one concrete answer; it decides whether the documented counter is emitted as P or as G. | **high** — it decides whether the design reproduces the behavior round 5 measured as its justification (`frontend/tests/optimize.lua:502,505`), and it fixes the loop fact's representation and the fact-pass cost. | **chosen** |
| B | Is the may-write predicate a correctness condition or a specialization heuristic? (If exact keys are used, any widening is safe; an under-widening only creates more versions.) | high for the design's framing: it changes what the rule must prove, and what "one version per loop header" means. | **answered as a by-product of A** and recorded in ARCHITECTURE. |
| C | Q12: which pass owns per-pc layouts, CSET targets and the cycle-body/backedge sets, and may the verifier's discarded `Shape` feed it? | medium — fact ownership and compile cost, not the rule. | refined by A's data requirements; stays open. |

**Method.** New probe `experiments/6-may-write.lua` and artifacts in
`6-may-write-out/` (not committed). Modules are assembled with the existing
assembler (`tools/assembler.lua`), disassembled with `build/abc dis`, and heights
are computed by abstract interpretation of the decoded stream with the verifier's
own join rule as an oracle: the analysis aborts if the A/B/C heights disagree at
any join target, so the heights used are the heights the verifier's `Shape`
records (`src/verify.c:158-284`). Instruction effects are modelled for the
fixture subset only, and an unknown mnemonic aborts the probe. Backedges,
reachability and the two candidate body sets are computed over the function CFG.
Fixtures: the exact documented counter source (`frontend/tests/optimize.lua:229`)
and a loop whose exit path pops the frame. Argument-gather order was measured
separately (`experiments/6-gather.lua`, `6-gather3.lua`, all four execution
modes).

## 1. What round 5 says the predicate is

From `experiments/5-loop-key.md` §3 (ABC instance):

- body = "loop interval for a header `h` = every pc from `h` to the largest
  backedge source into `h` (interval over-approximation; dead code in the
  interval only over-widens)";
- A/B depth `d` may-write iff the interval's minimum A/B height is `<= d`;
- C home `h` may-write iff the interval contains a `CSET` to `h`, or its minimum
  C height is `<= h`'s index, or "a `CALL`/`TCALL` in the interval gathers args at
  or below `h`'s index".

## 2. Measured: the predicate collapses the documented counter to the generic key

`loop` in the documented counter is function 2 at pc 0x29; its single backedge is
the self-tail `TCALL_A loop` at pc 0x48 (backedge source, `frame_cells = 4`); the
header frame is 4 C slots and the body CSETs two of them (slots 2 and 3). Probe
output:

```text
-- function 2, header pc 41, C height 4, backedge sources 72
   body writes (CSET slots): {2,3}   min C height: interval 4 / cycle 4
   round-5 rule   (interval + CALL/TCALL clause, body pcs 18): may-write C slots {0,1,2,3}  (4 of 4)
   corrected rule (cycle body, backedge is the join, body pcs 13): may-write C slots {2,3}  (2 of 4)
   constants kept: round-5 0, corrected 2
```

The interval's *height* clauses are harmless here (the exit `RET_A 4 2` sits at C
height 4, so the interval's minimum C height is still 4). The clause that fires is
the CALL/TCALL one: the self-tail `TCALL` gathers its four arguments at C base
`4 - 4 = 0`, i.e. at or below *every* home, so round 5's rule marks all four
slots may-write. That is exactly the round-3 all-location key: one body, but the
loop reads the bound and the step from the frame, which is the **G** shape round
5 measured as losing two instructions per iteration and both documented
immediates. The design's own flagship behavior — the incumbent's one-body emission
with two unknown slots and `BLTUI_A 50` / `ADDI_A 7` in the same body
(`experiments/5-loop-key.md` §1) — is therefore unreachable under round 5's
concrete predicate, not because of a measurement but because the predicate treats
the backedge transport as a body write.

The transport is not a body write: `TCALL` *replaces* the local frame from the
argument vector (`docs/spec.md` "Calls": "replaces its complete local frame/operand
regions"), so the target's slots are *defined* by the edge, exactly like
`binding.join` defines a join target. Treating it as a write is the same mistake
as treating a join's materialization as a store into the predecessor.

## 3. Measured: the interval includes code that is not on a cycle through the header

Second fixture (`exit-pop`): a loop whose exit path discards the frame
(`CGET.A 0; CPOP; CPOP; CPOP; RET.A 0 1`) while the cycle writes only one slot.
The exit block lies between the header and the backedge source in pc order, so the
interval contains its pops:

```text
-- function 0, header pc 9, C height 3, backedge sources 27
   body writes (CSET slots): {0}   min C height: interval 0 / cycle 3
   round-5 rule   (interval + CALL/TCALL clause, body pcs 13): may-write C slots {0,1,2}  (3 of 3)
   corrected rule (cycle body, backedge is the join, body pcs 6): may-write C slots {0}  (1 of 3)
```

Round 5's parenthetical "(dead code in the interval only over-widens)" does not
hold: the exit path is *live* code reachable from the header, just not on a path
back to the header. Any loop whose exit path pops temporaries, calls a function or
writes a slot over-widens that header. The rule needs loop-membership, not pc
order.

## 4. The may-write set is a specialization heuristic, not a correctness condition

Derivation, and it simplifies what the rule owes:

- Version creation is by *exact* key (round 4). The canonicalization is a total
  function of `(key, module facts)`; it never changes an existing version's key.
- If the static may-write set is too **large** (over-widening), the header key has
  fewer constants than necessary: quality loss only, measured in §2–3.
- If it is too **small** (under-widening), the backedge edge key differs from the
  header's key, so `version_at` creates another version at the header. That
  version's body is executed under its own key, so it is still correct; the loop
  simply specializes more than intended, is bounded by the per-pc budget (Q2), and
  falls back to the all-location key if that budget is exhausted.

So the loop-invariant key is exactly the round-5/round-3 **heuristic** it was
introduced as, and correctness never depends on the predicate being complete. The
design should say this: the predicate must be *cheap and static*; being
conservative costs code quality, never meaning. That removes the need to prove the
predicate sound, and it explains why a "may-write" rule can be stated per binding
without a cross-function analysis.

## 5. Corrected rule

**Body.** `cycle_body(h)` = the pcs on some path from `h` to a backedge source of
`h`, excluding the backedge instructions themselves (they are the edge/join).
Computed by a reverse walk from the backedge sources that does not expand through
`h`, kept to pcs reachable from `h`: successors and leaders are already module
facts, and the walk is bounded by the loop body, so the cost is still
near-linear (a nested loop is walked once per enclosing header).

**ABC may-write set** (binding-owned, over the ABC key vocabulary, which is C
slots only — see the simplification in §6):

- C slot `k` is may-write iff the minimum C height over `cycle_body(h)` is
  `<= k`, or `cycle_body(h)` contains a `CSET` whose target slot is `k`.
- The CALL/TCALL clause is deleted (§6).
- A self-tail backedge preserves positions: measured, the callee's `C_k` receives
  the caller's selected-stack depth `k` (argument 0 is the first pushed), so a
  same-position argument vector is identity and needs no extra widening
  (`experiments/6-gather*.lua`, all four modes: `f(1,2,3)` returns `1 2 3` from
  `CGET 0,1,2`). A *computed or re-ordered* argument vector can deliver a value
  from a different position; the body write set cannot see that, so the rule
  should widen when the tail-call argument vector is not a same-position read
  (a local, per-edge check), and otherwise accept extra versions (§4).

**Native may-write set:** the same C-slot clause over C-frame homes, plus A/B
depth `d` iff the minimum A/B height over the cycle body is `<= d`; native loop
backedges are plain jumps (identity transport), so it needs no transport clause.

**Why the call clause is unnecessary.** A callee's C frame starts at the caller's
call-time C height (`abc_symbolic_machine_call`, `src/symbolic.c:467-484`:
`cbase = n[C]`, `c_origin = n[C] + arguments`, and the machine's C index is the
absolute height). A callee can only address its own frame (`verify.c` C-instruction
cases are frame-local), so it cannot read, write or pop a caller slot below the
base; `machine_return` restores `n[C] = frame.cbase`. A caller slot index `k`
below the call base is only destroyed if the caller's own C height dropped to `k`
first — which the minimum-height clause already sees. A *residual* call does not
touch C at all (`symbolic.c:467-484` never writes `n[C]` on the non-virtual path).
A frame-replacing `TCALL` is either the backedge (excluded) or a terminating edge.

## 6. Simplifications recovered

1. **No CALL/TCALL clause** (deleted, above) — and with it the only reason the
   rule would have needed any cross-function information.
2. **No A/B clause for ABC.** Round 5 listed "A/B position at depth `d` is
   may-write iff ..." for ABC, but the ABC canonical key is A/B-empty by round 3's
   drain (`ARCHITECTURE.md` "Data representation"; `verify.c:284` fixes the join
   shape, `optimize.c:165-170` rejects `HOME` for A/B). ABC loop keys have C
   components only; the A/B clause is native's (and the portable-C binding's, whose
   key is also frame-like).
3. **No provenance/cross-function analysis**: the cycle body, the C heights and
   the CSET targets are all per-function; the transport rule is local to the
   backedge instruction.
4. **The rule no longer needs to be complete** (§4): the design can pick the
   cheapest static widening and rely on exact keys plus the budget for anything it
   misses.

## 7. What this changes in ARCHITECTURE

- The loop fact becomes `(header, backedge instructions, cycle-body pc set)` plus
  the derived may-write set; the pc interval is rejected as the body definition.
- The "only loss" sentence ("a may-written component whose value happens to stay
  the same constant") is replaced by the §4 statement: over-widening is a quality
  loss, under-widening costs extra versions bounded by the budget, and exact keys
  keep both sound.
- The loop-invariant key keeps its definition, but "every component whose storage
  the loop may write *or destroy*" is restated as "whose value can change on a
  cycle through the header, with the backedge transport counted as the join".
- The self-tail derivation (round 5, consequence 4) stands for the same-function
  case, with the transport caveat. The mutual-tail-recursion half of round 5's
  claim is unsupported: a cross-function tail cycle has no per-function body and
  no same-position transport, so the conservative choice is the all-location key
  (or no inlining). Raised as Q14.
- Q12's data requirement is now exact: per-pc A/B/C heights, per-pc `CSET` target
  slots (height minus depth), successors and the backedge list. The verifier
  computes the same heights in `Shape` (as `pool.nodes[...].depth`) and discards
  them; the module-facts owner should compute them once and the verifier should
  not be a dependency of the optimizer.

## 8. Not established

- The corpus effect of the corrected rule (version count, code size, compile
  time); the probe is two hand-built modules.
- Whether a real loop's tail-call argument vector is ever non-identity, i.e. how
  often the transport caveat costs a version.
- Cross-function tail cycles (Q14), the portable-C binding's corrected predicate
  (it currently forgets all constants at a loop entry,
  `src/residual_builder.c:1090-1091, 1195-1207`), and native's Q9 measurement.
- The `min C height` clause's interaction with inlined callees is argued, not
  measured (the probe models a call as a fall-through, which is the caller-side
  abstraction the rule needs).
