# Reserved continuation slots: actual-transfer experiment

## Verdict

**Promising layout, incomplete general-entry design.** Reserving continuation
slots at virtual-call entry permits the tested nested frames to transition to a
shared general native block and return through actual materialized ABC
continuations without moving address-exposed objects. However, an argument-count-
changing tail call exposes a home-conformance bug and distinct legacy general
entry origins. This is not ready for production adoption.

No production runtime files were changed. Changes live in the disposable copy
`/tmp/abc-cont-reserve.DHqoVq` and in the excluded experimental patch here. The
original source is the archived pre-teardown snapshot, not the incomplete active
working tree. No performance claims are made.

## Changes tested

1. The native call sink asks symbolic virtual calls to reserve one physical C
   cell for a continuation, without writing a return target or changing logical
   bytecode-visible C depths. Capacity checks include that cell.
2. Physical C homes are computed per owning virtual frame. One global
   `c_bias - c_origin` is no longer sufficient for all logical C cells: outer
   frames precede the reserved gaps. This mapping uses the existing continuation
   records and symbolic cache, not another register allocator.
3. An environment-selected interior edge forces materialization. This deliberately
   bypasses admission-policy questions to test the transport mechanism itself.
4. On that edge the prototype publishes values, writes native resume labels into
   the reserved cells, rebases the stack frontiers and jumps to a general version
   of the same original PC with no virtual continuations.
5. Actual `RET` instructions load those labels and transfer to native resume
   adapters. The adapters restore caller frontiers, route ordered results to A
   or B, and jump to general versions of the callers' return PCs. No helper
   recursively executes ABC. Diagnostic helpers only inspect/count events.

The resume adapters are experiment-only code and are **not accounted for by a
new production eight-version policy**. The old admission policy is still in use.
This probe demonstrates transport for particular entry contracts, not bounded
code growth for the entire design.

## Fixed-arity results

The original `layout-A/B` fixtures are described in the parent directory.
`alias-A/B` add explicit equality checks between frame addresses and escaped
pointers, then write 304 through the escaped leaf pointer and read it back via
frame addressing. The resulting sum must be 607 rather than 606.

At the materialization point, all three object locations remain stable:

| Object | Reserved-layout C cell before and after transfer |
| --- | ---: |
| main | 1 |
| middle | 6 |
| leaf | 12 |

There is no insertion, relocation or pointer repair. Both destination variants
retain live caller A/B/C values, return two results in order, and finish with 101.
All tested incoming materialized contexts reuse one general leaf entry at PC
`0x319`. The native logs verify unchanged root addresses, their contents, and
live leaf operands 555 and 666 after entry.

### Validation

`check_reserved.py` ran **1,188 executions**:

- original, reserved-slots-only, and forced-transfer configurations;
- original and strengthened alias fixtures, both A/B destinations;
- interpreted/eager/lazy policies;
- capacities 1–32 and 1024.

All 36 ample-stack executions returned 101. For the two experimental
configurations, the tested success/stack-failure outcomes and failure diagnostics
agree across policies. Every policy first succeeds at 15 cells. The original
engine's eager success at 14 cells and one lower-capacity diagnostic disagreement
are retained in `reserved-results.json` rather than hidden.

For each fixed-arity fixture/destination, the ample-stack forced-transfer run
records 10 general entries and 15 materialized returns in eager mode, or 14 in
lazy mode. Later calls may already use real continuations under the old admission
policy; these count as controls, not additional materializations.

The existing **234-execution continuation suite also passes** with reserved slots
and no forced-transfer environment variable. That suite includes recursion, tail
calls, register/home arguments, result arities and stack exhaustion. It does not
exercise the new forced interior transition.

## Tail-call stress: important failures retained

`tail-A/B` introduce `leaf → TCALL leafwide`, changing three arguments to four
before creating the leaf object. The forced edge is now PC `0x326`.

### Finding 1: original argument count is not the current return origin

The first adapter implementation derived the child stack-pointer origin from
its original CALL signature. After the tail call, that is wrong by one cell.
The first return failed the middle frame's live-C check (`ABORT 8`).
`tail-before-A-lazy.log` preserves the counterexample.

The experimental adapter now uses the actual current origin (the next saved
virtual frame's `old_bias`, or the current context's `c_bias`), not the original
callee's argument count. The materialized nested activations then return
successfully. This is an implementation requirement, not justification to add
argument-count families to the version budget.

