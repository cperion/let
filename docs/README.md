# Design documents

- **`syntax.md`:** the unified Let language contract for SLet `.slet` files and progressively typed Let `.let` files.
- **`spec.md`:** the authoritative VM specification, decisions and measurements.
- **`architecture.md`:** target repository structure and ownership boundaries for the Lua-generated C VM.
- **`module-format.md`:** the implemented versioned wire formats and verifier constraints.
- **`memory-profile.md`:** Milestone 2 frame/image/pointer instructions, memory-profile encoding and native-pointer obligations.
- **`callable-profile.md`:** Milestone 3 checked-core ABI, indirect site signatures, bounded rewriting and lexical closures.
- **`foreign-profile.md`:** typed named extern tables, VM-local binding, generated C-ABI bridges, and `FCALL`.
- **`dynamic-profile.md`:** one-cell `any`, generic operations, collected open-word maps and layout tokens, Let managed references/views, module trace metadata, GC, and eager/lazy obligations.
- **`slet-subset.md`:** the production Let/SLet frontend's supported source paths and deliberate limits.
- **`frontend-completion-plan.md`:** active specification-driven frontend backlog, audit probes, dependencies, detailed acceptance tests and performance gates.
- **`remaining-work.md`:** concise restart index into the active frontend completion plan.
- **`frontend-gap-analysis.md`:** implementation audit of the reused ASDL frontend, required compilation boundaries, completed foundation, and detailed source roadmap.
- **`compiler-continuations.md`:** continuation-directed production lowering, local `CALL`/`TCALL` selection, defunctionalization, recursion as cyclic control flow, and the restricted tail-call-modulo-accumulation optimization.
- **`symbolic-vm.md`:** generated musttail abstract ABC execution shared by the native, canonical-ABC, and portable-C peer sinks.
- **`symbolic-interpreter-refactor.md`:** archive-and-port rewrite from sink-controlled symbolic execution to a compact handwritten residual IR and one-way native/ABC/C consumers.
- **`abc-opt.md`:** the standalone C ABC-to-ABC symbolic optimizer, canonical stack re-projection, frontend-fact contract, provenance, fixpoint and differential guarantees.
- **`four_lane_fork_v3.md`:** the four-lane stack-register design, an alternative that was compiled, measured and not adopted. The specification's section "Status and measurements" records the comparison.
