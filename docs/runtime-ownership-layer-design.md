# Prepared runtime bindings and storage-based ownership

**Status: concrete proposal for approval, not implemented or an approved replacement
for the current runtime authorities.** Author: coordinating coding assistant.
Scope: WORKLIST E01–E03/E05, O04–O08, with the ownership boundary needed by C/T/D07.
Examined baseline: `c16666c8` (C release cutover). No runtime change accompanies this
proposal. WORKLIST remains the only implementation/completion ledger.

## 1. Decision and diagnosis

Use one model: **the compiler establishes resource-bearing storage; prepared runtime
bindings operate on that storage; the C runtime reclaims allocations.**

The current implementation makes source execution manage a binding protocol and a
second holding-slot representation. `lifetime.lua:allocate` calls `release_bind` on
each allocation. `release.c` searches a cache; `runtime_call.c` searches images again
to validate the returned handle. `abc_owner_slot` searches scope records. Every owner
pays for payload offset, policy and initialized-prefix state. Copy first duplicates
unacquired owner bits and subsequently repairs their ownership interpretation using
a prefix. Release specialization has its own field/data/progress emitter forms.

These are not required by reference counting or by ABC. Replace those contracts,
not merely their implementations. Preserve the checked counts, intrusive C queue,
immutable native publication, static acyclicity proofs and existing ABC machine.

The replacement has three boundaries:

1. **Source specialization:** actual-root proof, placement, representation and value
   construction/copy/move code. No runtime rediscovery of these decisions.
2. **Module preparation:** validate and bind runtime imports and restricted generated
   initialization/cleanup entries. Resolve once, before executable use.
3. **Execution:** ordinary ABC computation plus narrowly bound C operations on actual
   storage. Runtime state contains only facts that genuinely change at execution.

No runtime ownership graph, rank table, field-plan interpreter, tracing fallback,
second scalar implementation, second allocator or second native value IR is added.

## 2. Responsibility and lifetime table

| Principal | Owns | Must not own |
| --- | --- | --- |
| Source compiler | root identities, borrow proofs, holding effects, physical layouts, construction/copy/cleanup code | runtime refcounts or register allocation |
| Prepared module image | immutable allocation bindings, resolved runtime imports, generated runtime entry code | task stacks, current worker pointers, mutable counts |
| Execution context / future task | ABC stacks and explicit continuations, error state, cleanup-record chain, its mutable module world | executable publication or a cleanup evaluator |
| Worker | current execution binding, zero-owner queue and iterative drain | suspended task storage or source ownership inference |
| Allocation | count, immutable allocation binding, zero-owner queue link, value storage | source type operations, copy dispatch or per-activation state |

The present synchronous `abc_vm` remains the lifetime domain containing its images,
root context and worker. This does not require a new scheduler or public runtime API.
The future runtime/task split uses these same boundaries; this change does not build
unused scheduling objects. This does not claim existing ordinary source images are
fully shareable: native source entries currently embed image/world addresses. Until
E05 removes that coupling, those source images remain world-specific. Restricted
runtime entries have no mutable-world access and can serve cross-worker release
without changing source-world semantics. `module_enter` obtains the current image
from execution context, never a worker/world pointer baked into its cleanup code.

Loaded code and allocation bindings live until the domain is destroyed. Tasks,
module holdings and queues must be drained before images are freed. Do not unload
individual images while the domain is live. This deliberately avoids a second code
reference count on every object. Future exported handles must retain this domain;
raw owner pointers are not public handles. Until an explicit owning host API exists,
public calls cannot export owned source values. Existing pointer-only foreign APIs
remain subject to their existing contracts, not silently upgraded to owning handles.
Domain destruction requires quiescence: no executing callback/foreign call, registered
waiter or live child task. This proposal does not authorize asynchronous destruction
of a running VM, forced cancellation of foreign code or cross-domain raw owner transfer.

## 3. Source representation is selected before lifetime emission

Continue the existing order:

```
actual places and access summaries
  -> borrow/strict-edge solution
  -> root placement and physical specialization
  -> ordinary checked IR with explicit lifetime effects
  -> ABC -> interpreter/threaded/native execution
```

There is one canonical physical layout per specialization, shared by field access,
ABI transport, copying, allocation initialization and cleanup generation. It is not
reconstructed by residualization. `layout.lua` must cease treating every checked
`Ref` as one cell. Source types alone do not determine owning widths.

Native 64-bit physical contracts:

- Borrowed reference: target address. Owning reference: target address + root handle.
- Borrowed slice: target + length. Retained slice: target + length + root handle.
- Borrowed callable environment: code identity + environment address. Retained
  environment: code identity + environment address + environment root handle.
