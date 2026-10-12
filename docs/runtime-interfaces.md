# Implementer contract: primitive, owner and task interfaces

**Target private interfaces; partial owner/runtime-call binding implemented.** This binds the approved choices in
[runtime-primitives.md](runtime-primitives.md) to the current source tree. C fragments
are interface specifications, not drop-in patches. Use the names/responsibilities
below unless inspection reveals a material mismatch; discuss that mismatch rather
than adding an adapter or alternate subsystem. Public file-format/tag assignments
are deliberately not invented here; see §10's explicit release gates.

Execution work follows WORKLIST's substantial-chunk policy. Interfaces and their
producers/consumers/tests migrate together, not as unused helper libraries.

## 1. Authoritative primitive catalog

`gen/runtime_primitives.lua` is implemented for the initial owner/scope family,
consumed during generation, not at runtime. Container/task entries remain pending.
Each entry has these fields:

```text
name                 stable semantic operation name
inputs/results       ordered cell-layout expressions, including TypeOps parameters
holding_inputs       borrow | consume-on-success | consume-always for each holding
holding_results      new-holding | transferred-holding | borrow-with-origin
memory               exact read/write regions and invalidated facts
allocation           none | possible
failure              status/reason policy and original-site obligation
suspension           never | operation-ticket
clobbers             runtime-call binding clobbers, not source semantics
binding              allocation | retain | release | container | task operation
```

Generation rejects missing ownership/effect fields and duplicate names. Generate
immutable C metadata and frontend-readable declarations from it. `tools/opcodes.lua`
remains the public instruction/encoding authority; the primitive catalog does not
assign independent opcodes or create a second scalar computation. Existing arithmetic
still comes from `gen/semantics.lua`/shared computation.

Initial semantic families are owner allocate/retain/release, typed buffer copy/detach,
store grow/add/remove/check-id and task scope/spawn/join/channel/send/receive/close/
select/cancel/cancelled/yield. Families needing ordinary scalar control elaborate
through existing computation; a single opaque helper per language expression is
not the design. Do not generate register-specialized forms across the Cartesian
product of TypeOps, channel types and registers. Types/descriptors are bound operands.

### 1.1 Implemented initial call binding

The private runtime ABI uses reserved `__let_rt_v1_` symbols in the existing extern
section and existing FCALL.A/B instructions. There are no owner operand kinds,
owner opcodes, serialized ownership graphs or new module sections. Generated C
metadata validates the signature at module loading; unknown versions/signatures
reject. A host cannot override these bindings, and source `extern` declarations
cannot introduce them. This deliberately reserves the `__let_rt_` namespace; old
engines have no built-in implementation of these new symbols. Existing ordinary
externs and revision-6 encodings retain their behavior.

`frontend/let/lifetime.lua` emits ordinary checked IR using the shared builder.
Generated metadata supplies declarations and the staging allowlist. `runtime_call.c`
binds those calls through the current `abc_run`/VM context. The existing call-boundary
synchronization is retained; this initial binding does not claim specialized minimal
clobbers. Status and original call PC survive all four execution modes.

Each generated scope explicitly initializes a frame-storage record and its holding
slots. Allocation registers its first holding only after initialization succeeds;
retain installs a new slot only after checked increment; move transfers between
initialized scopes without changing the count. Normal scope exit releases slots.
On a failed VM call, only these registered holdings are released before stack reset.
No source deferred actions, effect rollback or stack-root scanning occurs. Persistent
module writes survive, and the VM can run another call. A successful return with an
unclosed holding scope instead fails without publishing results. Reentry into the
same executing VM rejects before resetting its stacks. Foreign longjmp/interruption,
workers/tasks and public exported owner handles are not supported by this binding.

Allocation failure and count-limit exhaustion use existing `ABC_NOMEM` resource
failure reporting; no new numeric language-abort reason is assigned, and counts
never wrap. See WORKLIST E01/E02/O04–O08 for admission and measurements.

## 2. Split runtime, task and execution context

`src/vm_internal.h` currently mixes stacks, interpreter cache, images and foreign
bindings in `abc_vm`. Introduce the following private responsibilities, without
changing `include/abc.h` embedding semantics as an incidental refactor:

