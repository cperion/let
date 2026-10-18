# Round 5 — the loop-header key is the loop-invariant join, and it is static

**Question pursued (ranked first of three below):** under the round-4 rule "a key
is exact, and is generalized only at a residual-call entry or at the per-pc
budget", what key must an edge into a **non-entry loop header** take? Round 3
chose the generic all-location key; round 4 chose exact keys everywhere. Those are
not the only two options, and the choice decides whether the documented loop
specialization survives.

**Candidate questions and ranking (materiality first).**

| # | Question | Materiality | Verdict |
|---|----------|-------------|---------|
| A | What key form does a non-entry loop header take: exact (unroll up to the budget), generic (round 3, one body, constants forgotten), or the **loop-invariant join** (one body, invariant constants kept)? | **high** — version policy (hard gate), code size, compile cost, whether the deleted widening machinery comes back, and whether documented behavior survives. | **chosen** |
| B | Is a version's entry layout a function of the pc or of `(pc, key)`, and who materializes A/B at a version body (the drain contract)? | high for the implementer, but round 3's fixtures already fix the answer (layout is per version body; the target body reads the drained slots); no measurement would change it. | deferred as a clarification, not this round's work. |
| C | Where do per-pc A/B/C layouts and loop may-write sets come from (one shared layout pass vs. reusing verifier data)? | medium — fact ownership and compile cost, not correctness of the rule. | opened as Q12 after A. |

**Method.** Hand-built ABC through the existing assembler, loader/verifier and all
four execution modes (`build/abc run … --interpreted | --jit=threaded |
--compiled | --lazy`), incumbent optimizer (`frontend/let/optimize.lua`) for
idempotence, and the portable-C sink (`build/abc c`) for the shipped loop-entry
rule. Script: `experiments/5-loop-key.lua`; artifacts in
`experiments/5-loop-key-out/` (not committed). No existing corpus was modified.

## 1. What the documented fixture actually does

The incumbent's optimized counter (`frontend/tests/optimize.lua:229`, measured
again in round 4 as 53 → 18 instructions) is:

```text
00000000 PUSH8_A 0                          ; i = 0
00000002 CPUSH_A                            ;   into C0
00000003 PUSH8_A 0                          ; acc = 0
00000005 CPUSH_A                            ;   into C1
00000006 CGET0_A                            ; header: read i
00000007 BLTUI_A 50 0x00000011              ;   compare against the constant 50
0000000c CGET0_A; CGET1_A; RET_A 2 2        ;   exit path
00000011 CGET0_A; ADDI_A 7; ZX32_A          ; body: i + 7
00000015 CGET1_A; ADDI_A 1; ZX32_A          ;       and the other step by 1
00000019 CSETN_A 1; CSET0_A                 ; write both loop slots
0000001c JMP 0x00000006                     ; one body, one header version
```

