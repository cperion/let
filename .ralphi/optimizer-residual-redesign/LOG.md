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
