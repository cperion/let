# Virtual source values and application contract

**Status: concrete design proposal, not implemented.** This refines
[source-partial-evaluation.md](source-partial-evaluation.md). The source layer
owns these contracts; neither `abc-opt` nor native residualization implements them.
No new scalar evaluator, instruction IR, scheduler or physical allocator is proposed.

## 1. Identity and records

A source-specialization context owns immutable virtual-value definitions and
versioned analysis facts. Keys include the context: existing `Ir.Value(1)` or
`Ir.Storage(1)` from different functions must never collide.

```text
ContextId = compilation-local stable definition/specialization identity
ValueId   = (ContextId, value ordinal)
PlaceId   = (ContextId, storage ordinal, typed source path)
PointId   = (ContextId, ordered source occurrence)
StateId   = identity of an incoming/joined source-analysis state

VirtualValue {
    id: ValueId,
    type: existing semantic type,
    interface: existing source interface, if any,
    definition: existing source or checked-IR definition,
    origins: retained-access provenance,
    span: source provenance
}

ValueFacts(value, state) = Exact(StaticValueHandle)
                        | Components(shape, VirtualValue[])
                        | Runtime

QueryStatus = Unseen | Waiting(dependencies) | Ready(answer)
```

`Runtime` is a conservative answer about contents, not a request to allocate a
slot or immediately emit a call. `Waiting` is not a language value. Do not install
an assumed exact value to break a recursive query cycle.

Immutable definitions can be shared. Facts about mutable place contents are
state-indexed. A scalar snapshot already read at one point is not changed when
another alias later writes its source place.

`StaticValueHandle` references one of:

- an already checked literal/static definition;
- an exact typed result published by the VM staging session;
- a component/alias of an established static value.

Type identity and exact bits are retained. Static object/code identity is a
compiler/session identity, never a serialized process address. Arbitrary host
numbers cannot be re-tagged as checked narrow values to bypass conversions.

## 2. Operations permitted on metadata

The source layer may perform compiler operations:

```text
literal(checked_literal) -> VirtualValue
parameter(checked_parameter) -> VirtualValue
alias(value) -> same semantic value information
project_established_structure(value, field) -> component VirtualValue
reference_definition(checked_expression) -> VirtualValue
query_facts(value, state) -> ValueFacts or Waiting
```

It may not compute the result of a source operation with a Lua operator or a
new host folding helper. In particular, adding constants, comparing them, casting
them, invoking a function or executing a checked memory access goes through the
VM when a computed static answer is required.

Projecting established compiler structure does not authorize deleting a source
check. A checked access carries its check/effect demand independently of its value.
Source-state updates record symbolic dependencies; they are not a second mutable
heap on which source initializer code executes.

## 3. One callable description

```text
Callable {
    code: KnownDefinition(definition_id) | VirtualValue,
    requirements: ordered remaining requirements with original identities,
    results: declared/inferred result contract,
    supplied: original requirement identity -> VirtualValue or VirtualPlace,
    captures: ordered capture identity -> VirtualValue or VirtualPlace,
    ownership: source ownership contract,
    origins: retained-access provenance
}
```

Signature and result information can be pending semantic demands; this is not
permission to invent a result signature before the language's selected-path
checking has established one. A `Callable` record is semantic metadata, not an
`Ir.View`, code pointer or allocated environment.

Named definitions and lambdas differ in how they obtain code/captures, not in
application or binding-time rules. A lambda's code identity is known even when
some capture values are runtime. A by-value capture is a snapshot; a place capture
retains the actual place, not its current contents copied into an owned object.

Direct uses need not materialize a callable. At a first-class boundary, the source
representation contract selects an existing supported view/owned representation.
Representation failure is explicit; it does not silently turn ownership into a
borrow or introduce allocation.

## 4. Ordered application protocol

There is one protocol for positional application. Keyed application uses the same
checked supply records but preserves its specified evaluation order before
canonicalizing requirements. Do not reorder evaluation to obtain canonical keys.

