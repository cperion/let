# Architecture

Status: candidate (round 2). Derived from `CONTRACT.md`, checked against the
code, and corrected by the round-2 ABC probe. Rationale and citations:
[experiments/1-rederive.md](experiments/1-rederive.md);
[experiments/2-abc-versioned-sink.md](experiments/2-abc-versioned-sink.md).

The one-line design: **execute ABC semantics once, symbolically, per version;
module facts and version identity have one owner; a sink owns only residue.**
A version key is **constants plus the binding's locations** — never sink residue
identity. That one rule is what lets every sink keep residue per version.

## Essential model

A residualizing compiler is five things:

1. **Module facts** — immutable, computed once per module: function ranges and
   signatures, block leaders, direct-call graph, recursive/nested-eligible
   components, unknown-call reachability, entry roots.
2. **Symbolic machine** — A/B/C stacks of `constant | home | sink value`, C frame
   coordinates, explicit continuations, transfer dispatch. This is the only
   semantics and, for native, the register allocation.
3. **Context key** — canonical identity of a specialization: the constants and the
   locations of everything else. **The binding defines what a location is**
   (native: register/homing; portable C: version argument; ABC: C-frame slot).
   Key equality is version identity; a canonical all-location key always exists
   as the binding's generic fallback.
4. **Version** — `(pc, key, owning residual function)` plus the sink's residue for
   the straight-line run from `pc` and its outgoing edges. The unit of code and
   the unit of work. Residue is per version; **a key never contains sink residue
   identity**, so no sink needs a cross-version value graph to compare keys.
5. **Binding (sink)** — the target mechanism: the location vocabulary, record/emit
   residue, materialize join values, place and publish code. Never semantics.

Invariants:

- each version body is symbolically executed exactly once; residue is never
  re-walked, so no SSA/IR round trip and no placement reconstruction can exist;
- **a key contains only constants and binding locations**; sink value identity
  (`abc_symbolic_value.reg`) never reaches a key, so residue can be per version
  and a sink never needs a function-wide value graph for key equality;
- the core never inspects residue; `abc_symbolic_value.reg` is opaque to it;
- version creation order is a function of module bytes and facts (deterministic);
- at the per-pc version budget a join key is replaced by the binding's canonical
  all-location key, so the worklist terminates without a module-wide budget;
- **a function entry has exactly one version** (ABC `CALL`/`TCALL` can only
  target a function entry, `verify.c:131-134`); its key is the monotone join of
  all incoming entry/call keys — `unreached → constant → unknown` per argument —
  and its body is re-executed until the key stops widening. This is the entry
  lattice, not a second driver;
- native consumes the symbolic cache directly: no stored native residual IR.

## Concepts

The reader must hold exactly these five, in this order: **facts → machine →
key → version → binding**. Everything currently spelled "path tree", "argument
fact fixpoint", "version table", "directive driver", "leader discovery" is an
instance of one of them.

## Data representation

- `abc_symbolic_context` unchanged in shape: three stacks of
  `abc_symbolic_value {kind, stack, dst_stack, reg, home, dst_home, constant}`,
  `c_origin/c_bias`, continuation stack, limits, `generic`.
- **Key** = the context after the binding's canonicalization: **constants plus
  locations**. Non-constant values are replaced by the binding's location
  descriptor before any lookup or comparison. The binding also supplies the
  canonical all-location form used by the budget fallback; the core does not
  assume `HOME(stack,index)` for every slot (that is the native form only).
- **Version table** keyed by (owning residual function, pc, key); the owning
  function is identity for sinks whose code is placed in per-function ranges
  (ABC, portable C: the driver runs per residual function), and is implicit for
  native (one code arena; a module-scope table).
- **Residue is sink-owned, per version, and never shared**: native — none
  (emitter packets are consumed immediately; locations are registers); portable
  C — one `residual.asdl` block per version with block arguments as the join
  representation; ABC — one bytecode region per version, with that body's
  expression DAG scheduled locally, plus provenance and residual calls. ABC's
  only stable location is a **C-frame slot**; the join writes it (`CPUSH`/`CSET`)
  and the target body reads it (`CGET`). Constants stay in the key and need no
  store.
