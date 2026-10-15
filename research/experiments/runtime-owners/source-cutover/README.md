# Connected source ownership cutover — E01/E02/O04–O08

This is the current post-removal implementation, atop `0802d299`, not qualification
of the retired v1/v2/v3 bindings or withdrawn larger revision7/v4 proposal.
WORKLIST remains the completion authority. No publication is authorized here.

## Implemented boundary

`Program.analyze` owns the exact checked source graph/proofs. `placement.lua`
consumes them into a separate physical graph without repeating inference. It emits
concrete root/value/result/scratch fields, direct retain-before-replace operations,
limited single-use same-loop moves, caller-owned owning-result records and actual
C-entry field drops. Projection retains root ownership. Proven borrowed functions
retain one-address `InPlace` contracts, including caller-frame lifetime constraints.

The C owner core embeds32 bytes; an activation embeds16 bytes of chain/drop header.
Six exact revision-7 source imports bind allocation/hold/clear/enter/leave/drop.
Every acquired holding is cleanup-visible immediately. Allocation zeroes outgoing
holdings before publishing its root; failure drops only established concrete fields.
VM cleanup runs before ABC storage reset/result publication, preserving original
errors and persistent ordinary image writes. Cleanup is not source `defer` or rollback.

All four execution modes eagerly prepare native lifecycle code and install real
`void(context, object)` C pointers before ordinary execution. Callbacks use the
existing symbolic computation/eight-register allocator; they enqueue and return.
C drain frees iteratively without allocation. No scope-slot registry, progress
prefix, release cache, pinned register, field-plan interpreter, second allocator or
runtime `abc-opt` dependency was introduced. Exact old/wrong runtime imports reject.
Tooling residual IR and portable C still reject lifecycle entries.

Known keyed runtime partial supplies use ordinary source supply/captures, not
mutable `Any` word construction. Known unfinished typed callable analysis is
lattice bottom until its producer updates, not an opaque unknown call.

## Acceptance evidence

- `validate-final.log`: **full incremental `make validate` passed**, including the
  complete `validate-slet`, native/threaded emitter, capacity/continuation/API,
  optimizer, oracle, format and standalone core regressions. Not a clean build.
- Source harness: **1110 checks / 352 actual VM calls**, four modes, original and
  optimized images, with lifecycle bodies also mirrored to stack B. Real source
  factories, saved access across replacement, self-replacement, recursive/loop
  allocation, multi-result returns, arrays, slices, interior projections, borrowed
  local calls, indirect owning results, closure/opened/keyed/partial captures and
  zero-width materialization. Ordinary image writes survive a source trap.
- C harness: **1043242 checks**. Allocation failure and actual retain overflow at
  every acquisition boundary in factory/closure/array/slice/callable fixtures;
  original FCALL PCs, untouched failed outputs, established partial construction,
  empty cleanup/dead queues, stack exhaustion, reuse, and failed RX publication
  followed by successful preparation. Wrappers observe balanced allocations/frees
  and no allocation attempts or recursive drains during reclamation.
- The source builds a **25-environment chain**; late allocation/acquire failure is
  checked. Separately, **C constructs a100001-owner chain**, then invokes the actual
  source-generated C drop on a128KiB pthread stack with source TLS unset. This is
  not a source100001-node execution or a migratable-task/race test.
- Malformed/retired runtime signatures reject at module load. Structurally valid
  lifecycle bodies with trapping arithmetic, C-frame allocation or a forbidden
  runtime call reject VM preparation in every mode before publication.
- `sanitizer-final.log`: the complete C source-fixture matrix passes ASan/UBSan with
  leak detection on `owner`, `lifetime`, `vm`, `memory_module`, `residualize`,
  `native_emit`, `native_image`, and the C harness. Remaining runtime objects and
  generated interpreter/threaded/native bodies are **not instrumented**. Function-
  type UBSan checks are disabled for calls into generated JIT code (which has no
  compiler-emitted type prefix). `sanitizer-1.log` preserves that initial incompatible
  probe's fault; `sanitizer-2.log` records the corrected focused configuration.