```text
prepare_application(callee, source_arguments, point, context):
    resolve/evaluate callee according to source order
    elaborate each argument under its currently established requirement
    satisfy dependent static/type demands where required
    apply source result-vector adjustment and requirement checks
    retain the ordered computation/effect obligations
    attach checked supply by original requirement identity
    determine saturation
```

The concrete result is:

```text
ApplicationAnswer {
    values: ordered VirtualValue vector, possibly pending,
    obligations: references to ordered source operations/checks,
    outgoing_state: StateId
}
```

A known result does not erase `obligations`. Discarding an argument's extra result
cells does not discard the argument's computation or its effects. Error ordering
and deferred actions follow the language, not query traversal order.

### Incomplete supply

For SLet, establish whether supplied values satisfy static-supply rules by asking
semantic knowledge queries, not by matching AST kinds. Empty application with
requirements remaining returns the same word and invokes no terminal.

An unanswered static demand suspends construction; it does not immediately mean
`static-required`. Reject only after establishing that the required static value
cannot be supplied under the applicable language/execution contract.

Let runtime supply produces the specified open word and retains its mutable-field
semantics. This proposal does not restore the unavailable profile-5 executable
backend or approximate it with SLet adapters.

### Saturated supply

All requirements supplied means invocation, including a nullary callable. Use
the full invocation information: code, supplied values, receiver/captures and
relevant state. Known explicit arguments alone are not sufficient.

- Required-static context: lower the demanded checked fragment and execute it
  through the VM session; publish typed results and accepted state.
- Residual context: retain the invocation and known facts, or specialize it using
  the same callable description. Optional early execution requires the documented
  termination/effect/no-abort proof. No trial execution with a semantic timeout.
- In either context: mere staticness of the result does not erase required effects.

A call with static arguments may produce a static result. A call with runtime
arguments may still have some known results. Neither fact justifies running its
body in the metadata layer.

## 5. VM request boundary

The source solver's proposed request record is:

```text
StaticRequest {
    checked_fragment_and_entry,
    inputs: ordered typed static handles,
    required_state: staging-session identity,
    reason: RequiredStatic | ProvenOptional,
    proof: optional-evaluation justification when applicable,
    source_origin
}

StaticReply = Success(typed_handles, accepted_state)
            | SourceAbort(diagnostic)
            | ResourceFailure(diagnostic)
            | UnsupportedRepresentation(diagnostic)
```

Only the staging bridge publishes computed handles. It performs normal ABC
lowering, verification and `abc_vm` execution. Optimization is optional and is
not an execution substitute. Mode selects interpreted/eager/lazy mechanics only.

Required source errors are not converted into unknown values to make compilation
continue. A refused optional request leaves the original residual computation
and publishes no speculative writes. Actual infrastructure/resource failures
must be reported according to an explicit host policy, not disguised as successful
folding. Persistent transport/snapshot APIs remain a separate design dependency.

## 6. Source places and demand

```text
VirtualPlace {
    id, type, root, typed_path,
    owner, retained_origins, required_lifetime
}

PlaceFacts(place, point, state) {
    contents: VirtualValue or unknown,
    may_alias: source identity/path information,
    observers: address/identity/effect uses
}
```

A projection refines the source path, not a byte address. A dereference needs
provenance evidence of its target; the local containing a reference is not the
referenced storage. Runtime indices conservatively join affected element facts.
Raw-pointer uncertainty cannot be converted into typed nonaliasing evidence.

Demand kinds are Value, Component, Contents-at-point, Identity, Address, Lifetime,
Effect and Control. Forward facts answer these backward queries. The demand
solver retains original definitions and dependencies until obligations stabilize.

For a private record `p = {a = 4, b = x}; p.a = 7`, a demand for `p.a + p.b` can
produce a checked residual addition of 7 and x without a residual `Var`, `Read`
or `Store` for p. If an opaque observer receives p's address, identity and content
obligations can require materializing that storage and its ordered stores.

This is typed source-state analysis, not another low-level load/store residualizer.
Unknown alias cases remain ordinary checked accesses for existing lower layers.

