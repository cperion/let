# Owners, references and ids

**Status: approved collector-free semantics and qualified source inference; runtime
ownership orchestration removed, replacement/source counted placement pending.**
This is the ownership target for one Let language, replacing the tracing-GC target.
WORKLIST O03 records formal/fresh-root, borrow/count/strict-edge inference; E01/E02
and O04–O08 record the removed runtime binding and current removal checkpoint.
Standalone C counting/queue code remains, but no source lifetime/cleanup binding is
currently implemented. The c-release evidence describes the historical v3 checkpoint,
not current admission or validation. The larger follow-up design was withdrawn.
General source owning layouts and placement, containers and tasks are not implemented;
typing now retains valid counted requirements on the checked program, while executable
admission still rejects them. Cycle and unsafe-access proof failures still reject during
analysis. Examples below remain target-language examples unless
explicitly qualified by the worklist.

This revision incorporates the engineering decisions approved after the initial
proposal. In particular, it does **not** count whole activations, decide safety by
referent-type reach alone, allow escaping store-element references, or switch live
non-atomic counters to atomic. See §15 for the explicit replacement map.

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
3. **A reference is either a proven borrow or retains its owner.** The program does
   not choose a different `Ref` spelling for the two representations.
4. **Mutable owning edges must satisfy a static acyclicity proof.** Immutable value
   graphs have a separate construction proof. Neither uses cycle collection.
5. **Ids carry no ownership.** They identify occupied store slots through a checked
   lookup using a separately held store.
6. **A closure has an environment owner.** Value captures copy; place captures
   retain access to their actual owner, by borrow or owning reference.
7. **Sharing cannot expose another task's mutable storage.** Read-only access alone
   does not establish immutable backing.
8. **Destruction has no user behavior.** Freeing memory runs generated releases,
   never a destructor, finalizer, arbitrary callback or source-level `defer`.

### 2.1 Owner selection

| Storage | Ownership and lifetime |
| --- | --- |
| ordinary locals, parameters, frame blocks | activation; proven uses end before it returns |
| escaping addressable value | separate counted owner for its root aggregate, allocated from the start |
| module data | module lifetime; immutable data may be shared, mutable places stay in their task's world |
| store slots | storage owned by that store; persistent links are ids |
| closure environment | frame-local if proven nonescaping, otherwise separately counted |
| value-container buffers | hidden counted storage, not addressable element places |

Counting an escaping `Ref(c.child)` retains the root `c`, not an independently
promoted child and not every unrelated local in the activation. If the necessary
root is embedded in a larger addressable aggregate, that aggregate is the root.
Selection is static and precedes physical placement. There is no stack-to-heap
promotion after an address has escaped.

```
let Counter = { value: U32, bump() = do value += 1 end }
let peek(c: Ref(Counter)): U32 = c.value
let make(start: U32): Ref(Counter) = do
  let c = Counter { value = start }
  return Ref(c)                    -- c has its own owner from the start
end
```

Module storage needs no retain. A borrow from a counted reference needs no extra
count when the original retained access is kept live for the entire borrow.
Foreign pointers supply no lifetime proof by themselves.

## 3. References, slices and lifetime proofs

A `Ref(T)` names a place. Mutating through it mutates that place. References to
fixed-layout parts keep the root owner alive. Replacing a record field's value
preserves that field's place; existing references observe the replacement.
`Ref(Ref(x))` and references to non-addressable temporaries still reject.

A `Slice(T)` is a read-only view, not a mutable container. Its lifetime is proved
or retained in the same way. A view of mutable array storage can observe writes
to that storage; it is not therefore an immutable snapshot or transferable value.
List/string views instead retain immutable snapshots (§6).

Proposed representations, in 64-bit cells:

| Value | Cells |
| --- | ---: |
| borrowed reference | address: 1 |
| owning reference | address + root owner: 2 |
| borrowed slice | address + length: 2 |
| retained slice | address + length + owner: 3 |
| id | position + generation packed: 1 |

