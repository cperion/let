# Standalone C owner core validation

Runtime source baseline: `df676f8c`, following removal of the v3 ownership binding.
This validates `src/owner.c/.h`, **not source counted placement, generated release
code delivery or VM failure cleanup**. No runtime implementation fix was needed
during this validation pass. `tools/validate_owner_core.c` and its Makefile target
are new; the core is unchanged from that baseline.

## Results

- `build.log`: incremental `make all` passes.
- `focused.log`: **113 checks** pass. Allocation sizes include the concrete header;
  alignment/rounding, invalid extents/policies and injected allocator failure preserve
  failed outputs. Tests cover local/shared count overflow, rejection of retain on a
  queued zero owner, null/immortal release, optional field-drop callbacks, failure-safe
  replacement, self-replacement, a diamond/FIFO queue and a100001-object chain.
- `validation.log`: full existing incremental `make validate` passes, now including
  `validate-owner-core`. This is not a clean build or qualification of unsupported
  source/optimizer configurations.
- `small-stack.log`: the core validator also passes with a128KiB host-stack limit.
- `sanitizer.log`: ASan/UBSan with leak detection passes. Both the core and test
  harness are instrumented, including C callback function checks. This is not
  whole-project sanitizer coverage; ordinary execution engines are not instrumented
  by this standalone executable.
- Four pthreads repeatedly retain/release one protected shared root; another thread
  performs final parent/child release. This is core count/publication evidence, not
  task migration, TSan or a race-freedom proof.
- Link wrappers track allocation/free traffic outside production code. No wrapped
  malloc/calloc/realloc/aligned_alloc attempt occurs during draining; allocations and
  frees balance. Internal calls made entirely within libc are not interposed by these
  linker wrappers.
- `sizeof(abc_owner)` is **32 bytes** on this build. No timing, speedup or RSS claim.

The harness uses concrete C objects with the owner as their first member and ordinary
C field-drop functions. It explicitly initializes fields before releasing/publishing.
It does not establish a constructor/failure-cleanup protocol for source bytecode.

## Reproduce

From repository root:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' all
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-owner-core
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
(ulimit -s 128; build/validate-owner-core)
```

Focused sanitizer (Clang20 objects linked with the installed Clang18 compiler-rt):

```sh
mkdir -p /tmp/let-owner-core-asan
for file in tools/validate_owner_core.c src/owner.c; do
  /tmp/clang20 -Iinclude -Isrc -Ibuild -O1 -g -std=c11 -pthread \
    -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    -c "$file" -o "/tmp/let-owner-core-asan/$(basename "$file" .c).o" || exit
done
clang -pthread -fsanitize=address,undefined /tmp/let-owner-core-asan/*.o \
  -Wl,--wrap=aligned_alloc,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=free \
  -o /tmp/let-validate-owner-core-asan
ASAN_OPTIONS=detect_leaks=1 /tmp/let-validate-owner-core-asan
```

`source.sha256` covers the core, harness and Makefile only, not the entire build
closure. Older v1/v2/v3 evidence in neighboring directories remains historical.
