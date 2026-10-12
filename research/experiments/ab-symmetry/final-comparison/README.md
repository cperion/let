# Fixed old/new migration comparison

This is the phase-5 comparison against the frozen phase-0 typed checkpoint, not
against another intermediate revision-6 build. No runtime tuning was performed.

## Identity and method

- Old executable/modules: `/tmp/abc-before-ab-symmetry.tdOxjk/performance/`.
  Their hashes and all four original workload source hashes still match
  `../baseline-artifact-checksums.txt`; see `sizes-and-integrity.txt`.
- New modules: same three SLet files and production compile/optimizer command as
  phase 0. The memory fixture changes only required revision-6 selected spellings
  (including the immediate branch's EXT encoding). Frozen sources are untouched.
- Runner source initially matched the phase-0 archive byte-for-byte. The current
  copy changes only the optional native-dump label loop from removed private
  `native->entry_count` to `m->function_count`. Timing, loading, warm-up, result
  handling and seven-trial median logic are unchanged. Dumping is disabled during
  measurements. This is an explicit private-API adaptation, not an identical-source
  claim for the final runner.
- Runner flags: `-O3 -march=native -std=c11 -Wall -Wextra -Wpedantic -Werror
  -Wno-newline-eof`; linked to each version's own runtime. Runtime builds use the
  normal Makefile `-O2 -g`; source/artifact hashes and object sizes are recorded.
- Current archive differs from the clean-validation archive in debug information:
  **all 18 debug-stripped objects are byte-identical**. See
  `clean-build-object-check.txt`; no stale executable object difference was found.
- CPU affinity: **CPU 0**, as in phase 0. Each process performs seven timed module
  reads, preparation, one warm-up/first call, then seven steady-state calls.
- **24 preflight processes**, then **six rotated rounds / 144 measured processes /
  1,008 timed steady-state calls**. Old/new order alternates within adjacent pairs.
  Every process succeeds and its final result matches the independent phase-0
  expectation. The unchanged runner reports only the final result, not an
  independent numerical assertion after each intermediate call.
- `raw.jsonl` preserves all process commands, statuses, stdout and stderr.
  `timings.csv` includes preflight rows with round -1; those are excluded from
  summaries. The runner exposes batch medians, not individual seven-call samples.
  `summary.json` and `phase-summary.txt` retain read/preparation/first-call times
  separately from steady-state medians and native byte counts.

## Steady-state results

Times below are medians of six batch medians. Ratios are median paired **new/old**
ratios with the six-pair range; greater than one means slower.

| Workload | Mode | Old ms | New ms | Paired ratio [min, max] |
| --- | --- | ---: | ---: | --- |
| loop | interpreted | 106.640 | 106.904 | 1.000 [0.986, 1.380] |
| loop | eager | 8.780 | 8.861 | 1.016 [0.968, 1.028] |
| loop | lazy | 8.887 | 8.750 | 0.986 [0.927, 1.006] |
| branch | interpreted | 71.832 | 72.259 | 1.004 [0.994, 1.040] |
| branch | eager | 3.508 | 3.571 | 1.003 [0.933, 1.036] |
| branch | lazy | 3.793 | 3.825 | 1.005 [0.985, 1.056] |
| fib | interpreted | 24.183 | 27.994 | **1.160 [1.149, 1.172]** |
| fib | eager | 6.603 | 6.826 | 1.050 [0.995, 1.092] |
| fib | lazy | 8.488 | 8.637 | 1.008 [0.968, 1.070] |
| memory | interpreted | 5.602 | 4.234 | **0.768 [0.707, 0.798]** |
| memory | eager | 1.612 | 1.632 | 1.021 [0.955, 1.206] |
| memory | lazy | 1.794 | 1.749 | 0.979 [0.896, 1.061] |

The interpreter Fibonacci regression is approximately **16%**, consistent across
these six pairs. The memory interpreter is approximately **23% faster** by the
paired median. Other ranges cross parity; there is no demonstrated general
speedup. In particular, eager Fibonacci's worse median is not a stable isolated
regression in this sample.

These are single-host observations, with affinity but no frequency isolation or
background-load control. The loop interpreter has a substantial outlier. This
comparison measures the migrated compiler/optimizer/runtime together, not an
isolated causal experiment on symmetry, quickening removal or one native change.
The historical phase-0 times remain available and were not overwritten; old
artifacts were rerun alongside current artifacts to reduce temporal confounding.

## Size and structural results

Module/code bytes, old → new:

| Workload | Module bytes | Code bytes |
| --- | --- | --- |
| loop | 134 → 136 | 60 → 62 |
| branch | 181 → 183 | 107 → 109 |
| fib | 135 → 135 | 45 → 45 |
| memory | 157 → 158 | 46 → 47 |

Banked-handler object text shrinks **2,375,520 → 2,008,368 bytes (15.5%)**;
its data grows **123,680 → 137,120 bytes (10.9%)**. These are object-section sizes,
not whole-executable resident memory measurements.

The runner reports emitted **body-region** bytes (`code_size`), excluding lazy
entry stubs, heap metadata and unused executable mapping capacity. This is the
same metric in both runners, not a total native-memory measurement.

| Workload | Eager body bytes old → new | Lazy body bytes old → new |
| --- | --- | --- |
| loop | 416 → 627 | 356 → 446 |
| branch | 1,631 → 1,818 | 1,191 → 1,172 |
| fib | 1,072 → 1,040 | 715 → 798 |
| memory | 264 → 450 | 227 → 324 |

**Native code growth is real**, especially loop and memory; fewer stencil families
or smaller handler text did not imply smaller per-program native realizations.

Separate `*-inspect.txt`, `*.bin` and `*.dis` files preserve eight additional
old/new Fibonacci/memory native inspections, outside the comparison samples.
The eager memory disassembly has three return/exit sequences where the old image
has two, a new initial home store/reload path, and larger continuation-aware
return sequences. Its eventual loop still alternates two register placements.
These observations identify contributors to code growth; they do not establish
its complete cause or justify changing allocation/continuation contracts.

The interpreter Fibonacci regression and the broader native-size growth remain
unfixed. No ABI/cache-policy experiment was adopted to hide either result.
Subsequent [investigation](../investigation/README.md) decomposes the memory
body-size growth and identifies call-transport/dead-argument leads for the
interpreter regression; it does not alter these measurements.

## Reproduction

From the project root, after building the normal current runtime/tooling:

```sh
out=research/experiments/ab-symmetry/final-comparison
/tmp/clang20 -O3 -march=native -std=c11 -Wall -Wextra -Wpedantic \
  -Werror -Wno-newline-eof -Iinclude -Isrc -Ibuild \
  "$out/runlet.c" build/libabc.a -lm -lpthread -o "$out/runlet"
for name in loop branch fib; do
  /tmp/lua-compat build/abc compile "$out/$name.slet" -o "$out/$name.abc"
done
/tmp/lua-compat build/abc asm "$out/memory.abcasm" -o "$out/memory.abc"
```

For another measurement, copy the runner source, `measure.py` and workload sources
into a **new output directory**, build there, then run its `measure.py`. It locates
new artifacts beside itself and opens raw result files exclusively to prevent
overwriting this evidence. Keep the frozen old directory unchanged.

This completes the fixed comparison measurement, not the whole migration audit,
performance acceptance, source partial evaluator or broader native redesign.
