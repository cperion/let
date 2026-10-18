# Round 1 — rederive: one semantics, one fact layer, one traversal

## 0. Method

No incumbent existed: `ARCHITECTURE.md`, `LOG.md`, `QUESTIONS.md` were empty
templates, so nothing was anchored. The design below was derived from
`CONTRACT.md` alone (sections 1–2), then checked against the code (section 3).
Longer rationale lives here; the candidate verdict lives in `ARCHITECTURE.md`.

Files inspected after deriving: `src/symbolic.{c,h}`, `src/residualize.c`,
`src/optimize.c`, `src/residual_builder.c`, `src/residual_analysis.{c,h}`,
`src/residual_ir.h`, `gen/symbolic.lua`, `schema/residual.asdl`,
`docs/symbolic-vm.md`, `docs/abc-opt.md`, `docs/threaded-execution.md`,
`REFACTOR.md` (target section, line 811).

## 1. Candidate questions, ranked

| # | Question | Materiality | Why |
|---|----------|-------------|-----|
| A | Which layer owns *specialization* (version identity, context keys, budgets, traversal)? Can the three independent traversals become one? | **high** | Changes data representation (path tree vs versions), number of concepts, compile-time bound, and ABC canonical output. Hits the version-policy hard gate. |
| B | Can abc-opt's function-wide expression DAG + Ershov scheduler be replaced by per-version residue scheduled locally? | high | Same axis as A; decides whether ABC residue is function-scoped or block-scoped. |
| C | Does the portable-C sink (2,759 + 1,293 lines, sole consumer of `residual.asdl`) earn its existence? | high (scope) | Deleting it removes a whole residue representation and a schema; not decidable without the user. |
| D | Should module facts (call graph, recursion, unknown-call reachability, block leaders) have one owner? | high | Pure duplication, no policy content; measurable compile-time win. Sub-problem of A's ownership rule. |
| E | Is `abc_symbolic_value.reg` (native register *or* sink DAG node) an acceptable union? | low | Convention-only; no semantic dependency observed. Not pursued. |

A is the most material and subsumes D. Chosen investigation: A, using D as the
confirming instance of the same ownership failure.

## 2. Derivation from the contract

The contract names the organizing idea: *one symbolic executor over verified ABC
that folds constants, earns facts, and hands residue to a sink*. It forbids a
second native allocator/residual IR, facade layers, round trips and legacy
dispatch. It requires one authoritative scalar computation, A/B symmetry, and
that runtime not depend on abc-opt. From that, the smallest entity set is:

1. **Module facts** — immutable, computed once: function ranges and signatures,
   block leaders, direct-call graph, recursive/nested-eligible components,
   unknown-call reachability, C-entry/export roots.
2. **Symbolic context** — A/B/C stacks of values (`constant | home | sink
   value`), C frame origin/bias, continuation stack, limits. This *is* the
   machine state and *is* the native register allocation.
3. **Context key** — the canonical identity of a specialization: which values
   are constants/known tags and where the rest live. Equality of keys is version
   identity; a canonical generic key always exists as the fallback.
4. **Version** — `(pc, key)` plus the sink's residue for the straight-line run
   from `pc` and its outgoing edges. The unit of code and the unit of work.
5. **Binding (sink)** — the target mechanism: emit/record residue, materialize
   join values, place code, publish. Never semantics.

Invariants forced by the contract:

- *One walk*: each version body is symbolically executed exactly once. Nothing
  re-walks emitted residue, so no SSA/IR round trip and no placement
  reconstruction can exist by construction.
- *One scalar computation*: the generated transfer handlers own folding, checks,
  branches and error edges; the binding only names the target mechanism.
- *Termination and determinism*: predecessor/successor discovery is a function of
  module bytes; versions are created in a deterministic queue order; at the
  per-call-site family budget the join key is replaced by the canonical generic
  key, which is unique per (owning function, pc, stack shape, continuation
  chain), so the worklist is finite without a module-wide budget.
