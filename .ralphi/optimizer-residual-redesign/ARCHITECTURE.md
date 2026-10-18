# Architecture

Status: candidate (round 7). Derived from `CONTRACT.md`, checked against the
code, and corrected by the round-2 … round-7 probes. Rationale and citations:
[experiments/1-rederive.md](experiments/1-rederive.md);
[experiments/2-abc-versioned-sink.md](experiments/2-abc-versioned-sink.md);
[experiments/3-loop-versions.md](experiments/3-loop-versions.md);
[experiments/4-entry-lattice.md](experiments/4-entry-lattice.md);
[experiments/5-loop-key.md](experiments/5-loop-key.md);
[experiments/6-may-write.md](experiments/6-may-write.md);
[experiments/7-budget.md](experiments/7-budget.md).

The one-line design: **execute ABC semantics once, symbolically, per version;
module facts and version identity have one owner; a sink owns only residue.**
A version key is **constants plus the binding's locations plus the core's
continuation chain** — never sink residue identity. A **family** is the key with the
constants removed: the stack shape plus the continuation chain. **A key is exact: a
version is created when the key differs, never widened by a fixpoint.**

There are exactly **two key rules and two bounds**:

1. **A residual function's entry version is the generic all-location key.** The
   entry key is the call ABI, not a canonicalization of an incoming edge key: a
   residual call (or the outside world) materializes argument values into
   binding-defined locations, so the callee's own residual function starts generic
   and has exactly one entry version. A virtual (inlined) entry is an ordinary
   version.
2. **Every edge into a loop header takes the loop-invariant key** (every component
   whose value can change on a cycle through the header becomes a location,
   everything else keeps its constant), including an inlined callee entry that is a
   cycle header. Both rules are static functions of the key and module facts, so
   nothing is ever rebuilt.
3. **The per-family version budget** replaces a key with its all-location form.
   It is per family because a value widening can never merge two continuation
   chains: `versions(pc) <= families(pc) * budget`.
4. **Inlining is bounded separately** by the number of distinct continuation
   families at the target pc (`K`); the fallback is a residual call, because only a
   call decision can remove a chain. `families(pc) <= K`.

That is what lets every sink keep residue per version, it makes **loops ordinary
versions**, and it makes **every version body execute exactly once, for the whole
module**.

## Essential model

A residualizing compiler is five things:

1. **Module facts** — immutable, computed once per module: function ranges and
   signatures, block leaders, direct-call graph, recursive/tail-only/nontail
   components (they also feed the inline rule), unknown-call reachability, entry
   roots, **loop headers** (a leader with an incoming edge whose source pc is at
   or after it) and, per loop header, its **backedge instructions** and **cycle
   body** (the pcs on a path from the header to a backedge source, excluding the
   backedge instructions), plus the per-pc A/B/C heights and `CSET` target slots
   it needs (Q12). The cycle body and the heights yield the loop's **may-write
   set**, which is what makes the loop-invariant key computable before the body
   is walked. The may-write set is a *heuristic*: exact keys keep any widening
   sound, so a conservative set costs code quality, never meaning.
2. **Symbolic machine** — A/B/C stacks of `constant | home | sink value`, C frame
   coordinates, explicit continuations, transfer dispatch. This is the only
   semantics and, for native, the register allocation.
3. **Context key** — canonical identity of a specialization: the constants, the
   locations of everything else, and the continuation chain. A **family** is the
   key with the constants removed (stack shape + continuation chain); it is the
   unit of the version budget, because key widening only removes constants. The
   continuation chain is never widened: it names the return site of an inlined
   call, so it is identity, not a location. **The binding
   defines what a location is** (native: register/homing; portable C: version
   argument; ABC: C-frame slot) and supplies its **may-write predicate** for the
   loop-invariant canonicalization. Key equality is version identity and is
   exact; the binding also supplies one canonical all-location form, used as a
   residual function's entry key and by the per-family budget. The continuation chain is
   core-owned because it identifies virtual (inlined) entries and return sites.
