# Let: proposed semantic core

## 0. Status and purpose

**Proposal, not implemented specification.** [DESIGN.md](DESIGN.md) remains authoritative;
[LANGUAGE_REFERENCE.md](LANGUAGE_REFERENCE.md) documents the current surface. Neither is replaced here.
All examples below are future acceptance criteria, not programs checked by the current test harness.

Let should have a small number of mechanisms whose rules compose: chains, construction-time
descriptions, and explicit ownership. Do not add a new mechanism for each useful example, or claim
that a short surface makes an unspecified checker simple.

The reduced proposal preserves nominal word/host identities, structural records, erased types,
direct specialization, and precisely ordered preludes. Callable annotations describe requirements;
they do not erase implementations. No mandatory closure runtime, heap, collector, reference count,
dynamic callable ABI, or runtime type descriptor is introduced.

Sections 1–6 state the proposed core. Section 7 explains the reduction; section 8 records what still
needs design or proof. This is not a complete grammar or an ownership soundness argument.

## 1. The objects already required by a chain

```text
template = declaration identity + lexical bindings + ordered groups/stages + terminal
word     = template + current position + bound environment
place    = owner identity + structural path
```

A template has one terminal payload: a data expression or a runtime body with a result description.
Its unresolved stage descriptions may depend on earlier bindings. Resolve lexical names once, at
declaration; evaluate dependent descriptions under those bindings, not the caller's lexical scope.

An environment binds declarations to descriptions, bound words, known data, symbolic runtime values,
or places. Every checked value has a semantic type. Word implementation identity can be known while
its retained fields remain runtime data. Ownership and dependency information accompany the value.

A partially bound word is a chain residual. The runtime operations emitted by compilation form the
residual program. Neither implies a universal closure representation.

## 2. Descriptions, identity, and acceptance

### 2.1 One description vocabulary

`Type` is the construction-time sort of descriptions. Its values include existing scalar/host/word
type descriptions, record and sum descriptions, and descriptions of a chain's remaining interface.
A chain description contains ordered stage descriptions and capabilities, terminal kind and result
description, and receiver usage. It is not another executable chain or another application interpreter.

A description can denote one exact semantic type or constrain a supplied concrete value. A record
with an open callable field is a requirement until an implementation is supplied, not an existential
dictionary layout. A concrete value still retains its exact semantic type and bound dependencies.

Three queries have different jobs:

| Query | Rule |
| --- | --- |
| `equal(D, E)` | Compare evaluated descriptions by their structure and declared identities |
| `accept(D, value)` | Check the supplied checked value against the description; retain its concrete identity |
| legal use | Check ownership, access, and escape obligations in the current context |

For equality, scalar descriptions compare by kind; host types by declaration; word types by template,
position, and relevant static semantic bindings. Records compare member names/order, capabilities,
and descriptions; sums compare their alternatives. Chain descriptions compare stages, capabilities,
terminal kind/result, and receiver usage. Aliases add no identity. Do not compare C layouts or try to
prove arbitrary construction programs extensionally equal. Description equality is not satisfaction:
square's exact word type differs from an Int-to-Int requirement that square satisfies.

For acceptance, exact types require equality, subject to explicit ordinary introductions such as a
unique sum injection. A chain requirement checks the supplied word's remaining interface. A record
requirement checks corresponding fields recursively, retaining their actual implementations. No width
subtyping, function variance, hidden capability conversion, or synthesized adapter is introduced.
Checked introductions carry their selected tags/operations forward; acceptance is not a boolean that
leaves lowering to guess how a conversion happened.

Runtime storage and C entries require concrete layouts. Runtime sums require concrete alternatives;
a callable requirement alone supplies neither a sum payload layout nor dynamic dispatch.
Descriptions, including requirements, may be arguments to ordinary Type stages. That does not itself
quantify over types or introduce a higher-rank callable. Operations needing a concrete type must wait
for a concrete binding or reject the request.

### 2.2 Calling requirements are not universal body proofs

**The contract describes the operation. The word supplies its implementation and dependencies.
The use site must have permission to perform it.**

`Int -> do Int` describes one Read Int stage, a runtime Int terminal, and invocation without taking
ownership of retained receiver state. It establishes the calling facts needed by `f(f(x))`; it does
not promise purity, no captured state, or compatibility with every surrounding live access.

Receiver ownership uses the same ownership capability distinction as arguments: borrow retained state
or transfer it. This is a separate position, not an extra argument stage. Owning an incoming word and
consuming that word on invocation are different events. The spelling of receiver capability in a
written contract is still to be settled; no dedicated constructor is assumed.

An implementation requiring receiver consumption cannot satisfy a borrowed-invocation requirement.
A transferred receiver can use a borrowed-invocable implementation only if cleanup leaves its result
valid. Ordinary invocation may consume newly acquired Own arguments. It must preserve retained
ownership positions: writable contents may be exchanged under a restoration obligation, but extracting
retained state without restoring those positions requires receiver transfer.

A result keeps its actual dependencies even when it satisfies a description. Consequently a consumer
may pass escape checking for one matching implementation and fail for another (P19). This is explicit
specialization-based checking, not an unstated promise of universal generic validity. Specialization
must not change a declared calling signature just to rescue an incompatible argument or result.

### 2.3 Types and requirements use ordinary construction

Annotations evaluate ordinary construction-time expressions yielding descriptions. Names keep their
meanings; a word name does not silently become its type after a colon. `TypeOf` is the proposed
explicit static inquiry, not runtime reflection. It observes the checked type, not merely an annotation
requirement, and does not invoke the terminal of a supplied word.

Its operand otherwise follows ordinary evaluation. `TypeOf with tick(1)` preserves tick's runtime
effect in runtime code and is disallowed in an annotation requiring runtime-free evaluation. Looking
up an existing binding's checked type needs no load or runtime descriptor. Moved sources remain
unusable, and temporary operand ownership still requires cleanup.

Generic dependencies use ordinary Type stages:

```let
let Unary = let A : Type let B : Type; A -> do B
let twice = let T : Type let f : Unary with T with T let x : T do : T
    return f(f(x))
end
```

Here T is bound before the requirement on f is evaluated. No separate dependent-contract binder is
needed. General requirements quantifying over an as-yet-unsupplied Type stage are not in this baseline.

Deduction matches declared requirements against checked argument types, not source-expression forms.
Obtain that information through the ordinary semantic engine, not a second `derived_type` interpreter.
A type-information request must not execute argument effects or commit its moves/accesses ahead of
earlier preludes. Runtime evaluation still occurs once at the position dictated by advancement.
Direct type variables and structural patterns can be matched; do not invert arbitrary type-producing
words. Ambiguity requires explicit arguments. Scheduling this query with dependent preludes is an
explicit algorithm obligation, not solved by the words “use the checked type”; P03 includes its trace.

Records remain structural. Two type-producing words may yield equal record descriptions despite
being distinct words themselves. A producer's code-cache key is not the identity of its returned
structural type. Runtime values and instance addresses do not create nominal types.

### 2.4 Surface kept small

Keep `let`, stages and capabilities, `with`, invocation, records, `move`, and `do`. Arrow descriptions
associate right, below application. An omitted stage capability means Read.

Use `do T` for a zero-stage runtime description and `do : T ... end` for an executable body; the
colon distinguishes the forms syntactically, without resolving a name. Statement constructs such as
`if ... do ... end` have their existing syntactic contexts. This grammar direction needs parser tests.

