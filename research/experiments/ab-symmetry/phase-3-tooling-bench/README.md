# Phase-3 tooling benchmark checkpoint

This is **not** the final old/new ISA or frontend comparison. It compares:

1. Frozen pre-tooling VM, original revision-6 modules (`baseline`).
2. Current VM, the identical original modules (`current`).
3. Current VM, current ABC optimizer output (`optimized`).

All nine benchmark modules come from `../../pre-tooling-vm/programs`. Only **fib28** changes under optimization; the other eight are unchanged-function/measurement controls, not optimizer coverage claims. Optimized modules are preserved here.

## Method and evidence

Same existing `pre-tooling-vm/run.c` runner; runtime Clang 20 `-O2 -g`, runner `-O3 -march=native`. Six workload-shuffled rounds, rotating mode and variant order so each occupies each position twice. CPU 0 affinity; one first/warmup call and seven timed calls per process. **486 processes, 3,402 timed calls, all expected results correct.**

The preserved pre-tooling baseline evidence was not overwritten. All native sizes were stable within each variant. The 37-file source check differs only for Makefile and the three build-time sources optimize/residual_builder/residual_c; runtime source is unchanged. The later call-graph-validator link correction changes Makefile only and does not affect measured binaries.

- `timings.json`: raw stdout/stderr, commands, every timing, expected result checks.
- `summary.txt`: pooled steady medians, ratios, native sizes.
- `components.txt`: separately summarized loading, preparation, first-call times, and range of per-process steady medians (milliseconds). Medians summarize each component independently; do not sum them as a measured end-to-end median.
- `source-check.json`, `artifact-sha256.json`: source/artifact identity at measurement time.
- `changed-modules.json`: exact original/output byte comparison.

No hardware counters collected. Affinity does not remove host/frequency/scheduling/layout variability. Some identical-module controls differ substantially; these timings are not evidence for a new runtime speedup. Absolute timings are also noticeably higher than the older checkpoint, including for the frozen baseline: do not interpret that cross-session difference as a code regression.

## Fibonacci 28: current original versus optimized

| Mode | Original ms | Optimized ms | Optimized/original | Native bytes original → optimized |
|---|---:|---:|---:|---:|
| Interpreted | 18.846 | 16.793 | 0.8911 | 0 → 0 |
| Eager native | 4.529 | 4.315 | 0.9528 | 732 → 707 |
| Lazy native | 6.386 | 6.495 | 1.0171 | 542 → 528 |

These are measured medians, **not established speed improvements**. Paired per-round ratios cross parity in every mode:

- interpreted: 0.8652, 1.1282, 0.8546, 0.8869, 0.9056, 1.0233;
- eager: 0.8714, 1.0322, 0.8945, 1.1225, 0.8787, 0.9278;
- lazy: 0.9366, 1.0554, 1.1449, 0.9880, 0.9852, 1.1519.

The lazy median is slightly worse, and remains slower than eager here; no cause or fix is claimed. Native byte reduction is structural evidence only. Baseline/current original modules emit identical native byte counts for every workload/mode. Their timing ratios range roughly 0.92–1.12, another caution against treating small deltas as improvements.

## Reproduction

From project root after building normal targets:

```sh
/tmp/clang20 -O3 -march=native -std=c11 -Wall -Wextra -Wpedantic \
 -Werror -Wno-newline-eof -Iinclude -Isrc -Ibuild \
 research/experiments/pre-tooling-vm/run.c build/libabc.a -lm -lpthread \
 -o /tmp/abc-phase3-normalization/bench
python3 research/experiments/ab-symmetry/measure-tooling.py \
 /tmp/abc-eager-c.trOsXI/current/build/pre-tooling-bench \
 /tmp/abc-phase3-normalization/bench build/abc-opt \
 research/experiments/pre-tooling-vm/programs /tmp/new-tooling-measurements
```

Use a new output directory to preserve these measurements. The frozen runtime source and its runner build instructions remain in `research/archive/c-cache-eager/current-source.tar.gz` and `research/experiments/pre-tooling-vm/README.md`. Component summaries use the median of each process's recorded read/prepare/first times; steady min/max use each process's recorded seven-call median. The full raw samples remain authoritative.
