# Earlier passing backend checkpoint — historical

After this checkpoint, broader frontend tests exposed a capacity-frontier bug.
It is now fixed; see [capacity-frontier/README.md](capacity-frontier/README.md)
for current validation and measurements. The logs and source archive below
predate that test expansion and correction (and the final help/reporting edits).
These original measurements are retained, not rewritten as post-fix evidence.

## Implementation

- One symbolic residualizer/allocator, parameterized for native eight or threaded
  seven value registers. Existing family/continuation threshold 16 is unchanged
  in meaning; it is now named `ABC_EXECUTION_VERSION_LIMIT` and used by both.
  Build-time tooling retains its separate threshold 8.
- `execution_emit.h`: labels, immediate operand packets and backend ownership.
  Native mappings, fixups, protection, lazy stubs and saved registers moved into
  `native_image.c`; byte relocation remains in `native_emit.c`.
- `threaded_emit.c` / `gen/threaded.lua`: final tape, 2,950 specialized handlers,
  byte offsets, explicit continuation transport and tail dispatch. Shared scalar
  expressions, float helpers/conversions and power computation; no second scalar
  execution algorithm, allocator or runtime optimizer dependency.
- Typed execution-image lifecycle, appended `ABC_EXEC_THREADED=3`, CLI
  `--jit=off|threaded|lazy|eager`, retained legacy aliases, staging mode selection.
  Threaded data is not forced into native low-address mappings.

See `../../../../docs/threaded-execution.md` for the exact ABI and record layouts.
No caller-owned regions, managed support, implicit promotion or default change.

## Validation

`four-mode-validation.log` is the full active build. `clean-validation.log` is
an independently extracted source-tree build with no preexisting build directory,
using the command:

```
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' all validate
```

Both pass:

- 113 independent oracle cases / 904 mirrored four-mode executions; 282 forms.
- 660 continuations; 168 returns, including nine-argument recursive A/B calls.
- 48 VM/module lifetime cases covering all mode pairs and cleanup orders.
- 280 staging-session checks; 27 staging checks; optimizer-disabled four-mode runs.
- 104 typed frontend executions, backedge placement, indirect-site observations,
  private-target rejection, foreign calls, errors and immutable-code checks.
- 4,230,894 native byte-emitter assertions; existing 2,400 poisoned-register
  interpreter handlers and 655 cache transitions (not threaded-handler coverage).
- New native/threaded backend test: forward labels across buffer growth, exact
  continuation record words, independent frame transport/control transfer,
  publication rejection/idempotence, packed capacity traps and unavailable forms.

`completed-backend.sha256`, `integrated-source.sha256`, and `clean-build-root.txt`
identify the sources/build. The archive is
`../../../archive/threaded-residual/integrated-backends-source.tar.gz`.
The generated native stencil C remains byte-identical to the original catalog
baseline. Current and pilot benchmark runners have byte-identical `.text`,
`.rodata` and `.data.rel.ro`; the final shared power-guard extraction did not alter
those sections (`final-pilot-code-equivalence.txt`). This is not a claim that
native host preparation or debug objects are unchanged from before integration.

## Short pilot, not performance acceptance

`runlet.c` checks the independently fixed result on **every** invocation. `measure.py`
uses identical revision-6 bytecode, CPU 0, four rotated workload/mode rounds,
one first call plus seven timed calls per process: 64 processes / 512 checked
calls, including 448 steady calls. Each batch reports its median; paired ratios
are computed per round, then summarized. Raw output is exclusive-created.

The table below uses **`rotated-final/`**. The first pilot accidentally canceled
mode rotation against workload rotation, leaving a fixed per-workload mode order.
Its raw files are retained at this directory's top level, but are superseded for
comparison. The corrected script asserts that every mode starts each workload
once. The final pilot uses the final-build runner.

| Workload | Off ms | Threaded ms | Lazy ms | Eager ms | Threaded/off median (range) |
| --- | ---: | ---: | ---: | ---: | ---: |
| loop | 106.384 | 46.881 | 8.289 | 8.022 | 0.439 (0.435–0.441) |
| branch | 69.881 | 32.294 | 6.651 | 2.344 | 0.463 (0.458–0.465) |
| Fibonacci | 26.086 | 32.852 | 8.633 | 5.560 | **1.256 (1.244–1.268)** |
| memory | 3.901 | 3.210 | 1.540 | 1.543 | 0.825 (0.818–0.827) |

Threaded Fibonacci regressed in every pair, beyond the roughly 10% tolerance.
Native remained fastest. No hardware-counter attribution or general speedup claim.

Median create/load preparation, microseconds (includes VM setup and image binding;
not an isolated emitter timer):

| Workload | Off | Threaded | Lazy | Eager |
| --- | ---: | ---: | ---: | ---: |
| loop | 16.06 | 40.07 | 31.00 | 54.09 |
| branch | 12.15 | 68.46 | 32.91 | 108.70 |
| Fibonacci | 13.67 | 36.95 | 42.26 | 57.14 |
| memory | 12.44 | 31.71 | 37.27 | 56.00 |

Module read, preparation and first-call timings are separate fields in the raw
and summary files. Lazy first-call time includes reached-context compilation.
The pilot does not isolate binding from residual preparation or control CPU frequency.

| Workload | Tape bytes | Retained tape capacity | Native eager/lazy body bytes |
| --- | ---: | ---: | ---: |
| loop | 1,424 | 2,048 | 581 / 404 |
| branch | 6,352 | 8,192 | 2,779 / 1,321 |
| Fibonacci | 1,784 | 2,048 | 1,024 / 789 |
| memory | 672 | 1,024 | 309 / 246 |

Native body sizes match the previous threshold-16 controls. They exclude lazy
stubs and metadata. Shared threaded object costs: **111,043 bytes text + 60,320
bytes form-table data + 61,480 bytes unwind data**, before alignment/debug info.
These are not per-module tape costs; omitting them would understate integration
footprint. Complete metadata, lazy-stub accounting, peak preparation memory,
whole-runtime sanitizers, exhaustive physical threaded-handler tests and broader
workloads remain outstanding.

Final measurements: `rotated-final/four-mode-raw.jsonl`,
`rotated-final/four-mode-summary.json/.txt`, `rotated-final/artifacts.sha256`.
Shared host/footprint information: `four-mode-host.txt`, `threaded-object-size.txt`.
The original pilot's raw files, summaries and hashes are retained at top level.
For another run, preserve these files and pass a fresh output directory and
runner path to `measure.py OUTPUT_DIRECTORY RUNNER`.
