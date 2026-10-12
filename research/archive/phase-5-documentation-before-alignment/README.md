# Documentation before the phase-5 contract alignment

These six files are verbatim snapshots taken before the documentation-only audit.
They preserve historical measurements, decision rationale and proposed behavior;
they are **not current runtime contracts**. Their relative links retain their
original `docs/` context and may not resolve from this archive directory.

`SHA256SUMS` identifies the original files. Current contracts and status are in
[`docs/spec.md`](../../../docs/spec.md), the symmetric ISA, module format and
`REFACTOR.md`. Stable decision numbers remain in the current specification.

The alignment removes claims of active quickening, old-format compatibility,
A-only call/foreign/memory behavior, active managed Let execution, fixed state-keyed
native stencils and completed source partial evaluation. It retains the intended
single per-location version budget while recording the implementation deviation;
it does not relax that contract to match current family-local accounting.

No runtime or generator file was changed by this documentation audit.
