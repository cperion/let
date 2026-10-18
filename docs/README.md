# Documentation

Each responsibility has one authority. Specifications describe intended contracts;
implementation and measured qualification are separate.

## Start here

- [WORKLIST](../WORKLIST.md) — the only live delivery ledger: IDs, dependencies,
  state, next actions and evidence. Do not reconstruct a backlog from old reports.
- [Architecture](architecture.md) — current components, execution boundaries and
  clearly labelled targets.
- [Implementation map](implementation-map.md) — files, consumers, tests and removals
  for the work IDs; proposed paths are not implemented components.
- [Designing and writing Let](designing-and-writing-let.md) — usage/style guidance,
  not a second grammar or implementation checklist.

## Language contracts

| Responsibility | Authority |
| --- | --- |
| Grammar, words/bindings, types, calls and modules | [Syntax](syntax.md) |
| Explicit Rc, borrowed Ref/Slice, cycles and owning library semantics | [Owners, references and ids](owners-references-ids.md) |
| Literal-led application, pending chains and receiver scopes | [Application sugar](application-sugar.md) |
| Supplies, packs, rest/templates, live vocabulary opening and import sugar | [Spread](spread.md) |
| Static operator protocols, trailing blocks and `endall` | [Operators and blocks](operators-and-blocks.md) |
| Structured groups, tasks, channels, select and cancellation | [Tasks](tasks.md) |
| Target library inventory, signatures and API gates | [Standard library](stdlib.md) |

The initial private Rc slice, ordinary application/opening and source-only packs
are implemented within current admission. General owning interfaces, static operator
protocols, containers/tasks and `.let`-only execution are not implied by that support.
Use WORKLIST for exact qualification, not repeated test counts in feature pages.

## Compiler contracts

- [Executable typed subset](slet-subset.md) — current source admission, distinct
  from the single-language target.
- [Source compilation and staging API](source-compilation-api.md) — host policy,
  checked programs, VM sessions, typed snapshots and loaded-image copying.
- [Source partial evaluation](source-partial-evaluation.md) and
  [virtual source contract](source-virtual-contract.md) — source knowledge/demand
  architecture and concrete metadata/application contracts; partially implemented.
- [Compiler continuations](compiler-continuations.md) — source control lowering,
  direct/tail calls and recursion without recursive host execution.
- [Tagged-value lowering](tagged-value-lowering.md) — packed layout and exact bitcasts.

## Machine and runtime contracts

- [Machine specification](spec.md), [symmetric ISA](symmetric-isa.md) and
  [module format](module-format.md) — semantics, encoding and loader/verifier boundaries.
- [Memory](memory-profile.md), [callables](callable-profile.md) and
  [foreign calls](foreign-profile.md) — active ABI contracts and explicit limits.
- [Dynamic profile](dynamic-profile.md) — collector-free target and encoding gates;
  not loadable old profile-5 compatibility.
- [Runtime interfaces](runtime-interfaces.md) — concrete ownership layouts/handoffs
  and source-checker boundaries, plus labelled target task/container protocols.
- [Runtime primitives](runtime-primitives.md) — selected algorithms, without duplicating
  interface layouts or retired catalogs.
- [Symbolic VM](symbolic-vm.md) and [threaded execution](threaded-execution.md) — shared
  execution computation, allocation and backend bindings.
- [ABC optimizer](abc-opt.md) — optional build-time rewriting, independent of execution.

## History, not active specifications

[REFACTOR](../REFACTOR.md) and `research/experiments/` preserve rationale and measured
results. [Retired documentation](../research/archive/docs-before-rc-consolidation/README.md)
contains old plans, conformance/implementation reports, migration proposals and the
unadopted four-lane design, with a destination map. Its status claims and relative
links belong to their recorded revisions. Archives/raw logs are immutable evidence,
not source code or fallback contracts.
