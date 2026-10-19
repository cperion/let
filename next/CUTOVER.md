# VM 3 cutover: approved approach and execution plan

**Status: semantic/execution approach approved; not implemented.** After discussion
of B liveness, in-place calls, one-cell continuations, explicit returns/tails, stable
blocks, virtual execution, logical capacity and delivery scope, the user confirmed:
“i validate that approach”. V07 records that approval. It covers the three coherent
implementation batches without per-file approval or repeated full validation.
Section 9's exact opcode numbers/field widths remain a working draft to finalize
with V08's producers/consumers, not a frozen public ABI. Material semantic changes
still require discussion; mechanical encoding finalization is not a new micro-gate.

[DESIGN.md](DESIGN.md) owns the settled topology. [WORKLIST V](../WORKLIST.md#v--vm-3-isolated-experiments)
is the single live ledger. V06 delivers this plan; V07 records approval; V08–V10 are
the three implementation batches below. Their status/ownership belongs in WORKLIST,
not a second checklist here. No subagents or internal edit-plan sidecars are implied.

## 1. Scope and fixed decisions

Implement VM 3 **inside `next/`**, replacing the copied organizing paths directly:

- One logical A sequence for arguments, continuation, locals/blocks and operands.
- One scalar B; no B operand stack, C stack or C bank.
- Concrete interpreter: ring `(R,T)`, single deepest-cell spill,
  **no eager refill, including on return**. Use N=8 as the initial T0 binding,
  not a public ABI or proven optimum. No refill-policy flag in the VM.
- Continuation storage on A above arguments; no dedicated link register.
- The symbolic cache remains the allocator. Known eligible calls reinterpret
  existing cells and use virtual continuations; the emitted tape/stencils already
  name physical registers. No second allocation pass or native value IR.
- Shared scalar/control computations with narrow concrete, threaded and native
  execution bindings. Runtime does not invoke the optimizer or portable-C writer.
- Preserve existing typed arithmetic, floating rules, effects, ownership algorithms,
  immutable module/site observation rules and explicit nonrecursive host control.
- Preserve current admission of typed source, private explicit Rc, borrowed callable
  views, foreign calls, lifecycle C entries and supported build-time outputs.

Not part of this cutover: language redesign, `.slet` renaming, dynamic/profile-5
execution, tasks, containers, public owning/FFI APIs, caller-owned region redesign,
new specialization budgets, new native/threaded register budgets, quickening, or incorporating the
upstream `.ralphi/` optimizer design. No experiment engine becomes a production
fallback. Existing historical evidence and raw experiment folders remain immutable.

### What inspection actually found

| Existing owner in `next/` | Actual dependency to replace |
| --- | --- |
| `src/execution_context.h` | Three backing arrays, three depths/cache occupancies, `h[4]`, `cr[3]`, and a separate `abc_frame` return-PC/destination array |
| `gen/cache.lua`, `gen/banked.lua` | Anchored bank shifts, C-relative accesses, dynamic A-to-C gathering and reverse result transport |
| `src/symbolic.c:abc_symbolic_machine_call` | Even virtual calls perform `abc_symbolic_machine_cpush` for arguments and change `c_origin/c_bias` |
| `src/symbolic.h` | Three symbolic vectors, three capacity facts and continuation coordinates for A/B/C |
| `src/residualize.c` | Existing cache allocator, alias captures, writable copies, register-entry recursive calls, generic conformance, and three-pointer call transport; preserve the sound algorithms, not the C transport |
| `gen/execution_forms.lua` | Register-addressed operations already exist; home loads/stores, guards, rebases, continuations and C-entry bindings still name three stacks |
| `src/verify.c` | Persistent typed shapes `{a,b,c}`, C block nodes and symmetric selected-first operands |
| `frontend/let/abc.lua` | `.expr(expr,stack)` can put slices/callables/aggregate vectors on B; `other(stack)` drives binary and memory routing; locals are preallocated then moved to C |
| `frontend/let/placement.lua` | Generated lifecycle assembly contains old CGET/PUSH.B/RET.A forms independently of ordinary lowering |
| `src/optimize.c` | DAG scheduling projects through C temporaries and old A/B routing; changing runtime alone leaves an invalid producer |
| `src/residual_builder.c` and analysis | Function inputs, homes, loop keys and parameter bindings still depend on C origin/bias |

The lab's historical observation that B was shallow is not a proof that the current
frontend already respects scalar B. Literal substitution or an old-ISA adapter is
not an acceptable migration.

## 2. Approved approach (V07)

The user validated the following semantic/execution approach after discussion.
These are the implementation invariants, not worker discretion. Exact byte allocation
and operand widths in section 9 remain provisional as described above.

| Contract | Concrete choice | Rationale |
| --- | --- | --- |
| P1 — encoding | New `ABC3`, revision 1, profiles 1–4; one-byte core plus extension prefix; section 9 allocation/layouts remain draft; reject `ABC2` outright in next | Incompatible bytecode and changed operand meanings cannot silently reuse revision 6/7 |
| P2 — scalar B | Fixed A-left/B-right binary operands; suffix chooses result; B empty at direct/foreign call entry and full of only the target at indirect entry; A-only argument/result vectors | Current frontend and verifier permit deeper B and both argument banks |
| P3 — frames/control | One opaque continuation cell; explicit `RET k,d,r`, `TCALL target,k,d,n`; all host entries have a protected sentinel; exact transports in section 4 | A return PC alone does not settle routing, varying locals, tails or host delivery |
| P4 — addressable storage | Blocks have stable canonical A homes; no eager caching of block bytes; explicit ALLOC/FREE and top-relative byte offsets | Folding C into A must not invalidate frame addresses or cleanup records |
| P5 — capacity | `stack_cells` bounds one logical A including continuation/block cells; B is separate; virtual cells count toward logical limits | Three independent capacity budgets cannot be silently treated as one |
| P6 — delivery boundary | Preserve all current typed runtime profiles and owning private bindings; initial T0 ring N=8; three batches with the stated temporary producer breakage, no legacy fallback | A scalar prototype or manifest change is not a completed VM replacement |

The new GT/GE and floating complementary families in section 9 are proposed to
preserve source evaluation order without operand-reversal shuffles. They are not
an invitation to invent additional fused families while migrating callers.

## 3. Logical values, B and verification

### 3.1 A is one sequence, not two hidden regions synchronized by a shim

A callee is verified from:

```text
arg0 ... arg(n-1) | CONT
```

At runtime there can be protected caller cells below arg0. A function's verified
shape never includes those cells. GET/SET may address its own arguments and scalar
cells but not CONT, byte blocks or caller storage. Ordinary consuming scalar
operations cannot cross CONT or consume block bytes.

**There is no separately tagged local/operand frontier above CONT.** Leaving a
computed scalar in place does not execute a binding instruction. Such a cell can
become a producer-designated local, then be dropped when its scope ends. Source
scope/ownership rules are enforced by source checking/lowering; the VM protects
control/block boundaries and typed shapes, not invisible source binding labels.
This explicitly replaces the design sketch's suggestion that the VM could reject
all local pops while also having no instruction/metadata marking a local.

Keep the verifier's interned persistent shape algorithm. Replace `Shape {a,b,c}`
with one A shape plus `b_valid/b_kind`. Add a protected control-cell node kind;
retain indivisible byte-block spans/requested sizes. At joins require exactly the
same A layout and B validity/kind. Replace `cslot/cset` with typed A lookup/rewrite;
remove the fixed `prefix[256]` rewrite path before admitting u16 depths. Bound its
scratch/path storage by the actual walked shape and existing verifier complexity
limit, with allocation failures propagated. Check instruction/site/relocation
metadata even for unreachable instructions as today. No runtime dynamic type tags
are added.

### 3.2 Scalar operations and transport

For every binary integer/float operation, capture **A0 as left, B as right**:

- `.A`: replace A0 with the result; B becomes empty.
- `.B`: pop A0; replace B with the result.

Do not reverse subtraction/division/shifts/comparisons for `.B`. Unary/check/cast
and immediate `.A/.B` forms read/replace their respective existing operand. Checked
operations preserve current abort reasons and original PC attribution.

`MOVE_AB` consumes A0 into empty B; `COPY_AB` copies A0 into empty B; `GET_B d`
copies A[d] into empty B; `MOVE_BA` pushes B onto A and empties B. A read-modify-write
of B is legal; an unrelated overwrite of a live B rejects. There is no B DUP/DROP,
B literal push, B range push or implicit B spill stack. A B literal is produced by
PUSH on A followed by MOVE_AB; symbolic execution may erase that transport. Its T0
cost must remain visible rather than being hidden in an undocumented new opcode.

`GET d` uses the pre-instruction A top. `GETR d,n` captures the original ordered
values A[d], A[d+1], ... and pushes them shallowest first; later pushes must not
change what subsequent depths mean. `SET d` captures/pops A0, then replaces depth d
in the remaining A. GET0/1/2 and SET0 are exact short encodings, not alternate rules.

`NIP` retains A0 and removes the scalar just below it. `SLIDE drop,keep` preserves
the top keep ordered scalar cells while removing drop scalar cells directly below
them. It cannot cross a control cell, split/free a block, or reach a caller prefix.
Counts are checked even when keep is zero. Source-only binding release can use DROP,
NIP or SLIDE; there is no new CPUSH operation with an empty implementation.

Depth-cell forms read A0 and the original A[d], compute A0 op A[d], replace A0 and
leave all other cells/B unchanged. d=0 is legal and aliases the destination; the
old operand must be captured before replacement.

### 3.3 Memory operand orientation

- Frame/image loads and address forms `.A/.B` produce a value; B forms require B
  empty. Frame/image stores consume A0 and preserve B.
- Pointer loads `.A/.B` replace the address in that location.
- Pointer stores take **address A0, value B**, consuming both.
- Indexed loads/IDX take **base A0, index B**; `.A/.B` selects the result, not the
  base/index order. Both old operands are consumed.
- MEMCPY takes destination A0 and source B, consuming both; overlap remains safe.

Keep exact widths, little-endian unaligned access, producer load-kind annotations,
raw bitcasts and unsafe-pointer obligations. Do not turn a native pointer into a
handle or weaken frame/block verification as a shortcut.

## 4. Frames, continuations, calls and capacity

### 4.1 One control cell, explicit static coordinates

For a function with n arguments, a return site has:

```text
caller prefix | n arguments | CONT | locals / complete blocks | r results
               <-------- k non-control frame cells --------->
```

`RET k,d,r` reads CONT at **pre-instruction depth d**, captures the ordered top r
results, removes exactly k+1 frame/control cells beneath them, and delivers the
results to the saved destination. The verifier requires its entire private A
shape to have k+1+r cells, the control node at d, and exactly the declared result
kinds on top. Therefore d=k+r-n, but it is encoded explicitly to avoid runtime
function lookup. B is empty at RET. r remains 0–255; do not impose the sketch's
unjustified two-result limit on existing callers.

All bytecode function entries, including host entry, use this shape. Host entry
places its arguments in source order and a protected sentinel above them. RET of
the host sentinel publishes ordered results only on success. HALT has the same
k,d,r shape operands, is host-entry-only, and retains its existing non-callable
function restriction. C-entry roles remain separately checked.

### 4.2 Execution-binding tokens, not a second frame stack

CONT is an opaque control cell, inaccessible to scalar GET/SET/pop. Its private
binding is:

- Interpreter: `((return_pc + 1) << 1) | destination`, with A=0/B=1. Zero is the
  host sentinel. PC is an original module instruction offset, not a cache-handler
  address; module limits leave ample space. No separate `abc_frame[]` duplicates
  this information.
- Threaded/native: a nonzero backend resume-entry address, or zero host sentinel.
  The bound resume entry knows its result destination and caller-origin restoration
  delta. It is not a public callable identity, serialized pointer or dedicated link
  register. It need not use pointer tagging.
- Symbolic virtual call: a control-slot descriptor plus the existing virtual
  continuation record; no runtime token store merely to enter a known callee.
  Materialize a real continuation only where a real control boundary requires it.

This does not adopt the benchmark's tagged record pointer as a public ABI. A raw
callable still uses the module's verified code-entry identity; the resolver maps
it to an execution entry only after exact identity/signature validation.

### 4.3 Ordinary and indirect calls

CALL.A/B takes n ordered arguments from A. B must be empty. Their cells stay in
place; append CONT and transfer. `.A` appends the callee's ordered result vector to
the caller prefix; `.B` delivers exactly one result to B and leaves A at the caller
prefix. The destination is independent of callee implementation placement.

CALLI.A/B requires B to hold only the code target. Validate same-module entry,
entry role and complete signature using the existing shared observation protocol;
consume that target, then use the same A argument/frame contract as direct CALL.
The environment remains argument zero, counted in n. Validation failure retains
current error/status/origin guarantees; no old-to-new argument transport remains.

FCALL.A/B also gathers its declared arguments from A with B empty on entry. The
foreign ABI limits remain unchanged. `.A` delivers its zero/one result to A;
`.B` requires one result and delivers it to B. Marshaling into a host ABI buffer is
a real boundary, not a C-stack compatibility layer. Preserve synchronization,
reentry rejection, persistent images and private source-binding behavior.

### 4.4 Tail replacement and overlap

`TCALL target,k,d,n` / `TCALLI k,d,n` require exactly the current frame/control
plus n new argument cells, no other private operands, and a matching result ABI.
For TCALLI, B holds only the target and is consumed; otherwise B is empty.

Capture the continuation and overlapping argument sources **before** releasing
old storage. New arguments replace the old activation at its original base; CONT
is placed immediately after the new argument vector. Preserve its original resume
and result destination even when arity changes. Caller prefix and surviving caller
block addresses remain unchanged. A real tail may move arguments; an ordinary
call must not gather them into a different array.

Return similarly captures CONT before results can overwrite its cell. Capture
results whose source homes would be overwritten; use the existing cache's alias/
parallel-copy rules, not an unconditionally allocated scratch vector. Ordered
memory moves may use memmove where the preserved slice is already contiguous.
Cached survivors are relocated only for required semantic compaction, not to
re-anchor the ring. Returning never triggers refill.

### 4.5 Resource behavior

`abc_limits.stack_cells` becomes the capacity of **one logical A**, including
arguments, control cells, locals, padded blocks and operands. B is not charged as
an A cell. Zero still selects 65,536; current maximum-size/error-code conventions
remain. Remove per-B/per-C limits and separate frame-array capacity.

The verifier produces one maximum logical activation extent. Host/call guards use
that extent and the current caller prefix, checking the active execution context,
not a captured first-VM capacity. ALLOC checks before writing. Failed execution
must not publish host results; image effects are not rolled back.

Virtual calls must count their logical control/frame cells even if no physical
store is emitted. Preserve required capacity checks at the originating call/effect
boundary unless the existing headroom proof establishes them. Do not claim an
infinite logical stack merely because values remain virtual. This unified budget
is an explicit VM 3 contract change, not numerically identical to V2's three limits.

## 5. Addressable blocks, effects and lifetime

A backing allocation provides canonical slots for logical A positions; a cached
scalar may have no current bits in its canonical slot. A byte block is different:
it must be real, contiguous, stable storage while live.

- `ALLOC bytes` appends a zero-initialized block of ceil(bytes/8) cells. Nonzero
  allocation requires B empty. In T0 publish cached A cells in logical order first,
  append/zero the block in backing memory, and leave T=0 without refill. R need
  not change merely because T became zero. Zero allocation is a no-op.
- Block bytes never enter the scalar ring: ordinary pops cannot consume them and
  there is no eager refill to pull them in accidentally.
- Frame offsets count bytes backward from the **logical A end**, not `asp` alone.
  In T0 that end is `asp + T` cells. Frame accesses must fit one live block's
  requested bytes, not padding, scalar/control cells or caller storage.
- `FREE bytes,keep` removes the complete block immediately below keep scalar
  cells. Verify exact requested size and indivisibility, capture keep cells,
  release the block, and compact the preserved scalar suffix. Require B empty for
  nonzero free. `FREE 0,0` is the canonical no-op; reject a nonzero keep with zero
  bytes. Scalar compaction may not relocate another live block.
- Native/threaded symbolic execution assigns stable canonical homes when a block
  is allocated/addressed. Do not eagerly materialize unrelated scalar aliases
  merely because the block is real; preserve existing required effect publication.
- The topology does not permit moving escaped storage. Return/tail can retire an
  activation only under the existing producer lifetime obligations. Borrowed
  references to a retiring activation do not become safe through a cache rename.

Preserve `owner.c`'s allocation-specific iterative release, counted holdings and
concrete `lifetime.c` source bindings. Update their frame/entry bindings, not the
algorithms. Physical renaming is not semantic retain/drop traffic. Preserve the
non-failing move/source-clear window and cleanup-visible partial construction.

Owning activation records remain stable byte blocks. They must be unlinked and
cleaned while their storage is live, before RET/TCALL/FREE reuses it. Failure cleanup
runs before resetting A. No release cache, root registry, implicit GC or whole-state
ownership inference is introduced.

Lifecycle C-entry wrappers still run native code in all four execution modes when
owning modules require it. Migrate their home extent from three stacks to one A;
retain exact entry signatures/roles, drop restrictions, publication failure and
image lifetime. Tooling residual C continues rejecting unsupported lifecycle ABI.

## 6. Symbolic execution and residual allocation

### 6.1 One authoritative symbolic cell map

Replace `s[3]/n[3]` with one A vector and a scalar B descriptor plus validity. Keep
constant/register/home value descriptors and backend-owned register IDs. Desired
A home and captured source home remain distinct where aliases require that.
A control-slot role is explicit; it is not an integer available to user operations.
Retain the existing virtual-continuation mechanism with unified coordinates:
caller frame floor/origin, argument base, caller control position, return PC,
callee identity and result destination. Remove `abase/bbase/cbase/c_origin/c_bias`
as three-stack bookkeeping, not by storing their old values behind a new facade.

B may denote a constant, a captured stable A value/home, or an allocated register.
It has no separate B home array. If a home becomes invalid/overwritten, capture B
beforehand. Do not spill a unique live B value into an invented B stack: protect its
materialized register through the existing allocator's live/protected masks. A
canonical generic native/threaded entry with B live requires B in r0; ordinary
specialized contexts may use any available register. Conform through the existing
allocator, preserving valid A aliases where possible. This is an entry convention,
not a permanently reserved register or new allocator. Explicit context publication
may save the scalar B field at a genuine boundary.

### 6.2 Virtual CALL/RET is the computation, not a peephole over transport

For an eligible known call:

1. Validate shape/signature and perform the required logical capacity proof/check.
2. Record argument-base and caller coordinates; leave argument descriptors in A.
3. Append a virtual control slot, change the private activation view, and push the
   virtual continuation. Do **not** loop through cpushing/copying arguments.
4. Continue the same generated symbolic machine at the callee with the same value
   identities, constant facts and physical placements.
5. At virtual RET capture only endangered result aliases, retire frame/control
   descriptors, restore the caller view and attach results to A or B.
6. Continue at the known return PC. Emit no call/frame-gather/return stencil solely
   for that virtual transition.

A real frame's home origin stays fixed across its virtual calls; only the private
activation floor/view changes. Home indices remain relative to that real origin.
Cell copying in the symbolic data structure must not become physical value copying.
Prefer the one A vector and activation coordinates rather than duplicating all
argument descriptors into a separate callee vector. GET can alias a value; SET or
frame retirement must capture mutable-home aliases before invalidating them.

For binary `.B`, compute **A-left op B-right** using a writable left value as needed,
then attach that result identity to logical B. It need not reuse B's previous
physical register, and must not emit a reversed operation or compensating move.
Threaded records and native stencils consume these already allocated operands.

### 6.3 Real boundaries, recursion and continuations

Keep existing recursive-SCC/unknown-call/ABI-visible eligibility rules and current
version budgets for this cutover. Do not inline recursion without bound or add a
new caller-region budget system. Preserve backedge constant weakening without
forcing every value to a memory home.

Native/threaded real frames use one canonical A origin at arg0. Rebase the origin
pointer to the existing argument base on entry; store the real resume token just
after the arguments. Eliminate all A/B-to-C gather loops and three-pointer rebases.

Preserve the existing recursive register-entry optimization, including protected
single-argument transfer, but bind parameters to A slots instead of reversed C
slots. Generic/indirect entry can require arguments at their actual A homes.
Publishing live caller values or conforming registers at a real boundary is allowed;
a second argument copy into another bank is not. Do not accidentally delete this
working register-entry algorithm while removing its old coordinate representation.

At a real return, capture the token first. Single results retain the existing r0
transfer convention; larger vectors occupy A slots at the callee origin in source
order. A caller-specific resume restores its origin by the known argument-base
delta and binds the result to A or B. A tail retains the original activation origin
while replacing arguments and moving the token to its new position. No caller
restoration depends on the final tail callee's arity. Transfer scratch registers
are temporary allocator obligations, not permanently reserved registers.

The native emitter still receives register-addressed operand packets immediately;
the threaded emitter still writes final handler/operand records. Preserve native
publication/entry indirection, lazy preparation, immutable tapes and observation
identity keyed by original PC. Native keeps its current eight value registers;
threaded keeps seven. T0's eight-plus-B ring ABI is not imposed on either allocator.

### 6.4 Build-time peers

The optimizer's ordered DAG and portable-C semantic residual IR remain their own
build-time sinks. Migrate their inputs/parameter homes, joins, call/return payloads
and projections to A/scalar-B. They do not become runtime intermediates. Preserve
supported C output and explicit refusal of unsupported memory/foreign/lifecycle
residue; do not expand portable-C admission incidentally or restore old bytecode
when a rewrite is unsupported. A preserved unoptimized function must still be V3.

## 7. Producers: replace routing at the source

Replace the symmetric `expr(expr,stack)` assumption in `frontend/let/abc.lua`:

- Scalar emission has an explicit A/B destination, requires B empty on entry and
  preserves the prior A prefix. Aggregate/vector emission appends only to A.
- Binary emission evaluates left into A, then right into B, then emits OP.dest.
  Nested right expressions use A while computing and occupy B only at their final
  result. This preserves left-to-right effects without a second B stack.
- Emit GT/GE or ordered float counterparts directly; do not preserve the old
  reverse-selected-operand trick or negate an ordered float comparison across NaN.
- A scalar reference can use GET_B directly. A compound expression requested in B
  still uses the same recursive lowering, not an opaque helper engine.
- Track exact A depth and B validity/kind as instructions are emitted, with label
  shape checks. These facts resolve frame byte/depth offsets at the producer.
  Replace raw string emissions that bypass this state with direct typed emission
  at those sites; no post-hoc pass translating wrong old assembly.
- Arguments, hidden-result address, environment and aggregate components are
  produced in order on A. CALL.B is used only for a single scalar result. Existing
  owning argument/result slot protocols remain distinct source responsibilities.
- Scalar locals are cells on A. Preserve the existing allocation/placement policy
  where sound: an initialized reserved slot can remain a real A local rather than
  requiring a new general source liveness optimizer. Eliminate CPUSH at definition;
  update GET/SET depths to include operands/blocks/control. Use scalar compaction
  only where a binding's storage actually ends.
- For stores whose source evaluation order produces value before address, capture
  the deeper scalar with GET_B and compact the redundant A cell as needed; do not
  reverse source effects or hide a SWAP subsystem. These explicit producer moves
  can disappear through symbolic aliases when physically unnecessary.
- Update packed bitfields/tags, slice/view pairs, bounds/indexing, aggregate stores,
  callable adapters and generated lifecycle bodies. `placement.lua`'s embedded
  assembly must migrate along with ordinary lowering, not after ownership tests
  start failing.

The optimizer's scheduler must follow the same scalar-B restriction. Its C-temp
projection becomes A locals with tracked depths and SLIDE cleanup. Reuse the
existing DAG/ordering and recursive-call handling; do not run a second full
optimization redesign during this topology migration.

## 8. Execution protocol: three batches, not microsteps

### Entry to implementation

V07 records approval of the semantic/execution approach. The executor may implement
all three batches without further per-file approval, finalizing the draft encoding
in the integrated manifest/producers/consumers. Only a material contract mismatch
reopens discussion. Build breaks during a batch are expected and must not motivate
adapters. A missing qualified toolchain is an external dependency, not a reason to
change the handler ABI or add a fallback.

Before heavy editing, do one targeted toolchain preflight. The installed Clang 18
lacks the copied handler ABI support and the copied foreign generator uses Lua
bitwise syntax that its default LuaJIT cannot parse. Select a compiler that actually
accepts preserve_none + musttail for the generated handler signature; do not infer
support solely from a version number or drop the attributes. If none is available,
report that dependency once instead of repeatedly rebuilding. No silent installation
or temporary compiler wrapper is authorized.

In the approved implementation, fix `gen/foreign.lua` directly for LuaJIT by using
its `bit.band/bit.lshift` API for the small generation-time masks, leaving emitted C
bitwise expressions intact. This is a generator-language correction, not a VM
compatibility shim. Retain the frontend's LuaJIT/FFI requirement.

### V08 — Runtime and execution-backend replacement

**Boundary:** all admitted V3 typed assembly executes in interpreted, threaded,
eager and lazy modes, including frame memory, foreign and lifecycle bindings. Old
source/optimizer producers may still be broken until V09; do not call that overall
completion or insert a V2 decoding path.

Implement together:

| Owner/files (all relative to next/) | Required replacement |
| --- | --- |
| `tools/opcodes.lua`, `tools/gen_opcodes.lua`, `tools/assembler.lua`, `src/module.c`, `src/memory_module.c`, `src/cli.c`, `src/internal.h` | New format, exact manifest, decoding, signatures/section roles, assembly/disassembly and regenerated PC metadata |
| `gen/semantics.lua`, `gen/fold.lua`, `gen/symbolic.lua`, `src/semantics.c` | Fixed A/B input order, explicit destination roles, new transfer/control forms and inherited checks |
| `src/verify.c` | One typed A shape, scalar B, CONT/block protection, static call/return/tail checks, unified maximum extent |
| `src/execution_context.h`, `src/handler_abi.h`, `src/vm_internal.h`, `src/vm.c`, `gen/cache.lua`, `gen/banked.lua`, `gen/cold.lua` | One backing allocation, ring and scalar B; remove frame side array, C bank, argument gathers and per-stack capacity logic |
| `src/symbolic.h/.c`, `src/residualize.h/.c` | One symbolic vector, virtual frame views and renaming; migrate allocator/context equality/aliases/conformance/guards and real entry/resume contracts |
| `gen/execution_forms.lua`, `execution_layout.lua`, `execution_compute.lua`, `threaded.lua`, `stencils.lua`, `src/execution_emit.h`, `threaded.h`, `threaded_emit.c`, `native_emit.h/.c`, `native_image.c` | One-home-domain load/store/guard/rebase/continuation packets, one-pointer entry binding, final tapes/native stencils; remove old B/C forms rather than hiding them |
| `gen/foreign.lua`, `src/lifetime.h/.c`, `src/owner.h/.c`, `include/abc.h` | Correct generator syntax; preserve ABI marshaling, stable cleanup storage and owning algorithms; update actual topology dependencies and stack_cells documentation only |
| `Makefile`, runtime-facing `tools/validate*` | Regenerate discarded build products and migrate relevant runtime/ISA/cache/call/effect fixtures and structural assertions; make `build/abc` depend on its CLI/runtime/Lua modules rather than optimizer/shared-tool outputs, while `all` still builds those tools |

Do not rename files just because their old names say banked; replace the
responsibility. Do not remove unaffected arithmetic, native patching/publication,
owner queue algorithms or verifier interning.

**Validation boundary A:** build the runtime libraries/CLI and generators once this
responsibility is integrated; run a grouped runtime contract target covering all
four modes. Use the migrated assembler directly for fixtures rather than requiring
old source lowering or the unported optimizer to build. The existing tools/abc
assembly path already avoids importing the source compiler; adjust its normal build
wiring as specified above, not a second assembler. Add one `validate-v3-runtime`
Make target grouping migrated ISA/cache, native/threaded emission, returns,
continuations, capacity, foreign and lifecycle-assembly checks. Add
`tools/validate_v3_runtime.lua` and `tools/validate_v3_runtime.c` only for new unified
frame/control/alias contracts and runtime-only lifecycle fixtures where existing
tests are coupled to the not-yet-ported optimizer; do not clone entire old suites.
Keep optimizer/source portions for boundary B instead of disabling their assertions.
Replace `tools/validate_symmetric_interpreter.lua` with
`tools/validate_operand_register.lua`, preserving numerical/trap regressions while
removing the old SUB.B orientation expectation. No per-opcode build/test loop.

If integration fails, diagnose the cluster, batch corrections, then rerun the
relevant group. Do not repeatedly run known-broken source/optimizer suites here.
A hand-written Fibonacci benchmark alone is not boundary A evidence.

### V09 — Source, optimizer and tooling producer cutover

**Boundary:** every currently admitted producer emits V3 directly; raw/optimized
source and supported residual-C outputs use the new contract. No source feature
is silently dropped to make the runtime migration appear complete.

Implement together:

| Owner/files | Required replacement |
| --- | --- |
| `frontend/let/abc.lua`, `placement.lua`, `layout.lua` | Scalar/vector separation, source-ordered routing, A-local/block offsets, adapters, tails, hidden results and lifecycle assembly |
| `frontend/let/abi.lua`, `stage.lua`, `compiler.lua`, `optimize.lua`, `snapshot.lua`, `tools/abc` | Correct next library/image binding, module format, staging and output publication; preserve current source admission/API |
| `src/optimize.c`, `include/abc_tool.h` | A-local projection and scalar-B scheduling, new calls/returns/metadata rewrite, no C-temp or old-ISA fallback |
| `src/residual_analysis.h/.c`, `residual_builder.h/.c`, `residual_ir.h/.c`, `residual_validate.c`, `residual_dump.c`, `residual_c.c`, `schema/residual.asdl` | Unified parameter/home/control contracts; preserve semantic residue and existing output/refusal boundaries |
| `frontend/tests/`, `tools/validate*`, `examples/`, `lab/core.js`, `lab/ui.js`, `lab/template.html`, `lab/build.lua` | Port fixtures/oracles/inspection expectations and the active lab/compiler; regenerate lab HTML rather than hand-edit it |

Most parser/type/borrow analysis should not change. Touch it only for an actual
machine-boundary dependency, not to reopen source ownership or language semantics.
Do not rename historical `.slet` examples/evidence. The lab is a consumer, not the
runtime's semantic authority or performance baseline.

**Validation boundary B:** one grouped producer/tooling check: source raw/optimized
execution across four modes, scalar-B scheduling with effectful nested expressions,
aggregate/callable/ownership fixtures, optimizer output re-verification, staging
sessions/snapshots and existing portable-C supported/refused cases. Tests must check
machine structure as well as returned values. Group this as
`validate-v3-producers`, reusing migrated existing test runners rather than cloning
a second suite. The final `validate` target invokes both groups without retaining
duplicate old top-level recipes or forwarding aliases. Replace
`frontend/tests/symmetric.lua` with
`frontend/tests/vm3_lowering.lua`; migrate `placement.lua` lifecycle fixtures too.
Do not assert that the old source `.expr(expr,stack)` can be retained just because
scalar examples pass. No broad performance run yet.

### V10 — Acceptance, removals and one performance comparison

**Boundary:** no active V2 organizing path remains reachable or built in next;
all approved responsibilities and consumers agree. Review actual diff and binaries,
not just declarations or passing output tests.

- Remove residual old fields/functions/forms/build dependencies, discarded fixture
  aliases and any stale current-implementation documentation under next. Preserve
  the checksum baseline and frozen experiments as history.
- Run one clean `make -C next all validate` (with the qualified toolchain), then a
  focused sanitizer boundary run if that toolchain supports the handler ABI.
  A sanitizer blocker is reported, not hidden by removing attributes or declaring
  complete sanitizer qualification. Batch diagnosed corrections before rerunning.
- Run one fixed performance matrix for T0/threaded/eager/lazy: recursive Fibonacci,
  acyclic call-heavy scalar code, live-local/branch code and memory/block access.
  Separate preparation from steady execution and record emitted body/tape sizes,
  code growth and emitted call/materialization counts. Emitted counts are not
  dynamic traffic or evidence of instruction-cache pressure; visited handlers and
  locality matter. Reuse the established pinned, warmed, balanced-sample method;
  do not run simulator timing as VM evidence.
- For a current-V2 comparison use a reproducible source baseline and the same
  qualified toolchain in a separate build location. Do not use the stale existing
  binaries. If a generator-only toolchain correction is necessary there, record
  that exact patch; do not call the baseline pristine or silently alter algorithms.
- Preserve raw logs, code/toolchain hashes and regressions. No universal speedup
  claim, mandatory "everything got faster" reward, or unapproved threshold tuning.
- Update WORKLIST with actual completed scope, failures and evidence. If a batch
  is partial, say so; do not close the whole cutover on an ISA manifest or a demo.

### Execution discipline for every batch

One approval covers the coherent batch, not each edit. Describe the jj change before
editing and snapshot at meaningful checkpoints. Temporary broken snapshots are
allowed and must be described honestly. Keep substantial cross-file replacements
together; do not manufacture one task/commit per symbol. Report progress when a
boundary is reached or a real blocker appears, not after every function.

A narrow probe is allowed to answer a concrete blocker. Otherwise work through the
batch, then validate its boundary. No speculative scaffolding, legacy facades,
dual representations, cache-policy switches or generic interpreter fallback to keep
intermediate builds green. Stop only for a genuine new contract conflict, missing
external dependency, corruption risk or unavailable information—not merely because
the next file no longer compiles against the old representation.

## 9. Proposed exact encoding and API details (P1–P5)

### 9.1 Header/sections

Retain the existing 16-byte header shape, little-endian fields and section framing.
Magic is `ABC3`, u16 revision is **1**, pointer size is 8, profiles are 1–4, reserved
word is zero. next rejects all ABC2 files; root stays unchanged and rejects ABC3.
No translator, profile-5 admission or old format alias is part of the cutover.

Profiles 1,2,3 require sections 1–3, 1–6, 1–8 respectively. Profile 4 requires 1–10;
section 10 can have zero entries. Retain existing payload definitions for function
signatures, image data, load kinds, indirect-site signatures, code relocations,
externs and lifecycle relocations. Regenerate every code offset. Lifecycle entry
roles and reserved source-binding signatures remain exact. The old revision-7 test
becomes ABC3/profile-4/section-10 admission, not a second V3 revision.

Function argument/result counts remain 0–255, hidden-result rules unchanged. Host
API signatures/results/error structures and AOT result/failure ABI remain unchanged;
`stack_cells` has the explicitly new unified meaning. Images remain VM-private and
persist across calls/aborts. Foreign and lifecycle ownership gates remain closed
where they were closed in the copied implementation.

### 9.2 Byte allocation

This table is a complete **proposed** assignment. Within a listed family sequence,
expand `.A,.B` consecutively for each family. Do not infer bank from opcode bit zero:
neutral groups break that assumption. The manifest is authoritative for roles.

| Core bytes | Ordered expansion |
| --- | --- |
| 00–13 | HALT, ABORT, PUSH8, PUSH32, PUSH64, DUP, DROP, NIP, SLIDE, GET0, GET1, GET2, GET, GETR, SET0, SET, MOVE_AB, COPY_AB, GET_B, MOVE_BA |
| 14–45 | `.A,.B` of ADD, SUB, MUL, DIVU, DIVS, REMU, REMS, AND, OR, XOR, SHL, SHR, SAR, EQ, NE, LT, LE, LTU, LEU, GT, GE, GTU, GEU, POW, POWS |
| 46–53 | `.A,.B` of NEG, NOT, LNOT, ZX32, SX32, ZX8, ZX16 |
| 54–5D | `.A,.B` of CHKU8, CHKU16, CHKU32, CHKI32, CHKNN |
| 5E–6F | `.A,.B` of ADDI, SUBI, MULI, ANDI, ORI, XORI, SHLI, SHRI, SARI |
| 70–78 | ADDG, SUBG, MULG, XORG, ANDG, ORG, SHLG, SHRG, SARG (A result) |
| 79–80 | JMP, JMP32, JZ.A, JZ.B, JNZ.A, JNZ.B, SWITCH.A, SWITCH.B |
| 81–8A | BEQ, BNE, BLT, BLE, BLTU, BLEU, BGT, BGE, BGTU, BGEU (A-left/B-right, consume both) |
| 8B–9E | `.A,.B` of BEQI, BNEI, BLTI, BLEI, BGTI, BGEI, BLTUI, BLEUI, BGTUI, BGEUI |
| 9F–A7 | CALL.A, CALL.B, TCALL, CALLI.A, CALLI.B, TCALLI, FCALL.A, FCALL.B, RET |
| A8–E4 | Memory expansion below (61 forms) |
| E5–FE | Unassigned; reject |
| FF | EXT, followed by one selector byte |

Memory expansion, in order: ALLOC, FREE; then for F followed by G, the five loads
LD8/16/32/32S/64 each `.A,.B`, the four stores ST8/16/32/64 without suffix, and
ADDR.A/ADDR.B. Then pointer LD8/16/32/32S/64 each `.A,.B`; pointer ST8/16/32/64
without suffix; LDX8/16/32/32S/64 each `.A,.B`; IDX.A, IDX.B, MEMCPY.

| EXT selector | Ordered expansion |
| --- | --- |
| 00–13 | `.A,.B` of FADD, FSUB, FMUL, FDIV, FLT, FLE, FEQ, FGT, FGE, FNE |
| 14–1D | `.A,.B` of FNEG, I2FS, I2FU, F2IS, F2IU |
| 1E–25 | `.A,.B` of F2BITS, BITS2F, ADDR2BITS, BITS2ADDR |
| 26–2B | FBLT, FBLE, FBEQ, FBGT, FBGE, FBNE (A-left/B-right, consume both) |
| 2C–FF | Unassigned; reject |

229 direct semantic forms plus 44 extended forms; EXT is a prefix, not another
semantic operation. No quickening bytes. Float ordered GT/GE compare in their named
direction; FNE/FBNE complement equality, including NaNs. Shared computation owns
these rules; do not duplicate them in backend handlers. Profile requirements follow
the operation: scalar/control integer forms profile 1; CHKNN, typed memory,
float and bitcasts profile 2+; indirect profile 3+; foreign/lifecycle profile 4.

### 9.3 Operands and lengths

All numbers are little-endian, unaligned. Multi-byte relative branches/calls are
measured from the end of the complete instruction. Extended instructions have one
origin PC at FF. No branch targets a selector/operand byte.

The assembly convenience `PUSH` chooses PUSH8/32/64; GET/SET select their short
forms when applicable. Other declared suffixes/roles are mandatory: there is no
implicit A default for binary arithmetic or legacy COPY.A/CPUSH alias. The new
assembler does not guess whether a source file intended V2 semantics.

| Instruction | Fields after opcode (after EXT selector for extended forms) |
| --- | --- |
| PUSH8 / PUSH32 / PUSH64 | i8 / i32 / u64 bits |
| GET, GET_B, SET, all G forms | u16 depth |
| GETR | u16 depth, u8 count |
| SLIDE | u16 drop, u8 keep |
| Immediate arithmetic | i8 immediate |
| JZ/JNZ, integer/float binary branches | i16 displacement |
| Immediate branches | i8 immediate, i16 displacement |
| JMP / JMP32 | i16 / i32 displacement |
| SWITCH | u16 count, count × i32 displacement; base is complete table end |
| CALL.A/B | i32 displacement, u8 arguments |
| TCALL | i32 displacement, u16 frame cells k, u16 control depth d, u8 arguments n |
| CALLI.A/B | u8 arguments; immutable site signature remains required |
| TCALLI | u16 frame cells k, u16 control depth d, u8 arguments n |
| RET / HALT | u16 frame cells k, u16 control depth d, u8 results r |
| FCALL.A/B | u16 extern index |
| ALLOC | u16 requested bytes |
| FREE | u16 requested bytes, u8 keep |
| FLD/FST/FADDR | u32 byte offset from logical A end |
| GLD/GST/GADDR | u32 image byte offset |
| LD/ST | u16 pointer byte offset |
| LDX | none |
| IDX | u16 element bytes |
| MEMCPY | u32 byte count |
| ABORT | u8 nonzero reason |
| All other forms | none |

Scalar depth/frame operands are limited by their declared u16 encoding, vector
counts by u8. Reject overflow in producers/assembler; never truncate. Requested
block size retains the existing u16 bound. Frame byte offsets widen to u32 because
unified operands above a block contribute to its offset. The one-byte core/EXT
trade-off is explicit; do not advertise the sketch's roughly 125-opcode estimate.

## 10. Decisive acceptance cases, grouped by boundary

Boundary A covers:

- All 72 T0 states, spills, empty-cache reads, captured GETR sources, overlapping
  SET/NIP/SLIDE/return/tail transport, poisoned inactive registers and no refill.
- A-left/B-right noncommutative results into both destinations; B validity/kind at
  joins; narrow/float/NaN/check/bitcast behavior and original abort PCs.
- Zero/many arguments, 0/1/many results, CALL.B restriction, recursion, different
  return paths, changing-arity tails, caller-prefix preservation and host sentinel.
- Invalid control-cell accesses, split blocks, frame-depth/count overflow, old
  modules, malformed EXT/targets, and indirect identity/signature/entry roles.
- Stable block addresses across nested calls and virtual frames, FREE with preserved
  scalar results, capacity failures with live cleanup records and foreign boundaries.
- Eligible virtual-call residue: no argument-gather stores, continuation store or
  return copy solely due to the call; an identity callee preserves the value's
  placement. Also test a mutable-home alias overwritten inside the callee so the
  necessary capture cannot be optimized away.
- Real recursive register-entry and single-result r0 transport, generic edge
  conformance with B live, backedge weakening, unknown indirect target and limits.

Boundary B covers:

- Deep/nested RHS expressions and effectful operand order, scalar B vs aggregate
  vectors, packed fields, slice/view pairs, ordered comparisons and bounds checks.
- Source owning arguments/results, partial acquisition failure, active-tag cleanup,
  adapters and C-entry drop bodies through raw/optimized execution in four modes.
- Optimizer-produced modules re-verify; source sessions and snapshots preserve
  current admission; supported portable-C results/errors match, unsupported residue
  still rejects rather than becoming an alternate evaluator.
- Structural removal: no active CPUSH/CGET/CSET/CPOP projection, B/C backing arrays,
  separate frame side stack or selected-first B reversal in next's implementation.
  Immutable experiments/baseline manifests are excluded from this active-code audit.

Boundary C is the clean integrated suite, architectural diff/removal review and
single fixed performance comparison described in V10. A passing demo cannot
substitute for these boundaries, but these boundaries are not permission to run
the full suite after every edit.
