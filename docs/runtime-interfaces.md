# Implementer contract: primitive, owner and task interfaces

**Connected source ownership slice implemented.** The v3 catalog/dispatch,
release preparation/cache, scope-slot/prefix protocol and compiler lifetime client
in §§1, 1.1 and 3 below remain historical, not implementation instructions. Their
replacement is the concrete source materializer and six narrow bindings described
below. The large revision7/v4 proposal remains withdrawn. Unrelated task/scheduler
target protocols are unchanged; WORKLIST E/O records incomplete general admission.

The remaining target interfaces relate the approved choices in
[runtime-primitives.md](runtime-primitives.md) to the current source tree. C fragments
are interface specifications, not drop-in patches. Use the names/responsibilities
below outside the explicitly retired ownership binding; discuss material mismatches rather
than adding an adapter or alternate subsystem. Public file-format/tag assignments
are deliberately not invented here; see §10's explicit release gates.

Execution work follows WORKLIST's substantial-chunk policy. Interfaces and their
producers/consumers/tests migrate together, not as unused helper libraries.

Current C core (`src/owner.h/.c`):
`abc_owner_alloc` takes the complete allocation extent/alignment, local/shared policy
and optional C field-drop function. The concrete object embeds `abc_owner` first;
its C layout supplies field offsets. No per-owner payload offset, construction prefix,
type descriptor or instrumentation counters remain. Retain needs only the owner/error
sink. Release enqueues into an explicit thread-confined context; drain invokes field
release and frees iteratively. Retain-before-replace is provided. The C caller must
initialize fields before release/publication. The source binding zeroes all payload
holdings before publishing the first root. The standalone core passes
113 checks, focused ASan/UBSan/LSan and a128KiB host-stack run; the existing full
incremental suite also passes. Native header is32 bytes. Evidence:
`research/experiments/runtime-owners/core/`. Connected source evidence is separate:
`research/experiments/runtime-owners/source-cutover/`.

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
exact non-failing field-drop binding. Generated bodies are straight-line concrete
field addresses plus enqueues. This is not a termination/pointer-safety proof for
arbitrary handwritten bytecode. Their C stack storage is proportional to verified
home extents; no generalized native resource-bound qualification is claimed.

## Current concrete source binding

`frontend/let/placement.lua` consumes the exact checked program and produces a
separate physical graph, structurally checked without repeating ownership inference.
Counted local roots allocate from creation. Context-dependent unresolved instances
reject rather than promote an allocation family. References carry data/root-owner;
projections preserve the root. Proven pointer-free borrowed functions use one-cell
access arguments, preserving `InPlace` lifetime constraints in physical IR.
Concrete records/arrays/slices and callable environments carry their actual holdings.
Owning results use an appended caller-owned result-record pointer; callable environment
argument0 and the existing ABC hidden-result convention retain their meanings.

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
holding; copy acquires before replacement, single-use same-loop moves clear source.
Heap objects embed the32-byte core header, then concrete payload. Zero-size roots
retain distinct allocations or byte anchors. No parallel slot registry or progress
prefix exists. Failure unwinds linked records while ABC storage is still live, before
reset/result publication. No source defer runs and persistent ordinary image writes
are not rolled back. Allocation/retain exhaustion reports `ABC_NOMEM` at the original
FCALL. Successful return with an unclosed record fails without publishing results.

Factories, replacement/saved accesses, recursion, closure/partial/opened captures,
indirect owning and multi-result returns, arrays and slices execute in raw/optimized
four-mode tests. Acquisition/allocation failures, traps, stack exhaustion and RX
publication failure are tested. See the source-cutover evidence for exact counts and
focused sanitizer limits. Public owning/foreign transport, persistent owning modules,
erasure, owning variants/containers/tasks, context-specific physical cloning and
unified executable `.let` remain unavailable. This is not completion of general
ownership or the library/task runtime.

## 1. Historical retired primitive catalog

`gen/runtime_primitives.lua` is implemented for the initial owner/scope family,
consumed during generation, not at runtime. Container/task entries remain pending.
Each entry has these fields:

