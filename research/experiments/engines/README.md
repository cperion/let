# Current execution-tier benchmark

This suite compares four ABC execution paths with LuaJIT and a handwritten native baseline:

- the product VM interpreter;
- eager native residual stencils;
- lazy native residual stencils;
- portable C AOT emitted from semantic residue produced by the shared symbolic executor and compiled by Clang;
- LuaJIT with its JIT disabled and enabled;
- equivalent handwritten C compiled by Clang.

The inputs deliberately exercise the scalar-integer portion of the production SLet frontend.

```sh
make -C ../../.. all -j8
make
make check
```

The driver pins every child process to one allowed CPU. Set `TRIALS` to an odd number of at least three to override the default of nine.

Related experiment: [selective unused-handler-register clearing](unused-registers.md)
reduced instruction count but regressed important interpreter workloads; the
production clearing policy was retained.

## Workloads

| workload | iterations/calls | purpose |
| --- | ---: | --- |
| `loop` | 5,000,000 | dependency-chained xorshift with the counter mixed into the result |
| `skip` | 3,000,000 | dependency-chained xorshift state advancement |
| `branch` | 3,000,000 | data-dependent Collatz-style branch and accumulation |
| `sum2` | 3,000,000 | two independent xorshift lanes |
| `mul` | 3,000,000 | wrapping multiply/add and masking |
| `divide` | 1,000,000 | unsigned quotient and remainder work |
| `mix` | 2,000,000 | shift/xor, multiply and accumulation chain |
| `fib(30)` | 2,692,537 calls | naive recursive Fibonacci |

The seven loops report nanoseconds per iteration. Fibonacci reports nanoseconds per recursive function call. The suite performs no instruction/fuel accounting or budget bisection.

## Method

1. Generate each `.slet` input and compile it with `build/abc`.
2. Load the same verified module through the public API in interpreted, eager, and lazy modes.
3. Emit portable C with `abc c`, then compile it as strict C11 with `clang -O3 -march=native`.
4. Warm every execution engine once, then report the median of nine internally timed runs.
5. Run equivalent Lua under LuaJIT with its JIT enabled and disabled.
6. Run equivalent handwritten C built with `clang -O3 -march=native`.
7. Check every result modulo its declared integer width.

Steady-state execution excludes process startup, module reading, verification, VM creation, eager compilation, portable-C emission, and C compilation. Fixed costs are reported separately. Frontend and C pipeline timings include process launch.

## Results on this host

Ryzen 7 PRO 8840HS, Clang 22.1.8, LuaJIT 2.1.1785763465, Linux x86-64. All processes were pinned to CPU 0. Absolute values vary with frequency and system load; ratios are generally more useful.

### Steady state

Median nanoseconds per iteration or recursive call; lower is better.

| benchmark | ABC interpreted | ABC eager | ABC lazy | ABC C AOT | LuaJIT off | LuaJIT | native C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `loop` | 14.130 | 1.485 | 1.496 | 1.272 | 48.679 | 1.573 | 1.271 |
| `skip` | 13.305 | 1.284 | 1.286 | 1.272 | 43.999 | 1.298 | 1.265 |
| `branch` | 15.236 | 1.167 | 1.952 | 0.802 | 37.212 | 3.559 | 0.719 |
| `sum2` | 24.695 | 1.382 | 1.514 | 1.271 | 80.940 | 1.292 | 1.269 |
| `mul` | 10.123 | 1.069 | 0.971 | 0.373 | 24.834 | 3.372 | 0.351 |
| `divide` | 11.682 | 2.973 | 2.869 | 1.064 | 40.401 | 7.502 | 1.059 |
| `mix` | 12.122 | 1.390 | 1.307 | 0.874 | 34.804 | 3.973 | 0.861 |
| `fib(30)` | 8.445 | 2.236 | 2.912 | 0.534 | 9.109 | 1.640 | 0.536 |

### Ratios

Each column is the left runtime divided by the right runtime. Values above 1 mean the left engine is slower. `I/E` is the interpreter-to-eager speedup.

