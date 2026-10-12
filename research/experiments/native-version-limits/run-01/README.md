# Native threshold control sweep — short pilot

**Subsequent decision:** the user selected 16 as the production native default.
The promotion preserves the existing policy and leaves tooling at 8. Active build
passes; its stripped native object exactly matches the full-suite-tested 16
variant. Regression caveats below remain. Statements about unchanged production
and no adoption below describe the experiment checkpoint before that decision.

User approved comparing the existing family/continuation policy at 8, 16 and 32,
not implementing a shared-PC or caller-owned-region budget. Production is unchanged.
After three clean full builds/validation runs passed, the user requested a faster
experiment turnaround. The measurement was therefore narrowed to a short pilot;
the planned full metadata/stub/peak-version accounting was **not completed**.

## Isolation and reproduction

Frozen source: `research/archive/native-version-limits/run-01-source.tar.gz`.
`build-root.txt` identifies the three isolated source/build directories.
`native-{8,16,32}.patch` changes only four native threshold checks via a local
constant. `src/symbolic.h`, optimizer/residual-builder policy and production files
are unchanged. `production-unchanged.txt` verifies production hashes.

All three fresh `all validate` runs pass; logs are retained. Build command:

```
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' all validate
```

Each runner is the unchanged `ab-symmetry/backedge-placement/runlet.c`, compiled
with Clang 20 `-O3 -march=native -std=c11 -Iinclude -Isrc -Ibuild`, linked to its
variant's `build/libabc.a`, `-lm -lpthread`. Hashes are retained. `quick.py` creates
three call-pressure modules, reuses four fixed bytecode benchmarks and executes
all native variants. Use a fresh evidence directory for another run; raw timing
output uses exclusive creation. The source archive contains no build products.

## Measurement

Seven workloads × two native modes × three thresholds × three rotated rounds:
**126 processes / 378 timed calls**, plus a first call in each process. CPU 0;
three timed calls per process; retained batch medians, preparation, load and first
call times. Every process succeeds and its final returned value matches an
independent expected result. The runner checks statuses on every invocation but
only reports/checks the final result vector. No hardware counters or isolated
frequency/background conditions. These are preliminary results, not a policy
acceptance study; tiny differences are not persuasive.

Paired median time relative to limit 8 (below 1 is faster):

| Workload/mode | 16 / 8 | 32 / 8 |
| --- | ---: | ---: |
| 32 call sites, eager | 0.963 | **0.620** |
| 32 call sites, lazy | 0.753 | **0.694** |
| nested 8×4 calls, eager | 0.864 | **0.604** |
| nested 8×4 calls, lazy | **1.110** | **0.773** |
| branch, eager | 0.712 | 0.853 |
| branch, lazy | **1.683** | **1.742** |

Call-heavy 32/8 ratios are below parity in every pair; branch-lazy ratios are
above parity in every pair. Fibonacci body sizes do not change and its paired
median ratios stay near parity. Loop/memory bodies likewise do not change;
timing variation on these controls cautions against interpreting small shifts.

Higher thresholds do not invariably grow bodies: 32-site eager code shrinks
2,003→1,619 bytes at 32; nested eager shrinks 2,294→2,113. Branch eager grows
1,790→2,779 and lazy grows 1,126→1,321 at both 16 and 32. These are **body bytes
only**, excluding stubs, metadata and unused mapping capacity. See raw/summary
files for all preparation/first-call medians, body sizes and ratio ranges.

## Conclusion and limits

The current thresholds create meaningful call-heavy cliffs; 32 helps these
constructed cases considerably. But simply increasing the knob is **not a general
win**: branch-lazy loses roughly 68–74%, and nested-lazy loses at 16. No default
change is adopted and no region-ownership claim follows. The source plan's
caller-owned regions are still a separate design, explicitly replacing the old
shared-helper budget model. Full footprint/peak-version accounting and broader
performance attribution remain unmeasured in this deliberately shortened pilot.
