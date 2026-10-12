# Revision-6 cache fixtures and remaining shipped examples

## Scope and exit

Finish the documented fixture integration blocker without changing the runtime,
cache policy, scalar algorithms, ABI or oracle expectations. Exit: cache cases and
shipped examples execute, followed by a clean full active validation run.

## Changed responsibilities

- `tools/validate_cache.lua`: replaced historical COPY.AB/COPY.BA and
  MOVE.AB/MOVE.BA with source-selected COPY.A/COPY.B and MOVE.A/MOVE.B;
  output draining uses MOVE.B and explicit RET.A. The independent logical A/B/C
  arrays, expected values, all 655 cases and repeat-call coverage are unchanged.
- `examples/divmod.abcasm`: explicit RET.A for both ordered result vectors.
- `examples/memory.abcasm`: explicit selected global loads/stores, address-selected
  ST64.A and RET.A. Existing address/value placement was already appropriate;
  no reordering or repair moves were added.
- `tools/validate.lua`: permanently tests both shipped examples and their A/B
  mirrors in all three execution modes. Independent expected results cover main,
  runtime divmod arguments, aggregate frame results, image state, address-valued
  loads and the large-frame entry. Foreign/callable/virtual examples remain
  covered by their existing API integration tests.

No historical-syntax translator, replacement oracle or skipped suite was added.

## Evidence

- Focused cache run: **2,400 exact-state poisoned-argument checks**, plus **655
  cache-transition cases**, each invoked twice through the public API.
- `full-validate.log`: in-place full `make validate` passed after cache migration,
  before adding the final example cases (92 general cases / 552 executions).
- `general.log`: final general suite passes **97 oracle cases / 582 mirrored
  three-mode executions**, assembling all **282 public core/EXT forms**.
- `clean-full.log`: a fresh copied-source **`all validate` passes**, including the
  final examples, all cache cases, 495 continuation executions, 209 lambda checks /
  60 executions, the frontend/session/lifetime suites and the other active targets.
  `clean-path` identifies `/tmp/abc-r6-clean.uwQnhE`. Source copy excluded `.git`,
  `.pi`, `build` and historical `research`; it did not reuse generated build files.
- `git diff --check` passes.

Command in the clean source directory:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' all validate
```

The cache generator and two example files have no source-line growth (25 lines
replaced across the three files); five example oracle cases were added to the
existing general validator. No performance rerun was made because runtime and
lowering implementations did not change in this chunk.

## Remaining boundary

Full active validation is no longer blocked. This does not complete the migration:
phase-5 old/new fixed-baseline performance comparison, comprehensive dead-path /
contract / documentation audit and complete-diff review remain pending. The
separately approved source virtual-value and static-demand architecture also
remains unfinished. Earlier failed validation logs are preserved as historical
checkpoints, not current blockers.
