# A/B symmetry migration: typed baseline

Status: phase 0 captured before any revision-6 runtime implementation. The workloads and logs here are migration evidence, not a new benchmark framework.

## Preserved checkpoint

- HEAD: see `../../archive/typed-before-ab-symmetry/head.txt`. HEAD alone does not represent the dirty typed checkpoint.
- Exact source snapshot, including untracked source and existing research: `../../archive/typed-before-ab-symmetry/source.tar.gz`.
- Original status and binary tracked diff: beside that archive.
- Original build snapshot and benchmark executables/modules: `/tmp/abc-before-ab-symmetry.tdOxjk/` (`build.tar.gz`, `performance/`). Build artifacts are not checked into the repository.
- Snapshot SHA-256: `checkpoint-checksums.txt`. The repository copy of source.tar.gz has the same hash as the named temporary copy.
- The snapshot predates creation of this evidence directory. Frozen benchmark source copies also reside in the checkpoint's `performance/` directory.

The source archive excludes `.git` and `build`; the separate build archive preserves the latter. It must be extracted into a separate directory, never over the active tree.

## Existing validation evidence

`typed-validation.log` is a copy of `/tmp/typed-split-validate.log`, the previously successful complete active suite. This was **not** rerun as part of baseline capture and is not evidence for the new ISA.

The recorded command was:

```sh
make LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

Compiler/host details: `baseline-host.txt`. Source/build identity: `baseline-status.txt`, snapshot checksums and `baseline-artifact-checksums.txt`.

## Fixed performance set

| Workload | Coverage | Size | Expected result |
| --- | --- | --- | --- |
| loop.slet | u32 arithmetic, shifts, normalization, tail loop | 5,000,000 iterations | 3180325737 |
| branch.slet | branches and a small direct helper | 3,000,000 iterations | 7015924 |
| fib.slet | non-tail recursive calls/returns | fib(30), 2,692,537 source invocations | 832040 |
| memory.abcasm | writable-image load/store and immediate-branch loop | 1,000,000 iterations | 1000000 |

The SLet sources are fixed instances of existing workloads in `../engines/run_bench.lua`. The memory workload resets its image cell at each invocation so repeated measurements return the same result. It deliberately uses a branch-immediate form whose revision-6 EXT cost must not be assumed free. It is old-ISA assembly and will need the explicit bank spellings when regenerated for revision 6; retain the frozen original for comparison.

The existing `../engines/runlet.c` measures all three runtime modes. There is one warmup/first call followed by seven timed calls, CPU affinity fixed to CPU 0, with median steady-state time. Read time is a median; preparation and first-call times are single observations, not medians. Native byte counts are captured after execution. No machine-noise controls beyond affinity were imposed; small differences need follow-up rather than performance claims.

`baseline-results.txt` contains all twelve workload/mode observations. Results agree across modes and with the three existing handwritten native references in `native-result-check.txt`; the memory result equals its iteration count. Native reference timings were used only as a result sanity check, not a performance comparison.

### Commands

Run from the project root. Use the build-directory tooling, whose runtime lives alongside it:

```sh
checkpoint=/tmp/abc-before-ab-symmetry.tdOxjk
output="$checkpoint/performance"

/tmp/clang20 -O3 -march=native -std=c11 -Wall -Wextra -Wpedantic \
  -Werror -Wno-newline-eof -Iinclude -Isrc -Ibuild \
  research/experiments/engines/runlet.c build/libabc.a -lm -lpthread \
  -o "$output/runlet"

for workload in loop branch fib; do
  luajit build/abc compile research/experiments/ab-symmetry/$workload.slet \
    -o "$output/$workload.abc"
done
luajit build/abc asm research/experiments/ab-symmetry/memory.abcasm \
  -o "$output/memory.abc"

for workload in loop branch fib memory; do
  for mode in interpreted compiled lazy; do
    taskset -c 0 "$output/runlet" "$mode" "$output/$workload.abc" 7
  done
done
size build/libabc.a
```

For final measurements, use a **different output directory**, regenerate revision-6 modules with the migrated producers, and relink the same runner source against the new library. Never overwrite the baseline modules/binary or pass old modules to the new runtime. Keep workload sizes, compiler flags, affinity and sample counts unchanged. Compare module bytes, banked handler text, native bytes, preparation/first-arrival and steady-state timings separately.

An initial attempt to invoke `tools/abc` directly stopped before compilation because its sibling runtime was absent. It was corrected to `build/abc`; no runtime source or build regeneration was needed.