So the incumbent's loop header is a **join**: the two loop-carried slots (0 and 1)
are unknown in the body, while the bound `50` and the step `7` remain constants in
the same single body. `frontend/tests/optimize.lua:502,505` pins exactly this
("recursive counter retains invariant limit and step specialization"; "loop
invariants become immediates in explicit residual control flow"). This is the
behavior a versioned sink must reproduce — and it is neither "generic key" nor
"exact key".

## 2. Measured emission under the three candidate rules

One loop, identical semantics in every shape: `acc = sum of i for i = 0, step, …
while i < limit`, `limit = 120` (fits the `BLTUI` i8 immediate), `step = 7`,
answer `1071`. All four shapes return `1071` in interpreted / threaded /
compiled / lazy. Idempotence under the incumbent is trivially satisfied for all of
them because `abc-opt` retains every function containing a backward edge (round
3's measured cliff), so it is a consistency check, not evidence of optimization.

| shape | header key | code size | loop cost / iteration | invariant immediates in the hot body |
|---|---|---|---|---|
| **P** pre-widened | `i` and `acc` are C locations; `limit`, `step` are constants in the key (the body never writes them) | **16** instructions | 2 header + 8 body = **10** | `BLTUI_A 120`, `ADDI_A 7` |
| **G** generic | every component a C slot (round-3 rule; also the C sink today) | 22 | 3 + 9 = **12** | none (`CGETN_B 3`, `CGETN_B 2`) |
| **E** exact, budget 8 | one header version per distinct key; entry key `(i=0, acc=0, limit=120, step=7)`, all constants | 29 | 12 in the tail | none in the tail |

P's listing (one body, both invariants immediate):

```text
00000006 CGET0_A
00000007 BLTUI_A 120 0x00000010
0000000c CGET1_A; RET_A 2 1
00000010 CGET1_A; CGET0_B; ADD_A; CSETN_A 1
00000015 CGET0_A; ADDI_A 7; CSET0_A
00000019 JMP 0x00000006
```

E's listing shows what exact keys do to a constant-trip loop: seven header
versions whose bodies fold completely to a jump, then the budget edge stores the
four surviving constants into slots and enters a generic tail:

```text
00000000 JMP 0x00000003  00000003 JMP 0x00000006  …  00000012 JMP 0x00000015
00000015 PUSH8_A 120; CPUSH_A; PUSH8_A 7; CPUSH_A
0000001b PUSH32_A 147; CPUSH_A; PUSH8_A 49; CPUSH_A
00000024 CGET0_A; CGETN_B 3; BLTU_A …            ; the hot tail: bound read from C
```

Computed executed-instruction counts for this fixture (trip count 18):

- P: `4 + 19·2 + 18·8 + 2 = 188`
- G: `8 + 19·3 + 18·9 + 2 = 229`
- E: `7 + 8 + 12·3 + 11·9 + 2 = 152` (7 header versions, the budget-edge
  materialization, then 12 generic header visits and 11 generic bodies)

E wins for this small constant trip count, P wins as the trip count grows (12 vs
10 per iteration; break-even around 36 iterations), and E's code is 1.8× P's
before the trip counts are even considered. A non-constant counter produces no
new keys under any of the three rules, so this whole difference exists only for
**compile-time-constant loop components** — which is exactly the documented case
(bound and step known before the loop), and for native the case where a constant
can stay in the symbolic cache instead of occupying a register.

The generic key's cost is measured directly in this fixture: two extra frame
reads per iteration, and the invariant is not an immediate at all. The portable-C
sink shows the same rule at the C level: for the ordinary (non-versioned) loop it
materializes the bound (`v_9 = 0x…78`) and the step before the loop but the header
version compares block-argument copies, `if(v_8 < v_5)`, because
`edge_version_mode` canonicalizes a loop entry with `forget_constants=1`
(`src/residual_builder.c:1090-1091, 1195-1207`). Unlike ABC and native, the C sink
hands its output to a host C compiler, which can re-propagate an invariant edge
argument; ABC bytecode and native machine code have no downstream optimizer, so
there the lost constant is permanent.

## 3. Answer: the loop-header key is the loop-invariant join, computed statically

The join over all incoming keys at a header is exactly what the incumbent's loop
machinery realizes dynamically (`loop_captured` / `loop_stable`), and it is what
the measured counter output shows. The round-1..4 objection to "the join" was that
a monotone widening computed *after* the body exists forces a discard-and-rebuild
of the function (`optimize.c:850-873`). That objection does not apply here:

- The join's per-component result over all iterations is determined by whether the
  loop can **change the storage of that component**. A component whose storage the
  loop never writes or destroys keeps its entry value for every iteration; a
  component whose storage the loop writes may hold any value. So the fixpoint of
  the join is the entry key with every component the loop may write replaced by
  the binding's location form.
- That set is a **static property of the loop body**, computable before the body is
  executed: from the instruction writes in the loop and the per-pc A/B/C heights.
  Therefore the loop-entry key is available when the header version is created.
  There is **no fixpoint, no re-execution, no rebuild, no call facts**, and the
  module-wide "each version body executes exactly once" invariant stands.
- The rule is a **canonicalization of every edge key into a loop header**, not a
  widening of an existing version: a constant component is kept iff its storage is
  untouched, so the backedge key canonicalizes to the same key as the preheader
  key and the header has exactly one version for a single-entry loop. (A loop with
  several forward entries gets one version per distinct canonical key, still
  budget-bounded by Q2's cap.)
- The only thing this loses against an exact dynamic join is a may-written position
  whose value nevertheless stays the same constant across iterations (the body
  rewrites the same constant). The static rule widens it unnecessarily; that is the
  price of not running a fixpoint, and it is a quality, not correctness, limit.

**ABC instance of the may-write set** (binding-owned, per Q5):

- loop interval for a header `h` = every pc from `h` to the largest backedge source
  into `h` (an interval over-approximation; no natural-loop computation, dead code
  in the interval only over-widens);
- A/B position at depth `d` is may-write iff the loop interval's minimum A/B height
  is `<= d` (the value was popped or overwritten);
- C home `h` is may-write iff the interval contains a `CSET` to `h`, or its minimum
  C height is `<= h`'s index, or a `CALL`/`TCALL` in the interval gathers args at or
  below `h`'s index (a callee's frame starts at the call's argument base and cannot
  read or write below it: `docs/spec.md` "Calls");
- an inlined callee has empty private A/B stacks and its C frame starts at the call
  base, so it cannot touch the caller's key components below that base; the
  caller-side `CALL` pc plus the min-height clause already covers the rest. No
  cross-function may-write analysis is needed.

**Native instance:** the same condition over its locations (A/B stack depths and
C-frame homes). Native's A/B traffic usually reaches the header depths, so those
components widen exactly as today; C-frame invariants are now kept. This deletes
the peel: today a forward edge keeps constants and the backward edge weakens all of
them (`src/residualize.c:424-438`), giving two header versions; under the shared
rule a header has one, pre-widened version. That is a native version-policy change
and remains Q9's gate.

**Residual-call entry that is also a loop header:** the entry canonicalization to
the all-location key already widens every component, and the loop-invariant form
of an all-location key is itself, so the function still has exactly one entry
version and any call can target it. A constant produced by the body (`x = 0·i`)
canonicalizes back to a location on the backedge, so it never adds a version.

## 4. Consequences

1. **Q11 answered: loop-invariant key.** Exact keys at a loop header are rejected
   because the per-pc budget would make the hot body all-location: the documented
   `BLTUI_A 50` / `ADDI_A 7` disappear from the emitted loop and
   `frontend/tests/optimize.lua:502,505` fails; a constant-trip loop also unrolls
   into up to `budget` header versions (29 vs 16 instructions measured) for a win
   that vanishes as soon as the trip count exceeds about 36. Generic keys are
   rejected because every iteration pays the frame reads (12 vs 10 instructions
   here) and the documented immediates are never emitted. The dynamic join stays
   rejected: the static may-write pre-widening gives the same key without a
   fixpoint or rebuild.
2. **The "exactly two forced-generic cases" claim is replaced by "three
   canonicalization points":** residual-call/module entry → all-location; non-entry
   loop header → loop-invariant key (may-write pre-widening); per-pc budget →
   all-location. Exact keys remain the default everywhere else.
3. **One new module fact:** the loop may-write set over the binding's key
   components, derived in the same linear pass as leaders/successors and the per-pc
   layouts (Q12). The loop-header boolean stays (it selects the canonicalization).
4. **Q10 gets its bound for self-recursion:** inlining a self-tail call makes the
   callee entry a loop header; its backedge canonicalizes to the loop-invariant key,
   so the recursion becomes a one-version cycle. The incumbent's "inline a
   self-recursive callee once" rule (`optimize.c:301,309-318`) is derived from the
   loop rule; the inline budget only has to bound nontail call chains (continuation
   chains, `symbolic.c:39-75`).
5. **The path tree's loop machinery remains retired:** the loop-invariant key is a
   static rule over ordinary versions, not `loop_captured`/`loop_home`/`backedge`
   lowering. The incumbent keeps the same specialization by dynamic means.
6. **Rejected refinement (recorded):** keep exact keys and change only the budget
   fallback for loop headers to the loop-invariant key. That dominates P for small
   constant trip counts (E's 152 vs P's 188 executed instructions at trip 18) but
   deliberately emits up to `budget` bodies per loop header, contradicting the
   compile-time and code-size goals and the "one version per loop header" invariant;
   if a benchmark later shows small constant loops matter, it can be added as a
   bounded unrolling *choice in the binding*, not as the key rule.

## 5. Not established

- An implementation of the may-write analysis on the corpus, and its effect on
  version count / code size / compile time over real modules (Q12).
- Native's measured cost/benefit after adopting the loop-invariant key (its C-frame
  constants are kept, its peel is dropped); this is Q9.
- Whether any real loop has a may-written position whose value is invariant, i.e.,
  the measured size of the static rule's only loss against the dynamic join.
- The ABC sink's per-version drain/entry-layout emission at scale (question B).
