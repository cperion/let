# ABC machine specification and architectural targets

This page separates **current revision-6 contracts** from **approved targets not
yet fully implemented**. Existing code does not redefine the intended design.
The former mixed historical/proposed document is preserved, including its
measurements and decision rationale, in
[the pre-alignment archive](../research/archive/phase-5-documentation-before-alignment/README.md).

## Authorities and status

- [Symmetric ISA](symmetric-isa.md): selected-stack semantics, instruction forms,
  byte assignments and call/return contracts.
- [Module format](module-format.md): revision 6, profiles 1–4, plus revision 7,
  profile 4 lifecycle C-entry metadata. Metadata is verified/optimized; native
  lifecycle delivery is implemented, with tooling residual IR/portable C still closed. Other revisions and profile 5 reject,
  without translation.
- [Architecture](architecture.md): current ownership, build/runtime boundaries
  and explicit conformance gaps.
- [Refactor plan](../REFACTOR.md): chronological implementation, validation and
  performance evidence. A proposed or approved design is not an implementation.
- [Source partial evaluation](source-partial-evaluation.md),
  [virtual contract](source-virtual-contract.md) and
  [compilation API](source-compilation-api.md): approved source architecture and
  its outstanding implementation, separate from native residualization.

The active typed runtime, supported source/tooling paths and clean full validation
pass. Migration closure is not complete: whole-diff review, broader documentation
alignment and native version-budget conformance remain open. Dynamic/managed Let
execution is unavailable. The hybrid eager-top C-cache idea is parked, not adopted.

## Machine state and values

The machine has an instruction pointer, A/B operand stacks, C structured state and
a VM-private module image. Cells carry 64 bits; signatures distinguish integer,
address and binary64 kinds where the profile permits them. Integer widths and
normalization are producer responsibilities, not different physical cell sizes.
Native pointers are addresses, not checked handles. Frame blocks are byte storage
on C, not freely accessible scalar cells.

The module is immutable. Its writable image is private to each VM/module pair and
persists across calls and aborts. Image ownership retains the module; teardown
releases native state before that module reference. Calls reset stacks, not image
writes. Public host inputs/results are ordered raw-cell vectors without an A/B
selector. See the embedding contract in `include/abc.h` and the module format.

## Selected operand semantics

Let X be the selected stack and Y the opposite stack:

| Form | Meaning |
| --- | --- |
| `OP.X` | consume X0 and Y0; compute **X0 op Y0**; push the result on X |
| `OPI.X k` | replace X0 with X0 op sign-extended i8 k |
| `OPC.X d` | replace X0 with X0 op C[d]; leave C unchanged |
| unary/check/literal `.X` | operate on X under the declared layout |
| `COPY.X` / `MOVE.X` | copy / move X0 to Y |
| `CPUSH.X` | move X0 to C0 |
| `CPUSHN.X n` | perform n ordered top-first transfers to C |
| `CGET.X d` / `CSET.X d` | read C[d] onto X / consume X0 to replace C[d] |
| `CGETR.X d,n` | copy C[d] through C[d+n-1] onto X, shallowest first |
| binary branch `.X` | compare X0 against Y0, consuming both |
| immediate branch `.X` | compare X0 against the immediate, consuming X0 |
| `SWITCH.X` | consume index X0; select its target or fall through if out of range |

Thus **SUB.B computes B0−A0**, not A0−B0. Immediate/C forms do not repack through
A. C accesses are explicit and must remain within the current function's verified
scalar/block layout. There are no implicit callee operands below private A/B
regions, even at zero arity.

A complete selected-first example (returns −7 in every mode):

```text
.function main 0 1
    PUSH.A 10
    PUSH.B 3
    SUB.B
    RET.B 0 1
.export main
```

## Arithmetic

Integer operations act on 64-bit bits with declared wrapping semantics. Narrow
source values use ZX8/ZX16/ZX32 or SX32 where required. Signedness matters for
ordered comparisons, division/remainder, right shifts and signed power checks.

Division/remainder by zero aborts with reason 1; signed MIN/−1 wraps. Large shifts
produce zero or arithmetic sign fill rather than host undefined behavior. Power
wraps, defines 0^0 as 1, and signed negative exponents abort with reason 4. LNOT
is XOR 1 under its boolean-input convention, not a general nonzero test.

