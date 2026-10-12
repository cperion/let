# VM staging-session implementation evidence

**Latest status:** the approved runtime correction is implemented and validated;
see [the lifetime-fix report](lifetime-fix/README.md): 27 ASan lifetime cases,
217 session/ABI checks and a clean frontend build pass. Full integration still
stops at the unrelated legacy cache fixture. Source partial evaluation is pending.

The rest of this page preserves the **earlier blocked checkpoint**. Adding
GC coverage exposed a public-runtime use-after-free, independently reproduced
without Lua under AddressSanitizer. No fix or Lua workaround had been applied
at that checkpoint; the report above supersedes its pending-approval status.

## Implemented

- Separate PIC `build/libabc.so` from the existing runtime sources; no optimizer
  dependency. `readelf -d` showed libm, libc and the loader only; no abc-opt symbols.
- Shared public ABI FFI declarations in `frontend/let/abi.lua`.
- `Stage.open`, prepared programs, persistent images, scalar transport and explicit
  close; one-shot staging uses this service instead of subprocess/file execution.
- Public export-signature checking, exact f64/integer cells, structured diagnostics,
  source/optimizer provenance, callback/reentrancy guards and defensive finalizers.
- The obsolete executable `runtime` option rejects; library override uses
  `ABC_RUNTIME_LIBRARY`. No source evaluator was added.

## Passing evidence before adding the GC regression

`clean-build-validate.log` records `all validate-slet` from a fresh copied source
tree `/tmp/abc-staging-clean.Y4YXEt`, not a destructive clean of the working tree.
It passed 259 compiler, 81 lowering, 105 optimizer, 24 original staging and
**211 session/ABI checks**, plus schema/parser/walker, symmetric frontend,
78 production-source executions and 12 portable-C cases. `sessions.log` preserves
the passing session result before the additional GC tests.

The 211 checks include all three modes, optimized/unoptimized preparation,
persistent writes, distinct module identities even for identical bytes, isolated
sessions, aborts retaining prior stores, callback failures, explicit cleanup,
closed handles, exact float bit patterns, malformed bytecode and transport/signature
rejection. A child process prevents optimizer loading and disables subprocess/file
execution helpers; unoptimized VM arithmetic and trap provenance still pass.

`full-validate.log` then passes frontend/API/native/continuation/general suites
through 552 general executions and 282 assembled forms, before the separate
legacy cache fixture fails on bare `RET`. This is not a full-suite pass.

These logs precede the latest finalizer hardening/GC regression additions. The
current suite now also exercises abandoned-session collection and segfaults in
lazy teardown. Do not report the earlier clean run as validation of that path.

## Confirmed blocker

`abc_vm_free` in `src/vm.c:89` drops the image's module reference **before**
`image_free` destroys the native image. In lazy mode `abc_native_image_free` still
reads `c->module->code_size` (`src/residualize.c:853`). If the caller has already
released its own reference, module memory has been freed. The public API expressly
allows this: VM images retain modules until VM destruction.

Independent repro:

1. Load `lifetime.abcasm`, create a lazy VM and load the module.
2. Execute `main` and verify 42.
3. Release the caller's module reference.
4. Destroy the VM.

`lifetime-asan.log` reports heap-use-after-free with precisely that free/read chain.
The two added Lua GC checks per mode independently trigger the same ownership case;
there is no assumption that module and VM finalizers run in a particular order.

Proposed authoritative fix (awaiting approval): retain the module pointer, destroy
the image/native lazy state first, then release the image's module reference.
Test release-before-VM-destruction in all modes and rerun ASan plus the GC suite.
Do not hide the broken public ownership contract by forcing a Lua finalizer order.

ASan reproduction commands (repository root):

```sh
build/abc asm /tmp/abc-staging-session/lifetime.abcasm -o /tmp/abc-staging-session/lifetime.abc
/tmp/clang20 -O1 -g -fsanitize=address -fno-omit-frame-pointer -Iinclude -Isrc -Ibuild \
  -c src/vm.c -o /tmp/abc-staging-session/vm-asan.o
/tmp/clang20 -O1 -g -fsanitize=address -fno-omit-frame-pointer -Iinclude -Isrc -Ibuild \
  -c src/residualize.c -o /tmp/abc-staging-session/residualize-asan.o
gcc -g -fsanitize=address -Iinclude /tmp/abc-staging-session/lifetime.c \
  /tmp/abc-staging-session/vm-asan.o /tmp/abc-staging-session/residualize-asan.o \
  build/libabc.a -lm -o /tmp/abc-staging-session/lifetime-asan
ASAN_OPTIONS=detect_leaks=0 /tmp/abc-staging-session/lifetime-asan /tmp/abc-staging-session/lifetime.abc
```

Clang 20's local installation lacked ASan runtime archives; compilation used Clang
20 to preserve the native calling convention and linking used GCC's ASan runtime.
Only vm/residualize and the probe are instrumented; this is not a whole-runtime
sanitizer validation. The preserved sources here can be copied to those scratch
paths to reproduce. No implementation has been changed to correct this defect yet.

## Preliminary bridge-overhead measurement

`measure.lua` compares the archived pre-change bridge with in-process one-shot and
reused prepared sessions. `stage-before.lua` hash matches the pre-implementation
baseline (`558917389fe2ad44255544ae8aa1d4a970da3ff26478bbab9a2a2743e2742634`).

It uses one identical pre-lowered scalar multiplication program and runtime input,
optimization disabled, CLOCK_MONOTONIC_RAW, seven rotated rounds of five calls per
bridge/mode. Every result is checked. `timings.csv` retains prepare/first/warm costs;
`timing-summary.txt` summarizes warm batch averages. Libraries receive warm-up;
this is not whole-process cold startup, source compilation or VM throughput.

Observed median per-call bridge costs (microseconds):

| Mode | old subprocess | in-process one-shot | prepared session |
|---|---:|---:|---:|
| interpreted | 11641 | 563 | 20.7 |
| eager | 9605 | 415 | 14.1 |
| lazy | 9808 | 589 | 16.4 |

No CPU pinning/frequency control; substantial batch variation, small sample count,
and no confidence intervals. These measurements predate finalizer hardening and
must not be represented as final performance or correctness evidence. Explicitly
closed sessions were measured, not the failing GC path. No ISA baseline was rebuilt.

## Still outside this slice

Source virtual values/places, source-required static demands, the approved
`staticMode`/CLI API policy, initialization snapshots/relocation, aggregate transport,
escaping owned environments and managed Let execution remain unimplemented.
The stateful assembly fixture tests the VM bridge directly; it is not evidence
that production source module initialization is implemented.