```c
typedef struct abc_runtime abc_runtime; /* images, workers, shared registries */
typedef struct abc_task abc_task;
typedef struct abc_worker abc_worker;
typedef struct abc_type_ops abc_type_ops;

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

Current `abc_execution_image.stack_end[3]` and embedded task/image addresses need
replacement. Bounds and mutable task data come from the current context. Preparation
must not specialize an error against the first task's capacity and share it with a
different-capacity task. Include the stack-capacity policy in the image preparation
key initially; require a compatible policy before entry. Actual addresses are never
part of a shareable code constant. Image/site metadata and mutable module-world
storage are separate; transitive world analysis governs access to the latter.

## 3. Owner and type operations

Private files `src/owner.h`, `src/owner.c`, `src/type_ops.h` now implement the initial
owner core. The code currently takes an `abc_owner_context` plus the existing error
sink, bound by `runtime_call.c` to the synchronous VM; the task/worker signatures
below remain the target for §2's unfinished split. There is no second allocator.
The initial generated descriptors cover pointer-free local/shared payloads and a
confined single-owner holding cell. Generated initialization explicitly establishes
its outgoing field; generated release decrements/enqueues, never invokes source code.
General source-specialized copy/release, variants, buffers and arrays remain pending.

Immutable type
layouts feed generated holding-operation bindings; their generator is `gen/type_ops.lua`
with generated output under `build/generated/`, not handwritten per-backend destructors.

```c
typedef enum {
    ABC_OWNER_LOCAL, ABC_OWNER_SHARED, ABC_OWNER_IMMORTAL
} abc_owner_kind;

typedef struct abc_owner {
    union { uint64_t local; _Atomic uint64_t shared; } count;
    const abc_type_ops *ops;
    struct abc_owner *release_next;
} abc_owner;

typedef uint32_t abc_type_op_id;
struct abc_type_ops {
    size_t payload_size, payload_align;
    abc_owner_kind owner_kind;
    abc_type_op_id copy_holding, release_holdings;
};

abc_status abc_owner_new(abc_exec_context *, const abc_type_ops *,
                         size_t payload_bytes, abc_owner **out);