Binary64 arithmetic/comparisons preserve IEEE-754 behavior. FEQ and ordered
comparisons are false for NaN; inequality/negation must preserve the complementary
branch behavior, not substitute a reversed ordered comparison. I2FS/I2FU use
nearest/ties-even; F2IS/F2IU truncate and abort on invalid/out-of-range input.
Conversions/check failures use reason 3. Explicit producer bounds checks may
branch to ABORT 2. Abort zero is invalid; a language abort records its reason and
original instruction PC and does not unwind deferred actions.

## The operand bank

Concrete interpreter placement is an implementation binding, not a callable ABI.
A/B share four anchored registers h0–h3. With a+b≤4, A0 is h[a−1] when a>0 and
B0 is h[4−b] when b>0. C has three registers; with cached depth c>0, C0 is c[c−1].
There are 15 A/B combinations and four C occupancies: 60 combined handler states.

Pushes spill when their bank is full. Pops do **not** eagerly refill; an uncached
read accesses its backing cell. Hence it is not true that only a full bank ever
touches memory. Calls preserve cache-state semantics rather than imposing a
public register layout. Allocation/free, range transfers and foreign boundaries
perform their required synchronization. There is no mandatory cached C top.

Native allocation is not 75 state-keyed stencils or a fixed four-register C bank:
the symbolic cell map allocates from the existing eight-register native value
cache and emits register-addressed stencils. Renaming, captures, copy-on-write,
real spills and edge conformance determine placement. No second allocator or
placement-reconstruction pass is part of the design.

## Memory model

**Current machine contracts below are unchanged.** The new source ownership target
is [owners-references-ids.md](owners-references-ids.md): separate counted escaping
roots, owner-aware acyclicity proofs, stores/ids, COW lists/strings/tables and
immutable sharing, with no collector. It is not implemented by profile 2. Its
release ABI, encoding and verifier facts require explicit design before runtime
changes; old profile-5 trace metadata is not a compatibility representation.

[The memory profile](memory-profile.md) defines frame blocks, image offsets and
unsafe pointers. In brief:

- Frame offsets count backward from the logical C end, within one live block's
  requested bytes. Scalar operations cannot reinterpret block cells.
- Image loads/stores select X; direct stores stay in the writable prefix.
- Pointer stores take **address X0, value Y0**. Indexed loads/index formation take
  **base X0, index Y0**. MEMCPY.X takes destination X0, source Y0; overlap is safe.
- CALLOC zero-initializes its rounded cell storage; CFREE must match the top block.
  Frame blocks and continuations count toward capacity.
- Addresses, pointer bounds and backing lifetimes are producer/host obligations.
  Verification is not a native-memory sandbox. Explicit load-kind annotations are
  producer assertions, not dynamic tags or GC metadata.

No fixed instruction-count or one-machine-instruction-per-access performance
promise follows from these semantic contracts. Required captures, spills,
conformance and effects may emit additional work.

## Instruction set and module format

The revision-6 core map contains **124 A/B pairs, EXT.A/EXT.B and six neutral
instructions**. Sixteen families use EXT selectors, including the two raw float/
integer bitcasts; there are 286 public selected core/extended forms. EXT, selector and operands are one instruction with one
origin PC. No internal quickening encodings or dynamic selectors are allocated.

CALLI.X is two bytes total (opcode, arguments); TCALLI.X is three (opcode,
frame cells, arguments). Site signatures are immutable metadata, not cache words.
All immediates use the declared little-endian layout. Branch displacements are
relative to instruction end. Selected forms require a bank; bare RET and historical
directional COPY/MOVE names are not compatibility aliases.

The module format is the sole section-record reference. The loader verifies
instruction boundaries, in-function edges, capability requirements, signatures,
typed stack joins, C layouts and protected caller regions before execution.
Unreachable instructions still decode and have their encoded metadata validated.

## Calls

For `CALL.X f n`, argument zero is deepest in the n-cell vector on X. Top-first
gathering puts argument zero at C0. A callee has empty private A/B stacks and
cannot read its caller's prefixes or continuation through C instructions.

