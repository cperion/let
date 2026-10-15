# Direct callable release / C reclamation

**Historical v3 checkpoint at `c16666c8`; the binding has since been removed.**
The commands, source manifests, validators and measurements below describe that
checkpoint, not the current removal state. Runtime replacement is pending; no fresh
build/test/performance claim accompanies removal. Preserve these logs as historical
evidence. This checkpoint never completed general source counted placement.
This supersedes the v2 TypeOps/SERVICE checkpoint in `../generated-cutover/` and
v1 fixed-layout checkpoint in `../`. WORKLIST E01–E03/E05/O04–O08 and D07 remain open.

## Architecture and removals

- Private ABI **`__let_rt_v3_`**, thirteen catalog operations. v1/v2 reject; rebuild
  their modules. Ordinary revision-6 bytecode, scalar/bank conventions and public
  embedding ABI are unchanged.
- Allocation takes scope/slot, explicit bytes/alignment/count policy and a prepared
  release handle. Each owner carries outgoing-release behavior, not a universal
  copy/layout/TypeOps bundle. Native header is48 bytes versus the former24-byte
  header plus8-byte initialized prefix: **16 extra bytes per allocation**, before
  allocator/alignment rounding. No source/wasm layout compatibility is implied.
- `gen/holding.lua` independently generates known copy on demand and private release
  bodies. Copies are compiler-selected direct calls, not runtime operation lookup.
  Explicit initialized state controls rollback; copied but uncommitted pointer bits
  do not constitute acquired holdings. Genuine erased-value operations are a separate,
  unimplemented boundary, not a renamed universal descriptor.
- `src/release.c` validates private release signatures/effects. Existing symbolic
  computation/register allocation prepares all branches with a normal C-callable ABI:
  `void(abc_owner_context *, abc_owner *)`. Slot7 transports that explicit C context;
  the existing allocator uses slots0–6. There is no second allocator/value IR.
- `src/owner.c` owns checked counts, retain-before-replace, initialized-field release
  and iterative draining/free. Release bodies only enqueue children; each callback
  returns before the next runs. Leaf bindings call C directly, without FCALL bridge
  dispatch or bank flushing. No field-plan interpreter or fixed layout registry.
- Deleted allocation TypeOps, `type_bind`, ownership SERVICE forms/exits, physical
  resume snapshots, pending publication state, ABC cleanup context/stacks and driver
  reentry into source engines. Persistent root context and context-bound limits remain.
  Task PARK/resume and scheduling are still pending, not implemented by this cleanup.
- Release preparation uses independent fresh native construction, RX sealing and
  publication before returning a usable handle. Failure discards the realization;
  retry is allowed and older source/release code remains executable. Code belongs to
  the loaded image and is freed at image teardown, after current holdings are drained.
- **Interpreted/threaded source also requires native release preparation.** No host
  C compiler runs at runtime. No-executable-code platforms need an AOT release binding;
  it is not implemented. There is no hidden ABC reclamation fallback.

The current automatic release producer accepts fixed owning offsets. Manually built
checked-IR branch/initialized-element-loop fixtures qualify the callable realization,
not general source variants/arrays. The private checker is not an arbitrary-pointer
memory-safety or termination verifier. Broader native spill/resource admission,
source placement/owning representations, containers/erasure, module/export/FFI/task
lifetimes, interruption/shutdown and Whippet vendor removal remain open. Counted
source requirements still reject; this is not a helper facade reported as source completion.

## Validation

`validation-final.log`: full **incremental** `make validate` passes, including frontend
**84 checks/80 VM executions** and C **4304 checks**. Both banks, raw/optimized,
interpreted/eager/lazy/threaded source:

- Live A/B prefixes/C, ordinary continuations, exact allocation/retain/release traffic,
  nested moves, direct known copying and uncommitted-prefix cleanup. Injected fourth
  retain failure:3 allocations,3 successful retains,6 releases.
- 100001-owner chains, with no malloc/calloc/realloc/aligned_alloc during draining.
  `small-host-stack.log` repeats the C validator successfully with a128KiB host stack.
- Branches select different owning fields; element loops release initialized counts
  0/1/2. Empty variant release succeeds with its entire payload page **PROT_NONE**:
  even the uninitialized tag must not be read before construction state permits it.
- Prepared native callbacks run with source TLS unset and leave the VM context
  byte-for-byte unchanged. A shared parent/child using prepared native release frees
  on a different pthread with that thread's explicit owner context. Core shared-count
  CAS stress also passes. These are not task migration, TSan or a race-freedom proof.
- Real allocation/retain failures, multiple recursive source frames at stack exhaustion,
  abort with persistent writes, forgotten scope leave, unchanged failed outputs,
  original FCALL PCs, same-VM reentry rejection, other-VM callback TLS restoration,
  reuse and null error sink.
- Release preparation allocation/RX failures with an older live owner: no handle/result
  published, all initialized holdings freed, old source bytes unchanged/executable,
  successful fresh retry. Invalid release effects, policies, signatures and ABI versions reject.

