# Current VM checkpoint before tooling migration

Requested before resuming phase-3 optimizer/residual-builder work. No runtime changes were made for this benchmark; current state-aware C caching is retained.

## Reproducibility and scope

The complete runtime library is the fresh `-O2 -g` Clang 20 build in `/tmp/abc-eager-c.trOsXI/current/build/libabc.a`. All 37 snapshot-listed runtime/header/generator/build/assembler source files still match the current checkout (`source-check.json`). Frozen source is `research/archive/c-cache-eager/current-source.tar.gz`; this is the current-policy snapshot, not the eager candidate.

`run.c` adapts the existing `research/experiments/engines/runlet.c`: uses module function count after removal of the private native entry-count field, checks every timed result, and retains all seven execution samples (sorted by the existing median function). Runner compilation:

```sh
base=/tmp/abc-eager-c.trOsXI/current
/tmp/clang20 -O3 -march=native -std=c11 -Wall -Wextra -Wpedantic \
  -Werror -Wno-newline-eof -I"$base/include" -I"$base/src" -I"$base/build" \
  research/experiments/pre-tooling-vm/run.c "$base/build/libabc.a" \
  -lm -lpthread -o "$base/build/pre-tooling-bench"
python3 research/experiments/pre-tooling-vm/measure.py \
  "$base/build/pre-tooling-bench" research/experiments/pre-tooling-vm/programs \
  research/experiments/pre-tooling-vm 6
```

Nine existing revision-6 workloads, identical modules in interpreted/eager/lazy modes. Six rounds with shuffled workload order and rotating mode order; each mode occupies each ordering position twice. CPU 0 affinity, one first/warmup call and seven steady-state calls per process: 42 timed calls per workload/mode. All 27 workload/mode combinations matched independent expected results; no compile or execution failures occurred.

Module loading, VM preparation, first call and steady-state timing are recorded separately. Lazy first-call time includes the compilation it triggers. Native bytes are collected after execution. Raw output and samples are in `timings.json`; round-median ranges are in `summary.txt`. Native byte counts were stable across rounds. Hardware counters were unavailable on this environment. Affinity does not eliminate frequency, host-scheduling or layout noise; sub-millisecond workloads and small differences warrant caution.

## Measured steady-state medians (milliseconds)

| Workload | Interpreter | Eager native | Lazy native | Eager/lazy bytes |
| --- | ---: | ---: | ---: | ---: |
| Warm top-C reads | 23.111 | 4.049 | 4.022 | 1326 / 1267 |
| Top reads after calls | 27.861 | 4.043 | 4.001 | 1436 / 1329 |
| Mixed reads after calls | 26.485 | 4.001 | 4.025 | 1436 / 1329 |
| Deep reads after calls | 26.685 | 4.038 | 4.032 | 1436 / 1329 |
| Top reads after frame free | 22.310 | 4.027 | 3.996 | 1970 / 1911 |
| A/B-only countdown | 7.749 | 0.448 | 0.501 | 134 / 134 |
| Fibonacci 28 | 10.252 | 2.552 | 3.364 | 732 / 542 |
| Frame-memory aliasing | 2.647 | 0.224 | 0.245 | 624 / 565 |
| Global memory | 4.037 | 1.689 | 1.687 | 333 / 270 |

Eager and lazy are close on most larger nonrecursive kernels. Fibonacci's lazy execution is about 32% slower than eager here, despite emitting fewer bytes. This is recorded, not fixed or explained by this benchmark.

## Limits

This is a **pre-tooling current-VM checkpoint**, not the phase-5 final comparison. Workloads are C-read-heavy microbenchmarks plus recursion/memory/control cases, not a representative application suite. The fixed old-ISA loop/branch/fib30/memory baseline has not been regenerated through the still-unmigrated frontend, so these numbers must not be presented as an old-versus-new ISA comparison or a near-C comparison.

The eager-C tangent used a different runner and execution schedule. Its paired current/eager measurements remain the evidence for that policy comparison; do not mix their absolute timings with this checkpoint's timings.

Next: resume optimizer/residual-builder and residual ABC/C consumer migration, preserving this source/workload/measurement checkpoint.