- Projections change target, never root. Module-backed access requires no count;
  an owning-compatible representation may use a null root for domain-lifetime data.
  A frame borrow cannot be widened this way to disguise an escape.
- Aggregate layout recursively contains these representations. A movable value is
  not the same thing as an addressable root. Published root storage never moves.
- A sum containing holdings reserves physical tag zero for cleanup-empty storage;
  active alternatives are numbered 1..N. Pointer-free packed sums need not change.
  This distinction belongs to physical specialization, not source syntax.

Root placement is Module, Activation, or Counted with an immutable local/shared
policy. Escaping roots are counted from creation. A mutable by-value parameter gets
an independent instance, not an alias to the argument; references copy access, not
the referent. Non-retaining calls may borrow under the existing elision proof.

Representation selection uses the existing source/checked IR and its specialization
machinery. It does not replay source bodies or introduce a residual ownership IR.
The source checker validates provenance/holding obligations before physical emission;
the physical checker validates the resulting explicit types, memory and call layouts.
All consumers use the same selected layout, rather than maintaining source and ABI
width assumptions independently.

## 4. Allocation binding and header

Choose a shared immutable **allocation binding**, not universal TypeOps:

```c
typedef void (*abc_storage_fn)(abc_owner_context *, void *storage);

typedef struct abc_allocation_binding {
    size_t minimum_payload_bytes;
    size_t payload_offset;
    size_t allocation_alignment;
    abc_owner_kind count_policy;       /* immutable local or shared */
    abc_storage_fn initialize_empty;   /* NULL for no initialization needed */
    abc_storage_fn drop;               /* NULL for no outgoing holdings */
} abc_allocation_binding;

struct abc_owner {
    union { uint64_t local; _Atomic uint64_t shared; } count;
    const abc_allocation_binding *binding;
    abc_owner *release_next;
};
```

On the present 64-bit ABI the header is24 bytes. This is a design calculation, not
an implemented measurement. Do not overlay the atomic count with the queue link or
tag pointers to save another word. Shared facts cost space per binding, not per object.

`payload_offset = align_up(sizeof(abc_owner), payload_alignment)`;
`allocation_alignment = max(alignof(abc_owner), payload_alignment)`.
Allocation checks power-of-two alignment, all size arithmetic, minimum payload size
and allocator rounding. Variable-sized buffers supply their actual payload extent;
a fixed object supplies its known size. Free uses the allocation base with the
platform allocator, so no generic per-object size field is needed.

This deliberately restores sharing of allocation facts. The last redesign was wrong
to equate shared immutable metadata with universal value operations. A descriptor is
not inherently bloat; making every allocation participate in value-copy dispatch and
making execution repeatedly discover that descriptor were the wrong responsibilities.

The binding has **no value-copy entry, source type identity, field list or erased
operation table**. `initialize_empty` is necessary to establish cleanup-safe storage
before a fallible constructor can run. It is not a source constructor and cannot
allocate or invoke user code. `drop` consumes only initialized outgoing holdings;
it does not free the containing allocation. C owns free and queue traversal.

Counting stays as approved: protected retain, no resurrection, checked overflow,
relaxed shared increment CAS, release decrement and acquire on zero. The policy is
never upgraded on a live object. Static immortal data uses no allocated owner; null
roots represent no holding. The immortal sentinel case, if retained internally,
never enters the allocation/free path.

## 5. Construction: cleanup-safe storage instead of prefix repair

Every registered storage region has a well-defined **cleanup state**, independent of
whether it contains a complete source value. An empty root cell is null and owns
nothing. This is established explicitly; arbitrary zero bytes are not inferred to
be initialized source values.

Initialization rules:

- Fixed records/arrays: generated `initialize_empty` initializes every root-bearing
  component needed by cleanup. Scalar bytes need not be initialized.
- Owning sums: initialize tag zero. No payload is inspected while tag is zero.
  Before activating an alternative, establish empty ownership components for that
  alternative, then set its active tag, then construct its fields. Errors during
  empty initialization cannot leak holdings because none have been acquired yet.
- Buffers: initialize committed length to zero. Capacity-sized element storage is
  not zero-filled. Cleanup visits only elements `[0, length)`.
- Closure environments follow the same aggregate rule; there is no special runtime
  closure release protocol.

**Copy never first installs unacquired root bits.** Copy scalar/borrowed components
with ordinary memory operations. For each new owning component, checked retain and
installation into its empty destination root cell happen in one C primitive. If
retain fails, that cell remains empty. Already installed fields are independently
cleanup-valid; there is no generic owner-prefix counter to repair the bit-copy.

