# Scalar instructions are shared control flow

Follow-up: [runtime-work audit](scalar-runtime-audit.md) traces the actual
immediate-u32 handler and accounts for duplicated native collection fragments.
Shared semantics alone did not yield an economical execution shape.

Baseline: `4d3e1fd`. Rejected implementations are preserved in
`research/archive/native-only-scalar-wip/` and
`research/archive/split-scalar-orchestration-wip/`. The latter shared arithmetic
leaves but still independently orchestrated concrete and symbolic scalar
execution. That was not the requested design.

## One computation

`gen/scalar_semantics.lua` defines all 35 scalar instructions: checks, selected
branches, representation operations, typed arithmetic/conversions, and specified
failure outcomes. Both bindings traverse that definition:

- `gen/scalar_banked.lua` binds concrete values, cache transitions and effects.
  Each EXT selector has its own ordinary banked handler and continuation site,
  with its instruction length known from the manifest. There is no observation,
  quickening, secondary arithmetic-selector dispatch or scalar opcode helper.
- `gen/scalar_symbolic.lua` binds the same steps to ordinary symbolic ABC
  operations. `src/symbolic_scalar.inc` abstracts tag predicates and supplies
  representation/control bindings; it contains no EXT algorithm switch.
- `src/native_scalar.inc` binds representation placement, conditional traps,
  safepoints and checked branch arms. The existing register-bearing symbolic
  context remains register allocation. There is no additional native value IR,
  allocator or placement reconstruction.

Typed expressions and conversion rules remain in `gen/semantics.lua`; shared
representation and tag predicates live in `src/any_repr.h` and
`src/scalar_rules.h`. `gen/scalar.lua` emits symbolic control flow and the numeric
conversion used at object/call ABIs, not a concrete scalar opcode dispatcher.
`src/dynamic.c` retains genuine object/call effects and allocation, not scalar
opcode execution. Build-time ABC rewriting remains supported; runtime never
invokes `abc-opt`.

The interpreter stores canonical `any` cells. Native values can remain raw
across compatible edges and spills, encoding or allocating only at represented
escapes. Boxing preserves bits; arithmetic/conversions apply normalization.
These are representation bindings of the same computation, not separate
language algorithms. Saturated versions conform to checked code, never a
scalar execution handler.

## Collection boundary

The shared flow includes the normative pending-request check. The request flag
belongs to the VM, not to the dynamic heap, so polling needs no heap-pointer
chase and requesting collection need not allocate a heap descriptor.

Native fast paths load/test the flag and branch past the collection path. The
cold path exposes all eight physical registers and the live physical home
ranges to Whippet. It neither changes placements nor boxes raw integers.
Nonmoving collection preserves those values. Requests against an empty heap
are consumed too; ordinary typed code intentionally leaves requests pending.

This closes the scalar-only native polling gap in the previous measurements.
It also has real code-size and timing costs: the cold collection sequence is
currently emitted at each eligible point. The measurements below include it.

## Validation

Full `make validate` passed, including:

- 32,856 type-version executions and 234 continuation executions;
- scalar-handler tripwires for both `vm_dynamic` and `vm_dynamic_native`;
- a structural comparison of all 2,133 semantic binding events for the same
  35 instruction definitions, plus absence of secondary arithmetic dispatch;
- exact traps, literals in both directions, noncanonical payloads, NaNs,
  aliases, joins, calls, managed roots and complete string equality;
- pending requests with/without an allocated heap, typed code leaving requests
  pending, and a word whose module root is cleared before scalar collection;
  the native test asserts that its live register root is supplied to the GC;
- frontend/build-time optimization, API/GC tests, 1,800 exact-state handlers and
  655 cache transitions.

The full nine-trial engine suite passed, including 315 small dynamic-workload
comparisons. Logs are retained alongside this report.

## Comparative suite: final tree

Intel Core i7-1255U, WSL2 x86-64, CPU 0, Clang 20.1.2, LuaJIT 2.1.1703358377.
Nine trials; median ns/iteration. T/D denote typed/dynamic ABC. LuaJIT/C are
algorithm baselines, not implementations of ABC tag/root/memory semantics.

| Workload | T-interp | D-interp | T-eager | D-eager | T-lazy | D-lazy | LJ-off | LuaJIT | C |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| u32-known | 15.395 | 53.391 | 2.328 | 3.636 | 2.244 | 3.571 | 25.045 | 5.535 | 1.838 |
| u32-carried | 15.980 | 54.358 | 2.264 | 3.666 | 2.347 | 3.605 | 25.473 | 5.347 | 2.008 |
| u32-checked | 15.528 | 61.147 | 2.319 | 3.773 | 2.369 | 7.688 | 25.951 | 5.350 | 2.044 |
| u32-unproven | 14.282 | 53.329 | 2.334 | 3.844 | 2.438 | 3.729 | 24.927 | 5.281 | 1.856 |
| u32-reload | 18.460 | 56.382 | 3.834 | 8.030 | 3.705 | 9.552 | 24.596 | 5.136 | 1.885 |
| width-alternate | 21.948 | 68.314 | 3.837 | 14.426 | 4.007 | 15.831 | 24.249 | 5.321 | 1.860 |
| f64-carried | 13.554 | 22.635 | 2.154 | 2.064 | 1.960 | 1.941 | 3.063 | 0.536 | 0.549 |

Dynamic interpretation remains **3.05–3.94× typed** for these integer kernels,
and 1.67× for floating arithmetic. This is not near parity and is not presented
as a solved interpreter-performance problem.

