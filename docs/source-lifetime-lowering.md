# Source lifetime lowering: concrete compiler contract

**Status: approved detailed binding; implementation in progress, not qualified.**
The direction and removal-first order were approved at `fd81f206`; the removal
checkpoint is `2b46dd89`. The user subsequently approved implementing this concrete
binding and its cross-file scope. This document defines the target, not evidence of
completion. WORKLIST O03–O08/E01/E02 is the only delivery ledger.

This proposal preserves ownership §2.1: a root escaping its defining activation is
counted from creation. It does not introduce an uncounted heap, change source cycle
legality, or change the six C lifetime bindings. Reference transport is not a new
holding. The ordinary ABC allocator and continuations remain authoritative.

## 1. Three different objects

The compiler must not collapse these into one type predicate:

1. **Root:** the allocation containing the addressed place. Projections preserve it.
2. **Carrier:** the data needed to use a reference/slice/callable value. Copying this
   data does not change a count.
3. **Holding:** one responsibility to keep a counted root alive and eventually
   release it. It occupies an actual concrete owner-pointer field, not a VM register
   or an entry in a runtime registry.

A carrier may contain an owner pointer as a *borrowed capability*. That pointer is
not a holding. Cleanup visits actual holding fields only. Conversely, a holding can
protect several local carrier aliases; it is not duplicated for each alias.

The following record definitions are compiler data, not serialized runtime layouts.
They refer to original source nodes/points; they contain no scalar evaluator.

## 2. Compiler records

Reuse `Borrow.Point`, `Borrow.Path`, `Borrow.Location`, `Ownership.Root`, existing
call contexts and the original IR value/storage IDs.

```text
UseId = (Point, operand_ordinal, component_path)
LoanId = (definition_point, original_value_binding, component_path)
       | (parameter, component_path)

Guard =
    Module(root)
  | Frame(root, activation)
  | Input(parameter, component_path)
  | Holding(HoldingId)

HoldingId =
    Allocation(root)
  | Result(call_point, result_resource_ordinal)
  | Field(storage_location, contents_version)
  | Preserve(loan_or_join_component)
  | ConsumedInput(input_group)

LoanAlternative = {
    root: Ownership.Root,
    guard: Guard,
    locator: source_location_at_read | none
}

LoanFact = {
    alternatives: set<LoanAlternative>,
    active_cases: enclosing (carrier, component_path, tag) conditions,
    capability_origin: original_operand_or_definition,
    needs_capability: boolean
}

SiteFacts = {
    defines: set<LoanId>,
    uses: set<LoanId>,
    writes: set<versioned source locations>,
    calls: bound source-call alternatives,
    successors: original CFG edges
}
```

The original value binding distinguishes multiple results defined at one call point;
equal result types and component paths must not merge their loan identities.

`locator` identifies the actual protecting owner field, not the referent address.
For `saved = box.child`, it may identify `box.child`'s owner field. For
`Ref(box.embedded)`, the protected root is `box`, not the embedded field.

A mutable location gets an entry version, a version at each definition/write, and
an interned join version where incoming versions differ. These are memory-provenance
versions for reference contents only, not a second value IR. Dynamic array indices
retain the existing conservative alias class unless the analysis proves disjointness.
An exact move locator additionally refers to the already-evaluated index/base at the
original read. It must not reread a subsequently mutated index or base variable.

The canonical version IDs are `Entry(location)`, `Written(point, location)` and
`Join(point, location)`. Incoming-version edges live in a separate compiler map keyed
by these IDs, so loop joins do not construct recursively interned ASDL values. Sets
use the existing interned-ASDL-keyed Lua tables; boundary lists are sorted before
interning. No runtime version numbers or per-iteration records are introduced.

A loop write always invalidates the preceding contents version. Reaching the same
static definition on another iteration does not mean the same allocation. In
particular, equal `Recurring` source names are never independent protection evidence.

### 2.1 Decisions attached to source sites

```text
SiteDecision = {
    borrowed_uses: map<UseId, protection witnesses>,
    before: ordered decisions,
    after: ordered decisions,
    edges: map<successor, ordered decisions>
}

Decision =
    Direct(ordered actions)
  | HasHolding(holding, present_decisions, absent_decisions)
  | SameRoot(capability, holding, equal_decisions, unequal_decisions)
  | CaseIs(carrier, path, tag, active_decisions, other_decisions)

LifetimeAction =
    Allocate(root, destination_holding)
  | Acquire(root_capability, destination_holding)
  | Transfer(source_holding, destination_holding)
  | Release(holding)
```

