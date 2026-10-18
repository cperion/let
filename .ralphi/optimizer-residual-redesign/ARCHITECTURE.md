# Architecture

Status: candidate (round 3). Derived from `CONTRACT.md`, checked against the
code, and corrected by the round-2 and round-3 ABC probes. Rationale and
citations: [experiments/1-rederive.md](experiments/1-rederive.md);
[experiments/2-abc-versioned-sink.md](experiments/2-abc-versioned-sink.md);
[experiments/3-loop-versions.md](experiments/3-loop-versions.md).

The one-line design: **execute ABC semantics once, symbolically, per version;
module facts and version identity have one owner; a sink owns only residue.**
A version key is **constants plus the binding's locations plus the core's
continuation chain** — never sink residue identity. That one rule is what lets
every sink keep residue per version, and it makes **loops ordinary versions**:
a loop header is a version, a backedge is an edge.

## Essential model

A residualizing compiler is five things:

1. **Module facts** — immutable, computed once per module: function ranges and
   signatures, block leaders, **loop headers** (a leader with an incoming edge
   whose source pc is at or after it), direct-call graph, recursive/nested-eligible
   components, unknown-call reachability, entry roots.
2. **Symbolic machine** — A/B/C stacks of `constant | home | sink value`, C frame
   coordinates, explicit continuations, transfer dispatch. This is the only
   semantics and, for native, the register allocation.
3. **Context key** — canonical identity of a specialization: the constants, the
   locations of everything else, and the continuation chain. **The binding
   defines what a location is** (native: register/homing; portable C: version
   argument; ABC: C-frame slot). Key equality is version identity; a canonical
   all-location key always exists as the binding's generic fallback, and the
   continuation chain is core-owned because it identifies virtual (inlined)
   entries.
4. **Version** — `(pc, key, owning residual function)` plus the sink's residue for
   the straight-line run from `pc` and its outgoing edges. The unit of code and
   the unit of work. Residue is per version; **a key never contains sink residue
   identity**, so no sink needs a cross-version value graph to compare keys.
   **A loop is not a version shape**: its header is a version, its backedge is an
   edge, and loop-carried values cross as the key's constants or locations.
5. **Binding (sink)** — the target mechanism: the location vocabulary, record/emit
   residue, materialize join values, place and publish code. Never semantics.

Invariants:

- each version body is symbolically executed exactly once; residue is never
  re-walked, so no SSA/IR round trip and no placement reconstruction can exist;
- **a key contains only constants, binding locations and the continuation
  chain**; sink value identity (`abc_symbolic_value.reg`) never reaches a key, so
  residue can be per version and a sink never needs a function-wide value graph
  for key equality;
- the core never inspects residue; `abc_symbolic_value.reg` is opaque to it;
- version creation order is a function of module bytes and facts (deterministic);
- **edge-key modes are the whole loop rule**: a plain forward edge keeps
  constants; an edge into a non-entry loop header uses the generic all-location
  key; an edge into a function-entry pc joins that entry's version (the single
  lattice-keyed version where the binding has one entry address); at the per-pc
  version budget a key is replaced by the same generic all-location key. There
  is no loop state, no loop prologue, no backedge lowering and no path-shaped
  control-flow representation;
- **a residual-function entry has exactly one version where the binding has one
  entry address** (ABC `CALL`/`TCALL` can only target a function entry,
  `verify.c:131-134`); its key is the monotone join of all incoming entry/call
  keys and its body is re-executed until the key stops widening. This is the
  entry lattice, not a second driver. A virtual (inlined) entry is a normal
  version distinguished by the continuation chain, and an inlined recursive loop
  is a self-edge on it;
- native consumes the symbolic cache directly: no stored native residual IR.

## Concepts

The reader must hold exactly these five, in this order: **facts → machine →
key → version → binding**. Everything currently spelled "path tree", "argument
fact fixpoint", "version table", "directive driver", "leader discovery", "loop
prologue" is an instance of one of them.

## Data representation

- `abc_symbolic_context` unchanged in shape: three stacks of
  `abc_symbolic_value {kind, stack, dst_stack, reg, home, dst_home, constant}`,
  `c_origin/c_bias`, continuation stack, limits, `generic`.
