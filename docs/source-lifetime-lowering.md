# Explicit Rc: source lifetime lowering and removal contract

**Status: explicit ownership and retain-on-copy approved; implementation not cut over.**
The user replaced implicit reference ownership with explicit `Rc(T)`, confirmed that
`Ref(T)` remains borrowed, and selected **copy retains**. The purpose is developer-
visible, typechecked ownership and a smaller, predictable compiler—not preservation
of the previous inference engine under new names. WORKLIST O01–O08/E01/E02 remains
the only delivery ledger. No implementation item is completed by this specification.

This replaces the previous version of this document: automatic counted-root
selection, capability-demand propagation, preservation holdings inferred for `Ref`,
and ownership-dependent private reference ABIs are no longer target mechanisms.
The interrupted implementation is preserved at jj/Git checkpoint `4a9da5db`;
older specifications and evidence remain in history and their existing archives.
Do not restore the removed blanket materializer or finish the superseded solver.

## 1. Approved semantic contract

| Type / operation | Meaning |
| --- | --- |
| `T` | Ordinary value/storage under its existing value/place rules |
| `Ref(T)` | Non-owning access to an existing place, subject to a lifetime proof |
| `Rc(T)` | Owning handle to an explicitly created counted root containing `T` |
| Rc construction | Explicit allocation, never promotion of a referenced local |
| Rc value copy | Retain the same allocation; do not copy `T` |
| Rc destruction | Release that holding; reclaim at zero through the existing queue |
| Rc replacement | Establish the incoming holding before releasing the old one |

The type constructor spelling `Rc(T)` is selected. `Rc(value)` is the proposed
value-constructor spelling; its elaboration and the borrow operation are listed in
§7 rather than silently implemented as new coercions.

A value-copy boundary includes owning local-value bindings, value arguments,
returns and stores, and copied field/element reads. Record/array/active-sum copies
copy their `Rc` components. Capture-by-value copies an `Rc`; a place capture is a
borrow and cannot silently become an owning capture. Merely aliasing an existing
mutable aggregate place is still not a value copy. Do not conflate that existing
place-alias rule with copying an `Rc` handle.

Typed IR must preserve these semantic boundaries. In particular, source elaboration
must not erase an owning copy as if it were an ordinary scalar SSA alias. Conversely,
register allocation, spilling, stack transport and intermediate address bits are
not semantic copies and do not acquire counts.

A proven move may replace copy-plus-release when the original holding is consumed
and no remaining alias/borrow requires that binding. Optimization must preserve
failure, evaluation-order and lifetime guarantees. It is not an alternative source
ownership policy; an unproved move uses the correct copy operation, not guessed
root-family equality. Baseline correctness must not depend on globally minimizing
count traffic.

## 2. Borrowing is checking, not ownership repair

`Ref` transport does not retain. Borrow checking verifies an existing storage or
holding lifetime; it never creates an `Rc` to make an invalid program pass.

- Returning a reference into a dying local/by-value parameter rejects.
- A caller-derived reference may return under an established input-lifetime relation.
- A module reference borrows module storage; it acquires no count.
- Borrowing from an `Rc` does not create a second holding. Moving, replacing or
  releasing its protecting binding while the borrow is used must be rejected unless
  independent existing protection is actually established.
- Reexecution/reuse cannot turn a frame borrow into an allocation request. A borrow
  surviving invalidation rejects; explicit `Rc` storage has its own lifetime.
- A borrow of a root's interior is still a borrow. No implicit owning interior
  `Ref` or `Rc(subobject)` conversion is introduced.
- Mutation effects, dynamic index overlap, input/result lifetime relations and
  unknown-call effects still matter. Empty provenance is not proof of safety.

For a field `child: Rc(Point)`, copying `box.child` into `saved` creates an ordinary
Rc holding. Replacing `box.child` cannot invalidate `saved`. The compiler does not
wait for the replacement to discover a preservation acquisition. A *borrow* of the
old child, in contrast, cannot survive loss of its protection by hidden counting.

