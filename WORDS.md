# Staged words: one semantic system

Design proposal grounded in the language specification, especially §§0–1, 4–6,
9–12, 14–15. This is the implementation target, **not implemented coverage**.
The proposed direct-call-only inliner is abandoned. The current scalar builder is
useful machinery, but its restrictions do not define the word model.

## 1. The organizing distinction

Separate **code**, **owned state**, and **one invocation**:

| Entity | Contains | Does not imply |
| --- | --- | --- |
| Template | Lexical binding identities; ordered stages and preparation regions; data/runtime terminal; phase and constraints | A runtime allocation or an invocation |
| Word value | Template/entry identity, next stage, stable fields, captured access paths | A universal closure object or permission to duplicate its state |
| Prepared activation | Access to an existing receiver, newly supplied stages, reached invocation-local preludes, temporary owners and loans | Execution of the terminal or another return continuation |
| Place | Owner identity and a field/index path with a capability | A copied value or a runtime borrow object |
| Region | Lifetime boundary and successful-initialization order | A required heap arena |

These are semantic roles. Immutable ASDL describes their shapes and operations.
Construction, constraint solving, ownership facts, demand, and physical placement
live in contexts. There is still one semantic belt, not a checked-AST clone followed
by an evaluator-specific residual AST.

A mutable field has a stable **place identity**, not a succession of unrelated
captured scalar snapshots. Its contents may become SSA values when no observation
requires an address. A stateful receiver is not copied into each activation and
written back after return: that would break aliases, reborrows, and tail transfers.

## 2. Lexical construction and recursion

Resolve names to binding IDs, never through the caller's name map. A template
captures exactly its free bindings. Preserve the distinction between copied values,
borrowed owner paths, and state owned by the constructed word (§10).

Module initialization is an ordered runtime region. Construct top-level bindings
in source order, publishing each name after its initializer completes. Module
unload drops completed bindings in reverse order. There is no implicit main.
Compiling known initializers is not permission to execute their host effects.

The terminal's self reference identifies the original defining word, not a copy
of the current invocation's transient argument packet. Keep a separate self binding
available only in the terminal (§4.2). It must not introduce an owning cycle or make
later module declarations visible. Self and lexical-owner links are accesses, not
additional owners; an escaping result must prove those links outlive it.

## 3. One advancement protocol

Use one advancement operation with an explicit destination lifetime. Persistent
specialization and transient saturation share stage checking and reached-prelude
execution; they differ in ownership destination and permitted loans.

```text
construct(template, captures, destination):
    acquire captures with their declared access/ownership
    run the initial preparation region exactly once
    stop at the first unsatisfied stage, or complete the terminal boundary

advance(cursor, argument, destination):
    require one remaining stage
    check its phase, constraint, and capability against this argument
    bind it into the destination
    run the consecutive newly reached preludes, in order
    stop at the next stage, or complete the terminal boundary

complete boundary:
    data terminal -> construct and return data; never invoke it implicitly
    do terminal   -> produce a ready runtime word/activation; do not enter it
```

The destination is an explicit region/owner, not an inference from which compiler
method happened to call advancement. Initial and inter-stage preparation can call
runtime words and can themselves contain a multi-block belt region. Their completion
interface is a typed state packet, not a source-level return.

Specialization evaluates the receiver and each argument left to right, advancing
after each argument. If completion produces another word as data, subsequent
specialization arguments apply to that value (§5.2). A ready do terminal cannot
absorb more stages by executing its body.

Invocation uses the same protocol:

```text
evaluate receiver once
begin an activation with access to its existing stable state
for each source argument:
    evaluate the argument in the caller's lexical environment
    advance one stage into the activation
    finish that stage's preparation before evaluating the next argument
require exact saturation and a do terminal
enter the prepared activation
```

There is no IR operation meaning 'evaluate all source arguments, then run preludes'.
An eventual Enter can take a completed packet because the earlier advancement
operations already enforced that order. Host words use this protocol too; an ordinary
C function is a host terminal with empty preparation regions, not a second call model.

## 4. Ownership and state placement

Each field descriptor records its semantic shape, writable/interior-mutable status,
and access mode: Copy value, owned value, read loan, or mutable loan. Borrow provenance
identifies an owner and path; it is not erased to an unqualified machine pointer.

