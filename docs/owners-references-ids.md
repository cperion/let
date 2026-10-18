# Owners, references and ids

**Authority:** ownership semantics for one collector-free Let. `Rc(T)` owns and
copies retain; `Ref(T)` and `Slice(T)` borrow. No implicit promotion or hidden
ownership repair is permitted.

**Implemented initial slice:** explicit construction/copy/borrow, records/fixed
arrays/sums, private direct owning calls and failure cleanup. **Approved targets,
not general runtime support:** containers, freezing, transferable erased values,
owning environments and tasks. Public/foreign owning transport remains gated.
The `.let`-only language migration is still pending. [WORKLIST](../WORKLIST.md)
O01–O08/E01/E02 owns delivery status and measured evidence; examples outside the
initial slice describe intended semantics, not executable admission.

[Runtime interfaces](runtime-interfaces.md#3-explicit-rc-layout-and-private-handoff)
own private layout/handoff and checker contracts; [runtime primitives](runtime-primitives.md)
own algorithms. Historical inference designs are archived, not alternate semantics.

This revision incorporates the engineering decisions approved after the initial
proposal. In particular, it does **not** count whole activations, decide safety by
referent-type reach alone, allow escaping store-element references, or switch live
non-atomic counters to atomic. See §15 for the implementation authorities.

## 1. One language, independent facts

Let has one value, place, call and ownership semantics. Type precision, lifetime
proof, allocation, counting and task transferability are separate facts. Adding a
type annotation does not select a different ownership engine or evaluator.

`count-free`, `allocation-free` and (where required) absence of `Any` are separately
inferred and enforceable requirements. An uncounted local store may allocate;
a scalar `Any` need not allocate or retain anything. Neither property follows
from a filename. **`.let` is the sole source extension.** SLet is retired as a
language/profile name; use the precise capability names rather than calling
count-free code another language. Typed and dynamic code may coexist in one file.

The approved migration removes `.slet` discovery and filename-selected semantic
profiles, with no `.slet` compatibility alias or ownership adapter. Imports resolve
Let source as `.let`; active examples, tests, tools and documentation migrate together.
Historical archives retain their original names and evidence.

This decision is not implemented: the current `.slet` execution path and `.let`
`dynamic-lowering` rejection remain implementation facts. Compiler/API dispatch,
imports and capability enforcement need a coordinated implementation, not a file
rename or removal of unsupported-feature diagnostics. Capability-requirement syntax
and concrete migration interfaces still need specification.

## 2. Values, places and owners

1. **Value boundaries copy.** Parameters, returns and assignment into fields or
   elements copy values. Local bindings to an existing mutable instance alias that
   instance, as for today's records and arrays. A copied field read is a snapshot,
   not a new alias to the field. Reference values copy the reference, not the target.
2. **Every addressable place has one root owner.** Subobjects inherit their root's
   owner. Moving storage after publishing an address is forbidden.
3. **`Ref(T)` borrows; `Rc(T)` owns.** Rc construction explicitly selects counted
   storage. Each semantic Rc value copy retains the same root; destruction releases
   it. Copying a Ref never retains, and an invalid borrow rejects rather than being
   repaired with a hidden holding. Rc copies do not copy the target `T`.
4. **Mutable owning edges must satisfy a static acyclicity proof.** Immutable value
   graphs have a separate construction proof. Neither uses cycle collection.
5. **Ids carry no ownership.** They identify occupied store slots through a checked
   lookup using a separately held store.
6. **Capture modes preserve ownership types.** Value captures copy, including Rc
   retains. Place captures borrow. An escaping environment must use an explicitly
   owning construction/contract; it cannot silently promote borrowed captures.
7. **Sharing cannot expose another task's mutable storage.** Read-only access alone
   does not establish immutable backing.
8. **Destruction has no user behavior.** Freeing memory runs generated releases,
   never a destructor, finalizer, arbitrary callback or source-level `defer`.

### 2.1 Explicit ownership selection

| Storage | Ownership and lifetime |
| --- | --- |
| ordinary locals, parameters, frame blocks | activation; borrowed uses must fit their valid storage lifetime |
| explicitly constructed `Rc(T)` root | separate counted allocation; every Rc copy is a holding |
| module data | module lifetime; immutable data may be shared, mutable places stay in their task's world |
| store slots | storage owned by that store; persistent links are ids |
| closure environment | borrowed/local or explicitly owning by its construction contract; no escape-driven promotion |
| value-container buffers | owning library-value semantics; not a conditionally owning Ref representation |

Ownership is declared, not inferred from escape. Returning `Ref(local)` after its
storage dies rejects. A factory that creates independent storage declares an
`Rc(T)` result instead. Interior projections borrow the same root's payload; the
initial Rc design has no owning-subobject handle or implicit `Ref`→`Rc` conversion.
The initial surface is `Rc(value)` and named `r.borrow()`, specified below;
private transport is fixed in runtime interfaces, not selected by provenance.

```
let Counter = { value: U32, bump() = do value += 1 end }
let peek(c: Ref(Counter)): U32 = c.value
let invalid(start: U32): Ref(Counter) = do
  let c = Counter { value = start }
  return Ref(c)                    -- rejects: c does not outlive the result
end
```

Rc construction allocates its selected root directly; no counting of whole
activations, later promotion or address repair occurs. Module storage needs no
retain. Borrowing a live Rc-protected object adds no count. Foreign pointers supply
no lifetime proof by themselves.

### 2.2 Construction and semantic copies

`Rc(value)` copies `value` into a fresh counted root and returns `Rc(T)`. It does
not move addressed storage or adopt a borrowed pointer. Initial payloads admit
scalars/raw pointers, finite records/arrays/sums and nested Rc handles; stored
Ref/Slice, callable and erased payloads are excluded. Rc indirection permits
recursive layout, but does not prove acyclicity. Raw pointers remain unchecked.

`r.borrow()` returns `Ref(T)` through an existing named holding without copying
or retaining it. Payload access uses that reference, with no implicit payload-method
forwarding. `Ref(r)` still means a reference to the handle's place, not its payload.
A temporary whose holding cannot protect subsequent use cannot be borrowed to
extend its lifetime. Source Rc has no null variant.

Semantic copies include owning local-value bindings, value arguments/results,
stores and copied field/element reads. Records, fixed arrays and active sum cases
copy each Rc field, even if two handles name the same allocation. Capture-by-value
would copy a holding; a place capture borrows. This does not admit an owning
callable environment before its separate contract is defined.

Aliasing a mutable aggregate place is not a value copy. Register transport,
spilling and intermediate address bits are also not semantic copies. A proven
move may eliminate copy-plus-release only if the consumed holding has no remaining
alias/borrow obligation and evaluation, failure and lifetime guarantees remain
unchanged. Correct baseline copying never depends on global count minimization.

## 3. References, slices and lifetime proofs

A `Ref(T)` names a place without owning it. Mutating through it mutates that place.
References to fixed-layout parts require independent protection of the root;
they do not keep it alive by counting. Replacing a record field's value preserves
that field's place, but can invalidate a borrow of the old referenced object.
These are different accesses. `Ref(Ref(x))` and references to non-addressable
temporaries still reject; an Rc handle must not silently change what `Ref(place)`
names.

A `Slice(T)` is a borrowed read-only view, not a mutable container or a conditionally
owning value. Mutable backing can change; readonly access is not immutable backing.
Owning list/string snapshots require an explicit owning type/API binding (§16),
not inferred capability cells behind `Slice(T)`.

| Value | Representation contract |
| --- | --- |
| `Ref(T)` | borrowed address; no owner cell or release obligation |
| `Slice(T)` | borrowed address and length; no owner cell |
| `Rc(T)` | one owner-header address cell in the private ABI; retain-on-copy; public transport gated |
| id | position + generation packed in one 64-bit cell; no ownership |

A value parameter/result of type Rc is owning; one of type Ref is borrowed. A
signature does not change ownership mode according to the caller's provenance.
Borrowed calls need an actual borrow operation/contract, not an owning copy
silently treated as borrowed. Public/foreign handoff still requires an explicit ABI.

A stored borrow must fit its destination's valid lifetime. Unknown protection
rejects; it is never permission to acquire an invisible holding. An Rc allocation
also does not make borrowed fields inside its payload safe. Admission of such
payloads beyond the initial exclusion is an explicit gate, not automatic promotion
of their referents.

Returning Ref into a dying local or by-value parameter rejects. Borrowed-input and
module-lifetime relations may justify borrowed results; an owning parameter's lifetime
during a call alone cannot protect a result after that holding is released. Use a
borrowed input to express that interface, not hidden caller-owner recovery.

A copied `saved = box.child` where `child: Rc(Point)` owns independently. Replacing
`box.child` cannot invalidate `saved`; borrowing the old child is different and must
reject use after its protection is lost. Moving/replacing/releasing a protecting
holding or reexecuting its definition cannot synthesize preservation counts. Unknown
call effects, index overlap and missing provenance must not be treated as harmless.

## 4. Mutable ownership: exact proof obligation

A finite layout through `Rc`, `Ref`, `Slice`, `id`, `Ptr` or a container indirection
does not itself prove safe ownership. Borrowed reference cycles do not create
strong edges; explicit Rc edges and other declared owning values must still satisfy
the collector-free acyclicity rules.

### 4.1 Owner constraints

Every explicit counted owner in the mutable ownership domain has an implicit
static rank parameter. For each possible strong edge from holder H to target O,
require:

```
rank(H) > rank(O)
```

Use the **actual retained root owner**, not just the referent's source type.
Include explicit Rc fields, owning containment, nested owning containers and
owning closure environments. Ref and borrowed Slice fields are not strong edges;
their independent borrow validity is checked separately. A non-transferable COW buffer participates in
this domain too: sharing its storage does not erase its mutable dependencies.

Check initialization, replacement stores, capture construction and value copies
into an owner. A copy into another owner must satisfy that destination's constraints.
Collect all possible edges at control-flow joins, even mutually exclusive stores:
ranks must remain valid throughout the owners' lifetimes, not only at one moment.

A finite strict-order graph has a solution exactly when it is acyclic. Detect
strongly connected components/self-edges and reject contradictions as `Ref-cycle`;
otherwise a topological ordering provides ranks. There are no runtime rank words,
graph scans, cycle detectors or user lifetime annotations.

Functions carry parameter/result owner-provenance and retention summaries with
rank constraints. Instantiate them with actual owners at calls. Recursive summaries
must reach a conservative fixed point; unresolved cyclic requirements reject.
Higher-order values retain environment bounds through parameter passing, returns
and erasure. Separate compilation must export these summaries. An opaque ABI
without sufficient evidence rejects; it does not erase an ownership obligation.

This is deliberately conservative. Mutable owning structures that cannot satisfy
finite checked bounds use stores and ids, not a collector or a runtime cycle check.
The current checker uses actual Rc edges and iterative SCC checking, with a separate
construction-only exemption. Automatic counted placement is removed. Broader
polymorphic/generalized proofs and stable export/ABI encoding remain incomplete.

### 4.2 Interior-reference counterexample

The former implicit-owning `Ref(p.child)` example is retired: this is now only a
borrow and cannot be promoted into a strong edge. Storing a copy of an Rc handle
into its own root's Rc field instead creates H → H and rejects, irrespective of
the referent's type. Borrowed interior access still needs independent protection;
finite referent-type layout is not an acyclicity or lifetime proof.

### 4.3 Closures

Capturing a button in an escaping environment E requires E → button. Storing that
closure back into the button requires button → E. The inequalities contradict.
A literal capture list makes this easy to diagnose, but hidden or passed callables
must obey exactly the same rule through their summaries.

The former `tally` example that returned a closure over an ordinary local counter
and silently allocated both owners is no longer valid target semantics. Explicit
Rc capture-by-value can create E → counter once an explicitly owning environment
contract is defined. Borrowing a local cannot trigger either allocation. The
callable surface/transport binding remains a gate; transferability still requires
transitive immutable backing, not just valid counting.

## 5. Stores and ids

`Store(T)` is a value with independent, addressable slots. Growing it adds stable
segments; existing slots do not move. Copying a store creates independent slots
and copies their values, preserving slot positions, occupancy and generations so
copied internal ids continue to work. References never retarget to the copy.
A move can transfer backing segments only when outstanding access permits it.

| Word | Meaning |
| --- | --- |
| `Store(T) {}` | empty store |
| `s.add(v)` | copy/store v and return its id; may allocate |
| `s.try_add(v)` | allocation-free insertion if capacity exists; `added(id)` or `full` |
| `s.reserve(n)` | reserve capacity for n further additions |
| `s[i]` | checked element access; reading copies, writing stores |
| `s.remove(i)` | remove a live element, release its value and vacate its slot |
| `s.has(i)` | non-aborting validity test |
| `s.length` | number of occupied slots |
| `s.each(body)` | live ids in storage order |

An id packs a 32-bit slot position and 32-bit generation. Check position against
allocated slot extent, then occupancy and generation. **Do not use live length as
an address bound.** Out-of-range positions use the bounds abort; vacant or
wrong-generation slots use `stale-id`. `has` returns false for either failure.
Filling a slot advances its generation. After 2^32 fills, a stale id can collide;
that limitation is explicit. Ids are not security capabilities. An id used with
another store of the same type may pass if the slot and generation happen to match.

Using an id requires live access to a store. Ids alone cannot access freed memory.
They are transferable ordinary values but do not transfer their originating store.

### 5.1 References to slots are temporary borrows

`Ref(s[i])` and method receivers borrow a live slot. They cannot escape or become
counted element references. Growth/reservation is permitted during a borrow because
segments remain stable. Removal cannot invalidate a live borrow; if slot disjointness
cannot be proved, reject removal until the borrow ends. Borrow uses determine the
extent; no new lifetime syntax is added. Removal, store replacement, moves and
whole-store destruction must all respect these live accesses.

A removed slot therefore has no observable dangling `Ref(T)`, no retained dead
payload, and no reference that later changes identity upon reuse. Long-lived links
are ids. Fixed-size array and record-field references keep their existing place
semantics; they are not vacated slots.

Trees, ASTs, worlds and cyclic graphs use ids within stores. A local store whose
only references are borrows needs no count; its segments are freed on exit.

## 6. Lists, strings and immutable value graphs

### 6.1 Construction proof

A completed immutable value may reference existing completed immutable values.
Do not publish partially initialized shells or permit references back into their
construction. Shared published storage cannot acquire outgoing edges.

A COW write evaluates and retains its incoming value **before** deciding whether
the destination buffer is unique. If an incoming value can reach that buffer,
there is an additional owning path and the write must copy. Thus `w.self = w`
creates a new map pointing to the old map, not a cycle. This applies through
nested boxes/containers, not merely direct self-assignment.

A last-use optimization cannot move a value into its own reachable storage or
ignore aliases/borrowed uses. Mutation targets count as uses. Unique-buffer
mutation is valid only when this proof and the task synchronization rules hold.

Transferable immutable graphs cannot point back into mutable owners. Non-transferable
containers instead carry the mutable-domain owner constraints of §4. Immutability
of one buffer is not evidence that everything reachable from it is immutable.

### 6.2 Lists

`List(T)` is a growable sequence of values. Its proposed representation is one
counted buffer reference; the buffer holds length, capacity and contiguous unboxed
values. Copying shares the buffer; writing copies first when shared. Local aliases
still designate one list instance. An empty list need not allocate.

| Word | Meaning |
| --- | --- |
| `List(T) {}` | empty list |
| `l[i]` | u32 position; checked read/copy or store |
| `l.length` | element count |
| `l.push(v)`, `l.try_push(v)` | append, possibly allocating / no-allocation `done` or `full` |
| `l.pop()` | remove/return last value; bounds abort if empty |
| `l.insert(i,v)`, `l.remove_at(i)` | ordered insertion/removal, shifting later elements |
| `l.append(view)`, `l.reserve(n)` | append a slice / reserve for n further appends |
| `l.view()` | read-only snapshot retaining the buffer |
| `l.each(body)` | positions and values in order |

Elements are values, not stable referencable places: `Ref(l[i])` rejects
`element-Ref`. Field/compound stores update the element. An element method operates
on a temporary and copies its result back on successful return; in-place execution
requires proof the method cannot reach/mutate the list through another path.
Precise copy-out behavior under reentrant removal/replacement remains an explicit
open library-contract question (§16), not permission to use stale addresses.

`try_push` cannot detach a shared buffer: if its operation would allocate, it
returns `full` without mutation. Similarly, `reserve` promises capacity, not that
future sharing can never cause a COW allocation.

### 6.3 Strings

`String` is a byte-sequence value, **not** `Slice(U8)`. Proposed representation:
a buffer reference plus one cell packing u32 offset and length. Substrings retain
the buffer. Literals use immortal module buffers and never change their counts.
Content equality remains; `<` is not string ordering. No text encoding is imposed.

| Word | Meaning |
| --- | --- |
| `s.length`, `s[i]` | byte count and checked byte read/store |
| `s.append(t)`, `s.push(b)` | build in place only when unique and ending at buffer end; otherwise copy |
| `s.sub(a,b)` | bytes in [a,b), sharing storage |
| `s.compact()` | explicit copy into storage for precisely these bytes |
| `s.view()` | immutable snapshot; explicit owning result type remains gated, not a conditionally owning `Slice(U8)` |
| `String(view)` | copy a byte view into a string |

Writing a substring detaches its own bytes when required, not unrelated prefix
or suffix bytes. A small substring can retain a large buffer; no heuristic
compaction is part of the language. `Ref(s[i])` rejects. Foreign non-retaining
calls can borrow `s.view()`; keeping a foreign view requires a valid ownership
contract or copying it, not inventing an owner.

### 6.4 Concatenation and text library

[stdlib.md](stdlib.md) owns the public module/API inventory, including incomplete
export signatures. The vocabulary here does not make every text operation a predefined
global or approve public modules merely from proposed implementation filenames.

`..` concatenates two strings or two lists of the same element type, with no
implicit numeric formatting. It is right associative, below additive and above
shift operators. Operands still evaluate left-to-right. `..=` is a compound store
on a writable field/element, not rebinding of an immutable local name.

A chain should compute lengths and fill one destination rather than repeatedly
copy prefixes. One-allocation concatenation/formatting is a performance target,
not a new observable allocation-count or error-order guarantee.

| Words | Proposed contract |
| --- | --- |
| `sub`, `prefix`, `suffix` | sharing substrings |
| `find`, `find_from` | `found(U32)` or `missing` |
| `contains`, `starts_with`, `ends_with` | boolean byte tests |
| `split(sep)` | list of sharing substrings; allocating result metadata, not copied subject bytes |
| `join(parts,sep)`, `repeat(n)` | build one resulting string |
| `replace`, `reverse` | resulting byte string |
| `upper`, `lower` | ASCII case conversion, other bytes unchanged |
| `trim`, `trim_start`, `trim_end` | ASCII whitespace removal by sharing |
| `compare` | `less`, `equal`, `greater` bytewise order |
| `hash` | u64 content hash, consistent with table key equality |
| `each` | positions and bytes |
| `parse(t,s)` | `parsed(T)` or `invalid`, for integer types and f64 |

`fmt(format,...)` accepts `{}`, `{x}`, `{N}`, `{N x}`, and escaped `{{`/`}}`.
Literal formats are checked during specialization; dynamic formats check at run
time. Mismatches use `format-mismatch`. Number formatting is explicit.

Patterns use Lua's byte-pattern syntax: classes/complements, sets/ranges,
`* + - ?`, anchors, `%b`, `%f`, substring and position captures. Proposed words:
`match`, `find_pattern`, `each_match`, `replace_pattern` (`%0`…`%9` replacements).
Literals specialize; malformed dynamic patterns abort `bad-pattern`. This is not
a promise of linear-time matching: Lua-style matching can backtrack. Position
captures do not fit `List(String)`; their result representation and detailed empty
match/separator behavior require resolution before the library contract is final.

## 7. Tables and any

`Table {}` constructs a dynamic ordered map. Tables are values; copies share a
COW map, while local aliases designate the same table instance. Fields hold `Any`,
which admits only transferable values. Mutable-place-capturing closures cannot
be table field values. There is no shared mutable table identity across value copies.

`w.name` selects string key `"name"`; `w[k]` uses a string, integer or bool key.
Integer key identity is numeric across integer widths. Missing reads abort;
`has(w,k)` tests and `remove(w,k)` removes a key. No nil is introduced. Stores
preserve the existing target/RHS evaluation order and snapshot rules. `Ref(w.k)`
and `Ref(w[i])` reject `element-Ref`.

A callable field invoked as `w.m(args)` receives the actual table borrowed as a
receiver. It need not capture that table. Extracted bound methods must retain
receiver provenance and obey ordinary borrowing/rank/transferability rules.
Schema methods remain static interfaces, not runtime method dictionaries.
The old open-word terminal/runtime-partial-supply subsystem is not automatically
retained by renaming maps; any extension to partial application needs its own
contract. Closed-word static specialization remains unchanged.

### 7.1 Dense integer part

- Positions start at zero; `length` is the exact consecutive run of integer keys
  starting at zero, not total key count or a representation-dependent boundary.
- Iterate that dense run first, then other keys in insertion order.
- `push`, `pop`, `insert`, `remove_at` have list-like dense-sequence behavior.
  Map removal in the middle creates a gap instead of shifting keys.
- Appending the missing boundary key absorbs consecutive keys already in the map.
- `view()` returns a snapshot of the array part; `each` visits keys and values.
- Represent the array part as value-buffer storage with integer/float/general-any
  kinds. Kind widening is one-way. Bounds and kind proofs are independent of
  named-field layout-token proofs.
- A non-owning layout token covers named keys, not array length or element kind.
  Copies share tokens; named structural changes renew them; ordinary array push
  must not invalidate named-field proofs. Token alone never makes a value constant.

Integer keys outside the dense run, insertion-history handling across dense/map
migration and builtin-name collisions need precise library rules before coding.
No shared mutation, key interning graph or collector is required for this layout.

### 7.2 Transferable dynamic values

`Any` retains type and ordinary scalar semantics; it is not a second scalar engine.
Scalars, ids, strings, tables, transferable aggregates/containers, frozen values,
transferable closures and slices backed by immutable storage can enter it.
A borrowed read-only view of mutable storage, mutable reference or raw foreign
pointer does not qualify merely because its representation is small.

A value too large for the dynamic cell is copied into a counted immutable box.
Do not borrow a mutable store through a box: value copying creates independent
storage before publishing the immutable value. Concrete tag/box layouts and
revision compatibility are separate ABI work; the old profile-5 tracing descriptor
is not silently reinterpreted as a release descriptor.

Statically known violations reject `not-transferable`; a dynamic boundary with
unproven transferable contents must validate before accepting the value. The
normal `Any` construction invariant does not require repeatedly inspecting every
already-validated value.

## 8. Freezing and tasks

`freeze(v)` copies, or safely moves, a transferable value into a new immutable
owner, returning `Frozen(T)`. It never freezes aliases in place. A move must account
for every outstanding borrow/address, not just the last textual use of one name.
Writes through frozen access reject `Frozen-write`.

Transferability is transitive absence of access to another world's mutable
storage, not just absence of syntactically mutable references. Immutable module
bytes, frozen storage and immutable snapshots qualify. A closure's implicit access
to mutable module state is a world capability and participates in this check even
if its explicit capture list is empty. Raw foreign pointers do not qualify by default.

Shareable buffers use atomic reference counts from creation. Task-local mutable
owners use ordinary counts. Do not upgrade a live counter while non-atomic users
may still access it. Count elision and unique-buffer mutation require proofs that
include all cross-task references and borrowed uses; publication requires the
appropriate synchronization. Memory-order choices and overflow handling need a
runtime specification before implementation.

[tasks.md](tasks.md) specifies structured groups, channels, select, cooperative
cancellation and work stealing (not implemented). Ordinary transferable values may
enter `Any`; group-bound capabilities are a separate permission. Groups, channels,
task handles and wrappers containing them may cross only within their valid group
lifetimes, never through unrestricted `Any` or frozen boxes. Channel payload bounds
must protect the entire queue lifetime; a child capability cannot enter an ancestor
queue. Group records are structurally owned, not retained through counted handle
cycles. Transitive reads as well as writes of another task's mutable module storage
are forbidden. Allocation, counting and suspension are independent effects.

## 9. Objects and ordinary code

Objects remain records with schema methods. A class is a schema; a receiver is a
borrowed actual place. An owning acyclic link has type `Rc(T)` with checked
strong-edge constraints. A potentially cyclic link is an id. World records can hold
stores of bodies and players, connected by `Id(Body)` and `Id(Player)`. No vtable,
inheritance system, garbage collector or object-specific destructor is introduced.

A stored closure can retain mutable state within its own task, subject to §4.
A table method receives a borrowed receiver rather than capturing its object.
These are different mechanisms with explicit ownership consequences, not two
names for a universal dynamic object graph.

## 10. Reclamation and the collector-free argument

An owner header carries its count and generated release operation. Generated
release code knows outgoing owning fields, including Rc handles; it is not tracing
metadata used by a collector. It never calls program code or follows borrow/id edges to free them.

On transition to zero, enqueue the owner on an intrusive destruction worklist,
release its outgoing strong references, enqueue newly zero owners, and free storage.
The worklist uses dead owners' own storage: releasing a long chain must neither
allocate nor recurse on the native stack. Scope exit releases root holdings;
module/task teardown releases their holdings under the same mechanism.

The proof obligation is:

1. Mutable-domain owning edges strictly descend in static rank.
2. Immutable value graphs are DAGs by construction and COW update ordering.
3. Immutable graphs cannot point back into mutable owners.
4. Borrow edges have independent lifetime proofs; ids own nothing.

Thus the combined strong graph is acyclic. Any unreachable finite subgraph has a
node with no remaining incoming strong edge; its count reaches zero, and repeated
release frees that subgraph. Roots still held by a running task or module are
intentional retention, not cycles. This argument is conditional on correct inference,
COW ordering, counting and concurrency—not a claim that the implementation is proved.

No tracing, weak references, finalizers, cycle detector, periodic graph walk or
fallback collector is part of the target. Reference-count overflow must not wrap;
allocation failure and failed construction must release partially acquired holdings.
Initial private Rc failure cleanup uses the concrete runtime contract. General
foreign/program-abort shutdown and concurrent lifetime qualification remain gates.

## 11. Source compiler obligations and effects

Extend existing source `PlaceId`/retained-access provenance, not VM cache allocation
or a new residual value IR. Required facts include root owner identity, borrow extent,
possible retained owner edges, callable world effects, ownership bounds and sharing
state. These are analysis facts, not additional source-value computations.

Order: elaborate explicit ownership types and semantic copy/allocation operations;
check borrows and actual strong-edge constraints; materialize those operations once;
lower to ordinary ABC and explicit continuations. Neither escape analysis nor
capability propagation chooses counted allocation or a reference's representation.
The VM remains the sole source computation engine. Build-time `abc-opt` and native/
threaded residualization must not guess or reconstruct source ownership.

`count-free` excludes counted-owner creation and remaining retain/release obligations,
including hidden buffers/boxes/environments and callees. Borrowing an existing counted
argument without retaining it is allowed. Eliminated operations can be removed from
the fact only with proof. `allocation-free` independently excludes possible allocation,
including COW detachment, store copying and boxing. `try_add`/`try_push` preserve it
only by refusing operations that would allocate. Snapshot creation may retain without
allocating; dropping a value may run generated releases but not user code.

Facts are transitive through calls and callable contracts. Unknown effects cannot
be treated as absent. Checked module requirements reject violations independent of
filename. Diagnostics identify the explicit Rc construction/copy, owning library
operation, invalid borrow, strong cycle or sharing operation—not an inferred reason
to manufacture ownership.

## 12. Lowering and ABI boundaries

Borrowed references use existing address instructions without ownership cells.
Rc handles have an explicit owning transport contract; no counted Ref or inferred
counted Slice representation remains. Physical argument/result handoff and cleanup
must remain failure-safe even where an owning value uses ordinary ABC cells.
Stores use segmented slots and generation checks. Strings/lists/tables use their
own declared owning buffer contracts, not tracing heap objects.

A nominal store segment target is about 4 KiB with at least 16 elements, using a
power-of-two slot count. Large element types necessarily produce larger segments;
this is a tuning target, not a contradiction hidden in an ABI promise. Container-
specific fields, transactions and public handles still need binding/qualification;
the existing owner header and initial private Rc handoff are already fixed in
runtime interfaces §§1/3.

For remaining container/dynamic/task surfaces, “no new instruction” is a lowering
hypothesis: existing scalar/memory operations
and runtime calls may suffice, but allocation, atomics, release worklists and exact
ABI transport must be validated. Do not change revision-6 bytecode or reuse old
profile-5 encodings without an explicit compatibility decision. Existing stack-limit,
trap, continuation, foreign-effect and operand-placement contracts remain binding.

## 13. Diagnostics

| Name | Meaning |
| --- | --- |
| `Ref-cycle` | owning constraints are contradictory or cannot establish required acyclicity |
| `element-Ref` | reference to a non-addressable list/string/table element |
| borrow diagnostic | invalid target, missing provenance, escaping slot borrow or invalidation of a live borrow |
| `not-transferable` | forbidden mutable/world/foreign access crosses a sharing, any or freezing boundary |
| `Frozen-write` | attempted write through frozen access |
| `stale-id` | vacant/wrong-generation slot |
| bounds abort | invalid extent/index; retains existing `ABORT 2` meaning |
| `format-mismatch`, `bad-pattern` | static rejection for malformed literals, runtime failure for dynamic forms |
| capability diagnostic | required count/allocation/type fact is not established |

New numeric abort assignments are not allocated by this document.

## 14. Required evidence before implementation is called complete

- Rejected returned references to dying locals/by-value parameters; explicit Rc
  factory results; borrowed projections protected by a live holding without counting.
- Rc copy-retain/drop behavior across bindings, reads, stores, arguments, results
  and captures; shared target identity rather than target copying.
- Borrowed calls and closures with no RC traffic, stored-borrow lifetime checks,
  rejection rather than hidden repair on invalidation, and unknown-contract rejection.
- Owner self-edges through interior references; multi-owner cycles; cycles through
  non-transferable list buffers, nested aggregates and closures; hidden callable
  captures preserved through return/erasure and separate-compilation summaries.
- Mutually exclusive edge additions conservatively checked; recursive summaries;
  same examples accepted with bounded borrows or ids. No false acyclicity from
  renamed types, boxes or purported readonly views.
- Long-chain iterative release, allocation-free destruction, partial-construction
  rollback, count overflow, scope/task/module teardown and abort behavior.
- Store copy independence/internal ids; holes, occupancy, wrong-store collisions,
  generation reuse/wrap boundary; growth under live borrow; rejected invalidation
  and escaping slot references. Old reference-sees-reused-element tests are removed.
- COW copies versus local aliases; direct and nested self-insertion; retain-before-
  uniqueness ordering; rejected self-moves; snapshots; substring retention/compact;
  immortal literal buffers; non-transferable buffers retaining their owner bounds.
- Freeze with outstanding aliases; mutable-backed readonly slice rejection; hidden
  mutable-global effects in task closures; atomic publication and final release races.
- Table dense/map migration, exact length/order, element kinds, named tokens and
  proof separation; method receivers, checked conversion and missing-key behavior.
- Operators, evaluation order, byte/text library words, formatting and Lua pattern
  reference cases including position/empty captures once their contracts are settled.
- Independent count-free/allocation-free/type facts, transitive calls and count
  elision; no filename-dependent semantics in the unified target.
- All execution bindings: operand placement, noncommutative order, independent
  CALL/RET banks, live prefixes, safepoint/effect boundaries where applicable,
  lifetime/trap/stack limits, code growth, prep/steady time and peak retained memory.

## 15. Implementation authorities

- [Runtime interfaces](runtime-interfaces.md): header, six bindings, failure-safe
  private owning slots, checker boundary and remaining public/foreign gates.
- [Runtime primitives](runtime-primitives.md): count/release, COW and task algorithms.
- [Implementation map](implementation-map.md): actual files, tests and retired paths.
- [WORKLIST](../WORKLIST.md): dependencies, qualification and remaining delivery.

Historical replacement/approval narratives live in
[the archive](../research/archive/docs-before-rc-consolidation/README.md) and REFACTOR,
not a second active ownership specification.

## 16. Explicit remaining specification work

The collector-free direction and proof obligations above are approved. The owner
layout, counter/overflow policy, iterative release, allocator and concurrency
algorithms are also already decided in the runtime contracts; this list does not
reopen them. Remaining binding/qualification and genuinely open interfaces include:

- borrow-carrying Rc payloads beyond the initial exclusion, explicitly owning
  environment and snapshot API types. `Rc(value)`, named `r.borrow()`, copy-retains
  and private typed-slot handoff are settled;
- extend the initial Rc/borrow/strong-edge implementation to persistent owning
  modules, containers/initialized-element loops and erased transport without
  restoring inferred ownership or changing borrowed Ref representation;
- borrow/strong-edge generalization and stable separate-compilation summaries,
  Rc/callable export ABI, raw-pointer boundary and dynamic encoding/profile revision;
  qualify shared memory orders and foreign teardown separately. Foreign code cannot
  be made safe by a documentation claim;
- exact copy-out and iteration mutation semantics, empty text/pattern cases, position
  capture result type, table builtin-name collisions and migration insertion history;
- capability-requirement syntax and implementation of the approved `.let`-only
  extension/import migration (no `.slet` alias);
- concrete suspension, concurrency publication/reclamation, group-bound summaries,
  foreign integration and shutdown ABIs implementing the approved [task semantics](tasks.md).

These are engineering specifications to finish under the no-collector constraint,
not permission to add a collector if implementation becomes difficult.
