# Implementer contract: primitive, owner and task interfaces

**Authority:** private layouts, call handoffs, state transitions and lock protocols.
[Ownership](owners-references-ids.md) owns language semantics;
[runtime-primitives.md](runtime-primitives.md) owns algorithms. Delivery status and
qualification belong in [WORKLIST](../WORKLIST.md), not duplicated test counts here.

**Implemented:** the C owner core, six source bindings, native lifecycle C entries,
and initial explicit-Rc lowering/checking (§§1, 3, 9). **Approved target:** container
and task interfaces (§§2, 4–8), except implementation facts explicitly identified.
**Gated:** the interfaces in §10. C fragments describing targets are not buildable
libraries or permission to add adapters. No public encoding is assigned here.

Retired v3 catalogs, release caches, prefix/slot registries and the implicit ownership
binding are preserved only in the
[documentation archive](../research/archive/docs-before-rc-consolidation/README.md).
They are not alternative implementations. The minimal revision-7/profile-4 C-entry
extension below is distinct from the withdrawn larger proposal.

## Current C-entry encoding boundary

The separately approved minimal revision-7/profile-4 extension is now implemented
in the assembler, loader/verifier and bytecode optimizer; see
[module-format.md §10](module-format.md#10-lifecycle-c-entry-relocations).
Section 10 declares C-entry image relocations, distinct from section-8 ABC code
identities. Targets have two address arguments, no results or hidden result storage,
and cannot be ABC call targets or exports. No instruction bytes or operand kinds
changed. Optimizer roots and index rewriting retain the distinct entry role.

VM image preparation eagerly prepares a separate native lifecycle image in **all four
execution modes**, installs actual C pointers in section-10 destinations, then prepares
ordinary execution. A genuine `void(context, object)` C wrapper provides verified
A/B/C home extents to the ordinary native body using the existing allocator and all
eight native registers. Images retain their lifecycle code until destruction. Failure
to seal executable memory publishes no VM image. An empty section 10 adds no entries.
Tooling residual IR and portable C still reject this ABI; executable-memory support
is required even for interpreted/threaded owning source.

`src/lifetime.c` additionally rejects ABC calls, abort/HALT, C-stack growth/shrink,
checked conversions, trapping integer operations and every foreign call except the
exact non-failing field-drop binding. Generated bodies use concrete
field addresses plus enqueues, with finite tag branches for active union payloads. This is not a termination/pointer-safety proof for
arbitrary handwritten bytecode. Their C stack storage is proportional to verified
home extents; no generalized native resource-bound qualification is claimed.

## 1. Owner core and source runtime bindings

`src/owner.h/.c` owns this concrete native layout (32 bytes on the qualified host;
not a wasm ABI assignment):

```c
struct abc_owner {
    union { uint64_t local; _Atomic uint64_t shared; } count;
    abc_drop_fields_fn drop_fields;
    abc_owner *next_dead;
    abc_owner_kind kind;
};
```

The object embeds this header first. Concrete layout supplies payload offsets and
outgoing field addresses; there is no stored payload offset, construction prefix,
universal TypeOps, ownership registry or traffic counter. `kind` and `drop_fields`
are immutable. The callback is `void(abc_owner_context *, abc_owner *)`.

- `abc_owner_alloc(bytes, alignment, kind, drop, out, error)` checks extent/alignment
  and returns one holding; failure leaves `*out` unchanged. Payload is uninitialized:
  the C caller must make fields cleanup-valid before publication or release. The
  source binding zeroes the payload before publishing the owner.
- `abc_owner_retain(owner, error)` requires existing protection, rejects zero and
  overflow, and never wraps. Local increments are checked; shared increments use
  a relaxed CAS loop. Immortal holds/releases do nothing. A live count never changes
  between atomic and non-atomic policies.
- `abc_owner_release(context, owner)` decrements/enqueues only. Shared decrement
  is release-ordered; 1→0 performs an acquire fence before payload inspection.
- `abc_owner_drain(context)` iteratively calls concrete field drops and frees through
  a thread-confined intrusive queue. Drops only enqueue children: no allocation,
  recursive drain, suspension, source callbacks or VM entry.
- `abc_owner_replace(context, slot, incoming, error)` retains incoming before
  replacing and enqueueing old. Failure leaves the slot/count unchanged; the caller
  exclusively owns the writable slot. Self-replacement obeys the same rule.

Use the thread-safe platform allocator and free on the thread observing final
release. Do not add remote-free queues or allocation caches without a measured need.
Source cell layouts are separate from these host C layouts.

The revision-7/profile-4 loader admits exactly these reserved extern contracts:

| Name suffix (`__let_rt_source_`) | Arguments → results | Responsibility |
| --- | --- | --- |
| `alloc` | `aiia → -` | Slot, complete extent/alignment, C drop pointer; zero payload then publish root |
| `hold` | `aa → -` | Retain incoming root before replacing concrete slot; overflow leaves it unchanged |
| `clear` | `aa → -` | Concrete object and C drop pointer; invoke then drain |
| `enter` | `aa → -` | Link embedded activation record and its C drop pointer |
| `leave` | `a → -` | Unlink the top activation, release fields, drain |
| `drop` | `aa → -` | Explicit queue context and concrete owner-slot address; null slot and enqueue only |

`a` is address, `i` integer. No host can rebind these; source extern impersonation,
retired names, wrong signatures and revision-6 lifetime imports reject. Ordinary
foreign synchronization remains unchanged. Staging still rejects foreign execution.
`drop` neither reads source TLS nor allocates/drains/calls ABC. Other bindings use
the active execution context; none is a dispatcher or runtime layout interpreter.

An owning activation embeds `{previous, drop}` (16 bytes) followed by its actual
root/value/result/scratch fields. Every acquire immediately publishes a cleanup-visible
holding; copies acquire before replacement and proven transfers clear their source.
Heap objects embed the32-byte core header, then concrete payload. Zero-size roots
retain distinct allocations or byte anchors. No parallel slot registry or progress
prefix exists. Failure unwinds linked records while ABC storage is still live, before
reset/result publication. No source defer runs and persistent ordinary image writes
are not rolled back. Allocation/retain exhaustion reports `ABC_NOMEM` at the original
FCALL. Successful return with an unclosed record fails without publishing results.
Reentry into the same executing VM rejects before stack reset. Foreign longjmp,
asynchronous interruption and general foreign/shutdown lifetime guarantees are not
provided by this binding.

The initial explicit-Rc slice is integration-tested in raw/optimized execution,
all four modes and both lifecycle banks, including failure cleanup and generated
C drains outside VM TLS. Qualification limits, measured costs and the sanitizer
toolchain blocker are recorded in WORKLIST and the
[cutover report](../research/experiments/runtime-owners/explicit-rc-cutover/README.md).
Earlier implicit-ownership results are not current API admission.

## 2. Split runtime, task and execution context

`src/execution_context.h` now separates the synchronous root's stack/cache/frame/error
state from session images/foreign bindings. Its worker owns the C release queue;
there is no second execution context or cleanup stack. TLS is rebound on source
entry and restored on exit,
including other-VM callbacks; no stack-local `abc_run` remains. This is not yet a
scheduler, migratable task or shared runtime. Complete the following responsibilities without
changing `include/abc.h` embedding semantics as an incidental refactor:

```c
typedef struct abc_runtime abc_runtime; /* images, workers, shared registries */
typedef struct abc_task abc_task;
typedef struct abc_worker abc_worker;
typedef struct abc_erased_value_ops abc_erased_value_ops; /* target erasure boundary only */

typedef struct abc_exec_context {
    abc_runtime *runtime;
    abc_task *task;
    uint64_t *base[3], *end[3];
    size_t depth[3];
    uint64_t h[4], cr[3];
    unsigned ca, cb, cc;
    abc_frame *frames;
    size_t frame_count, frame_capacity;
    abc_error error;
} abc_exec_context;
```

Task owns context/stack/frame storage. Worker owns the current-task pointer,
thread-local allocator/release queue and runnable deque. Runtime owns loaded immutable
module metadata, protected execution images, worker pool and timer/select coordination.
Group owns task/channel records structurally. A host `abc_vm` session owns a runtime
and a root execution task; public synchronous calls drive that root to completion.
Do not expose internal PARK as an `abc_status` error to existing embedding callers.

Set execution TLS on every scheduler entry and clear it on exit. Rebind it after
migration. Do not retain a pointer to a stack-local `abc_run` across PARK. Keep the
seven-register threaded ABI; access context at runtime boundaries through the bound
execution context/TLS rather than adding an eighth threaded value register.

`abc_execution_image.stack_end[3]` has been removed. Generated native/threaded guards
obtain bounds from the current execution context; interpreter bounds use that same
context. Session module-world and foreign/image bindings remain image-specific.
Bounds and mutable task data must continue to come from the current context. Preparation
must not specialize an error against the first task's capacity and share it with a
different-capacity task. Current symbolic headroom derives from verified function
requirements, not the root's capacity; entry/call guards check the active context.
Any future capacity specialization must key and validate its policy before entry.
Actual stack addresses are never part of a shareable code constant. Image/site metadata and mutable module-world
storage are separate; transitive world analysis governs access to the latter.

## 3. Explicit Rc layout and private handoff

**Implemented initial binding.** `Rc(T)` occupies one address cell naming the owner
header; concrete `T` determines the payload offset. Source Rc has no null variant.
Internal empty/moved slots use null solely for cleanup. `Ref(T)` stays one borrowed
address and Slice stays borrowed address/length; neither acquires an owner cell.

By-value inputs and results containing Rc use caller-allocated **typed owning-value
slots**, not inferred resource records for reference data. Argument copying initializes
these slots in source evaluation order while they are cleanup-visible. The callee
consumes incoming holdings and clears their source on transfer; entry failure leaves
caller holdings available to unwind. Result publication establishes holdings in
empty cleanup-visible caller storage. Pure scalar, borrowed Ref and other nonowning
transport keep their ordinary ABI. Callable environment argument 0 and the ABC
hidden-result convention retain their distinct meanings.

Copy actual owning fields, including independent fields whose handles alias. Capture
inputs before overwriting overlapping storage; acquire incoming holdings before
releasing old ones. Reused scratch/union storage is cleared according to its old tag,
zeroed, and given its new active tag before acquired fields become visible to cleanup.
Partial failure drops only established holdings in the active alternative. No runtime
layout interpreter, per-field registration or hidden borrowed-field preservation exists.

Transfers clear their source exactly once. The raw-copy/source-clear commit window
must be non-failing in every supported binding; instruction spelling alone is not a
proof. No callback or suspension may expose duplicate uncounted holdings. Ordinary
copies are correct without move elimination; an unproved move remains a retain/copy.

`placement.lua` consumes the checked program, emits a separate physical graph and
concrete active-tag C drops, and preserves original source identity for diagnostics.
Packed tags, aligned unions and ADDR2BITS/BITS2ADDR remain the canonical representation.
No owning field means no cleanup record, empty drop body or enter/leave pair. Root
allocation is explicit and immediate, never whole-activation counting or frame promotion.

Public/foreign Rc handoff, persistent owning modules, owning environments/results,
erased/container/task transport and owning snapshots remain gated. Existing borrowed
callables do not gain ownership by having a callable type. Generalized native resource
bounds, wasm/AOT ownership support and broad sanitizer acceptance are not established.

## 4. Containers and failure transactions

New `src/value_buffer.h/.c` and `src/store.h/.c`; generated source type specializations
supply element operations. Private APIs use pointers plus type metadata, not boxed
`Any` for every operation:

```c
typedef struct {
    abc_owner owner;
    size_t length, capacity;
    /* aligned elements follow */
} abc_value_buffer;

/* Target generic/erased buffer boundary, not an allocation header TypeOps. */
abc_status abc_buffer_copy(abc_exec_context *, const abc_erased_value_ops *element,
                           const void *src, size_t count, size_t capacity,
                           abc_value_buffer **out);
abc_status abc_buffer_detach(abc_exec_context *, abc_value_buffer *old,
                             const abc_erased_value_ops *element, size_t need,
                             abc_value_buffer **out);
```

`copy` produces a new holding, tracks copied initialized elements for rollback and
never mutates `src`. `detach` returns a new holding; its caller performs replacement
and releases old only after success. Unique in-place mutation is a separate checked
branch, so the helper cannot secretly mutate the old value before all checks pass.
Lengths/capacity must fit the source representation; host `size_t` is not permission
to exceed u32 string offsets. COW result/copy costs remain declared effects.

Store directory fields: segment-pointer array, directory capacity, slot extent,
live count, free-head index, slots-per-segment and element layout. Lookup computes
segment/slot by division/remainder by the prepared constant and checks extent,
occupied and generation before producing a borrow. Grow allocates new segments and
publishes the directory only after success. Remove drops the initialized element,
marks vacancy and links the slot; generation advances according to the source id
contract on reuse. Store copy duplicates slots/occupancy/generations, not segment
addresses. No permanent counted slot references are created.

## 5. Runtime operation request and ownership

New `src/task.h`, `src/task.c`, `src/channel.h/.c`, `src/task_select.c`.

```c
typedef enum { ABC_OP_DONE, ABC_OP_WAIT, ABC_OP_FAILED } abc_op_outcome;
typedef enum {
    ABC_TASK_NEW, ABC_TASK_RUNNABLE, ABC_TASK_RUNNING,
    ABC_TASK_PARKING, ABC_TASK_NOTIFIED, ABC_TASK_PARKED,
    ABC_TASK_FINISHING, ABC_TASK_FINISHED
} abc_task_state;

typedef struct abc_wait_node abc_wait_node;
typedef struct abc_op_ticket abc_op_ticket;
typedef struct abc_op_request {
    const abc_primitive_info *primitive; /* generated catalog entry */
    abc_task *task;
    uint32_t original_pc;
    uint64_t *inputs, *outputs; /* operation-frame cells, not helper locals */
    size_t input_cells, output_cells;
    void *prepared_payload;
    const abc_erased_value_ops *payload_ops; /* generic transport boundary */
    bool payload_owned;
} abc_op_request;

struct abc_wait_node {
    abc_wait_node *previous, *next;
    abc_op_ticket *ticket;
    abc_channel *channel;
    uint32_t case_index;
    unsigned direction; /* send or receive */
    bool linked; /* accessed under the channel mutex */
};

struct abc_op_ticket {
    abc_op_request *request;
    _Atomic unsigned completed; /* operation result committed, not yet safe to reuse */
    _Atomic uint32_t registrations_live; /* includes extracted timer callback ownership */
    _Atomic bool notified; /* exactly one final notification */
    uint32_t winner; /* NONE or case; select arbitration protects writes */
    abc_status status;
    abc_wait_node *registrations;
    size_t registration_count;
    abc_timer_registration *timer;
};

abc_op_outcome abc_task_try(abc_exec_context *, abc_op_request *);
abc_op_outcome abc_task_register(abc_exec_context *, abc_op_ticket *);
void abc_task_notify(abc_op_ticket *);
void abc_task_after_exit(abc_worker *, abc_task *);
```

`abc_channel`, `abc_timer_registration` and generated `abc_primitive_info` are
forward-declared private types. The task metadata is an approved target, not the
retired v3 owner catalog: it must describe input/result cells and holdings, memory
invalidation, allocation/failure, suspension and clobbers as required by
[runtime-primitives.md §1](runtime-primitives.md#1-integration-with-the-current-machine).
It assigns no independent scalar algorithm or opcode. A direct ticket has one registration; a select has
its fixed case count. Use a reserved UINT32_MAX winner for NONE and reject a source
case count that cannot be represented. Task operation-frame sizing uses checked
arithmetic and is included in resource accounting, not a VLA on the worker stack.

Request contains the semantic operation, group/channel/handle operands, prepared
payload/result storage and original source PC. It contains no borrowed pointer into
a C helper frame. The request is scoped to the task operation frame. The ticket
contains atomic completion state, result/status, request pointer and intrusive wait
registrations; a select ticket additionally contains winner index and case array.

`try` either commits exactly once (DONE), reports failure without partial publication,
or returns WAIT **without registering a waiter**. Before `register`, the generated
slow branch saves state and publishes PARKING. `register` rechecks readiness under
the relevant locks, then either completes or links the ticket. Both registered WAIT
and completion after PARKING return control through the scheduler PARK exit; do not
resume inline with a concurrently visible ticket. Immediate try-DONE skips this path.

Prepared send payload owns its holdings before registration. Commit moves them to a
queue/receiver; close/losing select releases them after deregistration. No caller
continues to believe a consumed payload is owned locally. Result storage becomes
initialized before completion publication. Its owner task copies/moves the result
through generated ordinary ABC result transport on resume.

## 6. Exact scheduling publication rules

A scheduler removes a runnable task under its deque mutex and transitions RUNNABLE
to RUNNING before entry. Exactly one queue owns a runnable task link. No waker acts
on a ticket twice: completion CAS or locked select-winner transition chooses one owner.

For notify after publishing result:

```text
loop:
    s = load(task.state, acquire)
    if s == PARKING:
        CAS(PARKING, NOTIFIED, release); on success return; else retry
    if s == PARKED:
        CAS(PARKED, RUNNABLE, acq_rel); on success enqueue_and_notify(); return
    otherwise: duplicate/protocol violation; never enqueue blindly
```

After backend entry returns PARK and no worker host execution remains:

```text
CAS(PARKING, PARKED, acq_rel)
if success: return without further task mutation
if observed NOTIFIED:
    CAS(NOTIFIED, RUNNABLE, acq_rel)
    enqueue_and_notify()
otherwise: protocol violation
```

Save stores precede publishing PARKING. Resume acquires task/result publication.
Queue mutex release/acquire protects queue links. Wakers retain valid ticket/task
storage through group lifetime and registration ownership. A task finishes only after
its active wait registrations are removed. FINISHED results remain in the group-owned
record for repeated joins; callers copy them, and group teardown drops the originals.

Worker idle uses a runtime wake mutex, condition variable and u64 generation. Producers
publish runnable work first, then increment generation and signal under the wake mutex.
A worker snapshots generation, checks local/stealable work, locks wake mutex and
rechecks generation before cond-wait. Waiting atomically releases that mutex. On
notification/spurious wake/deadline it retries work. Generation wrap requires an explicit
checked policy, not relying on subtraction across wrap. Timers use monotonic deadlines;
checked deadline arithmetic rejects overflow before registration.

## 7. Lock ownership and select algorithm

Lock rules (no nested locks except the listed case):

| Lock | Protects | Permitted nested lock |
| --- | --- | --- |
| select arbitration | select winner, multi-case registration/removal/commit | one channel mutex |
| channel mutex | ring, closed, FIFO waiter links | none |
| group registry | membership/cancelled flag, subgroup/channel registration | none |
| runnable deque | queue links | none |
| timer heap | deadline heap links | none |
| wake mutex | idle generation/condition | none |
| code construction | entry construction state | private emission only; no source execution |

Source execution, generated destruction, enqueue/wake, allocator calls and foreign
calls never run while channel/select/group locks are held. Required operation-frame
storage and payloads are prepared first. Timer processing extracts expired tickets
under the timer mutex, unlocks, then performs select arbitration. It does not retain
that mutex while acquiring channel/select locks.

Select registration holds arbitration, locks each distinct channel in turn, checks
readiness and installs registrations; no channel lock is held while taking another.
Random choice is among the observed ready cases, followed by readiness recheck before
commit. Ordinary operations encountering select nodes drop their channel lock and
retry under arbitration→channel. All select winner changes, including timers, hold
arbitration. Rendezvous pairs distinct unselected tickets and commits both while
holding arbitration and the one rendezvous channel lock. This prevents half-commits
without introducing per-ticket lock-order cycles.

On winner selection, registrations are logically inactive immediately via the winner
state. Physical removal takes arbitration and one channel at a time. Ordinary queue
walks skip completed select tickets under arbitration; they do not consume a losing
payload. Remove timer registrations separately under the timer lock after dropping
arbitration, using ticket completion to reject a concurrent extracted expiration.
Each published channel/timer registration holds one `registrations_live` unit. An
extracted timer transfers its unit to the callback, rather than dropping it when
removed from the heap. The winner also holds one cleanup unit until it has finished
unlinking losers. Drop units with acq_rel operations; after commit and the final unit
drops to zero, exactly one caller claims `notified` and invokes `abc_task_notify`
**after releasing all protocol locks**. Direct waits follow the same rule with their
single registration. This prevents ticket reuse while an extracted timer still has
a pointer to it, without blocking under arbitration or adding an epoch subsystem.
Do not notify at winner selection and then reuse the operation frame prematurely.
The resumed task invokes the handler only after this deregistration barrier.

Group cancellation: under group registry lock set cancelled and obtain protected
links to existing children/channels; unlock before closing channels or walking nested
groups. Registration under that same lock reads cancelled and inherits it before
publishing the object. The implementation uses group-lifetime-protected links and
iterative traversal, not a newly allocated snapshot array during cancel. Teardown
starts only after all member tasks/nested scopes and registrations have finished.
Lock-free traversal of a concurrently changing registry is forbidden; each next-link
read must be protected and teardown cannot reclaim enumerated records.

## 8. Backend entry/resume contract

Extend `src/execution_emit.h` with a private entry request/result, replacing the
current assumption that every backend exit is a completed public call:

```c
/* Task target only; synchronous C reclamation does not use this protocol. */
typedef enum { ABC_EXEC_RETURNED, ABC_EXEC_PARKED } abc_exec_disposition;
typedef struct {
    abc_exec_disposition disposition;
    uint64_t packed_error; /* existing status/reason/original-PC payload */
} abc_exec_exit;

typedef struct {
    uintptr_t entry;
    uint64_t *stack[3];
    uint64_t value_register[8]; /* threaded uses 0..6; slot 7 unused */
} abc_resume_state;

abc_exec_exit enter(const abc_exec_emitter *, abc_exec_context *,
                    const abc_resume_state *);
```

This is the C wrapper API. Internal generated handlers still use the established
native/threaded calling conventions; wrappers supply saved registers on resume.
This wrapper/disposition interface remains a task implementation target. Current
synchronous entry returns the existing packed status and does not retain resume
snapshots. The former ownership SERVICE binding has been removed: C reclamation
never needs it. Future PARK uses a backend-private out-of-band disposition, not a
stolen `abc_status` value or reinterpreted source result cell. Only a generated park
exit may set PARKED; the scheduler reads it after entry returns.

Task resume storage includes eight register slots and stack coordinates plus any
accounted primitive operation frame. The allocator's existing physical mapping
produces save/restore operations; it does not export a new residual SSA/value graph.
Interpreter suspension publishes logical stack state and its continuation PC; its
resume binding restores cache state or enters a designated canonical cache state.
The chosen cache transition must be explicit in generated bindings, not guessed by
reading poisoned inactive slots. Preserve existing capacity/error checks.

Modify `abc_execution_image` to own immutable code/tape allocations, stable entry
slots and preparation policy, not task stack addresses. Native lazy construction
writes fresh private page allocations, resolves labels, sets RX, then release-publishes
an atomic entry slot (implemented). Readers acquire entries; published bytes are never
reopened writable. Fallthrough crosses allocation boundaries through ordinary jumps;
stubs and bodies use separate construction regions. Preparation is serialized by an
image mutex, never held during generated execution. A failed preparation closes new
preparation for that image; previously published entries remain executable, including
cleanup. A compiled-but-unpublished version cannot be rebound as a prepared operation.
The emitter exposes regions and aggregate used/allocated bytes, not a fictitious
contiguous image. Lazy page fragmentation is measured and currently substantial.
Keep allocations
until all execution-image holdings are gone. Shared inline observations need their
own atomic state/target publication, not writes to bytecode. Threaded builds all tape
entries eagerly and uses the same resume metadata/ownership contract.

## 9. Source analysis interfaces

**Implemented initial boundary:** `Program.analyze` performs structural/type checking,
access analysis/validation and strong-cycle checking. The checked program owns its
results and named type definitions; shared `Ir.Fn`/type nodes do not carry mutable
proof annotations. `Program.select` selects Call/View/Code reachability independently
of ownership. `Placement.program` lowers declared types/operations; `Layout.physical`
and structural physical checking complete that boundary. See
[source compilation API](source-compilation-api.md#checked-program-and-physical-lowering).

`access.lua` checks CFGs referencing original typed statements, not a second expression
IR. Facts describe protected locations, permissions, callable identities and active
alternatives. Call-site activations have joined reachable inputs/results; caller memory
is not query identity. Only argument-reachable contents and named globals cross calls.
Private effects remain local. Scalar-only, global-independent boundaries check their
private allocations once rather than multiplying unrelated caller contexts.

Borrow protection is separate from allocation identity. Overlapping writes, value
redefinition and relevant scope exits invalidate protection; absent provenance is not
proof. Mutation effects and dynamic index overlap remain conservative. Erasure cannot
remove known borrow obligations. Opaque code without sufficient bounds rejects, rather
than gaining hidden ownership or being assumed nonretaining.

Callable facts preserve code identity and actual invocation-site environment storage:
value captures keep their formed snapshot; place captures read current contents. Local
ordinals from different contexts cannot collide. Formal callable invocations retain
ordered argument/result/effect obligations; forwarding through a higher-order argument
must reject the same escaping store as a direct call and accept supported nonretaining
controls. Do not substitute code-global capture unions or entry-time contents for live
captures. Recursion uses finite monotone bindings, not recursive source execution or
an arbitrary analysis-fuel cutoff. Public serialized summaries remain gated.

`ownership.lua` retains lifetime relations and iterative SCC checking of actual strong
Rc edges. Borrowed fields are never strong edges. Construction-only abstract cycles
are distinguished from mutation cycles; the former rely on immutable construction,
not a runtime cycle detector. General polymorphic/separate-compilation proofs remain
open. Whole-state queries, published snapshots/contents versions, carrier dependencies,
capability recovery, implicit promotion/preservation and resource-mode Ref ABIs are gone.
`Ty.Owned` remains callable specialization, not Rc.

Module aliases resolve the existing instance before requesting a value snapshot: equal
bytes are not alias proof. Field reads and function results are copies; source-visible
alias identity, initializer ordering and failure publication must remain intact.

Source elaboration preserves semantic Rc copies even where scalar SSA aliases would
otherwise suffice; register copies/spills do not retain. Packs/spread/operators still
elaborate through ordinary source IR. Only VM staging computes user values; neither
this checker nor a backend becomes another source evaluator.

## 10. Remaining hard gates and definition of a complete slice

The following are actual decisions, not ordinary implementation discretion:

- Public encoding/profile revision and metadata validation for new effects/types.
- Dynamic cell/interface representation and operator authority through structural joins.
- Borrow-carrying Rc payloads beyond the initial exclusion, explicitly owning
  environments/snapshots and public/foreign/erased Rc transport. Initial `Rc(value)`,
  named `r.borrow()` and private typed-slot handoff are settled, not open gates.
- Remaining polymorphic/recursive strong-edge/borrow-summary qualification,
  separate-compilation encoding and public FFI retention contracts. The old private
  implicit-owner binding is superseded, not authority to guess these Rc interfaces.
- Exact source abort/embedding shutdown behavior with foreign calls in flight.

Do not silently decide these by assigning a free opcode, adding fallback semantics or
turning an existing rejection into an unchecked path. Other structures/protocols above
are target interfaces to implement, not an invitation to redesign them per backend.

A vertical slice changes its authoritative producers/consumers together: operation
contracts, source lowering, checked module representation, verifier, interpreter, residualizer,
native/threaded bindings and focused tests. It removes replaced paths in that same
chunk. AOT follows its explicitly scoped support matrix rather than falsely accepting
unsupported operations. Validate at integrated boundaries; full suite/sanitizer/
performance work is milestone-based as stated in WORKLIST.
