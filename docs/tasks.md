# Tasks and channels

**Status: approved design direction and source semantics; not implemented.** Built
on [syntax.md](syntax.md) and [owners-references-ids.md](owners-references-ids.md).
Concrete suspension, concurrency, effect-summary and failure ABIs still require
specification and validation. Runtime obligations live in
[architecture.md](architecture.md#structured-task-runtime-target-not-implemented).
This replaces the earlier sharing-only sketch, not an existing task implementation.

## 1. Let's concurrency model

Go-like blocking-style concurrency, without a shared mutable application heap:

| Need | Mechanism |
| --- | --- |
| Independent mutable data | Ordinary value copy or proven move into another task |
| Shared read-only data | Frozen values and immutable COW snapshots |
| Shared changing service | One owning task, accessed through channels |

Everything is an ordinary word in `std.task`, imported with `use std.task` and
accessed as `task.…`. There is no new syntax, async function category, `await`,
detached task or initial public mutex/atomic-reference API. `.let` is the sole
target extension; task use is governed by capabilities, not source profiles.

Safe Let code cannot share unsynchronized mutable application storage. Runtime
queues, counters and scheduling state are synchronized mutable internals. Having
no collector eliminates GC pauses, not contention, blocking or synchronization.

## 2. Words and results

| Word | Contract |
| --- | --- |
| `task.scope(r, body)` | Run `body(g)` in the current task; join all children before returning its result of type `r` |
| `g.spawn(work)` | Start nullary work in group `g`; return a task handle |
| `h.join()` | Wait for completion; return ordinary value copies of its result vector, including on repeated joins |
| `g.channel(t, capacity)` | Create a typed channel explicitly owned by `g`; zero capacity means rendezvous |
| `ch.send(v)` | Wait to commit a send, returning `sent` or `closed` |
| `ch.receive()` | Wait for `item(v)` or a closed-and-drained channel's `closed` |
| `ch.close()` | Idempotently stop sending; queued values remain drainable |
| `g.cancel()` | Mark the group and descendants cancelled and close their channels |
| `g.cancelled()` | Read the cancellation flag; need not switch tasks |
| `task.yield()` | Explicit cooperative scheduling point |
| `task.select { label = case, ... }` | Commit one ready case, then run its handler |
| `ch.on_receive(handler)` | Receive case; handler receives the receive result |
| `ch.on_send(v, handler)` | Send case; handler receives the send result |
| `task.on_after(ns, handler)` | Timer case, measured from select start by monotonic time; handler receives unit |

Library types include `sent_or_closed = oneof { sent: unit, closed: unit }` and
`received(t) = oneof { item: t, closed: unit }`, `task.chan(t)` and task handles
parameterized by their work's result contract. Concrete handle/result-vector type
construction remains an interface design gate; the notation is not implemented.

Select uses ordinary keyed application with program-chosen labels, not a new AST
construct. Its handlers must return the same result vector. The compiler must
support this through the ordinary keyed-application contract, not resurrect the
retired mutable-open-word engine. Scope result-vector generalization beyond the
single `r` form above is not implicitly specified.

## 3. Groups and scoped capabilities

A group is a structural lifetime, not a reference-counted owner. Scope exit waits
for every child, including children never explicitly joined, then releases task
records and channels. Task results remain available for repeated joins until group
teardown; unobserved results are dropped there. This can retain significant memory.
No task can outlive its group. Nested groups finish before their enclosing task.

Two permissions must not be conflated:

- **Transferable values** may cross tasks and enter `any`. They preserve ordinary
  copy/move semantics; mutable aliases to another task are forbidden.
- **Group-bound capabilities** (groups, channels, task handles and values containing
  them) may cross only into task lifetimes contained by their owning group's
  lifetime. They cannot enter unrestricted `any`, an unrestricted frozen box or
  longer-lived storage. Wrapping one in a record, closure or container does not
  erase its group bound.

A channel payload may itself contain a scoped capability only if the channel's
lifetime is contained within that capability's validity. Thus a child channel
cannot be sent into an ancestor channel's longer-lived queue. Reply channels and
service protocols work when these bounds are compatible. Returned task results
must similarly remain valid for their result record's entire retention lifetime.
Group escape rejects `group-escape`; source lifetime annotations are not required,
but compiler summaries must preserve these bounds through calls and erasure.

Handles borrow group-owned records, not one another through strong counts. This
prevents channel/task-handle cycles from becoming reference-count cycles. It does
not prevent protocol deadlock: self/cyclic joins and unmatched channel operations
have no automatic progress guarantee. Deadlock diagnostics are not specified here.

## 4. Value transfer and task worlds

Scalars, transferable aggregates and stores copy or move. Store copies contain
independent places and preserve ids; sending an id alone does not share its store.
Strings, suitable lists/tables, frozen values and immutable snapshots may share
buffers while retaining value semantics. Closures transfer only when their full
capture/world-access summaries permit it, or under explicit scoped-capability
bounds for group-local work.

Mutable references, readonly views backed by mutable storage, closures retaining
those paths and raw foreign pointers do not acquire transferability by crossing a
boundary. `any` already contains only transferable values; channel/group handles
cannot be smuggled through it. External ingress still must uphold that invariant.

Spawned work cannot read **or write** another task's mutable module storage, even
through indirect/transitive calls. A merely `module-mutation-free` check is too
weak. Immutable module values may be read. Foreign declarations must distinguish
concurrent-call safety, blocking and thread affinity; no unsafe extern becomes
safe because its explicit arguments happen to be transferable.

## 5. Channel semantics

A positive-capacity channel holds at most that many values. Capacity zero commits
a send only together with a receive. Delivery order follows synchronized send
commit order, not the order senders later resume on their workers.

Close prevents further send commits. Waiting and subsequent sends return `closed`;
receivers drain committed values, then repeatedly return `closed`. Closing does not
run user code. Rejected send values and discarded queued values obey ordinary
ownership cleanup. Copy/evaluation costs are not erased by a failed send.

A closed channel is a normal result, not an abort. A consumer ending does not
implicitly close a channel; the protocol must close or cancel it as appropriate.

## 6. Select

Evaluate cases, handlers' captures and send values in source order. Only the
winning communication operation commits: losing sends do not publish their values
and losing receives consume nothing. Evaluation effects of losing cases still
happen; their retained values must be released normally.

Readiness means an operation can commit without waiting, including returning
`closed`; timers become ready at their deadlines. Choose randomly among ready
cases to avoid fixed priority, without an absolute starvation-freedom guarantee.
Timers are not cancelled automatically by group cancellation.

Case descriptors are scoped to their select operation and cannot escape. They may
borrow selecting-task state because handlers run in that task, not on an arbitrary
waking worker's task. Unregister losing waits before invoking the winning handler.
Exactly-once commitment, waiter reclamation and wakeup/registration races require a
concrete protocol. Opposing rendezvous cases must not let a select commit against
itself. An empty case set and timer range/overflow diagnostics remain API details
to settle before implementation.

## 7. Cancellation and failure

Cancellation is a request implemented by marking and closing, not interruption:

1. Mark the group and descendants cancelled; close their channels idempotently.
2. Queued values still drain. Receives need not immediately return `closed`.
3. `join` still waits and returns results, not `closed`.
4. Descendant groups inherit cancellation; channels created after cancellation
   start closed. New work in a cancelled group starts with cancellation observable.
5. Registration and cancellation synchronize so newly registered groups/channels
   cannot miss a cancellation walk.
6. A task computing or waiting on an ancestor's still-open channel need not finish
   promptly. It must cooperate with its protocol and cancellation flag.

Tasks finish through ordinary control flow, so ordinary deferred actions run.
Cancellation performs no unwinding. Scope exit always waits; a deadline requests
cancellation, not a guaranteed deadline for returning from the scope.

Recoverable failure is a value (normally a result sum). Join does not invent an
exception channel; a supervisor decides whether to cancel after seeing failure.
An abort remains program-ending, with no source deferred actions or task-local
unwinding. Report the originating task and source stack; simultaneous abort report
order can depend on timing. Coordinated worker shutdown, embedding behavior and
resource-failure handling remain runtime design gates, not promises of immediate
interruption of arbitrary computation or foreign calls.

## 8. Scheduling and effects

Use lightweight tasks over worker threads with work-stealing runnable queues.
Scheduling points are channel operations, select, join, final group join, task end
and explicit `task.yield()`. Allocation and spawn do not by themselves introduce
an implicit cooperative switch in the caller. A spawned task may run immediately
on another worker. Worker count is a host setting.

Blocking parks a task, not its worker. A non-yielding computation can occupy a
worker indefinitely; all workers can become occupied. No signal-based preemption
or automatic fairness guarantee is implied. One worker plus a fixed selection seed
is insufficient for deterministic real-time/I/O programs: repeatable tests need a
controlled clock and external event source as well.

Track effects independently and transitively:

| Fact/effect | Examples |
| --- | --- |
| May allocate | Group/channel/task creation; deep copying store payloads or joined results |
| May count | Retaining/releasing shared buffers |
| May suspend | Send/receive, select, join, yield and final group join |
| Mutable-world access | Reads as well as writes to task-owned module storage |
| Foreign effects | Concurrent-call safety, blocking and thread affinity |

No-count code may spawn and communicate; that does not make those operations
allocation-free. Allocation-free code may suspend. Scheduler bookkeeping can be
allocation-free only with sufficient reserved wait records; this is an implementation
obligation, not a blanket guarantee for send/receive/select/join. Argument evaluation,
copying and handlers retain their own effects. Repeated joins may allocate copies.
Cancel/close may perform substantial wakeup/release work even without allocation.
A blocking foreign call needs an explicit integration policy, not an assumption
that it behaves like a parkable channel operation.

## 9. Counting and runtime state

The concrete approved implementation baseline is [runtime-primitives.md](runtime-primitives.md):
locked ring-buffer channels, intrusive task-owned waits, select arbitration,
locked worker deques and a shared timer heap, explicit park/wake handshake and
allocator-generated resume bindings. Work stealing does not mean initial Chase–Lev
implementation. Native lazy code uses immutable per-realization publication; current
whole-image reprotection must be replaced before concurrent sharing.

Potentially shareable buffers use atomic counts **from creation**. Task-confined
mutable owners use ordinary counts; there is no live counter-mode upgrade. A
receiver's holding must exist before publication, and borrowed readers need a
protecting live holding. Count elision and uniqueness tests account for all tasks
and borrows. Exact memory orders and overflow handling remain to be specified.

Each task owns its ABC A/B/C stacks and explicit continuation state. Suspension
must transport all live execution state without leaving a dependency on a worker's
host stack or worker-local pointers. Migration, foreign boundaries and each of the
four execution bindings need a concrete suspension ABI. This does not authorize
new bytecodes, recursive host execution, a second allocator or a new residual IR.

Group records/queues/waiters have synchronized structural lifetimes. Shared buffers
may have their last holding released on any worker. Generated release stays
iterative, allocation-free and free of user callbacks; allocator remote-free support
and teardown races require validation.

Published executable code stays immutable. Concurrent lazy versions use synchronized
construction and atomic entry indirection, not unsafely patched executing stencils.
Acquire/release publication alone is not a complete lifetime/reclamation protocol.
The current backend is not declared thread-safe by this design. There are no GC
safepoints or tracing scans, but explicit scheduling/state synchronization remains.

### 9.1 Threading platform: pthreads, not a host concurrency framework

**Approved scope; not implemented or browser-validated.** Runtime workers use
pthreads. Keep a narrow internal wrapper for thread lifecycle, synchronization and
testing; do not design a general host scheduler API, JavaScript event-loop pump or
separate Web Worker backend. Let tasks are not pthreads: the Let scheduler still
multiplexes lightweight tasks over its workers and owns parking and continuations.

For Wasm/browser deployment, the application developer compiles generated AOT C
**and the runtime** through Emscripten's pthread support. Emscripten supplies the
Web Worker/shared-memory implementation of pthreads and supported atomic operations.
Application developers own toolchain flags, worker-pool setup, JavaScript integration
and hosting requirements (including shared-memory availability and cross-origin
isolation where required). There is no silent message-copying fallback when shared
memory or threads are unavailable.

Let remains responsible for correct pthread/atomic use, scheduler/channel protocols,
counting, memory lifetime, shutdown and avoiding unsupported platform assumptions.
Keep the Let scheduler off the browser main thread; Emscripten startup, worker-pool,
blocking and proxying constraints must be documented for the tested configuration.
Delegating platform adaptation does not establish browser correctness by itself.

Today's portable-C emitter supports a restricted subset, not task suspension.
Emscripten supplies threads, not Let continuations: task-capable AOT C must first
implement explicit suspension/resumption and runtime integration. Native JIT code
is not a Wasm execution backend. Browser support stays unvalidated until an actual
AOT/runtime Emscripten build passes lifecycle, parking, channel and release tests.

## 10. Examples

```let
use std.task

let total(): u64 = task.scope(u64, do(g)
  let weights = freeze(build_weights())
  let a = g.spawn(|| weigh(weights, 0, 500))
  let b = g.spawn(|| weigh(weights, 500, 1000))
  return a.join() + b.join()
end)
```

A channel is explicitly owned, rather than selected from ambient scope:

```let
let squares(n: u32): u64 = task.scope(u64, do(g)
  let ch = g.channel(u64, 16)
  g.spawn(|| produce_and_close(ch, n))
  return consume_until_closed(ch)
end)
```

`produce_and_close` must close `ch` when done; `consume_until_closed` drains it.
These examples illustrate target APIs, not runnable current fixtures. A task owning
a mutable service communicates through request/reply channels with compatible group
bounds; public mutexes and shared mutable references are not needed for that pattern.

## 11. Remaining implementation gates and acceptance

Specify the inferred group-bound/closure/result summary format, handle result ABI,
keyed select checking, timer limits, parking/stack resource policy, foreign integration,
abort/shutdown protocol and concrete memory-order/reclamation algorithms before coding.
Use the approved pthread contract through a narrow internal wrapper; a general host
concurrency abstraction and direct JavaScript worker backend are out of scope.
Pipeline `.par()` integration is separate; neither a pipeline API nor worker-count
independent reduction semantics are introduced by this document.

Required tests:

- Scope joins unobserved children; repeated joins copy independently and release
  retained results exactly once at teardown; nested group lifetimes cannot escape.
- Reject scoped handles in `any`/unrestricted frozen boxes, child handles in ancestor
  queues and expired handles hidden in results/closures; accept valid reply channels.
- Buffered/rendezvous FIFO by commit, full/empty waits, close races, draining and
  repeated closed results, including payload-copy failure and cleanup.
- Exactly one select commitment; no self-rendezvous, lost wakeups or surviving loser
  registrations; losing evaluation effects preserved, payloads released, handlers local.
- Cancellation races with spawn/channel/nested-group registration; inherited cancelled
  state, buffered draining, ancestor-channel limitation and cooperative completion.
- Reject mutable-backed views and transitive reads/writes of another task's globals;
  accept immutable snapshots; reject foreign calls lacking the required contract.
- Atomic publication/final-release and COW uniqueness races; cross-worker frees and
  long release chains; no host recursion or allocating release worklist.
- Suspension/resumption and worker migration under interpreted/threaded/eager/lazy
  execution, explicit continuations, original error PCs, stacks and capacity limits.
- Concurrent site/version publication with immutable code; failure and shutdown races.
- Separate allocation/count/suspension facts, including store sends and repeated joins.
- Reproducibility with controlled scheduling, seed, clock and events; randomized choice
  distribution tests without claiming that finite trials prove starvation freedom.

Measure spawn/park/wakeup/select overhead, contention, copy/count/atomic traffic,
peak group-result and queue retention, code size and first/steady execution costs.
No runtime implementation, safety proof or performance claim follows from this spec.