`Slice(T)` is a borrowed view under this cutover, not a conditionally owning carrier.
An owning container snapshot needs an explicitly owning type/API, not an extra
capability cell inferred behind the same slice type. Existing COW buffer algorithms
remain selected, but their view API/type binding must satisfy this distinction.

## 3. Type-directed layout and calls

Root-only `Rc(T)` is the initial target. The owning handle identifies the allocation;
projections borrow its payload. There is no universal data-plus-owner form for
`Ref`, and no demand-selected capability cell attached to it.

The physical Rc handle layout and its call handoff must be specified once before
implementation (§7). A single owner-header address is a candidate because the
payload location is fixed by concrete `T`; this is not yet a public ABI assignment.
Two independently replaceable Rc fields remain two holdings even if their handles
currently identify the same allocation. Cleanup visits actual Rc fields, not copies
of borrowed pointer bits in registers or all reference-bearing fields.

A signature returning `Rc(T)` declares ownership. One returning `Ref(T)` declares
borrowing. There is no mixed borrowed/fresh ownership mode behind a single `Ref`
result. Source alternatives must agree on their declared type or use an explicit
sum of different types. No silent `Ref`→`Rc` conversion is permitted.

No inference determines how many hidden result resources a reference needs, which
input holding a reference consumes, or which owner capability must cross that call.
Private instances are not cloned solely for such inferred ownership modes. Ordinary
type/layout/callable specialization still exists.

This does **not** imply that all physical handoff or temporary storage disappears.
The selected calling convention must keep every actual owning argument/result
cleanup-visible across call-entry, stack-capacity and other failures. Public/foreign
Rc transport additionally needs handle, code-image lifetime and teardown contracts;
a source type declaration alone does not open that ABI.

## 4. Runtime and failure invariants retained

Retain `src/owner.h/.c`, the six bindings in `src/lifetime.h/.c`, concrete C-entry
field drops, explicit ABC continuations and the shared native/threaded allocator.
No new runtime registry, ownership interpreter, tracing collector, cycle detector,
second allocator or recursive host execution is introduced.

- Rc construction allocates its selected root directly. Published addresses never
  move; no activation-wide counting or later frame-to-heap promotion occurs.
- Allocation/retain failure must leave established holdings cleanup-visible.
- Replacement evaluates/captures inputs according to source order, establishes new
  ownership before releasing old ownership, and cannot publish half a value.
- Generated drops traverse only initialized actual owning fields and active tags.
  Partial-construction handling must preserve that property on every failure edge.
- Transfer clears the source holding exactly once. Any two-store implementation
  must establish a genuinely non-failing commit window in all supported bindings;
  ordinary-looking IR is not by itself that qualification.
- Release enqueues and drains iteratively without allocation or user callbacks.
- Empty owning scopes emit no cleanup record, enter/leave pair or empty drop body.
- Packed tags, `ADDR2BITS`/`BITS2ADDR`, both operand destinations, stack limits,
  original traps and foreign synchronization remain unchanged.

Explicit Rc does not make cycles safe. Preserve the approved acyclicity obligation
for actual strong edges and the separate immutable-construction proof. Ordinary
borrowed references are not strong edges. Reuse the iterative SCC algorithm where
appropriate; do not preserve counted-placement inference just to reuse that code.
The general separate-compilation/polymorphic rank interface remains a gate.

## 5. Concrete removal and survivor set

