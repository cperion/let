# Log

Append only, newest last. One dense section per round. Point at evidence rather
than copying it.

## Round 1 — rederive

**Mode:** rederive (no incumbent; ARCHITECTURE/LOG/QUESTIONS were empty
templates). **Question:** round 1 had no single material question yet, so I ranked
three: (A) ownership of specialization/version identity and traversal, (B)
function-wide vs per-version ABC residue, (C) whether the portable-C sink earns
its existence. A is the most material because it decides the data representation,
the concept count and the compile-time bound; it subsumes the module-fact
duplication. Investigation: `experiments/1-rederive.md`.

**Derivation.** From `CONTRACT.md` alone, the smallest model is five entities —
module facts, symbolic machine, context key, version, binding — with two
invariants that do real work: a version body is executed once (no re-walk, hence
no SSA round trip or placement reconstruction), and key equality is version
identity with a canonical generic fallback for termination. Sink residue stays
sink-owned because the contract forbids staging native emission.

**Evidence against the incumbent implementation.** One idea is implemented more
than once: block-leader discovery 2× (native `residualize.c:440-463`, C
`residual_builder.c:2047-2110`, already drifted on end guards, loop headers and
TCALL backedges); context-key policy 2× (`residualize.c:408-438` + shared
equalities vs `residual_builder.c:851-978`); traversal 3× (native, C, and the ABC
path tree `optimize.c:361-387`); call graph 3×, including a formatting-only
duplicate (`optimize.c:57-118` vs `residual_analysis.c:24-85`) plus per-function
DFS helpers (`symbolic.c:553-578`) whose callers are O(F·(V+E)). The duplicated
policy has already diverged: `REFACTOR.md:811` records 10 native versions at one
PC against the approved 8-per-original-PC budget. The ABC tree is also the only
traversal not bounded by blocks × versions (≤4096 leaves/function, each a ~4.2 KB
`DagTree` + copied context — structural projection, not measured).

**Decision recorded in ARCHITECTURE.md.** Candidate: module facts, context-key
policy and the version driver each get one owner in the core; the three sinks
become bindings over one traversal (`binding.join` is the only place incoming
values meet a target key); native keeps zero stored residue, C keeps its per-block
residue, ABC keeps a per-version DAG scheduled locally. Named deletion set:
`optimize.c` call-graph copy + `ArgumentFact` fixpoint + path-tree walk,
`residual_analysis.c` as separate owner, `symbolic.c` DFS helpers, and the private
drivers/leader discovery/key canonicalization in `residualize.c` and
`residual_builder.c`. Q4 and Q5 answered yes on this evidence (no policy content,
only duplication).

**Not decided.** Adopting versions for abc-opt changes its analysis/version policy
and canonical output, so it is a hard gate (Q1): versions preserve path
sensitivity by creating a version per distinct key and additionally merge equal
contexts, but ABC function entries cannot be multiplicity-specialized (one entry
address ⇒ entry-fact lattice stays), and ABC code placement forces the owning
residual function into the key. Q2 raises the version-budget authority conflict;
Q3 raises the portable-C sink scope. No timings were run; projections and the
measurement plan are in the experiment §6.

**Next uncertainty.** Whether shared (versioned) ABC blocks cost more interpreter
dispatch than the duplicated path tree, and whether the ABC encoding/verifier
permits multiple versions of a non-entry block. Either answer reopens Q1; a
measurement on the existing optimizer fixture corpus plus interpreter dispatch
counts is the cheapest way to settle it.

## Round 2 — experiment

**Mode:** experiment. **Question ranked first (of three in
`experiments/2-questions.md`):** under a versioned ABC sink, is residue a
function-wide value DAG or per-version residue, and what is a version key
actually made of? Prerequisite verified in the same probe: is a versioned
non-entry block representable/verifiable, and what does the incumbent path tree
cost? Rejected as less material: the native version-budget value (8 vs 10) — one
owner is needed either way and no concept changes.

**What was measured.** New fixtures assembled with the repo's assembler, run
through the real `abc_optimize_mapped`, decoded and executed in interpreted and
threaded modes (`experiments/2-abc-probe.lua`, report and disassembly in
`experiments/2-abc-versioned-sink.md`). An 88-instruction function with 12
independent branches optimizes to **16,382 instructions** (one input RET copied
4,096 times) in **23.9 ms**; adding one branch (94 instructions) crosses
`ABC_OPTIMIZER_PATH_LIMIT` and the function is **retained with no optimization
at all** (after 21.7 ms of exploration). Every function with a branch and a
non-call effect — store, trap, allocation — is retained unoptimized regardless
of where the effect sits (`optimize.c:157,747`); a direct call in an arm is the
only effect that survives (`optimize.c:526-528`). The multi-result join
mechanism grows 8 → 19 instructions (`emit_phi_tree`/`PhiPatches`). The
documented canonical fixture (`docs/abc-opt.md:82-91`) is emitted exactly
(`CGET0_A; MULC_A 0; CGET1_B; MULC_B 1; ADD_A; RET_A 2 1`) and every case is
idempotent and execution-identical in both modes.

**Answers.**
1. *Representability*: already demonstrated by the incumbent — the path tree
   emits duplicate non-entry blocks with N:1 provenance and the verifier accepts
   them. Only a second function entry is forbidden (`verify.c:131-134`). Q1's
   encoding sub-question is closed; what remains is the policy gate.
2. *Residue scope*: **per version; keys are constants plus binding-defined
   locations.** Never sink residue identity: the C sink already canonicalizes
   every non-constant slot to a home and turns it into a version parameter, keeps
   constants in edge keys, forgets them at loop entries, widens recursive keys
   and falls back to the all-home key at the budget
   (`residual_builder.c:851-877,996-1062,1083-1123`). The core's all-stack
   `HOME(s,i)` generic form (`symbolic.c:62-75`) is native-specific: the ABC sink
   cannot consume `HOME` (`optimize.c:165-170`), so ABC's location vocabulary is
   the **C-frame slot** written by the join (`CPUSH`/`CSET`) and read by the
   target body (`CGET`). Constants in keys preserve the measured specialization
   (`diamond`, `choices` unchanged; `phi` shrinks).
3. *Entry rule*: a function entry stays **one** version whose key is the monotone
   join of all incoming keys, re-executed until stable (ABC `CALL`/`TCALL` can
   only target a function entry; the counter fixture depends on the resulting
   constant specialization). This corrects round 1's deletion set: the
   `ArgumentFact` lattice is not duplication — only its private dirty loop is
   replaced by the driver's entry widening.

**Decision recorded in ARCHITECTURE.md.** The candidate keeps five concepts but
corrects the key and residue definitions: key = constants + binding locations;
residue per version (native none, C block arguments, ABC per-version bytecode
with C-frame-slot joins); the binding supplies the location vocabulary and the
canonical generic form while the core owns equality/family/budget/recursion
widening/entry widening. Added: the invariant that no key contains sink residue
identity, the single-entry-version rule, the join's right to canonicalize the
operand-stack shape, and the corrected retired-path list (path tree, phi join,
path limit and the branch+effect refusal retire *if* Q1 is approved; the entry
lattice stays). Rejected: a function-wide ABC value graph with node ids in keys
(needs dominance-safe cross-version home reuse, keeps O(n²) hash-consing and
path-use counting, buys nothing for a blow-up that is control duplication), and
per-edge rematerialization across versions (deferred; would reintroduce the
dominance question).

**Q1 is now a recommendation, not an unknown**: adopt versioned blocks for
`abc-opt`. It remains the user's hard gate because output bytes and the version
policy change; the evidence, the versioned-sink shape and the validation plan are
in `experiments/2-abc-versioned-sink.md`. Q2 (budget authority) and Q3
(portable-C scope) are unchanged.

**Next uncertainty.** The versioned ABC sink's **byte determinism and
idempotence** are unproven (the path tree is idempotent on all measured cases);
and whether the C-frame-slot canonical key can be emitted without extra C traffic
on real modules. Cheapest decisive probe: a hand-built versioned emission for the
measured corpus (or a minimal prototype) that asserts fixpoint byte identity,
the canonical fixture, effect/branch coverage, and O(blocks × keys) growth — i.e.
re-run `frontend/tests/optimize.lua` and `tools/validate_optimizer_isa.lua`
against it.

## Round 3 — simplify

