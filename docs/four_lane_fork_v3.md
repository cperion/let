# Four-Lane Routed Stack-Register VM

## Four LIFO Lanes, Two-Cell Hot Windows, Routed Lifetime, and UNWIND Continuations

### Status

This document specifies the current four-lane VM design.

It is a fresh architecture derived from the following settled ideas:

- four identical unbounded scalar LIFO lanes;
- two cached top cells per lane;
- ordinary computation touches only true lane tops;
- a full routing byte names two source lanes, an arbitrary destination lane, and the lifetime of both source tops;
- the machine has one natural modulo-four winding order for newly materialized scalar state;
- there is no separate `WIND` instruction: ordinary allocation, routed result placement, calls, loops and nested execution perform the winding naturally;
- `UNWIND` has one deterministic meaning: expose a buried value by redistributing the live prefix over the other three lanes in canonical ring order;
- because winding is modulo four while redistribution is modulo three, `UNWIND` also phase-reshuffles the live layout instead of reconstructing the same grouping;
- flow and continuation are dynamic roles of the same scalar values, not distinct storage classes or opposite allocation directions;
- continuations are buried control tokens and are restored through `UNWIND`, not through a separate architectural continuation stack;
- addressable aggregates remain in a separate byte-addressable frame/memory arena;
- the register cache is also the native stencil ABI;
- startup copy-and-patch removes dispatch;
- SSA can lower directly into routed lifetime operations without a conventional global register-allocation phase;
- lazy basic-block versioning can specialize joins and loops to the lane layout actually produced by execution;
- compilation can be demand-driven: expose or compute values only when a consumer or continuation requires them.

Items that are not settled are marked **Open**.

---

# Abstract

The VM consists of four identical logical stacks:

```text
S0  S1  S2  S3
```

Each lane is an unbounded LIFO stack of scalar machine cells.

Each lane has a dedicated two-cell register cache:

```text
S0: S0.0 S0.1 | backing
S1: S1.0 S1.1 | backing
S2: S2.0 S2.1 | backing
S3: S3.0 S3.1 | backing
```

The intended native implementation therefore spends eight registers on hot scalar VM state.

Ordinary binary computation does not address stack depth. It names two lane tops and computes from those true tops.

A binary instruction carries a complete routing/lifetime byte:

```text
left source lane      2 bits
right source lane     2 bits
destination lane      2 bits
keep left source      1 bit
keep right source     1 bit
--------------------------------
                       8 bits
```

Thus the useful instruction itself says:

- where its two inputs currently live;
- where its result should live;
- whether each source remains live after the use.

No preparatory `DUP` is required merely to preserve an operand, and no separate `MOVE` is required merely to place the result on the compiler's next chosen frontier.

All source access remains top-only.

New scalar state winds naturally around the four lane frontiers:

```text
S0 -> S1 -> S2 -> S3 -> S0 -> ...
```

Repeated pressure therefore builds vertical history behind those frontiers. There is no architectural `WIND`; ordinary execution is the winding process.

When a needed value is buried, the VM does not reach to it. `UNWIND Si,n` pops exactly the `n` live values above the target and redistributes them, top-first, over the other three lanes in the canonical ring order beginning after `Si`. The target then becomes the true top of `Si`.

For example:

```text
S0 = [a,b,c,x,...]
```

becomes:

```text
S0 = [x,...]
S1 = [a,...]
S2 = [b,...]
S3 = [c,...]
```

For a longer prefix the redistribution wraps over those three lanes, so a vertical column becomes a folded horizontal register layout.

This is not merely access repair. Baseline winding has period four while an unwind redistributes over three destinations. Since `gcd(4,3)=1`, the two phases do not remain aligned. `UNWIND` therefore changes the phase of surviving values relative to future winding and gives the allocation a natural self-repairing tendency. The compiler keeps the resulting layout rather than canonicalizing it away.

The same mechanism defines continuation handling. A call does not need a conventional scalar frame. It buries a continuation token, performs work above it, then uses `UNWIND` to preserve live results while re-exposing the token. `RESUME` consumes the exposed token and continues execution.

Flow and continuation are not separate allocation directions. They are temporal regimes of the same values. A loop accumulator may be active flow inside an iteration, continuation state across a backedge, and active flow again in the next iteration without changing storage class.

This makes the machine a direct target for SSA. Definition creates a routed value, future use maps to KEEP, last use maps to consume, overlapping liveness maps to stacking, and an inconveniently buried demanded value maps to `UNWIND`. Basic-block versions may accept different lane layouts, so joins and loop backedges do not require a canonical register assignment.

The core thesis is:

> **Four routed LIFO lanes. Two hot cells per lane. Routing performs allocation. KEEP expresses lifetime. Ordinary execution winds modulo four. UNWIND redistributes modulo three, exposes buried futures, and reshuffles the register frontier.**

---

# 1. Design goals

The architecture is designed around eight goals.

## 1.1 True stack hygiene

Ordinary source operands are always genuine stack tops.

No arithmetic instruction deletes an interior stack cell.

No ordinary arithmetic instruction requires compaction.

## 1.2 More than one frontier

One stack gives one exposed value.

Four stacks give four independently exposed values while preserving LIFO history behind each frontier.

## 1.3 Cheap nested pressure

Each lane caches two cells.

A new short-lived value may temporarily shadow an older live value on the same lane without touching backing memory.

## 1.4 Local routing instead of a global register allocator

The compiler chooses lane names.

The instruction says where the result goes and which source tops survive.

The lane histories automatically hold older values.

## 1.5 Deep values remain stack-disciplined

Buried values are never read in place.

`UNWIND` preserves the live prefix above a buried value by redistributing that prefix across the other three lane tops.

The buried value then becomes a true top.

## 1.6 Continuation is not a separate storage mechanism

Return continuations, loop-carried state, immutable bindings and transient expression values are all scalar values allocated onto the same four lanes.

Flow and continuation are dynamic roles in time, not different storage classes.

## 1.7 Layout should repair rather than canonicalize

Ordinary execution winds state around four lanes. `UNWIND` redistributes a lane prefix over the other three.

