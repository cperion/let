# Shared check-first scalar execution

Baseline: `4d3e1fd`, preserved in `research/archive/scalar-helpers-4d3e1fd/`.
The rejected native-only implementation and its earlier measurements are in
`research/archive/native-only-scalar-wip/`. The results below measure the shared
refactor, not that implementation.

## Execution, not a second scalar engine

`gen/semantics.lua` defines typed arithmetic, normalization, unary and conversion
recipes. `gen/scalar.lua` generates their concrete operations and ordinary
symbolic-ABC compositions. Promotion, literal adoption and equality rules live
in `src/scalar_rules.h`; representation primitives live in `src/any_repr.h`.

- `gen/scalar_banked.lua` wires those operations into the existing banked cache.
  Scalar EXT instructions no longer flush the cache and enter `vm_dynamic`.
  Pending collection and actual allocation publish roots on their effect edges;
  the nonmoving collector leaves cached values valid.
- `src/symbolic_scalar.inc` executes the same recipes symbolically. Known checks
  fold; unknown tags produce refined branches. Selected arms execute ordinary
  symbolic binary/unary/conversion/check operations, with original-PC errors.
- `src/native_scalar.inc` handles representation placement and binds branch
  arms to that shared execution. It no longer implements arithmetic, literal
  evaluation or numeric conversions. The native sink emits directly from the
  register-bearing symbolic context; there is no new IR or allocator.
- `src/dynamic.c` no longer executes scalar opcodes. It retains object/call
  effects and the allocation-only `vm_scalar_allocate`, used by both engines.
  Scalar handlers, classifier/decoder calls and the unused residual adapter
  have been removed, rather than retained as fallbacks.

Boxing preserves bits, including oversized narrow payloads. Arithmetic and
conversions apply their own normalization rules. Native wide values remain raw
across compatible edges and spills; represented escapes check immediate fit
before allocating. The interpreter stores canonical dynamic cells and can
therefore allocate where native execution retains raw bits. Floats do not box.
Version saturation uses existing edge conformance, not a scalar handler.
Object construction and dynamic calls remain runtime boundaries. Collector
membership checks before object dereferences are nonallocating representation
checks, not another language-operation dispatcher. Runtime never invokes
`abc-opt`.

## Validation

Full `make validate` passed: 32,856 type-version executions, 234 continuation
executions, dynamic and frontend suites, shared-symbolic tests, 1,800 exact-state
handlers, 655 cache transitions, and API/GC checks. Link-time tripwires reject
scalar entry into **both** `vm_dynamic` and `vm_dynamic_native`. The selector
range includes unary instructions, which precede binary instructions in the
manifest. Shared-symbolic tests also check folding without opaque effects.

Coverage includes signed/unsigned/float/bool operations, conversions, exact
traps, both literal directions, NaNs, oversized payloads, aliases, replacement,
version pressure, object casts, managed roots and full-content string equality.
Forced collection runs through the common scalar allocator. Allocation-free
wide-loop assertions apply to compiled execution, not to the interpreter's
canonical-cell representation. The nine-trial engine suite passed, including
315 small dynamic-workload comparisons.

## Paired measurements

Intel Core i7-1255U, WSL2 x86-64, CPU 0, Clang 20.1.2, LuaJIT 2.1.1703358377.
Before/after use identical assembled ABC and toolchain settings, without the
optimizer. Nine pairs alternate process order; each sample is the median of
three executions after warmup. Typed controls use the same procedure.

Median dynamic ns/iteration, baseline → shared implementation:

| Workload | Interpreter | Eager | Lazy |
|---|---:|---:|---:|
| u32-known | 114.569 → 79.713 | 3.249 → 3.258 | 3.362 → 3.389 |
| u32-carried | 112.718 → 79.690 | 3.272 → 3.268 | 3.360 → 3.334 |
| u32-checked | 127.245 → 87.884 | 3.422 → 3.348 | 3.334 → 3.279 |
| u32-unproven | 119.969 → 84.485 | 20.361 → 3.824 | 20.155 → 4.017 |
| u32-reload | 128.493 → 102.624 | 21.277 → 7.533 | 21.134 → 6.926 |
| width-alternate | 158.529 → 103.779 | 31.375 → 9.013 | 33.206 → 11.648 |
| f64-carried | 39.784 → 31.004 | 27.457 → 2.060 | 28.772 → 2.099 |

Interpreter median paired ratios are 0.655–0.785: about 21–35% lower time,
not native-sized speedups. Dynamic interpretation still costs substantially
more than typed interpretation. Native already-specialized integer cases are
essentially unchanged; unproved boxing, reloads, varying widths and floats
benefit from removing helpers/materialization.

Typed-control paired ratios span 0.915–1.043 for interpretation and 0.968–1.024
for native execution. Native typed body sizes are identical. Frequency/load
variation is substantial; small differences are not established improvements.
Ratios are medians of paired ratios, not ratios of the displayed medians.
LuaJIT/C columns in the separate engine suite are algorithm baselines, not
implementations of ABC tags, roots and checked-memory semantics.

## Code space and setup

| Dynamic workload | Eager bytes before → after | Lazy bytes before → after |
|---|---:|---:|
| u32-carried | 3,974 → 1,485 | 1,506 → 1,001 |
| u32-unproven | 4,872 → 1,459 | 2,166 → 988 |
| u32-reload | 4,170 → 6,026 | 2,095 → 2,951 |
| width-alternate | 4,505 → 11,395 | 2,874 → 9,922 |
| f64-carried | 1,502 → 1,471 | 1,502 → 1,009 |

Body sizes exclude lazy activation stubs. Reload/width CFG expansion is a real
tradeoff. Inlining scalar execution across banked handlers also increases
aggregate banked-object text from 2,441,416 to 3,205,952 bytes (about 31%).

The separate nine-trial suite reports one VM creation/load per workload:
eager 85–151 microseconds, lazy 47–100 microseconds in this run. These are
unpaired setup observations, not evidence of a setup-time improvement; lazy
first-use compilation is separately included in that runner's warmup timing.

## Reproduction

Build baseline `4d3e1fd` in an isolated worktree with the same toolchain. Build
each tree's engine `runlet`, then:

```sh
PAIRS=9 luajit research/experiments/engines/compare_dynamic.lua \
  /path/to/baseline/research/experiments/engines/runlet
make -C research/experiments/engines check CC=/tmp/clang20 LUA=luajit TRIALS=9
```

The paired driver covers interpretation, eager and lazy execution, checks every
result and reports typed controls, paired ratios and body sizes. Temporary
modules are removed. Raw results for this run are in `shared-scalar-pairs.txt`.

## Remaining limits

Delayed predicates do not retain identity, descriptor proofs are not version
keys, and reloads are not assumed invariant across unknown effects. Object/call
boundaries and open-word cache work are outside this scalar refactor.

**The native host-request safepoint gap remains.** Banked scalar execution now
polls pending requests without unconditionally emptying its cache. Native
scalar-only paths, including the older helper-free narrow paths, do not poll
at every generic-bytecode boundary as required by the normative profile.
Actual allocation/runtime boundaries publish roots and honor requests. Passing
root/allocation tests does not establish the stronger polling requirement.