## Paired baseline comparison

Identical ABC, no optimizer, nine alternating before/after process pairs. Each
sample is the median of three warmed executions. Median dynamic ns/iteration,
`4d3e1fd` → final tree:

| Workload | Interpreter | Eager | Lazy |
|---|---:|---:|---:|
| u32-known | 130.530 → 58.318 | 3.589 → 3.795 | 3.797 → 3.581 |
| u32-carried | 127.105 → 55.343 | 3.583 → 3.631 | 3.548 → 3.523 |
| u32-checked | 151.486 → 60.192 | 3.752 → 3.893 | 3.572 → 6.812 |
| u32-unproven | 128.786 → 55.410 | 20.250 → 3.892 | 19.394 → 3.772 |
| u32-reload | 129.766 → 58.052 | 20.473 → 8.412 | 21.408 → 9.680 |
| width-alternate | 161.513 → 70.929 | 32.844 → 13.984 | 33.380 → 16.260 |
| f64-carried | 39.066 → 22.073 | 26.927 → 1.939 | 27.746 → 1.981 |

Interpreter median paired ratios are 0.396–0.555 (45–60% lower time). Typed
interpreter controls span 1.010–1.061. Native typed controls span 0.967–1.041
and have identical emitted body sizes. Small native differences are not
established improvements. **The checked lazy case regresses materially**:
median paired ratio 1.848. That regression is not dismissed as noise or hidden
by the faster unproved/reloaded/float cases.

Ratios are medians of paired ratios, not ratios of displayed medians. Frequency
and host-load variation remain substantial; the separately collected suite and
paired samples should not be mixed into new speedup estimates.

## Isolating interpreter dispatch cost

A separate A/B kept the common scalar computation and polling unchanged, but
replaced the large per-cache-state EXT body with selector-specific handlers.
This also makes instruction lengths constant and separates continuation sites.
Nine paired runs, median interpreter ns/iteration:

| Workload | Large EXT body | Separate handlers | Median paired ratio |
|---|---:|---:|---:|
| u32-known | 61.477 | 47.597 | 0.773 |
| u32-carried | 62.381 | 48.706 | 0.790 |
| u32-checked | 81.546 | 60.388 | 0.734 |
| u32-unproven | 66.314 | 52.970 | 0.802 |
| u32-reload | 70.341 | 53.856 | 0.763 |
| width-alternate | 85.753 | 67.562 | 0.793 |
| f64-carried | 25.799 | 22.008 | 0.858 |

Integer typed controls span 0.934–1.017. The floating typed control is 0.920,
so the floating attribution is less clear. This isolates handler organization,
not branch misses alone: lengths, code layout and generated register allocation
also change. Hardware branch-miss counters are unavailable (`perf_event_open`
returns `ENOENT` on this host); no counter-based attribution is claimed.

The ordinary carried integer loop executes 24 dynamic-form instructions versus
21 typed instructions. That 14% instruction-count difference cannot explain
the original several-fold gap. There are still nine scalar instructions per
iteration: four boxes and five arithmetic operations. They perform tag checks,
representation extraction/encoding and request polling, not just one extra
check for the entire loop. Further cost attribution remains work to do.

## Code size and remaining regressions

| Dynamic workload | Eager bytes before → after | Lazy bytes before → after |
|---|---:|---:|
| u32-known | 596 → 9,653 | 536 → 9,139 |
| u32-carried | 3,974 → 14,424 | 1,506 → 7,584 |
| u32-checked | 1,092 → 8,369 | 1,021 → 8,101 |
| u32-unproven | 4,872 → 14,398 | 2,166 → 7,571 |
| u32-reload | 4,170 → 20,327 | 2,095 → 9,988 |
| width-alternate | 4,505 → 37,727 | 2,874 → 24,223 |
| f64-carried | 1,502 → 4,195 | 1,502 → 3,279 |

Sizes exclude lazy activation stubs. Repeated cold collection paths add
substantial size beyond the checked CFGs. Aggregate banked-object text is
6,520,674 bytes versus 2,441,416 at baseline. The dispatch-only change increased
that text from 6,020,928 to 6,520,674 while improving the measured hot loops.
These are real costs, not evidence that generation or specialization is free.
The checked-lazy regression and code growth need further work.

The suite's one-VM setup samples are eager 81–198 microseconds and lazy 45–92
microseconds. They are unpaired observations, not setup-time improvement
claims. Lazy first-use work is recorded separately in warmup timing.

## Reproduction and raw results

```sh
make -C research/experiments/engines check CC=/tmp/clang20 LUA=luajit TRIALS=9
PAIRS=9 luajit research/experiments/engines/compare_dynamic.lua \
  /path/to/4d3e1fd/research/experiments/engines/runlet
# For an interpreter-only pair:
MODES=interpreted PAIRS=9 luajit research/experiments/engines/compare_dynamic.lua BEFORE_RUNLET
```

- `shared-scalar-engines.txt`: complete scalar/dynamic comparative suite.
- `shared-scalar-pairs.txt`: baseline pairs, typed controls and native sizes.
- `scalar-dispatch-pairs.txt`: dispatch-only diagnostic pairs.

The dispatch diagnostic's pre-change executable was saved as
`/tmp/scalar-dispatch-before-runlet` before changing handler organization; it is
not a separate supported engine. Object/call effects, delayed predicate
identities and descriptor-version facts are not added by this scalar refactor.
