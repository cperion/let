# Owning tagged values and address bitcasts — O04–O08/E01/E02

Approved separately at `e655a936`, implemented on top of collector-removal
`81f407cc`. WORKLIST remains the live completion authority. This qualifies the
private tagged slice, not general ownership, public/FFI transport or tasks.

## Integrated contract

- Revision-6 EXT selectors `10`/`11` (hex), profile 2+, are
  `ADDR2BITS.A/B` and `BITS2ADDR.A/B`. They preserve all 64 bits and change only
  the selected operand's declared kind. They neither create a safe source reference
  nor validate a pointer. Old encodings are unchanged; old engines reject the new
  selectors. There are now 18 selectors, 149 operations and 290 public forms.
- Shared scalar computation owns the identity. Native/threaded bindings preserve
  existing symbolic placement without a new stencil or allocator. The native form
  inventory remains 3771. Optimized bytecode retains kind transitions for constants;
  residual tooling records AddressToBits/BitsToAddress. Portable C still rejects
  address-valued programs and lifecycle entries.
- Source proofs are consumed once. A separate structurally checked physical graph
  represents tagged values with the existing tag/aligned union and packed cells.
  Pointer leaves use the new casts, never a temporary memory reinterpretation.
  Private ABI flattening includes tagged components in records/fixed arrays.
- Actual fields remain the holding inventory. Compiler-only conditional holding
  trees generate active-tag branches and concrete owner-slot operations. No runtime
  path table, descriptor interpreter, progress prefix or ownership dispatcher exists.
- Copy captures immutable carrier bits once. Reused scratch unions are zeroed,
  enclosing tags are published, and each successful retain becomes cleanup-visible
  immediately. Only after all acquires succeed is the destination replaced. Moves
  clear active owner slots; statement-level variant uses participate in last-use
  accounting. Clearing moved unions reads their tags, not their entire payloads.
- Owning results retain caller-owned result records. Transient packed cells do not
  retain. Bounded tagged references do not promote roots. Proven borrowed bodies
  with unchanged types and all call contracts keep ordinary value/local lowering.
  The value-only raw-pointer constructor test asserts no CALLOC or FADDR.
- Public/foreign packed-address sum contracts remain rejected. Private nested-aggregate
  flattening also does not widen unrelated, previously unsupported public aggregate ABIs. Raw pointer targets
  are not by-value payloads: inspecting a scalar field through an existing foreign
  raw pointer does not by itself select ownership materialization.

The removed paths are blanket variant rejection inside materialized functions,
physical packed-address rejection, and flat-offset-only cleanup. The C counting
core, six lifetime bridges, lifecycle format, explicit continuations and foreign
synchronization are unchanged. No collector dependency was introduced.

## Acceptance

`validate-reviewed.log` is the final **full incremental** `make validate` pass.
`validate-acceptance.log` predates the final public-aggregate admission regression;
`validate-final.log` also predates adding address casts to the poisoned-cache-state test.

- Source: **1763 checks, 568 VM calls**. All four modes, raw/optimized modules and
  mirrored lifecycle bodies. Covers direct/indirect/multiple owning results, nested
  alternatives and arrays, reference/slice/callable payloads, saved values across
  replacement, self-replacement, loops, recursion and traps. A separate no-counted-
  requirement module verifies bounded tagged references without heap promotion.
  Static tagged cycles and unsupported public/foreign transport still reject.
- C harness: **2508342 checks**. Every allocation and non-null acquisition boundary
  of the normal fixtures is faulted, including partial tagged scratch and multi-result
  construction. Real retain overflow preserves the destination. Failure leaves outputs
  untouched, result count zero, original FCALL PCs, no live owners, no cleanup chain
  and no pending queue. Tagged recursion also exercises ordinary stack exhaustion.
- The original source-built 25-environment chain remains. Separately, C builds
  100001-owner graphs using actual source-generated flat and branched C callbacks,
  drained on a 128 KiB pthread stack with source TLS unset. The tagged graph includes
  duplicate child holdings and a valid scalar alternative whose inactive owner-word
  positions contain nonzero, invalid-pointer-looking bits. Cleanup neither scans
  those inactive fields, allocates, nor recursively drains. These are **not**
  source-built 100001-node graphs or task/race tests.
- Machine oracle: 147 cases / 1176 mirrored four-mode executions, all 290 forms.
  Tests exact arbitrary bits, live opposite-bank/C aliases, real image pointers through
  calls, constant address kinds, and malformed operand kinds. Poisoned cache test:
  **3360 exact-state handlers** plus 655 transitions. Residual IR: 331 checks.
