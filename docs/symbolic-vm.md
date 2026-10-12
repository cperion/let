# Generated symbolic ABC VM

The optimizer, native residualizer, and portable-C backend share one internal symbolic ABC virtual machine. It executes verified ABC over abstract A/B/C stacks instead of concrete cells. It is not a source-language evaluator, a public execution policy, or a replacement for compile-time `abc_vm` execution.

## Generated execution core

The symbolic VM is generated from the same authoritative opcode manifest and semantic expressions as the concrete banked interpreter and stencil generator. Declarative instruction effects describe stack transport, scalar operations, conversions, checks, traps, control flow, memory, dynamic and foreign effects, calls, tails, returns, and `HALT`. Validation rejects an opcode without a transfer or explicit effect contract.

Generated handlers use one uniform C ABI and musttail dispatch. There is no per-instruction host loop and no C recursion for virtual calls. Known branches and virtual calls update the symbolic program counter and tail-dispatch directly. Unknown branches, real calls, joins, and barriers return structured exits to the backend's version driver.

Handwritten C owns contexts, facts, continuations, backend sinks, diagnostics, and module lifetime. Generated handlers own instruction transfer semantics.

## Abstract state

A symbolic context contains:

- symbolic A, B, and C stacks;
- each value's current representation and required destination home;
- the native stack cache's register identities and copy-on-write aliases;
- stack limits and C-frame bias/origin;
- virtual continuations;
- checked dynamic tag, width, and representation facts;
- the current bytecode offset.

A symbolic value is an exact constant, backend value, canonical home, or unknown represented value. The native backend value is already a stack-cache register assignment. It is not a target-independent SSA value awaiting a later allocator.

Constants, copies, compatible homes, and stack operations disappear during symbolic execution. Native register consumption is determined from the live symbolic stacks. A value is stored only when a real boundary, merge, root obligation, or overwrite requires a home.

Dynamic facts keep semantic tag sets and scalar widths separate from physical representation. Representation is raw, encoded `any`, boxed, unknown, or absent. Generic calls, GC-visible storage, unknown effects, and incompatible edges materialize the stable generic representation. Missing or conflicting facts only remove specialization.

## Copy-on-write homes

A symbolic copy can retain its source register or home until one alias is overwritten. Context flushing is therefore a parallel-copy problem, not permission to assign every value a permanent home. The native sink preserves older C-stack aliases before writing newer A/B scratch destinations. This order is required when a `CSET` renames a call result whose source A home will be reused by the next call.

At object/call and foreign boundaries, the sink materializes required representations and roots. Managed interior pointers remain visible through stack homes before allocation or collection. Object construction, open-word operations and dynamic calls retain the runtime ABI; scalar uncertainty does not use it.

## Check-driven scalar specialization

Scalar dynamic instructions are lowered to checks, typed bodies and specified
error edges in the existing register-bearing context. This covers binary and
literal arithmetic, unary operations, comparisons, conditions, boxing, casts
and type tests. `gen/scalar_semantics.lua` defines the complete control flow,
including checks, representation steps, selected typed operations and errors.
`gen/scalar_banked.lua` and `gen/scalar_symbolic.lua` bind that same computation
to concrete cache operations and ordinary symbolic ABC respectively.
`src/symbolic_scalar.inc` abstracts predicates and binds representation/control;
it does not independently orchestrate EXT algorithms. Typed expressions and
conversion recipes remain in `gen/semantics.lua`.
`src/native_scalar.inc` supplies only representation placement and branch-arm
binding; `src/residualize.c` drives the existing block versions. Neither engine
uses a scalar execution-handler fallback, including at version saturation.

