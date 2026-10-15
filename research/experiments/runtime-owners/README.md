# Initial owner runtime / existing-call binding (historical v1 evidence)

**Superseded implementation:** [generated-cutover/README.md](generated-cutover/README.md)
preserves historical v2 evidence; [c-release/README.md](c-release/README.md) records
the later, also removed direct-call release/C reclamation binding and its historical
validation/costs. Current ownership runtime integration is pending replacement.
The fixed descriptors, stack-local run context and v1 ABI described below were
removed. Old commands/`measure.c` reproduce the earlier checkpoint, not the current
tree; current sanitizer inputs and linker wrappers differ. Retain these logs as
historical evidence, not current admission or completion claims.

This is a **partial implementation**, not completion of collector-free source
execution. The approved source owner inference remains unchanged: counted source
escapes still reject. Explicit checked-IR lifetime clients now execute through the
normal compiler, existing FCALL.A/B, and interpreter/threaded/eager/lazy engines.
WORKLIST E01/E02/O04–O08 remains open, and D07 is not complete.

## Implemented path

- `gen/runtime_primitives.lua` and `tools/gen_runtime_primitives.lua`: one catalog
  generates C metadata and frontend declarations. Eight scope/owner operations use
  versioned `__let_rt_v1_` symbols and ordinary address/integer cells. Unknown reserved
  names/signatures reject at module load. Host rebinding and source extern declarations
  of reserved names reject. No opcode, operand kind, ownership module section, native
  value IR, placement reconstruction or allocator is added.
- `frontend/let/runtime.lua` and `lifetime.lua`: exact declarations/staging policy and
  ordinary checked-IR calls with explicit frame storage. No alternative source evaluator.
- `src/owner.h/.c`, `src/type_ops.h`, `gen/type_ops.lua`: immutable descriptors,
  platform aligned allocation, checked plain/atomic counts, immortal no-op handling,
  retained field replacement and intrusive iterative release. Three concrete generated
  layouts: local/shared pointer-free bytes and one confined owning field. These are
  initial implementation layouts, not a substitute for source-specialized TypeOps.
- `src/runtime_call.h/.c`, `src/vm.c`, `gen/cold.lua`, `src/residualize.c`, threaded/
  stencil bindings: existing calls execute against the current synchronous VM context.
  Failed calls release registered initialized holdings before stack reset. No source
  defers, effect rollback, root scanning, user destructors or recursive destruction.
  Status/original PC survives runtime failures. Normal scope exit must be explicit.

Module writes survive an abort. **Module-owned payloads are not yet implemented**;
this test does not prove persistent owning-holding cleanup or publication. Likewise,
fixtures explicitly choose their physical roots/layouts; they are not source placement.

## Qualification

```
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

`full-validation-final.log` passes the incremental project suite, including source
ownership170/56 and access176/112. `validate-owner-runtime` is an integrated target:

- `frontend/tests/runtime_owners.lua`: **29 checks, 24 VM executions**. Compiler-emitted
  allocation, retained copies, transfer to a caller scope and generated outgoing-field
  release stage through all four modes, raw/optimized. Ordinary foreign execution is
  still prohibited in staging. Restricted portable C rejects these unsupported calls.
- `tools/validate_owners.c`: **201268 checks**; most are repeated operations in the
  100001-owner chain, not distinct semantic scenarios. Both mirrored banks and raw/
  optimized modules run in all four modes. Tests keep A/B prefixes and a separate C
  value live across runtime calls, inspect exact allocation/retain/release/free traffic,
  and check unchanged failed outputs, original FCALL/ABORT PCs and VM reuse.
- Invalid layout, actual second-allocation failure after parent construction, abort
  after persistent image write, nested stack exhaustion, forgotten normal scope leave,
  null error sink, and retain-before-replace overflow rollback are exercised.
- Four host threads repeatedly retain/release a protected shared owner. Its final
  release occurs on a worker different from its allocating thread. This exercises
  atomic-count behavior; it is **not** task scheduling, transferability or a race proof.
- Same-VM callback reentry rejects without resetting active scopes. A callback can
  execute another VM and return to the original runtime context, tested in all modes.
- The deep chain drains without host recursion. Link-time wrappers for aligned_alloc,
  malloc, calloc and realloc verify no allocator calls during the drain. Failure
  injection is in the validator only, not a production allocator/testing API.

Early logs are retained: the first frontend fixture used the wrong extern syntax;
the second focused attempt used `PST64` instead of `ST64`; `focused-final.log` used
an incorrect C scope typedef; `focused-final-2.log` passed the assembler's second
return value to `file:write`. These were fixture errors, not passing qualifications.
`focused-final-3.log` and the final full validation pass.

### Focused sanitizers (not a fully instrumented build)

`sanitizer-qualified.log` passes ASan/UBSan with leak detection. Instrumented files:
validator, owner core, runtime call binding, VM, and generated TypeOps C. Other runtime
objects, generated engines, native code and Lua frontend are **not instrumented**.
Function-type sanitizer is disabled for generated machine-code entry boundaries.
The installed Clang20 wrapper lacks compiler-rt; `sanitizer-build.log` preserves that
failed link. Clang20-generated instrumented objects were linked with installed
Clang18 compiler-rt. Reproduce after the regular build/fixtures:

```sh
mkdir -p /tmp/let-owner-asan
for file in tools/validate_owners.c src/owner.c src/runtime_call.c src/vm.c \
            build/generated/type_ops.c; do
  /tmp/clang20 -Iinclude -Isrc -Ibuild -O1 -g -std=c11 \
    -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
    -fsanitize=address,undefined -fno-sanitize=function -fno-omit-frame-pointer \
    -c "$file" -o "/tmp/let-owner-asan/$(basename "$file" .c).o" || exit
 done