`RET.Y k r` removes the complete k-cell local C frame and returns exactly the
ordered r-result vector from Y to the saved destination. Y is independent of X;
all four combinations are valid. The opposite private stack must be empty.
TCALL.X replaces its complete local frame/operand regions while preserving the
original continuation and destination. Result signatures, including hidden-result
metadata, must agree. Frame transport is distinct from control transfer.

[Indirect calls](callable-profile.md) additionally consume the target from the
opposite stack and validate exact same-module public identity and complete ABI.
An environment address is argument zero, included in the argument count.
[FCALL.X](foreign-profile.md) consumes/produces on X, preserves the opposite
prefix, and invokes an explicitly bound host function under its declared ABI.

Source aggregates may use caller-provided hidden-result storage and adapters,
but source ownership/materialization decisions are not additional VM opcodes.
Profile-3 callable views do not create managed ownership automatically.

## Observations and residual execution

Interpreter execution uses ahead-of-time cache-state handlers without code
rewriting. Indirect sites have one observation record per VM/module/original PC,
shared across execution bindings: unseen → valid monomorphic → final generic.
A mismatch records final generic before validating its new target. A proven and
validated direct target can eliminate observation without inventing statistics.
Observed identity alone is not a specialization proof.

Eager and lazy native policies share symbolic semantics and register-addressed
stencil emission. Eager prepares code at load; lazy compiles reached contexts
through stable stubs. Native code does not execute through the build-time ABC
optimizer or portable-C representation. There is no heat-driven tier promotion,
tracing, semantic fuel or recursive host execution of ABC calls.

Eligible acyclic calls use virtual continuations. Real calls materialize the
required ABC state and transfer explicitly; tails retain their continuation.
Native singleton results use r0. General vectors retain their selected source;
r1/r2 carry continuation/source at transfer, not as permanently reserved registers.

At backward edges the current native implementation weakens exact constants,
materializes their bits and constructs canonical register descriptors. It does
not force a memory home merely because knowledge weakened. Real spills and
generic conformance remain. This is not a claim of invariant-constant analysis.

### Version accounting and deferred ownership

The **current native/threaded threshold is 16**, using the existing policy:
`version_for()`/`edge()` count matching context families, whose identity includes
virtual continuations; `inline_candidate()` separately counts continuation
families. This does not bound total versions at a PC to 16. Build-time residual
tooling retains its independent threshold of 8.

The earlier eight-total-versions-per-PC contract and the audit's ten-version probe
are historical accounting evidence. `REFACTOR.md` §§3–4 explicitly replace that
shared-callee model with **caller-owned region realizations**: an inlined callee's
internal blocks belong to the enclosing caller realization, not the standalone
callee's budget. Internal control points must converge rather than create
unlimited hidden version families. That redesign is not implemented by changing
the current threshold.

Saturation must preserve required ABC continuations, live values, placement,
resource/error behavior and general execution without an opaque scalar fallback.
The region implementation needs its own coordinated design. The 16 default is a
user decision after a short control sweep, not evidence of a general speedup;
its substantial lazy-branch regression remains recorded in `REFACTOR.md`.

## Portable build target: residual to C

The portable-C writer consumes semantic residue produced by the shared symbolic
VM, not native placement. It is a build-time peer of ABC optimization and native
emission. Its supported integer/control/direct-call subset uses typed locals,
structured control and the declared result/failure ABI; unsupported residue
rejects. Full typed memory/foreign/indirect and managed source coverage must not
be inferred from the general architectural target.

This remains the canonical intended route from supported source through verified
ABC to C. It is not a second source evaluator, runtime optimizer dependency or a
promise that every source program currently lowers to portable C.

## Source partial evaluation and counted ownership

The approved source design uses virtual values and places, backward demands,
forward knowledge and delayed materialization. Computation executes only through
verified ABC in the VM, not a Lua source evaluator. Existing Ershov scheduling
and backend cache allocation remain authoritative. Effects and knowledge are
separate; known results do not erase required effects.

In-process scalar staging sessions are implemented. Full source demands,
`staticMode` policy/API, initialization snapshots/relocations and aggregate
transport are not. Source static execution has no semantic fuel budget; optional
execution needs justified termination/effect/no-abort safety. Required execution
can fail through an actual abort/resource failure or external interruption.
Progress/interrupt diagnostics and memory snapshot policies remain requirements,
not claims about the current bridge.