**Mode:** simplify. **Question ranked first (of three in
`experiments/3-loop-versions.md`):** are ABC loop headers ordinary versions, so
that the whole `loop_candidate`/`loop_home`/`loop_prologue`/`backedge` subsystem
retires? Ranked above (B) the exact key content (folded into A) and (C) the
budget value (deferred: one owner either way, Q2 unchanged). A dominates because
it removes a concept plus its state, names a measured coverage cliff, and
settles the driver's edge-key rule.

**What was measured.** Hand-built ABC modules through the existing assembler,
loader/verifier and all four execution modes, plus the incumbent optimizer and
the portable-C sink (`experiments/3-loop-join-probe.lua`, report and
disassembly in `experiments/3-loop-versions.md`, artifacts in
`3-loop-join-out/`). Any function containing a local backward branch is
**retained byte-identically** by abc-opt — `sum-fold-source` with a foldable
`5+6` inside the loop stays 15 instructions, while the same shape without the
backedge optimizes 12 → 10. `dag_control` refuses any transfer with
`fallthrough <= origin` or `target <= origin` (`optimize.c:281,288`). Native
compiles and runs that same loop in compiled/lazy (no interpreter fallback,
`vm.c:168-171`), and the C sink compiles it to versioned blocks with edge
arguments (`3-loop-join-out/sum-source.c`). Hand-built "versioned emission"
shapes — empty A/B at every boundary, loop-carried values in C slots, one shared
header/join body reading `CGET`, backedge as an ordinary edge — verify and
execute in all four modes for n = 3,1,0; `opt(source)` and `opt(versioned)` are
**byte-identical and idempotent** (94 bytes for the join case). The verifier
accepts backward branch targets (`verify.c:122-125`) but requires identical
A/B/C shapes at every join (`verify.c:284`; a deliberately mismatched join is
rejected).

**Answers.**
1. **Loops are ordinary versions.** The ABC loop state and lowering retire:
   `loop_candidate`/`loop_target`/`loop_initial`/`loop_header`/`loop_home`/
   `loop_count`/`loop_captured`/`loop_stable`/`loop_temps`/`loop_prologue`/
   `backedge`/`nested_backedge`/`backedge_target` (`optimize.c:35-36,334-347,
   671-681,752-765`), the root-backedge operand lowering (`:615-622`) and the
   `N_LOOP_HOME` node kind. A virtualized recursive loop becomes a self-edge on
   the inlined entry version (continuation chain in the key), not a prologue.
2. **The edge-key rule is now concrete:** plain forward edge = constants +
   locations; an edge into a function-entry pc (real or virtual) joins the
   single lattice-keyed entry version; an edge into a non-entry loop header uses
   the generic all-location key; the budget fallback uses the same generic key.
   The loop-header fact (a leader with an incoming edge whose source pc is >=
   it) moves into shared module facts, replacing the C sink's private scan
   (`residual_builder.c:2047-2110`). The C sink's per-slot `RECURSIVE` widening
   and native's `edge()` constant weakening collapse into that one rule. Native
   would change (it keeps constants on a forward loop-header edge today), so
   that policy refinement is Q9, not a silent decision.
3. **The ABC location vocabulary is justified, not asserted:** join targets have
   verifier-fixed shapes, so the target layout is a function of the target pc;
   the body is emitted once for many predecessors and the ABC emitter can only
   address the C frame (`dag_value` rejects non-`CONST`/`BACKEND`,
   `optimize.c:165-170`; no entry-stack leaf, `:583-587`), so non-constant A/B
   values are drained into C slots at the edge and read with `CGET`. Rejected:
   keying A/B positions in place — needs an entry-stack value kind, gives up
   scheduled placement, and buys no measured quality.
4. **Key correction:** the key is constants + binding locations + **the core's
   continuation chain** (native compares the whole context, `symbolic.c:39-54`);
   without the continuation term virtual inline sites collide.

**Decision recorded in ARCHITECTURE.md.** Added the loop invariant (loops are
ordinary versions; no loop state/lowering), concretized the edge-mode selection
in `version_at`, moved loop headers into module facts, corrected the key to
include continuations, added the ABC drain rationale and the rejected A/B-key
alternative, and extended the retired-path list with the ABC loop machinery.
Q8 answered; Q9 opened (narrow native version-selection gate); Q1's evidence
gained the local-loop cliff; Q4/Q5/Q6/Q7 refined in place.

**Not established.** A versioned ABC emitter's byte determinism/idempotence end
to end (structural argument only: after one pass every block has exactly one
incoming key, and measured outputs remain idempotent), and the join's exact
push-vs-store sequence / C-traffic on real modules. Q2 (budget authority) still
blocks a single budget number for the shared driver, and Q9 decides whether
native adopts the loop-header generic key.

**Next uncertainty.** Whether the join's in-place store schedule can be emitted
without extra C traffic, and whether the generic-key-at-loop-header rule plus
the entry lattice still reproduce the documented counter specialization
(`BLTUI_A 50` / `ADDI_A 7`); both need a versioned driver prototype or an
emission-level fixture, after Q2/Q9 are answered.

## Round 4 — the entry lattice has no witness, and generic entries delete it

**Mode:** simplify. **Question ranked first (of three in
`experiments/4-entry-lattice.md`):** round 3 left a contradiction — a
residual-function entry is "one version whose key is the monotone join of all
incoming keys, re-executed until stable", yet call facts are produced by symbolic
execution, so the join can widen after a body (and its residue) exists. Where
does the widening physically live, what does it invalidate, and is it needed at
all? Ranked above (B) which calls are actually residual — it turned out to decide
A's whole scope — and (C) the join's push-vs-store emission schedule, deferred
again as a sink-level choice with no correctness or representation content.

**What was measured.** New fixtures through the existing assembler, verifier,
four execution modes, incumbent optimizer and the portable-C sink
(`experiments/4-entry-lattice.lua`, report in `experiments/4-entry-lattice.md`,
artifacts in `4-entry-lattice-out/`). The documented counter
(`frontend/tests/optimize.lua:229`) optimizes 53 → **18 instructions in ONE
function** with no `CALL_A`: all its calls are inlined (non-recursive calls always
virtualize, a nested-eligible self-tail callee virtualizes once as a loop
candidate, `optimize.c:299-318`), so `BLTUI_A 50`/`ADDI_A 7` come from inline
expansion, not from entry facts. Two roots calling `count_to(50)` and
`count_to(40)` yield 2 functions and two *independent* specializations
(`BLTUI_A 50`, `BLTUI_A 40`) — the entry keys are never joined. The real boundary
is the residual call, emitted only for recursive components that cannot be
inlined: mutual `even`/`odd` keeps `CALL_A`/`TCALL_A` and specializes the callees
from caller facts (`PUSH8_A 7` at both call sites, folded `100-7=93` and
`200-7=193`, while the decremented `i` widens); two roots passing steps 7 and 9
widen `step` (per-argument join) and both folds disappear. `mutual` is
`opt⁴ == opt` and execution-identical in all four modes. 40 roots cost 0.06–0.07
ms either way (same vs distinct steps). The same module through `abc c` folds
nothing and emits 13 static functions: the C sink uses generic entries and its
lattice API (`residual_analysis.c:215-266`, plus `residual_builder.h`'s
`argument_facts` option) has no caller. The incumbent's mechanism is a
module-level fixpoint over residual functions: call facts joined per argument
(`optimize.c:853-855`), dirty functions `clear_function_code`d and re-residualized
(`:870-873`), call displacements encoded only at module-write time (`:826-833`).

**Answers.**
1. **The join is a function-granular rebuild, not a version rule.** A widened
   entry key invalidates the whole function's residue; within one run every
   version body executes exactly once. Bounds: monotone `unreached → constant →
   unknown` per argument ⇒ ≤ 2·arity+1 runs per function; join is commutative and
   monotone ⇒ order-independent, so determinism is structural. Measured proof that
   the rebuild happens: with the first key `(50, 7)` retained, `i == 0` would have
   folded and `JZ_A` vanished; the emitted body tests `i`, i.e. it was built under
   the widened key.