These annotations are not executable IR and are never interpreted at runtime.
`placement.lua` translates them to ordinary existing IR calls/loads/stores at the
associated source point. A `HasHolding`/`SameRoot` decision tests once and emits
ordinary IR control flow; it does not retest a source slot after a preceding move has
cleared it. Existing source branch/tag decisions retain their existing CFG edges.
No decision bytecode, runtime table or generic lifetime helper is introduced. No
action is inferred there merely from `Ref`, `Slice`, `View`, record, array or sum
membership.

Each `Acquire` records a diagnostic reason and source witness: independent escaping
store, live snapshot across invalidation, or another explicit retention boundary.
An unresolved root/call contract is an admission error, not an acquisition reason.

A retention event must retain its destination component/location as well as the
holder/target roots; the current root-only holding event is insufficient. Allocation
placement and cycle checking still use the roots. Site decisions use the actual
locations, versions and source operands.

A transfer requires both (a) a real existing holding and (b) a usable, still-live
address for its source field. Knowing that two values have the same referent type,
allocation family, or even root is not proof that they own the same holding.

## 3. Carrier and storage layouts

```text
Reference carrier:
    data: address
    capability: address, only if demanded by a later lifetime operation

Slice carrier:
    data, length
    capability: address, only if demanded

Callable carrier:
    code, environment
    capability: environment-root address, only if demanded

Actual retained reference field:
    data: address
    holding: address                 # cleanup releases this field
```

If a retained field supplies a carrier, its `holding` also supplies the carrier's
capability; copying those bits does not acquire. A borrowed carrier with a capability
has the same two address bits but a different compile-time contract: cleanup does
not release it. There is no runtime borrowed/owned flag attached to every reference.

An addressable object's layout is chosen from its complete bound source contract
before construction. It never changes when somebody borrows the object. In particular,
a borrowed pointer to an object with retained fields still addresses that object's
actual retained-field layout.

Frame-local value carriers are not all collected into an ownership frame. They use
ordinary existing value/place lowering. The cleanup frame contains only real root,
result, preservation and transaction holdings. Its header remains the existing
16-byte `{previous, drop}`. If there are no such holdings, emit neither that header
nor enter/leave calls nor an empty C-entry callback.

Escaping mutable objects retain per-field holdings where the source contract requires
independent field lifetimes. Two independently replaceable fields are not merged
merely because their initial values happen to name the same root.

Packed tags retain the existing tag/aligned-union algorithm. Borrowed carrier shapes
and retained storage shapes can differ: inserting an actual holding at a storage
boundary constructs that destination's representation directly. There is no universal
fat form followed by a normalization pass, nor memory allocation just to repack bits.

## 4. Ordered analysis and guard validity

`access.lua` supplies the original CFG, stable points, reference definitions/uses,
versioned contents and call substitutions. It publishes converged facts, not an
intermediate worklist iteration. A conditional trap has its normal-success successor
unless its condition is statically always true; failure exits are separate.

For reference-bearing values and storage versions, compute ordinary backward liveness:

```text
LiveOut[p] = union(LiveIn[s] for each normal successor s)
LiveIn[p]  = Uses[p] union (LiveOut[p] minus Defines[p])
```

Uses include projections, variant payloads, captures, returned borrows and values
transported into later-readable storage. Direct place reads/writes and callable
invocations also use their containing root's protection even when their result is a
scalar: `p.x` must not disappear from root liveness just because it returns `U32`. A tag test does not invent a holding. Payload loan/capability operations are guarded
by all their enclosing `active_cases`; an inactive scalar alternative is never read
as an owner pointer, even when its bits resemble one. A `CaseIs` decision tests the
already-produced packed tag, not a replay of the source expression.
Calls use substituted argument/result dependencies and effects. Exceptional exits
require cleanup of actual holdings, not preservation of loans for nonexistent uses.

Guard validity is a forward analysis over the same graph:

