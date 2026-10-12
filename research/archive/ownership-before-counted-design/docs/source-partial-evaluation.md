# Source partial evaluation: bidirectional design proposal

**Status: architectural direction agreed; concrete interfaces proposed, not
implemented or validated.** The agreed direction is virtual source values and
places, backward demand plus forward knowledge, late source materialization,
existing Ershov scheduling, and VM-only evaluation. This document specifies the
source partial evaluator only; unresolved API/representation choices remain explicit.
The bootstrap retirement and revision-6 validation work remain separate,
incomplete integration work; this proposal does not mark either complete.

## 1. Scope and authoritative contracts

Language rules come from [syntax.md](syntax.md), especially sections 2–4, 9–11
and the Let extensions. Static execution follows [spec.md](spec.md#source-partial-evaluation-and-managed-execution)
(the static-execution paragraphs); the work packages are F04–F07 and F11 in
[frontend-completion-plan.md](frontend-completion-plan.md).

The source evaluator specializes a Let/SLet program against source knowledge.
Its output is ordinary checked frontend IR and the required initialized data.
It does not implement ABC instructions, byte-range alias analysis, operand-stack
projection, stencil selection or physical register allocation.

Keep three components distinct:

| Component | Input and responsibility | Output |
|---|---|---|
| Source partial evaluator | Source definitions, typed values/places, knowledge, effects, ownership; decide source static demands and residual source representations | Existing checked frontend IR plus required data state |
| `abc-opt` | Optional build-time bytecode optimization using its existing contracts | Optimized ABC |
| Native residualizer | Symbolic execution of ABC with the existing cache as register allocation | Native code and explicit ABC continuations |

The latter two are unchanged by this proposal. Source static execution uses the
normal lowering and verified VM, not either optimizer as a source interpreter.
Runtime execution remains independent of build-time `abc-opt`.

## 2. Findings at the pre-implementation baseline

- `semantic.lua:staticSupply()` recognizes literal syntax and primitive conversion
  syntax, not knowledge propagated through bindings and computed results.
- Module value construction accepts literals; a top-level partial word initializer
  is rejected before it can use normal callable construction.
- Local static partial application constructs `Ir.View` and local adapter storage.
  This conflates a semantic specialization with a runtime callable representation.
- Lambda construction rejects all SLet captures, including valid value captures.
- `analysis.lua` supplies usage/mutation/placement information, not a complete
  effect, alias or provenance analysis. Its storage-root walk must not be used as
  proof that dereferenced storage aliases the local containing the pointer.
- `frontend/ir.asdl` already defines typed values, places, owned/view callable
  types, and Borrow paths, sources, contents, locations and outlives constraints.
  These declarations do not establish that full provenance analysis is wired in.
- `stage.lua` invokes a fresh runtime subprocess and transports scalar cells.
  `specialize.lua` builds scalar known-argument wrappers and rejects hidden inputs.
  Neither constitutes a general source binding-time or initialization model.

The subprocess staging mechanism has since been replaced by the approved
[in-process session foundation](staging-session-implementation.md). Source-demand
integration, transportable initialization snapshots and the virtual source model
remain pending; that foundation does not resolve the other findings above.

## 3. Semantic records (compiler metadata, not executable IR)

The concrete record, application and VM-request contracts are proposed in
[source-virtual-contract.md](source-virtual-contract.md). Its historical-example
correction is important: a pure call with constant arguments is not inherently a
runtime value. The current bootstrap-replacement rejection is implementation
evidence, not a permanent language rule for that program.

All identities are qualified by module, definition and specialization as needed;
function-local value/storage numbers are never globally unique keys.

### Virtual values

```text
VirtualValue {
    identity,
    type, source_interface,
    definition: existing_source_or_checked_definition,
    knowledge,
    retained_origins,
    source_provenance
}

Knowledge = Exact(typed_static_value)
          | Structure(shape, component_virtual_values)
          | Runtime
```

All values are virtual before materialization, including constants and values
whose contents remain runtime. Runtime knowledge is not a commitment to emit a
particular instruction or allocate storage. A value with a runtime component can
remain entirely unmaterialized when its consumers only need component values.
Definitions reference existing source/checked operations; they are not instructions
for a new evaluator. Effects remain tied to their ordered source definitions.

Unresolved analysis is a solver state, not a language value or another spelling
of Runtime. Exact scalars preserve their bit representation; object/code/type
identities use explicit compiler identities, never host addresses. Type values
remain compiler metadata, not ordinary runtime ABI cells.

Knowledge propagates through aliases and components. A computed static result
has the same standing as a literal. Structural projection/copying of metadata is
not execution of source arithmetic. Conversions and computations needing language
semantics execute via verified ABC when authorized.

### VM-only evaluation boundary

There is exactly one execution path for a demanded source computation:

```text
checked fragment -> normal ABC lowering -> verification -> abc_vm
                                                       -> typed values/state
```

The source solver may resolve bindings, preserve literals, project established
structured values, propagate identities and follow an already established boolean.
It must not evaluate source arithmetic, comparisons, conversions, calls, checked
accesses or actual mutable storage operations in Lua or a new host evaluator.
Computing a condition is VM work; selecting a path from its established answer is
compiler control. Abstractly tracking a store's dependencies is not performing
that store in a parallel compile-time heap.

A computed Exact answer comes from VM execution, or propagation of an already
established answer. The solver does not call a scalar folding helper directly as
an alternate source evaluation path. Existing VM/native/abc-opt shared folding
remains unchanged inside its own components. `abc-opt` is not required to execute
a static source fragment.

Tests must exercise the unoptimized staging path as well as the normal path, so
an optimizer cannot mask the absence of VM evaluation or incorrect source lowering.
No Lua fallback is permitted if staging or a required value representation fails.

### Callable information

```text
CallableInfo {
    code_identity_or_residual_callable,
    remaining_requirements, result_contract,
    supplied_requirements,
    lexical_captures_or_receiver,
    ownership_and_origins
}
```

Named words, lambdas and partial words use the same description. Each supplied
component has its own knowledge. Known code with a runtime capture is useful
partial knowledge, not an entirely unknown callable.

A lambda is not runtime-only. Capture-free and statically captured lambdas can
execute statically or specialize residual code. Capture preparation and type
annotations retain their specified source position; creating code does not invoke
its terminal. Named definitions do not acquire implicit lexical capture privileges.

Static specialization does not allocate an adapter. A runtime representation is
chosen only when use demands it: direct invocation, a callable view, an owned
value, a borrowed environment, or a language-defined managed object.

### Source places and state

```text
VirtualPlace {
    root_identity,
    typed_projection_path,
    ownership_and_origin,
    identity_observers,
    required_lifetime
}

SourceState(point, context) {
    place_contents: virtual_place -> VirtualValue,
    effect_dependencies,
    reachable_control
}
```

Paths are source fields, sum payloads and array elements, not byte offsets.
Reuse/extend the existing Borrow vocabulary where its meaning fits; do not infer
physical locations merely from a set of retained loans. Exact element knowledge
needs an explicit refinement of the existing may-element path before use.

Virtual places denote source storage identity without assigning a frame offset,
ABC stack position or native register. A virtual address need not materialize its
object until an observing consumer requires an actual address. Reads reference a
specific source state; later mutations cannot retroactively change their answers.

Known place identity, known current contents and immutable static value are
separate facts. Reads through unknown references/pointers stay residual; affected
facts are invalidated conservatively. Overlapping raw byte accesses and copies
remain under the existing ABC memory contracts, not a new source byte interpreter.

## 4. Demand and solver interfaces

```text
Demand = Value(source_or_checked_value, context)
       | Component(value, typed_path, context)
       | Contents(place, source_point, context)
       | Identity(place)
       | Address(place, source_point)
       | Lifetime(place_or_callable, boundary)
       | Effect(source_operation, context)
       | Control(source_region, context)
```

Proposed internal operations:

```text
demand(query) -> VirtualAnswer | Pending
advance(region, incoming_facts) -> outgoing_facts
apply(callable, ordered_arguments, execution_context) -> value_information
execute_static(checked_fragment, session) -> typed_values + accepted_state
materialize(demanded_source_representation) -> existing_checked_IR
```

Solver tables hold answers, dependencies, a worklist and facts indexed by source
point/context. They reference source/checked definitions rather than introducing
an alternate instruction language. Code generation does not follow recursive
query visitation order.

## 5. Algorithm

1. Register source identities and interfaces. Follow the language's checking
   rules independently of whether residual output will use a value. Source
   elaboration is demand-capable: a type/requirement may need static execution
   before the enclosing checked function can be completed.
2. Seed demands from exported behavior, results, observable writes, foreign
   effects, checks/aborts, required completion behavior and initialization.
   Discarded result values do not make divergence or effects removable.
3. Resolve a value demand by inspecting its definition and requesting the facts
   needed to construct its inputs, callable/environment or source place.
4. Propagate knowledge forward over the relevant source region. Keep order of
   argument evaluation, capture preparation, checks, effects and deferred actions.
5. For source reads, consult typed place contents at that point. A known field or
   a previously assigned residual value may answer the read without a residual
   object access. Required checks remain independent obligations.
6. Source stores update typed-place facts and invalidate may-alias contents. A
   residual observable write is retained even when its new value is known.
   No byte-level store-history search or low-level memory reconstruction occurs.
7. At an unknown branch, join facts valid on every reachable incoming edge.
   Preserve branches whose effects/control are needed even if their results agree.
   Known conditions select paths according to source checking/execution rules.
8. Handle loops/recursive demands through reserved identities, dependencies and
   a worklist, not unlimited recursive expansion. Use finite conservative fact
   domains; changing loop contents can become residual while identity stays known.
   This analysis convergence is not a semantic source-execution budget.
9. Grow representation obligations until stable. Demanding an address or an
   escaping identity can force backing storage and its required initialization.
   Preserve the original source/checked definitions throughout solving.
10. Materialize the demanded program as ordinary checked IR. Preserve execution
    order and lifetime. Verify it before normal ABC lowering. A final cleanup may
    be useful, but generating everything and pruning is not the organizing model.
    Neither discovery order nor recursive demand traversal chooses A/B placement.
    Preserve the existing classical Ershov scheduling in `src/optimize.c` and the
    current destination-parametric frontend lowering. There is no new scheduler,
    evaluation reordering policy or placement-reconstruction pass.

Dependencies must include the facts on which an answer was established. Changes
to reachability, aliasing or state requeue dependent questions. Do not cache
Contents solely by object identity or cache a call result solely by arguments.

## 6. Application and execution

Evaluate callee and arguments in order; check/adjust requirements; attach supply;
then determine saturation. This rule is shared by named words and lambdas.

- Incomplete SLet application requires static supplied values under section 3.
  References to known bindings and computed static values qualify, not just literals.
- Let runtime supply retains its open-word/mutable-field semantics. It is not
  silently redefined as immutable lambda capture.
- Saturated required-static invocation executes its checked ABC fragment through
  the VM and feeds values/state back into elaboration.
- Residual invocation uses known arguments/captures to specialize while retaining
  required runtime execution. Partial and saturated supply canonicalize to the
  same specialization when code, bindings and contracts agree.
- Optional early whole-call execution needs the existing termination, effect-free
  and no-abort justification. Unknown proof means residual execution, not a timeout
  or fuel-based guess. Required static diagnostics still follow language rules.

Specialization identity and evaluated-result identity are distinct. Reserve
recursive specializations before elaborating bodies. Canonical keys must retain
exact value bits, semantic object/code identity, type and relevant captures; do
not structurally equate separate mutable objects.

## 7. Storage is part of the residual source program

Given a private local record with fields `a = 4`, `b = x`, followed by `a = 7`,
demanding only `a + b` can produce `7 + x` with no residual record. Demanding its
address for an opaque observer can require the record, its initialization and the
write to `a`; it can also invalidate facts about subsequent reads.

These are source identity and use decisions. They do not decide A/B/C placement,
register assignment, byte addressing or native load/store emission.

Accepted module-initialization writes can become residual image contents.
Invocation-local initialization cannot be moved into shared module data merely
because its value is known. A known write to observable runtime storage remains
at its required runtime position. Object lifetime, allocation effects, checks,
safepoints and GC/root policy remain constraints on elimination.

Late source materialization answers whether an object exists in the residual
program, which semantic lifetime owns it, and what representation a boundary
requires. Existing ABC lowering assigns frame offsets and emits transports;
existing Ershov optimization schedules eligible residual expression trees;
native symbolic cache state remains register allocation. These are separate
responsibilities, not copies of one placement algorithm.

Use existing complete source layouts for retained objects initially. Partial
physical layouts, new owned-environment ABIs and escaping environment transport
require explicit designs, not automatic consequences of structural knowledge.

## 8. Staging session contract

A session owns module/import identities, initialization states, verified staging
artifacts/VM instances, static value handles and source diagnostics.

Bindings transition `uninitialized -> initializing -> initialized`. Declaration
order and forward demands follow section 11; value-demand cycles reject, while
forming recursive code identities does not execute their bodies.

Accepted initialization retains permitted state. Optional speculation is isolated
and cannot publish writes/identities into accepted state. Transport uses typed
layouts and explicit relocation identities; VM-local pointers are not constants.

The old subprocess bridge could not meet this contract. The approved session
foundation now provides owned in-process VM/module state, exact scalar transport,
cleanup and source error mapping. Persistent source initialization, snapshots and
aggregate/identity transport still require explicit API designs. This proposal
does not presume those remaining APIs already exist.

Interpreted/eager/lazy are execution policies, not source meanings. No source fuel,
instruction, recursion or specialization-count budget is introduced.

## 9. Ownership and representation boundary

The source solver must distinguish immutable value snapshots from actual borrowed
places and from environments that retain other views. Track their origins through
aliases, aggregates, calls, stores, joins and every return form.

Reuse existing local typed adapters where valid. A signature alone cannot justify
returning a pointer to a local adapter. Owned closure returns require a genuine
supported owned representation, not an exception to lifetime checking.

Profile-5 executable Let is currently unavailable. This profile-neutral design
must not be reported as restoring managed execution, GC or dynamic staging.

## 10. File ownership and replacement boundaries

- `frontend/let/semantic.lua`: consume semantic knowledge rather than AST-shape
  staticness; unify application and callable descriptions; preserve source demands.
- `frontend/let/analysis.lua` and checked-IR validation: supply source fact/effect/
  provenance contracts without repurposing usage counts as alias proofs.
- `frontend/ir.asdl`: authoritative schema if contracts require extensions;
  regenerate `frontend/let/schema/ir.lua`, never edit the embedded copy directly.
- `frontend/let/compiler.lua`: session and import/static-demand orchestration.
- `frontend/let/specialize.lua`: source specialization identities and residual
  construction replace wrapper-only orchestration, not the C bytecode optimizer.
- `frontend/let/stage.lua`: implement the approved session bridge after its API
  design; retain verified normal lowering, VM semantics and source diagnostics.
- `frontend/let/abc.lua`: lower settled checked representations. It does not
  rediscover source binding time. No selected-stack/call ABI changes are proposed.
- New source-solver module(s), if needed, own only these metadata/worklist concerns.
  Their exact split is to be agreed, rather than adding a parallel compiler facade.

Remove superseded active paths as each replacement lands. No compatibility
translator for the retired bootstrap or new bytecode format is proposed.

## 11. Validation and measurement

Required paired cases:

- Named word / lambda; capture-free / static capture / runtime capture.
- Literal / known alias / VM-computed argument; partial / saturated supply.
- VM-backed arithmetic, comparisons, conversions and calls with optimization
  disabled, preserving exact integer/float bits, trap origins and operation order.
  Computed results must have no source-host evaluation fallback.
- Known scalar result with a retained effect; unknown result with no backing object.
- Private record field forwarding / address-observed record / aliased mutation.
- Constant array element / unknown index with retained bounds checking.
- Initialization image / invocation-local object / shared mutable identity.
- Valid local view / caller-origin view / invalid escape through each return form.
- Branch joins, recursive specialization and loop-carried source state.
- Initialization order, forward demands, cycles, rejected static effects and abort
  provenance; all three staging policies agree on artifacts and diagnostics.

Inspect checked residual IR and data as well as results: absence of unneeded
objects, adapters and operations, presence/order of required writes and checks,
correct callable and borrow contracts. Full validation remains necessary; existing
backend suites remain unchanged and are not substitutes for source-model tests.

Measure source-solving time, static VM preparation/execution, cache reuse, number
of specializations and residual IR/data/code sizes on frozen source inputs. These
are measurements, not semantic limits. No performance claim is made here.

## 12. Decisions required before implementation

1. Confirm these source-only contracts and the unchanged SLet/Let supply rules.
2. Specify the concrete metadata API and source-effect/provenance domain; identify
   precisely which existing schema constructs are sufficient and which are not.
3. Specify session/value-transport APIs and the bootstrap of checked static fragments
   during demand-driven elaboration, without creating a second typechecker.
4. Decide public compiler API behavior: `typed`/`typedFile` currently promise checked
   IR without backend execution, but source-required static demands may need a VM.
   Do not silently change that promise or substitute residual values for static demands.
5. Approve the staged implementation slices and supported transport/representation
   boundaries. Unsupported paths must remain explicit, not become semantic exceptions.

The first implementation slice should demonstrate the contracts on known bindings,
static partials and local source objects. Full initialization/state transport and
owned escaping environments must not be claimed complete from those examples.