2. **It is ABC-only and deletable.** A call that can only name a function entry
   is entered at the generic all-location key: one version, no join, no call
   facts, no fixpoint, no rebuild, and the module-wide "one execution per body"
   invariant is restored. The measured price is `mutual`'s cross-call folds. The
   recovered mechanism is inlining: every call that can be inlined becomes a
   **virtual entry** — an ordinary version carrying the caller's constants —
   which the ABC sink must have anyway (`docs/abc-opt.md:82-91` fixes the inlined
   `sq(a)+sq(b)` output). Nontail recursion cannot be inlined: continuation chains
   are part of key identity (`symbolic.c:39-75`), so each layer is a new family
   and the budget cannot merge them; tail-only cycles inline as version cycles.
   That derives the incumbent's `nested_eligible` rule instead of citing it.
3. **Inlining needs its own bound (Q10).** The per-pc budget counts key families
   and the continuation chain distinguishes call sites, so inlining across a call
   chain multiplies; the retired path limit was the only bound. One
   per-residual-function version budget with a residual-call fallback (generic
   entry) is the candidate; it needs corpus measurements.
4. **Round 3's loop-header generic key is not neutral (Q11).** It was justified as
   losing only loop-carried constants, but a loop header also has forward
   predecessors carrying constants that stay invariant inside the loop (the
   counter's `BLTUI_A 50` lives in the steady-state loop body; native peels; the C
   sink forgets them). The three coherent key forms (generic / per-slot join /
   exact) trade code size, version count and whether the widening mechanism
   survives; Q11 decides it, and Q9's recommendation is weakened accordingly.

**Decision recorded in ARCHITECTURE.md.** Keys are now exact; the only
forced-generic triggers are the residual-call entry and the per-pc budget. The
entry lattice, call facts, the function-level dirty fixpoint and the rebuild
policy leave the architecture and join the retired-path list (with the C sink's
dead lattice API and the `argument_facts` option). The call/inline rule becomes
part of the binding contract (bounded, Q10). The rejected alternative keeps the
lattice's measured mechanism and its cost on record. Q7 is revised to "generic
entry, no join"; Q10 (inline rule/bound) and Q11 (loop-header key form) are new;
Q1 gains the round-4 scope, Q4/Q5/Q9 are refined.