- **Key** = the context after the binding's canonicalization: **constants,
  locations, and the continuation chain**. Non-constant values are replaced by
  the binding's location descriptor before any lookup or comparison; the
  continuation list survives canonicalization (it is not a location). The
  binding also supplies the canonical all-location form used by the loop-header
  rule and the budget fallback; the core does not assume `HOME(stack,index)` for
  every slot (that is the native form only).
- **ABC canonical form**: A/B empty, every value either a constant or a **C-frame
  slot**. This is forced, not chosen: join targets must arrive with identical
  A/B/C shapes (`verify.c:284`), so the target layout is a function of the target
  pc; the body is emitted once for all predecessors and the ABC emitter can only
  address the C frame (`dag_value` accepts only `CONST`/`BACKEND`,
  `optimize.c:165-170`), so the join drains live A/B values into the target key's
  slots and the body reads them with `CGET`. Because the verifier fixes the join
  shape, the number and kinds of drained slots agree on every edge.
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
  set, a sink value inspected by the core, a loop-specific version shape, or a
  join that bypasses `binding.join` are unrepresentable by construction.

## Operations and algorithms

```text
version_at(pc, key, origin):
    key = canonicalize(key, mode(pc, origin))   # binding location hook
    if compatible version exists: return it
    if family_count(pc, key) == budget:
        return version_at(pc, generic(key), origin)
    v = create(pc, key); queue.push(v); return v

mode(pc, origin):                               # core rule, from module facts
    if pc is a function entry and one entry address: ENTRY   # lattice join
    if pc is a loop header and pc is not a function entry: GENERIC
    return PRESERVE                             # constants + locations
    # any edge with pc <= origin targets a loop header, so it takes GENERIC

run():
    for each entry root: entry[f] = version_at(f.entry, entry_key(f), f.entry)
    while queue not empty:
        v = queue.pop(); x = copy(v.key)
        loop:
            if pc != v.pc and leader[pc]:
                t = version_at(pc, x, v.pc); binding.join(v, t); binding.jump(t); break
            exit = symbolic_dispatch(pc, x, ALL)
            CONTROL|TERMINATED -> binding.finish(v); break
            BLOCK|BOUNDARY      -> pc = machine.pc; continue
            FAILURE             -> fail(v)
```

- **Join materialization** (`binding.join`) is where incoming symbolic values
  meet the target key: native homes/re-homes registers, C emits block arguments,
  ABC arranges the target's C-frame slots (push a drained A/B value or store it
  in place) and the target body reads them with `CGET`. It may change the
  operand-stack shape to the target key's canonical shape. It consumes symbolic
  values and emits target transport — it is not a second allocator.
- **Loops are ordinary versions**: a backedge calls `version_at` exactly like a
  forward edge, with the generic key; the header body is executed and emitted
  once per key, and the join stores the loop-carried values for the next
  iteration. Nothing distinguishes a loop from a branch except the generic-key
  mode for edges into a loop header. Virtualized recursion (an inlined recursive
  callee) is a self-edge on the inlined entry version, whose key carries the
  caller's continuation chain.
- **Entry keys**: where the binding has exactly one entry address per function
  (ABC: `CALL`/`TCALL` target the function entry, `verify.c:131-134`), a
  residual-function entry is one version keyed by the monotone join of all
  incoming keys — `unreached → constant → unknown` per argument — re-executed
  until the key stops widening (this is the entry-fact lattice, not a second
  driver). Native and portable C may give a called function several entry
  versions because the call names the target version directly, so their entry
  keys are plain keys. A virtual entry (inlined call) is part of the caller's
  residual function and uses the caller's continuation chain in the key; an
  inlined recursive loop is a self-edge on it.
- **Bounds**: the per-pc version budget (native approved policy: 8 total versions
  per original PC; see Q2) and the entry-fact lattice. ABC's
  `ABC_OPTIMIZER_PATH_LIMIT` is a path-tree bound and retires with the path tree
  if Q1 is approved; it is not a module code-size budget either way.
- **Complexity**: facts O(V+E); preparation O(V+E) versions; one walk per
  version body; per-body key comparison and scheduling. No pass re-walks emitted
  code and no pass is exponential in branches or loop iterations.

## Interfaces and naming