- Invalid states: a version without an owner, a key containing sink residue
  identity, an edge whose target key does not match the materialized location
  set, a sink value inspected by the core, or a join that bypasses
  `binding.join` are unrepresentable by construction.

## Operations and algorithms

```text
version_at(pc, key, mode):
    key = canonicalize(key, mode)
    if compatible version exists: return it
    if family_count(pc, key) == budget:
        return version_at(pc, generic(key), GENERIC)
    v = create(pc, key); queue.push(v); return v

run():
    for each entry root: entry[f] = version_at(f.entry, entry_key(f), ENTRY)
    while queue not empty:
        v = queue.pop(); x = copy(v.key)
        loop:
            if pc != v.pc and leader[pc]:
                t = version_at(pc, x, EDGE); binding.join(v, t); binding.jump(t); break
            exit = symbolic_dispatch(pc, x, ALL)
            CONTROL|TERMINATED -> binding.finish(v); break
            BLOCK|BOUNDARY      -> pc = machine.pc; continue
            FAILURE             -> fail(v)
```

- **Join materialization** (`binding.join`) is where incoming symbolic values
  meet the target key: native homes/re-homes registers, C emits block arguments,
  ABC stores live non-constant values into the target body's C-frame slots. It
  may change the operand-stack shape to the target key's canonical shape. It
  consumes symbolic values and emits target transport — it is not a second
  allocator.
- **Entry keys**: a function entry is one version (see invariants). ABC source
  functions and native recursive entries seed it with the entry-fact lattice;
  every recursive edge joins into it and widens the key monotonically
  (`unreached → constant → unknown`), re-executing the body until stable. A
  virtual entry (inlined acyclic call) is part of the caller's residual function
  and uses the caller's continuation chain in the key.
- **Bounds**: the per-pc version budget (native approved policy: 8 total versions
  per original PC; see Q2) and the entry-fact lattice. ABC's
  `ABC_OPTIMIZER_PATH_LIMIT` is a path-tree bound and retires with the path tree
  if Q1 is approved; it is not a module code-size budget either way.
- **Complexity**: facts O(V+E); preparation O(V+E) versions; one walk per
  version body; per-body key comparison and scheduling. No pass re-walks emitted
  code and no pass is exponential in branches.

## Interfaces and naming

- Core: `symbolic.c` (+ generated handlers) owns machine, folding, captures,
  continuations, module facts, and the key *rule*: equality/family counting,
  budget fallback, recursion widening, entry-widening order.
- Driver: one sink-agnostic unit, conceptually
  `abc_residual_binding { canonicalize(key, mode), canonical_generic(key),
  compatible, open/join/finish, jump, publish }` +
  `abc_residual_run(binding, function)`. The binding supplies its location
  vocabulary and canonical generic form; the driver owns traversal and the key
  rule. The name is the guarantee: a binding binds mechanisms, the driver owns
  specialization.
- Bindings: native/threaded emitter (two output bindings of one residualizer),
  portable-C residue builder → C writer, ABC emitter/writer.
- Retired paths (named now, deleted in the cutover):
  `optimize.c` call-graph copy, `ArgumentFact` dirty fixpoint loop (the lattice
  and entry widening move into the driver rule), and — conditional on Q1 — the
  whole path-tree machinery: `simulate_tree`/`DagTree`/`emit_tree`/
  `emit_phi_tree`/`mark_path_tree`/`branch_rematerializable`/
  `ABC_OPTIMIZER_PATH_LIMIT`, and the `noncall_effect` refusal of branchy
  effectful functions; `residual_analysis.c` as a separate owner; `symbolic.c`
  DFS reachability helpers; `residualize.c` and `residual_builder.c` private
  drivers, leader discovery and key canonicalization (their policy becomes the
  shared rule; each keeps only its location vocabulary).
- Kept, because it is required, not duplication: the entry-fact lattice and the
  single-entry-version rule (ABC `CALL` can only target a function entry); the
  per-sink location vocabulary; sink residue itself.

