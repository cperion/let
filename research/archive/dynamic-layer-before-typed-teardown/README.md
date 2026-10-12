# Dynamic layer before the typed-only teardown

This is an excluded historical snapshot, not an implementation to restore beneath the replacement.

The user approved removing the dynamic implementation and returning to the existing typed ABC base. The scalar EXT contract incorrectly consumed operands on A alone instead of following the A/B machine design. Further refactoring had accumulated representation, dispatch, and backend coupling around that mistake.

`snapshot/` preserves the actual working files before teardown, including uncommitted and untracked scalar work, frontend lowering, tests, documentation, and object/GC machinery. `pre-teardown-tracked.patch` and `pre-teardown-status.txt` record the tracked delta and working-tree status relative to HEAD `e723f1e8f42043a10672afa1251f9cf8cf62c3d5`.

The snapshot is not part of any build or test discovery. Its tests and semantic rules are historical evidence for the replacement, not proof that the archived architecture is correct. Its documentation describes the former implementation.

Existing measurements remain under `research/experiments/engines/`; those dynamic measurements do not describe the typed-only checkpoint.