**Not established.** The byte-level cost of a generic-entry versioned ABC sink and
its inline budget; the value of the dropped cross-call specialization on real
modules; the loop-header key choice; whether removing the documented
`docs/abc-opt.md:100` behavior is acceptable (part of Q1's gate).

**Next uncertainty.** Q11's loop-header key form is the last place where a key is
deliberately generalized while constants are still available; it decides whether
"no widening anywhere except the forced entry" is really the whole key rule, and
how many versions a constant-initialized loop costs.

## Round 5 — the loop-header key is the loop-invariant join, computed without a fixpoint

**Mode:** simplify (plus one measurement). **Question ranked first (of three in
`experiments/5-loop-key.md`):** round 4 made every key exact and left two
canonicalization points (residual-call entry, per-pc budget). That rule says
nothing special about a non-entry loop header, so a constant counter would create
a new version per iteration until the budget and then fall into the *all-location*
key — but round 3 had chosen the all-location key directly, and the incumbent's
documented counter keeps `BLTUI_A 50`/`ADDI_A 7` in its loop body. Which key form
is a loop header, and does the answer reintroduce the widening/rebuild machinery
round 4 deleted? Ranked above (B) the per-version drain/entry-layout contract —
already fixed by round 3's fixtures, deferred as a clarification — and (C) where
per-pc layouts and may-write sets are computed (opened as Q12 after A).

**What was measured.** New fixtures through the existing assembler, verifier,
four execution modes, incumbent optimizer and the portable-C sink
(`experiments/5-loop-key.lua`, report `experiments/5-loop-key.md`, artifacts in
`5-loop-key-out/`). The incumbent's optimized documented counter is **one body**
at pc 6: `CGET0_A; BLTUI_A 50`, body `CGET0_A; ADDI_A 7; ZX32_A; CGET1_A; ADDI_A 1;
ZX32_A; CSETN_A 1; CSET0_A; JMP 6` — both loop-carried slots unknown, bound and
step constants in the same body. That is a join, and
`frontend/tests/optimize.lua:502,505` pins it. Three hand-built emissions of one
loop (`acc = Σ i, i += 7 while i < 120`, answer 1071; all return 1071 in
interpreted/threaded/compiled/lazy and are idempotent): **loop-invariant key** 16
instructions, one body, 10 instructions/iteration, both immediates;
**generic key** 22 instructions, 12/iteration, no immediates; **exact keys** with
budget 8: 29 instructions — seven header versions whose bodies fold to a single
jump, four constant stores at the budget edge, then an all-location tail at
12/iteration with no immediates. Computed executed-instruction counts for trip 18:
188 / 229 / 152; exact keys win only for small constant trip counts (break-even
about 36 iterations). The portable-C sink materializes the bound before the loop
but the header version compares block-argument copies (`if(v_8 < v_5)`), its
loop-entry mode having canonicalized with `forget_constants=1`
(`residual_builder.c:1090-1091, 1195-1207`); the host C compiler can re-propagate
that, ABC/native code cannot. Native weakens *all* constants on a backward edge
(`residualize.c:414-438`), so its loop body also reads an invariant bound.

**Answers.**
1. **The loop-header key is the loop-invariant join, and it is static.** The join
   over all incoming keys differs per component exactly when the loop can change
   that component's storage, which is a static property of the loop body. So the
   loop-invariant key = the incoming key with every may-write component replaced by
   the binding's location form; it is available when the header version is created,
   so there is **no fixpoint, no re-execution, no rebuild, no call facts**. A
   constant-trip loop stays one body with its invariants as immediates, which is
   what the documented fixture requires.
2. **The may-write set is computable in one linear pass.** ABC: the loop interval
   (header to its largest backedge source, an over-approximation) writes a C home
   iff it contains a `CSET`/`CPUSH` to it, or its minimum C height reaches the
   home, or a call in it gathers arguments at or below the home; an A/B depth is
   may-write iff the interval's minimum A/B height reaches it. Native: the same
   predicate over A/B depths and C-frame homes. Inlined callees have private A/B
   stacks and C frames above the call base, so no cross-function analysis is
   needed. The static rule's only loss against a dynamic join is a may-written
   component whose value happens to stay the same constant.
3. **Exact keys at loop headers are wrong for ABC and native.** After the budget
   the hot body falls into the all-location key, so the documented immediates
   disappear (`frontend/tests/optimize.lua:502,505` would fail) and up to `budget`
   header bodies are emitted for a win that vanishes above ~36 iterations.
   Generic keys are wrong because every iteration pays the frame reads. The
   dynamic join remains rejected — and it is now rejected *by construction*, not
   only by cost, because the static rule subsumes the part loops need.
4. **Consequences for other findings.** The loop-header boolean stays as a fact and
   gains the may-write set (Q4/Q5); Q9 becomes a native version-policy gate with a
   clear recommendation (one header version instead of two, invariant C constants
   kept, the peel dropped); Q10's bound for self-tail recursion is derived from the
   loop rule (a self-tail inline is a one-version cycle), leaving the inline budget
   for nontail chains; Q12 opens where per-pc layouts and may-write sets live.
   Round 4's "exactly two canonicalization points" becomes "three: entry,
   loop header, budget".

**Decision recorded in ARCHITECTURE.md.** Replaced "exact keys everywhere, generic
only at entry/budget" with "exact keys plus three static canonicalization points";
the loop-invariant key is defined, its may-write predicate sketched for both
bindings, `version_at`/`mode` updated, the "one version per loop header" invariant
added, the data-representation wording fixed (the live-value set is pc-fixed, the
layout is per version), the loop-invariant fact added to module facts, self-tail
inlining derived, and three rejected alternatives recorded (generic header key,
exact header keys, unroll-to-budget) with their measured costs.

**Not established.** Corpus-wide version/code-size/compile-time effect of the
may-write rule (Q12); native's measured cost/benefit under Q9; the measured
frequency of the static rule's only loss; the ABC sink's entry-layout emission at
scale (question B).

**Next uncertainty.** Q12: whether the may-write set and the per-pc layouts are
computed by one shared linear pass (and whether the verifier's discarded `Shape`
data should feed it), because that decides the compile-cost of the loop rule the
design now depends on. Q2 still blocks a single budget number; Q1 remains the
scope gate.

## Round 6 — the loop may-write predicate is the cycle body with the backedge as the join

**Mode:** experiment (a measured correction). **Question ranked first (of three in
`experiments/6-may-write.md`):** round 5 fixed the loop-header *key form*
(loop-invariant) and sketched the may-write *predicate* concretely — the pc
interval `[header .. largest backedge source]`, min A/B/C heights, CSET targets,
and a "CALL/TCALL in the interval gathers args at or below h" clause. That
predicate is the load-bearing part of Q11: it decides whether the design emits
the documented counter as P (one body, limit/step immediates) or G (all-location).
Is it right? Ranked above (B) whether the predicate is a correctness condition or
a heuristic (answered as a by-product) and (C) Q12's fact ownership (refined).

**What was measured.** `experiments/6-may-write.lua` assembles the exact
documented counter source (`frontend/tests/optimize.lua:229`) and an exit-path-pop
loop with the existing assembler, disassembles with `build/abc dis`, and computes
per-pc A/B/C heights by abstract interpretation that aborts on any join-height
disagreement (so the heights match the verifier's `Shape`). Artifacts in
`6-may-write-out/`. Non-identity of the argument transport was tested separately
(`6-gather.lua`, `6-gather3.lua`).

**Answers.**

1. **Round 5's predicate collapses the documented counter to the generic key.**
   `loop` is function 2 at pc 0x29, one self-tail `TCALL` backedge at pc 0x48, C
   height 4, body CSETs slots 2 and 3. Round 5's rule marks may-write
   `{0,1,2,3}` (0 constants kept) because the interval contains the tail call,
   whose frame replacement gathers at C base `4-4 = 0`, so "args at or below h"
   fires for every slot. The cycle-body rule marks `{2,3}` (2 constants kept) —
   exactly the incumbent's measured two-unknown-slot body with `BLTUI_A 50` /
   `ADDI_A 7`. The documented P shape round 5 used as its justification is
   unreachable under its own predicate.
2. **The interval is the wrong body: it includes live code that is not on a cycle
   through the header.** The exit-path fixture (exit pops the frame before RET)
   goes from may-write `{0,1,2}` (interval, min C height 0) to `{0}` (cycle, min C
   height 3). "Dead code in the interval only over-widens" is false: the exit path
   is live.
3. **The backedge instruction is the join.** A self-tail `TCALL` replaces the
   complete local frame from the argument vector (`docs/spec.md` "Calls"), so its
   writes define the target key like `binding.join` defines a join. Corrected
   predicate: `cycle_body(h)` (pcs on a path from `h` to a backedge source,
   excluding the backedge instructions) + min C height + CSET targets (ABC;
   C-only because ABC keys are A/B-empty, so round 5's A/B clause is vacuous) +
   min A/B heights (native) + the per-edge transport check. The CALL clause is
   deleted: a callee frame starts at the caller's call-time C height
   (`symbolic.c:467-484`), a callee addresses only its own frame (`verify.c` C
   cases), `machine_return` restores `frame.cbase`, and a residual call does not
   change `n[C]` at all — so no plain call can touch a caller slot below its base,
   and a caller-side pop is already caught by the min-height clause.
4. **The predicate is a heuristic, not a correctness condition.** Exact keys are
   the correctness rule: over-widening loses constants; under-widening makes the
   backedge edge key differ, creating another version whose own body is still
   correct, bounded by the per-pc budget (Q2). This is what lets the rule be a
   cheap static function and why no fixpoint is needed anywhere.
5. **Transport.** The ABC gather is slot-identity (measured: `f(1,2,3)` returns
   `1 2 3`; argument 0 is the first pushed, callee `C_k` ← selected depth `k`, all
   four modes), so a same-function self-tail backedge preserves positions and
   needs no transport widening. A computed/re-ordered argument vector is widened
   at the edge (quality, not soundness). A cross-function tail cycle has no
   per-function cycle body and no position identity: round 5's claim that mutual
   tail recursion "keeps its invariant constants" is unsupported; the conservative
   answer is the all-location key (Q14).

**Decision recorded in ARCHITECTURE.md.** The loop rule now names the cycle body,
the backedge-as-join, the transport identity and the heuristic status; the call
clause and the ABC A/B clause are gone; the module facts gain backedge
instructions, cycle bodies, per-pc heights and CSET targets; the complexity note
admits one bounded reverse walk per header; the interval+CALL clause is recorded
as a rejected alternative with its measured cost; Q12's required data set is
pinned; Q13 (body definition) is answered and Q14 (cross-function tail cycles) is
opened.

**Not established.** Corpus effect of the corrected predicate (the probe is two
hand-built modules); whether a real loop's self-tail argument vector is ever
non-identity; the portable-C binding's corrected predicate (it still forgets all
constants at a loop entry, `residual_builder.c:1090-1091, 1195-1207`); Q9's native
measurement; whether the loop body can be computed without the bounded walk (e.g.
by a dominator-based reduction).

**Next uncertainty.** Q14 (cross-function tail cycles) and then Q12's ownership
decision: one shared shape/cycle-body pass in the core, with the verifier's
discarded `Shape` heights proving that the data is already computed today. Q2
still blocks a single budget number and Q1 remains the scope gate.

## Round 7 — the budget is per family; the continuation chain needs its own bound

**Mode:** experiment (a measured correction). **Question ranked first (of three in
`experiments/7-budget.md`):** the design claimed "exactly three canonicalization
points", the third being "at the per-pc version budget a key is replaced by the
all-location key". But a key is constants + locations + the continuation chain, and
the chain names the return site of an inlined call. Can an all-location widening
bound versions at all? Ranked above (B) the key of a version that is both an
inlined callee entry and a cycle header (answered as a corollary: the entry key is
the call ABI, not an edge canonicalization) and (C) Q14, which the finding does not
change because tail calls push no continuation.

**What was read and measured.** The three sinks' equality/canonicalization code,
and a new branch-free doubling call ladder (`experiments/7-call-paths.py`,
artifacts in `7-call-paths-out/`, not committed) through the existing assembler,
optimizer and disassembler.

**Answers.**

1. **All canonicalization in the tree is value-only; the chain is identity.**
   `abc_symbolic_context_equal` compares the chain (`symbolic.c:45-53`) and
   `..._family_equal` compares the stack shape *and* the chain (`:56-66`), while
   `canonicalize`/`widen_recursive_key` only replace values with homes
   (`residual_builder.c:851-868, 936-963`). So the all-location fallback is total
   *inside* one family and cannot merge two call instances; versions at a pc are
   `families x budget`, not `budget`. The only code that removes a chain is a call
   decision (`residualize.c:395-406`). This is the gap `REFACTOR.md:811` recorded
   verbatim (10 versions at one entry PC against the approved total-8 wording).
2. **Families = inlined non-tail call instances.** The call continuation records
   return pc, target and the call-time bases (`symbolic.c:471-477`); the verifier
   fixes the shape at each pc (`verify.c:284`), so intra-procedural branch paths
   cannot change the chain but different call paths do. Tail calls push no
   continuation (`:486-499`), so self-tail backedges keep one chain (why the
   loop-invariant key is stable) and multiplicity arises only from non-tail
   inlining, which the canonical `sq(a)+sq(b)` output requires.
3. **Measured: the multiplicity is exponential and independent of branches.** A
   ladder `f_i(x) = f_{i+1}(x) + f_{i+1}(x| x+1)` has `2^depth` syntactic call
   instances and no branches; the ABC sink's output doubles with the instance count
   (22, 46, 94, 190, 382, 766 instructions for 8…256 instances, ~1.75–3 per
   instance) until ABC's 255-cell C-frame limit stops the outer inlining at depth 9
   (`optimize.c:753, 762`). A versioned sink emits one body per inlined instance
   (the chain differs), so this is the multiplicity the design must bound; its
   per-pc key budget cannot.
4. **Corrected rule set.** (i) A residual function's entry version is the generic
   key because of the call ABI (the caller materializes values into binding
   locations) — not an edge canonicalization; the loop rule therefore applies to
   *every* edge into a cycle header, including the documented counter's `loop`,
   which **is** function 2 and whose header **is** that function's entry (a
   pc-scoped entry rule would make the measured P shape unreachable). (ii) The
   budget is **per family** (shape + chain), with the all-location form as the
   family's general slot. (iii) Inlining gets its own bound: the driver counts
   distinct continuation families at the target pc and residualizes the call at
   `K`; `families(pc) <= K`, `versions(pc) <= K x budget`, work bounded by
   `sum_functions (1+K) x code(f) x budget`. The static capped call-path fact and
   the per-residual-function version budget are recorded as alternatives.

**Decision recorded in ARCHITECTURE.md.** The "three canonicalization points"
paragraph is replaced by two key rules plus two bounds; the entry key is the call
ABI; the budget is per family and its fallback is total only within a family;
inlining has a distinct bound with a residual-call fallback; the pseudocode checks
the call before the leader, counts families rather than pc versions, and takes the
general slot at `budget-1`; module/version/bounds/complexity/interfaces are
updated; the pc-scoped entry rule, chain widening, a literal total-per-pc budget,
the static path fact and the per-function-only budget are recorded as rejected or
alternative with reasons; Q2 is refined from a number to a **quantity and scope**,
Q10's bound is sharpened, Q11 loses "non-entry", and Q15 is answered.

**Not established.** Corpus chain multiplicities and the right `K`; whether the
versioned ABC sink's loss of cross-instance value sharing (the ABC DAG can CSE
identical applications) matters on real modules; the exact trigger for the
incumbent's depth-9 stop (the 255-cell frame limit is consistent but not
instrumented); Q14 unchanged (tail cycles create one chain); Q9 and the C sink's
loop predicate still unmeasured.