The resulting 4/3 phase mismatch naturally reshuffles occupancy. The compiler treats the resulting lane state as authoritative instead of moving values back to a canonical layout.

## 1.8 The VM should specialize cheaply

The cache and symbolic lane state are finite enough to version locally.

The same stack/cache algebra drives:

- the generated tail-call interpreter;
- native stencil generation;
- startup copy-and-patch;
- demand-driven SSA lowering;
- lazy basic-block versioning;
- continuation virtualization.

# 2. Architectural scalar state

The scalar architectural state is:

```text
S0
S1
S2
S3
```

Each `Si` is an independent unbounded LIFO stack of scalar cells.

The architecture does not define:

```text
operand stack
context stack
return stack
local stack
```

as distinct storage classes.

The compiler may use any lane for any scalar role.

A typical point may look like:

```text
S0.top = expression result
S1.top = temporary
S2.top = loop index
S3.top = return continuation
```

Another point may use all four lanes for transient expression work.

The ISA does not care.

---

# 3. Cells and memory

A scalar lane stores machine cells.

For a Let-oriented implementation, a natural cell is 64 bits and can hold:

- normalized integers;
- an `f64` bit pattern;
- a boolean;
- a native address;
- a continuation token or native/bytecode code address.

Values whose identity or address must exist are not represented by pretending lane backing storage is an object heap.

Records, arrays, hidden result blocks and other addressable aggregates live in explicit byte-addressable memory/frame storage.

A scalar address to such storage may itself live on any lane.

Thus the architecture separates:

```text
scalar LIFO state
```

from:

```text
byte-addressable object/frame memory
```

without separating scalar "flow" from scalar "continuation".

---

# 4. Winding and dynamic roles

The machine has one canonical allocation ring:

```text
S0 -> S1 -> S2 -> S3 -> S0 -> ...
```

A minimal compiler maintains one symbolic winding cursor for newly materialized scalar state:

```c
lane = wind_cursor;
wind_cursor = (wind_cursor + 1) & 3;
```

Routed operations may place results directly on another convenient lane, so the runtime layout is not required to remain a perfect round-robin sequence. The ring is the natural baseline discipline, not an invariant that requires repair moves.

There is no separate continuation allocation direction.

A value's role is temporal:

```text
current flow
future continuation state
current flow again
```

For example, a loop accumulator may be actively consumed and replaced inside an iteration, remain live across the backedge as continuation state, and become active flow again at the next header.

Likewise, a return token is continuation state while buried, then becomes the current control operand when `UNWIND` exposes it for `RESUME`.

The ISA does not encode these roles. It only sees scalar lane state and control tokens.

This replaces the earlier idea of allocating flow and continuation from opposite ends. There is one winding law; the difference between flow and continuation is when a value is active, not which way it was allocated.

# 5. Collision means stacking

When allocation reaches a lane that already holds a live value, the new value simply pushes above it.

Example:

```text
before:

S2:
    loop_limit
```

Transient flow later reaches S2:

```text
after:

S2:
    temporary
    loop_limit
```

No special spill slot is allocated.

No register victim is selected.

The lane itself is the spill history.

When the temporary dies:

```text
pop S2
```

the loop limit becomes current again.

This is the basic overlap mechanism.

---

# 6. Two-cell hot window

Each lane has two dedicated native cache registers.

For lane `Si`, call them:

```text
Ri0
Ri1
```

They cache zero, one or two top logical cells of that lane.

The intended hot scalar budget is therefore:

```text
4 lanes × 2 cells = 8 native cache registers
```

The second cache cell has three important meanings:

1. the next value after a pop is already hot;
2. one level of nested lifetime overlap is register-only;
3. two selected lanes expose four hot values for optional four-leaf `FOLD2` operations.

---

# 7. Per-lane cache states

A lane has five physical cache states.

```text
U
    no lane value currently cached
    the logical lane may still contain values in backing memory

R0
    TOS is in Ri0

R1
    TOS is in Ri1

R01
    TOS is in Ri0
    next logical cell is in Ri1

R10
    TOS is in Ri1
    next logical cell is in Ri0
```

Logical stack depth is distinct from cache state.

The verifier/compiler knows the logical lane depths.

Cache state only describes which logical top cells are resident in the dedicated native cache registers.

---

# 8. Global cache state

The complete physical cache state is:

```text
(K0, K1, K2, K3)
```

where each `Ki` is one of the five lane-cache states.

The theoretical state space is:

```text
5^4 = 625
```

This is implementation state, not ISA state.

The important observation is that an ordinary binary handler only depends on the local states of the lanes it touches.

For two selected lanes, the local cache-state product is:

```text
5 × 5 = 25
```

The other two lane states pass through unchanged.

The generator therefore derives global transitions mechanically rather than hand-writing 625 independent algorithms.

---

# 9. No-refill pop

A pop never reloads merely because it exposed an older value.

Example:

```text
R01
```

means:

```text
Ri0 = top
Ri1 = next
```

Pop:

```text
R01 -> R1
```

No:

```c
Ri0 = Ri1;
```

Similarly:

```text
R10 -> R0
R0  -> U
R1  -> U
```

If deeper logical values exist after a transition to `U`, they remain in backing memory.

They are loaded only when some later instruction actually needs the lane top.

This rule avoids useless:

```text
pop
reload
push
spill
```

traffic.

---

# 10. Push

A push onto an uncached lane uses one free dedicated cache register.

A push onto a one-cached lane uses the other dedicated register.

The old top does not move.

Example:

```text
R0
```

push `x` into `Ri1`:

```text
R10
```

where:

```text
Ri1 = new top
Ri0 = old top
```

A push onto a two-cached lane spills only the cold cached cell.

For example, from:

```text
R01
```

push `x`:

1. spill the old cold `Ri1` to backing storage;
2. write `x` into `Ri1`;
3. reinterpret the state as `R10`.

There is no register-to-register canonicalization shuffle.

---

# 11. First overlap is free

Suppose:

```text
S2 = [continuation]
```

with one cached cell.

A transient value pushes onto S2:

```text
S2 = [temporary, continuation]
```

