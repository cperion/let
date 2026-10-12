# Before collector-free ownership alignment

These documents preserve the preceding syntax/GC/source-profile design and frontend
backlog, including historical measurements and unresolved paths. They are not an
alternative active ownership specification.

Current authority: `../../../docs/owners-references-ids.md`, with the aligned syntax,
dynamic target and frontend completion plan. The approved replacement has one Let
language, implicit owners, independently proved borrows, actual-owner acyclicity
constraints, immutable value DAGs, stores/ids and no collector.

Runtime behavior was not changed by this documentation migration. The current typed
`.slet` path and `.let` dynamic-lowering rejection remain until implementation and
validation. `sources.sha256` identifies the original core document snapshots; later
added historical frontend plan/gap/API snapshots are preserved alongside them.