**Next uncertainty.** Q2's scope decision (per-family vs total-per-pc) is the last
hard gate for a single budget owner; then Q12's ownership decision and the Q10/Q14
residual questions. If the user chooses a total-per-pc cap, the shared-budget
allocation must be designed before the driver is buildable.

## Round 8 — key identity is content; every widening is looked up

**Mode:** experiment (a model plus code oracle). **Question ranked first (of three
in `experiments/8-key-identity.md`):** is a version key's identity its *value
content* (constants, binding locations, frame coordinates, continuation chain), or
also the canonicalisation *mode* — and does version creation look the key up after
the budget widens it? The round-7 algorithm looks up the incoming key only, then
creates the all-location key; the incumbent's exact equality compares a stored
`generic` bit that `canonicalize` sets from the widening argument. Ranked above (B)
whether the design inlines a cross-function mutual tail cycle (Q14) and (C) Q12's
fact ownership.

**What was read and modelled.** Both incumbent version tables and canonicalizers,
and a model of the creation rule over an abstract key space
(`experiments/8-version-model.py`, output `.out`; 2-component keys, all arrival
sequences of the 9 possible value vectors, breadth-first over reachable version
tables, budget 3).

**Answers.**

1. **The mode bit is not content and makes value-identical keys distinct.** A key
   is values + `c_origin`/`c_bias` + continuation chain; `generic` is set by
   `canonicalize`/`conform_generic` from the *argument*
   (`residual_builder.c:856`, `residualize.c:168`) and compared by
   `abc_symbolic_context_equal` (`symbolic.c:57-59`), while the same property is
   recomputed from the values by `canonical_generic_context` (`:74-85`) and family
   equality ignores the bit (`:64-72`). The C sink's `VERSION_LOOP_ENTRY` is
   literally `canonicalize(key,1)` — the code reason its loop entry forgets
   invariants. In the design (loop keys keep constants) this costs a duplicate
   body exactly at a residual-function entry that is a loop header: the
   all-location entry key and the loop-invariant backedge key agree on every value
   (a residual entry supplies only locations; may-write widening only removes
   constants) and differ only in the bit. Model: 2 versions, 2 sharing a value
   vector with the bit; 1 version, 0 with content identity.
2. **The round-7 creation step never finds the general slot.** It looks up the
   incoming key, widens, and creates without a second lookup: past the budget,
   every distinct incoming key creates another all-location version — a duplicate
   key and unbounded family growth. Model: 4, 6, 8, 10 versions for arrival
   sequences of length 4, 6, 8, 10 (grows with variety); content identity plus
   lookup-after-widening saturates at 3 = budget, one version per value vector.
   Both incumbent sinks look up after widening (`residual_builder.c:1110-1119`;
   `residualize.c:410, 436`), so the design's algorithm contradicted its own
   invariant ("a version is created whenever an edge key differs from every
   existing version's key") and its own bound.
3. **The two key rules compose with no special case.** The all-location value key
   is a fixed point of the loop-invariant rule (no constants to widen, every
   component already a location), so the entry rule and the loop rule agree when a
   residual function's entry pc is a loop header: one version, one body. The
   `create(f.entry, ...)` bypass is unnecessary; the entry is an ordinary
   `version_at` call with the all-location key.
4. **Native's headroom condition is a binding refinement, not core identity.**
   `version_for` requires `in->limit[s] >= v->in.limit[s]` for an exact match
   (`residualize.c:411`): proven stack headroom is a resource condition that
   only *splits* a core key. A split stays in one family, so the per-family budget
   still bounds it, and a binding never merges two core keys.

**Decision recorded in ARCHITECTURE.md.** The key summary, the family, the
invariants, the data representation, the algorithm block, the bounds, the
interfaces and the evidence are updated: identity is content (constants,
locations, frame coordinates, chain); the all-location form is a value key and
"is generic" is a derived predicate; every widening is followed by a lookup; the
entry is created through `version_at`; a binding may add a resource refinement
that only splits. The stored mode bit and the lookup-before-widening order are
recorded as rejected alternatives with the model numbers. Q16 is answered; Q14's
evidence is sharpened (`nested_eligible` requires call-component size 1, so the
incumbent residualizes mutual calls, tail or not) but its policy choice stays open;
Q2, Q12 unchanged.

**Not established.** Whether any corpus module other than a hand-built two-root
case reaches the loop-header-entry configuration (the documented counter is fully
inlined, so its header is a virtual entry); the exact native headroom semantics
(`limit` records required cells, `residualize.c:84-92`) and whether native could
drop the refinement; the compile cost of the family scan (`version_for` is
linear in the versions at a pc, and the family count is a scan, not an index).

**Next uncertainty.** Q14's policy (inline a mutual tail cycle with a module-wide
cycle body, or residualize it as the incumbent does) is now the only key-rule
question with a concept cost; then Q2's scope decision, Q12's ownership and Q10's
`K` value.

## Round 9 — only inlined recursion keeps constants; a live fixture prices Q7

**Mode:** experiment (a measured oracle on a live in-repo fixture). **Question
ranked first (of three in `experiments/9-tail-cycle.md`):** a canonical fixture
(`frontend/tests/compiler.lua:790-804`, `docs/abc-opt.md:100`) pins
residual-*entry* invariant specialization for a mutual tail-recursive SCC, while
the design's residual entry is the generic all-location key (Q7). Is that
precision recoverable by any key rule, and what does the design's inline rule for
cross-function tail cycles (Q14) have to say? Ranked above (B) Q2's total-vs-
per-family scope (the design-side answer came out as a corollary: a new *family*
at a pc arrives only on a call edge, so a one-pass driver can only bound the
value keys inside a family) and (C) Q12's fact ownership.

**What was read and measured.** `frontend/tests/compiler.lua:790-804` (staged with
the default `optimize=true`, so abc-opt output; live via `Makefile:212`, suite
passes), `docs/abc-opt.md:100`, `src/optimize.c:108-114, 299-318, 850-873`,
`docs/spec.md:167-170`; a probe that stages the fixture with and without abc-opt,
a two-caller variant, all four execution modes, and diffs the callee bodies
(`experiments/9-tail-cycle.lua`, artifacts `9-tail-cycle-out/`).

**Answers.**

1. **The fold is abc-opt's entry facts.** Pre-optimizer: 48 instructions, callee
   bodies read the parameter (`CGETN_A 4`/`3`) and add; after abc-opt: 21
   instructions, `even` returns/passes `PUSH8_A 9`, `odd` returns `PUSH8_A 10`
   (folded `marker+1`). Value 9 in off/threaded/eager/lazy; `opt` is a
   byte-identical fixpoint. So the fixture witnesses the per-argument entry join,
   not frontend lowering — Q7/Q4's "the lattice has no witness" needs this
   correction: the documented counter was fully inlined, but this fixture is a
   real residual-entry witness.
2. **The two-caller variant is the measured oracle for the design's entry
   policy.** With `even(4,9) + even(4,7)` the join widens `marker` and the callee
   bodies become exactly the generic-entry shape: `even` 9 instructions
   unchanged, `odd` 9 → 11 (`CGET1_A; ADDI_A 1; ZX32_A` instead of
   `PUSH8_A 10`). Value 16 in all four modes. The design therefore does not
   invent a code shape; it applies the incumbent's disagreeing-caller shape to
   every caller.
