# Selective unused-handler-register clearing

## Decision

Do not adopt the tested selective-clearing policy. It passes validation and
reduces instruction count, but regresses important interpreter workloads.
`gen/banked.lua` and `src/handler_abi.h` remain unchanged from baseline `d677f08`.
Retain the poisoned-register regression tests in `tools/validate_cache.c`.

This experiment concerns the banked interpreter, not native JIT stencil emission.
It does not revive the abandoned compact-native lowering architecture.

## Why investigate

`B:forget_unused()` clears every handler argument outside the output cache state.
The interpreter ABI has four operand registers and three C registers, not eight
data registers. On this host Clang emits seven zeroing XORs for `ADD_A` in state
`(0,0,0)` and six in `(1,1,0)`. These are register writes, not memory stores.

By-value ABI arguments must contain defined values, but an unused cell need not
be zero for logical stack semantics. Entry values are initialized. Passing dead
arguments unchanged can remove those XORs. However, it also keeps their incoming
values compiler-live across scratch work and C helper calls.

In an initial isolated experiment, omitting final clearing for handlers without
`needs_run` changed these symbol sizes:

| Handler/state | Baseline | No final clearing |
| --- | ---: | ---: |
| ADD_A `(0,0,0)` | 48 B | 31 B |
| ADD_A `(1,1,0)` | 37 B | 22 B |
| SHL_A `(0,0,0)` | 73 B | 83 B |
| POW `(0,0,0)` | 65 B | 119 B |

Calls/returns/runtime boundaries have separate publication and register-pressure
concerns. Conservative GC can observe stale values, so logical-stack equivalence
alone does not establish identical retention behavior. Root hygiene should not
be conflated with the cost of every arithmetic dispatch.

## Tested policy

Keep every existing special call, return, foreign and dynamic path. In the final
ordinary-handler branch, forward unused arguments only for the following bases,
removing a terminal `_A` or `_B` before looking up the name:

```lua
local pass_unused = {
  PUSH8=true, PUSH32=true, PUSH64=true, DUP=true, DROP=true,
  COPY_AB=true, COPY_BA=true, MOVE_AB=true, MOVE_BA=true,
  CPUSH=true, CPOP=true, CGET0=true, CGET1=true, CSET0=true,
  ADD=true, SUB=true, MUL=true, AND=true, OR=true, XOR=true,
  ADDI=true, SUBI=true, MULI=true, ANDI=true, ORI=true, XORI=true,
  ADDC=true, SUBC=true, MULC=true, XORC=true,
  NEG=true, NOT=true, LNOT=true, ZX8=true, ZX16=true, ZX32=true,
  EQ=true, NE=true, LT=true, LE=true, LTU=true, LEU=true,
  FADD=true, FSUB=true, FMUL=true, FDIV=true, FLT=true, FLE=true, FEQ=true, FNEG=true,
}
-- Replace only the final ordinary-path b:forget_unused(); emit(b:finish()):
if not pass_unused[(opcode:gsub('_[AB]$',''))] then b:forget_unused() end
emit(b:finish())
```

The first full candidate also included SX32. Disassembly exposed its call to
`abc_i32_from_u64`, with substantial preservation overhead. The second candidate
above removed SX32 and is the one reported in the paired results below.
No policy change is retained in the production generator.

## Measurement

Host: AMD Ryzen 7 PRO 8840HS, Linux x86-64, Clang 22.1.8. Runtime handlers use
the normal `-O2 -g` build; the engine harness uses `-O3 -march=native`. Pin to CPU 0.

1. Run the normal engine suite with `TRIALS=7`; save its baseline `runlet` binary.
2. Build the candidate and run the same suite and exact-state cache tests.
3. Compare the saved baseline and candidate on identical `.abc` files, alternating
   A/B and B/A order for five rounds. Each process reports the median of five
   timed calls after warmup; report the median of those five process medians.
4. Check every A/B result for equality. Use normal loop/call unit counts from
   `run_bench.lua`, including 2,692,537 recursive calls for `fib(30)`.
5. Inspect symbol sizes and collect `perf stat` counters separately; do not infer
   runtime improvement from fewer instructions or smaller handlers.

Commands used for each individual comparison:

```sh
taskset -c 0 /tmp/abc-unused-baseline-runlet interpreted research/experiments/engines/mix.abc 5
taskset -c 0 research/experiments/engines/runlet interpreted research/experiments/engines/mix.abc 5
perf stat -e cycles,instructions,branches,branch-misses taskset -c 0 research/experiments/engines/runlet interpreted research/experiments/engines/mix.abc 5
```

Temporary binaries/logs are local scratch artifacts, not required project inputs.
The policy above and baseline revision make the experiment reproducible.

### Paired interpreter results (second candidate)

Median ns per iteration/call; positive change means slower.

| Benchmark | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| loop | 13.673 | 13.912 | +1.7% |
| skip | 12.662 | 13.142 | +3.8% |
| branch | 15.516 | 16.682 | +7.5% |
| sum2 | 23.833 | 24.353 | +2.2% |
| mul | 10.495 | 10.438 | -0.5% |
| divide | 12.736 | 11.556 | -9.3% |
| mix | 12.201 | 13.356 | +9.5% |
| fib | 8.451 | 8.279 | -2.0% |

For branch, baseline round medians ranged 15.493–15.988 ns and candidate medians
16.432–17.050 ns. For mix the ranges were 12.183–12.208 and 13.221–13.996 ns.
The first candidate also regressed these workloads, by roughly 16%. These are
single-host observations, not universal architectural conclusions.

Total `size` text-column bytes for the eight banked objects (including read-only
data) decreased from 2,504,904 to 2,474,968, about 1.2%. Native stencil object
SHA-256 remained unchanged; the first candidate's full engine suite retained
the same generated native image sizes and results.

Separate mix counter samples for five timed calls plus warmup/startup:

| Counter | Baseline | Second candidate |
| --- | ---: | ---: |
| User instructions | 3,948,500,267 | 3,216,500,079 |
| User cycles | 675,624,762 | 807,705,616 |
| User branches | 552,111,069 | 552,111,123 |
| User branch misses | 9,238 | 9,395 |

Instruction count falls about 18.5%, but the cycle samples increase. This rules
out treating the removed XOR count as a speedup estimate. It does not identify
a definitive cause: code layout, register pressure and dependency effects need
more targeted investigation before selecting another policy.

## Correctness coverage

- The second candidate passes full `make validate`, including dynamic/GC tests,
  all three execution modes, frontend suites and optimizer fixpoints.
- New direct-handler tests cover all 60 interpreter cache states, 15 arithmetic/
  stack operations and two nonzero dead-register patterns: 1,800 exact-state cases.
  Each starts with backing cells and compares all three published stacks with an
  independent logical-stack oracle. Coverage includes helper/scratch controls.
- The existing 655 public-call cache-transition fixtures now run twice with
  different poisoned register arrays, including the quickened repeat path.
- These tests establish tested stack behavior, not universal GC-retention proof.

The generator change was reverted because performance acceptance failed. A clean
rebuild and full validation also pass after the revert. The rebuilt engine
`runlet` executable and sampled banked object are byte-identical to their saved
baseline binaries; the native stencil object SHA-256 also matches.
Further work should isolate why fewer instructions took more cycles, not expand
the allowlist blindly or weaken correctness/performance gates.