| Event | Ownership/lifetime consequence |
| --- | --- |
| Persistent plain stage | Copy only; no retained read loan |
| Persistent mut stage | Forbidden by §5.3 |
| Persistent own / own mut stage | Acquire fresh or visibly moved ownership; own mut creates writable state |
| Transient plain stage | Copy or read loan, as specified by the actual shape |
| Transient mut stage | Loan of the actual place, not copy-in/copy-out |
| Transient own / own mut stage | The receiving entry owns it and releases it at that entry's exit |
| Reached persistent prelude | Newly initialized state belongs to the resulting word |
| Reached transient prelude | The call site builds it; the entry it is handed to releases it |

An existing receiver's stable state stays with that receiver. An invocation borrows
the access it needs; it does not destroy persistent state on ordinary return.
A freshly produced receiver needs a temporary owner whose lifetime covers invocation.
Borrowed captures of a non-escaping word remain loans; storing the word must not
silently turn them into owned state. Escape checking follows result and storage uses,
including ownership-taking calls, rather than just looking for a return statement.

Access requirements for a concrete word include the paths its terminal reads, writes,
or consumes. Apply them to the actual receiver capability, including projected word
views. Track changes to initialization of persistent fields across calls. An immutable
owning binding and a narrowed read loan are not interchangeable: the counter example
permits invocation of its private mutable state, whereas §9 forbids mutation through
a read-only borrowed owner. The precise higher-order boundary is noted in §11 below.

Initialization facts and loan sets are side-table dataflow facts. At a join, usable
ownership must hold on every predecessor. Conditional destruction may need a runtime
alive bit; that is not a runtime permission to read a maybe-moved value. Loops and
recursive call summaries solve these facts to a fixed point.

Physical storage follows proved lifetime and access: SSA for unobserved scalar state;
explicit cells for observable places; module storage for module owners; caller or
activation storage for bounded loans; independently owned storage for escaping state.
Do not heap-allocate every word or add reference counting. An owning representation
must keep borrowed views valid for their allowed lifetime when its owner is moved;
use stable storage or owner-relative paths as required, not stale self-pointers.

## 5. Return, tail transfer, and traps

Normal return first preserves/transfers its result, then closes invocation-local
scopes in reverse successful-initialization order, including reached transient
preludes and argument temporary owners. Release loans at their proper boundary.
Do not drop receiver-owned stable fields. Destruction of the receiver is a separate
owner-lifetime event. Returned words undergo the same escape checks as other values.

A tail call has a **preparation region distinct from the retiring activation**:

```text
evaluate receiver and prepare each stage/prelude of the next activation
prove its receiver, captures, loans, and temporary owners survive caller retirement
transfer moved ownership into the prepared destination
retire the old activation, preserving that destination
enter the destination with the same return continuation
```

The prepared destination must not accidentally live in the scope being cleaned.
A read loan derived from a caller local that retirement destroys is illegal. Fresh
argument temporaries must be assigned an explicit surviving owner or rejected for
a real lifetime violation; they are not automatically classified as caller locals.
No cleanup is postponed until after the tail callee returns.

All operations remain on the ordered dependency chain. A trap exits through the
host trap hook immediately, without running pending normal cleanup (§14.2). A
prepared packet partially constructed before a trap is not unwound by Let. Recoverable
paths are ordinary control and therefore have explicit, normal region exits.

## 6. Belt contracts to implement

The existing Word/Supply/Invoke declarations are placeholders, not enough to encode
these rules. Replace them together rather than extending an accidental opcode ABI.
Names below describe contracts; final ASDL fields should encode these distinctions:

| Operation/region | Inputs | Completion |
| --- | --- | --- |
| Construct | Effect, template identity, resolved capture packet, destination | Initial preparation, then word or data plus effect |
| Begin activation | Effect, receiver access, activation region | Unsupplied activation cursor plus effect |
| Advance | Effect, cursor, one value/place with capability, destination | Checked stage binding and reached preparation, next cursor/data plus effect |
| Enter | Effect, ready activation, resolved terminal contract | Result plus effect on normal return |
| Tail enter | Effect, ready activation, inherited return destination | Control exit, not a result-producing call followed by Return |
| Finish preparation | Effect and typed live field packet | Next boundary, no enclosing source return |
| End region | Effect, reverse-ordered lifetime obligations and retained outputs | Destruction/loan release and successor effect |

