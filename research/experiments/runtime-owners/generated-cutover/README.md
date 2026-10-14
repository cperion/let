# Generated holding operations / service and cleanup binding

Qualified runtime cutover, **not source counted placement or collector-free completion**.
Parent v1 evidence is historical. WORKLIST E01–E03/E05/O04–O08 and D07 remain open.

## Implemented producer-to-execution path

- `gen/runtime_primitives.lua` now declares twelve `__let_rt_v2_` operations. Module
  loading checks reserved names/signatures; source extern impersonation/host rebinding
  reject. v1 fixed-layout modules reject and must be rebuilt; revision-6 ordinary
  opcode/operand kinds remain unchanged.
- `frontend/let/lifetime.lua` calls the compiler-time `gen/type_ops.lua` generator.
  Physical payload type/layout and ordered owning offsets produce ordinary checked-IR
  copy/release functions. `Ir.Code` uses existing `.codeaddr` relocations; raw Ptr-to-Ptr
  Convert changes the compiler pointee view without changing address bits. This does
  not authorize safe-Ref reinterpretation or introduce a source cast feature.
- `src/type_ops.c` validates operation signatures/effects, resolves module function
  indices, reserves cleanup storage and prepares all release/copy branches before
  descriptor publication. Descriptors carry image bindings, not a fixed NONE/OWNER
  switch or a serialized native pointer. Generated C TypeOps registry/output is gone.
  The private operation checker is not a termination/memory-safety proof for arbitrary
  handwritten pointer bytecode.
- Owners carry explicit initialized-holding prefix storage outside uninitialized
  payload bytes. Generated copy increments counts and advances that prefix after
  each successful retain. Failure cleanup releases only the committed prefix.
- Persistent `abc_exec_context` replaces stack-local `abc_run`; a synchronous worker
  owns the intrusive queue and separate preallocated cleanup context. Native/threaded
  guards read context bounds, not embedded root-stack addresses. The full shared
  runtime/task/scheduler split is not implemented.
- Runtime primitive effects commit once. A generated SERVICE boundary returns to the
  driver with continuation, existing physical register bindings and stack coordinates.
  Interpreter service uses canonical empty caches and the next PC. After preparation
  or iterative cleanup, resume continues after the primitive. SERVICE is not PARK,
  not a public status and not recursive entry into a running source VM.
- The driver enters one prepared generated release routine at a time; child releases
  only enqueue. Source frame records remain valid through unwind. Cleanup uses its
  independent reserved storage after source stack failure; it does not allocate,
  compile lazily, ask for stack growth, scan roots or invoke source deferred actions.
- Native emission constructs fresh writable page regions, patches private labels,
  seals RX, then release-publishes atomic entry slots (acquire readers). Published
  bytes never reopen writable. Stubs and bodies have separate construction regions;
  ordinary jumps cross page fallthrough boundaries. Preparation holds an image mutex,
  never across generated execution. A failed preparation closes further preparation
  for that image but preserves existing executable source/cleanup entries. Compiled
  but unsealed code is not a prepared holding entry, including on retry.
- Emitter region enumeration and aggregate used/allocated bytes replace the false
  contiguous-native-image view. Pages live until image teardown. Images still bind
  session module-world/foreign data; general shared image lifetime is not qualified.

## Validation

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

`validation-final.log` is the final incremental full suite; not a clean build.
`focused-final.log` passes frontend **36 checks / 32 VM executions** and C **2822
checks**. These are assertions, not distinct scenarios. Four execution modes, both
mirrored banks, raw/optimized modules exercise:

- live A/B prefixes and separate C value; allocation, retain, move, normal leave;
- generated single-child and two-owning-cell copy/release, exact count traffic;
- partial-copy checked-retain failure: 3 allocations, 3 successful retains, 6 releases,
  no leak or release of the uncommitted destination field;
- 100001-owner chains executed through generated release entries, with no host-recursive
  destruction or allocator calls during release (malloc/calloc/realloc/aligned_alloc wrappers);
- actual child allocation failure, abort after persistent image write (writes survive),
  multiple registered recursive frames at stack exhaustion, forgotten scope rejection;
- cleanup-storage allocation failure and native RX-sealing failure after an older
  owner exists; old code bytes remain identical/executable, initialized holdings free,
  output stays unchanged and error identifies the original `type_bind` FCALL;
- retry after sealing failure rejects, rather than publishing an unprepared descriptor;
- invalid holding effects/policy, reserved namespace/version/signature checks;
- same-VM callback reentry rejection and successful other-VM execution/TLS restoration;
- shared-count core concurrency and final free on another thread (not task migration).

