# Design documents

- **`syntax.md`:** the unified Let language contract for SLet `.slet` files and progressively typed Let `.let` files.
- **`spec.md`:** the authoritative VM specification, decisions and measurements.
- **`architecture.md`:** target repository structure and ownership boundaries for the Lua-generated C VM.
- **`module-format.md`:** the implemented versioned wire formats and verifier constraints.
- **`memory-profile.md`:** Milestone 2 frame/image/pointer instructions, memory-profile encoding and native-pointer obligations.
- **`callable-profile.md`:** Milestone 3 checked-core ABI, indirect site signatures, bounded rewriting and lexical closures.
- **`foreign-profile.md`:** typed named extern tables, VM-local binding, generated C-ABI bridges, and `FCALL`.
- **`dynamic-profile.md`:** one-cell `any`, generic operations, collected open-word maps and layout tokens, Let managed references/views, module trace metadata, GC, and eager/lazy obligations.
- **`slet-subset.md`:** the LuaJIT scalar frontend's supported syntax and deliberate limits.
- **`frontend-gap-analysis.md`:** audit of the scalar frontend, the reused ASDL frontend snapshot under `../frontend/`, and the ABC lowering roadmap.
- **`compiler-continuations.md`:** continuation-directed production lowering, local `CALL`/`TCALL` selection, defunctionalization, recursion as cyclic control flow, and the restricted tail-call-modulo-accumulation optimization.
- **`symbolic-vm.md`:** generated musttail abstract ABC execution shared by the native residualizer and ABC optimizer sinks.
- **`abc-opt.md`:** the standalone C ABC-to-ABC symbolic optimizer, canonical stack re-projection, frontend-fact contract, provenance, fixpoint and differential guarantees.
- **`abc-opt.md`:** the standalone C ABC-to-ABC symbolic optimizer, canonical stack re-projection, frontend-fact contract, provenance, fixpoint and differential guarantees.
- **`four_lane_fork_v3.md`:** the four-lane stack-register design, an alternative that was compiled, measured and not adopted. The specification's section "Status and measurements" records the comparison.
