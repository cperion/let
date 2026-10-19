# V04: real execution of ring-cache refill policies

**Decision: keep no eager refill, including on return.** The user confirmed this
V3 choice after reviewing the runtime results. This experiment supports that choice
for this interpreter; it does not prove a universal performance optimum.

This is a **native-coded baseline interpreter**, not a native JIT and not a complete
VM 3 implementation. It executes real programs with runtime branches, eight physical
ring registers and explicit VM continuations. It does not replay simulator traces.
The production VM and copied baseline sources are unchanged.

[VM 3 design](../../DESIGN.md) owns the topology;
[WORKLIST V04](../../../WORKLIST.md#v--vm-3-isolated-experiments) owns delivery status.
The earlier [traffic model](../refill/README.md) is separate evidence.

## Mechanism

`generate.py` emits x86-64 assembly handlers specialized by opcode and `(R,T)`.
There are 46 private operations and 72 possible ring states per policy. Registers
`r8`–`r15` are A's ring bank, `rbx` is scalar B, `rsi` is the instruction pointer
and `rbp` is the backing-stack pointer. Cache state is carried by handler identity,
not a runtime register-array lookup. Surviving cache registers do not shift.

Three independently entered versions share the same generator computations:

- **No eager refill** (`demand` in raw files): uncached reads access backing memory;
  pops, drops and returns never refill.
- **Eager:** after a completed instruction reduces A depth, fill all available
  cache slots from the surviving backing prefix.
- **Return-only:** perform that refill only after return/result transport.

There is no runtime policy selector inside a handler. Each refill policy uses
state-specific refill tails reached by a direct jump, followed by dispatch into
the resulting state. A refill tail checks available backing depth; it loads the
new deepest registers without shifting survivors. This implementation cost is
part of the measured policy. An alternative inlined or threshold-based refill
implementation could perform differently and was not tested.

Eager refill here means **actual earlier loads**, not CPU prefetch hints. It can
potentially change load latency and dispatch-target locality, but the experiment
does not directly measure either mechanism. Full pushes always store the displaced
cell; no dirty-bit tracking suppresses stores of recently refilled values.

### Private program contract

The experiment uses aligned 16-byte records (opcode and argument), not production
ABC bytecode. GET depths are specialized as GET0 through GET31. SET1 consumes the
source before addressing depth one; that private convention does not settle V3's
public SET encoding. Arithmetic is wrapping 64-bit integer arithmetic.

CALL leaves its one argument in place and pushes a continuation above it. The
continuation is an aligned record pointer with bit zero marking a B destination.
RET captures its result and continuation, removes one argument plus continuation,
and delivers the single result to A or B. Recursion uses the VM stack and explicit
jumps, never recursive host execution. Host `rsp` holds only outer ABI saves,
backing-base bookkeeping and, in the checked build, temporary validation snapshots.

These are intentionally narrow benchmark conventions, **not approved public VM 3
continuation or module ABIs**. No indirect/foreign calls, owning values, addressable
frame blocks, suspension, general result vectors or complete verifier are supplied.
Inputs are trusted generated programs. Guard pages surround backing storage;
production-style per-operation resource/error checking is not modeled.

## Validation and assembly inspection

`driver.c` contains an independent uncached C oracle that executes the program's
logical operations and explicit continuations. The `-DCHECKED` assembly build
calls it at every instruction entry, checking the complete logical stack,
continuation/control position and live B value against actual physical registers
and backing cells. Initial inactive registers are poisoned.

Each of the six builds passed 15,504 policy/case executions and 884,808 checked
instruction entries. Fixtures inject all 72 ring states with multiple backing
depths, exercise supported operations and both return destinations, and include
100 deterministic mixed programs. All four timed programs also pass the checker.

The timed object is assembled **without** the snapshot hook. `objdump` inspection
confirms zero host `call` instructions inside the interpreter and exactly three
outer host returns. There is no per-instruction timing/checking counter in it.
The driver's timing boundaries and batch checksums remain outside interpretation.
An uncached oracle computes instruction counts outside timed execution.

Per-policy text sizes (excluding dispatch tables, driver and checked binary):

| Policy | Bytes |
| --- | ---: |
| No eager refill | 110,063 |
| Eager | 115,439 |
| Return-only | 121,199 |

These totals are not hot instruction-cache footprints. For example, Fibonacci
actually visits 323 no-refill handlers, 100 eager handlers and 107 return-only
handlers. It visits 72, 16 and 23 `(R,T)` states respectively. Fewer visited
handlers did not make eager faster in these measurements.

## Workloads and measurement

- **fib20:** actual recursive Fibonacci(20), result 6,765; both A and B return
  destinations occur. Branches inspect runtime values.
- **expressions64:** 256 right-deep 64-term sums, combined through scalar B and
  accumulated in a local; result 532,480. This deliberately stresses deep
  expression storage, not an optimal scheduling claim for a source compiler.
- **locals12:** 12 surviving locals beneath temporary operands, repeated reads and
  accumulation, 64 loop iterations; result 33,792.
- **oscillation:** a 32-cell stack, 4,096 pop-to-B/push-from-B cycles with runtime
  countdown/branching, then cleanup; result zero.

These programs include real loop/control/accumulator operations and are not
instruction-for-instruction replicas of the earlier synthetic traffic traces.

Runs used Clang 18 on x86-64 Linux, on a virtualized host reporting an Intel
Core i7-1255U. Each process was pinned to permitted logical CPU 0. The driver warms
all policies, calibrates a common iteration count per workload to at least 30 ms
for the no-refill batch, and measures using `CLOCK_MONOTONIC_RAW`. Each sample's
three policies run in one of six balanced orders, repeated three times (18 samples
per policy/workload). Timing includes the outer interpreter entry/exit, amortized
across each complete program invocation.

All six permutations of policy text/table placement were built and measured to
expose address/layout sensitivity: 108 samples per policy/workload in total.
Core frequency and other host activity were not controlled. No hardware branch,
cache or TLB counters were collected; `perf` was unavailable. Quantiles and raw
samples are recorded, not promoted to a causal branch-prediction explanation.

## Results

Times below are microseconds per complete program: **median of the six layout
medians**, not a pooled confidence interval. The ratio range is the range of each
layout's median paired eager/no-refill sample ratios.

| Workload | No eager refill | Eager | Return-only | Eager / no-refill ratio range |
| --- | ---: | ---: | ---: | ---: |
| fib20 | 107.932 | 139.140 | 120.317 | 1.275–1.442 |
| expressions64 | 26.448 | 37.582 | 26.406 | 1.354–1.625 |
| locals12 | 18.579 | 30.246 | 18.421 | 1.360–1.709 |
| oscillation | 7.550 | 12.754 | 7.486 | 1.327–1.768 |

No eager refill beat eager in every tested placement/workload. For Fibonacci,
eager was approximately **28–44% slower**, and return-only was **9–13% slower**.

The three nonrecursive programs never execute RET, so no-refill and return-only
have the same refill behavior there. Yet their timings can differ substantially:
local-read paired ratios span 0.818–1.197, and oscillation 0.841–1.006. This is an
important layout/noise control, not a return-only policy benefit on those programs.
It prevents interpreting every small timing difference as a semantic-policy effect.
The six placements do not exhaust all possible handler layouts or machines.

This is stronger evidence than traffic counts alone, but it **does not establish**:

- a measured branch-prediction, cache-miss or prefetch explanation;
- superiority over every eager-refill algorithm;
- the performance of VM 3's future threaded/native residual execution;
- a speedup over a fresh, comparable current VM 2 build.

The existing VM binaries were older than the copied source snapshot and were not
used as a current-V2 performance baseline. No eager refill is the selected V3 rule;
there is no need to keep runtime policy switching in the actual implementation.

## Evidence and reproduction

[`runs/comparison.json`](runs/comparison.json) aggregates the six immutable run
folders `runs/n8-001` through `runs/n8-006`. Each contains:

- `samples.csv`: raw timings, sample/iteration counts and checksums;
- `summary.json`: medians, quartiles, extrema and paired ratios;
- `checked.log`: validation and actual visited-state/handler counts;
- `inspection.json`: text sizes and disassembly checks;
- `environment.json`: host/compiler metadata, flags and source/binary hashes;
- `build.log` and `source/`: exact commands and hashed experiment source snapshots.

The first run used the default placement. The runner then gained the explicit
placement-order option; its original sources are preserved in that run's snapshot.
No earlier measurements were overwritten. Generated assembly, binaries and full
disassembly are disposable output under ignored `build/`.

From the repository root (x86-64 Linux, Python 3, Clang, GNU objdump/nm):

```sh
python3 next/experiments/refill-native/run.py \
  --output next/experiments/refill-native/runs/n8-NEW \
  --order demand,eager,return_only
```

Use a new output path; existing evidence directories reject. `--order` controls
policy code placement, not the balanced measurement order. This experiment has
no dependency on the copied VM's currently blocked Lua/native build toolchain.
