# Round 7 — what the version budget caps, and why the continuation chain needs its own bound

**Question pursued (ranked first of three below):** `ARCHITECTURE.md` claims "exactly
three canonicalization points": a residual-call/module entry takes the all-location
key, a loop header takes the loop-invariant key, and at the per-pc version budget a
key "is replaced by the canonical all-location key" (Q5/Q10/Q11). But a key is
*constants + locations + the continuation chain*, and the chain identifies the
return site of every inlined call. Can the all-location fallback bound the version
count at all — and if not, what actually bounds it, with what fallback?

**Candidate questions and ranking (materiality first).**

| # | Question | Materiality | Verdict |
|---|----------|-------------|---------|
| A | Does the per-pc version budget bound *all* version multiplicity? The key's continuation chain is never widened, so the all-location fallback can only merge keys inside one chain. What is the authoritative budget quantity (total versions per pc, versions per key family, or chains per pc), and what is the fallback? | **high** — it decides whether the approved "eight total versions per original PC" (`REFACTOR.md:811`) is satisfiable at all, whether compile time/code size are bounded, and whether the budget is a key canonicalization or an inline/residual decision. It changes the mechanism count and the budget's owner. | **chosen** |
| B | What is the key of a version that is simultaneously an inlined callee entry and a cycle header (the documented counter's `loop` *is* function 2 and its header *is* the function entry), and is a residual-call entry a canonicalization of an edge key at all? | high for the flagship P shape and the documented test, but the answer falls out of A: the generic entry key is the call ABI's key for the callee's own residual-function entry, not a pc-scoped edge canonicalization; the loop rule then applies to *every* edge into a cycle header. | **answered as a corollary of A** and recorded in `ARCHITECTURE.md`. |
| C | Q14: cross-function tail cycles (mutual tail calls, inlined). Do they get the loop-invariant key, or the all-location key? | medium-high; but tail calls push **no** continuation (`symbolic.c:486-499`), so the multiplicity finding does not change Q14: a cross-function tail cycle has no per-function cycle body/transport fact, and the conservative all-location answer still stands. | deferred; unchanged. |

**Method.** (1) Read the three sinks' key/version code. (2) New probe
`experiments/7-call-paths.py`, artifacts in `7-call-paths-out/` (not committed):
a branch-free "call-diamond ladder" `f_i(x) = f_{i+1}(x) + f_{i+1}(x or x+1)` with
`2^depth` syntactic non-tail call instances, built with the existing assembler and
run through the existing `abc opt` sink; instruction counts from `abc dis`. The
ladder measures the multiplicity that the *versioned* sink would also have to emit
(one version per inlined call instance), because the version key includes the call
chain and therefore cannot merge instances the way the ABC value DAG can merge
identical applications.

## 1. The continuation chain is part of key identity and is never widened

Round 4 established that the continuation chain is in the key
(`experiments/4-entry-lattice.md` §2.4). What matters here is *where* it sits in
the equality and in the canonicalizations:

- `abc_symbolic_context_equal` compares the chain (`src/symbolic.c:45-53`), so two
  call instances of the same callee are different versions.
- `abc_symbolic_context_family_equal` compares the *shape* (`c_origin`, `c_bias`,
  A/B/C heights) **and the chain**, and deliberately ignores which values are
  constants (`src/symbolic.c:56-66`). So a "family" is exactly
  **(stack shape, continuation chain)**.
- Every canonicalization in the tree widens **values only**:
  `canonicalize` replaces each non-constant with a home and sets `generic`; it
  never touches `ncont`/`cont` (`src/residual_builder.c:851-868`).
  `widen_recursive_key` is also value-only (`:936-963`).
- Therefore the all-location fallback is **total inside a family** (the C sink's
  `family_count >= ABC_BLOCK_VERSION_LIMIT-1` → canonicalize → find or create the
  one all-location version, `src/residual_builder.c:965-1004, 1108-1117`) and
  **impotent across families**: two keys that differ only in the chain stay two
  keys no matter how far they are widened.
- The only code that removes a chain is a **call decision**: native's
  `inline_candidate` refuses to inline once the target pc already has
  `ABC_EXECUTION_VERSION_LIMIT` distinct continuations, and the call then remains
  a real call (`src/residualize.c:395-406`); `version_for`/`edge` otherwise fail
  the whole compile at the family limit (`:408-414, 424-437`).

This is the architectural gap `REFACTOR.md:811` recorded and did not fix: "the
implemented family count includes the virtual continuation chain;
`version_for()`/`edge()` count matching families, while `inline_candidate()` caps
continuation families separately. This differs from the approved eight total
versions per original PC." It measured 10 versions at helper entry PC 50.

## 2. The number of chains is the number of inlined non-tail call instances

`abc_symbolic_machine_call` builds one continuation component
`{return_pc, target, abase, bbase, cbase, old_origin, old_bias, dst}`
(`src/symbolic.c:471-477`). The verifier fixes the A/B/C shape at every pc
(`src/verify.c:284`), so two intra-procedural branch paths to the same call site
produce the *same* component: the chain is a function of the **call path**, not of
the branch path. Hence:

> the number of distinct chains (families) at a pc = the number of inlined
> non-tail call instances that reach it.

`abc_symbolic_machine_tail` pushes no continuation (`src/symbolic.c:486-499`), so
self-tail backedges keep their chain — that is why the loop-invariant key of round
5/6 is stable — and multiplicity arises **only from non-tail inlining**. Nontail
inlining is required: the canonical `sq(a)+sq(b)` output in `docs/abc-opt.md:82-91`
depends on it.

A call graph where each function has two call sites to the next function has
`2^depth` syntactic call instances. Under the versioned key that is `2^depth`
distinct versions at the leaf's entry pc, each with its own body; the per-pc
all-location fallback cannot merge one of them. The number is bounded only by a
*decision not to inline* at some call sites, i.e. by residualizing the call.

## 3. Measured: code size tracks the syntactic instance count

Branch-free "call-diamond" ladder `f_i(x) = f_{i+1}(x) + f_{i+1}(a)`, with `a = x`
(`same`) or `a = x+1` (`distinct`). Each level contains two syntactic call sites,
so the module has `2^depth` syntactic non-tail call instances and no branches at
all. The existing `abc opt` sink inlines every instance (a callee is
non-recursive), and its output tracks the instance count, not the module size:

```text
depth  instances   same in/out    distinct in/out
  3        8        29 /   13        35 /   22
  4       16        38 /   27        46 /   46
  5       32        47 /   55        57 /   94
  6       64        56 /  111        68 /  190
  7      128        65 /  223        79 /  382
  8      256        74 /  447        90 /  766
  9      512        83 /  895       101 /  777 (funcs 2)
 10     1024        92 /  904       112 /  788 (funcs 3)
 12     4096       110 /  922       134 /  810 (funcs 5)
```

Output doubles with the instance count up to depth 8-9 (about 1.75 emitted
instructions per instance for `same`, about 3 for `distinct`). From depth 9 the ABC
sink stops inlining the *outer* function and emits a residual call to a separately
optimized copy instead (function count grows, the total body plateaus). That stop
is consistent with an omitted ABC frame limit, not with a version budget:
`optimize.c` refuses to emit when `f->arguments+schedule.temps >= 255`
(`src/optimize.c:753, 762`), and the hoisted temporaries are per emitted value.
The versioned sink has one body per inlined instance (the chain differs), so it
would pay this instance count too, and its per-pc budget cannot reduce it.

**What this establishes and what it does not.** It does not measure the versioned
sink (there is none). It establishes the *quantity* the sink must bound — inlined
non-tail call instances — and that it is exponential in the acyclic call graph,
independent of branches. Branch multiplicity is already bounded by the per-pc
(per-family) budget: branch paths that reconverge share a chain, so the
all-location fallback merges their keys. Call multiplicity is not: every instance
is a different family.

## 4. Corrected design

**4.1 A residual function's entry key is the call ABI, not a canonicalization.**
The callee's own residual function starts at the generic all-location key because
its callers materialize argument values into binding-defined locations (native:
ABI registers/homes; portable C: block arguments; ABC: the callee C frame placed
at the caller's call-time C height, `src/symbolic.c:470`). So the driver
creates the entry version directly; no *edge* is canonicalized because it enters a
function entry, and a virtual (inlined) entry is an ordinary version. Consequences:

- `version_at` loses the entry branch entirely; the "three canonicalization
  points" become one widening rule plus a budget.
- The loop rule applies to **every** edge into a cycle header, including an
  inlined callee entry. This matters concretely: in the documented counter
  `loop` **is** function 2 and its header pc `0x29` **is** that function's entry
  (`7-call-paths-out` not needed; `experiments/6-may-write-out/counter.dis`
  shows `function 2` starting `0x29` with the `TCALL_A 0x29` backedge). A
  pc-scoped entry rule would take the all-location key there and make the measured
  P shape (`BLTUI_A 50`/`ADDI_A 7`, 2 of 4 constants kept) unreachable even though
  round 6 measured the may-write set `{2,3}`. The wording "a non-entry loop header"
  is retired: the rule is about the *edge and the target pc*, not about the target
  being somebody's entry.
- The one-entry-address rule survives as a consequence, not as a rule: a residual
  function has one entry version (the generic one), so every call to its address is
  correct; virtual entries are separate versions in the caller's residual function.

**4.2 The per-pc budget is a per-family budget.** Family = (shape, chain)
(`src/symbolic.c:56-66`). Inside a family the all-location fallback is total: at
most `budget` versions, one of which is the all-location form. Consequently
`versions(pc) = Σ_families versions(family) ≤ families(pc) × budget`, and the
approved "eight total per pc" is not that quantity — it is unenforceable by key
widening because no widening removes a family.

**4.3 Inlining multiplicity is a second bound with a different fallback.** No key
widening removes a chain, so the only fallback is to **not inline** — a residual
call at the callee's generic entry key. Recommended rule (owned by the driver, with
the binding supplying only call eligibility): inline a non-tail direct call only
if the target pc has fewer than `K` distinct continuation families; otherwise
residualize. This is the incumbent native rule generalized (`src/residualize.c:
395-406`), is deterministic under the driver's fixed traversal order, is local
(one family count at the target pc), and gives the bound
`families(pc) ≤ K`, hence `versions(pc) ≤ K × budget`.

Rejected alternative (recorded): a *static* capped call-path multiplicity per
function in module facts, with "inline iff instances(callee) ≤ K". It makes the
decision order-independent and needs no version-table scan, but it needs a new
module fact, a saturating DP over the call DAG, and it over-counts paths that will
be residualized for other reasons (quality loss either way). The dynamic count
buys the same invariant with one counter and no new fact; revisit only if the
order-dependence is shown to matter.

**4.4 The budget policy needs a scope, not only a number (Q2).** The approved
policy must say *which* quantity is capped. Recommendation to the gate: the
number 8 is the **per-family** budget (with "the general slot" being the family's
all-location version), and `K` separately caps families per pc (suggested equal to
the same number). If the user requires a *total* eight versions per pc, the design
must share one budget between constant families and chains, which weakens the
all-location fallback and changes what "the general slot" means; that is a policy
choice, not something the key rule can decide.

## 5. Consequences for the documents

- `ARCHITECTURE.md` "exactly three canonicalization points" is replaced by:
  (i) a residual function's entry version is the generic key because of the call
  ABI; (ii) every edge into a cycle header takes the loop-invariant key;
  (iii) the per-family budget takes the all-location form; and a separate
  inlining-multiplicity bound whose fallback is a residual call.
- The version bound becomes `families(pc) ≤ K` and
  `versions(pc) ≤ K × budget`; compile time is bounded by
  `Σ_functions (1 + K) × code(f) × budget`.
- Q10's "one per-residual-function version budget whose fallback is a residual
  call" is sharpened: the *mechanism* is the family count at the target pc, not a
  per-function version count (a per-function count would also stop inlining for
  unrelated calls and is not what the incumbent measures).
- Q2 (hard gate) gains the scope question; the number alone does not determine
  behavior.
- Q5's "three canonicalization points" wording, and Q7/Q8/Q13 references to
  "non-entry" loop headers, are updated to the edge rule.

## 6. Not established

- Corpus chain multiplicities and the right `K`; the ladder is synthetic and
  unbranched.
- Whether the versioned ABC sink's loss of cross-instance value sharing (the ABC
  DAG's identical-application CSE, visible in the same-argument column) is
  material on real modules; it is a code-size cost of making every virtual entry a
  version.
- The exact trigger for the incumbent's stop at depth 9; the 255-cell C-frame
  limit is consistent with the code but not instrumented.
- Q14 is untouched: non-tail inlining multiplicity does not apply to tail cycles
  (no continuation is pushed), so the conservative all-location answer for
  cross-function tail cycles remains the open question it was.
- Native's Q9 measurement and the portable-C binding's corrected loop predicate
  remain open as before.