- *Residue is never shared*: native consumes the symbolic cache directly
  (contract hard constraint); ABC and C may hold build-time residue, but it must
  never become a stage of native emission.
- *Frame transport ≠ control transfer* and explicit continuations stay in the
  core (already true in `abc_symbolic_machine_call/tail/return`).

Derived driver (sink-agnostic):

```
version_at(pc, key, mode):                     # called on every edge / entry
    key = canonicalize(key, mode)
    if compatible version exists: return it
    if family_count(pc, key) == budget:
        key = generic(key)                     # drop facts, keep homes
        return version_at(pc, key, GENERIC)
    v = create(pc, key)                        # allocate residue block
    queue.push(v); return v

run():
    for each entry root: entry[f] = version_at(f.entry, entry_key(f), ENTRY)
    while queue not empty:
        v = queue.pop()
        x = copy(v.key)
        while true:
            if machine.pc != v.pc and leader[machine.pc]:
                edge = version_at(machine.pc, x, EDGE)
                binding.join(v, edge, x); binding.jump(edge); break
            exit = symbolic_dispatch(machine(pc, x, transfer_mask=ALL))
            if exit == CONTROL|TERMINATED: binding.finish(v); break
            if exit == BLOCK|BOUNDARY: continue with machine.pc
            if exit == FAILURE: fail(v)
            assert machine.pc advanced
```

`binding.join` is the only place where differing incoming keys meet the target
key; it is where native spills/re-homes, C emits block arguments, and ABC would
copy to the target's C homes. This is target representation, not a second
allocator: it consumes symbolic values and emits the target's transport.

Two policy numbers only: a **version budget per (owning function, pc) family**
(approved policy for native is 8 total versions per original PC; see gate Q2) and
the **entry-fact lattice** for functions whose body is shared by all callers.

## 3. Reconciliation with the implementation

### 3.1 Ownership audit

| Idea | Owners today | Evidence | Verdict |
|------|--------------|----------|---------|
| ABC transfer semantics, folding, captures, continuations, frame transport | `src/symbolic.c` + generated `symbolic_dispatch.c` from `gen/symbolic.lua` | `symbolic.c:180-538`; `gen/symbolic.lua` | **single owner, keep** |
| Scalar check/branch/representation control flow | `gen/scalar_semantics.lua` bound by `scalar_banked.lua` / `scalar_symbolic.lua` + `src/symbolic_scalar.inc` | `docs/symbolic-vm.md` §check-driven | **single owner, keep** |
| Module call graph / SCC / recursion / nested eligibility | 3 copies: `src/optimize.c:57-118`, `src/residual_analysis.c:24-85`, `src/symbolic.c:553-578` | `diff` of the two SCC bodies: identical algorithm, formatting only (122 diff lines); validator `tools/validate_call_graph.c` already uses the shared one | **duplicate; must have one owner** |
| Unknown-call reachability | 2 call sites, per function: `src/residualize.c:824-825`, `src/residual_builder.c:2684` | each allocates an F-byte `seen` per function and re-walks the reachable graph | **O(F·(V+E)) per residualization; fold into the same SCC pass** |
| Block leaders | 2 implementations: `src/residualize.c:440-463`, `src/residual_builder.c:2047-2110` | different guards: C checks `next < function->end`, tracks loop headers and TCALL backedges; native does not | **drifted duplicate** |
| Context key canonicalization, equality, family budget, recursion widening | 2 implementations: native uses shared equality (`symbolic.c:45-75`) + `residualize.c:408-438`; C reimplements `residual_builder.c:851-978` (`canonicalize`, `widen_recursive_key`, `family_count`) | native's `edge()` counts families and conforms to generic at `LIMIT-1`; C canonicalizes/looks up at `LIMIT-1`; same intent, separate code | **duplicate policy; one owner in the core** |
| Traversal / versioning | 3 implementations: native `residualize.c:408-463, 776-801, 822-826`; C `residual_builder.c:979-1200, 2283-2345`; ABC `optimize.c:361-387` path tree | native/C are one walk per version block; ABC walks whole paths, stopping only at terminal/backedge, bounded by 4096 leaves (`symbolic.h:6-9`), with one context copy per branch and a `DagTree` carrying `abc_symbolic_value results[255]` (`optimize.c:41-44`) | **three implementations of one idea** |
| Residue | per sink: native none (emitter packets consumed immediately), C `residual.asdl`, ABC per-function DAG | `docs/threaded-execution.md` "One residualizer, two output bindings"; `docs/symbolic-vm.md` "Peer sinks" | **permitted by contract/REFACTOR target; keep** |
| Threaded vs native output | one residualizer, two emitter bindings | `docs/threaded-execution.md` | **already the correct shape; keep as the model for the other sinks** |