`A -> B -> do C` describes two stages. A concrete data type in tail position describes a data terminal.
A data terminal returning a word can name its exact word type. The spelling for a data terminal whose
result is itself only a callable requirement remains open; do not invent another constructor for it
before deciding whether that broader description is needed.

## 3. One advancement operation, two retention policies

A template interleaves groups and stages, then reaches its terminal. Constructing it reaches group0.
For each supplied argument:

```text
obtain the receiver before its arguments
evaluate the next argument once
evaluate/check the stage description and capability under existing bindings
bind the argument
process the newly reached prelude group before evaluating another argument
return the partial word, or evaluate the reached terminal
```

`with` permits a persistent partial result. Invocation requires saturation and keeps intermediates
transient. Supplying the last stage reaches the terminal in either form. An originally zero-stage
do word is constructed without invoking its body; `word()` invokes it. Returning another word from
a data/body terminal returns that value, not an instruction to keep invoking it.

| Operation | Existing retained state | Newly acquired ownership |
| --- | --- | --- |
| Persistent advancement | Copy if Copy; otherwise transfer a fresh receiver or require explicit move of an existing one | Belongs to the resulting residual |
| Ordinary invocation | Borrow receiver state | Belongs to the activation until transferred or destroyed |
| Consuming invocation | Transfer receiver state | Belongs to the activation until transferred or destroyed |

Thus `prepared(1)` may borrow a non-Copy receiver while `prepared with 1` requires moving it. This is
a deliberate retention-policy difference, not permission to duplicate ownership or rerun old preludes.

| Stage capability | Binding rule |
| --- | --- |
| Read | Copy Copy data; otherwise retain a scoped dependency on the supplied value |
| Own | Transfer ownership; a fresh owned result needs no named-source move |
| Mut | Reserve exclusive access when supplied; the remaining suffix cannot independently persist |
| OwnMut | Transfer writable ownership |

A retained dependency must fit its destination's permitted lexical extent, including cleanup order;
it may end earlier when that holder is replaced or destroyed. A transient dependency lasts for its
permitted use/result extent. Copy arguments retain the value read when supplied, not a later read
from that place. Type bindings remain construction knowledge and are erased.

Phase, knowledge, and effects are separate. Execute construction operations only where authorized.
Known arguments do not make an ordered runtime host call executable in the compiler. Preserve ordered
effects and trapping behavior even when their data results are unused. Fold scalars only with exact
Let semantics, never through imprecise Lua-double conversions.

Unknown runtime control produces branches/loops. Same-instance recursion refers to reserved code
identities; it does not require evaluating the runtime recursion. No general symbolic path solver is
assumed. Unbounded construction or new static instances can exhaust an explicit compiler budget.

## 4. One checker state and its transitions

These are proposed static transitions modeling source execution, not runtime owner IDs, locks, or
borrow tables. They refine the rules above; an implementation and soundness argument remain to be
built. Operation phase is a precondition, not something inferred from known arguments.

### 4.1 The facts in a state

| Fact | Contents |
| --- | --- |
| Places | Stable place identity/path, permitted writes, declared requirement, concrete storage type, and Uninitialized / Live(value) / Moved state |
| Values | Exact semantic type and word identity, known/symbolic data, owned children, and retained dependencies, including possible origins after a join |
| Loans | Target, Read/Write permission, holder, permitted extent, delegation parent, suspended parent uses, and any place-restoration obligation |
| Activations | Caller/callee and chain position, retained-borrowed versus activation-owned state, application temporaries, and fixed cleanup positions |

These are views of one state, not independent checkers. A place and its current value are distinct.
Assignment preserves the destination place but replaces its occupant. Moving transfers a value and
its owned subtree; it does not make an old source slot a second name for the destination.

Field places belong to the containing value. Destroying that value ends those places, even if a new
record later occupies the same address. Capturing a mutable outer binding instead can follow later
replacement of that binding; a dependent on a particular old field/owner cannot be silently retargeted.

A requirement annotation does not create existential storage. Once an ordinary runtime slot is
initialized, its concrete type is fixed. Another value satisfying the same calling requirement but
having a different exact word type cannot be assigned to that slot. Use an explicit concrete sum for
runtime implementation choice. Static bindings have no runtime slot.

Dependencies retain their kind and holder:

| Dependency | Protected fact |
| --- | --- |
| Place capture | The captured place and its owner remain available; permitted replacement of that place's contents may occur |
| Retained Read of a non-Copy value | That bound value remains available; replacement, move, or destruction of it is blocked while dependent |
| Host view | The producer-declared storage/content and access extent; conservatively pins opaque storage |

Dependency facts belong to live values, structurally to the relevant fields, not permanently to a
variable name. Copies retain their own contributions. Overwriting one holder does not end another
holder's dependency. Place captures are deferred requests; actual host views retain active access.

### 4.2 Transition table

Each row includes the acceptance and ownership checks it needs. A failed precondition rejects the
operation; there is no speculative execution followed by rollback. Transferring an existing non-Copy
source requires explicit move with owning authority or a restoring exclusive permission (section 4.5).
A fresh owned result can transfer directly. Matching a type never grants ownership of a Read borrow.

| Transition | Check and update |
| --- | --- |
| Construct a word/aggregate | Create fresh owned state; acquire captures by section 4.3; initialize reached fields in order. Check each initializer against the current state. A field becomes Live only when initialized. |
| Bind a description | Evaluate authorized construction semantics and retain the static description. Do not create runtime ownership/layout for the description itself. Preserve any independently required operand effects. |
| Bind a runtime value | Check the requirement and establish the concrete type. Copy, transfer, or bind a dependency according to capability. Validate installation at the destination, including dependency extent and cleanup order, then install its facts. |
| Obtain an invocation receiver | Read a Copy receiver as a value, preserving its snapshot/dependencies; borrow and protect an existing non-Copy receiver against destruction/relocation. A fresh receiver is an application temporary unless transferred. Do not activate captures yet. |
| Supply a stage | Evaluate the argument in caller context, check its description/capability, and bind it in the pending callee. Own transfers; Read copies or retains a dependency; Mut reserves an exclusive slot loan. |
| Enter a reached prelude/body | Switch to the callee activation. New owned inputs/preludes are activation-owned; retained state follows receiver mode. Apply checked state effects in source order (section 4.8), not just result-dependency substitution. |
| Finish an unsaturated persistent advance | Install a new retained word using copy/transfer rules. Recompute receiver-use requirements for the new prefix. No independently persistent residual may retain a bound Mut loan. |
| Request nested access | Prove owner/path, authorized mode and eligible ancestor; check competing loans; suspend the parent's overlapping use. A pending sibling argument slot is not an ancestor. |
| End or hand off a loan | Require covered places restored where owed. End that holder's access; resume the parent only when no surviving child/view keeps it suspended. Returned/copied views retain their obligations. |
| Assign | Evaluate RHS once, then use the replacement transition in section 4.5. Preserve destination place identity, not old value identity. |
| Move a non-Copy value | Require an initialized source and owning or restoring exclusive authority, plus the transfer checks in section 4.7. Mark source Moved and transfer the value/facts. A restoring take keeps its permission active until the place is reinitialized. |
| Copy a value, including move of Copy data | Require a valid initialized read and Copy type. Create a new value with copied data/dependencies. Leave the source live; do not create another owner of a non-Copy target. |
| Join branches | End branch-local extents, check ownership/carrier agreement, and merge remaining facts by section 4.6. Never keep only the last checked branch's dependencies. |
| Check a loop | Require ownership/carrier agreement at its header/backedge; close dependency/knowledge facts over entry and backedges before accepting uses based on them. |
| Return | Validate escaping installations and transfer/copy the result; run ordered cleanup, checking restoration at every loan-release/handoff boundary; publish the final post-state, including cleanup effects, to the caller. |
| Destroy / leave scope | Use fixed reverse cleanup positions (section 4.7). Keep required dependencies through cleanup, then release that holder's contributions. Skip moved occupants; never destroy a borrowed target. |