- Module/active-frame guards last for their declared extent.
- An input loan uses the caller's protection contract, not a new callee holding.
- A holding guard lasts until its slot is moved, cleared, overwritten, or its
  containing storage can be destroyed.
- A field guard also requires its containing allocation to remain live.
- A call may invalidate field guards according to its substituted write/release
  effects. A non-retaining call is not automatically a non-mutating call.
- At joins, retain loan alternatives with their own guard witnesses. Do not use the
  union of guards to claim that any particular guard exists on every path.

Source cycle checking remains the existing checker over source obligations. This
lowering does not make a previously rejected escaping self-cycle legal by declaring
its own disputed edge to be a guard.

### 4.1 What happens when a live loan loses its guard

For each guard invalidation, intersect its dependent loans with `LiveOut`:

```text
if no dependent loan survives:
    ordinary release/overwrite
else if another independent guard already covers every surviving use:
    change compiler witness; emit no count operation
else if the dying holding has an exact usable locator:
    transfer it into a concrete preservation holding
    rebind the surviving local loans to that holding
else:
    acquire the selected loan's root into a preservation holding
    before the potentially invalidating operation
```

The last branch needs an established root capability, a still-valid protection at
the acquisition point, and the existing acyclicity proof. It cannot resurrect a root
after invalidation. A frame guard ending while an access escapes requires the original
counted placement decision from creation; it is never repaired by retaining a frame
address. It does not retain every root in an abstract may-alias set: it retains the
actual selected root carried by that value. Aliases proven to share that one loan
use the same preservation holding.

A direct `box.child = ...` can transfer the dying old field holding to protect a
saved read. Across a call which may read and then replace that field, the caller
cannot clear the field in advance. It establishes the saved read's independent
protection before the call instead. This is a concrete use of refcounting when the
simple existing-guard rule cannot cross the boundary, not a retain on every read.

When an uncertain alias is the only reason for invalidation at a direct store, the
emitter can compare the captured root capability with the old destination root and
perform preservation only on a match. This is an ordinary pointer comparison at
that store, not a runtime alias graph or descriptor interpreter. An acquisition is
still never based on pointer equality as evidence that an otherwise dead root lives.

A local allocation/result holding may also move into a new retaining destination
while local aliases remain in use. Rebind those loans to the destination's actual
holding and check its subsequent invalidations by the same rules. Do not require a
single textual use. This is valid only if the old *holding location* has no independent
obligation to remain owning. An ordinary subsequently readable retained field cannot
simply have its owner metadata cleared; consuming its value needs a separate proof.

The root's data address/capability is captured while the allocation is live. Later
source place accesses must not reload a cleared holding slot to reconstruct that
address after a transfer.

A preservation holding lives through its dependent loans. Release it on normal edges
after their last demand; the linked cleanup record handles earlier failure. It is
not a second registry: it is the one concrete field owning that retained/transferred
root. The carrier copies remain non-owning bits.

## 5. Joins and loops

Where predecessor edges deliver different holdings for the same surviving logical
value, allocate one nullable holding field at the receiving join. Each owning edge
moves into it. Borrowed edges leave it null and preserve the corresponding external
loan dependencies. No retain is inserted just to reconcile two predecessor names.

If the receiver genuinely requires independent ownership on all paths, borrowed
edges acquire there and owning edges transfer. Acquisitions therefore occur on the
edges needing them, not indiscriminately before the branch.

Loop-carried protection belongs to the loop-carried source binding/component, not
an endlessly growing list of iteration roots. Its slot is zero-initialized before
the loop; incoming owning edges transfer into it. Before reusing a call-result,
allocation or preservation slot on the next iteration, treat that reuse as a kill
of its previous contents and apply §4.1. Never skip this because the source IDs match.

If an old iteration's value survives in another source binding, that binding carries
its protection. If values accumulate in an actual array/escaping object, its concrete
fields carry the required holdings. No per-iteration runtime slot registry is added.

### 5.1 Termination of the compiler worklists

The domains are finite: original source points, component paths, existing finitely
folded call contexts, write/join versions and guards associated with those sites.
Liveness and provenance use set union; capability demands and required preservation
sites grow monotonically. Join protection slots are interned by receiving source
binding/component and CFG join, never by iteration number.

The sequence is:

1. Converge existing provenance/retention/cycle facts.
2. Solve loan liveness and guard invalidations; introduce required preservation and
   result/join holding sites.