### Finding 2: canonical home stores are not a parallel copy

When the old admission policy later uses a real call, the forced interior edge
finds these displaced sources:

```text
C logical cell 0: constant dummy argument → home -3
C logical cell 1: source home -3         → home -2
C logical cell 2: source home -2         → home -1
C logical cell 3: source home -1         → home  0
```

The old `conform_context` walks forward and overwrites a source before its last
reader. The middle-pointer equality check catches the corrupted argument with
`ABORT 12` at byte `0x33d`. `tail-trace.log` and the final `checked-tail-*` logs
record the source/destination map. The stack objects themselves have not moved;
this is value-transport alias corruption.

This was **not patched with a reversed loop or fixture-specific workaround**.
The refactor needs dependency-safe home/register conformance through the existing
symbolic allocator, including overlapping copies and cycles.

### Finding 3: a reserved slot alone does not canonicalize every return ABI

The real-call tail path retains `c_bias=1`, while the materialized path has a
canonical zero-bias entry. The old engine therefore creates two legacy general
contexts at the same leaf PC. The diagnostic initially asserted a zero bias for
every entry; it was corrected to inspect each actual entry contract, not to
change execution. Both retained contexts are visible in the logs.

We have **not** demonstrated the new single-reserved-general-slot requirement
for this case. A canonical return-frontier convention must be designed before
simply rebasing away the bias: the existing real caller's continuation expects
its original callee-entry frontier.

### Final tail results

`check_tail.py` ran 18 ample-stack executions:

- 14 controls succeed (original engine, slots-only, and interpreted execution).
- All four forced native cases still fail the pointer equality assertion after
  the overlapping-home conformance described above.
- Eager reaches six successful two-continuation materializations before failure;
  lazy reaches seven. The failing general entry is respectively the seventh or
  eighth activation.

The checker intentionally verifies these counterexamples. Its successful exit
means the recorded failure reproduced, **not that tail materialization is correct**.
Full outcomes are in `tail-results.json`. No tail stack sweep or full dynamic/GC
validation was performed.

## What this establishes, and what it does not

Established for these fixtures:

- Reserved physical slots can keep escaped frame addresses stable.
- Storing continuation targets can remain deferred until materialization.
- Nested virtual state can become real ABC continuations and execute returns,
  including both result destinations, without host-recursive ABC execution.
- Charging the reserved slots removes the observed fixed-arity capacity mismatch.

Still required:

- An alias-safe general conformance algorithm, not sequential home publication.
- A canonical continuation/return-frontier contract that also covers
  argument-count-changing tail calls and existing real-call entries.
- Accounting for resume realizations within the agreed code-growth budget.
- More shapes, deeper nesting, lazy publication/failure tests and effect-boundary
  validation. GC safety of reserved uninitialized slots is not addressed here.
- Startup, steady-state and code-size measurements after correctness; diagnostic
  calls and forced publication make this build unsuitable for timing claims.

A possible next design experiment is to make native returns expose a stable
frame boundary (for example, the continuation-cell position) rather than the
callee's argument-end pointer. That could decouple caller restoration from tail
argument count. It has **not** been implemented or approved as a new ABI here.

## Reproduction

Start a fresh disposable copy, as in the parent experiment. Build the unmodified
archive and preserve `build/abc-runtime` as `original-runtime`. Copy the parent's
`probe_generate.py`, and copy this directory's `strengthen_fixture.py`,
`tail_fixture.py`, `check_reserved.py`, and `check_tail.py` into that copy.

Then, inside the disposable copy (`probe` below is this directory's absolute path):

```sh
patch -p1 < "$probe/experiment.patch"
cp "$probe/reserved_probe.inc" src/
make -j4 -W gen/stencils.lua -W src/residualize.c \
  LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' build/abc-runtime
python3 probe_generate.py
python3 strengthen_fixture.py
python3 tail_fixture.py
python3 check_reserved.py
python3 check_tail.py
luajit tools/validate_continuations.lua
```

The scripts set the forced-edge variable only for the transfer configurations.
Use `-W src/residualize.c` after editing the included experiment file: it is not
part of production build dependencies. The prototype's fixed 32-continuation
scratch bound and global diagnostic counters are fixture instrumentation, not a
proposed runtime policy or thread-safety contract.
