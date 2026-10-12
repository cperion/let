# Revision-6 SLet execution tiers

Current-checkpoint comparison, **not** a before/after ISA regression claim or completion of the full refactor. Historical engine/baseline experiments are unchanged. All ABC inputs here go through the production SLet frontend and its ordinary `abc-opt` path.

## Results

Intel Core i7-1255U reported by WSL2/Hyper-V, logical CPU 0; Clang 20.1.2; LuaJIT 2.1.1703358377. C baselines use `-O3 -march=native`, no LTO. The VM is freshly built from frozen working-tree sources with normal `-O2 -g` flags; stencil generation retains its normal Makefile flags.

**Milliseconds per complete invocation; lower is better.** Each cell is the median of seven process medians, each from seven steady calls after one first/warm-up call.

| Workload | Input | Interpreter | Eager JIT | Lazy JIT | AOT C | Hand C | LJ off | LJ on |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| xorshift + counter | 5M | 112.724 | 8.911 | 8.871 | 7.606 | 7.647 | 307.269 | 9.429 |
| xorshift | 3M | 60.356 | 4.494 | 4.547 | 4.595 | 4.630 | 169.184 | 4.568 |
| branch | 3M | 73.300 | 3.762 | 4.101 | 1.795 | 3.625 | 136.297 | 14.412 |
| two xorshift lanes | 3M | 101.050 | 4.592 | 4.527 | 4.481 | 4.584 | 315.401 | 4.902 |
| multiply/accumulate | 3M | 49.469 | 3.002 | 3.035 | 2.623 | 1.028 | 75.760 | 12.251 |
| divide/remainder | 1M | 19.788 | 3.752 | 3.787 | 1.508 | 1.269 | 37.900 | 9.762 |
| shift/multiply mix | 2M | 40.104 | 3.239 | 3.188 | 2.705 | 2.620 | 69.475 | 9.297 |
| Fibonacci | 30 | 27.263 | 6.654 | 8.754 | 3.145 | 1.870 | 31.357 | 5.881 |

All results matched an independent Python oracle: **290 small/boundary-input preflight processes**, followed by **406 timed processes / 2,842 steady samples**, plus 406 first calls. Each runner also checks that repeated results remain unchanged. Preflight uses 0, 1, 2, 7 and 31 (10 for Fibonacci) without recompiling modules.

### What the measurements say

Ratios below are medians of *paired round ratios*, not divisions of the table medians.

- Eager beats the interpreter by **4.08–22.13×** across this corpus. The typed interpreter is faster than LuaJIT with JIT disabled on these eight algorithms; this is not a general language comparison.
- Eager is clearly faster than LuaJIT on branch (**0.261×** its time), multiply (**0.244×**), divide (**0.384×**) and mix (**0.348×**). Xorshift cases are close. Fibonacci's eager/LuaJIT ratio is **1.113×**, but its round range **0.916–1.263** crosses parity; do not claim a stable winner there.
- Eager is around handwritten C on skip, branch and two-lane xorshift, about **1.17×** on loop and **1.25×** on mix, but **2.92×** on multiply and **2.96×** on divide. Those remain substantial gaps.
- AOT C is close to handwritten C on loop, skip, sum2 and mix. It is **2.55× slower on multiply**, **1.19× slower on divide**, and **1.68× slower on ordinary Fibonacci**. Near-C performance is not universal.
- AOT C is **about twice as fast as this handwritten C branch implementation**. This is a code-generation result on this workload/host, not evidence that generated C generally beats good handwritten C.
- Lazy/eager differences mostly cross parity across rounds for the straight loops. Lazy is consistently slower on branch (**1.082×**) and Fibonacci (**1.314×**) in this run.

`run-01/summary.txt` and `summary.json` retain all round ranges. These ranges are descriptive min/max ranges, **not confidence intervals**. Host scheduling/frequency noise remains despite pinning; no governor, turbo, or hypervisor controls were changed. Fibonacci LuaJIT process medians ranged from 5.249 to 7.263 ms. No hardware-counter or profiler-based attribution was performed.

### Fibonacci and C control-flow optimization

| Fibonacci(30) | Eager | Lazy | AOT C | Hand C |
|---|---:|---:|---:|---:|
| ordinary build, ms | 6.654 | 8.754 | 3.145 | 1.870 |
| C with `-fno-optimize-sibling-calls`, ms | unchanged | unchanged | 3.218 | 3.139 |

No-TCO AOT/hand-C paired ratio: **1.033**, round range **0.967–1.090**. Thus the ordinary 1.68× AOT gap largely disappears in this control.

Saved disassembly shows the ordinary handwritten `fib` has one recursive call plus an accumulator loop. The ordinary generated `abc_aot_function_0` still has two recursive calls. Generated C declares that private function `uint64_t(uint64_t)`, versus handwritten `uint32_t(uint32_t)`; the SLet source itself declares `u32`. This is a structural lead concerning representation/proof propagation, not a demonstrated fix or complete causal attribution. Disabling sibling-call optimization is not a guarantee of otherwise identical machine instructions or inlining.

### Other code-generation observations

