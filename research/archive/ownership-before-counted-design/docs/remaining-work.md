# Remaining implementation work

The active detailed backlog is [frontend-completion-plan.md](frontend-completion-plan.md).
It supersedes this file's earlier dependency order and the older gap matrix.
The language contract remains `syntax.md`; `spec.md` is authoritative for the VM.

## Current baseline

Primary branch: `master`, retaining the restored fast implementation from `2356e7e`. Full validation
passes with 232 parser, 276 compiler, 100 lowering, 127 optimizer and 23 staging
checks, plus runtime suites. Test counts establish the supported subset, not
complete conformance.

Open-word methods and named-word runtime keyed supply are already implemented.
The audit also confirmed missing core inference/generic/result/capture semantics
and two accepted-but-broken dynamic conversions. See the detailed plan's probes.

## Ordered work packages

1. **F01:** Spec conformance matrix, broken-path containment and benchmark baseline.
2. **F02–F04:** Results/unit callables, inference/defaults and valid SLet captures.
3. **F05–F07:** Persistent VM staging, source binding time and type generics.
4. **F08–F10:** Structural/typed-callable conversions and complete word supply.
5. **F11–F12:** Module initialization/storage, imports/interfaces and export closure.
6. **F13–F15:** Deep borrow/managed proofs and managed/address-bearing sum ABIs.
7. **F16–F17:** Standard-module/program integration and staging diagnostics.
8. **F18:** Cross-mode conformance, performance and documentation closure.

The detailed plan supplies dependencies, checklists, implementation entry points
and acceptance criteria for each package. All packages are pending.

## Non-negotiable acceptance

- Work sequentially, without subagents; preserve the fast direct native pipeline.
- Execute represented source computation through verified ABC, never a Lua evaluator.
- Preserve effect order, traps, ownership, GC roots, ABI checks and deterministic output.
- Keep SLet borrowing distinct from Let managed ownership; do not ban valid captures.
- Require full validation, optimizer fixpoints and repeated performance comparisons.
- Portable C remains SLet-only; do not revive the archived compact-native refactor.