Both cells are cached.

When the temporary is later consumed:

```text
S2 = [continuation]
```

the continuation is again top, with no backing-memory traffic.

Thus a lane has the following pressure curve:

```text
1 live occupant          register
2 nested live occupants  registers
3+                       backing chain begins
```

This is the reason for choosing four lanes with two cached cells rather than eight lanes with one cached cell.

---

# 12. Full routing/lifetime byte

Every routed binary operation carries one complete byte of placement and lifetime information.

For distinct source lanes:

```text
left source lane       2 bits
right source lane      2 bits
destination lane       2 bits
keep left source       1 bit
keep right source      1 bit
--------------------------------
                       8 bits
```

The opcode says **what** to compute.

The routing byte says:

- where the left source lives;
- where the right source lives;
- where the result should be pushed;
- whether the old left top survives;
- whether the old right top survives.

No bit is wasted.

---

# 13. Routed binary semantics

Let:

```text
L = selected left lane
R = selected right lane
D = selected destination lane

x = top(L)
y = top(R)

r = x OP y
```

For distinct source lanes, the logical effect is:

```text
if keep_left  == 0:
    pop L

if keep_right == 0:
    pop R

push D, r
```

The pushes/pops are logical semantics.

An implementation fuses obvious aliases.

If `D == L` and the left source is consumed, the result can replace the old left TOS directly instead of performing a literal pop and push.

If `D == L` and the left source is kept, the result pushes above the preserved source.

The same rule applies symmetrically to `R`.

If `D` is a third lane, the result is simply pushed there.

Thus one useful arithmetic instruction performs computation, lifetime transition and result placement together.

---

# 14. Depth effect

For distinct source lanes, the depth change of any lane `k` can be described as:

```text
delta(k) =
    +1 if k == D
    -1 if k == L and keep_left  == 0
    -1 if k == R and keep_right == 0
```

When destination aliases a consumed source, `+1` and `-1` cancel.

This is the in-place replacement case.

When destination aliases a kept source, the lane grows by one.

This is exactly the case that a separate `DUP` would otherwise have created.

The verifier and compiler can derive routed stack effects mechanically from these five fields.

---

# 15. KEEP replaces many preparatory DUP/COPY operations

Consider:

```text
S0 = [a, ...]
S1 = [b, ...]
```

If both operands die:

```text
ADD S0,S1 -> S0
keep_left=0
keep_right=0
```

may compile to:

```text
S0.top = a + b
pop S1
```

If `a` must survive:

```text
ADD S0,S1 -> S0
keep_left=1
keep_right=0
```

the logical result is:

```text
S0 = [a+b, a, ...]
S1 = [...]
```

No preceding `DUP S0` dispatch is required.

If both operands must survive and the result belongs on S2:

```text
MUL S0,S1 -> S2
keep_left=1
keep_right=1
```

the logical result is:

```text
S0 = [a, ...]
S1 = [b, ...]
S2 = [a*b, ...]
```

This is dataflow-like, but still touches only genuine lane tops.

KEEP is therefore safe here in a way it was not in reached-stack designs: it can never create an interior hole.

---

# 16. Arbitrary destination is allocation

The destination field is not merely a result-format convenience.

It lets the useful instruction place the result directly onto the compiler's next chosen lane.

Without it:

```text
compute
MOVE result
```

would often require two bytecode dispatches.

With routed destination:

```text
OP L,R -> D
```

the computation itself performs the scheduling transition.

Thus:

> **routing is register allocation.**

---

# 17. Same-source routing

**Open.**

The semantics of:

```text
L == R
```

are not frozen.

Possible choices include:

1. both logical source roles read the same TOS;
2. the form means top-two-of-one-lane;
3. equal-source encodings are reserved for another family.

The architecture does not rely on same-source routing.

Until this is decided, ordinary routed binary code requires:

```text
L != R
```

The optional `FOLD2` family already provides an explicit mechanism for operations involving two cells from one lane pair.

---

# 18. Unary operations

Unary operations name one lane:

```text
NEG Si
NOT Si
CONVERT Si
...
```

and replace its true top:

```text
Si.top = F(Si.top)
```

The logical lane depth is unchanged.

The physical implementation depends only on the selected lane's local cache state.

---

# 19. Explicit structural operations

The architecture still needs explicit one-source structural operations.

Typical forms are:

```text
DROP Si
COPY Si -> Sj
MOVE Si -> Sj
PUSH Si, value
```

`COPY` creates additional liveness:

```text
push Sj, top(Si)
```

while leaving `Si` unchanged.

`MOVE` transfers ownership:

```text
x = pop Si
push Sj, x
```

Many compiler patterns that once required `DUP` or `COPY` before arithmetic are instead handled by the binary routing byte's KEEP bits.

Structural operations remain for cases that genuinely have no useful binary computation to fuse with the lifetime change.

---

# 20. Why deep addressing is deliberately absent

A buried value is not read through the newer values above it.

Suppose:

```text
S0:
    a
    b
    c
    x
```

and `x` is needed while `a`, `b` and `c` remain live.

The VM does not define:

```text
READ S0[3]
```

and it does not destroy:

```text
a
b
c
```

Instead it uses `UNWIND`.

This preserves the strongest property of the design:

> **Every computational source is a true top.**

---

# 21. UNWIND: depth becomes breadth

`UNWIND` exposes a buried value by moving every live value above it across the other lane frontiers.

Example:

```text
S0 = [a,b,c,x,...]
```

Then:

```text
UNWIND S0,3
```

redistributes the live prefix in canonical ring order:

```text
S0 = [x,...]
S1 = [a,...]
S2 = [b,...]
S3 = [c,...]
```

No value was dropped.

No interior cell was removed.

`x` is now a genuine TOS.

The fundamental interpretation is:

> **UNWIND converts vertical depth into horizontal frontier width.**

For prefixes longer than three, redistribution wraps over the other lanes and creates additional cached/backing rows. This folding behavior is part of the semantics, not a scheduling option.

# 22. Deterministic UNWIND semantics

`UNWIND` has no direction bit and no permutation choice.

The machine already has a canonical winding ring:

