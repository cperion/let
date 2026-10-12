# Explicit float-bitcast correction — implemented and incrementally validated

User-approved additive revision-6 EXT assignments: 0E F2BITS, 0F BITS2F,
selected A/B, profile 2+. Typed unary transfer is raw identity: float↔integer,
all 64 bits unchanged, no allocation/arithmetic/traps/safepoints. Existing bytecode
keeps its meaning; older engines reject the new selectors. No ABI/layout or
alternative allocator, numeric conversion, scratch-memory or verifier bypass.

`gen/semantics.lua` defines the transfer and computation. Generated existing unary
interpreter/symbolic bindings consume it. Native/threaded retain the original
symbolic value/placement without emitting a stencil. Optimizer output retains
explicit kind transitions, including folded constants. Residual schema/builder/
validator expose typed pure FloatToBits/BitsToFloat; portable C still rejects float
operations. `frontend/let/abc.lua` emits casts at F64 packed leaf boundaries.

## Interpreter cost follow-up

The approved transparent-EXT binding was prototyped and fully incrementally
validated, but **not adopted**: cast-heavy gains came with roughly15–23% ADDC
regressions and no reliable packed-program gain. The original binding is restored;
stronger exact-state payload tests remain. This does not withdraw the explicit
bitcast correction. See [measurements, controls and candidate patches](transparent-ext/README.md).

## Validation

- `build.log`: build and generated consumers; stencil output 3770 entries/77472
  code bytes. No comparison with a clean pre-extension build is claimed.
- `oracle.log`: 143 independent oracle cases / 1144 original/mirrored four-mode
  executions, all 286 public forms. Raw bitcast tests include optimized output,
  both banks, unchanged live prefixes/C aliases, all-zero/negative zero, subnormals,
  finite values, infinities, quiet/signalling NaNs and arbitrary all-one bits.
  Constant float results also pass with stack capacity one.
- `focused.log`: packed suite 1894 checks / 496 executions; optimized/unoptimized
  interpreted/threaded/eager/lazy. Includes construction/extraction, exact float
  arithmetic, nested mixed records and arrays, direct/indirect transport, real
  storage, plus the earlier integer/odd-width/storage-boundary subset.
- Full validation logs include ISA selector/profile/kind/decode checks, invalid
  operand-kind/empty-stack rejection, residual 315 checks, cache 2880 exact-state
  handlers with poisoned dead ABI arguments and 655 logical transitions, optimizer,
  capacity/lifetime/continuation/API and frontend suites.
- `full-validation-1.log` passed before the final three float aggregate fixtures
  and capacity-one oracle were added; `full-validation-2.log` is the final run.
- Initial failed draft fixture logs: `packed-attempt-1.log` supplied mixed record
  fields in the wrong sorted order; `measure-attempt-1.log` referred to a nonexistent
  lowered artifact.bytes. Corrected tests do not change production semantics.

Command:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

This is incremental validation, not a clean-build/sanitizer qualification, complete
F04, ownership proof or closure of the separate optimizer frame-access defect.
Broader repeated construction/padding/loop/tight-resource qualification remains.
The historical nested-extraction shift defect is corrected separately (`../shift-fix/`).

## Runtime and module-size measurement

`measure.lua` / `measurement.log` preserve the preliminary separate-process series.
It is noisy and is superseded for comparison by `measure-paired.lua` /
`measurement-paired.log`: same checked IR/schema/runtime/host in one process, old
and current lowerings, alternating order, 10000 warmup pairs and nine samples of
200000 raw VM calls per artifact/mode. Median CPU nanoseconds include public-call
and LuaJIT FFI overhead. Each fixture checks exact runtime inputs/results; the
roundtrip uses a signalling-NaN payload, the arithmetic fixture computes 1.5+2.

Baseline is `frontend/let/abc.lua` from 9cfd7f65 with schema-name-only adaptation:
S.u8/U16/etc, S.ref/ptr/array/slice and other type constructors changed to current
capitalized S names; `node.kind=="Ref"` changed to S.Ir.Ref:isclassof(node) to avoid
the naming collision. No packed logic, optimizer/runtime or scalar algorithms
were backported. Both baseline and current use the current schemas/runtime. The
adapted file used was `/tmp/let-packed-memory-before.fgo5_4jd/frontend/let/abc.lua`;
its unadapted original was `/tmp/let-bitcasts-before-abc.lua`, obtained with:

```sh
jj file show -r 9cfd7f65 frontend/let/abc.lua > /tmp/let-bitcasts-before-abc.lua
cd frontend
/tmp/lua-compat ../research/experiments/frontend-syntax/packed-tagged/float-bitcasts/measure-paired.lua \
  /tmp/let-packed-memory-before.fgo5_4jd/frontend/let/abc.lua
```

| Fixture | Raw/optimized module bytes before → current | Artificial CALLOC |
| --- | --- | --- |
| Roundtrip | 145 → 144 | 1 → 0 |
| Add extracted float | 164 → 163 | 1 → 0 |

Paired medians: interpreted **regresses 3–20%**, threaded improves 13–28%,
native eager/lazy vary from 9% faster to 8% slower. These tiny, overhead-inclusive
probes are not universal speedup or regression bounds. Preparation/first-call CPU
samples are retained separately and are too noisy for conclusions. No machine-code
image growth or process-memory bound was measured. The removed artificial allocation
and zero-stencil casts are structural facts, not a guarantee of faster execution.

## Remaining work

Broader resource/padding/loop coverage and measurements of representative source
compositions; interpreted EXT decoding cost warrants follow-up. No performance
optimization or new representation was silently introduced to hide measured costs.
The independent optimizer `frame access outside a live byte block` defect remains.
