# Production check-driven type versions

This integrates the mechanism tested on `experiment/check-cfg-versions`
(`ac3866f`), without merging its experiment switches or expanded ABC fixtures.
The pristine comparison is `master` at `d677f08`. Existing pending cache tests
and unused-register experiment notes were preserved.

## Implementation contract

- Original `DADD`–`DXOR` instructions expose a JIT-local semantic dispatch CFG.
  `src/dynamic.h` shares valid operand pairs, signedness and promotion with the
  concrete runtime. There are no new public opcodes or frontend expansions.
- A nonallocating classifier checks unknown operands. Typed successors refine
  live aliases and use existing versions. `u8`, `u16`, `u32` and `i32` arithmetic
  uses ordinary native stencils, including division, remainder, power and shifts.
  Wide and floating results retain the original arithmetic helper.
- Success postconditions are distinct from entry proofs. The invalid classifier
  arm calls the original helper for its exact error and terminates; inventing a
  successful continuation there exhausted eager version families.
- Scalar helpers retain facts while materializing roots. Known primitive tests
  fold. Adjacent `ANY_IS; JZ.A/JNZ.A` edges refine both outcomes. No persistent
  predicate identity is inferred through delayed tests, replacement or calls.
- Raw values stay in the native stack cache across compatible edges. No residual
  ID allocator, allocation reconstruction or universal IR was added.
- Real ABI boundaries encode raw values. New tests exposed and fixed missing
  encoding before real indirect-call argument publication.
- Tags do not prove payload normalization. Exact-tag casts preserve oversized
  payloads; different-tag numeric conversions remain checked. Raw identity
  casts can disappear, but a tag alone does not prove raw representation.
  A separate zero-extension fact prevents immediate unsigned boxing from
  truncating sign-extended negatives. Fused `ZX32` preserves that proof.
- The canonical ABC sink declines rewrites that would pass raw symbolic `any`
  through represented stores/call effects. Original verified functions survive
  instead of producing an invalid optimized module.
- Pure unit boxing becomes a constant. This matters for real frontend output,
  which introduces a unit local at recursive function entry.
- Edge-specific moves occur after branch selection. Proven store-only spills
  may precede it. Always adding local branch trampolines regressed the ordinary
  typed branch benchmark; the store-only proof restored its original code size
  and steady-state performance.
- Runtime archive order puts banked handlers before the native compiler. This
  isolates their link placement from native-emitter growth without changing
  handler instructions, register clearing or the ABI.

The banked interpreter, handler ABI, local eight-version limit, and direct
native emission architecture remain intact. There are 16 additional classifier/
decoder stencils: 5,859 total, 137,715 extracted code bytes, 5,071 tail jumps
removed (previously 5,843 / 136,083 / 5,055).

## Correctness

A clean `make -j4 validate` passed, including all frontend, optimizer, C AOT,
dynamic, cache, API, callable, root and GC suites.

`tools/validate_type_versions.lua`, integrated into `make validate`, checks
**21,711 executions** across interpreted, eager and lazy policies:

- all eight tested scalar operand types crossed with each other for all twelve
  numeric operations; floats and invalid bool/numeric pairs included;
- zero divisors, signed overflow, negative/oversized payloads, extreme operands,
  and shift counts at and above 64;
- exact same-program trap status, reason and byte offset;
- A/B/C aliases, twenty live copies, checked-slot replacement, delayed predicates,
  eight independent type decisions, loops and `SWITCH` under changing types;
- signed versus zero extension, direct casts and stored/reloaded boxed values;
- recursive real calls and both indirect result stacks plus indirect tails;
- optimized normalization/ABI cases and byte-identical optimizer fixpoints.

Symbolic unit checks cover fused binary/immediate/C-operand normalization,
positive/negative type folding, entry proof versus successful result facts,
and range versus representation requirements. Differential execution
is evidence against the concrete VM, not a claim of complete language conformance.

## Repeated performance comparison

Ryzen 7 PRO 8840HS, Linux x86-64, Clang 22.1.8. Runtime `-O2 -g`; harness
`-O3 -march=native`; CPU 0. Five alternating A/B-order rounds, each with one
warmup and five timed trials. Same verified ABC in both binaries. Reported
values are medians of round medians, **ns/add including loop overhead**.
Normal loops perform one million additions; heap-u64 performs 100,000 starting
at 2^63. Timing excludes preparation. The explicit-CFG side experiment used
different programs, so its absolute timings are not directly comparable.
CPU frequency was not fixed and changed substantially during the session.
Earlier runs reached 0.66 ns/add for the source loop; the final numbers below
come from the final binary and paired run, not that earlier frequency state.
`perf stat` also records whole-process cycles and instructions (including
preparation), independently of the harness's timed-call measurements.

| Case | Eager before | Eager after | Lazy before | Lazy after |
|---|---:|---:|---:|---:|
| u8 | 36.287 | 23.608 | 36.492 | 1.549 |
| u16 | 36.029 | 5.506 | 36.023 | 1.550 |
| u32 | 22.415 | 0.931 | 22.423 | 1.551 |
| i32 | 22.604 | 1.034 | 22.388 | 1.554 |
| u64 | 22.534 | 23.121 | 22.548 | 22.969 |
| i64 | 23.050 | 23.317 | 23.069 | 23.372 |
| f64 | 33.305 | 33.433 | 33.241 | 33.404 |
| heap-u64 | 40.920 | 40.494 | 40.542 | 41.029 |
| Let source, any accumulator | 34.562 | 0.934 | 34.517 | 1.864 |

