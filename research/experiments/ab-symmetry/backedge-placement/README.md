# Backedge knowledge weakening preserves register placement

**Implemented and validated.** The user approved correcting the native backedge
placement issue after the investigation and rejected interpreter experiment.

## Contract and implementation

`src/residualize.c:edge()` still forgets constant knowledge on the same backward
edges. It materializes each constant using the existing cache allocator, then
constructs the existing canonical register descriptor with the same destination
home. It no longer unconditionally saves that value to memory and replaces its
placement with HOME.

Register pressure may still cause real spills. Existing generic-entry conformance,
version budgets, branch-decision ordering, aliases/captures, capacity checks and
continuation transport are unchanged. No second allocator, placement pass, IR,
new entry ABI, quickening or interpreter modification was introduced.

Canonical construction matters: `materialize()` changes kind and register but
retains the old constant payload; context equality compares descriptor fields.
`reg_value()` removes that inactive payload without changing the actual register
bits. This is a local use of the existing constructor, not a global change to
context equality or specialization policy.

## Architectural validation

- `tools/validate.lua` adds **16 oracle cases / 96 mirrored three-mode executions**:
  constants and untouched values on A/B/C; a duplicated initial value whose live
  copy must survive modification; more than eight live values to force native
  spills; unconditional and conditional backedges; zero, one, six and 2,000 loop
  iterations. Explicit expected vectors check noncommutative B updates and order.
  General totals are now **113 cases / 678 executions**, all 282 forms assembled.
- `tools/validate_backedges.{c,abcasm}`, integrated in `make validate`, verifies
  repeated results and bounds native realizations: at most nine eager / eight
  lazy for the fixture, excluding the unnecessary home-backed loop context.
  It deliberately uses a zero-left addition so subsequent unknown iterations
  have fresh descriptor payloads; stale first-iteration constants cannot silently
  create a separate register-context family.
- The structural test **fails against the pre-fix revision-6 archive** with the
  expected extra-realization diagnostic (`before-regression.log`). It passes with
  this correction.
- A separately compiled temporary mutation that omits canonical descriptor
  construction also **fails the structural test** (`mutant.log`). It was never
  installed in the active runtime.
- Full active `all validate` passes (`final-validate.log`), including optimizer,
  capture, continuation, cache, source/staging/session/lifetime and portable-C
  suites. A fresh copied-source `all validate` passes (`clean-validate.log`).
  After strengthening only the structural fixture, the complete target passes
  again in that clean build (`clean-final-validate.log`). No source/build artifacts
  were copied from the active build into the fresh build. See `clean-path`.
- `git diff --check` passes. The first C test attempt omitted the API-required
  eager `abc_vm_load`; correcting that test setup preceded these passing runs.

The eight-line replacement in the existing edge owner removes unconditional
home publication for this case; it does not wrap or preserve that old path.

## Controlled before/after comparison

The `old` label in this directory means the preserved **pre-fix revision-6**
runner in `../final-comparison`, not the historical phase-0 engine. Both versions
execute identical copied modules through identical runner timing logic/flags.
The rejected dead-slot candidate is not included in either runtime.

CPU 0, seven-call batches, 24 preflight processes plus six rotated paired rounds:
**144 measurement processes / 1,008 timed steady-state calls**. All processes
succeed with the expected final result. Raw commands/status/output, timings and
load/preparation/first-call medians are preserved in the JSONL/CSV/JSON files.

### Native body bytes

| Workload | Eager before → after | Lazy before → after |
| --- | --- | --- |
| loop | 627 → 581 | 446 → 404 |
| branch | 1,818 → 1,790 | 1,172 → 1,126 |
| fib | 1,040 → 1,024 | 798 → 789 |
| memory | **450 → 309** | **324 → 246** |

Every measured native body is smaller. Memory removes the predicted extra context
and the initial seven-byte home store: **141 eager / 78 lazy bytes removed**.
`memory-compiled.dis` preserves the resulting stream. These are body-region bytes,
not lazy-stub, metadata, reserved mapping or resident-memory totals.

### Timing

Six-round paired after/before medians and ranges:

- Eager Fibonacci: **0.878 [0.765,0.977]**.
- Lazy Fibonacci: **1.070 [1.018,1.250]**.
- Other native workload ranges cross parity; no speedup is established there.
- Interpreter implementation is unchanged; observed interpreter timing shifts are
  controls, not claimed benefits of this native correction.

A separate **eight-round / 48-process / 336-timed-call** Fibonacci follow-up gives:

- Eager: **0.860 [0.822,0.926]**.
- Lazy: **1.112 [0.914,1.316]**.
- Interpreter control: **0.953 [0.666,1.005]**, showing substantial noise.

Thus eager Fibonacci is faster in both measured samples, while lazy Fibonacci's
median is **roughly 7–11% slower**. The latter remains a reported regression, not
hidden by smaller code. The user accepts regressions around 10%; no broad speedup
or exact causal timing explanation is claimed. Affinity does not isolate frequency
or background load, and each row is a batch median rather than retained individual
call samples. Full results remain in `summary.json` and `fib-followup*`.

## Scope remaining

This corrects the identified native placement coupling. It does not fix the
interpreter Fibonacci regression, finish general context/version-budget redesign,
eliminate all native code growth relative to phase 0, or complete the source
partial evaluator/documentation audit. Real memory homes, observable frame
storage and generic-entry obligations remain authoritative where required.

To repeat measurements, copy scripts/modules/runner source into a fresh sibling
output directory, relink with the intended runtime and the flags from the fixed
comparison report, then run the scripts. Raw output files use exclusive creation;
keep all previous runners and modules unchanged.
