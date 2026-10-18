# Contract

## Problem
Redesign ABC's residualizing optimizer stack so it is simple, compiles extremely fast, and emits the fastest code — with residualization (one symbolic executor over verified ABC that folds constants, earns facts, and hands residue to a sink) as the organizing principle.

Scope: the shared optimizer core and its sinks as they exist today — `src/symbolic.c` + `gen/symbolic.lua` (shared symbolic execution / dispatch, folding, continuations), `src/optimize.c` (build-time ABC-to-ABC residual DAG optimizer, "abc-opt"), `src/residualize.c` (native eager/lazy JIT: stack-cache register allocation, block versions, register-addressed stencil copy-and-patch), `src/residual_builder.c` + `src/residual_c.c` (semantic residue to strict C11), plus their generators (`gen/stencils.lua`, `gen/threaded.lua`, `gen/banked.lua`), schemas, and validation tooling.

The design question: what is the smallest, most coherent architecture that keeps one authoritative residualization semantics while making (a) compile time near-trivial (no redundant passes, one walk per block, no SSA/IR round trips, no second allocator, no placement reconstruction, no post-hoc normalization), (b) generated code as fast as achievable (register-addressed single-instruction stencils, no state-keyed residue in compiled output, efficient calls/continuations/loops, good immediate and home selection), and (c) the whole thing explainable on one page.

Required behavior to preserve (from the project's approved authorities): meaning preservation via symbolic execution of ABC semantics, verifier-checked output, determinism and idempotence, provenance, check/trap/abort ordering, IEEE grouping, signature and result-cell order, explicit ABC continuations with frame transport separate from control transfer, effect synchronization, stack-limit behavior, no tracing collector, entry-guard/block-version policy, eager/lazy/threaded/off policy separation, and build-time optimizer independence from runtime execution. Any change to version policy, continuation representation, ABI, encoding, or owner/lifetime semantics is a hard gate that must be surfaced as an explicit question, not decided silently.

Hard constraints:
- No second (native) register allocator, no separate native residual-value IR, no placement-reconstruction pass: symbolic cache state IS the register allocation.
- No new generic facade/helper interpreter over the existing implementation, no old-to-new-to-old round trips, no legacy/replacement dispatch flags, no "temporary" compatibility layers. Cut over responsibilities directly; name the retired paths.
- One authoritative scalar computation owns checks, branches, representation, errors; backends bind execution mechanisms only.
- Runtime execution must not depend on the build-time abc-opt pipeline.
- Keep the A/B symmetric stack model (for `.X`, X0 op Y0, result on X); no A-only repacking.
- Do not invent requirements; where a change is genuinely a policy or interface gate for the user, list it as an open question.

Non-goals: implementing the redesign (design only), Whippet/GC work, the Let frontend's source partial evaluator, and speculative new language features.

The audit should judge the winning design on: simplicity/explainability, expected compile-time cost, expected generated-code quality, how much existing machinery it deletes, conformance to the constraints above, and whether its claimed performance wins are backed by existing measurements in the repo (or are honest projections with a measurement plan).

## Constraints
Must preserve meaning preservation via ABC symbolic semantics, verifier-checked output, determinism/idempotence, provenance, trap/check/abort ordering, IEEE grouping, signatures and result-cell order, explicit continuations with frame transport separate from control transfer, effect synchronization, stack-limit behavior, and the no-collector target. Must not introduce a second register allocator, a second native residual-value IR, a placement-reconstruction pass, a facade over the old implementation, old-to-new-to-old normalization, or legacy/replacement dispatch flags. Must keep one authoritative scalar computation; backends bind execution mechanisms only. Must preserve the A/B symmetric stack model. Hard gates (version policy, continuation representation, ABI, encoding, owner/lifetime semantics) must be raised as questions rather than decided.

## Existing code
- `src/optimize.c`
- `src/residualize.c`
- `src/symbolic.c`
- `src/symbolic.h`
- `src/residual_builder.c`
- `src/residual_c.c`
- `src/residual_ir.c`
- `src/residual_ir.h`
- `src/verify.c`
- `gen/symbolic.lua`
- `gen/stencils.lua`
- `gen/threaded.lua`
- `gen/banked.lua`
- `gen/semantics.lua`
- `gen/execution_forms.lua`
- `gen/cache.lua`
- `docs/abc-opt.md`
- `docs/architecture.md`
- `docs/spec.md`
- `docs/runtime-interfaces.md`
- `docs/runtime-primitives.md`
- `docs/symbolic-vm.md`
- `docs/threaded-execution.md`
- `docs/implementation-map.md`
- `REFACTOR.md`
- `WORKLIST.md`
- `tools/abc_opt.c`
- `tools/validate_optimizer_isa.lua`
- `frontend/let/optimize.lua`
- `schema/residual.asdl`
- `Makefile`

## Rules for this search
- Required behavior, observed legacy behavior, confirmed constraints, assumptions and preferences are distinct. Do not promote one into another.
- Missing requirements are open questions, never inventions.
- Definition of done: every stated requirement is accounted for, no unresolved material question remains, and an implementer can build the design without inventing semantics.
