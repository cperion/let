# Runtime primitives and resumable execution

**Authority:** selected algorithms and data structures. The C owner core, iterative
release, six bindings and initial private explicit-Rc source slice are implemented.
Container/task algorithms below remain approved targets, not executable support.
[Runtime interfaces](runtime-interfaces.md) owns concrete layouts/signatures and
state/lock protocols; [ownership](owners-references-ids.md) owns source semantics.
Do not duplicate retired ABI catalogs here. Qualification, costs and remaining
implementation gates live in WORKLIST E/O/C/D/T/P/W; initial Rc qualification does
not establish task concurrency, owning public transport or broad sanitizer acceptance.
Changes to the selected algorithms require discussion, not an alternate backend design.

Authorities: [ownership](owners-references-ids.md), [tasks](tasks.md),
[operators](operators-and-blocks.md), [spread](spread.md). Live delivery tracking:
[WORKLIST.md](../WORKLIST.md), E and the linked O/C/D/T/P/W packages.

## 1. Integration with the current machine

Current anchors are `src/execution_emit.h`, `src/residualize.c`,
`gen/execution_forms.lua`, `src/threaded.h`, `src/native_image.c` and the portable-C
emitter. The shared residualizer/allocator remains authoritative. Threaded has seven
value registers; native has eight. Eager threaded tape is not lazy bytecode execution.

Spread/packs/import spread disappear during elaboration. Trailing blocks become
ordinary lambdas. Statically resolved operators become ordinary method calls.
Container types specialize sizes, offsets and holding operations. No runtime pack,
operator-specific opcode family, second scalar algorithm or second allocator is added.

Classify actual runtime operations, not source feature names:

1. **Ordinary computation:** existing typed arithmetic, branches, addresses and memory.
2. **Non-suspending primitives:** allocation, holding changes, atomic transitions,
   cancellation query and completed-operation paths. These return without parking.
3. **Suspendable operations:** completion/error/pending outcomes with an explicit
   scheduler-return boundary. A C helper never parks with its host frames retained.

Each authoritative primitive contract specifies cell inputs/results, borrowed/consumed/
produced holdings, memory reads/writes/alias invalidation, allocation/failure effects,
register clobbers and suspension class. Source analysis, verifier/lowering, shared
execution computation and emitters consume the same contract. A runtime call is not
an excuse to discard all facts or flush all stacks; synchronize exactly its declared
live inputs/clobbers and retained accesses.

Public opcode numbers, concrete C signatures and serialized metadata are binding
work, not settled by this document. No existing foreign-call ABI is silently reused
for parking, no old profile-5 file is reinterpreted and no hidden C cells are added.

## 2. Owners and semantic holdings