clang -fsanitize=address,undefined /tmp/let-owner-asan/*.o build/libabc.a \
  -Wl,--wrap=aligned_alloc,--wrap=malloc,--wrap=calloc,--wrap=realloc \
  -lm -lpthread -o /tmp/let-validate-owners-asan
ASAN_OPTIONS=detect_leaks=1 /tmp/let-validate-owners-asan \
  build/runtime-owners-a.abc build/runtime-owners-b.abc \
  build/runtime-owners-a-opt.abc build/runtime-owners-b-opt.abc \
  build/runtime-owners-reentry.abc
```

No clean-build, whole-project sanitizer, TSan, exhaustive resource or non-x86-64/wasm
qualification is claimed. The current frame-record ABI explicitly asserts a 64-bit
host; wasm layout generation is pending.

## Costs, not speedup claims

`measure.c` uses one process/library and PROCESS_CPUTIME_ID, 2000 warm-up calls,
then nine 20000-call trials per mode/case. Timings include `abc_vm_call`; host execution
is uncontrolled and unpinned. `cost-raw-final.log` and `cost-optimized-final.log` are
final repeat samples, not paired before/after measurements. In particular the scalar
control is a different program, not a baseline for owner semantics. No ordinary-call
regression qualification or performance acceptance is established here.

| Case | Allocations / retains / releases per call | Final sampled median range |
| --- | --- | --- |
| scalar control | 0 / 0 / 0 | 21–40 ns |
| allocate, retain, drop, scope release | 1 / 1 / 2 | 315–489 ns |
| nested allocation, move to caller | 1 / 0 / 1 | 336–531 ns |
| parent with one owned child | 2 / 1 / 3 | 399–589 ns |

All sampled calls end with zero live allocations. This is not a peak-live/RSS bound,
allocator acceptance, generalized retain elimination or source-program performance.
The ordinary full-call synchronization and small catalog lookup remain in this initial
binding; specialized minimal-clobber paths are not claimed.

```sh
/tmp/clang20 -Iinclude -Isrc -Ibuild -O2 -std=c11 \
  -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
  research/experiments/runtime-owners/measure.c build/libabc.a -lm \
  -o /tmp/let-owner-measure
/tmp/let-owner-measure build/runtime-owners-a.abc
/tmp/let-owner-measure build/runtime-owners-a-opt.abc
```

`size.log` records ELF section sizes versus the retained pre-binding shared library:
text **+10762 bytes**, data **+880 bytes**, bss unchanged. `jj diff` confirms runtime
sources/generators/headers/opcodes did not change between that retained library's
source checkpoint `b6c5f428` and pre-binding checkpoint `06b64f6c7ff6` (only a Makefile
frontend test entry changed). This is code/data growth, not native-image capacity or
RSS. Native timing attribution across separately loaded libraries is not attempted.

## Remaining work

General source owner placement, owning ref/slice/callable ABI and root selection;
source-specialized TypeOps and aggregate/variant copy rollback; module/VM persistent
owner teardown; exported/foreign handles, interruption and shutdown; frozen/erased/
container holdings; tasks/worker context split, suspension and publication. Existing
source counted admission remains closed rather than pretending these are supplied
by the new builder or raw pointer ABI. Ownership inference is still independent of
runtime accounting; no runtime ranks or cycle detector were added.

Whippet audit command (exit1, no matches; empty `active-gc-audit.log`):

```
rg -n 'whippet|gc_alloc|gc_collect|gc_root|whippet_types|any_repr' \
  src include gen tools Makefile .github --glob '!*.md'
```

Absent active references are not completion of the responsibility migration.
`vendor/whippet` remains; D07 stays open. No dormant GC allocator or fallback was added.
