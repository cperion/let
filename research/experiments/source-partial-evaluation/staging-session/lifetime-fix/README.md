# Approved module/native teardown correction — validated

The user approved correcting the authoritative runtime ownership contract after
the independent ASan reproduction preserved in the parent directory.

## Change

`src/vm.c` now destroys image/native state before releasing the image's retained
module reference. The native-preparation failure path uses the same dependency
order. Lazy native cleanup may therefore still read module metadata even when the
caller has already released its own reference. No Lua finalizer-order workaround,
new reference layer, ISA change or GC/safepoint policy change was introduced.

`tools/validate_lifetime.c` uses only the public API. It covers all nine pairs of
VM modes, with uncalled images, calls before releasing caller ownership, and calls
after release (including after destroying the first VM): 27 lifetime cases.
It is included in `make validate-slet`, alongside the existing ABI probe and Lua
session tests.

## Validation

- `asan.log`: all **27 lifetime cases** pass with `ASAN_OPTIONS=detect_leaks=1`.
  Instrumented objects are vm.c/residualize.c plus the public API test; other
  runtime objects are the normal static archive. This is not a whole-runtime
  sanitizer run. The earlier reproduction used the same instrumentation strategy.
- `validate-slet.log`: **24 original staging checks and 217 session/ABI checks**
  pass, now including abandoned-session GC in all three modes. Independent child
  testing disables optimizer loading and subprocess/file execution helpers.
- `clean-build-validate.log`: copied-source clean `all validate-slet` passes under
  `/tmp/abc-staging-fixed-clean.YQYfh9`, including 259 compiler, 81 lowering,
  105 optimizer, schema/parser/walker, symmetric source, 78 production-source
  executions and 12 portable-C cases.
- `full-validate.log`: full integration again reaches and passes the API suite,
  495 continuation executions, 552 general executions and 282 assembled forms.
  It then fails on the separate legacy cache fixture's bare `RET` at line 3.
  Full-suite exit status is 2; full validation remains incomplete.

Normal command:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-slet
```

ASan commands (after building `build/validate-lifetime.abc`):

```sh
/tmp/clang20 -O1 -g -fsanitize=address -fno-omit-frame-pointer -Iinclude -Isrc -Ibuild \
  -c src/vm.c -o /tmp/abc-staging-lifetime-fix/vm-asan.o
/tmp/clang20 -O1 -g -fsanitize=address -fno-omit-frame-pointer -Iinclude -Isrc -Ibuild \
  -c src/residualize.c -o /tmp/abc-staging-lifetime-fix/residualize-asan.o
gcc -g -fsanitize=address -Iinclude tools/validate_lifetime.c \
  /tmp/abc-staging-lifetime-fix/vm-asan.o /tmp/abc-staging-lifetime-fix/residualize-asan.o \
  build/libabc.a -lm -o /tmp/abc-staging-lifetime-fix/lifetime-asan
ASAN_OPTIONS=detect_leaks=1 /tmp/abc-staging-lifetime-fix/lifetime-asan build/validate-lifetime.abc
```

Clang compiles the special calling conventions; GCC supplies its available ASan
runtime at link time because the local Clang 20 installation lacks sanitizer archives.

## Bridge-overhead rerun

`timings.csv` and `timing-summary.txt` rerun the parent's `measure.lua` against the
fixed implementation. Same pre-lowered multiplication, exact runtime argument,
optimization disabled, three modes, three bridges, seven rotated five-call batches
(315 timed calls). All results match 42. Prepare/first-call costs are separate.

Median warm batch-average microseconds per call:

| Mode | archived subprocess | in-process one-shot | prepared session |
|---|---:|---:|---:|
| interpreted | 11551 | 646 | 53.2 |
| eager | 10192 | 614 | 11.7 |
| lazy | 11591 | 877 | 14.9 |

This is a narrow bridge-overhead comparison, not source compilation, native VM
throughput or the old/new ISA baseline. No CPU pinning/frequency control, very
short warm-up, and substantial variation (interpreted prepared batches span
10.4–106.5 microseconds/call). Do not interpret between-mode or between-run
variation as a VM performance regression or improvement. Raw measurements remain
available; the earlier run is not overwritten.

## Completion boundary

The in-process scalar VM-session foundation and teardown correction are now
validated at their stated scope. Production Lua grew from 166 to 216 lines in
stage.lua, plus a 28-line shared ABI binding; optimize.lua shed its duplicate error
ABI declaration. This adds lifecycle/transport checks and tests, not source
arithmetic algorithms.

Source virtual values/places, required-static elaboration, the approved
`staticMode`/CLI source policy, initialization snapshots, aggregate/relocation
transport and managed Let execution are still pending. Public API persistence
and assembly-based image tests do not implement those source capabilities.