3. Propagate owner-capability demands backward through the original reference-producing
   operations and call interfaces until no demand changes.
4. Bind concrete contracts and choose eligible transfers/consuming variants. Recompute
   a variant's local decisions under that binding; do not reuse stale decisions from
   a different input ownership mode.
5. Check every live loan at every use has a valid independent witness, and every actual
   holding has a defined normal transfer/release and failure-cleanup location.

No step invents extra call-depth, iteration or specialization-count budgets. Recursive
family folding is for termination, not proof of lifetime or identity. An unresolvable
binding rejects with its source witness; it does not select a fat/counting fallback.

## 6. Concrete private call contracts

```text
InputContract = {
    carrier_shape,
    referent_layout,
    mode: Borrow | ConsumeSlot | OfferSlot,
    capability_requirement,
    normalized_root_and_guard_relations
}

ResultContract = {
    carrier_shape,
    borrowed_from: set<relative external guard paths>,
    resources: zero or more nullable holding fields,
    carrier_to_resource_relations
}
```

A relative guard path can name an input root or the contents of a field reachable
through an input. A borrowed result of `parent.child` depends on that field's value
holding, not just on the parent allocation. Entry-content and return-content versions
are distinct. The caller binds these paths against the already-computed call state.

### 6.1 Borrowed inputs

Arguments transport carrier bits. The caller keeps the required protection live
through the call. If the callee can invalidate that protection, §4.1 establishes
independent protection before entry. Returning a borrow adds the result's uses to
the originating loan's liveness; it does not create a holding in the callee.

An identity function can take one address and return one address. No cleanup record,
result holding or retain is involved. A function that may independently store its
input needs the root capability as well; its parameter itself still does not own it.

### 6.2 Consuming inputs

Generate a consuming variant only when it eliminates an actual acquisition and the
caller can relinquish a real holding, including its outstanding borrow obligations.
Outstanding borrows are permitted only when the bound callee contract guarantees a
specific surviving result/external-field guard for them on every successful return;
otherwise the caller must retain its protection. Failure has no continuing caller
uses. Merely observing that the argument expression has its last textual occurrence
is insufficient.
Do not generate consuming versions of read-only functions merely because an argument
happens to have a last use.

The caller passes ordinary carrier data plus the address of the actual holding slot.
It does **not** clear the slot before `CALL`. Callee stack-limit/entry failure therefore
leaves the holding visible in the caller's cleanup record.

The callee may move from that slot into a concrete destination. Successful return
requires every consumed input slot to be null: it was either transferred or released.
On failure, untouched slots remain covered by caller cleanup; moved holdings are
covered by their destinations. The callee must not register the caller slot a second
time in its own cleanup record.

Slot addresses must remain valid through their last callee use. For this binding,
consume slots are caller-frame/result storage, represented as actual `InPlace`/
`BorrowArg` transport. A heap-field holding can first be moved to such storage only
if source alias/effect analysis proves that consuming it does not change a subsequently
read source value. Otherwise use the borrowing contract and acquire where needed.

Multiple arguments backed by one identical holding pass one consume slot, with
explicit formal-to-slot bindings. Two different holdings of the same root are not
collapsed. These are different cases even when the owner pointer bits are equal.

A consuming slot in the current frame prevents a tail call which would retire that
frame. No ownership is left only in transient argument registers across a fallible
call boundary.

`ConsumeSlot` guarantees that a counted input root is actually held in that slot.
A null slot may denote a statically permitted non-counted module root; it cannot
silently denote a borrowed counted root.

`OfferSlot` handles the concrete mixed-result case: the caller has a nullable holding
slot and the value may instead borrow an independently protected root. It passes the
data, demanded capability and slot address under one fixed signature. Non-null offers
can transfer; null offers borrow under the caller's existing protection. At a real
retaining store, emit `HasHolding(slot, Transfer, Acquire(capability))`. Successful
return leaves the offered slot empty. The same outstanding-borrow and slot-liveness
requirements apply as for `ConsumeSlot`.

Do not normalize a null offer by acquiring in the caller merely to force a consuming
ABI. That could move overflow ahead of an allocation or trap inside the callee and
create an unnecessary holding on a non-retaining branch. The callee makes the choice
at the actual retaining source operation. This is an ordinary conditional transfer
at that operation, not a runtime dispatcher choosing between two function ABIs.