### 4.3 Capture acquisition and Copy

A free binding needed by the suspended remainder is acquired during word construction, not
reconstructed on invocation:

| Captured binding | Acquisition |
| --- | --- |
| Construction-only description/static binding | Retain static knowledge; erase it from runtime layout |
| Immutable Copy value | Copy the value into retained state, preserving any dependencies that value already carries |
| Mutable binding, even of Copy type | Retain its place so future reads observe the binding, not an old snapshot |
| Non-Copy value not explicitly transferred into owned state | Retain the appropriate scoped dependency; capture does not take ownership |

References used only by immediately reached initializers are evaluated now; they are not automatically
retained captures. Those initializers use the constructing context's authority. For example, a reached
`let owned = move buffer` can transfer a caller-owned buffer into new retained state. Deferred code
has only its captures' permissions: a Read dependency cannot be taken; a writable place can use the
restoration rule, not implicitly acquire its enclosing owner. A captured borrow carries its loan and
extent. Capturing its place neither discharges restoration nor silently extends that permission.

Taking ownership into retained state uses ordinary owned initialization or Own advancement, not an
implicit owning capture. Capturing a value by copy is different from acquiring a non-owning edge to
its old local slot. P22 exercises both copy capture and explicit owned initialization.

Copy is derived from concrete semantic state, not from whether its C representation happens to be
pointer-sized. Preserve the scalar/Unit/literal rules. A record is Copy only when all fields are Copy
and it has no mutable member; a sum only when every alternative is Copy. Host values require the
host type's Copy policy; destructor-owning resources are not implicitly Copy.

A concrete word is Copy only when its owned retained components are Copy and none introduce owned
mutable identity. Deferred dependencies can be copied without owning their targets: a word retaining
only a Read dependency on Buffer need not own or duplicate that Buffer. Copying a permitted read view
retains its access obligation. A persistent exclusive view cannot be made Copy by copying a pointer;
a host type admitting such a view must not advertise that Copy guarantee.

Binding mutability alone does not change the type's Copy property. `move` of an Int copies its value;
it does not move the mutable place or invalidate words capturing that place.

### 4.4 Invocation frames and receiver prefixes

A pending callee retains its bound arguments between stages. Argument expressions execute in the
caller; newly reached preludes execute in the callee. Temporarily switching back to the caller for
another argument does not release earlier stage loans.

Therefore a callback from a reached callee prelude may reborrow a bound Mut permission, while the
same callback used as a later caller argument may not borrow from the pending callee's slot (P21).
This ancestry is semantic and must survive inlining or splitting the chain into generated C helpers.

For nested access, the enclosing permission must cover the proved place and mode, the parent use
must be suspended, and no other live loan/view may conflict. Read cannot fund Write. Distinct Mut
argument slots are simultaneous grants, not parent and child. Proven disjoint fields can be borrowed
independently; unknown paths overlap conservatively. An owner's authority is not a self-borrow.

Obtaining f in `f(f(x))` does not reserve its captures ahead of the inner call. Do not eagerly acquire
the union of possible capture accesses for the entire caller. Declared interior mutability still
permits field writes, subject to actual exclusive-access checks.

Receiver use is derived for each retained prefix from the remaining preludes and terminal. Extraction
from retained state without restoration requires an owning receiver; a borrowed receiver may exchange
a writable field under section 4.5. An immutable retained field provides no such write permission.
Consumption of a new Own argument instead uses activation ownership. Retaining that argument changes
its role, so the residual contract is not obtained just by deleting an arrow (P07).

Taking a mutable field's occupant does not transfer the containing receiver or place. Every required
retained position must be initialized again before borrowed invocation finishes. External captures
remain dependencies even when the receiver itself is transferred; only their actual permissions apply.

A fresh receiver can fund a required consuming invocation without a named-source move. An existing
non-Copy binding requires explicit move for receiver transfer. Anonymous receiver ownership and its
cleanup boundary are defined in section 4.9; borrowed invocation does not extend that boundary.

### 4.5 Assignment is replacement, not destruction of a place

For a local binding or a statically identified field destination:

1. Evaluate the RHS once, retaining its value and effects. Do not destroy the old destination first.
2. Check the resulting value against both the declared requirement and the slot's fixed concrete type.
3. Consult the post-RHS state: the destination may still be Live, or the RHS may have moved its value.
4. Obtain write permission. Check incoming dependencies against destination extent and cleanup
   position. Reject dependencies/views invalidated by replacement, including ones just produced by
   the RHS. A capture of the destination place can remain if the place survives; a dependency on its
   old value or places owned by that value cannot.
5. If the old value remains Live, destroy it once under its cleanup obligations. If moved, skip its
   destruction. No user computation may observe an uninitialized slot between this cleanup and install.
6. Install the incoming value as Live and discharge restoration owed for that place. Release old
   contributions after required cleanup; preserve surviving copies' obligations.

Binding, assignment, aggregate installation, and return use the same destination check. Storing a
dependent in a longer-lived slot is not excused by a hoped-for later overwrite; the baseline requires
it to fit that destination's permitted extent.

A non-Copy occupant may also be taken through exclusive writable-place permission, without taking
the place or its enclosing owner:

- Require the normal move/invalidation checks, a live occupant, and an exclusive permission whose
  extent covers the take and restoration. Read permission cannot authorize this operation.
- Mark the place Moved and make the extracted value owned at its destination. Record an obligation
  on the permission to restore that place, at its fixed concrete type, on every normal exit.
- Keep the permission active while the place is vacant. Reads, ordinary argument borrowing, and
  callbacks that would use the vacant place are rejected. Unrelated operations may still execute.
- Require restoration before ending the permission, resuming its parent, or handing it out as an
  outgoing view. Early return does not bypass the obligation; loop/join checks retain pending debts.

Deferred captures of that same stable place may remain during a restoring take, because access is
excluded while it is vacant and later reads observe the replacement. A dependency on the old value,
one of its owned places, or a conflicting live view still blocks taking it. This does not permit
relocating an enclosing owner under an outside capture.

An owned mutable local normally needs no restoration after move. If a deferred place capture would
otherwise be invalidated by leaving it empty, only a restoring take is permitted. Thus
`buffer = extend(move buffer)` can restore an exclusively protected place without a double destroy;
a rejected take is never retroactively legalized by a later store. P23/P27 exercise these cases.

This is a statically checked obligation, not an atomic batch, rollback, or implicit swap primitive.
Effects between take and restoration remain observable. The initial no-unwinding boundary is
essential: any future recoverable exit mechanism would need to preserve these obligations.

Binding/field destinations must retain the same enclosing place/owner across RHS evaluation. If the
RHS invalidates a containing record needed for that destination, reject rather than store through a
stale address. Computed destination evaluation order and more general replacement paths still need
grammar/operator-level specification.

### 4.6 Joins preserve owners and conservatively merge provenance

At a join, discard terminated paths and finish branch-local cleanup/loans first. For each surviving
slot, incoming paths must agree on initialized/moved state and concrete carrier type. Different live
occupants can be represented as one joined abstract value: exactly one runtime occupant is owned,
not every possible incoming resource. Rebase internal child/field relationships onto that joined value.

Merge remaining facts as follows:

