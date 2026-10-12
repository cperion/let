# Project instructions for coding agents

## Design together before coding — mandatory

Before every implementation change:

1. **Inspect the existing code and the intended specification.** Trace the relevant producers, contracts, consumers, and tests. Existing implementation behavior is not automatically the intended design; it may already contain drift.
2. **Present a concrete solution design to the user before editing implementation files.** Explain:
   - the problem and the intended architectural invariants;
   - the proposed end-to-end data flow, control flow, and interfaces;
   - which components and files must change;
   - what existing abstractions, assumptions, and code will be removed or replaced;
   - effects on semantics, representation, placement, continuations, and GC where relevant;
   - encoding/API compatibility decisions, alternatives, and unresolved questions;
   - how correctness and architectural conformance will be tested, and how performance will be measured when relevant.
3. **Wait for explicit user approval of that design before implementing it.** An instruction to fix a problem starts the design discussion; it does not waive this gate. Approval to investigate or discuss is not approval to code. Do not make a “small first patch” while the design is still being discussed.
4. **If implementation reveals a material design change, stop and discuss it.** Do not silently add a workaround, fallback, compatibility layer, or new subsystem.

The purpose is to think together and prevent architectural drift. A checklist of edits or a promise to “fix it end to end” is not a substitute for explaining the design.

Explicitly requested instruction/documentation edits, such as creating this file, may be made as requested; they do not authorize runtime implementation work.

## Replace wrong abstractions; do not accommodate them

- The goal is a coherent architecture, **not the minimum edits that keep existing behavior working**.
- Correct a broken contract at its authoritative definition and update every producer and consumer consistently.
- Remove obsolete assumptions, orchestration, and adapters when replacing them. Do not leave the old implementation underneath a new façade.
- Do not append transformation layers over incorrect definitions merely to avoid changing their consumers.
- Do not introduce compatibility machinery without discussing whether compatibility is actually required. Never silently reinterpret old bytecode with new semantics.
- Keep the change scoped to the approved design. Architectural cleanup does not authorize unrelated rewrites.
- Treat proposed, approved, implemented, and validated behavior as distinct states in both explanations and documentation.

## Preserve the ABC machine design

- A and B are symmetric operand stacks. For `.X`, X is the selected stack and Y its opposite: binary scalar operations compute **X0 op Y0**, consume both tops and place the result on X. In particular, `SUB.B` computes **B0 - A0**, not A0 - B0.
- Dynamic scalar operations must follow that same model, not a separate two-operands-on-A convention with internal repacking.
- Unary, literal, boxing, cast, and test forms operate on the selected stack under their declared layout contracts.
- C holds structured state and is accessed explicitly. Call argument gathering is a separate calling convention, not a reason to make scalar arithmetic A-only.
- Existing A-only dynamic scalar implementations are a known deviation to correct, not a compatibility invariant to preserve by default.
- One authoritative scalar computation owns checks, branches, representation decisions, errors, and composition of existing typed operations. Backends bind execution mechanisms; they must not independently implement scalar algorithms.
- Symbolic cache state is register allocation. Do not introduce a separate native residual-value IR, second allocator, or placement-reconstruction pass.
- Keep runtime execution independent of the build-time `abc-opt` pipeline.
- Allocation is an effect; “dynamic” is not an effect. Unknown types and version saturation are not excuses for opaque scalar execution fallbacks.
- Preserve explicit ABC continuations and separate frame transport from control transfer. Do not implement ABC recursion through recursive host execution.
- Preserve safepoint, root, trap, and stack-limit behavior unless a policy change has been explicitly discussed and approved.

## Validation and reporting

- Test the architectural contract as well as outputs: operand placement, both destinations, noncommutative operand order, untouched live values, and relevant effect boundaries.
- Passing tests alone does not establish architectural cleanliness or acceptable performance.
- Distinguish measured results from structural expectations. Report regressions, code growth, incomplete work, and untested paths plainly.
- Do not report a manifest edit, partial migration, or unvalidated change as a completed fix.
- Preserve existing user work and unrelated uncommitted changes.
- Do not use subagents or modify internal edit-plan sidecars unless the user explicitly requests it.