## Rejected alternatives

- **Shared generic residue IR for all sinks** — violates the native constraint
  and the approved REFACTOR target (ABC/C may hold build-time residue; it must
  never stage native emission).
- **Keep three independent traversals** — one idea in three implementations;
  already drifted (leaders, version budget), compile-time cost not block-bounded.
- **Keep the ABC path tree as a "policy" inside the shared driver** — path
  layout is recursive (contiguous per-path emission, local displacements), so
  the traversal would not actually be shared. Measured: 2^n suffix duplication
  and a whole-function cliff at 4096 paths.
- **Function-wide ABC value graph with sink value identity in version keys** —
  rejected round 2. It needs dominance-safe cross-version home reuse
  (`mark_path_tree`/`branch_rematerializable` are tree-shaped), keeps O(n²)
  hash-consing and per-path use counting, and buys nothing for the measured
  blow-up, which is control duplication. The portable-C sink already proves that
  constants + locations dominate the same cases (`diamond`, `choices`) with
  per-version residue.
- **Per-edge rematerialization/hoisting of pure expressions across versions** —
  deferred, not needed for the measured corpus. Reintroducing it would
  reintroduce the dominance question the per-version model exists to avoid;
  only a measurement showing added C traffic on real modules would justify it.
- **ABC stored SSA/IR + normalization** — forbidden by the contract.
- **Delete the portable-C sink** — plausible simplification, but a scope decision;
  raised as a question, not decided.

## Evidence

- Ownership audit with file:line citations, duplicate-SCC diff, leader-discovery
  drift, version-budget divergence: `experiments/1-rederive.md` §3.
- Round-2 measured ABC probe (new fixtures, existing assembler/optimizer/runtime):
  `experiments/2-abc-versioned-sink.md` §1–2 and `experiments/2-abc-probe.lua`.
  Key numbers: an 88-instruction branch chain optimizes to 16,382 instructions
  (186×, one input pc duplicated 4,096×, 23.9 ms); one more branch (94
  instructions) exceeds `ABC_OPTIMIZER_PATH_LIMIT` and the whole function is
  retained; functions with a branch and any non-call effect (`store`, `trap`)
  are retained unoptimized; the multi-result join grows 8 → 19 instructions;
  the documented canonical fixture (`docs/abc-opt.md:82-91`) is emitted exactly;
  every case is idempotent and executes identically interpreted/threaded.
- The C sink's per-version homes+constants policy:
  `src/residual_builder.c:851-877, 996-1062, 1083-1123`; key equality over
  sink-owned values `src/symbolic.c:33-38`; native form only
  `src/symbolic.c:62-75`; ABC `dag_value` rejects `HOME` `src/optimize.c:165-170`;
  `CALL`/`TCALL` must target a function entry `src/verify.c:131-134`.
- Code (round 1): `src/symbolic.c:45-75,180-538,553-578`;
  `src/residualize.c:408-463,776-801,822-826`;
  `src/residual_builder.c:851-978,979-1200,2047-2110`;
  `src/optimize.c:57-118,153-161,157,361-387,705-779,850-873`;
  `src/residual_analysis.c:24-85`; `REFACTOR.md:811`.

## Open questions

See `QUESTIONS.md` (Q1 ABC version policy gate; Q2 version-budget authority;
Q3 portable-C scope). Do not duplicate them here.

Q1 is the one remaining scope gate for this design. Round-2 measurements make
the recommendation explicit: **adopt versioned blocks for `abc-opt`**, because
the path tree's duplication is exponential in branches, has a whole-function
cliff at 4096 paths, and refuses to optimize any branch-plus-effect function.
The gate is the user's because output bytes and the analysis policy change; the
measured evidence, the representability argument and the validation plan are in
`experiments/2-abc-versioned-sink.md`. If the gate is refused, the driver is
shared by native and C only, the ABC sink keeps a declared sink-owned path
emitter with its path limit, and everything else in this document stands. Q2
must be answered before the version budget can have a single owner. Q3 decides
whether the binding set is two or three (the C sink's policy is already the
precedent for Q5/Q6 either way).
