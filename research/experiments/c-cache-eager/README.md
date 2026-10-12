# Fixed eager C top-three versus current state-aware caching

Experimental only. Main runtime files were not changed or promoted. Both variants were built in isolated detached worktrees from the same dirty revision-6 source snapshot:

- `/tmp/abc-eager-c.trOsXI/current`
- `/tmp/abc-eager-c.trOsXI/eager`

Frozen baseline source: `research/archive/c-cache-eager/current-source.tar.gz`. Apply `eager.patch` to that source to reproduce the candidate. Snapshot and artifact hashes are included here. This comparison is against the current revision-6 interpreter, not the historical pre-migration ISA baseline.

## Policy

Same three C registers, same A/B cache, no rotation. Candidate C0/C1/C2 have fixed register positions, csp is the logical end, and unused registers are dead at shallow depths. Scalar pops refill; bulk removal moves surviving cached values or refills the final window. Calls/tails gather argument bursts in memory and populate the final window once. C occupancy is absent from dispatch (15 A/B combinations versus the current 60 combined combinations).

Frame-block cells are cached too. The candidate conservatively publishes cached C homes before frame or potentially aliasing pointer reads/writes; after writes/copies and foreign effects it refreshes the window. Global-image accesses do not require this synchronization. Allocations publish old homes, zero the new block, and refill. This is a correct first candidate, not a claim of optimal frame-memory coherence code or optimal zero-allocation handling.

## Validation

Both fresh full runtime-library builds pass:

- 36 banked/call cases;
- 28 symbolic selected-bank contracts plus existing regressions;
- 120 interpreter/eager/lazy return checks;
- 16 mirrored interpreter assembly contracts.

All twelve benchmark/check modules match independent expected results in both interpreters, including an escaped caller frame block, partial-byte frame writes, overlapping frame copies and frame release. Logs are included. The old exact-occupancy cache validator was not applied to the different eager representation. This is focused experimental validation, not the full migration suite.

## Measurement

Clang 20, project `-O2 -g`, strict warnings, fresh generated handlers and runtime libraries. Same public-API timing runner and identical revision-6 modules; no frontend/optimizer dependency. CPU 0 affinity on the reported i7-1255U environment. Each workload has six counterbalanced pairs, one warmup and seven timed calls per process (42 samples per variant); workload order is seeded and shuffled each round. Reported times are pooled medians. Paired median ratio ranges are in `summary.txt`; individual timings, preparation and warmup values are in `timings.json`.

Hardware CPU counters were unavailable: `perf_event_open` for hardware cycles returned ENOENT. No instrumented refill counters were collected. Timing alone does not establish the microarchitectural cause. Frequency, thermal behavior and competing host activity were not controlled beyond affinity/counterbalanced ordering. Especially small differences and the shortest workloads should not be overinterpreted.

| Workload | Current ms | Eager ms | Eager/current |
| --- | ---: | ---: | ---: |
| Warm top reads | 21.437 | 22.992 | 1.073 |
| Top reads after call | 30.730 | 30.309 | 0.986 |
| Mixed reads after call | 30.348 | 33.095 | 1.091 |
| Deep reads after call | 29.277 | 30.570 | 1.044 |
| Top reads after frame free | 24.659 | 29.396 | 1.192 |
| A/B-only control | 7.941 | 7.974 | 1.004 |
| Fibonacci 28 | 9.997 | 11.445 | 1.145 |
| Frame-memory aliasing | 2.660 | 5.281 | 1.985 |
| Global memory | 5.708 | 5.905 | 1.034 |

The post-call-top difference is small and its paired range crosses parity. Eager caching does not establish a speed win here. Warm-cache, mixed-read, frame-free and recursive cases favor the current implementation; the coherence-heavy frame case is substantially worse in the eager candidate. These are results for this implementation and machine, not a proof that every eager design loses.

Code-size benefit is substantial: summed banked `.text` is 1,594,488 → 522,800 bytes (-67.2%); `.data.rel.ro` is 137,120 → 34,288 bytes (-75.0%). This excludes debug/unwind information and is not whole-runtime size.

**Decision: retain current state-aware caching.** A smaller handler footprint alone does not justify promoting the measured candidate. The simple latency simulation did not model interpreter dispatch/CPU overlap or the full maintenance/coherence costs; it was not a throughput prediction.

## Reproduce

Extract the archived current source into two directories; apply `eager.patch` in one. Build both:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' \
  build/libabc.a build/abc-runtime build/validate-banked-isa build/validate-symbolic
```

For each variant compile this directory's `run.c` with `-O2 -g`, its `include/` directory and its `build/libabc.a`, linking `-lm`; output `build/c-cache-bench`.

Create an experiment root with `current/`, `eager/`, and `programs/`, then:

```sh
luajit workloads.lua EXPERIMENT/programs EXPERIMENT/current
python3 measure.py EXPERIMENT 6
```

The archived snapshot predates these experiment scripts; use the scripts preserved in this directory. Native code generation was not changed by the candidate. Broader ISA migration/tooling work remains separate.