- Handwritten multiply is unrolled eight iterations with combined affine recurrences; generated C retains a single-iteration dependent loop. This is a concrete structural difference corresponding to the measured gap, not a proposed runtime workaround.
- Handwritten branch uses conditional moves in an unrolled loop; generated branch uses conditional jumps. The Collatz-style trajectory has a highly structured steady pattern, so this row must not be generalized to unpredictable branching.
- Native/AOT disassemblies are saved under `run-01/*.dis`; ABC disassembly and generated C are under `run-01/programs/`. No engine or source algorithm was tuned after seeing these results.

## Fixed costs and sizes

Medians of three external pipeline invocations, **including process launch**:

| Workload | SLet → optimized ABC ms | Emit C ms | Compile/link C ms | ABC bytes | Eager native bytes | Lazy native bytes |
|---|---:|---:|---:|---:|---:|---:|
| loop | 18.866 | 10.729 | 179.400 | 156 | 1102 | 399 |
| skip | 18.409 | 10.404 | 187.389 | 159 | 1074 | 390 |
| branch | 20.232 | 10.410 | 173.462 | 202 | 4025 | 1407 |
| sum2 | 19.805 | 11.382 | 172.339 | 199 | 2521 | 990 |
| mul | 20.382 | 11.873 | 175.212 | 154 | 963 | 410 |
| divide | 18.427 | 12.509 | 189.069 | 163 | 1381 | 619 |
| mix | 20.007 | 11.044 | 180.154 | 160 | 1023 | 439 |
| fib | 20.673 | 12.370 | 203.660 | 134 | 788 | 553 |

Read/verify medians span roughly **42–55 µs**. VM creation/load/prepare medians are **12–15 µs interpreted**, **45–89 µs eager**, and **31–35 µs lazy**. Filesystem caches are warm; these are not cold-disk costs. First calls are reported separately in the raw data and summary and **include the useful workload**, not just JIT compilation. Do not subtract a noisy steady median and call the remainder a precise lazy compilation cost.

AOT executable sizes are 16,688 bytes for the loops and 16,728 for Fibonacci. These include the export/measurement harness and binary metadata and are **not comparable** to JIT code-image bytes. `pipeline.json` also includes section sizes. Small code images alone are not evidence of speed.

## Method and scope

- Workloads derive from `../engines/run_bench.lua`, but each SLet entry is now `main(n: u32)`: input counts arrive at runtime in every tier. Seeds remain algorithm constants. This avoids benchmarking compile-time known complete inputs. The native and AOT runners read volatile input values between calls, preventing pure-kernel result reuse; AOT is compiled separately from its runner without LTO.
- The same frontend-produced module feeds interpreter, eager, lazy and C emission. C uses the shared semantic residual builder, not a separate source-language implementation.
- The handwritten C uses `uint32_t` state. Lua uses explicit bit operations/truncations and unsigned conversion before division to match wrapping-u32 semantics. There is no floating/dynamic-value workload disguised as a typed integer comparison.
- Every runner uses `CLOCK_MONOTONIC_RAW`. Kernel timing excludes startup, loading, preparation, emission and C compilation. Lua's first call permits normal trace warm-up; later calls use default LuaJIT settings. JIT on/off state is checked in every Lua result.
- Processes run serially pinned to allowed logical CPU 0. Workload and engine starting positions rotate across seven rounds. Seven-engine loop rows traverse a complete order rotation; Fibonacci has nine engines including its two controls, so its seven rotations are not a complete nine-position balance.
- Source correctness and performance are distinct. This is a scalar-integer/direct-call corpus: **no memory, float, foreign/indirect call, GC, dynamic, or allocation benchmark claims**. The repository's known legacy-fixture full-validation blocker is not resolved by this experiment.
- Historical fixed-input/old-ISA results and historical measurements on a different CPU/compiler are not used as regression baselines. This is not the final fixed old/new ISA comparison.

## Reproduce / evidence

From the repository root, with Clang 20 available at the supplied path:

```sh
python3 research/experiments/slet-tiers-r6/measure.py \
  --cc /tmp/clang20 --lua /tmp/lua-compat \
  --output /tmp/slet-tiers-new-run --rounds 7 --samples 7
```

The output path must not already exist. The script freezes the current dirty working-tree sources, builds from scratch in `OUTPUT/project`, generates SLet/ABC/C artifacts, checks correctness, then measures. It changes no runtime implementation or historical benchmark artifacts.

`run-01/` contains:

- `source.tar.gz`, `source-sha256.json`, `source-unchanged.json`: frozen sources, **202 source hashes**, and confirmation the original sources stayed unchanged throughout measurement;
- `harness/`: exact scripts/runners used;
- `host.json`, `build.log`, `commands.jsonl`, `run.log`: host, flags, fresh build and command evidence;
- `programs/`: generated SLet, optimized ABC, emitted C, executables and ABC listings;
- `preflight.json`, `expected.json`, `timings.jsonl`: validation and ordered raw samples;
- `pipeline.json`, `summary.{json,txt}`: separate costs, sizes and derived results;
- `artifact-sha256.json`, `inspection-sha256.json`: binaries/sources and post-run disassembly hashes.

The generated project/build tree and native executables are local reproducible artifacts; the source archive, runner snapshot, generated source inputs, raw measurements and hashes retain the evidence needed to reconstruct the run.
