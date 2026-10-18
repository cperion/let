# Architecture

Status: candidate (round 4). Derived from `CONTRACT.md`, checked against the
code, and corrected by the round-2, round-3 and round-4 probes. Rationale and
citations: [experiments/1-rederive.md](experiments/1-rederive.md);
[experiments/2-abc-versioned-sink.md](experiments/2-abc-versioned-sink.md);
[experiments/3-loop-versions.md](experiments/3-loop-versions.md);
[experiments/4-entry-lattice.md](experiments/4-entry-lattice.md).

The one-line design: **execute ABC semantics once, symbolically, per version;
module facts and version identity have one owner; a sink owns only residue.**
A version key is **constants plus the binding's locations plus the core's
continuation chain** — never sink residue identity. **A key is exact: a version
is created when the key differs, never widened.** The key is generalized to the
binding's canonical all-location form only where identity forces it (a call that
can only name a function entry) or at the per-pc budget. That one rule is what
lets every sink keep residue per version, it makes **loops ordinary versions**,
and it makes **every version body execute exactly once, for the whole module**.

## Essential model

A residualizing compiler is five things:

1. **Module facts** — immutable, computed once per module: function ranges and
   signatures, block leaders, direct-call graph, recursive/tail-only/nontail
   components (they also feed the inline rule), unknown-call reachability, entry
   roots, and **loop headers** (a leader with an incoming edge whose source pc is
   at or after it) while Q11 keeps a loop-header key form.
2. **Symbolic machine** — A/B/C stacks of `constant | home | sink value`, C frame
   coordinates, explicit continuations, transfer dispatch. This is the only
   semantics and, for native, the register allocation.
3. **Context key** — canonical identity of a specialization: the constants, the
   locations of everything else, and the continuation chain. **The binding
   defines what a location is** (native: register/homing; portable C: version
   argument; ABC: C-frame slot). Key equality is version identity and is exact;
   the binding also supplies one canonical all-location form, used only by the
   forced-generic triggers (residual-call entry, per-pc budget, and the
   loop-header rule pending Q11). The continuation chain is core-owned
   because it identifies virtual (inlined) entries and return sites.
4. **Version** — `(pc, key, owning residual function)` plus the sink's residue for
   the straight-line run from `pc` and its outgoing edges. The unit of code and
   the unit of work. Residue is per version; **a key never contains sink residue
   identity**, so no sink needs a cross-version value graph to compare keys.
   **A loop is not a version shape**: its header is a version, its backedge is an
   edge, and loop-carried values cross as the key's constants or locations.
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
- **a key is exact.** A version is created whenever an edge's key differs from
  every existing version's key at that `pc`; no version key is ever widened.
  There are exactly two forced-generic cases: (i) an edge into a **residual-call
  entry** — a function entry that a call can address only as an address, not as a
  version — takes the binding's canonical all-location key, because the binding
  has one entry address and the callee must be correct for every caller (ABC
  `CALL`/`TCALL`, `verify.c:131-134`); (ii) at the per-pc version budget a key is
  replaced by the same canonical all-location key. **There is no entry join, no
  entry-fact lattice, no call facts, no widening fixpoint and no residue
  rebuild.** The measured specialization that the old lattice provided comes from
  inlining instead: an inlined call is a **virtual entry**, an ordinary version
  whose key carries the caller's constants and whose continuation chain
  identifies the return site;
