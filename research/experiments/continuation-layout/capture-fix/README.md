# Capture correction: project values, not deferred mutable homes

## Implemented

The correction is applied to active `src/symbolic.c`, `src/symbolic.h`, and
`src/residualize.c`, after executable validation in two disposable archived builds.
It restores the value-capture obligation identified by
[the projection trace](../projection-trace/README.md).

- Shared symbolic DUP/MOVE/COPY/CGET/CSET/CPUSH transfers capture memory-backed
  inputs before consuming sources or replacing destinations. CGETR and CPUSHN
  use those same operations.
- The native capture binding uses the existing `materialize()` and cache. A
  constant or already-captured register still renames without a memory read.
- Virtual CALL/TCALL move arguments with the same CPUSH operation, rather than
  snapshotting an array of mutable-home descriptors.
- Virtual returns to B capture results in their original order while A sources
  remain live. Returns to A already occupy their result slots.
- Real direct-call results are captured when moving from returned homes to a
  different destination. In particular, results on B cannot retain deferred
  references to A slots that the caller is about to reuse.
- Branch emission keeps a consumed right operand's register unavailable while
  materializing the left operand. The shared branch has popped both cells, but
  both values remain live until their comparison. This uses the existing mask.

No second allocator, native value IR, copy scheduler, exchange stencil, extra ABC
scratch cell, runtime interpreter fallback, or new return convention was added.
The existing register-selection policy is unchanged; this is a capture/liveness
correction, not completion of the shared-generator or version-manager refactor.
Build-time sinks whose inputs are immutable definitions do not need a native
memory-capture binding.

Permanent tests:

- `tools/validate_capture.c`: 14 capture-ordering, failure/PC-preservation and
  register/constant-renaming contracts; added to `Makefile`'s validate target.
- `tools/validate_continuations.lua`: added 12-cell results through repeated
  CALL.A/CALL.B and the consumed-branch-input regression, increasing the suite
  from 234 to 243 executions.

## Executable results

### Original archived layout, with the capture correction

Disposable tree: `/tmp/abc-capture-fix.fQALRj`.

The original four forced general-home conformance failures at PC `0x326` now
return 101 in eager and lazy modes, for both result destinations. No reserved
slots or changed return mechanism are involved in this first build.

`check_capture.py` generates 18 typed fixtures and checks both normal execution
and each jump target with the existing home-conformance operation forced there.
It includes more live values than registers, 64-bit payloads with upper bits set,
CGETR/CPUSHN, both stacks, mutable source replacement, 12-cell calls/results, tail
arity changes 12→9 and 12→13, and branch operand lifetime.

- Before correction: **141 executions, 18 wrong results**.
- After correction: **141 executions, no failures**.
- The old wide CALL.B case also fails without forced conformance: this is not
  exclusively a diagnostic-only boundary problem.

The first capture-only implementation exposed a previously hidden branch bug:
`PUSH.A 101; CGET.B 0; BEQ ...` incorrectly compared 101 with itself when the B
argument was 102. Materializing A had reused B's now-untracked register. The four
native failures and their results are retained in `capture-before-branch-fix.log`
and `before-branch-fix-results.json`; the final implementation protects that
input until the comparison. No test expectation was changed to accept 99.
The CLI prints signed decimal; the checker compares exact 64-bit payloads.

Other successful archived-build checks:

- 14 capture contracts and the existing symbolic validator;
- 243 continuation executions (also retained the earlier 234-case run);
- 1,800 exact-state interpreter handlers and 655 cache transitions;
- 48 differential cases/all public opcode forms;
- portable-C residual arithmetic, branches, loops, calls and export ABI;
- compiler 276, lowering 100, optimizer 128, staging 24 checks.

### Same correction in the existing reserved-slot experiment

Disposable tree: `/tmp/abc-reserved-capture.zAuMfW`.

The same capture correction was applied to the pre-existing reserved-slot probe.
Its only integration adjustment advances the symbolic C bias over the already
reserved cell before CPUSH gathers virtual-call arguments; this keeps their
homes identical to the old probe's argument placement. It does not adopt that
layout in production or introduce another return convention.

