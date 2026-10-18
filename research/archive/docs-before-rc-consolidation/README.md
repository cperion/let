# Documentation before explicit-Rc consolidation

Frozen verbatim copies from `b7b74276`, before the A02 documentation cutover.
These are historical records, **not active contracts or current status**. Relative
links inside the snapshots retain their original repository context; use the
recorded revision to read them, rather than interpreting them as archive-local links.
Existing experiment archives and raw logs were not changed.

## Where the active responsibilities went

| Retired active page | Current authority / disposition |
| --- | --- |
| `remaining-work.md` | [WORKLIST](../../../WORKLIST.md), no parallel status index |
| `frontend-completion-plan.md` | WORKLIST S/O/C/D/U/T/P/W/L/X dependencies and acceptance; its escape-selected ownership design is superseded, not transferred |
| `frontend-gap-analysis.md` | Historical audit only; WORKLIST F owns current gaps |
| `four_lane_fork_v3.md` | Unadopted machine experiment, no active replacement |
| `actual-binding-access-conformance.md` | [Runtime interfaces §9](../../../docs/runtime-interfaces.md#9-source-analysis-interfaces) owns the surviving checker contract; WORKLIST S/O owns qualification |
| `staging-session-implementation.md` | [Source compilation API](../../../docs/source-compilation-api.md) owns the session contract; original experiment reports own historical results |
| `source-lifetime-lowering.md` | [Ownership](../../../docs/owners-references-ids.md) owns Rc/borrow semantics; [runtime interfaces](../../../docs/runtime-interfaces.md) own private layout/handoff; [implementation map](../../../docs/implementation-map.md) records removals |
| `module-image-copy.md` | Source compilation API, loaded-image copy and snapshot transport |
| `word-bindings.md` | [Syntax](../../../docs/syntax.md), [application](../../../docs/application-sugar.md), [spread](../../../docs/spread.md); architecture records the shared word elaborator |

`docs/runtime-interfaces.md` is also preserved here because its retired v3 catalog,
release-cache ABI and 48-byte header are removed from the active interface document.
Its task/container protocols remain in the active document unchanged. The obsolete
protocols must not be restored from this snapshot.

`snapshots.sha256` uses repository-relative paths. Verify with
`sha256sum -c research/archive/docs-before-rc-consolidation/snapshots.sha256`.
The consolidation changes documentation only; it is not fresh runtime qualification.

`validation.log` records the documentation checks: 262 local links/anchors, snapshot
identity/hashes, unchanged task protocol sections and the documentation-only diff.
Active `docs/` shrank from 38 to 29 pages and by 3,607 lines. No runtime tests were run.
Broader A02/F01 code-to-spec review remains open in WORKLIST.