3. **No key rule can recover a residual entry's constants.** At a residual call
   the ABC ABI supplies *locations* (`CALL` gathers argument zero at `C0`; callee
   A/B empty), and one body serves every caller. The loop rule preserves
   constants **already present in a key**, so it is a no-op on an all-location
   entry key. This kills round 8's hope that a module-wide cycle body would keep
   a mutual SCC's invariants; only (i) the per-argument entry join or (ii)
   inlining can carry a caller constant into a callee body.
4. **Q14 answered: residualize every cross-function recursive call, tail or not;
   no module-wide cycle body.** Inlining a tail-only SCC would restore the
   constants as virtual-entry constants but replace the documented
   three-function/`TCALL` shape with one function, duplicate the cycle per call
   site, and still need a cross-function cycle body to keep the invariants past
   the all-location budget slot. The kept rule is the incumbent's derived
   `nested_eligible`: the only inlined recursion is a same-function self-tail
   cycle, which is a loop header. The core owns this recursion decision; the
   binding may only narrow it (frames, effects, hidden results).
5. **The consequence is a design rule, not a sink limitation:** only inlined
   recursion keeps constants. A residual recursive function — mutual *or*
   self-tail — has an all-location entry and therefore a no-op loop rule. The
   measured price on the canonical fixture: module 21 → 23 instructions (odd's
   body 9 → 11) and the two `PUSH8_A 9`/`PUSH8_A 10` assertions at
   `compiler.lua:803` stop holding. That output change rides on Q1/Q7's gate,
   which round 4 had already raised for `docs/abc-opt.md:100`; round 9 adds the
   frontend test to the blast radius and prices the loss.

**Decision recorded in ARCHITECTURE.md.** The headline adds "recursion is inlined
only when it is a same-function tail cycle, so residual recursion carries no
entry constants"; the calls-and-edges invariant and the call-policy bullet state
the core-owned recursion rule, the cross-function-cycle rejection and the
measured price; the entry-keys bullet states the residual self-tail case; the
algorithm comment marks the call gate; the round-4 lattice bullet's
"recoverable at virtual entries" justification is corrected and priced; a new
rejected alternative records the cross-function cycle inline option with the
measured comparison; the round-9 evidence block is added; Q14 is answered, Q7's
answer carries the round-9 correction, Q10 is narrowed to an open `K` value, and
the open-questions list loses Q14.

**Not established.** Corpus-wide cost of deleting the entry lattice (the
canonical witness is +2 instructions; round 4 measured larger folds on hand-built
mutual fixtures); whether the frontend test should be rewritten to assert values
and shape rather than immediates, or whether the user prefers keeping the lattice
for `docs/abc-opt.md:100` compatibility; policy (b)'s code size at a non-constant
trip count (a projection from round 5's exact-key loop).

**Next uncertainty.** With Q7/Q14 closed, the remaining decisions are the user
gates Q1 (ABC version policy), Q2 (budget number/scope), Q3 (portable-C scope),
Q9 (native loop-header policy), and the two measurements that need no user input:
Q12's one-owner shape pass and the value of `K` (Q10), plus whether the family
scan at a pc is acceptable compile cost.

## Round 10 — a residual call is an effect; `edge_to` is the only keyed edge

**Mode:** experiment (code reading + a measured probe of emitted ABC, generated C
and the native version count). **Question ranked first (of three in
`experiments/10-call-continuation.md`):** what creates a version and what ends a
version body? Is a residual (non-inlined) direct call an **in-body effect** that
resumes in the caller's body, or a control transfer plus a separate return
version/key — and which machine events create the keyed edges (branch/switch
arms, virtual returns, virtual call entries, fallthrough into a leader)? Ranked
above (B) the residual-function set (which functions get an entry version/body)
and (C) Q12's fact ownership, because it is a completeness/correctness defect in
the design's only normative procedure, not a policy choice.

**What was read.** `ARCHITECTURE.md:316-372` (the old `run()` block);
`src/symbolic.c:220-259` (`machine_call`: virtual → pushes a continuation, emits
an edge, `ABC_SYM_EXIT_CONTROL`; residual → pushes the sink's result values and
**returns 1**, so the walk continues at `return_pc` in the same body),
`:445-465` (`machine_foreign`/`machine_indirect`, same shape), `:471-477`
(`machine_return`: a virtual return pops the continuation, emits the return and an
edge to `frame.return_pc`); `gen/symbolic.lua:7` (`SYM_NEXT` returns
`ABC_SYM_EXIT_BLOCK` iff `m->blocks[m->pc]` — the **sink's** block array decides
body boundaries); `src/optimize.c:299-303, 364-385` (`dag_call` residual node;
`simulate_tree` rejects BLOCK and keeps walking, so ABC has no call-return
boundary); `src/residual_builder.c:1699-1758` (`on_call` emits an operation, no
terminator) and `:2048-2113` (`discover_leaders` does not mark call returns);
`src/residualize.c:445-462` (`discover_blocks`: `K_CALL → block[next]=1`),
`:785-801` (`compile_version` ends the body at any block) and `:589` (an `FCALL`
continues in-body); `:492-570, 592-598` (`native_emit_control`/`emit_edge` call
`edge`/`version_for`); `residual_builder.c:1212-1348, 1980-2046`
(`on_control`/`make_edge` compute target versions privately).

**Answers** (evidence: `experiments/10-call-continuation.md`, `.lua`, `.out`,
`10-version-count.c`, artifacts in `experiments/10-call-continuation-out/`).

1. **A residual direct call is an in-body effect, not a control transfer.** The
   shared machine already models it so: `machine_call` with `virtualize == 0`
   pushes the result values as binding locations and returns 1, and the walk
   continues at `return_pc`. There is no return edge, no return-pc version and no
   return key; the callee is reached by the call ABI, and the runtime
   continuation (ABC return address, C call expression, native stored resume
   label) lives inside the body. Measured: mutual and same-function **non-tail**
   recursive fixtures (`ping/pong`, `f(n)=f(n-1)+3`), abc-opt emits the post-call
   computation directly after `CALL_A` (`f0 0f CALL_A` → `15 ADDI_A 1`;
   `f1 2a CALL_A` → `30 ADDI_A 2`; self → `ADDI_A 3`), the pre-optimizer module
   likewise (`CSETN_A`), and abc-opt shrinks 58→24 and 31→13 instructions with
   values 13/15 in all four modes. The C sink keeps the call and its used result
   in one block (`block_9: v_19=abc_aot_function_1(...)` then
   `v_22=v_19+v_20`). Only native disagrees, because `discover_blocks` marks every
   `K_CALL` return pc a block: measured 19/12 (eager) and 11/8 (lazy) version
   bodies for 2/1 **non-tail** residual call sites (the fixtures' other call is a
   tail call, which has no return pc). That boundary is redundant: native already
   continues in-body after an `FCALL`, which clobbers the same cache, so the
   call-return block and the post-call version bodies retire (binding obligation:
   materialize values live across the call, hand back result locations, reset
   placement state).
2. **Every keyed edge is created by one driver function.** `edge_to(target,
   context)` = canonicalize + loop-invariant rule for a loop-header target +
   `version_at` (content lookup, per-family budget with lookup-after-widening).
   It is called for both arms of a branch (and every switch arm plus
   fallthrough), a virtual return's `frame.return_pc`, a virtual call's callee
   entry, and straight-line fallthrough into a leader; a body ends at any of
   these or at a terminator. The binding never sees a key: it receives version
   handles (`jump/branch/switch/return/call`). This replaces the three private
   target-version computations (`native_emit_control`'s `edge`, the C sink's
   `make_edge`, the ABC path tree), which is the drift the design's one-owner key
   rule exists to remove.
3. **The inline/residual decision belongs at the call instruction**, inside the
   driver-owned call hook — not to the old pre-dispatch test "pc is a direct-call
   target" (that pc is the callee's entry, not the call site). Inline: the machine
   pushes the continuation and the driver calls `edge_to` for the callee entry.
   Residual: `binding.residual_call` emits the call, results are locations, the
   walk continues at `return_pc`. The `K` fallback is exactly this residual form,
   so it drops the chain without ending the caller's body. Every residual
   function's entry version is created before any body is walked, so a call can
   name its target independent of walk order (determinism).

**Decision recorded in ARCHITECTURE.md.** The headline, the version concept, the
leaders fact ("a call-return pc is not a leader"), the deterministic-order
invariant, the new **bodies/edges/effects** invariant, the call-decision
invariant, the invalid-states list, the whole algorithm block (new `edge_to`, the
hook contract, the corrected `run()`), the join/loop/call bullets, the binding
interface (version handles; `branch/switch/return`; the driver owns every
version lookup), the retired paths (native's `K_CALL`-return block marking and
post-call versions; the sinks' private `edge`/`make_edge` target computation),
four rejected alternatives (post-call return version; residual call as a keyed
edge; binding-computed arm targets; trace layout through the fallthrough arm) and
a round-10 evidence block are updated; Q10's wording says "in-body residual call",
Q17 is added and answered, and the open-questions list records it.

**Not established.** The per-kind native version delta (only the total is
measured; the call-return attribution is code-structural); candidate B, the exact
residual-function set (entry roots, address-taken/indirect targets, the closure
over non-inlined calls); whether a virtual return's `return_pc` could be an
intra-body local label instead of a version (kept a version here, matching C and
native; a layout question, not a key rule).

**Next uncertainty.** Candidate B (residual-function set) is the last input-free
omission in the algorithm — `run()` needs the set before it can create the entry
versions; then the user gates Q1, Q2, Q3, Q9 and the input-free values Q10's `K`
and Q12's one-owner shape pass.

## Round 11 — the residual-function set is a root set plus lazy calls, not a pre-pass

**Mode:** experiment (code reading + a measured probe of abc-opt's emitted
function table, the native entry table and the portable-C writer). **Question
ranked first (of three in `experiments/11-residual-root-set.md`):** what is the
**residual-function set** — which functions get a residual entry version and a
body — and when can it be computed? `run()` starts from "each residual function"
and the design says every such entry version exists before any body is walked,
but a function is residual only if a call to it stayed residual, which is the
walk's output; the incumbent breaks the circle with a second, function-level
worklist (`optimize.c:862-873`), the one the design claims to delete. Ranked
above (B) native's entry set (`Q19`: may it shrink to the addressable entries?
the same fact, priced in the same probe) and (C) Q12's fact ownership, because a
normative algorithm that cannot start and a circular definition are worse than an
ownership preference.

**What was read.** `ARCHITECTURE.md:119-122` (entry-before-walking),
`:359-386` (`run()`), `:489-505` (per-function driver), `:64-73` (module facts
already list "entry roots", unused); `src/optimize.c:781-785`
(`retain_function` → `append_unknown_call`), `:809-817` (`mark_live_functions`),
`:826-846` (writer renumbering, CALL/TCALL rewrite, fail on a non-live call
target, `else memset(live,1)`), `:862-873` (`activate_function_facts` + dirty
loop); `docs/abc-opt.md:95`; `src/residualize.c:822-841` (native entry for every
function, `c_entry` split), `:96-106` (`resolve_execution_target` →
`image->entries[index]`), `src/vm.c:214,253-263` (host entry by export),
`gen/cold.lua:19-29` (`vm_resolve_indirect` accepts any function entry),
`docs/module-format.md:116-122` and `docs/callable-profile.md:81` (code addresses
enter only through relocations); `src/residual_builder.c:2704-2712`,
`src/residual_c.c:222-240, 1254-1280`.

**What was measured** (`experiments/11-residual-root-set.md`, `.lua`, `.out`,
`11-entry-table.c`, artifacts in `11-residual-root-set-out/`). Four hand-built
modules through the assembler, verifier, abc-opt and all four modes:
`acyclic-export` 2 → **1** function (inlined helper deleted; 42 in all modes);
`acyclic-no-export` 2 → **2** (no roots ⇒ every function kept, helper body still
emitted verbatim although its call folded to `PUSH8_A 42`); `recursive-export`
2 → **2** (the `CALL_A` survives and the caller continues after it:
`CALL_A; CPUSH_A; CGET0_A; RET`; 15 in all modes); `reloc-root` 3 → **2** (a
`.codeaddr` relocation keeps an otherwise-uncalled `target`; `dead` dropped; 42
in all modes). Native (eager): entries for **every** function, including one that
no export/reloc/call reaches (2/2 on `acyclic-no-export`); 4 bodies for the raw
two-function `acyclic-export` (1 virtual call, 1 virtual return, 0 real calls)
against 1 body for its abc-opt output; a non-exported function named only by a
relocation is entered and executes. Portable C emits every function of its input
module (1/2/2 bodies for the 1/2/2-function modules).

**Answers.**

1. **The ABC set is a static root set plus a post-walk residual-call closure.**
   Roots are exports ∪ code-address relocations ∪ revision-7 C-entry relocations
   (`optimize.c:813-816, 864-869`; documented `docs/abc-opt.md:95`); if all three
   tables are empty, every function (`:826`, measured 2 → 2). The closure is over
   the *emitted* call lists: residual (non-inlined) direct calls plus every direct
   call of a **retained** function (a refused body is emitted verbatim, so none of
   its calls can be inlined), transitively. The optimizer already walks only that
   closure; the writer emits it, renumbers it and rewrites displacements.
2. **Native's set is every function of its input module** (split by `c_entry`
   into execution/lifecycle images). The runtime reaches an entry only by an
   export name or by an indirect call whose public ABC entry address resolves to a
   function index, and the resolver accepts any function entry with a matching
   signature; code addresses enter a module only through relocations. So the
   cheap-looking "all functions" rule compiles one never-entered body per inlined
   callee on raw modules (measured), while the addressable-root rule would not.