```text
S0 -> S1 -> S2 -> S3 -> S0 -> ...
```

`UNWIND Si,n` uses the same ring order while skipping the source lane.

For source `Si`, define the three destination lanes as:

```text
Si+1, Si+2, Si+3
```

with lane indices taken modulo four.

The `j`-th popped value, where `j=0` is the original source top, is pushed to:

```text
S((i + 1 + (j mod 3)) mod 4)
```

Thus:

```text
UNWIND S0,n
```

redistributes top-first through:

```text
S1, S2, S3, S1, S2, S3, ...
```

and:

```text
UNWIND S2,n
```

redistributes through:

```text
S3, S0, S1, S3, S0, S1, ...
```

After exactly `n` transfers, the original depth-`n` value is the true top of the source lane.

This is the structural inverse of winding: normal execution creates depth naturally; `UNWIND` turns that depth back into frontier breadth. It is not a general permutation instruction.

There is deliberately no `WIND` instruction. Pushes, routed result placement, nested execution and repeated modulo-four allocation are already the winding process.

## 22.1 Column-to-row folding

Suppose:

```text
S0 = [a,b,c,d,e,f,x,...]
```

Then:

```text
UNWIND S0,6
```

produces:

```text
        S0    S1    S2    S3
top      x     d     e     f
next           a     b     c
```

The older source column has been folded over the three remaining lane columns. Values nearest the exposed target naturally become the new top row.

## 22.2 The 4/3 phase reshuffle

Under the baseline winding discipline, repeated visits to one lane are separated by a modulo-four allocation phase. `UNWIND` redistributes a source prefix over a modulo-three destination cycle.

The relevant arithmetic is:

```text
4 mod 3 = 1
gcd(4,3) = 1
lcm(4,3) = 12
```

The two periodicities therefore do not remain phase-aligned. Redistributing a wound column changes how its surviving values line up with future modulo-four allocation.

This gives the register layout a natural mixing or self-repairing tendency: a bad vertical concentration, once unwound, is not simply rebuilt into the same grouping.

This is a structural tendency, not a theorem that every program monotonically reduces its future `UNWIND` count. Pathological access orders can still create repeated burial.

The compiler should therefore preserve the exact post-`UNWIND` symbolic layout and continue from it rather than canonicalizing values back to preferred lanes.

# 23. UNWIND preserves every live value

If:

```text
S0 = [p,q,x]
S1 = [u]
S2 = [v]
S3 = [ret]
```

then:

```text
UNWIND S0,2
```

produces:

```text
S0 = [x]
S1 = [p,u]
S2 = [q,v]
S3 = [ret]
```

Every value remains live.

Because each destination lane had one cached value, `p` and `q` occupy their free second hot slots.

The entire unwind can therefore occur without backing-memory traffic.

This is the most important interaction between `UNWIND` and the two-cell cache.

# 24. UNWIND removes the strict nested-live-range requirement

Pure LIFO allocation only works when an older value is not needed until every value stacked above it dies.

`UNWIND` relaxes that restriction without adding arbitrary reach.

Suppose:

```text
S0:
    p
    q
    x
```

but `x` is needed while `p` and `q` must remain live.

`UNWIND` rehomes `p` and `q` onto other lane tops.

The compiler therefore does not need perfect global scheduling.

When local allocation produces an inconvenient burial, it can repair the layout structurally.

This is a key reason the baseline compiler can remain simple.

---

# 25. Baseline compiler algorithm

The minimal allocator/compiler state is approximately:

```text
wind_cursor
symbolic stacks S0..S3
```

New materialized scalar state normally follows the modulo-four winding cursor:

```text
lane = wind_cursor
wind_cursor = (wind_cursor + 1) mod 4
```

Routed operations are free to send their result directly to the lane that best serves the next local use; that resulting state becomes the new symbolic truth.

Use:

```text
if required value is already a lane TOS:
    use it

otherwise:
    emit deterministic UNWIND on its lane to expose it
```

Computation:

```text
emit routed OP:
    left lane
    right lane
    destination lane
    keep/consume left
    keep/consume right
```

After `UNWIND`, the compiler does not restore a canonical assignment. It updates its four symbolic stacks to the exact deterministic redistribution and continues winding from that state.

This is important: the architecture relies on the redistribution to repair layout pressure over time.

No graph-coloring register allocator is required for the baseline compiler.

# 26. Continuation as buried future

The architecture does not need a dedicated continuation stack.

A continuation is a scalar control token buried under later work.

The lane histories already preserve the caller's older scalar state.

A return continuation therefore only needs to encode where control should continue.

The rest of the continuation is implicit in the older values already stored underneath newer lane values.

This gives the central continuation principle:

> **A continuation is a buried future. UNWIND makes that future current again.**

---

# 27. LINK and RESUME

The conceptual continuation primitives are:

```text
LINK Si, target
RESUME Si
```

`LINK` pushes a continuation token representing `target` onto lane `Si`.

It does not need to save every scalar local or native register.

Those values are already preserved by the four lane histories.

`RESUME Si` requires the continuation token to be the true top of `Si`.

It consumes that token and transfers control to it.

No other lane is implicitly restored.

Any values that should survive the transition remain live on their lanes.

---

# 28. Calls are LINK plus control transfer

A direct call can be lowered conceptually as:

```text
LINK Sk, return_target
JMP callee
```

The continuation token may be created before later argument/callee work stacks above it.

The callee uses the same four lanes.

Its values may shadow caller values:

```text
before call:

S2 = [caller_local]
S3 = [caller_state]

inside callee:

S2 = [callee_temp, caller_local]
S3 = [callee_value, caller_state]
```

When callee values die or are redistributed, the caller's older values naturally reappear.

There is no scalar register-save frame.

---

# 29. Returning through UNWIND

Suppose a continuation token is buried:

```text
S3:
    r2
    r1
    K_return
    caller_state...
```

and both `r2` and `r1` are live return values.

Returning does not drop them.

Instead:

```text
UNWIND S3, 2
```

redistributes them onto other lanes.

For example:

```text
S0 = [r2,...]
S1 = [r1,...]
S3 = [K_return, caller_state...]
```