Include an initial preparation entry in each template. Distinguish data and runtime
terminals, and persistent word state from transient activation state. Effects are
dependencies, not ordinary captured user fields. Packet layouts are typed by boundary;
do not assume every stage adds exactly one slot or that an effect has the same slot
number in every kind of packet.

Capture/stage/prelude field IDs are stable independently of storage layout. Across
blocks, packet fields travel as block parameters. Within blocks, use existing relative
producer/output references and never renumber during demand analysis. Frontend places
retain owner/path identity even when their physical realization uses an address.

Verification must establish boundary contracts, exact stage advancement, loan and
ownership transfers, region exits, and prepared-tail survival, in addition to opcode
types and effect continuity. An Effect token alone proves none of the ownership rules.

## 7. Concrete contracts and higher-order words

A generic template is not assigned one global inferred callback signature. Each
concrete use supplies shape and capability constraints. Its executable contract
includes remaining stages, result shape, capture access, escape behavior, and state
initialization transitions. Executable by itself proves only an eventual do terminal.

Instantiate a body against a concrete contract using constructor-owned elaboration
methods. Keep the original AST as the source template; do not construct another
annotated AST. Publish an in-progress entry before descending into calls, so recursive
references target a shared contract node rather than recursively copying the body.
Solve call-graph strongly connected components for compatible interfaces and summaries.

Different concrete answer shapes can have different instantiations of the same
source template. Do not accidentally impose an earlier compiler's monomorphic callback
contract on the language. Unknown scalar values are normal runtime inputs; unresolved
primitive representations are a static error only when the relevant constraints
cannot be proved. An analysis budget limit is an implementation limit, not such a proof.

Known word identities specialize to direct entries. If control selects among several
word values with a compatible concrete contract, retain the necessary code selection
and state representation. Dispatch on a word's runtime entry identity is not implicit
runtime type inference. No universal tagged value or public function-pointer ABI is
required, but dynamic word selection must not simply be rejected to avoid designing it.

## 8. Consumer-driven execution and output

A demand context identifies an instantiated region, its abstract inputs/memory state,
and demanded outputs or paths. Producer answers are memoized within that context.
Answers may contain known scalar bits, structured field answers, word entry/state
descriptions, storage references, or scheduled runtime results.

Start with observable returns, selected control, effects, and lifetime obligations.
Ask producers for answers backward; execute or schedule their dependencies forward.
A shared producer is not re-executed for each consumer. Loop iterations and distinct
word instances are not confused merely because their instructions share a source ID.

A runtime host remains runtime even with known arguments. Compiler-known primitive
semantics can produce known answers; host registration must not be treated as permission
to invoke arbitrary runtime host code while compiling. Pure unused results may vanish;
effects, traps, movement, and required destruction do not vanish with them.

Track mutable contents by place identity and effect/memory version. Two counters with
the same template and starting value are distinct mutable owners. Specialization-cache
keys can share code by layout and contract, not coalesce those instances. Borrowing or
escaping a place invalidates inappropriate known-content assumptions.

Use a worklist for recursive demand and abstract loop entries. Generalize changing
known scalar inputs to runtime values when needed; do not unroll indefinitely.
Structural constraints and lifetime facts need their own sound fixed points, not
arbitrary guesses made when value-specialization fuel runs out.

The emitter consumes these answers and per-region schedules directly into C ASDL.
It must not build a second semantic residual program. Known-identity stage advancement
may disappear physically; all its required effects and lifetime actions remain.

## 9. Native calls and bounded tail execution

Physical C interfaces are chosen after concrete contracts and live state layouts are
known. Scalarize packets where possible; materialize storage where identity requires it.
Flattened source evaluation order must precede C argument expressions with unspecified
evaluation order. Block-edge packet assignment is parallel, not a sequence of clobbering
assignments.

Do not rely on C tail-call optimization. Tail-connected entries use an explicit dispatch
loop and typed activation storage; direct self loops are the simplest case. Compatible
finite target families can use a tagged union of concrete frames. A fresh destination
can require scratch storage while arguments/preludes still reference the old activation.
Retire the old frame only after preparation; reuse storage without growing a chain of
pending caller continuations.