The concrete header is defined once in
[runtime interfaces §1](runtime-interfaces.md#1-owner-core-and-source-runtime-bindings):
count, direct field-drop entry, intrusive queue link and immutable count policy.
Construction state resides in cleanup-valid concrete fields/active tags, not a header
prefix. Allocator metadata is separate. Confined/plain and shareable/atomic count
policies never switch on a live allocation.

Do not put a universal `TypeOps` object on every allocation. Allocation destruction,
value copying and layout are distinct concerns. The allocation carries only its
direct outgoing-release behavior and necessary count/queue/policy fields.
Size/alignment/policy are explicit allocation inputs. Known-type copy/construction
code is selected directly by the compiler, independently of allocation release.
Only genuinely erased values or generic runtime transport boundaries need a narrowly
scoped value-operation descriptor; that separate descriptor is not implemented yet.

Section-10 C-entry relocations resolve through the image into a direct C-callable native
entry. Native addresses are process-local bindings, never serialized. Preparation uses
the existing shared symbolic computation/allocator, not a host C compiler or a second
value IR. All source execution modes, including interpreted, prepare this glue before
allocating an owner. Platforms without executable-code preparation require an AOT
binding; there is no ABC cleanup-engine fallback.

Ref/Slice values are borrowed carriers, never conditionally owning representations.
Rc construction explicitly selects a counted root; Rc copies retain that root and
drops release it. Interior projections only borrow. The concrete root-handle and
failure-safe private handoff are fixed in runtime interfaces §3, not new algorithms.
There is no escape-selected allocation, activation counting, late promotion or
pointer repair.

Counting rules:

- A non-retaining call borrows under an existing live holding, with no retain.
- A new independent holding increments; a move transfers without incrementing.
- Register/stack transport and spilling do not create semantic holdings.
- Shared increment is a checked atomic update; overflow aborts, never wraps.
- Shared decrement uses release ordering; zero transition acquires before destruction.
- Proof-driven count elision must preserve all task/borrow lifetime obligations.

Zero-count owners enter a thread-local intrusive release list. The loop removes an
owner, releases its outgoing holdings, then frees it. Newly zero owners are appended,
not recursively destroyed. It allocates nothing and invokes no source callbacks.
Cross-worker freeing uses the allocator integration in §8, not a source destructor.
Prepared release routines return to this C loop without recursive host release.
They use a normal native spill frame, not persistent ABC cleanup stacks or a second
VM context. Reclamation does not require SERVICE/PARK exits or register snapshots.
The current compiler-private generator supplies concrete owning offsets and finite
active-tag branches, qualified with actual source-produced layouts and failure cleanup.
Fixed arrays are statically traversed. Dynamic initialized-element loops and general
container layout production remain separate work; historical checked-IR loop fixtures
are not their source integration evidence.

## 3. Concrete containers

### Lists

```text
owner header | length | capacity | aligned elements[]
```

Type specialization fixes element stride and copy/release operations. `List(U32)`
has no per-element type dispatch/release; `List(String)` has statically selected
holding operations; `List(Any)` uses its genuinely dynamic representation.

### Strings

```text
value: buffer pointer + packed offset/length
buffer: owner header + capacity + bytes[]
```

Literal buffers are immortal. Substrings retain a buffer and adjust offsets. No
conversion to a borrowed mutable byte slice is implicit.

### Stores

A growable directory points to separately allocated, nonmoving, fixed-size segments.
Segment slot count is a type-layout preparation constant. Slot layout:

```text
generation | occupied | free-list link when vacant | aligned element storage
```

Directory growth never moves slots. Ids remain position32/generation32; access checks
extent, occupancy and generation. Store copies allocate independent segments and
preserve positions/generations. Existing generation-wrap limitations remain explicit;
this layout does not promise eternal stale-id detection. Temporary slot borrows and
removal/replacement proofs follow the ownership spec.

### COW write algorithm

1. Evaluate and protect incoming holdings, including aliases to the destination.
2. Establish exclusive writable access under the complete borrow/publication contract.
3. If exclusive with sufficient capacity, mutate in place.
4. Otherwise allocate/copy a destination buffer and mutate that buffer.
5. Replace the destination holding and release the displaced buffer.

A raw count-equals-one check is not the borrow protocol. Retain-before-uniqueness is
mandatory for self-insertion. Failure before replacement leaves the existing value
intact and releases partially acquired holdings according to its failure contract.
Known layouts use ordinary typed computation around these effectful boundaries.
Table storage details continue to require their own D04 layout design; this document
does not claim that a list buffer fully specifies an ordered COW table.

## 4. Task state and suspension

Logical task record:

```text
atomic scheduling state
owning group and protected execution-image lifetime
A/B/C stack storage and coordinates
backend resume entry
allocator-generated suspension spill area
operation ticket and scoped wait registrations
result storage
runnable queue link
```

Group linkage is structural, not a counted handle cycle. Task stacks are fixed
capacity for their lifetime and do not relocate under published references. Exhaustion
follows explicit stack-resource policy, not host recursion or unbounded hidden growth.

For each suspension site the existing allocator generates a save binding, resume
entry, live-value layout, result destinations and original error identity. Spill
storage is task-owned and separately accounted, not hidden C-stack cells. Existing
ABC continuation frames remain the control representation. No worker host stack or
worker-local pointer survives in suspended state as an execution dependency.

Operation flow:

1. Attempt immediate completion. A successful channel/join operation returns directly
   without scheduler exit or full suspension-state materialization.
2. If waiting is necessary, save the resume state and prepare the ticket.
3. Register the ticket while rechecking readiness under the operation protocol: a
   change between the first attempt and registration cannot be lost.
4. If registration commits to waiting, return a PARK disposition to the scheduler.
   Completion during this interval uses the handshake below.

### Wake-before-park handshake

```text
RUNNING -> PARKING -> PARKED -> RUNNABLE
                  -> NOTIFIED -> RUNNABLE
```

The task is PARKING before a registered ticket becomes visible. A waker publishes
results and changes PARKING to NOTIFIED without enqueueing. If already PARKED, it
changes PARKED to RUNNABLE and enqueues exactly once. After execution has returned
to the scheduler, the scheduler changes PARKING to PARKED, or NOTIFIED to RUNNABLE
and enqueues. Consequently another worker cannot enter the same task before its
previous execution has returned. Completion/winner ownership prevents duplicate wakes.

Specify exact atomic memory orders with the C ABI and queue publication, including
result acquire and registration cleanup. These orders implement this state machine;
they are not permission to replace it with an unsynchronized ready flag.

## 5. Channels: locked ring and intrusive FIFO waits

```text
group | payload layout/erased transport operations | mutex | closed
capacity | head | length | ring storage
FIFO sender registrations | FIFO receiver registrations
```

Use pthread mutexes, not an initial lock-free MPMC implementation. Wait nodes belong
to tasks; communication does not allocate a new node for each wait. Select's statically
known registrations occupy a task-owned operation frame with accounted capacity.

Under the channel lock, commit only operations allowed by FIFO and close rules:
match an eligible receiver or use ring capacity for send; receive consumes the oldest
committed ring value or matches a sender. Blocked producers/consumers are linked
intrusively. Close prevents new send commits; committed values still drain. A later
sender must not overtake a previously committed buffered value.

Prepare ownership-heavy payload copies before committing; the queue receives a
fully constructed owned value. Closed/losing operations release prepared holdings
outside the lock. Queue transfer under lock moves holdings, not arbitrary source code.
Wakeup enqueueing and generated destruction occur after unlocking. No source handler,
foreign call, allocating deep copy or recursive release runs under a channel lock.

The channel ticket algorithm must specify pending-sender FIFO eligibility and failure
cleanup alongside the concrete ring implementation; source order is synchronized
commit order, not sender resumption time.

## 6. Select arbitration

One select invocation owns one ticket:

```text
winner = NONE or case index
result storage
case registrations[]
```

Use one select-arbitration mutex to commit select tickets. Ordinary channel operations
do not acquire it unless interacting with a select registration. Lock order is always:

```text
select arbitration -> channel lock
```

An ordinary operation finding a select registration drops the channel lock, acquires
arbitration, reacquires the channel lock and rechecks. Under arbitration, confirm
unselected tickets, commit the chosen channel operation and publish its result.
Rendezvous between selects commits both distinct tickets together; a select never
matches itself. Timer commitment uses the same arbitration mutex.

Registration/removal involving multiple channels holds arbitration and takes channel
locks in a specified noncyclic order; the implementation must not reverse the above
order. Losing registrations are removed before the handler executes in its selecting
task. Group structural lifetime protects channels during removal. Arbitration is a
chosen select-contention cost, not a lock around all ordinary channel traffic.

## 7. Scheduler: locked deques first

Use a fixed pthread worker pool. Each worker has a mutex-protected runnable deque:
owner pushes/pops at the back; thieves steal from the front. Use a single mutex-
protected monotonic timer heap. Idle workers use a condition variable plus notification
generation: snapshot generation, check work, and wait only if generation is unchanged,
with the condition-variable mutex protecting the final check/wait transition.

Spawn allocates task records/fixed-capacity stacks and publishes to a runnable queue.
Yield explicitly reschedules. Computing tasks are not preempted; all workers can be
occupied by non-yielding work. Blocking/affine foreign integration remains explicit.

**Do not implement Chase–Lev initially.** Locked deques avoid adding a lock-free
reclamation problem before measurements establish its value. Work stealing describes
the scheduling policy, not a requirement for a particular lock-free deque.
Cancellation, nested-group creation and teardown still require synchronized registries
under the task semantics. The scheduler choice does not settle their lock hierarchy
by implication; specify it with group implementation before coding that slice.

## 8. Cross-worker lifetime and executable publication

The first allocator binding uses the thread-safe platform allocator and frees on
the worker performing the final release, as specified in runtime-interfaces §1.
There are initially no worker allocation caches or remote-free queues. If measurements
justify a later allocator replacement requiring remote routing, freed/dead allocation
storage supplies intrusive links; release must still allocate nothing. No hidden
collector or epoch subsystem is introduced.

Specialized shared code embeds only immutable facts protected by its image lifetime.
Task stack addresses, mutable module instances, wait records and worker allocator
pointers belong in explicit execution context/operands, not shared code constants.

Replace current `native_image.c` whole-mapping RW/RX lazy preparation with:

1. Compile a realization in a separate private writable allocation.
2. Resolve relocations.
3. Publish the allocation executable and immutable.
4. Publish its address through an atomic entry slot.
5. Retain all published allocations until execution-image destruction.

Tasks protect their execution image. No fine-grained code reclamation, executing-code
patching or live mapping permission changes are introduced. Construction is synchronized;
readers acquire published entries. Binding sizes/page pooling and entry-slot ABI need
concrete accounting, not a claim of unchanged memory usage.

Threaded tapes stay eagerly prepared and immutable; resume entries are tape targets.
Dynamic resolution uses type/interface guards then ordinary callable transport. It
never becomes backend-specific record arithmetic or a hidden fallback scalar engine.

## 9. AOT and platform boundary

Task-capable C uses explicit continuation entries and task-owned state. Suspendable
ABC recursion does not become a host C call chain that must survive parking. All
bindings implement the same logical resume contract with backend-specific entries.

Workers use pthreads behind a narrow internal wrapper. Emscripten supplies pthread/
atomic adaptation for browser builds of generated C plus runtime; it does not supply
Let continuations. No direct JS-worker backend or general host scheduler API is added.
Current restricted C emission and browser deployment are not task support.

## 10. Binding deliverables and execution order

The structures/algorithms above are selected. Remaining work is concrete integration,
not repeated reconsideration of locked versus lock-free or eager versus deferred state:

1. Trace producers/contracts/consumers and define the shared primitive-contract schema.
2. Bind allocation release, known copy and erased-value operations to source lowering, verifier and
   all execution bindings, including failure paths.
3. Bind task execution context, suspension spill/result layout and scheduler-return
   status without collision with current error/return encoding.
4. Specify atomic transitions and the complete lock hierarchy for wait/select/group/
   timer/queue interactions; derive adversarial schedules and check single execution.
5. Replace publication machinery before sharing executable images between workers.
6. Implement scheduler/channel/task integration in substantial coherent slices; then
   add AOT suspension using the same logical contract.

At each integrated boundary test architectural contracts and outcomes together.
Measure retain/copy traffic, immediate versus parked cost, contention, task-stack/
spill/wait storage, code allocation fragmentation and retained images/results. Preserve
known regressions and compare against the current typed baseline. This is a concrete
engineering baseline, not a claim of optimal speed or completed concurrency proof.