### 6.3 Results, including borrowed/fresh joins

**Result data stays in ordinary ABC cells. Only actual holdings need caller-owned
storage.** Do not restore the old all-results-in-an-owning-record convention.

Origin relations are compile-time metadata. A known single-input origin need not
return its capability: the caller can recover it from its captured argument binding
when required.

For each possible outgoing resource role, append one `InPlace(OwnerPointer)` argument
naming an actual caller-owned holding field. The caller initializes that field to null
and makes it cleanup-visible before the call. These are direct field addresses, not
a runtime vector or descriptor. Keeping the addresses separate permits a nested
constructor to bind resources directly to nonadjacent final fields without a temporary
result object or a new function clone for each byte offset.

Logical value results still use the existing independent CALL/RET banks and existing
large-result rules. Environment argument zero and the ordinary ABC hidden-result
convention keep their existing roles. Physical signature limits still apply; there
is no boxing fallback for a signature which cannot be encoded.

For one reference which may borrow `p` or deliver a fresh allocation:

```text
extra input:
    out_held: InPlace(OwnerPointer)  # *out_held is null on entry
ordinary results:
    data: address
    capability: address, only when needed

borrowed return: return p.data [, p.capability]; leave *out_held null
fresh return:   move initial holding into *out_held; return new_data [, new_root]
```

There is no ownership-kind tag. The existing null-slot cleanup convention suffices.
If every return transfers the same result holding role, the caller can load its
capability from that field; do not also return a duplicate capability cell. Thus a
fresh-reference result needs one actual owner slot and one data result. Borrowed
identity needs one data result and no owner slot. The genuinely mixed case may need
one actual owner slot plus two ordinary result cells. It does not increment the
borrowed path merely to force a uniform owning result.

For multiple results, one identical outgoing holding is transferred once even when
several carriers borrow it. Resource roles are canonicalized in result/component
order. Alternative returns can leave resource fields null. Distinct existing holdings
are not merged merely because their roots may compare equal. Different output roles
must bind disjoint slots, and output slots must not alias live consumed-input slots.

Concrete examples, with `i` denoting the integer bank kind and `a` the address kind:

```text
borrowed identity:           a -> a
leaf(n), fresh reference:   ia -> a       # n, address of result owner slot
mixed choose, cap needed: aaia -> aa      # p.data, p.cap, flag, owner-slot address
```

These are private function signatures, not new module or instruction encodings.

A callee may allocate directly into a caller result holding when that is the proved
final sink, the slot starts empty, and all later construction failure can clean it.
Otherwise it uses a real local root holding and transfers on return. Both paths
start the allocation at count one and require zero extra retain for the return.
If a result is built directly inside a tagged destination, the caller must establish
the enclosing active tags/null holding fields before the call, or instead supply a
real independently cleanup-visible holding field. A slot invisible to cleanup under
the current tag is not a valid output binding.

## 7. Instance identity and recursive binding

Concrete function identity is:

```text
(source function id,
 input carrier/referent layouts,
 consume-slot partition,
 result contract,
 local allocation-placement mask,
 canonical lifetime-decision signature)
```

The last signature records code-relevant alias/protection relations, bound call
contracts and site decisions, renamed to formal positions and local source sites. It does not include incidental
caller names, runtime addresses, full call strings or concrete allocation identities.
Two factory calls can therefore remain distinct roots in the proof while sharing
identical machine code. A changed alias/protection contract cannot accidentally reuse
an incompatible realization.

Do not require the completed body signature in order to discover a recursive call.
The provisional request key is `(source function, normalized boundary root/guard
relations, formal callable bindings/effects, input modes/layout constraints, result
capability demands)`. Callable bindings distinguish, for example, a callback which
captures a local point from one which only reads it, even when their source types are
equal. They come from the existing checked call contexts, not a new body evaluator.
Create/intern
these requests first and attach recursive edges to an existing request. Solve its
call SCC's capability/layout constraints by monotone union. Then compute the concrete
site decisions and the final code-deduplication key above. Repeating a request is not
another clone, and a provisional key is not permission to emit an incomplete body.
Pointer-indirected recursive layouts are canonical finite layout graphs, not recursively
expanded trees.