Earlier numbered logs preserve failed attempts, not additional final passes.
In particular integration7's `indirect_result` allocation expectation was wrong:
the by-value scalar capture needs one environment plus one leaf allocation, not a
third scalar-root allocation. The corrected exact assertion remains in the harness.
Some earlier shell batches ended successfully after an earlier constituent failed;
individual log results, not those aggregate shell statuses, are the evidence.

## Costs and exclusions

`sizes-final.log` measures this fixture, not a benchmark or performance acceptance:

| Quantity | Original | Optimized |
| --- | ---: | ---: |
| Encoded file bytes | 34548 | 34465 |
| Bytecode bytes | 25467 | 25422 |
| Writable image bytes | 468 | 468 |
| Lifecycle functions / relocations | 49 / 49 | 49 / 49 |
| Native lifecycle body bytes | 39083 | 39083 |
| Native lifecycle allocated bytes | 40960 | 40960 |
| Maximum callback home bytes (excluding host ABI frame) | 48 | 48 |

Interpreted/threaded owning execution therefore also pays native-code preparation
and storage costs. Header cost is32 bytes/allocation plus alignment; activation
header16 bytes excludes actual holding/scratch/result fields. Borrow-only exported
reader/local caller tests acquire/allocate zero owners. `main(2)` allocates three
owners; its exact count and release balance are asserted. No current timing,
RSS/retention, speedup, whole-project sanitizer, TSan/race or browser/wasm result.

Context-dependent unresolved physical instances, owning variants/erasure/containers,
public owning/access transport beyond the proven borrowed specialization, foreign
ownership, persistent owning modules, tasks/interruption/shutdown remain unsupported.
Some addressed loop-local borrowed storage/environments reject pending iteration
lifetime resolution. General native callback resource bounds and arbitrary handwritten
bytecode termination/pointer safety are not proven; generated callbacks are straight
line with the small measured home extent. `.let` executable lowering remains closed;
these source fixtures are `.slet`. Whippet removal is still separate unfinished D07
work. No hidden fallbacks or compatibility execution were added.

## Reproduction

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
# Focused source matrix (also included in validate):
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-source-owners
```

Focused instrumentation, Clang20 objects linked with the installed Clang compiler-rt:

```sh
mkdir -p /tmp/let-source-cutover-asan
cp build/libabc.a /tmp/let-source-cutover-asan/libabc.a
for f in owner lifetime vm memory_module residualize native_emit native_image; do
  /tmp/clang20 -Iinclude -Isrc -Ibuild -O1 -g -pthread -std=c11 \
    -fsanitize=address,undefined -fno-sanitize=function -fno-omit-frame-pointer \
    -c src/$f.c -o /tmp/let-source-cutover-asan/$f.o
done
ar r /tmp/let-source-cutover-asan/libabc.a \
  /tmp/let-source-cutover-asan/{owner,lifetime,vm,memory_module,residualize,native_emit,native_image}.o
/tmp/clang20 -Iinclude -Isrc -Ibuild -O1 -g -pthread -std=c11 \
  -fsanitize=address,undefined -fno-sanitize=function -fno-omit-frame-pointer \
  -c tools/validate_source_owners.c -o /tmp/let-source-cutover-asan/test.o
clang -pthread -fsanitize=address,undefined /tmp/let-source-cutover-asan/test.o \
  /tmp/let-source-cutover-asan/libabc.a -lm \
  -Wl,--wrap=aligned_alloc,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=free,--wrap=abc_owner_replace,--wrap=abc_owner_drain,--wrap=mprotect \
  -o /tmp/let-source-cutover-asan/validate-source-owners
ASAN_OPTIONS=detect_leaks=1 /tmp/let-source-cutover-asan/validate-source-owners \
  build/source-owners{,-opt,-b,-b-opt}.abc
```

`sizes.c` links against `build/libabc.a` with `-Iinclude -Isrc -Ibuild -pthread -lm`.
`manifest.sha256` records selected implementation inputs and generated fixture images;
ignored build artifacts are regenerated, not durable jj snapshots.
