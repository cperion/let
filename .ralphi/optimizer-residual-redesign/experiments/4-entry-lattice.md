# Round 4 — where a widened entry key actually lives (and why the lattice can go)

**Question pursued (ranked first of three below):** the round-3 architecture says
a residual-function entry is "one version whose key is the monotone join of all
incoming keys, re-executed until the key stops widening". But call facts are
produced *by* symbolic execution, so the join can widen after a body has already
been walked and its residue produced. Where does that widening physically live,
what does it invalidate, and is the mechanism needed at all?

**Candidate questions and ranking (materiality first).**

| # | Question | Materiality | Verdict |
|---|----------|-------------|---------|
| A | Is the entry lattice a rule inside the version queue ("one version, re-executed") or a module-level fixpoint over residual functions with residue discard/rebuild — and is it needed at all? | **high** — correctness (a widened key makes emitted residue stale), the invariant "a version body is executed exactly once", the residue data representation (discardable per function), and the concept count (a second worklist level, call facts). | **chosen** |
| B | Which calls are residual, and is the documented recursive-counter specialization carried by the lattice or by inlining? This decides the lattice's scope or its death. | high — a wrong answer here would keep a mechanism that no measured behavior needs, or delete one that a documented fixture needs. | measured as part of A. |
| C | The ABC join's emission schedule (push-once/store-in-place vs push-per-edge) and its C traffic. | medium — a sink emission choice with a measurable code-size/traffic cost, no correctness or representation change. | deferred (round-3 next uncertainty, still open). |

**Method.** No implementation change. New ABC fixtures assembled with the
existing `tools/assembler.lua`, run through the existing loader/verifier in all
four execution modes (`build/abc run … --interpreted | --jit=threaded |
--compiled | --lazy`), and optimized with the incumbent optimizer through
`frontend/let/optimize.lua`. The portable-C sink was run on the same module.
Script: `experiments/4-entry-lattice.lua`; artifacts in
`experiments/4-entry-lattice-out/` (not committed). The counter fixture is copied
verbatim from `frontend/tests/optimize.lua:229`; the other fixtures are new.

## 1. Measured results

| case | what it is | in instr | out instr | funcs | idem | exec (4 modes) | specialization |
|---|---|---|---|---|---|---|---|
| `counter` | the documented fixture (`frontend/tests/optimize.lua:229`) | 53 | **18** | **1** | yes | ok | `BLTUI_A 50`, `ADDI_A 7`, **no `CALL_A`** |
| `counter-two-limits` | same, plus a second root calling `count_to(40)` | 56 | 36 | 2 | yes | ok (main 56 8, alt 42 6) | `BLTUI_A 50` in root 0, `BLTUI_A 40` in root 1: **two independent specializations, no join** |
| `mutual` | `even`/`odd` mutual tail recursion, args `(i, step)`: `i` decremented, `step` carried | 26 | 22 | 3 | yes | ok (93) | `PUSH8_A 7` at both tail-call sites, folded `100-7=93` and `200-7=193`; `i` unknown (`CGET0_A; JZ_A`) |
| `mutual-two-steps` | two roots calling `even` with step 7 and 9 | 30 | 30 | 4 | yes | ok (93, 91) | folded `93`/`193` **gone**: per-argument join widens `step` to unknown |
| `many-roots-40` (same step / distinct steps) | 40 roots over `even`/`odd` | — | — | — | yes | — | `0.07 ms` vs `0.06 ms` optimize time; folded 93 present vs absent |
| `mutual` → portable C | same module through `build/abc c` | — | — | 13 static | — | — | **no folded 93/193**: generic entry keys, no cross-function facts |

`mutual` is idempotent to a byte fixpoint (`opt⁴ == opt`), 166 bytes.

## 2. Findings

### 2.1 The documented counter does not witness the entry lattice

abc-opt inlines every non-recursive direct call (`src/optimize.c:302`,
`effect->virtualize=1`) and inlines a nested-eligible self-recursive callee once
as a loop candidate (`:301`, `:309-318`; eligibility at `:108-114`). The counter's
calls are `main → count_to` (acyclic), `count_to → loop` (acyclic) and
`loop → bump` (acyclic) plus `loop → loop` (self-tail, eligible). The optimized
module therefore contains **one** function, `main`, with the loop lowered inline
and `BLTUI_A 50`/`ADDI_A 7` as immediates — no `CALL_A` survives, no residual
call exists, and the argument-fact lattice is never exercised. The two-root
variant confirms it from the other side: each root is its own residual function
and inlines its own copy, producing `BLTUI_A 50` in one and `BLTUI_A 40` in the
other — the two entry keys are never joined.