Operand validity, promotion, literal adoption and equality rules live in
`src/scalar_rules.h`; descriptor projection lives in `src/dynamic.h`.
Representation bit operations and object layouts live in `src/any_repr.h`,
inlined into concrete operations and extracted stencils. Unknown
operands get register tag projections and ordinary branches. A possible object
address is checked with the collector's nonallocating membership predicate
before its header is read; this is not a language-operation dispatcher and
requires no whole-context publication. Proven tags skip the projections.
Checked successors refine live aliases. Narrow integers, wide integers and
`f64` use ordinary typed arithmetic. Failed arithmetic checks abort directly;
equality has its distinct mixed-signedness and unequal-type rules. No new IR,
allocator, placement pass or interpreter excursion is involved.

Primitive `ANY_IS` folds from existing facts. An adjacent `ANY_IS; JZ.A/JNZ.A`
also refines positive and negative successor contexts. Alias occurrences are
captured before register placement changes. Stored, combined or delayed
predicates do not carry persistent identities and therefore do not refine
successors. Aggregate/managed descriptor checks and unboxing use checked header
and field accesses, but descriptor proofs are not yet carried in version keys.

Unit boxing is an encoded constant; numeric boxing initially carries raw bits
and a tag fact, including when normalization is unproved. Raw wide integers and
floats survive compatible edges and spills. Real call arguments, returns,
stores and incompatible edges encode raw `any` values before crossing their
represented ABI. Float encoding never allocates. Integer escapes check payload
fit; only the non-fitting edge publishes roots and calls the scalar allocator.
That entry allocates an object, not an arithmetic or tag-dispatch operation.
Raw numbers need no boxes merely to make other roots visible to collection.
NaNs are canonicalized when encoded or exposed by an identity float cast.

Tag, width, range and encoding are distinct proofs. `SX32` is not an unsigned
range proof for immediate boxing. Exact-tag casts preserve even oversized
payloads: the sink can elide an already-raw identity cast, but a tag alone
does not prove that its value is decoded. Different-tag numeric conversions
remain checked. Native fusion of `ZX32` retains the zero-extension proof.
The ABC optimizer
retains source functions when a raw value cannot cross a represented effect
without boxing; it must not emit invalid ABC.

Edge-specific representation changes occur after the branch decision. Plain
register spills to distinct canonical homes can precede it: they neither
clobber the predicate nor overwrite a live home source. This keeps ordinary
typed branches on their original direct stencil path.

The interpreter generates a separate handler and continuation site for each
scalar selector, without quickening or a second arithmetic-selector dispatch.
It preserves its banked cache through scalar instructions, publishing roots
only on allocation or pending-collection edges. It stores canonical dynamic
cells rather than the native executor's raw representations.
Both engines use the allocation-only `vm_scalar_allocate`; `src/dynamic.c`
retains object/call effects, not scalar opcode execution.

Validation links tripwires rejecting scalar entry into both `vm_dynamic` and
`vm_dynamic_native`, including unary operations, casts and descriptor tests,
and a separate native allocation tripwire for a wide loop without escapes.
Both bindings poll the VM's pending-request flag at scalar boundaries. Native
code exposes live physical homes and its register bank only on the collection
edge, without reallocation or boxing raw integers. Tests cover pending requests
with/without a heap and a live register root after its module root is cleared.
A structural test also compares all semantic binding events of the two
generators. Repeated cold collection paths currently cause substantial native
code growth, and the checked-lazy benchmark regresses; see
[check-first measurements](../research/experiments/engines/check-first.md) and the
[historical type-version measurements](../research/experiments/type-versions/README.md).

## Versioning and termination

Basic-block versioning has one policy knob: `ABC_BLOCK_VERSION_LIMIT`. It limits versions locally for one compatible block-context family, including versions reached through virtual continuations. It is not an optimizer path limit, a continuation-depth limit, or a total-code-size budget. Known calls can use virtual continuations while the destination block has local version room. Recursive SCC boundaries, unknown calls, and ABI-visible calls remain real. There is no fuel, hotness, instruction, or module-wide code budget.

At the local limit, an edge materializes a compatible canonical generic context. Ordinary compatible edges retain the native stack-cache representation; this fallback is not a general all-home lowering. Eager admission can exhaust a family before every type has a stable specialized cycle. Lazy compilation admits only reached contexts, but uses the same proofs and local bound. Neither policy learns tags merely by reading saved activation registers.