Nested sums and aggregates use their own physical cleanup state. A buffer element is
constructed completely in protected temporary storage, then committed as described
below. Thus partial progress need not be permanently stored in every allocation.
A representation that genuinely needs a length/tag keeps it as value-specific state.

Source publication is separate: no incomplete value is readable by source code.
Compiler definite-initialization and access rules enforce that. Cleanup is allowed
to see the weaker cleanup-valid state after a failure.

## 6. Exact execution operations

The catalog remains authoritative. The following are logical primitive contracts;
C bindings supply the current context/error sink and any static binding operand.
They are not new ownership opcodes or operand kinds.

| Primitive | Dynamic inputs | Result/effect |
| --- | --- | --- |
| `allocate_into` | empty root-cell address, payload byte count | fallible; installs one new holding in that cell after empty initialization |
| `retain_into` | empty root-cell address, protected incoming owner | fallible; increment and install, or destination/count unchanged; null incoming is empty |
| `drop_slot` | root-cell address | clear, decrement/enqueue, drain; non-failing for valid storage |
| `move_bytes` | empty destination, source, byte count | move exact bytes then zero source in one non-failing call |
| `swap_bytes` | two storage addresses, byte count | exchange exact bytes in one non-failing call |
| `buffer_append_move` | element destination, source temporary, element byte count, committed-length address | move/zero then increment prechecked length in one non-failing call |
| `cleanup_enter` | cleanup-record address, storage address | initialize cleanup-empty storage and link record using its statically bound init/drop entries |
| `cleanup_leave` | cleanup-record address | check LIFO, unlink, drop storage, drain |
| `cleanup_apply` | storage address | invoke statically bound drop on that storage and drain, without unlinking its containing frame |
| `module_enter` | module cleanup-record address, module storage address | once-only initialize/register persistent module storage; same bound init/drop contract, module-image chain rather than task chain |
| `enqueue` | explicit owner-context address, owner | callback-only leaf: decrement/enqueue, never drain |

Core C interfaces (exact ownership of arguments, not a public embedding ABI):

```c
abc_status abc_allocate_into(abc_owner_context *, const abc_allocation_binding *,
    size_t payload_bytes, abc_owner **empty_slot, abc_error *);
abc_status abc_retain_into(abc_owner_context *, abc_owner **empty_slot,
    abc_owner *protected_incoming, abc_error *);
void abc_drop_slot(abc_owner_context *, abc_owner **slot);
void abc_move_bytes(void *empty_dst, void *src, size_t bytes);
void abc_swap_bytes(void *left, void *right, size_t bytes);
void abc_buffer_append_move(void *element_dst, void *temporary,
    size_t element_bytes, uint32_t *committed_length);
void abc_owner_enqueue(abc_owner_context *, abc_owner *);
void abc_owner_drain(abc_owner_context *);
```

Allocation initializes count/binding, invokes the non-failing empty initializer,
then stores the owner into `empty_slot`. All its fallible work precedes that store.
Retain checks the destination and count before changing either; null incoming needs
no count. Drop clears the slot before enqueueing and draining. The three byte-transfer
helpers require valid prechecked storage and do not report language failures. They
are separately declared primitives because their memory/publication contracts differ,
not because the runtime understands their source types.

`allocate_into`, `retain_into`, `drop_slot` require no scope identity or slot number.
The root cell is in actual value storage. A new allocation is installed in that cell
before the primitive succeeds, so a subsequent engine error cannot lose its holding.
No result-register-to-cleanup-registration gap exists.

`move_bytes` and `swap_bytes` are memory transfers, not runtime type interpreters.
The compiler supplies exact same-representation regions. They perform no field
inspection, counting or dynamic dispatch. Distinct regions must not overlap; exact
self-transfer is a no-op. Their contracts include exclusive destination access and
valid extents. A small fixed C scratch chunk suffices for swap; no heap allocation or
size-dependent host-stack allocation. They transfer bytes without interpreting scalar
or padding contents. All-zero moved-from storage is cleanup-empty only under the
selected physical representation (null root bits and zero empty sum tags); this is
not a portable promise for arbitrary host C structs. Owner headers themselves are
never moved/cleared by these operations. These operations cannot move an addressable
root whose location is observable. They move values only when source proofs permit.

For `buffer_append_move`, the compiler has checked capacity, destination extent,
length overflow and type compatibility before entry. The helper is just the
non-failing memory/length commit; no container policy, allocation or copy algorithm
is hidden inside it. After success, the buffer owns the element and the temporary is
empty. Before success, the temporary owns it. This one boundary prevents a trap or
lazy-preparation failure between storing the element and advancing length.