Failure injection belongs to the validator only. Early failed logs are retained:
wrong builder method/op spelling, illegal pointer conversion before the raw-pointer
view binding, duplicate foreign declaration installation, stale cache consumer/form
count, fixture indentation/type/multiword-literal mistakes. They are not passes.

### Focused sanitizers

`sanitizer.log` passes ASan/UBSan/LSan with leak detection. Instrumented: validator,
owner/runtime call/type binding/VM, native image/emitter, threaded emitter, residualizer.
Other archive objects, generated interpreter/threaded engines, generated machine code
and Lua frontend are **not** instrumented. Function-type sanitizer is disabled for
machine-code entry boundaries. Clang20 objects use the installed Clang18 sanitizer
runtime because the local Clang20 wrapper lacks compiler-rt.

```sh
mkdir -p /tmp/let-generated-owner-asan
for file in tools/validate_owners.c src/owner.c src/runtime_call.c src/type_ops.c \
            src/vm.c src/native_image.c src/native_emit.c src/threaded_emit.c \
            src/residualize.c; do
  /tmp/clang20 -Iinclude -Isrc -Ibuild -O1 -g -std=c11 -pthread \
    -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
    -fsanitize=address,undefined -fno-sanitize=function -fno-omit-frame-pointer \
    -c "$file" -o "/tmp/let-generated-owner-asan/$(basename "$file" .c).o" || exit
done
clang -pthread -fsanitize=address,undefined /tmp/let-generated-owner-asan/*.o \
  build/libabc.a \
  -Wl,--wrap=aligned_alloc,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=mprotect,--wrap=abc_owner_retain \
  -lm -o /tmp/let-generated-validate-owners-asan
ASAN_OPTIONS=detect_leaks=1 /tmp/let-generated-validate-owners-asan \
  build/runtime-owners-a.abc build/runtime-owners-b.abc \
  build/runtime-owners-a-opt.abc build/runtime-owners-b-opt.abc \
  build/runtime-owners-reentry.abc
```

No whole-project sanitizer, TSan/race proof, wasm/non-x86-64, asynchronous interruption,
shutdown or exhaustive-resource qualification.

## Cost and retained storage

`measure.c`: one process/library, process CPU time, 2000 warmups then nine trials of
20000 API calls per case/mode, unpinned uncontrolled host. `cost-raw.log` and
`cost-optimized.log` contain medians, exact per-call traffic and image storage:

| Fixture | Allocations / retains / releases | Sample median range |
| --- | --- | --- |
| scalar control | 0 / 0 / 0 | 31–37 ns |
| normal | 1 / 1 / 2 | 552–734 ns |
| nested move | 1 / 0 / 1 | 557–791 ns |
| parent-child | 2 / 1 / 3 | 1087–1519 ns |
| copied pair | 3 / 4 / 7 | 2167–3173 ns |

Each measured owner call has one reclamation service exit and ends with zero live
owners. These samples are slower than historical fixed-helper samples (normal315–489ns,
parent-child399–589ns). They are not controlled before/after ratios, no performance
acceptance is claimed, and ordinary-call/recursive-guard regression remains unqualified.
Generated release and full ordinary-call synchronization have real overhead.

In the raw fixture, eager native uses61406 body bytes in65536 allocated bytes over16
regions. Lazy uses38609 body bytes in327680 allocated bytes over80 regions: **substantial
page fragmentation**, not an accepted space bound. Threaded35120/65536 bytes is one
region. Cleanup reserves6 cells per bank (plus its frame array), independent of the
root limit. These are fixture-specific allocation extents, not RSS/peak bounds.
ELF shared-library text3621605/data360872/bss16 (`size.log`); relative to the historical
v1 sample this is text−89610/data+12776 bytes, not a speed result or isolated attribution.

```sh
/tmp/clang20 -Iinclude -Isrc -Ibuild -O2 -std=c11 -pthread \
  -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
  research/experiments/runtime-owners/generated-cutover/measure.c build/libabc.a -lm \
  -o /tmp/let-generated-owner-measure
/tmp/let-generated-owner-measure build/runtime-owners-a.abc
/tmp/let-generated-owner-measure build/runtime-owners-a-opt.abc
```

## Remaining architectural work

**Source counted admission is still closed.** Fixtures explicitly choose physical
roots, payload types and owning offsets. No source placement/owning Ref/slice/callable
representation cutover has happened. Variants, initialized-element loops, generalized
buffers/arrays, aliases/replacement lifetimes, module persistent owners, exports/FFI,
frozen/erased/container holding transport and task PARK/scheduling remain incomplete.
The cutover removes wrong runtime abstractions; it does not replace these producers
with a helper façade or a runtime holding-plan interpreter. Whippet responsibility
migration/vendor removal is still mandatory; D07 remains open.