The source case is compiled through the unchanged production frontend:

```let
let loop(n: u32, x: any): any = do
  if n == 0 then return x end
  return loop(n - 1, x + any(u32(1)))
end
let main(): u32 = u32(loop(1000000, any(u32(0))))
```

The final u32 eager round medians ranged 0.929–0.934 ns; baseline
22.299–23.044. Source eager ranged 0.928–0.936 versus 34.499–36.871.

Fallback is **not free**: this run measured up to 2.6% slowdown for wide/float
helper workloads, rather than the side experiment's roughly 2x penalty.
Interpreted dynamic cases ranged roughly 0% to +2.4%. No blanket non-regression
claim is made. Eager u8 still has a helper in its loop: preparing all possible
type arms consumes the existing version budget. Lazy u8 reaches a helper-free
cycle. No version limit was raised to hide this admission limitation.

Occupied eager image bytes: u32 899 → 2,604; source 2,617 → 4,904; u8
1,349 → 4,581. Lazy: u32 899 → 1,423; source 1,690 → 1,899; u8
1,349 → 1,907. Wide/float fallback image sizes are unchanged.

The existing eight typed engine workloads also passed cross-engine result
checks. A separate five-round paired comparison on their identical modules
retained **every eager and lazy image size**. Eager wall-time ratios ranged
0.999–1.057; lazy 0.996–1.002. Interpreter ratios ranged 0.926–1.007.
Whole-process cycle ratios were 0.997–1.030 eager, 0.998–1.001 lazy, and
0.930–1.008 interpreted. The eager branch outlier had overlapping round ranges
and **byte-identical emitted code** in a separate dump comparison; its measured
variation is reported rather than hidden.

### Interpreter link-placement gate

An intermediate final build regressed interpreted loop/branch/mix by roughly
19–24%, despite unchanged banked instructions. For mix, whole-process counts
were 3,948,500,597 versus 3,948,500,752 instructions, but 684,229,509 versus
835,307,409 cycles. Native-emitter growth had moved the handlers in the linked
harness. Reordering only the same archive members restored performance: a
five-round paired cycle comparison ranged 0.916–1.008 across all eight typed
workloads. The final full comparison above confirms the fix.

All eight rebuilt banked object files compared byte-for-byte equal to the
pristine archive. `gen/banked.lua` and `src/handler_abi.h` were not changed.
This establishes link-placement sensitivity, not a specific microarchitectural
cause or a guarantee for every embedding executable.

## Emitted-code and runtime inspection

`inspect.py` dumps native images and uses direct-branch cyclic regions as an
inspection aid, not a replacement for execution:

- u32 eager: baseline cycle 58 instructions / one call site; specialized cycle
  30 instructions / **zero calls**. Separate generic code remains.
- Let source eager: specialized cycles contain 32 instructions / **zero calls**
  and ordinary 32-bit addition, decrement and loop branches. No tag checks.
- u8 eager: its remaining cycle has 60 instructions / one call site.

GDB independently counts `vm_dynamic_native`, numeric classifier and decoder
entries. Across warmup plus three calls, both 200- and 1,000,000-iteration
programs record **(4, 4, 8)** entries respectively: 16 total, constant startup/
exit cost. This holds for u32 eager/lazy, source eager/lazy, and u8 lazy.
Lazy body dumps omit distant activation stubs, so their direct-branch graph
alone cannot establish complete cycles; the runtime counters cover that gap.

## Reproduce

Requirements: normal build dependencies, Python 3, GNU objdump, GDB, taskset;
the benchmark currently pins CPU 0. Hardware counters additionally require
`perf` and permission to access its events.

```sh
git worktree add --detach /tmp/abc-type-pristine d677f08
make -C /tmp/abc-type-pristine -j4 all
make -C /tmp/abc-type-pristine/research/experiments/engines runlet
BASE=/tmp/abc-type-pristine/research/experiments/engines/runlet

make clean && make -j4 validate
make -C research/experiments/engines runlet native
TRIALS=3 luajit research/experiments/engines/run_bench.lua
ABC_BENCH_PERF=1 python3 research/experiments/type-versions/run.py "$BASE"
python3 research/experiments/type-versions/inspect.py "$BASE"
```

`run.py` measures the eight ordinary engine fixtures too when present.
Omit `ABC_BENCH_PERF=1` to run without hardware counters. Generated fixtures,
JSON samples, dumps, assembly and GDB logs go to `build/type-version-bench/`.
The full validator retains its temporary directory on failure. Build artifacts
and `/tmp` session logs are disposable; the scripts reproduce the evidence.

Not implemented here: generalized predicate identities, aggregate/token
refinement, wide arithmetic without per-operation materialization, generic
semantic CFGs for every object/call operation, profile-driven eager admission,
or complete dynamic portable-C lowering. Existing frontend completion packages
remain separate work.

