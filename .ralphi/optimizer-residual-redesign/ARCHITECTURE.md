# Architecture

Status: candidate (round 1, rederive). Derived from `CONTRACT.md`, then checked
against the code. Rationale, citations and projections:
[experiments/1-rederive.md](experiments/1-rederive.md).

The one-line design: **execute ABC semantics once, symbolically, per version;
module facts and version identity have one owner; a sink owns only residue.**

## Essential model

A residualizing compiler is five things:

1. **Module facts** — immutable, computed once per module: function ranges and
   signatures, block leaders, direct-call graph, recursive/nested-eligible
   components, unknown-call reachability, entry roots.
2. **Symbolic machine** — A/B/C stacks of `constant | home | sink value`, C frame
   coordinates, explicit continuations, transfer dispatch. This is the only
   semantics and, for native, the register allocation.
3. **Context key** — canonical identity of a specialization: which values are
   constants/known facts and where the rest live. Key equality is version
   identity; a canonical generic key is always the fallback.
4. **Version** — `(pc, key, owning residual function)` plus the sink's residue for
   the straight-line run from `pc` and its outgoing edges. The unit of code and
   the unit of work.
5. **Binding (sink)** — the target mechanism: record/emit residue, materialize
   join values, place and publish code. Never semantics.

Invariants:

- each version body is symbolically executed exactly once; residue is never
  re-walked, so no SSA/IR round trip and no placement reconstruction can exist;
- the core never inspects residue; `abc_symbolic_value.reg` is opaque to it;
- version creation order is a function of module bytes and facts (deterministic);
- at the per-call-site version budget a join key is replaced by the canonical
  generic key, so the worklist terminates without a module-wide budget;
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
- **Key** = context plus the key policy's canonicalization mode; generic keys
  contain only homes (`canonical_generic_context` generalized).
- **Version table** keyed by (owning residual function, pc, key); the owning
  function is identity for sinks whose code is placed in per-function ranges
  (ABC), and is implicit for native/C.
- **Residue is sink-owned and never shared**: native — none (emitter packets are
  consumed immediately); portable C — one `residual.asdl` block per version with
  block arguments as the join representation; ABC — one bytecode region per
  version, with the per-version expression DAG scheduled locally, plus
  provenance and residual calls.
- Invalid states: a version without an owner, an edge whose target key has a
  different stack shape, a sink value inspected by the core, or a join that
  bypasses `binding.join` are unrepresentable by construction.

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
  meet the target key: native spills/re-homes registers, C emits block
  arguments, ABC copies to the target's C homes. It consumes symbolic values and
  emits target transport — it is not a second allocator.
- **Entry keys**: functions whose body is shared by all callers (ABC source
  functions; native recursive entries) use the entry-fact lattice in the key;
  recursive edges widen the key monotonically. A virtual entry (inlined call)
  uses the caller's continuation chain in the key.
- **Bounds**: two numbers, each owned once — the per-call-site version budget
  (native approved policy: 8 total versions per original PC) and the ABC
  entry-fact/path policy. Neither is a module code-size budget.
- **Complexity**: facts O(V+E); preparation O(V+E) versions; one walk per
  version body. No pass re-walks emitted code.

## Interfaces and naming

- Core: `symbolic.c` (+ generated handlers) owns machine, folding, captures,
  continuations, module facts and context-key policy.
- Driver: one sink-agnostic unit, conceptually
  `abc_residual_binding { canonicalize, compatible, budget, open/join/finish,
  jump, publish }` + `abc_residual_run(binding, module)`. The name is the
  guarantee: a binding binds mechanisms, the driver owns traversal.
- Bindings: native/threaded emitter (two output bindings of one residualizer),
  portable-C residue builder → C writer, ABC emitter/writer.
- Retired paths (named now, deleted in the cutover):
  `optimize.c` call-graph copy + `ArgumentFact` fixpoint + path-tree walk;
  `residual_analysis.c` as a separate owner; `symbolic.c` DFS reachability
  helpers; `residualize.c` and `residual_builder.c` private drivers, leader
  discovery and key canonicalization.

## Rejected alternatives

- **Shared generic residue IR for all sinks** — violates the native constraint
  and the approved REFACTOR target (ABC/C may hold build-time residue; it must
  never stage native emission).
- **Keep three independent traversals** — one idea in three implementations;
  already drifted (leaders, version budget), compile-time cost not block-bounded.
- **Keep the ABC path tree as a "policy" inside the shared driver** — path
  layout is recursive (contiguous per-path emission, local displacements), so
  the traversal would not actually be shared.
- **ABC stored SSA/IR + normalization** — forbidden by the contract.
- **Delete the portable-C sink** — plausible simplification, but a scope decision;
  raised as a question, not decided.

## Evidence

- Ownership audit with file:line citations, duplicate-SCC diff, leader-discovery
  drift, version-budget divergence: `experiments/1-rederive.md` §3.
- Code: `src/symbolic.c:45-75,180-538,553-578`; `src/residualize.c:408-463,
  776-801,822-826`; `src/residual_builder.c:851-978,979-1200,2047-2110`;
  `src/optimize.c:57-118,361-387`; `src/residual_analysis.c:24-85`;
  `REFACTOR.md:811`.
- Measurements: none run this round. Projections and the measurement plan are in
  `experiments/1-rederive.md` §6.

## Open questions

See `QUESTIONS.md` (Q1 ABC version policy gate; Q2 version-budget authority;
Q3 portable-C scope). Do not duplicate them here.

Q1 scopes the one-traversal claim: if ABC keeps whole-path expansion, the driver
is shared by native and C only, and the ABC sink keeps a declared sink-owned path
emitter; the rest of this design is unchanged. Q2 must be answered before the
version budget can have a single owner. Q3 decides whether the binding set is two
or three.
