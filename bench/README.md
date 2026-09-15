# Let → C: GCC code-quality probes

Everything is driven by **LuaJIT**, with no Python dependency. Let supplies the
programs; a native C harness measures the compiled functions. Keeping the timed
loop in C avoids measuring Lua dispatch, FFI conversions, or LuaJIT trace behavior.

## Run

Requires Linux, LuaJIT, GCC, binutils (`nm`, `size`, `objdump`), and `taskset`.

```sh
luajit bench/run.lua
luajit bench/run.lua --samples 9 --seconds 0.04 --out bench/out-repeat
luajit bench/run.lua --opts O3 --native --out bench/out-native
luajit bench/run.lua --opts O3 --cflag=-fno-split-paths --out bench/out-no-split
```

The default uses baseline target flags, **not** `-march=native`. Native executables
are pinned to the first CPU in the process's allowed affinity mask; use `--cpu N`
to select another. The runner works from outside the repository as well.

- `kernels.let`: constant specialization, affine specialization, loop/tail sums,
  iterative/recursive Fibonacci, wrapping multiply-add, GCD, recursive preludes,
  and owned resources in loops/tail recursion.
- `reference.c`: corresponding handwritten C, with explicit unsigned wrapping
  and bit-preserving signed results on the measured two's-complement target.
  Reference tail recursion is written as loops, preserving bounded stack at `-O0`.
- `host.c`: a small shared handle pool, not a malloc benchmark.
- `driver.c`: correctness checks, resource accounting, calibration, native timing.
- `emit.lua`: invokes the Let compiler and records residual C emission statistics.
- `run.lua`: build, affinity, execution, statistics, and artifact reporting.

## Inspect the artifacts

The default directory is `bench/out/`:

| File | Contents |
|---|---|
| `generated.c` | Actual Let → C output, unmodified |
| `residual.csv` | Per-function C locals, labels, statement lines, calls |
| `let-O3.asm`, `c-O3.asm` | Native assembly and relocations |
| `let-O3.optimized` | GCC's optimized GIMPLE |
| `*.vectorization.txt` | GCC vectorization successes and failures |
| `timings.csv`, `O3.csv` | Raw native samples, repeat counts, checksums |
| `summary.md` | Readable median timing and entry-point size table |
| `summary.lua`, `metrics.lua`, `environment.lua` | Loadable Lua result tables |
| `bench-O0`, `bench-O2`, `bench-O3` | Standalone native benchmark executables |

```sh
objdump -d -Mintel --disassemble=let_sum_loop bench/out/let-O3.o
luajit -e 'local m=dofile("bench/out/metrics.lua"); print(m.builds["let-O3"].text_bytes)'
```

The runner now measures the explicit binding-time partial evaluator and direct C
printer. The earlier backend measurements below are historical.

## Method

Both implementations use the same GCC level. The driver and resource host are
separate translation units compiled at `-O2`; LTO is explicitly disabled. Each
kernel receives alternating runtime inputs `n` and `n+1`, and its results feed a
volatile checksum. Before timing, Let and C results are compared for negative,
zero, small, and representative inputs. Resource counts and balanced ownership
are also checked. Timing excludes compilation and performs no Lua/FFI calls.

Seven samples per implementation by default; implementation order alternates.
Each implementation calibrates its own repeat count to a minimum 20 ms batch.
Reports retain min/max samples as well as medians. Compilation timings include
process startup and are single observations, not statistically stable benchmarks.

These are small scalar/handle probes, not whole-application performance claims.
There are no array/memory-bandwidth, floating-point, string, or allocation-heavy
workloads yet. CPU boost and other system load are not controlled. Sub-nanosecond
differences between trivial functions are dominated by harness/code-layout effects.

## Current partial evaluator

```sh
luajit bench/run.lua --out bench/out-pe
luajit test/partial.lua
```

The intermediate lowering-based evaluator was deleted, not retained behind the
new interface. `domain.lua`, `state.lua`, `evaluate.lua`, and `specialize.lua` now
evaluate explicit known values, residual values, mutable places, ownership state,
and non-returning computations. `codegen.lua` only prints residual code.