## Peer sinks

The generated dispatcher drives three peer sinks:

1. **Native stencil sink (`src/residualize.c`).** It emits register-addressed stencils directly from the symbolic stack cache. Renaming, copy-on-write, consumption, constants, and known stack operations are resolved before emission. There is no residual SSA graph, all-value home plan, or separate register allocator between symbolic execution and machine code.
2. **Canonical ABC sink (`src/optimize.c`).** It records an ordered expression/effect DAG inside the sink, virtualizes eligible calls, preserves unsafe functions, and re-projects symbolic residue onto canonical verified A/B/C bytecode. The standalone optimizer, embedding API, and LuaJIT FFI use this sink.
3. **Portable-C sink (`src/residual_builder.c`, `src/residual_c.c`).** It records target-independent semantic residue because structured self-contained C needs explicit values, blocks, calls, ABI metadata, and provenance. The writer maps proven scalar values to typed C locals, direct known calls to natural typed C signatures, and eligible single results to scalar returns. Pointer-array/status adapters remain only at exports and genuinely generic, trapping, or multi-result boundaries. This residue is private to the C backend; native emission is never routed through it.

Shared semantics do not imply a shared generic value machine. All three sinks receive the same generated transfer contracts and symbolic stack transitions, while each sink records only the residue required by its target.

## Calls and callable targets

Direct nonrecursive calls can be virtualized when their contexts are compatible. Recursive and ABI-visible boundaries retain explicit calls and returns when required. Callable-profile raw indirect calls use signature-checked direct resolution without adaptive-site transitions; dynamic callable sites retain adaptive inline caches and represented closure semantics.

Native direct calls decompose frame transport from transfer, following the
specification's frame-operation-plus-jump rule. After publishing surviving caller
values and conforming arguments to the callee context, the sink stores a local
resume label in C, rebases the necessary stack frontiers, and emits an ordinary
direct edge. The resume label restores those frontiers with the same rebase
primitives. Zero rebases emit nothing. A terminal return publishes its results,
loads the continuation with an ordinary C-home load, and transfers through the
loaded register (or finishes at the host sentinel). Loading that target uses a
dead register distinct from the canonical single-result register.

There are no fused `CALL_JUMP`, `CALL_RESUME`, or `RETURN_CONT` stencils and no
packed call-frame immediate. Adjacent transport stencils fall through; extraction
removes their trailing `NEXT` jumps, not their semantic boundaries. Local resume
references use the same fixup mechanism as local branches and are bound before
the version is published, including during lazy activation. Register-entry
contexts, virtual continuations, and indirect/foreign/dynamic helper conventions
are unchanged; this is not a new residual IR or a host-stack calling convention.

Unknown, escaping, identity-observable, ABI-visible, managed-stored, or `any` callables retain their represented closure or word. Eliminating a callable cannot remove capture effects, change ownership or roots, change signatures/results, or move a trap.

## Current implementation boundary

`src/symbolic.c` owns abstract values, A/B/C shape changes, virtual continuations, folding, control exits, result adjustment, continuation restoration, and tail-frame replacement. `gen/symbolic.lua` emits musttail handlers for all public opcodes.

`compile_version()` in the native sink contains no handwritten opcode switch or source-bytecode recovery path. It establishes a symbolic machine, handles structured exits, and schedules native block versions. Native callbacks maintain register/home representations, roots, stencil placement, and edges.

The optimizer and portable-C builder configure the same dispatcher with their own callbacks. Unsupported optimizer rewrites preserve verified source functions. Portable C validates semantic residue and emits strict self-contained C11 for its current integer/control/direct-call subset; float, memory, indirect/foreign, managed and dynamic operations currently reject rather than falling back to another backend.

The acceptance gate is both semantic and architectural: full interpreted/eager/lazy/C parity must pass, and native steady-state performance must remain in the pre-refactor near-LuaJIT/native class. A correct but all-home native lowering is not an acceptable implementation.