- **calls and edges**: a direct call is either a virtual entry (inlined: the
  callee's pc becomes a version in the caller's residual function, under the
  caller's continuation chain) or a residual call into the callee's single
  generic-key entry version. Inlining is chosen by the binding's call rule over
  module facts, and it is bounded (Q10). A recursive cycle that contains a
  nontail call cannot be inlined: every inlined layer grows the continuation
  chain, which is part of key identity, so the family never converges
  (`symbolic.c:39-75`). Tail-only cycles (self-tail loops, mutual tail recursion)
  inline into a version cycle and keep their invariant constants;
- **edge-key modes are the whole loop rule**: a plain forward edge keeps
  constants; at the per-pc version budget the key becomes the generic key. An
  edge into a non-entry loop header takes the generic key under the round-3 rule,
  which is reopened in Q11 (it also loses constants that are known before the
  loop and legitimately invariant inside it). There is no loop state, no loop
  prologue, no backedge lowering and no path-shaped control-flow representation;
- **a residual-function entry has exactly one version**, keyed by the generic
  all-location key where the binding has one entry address; the same is true of a
  module entry (export, relocation, C entry). No join is computed, so no
  re-execution and no publish-then-modify exists;
- native consumes the symbolic cache directly: no stored native residual IR.

## Concepts

The reader must hold exactly these five, in this order: **facts → machine →
key → version → binding**. Everything currently spelled "path tree", "version
table", "directive driver", "leader discovery", "loop prologue" is an instance of
one of them; "argument fact fixpoint" and "call facts" are not — they are deleted
mechanisms (Q7), because a key never widens.

## Data representation

- `abc_symbolic_context` unchanged in shape: three stacks of
  `abc_symbolic_value {kind, stack, dst_stack, reg, home, dst_home, constant}`,
  `c_origin/c_bias`, continuation stack, limits, `generic`.
- **Key** = the context after the binding's canonicalization: **constants,
  locations, and the continuation chain**. Non-constant values are replaced by
  the binding's location descriptor before any lookup or comparison; the
  continuation list survives canonicalization (it is not a location). Keys are
  compared for exact equality; **the binding's canonical all-location form is a
  second, separate descriptor** used only by the two forced-generic triggers
  (residual-call entry, per-pc budget) and by the loop-header rule pending Q11.
  The core does not assume `HOME(stack,index)` for every slot (that is the native
  form only).
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
  native (one code arena; a module-scope table). A residual function has exactly
  one entry version; every other version at a pc exists because some edge's exact
  key differed.
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
  that bypasses `binding.join`, or a residue region that is rebuilt after publish
  are unrepresentable by construction.

## Operations and algorithms

```text
version_at(pc, key, origin):
    key = canonicalize(key)                     # binding location hook
    if version with this exact key exists: return it
    if family_count(pc, key) == budget:
        return version_at(pc, generic(key), origin)   # forced generic
    v = create(pc, key); queue.push(v); return v

mode(pc, origin):                               # core rule, from module facts
    if pc is a residual-call entry / module entry: GENERIC  # one version, no join
    if pc is a non-entry loop header: GENERIC (round-3 rule; reopened by Q11)
    return PRESERVE                             # constants + locations

run():
    for each residual function f:
        v = version_at(f.entry, generic_key(f), f.entry)   # single entry version
        while f.queue not empty:
            v = f.queue.pop(); x = copy(v.key)
            loop:
                if pc != v.pc and leader[pc]:
                    t = version_at(pc, x, v.pc); binding.join(v, t); binding.jump(t); break
                if pc is a direct-call target and the call rule inlines it:
                    t = version_at(pc, x, v.pc)        # virtual entry, normal key
                    binding.join(v, t); binding.jump(t); break
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
  forward edge; the header body is executed and emitted once per key, and the
  join stores the loop-carried values for the next iteration. Which key form a
  non-entry loop header takes (exact, per-slot join, or generic) is Q11; the
  round-3 choice is generic.
- **Call policy** (owned by the binding over module facts, bounded): a direct
  call is either inlined as a virtual entry (an ordinary version at the callee's
  pc under the caller's continuation chain — constants cross, invariant constants
  of tail-recursive cycles survive) or residualized (the callee's single
  generic-key entry version; no constants cross). Nontail recursive cycles must
  be residualized because inlining grows the continuation chain without bound.
  Inlining is bounded by a per-residual-function version budget (Q10); beyond it
  the call is residualized. The ABC sink must inline pure acyclic direct calls:
  `docs/abc-opt.md:82-91` fixes that canonical output.
- **Entry keys**: a residual-call entry, and every module entry, is a single
  version keyed by the generic all-location key, because the call or the outside
  world supplies the argument values and the body must be correct for all
  callers. No join, no per-argument lattice, no re-execution. A virtual entry
  (inlined call) is a normal version; an inlined recursive loop is a self-edge on
  it, and its key keeps the invariant constants.
- **Bounds**: the per-pc version budget (native approved policy: 8 total versions
  per original PC; see Q2), the per-residual-function inline/version budget
  (Q10), and the vtable/state limits of the bindings. The ABC
  `ABC_OPTIMIZER_PATH_LIMIT` is a path-tree bound and retires with the path tree
  if Q1 is approved; it is not a module code-size budget either way.
- **Complexity**: facts O(V+E); one walk per version body; per-body key
  comparison and scheduling; no fixpoint over functions, so no function is ever
  walked twice. No pass re-walks emitted
  code and no pass is exponential in branches or loop iterations.

## Interfaces and naming

- Core: `symbolic.c` (+ generated handlers) owns machine, folding, captures,
  continuations, module facts (including loop headers pending Q11), and the key
  *rule*: exact equality, family counting, budget fallback, the forced-generic
  triggers (residual-call entry, budget), and the loop-header key form.
- Driver: one sink-agnostic unit, conceptually
  `abc_residual_binding { canonicalize(key), canonical_generic(key),
  equal/family_count, open/join/finish, jump, publish, inline(call) }` +
  `abc_residual_run(binding, function)`. The binding supplies its location
  vocabulary, its canonical generic form and its bounded inline rule; the driver
  owns traversal and the key rule. The name is the guarantee: a binding binds
  mechanisms, the driver owns specialization.
- Bindings: native/threaded emitter (two output bindings of one residualizer),
  portable-C residue builder → C writer, ABC emitter/writer.
- Retired paths (named now, deleted in the cutover):
  the ABC **argument-fact machinery**: `ArgumentFact`, `argument_fact`,
  `record_call`/`ResidualCall.facts`, `activate_function_facts`,
  `join_call_facts` and the `dirty` fixpoint loop in `optimize.c:850-873`, because
  a residual-call entry is the generic key and no key widens; the dead
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
  arms and `emit_root_backedge_operands`), because loops are ordinary versions;
  `residual_analysis.c` as a separate owner; `symbolic.c` DFS reachability
  helpers; `residualize.c` and `residual_builder.c` private drivers, leader
  discovery, loop-header scan and key canonicalization (their policy becomes the
  shared rule; each keeps only its location vocabulary). `docs/abc-opt.md:25,100`
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
  non-inlinable recursive calls.
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

## Open questions

See `QUESTIONS.md` (Q1 ABC version policy gate; Q2 version-budget authority;
Q3 portable-C scope; Q9 native loop-header policy; Q10 ABC inline policy and its
bound; Q11 loop-header key form). Do not duplicate them here.

Q1 is the one remaining scope gate for this design. Round-2, round-3 and round-4
measurements make the recommendation explicit: **adopt versioned blocks for
`abc-opt`**, because the path tree's duplication is exponential in branches, has
a whole-function cliff at 4096 paths, refuses any branch-plus-effect function,
refuses any function containing a local loop (measured, with foldable arithmetic
left untouched), and its argument-fact lattice exists only to patch the calls the
path tree cannot inline (round 4). The gate is the user's because output bytes
and the analysis policy change; the measured evidence, the representability
argument and the validation plan are in `experiments/2-abc-versioned-sink.md`,
`experiments/3-loop-versions.md` and `experiments/4-entry-lattice.md`. If the
gate is refused, the driver is shared by native and C only, the ABC sink keeps a
declared sink-owned path emitter with its path limit (and keeps the loop
machinery, since a path tree cannot represent a backedge), and everything else in
this document stands. Q2 must be answered before the version budget can have a
single owner. Q9 decides whether native adopts the round-3 generic loop-header
key; round 4 found that key form loses constants that are invariant *inside* the
loop, so Q11 decides the form for all bindings. Q10 decides the ABC inline rule
and its per-function budget. Q3 decides whether the binding set is two or three
(the C sink's policy is already the precedent for Q5/Q6 either way).
