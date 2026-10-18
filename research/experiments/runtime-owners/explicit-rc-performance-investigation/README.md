# Explicit-Rc performance investigation — incomplete cutover

This is diagnostic evidence, not source-owner acceptance or a performance fix.
The implementation under investigation is working-copy snapshot `3c86de05`,
parented by approval `beec9a0d`. No production implementation was changed during
this investigation. The user stopped the broad acceptance run and requested an
investigation; subsequent probes used explicit time limits and no VM execution.

## Frontend finding

The retained access-analysis engine, not Rc placement, dominates compilation.
`let-rc-phases.log` records one instrumented compile of `fixture.lua`:

| Phase | CPU seconds |
| --- | ---: |
| Access analysis | 28.445 |
| Ownership/borrow/strong-edge check after access | 0.218 |
| Semantic build, inclusive | 28.737 |
| Physical Rc placement, inclusive of physical check | 0.193 |
| ABC lowering, inclusive of placement | 0.542 |

There were 79 source functions, 537 source relations, 3,258 access contexts and
6,257 query iterations. Generated assembly was 306,052 bytes; its raw image was
63,809 bytes. Lua heap readings reached 480 MiB after emission; this includes
uncollected garbage, not just retained live state. These are diagnostic single
runs, not repeatable benchmark statistics or evidence of a speedup over the
previous unprofiled 51.4-second run. Worklist order/JIT/GC and instrumentation can
change timing and iteration counts.

`access.lua`'s `request` keys queries by activation, **entire caller state**, and
arguments. It clones that state into each new query. `applyInvoke` passes the full
state; `run` copies states at CFG points and publishes before/after snapshots.
Intermediate state variants remain distinct query identities instead of being
updates to one relevant analysis input. The sampler repeatedly found state
copy/join/key work and GC on these stacks.

The isolated `loop` slice makes this disproportion concrete (`loop-slice.log`):

- 5 source declarations, 4 functions, 22 relations.
- 460 contexts, 1,322 iterations, 2.619 seconds in access analysis.
- The scalar-input `leaf` factory has **154 queries for six call paths**; its
  inputs carry an average 8.53 caller storage roots.
- 6,098 before/after snapshots contain 57,226 root entries.
- Query-key strings total 2,811,614 bytes.
- Lua heap: 95.7 MiB before collection, **44.5 MiB retained after full collection**.

A preceding isolated `variant_loop` diagnostic completed in 17.645 CPU seconds:
11 functions, 74 relations, 1,968 contexts, 3,262 iterations, 26,070 snapshots,
223,047 snapshot root entries, 13,976,372 query-key bytes, 229.8 MiB Lua heap before
collection. Those figures are transcribed from the tool output, not a separately
saved raw log. A simple `main` slice took 0.025 seconds with nine contexts.

Removing the promotion/capability solver did **not** remove this expensive
context/state propagation. The replacement is therefore not yet the intended
simple, fast compiler.

## Optimizer finding

The existing optimizer also has a separate combinatorial cost. Its production
source `src/optimize.c` is unchanged by the Rc cutover.

A temporary instrumented copy (`optimizer-trace.patch`) shows the saved image loads
in about 0.004 CPU seconds and preceding functions finish immediately. Work then
concentrates in function 39, the 11-byte `variant_direct` wrapper. Its tail call
virtualizes `variant`; the ordinary top-level function scan that declines
functions containing allocation is not applied as a boundary to that inlined
callee.

`simulate_tree` explores unknown branches by recursively copying contexts and
replaying their successors, including shared suffixes. Ordered memory/foreign
nodes accumulate separately per path. `node` scans the existing node array for
common expressions; payload lookup also uses linear scans. The path cap is 4,096
**completed leaves**, not a bound on nodes or work. The trace reached 200,000 nodes
and 1,612 leaves at 9.384 CPU seconds before the 10-second process timeout.
This is progressing CPU-bound exploration, not evidence of a deadlock.

A small reproduction uses **no Rc operations**: two functions, an allocation/free
pair, repeated unknown conditional foreign effects and a common suffix of 32
foreign effects. The wrapper causes inlining. `optimizer-repro.log` records:

| Unknown branches | Image bytes | Result |
| --- | ---: | --- |
| 8, wrapper | 391 | 0.052 CPU seconds; unchanged image size |
| 10, wrapper | 409 | 0.701 CPU seconds; unchanged image size |
| 12, wrapper | 427 | killed at the 3-second wall limit |
| 12, direct export, no wrapper | 399 | 0.00033 CPU seconds; unchanged image size |

The 12-branch wrapper also exceeded a preceding 10-second limit. Input-size growth
is tiny; path and node growth is not. Actual Rc aggregate lowering exposes the
same optimizer weakness through considerably larger effectful suffixes.

## Reproduction

Run Lua probes from `frontend/`. The archived phase/slice probes read the adjacent
frozen `fixture.lua`; they do not execute its test harness. They still use the
working frontend implementation, so use the recorded implementation snapshot for
comparisons.

```sh
timeout -k 2s 70s luajit ../research/experiments/runtime-owners/explicit-rc-performance-investigation/let-rc-phase-probe.lua
timeout -k 2s 10s luajit ../research/experiments/runtime-owners/explicit-rc-performance-investigation/let-rc-slice-probe.lua loop
timeout -k 2s 3s luajit ../research/experiments/runtime-owners/explicit-rc-performance-investigation/let-rc-opt-repro.lua 12 wrapper 32
```

The optimizer reproduction writes its small assembly and bytecode under `/tmp`.
The trace patch is for a temporary copy of `src/optimize.c`, built with GCC `-O2`
and linked against the existing `build/libabc-tool.a` and `tools/abc_opt.c`.
Its timing is not directly comparable to the normal Clang build. It logs phase,
function, node and path progress; it does not change optimizer decisions.

Input SHA-256:

- frozen fixture: `622351432e2bb67a4ed1de42b83eab6ae232b2522d730470b07cfd307539f1b5`
- optimizer source: `40d002cf504c40701230327045d66d4c7874ef0d396fda8e28cc33ce22dfbba5`
- generated assembly: `35fe305452fafff82bb2954bf5c20b07d4ec6e6670674384aca6a7e2849c810d`
- raw image: `b6dbba0bf22a17b642059c10b7afa8bf4d5cc0bc6151d0a1b6e36d8d5ecbd197`

## Proposed next design discussion — not implemented

1. Make access checking consume relevant borrowed inputs, observable mutation,
   callable state and actual strong-edge relationships. Stop making unrelated
   caller storage and every intermediate state a new query identity. Preserve
   branch/version correlation and invocation-site environments; simply deleting
   state from a cache key would not be a sound fix.
2. Bound optimizer speculation by actual work/node growth before expensive path
   expansion, and remove the quadratic node/payload lookup costs. Review control
   joins/inlining against the existing optimizer contract. No Rc-specific bypass,
   extra runtime ownership machinery, disabled optimizer or larger timeout is a
   solution.
3. Establish bounded scaling regressions for both reproductions before resuming
   the full source-owner acceptance milestone. The production ownership cutover,
   its safety tests and its test migrations remain unfinished.