Then:

```text
RESUME S3
```

consumes the exposed continuation token and jumps.

Thus return-value allocation and continuation restoration use the same structural primitive.

---

# 30. CALL and RET are optional encoding fusions

The semantic core does not require architectural `CALL` and `RET` instructions.

A compact implementation may later provide:

```text
CALL
```

as a fused encoding of:

```text
LINK + JMP
```

and may provide a return form that fuses some common:

```text
UNWIND + RESUME
```

pattern.

Such instructions are compression/performance forms over the continuation algebra.

They do not define the underlying semantics.

---

# 31. Tail calls

A tail call creates no new continuation.

Conceptually it is simply:

```text
arrange required live state
JMP callee
```

Any caller-local values that must disappear are consumed or redistributed before the jump.

The callee eventually resumes the caller's existing continuation token.

Thus:

> **tail call = call without LINK.**

No frame-destruction instruction is required.

---

# 32. Nested calls

Nested calls naturally bury continuation tokens and scalar state.

A lane may look like:

```text
S3:
    current callee temporary
    current return token
    parent return token
    older state
```

Another lane may simultaneously contain:

```text
S1:
    callee local
    caller local
    caller's caller local
```

This is legal.

Return uses liveness plus `UNWIND` to preserve surviving values while exposing the current continuation token.

The older caller state underneath then becomes current again.

---

# 33. Loops are transitions between flow and continuation regimes

Loops do not need a separate architectural loop stack.

Loop-carried values are ordinary lane values. Their role changes with control time.

For an accumulator:

```text
inside iteration:
    active flow

across backedge:
    continuation state

next iteration:
    active flow again
```

No storage-class conversion occurs.

A loop body naturally winds transient state over older loop-carried state. When a buried carried value, exit token or enclosing continuation is required, `UNWIND` exposes it while redistributing the still-live prefix.

This means an iteration can behave like:

```text
incoming frontier
    -> ordinary modulo-4 winding
    -> computation
    -> lifetime consumption
    -> UNWIND if a buried future is demanded
    -> reshuffled outgoing frontier
    -> backedge/resume
```

The outgoing lane layout need not equal the incoming one.

A backedge therefore does not require a canonical register assignment. Lazy block versioning may compile different header versions for the layouts that actually arrive:

```text
header_A -> body_A -> header_B
header_B -> body_B -> header_C
header_C -> body_C -> header_A
```

The loop can settle into a fixed layout or a small layout orbit.

This is a natural decomposition of the loop into physical allocation phases while preserving one semantic SSA loop.

Break, continue, nested-loop exit and function return are all instances of the same question:

> **Which buried future becomes current now, and which live values survive into it?**

When a loop or nested region buries a control continuation under later work, `UNWIND` exposes it in exactly the same way as a function return.

# 34. Minimal live continuation

The compiler should keep only scalar values that are still required by the future continuation.

An immutable binding may die at its last use rather than at lexical scope end.

The routed KEEP bits make this local:

- if the source has another future use, KEEP it;
- if this is its last use, consume it.

A continuation therefore tends to shrink as execution approaches a call, return, loop exit or other boundary.

This reduces lane pressure before control transitions without requiring a special context-stack cleanup protocol.

---

# 35. Multiple results

Multiple results are ordinary live scalar values.

A callee may finish with several results distributed across lane tops.

If a continuation token is buried beneath some of those results, `UNWIND` preserves and redistributes them before `RESUME`.

There is no requirement for fixed architectural return registers beyond the lane-routing convention chosen by the compiler/calling convention.

A language such as Let, whose multiple results are ordered scalar cells rather than tuple objects, maps naturally onto this mechanism.

---

# 36. DAG fan-out

Tree-shaped computation normally consumes values once.

A DAG creates genuine multiple future uses.

The routing KEEP bits eliminate many explicit fan-out preparations when one of those uses is the current arithmetic operation.

For example:

```text
OP L,R -> D
keep_left=1
keep_right=0
```

uses the left source while preserving it for another future edge.

If a value must be duplicated without an accompanying useful binary operation, explicit `COPY` remains the structural primitive.

Thus:

```text
KEEP = preserve through useful computation
COPY = create fan-out without such a computation
```

---

# 37. Four-leaf tree tile

Two cached cells on each of two lanes expose:

```text
Si0 Si1
Sj0 Sj1
```

This matches the local tree:

```text
          op2
         /   \
       op1   op1
      / \     / \
    Si0 Sj0 Si1 Sj1
```

or:

```text
(Si0 op1 Sj0) op2 (Si1 op1 Sj1)
```

This shape is important enough that the compiler may greedily recognize it.

The ordinary four-lane routing algebra remains the core.

---

# 38. Optional FOLD2 extension

`FOLD2` is an optional extension for the four-leaf tile.

Conceptually:

```text
FOLD2(op1,op2) Si,Sj -> D
```

performs:

```text
x0 = Si0 op1 Sj0
x1 = Si1 op1 Sj1
r  = x0 op2 x1
push D, r
```

The exact lifetime policy and enumerated `op1/op2` family are not frozen by this specification.

`FOLD2` is intentionally kept orthogonal to the ordinary routed binary byte rather than complicating the core semantics.

---

# 39. Handler shape

A generated handler is specialized to:

```text
opcode
routing byte
incoming four-lane cache state
```

Therefore it knows:

- which two lanes are sources;
- which lane receives the result;
- whether each source survives;
- exactly which physical cache register currently holds each cached source top;
- which second cache cells exist;
- which cache registers are free;
- which backing access is required for an uncached source;
- the exact outgoing cache state.

The handler does not decode a generic runtime cache structure.

The current handler identity/control-flow state already encodes this information.

---

# 40. Cached binary fast path

Suppose both source tops are cached.

For:

```text
ADD S1,S3 -> S2
keep_left=0
keep_right=0
```

the conceptual native sequence is:

```c
R2_free = R1_top + R3_top;
```

followed by cache-state transitions that consume the old S1 and S3 tops and make the new S2 top live.

If destination aliases one consumed source:

```text
ADD S1,S3 -> S1
```

the hot operation is simply:

```c
R1_top = R1_top + R3_top;
```

then the S3 cache state pops.

If one source is kept and destination aliases that source, the result is pushed into that lane's other cache register when free.

Thus the routing/lifetime byte maps directly onto useful native register operations.

---

# 41. Uncached source behavior

If a selected source lane is in state `U` but logically nonempty, its top resides in backing memory.

The handler reads that top directly.

A consuming use advances the backing representation.

A kept use leaves it in place.

The handler does not refill the lane merely because it touched the value.

If the result is pushed into that lane, the now-useful result may occupy one of the dedicated cache registers.

Thus computation can opportunistically re-cache a lane without an eager refill policy.

---

# 42. UNWIND handler behavior

`UNWIND` is deterministic.

For a statically known source `Si` and count `n`:

1. pop the source lane;
2. push the popped value to `Si+1`, `Si+2`, then `Si+3`, modulo four and skipping the source;
3. repeat that three-lane cycle;
4. stop after exactly `n` transfers;
5. the former depth-`n` value is now the source-lane TOS.

The generator knows the incoming cache state and can emit the minimal native actions for every transfer.

Many transfers remain entirely within the eight hot cache registers.

Because the count and destination sequence are known, startup copy-and-patch can unroll the operation completely.

The resulting cache/lane state is not canonicalized. It is the outgoing ABI state for the next stencil or block version.

# 43. Cache state is the stencil ABI

The eight dedicated cache registers are not just an interpreter optimization.

They form the native VM ABI between generated handlers/stencils.

The tail-call interpreter carries them as hot values between tiny specialized handler functions.

The startup copy-and-patch compiler uses the same register convention between adjacent native stencils.

Therefore:

> **stack caching is native register allocation from the beginning.**

No second allocator is required merely to keep ordinary scalar VM state in registers.

---

# 44. Startup copy-and-patch

The baseline native execution path is:

```text
verified bytecode
    ->
walk control flow with known logical lane shapes
    ->
choose stencil for opcode + routing + cache state
    ->
copy stencil
    ->
patch immediates and native control edges
    ->
run
```

Dispatch disappears from stitched code.

This removes the main reason for a superinstruction layer.

The bytecode remains semantic and regular while native stencils become contiguous code.

---

# 45. Why UNWIND works well with copy-and-patch

An interpreted `UNWIND` may conceptually consist of several transfers.

In startup-compiled code:

```text
UNWIND S0,3
```

is known statically.

The compiler emits only the concrete cache/backing transitions required for those three values.

If the destination second-cache slots are free, an unwind may reduce to a small sequence of native register moves plus changed cache-state interpretation.

There is no dynamic search for the buried value.

The compiler already knows the lane and depth.

---

# 46. Lazy basic-block versioning

A later optimizing tier lazily compiles block versions keyed by facts such as:

```text
SSA/basic block
incoming symbolic lane contents
incoming four-lane cache state
known constants
known call targets
virtual continuation state
demanded outgoing values
```

The important addition is that lane layout is not normalized at control-flow joins.

If two predecessors reach the same semantic block with different physical lane states, the compiler may create two versions of that block rather than inserting moves solely to force one canonical assignment.

The versioner propagates facts along executed edges. It may forget facts and fall back to a less-specialized or baseline block version at any time.

Correctness does not depend on specialization.

The baseline copy-and-patch code remains the universal fallback.

---

# 47. Virtual continuation

A specialized known call does not necessarily need to materialize a `LINK` token.

The block-version compiler may carry:

```text
return block
caller symbolic lane state
values demanded by the return continuation
```

as compiler metadata.

The callee's specialized `RESUME` becomes a direct continuation into the caller's next block version.

That block version may accept exactly the lane layout produced by the callee's final `UNWIND`; no canonical return-register shuffle is inherently required.

If execution must leave the specialized region, the omitted continuation token and any required baseline state are materialized before resuming baseline execution.

This is the optimized form of the same architectural continuation semantics.

---

# 48. Direct SSA lowering

The four-lane machine can be a direct target for SSA rather than lowering SSA first and then running an unrelated global register allocator.

The correspondence is unusually direct:

```text
SSA definition           -> routed push/result placement
SSA use                  -> selected lane TOS
future use remains       -> KEEP
last use                 -> consume
live-range overlap       -> ordinary stacking
buried demanded value    -> UNWIND
control-flow future      -> block edge / LINK continuation
join                     -> block version with incoming symbolic layout
```

SSA already provides the exact lifetime fact the routing byte needs: whether a source has another future use.

Therefore KEEP/consume is not guessed from stack syntax. It comes directly from SSA liveness/use information.

This eliminates a large class of preparatory `DUP`, move, spill and reload operations that a conventional backend introduces after SSA destruction.

The VM still has physical constraints: only lane tops are directly usable, and each lane has finite hot cache. `UNWIND` is the structural fallback when the demanded SSA value is buried.

---

# 49. Phi nodes and block arguments

A conventional SSA backend often destroys a phi by placing edge moves so every incoming value occupies one canonical physical location.

This VM need not do so.

For:

```text
B3:
    x = phi(x1 from B1, x2 from B2)
```

one predecessor may arrive with:

```text
x1 = S0.top
```

while another arrives with:

```text
x2 = S2.top
```

The compiler may create:

```text
B3/layout_A: x is S0.top
B3/layout_B: x is S2.top
```

rather than emitting a move only to make both edges agree.

The phi becomes a semantic name/block argument; the block version supplies its physical interpretation.

This same mechanism handles loop-header phis. A backedge may feed the next iteration in the exact lane layout produced by the previous iteration.

Version limits remain an implementation policy. If too many layouts reach one block, the optimizer may merge facts or fall back to a more generic entry. Canonicalization is a pressure-release valve, not the default semantics.

---

# 50. Demand-driven compilation

The natural compilation unit becomes approximately:

```text
compile(block, incoming_state, demanded_values)
```

where `incoming_state` contains the symbolic four-lane contents, cache state and known control/constant facts.

Compilation starts from what the block's continuation or consumer actually demands.