For replacement of a complete owning aggregate, construct the incoming value in
registered temporary storage. `swap_bytes(destination, temporary, size)` commits.
The destination now owns the new value; the temporary owns the old value. Cleanup of
the temporary releases the old. Failure before swap leaves the destination unchanged;
failure after swap cleans the old value without undoing the committed write. This
preserves existing no-effect-rollback semantics. A single root replacement can use
the same sequence; do not add a second replacement algorithm before measuring a need.

Direct ordinary stores can initialize empty scalar/root-free data. But no ordinary
instruction sequence may temporarily duplicate or orphan an acquired holding across
a possible stack check, lazy preparation, call, trap or park. Use the atomic-in-the-
execution-model operations above at such transfers; this is not hardware atomicity.
No asynchronous signal/foreign-longjmp cleanup is promised.

## 7. Cleanup records: actual storage, one chain

```c
struct abc_cleanup_record {
    abc_cleanup_record *previous;
    abc_storage_fn drop;
    void *storage;
};
```

A function with lifetime-managed local storage reserves a fixed cleanup storage block
in its existing C-frame layout, plus one record. That block contains the actual
values/temporaries requiring cleanup, not copies of their owner cells. Other locals
need not move into it. Generated cleanup knows this block's physical offsets and
uses ordinary loads/branches/loops; no offset list is interpreted at runtime.

`cleanup_enter` is bound to this block's initialize/drop code and fixed byte extent.
It checks frame-storage bounds once, initializes cleanup-empty state, and links the
record. A failed frame reservation/entry precedes resource acquisition. LIFO leave
checks the head in O(1). Reentering a live record is forbidden by the compiler-private
storage contract; do not preserve v3's linear duplicate-scope search or add a runtime
address registry. This explicitly narrows runtime validation of malformed raw pointer
clients: duplicate-link misuse is not promised to produce a diagnostic. Legal source
cannot produce it, and the lifetime IR checker must reject duplicate link paths.
Under the existing unsafe-pointer module model, the compiler also guarantees root-cell
address validity; this is not a new memory sandbox.

Normal lexical exits drop the relevant actual values and leave them cleanup-empty.
Normal function exit transfers results, unlinks/drops the record, then performs
ordinary RET. On failure, the execution driver walks records newest first while
C-frame storage is still valid, invokes their prepared drops, then drains and resets
ABC stacks. It does not scan operand stacks, execute source defers or roll back writes.

Registration makes this storage runtime-observable at every later failing boundary.
That is a retained-memory effect in the authoritative catalog and alias analysis,
not merely a comment on a pointer argument. Optimizers cannot sink root-field stores
past a possible error, omit them as dead local writes, or leave the sole authoritative
holding only in a cache register. Ordinary cached copies of root bits are non-owning
transport; the committed storage remains authoritative. Existing effect synchronization
must materialize relevant state before invocation/escape, without flushing unrelated
banks. Failure-injection tests must exercise optimized code, not only debug memory
layouts, to qualify this contract.

The callback takes an explicit worker owner-context at invocation. The record stores
no worker-local pointer, so task migration does not invalidate it. Parked task C
storage remains allocated and unmoved; cleanup records remain linked. Module state
and task result storage use the same initialized-storage/drop contract, with their
structural owner responsible for invoking it at teardown rather than a fake stack
scope. `module_enter` binds to the calling module image, checks its record/storage
extents there, and links into that image's persistent chain. It is emitted once by
that compilation's initializer, not on every global access or function call. Domain
teardown drops module chains before freeing any image. A source-call failure unwinds
the task chain, not published module holdings: earlier module writes remain visible.
Failed construction of a new global uses a task-owned temporary and commits by swap,
so a failed constructor does not corrupt an existing global. Generalized staging of
these pointers into another compilation still rejects; this is execution lifetime,
not frozen-byte transport. No second cleanup VM, worker cleanup stack or source TLS
rebinding is needed.

## 8. Calls, results and failure-safe handoff

Ordinary ABC CALL/RET/TCALL, independent return/destination banks and explicit
continuations remain unchanged. Ownership belongs to source physical signatures,
not cell transport. Register moves/spills do not acquire holdings.

For the new source ABI, a result containing holdings uses **caller-owned initialized
result storage**, passed as an explicit hidden address under the existing aggregate-
result convention. If any result needs this transport, the complete result tuple is
stored there. The caller registers/initializes that storage before calling. The
callee constructs locally and moves completed result bytes into it before normal
exit. A callee failure after publication still leaves a valid caller-owned holding,
which caller failure cleanup consumes. No unprotected owning result travels solely
through a result register. Pointer-free result ABIs remain unchanged.

