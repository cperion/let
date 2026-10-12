# Typed checkpoint before A/B symmetry migration

`source.tar.gz` preserves the actual dirty working tree, including untracked files, before the revision-6 implementation starts. `.git` and `build` are excluded. `head.txt`, `status.txt` and `tracked.patch` identify its relationship to Git; the patch alone omits untracked files and is not the complete snapshot.

Extract into a separate directory, not over active work. The matching build archive is `/tmp/abc-before-ab-symmetry.tdOxjk/build.tar.gz`. Checksums, fixed workloads, prior validation evidence and new baseline measurements are in `../../experiments/ab-symmetry/`.

This archive retains the old A-left/B-destination semantics and bytecode quickening. It is historical baseline evidence, not a second runtime or compatibility implementation.
