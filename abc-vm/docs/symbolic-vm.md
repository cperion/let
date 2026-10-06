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

At dynamic and foreign boundaries, the sink materializes required representations and roots. Managed interior pointers remain visible through stack homes before allocation or collection. Unknown dynamic operations continue through `vm_dynamic_native()`.

## Versioning and termination

Basic-block versioning has one policy knob: `ABC_BLOCK_VERSION_LIMIT`. It limits versions locally for one compatible block-context family, including versions reached through virtual continuations. It is not an optimizer path limit, a continuation-depth limit, or a total-code-size budget. Known calls can use virtual continuations while the destination block has local version room. Recursive SCC boundaries, unknown calls, and ABI-visible calls remain real. There is no fuel, hotness, instruction, or module-wide code budget.

At the local limit, an edge generalizes to a compatible context; it does not force native values through a generic all-home representation. Backedges conform only values that must cross the edge.

## Peer sinks

The generated dispatcher drives three peer sinks:

1. **Native stencil sink (`src/residualize.c`).** It emits register-addressed stencils directly from the symbolic stack cache. Renaming, copy-on-write, consumption, constants, and known stack operations are resolved before emission. There is no residual SSA graph, all-value home plan, or separate register allocator between symbolic execution and machine code.
2. **Canonical ABC sink (`src/optimize.c`).** It records an ordered expression/effect DAG inside the sink, virtualizes eligible calls, preserves unsafe functions, and re-projects symbolic residue onto canonical verified A/B/C bytecode. The standalone optimizer, embedding API, and LuaJIT FFI use this sink.
3. **Portable-C sink (`src/residual_builder.c`, `src/residual_c.c`).** It records target-independent semantic residue because structured self-contained C needs explicit values, blocks, calls, ABI metadata, and provenance. The writer maps proven scalar values to typed C locals, direct known calls to natural typed C signatures, and eligible single results to scalar returns. Pointer-array/status adapters remain only at exports and genuinely generic, trapping, or multi-result boundaries. This residue is private to the C backend; native emission is never routed through it.

Shared semantics do not imply a shared generic value machine. All three sinks receive the same generated transfer contracts and symbolic stack transitions, while each sink records only the residue required by its target.

## Calls and callable targets

Direct nonrecursive calls can be virtualized when their contexts are compatible. Recursive and ABI-visible boundaries retain explicit calls and returns when required. Callable-profile raw indirect calls use signature-checked direct resolution without adaptive-site transitions; dynamic callable sites retain adaptive inline caches and represented closure semantics.

Unknown, escaping, identity-observable, ABI-visible, managed-stored, or `any` callables retain their represented closure or word. Eliminating a callable cannot remove capture effects, change ownership or roots, change signatures/results, or move a trap.

## Current implementation boundary

`src/symbolic.c` owns abstract values, A/B/C shape changes, virtual continuations, folding, control exits, result adjustment, continuation restoration, and tail-frame replacement. `gen/symbolic.lua` emits musttail handlers for all public opcodes.

`compile_version()` in the native sink contains no handwritten opcode switch or source-bytecode recovery path. It establishes a symbolic machine, handles structured exits, and schedules native block versions. Native callbacks maintain register/home representations, roots, stencil placement, and edges.

The optimizer and portable-C builder configure the same dispatcher with their own callbacks. Unsupported optimizer rewrites preserve verified source functions. Portable C validates semantic residue and emits strict self-contained C11 for its current integer/control/direct-call subset; float, memory, indirect/foreign, managed and dynamic operations currently reject rather than falling back to another backend.

The acceptance gate is both semantic and architectural: full interpreted/eager/lazy/C parity must pass, and native steady-state performance must remain in the pre-refactor near-LuaJIT/native class. A correct but all-home native lowering is not an acceptable implementation.
