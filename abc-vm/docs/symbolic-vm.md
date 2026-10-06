# Generated symbolic ABC VM

The optimizer and native residualizer share one internal symbolic ABC virtual machine. It executes verified ABC over abstract values instead of concrete cells. It is not a source-language evaluator, a public execution policy, or a replacement for compile-time `abc_vm` execution.

## Generated execution core

The symbolic VM is generated from the same authoritative opcode manifest and semantic expressions as the concrete banked interpreter and stencil generator. A new declarative instruction-effect layer records stack effects, control effects, traps, memory effects and call boundaries. Both concrete and symbolic generators consume that layer; validation rejects an opcode that lacks either implementation.

Generated symbolic handlers use one uniform C ABI and musttail dispatch:

```c
typedef abc_sym_exit (*abc_sym_handler)(abc_sym_machine *);

handler(m):
    update abstract A/B/C state or append a residual node
    advance symbolic pc
    if a version/block boundary is reached: return an exit descriptor
    musttail return handlers[next_opcode](m)
```

There is no per-instruction host loop and no C recursion for virtual calls. The machine carries virtual continuations explicitly. Known branches and virtual calls update `pc` and tail-dispatch directly; unknown branches, real calls, joins and barriers return structured exits to the version driver.

Generation is sharded if compile size requires it, as for the concrete banked interpreter. Generated handlers contain instruction transfer logic, while handwritten C owns arenas, context/version tables, facts, sinks, diagnostics and module lifetime.

## Abstract state

An abstract context contains:

- symbolic A, B and C stacks;
- stack limits and canonical frame homes;
- a virtual continuation stack;
- checked context facts, including dynamic tags and layout tokens when available;
- a residual effect token;
- the current bytecode offset and complete provenance chain.

A symbolic value is one of:

- an exact constant;
- a canonical stack/frame/module home;
- a residual DAG node;
- an exact callable target with symbolic captures and receiver;
- a finite canonical set of callable alternatives;
- an unknown represented value.

Residual nodes describe operations and dependencies, not machine registers or ABC stack placement. Effectful and potentially trapping nodes depend on the previous effect token, which prevents illegal reordering. Every node records its original bytecode offset and any virtual-call provenance.

Dynamic facts keep semantic tag sets and scalar widths separate from physical representation. Representation is `raw`, encoded `any`, boxed, unknown, or absent. Copies and compatible homes preserve facts; typed operations clear them unless they establish a new width; joins union tags and widen conflicting widths or representations. A home store is not itself an escape, so a specialized loop may carry raw scalar bits. Generic calls, GC-visible storage, unknown effects, and incompatible edges materialize the stable generic representation. Missing or conflicting facts only remove specialization.

Proven `u32` and `i32` boxes, immediate-representable constant `u64` and `i64` boxes, matching casts, and same-singleton-tag `DADD`, `DSUB`, `DMUL`, `DAND`, `DOR`, and `DXOR` use typed scalar transfers. Wide operations specialize only for exact constants whose result remains directly encodable; results that require a runtime scalar box stay generic. Narrow results are normalized to their dynamic width. The native sink encodes raw values before generic call and effect boundaries. The ABC sink retains a whole function when a raw value would reach an unsupported generic dynamic operation. Thus `vm_dynamic_native()` remains the correctness path for unknown, mixed-tag, boxed, or otherwise unsupported cases.

## Version driver and termination

The version driver owns CFG discovery, context joins, virtual continuations, recursive-SCC detection and `ABC_SYMBOLIC_VERSION_CAP`. Backedges conform constants and temporary nodes to canonical homes. At the cap, a context becomes the most specific compatible generic context. There is no fuel, hotness or instruction budget.

Direct-call SCC membership controls only virtual inlining. Tailness was already encoded locally as `TCALL` by continuation-directed frontend lowering. Indirect and dynamic calls remain real unless the callable lattice proves an exact or finite non-escaping target.

## Residual graph consumers

The generated VM produces the same target-independent residual graph for two consumers:

1. **Native sink.** The eager/lazy residualizer schedules each block-version graph directly into register-addressed stencils. It preserves constants, register maps, continuations and checked dynamic facts. It never emits or re-reads ABC.
2. **ABC sink.** `abc-opt` combines eligible acyclic regions, performs closure elimination and finite defunctionalization, assigns cross-block homes, computes Ershov numbers and emits canonical verified A/B/C bytecode.

The native sink can initially preserve original residual-node order to make the refactor behavior-neutral. The ABC sink is the only consumer that re-projects a graph onto architectural stacks.

## Callable semantics

An exact non-escaping callable becomes its target plus plain symbolic captures; construction allocates nothing. A finite join becomes a canonical tag and union of capture values, and the ABC sink emits `SWITCH` with direct-call arms. Unknown, escaping, identity-observable, ABI-visible, managed-stored or `any` callables retain their represented closure/word and indirect or dynamic call.

Capture and receiver evaluation remains in the effect chain. Eliminating a closure cannot eliminate capture effects, change ownership or root obligations, change signatures/results, or move a trap. A finite tag representation never escapes optimizer-internal regions.

## Refactoring sequence

1. Extract exact folding, call-graph analysis, abstract values, contexts and continuations from `residualize.c`.
2. Introduce residual DAG/effect/provenance arenas and a version-driver API.
3. Add declarative generated symbolic handlers with musttail dispatch.
4. Port the current native register allocator/stencil placement into the native graph sink and require unchanged eager/lazy tests and benchmark behavior.
5. Add the canonical ABC sink and standalone `abc-opt` module writer/verifier.
6. Add callable facts, closure elimination and finite defunctionalization.
7. Differentially compare unoptimized ABC, optimized ABC and both sinks under every execution policy.

During migration, each extraction keeps `make validate` green. The old monolithic transfer case is removed only after its generated handler and native-sink path have equivalent differential coverage.

### Current migration boundary

`src/symbolic.c` owns abstract values, contexts, virtual continuations, folding, control exits and call-graph facts. `gen/symbolic.lua` emits a `musttail` handler for all 253 opcodes from `tools/opcodes.lua`; generation now fails if an opcode has neither a transfer class nor an explicit effect contract. Stack transport, scalar operations, conversions, checks, traps, control flow, memory operations, dynamic and foreign effects, direct and indirect calls, tail calls, returns and `HALT` all enter the native residualizer through generated dispatch. `compile_version()` contains no handwritten opcode switch or fallback chain; it only establishes a machine, handles structured exits and schedules block versions.

Generated handlers now invoke typed shared transfer contracts for memory, dynamic and foreign effects, direct and indirect calls, direct and indirect tail calls, `RET`, and virtual continuations. `src/symbolic.c` owns their A/B/C shape changes, result adjustment, continuation restoration and tail-frame replacement. Native callbacks only maintain target representations and roots, emit stencils, and schedule versions or edges.

`src/optimize.c` is the second C sink over this dispatcher. It builds ordered residual DAGs, virtualizes acyclic direct calls, lowers compatible self-tail transfers to backedges, and can ask the shared tail transfer to terminate at an explicit residual `TCALL` for non-tail or mutual SCC boundaries. Module-level SCC analysis joins private argument constants to stable recursive headers before re-emission, while ABI-visible roots begin unknown. Unknown control is bounded by `ABC_SYMBOLIC_VERSION_CAP`; one-result single-use recursive calls remain ordered in their control arm, and unsupported effect/result shapes retain the verified source function. The standalone binary, embedding API and LuaJIT FFI binding all reuse this sink.
