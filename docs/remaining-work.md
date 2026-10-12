# Remaining implementation work

The active source target is [one collector-free Let](owners-references-ids.md).
Its dependency and acceptance plan is [frontend-completion-plan.md](frontend-completion-plan.md).
The prior SLet/GC work order and old test counts are preserved in the ownership
archive, not treated as current implementation status.

## Current baseline

Revision-6 typed profiles 1–4 execute under interpreted, threaded and native eager/
lazy policies. Typed `.slet` lowering and scalar VM staging sessions work; `.let`
dynamic lowering and profile-5 execution remain unavailable. Source virtual
values/places, demands, aggregate staging transport and the new owner model are
not completed by the existing scalar bridge. See `../REFACTOR.md` for measured
implementation checkpoints rather than fixed test counts here.

## Next design/implementation gates

1. Formalize actual-owner provenance, borrow independence, rank constraints and
   higher-order/recursive/separate-compilation summaries in the existing source model.
2. Specify counted root/environment placement, ABI, failure cleanup and iterative release.
3. Stable-slot stores and ids, with temporary element borrows and safe removal.
4. Immutable/COW list and string buffers, snapshots, boxes and freeze/move rules.
5. Transferable dynamic values and value tables; explicit encoding compatibility.
6. Independent capability facts and the approved `.let`-only migration: remove
   filename-selected profiles, retire `.slet` without an alias, and migrate imports,
   compiler APIs, CLI/build tools, active fixtures and runnable docs together.
7. Implement the approved structured-task/channel/select design: scoped capability
   summaries, parking/migration, cancellation/select races, atomic publication and
   foreign/shutdown protocols. Source semantics are in `tasks.md`; runtime remains
   unimplemented. Text-library edge cases remain separate work.
8. Whole-diff conformance, all execution modes, memory accounting and performance acceptance.

There is no tracing-collector package, GC ownership adapter or open-word engine to
restore. No collector may be substituted for an unresolved ownership proof.
Source memory ownership is distinct from deferred caller-owned execution regions.
Keep VM-only evaluation, the shared scalar computation and the existing allocator;
no second evaluator, runtime optimizer dependency or compatibility facade.