| Fact | Join rule |
| --- | --- |
| Known runtime scalar | Keep it if all incoming values agree; otherwise mark symbolic |
| Static description | Require the same description wherever such a join is allowed; do not invent a runtime type descriptor |
| Concrete word implementation/type | Require agreement, or an explicit concrete sum at the source; a shared calling requirement is insufficient |
| Retained dependency origin | Retain the union of possible outside origins, after rebasing corresponding owned state |
| View access | Retain every possibly live access obligation contributed by surviving values, including target, mode, holder/extent, and provenance |
| Enclosing permission | Preserve compatible authority, all pending restoration obligations, and suspension while a possible descendant view survives |

A later move, replacement, or escape must be legal for every possible retained origin. A union of
origins is not proof of one particular alias or delegation parent. Reborrowing requires provenance
proved for the possible cases; if lost correlations are needed to establish legality, reject rather
than guess. Conservative provenance may reject programs that would require relational path analysis.

Unconditionally overwriting a slot can replace its own may-dependencies with the new value's facts.
It cannot erase a surviving copy's obligations. Scope exit releases the contributions of values that
actually leave the scope. These are static checks, not runtime reference counts or ownership flags.

Loops need a stable conservative result for these facts over entry/backedges. Exact ownership
agreement remains required; it does not eliminate provenance analysis. Abstract iteration must use
bounded symbolic origins/widening, not mint a new compiler owner for each simulated runtime iteration.
A finite loop/recursive-summary algorithm is still an adoption gate. P20 supplies a join witness.

### 4.7 Transfer, return, and cleanup boundaries

A non-Copy move transfers one owned subtree. Dependencies on the transferred value or its owned
places, and competing loans, must not be invalidated. A capture of the vacated slot itself can remain
under section 4.5's restoration rule. The governing exclusive permission is not a competing loan.
Outside dependencies must fit their owners' extents; internal relationships must survive at the
destination; host stability obligations must permit relocation. Aggregate initializers run in order
and each move must be legal. There is no batch transaction for moving already-borrowed independent
owners and their dependents into a new aggregate.

Preserving those relationships is the semantic obligation. Destination construction, relative paths,
or pointer repair are representation strategies, not permission for arbitrary C struct copying.
Opaque host views remain pinned unless their contract proves the relevant transfer safe.

Every escaping installation, including a store through a parameter/capture, maps its dependencies to
state transferred with it, surviving outside owners/places, or dying local owners. Rebase the first,
validate the second against the destination extent/cleanup position, and reject the third. Returning
Unit does not exempt side-effect stores from this check.

Return additionally requires borrowed positions restored before caller permissions can resume.
Outgoing view loans need authority from a surviving source permission; they cannot retain a grant
whose only authority dies with the callee. Parent uses remain suspended for valid outgoing extents.
The substitution algorithm must cover result and post-state together, not promise escape from a
declared result type alone.

Cleanup positions belong to bindings, retained fields, and registered temporaries, in their ordered
initialization/acquisition sequence. Replacement and reinitialization reuse a position; they do not
append a new one because the occupying value is newer. Transfer to another destination uses that
destination's position and leaves the source moved. A transferred aggregate preserves its internal
field order. All of these decisions are static; conditional replacement adds no ownership flags.

After transferring the result, use one reverse-position cleanup order for the activation and its
application temporaries. Borrowed invocation leaves retained ownership intact; consuming invocation
includes retained state not returned. Each holder keeps dependencies through its required cleanup
and releases them at its position. Reject incompatible dependencies instead of dynamically reordering
cleanup. P26/P28 fix temporary and replacement destructor traces.

Cleanup effects may update other surviving places, but cannot install a new occupant into a position
whose cleanup has begun or finished. Reject a destructor contract/post-state that repopulates such a
position; do not add dynamic cleanup registration or silently abandon the new owner.

Records may have statically known moved fields. Transferring a non-Copy sum payload consumes the
whole sum; copying a Copy payload is a read, not a partial ownership hole. Opaque resources remain
indivisible unless their host contract supplies decomposition. Ordinary records use derived cleanup.
End dependent uses before ending their owners' places.

### 4.8 A call transforms state, even when its result is Unit

The semantic boundary is `(state, instance, actual bindings) -> (post-state, checked result)`. A
checked body may serve as its own parameterized state transformer; this does not require another
IR or a second interpreter for types. Reusable checking information must account for:

| Part | Required information |
| --- | --- |
| Entry | Initialized places, capabilities, dependency/invalidation constraints, and actual alias/provenance bindings |
| Ordered work | Reads of current places, acquisitions/releases, moves, replacements, callbacks, and newly created owners/dependencies, sequenced through control flow |
| Normal exit | Updated facts for every affected surviving place, result facts and outgoing loans, restored borrowed positions, and cleanup obligations |

Substitute caller places/owners at use. Capture snapshots when the source evaluates their values;
later loads from captured mutable places consult the updated state, not facts frozen at first
specialization. A cached body must not carry another invocation's owners, permission, or post-state.

A definite store to a proved single target replaces that holder's facts. Conditional or uncertain
stores conservatively join old/new possibilities; they cannot erase an obligation merely because
some possible target was overwritten. Preserve incoming facts for places proved untouched.

Effects of reached preludes are visible before the next caller argument. Nested calls likewise
publish their effects before subsequent operations in the enclosing body. This is not a union of
all possible accesses reserved at entry. Deduction/type inquiry must not apply these transitions
before their source position.

Apply the same destination checks to stores into caller-owned or captured storage as to results.
An incoming Read argument may be retained only where its actual owner and permission allow; it is
not automatically limited to the callee's local binding, nor automatically valid in module storage.
A Unit result does not make a call an identity transformer (P24). Destructors and other cleanup calls
also contribute ordered state effects. The returned value is selected before cleanup; the caller's
post-state is the state after cleanup. Neither may be substituted for the other.

Recursive calls need a conservative joint solution for post-state effects and result/loan facts.
Reserving a code identity does not supply that solution. Do not check a recursive call against an
empty effect or dependency summary and later cache that answer as proof. A bounded algorithm and
its treatment of uncertain targets remain explicit adoption gates.

### 4.9 Anonymous ownership has an application boundary

An application owns anonymous receiver/argument values that it obtains but does not transfer into
other ownership. Its region starts before obtaining the receiver and ends after its reached work,
result validation/transfer, and cleanup. Argument expressions still execute in caller context;
ownership region and permission ancestry are not the same fact.

A nested producer hands its fresh owned result to the consuming application, initializer, assignment,
aggregate field, or return. It does not destroy that result on its own exit. A named destination then
owns it at that destination's cleanup position. An assignment holds its RHS through old-value cleanup
and installation; a discarded expression destroys any untransferred result at its evaluation boundary.

At application completion, activation bindings and anonymous operands share section 4.7's ordered
cleanup positions. End transient dependencies/loans at their positions before destroying protected
owners. Do not clean up all activation ownership first and all anonymous operands afterward: a later
Read-argument temporary was acquired after an earlier prelude, and must be cleaned up before it.

A fresh borrowed receiver and a fresh Read argument remain owned by this application, not by their
borrowed bindings. Own inputs transfer to activation/retained ownership; their old temporary positions
are moved and do not destroy them a second time.

A result depending on an anonymous owner destroyed at this boundary cannot leave the application
unless ownership of that owner travels in the result. Do not extend a temporary merely because an
enclosing expression could use its dependent immediately. Naming the owner explicitly gives it the
ordinary binding extent instead (P26).

