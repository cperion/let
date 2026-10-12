# Check-first native scalar lowering

Baseline: `4d3e1fd`. Historical sources are preserved in
`research/archive/scalar-helpers-4d3e1fd/`.

## What changed

Scalar uncertainty no longer selects a second execution engine:

```
unknown tag → register check → refined successor → typed operation
known tag   → typed operation
bad operands → specified error (or false for unequal-type equality)
```

- Removed `abc_dynamic_numeric_classify`, `abc_dynamic_numeric_bits`, and their
  call stencils. Tag tests do not publish the whole symbolic context.
- Binary, literal, unary, comparison, condition and numeric-conversion bodies
  use typed stencils. Wide integers and floats are not arithmetic-helper cases.
- Primitive tests fold from facts. Descriptor tests/unboxing use checked object
  headers and field accesses; they do not run the EXT handler.
- Numeric boxing carries raw bits and a tag, without demanding a frontend
  normalization instruction. Boxing preserves noncanonical narrow payloads;
  arithmetic and checked conversions apply their own normalization rules.
- Wide values remain raw across compatible edges and spills. On escape, a
  payload-fit branch selects immediate encoding or actual object allocation.
  Only the allocating edge publishes roots. Float encoding never allocates.
- Saturated version families conform to a checked generic CFG, not a scalar
  execution helper. The existing local version bound remains authoritative.

The symbolic cache still **is register allocation**. There is no residual-value
IR, second allocator, placement reconstruction, or runtime `abc-opt` invocation.
Object construction, open-word operations, dynamic calls and foreign calls
retain runtime boundaries. A possible heap address uses the collector's
nonallocating membership predicate before header access; that predicate does
not implement a language operation or publish the VM context.

During equality lowering, inspection found that the interpreter accepted a
string object's header/payload as a scalar box. Equality could consequently
compare only its first bytes. Scalar extraction now excludes strings, and
string equality compares lengths and complete contents in both engines. Managed
reference descriptors also now carry their actual aggregate tag fact rather
than the raw-pointer box tag.

## Validation

`make validate` includes a link-time tripwire in
`tools/validate_scalar_native.c`: any native scalar opcode, cast or type test
entering `vm_dynamic_native` fails the test. Object construction/operations are
not forbidden by this tripwire. A separate allocation tripwire covers a wide
loop and reversed-literal register pressure without escapes. An indirect-return
home-alias regression forces collection on each allocating scalar escape:
live C aliases must be protected before replacement A registers are published.

Coverage includes the integer/float/bool binary and comparison matrix, every
numeric/bool cast pairing, unary operations, both literal operand orders,
oversized narrow payloads, exact errors, aliases, replacement, version pressure,
real-call ABI, NaNs, object casts, managed roots and string content equality.
The scalar/type-version suite executes 32,856 cases; continuation validation
executes 234. The full scalar and dynamic engine suites also pass, including
315 small dynamic-workload comparisons.

## Paired measurements

Intel Core i7-1255U, WSL2 x86-64, affinity CPU 0, Clang 20.1.2. Same toolchain and
flags as `dynamic-types.md`. Before and after runners consume **identical ABC**,
without the optimizer. Nine before/after process pairs alternate order. Each
sample is the median of three executions after one warmup. Typed controls are
measured the same way. Frequency/load variation remains substantial.

Median ns/iteration, dynamic ABC:

| Workload | Eager before | Eager after | Lazy before | Lazy after |
|---|---:|---:|---:|---:|
| u32-known | 3.300 | 3.263 | 3.411 | 3.410 |
| u32-carried | 3.351 | 3.253 | 3.338 | 3.341 |
| u32-checked | 3.375 | 3.372 | 3.337 | 3.391 |
| u32-unproven | 17.240 | 3.318 | 17.651 | 3.303 |
| u32-reload | 18.172 | 6.379 | 18.609 | 6.315 |
| width-alternate | 28.192 | 8.519 | 29.969 | 10.148 |
| f64-carried | 27.947 | 2.046 | 29.519 | 2.085 |

The already-specialized integer paths are essentially unchanged. Unproved
boxing, reloaded operands, polymorphic widths and floating arithmetic lose
substantial helper/materialization work. Typed-control median paired ratios
range from 0.979 to 1.029, with identical emitted body sizes; small changes in
those controls or the already-fast dynamic rows are not established speedups.

This is not a claim that all checks vanish. Reloads retain checks, width changes
select different typed arms, and encoding/normalization still costs work.
The new eager dynamic/typed ratios in the ordinary nine-trial suite were about
1.6 for the carried integer kernel, 1.9 for reload, 2.6 for alternating widths,
and 1.0 for the floating kernel. The LuaJIT/C columns remain algorithm baselines,
not implementations of ABC tag/check/memory semantics.

Explicit CFGs can cost code space:

| Dynamic workload | Eager bytes before → after | Lazy bytes before → after |
|---|---:|---:|
| u32-carried | 3,974 → 1,486 | 1,506 → 1,002 |
| u32-unproven | 4,872 → 1,460 | 2,166 → 989 |
| u32-reload | 4,170 → 6,075 | 2,095 → 2,973 |
| width-alternate | 4,505 → 11,446 | 2,874 → 9,964 |
| f64-carried | 1,502 → 1,480 | 1,502 → 1,018 |

Reload and width-alternation code growth is a real tradeoff, not hidden by the
timing result. Body sizes exclude lazy activation stubs.

## Reproduction

Build the baseline in an isolated worktree at `4d3e1fd`, using the same Lua and
Clang setup as the current tree. Build each tree's engine `runlet`, then:

```sh
PAIRS=9 luajit research/experiments/engines/compare_dynamic.lua \
  /path/to/baseline/research/experiments/engines/runlet
make -C research/experiments/engines check CC=/tmp/clang20 LUA=luajit TRIALS=9
```

The paired driver assembles once per workload/form, checks every result, pins
both runners to the same CPU, and removes its temporary modules. It reports
median times, median paired ratios and body sizes.

## Remaining limits

Delayed/combined predicates do not retain predicate identity, descriptor proofs
are not version-key facts, and memory reloads are not assumed invariant across
unknown effects. This change does not implement open-word inline caches or
remove object/call runtime boundaries.

The safepoint protocol is not rewritten here. As with the previous helper-free
narrow paths, scalar-only native code does not poll host collection requests at
every generic-bytecode boundary. The profile's stronger polling requirement
remains a conformance gap; root/allocation tests are not proof of that polling
requirement. Actual allocation and runtime boundaries still publish roots and
honor pending collection requests.