- Core: `symbolic.c` (+ generated handlers) owns machine, folding, captures,
  continuations, module facts (including loop headers), and the key *rule*:
  equality/family counting, budget fallback, the edge-mode selection
  (entry join / loop-header generic / plain), recursion widening, entry-widening
  order.
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
  effectful functions; **the ABC loop machinery** (`loop_candidate`/
  `loop_target`/`loop_initial`/`loop_header`/`loop_home`/`loop_count`/
  `loop_captured`/`loop_stable`/`loop_temps`/`loop_prologue`/`backedge`/
  `nested_backedge`/`backedge_target`, `N_LOOP_HOME`, `emit_tree`'s backedge
  arms and `emit_root_backedge_operands`), because loops are ordinary versions;
  `residual_analysis.c` as a separate owner; `symbolic.c` DFS reachability
  helpers; `residualize.c` and `residual_builder.c` private drivers, leader
  discovery, loop-header scan and key canonicalization (their policy becomes the
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
- **Keying ABC A/B stack positions as locations (no C-slot drain)** — rejected
  round 3. The verifier fixes the shape at every join (`verify.c:284`), so the
  input's A/B positions *are* available, but the body is emitted once for all
  predecessors and a value below the entry top can only be consumed after the
  values above it, so the emitter would need a new entry-stack value kind and
  give up scheduled placement of multi-use values; the drain costs one push per
  live A/B value per edge and buys a clean, addressable entry frame. Measured:
  `opt(source)` and `opt(C-slot-drained)` are byte-identical
  (`experiments/3-loop-versions.md` §1), so the drain loses nothing.
- **A loop-specific version shape or prologue** — rejected round 3: measured
  representability and execution of loops as ordinary versions
  (`experiments/3-loop-versions.md` §1–2), and the C sink already emits loops as
  versioned blocks. Keeping `loop_home`/`loop_prologue` would re-introduce
  path-shaped state that only exists because the path tree cannot represent a
  backedge.
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
- Round-3 measured loop/join probe (hand-built ABC through the existing
  assembler, verifier, four execution modes, incumbent optimizer and C sink):
  `experiments/3-loop-versions.md` §1–4 and `experiments/3-loop-join-probe.lua`.
  Key numbers: a function with a local backward branch is retained
  byte-identically (`sum-fold-source` 15 → 15, foldable `5+6` untouched; the same
  shape without the backedge optimizes 12 → 10); hand-built versioned loop/join
  emissions verify and execute in interpreted/threaded/compiled/lazy for
  n = 3,1,0; `opt(source)` and `opt(versioned)` are byte-identical (94 bytes) and
  idempotent; a join with mismatched C shapes is rejected; the C sink compiles
  loops as versioned blocks with edge arguments; native compiles the same loop.
  Verifier facts: backward targets legal (`verify.c:122-125`), identical A/B/C
  shapes at joins (`:284`). Rule evidence: C sink
  `residual_builder.c:1195-1207, 1090-1091, 1102-1118`, native
  `residualize.c:424-438`; continuation equality `symbolic.c:39-54`.

## Open questions

See `QUESTIONS.md` (Q1 ABC version policy gate; Q2 version-budget authority;
Q3 portable-C scope; Q9 shared loop-header key rule for native). Do not duplicate
them here.

Q1 is the one remaining scope gate for this design. Round-2 and round-3
measurements make the recommendation explicit: **adopt versioned blocks for
`abc-opt`**, because the path tree's duplication is exponential in branches, has
a whole-function cliff at 4096 paths, refuses any branch-plus-effect function,
and now also refuses any function containing a local loop (measured, with
foldable arithmetic left untouched). The gate is the user's because output bytes
and the analysis policy change; the measured evidence, the representability
argument and the validation plan are in `experiments/2-abc-versioned-sink.md` and
`experiments/3-loop-versions.md`. If the gate is refused, the driver is shared by
native and C only, the ABC sink keeps a declared sink-owned path emitter with its
path limit (and keeps the loop machinery, since a path tree cannot represent a
backedge), and everything else in this document stands. Q2 must be answered
before the version budget can have a single owner. Q9 decides whether native
adopts the generic loop-header key. Q3 decides whether the binding set is two or
three (the C sink's policy is already the precedent for Q5/Q6 either way).
