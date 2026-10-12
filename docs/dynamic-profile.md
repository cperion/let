# Dynamic values and counted ownership — target, not a wire profile

**Status: approved collector-free direction; not implemented.** Revision-6 profiles
1–4 remain the executable runtime. Profile 5 still rejects. This page replaces the
former profile-5 tracing specification; it does not assign new bytecodes, restore
an archived engine or reinterpret old modules.

The ownership authority is [owners-references-ids.md](owners-references-ids.md), and
surface behavior is in [syntax.md](syntax.md). The earlier tagged-cell, tracing,
open-word and descriptor details are preserved in
[the ownership archive](../research/archive/ownership-before-counted-design/docs/dynamic-profile.md).

## 1. Retained computation invariants

- One scalar computation owns checks, branches, representation decisions and
  errors; execution bindings do not implement separate dynamic algorithms.
- Revision-6 binary operations consume selected X0 then opposite Y0; destination
  choice is not an A-only repacking convention. Unary/cast/test forms follow their
  declared selected-stack contracts.
- Symbolic cache state remains register allocation. No extra value IR, second
  allocator or runtime dependency on `abc-opt` is introduced.
- Dynamic type uncertainty is not an effect. Allocation, retaining/releasing and
  foreign operations have their own obligations. No opaque fallback is justified
  by unknown types or version saturation.
- Explicit ABC frame transport/control, observable ordering, original error PCs,
  stack limits and public callable identity remain binding.
- No bytecode quickening is reintroduced. Layout observations are VM-private facts,
  not rewritten public instructions or owning references to key data.

## 2. Dynamic values are transferable values

`any` stores a type and a transferable value. Non-fitting values use immutable
counted boxes. Mutable references, mutable-backed readonly views, mutable-capturing
closures and raw foreign pointers are not automatically admissible. A box must
not retain mutable storage by pretending a borrowed address is a value copy.

Integer/float rules remain the shared typed rules, including checked conversions,
canonical dynamic NaNs and preserving exact integer bits where required. Scalar
representation selection must not force allocation for f64 or box known unboxed
values prematurely. These are computation/representation obligations, not approval
of a particular tagged-bit layout from the retired profile.

## 3. Heap storage without tracing

Mutable owner edges satisfy static strict-order constraints on actual retained
owners. Interior references retain their aggregate root. Escaping roots are
allocated separately from their activations from the start. Closure environments
retain their own owner/provenance bounds across calls and erasure.

Immutable boxes, transferable environments, COW buffers and frozen values form
DAGs by construction. Incoming values are retained before uniqueness testing;
shared published storage cannot acquire backedges. Non-transferable containers
remain in the mutable owner-constraint domain.

Generated release operations drop strong holdings through an intrusive worklist.
There are no collection safepoints, trace descriptors, scanned VM/native stacks,
extern GC spaces or descriptor-rooted module ranges in this target. Runtime
liveness still matters: premature release, omitted retains or incorrect effect
ordering remain bugs. Removing a tracing requirement does not remove lifetime
requirements or authorize changing the active runtime's effect boundaries.

Shareable buffers have atomic counts from creation; task-confined mutable owners
have ordinary counts. No dynamic counter-mode upgrade is assumed. Failure cleanup,
overflow handling, memory orders and the concrete release ABI require a separate
validated runtime design.

## 4. Tables, strings and layout facts

Tables replace reference-semantic open maps with value semantics and COW maps.
Values are transferable `any`; methods borrow the actual table as receiver rather
than capture it. Table entries cannot be independently referenced.

Integer keys form an exact dense prefix starting at zero. Iteration visits that
prefix first, then other keys in insertion order. Named-key layout tokens are
non-owning and independent of array length and integer/float/general element kind.
Copies share tokens; named structural changes renew them. An array push does not
invalidate named-field facts. A known token is not a known object/value.

Strings are COW byte values with buffer plus packed offset/length, not `slice(u8)`.
Literals use immortal buffers. List/string snapshots retain immutable buffers;
views of mutable arrays do not acquire immutability just by being read-only.

## 5. Encoding and compatibility gates

Before implementing dynamic execution, specify and approve:

1. Dynamic cell tags and boxes, exact scalar conversions and ownership witnesses.
2. Owner headers, generated release ABI, allocation/abort cleanup and count overflow.
3. Retained reference/slice/callable ABI and imported ownership/retention/world summaries.
4. Table/array storage, token lifetime and independent shape/kind guards.
5. Host handles, FFI borrow/retention contracts and atomic task publication.
6. New profile/revision policy if existing encodings cannot express the contracts.

Do not translate old profile-5 tracing metadata into release metadata silently.
“No new instruction required” remains a hypothesis to test against allocation,
atomics, release and all execution bindings, not an encoding decision.

## 6. Required evidence

Use the canonical ownership test matrix, including rejected owner cycles through
interior references and hidden captures, COW self-insertion, long iterative release,
failed construction, copied stores/ids, immutable snapshot sharing and world effects.
Test outcomes and architectural contracts under all four execution modes, with
independent operand-order, lifetime, capacity and error-order oracles. Report code
size, count traffic, allocation/COW behavior, peak retained memory and timings.
Passing the current typed suite does not establish any of these new capabilities.
