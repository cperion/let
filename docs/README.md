# Design documents

**Project management:** [WORKLIST.md](../WORKLIST.md) is the live, code-audited
checkbox ledger. [REFACTOR.md](../REFACTOR.md) preserves architecture and historical
implementation evidence; specs below do not establish implementation status.

- **`runtime-interfaces.md`:** implementer-facing private C interfaces, layouts, ownership transport, scheduler state/memory orders, lock hierarchy and VM binding rules. Target, not implemented.
- **`implementation-map.md`:** existing/new files, responsibilities, tests and removals keyed to live worklist IDs.
- **`runtime-primitives.md`:** concrete owner/container/task/scheduler data structures and execution algorithms; approved implementation baseline, ABI binding pending, not implemented.
- **`owners-references-ids.md`:** approved collector-free ownership target, actual-owner proof, containers/ids, capability facts, explicit remaining gates and required tests. Not implemented.
- **`application-sugar.md`:** literal-led postfix arguments and member-first, closed-interface lexical receiver calls; ordinary ownership semantics, imports and generic/dynamic boundaries. Not implemented.
- **`operators-and-blocks.md`:** schema-owned operator protocols and trailing block sugar; static-first design, concrete interface/ordering gates and separate dynamic integration. Not implemented.
- **`spread.md`:** static supply expansion, second-class packs, record updates, name binding and `use ...module` sugar; target semantics and tests, not implemented.
- **`tasks.md`:** approved structured-task/channel/select design, scoped capabilities, cancellation and work stealing; concrete suspension/concurrency ABIs remain pending. Not implemented.
- **`syntax.md`:** integrated target grammar (spread/rest/import sugar/trailing blocks), operator protocols and standard-library navigation for one collector-free Let; implementation status is separate.
- **`stdlib.md`:** canonical target module/API inventory, container/task/text/resource contracts and explicit remaining signature/export gates. Not a claim that modules are bundled.
- **`spec.md`:** machine contracts and stable decisions, with implemented behavior separated from architectural targets and known conformance gaps.
- **`symmetric-isa.md`:** authoritative revision-6 selected-stack semantics and instruction encoding.
- **`architecture.md`:** current repository responsibilities, execution/tooling boundaries and remaining architectural gaps.
- **`threaded-execution.md`:** four execution modes, exact threaded records, shared residualization/backend ownership, validation and measured caveats.
- **`module-format.md`:** implemented revision-6 profiles 1–4 and verifier/ownership constraints; no old-format compatibility.
- **`memory-profile.md`:** selected frame/image/pointer operations and native-pointer obligations.
- **`callable-profile.md`:** checked indirect ABI, immutable signatures, shared observations and source-support limits; no bytecode rewriting.
- **`foreign-profile.md`:** typed externs, VM-local binding, C-ABI bridges and selected `FCALL.X`.
- **`dynamic-profile.md`:** collector-free dynamic-value/counting obligations and encoding gates; supersedes tracing profile 5 without making it loadable.
- **`slet-subset.md`:** the production Let/SLet frontend's supported source paths and deliberate limits.
- **`frontend-completion-plan.md`:** active specification-driven frontend backlog, audit probes, dependencies, detailed acceptance tests and performance gates.
- **`remaining-work.md`:** concise restart index into the active frontend completion plan.
- **`frontend-gap-analysis.md`:** historical implementation audit; its source-profile/GC roadmap is superseded by the current ownership and completion plans.
- **`compiler-continuations.md`:** continuation-directed production lowering, local `CALL`/`TCALL` selection, defunctionalization, recursion as cyclic control flow, and the restricted tail-call-modulo-accumulation optimization.
- **`symbolic-vm.md`:** generated musttail abstract ABC execution shared by the native, canonical-ABC, and portable-C peer sinks.
- **`abc-opt.md`:** the standalone C ABC-to-ABC symbolic optimizer, canonical stack re-projection, frontend-fact contract, provenance, fixpoint and differential guarantees.
- **`four_lane_fork_v3.md`:** the four-lane stack-register design, an alternative that was compiled, measured and not adopted. The pre-alignment specification archive preserves the historical comparison.