For a demanded SSA value:

1. if it is already an exposed lane top, use it;
2. if it is live but buried, emit the deterministic `UNWIND` required to expose it;
3. if it is virtual, recursively demand the operands that define it;
4. fold it if the inputs are statically known;
5. otherwise emit the routed operation directly into a useful destination lane;
6. KEEP operands with remaining uses and consume last uses;
7. preserve the exact resulting lane state for the next demand.

The compiler therefore does not need to eagerly lower an entire SSA graph and then repair the resulting register pressure.

It can materialize computation only when a value becomes necessary.

A continuation is naturally a future demand:

```text
resume block B
requiring values {x,y,z}
```

A known continuation can remain virtual compiler metadata. A residual runtime continuation is materialized with `LINK` and later exposed through `UNWIND`.

---

# 51. Loop layout phases and self-repair

Demand-driven block versioning and the 4/3 unwind reshuffle interact particularly well in loops.

Suppose one iteration enters with:

```text
i   = S0
acc = S2
```

and its computation/unwind leaves:

```text
i_next   = S1
acc_next = S3
```

A conventional backend would often move those values back to the loop header's chosen registers.

This VM may instead compile the next header version for the produced layout:

```text
header_A(S0,S2)
    -> body_A
    -> header_B(S1,S3)
```

If `header_B` later returns to layout A, the physical loop has a two-phase orbit. Other loops may converge to a fixed layout or visit a few states before repeating.

This is not semantic loop unrolling. It is physical allocation-phase specialization of the same SSA loop.

The crucial rule is:

> **Do not destroy the post-UNWIND reshuffle merely to recover a canonical register assignment.**

The mismatch between modulo-four winding and modulo-three redistribution is useful state. Preserving it lets later execution inherit the repaired frontier and may reduce the need for further unwinds.

# 52. Frontend call elimination

A language frontend with partial evaluation and known code identity may remove even more call boundaries before bytecode is emitted.

A known call may be:

- executed completely at compile time;
- specialized;
- inlined/residualized into the caller;
- lowered as a tail jump.

Therefore runtime continuation tokens are only required for the truly residual call boundaries.

The VM's continuation model does not force source-level calls to materialize runtime frames.

---

# 53. Frame memory

The four scalar lanes do not replace byte-addressable frame memory.

A value that requires an address must live in explicit storage.

Examples:

```text
record with identity
array
hidden aggregate result
environment block
object named by ref/ptr
```

The compiler may scalarize an aggregate into lane cells when it proves no observable identity or address is required.

Otherwise it allocates frame memory and keeps only addresses/scalars on the lanes.

This separation keeps the lane semantics honest.

---

# 54. Verification

For materialized bytecode, the verifier tracks the logical depth and required logical lane shape at every instruction.

It checks:

- no lane underflows;
- all jump targets begin at valid instructions;
- incoming edges to one materialized bytecode block agree on that block's logical lane contract;
- routed binary source lanes are logically nonempty;
- routed lifetime effects produce the verified outgoing depths;
- `UNWIND Si,n` requires at least `n+1` logical values in the source lane;
- `FOLD2`, when implemented, requires two logical values in each selected source lane;
- `RESUME Si` sees a continuation token at that lane top according to the verified calling/control convention;
- memory/frame accesses remain valid.

A semantic SSA block is allowed to have several materialized block versions with different lane layouts. Each version has its own verified entry contract. Block cloning/versioning is therefore how different physical layouts coexist without making one bytecode instruction ambiguous about its routed lanes.

Cache state is not semantic verification state.

A valid materialized block remains valid regardless of which of its logical top cells happen to be cached on entry; cache-state specialization is a native execution concern.

---

# 55. Why the compiler may remain simple

The architecture embeds several allocation decisions in its storage model.

```text
new scalar value
    -> wind to a lane / route directly to a useful lane

push
    -> allocate newer value

one overlap
    -> use second hot register

more pressure
    -> lane backing chain

future SSA use
    -> KEEP

last SSA use
    -> consume

need buried value
    -> deterministic UNWIND

control join with a new layout
    -> select/compile a matching block version
```

The baseline compiler does not need to invent separate spill slots, reload instructions or a graph-coloring solution for ordinary scalar state.

More importantly, it does not need to prevent every inconvenient layout in advance.

Its policy can be:

> **Wind cheaply. Route locally. Unwind only on demand. Keep the repaired layout.**

Demand-driven SSA lowering supplies precise lifetime information, while the VM supplies the structural fallback when that information produces a buried live value.

# 56. Comparison with a flat register VM

A flat register machine exposes a fixed set of current values.

If a register must hold a new value while its previous value remains live, the compiler has to move or spill the old value explicitly.

In this VM, every lane has an automatic LIFO history:

```text
new current value
older value
older value
...
```

and the first two values are cached.

The ISA is register-like in that instructions name a small set of lanes.

It remains stack-like in that old values survive underneath and reappear naturally.

The result is:

> **four routed register names, each backed by an automatic LIFO history.**

---

# 57. Comparison with a traditional stack VM

A traditional stack VM provides one frontier.

This VM provides four.

A traditional binary op usually relies on top and next-on-stack.

This VM normally consumes two independently selected true tops.

The routing byte adds register-like placement/lifetime control without permitting arbitrary interior mutation.

`UNWIND` solves inconvenient depth structurally rather than by turning the lanes into random-access arrays.

---

# 58. Comparison with the previous A/B/C design

The previous design had:

```text
A/B operand frontiers
separate C continuation stack
shared operand register bank
```

The current design has:

```text
four identical routed scalar lanes
two hot cells per lane
no architectural continuation storage class
```

It gains:

- four simultaneous frontiers rather than two;
- complete source/result routing in one byte;
- explicit source lifetime in that same byte;
- one free nested overlap per lane;
- a unified continuation model based on buried tokens;
- one natural winding law instead of separate flow/continuation allocation directions;
- deterministic modulo-three `UNWIND` redistribution over the other lanes;
- a 4/3 phase reshuffle that naturally repairs some register layouts;
- direct SSA lifetime lowering and layout-specialized joins;
- `UNWIND` as a universal depth-repair, register-reshuffle and continuation-restoration primitive.