- Existing pointer-free packed suite: **1894 checks / 496 executions**, including its
  allocation-free value assertions. Full frontend, continuation/capacity, emitter,
  format/API, optimizer and collector-dependency regressions pass.
- `sanitizer-reviewed.log` (also the earlier `sanitizer-final.log`): ASan/UBSan
  with leak detection passes the entire C source
  fixture matrix. Instrumented: owner, lifetime, vm, memory_module, residualize,
  native_emit, native_image and the harness. Other runtime objects and generated
  interpreter/threaded/native code are **not instrumented**. Function-type UBSan
  checks are disabled because generated JIT entries have no compiler type prefix.

Earlier logs are retained failures/checkpoints, not current failures or extra
acceptance claims. They include source-fixture spelling/addressability corrections,
excess duplicate carrier slots exceeding existing u8 C indices, and an overly broad
initial materialization trigger that incorrectly descended raw-pointer pointee types.
The final trigger examines actual value/storage producers and function contracts.

## Measured costs, not speedup claims

`sizes-acceptance.log` matches `sizes-final.log`:

| Quantity | Original | Optimized |
| --- | ---: | ---: |
| Encoded file bytes | 95615 | 95523 |
| Bytecode bytes | 80484 | 80430 |
| Writable image bytes | 820 | 820 |
| Lifecycle entries/relocations | 92/92 | 92/92 |
| Stack-A native lifecycle body/storage bytes | 131788/135168 | 131788/135168 |
| Stack-B native lifecycle body/storage bytes | 134113/139264 | 134113/139264 |
| Maximum callback home bytes, excluding ABI frame | 48 | 48 |

This larger corpus includes the original fixtures plus tagged cases; comparison with
source-cutover's smaller corpus is **not a like-for-like regression measurement**.
Interpreted/threaded owning execution also pays native lifecycle preparation/storage.
Owner headers remain 32 bytes and activation headers 16 bytes, excluding actual fields.

The C wrapper measures non-null acquires and peak live owner allocation bytes (including
headers/alignment, not frame/code storage or RSS), for input 2:

| Fixture | Owners allocated | Non-null acquires | Peak owner bytes |
| --- | ---: | ---: | ---: |
| variant | 1 | 5 | 40 |
| variant_replace | 4 | 23 | 200 |
| variant_nested | 3 | 35 | 120 |
| variant_indirect | 2 | 6 | 80 |
| variant_callable | 2 | 4 | 88 |
| variant_slice | 1 | 3 | 40 |
| variant_loop | 2 | 16 | 80 |
| variant_multi | 2 | 10 | 80 |
| variant_raw | 1 | 1 | 40 |

Tagged allocation counts are asserted across four modes and four module variants;
observed acquire counts drive all-boundary failure injection in every run. The table
is printed once for the raw/interpreted run. The empty variant allocates/acquires zero. Root
promotion is not required merely by a tag, but retained values still have real costs.
No timing, clean build, whole-project sanitizer, TSan, browser/wasm or performance
acceptance is claimed. Existing C-index/frame/branch encoding limits remain; this is
not generalized native resource, termination or raw-pointer-safety qualification.

Context-specific physical instances, persistent owning modules, erasure/containers,
public/FFI/task transport, interruption/shutdown, portable-C lifecycle delivery and
executable `.let` remain separate work. No unsupported fallback was added.

## Reproduction

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
# Focused integrated source/failure matrix:
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-source-owners
```

For focused instrumentation, use the commands in
[`../source-cutover/README.md`](../source-cutover/README.md#reproduction), with a fresh
`/tmp/let-tagged-asan.*` directory and the current harness/images. The recorded run
used `/tmp/let-tagged-asan.Bws3uF`. Clang20 compiles instrumented objects; installed
`clang` supplies compiler-rt at link. The wrapper set and instrumentation exclusions
are identical. `sanitizer-build.log` records the runtime archive build;
`sanitizer-final.log` includes the updated harness and its first execution, and
`sanitizer-reviewed.log` repeats that unchanged runtime/harness against the final images.

Size measurement reuses the unchanged `../source-cutover/sizes.c`, linked against
current `build/libabc.a` with `-Iinclude -Isrc -Ibuild -pthread -lm`.
`manifest.sha256` identifies selected implementation/test inputs and generated images;
ignored build products must be regenerated rather than treated as jj backups.
