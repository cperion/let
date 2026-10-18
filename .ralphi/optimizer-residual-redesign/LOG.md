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