`with` also has this boundary. An unsaturated result must be independently retainable:
`inspect_read with open_buffer(8)` cannot silently acquire ownership of its Read argument. Likewise a
partial result retaining a bound Mut loan cannot cross this boundary merely because a surrounding
application would immediately saturate it. Use one saturated invocation for transient Mut stages.
Ordinary aggregate construction instead transfers owned field initializers into the aggregate in
order; moving that existing closed aggregate remains governed by section 4.7.

## 5. A compiler with one owner for each decision

```text
parse and resolve -> demand-driven elaboration -> verify/simplify residual IR -> storage/ABI and C
```

These are responsibility boundaries, not a required file count or a new framework. Refactor the
existing compiler incrementally. A shared evaluator is justified by shared application semantics,
not by renaming passes; ordinary helpers and explicit results are sufficient.

- Resolution establishes lexical identities and templates. It does not execute generic applications.
- Elaboration evaluates expressions and descriptions, advances words, checks ownership/use, and
  builds runtime operations. One implementation owns each semantic decision.
- The residual builder owns stable handles, control joins, effects, and temporary transport. Encode
  relative belt references when sealing, not by handwritten bookkeeping in expression evaluators.
- Representation chooses storage and calling convention under established ownership/extent obligations.
  Emission prints selected calls, members, injections, and cleanup; it does not reconstruct them.

Parse/resolve all templates. Check concrete semantic instances demanded by initialization, calls,
exports, cleanup, or requirements needing body guarantees. Check both arms of runtime control before
optimization, even for a constant condition; construction-time selection may choose one instance.
An undemanded local body's type errors remain deferred, generic or not. This diagnostic policy is a
proposal, not a consequence forced by erasure. It must be tested independently of optimizer behavior.

Reserve instance identities before recursive elaboration. Cache code and parameterized checking
information for section 4.8's state transformation, not runtime state or permission to call it.
Instantiate against actual owners/state at each use. Code sharing never implies identical legal
uses or identical post-states. Do not put runtime addresses or every known scalar into a code key.

Required schema/implementation invariants:

| Decision | Single owner / carried result |
| --- | --- |
| Expression/type application | The evaluator's checked values; no partial syntax-based type guesser |
| Terminal | One payload per template, not a kind in one schema and an optional body elsewhere |
| Acceptance/injection | Selected semantic introduction and tag, retained into IR |
| Copyability | One query using concrete semantic types and declarations |
| Runtime state | One concrete layout used by construction, advancement, captures, unpacking, transfer, and destruction |
| Erasure | Description-only bindings never enter that layout or any generated runtime packet |
| Storage | Owner/extent obligations survive into representation |

Keep ASDL for structural vocabularies, not every mutable analysis table. Separate evaluator values
from the residual analyzer's Known/Runtime facts. Verification checks IR references, types, edge
interfaces, and effect continuity; it does not repair malformed IR or prove source ownership by shape.

Report source rejection, unsupported implementation, and internal invariant failure distinctly.
Instantiation diagnostics need the failing operation and its application chain. A construction budget
failure is an operational compiler limit, not evidence of a type error or compiler bug.

## 6. Modules and the foreign boundary

A module is an owning chain result: its export plus retained state. Initialization runs its reached
preludes in order; unload destroys owned state. Distinct initializations have distinct owners even
when their code and nominal type identities are shared. Modules are not exemptions from capture rules.

Destination-passing initialization, pointer-receiver entries, and in-place drop are suitable C ABI
strategies. Generate a move operation only for a movable layout. The host supplies storage and must
not duplicate ownership with struct assignment, use moved/unloaded instances, or move pinned storage.
No particular allocator is required.

A language-level generic export remains a specialization recipe. A requested C entry must have fixed
types/layouts after static bindings; a callable requirement is not a universal callable ABI.

A foreign operation supplies the same input/output state obligations as a checked Let body, but as
trusted declarations. Result dependencies name source storage/value/path, access, and extent. Mutated
slots also need post-state information; a result-only producer contract is insufficient.

For an opaque Mut input, assume it may replace/destroy the old occupant and invalidate its owned
storage, even if it returns Unit. Reject the call while a value dependency or view forbids that
invalidation. A place capture can remain only if the place itself survives. The host must return
every Mut position initialized at its fixed concrete type; nonlocal unwinding is not allowed. Writes
through declared retained permissions, including during destruction, require the same invalidation
and post-state treatment; the rule is not limited to syntactically explicit Mut parameters.

Without a stronger postcondition, forget the old occupant's identity and known contents. Retain
possible old dependencies together with any declared new ones: possible replacement is not proof
that old obligations ended. A definite replacement/preservation contract may give more precise facts.
Dependency-bearing replacements require declared origins; missing information is not an empty set.
Undeclared retained borrows remain forbidden. Reject boundaries whose post-state cannot be represented.

A precise preservation guarantee may permit mutation under a deferred value dependency. Preserving
value identity does not also promise stable backing addresses/content, or permit Write while a
conflicting Read view is active. Ownership transfers and result/slot origins must distinguish entry
values from post-call contents, as an exchange operation returns the old occupant, not the new one.

A view type alone cannot give one argument index for all producers. Without a more precise contract,
a borrowed host view retains a lexical Read access and pins its owner. A local borrow cannot become
dependency-free foreign storage. P25 exercises invalidation independently of result type.

The initial boundary excludes undeclared retained borrows, callbacks into Let, and nonlocal unwinding
across Let frames. These are trusted host obligations. Extending them requires an explicit contract;
normal cleanup guarantees do not cover process termination.

## 7. What this reduction removes

- No nominal-record branding or separate branded-construction operation.
- No `For` primitive: use ordinary Type stages and construct the requirement after binding them.
- No `Consuming` constructor: receiver ownership is capability information; settle its spelling separately.
- No `Runtime` constructor: the description `do T` differs syntactically from a body `do : T ... end`.
- No speculative `Data` constructor to settle an unresolved corner of arrow notation.
- No transactional/contiguous batch-move rule. Move an existing ownership aggregate.
- No mandatory component per responsibility or new method/continuation framework.

`TypeOf` remains one proposed explicit inquiry because names keep their meanings in annotations.
Descriptions still need primitive formation rules, just as scalars need primitive operations. Those
rules are not a second language for applying or specializing words.

## 8. Remaining design and validation work

| Question | Required next artifact |
| --- | --- |
| Description/receiver surface | Parseable grammar for receiver capability and callable-valued data terminals; do not invent new constructors by default |
| Semantic schemas | Encode the section 4 state and canonical static keys; specify bounded deduction without premature effects/moves |
| Phase authorization | Classify source terminals/primitives and erased-result cases, including `do : Type`; known values must not determine execution permission |
| Access checking | A bounded implementation/proof for call post-states, joins/recursion, restoring takes, and outgoing loans; validate temporary and cleanup boundaries with P24–P28 |
| Transfer representation | A worked returned aggregate with captures, safe relocation, exact destruction order, and opaque pinning |
| Foreign interface | Entry-value/post-state and producer-origin schema, preservation guarantees, export/storage contract, and conformance examples |

These are not implementation details already solved by the prose. The following witnesses constrain
the work; they do not establish soundness. Close these questions before adopting this as the current
specification or starting an independent compiler rewrite.


## 9. Worked proposal witnesses

Each witness is a future acceptance criterion, not a passing current test. Local fragments are marked
as such. Exact diagnostics and final helper spellings are intentionally not fixed.

### P01 — Contract-constrained words: accept, specialize, erase the requirement