The most important acceptance checks occur before GCC: static mutation and finite
loops become literal returns; invariant recursive arguments disappear from helper
ABIs; changing arguments generalize; and only differing initialization states need
runtime alive flags. Tests also cover return-state joins, memoized prelude effects,
escaped-memory invalidation, and known traps. Existing native behavior tests remain.

The first five-sample probe run emitted about 10.8 KB of C in 20 ms. Arithmetic
loops remained close to the handwritten `-O3` reference; tail/prelude reductions
still lagged that reference. This is not a claim of minimal residual C or universal
speed improvement. Inspect a fresh run rather than treating historical timings
as current results.

## Historical intermediate residual backend

The CBlock backend has been removed. The same programs, host, reference C, native
timing harness, and LuaJIT runner exercised that intermediate backend. Its run was:

```sh
luajit bench/run.lua --out bench/out-residual
```

The first seven-sample run reduced emitted C from **128 KB to about 12 KB**,
and emission time from approximately **77 ms to 20 ms**. Affine specialization
now emits one return expression and compiles to **six native bytes** versus the
old 26. Constant specialization is already a literal return before GCC runs.

| Kernel | Old Let O3 | Residual Let O3 | C O3 |
|---|---:|---:|---:|
| Sum loop | 4.35 µs | 2.17 µs | 2.17 µs |
| Iterative Fibonacci | 0.846 µs | 0.236 µs | 0.234 µs |
| Multiply-add | 12.71 µs | 8.62 µs | 8.59 µs |
| Tail sum | 4.31 µs | 2.16 µs | 1.11 µs |
| Recursive Fibonacci | 4.99 µs | 20.99 µs | 20.97 µs |

This removes the measured sign-reconstruction regressions in the arithmetic loops.
It is **not universally faster**: the recursive Fibonacci probe loses the old
backend's favorable GCC recursion/inlining shape, and some `-O0` loops are slower
because GCC leaves calls to the bit-reinterpretation helper. Tail/prelude reduction
code still needs investigation; matching C on those examples is not yet achieved.

`-O3` `.text*` for this run totals 2,662 bytes including native helpers, versus
2,152 for the old backend and 2,765 for the handwritten reference. More readable
C and less compiler machinery do not automatically imply smaller native code.

Keep using all optimization levels and inspect the raw samples. The old recommendation
to try `-fno-split-paths` was specific to the old reconstruction graph, not a new
backend requirement. Future work should target the remaining residual loops and
control regions, not reintroduce a generic register graph.

## Historical CBlock baseline

Measured with GCC **16.1.1**, x86-64 baseline flags, on an **AMD Ryzen 7 PRO 8840HS**,
pinned to CPU 0. The table below is from the LuaJIT runner's seven-sample run.
Figures are **microseconds per function call**, not per loop iteration:

| Kernel | Input n | Let O0 | Let O2 | Let O3 | C O3 |
|---|---:|---:|---:|---:|---:|
| Sum loop | 10000 | 19.50 | 2.16 | 4.35 | 2.15 |
| Sum tail | 10000 | 40.99 | 4.25 | 4.31 | 1.10 |
| Iterative Fibonacci | 1000 | 2.39 | 0.226 | 0.846 | 0.230 |
| Recursive Fibonacci | 22 | 287.91 | 5.33 | 4.99 | 20.02 |
| Wrapping multiply-add | 10000 | 30.46 | 9.65 | 12.71 | 8.46 |
| Prelude tail | 10000 | 38.83 | 2.15 | 2.15 | 1.09 |
| Resource loop | 1000 | 5.47 | 3.49 | 3.47 | 3.26 |
| Resource tail | 1000 | 10.01 | 3.82 | 3.58 | 3.80 |

### GCC already removes a lot

- Constant specialization becomes `mov eax, 42; ret`: six bytes, identical to the
  optimized C reference. The apparent timing difference is not meaningful evidence
  of a language advantage for identical machine bodies.