Round 3's evidence line "the recursive counter fixture depends on the resulting
invariant-constant specialization" is therefore **retracted**. The specialization
is inline expansion (and, in the incumbent, the loop machinery's invariant-slot
handling), not `ArgumentFact`.

### 2.2 The real boundary is the residual call, and it is ABC-only

A residual call is emitted only for a recursive component that cannot be
inlined: SCC size > 1, a nontail `CALL` inside the component, or an already-used
loop candidate (`optimize.c:299-303, 309-318`). Mutual recursion is the minimal
witness. The measured `mutual` module keeps real `CALL_A`/`TCALL_A` boundaries,
and the callee bodies are specialized by caller facts: the constant step becomes
`PUSH8_A 7` at the call sites and folds the done cases to 93/193, while the
decremented `i` is unknown. With two roots passing steps 7 and 9, the per-argument
join makes `step` unknown and both folded values disappear — the join is per
argument, not whole-key.

The other two bindings do not have this mechanism at all:

- The portable-C builder's shipped path passes **no** argument facts
  (`src/residual_c.c:1239`, `abc_residual_build(module, NULL, …)`); its
  initial context is all-backend (`residual_builder.c:2177-2210`) and its
  embedded/virtual entries deliberately preserve incoming constants
  (`:898-933`, `make_home = facts && …`). Measured: the C output for `mutual`
  has no folded 93/193.
- The only other lattice implementation, `abc_residual_analysis_activate_facts` /
  `_join_call_facts` (`src/residual_analysis.c:215-266`), has **no caller**
  anywhere in `src/`, `frontend/` or `tools/`; `residual_builder.h`'s
  `argument_facts` option and the bundle's call metadata have no consumer in
  `residual_c.c`. It is a second, dead copy of the ABC lattice.
- Native selects a block version at the call site, so its entry keys are ordinary
  keys (no single-address constraint).

So the lattice exists for exactly one population: ABC residual calls.

### 2.3 The incumbent's mechanism is a function-granular fixpoint with rebuild

`optimize_impl` keeps `ArgumentFact **facts`, `needed`, and `dirty`
(`optimize.c:862`), seeds roots with unknown facts (`:866-869`), and loops
(`:870-873`): pick a dirty function, **`clear_function_code`** (frees its code,
provenance and recorded calls), re-run `residualize_function` with the current
facts, then join every recorded call's facts into its callee (`join_call_facts`,
`:853-855`) and mark the callee dirty if anything widened. Cross-function
addresses are never frozen: call displacements and function entries are encoded
only in `write_module` after the fixpoint (`:826-833`).

Consequences the architecture must state:

1. **A widened entry key invalidates the whole function's residue**, not one
   version. Re-executing only the entry version would leave already-emitted
   downstream versions built from stale constants.
2. The loop is over **residual functions**, not over versions: one run per
   function, and within a run every version body is executed exactly once. The
   global invariant "a version body is executed exactly once" holds only if no
   entry key ever widens — which is the design question.
3. The lattice is monotone per argument (`unreached → constant → unknown`,
   `:854`), so a function runs at most `2·arity+1` times; the join is commutative
   and monotone, so the fixpoint is independent of function order (determinism is
   structural, not an accident of the worklist).
4. The residue store must be discardable per function until publish: ABC code is
   one buffer per function and calls are re-encoded at module-write time. The
   measured `mutual` output shows the widening really happened: had the first
   key `(50, 7)` been kept, `i == 0` would have folded and the `JZ_A` would be
   gone; the emitted body tests `i` at runtime, so the body was rebuilt under the
   joined key `(⊥, 7)`.
5. Measured cost at this size is nil (`0.06–0.07 ms` for 40 roots, same vs
   distinct steps). The cost bound is structural, not a measured regression.

### 2.4 Why the lattice can be deleted instead of formalized

If a call that can only name a function entry is entered at the **generic
all-location key**, then no key can widen anywhere, the fixpoint is vacuous
(one run per function), and the call-fact lattice, the dirty loop, the
discard/rebuild policy, and the entry-join rule all retire. What is lost is
cross-call constant specialization for residual calls — the measured
`mutual` folds (`93`, `193`, `PUSH 7` at the call sites). Nothing else changes:
the callee body is built once with unknown arguments, which is exactly what the
sibling portable-C sink already does.