| Existing responsibility | Cutover |
| --- | --- |
| `ownership.lua`: `returned`, `independent`, counted worklist in `solve` | Remove automatic promotion and promotion-induced retention propagation |
| `ownership.lua`: `capabilities` | Remove owner-capability recovery and ABI demand for ordinary references |
| `ownership.lua`: `snapshotDemands` preservation policy | Remove hidden acquisitions that repair invalid borrows; copied Rc values already own |
| `ownership.lua`: `reuseRequirements` | Remove counted-placement repair; retain required reuse-invalidates-borrow checks |
| `ownership.lua`: `requireBorrowed` | Retire the temporary implicit-materializer admission gate |
| `ownership.lua`: interrupted `rootBindings` | Remove inferred result resources, alias/resource partitioning and ownership-mode binding |
| `bindLoans`, `lifetimeTemplate`, `locators`, `sameLocator` and context/version facts | Audit for borrow/cycle-check clients; retain necessary checking algorithms, not the entire ownership solver as an optimizer |
| `access.lua`: `Ownership.events/hold/returned/merge` channel and `facts.ownership_events` | Remove implicit-owner producers and their propagation; introduce only facts required for explicit strong edges and borrows |
| `ir.asdl`: implicit `Ownership.Requirement` / counted summary contracts | Replace with explicit Rc type/semantic operations and actual checking contracts; regenerate schema |
| `program.lua` | Keep immutable checked-program ownership; replace implicit owner-selection analysis with Rc/borrow/cycle validation |
| `layout.lua`, `placement.lua` | Use declared owning types and explicit operations; keep concrete drop/layout algorithms |
| `abc.lua`, `compiler.lua` | Keep entry-rooted code selection and the checked-to-physical boundary; disconnect implicit resource binding |

Keep original-site identities, readonly checks, alias/mutation footprints, callable
resolution, provenance needed for borrow validity, module identity, and sound SCC
code. `Ty.Owned` is an existing callable specialization form, **not** the new Rc
type: it must not be deleted merely because of its name. Materialized environments
must continue to read actual invocation-site capture storage, not resurrect the
removed code-global capture-value union.

Do not delete historical `.slet` experiments or rewrite raw evidence. No old-to-new-
to-old adapter, dormant implicit-ownership path or profile flag choosing between
ownership languages remains in the completed cutover.

## 6. Integration boundary and evidence

Actual implementation files: `frontend/ir.asdl`, generated
`frontend/let/schema/ir.lua`, `frontend/let/{schema,semantic,ir,access,ownership,
program,check,layout,placement,abc,compiler}.lua` as required by their traced clients.
Existing tests: `frontend/tests/{schemas,ownership,access_proofs,program,source_owners,
packed_tagged}.lua`, `tools/validate_source_owners.c` and the existing C core/C-entry
validators. Extend existing suites rather than retaining implicit semantics to keep
them green. The implementation map owns the file-level breakdown.

Required source evidence:

- Explicit Rc factories return owning handles; local/by-value `Ref` escapes reject.
- Local/field/element/argument/result/capture Rc copies retain the same root, not
  duplicate its payload; copies remain valid after the original holding is released.
- Plain references, scalar-only code and non-retaining borrowed calls emit no RC
  traffic or empty cleanup scopes.
- Mutation invalidating a live borrow rejects; a copied Rc snapshot survives.
- Replacement, self-assignment, aliases, partial construction, overflow, allocation
  failure, call-entry failure and stack failure preserve cleanup and error ordering.
- Strong cycles reject; borrowed cycles cannot masquerade as strong cycles or escape
  their protecting lifetimes. Long acyclic graphs reclaim iteratively.
- Fixed arrays, tagged payloads and multiple results use their actual typed holdings,
  with active-case-only cleanup and no ownership-mode reference ABI.
- Raw/optimized execution in all four modes and both lifecycle banks; full suite and
  relevant sanitizers at the integrated milestone. Public/foreign/erased/task gates
  stay closed until their separate contracts and tests exist.

Measure frontend time/query counts and memory against the preserved checkpoint,
including scalar, callback and recursive programs. Measure emitted code, count
traffic, cleanup storage and peak owner bytes. Fewer inference passes is a structural
simplification, not a measured speedup or a claim that borrow/cycle checking is free.

## 7. Remaining concrete binding decisions

The user has settled explicit ownership, strictly borrowed references, root-only
initial Rc and retain-on-copy. Do not reopen move-by-default versus copy.

The following are still design gates, not license to invent new behavior in code:

1. **Construction and borrowing surface.** Proposed: `Rc(value)` copies `value` into
   a new root; an explicit borrow operation returns `Ref(T)` tied to an existing Rc
   holding. Settle its spelling and receiver rules. Do not silently redefine
   `Ref(place)` to mean a different place when that place stores an Rc handle.