By-value arguments are constructed as independent, protected caller temporaries as
required by source semantics. The callee borrows that physical argument storage for
the duration of the call; it acquires holdings only when it needs independent
retention. A counted parameter root is selected and allocated before its address is
passed. Borrow-elision can remove redundant copies/counts when existing proofs allow.
Callee entry failure therefore leaves all argument ownership in caller storage.

The hidden result storage is already a feature of the machine format, but this is a
new compiler-private source ABI convention. Direct and indirect signatures must
agree exactly; physical widths and hidden-result bytes are not guessed from `Ref`.
Owning functions are not exposed through the current pointer-only public call API.

Tail emission is permitted only when argument storage outlives the outgoing frame
and the caller's cleanup record can be left before TCALL. Result storage may be
forwarded. Otherwise emit CALL+RET, not a dangling tail transfer. This is an explicit
restriction of newly admitted owning source lowering; existing raw ABC and existing
non-owning tailcalls retain their contracts. Do not add tail packets, a second call
stack or host recursion to recover that optimization. Tests must report the stack
cost of owning recursion rather than claim constant-space tail execution.

## 9. Preparation and serialization: an explicit format decision

Runtime binding is image work, not executable source work. There is no runtime
`release_bind`, code-handle validation scan or compiler-visible release-handle cell.

Propose **format revision7**, retaining all revision6 instruction bytes/semantics.
Profiles1–3 keep their section sets. Profile4 adds required section10, **runtime import
bindings**, possibly empty. Revision6 ordinary modules remain supported unchanged;
old reserved runtime ABI v1/v2/v3 is rejected. New runtime imports use v4. This is a
proposed public format decision requiring approval, not an assigned current encoding.

Section10 is a u32 count followed by records sorted by extern index. Each has u32
extern index, u16 catalog operation ID, u8 binding class, u8 reserved-zero flags,
u32 payload byte length, then the class payload. Operation IDs come from the versioned
v4 catalog, not from source names. Classes proposed for this revision:

- 0, ordinary catalog primitive: empty payload.
- 1, allocation binding: u64 minimum payload bytes, u32 payload alignment, u32 count
  policy (0 local,1 shared), u32 initialize function index, u32 drop function index.
- 2, storage cleanup binding: u64 storage extent, u32 initialize function index,
  u32 drop function index.

`UINT32_MAX` means a proven unnecessary init/drop entry. The source compiler supplies
it only for storage with no relevant work. The loader validates layout arithmetic,
policy, exact signatures, indices, reserved fields, unique records and primitive/
binding-class compatibility. Every reserved import has exactly one binding; ordinary
host imports have none. Reserved extern names are unique `__let_rt_v4_` labels for
assembly/tooling, not a second encoding of operation identity or static operands.
The validated numeric catalog ID determines the exact signature and permitted binding
class. A prefix alone never grants a callable runtime operation. Multiple extern slots
may bind the same operation with different immutable operands. This avoids mangling
layout/function identities into names or parsing runtime symbol suffixes.

This serializes fixed allocation facts and code identities, **not ownership edges,
ranks, field lists, cleanup instructions or native pointers**. Existing code-address
relocations retain their exact ordinary-ABC identity semantics. No reinterpretation
of `.codeaddr` as a native callback pointer.

Functions referenced as init/drop entries have physical signature `(address context,
address storage) -> ()`, no hidden result area, and a restricted non-failing runtime
role. They cannot also be exported, reached by ordinary ABC CALL/TCALL/indirect code
relocations or invoked as source functions. The verifier checks that separation.
Their bodies are ordinary checked IR/ABC. They may use verified scalar/address/control
operations, loads/stores and catalog leaves allowed for that role. They cannot call
source ABC, allocate, retain with possible overflow, abort, park, or perform potentially
trapping operations. Initialization may only establish empty storage, not consume
holdings; drop may enqueue and clear holdings, not acquire them. The callback leaf
allowlist is enqueue plus non-failing raw memory operations: it excludes allocate,
retain, cleanup-enter/leave/apply, module-enter and any leaf that drains or invokes
another generated callback. Thus no recursive cleanup call chain can hide behind a
catalog import. Neither role may
access a mutable module world or capture a task/worker address. Direct global/image
access is rejected for these entries; layout and immutable scalar facts are embedded
constants. The compiler emits accesses through the explicit storage/context arguments.
Generated repeated-element traversal is a loop, not recursive host execution. Helpers
are flattened by the compiler where necessary.

Role validation is not a proof of arbitrary handwritten pointer code's memory safety
or termination. That remains the private compiler contract and existing unsafe-memory
embedding model. Do not claim protection from a malicious module merely because its
runtime entry signature matches.