4. **Version** — `(pc, key, owning residual function)` plus the sink's residue for
   the straight-line run from `pc` and its outgoing edges. The unit of code and
   the unit of work. Residue is per version; **a key never contains sink residue
   identity**, so no sink needs a cross-version value graph to compare keys.
   **A loop is not a version shape**: its header is a version keyed by the
   loop-invariant key, its backedge is an edge, and loop-carried values cross as
   the key's constants or locations. A single-entry loop header has exactly one
   version per family (one for a function's own, non-inlined body).
5. **Binding (sink)** — the target mechanism: the location vocabulary, record/emit
   residue, materialize join values, place and publish code. Never semantics.

Invariants:

- each version body is symbolically executed exactly once, module-wide; residue is
  never re-walked and never rebuilt, so no SSA/IR round trip and no placement
  reconstruction can exist;
- **a key contains only constants, binding locations and the continuation
  chain**; sink value identity (`abc_symbolic_value.reg`) never reaches a key, so
  residue can be per version and a sink never needs a function-wide value graph
  for key equality;
- the core never inspects residue; `abc_symbolic_value.reg` is opaque to it;
- version creation order is a function of module bytes and facts (deterministic);
- **a key is exact.** A version is created whenever an edge key differs from
  every existing version's key at that `pc`; no version key is widened by a
  fixpoint. There are two key rules, one budget and one non-key bound:
  (i) **a residual function's entry version is the binding's generic
  all-location key.** This is the call ABI, not an edge canonicalization: a
  residual call (or the outside world) materializes argument values into
  binding-defined locations, so the callee's own residual function starts generic
  and has exactly one entry version — correct for every caller and every entry
  address (`verify.c:131-134`). A virtual (inlined) entry is an ordinary version;
  (ii) **every edge into a loop header** takes the **loop-invariant key**: the key
  with every component whose value can change on a cycle through the header
  replaced by a location, and every other component unchanged, because the header
  body is one version that runs every iteration (see below). This includes a
  virtual entry into an inlined callee whose entry pc is a cycle header — the
  documented counter's `loop` is function 2 and its header is that function's
  entry, so a pc-scoped entry rule would make the measured P shape unreachable;
  (iii) at the **per-family version budget** a key is replaced by its all-location
  form. This is total inside a family, because the stack shape and the
  continuation chain are family identity and are never widened; it cannot merge
  two families, so it bounds only `versions per family`;
  (iv) **inlining is bounded separately.** A non-tail direct call is inlined only
  while its target pc has fewer than `K` distinct continuation families (the
  driver counts families; the binding supplies call eligibility); otherwise the
  call is residualized at the callee's generic entry key. No key widening can
  remove a continuation chain, so this is the only bound on the number of families
  at a pc: `families(pc) <= K` and `versions(pc) <= K * budget`.
  **There is no entry join, no entry-fact lattice, no call facts, no widening
  fixpoint and no residue rebuild.** The measured specialization that the old
  lattice provided comes from inlining instead: an inlined call is a **virtual
  entry**, an ordinary version whose key carries the caller's constants and whose
  continuation chain identifies the return site;
- **calls and edges**: a direct call is either a virtual entry (inlined: the
  callee's pc becomes a version in the caller's residual function, under the
  caller's continuation chain) or a residual call into the callee's single
  generic-key entry version. Inlining is chosen by the binding's call rule over
  module facts and bounded by the driver's family count at the target pc (Q10);
  the fallback is a residual call, which drops the chain. A recursive cycle that
  contains a nontail call cannot be inlined: every inlined layer grows the
  continuation chain, which is part of key identity, so the family never converges
  (`symbolic.c:39-75`). Tail calls push no continuation, so a tail-only cycle
  inlines into a version cycle with one chain; a same-function self-tail loop
  keeps its invariant constants under the loop rule, while a cross-function tail
  cycle has no per-function cycle body and keeps exact keys (conservatively the
  all-location key; Q14);
- **edge-key modes are the whole loop rule**: a plain forward edge keeps
  constants; an edge into a loop header takes the loop-invariant key; at the
  per-family version budget the key becomes the all-location key. The
  loop-invariant key keeps the entry key's constant on a component iff the loop
  cannot change the value the header sees there. Its **body is the cycle body,
  not a pc interval** (measured: an interval includes live exit code and the
  frame-replacing backedge; `experiments/6-may-write.md` §2–3), and the
  **backedge instruction is the join, not a body write**: a self-tail `TCALL`
  replaces the local frame from its argument vector (`docs/spec.md` "Calls"), so
  its writes define the target key exactly like `binding.join`. The static
  predicate is binding-owned and one pass: **ABC** — C slot `k` is may-write iff
  the cycle body's minimum C height is `<= k` or the cycle body contains a `CSET`
  targeting `k` (ABC keys are C-only, and a call cannot touch the caller's slots
  below its base: a callee frame starts at the caller's call-time C height and a
  callee addresses only its own frame, `symbolic.c:467-484`, so no call clause is
  needed); **native** — the same C clause plus A/B depth `d` iff the cycle body's
  minimum A/B height is `<= d` (native loop backedges are plain jumps).
  A same-function self-tail backedge is position-preserving (measured: the callee
  `C_k` receives selected-stack depth `k`, all four modes); a computed or
  re-ordered argument vector is widened at the edge. The may-write set is a
  **heuristic, not a correctness condition**: over-widening loses constants,
  under-widening only makes the backedge create another version, bounded by the
  per-family budget and the inline bound, and exact keys keep every version body
  correct either way. **A
  loop header is a version like any other**: one version per distinct
  loop-invariant key per family (one for a function's own, non-inlined body), its backedge is an edge, and
  its body keeps every constant the loop does not overwrite (measured: the
  documented counter's one body with `BLTUI_A 50`/`ADDI_A 7`). There is no loop
  state, no loop prologue, no backedge lowering and no path-shaped
  control-flow representation;
- **a residual-function entry has exactly one version**, keyed by the generic
  all-location key because the call ABI materializes arguments into locations;
  the same is true of a module entry (export, relocation, C entry). The entry key
  is not a canonicalization of any incoming edge key. No join is computed, so no
  re-execution and no publish-then-modify exists;
- native consumes the symbolic cache directly: no stored native residual IR.

## Concepts

The reader must hold exactly these five, in this order: **facts → machine →
key → version → binding**. Everything currently spelled "path tree", "version
table", "directive driver", "leader discovery", "loop prologue" is an instance of
one of them; "argument fact fixpoint", "call facts" and the dynamic loop join
(`loop_captured`/`loop_stable`) are not — they are deleted mechanisms, because
every key is computed statically: entries at the all-location key (the call
ABI), loop headers at the loop-invariant key, everything else exact, and the
number of inlined call instances is bounded separately (the only non-key bound).

## Data representation

- `abc_symbolic_context` unchanged in shape: three stacks of
  `abc_symbolic_value {kind, stack, dst_stack, reg, home, dst_home, constant}`,
  `c_origin/c_bias`, continuation stack, limits, `generic`.
- **Key** = the context after the binding's canonicalization: **constants,
  locations, and the continuation chain**. Non-constant values are replaced by
  the binding's location descriptor before any lookup or comparison; the
  continuation list survives canonicalization (it is not a location). Keys are
  compared for exact equality. The binding supplies two further descriptors: its
  **canonical all-location form** (the entry key and the per-family budget) and its
  **loop-entry form** (the loop-invariant key: a component the loop's cycle body
  may write or the backedge transports non-identically becomes a location,
  everything else keeps its constant).
  The core does not assume `HOME(stack,index)` for every slot (that is the native
  form only).
- **ABC canonical form**: A/B empty, every value either a constant or a **C-frame
  slot**. This is forced, not chosen: join targets must arrive with identical
  A/B/C shapes (`verify.c:284`), so the set of live values at a target is a
  property of the input pc; the body is emitted once per version and the ABC
  emitter can only address the C frame (`dag_value` accepts only
  `CONST`/`BACKEND`, `optimize.c:165-170`), so the join drains live A/B values
  into the target key's slots and the body reads them with `CGET`. Because the
  verifier fixes the join shape, the number and kinds of live values agree on
  every edge. The **layout** (which of them are C slots) is per version: a
  version is its own emitted label, so two versions at the same pc may keep
  different components as constants, and each emits its own prologue.
- **Version table** keyed by (owning residual function, pc, key); the owning
  function is identity for sinks whose code is placed in per-function ranges
  (ABC, portable C: the driver runs per residual function), and is implicit for
  native (one code arena; a module-scope table). A residual function has exactly
  one entry version; a single-entry loop header has exactly one version per
  family (its loop-invariant key); every other version at a pc exists because
  some edge's exact key differed. A **family** is (stack shape, continuation
  chain): the unit of the version budget and of the inlining bound.
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
  set, a sink value inspected by the core, a loop-specific version shape, a join
  that bypasses `binding.join`, a residual-function entry version that is not the
  generic key, or a residue region that is rebuilt after publish are
  unrepresentable by construction.

## Operations and algorithms

```text
version_at(pc, key, owner):
    key = canonicalize(key)                     # binding location hook
    if pc is a loop header: key = loop_invariant(key)   # may-write heuristic
    if a version with this exact key exists: return it
    if family_count(pc, family(key)) >= budget - 1:
        key = all_locations(key)   # the family's "general slot"; total in the family
    v = create(pc, key); queue.push(v); return v

# family(key) = stack shape + continuation chain; constants are the only part a
# widening can remove, so a budget is per family, never per pc.
# binding predicate used by loop_invariant:
#   may_write(component, header) -- true iff the loop's cycle body can change the
#   value the header sees at that component.  Static, from module facts: the
#   cycle body, per-pc A/B/C heights, CSET targets and the backedge transport
#   identity.  A heuristic: exact keys keep it sound either way.

run():
    for each residual function f:
        v = create(f.entry, generic_key(f))     # the call ABI's key; no edge
        while f.queue not empty:
            v = f.queue.pop(); x = copy(v.key)
            loop:
                if pc is a direct-call target and the call rule accepts it:
                    if distinct_families(target) >= K:      # continuation-chain bound
                        binding.residual_call(v, target); binding.finish(v); break
                    t = version_at(target, callee_key, f)   # virtual entry
                    binding.join(v, t); binding.jump(t); break
                if pc != v.pc and leader[pc]:
                    t = version_at(pc, x, f); binding.join(v, t); binding.jump(t); break
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
  values and emits target transport — it is not a second allocator. No join ever
  changes an existing version's key.
- **Loops are ordinary versions**: a backedge calls `version_at` exactly like a
  forward edge. Every edge into a loop header is canonicalized to the
  loop-invariant key, so a single-entry loop header has one body per family (its own
  non-inlined body has exactly one); the join stores
  the loop-carried values for the next iteration, and the body keeps every
  constant whose storage the loop does not touch (`experiments/5-loop-key.md`).
  The invariant is a static join, not a fixpoint: no version is ever widened
  after creation, so nothing is rebuilt.
- **Call policy** (the binding supplies eligibility over module facts; the driver
  supplies the bound): a direct call is either inlined as a virtual entry (an
  ordinary version at the callee's pc under the caller's continuation chain —
  constants cross, invariant constants of same-function tail cycles survive) or
  residualized (the callee's single generic-key entry version; no constants
  cross). Nontail recursive cycles must be residualized because inlining grows
  the continuation chain without bound. Inlining is bounded by the number of
  distinct continuation families already at the target pc: below `K` the call
  inlines, at `K` it becomes a residual call (Q10). That is the only bound on
  families, and therefore on versions, at a pc. A **self-tail** call creates no
  new family (tail calls push no continuation, `symbolic.c:486-499`): it becomes a
  loop header whose backedge canonicalizes to the loop-invariant key, i.e. a
  one-version cycle (this derives the incumbent's self-recursive inline rule).
  The ABC sink must inline pure acyclic direct calls: `docs/abc-opt.md:82-91`
  fixes that canonical output.
- **Entry keys**: a residual-call entry, and every module entry, is a single
  version keyed by the generic all-location key, because the call or the outside
  world supplies the argument values in binding-defined locations and the body
  must be correct for all callers. This is the call ABI, not a canonicalization of
  an incoming key; no join, no per-argument lattice, no re-execution. A virtual
  entry (inlined call) is a normal version (exact or loop-invariant key); an
  inlined self-tail loop is a self-edge on it and keeps the invariant constants.
- **Bounds**: three independent limits, each with an explicit fallback. (1) The
  **per-family version budget** (the approved policy number; the all-location form
  is the family's "general slot"; Q2 decides number *and* scope) — fallback: the
  all-location key, total inside the family. (2) The **inlining bound `K`** on
  distinct continuation families per target pc — fallback: a residual call,
  because no key widening can remove a chain. (3) The binding's own
  vtable/state limits. Together: `families(pc) <= K`, `versions(pc) <= K *
  budget`, and total work is bounded by `sum_functions (1 + K) * code(f) *
  budget`. The ABC `ABC_OPTIMIZER_PATH_LIMIT` is a path-tree bound and retires
  with the path tree if Q1 is approved; it is not a module code-size budget
  either way.
- **Complexity**: facts O(V+E) plus one reverse walk per loop header bounded by
  its cycle body (a nested loop is walked once per enclosing header); one walk per
  version body; per-body key comparison and scheduling; the family count and the
  inlining bound are version-table queries, not passes; no fixpoint over
  functions, so no function is ever walked twice. No pass re-walks emitted
  code and no pass is exponential in branches or loop iterations.

## Interfaces and naming

- Core: `symbolic.c` (+ generated handlers) owns machine, folding, captures,
  continuations, module facts (loop headers, backedge instructions, cycle bodies,
  per-pc heights and `CSET` targets, loop may-write sets), and the key *rule*:
  exact equality, family counting (shape + continuation chain), the loop-invariant
  canonicalization, the per-family budget, and the two canonical descriptors
  (all-location and loop-entry).
- Driver: one sink-agnostic unit, conceptually
  `abc_residual_binding { canonicalize(key), all_locations(key),
  loop_entry(key, facts), may_write(component, loop), equal/family_count,
  open/join/finish, jump, publish, call_eligible(call), residual_call(call) }` +
  `abc_residual_run(binding, function)`. The binding supplies its location
  vocabulary (which also defines what "may write" means), its two canonical
  forms and whether a call may be inlined at all (recursion, effect and frame
  exclusions); the driver owns traversal, the key rule, the family count and the
  inlining bound (`K`), because both are properties of key identity, not of the
  target mechanism.
  The name is the guarantee: a binding binds mechanisms, the driver owns
  specialization.
- Bindings: native/threaded emitter (two output bindings of one residualizer),
  portable-C residue builder → C writer, ABC emitter/writer.
- Retired paths (named now, deleted in the cutover):
  the ABC **argument-fact machinery**: `ArgumentFact`, `argument_fact`,
  `record_call`/`ResidualCall.facts`, `activate_function_facts`,
  `join_call_facts` and the `dirty` fixpoint loop in `optimize.c:850-873`, because
  a residual-call entry is the generic key (the call ABI) and no key widens; the dead
  `abc_residual_analysis_activate_facts`/`_join_call_facts` lattice and the
  `abc_residual_options.argument_facts` hook in the portable-C builder (no caller
  today); `optimize.c`'s call-graph copy; and — conditional on Q1 — the
  whole path-tree machinery: `simulate_tree`/`DagTree`/`emit_tree`/
  `emit_phi_tree`/`mark_path_tree`/`branch_rematerializable`/
  `ABC_OPTIMIZER_PATH_LIMIT`, and the `noncall_effect` refusal of branchy
  effectful functions; **the ABC loop machinery** (`loop_candidate`/
  `loop_target`/`loop_initial`/`loop_header`/`loop_home`/`loop_count`/
  `loop_captured`/`loop_stable`/`loop_temps`/`loop_prologue`/`backedge`/
  `nested_backedge`/`backedge_target`, `N_LOOP_HOME`, `emit_tree`'s backedge
  arms and `emit_root_backedge_operands`), because loops are ordinary versions
  and the loop-invariant key replaces the dynamic loop capture;
  `residual_analysis.c` as a separate owner; `symbolic.c` DFS reachability
  helpers; `residualize.c` and `residual_builder.c` private drivers, leader
  discovery, loop-header scan and key canonicalization (their policy becomes the
  shared rule; each keeps only its location vocabulary); and the traversal-time
  continuation scan inside native's `inline_candidate` (`residualize.c:401-406`),
  which becomes the driver's family count with the same `K` fallback. `docs/abc-opt.md:25,100`
  documents the retired call-fact behavior and must be updated in the same
  cutover; that is part of Q1's gate, not a silent policy change.
- Kept, because it is required, not duplication: the single-entry-version rule for
  address-only calls (ABC `CALL` can only target a function entry); the per-sink
  location vocabulary; sink residue itself; the bounded inline rule.

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
- **Generic (all-location) key at a loop header** — the round-3 choice,
  rejected round 5. It is sound and one body, but it forgets every constant whose
  value is known before the loop and invariant inside it, including the documented
  counter's bound and step: measured 12 vs 10 instructions per iteration in the
  probe loop, and the shipped C sink emits `if(v_8 < v_5)` where the invariant
  version emits `BLTUI 120` (`experiments/5-loop-key.md` §1–2). ABC bytecode and
  native code have no downstream optimizer to recover it.
- **Exact keys at a loop header** — the round-4 rule, rejected round 5
  for ABC and native. A constant loop-carried component produces one version per
  iteration until the per-family budget, at which point the all-location key makes the
  *hot* body generic: the documented fixture's `BLTUI_A 50` / `ADDI_A 7` then
  disappear from the emitted loop and `frontend/tests/optimize.lua:502,505`
  fails. Measured emission: 7 folded header versions + a generic tail, 29
  instructions vs 16 for the loop-invariant key, and its executed-instruction
  advantage (152 vs 188 at trip count 18) vanishes above about 36 iterations
  (`experiments/5-loop-key.md` §2).
- **The pc-interval body plus a CALL/TCALL argument clause (round 5's concrete
  predicate)** — rejected round 6. An interval `[header .. largest backedge
  source]` contains live exit code (measured: a loop whose exit path pops the
  frame marks every slot may-write while the cycle writes one,
  `experiments/6-may-write.md` §3) and contains the self-tail `TCALL` whose frame
  replacement gathers arguments at C base 0, so the clause marks all four slots
  of the documented counter may-write and the loop-invariant key collapses to the
  all-location key (0 constants kept vs 2 under the cycle-body rule, §2) — i.e.
  the documented P shape round 5 used as its justification becomes unreachable.
  The call clause is also unnecessary: callee frames start at the caller's
  call-time C height and are frame-local. The interval's only surviving
  justification was that dead code over-widens, but the exit path is not dead.
- **Widen the continuation chain so that the per-pc budget can merge call
  instances** — rejected round 7. The chain names the return site of an inlined
  call; widening it would change where the body returns, and every
  canonicalization in the tree is value-only (`symbolic.c:45-53`;
  `residual_builder.c:851-868`). The budget is therefore per family (shape +
  chain), and families need a separate inline bound.
- **A literal "total versions per pc" budget enforced by key widening** —
  unenforceable: a total cap must be shared between constant families and chains,
  which changes what the all-location fallback guarantees. Raised as Q2's scope
  decision; the design's recommendation is the per-family budget plus `K`.
- **A pc-scoped residual-call-entry canonicalization** — rejected round 7. The
  documented counter's loop header *is* the inlined callee's function entry
  (`experiments/6-may-write-out/counter.dis`: function 2 starts at the header pc
  `0x29`), so a rule keyed on "the target pc is somebody's function entry" would
  take the all-location key there and make the measured P shape
  (`BLTUI_A 50`/`ADDI_A 7`) unreachable. The generic key belongs to the callee's
  own residual-function entry, which is the call ABI.
- **A static capped call-path multiplicity fact as the inlining bound** —
  recorded alternative (round 7): order-independent and no version-table scan,
  but a new module fact plus a saturating DP over the call DAG, over-counting
  paths that will be residualized for other reasons. The driver's local family
  count at the target pc gives the same invariant (`families(pc) <= K`) with one
  counter; revisit only if the order-dependence matters.
- **A per-residual-function version budget as the only inlining bound** — the
  round-6 sketch: it does bound total work, but it stops unrelated calls once the
  function is large and is not the quantity the incumbent measures
  (`inline_candidate` counts continuations at the target pc). Kept as the
  coarser fallback if the per-pc count proves awkward.
- **Unroll a constant-trip loop up to the per-family budget (exact prefix + 
  loop-invariant tail)** — the best measured code for small constant loops
  (152 vs 188 executed instructions at trip 18) but it deliberately emits up to
  `budget` loop-header bodies, which contradicts the compile-time and code-size
  goals and the "one version per loop header family" invariant. Recorded as a possible
  later *binding-side unrolling choice* with its own bound, not as the key rule.
- **A single lattice-keyed entry (monotone join + function-granular rebuild)** —
  rejected round 4. It is the only mechanism that can carry constants across a
  residual call into a function with one entry address (measured: `mutual`
  folds `100-7` and `200-7`, widens `i`; `experiments/4-entry-lattice.md` §2.2–3),
  and it costs a second worklist level over residual functions, per-argument
  call facts, and whole-function discard/rebuild when the join widens (the
  incumbent: `optimize.c:850-873`; measured that a first-key-only design would
  have folded `i == 0` and been wrong). Its cited witness (the documented
  recursive counter) is invalid: the counter is fully inlined (53→18
  instructions, one function, no `CALL_A`), and a two-root module produces two
  independent specializations rather than a join. A generic entry key deletes the
  whole mechanism and keeps every version body single-execution; the lost
  cross-call constants are recoverable at virtual entries (inlined calls), which
  the ABC sink must have anyway for `docs/abc-opt.md:82-91`. It remains the
  fallback if the user requires the documented `docs/abc-opt.md:100` behavior for
  non-inlinable recursive calls. Round 5 separates the *loop-granular* part: the
  join a loop header needs is computed statically from the loop's may-write set,
  so no dynamic join or rebuild is needed anywhere, including loops.
- **Inline every direct call, unbounded** — the canonical `sq(a)+sq(b)` fixture
  requires inlining pure acyclic calls, and safe tail-only recursive cycles can
  be inlined, but nontail recursive layers grow the continuation chain that is
  part of key identity (`symbolic.c:39-75`), so those calls must stay residual;
  and because each nontail call site is a distinct key family at the callee's pc,
  inlining across a call chain multiplies. A per-residual-function version budget
  with a residual-call fallback is required (Q10).
- **Clone a residual function per entry key** — gives residual calls constants
  without a join, but adds a function-cloning concept, duplicate exports and
  relocation/identity questions for code addresses, callables and provenance for
  a bounded gain.
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
- Round-4 measured entry/call boundary probe (new mutual-recursion fixtures and
  the documented counter through the existing assembler, four execution modes,
  incumbent optimizer and portable-C sink): `experiments/4-entry-lattice.md`
  §1–2.5 and `experiments/4-entry-lattice.lua`. Key numbers: the counter is fully
  inlined (53 → 18 instructions, **one** function, no `CALL_A`); two roots with
  limits 50/40 produce two independent specializations (2 functions,
  `BLTUI_A 50` and `BLTUI_A 40`), not a join; mutual recursion keeps residual
  calls and folds `step = 7` into both callees (`93`, `193`, `PUSH 8·7` at the
  call sites) while widening `i`; two roots with steps 7/9 widen `step` and the
  folds disappear (per-argument join); 40 roots cost 0.06–0.07 ms either way;
  `opt⁴ == opt` (166 bytes); the portable-C output for the same module folds
  nothing (generic entries). Mechanism citations: inline rule `optimize.c:299-318`,
  SCC eligibility `:108-114`; call facts + dirty rebuild loop `:850-873`; module
  write-time call encoding `:826-833`; C sink generic entries
  `residual_c.c:1239`, `residual_builder.c:2177-2210, 898-933`; dead lattice
  `residual_analysis.c:215-266`; continuation in key identity `symbolic.c:39-75`.
- Round-7 measured budget/chain probe: `experiments/7-budget.md` §1–§6 and
  `experiments/7-call-paths.py` (artifacts in `7-call-paths-out/`, not committed).
  Key facts: key equality compares the continuation chain (`src/symbolic.c:45-53`)
  and family equality adds the stack shape (`:56-66`), while every
  canonicalization is value-only (`src/residual_builder.c:851-868, 936-963`), so
  the all-location fallback is total inside a family and cannot merge call
  instances; the only code that removes a chain is a call decision
  (`src/residualize.c:395-406`). Measured on a branch-free doubling call ladder:
  the ABC sink's output doubles with the number of syntactic non-tail call
  instances (2^depth) — 22, 46, 94, 190, 382, 766 instructions for 8…256
  instances, ~1.75–3 instructions per instance — until ABC's 255-cell C-frame
  limit stops the outer inlining at depth 9 (`src/optimize.c:753, 762`); the
  versioned sink emits one body per inlined instance because the chain differs,
  so this is the multiplicity its inline bound must cut. `REFACTOR.md:811`
  records the incumbent's 10-versions-at-one-entry-PC divergence. Rule citations:
  `src/symbolic.c:471-477, 486-499` (call continuation; tail pushes none), `src/verify.c:284`
  (shape fixed per pc), `src/residual_builder.c:965-1004, 1108-1117`.
- Round-6 measured may-write probe (the documented counter and an exit-path-pop
  loop through the existing assembler, disassembler and the verifier's join rule
  as the height oracle): `experiments/6-may-write.md` §1–7 and
  `experiments/6-may-write.lua`, artifacts in `experiments/6-may-write-out/`.
  Key numbers: the documented counter's `loop` (header pc 41, C height 4,
  self-tail `TCALL` backedge at pc 72, body `CSET`s slots 2 and 3) is marked
  may-write `{0,1,2,3}` by round 5's interval + CALL/TCALL rule (0 constants kept)
  and `{2,3}` by the cycle-body rule (2 constants kept — the incumbent's
  two-unknown-slot body); the exit-path fixture goes `{0,1,2}` → `{0}` (min C
  height 0 → 3); argument 0 is the first pushed value (`f(1,2,3)` returns
  `1 2 3`), so a self-tail transport is position-preserving. Rule citations:
  `src/symbolic.c:467-484` (a call's frame starts at the caller's C height and
  does not change `n[C]` when residualized), `docs/spec.md` "Calls" (`TCALL`
  replaces the complete frame), `src/verify.c` C cases (a callee addresses only
  its own C frame), `gen/banked.lua:234` (gather).
- Round-5 measured loop-key probe (hand-built ABC through the existing assembler,
  verifier, four execution modes, incumbent optimizer and portable-C sink):
  `experiments/5-loop-key.md` §1–3 and `experiments/5-loop-key.lua`. Key numbers:
  the documented counter's optimized loop is one body at pc 6 with `BLTUI_A 50`
  and `ADDI_A 7` and both loop slots unknown — the incumbent's loop header is a
  join that keeps unwritten constants; the loop-invariant-key emission of the same
  loop returns 1071 in all four modes at 16 instructions with 10
  instructions/iteration; the generic-key emission costs 22 and 12/iteration; the
  exact-key emission with budget 8 is 29 instructions (7 folded header versions +
  4 constant stores + a generic tail) with 12/iteration in the hot tail.
  `frontend/tests/optimize.lua:502,505` pins the immediates, so exact keys at a
  loop header would fail it. The portable-C sink's loop entry compares
  block-argument copies (`if(v_8 < v_5)`) although the bound is materialized
  before the loop. Rule citations: `residual_builder.c:1090-1091, 1195-1207`
  (loop entry forgets constants), `residualize.c:414-438` (native weakens all
  constants on a backward edge), `verify.c:284` (join shapes),
  `docs/symmetric-isa.md:183-187` for the i8 immediate forms.

## Open questions

See `QUESTIONS.md` (Q1 ABC version policy gate; Q2 version-budget authority —
now number **and scope**, because a key widening cannot merge continuation
chains; Q3 portable-C scope; Q9 native loop-header policy; Q10 ABC inline policy
and its bound — round 7 recommends the driver's continuation-family count with a
residual-call fallback; Q12 layout/cycle-body fact ownership; Q14 cross-function
tail cycles). Q11 is answered (the loop-invariant key), Q13 answers what its body
is (the cycle body, backedge as join), and Q15 is answered round 7 (the budget is
per family; families are bounded by the inline rule). Do not duplicate them
here.

Q1 is the one remaining scope gate for this design. Round-2, round-3 and round-4
measurements make the recommendation explicit: **adopt versioned blocks for
`abc-opt`**, because the path tree's duplication is exponential in branches, has
a whole-function cliff at 4096 paths, refuses any branch-plus-effect function,
refuses any function containing a local loop (measured, with foldable arithmetic
left untouched), and its argument-fact lattice exists only to patch the calls the
path tree cannot inline (round 4). The gate is the user's because output bytes
and the analysis policy change; the measured evidence, the representability
argument and the validation plan are in `experiments/2-abc-versioned-sink.md`,
`experiments/3-loop-versions.md`, `experiments/4-entry-lattice.md` and
`experiments/5-loop-key.md`. If the
gate is refused, the driver is shared by native and C only, the ABC sink keeps a
declared sink-owned path emitter with its path limit (and keeps the loop
machinery, since a path tree cannot represent a backedge), and everything else in
this document stands. Q2 must be answered before the version budget can have a
single owner: the approved number alone does not determine behavior, because
"total versions per original PC" and "versions per family per PC" are different
quantities (`experiments/7-budget.md` §4.2–§4.4). Q9 decides whether native adopts the loop-invariant header key
(round 5's recommendation: yes — one header version instead of two, invariant
C-frame constants kept, the one-iteration peel dropped); the rule is otherwise
fixed by Q11. Q10 decides the ABC inline rule and its continuation-family bound
(`K`), now with self-tail recursion bounded by the loop rule rather than the
bound because tail calls push no continuation. Q12
decides where per-pc heights, `CSET` targets and cycle-body/may-write sets are
computed (round 6 pins the required data: heights, `CSET` targets, successors and
backedges; the verifier's discarded `Shape` records the same heights but must not
become an optimizer dependency). Q14 decides whether a cross-function tail cycle
keeps invariants (round 5's claim is unsupported; the conservative answer is the
all-location key). Q3 decides
whether the binding set is two or three (the C sink's policy is already the
precedent for Q5/Q6 either way).