```text
name                 stable semantic operation name
inputs/results       ordered cells, allocation facts and explicit holding/erasure operands
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
product of source types, channel types and registers. Layout/operation bindings are operands.

### 1.1 Historical retired owner/holding call binding

The private runtime ABI uses reserved `__let_rt_v3_` symbols in the existing extern
section and existing FCALL.A/B instructions. There are no owner operand kinds,
owner opcodes, serialized ownership graphs or new module sections. Generated C
metadata validates the signature at module loading; unknown versions/signatures
reject. A host cannot override these bindings, and source `extern` declarations
cannot introduce them. This deliberately reserves the `__let_rt_` namespace; old
engines have no built-in implementation of these new symbols. Transitional v1/v2
ABIs are removed, not reinterpreted: their modules reject and must be rebuilt.
Existing ordinary externs and revision-6 encodings retain their behavior.

`frontend/let/lifetime.lua` emits ordinary checked IR using the shared builder.
Generated metadata supplies declarations and the staging allowlist. `runtime_call.c`
binds those calls through persistent `abc_exec_context` TLS. The existing call-boundary
synchronization is retained; specialized minimal clobbers are not claimed. Status and
original call PC survive all four execution modes. Thirteen operations include
`release_bind a -> a` and `owner_new aiiiia -> a` (scope, slot, bytes, alignment,
count policy, prepared release handle). Universal `type_bind` and allocation TypeOps
are gone. Known copy code is selected directly by the compiler, not through a
runtime descriptor. Erased-value operation descriptors are a separate, pending binding.

Each generated scope explicitly initializes a frame-storage record and its holding
slots. Allocation registers its first holding only after initialization succeeds;
retain installs a new slot only after checked increment; move transfers between
initialized scopes without changing the count. Normal scope exit releases slots.
On a failed VM call, only these registered holdings are released before stack reset.
No source deferred actions, effect rollback or stack-root scanning occurs. Persistent
module writes survive, and the VM can run another call. A successful return with an
unclosed holding scope instead fails without publishing results. Reentry into the
same executing VM rejects before resetting its stacks. Foreign longjmp/interruption,
scheduled tasks and public exported owner handles are not supported by this binding.

`release_bind` synchronously validates and prepares a private release realization
before returning its handle. Preparation uses fresh native allocations and publishes
only after RX sealing succeeds. A failed realization is discarded; existing source
and release code remain executable, and retry can prepare a fresh realization. The
error reports the original binding FCALL, not the helper-definition PC. No host C
compiler or dependency on `abc-opt` is introduced.

This preparation is required even for interpreted/threaded source. A platform without
executable-code preparation needs an AOT release binding (not implemented); there is
no ABC cleanup-engine fallback. Count/slot mutations enqueue zero owners, and the
C runtime drains at drop/leave/failure boundaries. Each prepared outgoing routine
returns before the next runs; children only enqueue. Normal native spill frames,
not task ABC storage, hold temporary values even after source stack exhaustion.
No SERVICE exit, reclamation register snapshot, pending descriptor or separate
cleanup execution context remains. Source records stay readable until consumed.

Allocation failure and count-limit exhaustion use existing `ABC_NOMEM` resource
failure reporting; no new numeric language-abort reason is assigned, and counts
never wrap. See WORKLIST E01/E02/O04–O08 for admission and measurements.

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

## 3. Historical retired allocation-release binding and erasure target

`src/owner.h/.c` owns allocation, checked counts, explicit construction state, holding
replacement and the intrusive C drain. `src/release.h/.c` binds portable release
identities to direct callable entries. There is no universal allocation TypeOps bundle,
second allocator or layout-plan interpreter. The full task/runtime split remains pending.

`gen/holding.lua`, called by `frontend/let/lifetime.lua`, independently generates:

- Known copy functions, only when requested, called directly through ordinary source
  calling conventions. They transport payload bits and commit each successful retain;
  failure releases only the acquired prefix. There is no runtime copy lookup.
- Private portable release bodies, using existing checked IR/ABC and `.codeaddr`
  identities. Their selected owning offsets are code constants, not a runtime table.
  `release_bind` forbids ABC callbacks and allocating/failing effects, then the existing
  symbolic computation/allocator eagerly realizes every branch with a direct C ABI.

The callback is `void(abc_owner_context *, abc_owner *)`. Its native wrapper reserves
one normal frame for allocator-selected homes/spills. Native slot7 carries the explicit
runtime-context argument; slots0–6 are allocated by the existing allocator. This is
not a hidden ABC cell, a new allocator, or an eighth threaded value register. Leaf
holding operations call C directly without foreign-bridge dispatch or bank flushing.
The callback does not enter any source engine, rebind source TLS, interpret a plan,
allocate or recursively release. Independent-context tests invoke it with source TLS
unset and verify that the VM context remains unchanged.

The current layout producer handles client-selected fixed owning cells. Checked-IR
fixtures additionally qualify native branch/initialized-element-loop execution through
ordinary scalar/address/control operations and direct C leaf bindings. General source
representations, variants/arrays/containers and erased-value copy operations remain
pending. The private checker is not a termination or pointer-safety verifier for
arbitrary handwritten bytecode; broad native spill/resource bounds remain an admission
obligation before generalized source counted execution can open.

Current native owner layout (48 bytes; not a wasm ABI claim):

```c
typedef void (*abc_release_fn)(abc_owner_context *, abc_owner *);
struct abc_owner {
    union { uint64_t local; _Atomic uint64_t shared; } count;
    abc_release_fn release_outgoing;
    struct abc_owner *release_next;
    size_t payload_offset;
    uint64_t initialized;
    abc_owner_kind kind;
};