2. **Borrow-carrying Rc payloads.** Decide whether the initial `Rc(T)` payload rule
   excludes `Ref`/borrowed slices/borrow-capturing callables, or admits a precisely
   checked lifetime relation. A heap root does not make copied frame borrows safe.
   Do not recreate inferred owning fields to admit these cases.
3. **Concrete Rc transport.** Choose the private handle representation and a
   failure-safe argument/result handoff using the existing ABC/runtime mechanisms.
   Public/foreign encoding is separately gated; no numeric tag/opcode is assigned.
4. **Escaping callable and snapshot APIs.** Specify explicitly owning environment/
   view types or construction. Merely putting a borrowed callable or slice inside
   `Rc` must not promote its referents or captures.

The next implementation design must resolve the gates for its concrete slice,
name the retired producers/consumers and test the integrated replacement. Until
then the code at the interrupted checkpoint remains partial and superseded, not
an implementation of this specification.

## 8. Proposed first integrated binding — awaiting approval

The following is a concrete proposal, **not additional approved semantics**:

- **Construction:** `Rc(value)` copies a value into a fresh counted root and returns
  `Rc(T)`. It does not move existing addressed storage or adopt a borrowed pointer.
- **Access:** `r.borrow()` is a typed borrow operation returning `Ref(T)`, tied to
  the existing Rc binding without copying/retaining it. Payload access uses that
  reference; no automatic payload forwarding or reinterpretation of `Ref(r)` is
  needed. The operation must work on a named owning value without pretending it is
  an ordinary by-value Rc argument. Borrowing a temporary that dies before the
  reference's use rejects.
- **Payload restriction:** initially admit scalar/raw-pointer values, finite
  records/arrays/sums and nested Rc handles, but not stored Ref/Slice/borrowed
  callable/erased payloads. Rc root types must have finite layout; Rc indirection
  permits recursive type layout but does not prove strong-edge acyclicity. Raw
  pointers retain their existing unchecked status. This explicit admission rule
  avoids adding lifetime-polymorphic Rc types to the first slice.
- **Borrowed results:** ordinary borrowed-input/module relations remain valid;
  an owned parameter's existence during a call alone cannot justify a borrowed
  result after that parameter is released. Use a borrowed input to express that
  interface, rather than hidden caller-owner recovery or an extra result holding.
- **Handle:** one address cell naming the owner header. Concrete `T` supplies its
  payload offset; Rc values have no public null variant. Internal uninitialized/
  moved holding slots use null for cleanup, not as a source Rc value.
- **Private call handoff:** a by-value input or result containing Rc uses a concrete
  caller-allocated owning value slot. Argument copying initializes that slot in
  source evaluation order before entry, while it is already cleanup-visible.
  The callee consumes the argument holding and clears it on release/transfer;
  entry failure leaves it available for caller unwind. Results are written into
  empty cleanup-visible caller slots. These are the owning values themselves,
  not separate capabilities/resources inferred for reference data. Pure scalar,
  borrowed Ref and other nonowning call transport retain their existing ABI.
- **Aggregate copies:** copy actual Rc fields, including each independently owned
  field even when handles alias. Zero owning scratch fields before partial copy;
  establish active tags before publishing acquired fields to cleanup. Moves are
  local proven transfers, never a prerequisite for correct baseline copying.
- **Scope:** implement explicit roots/copies/borrows, records/fixed arrays/tags,
  private direct calls and failure cleanup together. Owning public/foreign/erased
  and environment/snapshot interfaces remain explicitly rejected until bound.
  Borrowed callable behavior and source safety must survive removal of the old
  solver. No runtime or bytecode redesign is proposed.

This binding uses the existing six runtime operations and concrete C-entry drops.
Implementation must validate call-entry/return handoff and any transfer window,
not merely infer safety from unchanged scalar instruction kinds. The removal set
in §5 and the source-to-physical tests in §6 are part of this same cutover.