Specialization knows which representation a parameter receives. A non-retaining
call can borrow from an owning argument without a retain/release pair. A public
or indirect ABI must carry an explicit contract; the same source type does not
license silently guessing its cell width.

A borrow stored in an escaping value must be valid for that value's lifetime,
not merely for the constructing call. Proof must be independent of the edge whose
retain is being omitted. Unknown evidence causes conservative retention plus the
ownership check, or rejection if that cannot be justified. It never means safe.

## 4. Mutable ownership: exact proof obligation

A finite layout through `Ref`, `Slice`, `id`, `Ptr` or a container indirection does
not itself prove safe ownership. A cycle-capable type can be used with bounded
borrows; that does not authorize counted cycles.

### 4.1 Owner constraints

Every potentially counted owner in the mutable-reference domain has an implicit
static rank parameter. For each possible strong edge from holder H to target O,
require:

```
rank(H) > rank(O)
```

Use the **actual retained root owner**, not just the referent's source type.
Include owning containment, nested containers, references, slices of mutable
storage, and closure environments. A non-transferable COW buffer participates in
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

This is deliberately conservative. Arbitrarily deep mutable owning structures
that cannot satisfy finite inferred bounds use stores and ids, not a collector or
a runtime cycle check. The first private inference/summary binding is implemented
within the admission described in runtime-interfaces §9 and WORKLIST O03. Broader
generalization and stable export/ABI encoding remain incomplete; the obligations
above may not be weakened to make an example pass.

### 4.2 Interior-reference counterexample

If `p` owns both `child` and a reference-valued `saved` field, storing
`Ref(p.child)` into `p.saved` as an owning reference creates H → H. It rejects even
when the declared child type has no references. A proven nonowning version can
remain valid within a bounded extent. This is why referent-type reach alone was
removed from the initial proposal.

### 4.3 Closures

Capturing a button in an escaping environment E requires E → button. Storing that
closure back into the button requires button → E. The inequalities contradict.
A literal capture list makes this easy to diagnose, but hidden or passed callables
must obey exactly the same rule through their summaries.

```
let adder(n: U32): (U32): U32 = (do(x: U32) = x + n)
let tally(): (U32): Unit = do
  let c = counter { value = 0 }
  return do(k: U32) c.value += k end
end
```

`tally` can allocate a counter owner and an environment retaining it: E → counter.
It does not count the whole activation. Closures holding mutable references are
not transferable, but can escape safely within their own task when ranks permit.

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
| `s.view()` | immutable snapshot `Slice(U8)` |
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
borrowed actual place. An owning acyclic link is a checked reference with inferred
owner constraints. A potentially cyclic link is an id. World records can hold
stores of bodies and players, connected by `Id(Body)` and `Id(Player)`. No vtable,
inheritance system, garbage collector or object-specific destructor is introduced.

A stored closure can retain mutable state within its own task, subject to §4.
A table method receives a borrowed receiver rather than capturing its object.
These are different mechanisms with explicit ownership consequences, not two
names for a universal dynamic object graph.

## 10. Reclamation and the collector-free argument

An owner header carries its count and generated release operation. Generated
release code knows outgoing owning references; it is not tracing metadata used
by a collector. It never calls program code or follows borrow/id edges to free them.

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
Exact failure/abort cleanup and concurrent release rules remain implementation gates.

## 11. Source compiler obligations and effects

Extend existing source `PlaceId`/retained-access provenance, not VM cache allocation
or a new residual value IR. Required facts include root owner identity, borrow extent,
possible retained owner edges, callable world effects, ownership bounds and sharing
state. These are analysis facts, not additional source-value computations.

Order: establish value/place identity and retention demands; solve owner/borrow
constraints; choose owner roots and representations; materialize once; lower to
ordinary ABC and explicit continuations. Escaping storage starts in its final owner.
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
filename. Diagnostics should explain the escape, store, call or sharing operation
that required an owner/count/COW or made a proof fail.