```let
let Transform : Type = Int -> do Int
let square = let x : Int do : Int return x * x end
let increment = let x : Int do : Int return x + 1 end
let twice = let f : Transform let x : Int do : Int return f(f(x)) end
let a = twice(square, 3)
let b = twice(increment, 3)
```

Expected values: `81`, `5`. The requirement is erased; concrete implementation identity survives.
Produce concrete calls or equivalent simplified code, not a universal callable field. Supplying a
word returning `Text` instead of `Int` must be rejected at the argument.

### P02 — Exact identity versus a shared contract: accept one, reject one

```let
let square = let x : Int do : Int return x * x end
let increment = let x : Int do : Int return x + 1 end
let SquareWord : Type = TypeOf with square
let yes : SquareWord = square
let no : SquareWord = increment
```

The last binding is rejected. Sharing a chain contract does not make the nominal identities equal.
No runtime type descriptor is introduced.

### P03 — Contracts are produced by words: accept

```let
let Unary = let A : Type let B : Type; A -> do B
let Transform = Unary with Int with Int
let identity = let T : Type let x : T do : T return x end
let n = 42
let a = identity(Int, n)
let b = identity(n)
```

Both results are `42`. `Unary`, its arguments, and its result have no runtime representation.
Deduction uses the checked type of `n`; replacing `n` by `42` must not change acceptance.

It must also preserve the position of effects, not evaluate an argument early to find its type:

```let
extern tick (x : Int) : Int
let staged = let T : Type let reached = tick(10) let x : T do : T
    return x
end
let explicit = staged(Int, tick(1))
let deduced = staged(tick(1))
```

With tick recording and returning its argument, both results are `1`; the combined trace is
`10, 1, 10, 1`. The erased Type argument is known before its following prelude, but the runtime tick(1)
operand is evaluated only after that prelude. Deduction must neither run it twice nor change the order.

### P04 — Dictionary requirements preserve concrete fields: accept

```let
let Policy : Type = { ok : Int -> do Int, err : Int -> do Int }
let success = let n : Int do : Int return n + 1 end
let failure = let n : Int do : Int return 0 - n end
let divide = let policy : Policy let n : Int let d : Int do : Int
    if d == 0 do return policy.err(1) end
    return policy.ok(n / d)
end
let checked = divide with { let ok = success let err = failure }
let answer = checked(84, 2)
```

Expected value: `43`. Specialization retains the actual field implementations and any runtime fields
they need. The shape requirement is not an existential dictionary ABI.

### P05 — Reached effects preserve stage order: accept and emit the trace

```let
extern tick (x : Int) : Int
let f = let a : Int let reached = tick(10) let b : Int do : Int
    return a + b
end
let answer = f(tick(1), tick(2))
```

With a host `tick` that records and returns its argument, runtime trace is `1, 10, 2`; result is `3`.
Compilation must not call the host. A discarded data result does not remove required ordered calls.

### P06 — Retained ownership versus activation ownership: accept

```let
host Buffer app_close
extern open_buffer (size : Int) : Buffer
extern buffer_size (buffer : Buffer) : Int
let inspect = let buffer own : Buffer let extra : Int do : Int
    return buffer_size(buffer) + extra
end
let run = do : Int
    let buffer = open_buffer(16)
    let prepared = inspect with move buffer
    let a = prepared(1)
    let b = prepared(2)
    return a + b
end
```

Assuming the host reports the requested size, `run()` returns `35`. `prepared` owns the buffer and
closes it once when its scope ends, not after each invocation. In contrast,
`inspect(open_buffer(16), 1)` acquires the fresh resource in its activation and closes it when that
invocation finishes. A fresh owned result need not name and then move a temporary binding.

### P07 — Consuming retained state needs receiver transfer

Local fragment, using the resource declarations above:

```let
let extract = let buffer own : Buffer let ignored : Int do : Buffer
    return move buffer
end
let prepared = extract with open_buffer(16)
let result = (move prepared)(0)
```

The proposed consuming invocation transfers the buffer into `result`; `prepared` is moved. Changing
it to `prepared(0)` is rejected because ordinary invocation borrows retained receiver state.
Direct `extract(open_buffer(16), 0)` is allowed because that buffer is newly activation-owned.
Its remaining chain requires ownership of the receiver. The plain requirement `Int -> do Buffer`
must not promise borrowed invocation of this retained state. The prefix-zero word can accept Own
Buffer as activation input; retaining that input changes the remaining receiver requirement. This
holds even if extract was supplied through a calling requirement before specialization. The checker
must derive the new prefix's requirement, not simply truncate an arrow.

Receiver ownership and the Own capability of a stage receiving such a word are separate positions;
their concrete contract spelling is open. A fresh `(extract with open_buffer(16))(0)` may transfer
its temporary receiver without a named-source move; the buffer is still owned exactly once.

### P08 — Persistent read dependency constrains escape and movement

Inside a local scope, let `inspect_read` have a Read Buffer stage followed by an Int stage.
After `let prepared = inspect_read with buffer`, `buffer` remains the owner. Calls through
`prepared` do not destroy it. Moving `buffer` alone while `prepared` remains in scope is rejected.
Returning `prepared` while leaving that local owner behind is rejected.

Constructing the owner and dependent inside one owning aggregate from the start allows returning
that aggregate under P09. This is not permission to move an already-borrowed standalone owner into
a new record while its dependent remains outside. Copying a pointer is not an ownership transfer.

### P09 — Closed owner transfer versus an outside dependency

```text
package owns counter and bump
bump captures package.counter

move whole package, inactive, no outside borrower  -> accept with preserved internal dependencies
move the Int counter as a value                   -> copy; the captured place remains live
extract a captured non-Copy field without restoring its place -> reject while its dependent remains outside that transfer
move package while an outside word captures it   -> reject
return only bump while destroying package         -> reject
return existing package owning both counter and bump -> accept if its dependency boundary is closed
```

Construct the group as an ordinary aggregate, for example:

```let
let package = {
    let counter mut = 0
    let bump = do : Int counter = counter + 1 return counter end
}
```

Initialization or transfer into the final destination must leave captures referring to destination
state. Test after returning from the constructor, not only while its stack frame is still alive.
The representation may use destination construction, relative access, or generated pointer repair.

### P10 — Nested access is a reborrow, duplicate access is not

```let
let counter mut = 0
let bump = do : Int counter = counter + 1 return counter end
let twice = do : Int let first = bump() return bump() end
```

A call of `twice` starting from zero returns `2`. Nested calls obtain authorized child access and
return it before the next use. Separately, supplying one place to two simultaneous `mut` stages is
rejected. Supplying provably disjoint fields may be accepted. Actual capture accesses participate
in overlap checking; merely retaining those captures does not activate their accesses.

### P11 — Record names do not create nominal brands

```let
let Point : Type = { x : Int, y : Int }
let Vector : Type = { x : Int, y : Int }
let Alias = Point
let p : Point = { let x = 10 let y = 20 }
let q : Vector = p
let r : Alias = p
```

All bindings are accepted. Point, Vector, and Alias describe the same structural type. This does not
identify distinct concrete words: P02 still rejects assigning increment to square's exact word type.
Aggregate construction uses the ordinary record form, with no branding operation.

### P12 — Exact arithmetic and expression composition

```let
let n = 9007199254740993
let same = 9007199254740992 == 9007199254740993
let pair = { true, true or false }
```

Expected: exact `n`, false `same`, and two true tuple members. A folded and runtime computation must
agree. The control split in the second tuple element must preserve the first element's temporary.

### P13 — Generic requirements use ordinary Type stages