- `sum_loop` at `-O2` is a 29-byte scalar loop without stack slots.
- Recursive prelude/activation transport largely disappears. The prelude-tail
  probe improves approximately **18×** from `-O0` to `-O2`.
- Resource alive flags disappear from the inspected optimized loop/tail paths.
  Required acquire/read/release calls and their ordering remain. These examples
  are close to the corresponding external-call C baseline.
- Recursive Fibonacci gets a different inlining/recursion shape from the C
  reference and is faster here. This is one baseline implementation, not proof
  that Let generally beats C. Its helper code must be counted too.

The 1,530-line, 128,124-byte emitted C translation unit becomes 8,145 bytes of
`.text*` at `-O0`, 1,928 at `-O2`, and 2,152 at `-O3`. Emission took about 77 ms;
GCC compilation of the generated unit took about 46 / 113 / 125 ms respectively.

### O3 is not an automatic upgrade

`-O3` regresses the generated sum loop by roughly **2×** and iterative Fibonacci
by roughly **3.75×** versus `-O2`; the multiply-add loop regresses about **1.32×**.
The differences reproduced in repeated runs and have visible assembly causes.

The current lowering expands signed reconstruction into branches around unsigned
arithmetic. At `-O2`, GCC collapses more of this control flow. At `-O3`, sign tests,
extra paths, and conversions survive in several loop bodies. Disabling one pass
with `-O3 -fno-split-paths` restores the inspected sum/Fibonacci loops to their
`-O2` machine sizes and approximately their `-O2` timings:

| Kernel | O3 | O3, no split paths |
|---|---:|---:|
| Sum loop | 4.35 µs | 2.16 µs |
| Iterative Fibonacci | 0.846 µs | 0.225 µs |
| Multiply-add | 12.71 µs | 9.61 µs |

This is a diagnostic/tuning result for this compiler version, not a portable
guarantee. It does **not** fix the missed vectorization: the handwritten tail-sum
and prelude-tail reductions vectorize at `-O3`; their Let counterparts do not.
GCC reports unsupported uses/non-profitable vectorization in the generated CFG.

### Emitted C readability is currently poor

The flat control model is fine, but basic constants and arithmetic are far too
verbose. Even the specialized affine entry (`3*x+7`) has **285 virtual registers
and 15 blocks** before GCC, and **26 native bytes** afterward versus six for the
reference. Its optimized body retains redundant reconstruction instructions:

```asm
lea   rax, [rdi+rdi*2]
mov   rdx, -8
sub   rdx, rax
add   rax, 7
not   rdx
cmovs rax, rdx
ret
```

The reference is just `lea rax, [rdi+rdi*2+7]; ret`. Generated C also contains
very long repeated expressions reconstructing even small integer literals from
typed zero/chunk arithmetic. GCC folds the constants, but we still pay in graph
size, readability, and compilation work.

The wrapping semantics themselves do not require this overhead. A small standalone
C version of the range-safe conversion formula optimizes cleanly on this GCC.
The immediate problem is its expanded encoding and interaction with CFG passes.

## Priorities identified in the old baseline

1. **Exact typed integer constants in the CBlock boundary.** Preserve all 64 bits
   without routing each small literal through limb arithmetic and range branches.
2. **A canonical integer bit reinterpretation operation.** Consider a supported
   integer-to-integer bitcast (`memcpy`-based emission) rather than reconstructing
   signed values through a large branch graph. Do not use undefined signed overflow
   or weaken the existing integer-boundary tests.
3. **Re-run these probes after arithmetic lowering improves.** Check vectorization
   and emitted C size before building a separate optimizer.
4. **Only then investigate remaining loop/call shaping.** The ownership machinery
   is not the dominant overhead in these tested paths.

For that old output, `-O2` was the safer baseline. The direct backend above replaces
its arithmetic representation and supersedes this tuning recommendation. Full
optimization results remain target/version-specific.

