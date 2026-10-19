# ABC VM 3 — unified stack and operand register

**Status: design, not implemented.** This document grounds the VM 3 experiment in
`next/`. Its agreed topology replaces the three-stack machine here, not in the
production VM at the repository root. The copied sources still implement VM 2.
[README.md](README.md) records the copied baseline and build isolation;
[WORKLIST V](../WORKLIST.md#v--vm-3-isolated-experiments) is the only live delivery
ledger. This document is a design contract, not an implementation progress report.

The user's initial sketch is the starting proposal. Subsequent discussion settled
**a ring register bank with dynamic occupancy and no eager refill, including at
returns**. That supersedes the sketch's anchored bank, block spilling and special
return refill. Unresolved contracts below are deliberately not implementation
permission or silently assigned ABI/encoding decisions.

**Refill decision confirmed by experiment:** retain **no eager refill**, including
on return. The user confirmed this choice after the isolated
[register-specialized runtime comparison](experiments/refill-native/README.md).
That evidence supports this interpreter policy, not a universal optimum or a
speedup over the current production VM. “Demand” in raw experiment files means
no eager refill; the design uses the explicit name to avoid ambiguity.

## 1. Agreed architectural direction

- **A is one logical stack:** activation storage and expression operands occupy
  one sequence. There is no separate C stack or C register bank.
- **B is one operand register, not a stack.** It supplies the right operand and
  can receive a result. It has no implicit backing stack or automatic spill slot.
- **Call arguments stay in place.** The caller's top argument cells become the
  callee's argument portion of its frame; ordinary call entry does not copy them
  to another stack.
- **Continuations stay on A above the arguments.** There is no dedicated link
  register in the selected V3 calling design.
- **A's concrete interpreter cache is a ring.** Its placement state is `(R,T)`,
  rotation and occupancy, not three separately partitioned stack occupancies.
- **Pushes fill free registers.** Full-bank pushes spill the deepest cached cell
  and reuse its physical register. Maintaining the cache layout requires no
  shifting of surviving registers.
- **Pops never refill.** Reading a backing cell accesses it directly. Returns do
  not perform speculative or threshold-triggered reloads.
- **The original VM remains isolated.** VM 3 does not reinterpret existing modules
  or alter the production VM's selected-first A/B semantics.

The point is not just fewer instructions. Storage that changes roles should not
need to move merely because it becomes an argument or a local. The register bank
should serve whichever top-of-stack cells are live, without a fixed allocation
between frame storage and expression storage.

## 2. Logical machine and activation layout

A cells carry 64 bits. The topology does not by itself change integer arithmetic,
float behavior, value kinds, error reasons, ownership or memory-safety obligations.

The selected continuation placement, shown deepest to shallowest, is:

```text
... caller cells | arg0 ... arg(n-1) | continuation | locals | operands
                   <----------- current activation ----------->
```

The arguments are already in A before the call. The continuation is placed above
those arguments rather than inserted below them. Locals and operands grow above
it. Stack-resident continuation placement is selected; the exact continuation
contents, size and frame bookkeeping remain gates in section 6.

A binding can remain where its value was produced: changing its role from operand
to local requires no CPUSH. Ending a binding with a result above it can require a
NIP-like operation. Eliminating CPUSH does not eliminate semantic destruction,
result relocation or ownership obligations.

At each verified instruction the activation-relative stack shape must be known.
GET/SET depths are measured from the **whole logical A top**, including operands
above the selected local. A frame access must not depend on cache occupancy.
Neither operands nor frame accesses may reach a caller's protected cells, and the
continuation is protected control state, not an ordinary readable/writable local.

Static depth does not imply that the absolute runtime stack depth, cache rotation,
or recursion depth is constant. Nor does a compiler-known layout make stack walking
metadata-free: a runtime walker still needs a way to obtain that layout.

## 3. Ring cache: representation and transitions

### 3.1 State and invariant

For the concrete stack interpreter, let:

| Name | Meaning |
| --- | --- |
| `ip` | Instruction position |
| `asp` | Next free backing-memory cell, above the uncached prefix of A |
| `r[0..N-1]` | Physical value-register bank |
| `R` | Register holding the deepest cached A cell, modulo N |
| `T` | Number of cached A cells, 0 through N |
| `B` | Scalar operand/result register |

`N = 8` is the starting proposal, not a measured optimum or a public ABI. Activation
boundaries, stack capacity, module state and verification information still exist;
this table is not a claim that five fields describe the entire runtime.

If backing memory holds M live cells, the logical sequence is:

```text
A = memory[0 .. M-1] ++ r[R], r[(R+1) mod N], ..., r[(R+T-1) mod N]
asp = memory + M
logical depth = M + T
```

Only those T registers are live A cells. Other registers contain irrelevant bits.
No stale backing copy is authoritative for a currently cached cell. The cached
cells always form a contiguous logical suffix, even though physical register
indices wrap. Frame/operand boundaries do not partition that suffix.

The formulas below use the convention that an ordinary pop leaves R unchanged,
including when T becomes zero. They define the reference ring transitions; they
do not require R and T to occupy dedicated runtime machine registers.

### 3.2 Push

Capture the input value before overwriting any register it aliases.

With space (`T < N`):

```text
r[(R + T) mod N] = value
T = T + 1
```

When full (`T == N`):

```text
*asp = r[R]                // spill the deepest cached cell
asp = asp + 1
r[R] = value               // reuse that physical register for the new top
R = (R + 1) mod N
T remains N
```

One full-bank push performs one backing store and no rotation-induced register
moves. Bounds/resource checks still apply before committing a failing operation.
There is no half-bank spill and no intentional emptying of registers.

### 3.3 Pop

With cached cells (`T > 0`):

```text
value = r[(R + T - 1) mod N]
T = T - 1
```

With no cached cells (`T == 0`):

```text
asp = asp - 1
value = *asp
T remains 0
```

These transitions presume a legal, nonempty operand region. They do not authorize
popping locals, protected continuation cells or caller prefixes as operands.
DROP can discard a value without physically loading its bits when semantics allow.
Neither case reloads surviving backing cells into the bank.

### 3.4 Depth reads and writes

For a valid depth d, with depth zero denoting the logical A top:

```text
d < T:   r[(R + T - 1 - d) mod N]
d >= T:  asp[-1 - (d - T)]
```

An uncached read uses that backing cell without installing it in the cache. GET d
is different: it reads a value, then **pushes a new logical copy**. That push follows
section 3.2; it is not a refill of the source cell. GET_B d reads into B without
changing A's occupancy.

A write to an existing logical cell updates its authoritative location. SET's
encoded depth convention (before or after consuming its input) must be settled in
the instruction contract; these addressing formulas do not silently settle it.
Capture source values before a push, pop, overwrite or spill can change their
locations. Addressable frame blocks and escaped addresses need the separate
placement contract identified in section 8.

### 3.5 Small example

For N = 4, let R = 2 and T = 4. Deepest to top, the cached values are:

```text
physical registers: r2=a, r3=b, r0=c, r1=d
logical suffix:      a b c d
```

Pushing e stores a to backing memory and writes e into r2. Now R = 3, T = 4:

```text
logical A:           ... a | b c d e
cached suffix:              r3 r0 r1 r2
```

Popping e leaves R = 3, T = 3. No cell is reloaded. Pushing f writes r2 directly.
If all four cached cells are popped, a remains in backing memory; its subsequent
read/pop is a direct memory access, not an eager refill.

### 3.6 Returns and other boundaries

**Return is not a cache-refill event.** After frame removal and required result
transport, whatever valid cached suffix remains stays cached; backing cells do
not become cached merely because capacity became available. New result pushes
obey the ordinary push rules.

Result transport, NIP, tail replacement and explicit synchronization can still
require moves, stores or loads. The ring removes moves needed solely to re-anchor
the cache, not moves required by instruction semantics. Their exact algorithms
must preserve the suffix invariant and capture live inputs before overlap.

Foreign calls, suspension, allocation and error reporting retain their required
state synchronization. No eager refill does not mean no boundary publication.

## 4. B and operand routing

B is either empty or contains one live value. That validity belongs to verified
logical state; it is not another dimension of A's register-cache occupancy.

The sketch proposes these operations:

| Operation | Logical effect |
| --- | --- |
| MOVE_AB | Pop A into empty B |
| COPY_AB | Copy A's top into empty B |
| GET_B d | Read A[d] into empty B |
| MOVE_BA | Consume B and push its value on A |
| OP_A | Compute A0 op B, replace A0, consume B |
| OP_B | Compute A0 op B, pop A0, replace B with the result |
| Unary/immediate `_A` or `_B` | Read and replace the selected operand |

**In this proposal `_B` selects the result destination, not operand reversal.**
SUB_B would compute A0 minus B. This differs deliberately from the copied VM's
SUB.B, which computes B0 minus A0. Exact opcode spellings/encodings are not assigned.

A read-modify-write of B consumes its old value and produces a new one; it is not
an illegal overwrite. Writing an unrelated value while B remains live must reject.
Joins need compatible B validity/kind as well as compatible A layouts.

The caller/callee B contract is still open. Requiring B empty at ordinary call
entry is a candidate, not a settled rule. A callee cannot silently overwrite a
caller-live B, and the implementation must not introduce an automatic hidden B
spill stack to disguise a missing contract.

The historical lab observation that B never exceeded one cell in compiled examples
motivates the restriction; it does not prove that arbitrary current producers can
be ported unchanged. Nested right-hand expressions, noncommutative operations and
effect-preserving evaluation order must be tested. Extra explicit A storage or
moves needed by scheduling must be measured, not called free.

## 5. Instruction surface: proposal, not encoding

Retain the distinction between logical instructions and cache-state handlers.
The rough surface includes:

- A literals, DUP, DROP and NIP;
- GET/SET and selected short depth forms;
- the B transfers and result-destination operations above;
- integer/float arithmetic, normalization, checks and conversions;
- immediate and depth-cell operand forms;
- direct/indirect calls, tails, returns, branches and host completion;
- memory, foreign and lifecycle operations admitted by the existing VM.

Cell-operand forms read A[d] directly and leave that source unchanged unless it
aliases a specified destination. Their exact legal depths and overlap semantics
need a complete instruction table. Fused forms are not automatically cold or free.

The initial estimate of roughly 125 opcodes is not an audited inventory of the
current runtime. No byte map, extension allocation, module revision, maximum result
count or quickening range is assigned by this document. The copied ISA has a
broader current contract than the historical lab baseline.

Quickening is **not adopted here**. The original sketch proposed counted variants;
the current VM explicitly uses immutable bytecode without quickening. Count
specialization, if desired, needs a separate execution/encoding decision. Handler
specialization by cache state does not itself require rewriting bytecode.

## 6. Calls, returns and continuations

### Selected placement: no dedicated link register

Keep the continuation on A above the arguments, created as part of CALL. The user
confirmed this choice after discussing the leaf/non-leaf trade-off. It gives each
recursive activation its explicit continuation without reserving a dedicated link
register or introducing a separate non-leaf save instruction.

This is a simplicity/register-budget decision, not a measured defeat of link
registers. Both refill experiments used stack continuations throughout; neither
compared a link-register convention. A different convention could benefit leaf
calls or fuse saving into CALL, so an extra SAVE dispatch is not an inherent cost
of every possible link-register design. That alternative is not selected here.

### Entry

The intended ordinary-call dataflow is:

1. Produce the ordered argument vector at A's top.
2. Establish the continuation above those cells.
3. Reclassify those existing argument cells as the callee's frame.
4. Transfer explicitly to the callee.

No argument gather or A-to-C conversion remains. A continuation push still changes
T and can spill; the call as a whole does **not** leave cache state unchanged.
Zero argument movement is not a promise of zero call overhead.

### Return

RET must capture its result vector, recover the continuation, remove the complete
callee activation and deliver the results to the caller's declared destination.
A destination-B call must return exactly one value to B if that sketch form is
adopted. Delivery to A may relocate results over the removed activation. There is
no eager refill before or after the return transfer.

The continuation must distinguish at least the return target and result destination
and provide or recover the required caller coordinates. Whether that information
fits one cell, uses immutable metadata, or requires additional explicit fields is
unresolved. A bare return PC is not assumed sufficient.

Arguments and locals lie on opposite sides of the continuation storage.
A single total frame-cell count does not necessarily identify its depth when local
counts vary. RET operands and/or verified layout metadata must settle that before
implementation; the sketch's `RET k,r` is not yet a complete frame contract.

### Tail replacement

A tail call preserves the original continuation and result destination while
replacing the current activation's argument/local region. Its resulting layout
must be the same as ordinary entry: **arguments below the continuation**. The
sketch's wording about leaving the continuation below replacement arguments is
not compatible with that entry layout and must not be implemented literally.

Changing arity and overlapping old/new vectors require explicit capture and
relocation rules. Tail calls can move arguments even though ordinary calls do not.

### Execution mechanism

Preserve explicit ABC continuations; recursion must not become recursive host
execution. A native/link-register mechanism is not authorized merely by calling
it a tier-local convention. Any such binding must preserve the logical continuation,
capacity, failure and future suspension contracts and receive explicit approval.
Indirect calls still require validated callable identity and complete ABI agreement.

## 7. Interpreter and residual execution

For T0, a generated handler specialized by `(opcode,R,T)` can name each physical
register statically. The modulo arithmetic in section 3 can be generator-time
arithmetic, not runtime division or register-array indexing. State can be carried
by dispatch target identity rather than additional allocated state registers.

With N = 8 there are at most 8 × 9 = 72 raw `(R,T)` combinations. This is a possible
handler inventory, **not a runtime instruction-cache working-set measurement**.
Actual stack traffic and control flow determine the sequence of states/handlers;
operand values affect it through control flow. Frequency, locality, layout and
branch prediction matter. Total generated size also matters separately for build
time and binary size. Neither nine anchored states nor 72 ring states proves a
runtime performance advantage.

Do not reconstruct the historical state-keyed native compiler. The copied current
runtime already shares symbolic execution and allocates register-addressed native
stencils (eight native value registers) or threaded records (seven value registers).
The symbolic cell map remains the allocator; VM 3 must not add a second value IR,
allocator or post-hoc placement-reconstruction pass just to model the ring.

The concrete T0 ring is not automatically a mandatory native calling convention.
How residual execution represents the unified stack, B and entry/edge placements
needs its own coordinated design. There is no approved bound of N+1 compiled
function versions: rotation, placement, facts and continuations can matter too.
Runtime execution remains independent of the build-time optimizer and portable-C
writer. Shared semantics, not copied per-backend scalar algorithms, remain the goal.

## 8. Semantic preservation and open gates

The topology does not authorize weaker correctness at any boundary. Before a
runtime cutover, resolve:

1. **Instruction/encoding contract:** complete producer-consumer inventory, exact
   depth conventions, operand order, result vectors and incompatible module
   admission. Never silently interpret VM 2 bytes as VM 3.
2. **Frame/control contract:** continuation representation, caller isolation,
   CALL_B return routing, variable-arity tails, frame limits and stack walking.
3. **B lifetime contract:** calls, joins, foreign boundaries and compiler scheduling.
4. **Addressable storage:** frame blocks, pointer formation, escaped addresses,
   stable storage and writes that alias cached cells. Folding C into A must not
   silently move observable storage or turn cache copies into stale memory views.
5. **Ownership/effects:** distinguish physical register transport from semantic
   copy/drop; retain counted holdings, borrow lifetimes, lifecycle entry contracts,
   failure cleanup and required effect synchronization. No tracing collector or
   runtime cycle-detector fallback.
6. **Residual bindings:** exact symbolic contexts, edge conformance, entry contracts,
   continuation transport, version ownership and native/threaded register budgets.
7. **Foreign/host and future suspension:** preserve explicit ABI and state handoffs;
   no retained worker-host-stack dependency or second spill allocator.

These are design questions, not permission to retain a hidden C engine, stage B
through an obsolete A/B representation, add compatibility dispatch flags or claim
that a working toy evaluator completes the full VM replacement.

## 9. Cutover responsibilities inside next/

Paths below are existing copies, not newly implemented VM 3 components. Each
approved implementation slice must change its authoritative producers, consumers
and tests together. The production paths outside `next/` remain untouched.

| Responsibility | Existing files relative to next/ | Replacement/removal boundary |
| --- | --- | --- |
| ISA and verification | `tools/opcodes.lua`, `tools/assembler.lua`, `tools/gen_opcodes.lua`, `src/module.c`, `src/memory_module.c`, `src/verify.c` | Replace three-stack shapes and selected-first A/B decoding coherently; define new admission, not a bytecode reinterpretation |
| Shared semantics | `gen/semantics.lua`, `gen/symbolic.lua`, `gen/fold.lua`, `src/semantics.c` | One unified-stack/B computation; remove obsolete transfer families only with their consumers migrated |
| Concrete storage/cache | `gen/cache.lua`, `gen/banked.lua`, `gen/cold.lua`, `src/execution_context.h`, `src/vm.c`, `src/vm_internal.h` | Replace anchored A/B plus C banks, three backing stacks and A-to-C argument transport with the agreed topology |
| Residual execution | `src/symbolic.c`, `src/symbolic.h`, `src/residualize.c`, `src/execution_emit.h`, `gen/execution_forms.lua`, `gen/execution_compute.lua`, native/threaded emitters | Migrate the existing allocator and explicit control transport; do not wrap the old machine |
| External/effect boundaries | `include/abc.h`, `gen/foreign.lua`, `src/lifetime.c`, `src/owner.c`, `src/internal.h` | Preserve sound ownership algorithms and host guarantees; change only topology-dependent bindings under their approved contracts |
| Build-time consumers | `src/optimize.c`, `src/residual_builder.c`, `src/residual_c.c`, residual schema/analysis/validation | Migrate machine consumers without inserting them into runtime execution |
| Producers and tests | `frontend/let/abc.lua`, placement/layout clients, `tools/validate*`, `frontend/tests/`, `examples/`, `lab/` | Update scheduling, depths, calls, fixtures and oracles; do not assume lab routing proves all producer coverage |

Correct arithmetic, checking, ownership and native emission algorithms should
survive where applicable. The removal set is the obsolete organization, not every
algorithm implemented under it. Copying the repository is preparation, not a VM 3
cutover; no adapter layer becomes the new owner merely by exposing new names.

## 10. Validation and measurement plan

### Architectural correctness

Use a simple uncached semantic oracle and generated transition cases. Exercise
all rotations and occupancies, wraparound, full pushes, empty-cache pops, deep
reads/writes and poisoned inactive registers. Check both values and physical
obligations: no eager refill, exactly one deepest-cell spill on full push, no
alignment-only moves, and a contiguous logical cached suffix.

Cover source captures when GET/DUP/NIP/SET or result transport overlaps spill or
destination registers. Check actual backing loads separately from copies newly
pushed by GET. Test no-refill behavior across returns, not only straight-line pops.

Call tests need zero/multiple arguments, recursion, live caller prefixes, result
routing, varying local counts, changing-arity tails, nested B use, exact capacity
boundaries, abort origins and invalid continuation/caller accesses. Add typed
memory/aliasing, lifecycle and foreign tests as those contracts are integrated.
Differential execution must cover interpreter, threaded and native bindings when
implemented; a scalar-only prototype is explicitly narrower evidence.

### Performance

Measure both mechanism counts and end-to-end time:

- executed dispatches and `(opcode,R,T)` frequency/transition distributions;
- hot handler footprint, instruction-cache/ITLB behavior and dispatch prediction
  where hardware counters are available;
- backing loads, spills, semantic register moves and call/result transport;
- total generated code, compile time and native/threaded realization growth;
- recursion, deep expressions, many locals, loops, tails with changing arity,
  memory-heavy code and workloads that stress B scheduling.

Use identical semantics, inputs and toolchain settings with repeatable runs.
Compare against the copied **current** VM, not historical stencil inventories or
the old lab alone. Report ring-policy benefits separately from ISA/compiler changes
where feasible. Any cache-size sweep is measurement, not a public ABI change.

The sketch's lab percentages, stencil counts, dispatch costs and predicted speedups
are historical observations/estimates supplied with the proposal. They are not
VM 3 results, nor a faithful description of every current VM 2 backend. In
particular, the old return-refill performance rationale no longer describes the
agreed design. No speedup or universal optimality is asserted here.