```let
let Unary = let A : Type let B : Type; A -> do B
let identity = let T : Type let x : T do : T return x end
let twice = let T : Type let f : Unary with T with T let x : T do : T
    return f(f(x))
end
let int_identity = identity with Int
let answer = twice(Int, int_identity, 42)
```

The result is `42`. Binding T determines the requirement on f through ordinary application of Unary.
There is no separate universally quantified contract value. Each demanded instantiation checks its
body: identity's Read stage cannot silently become Own to return an arbitrary non-Copy argument.

A requirement is itself a description value and may be supplied to a Type stage. For example,
`identity(Unary with Int with Int, int_identity)` returns the same concrete word value. It does not
create a universal callable layout or erase int_identity's exact type.

### P14 — Contract requirements do not supply existential storage

```text
a field requirement f : Int -> do Int with concrete square supplied   -> accept
C entry requesting a record layout from only that open requirement     -> reject until concrete
runtime sum of the exact types of square and increment                 -> concrete tagged layout
runtime slot of unknown implementation with only Int -> do Int known   -> reject; no implicit vtable
```

A contract may travel as an erased construction-time value without supplying a runtime layout.
Obtaining that layout requires a concrete binding, not merely another alias for the requirement.

### P15 — Type-producing words do not brand structural results

```let
let Box = let T : Type; { value : T }
let OtherBox = let T : Type; { value : T }
let A = Box with Int
let B = Box with Int
let C = Box with Text
let D = OtherBox with Int
let a : A = { let value = 1 }
let b : B = a
let d : D = a
let bad : C = a
```

`A`, `B`, and `D` are the same structural type even though Box and OtherBox are distinct words.
Only the last binding is rejected: its field requires Text, not Int. Repeated application and aliases
do not introduce new identities for these record descriptions.

### P16 — A callback can reborrow an enclosing exclusive permission

```let
let counter mut = 0
let bump = let ignored : Int do : Int
    counter = counter + 1
    return counter
end
let apply = let f : Int -> do Int let target mut : Int do : Int
    let result = f(0)
    return target + result
end
let answer = apply(bump, mut counter)
```

Accept, with `answer` equal to `2`. Supplying `target` grants exclusive access to counter. Storing
bump in `f` retains its dependency but does not grant a second active access to counter. When `f(0)`
runs, the compiler proves that its capture reaches the same place and delegates a child Write loan.
The parent's use through target is suspended until the child finishes, then resumes for the addition.

This is static permission delegation, not runtime pointer comparison or a locking mechanism. It does
not merge two simultaneously promised exclusive slots or allow arbitrary callback reentry.

Required contrasts:

```text
update_two(mut counter, mut counter)                  -> reject: overlapping exclusive slots
apply retains a read view of target across f(0)       -> reject: conflicting live view
child requests Write from only an enclosing Read      -> reject: insufficient permission
child keeps active access beyond its permitted extent -> reject: escaping loan
later argument calls bump after an earlier Mut argument reserved counter -> reject: pending callee is not that call's ancestor
sequential sibling invocations without conflicting loans -> accept
```

Also check nested expression evaluation separately: starting from zero, `bump(bump(0))` returns `2`.
The outer receiver is obtained first, but its capture access must not be reserved ahead of evaluating
the inner call. Unknown provenance cannot substitute for the proof required by the accepted example.

### P17 — Type inquiries keep ordinary effects

```text
TypeOf with an existing Int binding          -> Int, no runtime descriptor
TypeOf with tick(1) in ordinary runtime code -> Int plus the runtime tick effect
the same tick expression inside an annotation -> reject: runtime work in a type-only context
TypeOf with an already moved resource place  -> reject: ordinary use of a moved source
```

If operand evaluation creates a temporary owned resource, it still needs its ordinary destruction.
Erasing the returned type value must not erase operand effects or cleanup.

### P18 — Semantic checking demand is not optimizer reachability

```text
unknown name in an uncalled local word                    -> reject during resolution
ill-typed body of an uncalled/unexported local word        -> deferred until instance demand
the same word referenced by a call in runtime if false    -> check and reject
valid runtime recursion with the same static instance key -> reserve one body identity
recursion producing unbounded new static instances        -> compilation resource-limit diagnostic
```

Generic and nongeneric local words follow the same demand rule. Exported words are not exempt merely
because there is no Let caller. A resource-limit diagnostic is not evidence that the source program
is ill-typed and is not an internal compiler bug.

### P19 — The same calling requirement can yield different escape obligations

Schematic fragment: assume host vocabulary Buffer and View, an owning `open_buffer` operation, and
concrete callbacks whose producer contracts describe the storage their returned views depend on.

```let
let produce = let f : Buffer -> do View do : View
    let buffer = open_buffer(16)
    return f(buffer)
end
```

Both of these callback behaviors can satisfy the stated calling requirement:

```text
callback returns a view into its supplied buffer -> reject this produce instantiation: local owner dies
callback returns a view into module-owned storage -> accept if that owner outlives the result and accesses are legal
```

The second result retains its module dependency; it is not lifetime-free. The contract guarantees the
argument type/capability, terminal kind, result type, and borrowed receiver use, not independence of
the result from every argument or capture. Specialization-dependent escape checking is intentional.

Likewise, two bound words may share an implementation and generated code but refer to different
owners. If one owner has a conflicting live view, a call using that word may be rejected while the
other is accepted. A code cache must not cache permission to invoke either bound value.

### P20 — A join must retain possible dependency origins

Local body fragment with a runtime condition, owned Buffers `a` and `b`, and `reader` having a Read
Buffer stage followed by an Int stage:

```let
let selected mut = reader with a
if condition do
    selected = reader with b
end
let taken = move a
let answer = selected(0)
```

Reject the move of a: selected may still depend on it. Its exact word type, implementation, and
initialized state agree across the branch; those facts alone do not discharge the dependency.
After an unconditional `selected = reader with b`, selected's own old contribution to a can end.
If another copy of the old selected value survives, that copy still prevents moving a.

The same rule applies to view loans and loop-carried dependencies, not only deferred captures.
Different implementations require a different check: a runtime slot initialized with square cannot
be reassigned increment merely because both satisfy `Int -> do Int`. Use an explicit sum.

### P21 — Callee preludes and later caller arguments have different ancestry

```let
let counter mut = 0
let bump = let ignored : Int do : Int
    counter = counter + 1
    return counter
end
let staged = let target mut : Int let reached = bump(0) let extra : Int do : Int
    return target + extra
end
let answer = staged(mut counter, 0)
```

Accept with answer `1`: the reached prelude executes in staged's activation and can delegate its
target permission to bump. Replacing the call with `staged(mut counter, bump(0))` is rejected: the
second argument executes in the caller while staged's target slot is reserved. It is not a child
use inside staged. Generated helper boundaries or inlining must not change either answer.

### P22 — Copy capture versus capture of a mutable place

```let
let constant = let x : Int do : do Int
    return do : Int return x end
end
let saved = constant(42)
let answer = saved()
let observe = do : Int
    let counter mut = 0
    let get = do : Int return counter end
    counter = 7
    return get()
end
let observed = observe()
```

Accept: answer is `42`, observed is `7`. The first word retains a copy of x, not a dependency on the
departed activation's slot. The second captures a mutable place and observes its replacement.
A captured immutable Copy word/view must also retain any dependencies already carried by its value.

Explicit owned initialization is different again. Using P06's host vocabulary:

```let
let keep = let buffer own : Buffer;
    (let owned = move buffer do : Int return buffer_size(owned) end)
let held = keep(open_buffer(16))
let size = held()
```