abc_status abc_owner_retain(abc_exec_context *, abc_owner *);
void abc_owner_release(abc_worker *, abc_owner *);
```

Owner kind is immutable descriptor information; descriptors distinguish local/shared
allocation policy even for identical source payload types. Initialize only the
selected union member. Never mix atomic and non-atomic accesses to one live count.
Immortal retain/release are no-ops. Payload starts at the aligned offset computed
from `sizeof(abc_owner)` and `payload_align`; do not assume header size is identical
on native and wasm32. Source cell layouts remain separate from host C layouts.

`new` returns one holding only after successful initialization; output is unchanged
on failure. It uses checked size/alignment arithmetic. Constructor cleanup tracks the
initialized prefix/fields explicitly; zeroed bytes are not proof of initialized holdings.
`retain` does not resurrect count zero. Local checked increment rejects UINT64_MAX;
shared increment uses a relaxed CAS loop with the same overflow check. Existing
holding/borrow protection is a precondition for retain. Shared release uses release
fetch-sub; the 1→0 path performs an acquire fence before inspecting payload.

Release processes the worker's intrusive zero-owner queue. Each selected release
operation visits only declared owning fields and enqueues newly zero owners. It does
not call source code, allocate, suspend or recursively invoke the VM. Type operation
identities bind to generated nonrecursive runtime holding operations; they are not
user-callable functions or tracing callbacks. Repeated fields use bounded loops over
initialized elements. Descriptor lookup at erased boundaries never changes this rule.

First allocator binding: use the platform allocator with thread-safe cross-thread
free; free on the worker observing the zero transition. Do not add worker allocation
caches/remote-free queues before measuring a need. If a later allocator requires
remote-free routing, dead allocation storage supplies links; source release semantics
and the nonallocation guarantee stay unchanged. This chooses a concrete implementation
of the approved cross-worker-free requirement, not a collector.

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

abc_status abc_buffer_copy(abc_exec_context *, const abc_type_ops *element,
                           const void *src, size_t count, size_t capacity,
                           abc_value_buffer **out);
abc_status abc_buffer_detach(abc_exec_context *, abc_value_buffer *old,
                             const abc_type_ops *element, size_t need,
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
    const abc_type_ops *payload_ops;
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
forward-declared private types. A direct ticket has one registration; a select has
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
A backend-private out-of-band disposition in task context distinguishes PARK from
the unchanged packed-error return. Do not steal an `abc_status` value or reinterpret
source result cells. Each entry initializes disposition to RETURNED; only a generated
park exit sets PARKED. Scheduler reads it after entry returns.

Task resume storage includes eight register slots and stack coordinates plus any
accounted primitive operation frame. The allocator's existing physical mapping
produces save/restore operations; it does not export a new residual SSA/value graph.
Interpreter suspension publishes logical stack state and its continuation PC; its
resume binding restores cache state or enters a designated canonical cache state.
The chosen cache transition must be explicit in generated bindings, not guessed by
reading poisoned inactive slots. Preserve existing capacity/error checks.

Modify `abc_execution_image` to own immutable code/tape allocations, stable entry
slots and preparation policy, not task stack addresses. Native lazy construction
writes a fresh allocation, resolves labels, sets RX, then release-publishes an entry.
Readers acquire entries; published bytes are never reopened writable. Keep allocations
until all execution-image holdings are gone. Shared inline observations need their
own atomic state/target publication, not writes to bytecode. Threaded builds all tape
entries eagerly and uses the same resume metadata/ownership contract.

## 9. Source analysis interfaces: no disconnected analysis layer

New `frontend/let/ownership.lua` is a client of existing source value/place/state
metadata, not another IR or evaluator. Its target interface is:

```text
root(place) -> RootId
borrow(origin, holder_extent, use) -> BorrowObligation
retain(holder_root, target_root, source_site) -> StrictEdge
join(states) -> state with union of possible edges/borrow obligations
instantiate(call_summary, actual_roots, result_destinations) -> obligations
solve(component) -> checked summary or diagnostic with edge/source witness
```

Root identity is original context/storage root, not projected element type. Ordinary
copy creates destination holdings and corresponding edges; projected refs retain the
same root. Keep borrowing obligations separate from strong edges. A borrow proof
cannot assume the very strong edge whose omission it is meant to justify.

For a finite inferred component, union all possible strict edges, run SCC detection,
reject self-edges/nontrivial SCCs and topologically order the remainder. Cross-function
summaries carry formal owner variables and inequalities; instantiate them at calls.
Recursive inference conservatively stabilizes these finite summaries, rejecting
unprovable demands rather than inventing runtime ranks or a cycle detector. Immutable
construction/COW has separate proof obligations and cannot point into mutable owners.
The approved first private binding is now implemented in `frontend/ir.asdl`,
`access.lua`, `ownership.lua` and `check.lua`: function summaries carry formal,
fresh, module and deferred owner variables, component results, holding obligations,
independent borrow evidence, strict edges and counted requirements. The existing
access worklist performs actual-root substitution and call-context qualification;
owner inference does not replay bodies. Fresh factory results remain distinct through
wrappers. Recursive allocation families fold at repeated call sites; equal family
names alone never prove an activation borrow. Actual same-activation formations
supply independent extent evidence. Relative access-origin markers are cleared at
call boundaries; formation proofs remain bound to their original extent and become
invalid when their holder becomes counted.
Formal-only inequalities remain conditional on borrowing/owning specialization;
instantiation with concrete counted roots checks their contradictions.

This is qualified source inference, not counted execution or a finalized public
summary format. `check.lua` rejects inferred counted requirements until source
placement, layouts and generated lifetime paths exist. The initial explicit checked-IR
runtime binding in §1.1 does not discharge that source admission. Broader polymorphic/recursive borrowing precision,
erased/dynamic/container admission and separate-compilation/FFI contracts remain
incomplete. See WORKLIST O03 and the ownership-inference evidence; a finite SCC
solver alone is not a complete ownership language implementation.

Packs/spread/operator elaboration stays in `semantic.lua` and ordinary IR builders.
Owner/effect queries attach to those operations; they must not rerun source computation.
Only the VM staging service computes user values. Borrowed/consumed/produced holding
annotations then drive ordinary lowering and explicit lifetime effects.

## 10. Remaining hard gates and definition of a complete slice

The following are actual decisions, not ordinary implementation discretion:

- Public encoding/profile revision and metadata validation for new effects/types.
- Dynamic cell/interface representation and operator authority through structural joins.
- Remaining polymorphic/recursive owner-summary qualification, separate-compilation
  encoding and public FFI retention contracts; the first private source binding above
  is approved and implemented, not awaiting another model approval.
- Exact source abort/embedding shutdown behavior with foreign calls in flight.

Do not silently decide these by assigning a free opcode, adding fallback semantics or
turning an existing rejection into an unchecked path. Other structures/protocols above
are target interfaces to implement, not an invitation to redesign them per backend.

A vertical slice changes all authoritative producers/consumers together: catalog,
source lowering, checked module representation, verifier, interpreter, residualizer,
native/threaded bindings and focused tests. It removes replaced paths in that same
chunk. AOT follows its explicitly scoped support matrix rather than falsely accepting
unsupported operations. Validate at integrated boundaries; full suite/sanitizer/
performance work is milestone-based as stated in WORKLIST.