Emission is rooted in requested exports/entry functions and referenced code identities.
An unbound private definition remains a checked source template; it is not emitted
under an invented universal owning ABI. Raw lowering which explicitly requests such a
function must supply/establish a closed contract or reject. Source artifact `.functions`
continues to identify the checked source graph, not the list of machine instances.

For a known indirect target set, all selected target realizations use one contract
fixed for that callable value and all of its uses, not a different ABI guessed at each
invocation. Unify demands before emitting its `.codeaddr` identity. Use a consuming
or offering indirect contract only when every bound use satisfies its slot/protection
requirements; otherwise its inputs borrow.
Result-resource slots use the union of possible resource roles; borrowed paths leave
them null. Do not retarget an existing callable at invocation time. There is no runtime
ownership-mode dispatcher or forwarding adapter from the old ABI. Unknown owning callable/foreign/public contracts remain
closed rather than being guessed.

## 8. Store, move and failure algorithms

The four actions have these concrete bindings:

```text
Allocate(root, h):
    alignment = max(owner_header_alignment, payload_alignment)
    payload_offset = align_up(32, payload_alignment)
    bytes = align_up(payload_offset + payload_bytes, alignment)
    source_alloc(&h, bytes, alignment, drop_entry)
Acquire(cap, h):
    source_hold(&h, cap)
Transfer(s, d):
    ordinary address loads/stores in the non-failing window below
Release(h):
    source_clear(&h, single_owner_slot_drop_entry)
```

The payload offset is a compiler constant, not a new header field; it is 32 for the
currently admitted source layouts. Root-data addressing and its concrete drop callback
must use that same offset.

Use the retained concrete drop emitter to generate/cache the single-slot entry. It
receives the existing explicit context/object C ABI and enqueues via `source_drop`;
it does not use source TLS or recursively drain. For a proved-empty slot, emit no
release. For a nullable holding, guard an individual early release with `HasHolding`
when its absence can be known only at runtime. Scope exit uses the one actual frame
callback through `source_leave`, rather than a separate call per frame field.

Initialize actual frame holding fields before `source_enter`; acquire nothing before
that frame is linked. An optional result from a call that may allocate needs its
caller cleanup linked before the call even on executions where the result eventually
borrows. This can cost an empty cleanup traversal on that path, but not an acquisition;
the proposal does not disguise it as zero runtime overhead.

### Empty destination

- Borrowed carrier: ordinary value stores, no lifetime call.
- Transferable holding: move directly into its actual destination field.
- New independent holding: acquire directly into its initialized, cleanup-visible
  destination. Do not invent a second scratch object just because the value is tagged.

### Replacement

1. Evaluate/capture incoming value bits and required capabilities once.
2. Identify actual incoming holdings, destination holdings, outstanding loans and
   storage overlap using the source facts.
3. Complete required fallible acquisitions before changing the old destination.
   A single independent slot replacement with no surviving old loan uses the existing
   `source_hold`/`abc_owner_replace` directly. Its equal-owner case does not increment.
4. Preserve old holdings needed by surviving loans. Move a dying known field holding
   where possible; do not release it and then try to retain its former pointer.
5. Commit value stores and ownership transfers; clear moved source fields.
6. Release superseded holdings which protect no remaining use.

A real multi-holding, failure-atomic replacement uses a concrete incoming transaction
record. Each successful acquire immediately fills its actual owner field. The old
value remains intact until all acquisitions succeed. Failed partial construction drops
only those fields. This is the narrow remaining reason for acquisition scratch.

Overlapping source/destination storage is not treated as a disjoint move. If destroying
the destination could destroy the source slot, first move the source holding into a
cleanup-visible temporary holding, then destroy the old destination and move into the
final slot. No extra count is needed. If a stable source locator cannot be established,
use an actual acquire before destruction rather than a speculative move.

Self-assignment of the same value/holding has no lifetime action. Dynamic equal-root
single-reference replacement can update data bits without a count change; it must not
confuse different interior data addresses with different owner identities.

### Non-failing move window

```text
root = load source_slot
store destination_slot = root
store source_slot = null
```

