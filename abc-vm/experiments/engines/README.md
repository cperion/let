# Current execution-tier benchmark

This suite compares four ABC execution paths with LuaJIT and a handwritten native baseline:

- the product VM interpreter;
- eager native residual stencils;
- lazy native residual stencils;
- portable C AOT emitted from semantic residue produced by the shared symbolic executor and compiled by Clang;
- LuaJIT with its JIT disabled and enabled;
- equivalent handwritten C compiled by Clang.

The inputs use programs accepted by the current scalar SLet frontend.

```sh
make -C ../.. all -j8
make
make check
```

The driver pins every child process to one allowed CPU. Set `TRIALS` to an odd number of at least three to override the default of nine.

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

Ryzen 7 PRO 8840HS, Clang 22.1.8, LuaJIT 2.1.1785763465, Linux x86-64. All processes were pinned to CPU 2. Absolute values vary with frequency and system load; ratios are generally more useful.

### Steady state

Median nanoseconds per iteration or recursive call; lower is better.

| benchmark | ABC interpreted | ABC eager | ABC lazy | ABC C AOT | LuaJIT off | LuaJIT | native C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `loop` | 14.479 | 1.476 | 1.484 | 1.264 | 49.319 | 1.562 | 1.262 |
| `skip` | 13.072 | 1.271 | 1.270 | 1.263 | 43.088 | 1.294 | 1.261 |
| `branch` | 15.805 | 1.153 | 1.926 | 0.752 | 36.636 | 3.563 | 0.719 |
| `sum2` | 24.242 | 1.365 | 1.493 | 1.265 | 79.919 | 1.317 | 1.263 |
| `mul` | 9.920 | 1.067 | 0.957 | 0.350 | 24.490 | 3.371 | 0.350 |
| `divide` | 11.443 | 2.983 | 2.861 | 1.059 | 39.215 | 7.410 | 1.060 |
| `mix` | 11.865 | 1.376 | 1.299 | 0.870 | 35.681 | 3.962 | 0.860 |
| `fib(30)` | 8.530 | 2.198 | 2.856 | 1.488 | 9.026 | 1.669 | 0.531 |

### Ratios

Each column is the left runtime divided by the right runtime. Values above 1 mean the left engine is slower. `I/E` is the interpreter-to-eager speedup.

| benchmark | eager / ABC C | ABC C / native C | eager / native C | lazy / eager | eager / LuaJIT | I/E speedup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `loop` | 1.17x | 1.00x | 1.17x | 1.01x | 0.94x | 9.81x |
| `skip` | 1.01x | 1.00x | 1.01x | 1.00x | 0.98x | 10.28x |
| `branch` | 1.53x | 1.05x | 1.60x | 1.67x | 0.32x | 13.71x |
| `sum2` | 1.08x | 1.00x | 1.08x | 1.09x | 1.04x | 17.76x |
| `mul` | 3.05x | 1.00x | 3.05x | 0.90x | 0.32x | 9.30x |
| `divide` | 2.82x | 1.00x | 2.82x | 0.96x | 0.40x | 3.84x |
| `mix` | 1.58x | 1.01x | 1.60x | 0.94x | 0.35x | 8.62x |
| `fib(30)` | 1.48x | 2.80x | 4.14x | 1.30x | 1.32x | 3.88x |

Generated C matches handwritten C within about 1% on six loop kernels and within 5% on `branch`. Recursive generated C is 2.80x slower than handwritten C, making call lowering the clearest C-backend gap. Eager native is within 17% of generated C on `loop`, within 8% on `sum2`, and effectively tied on `skip`; multiply and divide remain the clearest native instruction-selection gaps. Lazy activation has the same steady-state performance as eager on the straight-line loops, with additional path/version overhead on `branch` and recursive `fib`.

### VM fixed costs

| benchmark | frontend | module read | interpreted load | eager load | lazy load | lazy first-arrival premium | native image |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `loop` | 16.819 ms | 4.97 us | 15.10 us | 58.47 us | 35.16 us | 45.02 us | 357 B |
| `skip` | 16.260 ms | 5.39 us | 17.11 us | 54.84 us | 32.23 us | 85.91 us | 338 B |
| `branch` | 17.935 ms | 5.43 us | 15.74 us | 75.52 us | 32.73 us | 197.38 us | 1,194 B |
| `sum2` | 17.625 ms | 5.34 us | 14.58 us | 60.75 us | 34.77 us | 1,590.38 us | 557 B |
| `mul` | 15.986 ms | 5.00 us | 14.90 us | 51.87 us | 31.81 us | 37.59 us | 255 B |
| `divide` | 16.736 ms | 4.79 us | 14.70 us | 52.66 us | 41.86 us | 1,600.18 us | 431 B |
| `mix` | 16.604 ms | 5.01 us | 14.66 us | 53.91 us | 29.35 us | 32.54 us | 290 B |
| `fib` | 16.405 ms | 4.84 us | 14.83 us | 56.80 us | 33.17 us | 106.32 us | 1,021 B |

Eager load residualizes every load-time-reachable context. Lazy load installs activation stubs. The lazy first-arrival premium is first execution minus median steady execution, clamped to zero, so it is noisy when activation is small.

### Portable C pipeline costs

| benchmark | `abc c` emission | Clang compilation | executable |
| --- | ---: | ---: | ---: |
| `loop` | 13.963 ms | 77.707 ms | 13,200 B |
| `skip` | 14.112 ms | 78.121 ms | 13,200 B |
| `branch` | 13.623 ms | 77.285 ms | 13,200 B |
| `sum2` | 13.644 ms | 77.076 ms | 13,200 B |
| `mul` | 15.243 ms | 79.146 ms | 13,192 B |
| `divide` | 13.896 ms | 76.330 ms | 13,200 B |
| `mix` | 14.144 ms | 77.796 ms | 13,192 B |
| `fib` | 14.587 ms | 74.984 ms | 13,240 B |

## Caveats

- These are eight small scalar integer programs, not a general language benchmark suite.
- The scalar SLet frontend selects immediate arithmetic, C-operand, immediate-branch, and direct two-stack branch forms. It is not the full SLet partial evaluator and does not perform global stack scheduling.
- LuaJIT receives idiomatic Lua with explicit 32-bit bit operations. The handwritten C baseline uses equivalent loops. ABC C AOT is generated directly from validated residual IR.
- `fib` deliberately measures real recursion. The loop workloads use direct tail calls that become loops.
- Timings are medians from one pinned core, not confidence intervals. Repeat the suite before interpreting small differences.
- Portable C emission and native stencil generation optimize different machine-level concerns. Similar residual semantics do not imply similar code quality.
