# Dynamic numeric benchmarks

The initial measurements below describe the helper-based implementation at
`4d3e1fd`. See [check-first lowering](check-first.md) for the replacement,
structural validation and paired before/after results.

Run both the original scalar suite and this suite:

```sh
make -C research/experiments/engines check
```

Or run only this suite:

```sh
make -C research/experiments/engines check-dynamic
# Optional: TRIALS=3 for a smoke run; default is nine.
```

`CC` selects the baseline compiler; `LUAJIT` selects the comparison interpreter.
Like the scalar suite, every child is pinned to the first allowed CPU. Each
engine warms once and reports the median of internally timed executions.

## What is measured

Every case has **typed and dynamic ABC implementations** with matching numeric
results and loop structure, run interpreted, eagerly compiled, and lazily
compiled. They are assembled and verified directly, **without `abc-opt`**. This
isolates runtime lowering from frontend and build-time optimization. It is not a
source-language benchmark. The typed modules use the memory profile; dynamic
modules use profile 5, explicit descriptors and a rooted `any` memory slot.

All integer cases run one million dependency-chained iterations:

```text
x = 12345
for i = 0 .. N-1:
    x = ((x XOR (x >> 7)) * 5 + i) AND 65535
return x
```

The shift/xor prevents the comparison from reducing to an affine recurrence.
Every value fits the declared widths for these iteration counts. The dynamic
loop uses DSHR, DXOR, DMUL, DADD and DAND. The typed counterpart uses ordinary
integer opcodes. Both normally normalize the counter with ZX32 before use; that
explicit fact matters to native boxing specialization.

| Case | Purpose |
| --- | --- |
| `u32-known` | Box the initial value locally; preserve type knowledge without an opaque entry load. |
| `u32-carried` | Obtain the initial boxed value from an opaque `any` load, then carry it around the loop. |
| `u32-checked` | Same as carried, plus ANY_IS u32 and an abort edge every iteration; tests check-driven specialization. The typed counterpart needs no type check. |
| `u32-unproven` | Same numeric values as carried, but omit counter ZX32 in both implementations. Exposes the cost of boxing a value whose u32 normalization is not explicitly established. |
| `u32-reload` | Store/reload the boxed accumulator through an opaque `any` slot every iteration; the typed counterpart also stores/reloads. Tests repeated loss of type facts. |
| `width-alternate` | Alternate u16/u32 boxing of the accumulator at the same memory-load/arithmetic site; decode the result to u32 between iterations. The typed counterpart retains the same branch and memory roundtrip without tags. |
| `f64-carried` | Opaque initial f64 load, then one million `x += 0.5` operations starting at 1. Return integer `2*x`; all operations are exactly representable. |

Initial values and memory slots are reset on every invocation. Typed and dynamic
results are checked against an independent numeric oracle for N=0,1,2,17,257
before timing. C and both LuaJIT modes are checked at those sizes too: **315
small-case comparisons**, plus every timed result.

LuaJIT and handwritten C implement the numeric algorithms, **not ABC's explicit
checks, memory barriers or tagged widths**. Lua numbers do not distinguish u16
from u32. These columns are algorithm baselines; use paired ABC columns to assess
the added dynamic representation/check/conversion work. The C runner prevents
interprocedural hoisting of timed invocations. No portable-C AOT column is shown:
that backend does not support this dynamic profile.

## First nine-trial run

Runtime baseline: `2da6b4c`; benchmark additions only, no runtime changes.
Intel i7-1255U, WSL2 x86-64, CPU 0, Ubuntu Clang 20.1.2,
LuaJIT 2.1.1703358377. Command:

```sh
make -C research/experiments/engines check CC=/tmp/clang20 LUA=luajit
```

`/tmp/clang20` is the locally extracted Clang toolchain wrapper described in
[continuation-primitives.md](continuation-primitives.md). The runtime retains
that report's build configuration and compatibility workarounds.

Median ns/iteration; T=typed, D=dynamic, I/E/L=interpreted/eager/lazy:

| case | T-I | D-I | T-E | D-E | T-L | D-L | LJ off | LuaJIT | C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| u32-known | 13.265 | 125.269 | 2.464 | 3.873 | 2.504 | 3.878 | 29.693 | 6.246 | 1.933 |
| u32-carried | 15.528 | 119.775 | 2.014 | 3.286 | 2.133 | 3.398 | 23.300 | 4.722 | 1.702 |
| u32-checked | 13.288 | 129.167 | 2.001 | 3.371 | 2.120 | 3.378 | 22.954 | 4.903 | 1.757 |
| u32-unproven | 12.569 | 115.562 | 1.995 | 18.967 | 2.081 | 19.482 | 23.923 | 4.686 | 1.736 |
| u32-reload | 16.393 | 121.150 | 3.362 | 20.173 | 3.399 | 20.376 | 22.913 | 4.788 | 1.710 |
| width-alternate | 18.372 | 152.819 | 3.639 | 30.177 | 3.812 | 32.325 | 36.138 | 6.136 | 1.742 |
| f64-carried | 13.180 | 41.337 | 2.167 | 27.472 | 1.923 | 32.161 | 3.605 | 0.639 | 0.638 |

### Interpretation

- Stable, normalized u32 values are relatively cheap in native code: **1.57–1.68x
  the paired typed cost**, and faster than the LuaJIT algorithm baseline here.
- The explicit u32 test has little steady-state penalty versus carried u32 in
  this run. Its eager body is also smaller (1,092 versus 3,974 bytes), consistent
  with a checked edge narrowing the reachable type versions.
- Cheapness depends on retained facts. Unproven normalization, opaque reloads,
  and alternating widths expose much larger overhead: **6–9.5x** the paired typed
  eager cost. They must not be hidden by reporting only a monomorphic case.
- Dynamic f64 is **12.68x** the typed eager cost. The current native numeric sink
  specializes narrow integers; runtime floating arithmetic still uses dynamic
  helpers. This is a distinct optimization opportunity, not evidence that all
  dynamic operations are cheap.
- Interpretation retains substantially more dynamic work; native results do not
  describe interpreter overhead.

These are observations from small numeric kernels, not a general dynamic-language
ranking. System load/frequency varied visibly across rows. Repeat before drawing
conclusions from small differences. These workloads do **not** measure aggregates,
allocation-heavy objects, word lookup, dynamic calls, GC pressure, or mixed
integer/floating arithmetic. Setup figures printed by the driver are single
VM-create/load observations, not medians; lazy body bytes exclude activation
stubs. No compilation-latency claim is made.