It pays for this with:

- 16-bit routed binary instructions rather than one-byte fixed-A/B binaries;
- a larger cache-state space;
- a compiler that chooses among four lane names rather than two.

The design deliberately accepts those costs because the routing byte subsumes allocation and lifetime operations that would otherwise become extra dispatches.

---

# 59. Open questions

The following are deliberately unresolved.

## 59.1 Same-lane binary sources

The semantics of:

```text
OP S2,S2
```

are not yet frozen.

## 59.2 Exact UNWIND encoding

The deterministic source-relative redistribution order and count semantics are specified.

The final compact opcode/immediate format is not.

## 59.3 Exact LINK/RESUME token representation

A continuation token must identify a continuation target.

Whether it is a bytecode offset, native address, tagged code pointer or tier-specific representation is an implementation/calling-convention decision.

## 59.4 Exact backing-lane representation

The lanes are architecturally unbounded.

The backend may use separate pointers, a shared activation spill area, statically assigned lane regions or another representation.

This should be chosen against the native register budget rather than frozen in the ISA.

## 59.5 FOLD2 enumeration

The four-leaf tile is structurally attractive.

The exact set of `op1/op2` combinations worth one-byte opcode space remains empirical.

---

# 60. Core laws

The architecture can be summarized by the following laws.

### Law 1: four identical scalar LIFO lanes

```text
S0 S1 S2 S3
```

### Law 2: two hot cells per lane

```text
Si0 Si1 | backing
```

### Law 3: ordinary computation only reads true tops

No arbitrary depth operand exists.

### Law 4: the routing byte is complete

It encodes:

```text
left source
right source
destination
left lifetime
right lifetime
```

### Law 5: KEEP is safe because it only preserves a true TOS

It never creates an interior hole.

### Law 6: destination routing is allocation

The useful operation places its result directly on the desired frontier.

### Law 7: ordinary execution is WIND

New state naturally winds around the modulo-four lane ring. There is no separate `WIND` instruction.

### Law 8: overlap is stacking

Newer live values may shadow older live values on the same lane by ordinary LIFO nesting.

### Law 9: first overlap is register-only

The second hot cell absorbs one nested collision without backing traffic.

### Law 10: UNWIND has one deterministic meaning

It exposes a buried source-lane value by redistributing the live prefix over the other three lanes in canonical ring order.

### Law 11: winding and unwinding have different periodicities

Winding is modulo four; redistribution is modulo three. The coprime 4/3 phase relationship reshuffles surviving state relative to future allocation.

### Law 12: never canonicalize merely for aesthetics

The exact post-`UNWIND` lane state is useful allocation state and should feed subsequent computation or a matching block version.

### Law 13: continuation is a dynamic role

A continuation token or loop-carried scalar is an ordinary buried value whose future control region has not yet become current.

### Law 14: continuation is buried control state

A continuation token is pushed, later exposed by `UNWIND`, then consumed by `RESUME`.

### Law 15: SSA lifetime maps directly to routing lifetime

Future uses imply KEEP; last use implies consume. Buried demanded values imply `UNWIND` rather than a global reallocation pass.

### Law 16: block versions may carry physical layout

A semantic join or loop header may have multiple physical entry versions instead of forcing all predecessors into one canonical lane assignment.

### Law 17: frame memory remains real memory

Addressable aggregate storage is not faked with scalar lanes.

### Law 18: the cache is the native ABI

Interpreter handlers and native stencils share the same hot-state representation.

# 61. Thesis

The machine begins with a stack insight:

> LIFO storage handles nested lifetime exceptionally well.

It adds a register insight:

> several simultaneously exposed values make compilation and arithmetic much easier.

It therefore provides four independent LIFO frontiers.

It adds a cache insight:

> the first nested collision on a lane is common enough to deserve another native register.

It therefore caches two cells per lane.

It adds a routing insight:

> if source location, result location and source lifetime fit in one byte, the useful instruction itself can perform most local allocation work.

It therefore uses the full routing byte.

It adds a winding insight:

> ordinary execution already performs the constructive half of layout management.

New scalar state winds around four lane frontiers. No separate `WIND` primitive is required.

It adds an unwind insight:

> a buried value should not become random-access merely because it is needed early.

The live prefix should be preserved and unfolded over the other three frontiers until the demanded value becomes a true top.

Because winding is modulo four and unfolding is modulo three, the operation also changes allocation phase. A vertical concentration becomes a different horizontal frontier arrangement rather than being reconstructed unchanged. This gives the machine a natural self-repairing register-layout tendency.

It adds a continuation insight:

> flow and continuation are not separate storage classes; they are different moments in the lifetime of the same values.

A loop-carried scalar can move from active flow to future continuation and back to active flow without changing representation. A call is the same general pattern with an explicit buried control token.

Finally, it adds an SSA insight:

> SSA already knows which values exist, which uses remain, and which futures demand them.

That information can lower directly into routed destination, KEEP/consume and deterministic `UNWIND`. Joins and loops may be specialized to the physical lane states that actually arrive rather than repaired into one canonical register assignment.

The result is a machine in which:

```text
ordinary execution     winds state modulo 4
routing                performs local allocation
KEEP                   performs local lifetime control
stacking               performs scalar spilling
two-cell cache          makes one overlap free
UNWIND                  exposes demand and redistributes modulo 3
4/3 phase mixing        reshuffles future allocation
LINK/RESUME             express materialized continuation
demand-driven SSA       decides what must exist now
lazy BBV                accepts the layout that actually arrives
copy-and-patch          removes dispatch
```

The compiler need not maintain a perfect register layout continuously.

It can instead follow a much simpler discipline:

> **Wind cheaply. Compute from true tops. Preserve only real future uses. Unwind when a buried value becomes demanded. Keep the reshuffled state. Compile the continuation that actually arrives.**

The design can be stated compactly:

> **Four stacks. Two hot tops each. One complete routing byte. Execution winds on four; UNWIND unfolds on three. Continuations are buried futures, and SSA demand decides when those futures and values become current.**
