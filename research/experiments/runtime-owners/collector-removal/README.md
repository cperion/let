# D07 — collector dependency removal

Approved removal slice atop `42d88634`. This removes the dormant collector, not the
remaining owning public/FFI/module/task implementation gates. WORKLIST owns status.

## Changes and preservation

- Deleted all81 tracked files under `vendor/whippet` (about720KiB on disk).
- `src/whippet_types.h`, `src/any_repr.h`, `src/dynamic.c/.h` were already absent.
  No remaining active collector build/CI integration, tracing adapter, root/collection
  call or obsolete GC example/test required another runtime removal.
- Added `tools/validate_no_collector.lua` and `make validate-no-collector`, included
  in `make validate`. It scans active source/build/dependency paths (including
  untracked files), rejects collector names/APIs/link flags and executable archive
  references, and checks the vendor path is absent even when empty.
- Historical archives/raw logs are unchanged. Markdown can describe history and the
  no-GC contract. Build outputs, research evidence and VCS/agent metadata are excluded
  from the source scan; built artifacts are audited separately below.
- The guard excludes its own negative-control strings. It is a regression audit,
  not a proof against obfuscated/dynamically constructed dependency paths.
- Owner/lifetime runtime code, foreign synchronization, traps and stack limits did
  not change. The residual `safepoint` effect bit currently marks conservative call
  synchronization, not collection; it is deliberately preserved and documented.

## Actual qualification

- `validate.log`: full incremental `make validate` passed. Includes the dependency
  guard, source1110 checks/352 calls, C1043242 cleanup checks,48 public module/VM
  lifetime cases, four-mode image/foreign/API checks and the remaining frontend,
  optimizer, emitter, continuation, capacity and oracle suites.
- `audit.log` / `audit-final.log`: active tree scan passed (234 files,17 positive/negative probes).
  After the full run, the explicit empty-vendor-path check was added; the final
  focused guard and filesystem controls passed. No runtime code changed afterward.
- `negative-controls-final.log`: eight isolated filesystem scenarios passed, including
  deliberate failures for an empty vendor directory, collector API/link dependency,
  archive source include and archive symlink. Preserved archives and generic call
  barriers are accepted. `negative_controls.py` reproduces these checks in temporary
  directories outside the repository; expected rejection traces are not failures
  of the qualification run.
- `link-audit.log`: `readelf` finds only ordinary system dependencies in runtime and
  tooling binaries/libraries. `nm` finds no collector symbols in runtime/tooling
  static/shared libraries; retired paths are absent.

This is **not** a clean rebuild, fresh sanitizer/race qualification, performance
measurement, completed generalized ownership, or owning public/foreign/task support.
The current supported source boundaries remain those qualified in `source-cutover/`.

## Reproduction

```sh
make LUA=/tmp/lua-compat validate-no-collector
python3 research/experiments/runtime-owners/collector-removal/negative_controls.py
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
readelf -d build/libabc.so build/libabc-opt.so build/abc-runtime build/abc-opt
nm -A build/libabc.a build/libabc-tool.a build/libabc.so build/libabc-opt.so \
  | grep -Ei '(^|[[:space:]])(_?gc_|whippet|GC_)' # expected: no matches
```

The guard uses the project's Lua tooling and GNU `find` for NUL-delimited file/link
paths. Python is only needed for the separate filesystem-control reproduction.
No runtime/build dependency on Python was added.