The destination must be empty. No call, branch, checked operation, dynamic allocation
or continuation transfer may appear between the two stores. Slot addresses and value
bits are evaluated first. Ordinary function entry/call capacity checks cover the static
A/B/C requirements; materialization must not grow C storage in this window. The emitter
must not place a label or resolution boundary inside it. Backend qualification must check that lazy preparation/capacity boundaries do not split it.
An unresolved source/destination alias is not permission to assume this window valid.

### Tagged construction

For actual held fields inside a union, clear the new alternative's owner storage before
publishing its tag, and publish the enclosing tags before any fallible acquisition.
Inactive scalar bytes must never become apparent owners. Pure carrier construction,
matching and extraction use packed cells and the approved bitcasts without any holding
operation. The retained concrete drop emitter visits only active actual holding fields.

### 8.1 Worked state transition: saved child

After `saved = p.child`, let `r1` be the old child root:

```text
p.child.holding = r1       # real count contribution: 1
saved.data      = old_data
saved protection: Field(p.child, version_0)
```

Evaluate `leaf(2)` before changing that field. Its initial holding is visible in a
caller result slot `new_h`:

```text
new_h = r2                # initial contribution: 1; no retain
saved preservation slot old_h = null
```

For a direct assignment with no remaining need for the old field contents:

```text
old_h = p.child.holding; p.child.holding = null
p.child.data = new_data
p.child.holding = new_h; new_h = null
# saved now borrows under old_h
read saved.data.x
release old_h at its last demand
```

All stores in each transfer window are non-failing. Initial allocation holdings are
moved, not incremented. A failure allocating `r2` happens before these moves, so
`p.child` is unchanged and the existing cleanup still sees `r1`. A later failure sees
`r1` in `old_h` and `r2` in the child field, exactly once each. Destruction of `p` must
not destroy `old_h`; they are separate actual holdings after the assignment.

### 8.2 Worked state transition: mixed result

Caller has a live guard `gp` for `p` and initializes `out_h = null`. Callee returns
`data, cap` and possibly fills `out_h`:

```text
branch borrow: out_h = null, data = p.data, cap = p.cap
branch fresh:  out_h = r,    data = r.payload, cap = r
```

A read-only consumer uses the returned data under `gp` or `out_h`, respectively.
There is no acquisition on either path. If the caller later needs an independent
escaping field and cannot transfer `gp`:

```text
HasHolding(out_h,
    present: Transfer(out_h, destination.holding),
    absent:  Acquire(cap, destination.holding))
```

The ownership choice is tested before either action. It is not a `Transfer` followed
by a test of the now-cleared slot. For a fresh result this adds zero counts; for the
borrowed result it adds exactly the independently required holding. A module capability
can be null and requires no count. The source data is still returned through A/B cells,
not copied through a mandatory result-value memory record.

## 9. File/API changes

The compiler entry points are proposed as follows:

```text
Access.analyze(functions)
    -> queries, access_summaries, statistics, flow

flow.functions[fn_id] = { entry, nodes[Point], statement_at[Point] }
flow.contexts[context_id] = {
    fn_id, formal_bindings, loan_facts, contents_versions, call_edges
}

Ownership.analyze(functions, queries, flow)
    -> ownership[fn_id] = {
         summary, cycle, spans, lifetime_template
       }

Ownership.bind(checked_program, entry_requests)
    -> bound = {
         source=checked_program,
         entries, instances, call_bindings, layout_contracts
       }

Placement.program(bound)
    -> physical_program = {
         phase='physical-program', source=bound.source,
         functions, modules, foreigns, lifecycle
       }

Check.program(physical.functions, physical.modules, physical.foreigns, true)
```

`flow` contains only lifetime-relevant uses/places and references to original nodes;
it does not clone arithmetic or retain a second scalar program. Scalar-only functions
with no relevant access have empty lifetime templates. The existing access worklist
must propagate changes affecting these facts before returning them.

`Ownership.bind` substitutes already-checked formal contracts and selects concrete
instances; it must not call `Access.analyze`, replay source computations, or silently
recheck a mutated source graph. The returned binding is separate from the immutable
checked program. Original allocation identities remain distinct in proofs even when
their normalized code contracts deduplicate.

`Placement.program` is a new implementation at the old responsibility boundary, not
an alias to the removed code. It accepts a completed binding, not a source graph from
which to guess ownership. The physical graph can reuse unchanged immutable functions;
that is decided by actual bound types/actions, not by a whole-function ownership mode.