### 3.2 What the duplication already costs

- **Literal duplicate**: `optimize.c:57-118` and `residual_analysis.c:24-85` are
  the same algorithm. The shared file exists, is tested by
  `tools/validate_call_graph.c`, and the optimizer still does not use it.
- **Drift already present**: leader discovery differs between native and C
  (end guards, loop headers, tail-call backedges). This is exactly the failure
  mode of duplicated policy code.
- **Version-budget divergence is documented**: `REFACTOR.md:811` records that
  `abc_symbolic_context_family_equal()` includes the virtual-continuation chain,
  so the implemented count (10 versions at one PC) differs from the approved
  policy (8 total per original PC). The policy has no single owner, so its
  conformance cannot be stated in one place.
- **ABC traversal cost is not block-bounded**: per function the path tree may
  materialize up to 4,096 leaves (`ABC_OPTIMIZER_PATH_LIMIT`), each leaf a
  `DagTree` of ~4.2 KB (255 symbolic results) plus a copied context; that is a
  structural worst case of ~17 MB of leaf nodes per function, before the DAG.
  This is a projection from the struct and the limit, not a measurement.

## 4. The candidate architecture (derived)

Five concepts, one owner each:

1. **Module facts** (`symbolic.c` or a renamed core module): leaders, call graph,
   SCC/recursion/nested eligibility, unknown-call reachability. Computed in one
   O(V+E) pass per module, reused by every sink. Deletes `residual_analysis.c`
   as a separate owner and the two DFS helpers.
2. **Symbolic machine** (`symbolic.c` + generated handlers): unchanged semantics.
3. **Context key policy** (core): canonicalization, exact/family/generic
   compatibility, family budget, recursion widening, entry-fact lattice. Moves
   out of `residual_builder.c` and `residualize.c`, so native, C and ABC cannot
   disagree about what a version is.
4. **Version driver** (one new shared file, sink-agnostic): the pseudocode in §2.
   Owns block-leader stops, transfer masking, queue order, lazy activation,
   entry roots, edges and the canonical-generic fallback. It never inspects
   residue and has no opcode switch.
5. **Bindings** (`native_emit.c`/`threaded_emit.c` behind it, `residual_builder.c`
   for C, ABC emission in `optimize.c`): transfer callbacks, join
   materialization, placement/publish. Residue stays sink-owned.

Complexity: preparation `O(V + E + B·S)` for facts and `O(V + E)` for the
version graph; each version body is walked once, so the total symbolic work is
`Σ_version body length`, bounded by `leaders × budget` rather than by path count.
No pass re-walks emitted code.

What the cutover deletes (named, not wrapped): `optimize.c` `build_call_graph`
and `ArgumentFact` activation/join/dirty loop; `residual_analysis.c` as a
separate owner (its API folds into core facts); `symbolic.c`
`abc_symbolic_reaches_function` / `abc_symbolic_has_unknown_call`;
`residualize.c` `discover_blocks`/`version_for`/`edge`/`compile_version` driver
and the per-function recursion loop; `residual_builder.c` `discover_leaders`,
`find_version`/`create_version`/`version_for`/`make_edge` driver,
`canonicalize*`, `widen_recursive_key`, `family_count`.

## 5. The one part that is not derivable: ABC specialization policy (gate Q1)

