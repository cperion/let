# Current execution-tier benchmark

This benchmark compares the product VM's interpreted, eager-JIT and lazy-JIT modes with LuaJIT's interpreter and tracing JIT, plus native C compiled by Clang. It uses programs accepted by the current scalar SLet frontend.

```sh
make -C ../.. -j8
make
make check
```

The driver pins every child process to one allowed CPU. Override `TRIALS` with an odd number of at least three. Nine is the default.

## Workloads

- `loop`: a dependency-chained xorshift loop with no non-tail call.
- `skip`: the same xorshift computation in a small `next32` word called on every iteration. ABC can use a virtual continuation here.
- `branch`: a branch-dependent integer step called on every iteration.
- `fib(30)`: naive recursive Fibonacci.

The first three report nanoseconds per loop iteration. Fibonacci reports nanoseconds per recursive function call. The benchmark performs no instruction/fuel accounting or budget bisection.

## Method

1. Generate each `.slet` source and compile it with `build/abc`.
2. Load the same verified module through the public API in interpreted, eager-JIT and lazy-JIT modes.
3. Warm each execution engine once, then report the median of nine internally timed runs.
4. Run equivalent Lua code under LuaJIT with its JIT enabled and disabled.
5. Run equivalent C built with `clang -O3 -march=native`.
6. Check every result modulo its declared integer width.

Execution timing excludes process start, module reading, verification, VM creation, and eager compilation. Those costs are reported separately. Let frontend time is end-to-end and therefore includes starting `build/abc` and writing the module.

## Results on this host

Ryzen 7 PRO 8840HS, Clang 22.1.8, LuaJIT 2.1.1785763465, Linux x86-64. Absolute values vary with frequency and system load; comparative ratios are more useful. The budget-free driver reports no work-counter column and performs no budget bisection.

### Steady state

| benchmark | ABC interpreted | ABC eager | ABC lazy | LuaJIT off | LuaJIT | C `-O3` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `loop` | 19.026 ns | 1.495 ns | 1.500 ns | 48.253 ns | 1.560 ns | 1.275 ns |
| `skip` | 44.607 ns | 1.288 ns | 1.930 ns | 43.492 ns | 1.293 ns | 1.278 ns |
| `branch` | 19.496 ns | 1.300 ns | 2.903 ns | 37.060 ns | 2.847 ns | 0.727 ns |
| `fib(30)` | 8.167 ns | 2.455 ns | 3.191 ns | 8.945 ns | 1.580 ns | 0.539 ns |

| benchmark | eager / C | eager / LuaJIT | interpreted / LuaJIT-off | interpreted-to-eager speedup |
| --- | ---: | ---: | ---: | ---: |
| `loop` | 1.17x | 0.96x | 0.39x | 12.72x |
| `skip` | 1.01x | 1.00x | 1.03x | 34.64x |
| `branch` | 1.79x | 0.46x | 0.53x | 15.00x |
| `fib(30)` | 4.56x | 1.55x | 0.91x | 3.33x |

### Fixed costs

| benchmark | Let frontend | module read | interpreted load | eager load | lazy load | lazy compile premium | lazy native bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `loop` | 9.447 ms | 7.87 us | 14.26 us | 84.66 us | 43.57 us | 75.16 us | 535 B |
| `skip` | 9.774 ms | 5.18 us | 26.78 us | 93.26 us | 33.29 us | 116.61 us | 590 B |
| `branch` | 9.539 ms | 7.96 us | 15.51 us | 137.09 us | 32.25 us | 114.44 us | 831 B |
| `fib` | 9.029 ms | 7.42 us | 14.56 us | 69.29 us | 32.02 us | 0.00 us | 1,092 B |

Eager load compiles every load-time-reachable version. Lazy load installs stable entry stubs only. The lazy compilation premium is the first execution minus median steady execution, so it is noisy when compilation is small.

## Caveats

- Four small integer programs are an initial overview, not a general language benchmark suite.
- The scalar SLet frontend now selects the spec's immediate arithmetic, C-operand, immediate-branch, and direct two-stack branch forms. It is still not the full SLet partial evaluator and does not perform global stack scheduling or eliminate every repeated binding load.
- LuaJIT receives idiomatic Lua functions with 32-bit bit operations. C receives equivalent loops rather than generated C from ABC; it represents a strong native baseline, not byte-for-byte equivalent lowering.
- `fib` deliberately measures real recursion. The other direct tail calls and small non-recursive calls can be virtualized.
- Timings are medians from one pinned core, not confidence intervals. Run the suite repeatedly before using small differences.
- The benchmark exposed and now guards residualizer issues around virtual continuations: inactive continuation storage, non-canonical generic homes, and a global callee-version test that incorrectly forced otherwise eligible calls back to the real ABI.

Earlier hardware-counter work reduced the straight `loop` to approximately 19 retired instructions and 2 branches per iteration. Native dumps confirm that the steady `skip` and `branch` loops retain their virtual continuations after context capping. Direct calls that cannot be virtualized use the VM's own C-stack continuation cell and native jumps rather than nesting the host C ABI. Recursive SCCs additionally share capped register-entry versions, so recursion is a cyclic CFG over run-time continuation records instead of compile-time unrolling; one-cell results return in the canonical result register. The recursive `fib` image contains no machine `call` instructions. Remaining general call work includes backward dead-stack liveness and canonical multi-result register returns.