## 12. Lowering and ABI boundaries

Borrowed frame/module references can continue using existing address instructions.
Owning references retain a root handle; counted slices add that handle to address
and length. Stores use segmented slots and generation checks. Strings/lists/tables
use the buffer representations above, not tracing heap objects.

A nominal store segment target is about 4 KiB with at least 16 elements, using a
power-of-two slot count. Large element types necessarily produce larger segments;
this is a tuning target, not a contradiction hidden in an ABI promise. Store layout,
release-header offsets, atomic API, OOM behavior and handle ABI need specification.

“No new instruction” is a lowering hypothesis: existing scalar/memory operations
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

- Returned local/by-value-parameter references; part references retaining the whole
  aggregate but not unrelated activation locals; addresses unchanged across escape.
- Borrow elision for non-retaining calls and closures, including stored borrows
  checked for holder lifetime and unknown-contract rejection.
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

## 15. Replacement map

| Existing document/claim | Replacement |
| --- | --- |
| syntax §§8.2–8.4, 9: lexical-only escapes/string-as-slice | owners, inferred borrows/counts, distinct COW strings and snapshots |
| syntax §7 | `..` and compound `..=` with preserved evaluation order |
| syntax §§8.7–8.8, 14 | explicit external-resource cleanup; invisible memory release; no finalizers |
| syntax §15: tracing GC, reference-semantic open words, filename profiles | one progressively typed Let, transferable any, value tables and frozen values |
| spec/memory/dynamic target | counted owners and immutable graphs; no tracing/safepoints/module trace roots |
| initial proposal: counted activations | escaping root values allocated separately from the start |
| initial proposal: type reach proves acyclicity | actual-owner strict-order constraints and immutable construction proof |
| initial proposal: removed slot references see replacement | nonescaping element borrows; ids for durable links |
| initial proposal: live length bounds ids | slot extent, occupancy and generation |
| initial proposal: no mutable ref implies sharing | transitive immutable-backing/world-access contract |
| initial proposal: switch counters to atomic on transfer | atomic shareable-buffer counters from creation |
| initial proposal: present SLet exactly equals count-free | independent capability facts; legacy implementation distinction is not target semantics |
| source partial evaluation | integrate owner proofs with existing place/provenance/demand model |
| tasks | shared values/immutable buffers; no copy(w) escape hatch or collector dependency |

The superseded documents are preserved under
`../research/archive/ownership-before-counted-design/`. Their representations and
collector policies are historical, not a second active design.

## 16. Explicit remaining specification work

The collector-free direction and proof obligations above are approved. The owner
layout, counter/overflow policy, iterative release, allocator and concurrency
algorithms are also already decided in the runtime contracts; this list does not
reopen them. Remaining binding/qualification and genuinely open interfaces include:

- broader inference/generalization and stable separate-compilation summary format
  beyond the implemented private source binding (runtime-interfaces §9);
- generalize the connected concrete source binding beyond its qualified records,
  fixed arrays, slices, callable environments and active tagged alternatives: resolve
  context-specific instances, persistent module holdings, containers/initialized-element
  loops and erasure; qualify broader shared memory orders and foreign teardown beyond
  the tested source/physical-layout clients;
- counted/reference/callable export ABI, raw-pointer capability boundary and dynamic
  encoding/profile revision (foreign code cannot be made safe by a documentation claim);
- exact copy-out and iteration mutation semantics, empty text/pattern cases, position
  capture result type, table builtin-name collisions and migration insertion history;
- capability-requirement syntax and implementation of the approved `.let`-only
  extension/import migration (no `.slet` alias);
- concrete suspension, concurrency publication/reclamation, group-bound summaries,
  foreign integration and shutdown ABIs implementing the approved [task semantics](tasks.md).

These are engineering specifications to finish under the no-collector constraint,
not permission to add a collector if implementation becomes difficult.