## 7. Materialization contract

```text
materialize(value_or_place, representation_obligation, destination_scope)
    -> existing checked Ir.Expr / Ir.Place / ordered Ir.Stmt
```

Materialization must establish:

1. Dominance and execution order for every emitted definition/effect.
2. Correct call/result shape and source evaluation order.
3. Shared identity for aliases; no independent copies of an observed mutable place.
4. Proven outlives relationships for addresses, views and environments.
5. Correct per-invocation versus module lifetime.
6. Preservation of required traps, allocation effects, safepoints and roots.

It does not choose native registers, A/B scheduling or a new frame allocator.
Existing lowering owns concrete frame offsets; the existing Ershov optimizer
owns eligible expression scheduling; native cache state owns register allocation.

Initially retain complete existing layouts for objects that must materialize.
Escaping owned closures and residual module snapshots require supported explicit
representations, not ad hoc extensions to this operation.

## 8. Canonicalization and recursion

A specialization key contains code identity, applicable type/result contracts,
static supply and capture components, and runtime component shapes. Canonical
order is requirement order, not the chronology in which values were supplied.
Preserve ordered effect obligations separately.

Partial followed by saturated application and equivalent directly saturated
application should reach the same specialization when all relevant bindings and
contracts agree. Different lambda definitions are not assumed equivalent merely
because their bodies look alike.

Reserve recursive specialization identities before constructing bodies. Worklist
facts converge conservatively; do not invent a recursion-depth/count limit or
unroll a recursive call until the host stack fails. Mutable-state read queries
include their state identity. A specialization cache is not a memo table for
executed calls with effects.

## 9. Important correction to the historical example

The archived `closures.slet` uses `seed(40)` and `seed(41)`, where seed is a pure
identity function. Those expressions are not inherently runtime values. If
permitted VM evaluation establishes their results, `add(base)` and
`add(seed(41))` are static supplies and can conform to SLet's existing rule.

The current rejection documents missing knowledge/evaluation support; it must not
be promoted into a permanent language rejection merely because the initializer
syntax is a call. Conversely, this program alone does not establish support for
runtime captures. That needs a positive explicit-lambda test with an actual
runtime parameter. A negative runtime-partial test must also use a genuine runtime
parameter, rather than rely on a pure constant-input call staying opaque.

## 10. Migration contract and tests before implementation

Replace the current authoritative producers and consumers together:

- `staticSupply()` in positional and keyed application must be replaced, not kept
  behind a special module-supply adapter.
- Scope bindings, callable references, lambda captures and application must share
  virtual values rather than separate literal/IR-ref/ad hoc callable conventions.
- Do not collapse callable identity into a `View` during binding. Create that
  representation only where its use requires it.
- A scalar `borrowedLocal` flag is not a complete provenance contract. Metadata
  migration must preserve origin information through all consumers and returns.
- Do not silently change `Compiler.typed`/`typedFile`'s backend-independent promise.
  Required static demands make that API boundary an explicit decision still to agree.

Contract tests should cover:

| Input situation | Required result |
|---|---|
| Literal and immutable alias | Same static supply eligibility |
| VM-produced value and its alias | Same eligibility as the corresponding literal |
| Genuine runtime parameter supplied partially in SLet | `static-required` |
| Historical seed(40) example | Not classified runtime solely from syntax |
| Named word and equivalent statically captured lambda | Same application/evaluation rules |
| Known code with runtime lambda capture | Preserve partial knowledge; no eager adapter requirement |
| Known result with an ordered effect | Retain the effect |
| Private virtual record and projected results | No unnecessary source object materialization |
| Observed address / may-alias write | Correct identity, mutation and residual access |
| VM arithmetic/check tests with optimization disabled | Correct values, effects and error provenance |

No executable tests or compiler edits implementing these records accompany this
proposal. The proposed typed-entry/policy decision is in
[source-compilation-api.md](source-compilation-api.md). Confirm that decision and
the first supported staging transport scope before implementing a vertical slice
with these contract tests rather than an unused metadata library.