- **All four formerly failing native tail/materialization runs now return 101.**
- Each ample-stack forced native tail run completes all ten general entries;
  escaped root identities and read/write-through-alias assertions survive.
- Fixed-arity layout/alias sweep: **1,188 executions**, checks pass.
- Tail sweep: **594 executions**, checks pass.
- Experimental reserved/transfer configurations agree across interpreter,
  eager and lazy on success/failure and stack diagnostic. First successful
  capacities are 15 cells for fixed arity and 16 for changing tail arity.
- The original baseline's lower eager capacity requirement and diagnostic
  disagreements remain recorded, not silently declared fixed.
- The expanded **243 continuation executions** also pass with reserved slots
  enabled and no forced edge.

The original `check_tail.py`, which expects the old failure, was not rewritten.
The new `check_tail_capture.py` requires semantic success and preserves the old
counterexample in the parent report.

## Still unresolved

**The tail probe still creates two legacy general contexts at the same PC:**
zero bias for materialized virtual calls and bias one for the legacy real-call
arrival. `LEGACY_GENERAL ... versions_at_pc=2` remains in the successful logs,
and the new checker explicitly records that count. Thus success here does not
prove one reserved general version, the eight-version budget, or bounded adapter
accounting. The next versioning work must address that entry-contract issue;
this capture correction establishes no need for a new return ABI.

Strict eager publication, shared site ownership, the typed-only teardown and GC
validation are not completed by these tests. No performance/code-size claim is
made. The diagnostic builds are not benchmark evidence.

## Active-tree validation status

The core patch is present in active sources. Its 14 contract tests also pass
compiled directly against the **active typed** `src/symbolic.c` and `src/module.c`:

```sh
/tmp/clang20 -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
  -ffunction-sections -fdata-sections -Iinclude -Isrc -Ibuild \
  tools/validate_capture.c src/symbolic.c src/module.c -Wl,--gc-sections -lm \
  -o /tmp/active-validate-capture
/tmp/active-validate-capture
```

The modified active runtime sources pass syntax checking with the historical GC
header configuration required by the still-present, unused `gc-api.h` include in
`src/residualize.c`:

```sh
/tmp/clang20 -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
  -Iinclude -Isrc -Ibuild -isystem vendor/whippet/api \
  '-DGC_ATTRS="mmc-attrs.h"' -DGC_CONSERVATIVE_ROOTS=1 \
  -fsyntax-only src/symbolic.c src/residualize.c
```

That is **not a successful production build**. The paused typed-only teardown
still has stale consumers and a missing validator. Full execution results above
belong to disposable archived builds with the same capture correction. The
unchanged historical GC include was not removed as an unrelated part of this
patch. Patch dry-runs, reverse dry-run against active core sources, Python syntax
checks and `git diff --check` pass.

## Reproduction

For original-layout results, reproduce `../projection-trace/README.md` in a
fresh archived copy. Preserve its diagnostic runtime as `before-runtime`, apply
`capture.patch`, and rebuild. Copy `check_capture.py` to the copy's root and run
it there. The forcing hook comes from the parent diagnostic patch, not the
capture correction. Copy the two permanent validators from this directory when
reproducing the expanded suites.

For reserved-slot results, reproduce the original reserved-slot experiment,
then apply **`reserved-capture.patch` instead of `capture.patch`**. Rebuild with
`-W src/residualize.c`; retain the original unmodified baseline binary as
`original-runtime`. Copy `check_tail_capture.py` into that disposable root, then
run it and the unchanged `check_reserved.py`. (The old fixed-arity checker's
limits text refers to its old companion tail checker; the new tail evidence is
in this report.)

Build flags for either disposable copy:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' all
```

`capture.patch` applies directly to the archived snapshot as well. No forcing
or tracing hooks are needed for ordinary execution or the permanent validators.
Raw JSON, generated fixtures, diagnostics, checksums and logs accompany this
report. Earlier failures remain under `../projection-trace/` and
`../reserved-slots/`.