During `abc_vm_load`, gather all referenced runtime entries, deduplicate by function
index, and eagerly prepare them as **one image-owned batch**. All source modes do
this. Pack entries into ordinary native code chunks, fix branches, seal RX, then
publish the bindings/image together. Failure discards the unpublished image/batch;
no owner can depend on it. Previously loaded images remain usable. Retry constructs
a fresh image. Preparation errors are load-time errors with binding/function location;
allocation/count errors during execution retain their originating FCALL location.
This intentionally replaces the old runtime-binding failure timing.

No no-JIT fallback is introduced: an AOT target supplies the same entry table as
statically compiled C functions. Missing AOT delivery or executable preparation
rejects loading these modules. Interpreted source still requires native cleanup when
using counted storage; this previously approved policy is retained and made explicit.

## 10. One computation/allocator, narrow execution bindings

Remove `release_glue`'s special meaning and RELEASE_FIELD/DATA/PROGRESS/ENQUEUE forms.
Runtime entries have two ordinary arguments, including context, and use the existing
symbolic computation/register allocator. The native C-entry wrapper initializes that
ordinary argument layout and calls the prepared body. Context is not pinned to r7;
normal liveness decides its placement. Native keeps eight value registers, threaded
source seven. No ownership-specific register convention is added.

The common native binding facility emits direct calls to catalog C helpers with
ordered captured inputs, declared results/clobbers and exact status propagation.
It serves normal source primitives and runtime-entry leaves. Backends do not implement
counting, construction or release algorithms independently. Choose fixed input cache
register positions r0..rN for each catalog call shape and a fixed result position where
needed. The existing allocator satisfies those constraints with its existing moves,
materialization and home spills; it preserves other live values. Generate a finite
call form per catalog operation/ABI shape, not a Cartesian product of input register
numbers or source types. Values stay in the same symbolic cache representation.
Helper calls use ordinary native ABI spills as required; fixed input positions do not
mean a second allocator or permanent register reservations. Threaded uses the analogous
seven-register mechanism and interpreter handlers preserve their declared cache state.
Source C adapters acquire the active context and pass it to the core helper; runtime-
entry leaves use their explicit context input. These are two execution bindings of
the same C operation, not duplicated ownership algorithms.

At image preparation, each runtime import becomes a bound operation with its catalog
identity, C target and immutable static operands. Interpreter dispatch is an indexed
call to that operation's generated adapter. It does not repeat symbol lookup, signature
checking or a giant runtime-operation switch. Native/threaded generation consumes the
same bound operation and synchronizes only its declared memory/argument/clobber needs.
Ordinary host foreign calls retain their separate conservative bridge and reentry
contracts. Trusted runtime primitives are not arbitrary host externs.

Generated runtime entries use fixed native homes and normal C ABI spills, never a
persistent ABC cleanup stack. Select a preparation admission limit of **4096 bytes
maximum native stack per generated runtime entry**, including wrapper, alignment and
worst-case per-stencil call/spill contribution, not just ABC home bytes. Reject an
entry exceeding it rather than silently falling back. C leaf helpers have fixed,
nonrecursive stack use separately audited in the platform binding. This is a new
explicit resource policy; it is not currently validated. It does not make arbitrary
host reentry or exhausted operating-system stacks safe. Embedders must provide the
normal documented host stack margin; source ABC capacity remains independently checked.

Preparation must compute this bound from actual emitted forms, not an estimate based
only on `max_a/max_b/max_c`. No failing stack guard or lazy compilation is reachable
once a registered cleanup entry begins executing.

## 11. Concrete lifecycles

### Escaping object and interior reference

1. Inference identifies root R and proves its outgoing edges; placement selects a
   counted R before any address publication.
2. Caller/activation result storage has an empty root cell and active cleanup record.
3. Bound `allocate_into(&temporary.root, sizeof R)` initializes R cleanup-empty and
   installs its initial holding. Ordinary code derives payload/interior addresses
   using the selected constant payload/field offsets.
4. Constructor writes scalar fields and retains outgoing references directly into
   R's initialized-empty root cells. Any error releases precisely installed fields.
5. Returned reference is `(interior address, R root)`, moved into protected caller
   result storage. No child allocation, activation counting or promotion.
6. Last holding of R reaches zero, its binding drops outgoing fields, then C frees R.

### Closure retaining that object

The environment E is a separate root. Its captured owning reference is initialized
empty, then `retain_into` establishes E -> R. Callable transport is code/environment/
root. Copies retain E, not every capture. Dropping E releases R through the queue.
Storing E back into R still rejects as a strict-edge cycle before lowering.

### Copy failing halfway

Destination is cleanup-empty. Each installed outgoing root is acquired atomically
with its field publication. Failure on the fourth retain leaves three installed
fields and the fourth null. Destination cleanup visits its actual fields and releases
three; no count repair, uncommitted pointer bits or initialized-prefix scan exists.
If constructing a replacement, the old destination remains untouched until swap.