| benchmark | eager / ABC C | ABC C / native C | eager / native C | lazy / eager | eager / LuaJIT | I/E speedup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `loop` | 1.17x | 1.00x | 1.17x | 1.01x | 0.94x | 9.51x |
| `skip` | 1.01x | 1.01x | 1.01x | 1.00x | 0.99x | 10.37x |
| `branch` | 1.46x | 1.12x | 1.62x | 1.67x | 0.33x | 13.06x |
| `sum2` | 1.09x | 1.00x | 1.09x | 1.10x | 1.07x | 17.87x |
| `mul` | 2.86x | 1.06x | 3.05x | 0.91x | 0.32x | 9.47x |
| `divide` | 2.80x | 1.00x | 2.81x | 0.97x | 0.40x | 3.93x |
| `mix` | 1.59x | 1.02x | 1.61x | 0.94x | 0.35x | 8.72x |
| `fib(30)` | 4.19x | 1.00x | 4.17x | 1.30x | 1.36x | 3.78x |

Generated C is effectively tied with handwritten C on `loop`, `sum2`, `divide`, and recursive `fib`; `branch` and `mul` remain within about 10%. Internal `static inline` linkage, direct scalar calls, ordinary typed C locals, and whole-program `u32` call/result inference reduced recursive `fib` from 2.80x handwritten C to parity. The inferred `uint32_t` signature lets Clang convert the second recursive call into the same accumulator loop used for handwritten C. Eager native remains close to generated C on `loop`, `sum2`, and `skip`; multiply and divide remain the clearest native instruction-selection gaps.

### VM fixed costs

| benchmark | frontend | module read | interpreted load | eager load | lazy load | lazy first-arrival premium | native image |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `loop` | 17.272 ms | 5.02 us | 22.81 us | 54.71 us | 33.19 us | 0.00 us | 357 B |
| `skip` | 17.206 ms | 4.99 us | 15.46 us | 72.12 us | 46.31 us | 58.56 us | 338 B |
| `branch` | 18.782 ms | 5.24 us | 21.38 us | 77.34 us | 37.04 us | 127.77 us | 1,194 B |
| `sum2` | 19.213 ms | 5.32 us | 21.43 us | 64.46 us | 37.70 us | 63.36 us | 557 B |
| `mul` | 17.216 ms | 5.21 us | 21.98 us | 67.51 us | 44.34 us | 38.37 us | 255 B |
| `divide` | 17.551 ms | 7.94 us | 21.53 us | 57.07 us | 43.61 us | 366.20 us | 431 B |
| `mix` | 17.516 ms | 5.07 us | 21.04 us | 55.71 us | 43.25 us | 382.24 us | 290 B |
| `fib` | 16.562 ms | 4.89 us | 15.07 us | 57.23 us | 42.51 us | 76.98 us | 1,021 B |

Eager load residualizes every load-time-reachable context. Lazy load installs activation stubs. The lazy first-arrival premium is first execution minus median steady execution, clamped to zero, so it is noisy when activation is small.

### Portable C pipeline costs

| benchmark | `abc c` emission | Clang compilation | executable |
| --- | ---: | ---: | ---: |
| `loop` | 15.924 ms | 77.164 ms | 13,152 B |
| `skip` | 15.123 ms | 74.770 ms | 13,152 B |
| `branch` | 15.970 ms | 77.832 ms | 13,152 B |
| `sum2` | 15.568 ms | 76.517 ms | 13,152 B |
| `mul` | 16.256 ms | 76.964 ms | 13,152 B |
| `divide` | 15.983 ms | 76.993 ms | 13,152 B |
| `mix` | 17.263 ms | 79.405 ms | 13,152 B |
| `fib` | 14.993 ms | 75.471 ms | 13,192 B |

## Caveats

- These are eight small scalar integer programs, not a general language benchmark suite.
- Frontend lowering for these scalar inputs selects immediate arithmetic, C-operand, immediate-branch, and direct two-stack branch forms. The benchmark does not exercise the full production source surface or perform global stack scheduling.
- LuaJIT receives idiomatic Lua with explicit 32-bit bit operations. The handwritten C baseline uses equivalent loops. ABC C AOT is generated from validated semantic residue produced by the shared symbolic executor.
- `fib` deliberately measures real recursion. The loop workloads use direct tail calls that become loops.
- Timings are medians from one pinned core, not confidence intervals. Repeat the suite before interpreting small differences.
- Portable C emission and native stencil generation optimize different machine-level concerns. Similar residual semantics do not imply similar code quality.
