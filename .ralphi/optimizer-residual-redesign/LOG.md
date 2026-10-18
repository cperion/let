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