`sanitizer-final.log`: focused ASan/UBSan/LSan with leak detection passes. Instrumented:
validator, owner, runtime call, release binding, VM, native image/emission, threaded
emitter and residualizer. Remaining archive objects/generated engines/native machine
code/Lua frontend are not instrumented. Function sanitizer is disabled for generated
entries. Clang20 compilation uses Clang18 compiler-rt at link. No clean-build, whole-
project sanitizer, wasm, full resource bound, TSan or general source-lifetime claim.

`obsolete-binding-audit.log` has one intentional match: the frontend negative test
replaces v3 with v2 and requires rejection. The active implementation audit has no
obsolete binding matches. Active GC audit has no matches; vendor removal/D07 is not done.

## Costs, growth and limitations

`measure.c`, `cost-raw.log`, `cost-optimized.log`: nine20000-call trials after2000
warmups, process CPU time, API-inclusive; uncontrolled/unpinned host. Lookup, bridge,
allocation and count costs remain included. Case order is plain/normal/nested/parent-
child/copied pair. First-call samples are not isolated cold-preparation benchmarks:
prior cases warm shared entries and eager session loading already compiles source.
Final raw+optimized medians across modes: scalar41–60ns, normal581–808ns,
nested649–853ns, parent-child1038–1340ns, copied pair2258–3079ns. First normal
call113–339us includes release preparation. There is **no controlled speedup or
performance acceptance**; see logs for individual cases and session-load costs. Historical v2 samples overlap some current cases, while some
current samples are worse. Do not infer causality or subtract the scalar control.

Three prepared release bodies occupy660 bytes in12288 allocated bytes/three regions,
including interpreted execution; sampled native home reservation is40 bytes maximum,
**excluding normal ABI/compiler spills**. Broader fixtures assert home reservation
at most256 bytes, not a generalized runtime policy. Per-routine page fragmentation
remains substantial, as does lazy source fragmentation; source body/allocated/region
counts are printed separately: raw source eager50263/53248 bytes/13 regions,
lazy20773/241664/59, threaded39912/65536/one. `size.log` records shared ELF
text3616285/data362224/bss16, versus v2 text3621605/data360872/bss16 (text−5320,
data+1352). This is not speed, peak memory, RSS or isolated attribution.
Small objects pay the extra16 header/state bytes.

VM/context code is smaller, but this is not an overall source-size reduction:
`src/vm.c` plus `execution_context.h` remove59 net lines; the runtime/generator/compiler/
build cutover adds21 net lines (355 added/334 removed), before tests/docs/evidence.
Native callable bindings add forms (3803 total versus3771), rather than a second VM.
Earlier `cost-*-export-order-1.log` used new exports ahead of existing cases and thus
changed linear API lookup costs. Existing case positions were restored. The retained
`cost-*-prior-prefix-fixture.log` precede the final zero-prefix/guard qualification;
neither earlier set is the final cost sample. `cost-*-repeat-1.log` repeats the final
prefix/guard fixture before a catalog-description-only change; it includes worse
samples (normal616–890ns, parent-child1061–2057ns, pair2256–5275ns). This variability
precludes attributing performance gains to the architectural cutover.

## Reproduction

From repository root (current private binding; not the historical parent commands):

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' all validate

(ulimit -s 128; build/validate-owners \
  build/runtime-owners-a.abc build/runtime-owners-b.abc \
  build/runtime-owners-a-opt.abc build/runtime-owners-b-opt.abc \
  build/runtime-owners-reentry.abc)

/tmp/clang20 -Iinclude -Isrc -Ibuild -O2 -std=c11 -pthread \
  -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
  research/experiments/runtime-owners/c-release/measure.c \
  build/libabc.a -lm -o /tmp/let-c-release-measure
/tmp/let-c-release-measure build/runtime-owners-a.abc
/tmp/let-c-release-measure build/runtime-owners-a-opt.abc
```

Focused sanitizer:

```sh
mkdir -p /tmp/let-c-release-asan
for file in tools/validate_owners.c src/owner.c src/runtime_call.c src/release.c \
            src/vm.c src/native_image.c src/native_emit.c src/threaded_emit.c \
            src/residualize.c; do
  /tmp/clang20 -Iinclude -Isrc -Ibuild -O1 -g -std=c11 -pthread \
    -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
    -fsanitize=address,undefined -fno-sanitize=function -fno-omit-frame-pointer \
    -c "$file" -o "/tmp/let-c-release-asan/$(basename "$file" .c).o" || exit
done
clang -pthread -fsanitize=address,undefined /tmp/let-c-release-asan/*.o \
  build/libabc.a \
  -Wl,--wrap=aligned_alloc,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=mprotect,--wrap=abc_owner_retain \
  -lm -o /tmp/let-validate-c-release-asan
ASAN_OPTIONS=detect_leaks=1 /tmp/let-validate-c-release-asan \
  build/runtime-owners-a.abc build/runtime-owners-b.abc \
  build/runtime-owners-a-opt.abc build/runtime-owners-b-opt.abc \
  build/runtime-owners-reentry.abc
```

The source manifest covers surviving files changed by this cutover, based on parent
`9b76c5a5`; it is not the complete build dependency closure. Artifact hashes cover
this local incremental build. Both manifests are rooted at the repository directory.
Check with
`sha256sum -c research/experiments/runtime-owners/c-release/source.sha256` and the
corresponding `artifacts.sha256`; generated artifacts require this exact local build.