The lost specialization is *recoverable where it matters*, because the ABC sink
must inline anyway: `docs/abc-opt.md:82-91` requires the canonical `sq(a)+sq(b)`
fixture to fold after inlining, and the measured counter is generated by inline
expansion. An inlined call is a **virtual entry**: an ordinary version whose key
carries the caller's constants and whose continuation chain identifies the return
site (round-3 key correction). So specialization of callee bodies comes from
version edges, not from call facts.

Two constraints bound the inlining option and explain the incumbent's policy:

- **Nontail recursion cannot be inlined.** Version identity compares the
  continuation chain (`src/symbolic.c:39-61`), and the generic fallback
  `canonical_generic_context` also keeps it (`:63-75`). Each inlined nontail
  recursive layer pushes a continuation, so the key family never converges; the
  per-pc budget cannot merge them. Tail-only cycles (the counter's self-tail
  loop, mutual tail recursion) do not grow the continuation and inline into a
  version cycle. This derives the incumbent's `nested_eligible` rule instead of
  citing it.
- **Call-site multiplicity is not bounded by the per-pc key budget.** Family
  equality includes the continuation chain, so each nontail call site is a
  distinct family at the callee's pc: inlining across a call chain multiplies
  (two calls per level → 2^depth). The retired `ABC_OPTIMIZER_PATH_LIMIT` was
  the only bound. The versioned driver needs a per-residual-function version
  budget and a residual-call fallback at that budget — the fallback's entry key
  is the generic key, so it adds no new rule.

### 2.5 A second, unintended consequence: the loop-header generic key is not neutral

Round 3 made every edge into a non-entry loop header take the generic
all-location key, justified as "the only specialization this can lose is a
loop-carried constant, which is loop invariant by definition and belongs to an
entry key anyway." That justification is wrong for the common case: a loop
header also has **forward** predecessors from before the loop, and their
constants are legitimately invariant *inside* the loop (bounds, strides, table
bases). Forgetting them makes every loop body read them back from memory. The
incumbent keeps them: the counter's inlined loop folds `BLTUI_A 50` and
`ADDI_A 7` in the steady-state body, and the portable-C sink does the opposite
(`residual_builder.c:1090-1091` forgets constants at loop entries), which is why
round 3 read the two sinks as converging when in fact they disagree.

Three coherent choices exist for a loop header and they trade real things:

1. **generic key** (round-3 rule): one body, no widening mechanism, invariant
   constants lost.
2. **per-slot join** of the incoming keys (what the ABC loop-home machinery does
   in another form, and what the C sink's `widen_recursive_key` gropes at): one
   body, invariant constants kept, but a widening join whose body must be rebuilt
   — the same function-granular fixpoint deleted in §2.4, now at loop granularity.
3. **exact keys** (no loop mode at all): each distinct key is a version; a loop
   with a constant-initialized changing slot unrolls until the per-pc budget and
   then converges to the generic version. No mechanism, but up to `budget`
   versions per loop header and a peeled prologue.

This is a version-policy choice with a code-size/compile-time cost, not a
correctness bug. It is raised as an open question (Q11); round 4 does not decide
it, and the architecture keeps round-3's rule flagged with the counterexample.

## 3. What the numbers do and do not establish

Established: the counter is fully inlined and does not exercise the lattice; the
residual-call population is mutual/nontail recursion; the entry join is per
argument; the incumbent implements it as a function-granular rebuild; the C sink
uses generic entries and the residual_analysis lattice is dead; a generic entry
key deletes the lattice with the measured loss of `mutual`'s folded constants;
nontail recursion cannot be inlined because continuations are part of key
identity; per-pc budgets do not bound call-site duplication.

Not established: the byte-level cost of a versioned ABC sink with generic entries
and the new inline budget (no prototype); the value of the lost cross-call
specialization on real modules (unmeasured; the fixture population does not
depend on it); which loop-header key form wins (Q11); the version budget number
(Q2); whether dropping the documented "invariant arguments still specialize"
behavior of `docs/abc-opt.md:100` is acceptable (a user gate under Q1).

## 4. Recommendation

Answer A: the entry lattice is a **module-level fixpoint over residual functions
whose widening discards and rebuilds the entire function's residue** — but it
should not be built. Give the forced single-address entry the generic key,
delete the fact lattice/dirty loop/call facts/rebuild, and let specialization
come from virtual-entry versions produced by inlining (bounded by a new
per-residual-function version budget). Keep the two-level fixpoint documented as
the rejected alternative and as the fallback if the user requires the documented
cross-call specialization for non-inlinable recursive calls.