Accept with size `16`. keep's data terminal constructs a zero-stage word; its reached initializer
transfers buffer into that word's owned state. Returning held does not leave a dependency on keep's
activation. The buffer closes once when held's owning scope ends, not when keep or held() returns.

A word owning a mutable counter is not Copy merely because Int is Copy. A word retaining only a
permitted deferred Read dependency can copy that dependency without copying or owning its resource.

### P23 — Replacement distinguishes a place from its old value

Using P06's host vocabulary:

```let
let replace = do : Int
    let buffer mut = open_buffer(8)
    let size = do : Int return buffer_size(buffer) end
    buffer = open_buffer(16)
    return size()
end
let answer = replace()
```

Accept with answer `16`. Close the old buffer once at replacement, and the new buffer once at scope
exit. The method captures the buffer place; replacement does not destroy that place.

In contrast, if `prepared = inspect_read with buffer` retains a Read dependency on the old non-Copy
value, replacing buffer while prepared remains live is rejected. A host view of the old contents
also blocks invalidating replacement.

Separately, for an owned unborrowed local and an operation consuming and returning Buffer,
`buffer = extend(move buffer)` skips destruction of the already-moved old value. The returned value
is installed and eventually destroyed once. An RHS that leaves the old value live requires its usual
replacement destruction. Neither case can discard dependencies carried by the RHS or surviving copies.

### P24 — A call publishes stored dependencies

Local fragment: a and b are owned Buffers declared before selected, in the same scope. Reader has
a Read Buffer stage followed by an Int stage. The helper borrows its argument; it does not capture b.

```let
let selected mut = reader with a
let redirect = let source : Buffer do : Int
    selected = reader with source
    return 0
end
let ignored = redirect(b)
let taken = move b
```

Reject the move: selected now depends on b. Returning a dependency-free Int (or Unit) does not erase
the helper's store. The same answer is required with cached code and when the helper is inlined.
A later unconditional replacement of selected can end its own contribution, but not another copy's.

Reject instead at installation if a helper stores a dependency on its local Buffer into this outer
slot. Likewise an export cannot retain a call-bounded host argument in module storage without an
adequate declared extent. A hoped-for clearing call is not an escape proof.

### P25 — Opaque mutation may invalidate a retained value

Local fragment, with reset declared as an opaque Mut operation and no preservation guarantee:

```let
extern reset (buffer mut : Buffer) : Unit
let buffer mut = open_buffer(8)
let prepared = inspect_read with buffer
reset(mut buffer)
```

Reject: reset may destroy the old Buffer and install another. Prepared's deferred value dependency
blocks that invalidation even though it is not an active Read view. Ignoring reset's Unit result
does not change this answer.

A contents-only operation with an adequate value-preservation contract may be accepted while
prepared is inactive. A conflicting live host view still blocks its write. Conversely, a word that
captures only the stable buffer place may follow a permitted replacement; the call's post-state
must describe the new contents and cannot retain the old occupant as a known identity.

### P26 — Application temporaries have observable cleanup order

Using P06's inspect and Buffer operations, with tick recording and returning its input:

```let
extern tick (x : Int) : Int
let make_reader = let size : Int; inspect with open_buffer(size)
let add = let a : Int let b : Int do : Int return a + b end
let answer = add(make_reader(8)(0), tick(1))
```

Answer is `9`. With allocation/destruction logging size, the relevant trace is
`open(8), close(8), tick(1)`. The fresh receiver belongs to its invocation's application region and
closes after that borrowed invocation, before the enclosing add evaluates its second argument.

Also require one cleanup order across reached preludes and anonymous arguments:

```let
let staged_drop = let first own : Buffer let middle = open_buffer(2) let last : Buffer do : Int
    return 0
end
let zero = staged_drop(open_buffer(1), open_buffer(3))
```

The trace is `open(1), open(2), open(3), close(3), close(2), close(1)`. The later Read argument's
temporary dies before the earlier prelude and Own input. Source ordering, not generated C frame
boundaries, determines those cleanup positions.

Naming it first with `let held = make_reader(8)` instead keeps its Buffer until held's binding
cleanup. A fresh Read argument in `inspect_read(open_buffer(8), 0)` also closes at that application's
completion. `inspect_read with open_buffer(8)` is rejected: its partial result would depend on a
temporary destroyed at the with boundary. No implicit lifetime extension or owning Read capture occurs.

If a borrowed invocation returns a view into its fresh receiver's owned storage, that view cannot
leave the application even just to feed an enclosing consumer. Naming the receiver can make the
same use legal when its extent and access obligations suffice. Returning an owning aggregate that
contains both owner and dependent is a different, explicitly ownership-transferring case.

### P27 — A restoring Mut take can implement exchange

```let
let exchange = let slot mut : Buffer let fresh own : Buffer do : Buffer
    let old = move slot
    slot = move fresh
    return move old
end
```

For an otherwise unborrowed mutable buffer,
`let old = exchange(mut buffer, open_buffer(16))` is accepted. The caller's buffer position holds the
new value; old owns the previous value. Neither is destroyed by exchange, and each is destroyed once
at its eventual owning position. No swap primitive or implicit ownership duplication is needed.

Required contrasts:

```text
return before restoring slot                       -> reject: outstanding restoration obligation
read/borrow slot while it is vacant                 -> reject: moved place
take a Read parameter's non-Copy value              -> reject: no owning or exclusive writable permission
take while a dependency protects the old value      -> reject even if restoration is planned
deferred capture of the stable slot only            -> may remain; no access while vacant, then follows replacement
exchange contents of a writable retained field      -> borrowed receiver may suffice if restoration is proved
extract an immutable retained field without refill  -> still requires consuming receiver (P07)
swap through two proved disjoint Mut slots          -> each take/store must be legal and both slots restored
supply one place to those two Mut slots             -> still reject simultaneous exclusive slots
```

No recoverable unwinding is assumed. Checking all normal exits and nested delegation boundaries is
part of the proof obligation, not something established by this positive example.

### P28 — Replacement does not reorder cleanup positions

```let
let run = do : Int
    let a mut = open_buffer(1)
    let b = open_buffer(2)
    a = open_buffer(3)
    return 0
end
let answer = run()
```

Answer is `0`. With allocation/destruction logging size, require
`open(1), open(2), open(3), close(1), close(2), close(3)`. Replacement closes the old a, but the new
occupant retains a's earlier cleanup position. Cleanup of b therefore precedes cleanup of the new a.

For a conditional replacement, cleanup still visits b then whichever value occupies a. No dynamic
destruction-order flags are introduced. A newly installed dependency must also fit that fixed order;
reject an incompatible installation rather than silently moving its holder's cleanup position.
A destructor may not repopulate a position already being cleaned up or already ended. Its effects on
other surviving places still belong in the enclosing call's final post-state.

## 10. Validation and migration

Keep the current implementation working. Turn these proposed witnesses into a separate acceptance/
rejection corpus only when the semantics and grammar they exercise are specified. Existing checks
against DESIGN.md do not validate this proposal.

Require runtime answers, ordered traces, destructor counts/order, accepted and rejected uses, and
post-return lifetime tests. Include multiple module instances, exact arithmetic, alias/shadowing
cases, deduction from bindings and call results, same-layout distinct word types in sums, and IR
verification. Use native sanitizer tests for capture/storage failures; compiling successfully is not
enough.

Migrate by making each existing semantic decision single-owner and carrying its result forward.
Preserve an end-to-end working slice. Do not independently patch erasure, injection, application, or
ownership policy into every consumer, and do not mistake fewer pass names for a better compiler.