abc_status abc_owner_new(abc_owner_context *, size_t bytes, size_t alignment,
    abc_owner_kind, abc_release_fn, abc_owner **out, abc_error *);
abc_status abc_owner_retain(abc_owner_context *, abc_owner *, abc_error *);
void abc_owner_release(abc_owner_context *, abc_owner *); /* decrement/enqueue only */
void abc_owner_drain(abc_owner_context *);
```

The image owns prepared release-code allocations/cache entries until teardown; an
owner stores its callable release behavior, not copy/size/alignment dispatch. General
exported owner/image retention is not implemented. Count policy is immutable per
allocation, including identical payloads under different policies. Initialize only
the selected union member. Never mix atomic and non-atomic accesses to one live count.
Immortal retain/release are no-ops. Payload offset comes from checked alignment of
`sizeof(abc_owner)`; construction progress is explicit header state, not zeroed payload.
This costs16 more header/state bytes than the earlier24-byte header plus8-byte prefix.
Source cell layouts remain separate from host C layouts.

`new` returns one holding only after successful initialization; output is unchanged
on failure. It uses checked size/alignment arithmetic. Constructor cleanup tracks the
initialized prefix/fields explicitly; zeroed bytes are not proof of initialized holdings.
`retain` does not resurrect count zero. Local checked increment rejects UINT64_MAX;
shared increment uses a relaxed CAS loop with the same overflow check. Existing
holding/borrow protection is a precondition for retain. Shared release uses release
fetch-sub; the 1→0 path performs an acquire fence before inspecting payload.

Release processes the worker's intrusive zero-owner queue. Each selected release
operation visits only declared owning fields and enqueues newly zero owners. It does
not call source code, allocate, suspend or recursively invoke the VM. Prepared release
entries are compiler-private runtime code, not user callbacks or tracing functions.
Repeated fields use loops bounded by explicit initialized state. Descriptors at erased
boundaries must obey the same nonrecursive/nonallocating destruction contract.

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
`access.lua`, `ownership.lua` and `program.lua`: program-local function summaries carry formal,
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

These are source inference facts, not a finalized public summary format.
`check.lua` performs structural/type checks only. `program.lua` explicitly runs
analysis and owns the results for the completed graph; it never publishes proofs on
shared function nodes. `layout.lua` selects borrowed versus owning representation;
`placement.lua` consumes counted facts and checks supported physical admission.
The current concrete source binding above, not historical §1.1, implements the first
connected executable slice. Broader polymorphic/recursive borrowing precision,
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