| File | Concrete responsibility |
| --- | --- |
| `frontend/ir.asdl` | Canonical source lifetime fact/contract records above; no new executable ownership instruction |
| `frontend/let/schema/ir.lua` | Generated embedding of the schema |
| `frontend/let/access.lua` | Publish converged original-point CFG/use/version/call facts; extend existing worklist rather than build a second evaluator |
| `frontend/let/ownership.lua` | Solve liveness/protection/capability demands, source-site actions and normalized instance contracts; retain source root/rank/cycle validation |
| `frontend/let/program.lua` | Own the completed source facts/templates; never attach mutable proof state to shared functions |
| `frontend/let/compiler.lua` | Supply the existing export/entry requests to concrete binding; raw IR still explicitly analyzes first |
| `frontend/let/placement.lua` | Bind already-checked contracts, emit one physical graph from site decisions, and use the retained concrete drop generator; no type-based lifetime inference |
| `frontend/let/layout.lua` | Canonical concrete carrier/storage/result layouts and offsets; no global owning width |
| `frontend/let/check.lua` | Check physical IR/signature consistency, not re-infer source ownership |
| `frontend/let/abc.lua` | Emit ordinary ABC from that physical graph with correct call/return banks, `InPlace` liveness and code identities |
| `frontend/tests/{ownership,access_proofs,program,source_owners}.lua` | Proof/action/ABI and source execution contracts below |
| `tools/validate_source_owners.c` | Actual allocations/count changes/failure cleanup; distinguish helper calls, acquisition attempts and successful count changes |

No new runtime source files, owner kinds, C bridge signatures, opcodes, native value
IR or allocation machinery are part of this proposal. No changes to public ownership,
FFI, task or persistent-module lifetime policy are included.

## 10. Concrete acceptance cases

| Case | Required behavior |
| --- | --- |
| Local `Point`, `read_only(Ref(point))` | Ordinary addressable storage if needed; zero counted allocation, acquire, release, cleanup record |
| Read-only borrow of an already-counted point | Zero additional count traffic, including in a function/program which has other escaping roots |
| `identity(p: Ref(Point)): Ref(Point) = p` | Borrow input/result; one-address contract where no capability is demanded; no result holding |
| `leaf(n)` returning its freshly allocated point | One counted allocation, initial count one; transfer to caller; zero extra acquires |
| `Choice.one(leaf(n))` and match | Transfer original holding through owning boundary; constructor/extraction aliases do not acquire |
| Existing three-root nested fixture | Three initial owner allocations, zero additional acquires attributable to construction/transport/matching; each owner freed once |
| Two independently escaping boxes share a fresh point | Three initial allocations; one additional point holding if its initial holding transfers into one box; no parameter/temporary retains |
| Saved child, direct known-field replacement | Transfer old field holding to preservation when legal; saved child remains valid; no gratuitous retain/release pair |
| Saved child across mutating helper call | Protect before call when caller cannot consume the field; one actual selected-root acquisition if no other guard covers it |
| Borrowed/fresh conditional result | Borrowed path adds no count; fresh path transfers; optional result slot is zero/nonzero as specified |
| Loop overwrites a result slot while prior access survives | Prior occurrence protected before reuse; static root-family equality does not elide it |
| Consuming-call stack failure before entry | Caller slot still owns root; normal unwind frees exactly once |
| Failure after callee moved a consumed holding | Source slot null; destination cleanup owns it exactly once |
| Partial independent aggregate acquisition | Old destination unchanged on failed acquisition; successful partial acquisitions cleaned |
| Conditional false trap before later accesses/edges | Normal successor remains in analysis; later uses and cycle obligations cannot disappear |
| Escaping source self-cycle | Still rejected by the existing source policy |

Run raw/optimized execution in all four modes and both lifecycle banks, with failure
injection at remaining real allocation/acquisition boundaries. Verify structural
absence of ownership calls/records in the zero-traffic cases. Do not merely observe
that zero-pointer retain calls do nothing. Compare emitted code bytes, actual cleanup
storage, peak live owner bytes and count operations against the named fixtures.
Performance claims require measurements; no universal optimal-retain or zero-overhead
claim follows from this algorithm. General container/erased/task contracts remain
outside this binding.