3. **The portable-C sink emits every function**; exports only add wrappers, and
   unused statics are the C compiler's dead code, so the set has no cost.
4. **Design: the set is derived, not precomputed.** Only the **root set** is a
   pre-pass (`entry_roots`), because only it can be entered from outside the
   traversal. A residual call creates its callee's entry version at the call
   (`entry_version` = `version_at(callee.entry, all_locations, callee)`; the key is
   the call ABI, so identity is content and no other walk's progress matters).
   A **retained** body is the third source: the binding reports its direct call
   targets and they are residual by definition — exactly the incumbent's
   `retain_function`/`append_unknown_call` rule. The residual-function set is then
   the set of entry-version owners; the ABC writer emits exactly those functions
   (measured 2 → 1 and 3 → 2), and its "call target must be live" failure becomes
   unreachable. The incumbent's function-level worklist (`needed`/`dirty`/
   `ArgumentFact` activation, each residual callee re-walked) and the writer's
   `mark_live_functions` closure pass retire; the driver is `run(binding, module)`.

**Decision recorded in ARCHITECTURE.md.** Headline, one-line design, the version
concept ("a residual function is the owner of an entry version"), the
deterministic-order invariant (root pre-pass only), the data-representation entry
table (the version table's (owner, entry pc) pairs *are* the residual-function
set; ABC emits those functions, native's table is its root set), the invalid
states (a function emitted without an entry version; an entry version nobody can
name), the algorithm block (`entry_version`, `run(module)`, the residual-call hook
creating its target, the `retain` step), the call-policy/entry-key/complexity
bullets, the binding interface (`entry_roots`, `residual_call(call, target)`,
`retain(function, direct_targets)`, `run(binding, module)`), the retired paths
(the function-level worklist and `mark_live_functions`), three rejected
alternatives (static call-graph closure; walk every function; requiring all entry
versions up front), the round-11 evidence block, and the round-10 evidence's
superseded sentence. Q18 is added and answered, Q19 is added open; the open list
gains Q19.

**Not established.** Whether native may shrink its entry set to the addressable
entries plus residual calls (Q19): code says the reachable set is exports ∪
relocations, the probe prices it (2 of 4 raw eager bodies are never entered, one
of them the inlined callee's own entry; the other is the round-10 call-return
split), but no restricted image was built. Also whether an ABC retained body's
`TCALL` targets must be roots (the incumbent says yes: `retain_function` records
both `CALL` and `TCALL`).

**Next uncertainty.** Q19 (native compile set) is the last input-free choice;
then the user gates Q1, Q2, Q3, Q9, Q10's `K` value and Q12's one-owner shape
pass. With Q18 answered the design's normative algorithm has no undefined input:
`run(module)` starts from the binding's root set, and every other version is
created by the construct that needs it.

## Round 12 — a refusal belongs to the owner; the entry version survives it

**Mode:** experiment (code reading + a measured probe of abc-opt retention, the C
writer and the four execution modes). **Question ranked first (of three in
`experiments/12-refusal-owner.md`):** what is the **unit of a sink refusal and of
version publication**? The design lets a sink refuse "at a later version of the
same owner", discards only "unpublished versions", and gives every sink a verbatim
retained body — but (a) if recordability were a function fact the mid-walk
machinery would be dead, while if it depends on the walk "no walk" is false and the
queue must be cleaned; (b) a per-version publish can leave an owner whose entry
body was published and whose interior body is refused (a mixed function); (c) only
the ABC writer has verbatim source residue — portable C rejects what it cannot
record and native fails the image. Ranked above (B) the same paragraph's unstated
call contract for calls with no target version (indirect `CALLI`/`TCALLI`,
foreign externs; answered as a corollary, Q21) and above (C) Q19's native
compile-set policy, because a refused owner can be emitted with dangling interior
references.

**What was read.** `ARCHITECTURE.md` pre-round (`:109-111` entry-owner, `:264-278`
retained-body paragraph, `:366-390` run block, `:454-463` entry creation,
`:543-556` interface); `src/optimize.c:726-787` (the whole function is built in a
local `Bytes`, freed on failure; `retain_function` replaces the whole
`FunctionCode`), `:54-56` (`direct_target` accepts `K_CALL` **and** `K_TCALL`),
`:871` (retain on any `residualize_function` failure), `:826` (all functions
emitted after the walk loop), `:291-318` (`materializes_frame`, `dag_call`/
`dag_tail`), `:726-749` (`residualize_function` installs no float/pow handlers);
`src/symbolic.c:205-215,304-310` (a float/pow with no handler exits BOUNDARY only
when non-folded), `:443-457` (`machine_indirect`: known target → direct call, else
an unresolved effect), `:530-538` (`machine_foreign`); `src/residualize.c:598-650`
(`native_emit_indirect` → `place_indirect_resolution`, no version), `:794-799`
(any failure fails the image), `:822-841` (entry loop has no skip), `:845`
(`publish` at the end); `src/residual_builder.c:2399-2400` (`supported` only after
the whole function IR), `:2469-2533` (`function_references_unsupported`,
`remove_unsupported_dependencies`, called from `finalize_program`), `:2537,2560`
(unsupported functions omitted), `src/residual_c.c:1232-1237` (memory profile
rejected), `:1266-1272` (export error); `docs/symbolic-vm.md:164` (portable C
rejects outside its integer/control/direct-call subset), `docs/architecture.md:208`,
`docs/abc-opt.md:100` ("unsupported functions are retained independently").

**What was measured** (`experiments/12-refusal-owner.md`, `.lua`, `.out`,
artifacts in `experiments/12-refusal-owner-out/`). Four hand-built modules through
the existing assembler, verifier, abc-opt, the C writer and all four execution
modes. `retain-float` (a non-constant `FADD`/`F2IS` over float arguments, followed
by an independently foldable `3 + 4` witness) is emitted **byte-identically**
(raw == opt, a fixpoint) with the witness still unfolded — the whole owner is
retained — and executes in interpreted/compiled/lazy/threaded (8). `fold-float`
(the **same** float instruction kinds with constant operands) optimizes 10 → **4**
instructions (`PUSH8_A 8; RET_A 0 1`, value 8 in all modes). `mixed` (a retained
float owner next to a foldable sibling) keeps the owner byte-identical (2 → 2
functions) while the sibling optimizes to `PUSH8_A 7`, and both exports execute in
all modes (calc = 8, good = 7). `calli` (round 11's relocation-rooted indirect
call) is retained byte-identically and executes in all modes (42). The C writer
**rejects** all four modules (exit 1, "portable C currently supports only the
integer/static profile"), so it never retains and never reaches the incumbent's
silent per-function drop.

**Answers.**

1. **Recordability is a property of the walk, not of the function.** The same float
   instruction kinds are recordable when their operands fold and unrecordable when
   they do not; a pre-walk "contains a float/pow operation" predicate would retain
   `fold-float` and lose its whole fold. The refusal is discovered mid-walk and
   stays.
2. **The refusal is owner-granular and the entry version is the survivor.** A
   function is entered from outside only at its entry pc (`verify.c:131-134`), and
   every interior version is created by an edge inside that function's own walk,
   so the only cross-owner version handle is an entry version. On a refusal the
   driver drops every version owned by the refused function except its entry,
   keeps that entry's handle and gives it the source body as residue, and expands
   the owner's direct `CALL`/`TCALL` targets. No other owner's body is rebuilt.
   Publication is per owner: the incumbent ABC sink already builds a function in a
   local buffer and replaces or discards it as a unit (`optimize.c:726-787`), and
   the C builder finalizes all of a function's versions together
   (`residual_builder.c:2399-2400`). The measured `mixed` module is the form: the
   sibling is emitted and correct.
3. **The retained body's targets are `CALL` and `TCALL`, derivable from module
   facts.** `direct_target` accepts both (`optimize.c:54-56`) and `retain_function`
   records both (`:782-787`), closing round 11's open item; the direct-call graph
   already covers both (`:57-118`), so the round-11 hook argument
   `retain(function, direct_targets)` retires.
4. **Only ABC can retain.** Portable C has no verbatim source residue and rejects
   what it cannot record (measured; documented `docs/symbolic-vm.md:164`); native
   has no per-function fallback (`residualize.c:794-799,822-841`). A binding must
   declare the capability; a refusal in a binding without it fails the build. The
   C builder's `supported` drop and `remove_unsupported_dependencies` closure are a
   post-walk salvage of functions the sink cannot emit, not a target mechanism.
5. **A call with no target version is an effect (Q21).** An unresolved
   `CALLI`/`TCALLI` is an in-body effect whose target is a binding location and
   whose callee the runtime resolves through the image's entry table (native
   `native_emit_indirect` → `place_indirect_resolution`; measured 42 in all four
   modes), which is why code-address relocations are entry roots. A statically
   resolved indirect call becomes the corresponding direct call
   (`symbolic.c:443-457`) and follows the direct-call rule. A foreign call names
   the binding's extern (`symbolic.c:530-538`). Neither is ever inlined or names a
   version; the ABC sink has no unresolved-indirect residue (`optimize.c:305-306`),
   which is exactly why the `calli` owner is retained.

**Decision recorded in ARCHITECTURE.md.** The one-line design and the version
concept add the owner-granular refusal and the surviving entry version; the binding
concept gains the verbatim-source-body capability; two new invariants (owner-
granular atomic refusal; only a direct call names a version); the execution
invariant becomes "walked at most once, each emitted body exactly once"; the
data-representation entry table and residue rules state the retained owner's single
entry version and per-owner staging; the invalid-state list gains a version of a
retained owner other than its entry, a cross-owner edge to an interior version, a
body published before its owner's refusal is resolved, and an indirect/foreign call
naming a version; the algorithm block gains the `FAILURE` and `REFUSED` branches
(`binding.retain(owner)` installs the source body and returns true → drop the
owner's other versions → expand `direct_targets(owner)` from facts, else fail), the indirect/foreign call hooks and
the `refuse` contract; the direct-call, entry-creation, refusal/publication and
call-policy bullets are rewritten; the binding interface becomes
`retain(owner) -> bool`, `indirect_call`, `foreign_call`,
`publish(owner)` and drops `retain(function, direct_targets)`; the retired paths
add the portable-C post-walk salvage; four rejected alternatives (pre-walk
recordability, per-version publish with owner revocation, universal retention,
silent C omission) and a round-12 evidence block are added; Q20 and Q21 are added
and answered, the open-questions summary records that round 12 closes round 11's
`TCALL` item, and Q19 stays the only open input-free choice.

**Not established.** The portable-C binding's exact scope under Q3 (reject the
module versus emit a statically recordable subset); whether any refusal is
reachable from a verified integer-profile module (the builder's type-compatibility
and unmapped-`HOME` paths were not constructed); corpus-wide retention frequency
and its compile-time share (not measured).

**Next uncertainty.** All remaining decisions are user gates: Q1 (ABC version
policy), Q2 (budget number and scope), Q3 (portable-C scope), Q9 (native loop-header
policy), Q10's `K` value, Q12's one-owner shape/cycle-body pass, and Q19 (native
compile set). The normative driver contract now has a defined answer for every
construct the machine can reach: direct calls inline or residualize, indirect and
foreign calls are effects, a refused owner is retained only where the sink can emit
one, and no version body is ever rebuilt.