### Buffer growth

Allocate a new buffer, committed length0. Copy one element into protected temporary
storage, then append-move it and advance length in one non-failing commit. Repeat.
Failure cleans the temporary and the committed prefix in the new buffer; old buffer
and its length remain unchanged. After success, swap the buffer holding into the
container's actual root cell and drop the old holding. Capacity/byte arithmetic is
checked before mutation. Unique in-place growth/mutation is a separately proven path,
not an implicit fallback that changes failure semantics.

### Task transfer

Only transferable data crosses. Shared roots use atomic counts from creation. A
prepared message payload is cleanup-valid task-owned storage before registration.
Queue commit transfers its bytes/cleanup responsibility under the existing channel
lock and publication protocol; it cannot fail halfway. A losing/closed send cleans
that same storage after deregistration. Displaced/closed payloads are detached while
locked, kept structurally alive, and dropped after unlocking; no drain runs under
channel/select/group locks. The receiving task obtains its holding before
publication says complete. No task pointer, worker pointer or C-stack address is
embedded in an allocation binding or suspended payload. Existing PARKING/PARKED/
NOTIFIED and ticket lifetime rules remain authoritative; this design does not replace
them with generic ownership callbacks. Code lifetime is protected by the runtime domain.

## 12. Replacement map

| Component | Required replacement |
| --- | --- |
| `frontend/ir.asdl`, `ownership.lua`, `check.lua`, `layout.lua`, `abi.lua`, `abc.lua` | canonical per-specialization owning representations, initialized-storage contracts, caller-owned owning results; no global Ref=one-cell assumption |
| `frontend/let/lifetime.lua` | emit actual-storage initialization/holding/commit operations; remove release-handle and scope/slot-number protocol |
| `gen/holding.lua` | generate separate empty initialization, ordinary known copy and restricted storage drop from the same physical layout; no bit-copy-then-prefix repair |
| `gen/runtime_primitives.lua`, generator, `frontend/let/runtime.lua`, `stage.lua` | v4 contracts/static binding declarations, effects, exact adapters and metadata-based staging allowlist; no runtime name/signature dispatch |
| `schema/module.asdl`, `module.c`, `memory_module.c`, `verify.c`, assembler/disassembler and module docs | explicit revision7 binding section/validation, runtime-role separation; preserve revision6 ordinary semantics |
| `src/owner.h/.c` |24-byte header/shared binding, actual-slot primitives, existing count memory orders and C queue; remove generic payload-offset/policy/progress words and scope membership search |
| `src/release.h/.c` | replace on-demand release-handle cache with batch runtime-entry preparation integrated with image loading; rename to runtime-entry binding if retained as a file |
| `src/runtime_call.c`, `gen/cold.lua`, `gen/banked.lua` | prepared primitive invocation, storage cleanup chain, no per-operation discovery or scope scan |
| `src/residualize.c/.h`, native/threaded emitters, stencil/form generators | normal two-input runtime-entry ABI and catalog call mechanism using existing allocator; delete release-specific forms/r7 reservation |
| `src/vm.c`, `vm_internal.h`, `execution_context.h`, `frontend/let/demand.lua` | load/publish bindings as an image unit; task and module storage-cleanup chains, once-only module initialization and domain teardown ordering; no new cleanup executor |
| `src/residual_c.c`, AOT tooling | same prepared entry/import table emitted as C; reject unsupported target until this binding exists, never use host-recursive source execution |
| frontend/runtime/ABI/module/continuation validators | replace old binding fixtures while retaining independent failure/count/bank/continuation regressions |

Do not preserve v3 behind wrappers or add old/new runtime mode switches. Keep the
published cutover evidence immutable. On approval, amend runtime-interfaces,
runtime-primitives, module-format and implementation-map together with this selected
design; this proposal itself is not a competing implementation ledger.

## 13. Conformance and cost acceptance

Correctness tests must cover all four source engines, both banks, raw/optimized:

- actual source factory/interior/capture/copy cases, not only manually built IR;
- owning/non-owning physical ABI distinctions, actual root retention and noncommutative
  scalar order/live prefixes around primitive calls;
- failure before allocation, during empty initialization admission/preparation, at
  each retain, after value commit, on callee entry/return, and at lazy source boundaries;
- an owning result published before subsequent failure; caller cleans it exactly once;
- zero/partial/full arrays and alternatives, protected genuinely uninitialized payload
  pages, unchanged destination on failed construction, committed writes survive later
  abort. Initialized tags/counts/root cells remain accessible: the old fixture protecting
  the entire payload because progress lived in the owner header must change with the
  representation. Preserve its safety property, not its obsolete metadata placement;