Ordinary non-tail calls create a return continuation. A native helper is valid where
its ABI and the tail dispatcher preserve the same contract. A higher-order tail edge
with a runtime-selected target still uses bounded tail dispatch, not an ordinary C
function-pointer call followed by return. Independently owned escaping state may
allocate; proper tail transfer promises bounded continuation growth, not zero allocation.

Embedding defines native representations and entry contracts, module instance lifetime,
and the nonreturning trap hook. It does not weaken source ownership or permit reentry
from destructors. Reentrancy policy for other hosts must be declared and respected,
not assumed away by a global mutable-state cache.

## 10. Build sequence: connected contracts, not supported-case shortcuts

1. **Done.** Receiver policy settled in specification §§0/5.2; word/activation/region
   ASDL replaced with `Belt.Word` field bundles and `CallFunction`/`TailCall`; contract
   checks live in `binding.lua` and `verify.lua`.
2. **Done for the covered shapes.** `resolve.lua` assigns binding IDs, exact capture
   dependencies, and preparation ranges; `program.lua` constructs module bindings in
   source order and resolves the terminal-only self identity.
3. **Done for Copy and owned data.** One `Builder:supply` serves persistent
   specialization and transient invocation; interior mutable state is returned and
   written back; prelude state carries an explicit retention flag.
4. **Done for the covered shapes.** Terminal entry, return, bounded self tail retirement and
   argument-determined (`Executable`) stages work. General recursive contracts remain; directly
   named mutual recursion is outside the design, so there is no mutual contract to state.
5. **Done for the covered shapes.** The binding-time evaluator (`let/known.lua`) answers
   producers, demand folds and prunes, and `let/emit.lua` prints C with a direct `TailCall`
   becoming a `goto`. Nothing is outstanding here: an effect-carrying loop is emitted as a loop,
   and directly named mutual recursion is outside the design, both by decision -- see COMPILER.md,
   "Deliberately outside".

Each step may be unfinished while under construction. It must not introduce a competing
meaning of words or a temporary special-case call path. Reuse the existing scalar/control
constructors where their contracts fit; replace the terminal-only context assumptions
instead of wrapping them in an inliner.

Use a small set of end-to-end witnesses: two independent counters; first/prelude/second
ordering; a resource-owning persistent word; a transient borrowed callback; a returned
owning word; recursive continuation tail transfer; and a trap during preparation.
Check their results and lifetime/effect traces, rather than growing a rejection matrix.

## 11. Specification questions that implementation must not silently answer

### Existing non-copyable receivers under specialization

§0 says specialization produces a new result and leaves the original word unchanged.
§5.2 requires independent mutable state; §§9–10 forbid implicit copies of owned words.
The spec does not give a general clone operation for an already stateful prefix.

Consequently we cannot implement `stateful argument` by silently moving state out of
`stateful`, sharing its private mutable cells, cloning an opaque resource, or replaying
already reached effectful preludes. These are observably different policies.

Confirmed and recorded in specification §§0 and 5.2: specialize a Copy receiver by
value; permit transfer from a fresh receiver where no original owner remains
observable; require explicit independent-copy vocabulary for an existing non-copyable
receiver. This includes a word with private mutable but scalar-only state.
Current grammar also does not admit `(move word)` as a grouped expression, so that
must not be invented as an implementation-only receiver spelling.

### Borrowed access to stateful executable values

§10's counter can mutate private prelude state through an immutable owning binding.
§9 says a plain stage cannot mutate its borrowed argument. Confirm that passing that
counter through a plain stage narrows receiver access and prevents a terminal requiring
write access to its owned state, while owning access permits its declared interior
mutation. Captured external loans must be checked by their own provenance, not assumed
to grant ownership of their referents.

### One resolved and one open editorial question

Partial moves are now stated in §9.2 as language behavior, with only their interaction
with run-time-computed paths deferred in §18, so that inconsistency is resolved. §3.1 still
restricts constraint arguments more than §11.1's `specialization_argument` rule; resolve
that in the specification before extending constraint-word arguments, because neither
reading justifies an ad hoc runtime meaning in the compiler.