[Collector-free ownership](owners-references-ids.md) is the approved source target:
one Let language, independent type/count/allocation facts, implicit owners, strict
owner-edge constraints and immutable value DAGs. It replaces GC roots/safepoints,
tracing descriptors and collected open words as future ownership requirements.
[Dynamic values](dynamic-profile.md) retain shared scalar computation and non-owning
named-layout tokens, but use transferable values and COW tables. The target is not
implemented; the typed `.slet` path and `.let` lowering rejection remain current.
No new bytecode/profile or extension compatibility is authorized by these docs.
Selected-first A/B semantics and the no-quickening decision remain binding.

## Decisions

Stable decision numbers preserve references from earlier design discussions.
Historical measurements/rationale remain in the archive; later revision-6 and
source contracts supersede incompatible old wording.

1. **Calls/registers:** stack semantics are public; cache registers are private.
2. **Parameters:** CALL.X gathers into C; CPUSHN.X/CGETR.X retain ordered transport.
3. **Small records:** identity-preserving scalarization is a source target, not
   blanket implemented record flattening or permission to copy aliases incorrectly.
4. **Float branches:** ordered/equality NaN rules and complementary branch
   negation are retained; selected operand routing must preserve evaluation order.
5. **Targets:** x86-64 stencil execution is current. ARM64 is future work, not an
   implemented ABI/cache configuration; portable C is a separate build-time route.
6. **Range reads:** CGETR.X is adopted; CSETR is not.
7. **Duplicate check:** CHKNN subsumes the historical CHKI63 proposal.
8. **Negative literals:** follow the language's signed-literal/type-context rule;
   source literal semantics are not inferred from PUSH encoding width.
9. **Cache:** A/B share four anchored interpreter registers; C remains one dynamic
   lane. Native symbolic allocation is distinct. Hybrid eager refill is not adopted.
10. **FOLD2:** not adopted; no hidden two-deep scalar instruction convention.
11. **Operand forms:** OPI.X and OPC.X are selected-first; immediate branches
    exist in both banks. Current forms/EXT placement are in the symmetric ISA.
12. **Escape prefix:** EXT.A/B select declared typed families. Old single-EXT and
    internal quickening reservations are superseded; no serialized mutable cache.
13. **Versions:** shared observation history is distinct from entry-contract
    versions. Current native/threaded family/continuation thresholds are 16; caller-owned
    region budgeting supersedes the older shared-callee target and remains future
    work. Changing a threshold does not implement that ownership.
14. **Execution residualization:** one symbolic cache allocates eight native or
    seven threaded value registers. Shared preparation emits native stencils or
    final threaded records directly, with backend-independent labels and no
    second value IR. See [threaded-execution.md](threaded-execution.md).
15. **Execution policy:** host-selected `off`, `threaded`, `lazy`, or `eager`,
    independent of source filenames. Threaded preparation is eager and allocates
    no executable mapping; no bytecode quickening or automatic tiering.
16. **Portable C:** shared semantic residue is the canonical build-time route;
    implemented coverage is narrower than the complete target.
17. **Ownership target:** collector-free counted roots and immutable value DAGs
    replace the historical profile-5 GC design. One Let language uses independent
    capability facts. This is not executable support, a new encoding, or permission
    to restore archived engines.

## Status and measurements

Full active validation passes, including clean builds and the backedge placement
regression. This does not complete architectural acceptance or the whole-diff
review. Evidence, raw results and limitations are linked from `REFACTOR.md`.

The frozen old/new ISA comparison measured a roughly 16% interpreter Fibonacci
regression and a memory-interpreter improvement; most other paired ranges crossed
parity. The later native backedge correction reduced all four measured native
bodies, including memory 450→309 eager and 324→246 lazy bytes. Fibonacci eager
improved in those isolated comparisons; lazy's median regressed roughly 7–11%.
Native byte counts exclude lazy stubs, metadata and unused mapping capacity.

The user accepts regressions around 10%; this is not permission to conceal larger
regressions or claim a general speedup. Historical simulator, prototype and
four-lane measurements are not current revision-6 evidence. The four-lane fork,
operand-entry function ABI and eager C-top experiment are not adopted.