The derived architecture has one traversal. Native and C already fit it. The ABC
sink does not: it emits a recursive path tree with no block reuse, so adopting
the driver changes abc-opt's analysis policy and its canonical output.

Analysis of the trade (not a decision):

- Versions do **not** lose path sensitivity: two paths with different keys
  create two versions of the join block, exactly as the tree duplicates it.
  Versions additionally merge *equal* contexts, which the tree always duplicates;
  merging costs one jump at the join and saves duplicated straight-line code.
- Versions **do** change output bytes, and ABC function entries cannot be
  multiplicity-specialized: a source function has one entry address, so recursive
  header specialization must stay a *single body keyed by the entry-fact
  lattice* (same shape as `ArgumentFact` today). Non-entry and virtual-entry
  blocks can have multiple versions.
- ABC code placement is per source function; a version reached by inlining from
  a caller must be owned by the caller's residual function (cross-function jumps
  are not representable as direct edges). The owning residual function is
  therefore part of the ABC key. Native has no such constraint.
- Determinism/idempotence must be re-established for the versioned sink; the
  canonical generic fallback and queue order make it plausible, not proven.

This is a change to version/analysis policy for abc-opt, which the contract marks
as a hard gate. Q1 records it; the candidate adopts versions as the recommended
shape and records the path tree as the fallback if the gate is refused. The
measurement plan if approved: existing optimizer fixtures (50 mirrored modules)
plus interpreter dispatch counts, optimized module size, `abc-opt` wall time, and
byte-identity of the second optimization on the fixture set.

## 6. Compile-time projection and measurement plan

| Cost | Today (structural) | Candidate |
|------|--------------------|-----------|
| Block leaders | computed twice, with different rules | once, O(code) |
| Call graph / recursion | SCC built 2× per module; plus 2 DFS walks per function | once, O(V+E) |
| Version key policy | 2 implementations | 1 |
| ABC exploration | ≤ 4096 path leaves/function × (context copy + ~4.2 KB leaf) | ≤ leaders × budget versions, one walk each |
| Native/C exploration | one walk per version (already) | unchanged |
| Passes over emitted residue | none (native/C); ABC: DAG → use counts → path uses → schedule → emit | ABC: per-version DAG + local schedule |

No timings were run in this round. The plan is a fixture-based measurement after
the cutover: `abc-opt` wall time and peak RSS on the optimizer fixture corpus,
JIT preparation time on the four-mode benchmark modules, and interpreter
dispatch counts for optimized modules.

## 7. Rejected alternatives

- **One shared generic residue IR for all sinks.** Rejected: violates the
  contract's native constraint and the REFACTOR target ("ABC and C sinks may use
  their own build-time representations; those must not become an intermediate
  stage in native emission").
- **Keep three independent traversals.** Rejected: one idea in three
  implementations is the largest source of duplicated policy, has already
  drifted, and makes "one walk per block" false for the whole stack.
- **Delete the portable-C sink to shrink the concept count.** Not rejected on
  merit, but it is a scope decision the contract does not grant: recorded as Q3.
- **Keep the ABC path tree as a "policy" inside the shared driver.** Rejected:
  path layout is inherently recursive (contiguous emission per path, local
  branch displacements), so sharing the driver would still require a distinct
  emitter and would not delete the traversal; it would only add a policy mode.
- **Represent ABC remainder as a stored SSA/IR and normalize afterwards.**
  Rejected by the contract (no SSA round trips, no post-hoc normalization).

## 8. What would falsify this design

- Measurement showing that shared (versioned) ABC blocks cost materially more
  interpreter dispatch than the duplicated tree on the fixture corpus.
- An ABC encoding/verifier constraint that forbids multiple versions of a
  non-entry block (would force function-wide path duplication for abc-opt).
- Evidence that the C sink's block arguments or the ABC per-version DAG need a
  placement pass after the version is chosen (would contradict "no placement
  reconstruction").
- A user decision that abc-opt output bytes are themselves a compatibility
  requirement.