- long graphs, source exhaustion, maximum admitted native cleanup frame, cross-thread
  shared release, no callback TLS dependency and no allocations during drop/drain;
- task/message ownership transitions under the existing scheduler validation gates
  when tasks are implemented, not inferred from standalone pthread owner tests;
- failed batch/RX preparation leaves no loaded image/binding or changed older code;
- malformed static bindings/signatures/roles, revision6 compatibility and v1–v3 rejection;
- teardown drains all registered storage before freeing bindings/code.

Architectural tests: zero binding/name/signature searches after load; no dynamic
release-handle cells; no ownership-specific native forms; no duplicated cleanup root
representation; no generic prefix on every object; no source VM entry from cleanup;
no hidden result holding; no per-function executable page requirement. Verify actual
symbols/paths are deleted, not merely unused by the happy-path fixture.

Measure both mechanism and complete workloads. Retain the current baseline. Compare
in separate otherwise matched builds/processes, fixing API lookup positions, compiler
flags and workload inputs. Report distributions and host control, not a single ratio.
Separate load/preparation time from execution; isolate allocation, count, value-copy,
move/replace, callback and whole-drain costs; also measure actual source factories,
closures and buffers. Record header/alignment/initialization traffic, cleanup-frame
bytes, shared binding bytes, code body/allocated pages, allocations/counts, retained
memory, compiler cost and ELF growth. Compare pointer-free source paths too.

Structural expectations: no runtime binding searches;24-byte generic header; no
universal progress word; image-batched code pages. These are not measured speedups.
Explicit costs include empty-root initialization, indirect binding access at drop,
caller-owned result storage, whole-value swap/move traffic and rejected tailcall
optimizations. Reject unexplained common-path regressions rather than declaring the
architecture successful solely because it is cleaner or the tests pass.

## 14. Why these choices, rather than the nearby alternatives

- **Shared binding rather than direct release pointer plus per-object layout/policy:**
  the latter duplicated immutable facts and produced the48-byte header. This binding
  shares only allocation facts; known-value copy remains statically selected.
- **Empty ownership components rather than a universal committed-prefix counter:**
  actual fields describe which holdings exist, including replacement and variants.
  This costs initialization writes, but removes bit-copy/ownership-repair ordering.
  Buffers retain their natural committed length; their unused capacity is not cleared.
- **Generated storage drop rather than a runtime field table or duplicated slot list:**
  the same physical-layout producer handles ordinary values, frames and allocations.
  Cleanup reads real storage, while C owns the queue and freeing. There is no holding
  interpreter hidden inside a supposedly simpler helper.
- **Small C commit operations rather than a generic transaction engine:** move, swap
  and append are explicit bounded byte operations. They need no transaction records,
  rollback log, dynamic schema or error recovery after partial mutation.
- **Caller-owned results rather than a hidden holding in result registers:** stack
  exhaustion or lazy continuation preparation cannot strand an unregistered owner.
  The cost is result storage/transport and restricted tailcall eligibility, stated above.
- **Eager image-batched runtime preparation rather than per-allocation lazy binding:**
  one load-time failure boundary and no hot binding protocol. The cost is startup work
  even for unused counted paths; this is explicit, not a promised free optimization.
- **One domain lifetime rather than per-object code pinning or image-unload tracking:**
  images are deliberately retained to domain teardown. This may retain unused code
  longer, but prevents dangling release entries without another reclamation protocol.

These choices do not add a generic object model or scheduler. They replace the
organizing path of the current ownership layer. Source counted admission still
requires its actual representation producer, not just a successful low-level fixture.

## 15. Approval boundary

This proposal makes the choices rather than deferring them. The new decisions needing
approval are revision7/static runtime bindings and their eager preparation/failure
timing; shared allocation bindings with initialization+drop (not value-copy TypeOps);
cleanup-empty representations and atomic byte-transfer commits; actual-storage
cleanup records and removal of linear duplicate-link validation for raw pointer clients;
caller-owned owning results and tailcall eligibility; the native
runtime-entry resource limit. The native-glue-in-interpreted-mode policy, static
acyclicity, ordinary ABC semantics, C iterative release and task scheduling protocol
are retained, not reopened.

Remaining public FFI-owning handles, stable separate-compilation ownership summaries,
full task implementation and no-JIT/AOT availability stay explicit product gates.
They are not unspecified behavior inside this design: unsupported entry/exit cases
reject. Source counted admission opens only for physical specializations whose full
production, transport and cleanup path passes these gates. No implementation is
authorized merely by writing this proposal.
