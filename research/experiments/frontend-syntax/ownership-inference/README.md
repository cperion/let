# Qualified source owner-inference implementation

Status: implemented source-analysis chunk, **not counted execution or collector
retirement**. `WORKLIST.md` O01–O03 remain partial; O04–O08/E02 are not completed.
This records the approved private summary binding, not a replacement ownership model.

## Code and data flow

- Canonical schema: `frontend/ir.asdl`, generated `frontend/let/schema/ir.lua`.
  `Ownership` descriptors represent formal/fresh/module/deferred roots, component
  results, conditional holdings, independent activation evidence, strict edges and
  counted requirements. They are not runtime values, placement or another evaluator.
- `frontend/let/access.lua` still inspects each checked body once and composes its
  provenance/state relations through the existing worklist. It now records owner
  obligations at initialization, stores, captures, returns and calls. Address-exposed
  locals, retained fields and environments get context-qualified allocation families.
  Direct-call propagation avoids cloning scalar-only summaries by full call path.
- Nested factory calls distinguish fresh roots; copied refs and interior projections
  preserve the original root. Reachable result state, including callable holdings,
  transports back to the caller; unrelated callee locals do not.
- A materialized callable value retains its environment root; capture dependencies
  are environment holdings, not duplicate direct loans that create spurious self edges.
- `frontend/let/ownership.lua` solves counted requirements to a worklist fixed point.
  Counting a holder invalidates its activation-only borrowing of outgoing holdings.
  An iterative SCC traversal checks strict edges and provides an actual edge/source
  witness. No runtime ranks, graph scans, cycle detector or recursive release exists.
- Formal inequalities are conditional on borrowing/owning specialization: bounded
  actual roots can discharge a formal self inequality; concrete counted roots cannot.
  Repeated recursive call sites fold to finite families. Family equality is not a
  lifetime proof. Actual same-activation formation has separate evidence; relative
  origin markers are cleared at call boundaries, never inferred from family equality.
- `check.lua` replaces the old hardcoded local frame-store/return tests with inferred
  counted requirements. It still rejects required counted placement/release as
  `borrow-return`/`borrow-store`. Cyclic concrete ownership rejects as `Ref-cycle`,
  with canonical `ownership`/`witness` evidence on the diagnostic. Raw pointers export
  neither a checked owner-result loan nor a strong edge.

No backend, bytecode encoding, cell width, runtime allocator or collector changed.
These summaries have not become a stable separate-compilation/public ownership ABI.
Finalized ranks/placement, retain/release, cleanup, COW/containers, tasks, erased/dynamic
admission and broader recursive borrow precision remain incomplete. Recursive family
folding is deliberately conservative; this is not acceptance of all bounded programs.

## Validation

From the repository root:

```sh
cd frontend
/tmp/lua-compat tests/schemas.lua
/tmp/lua-compat tests/ownership.lua
/tmp/lua-compat tests/access_proofs.lua
/tmp/lua-compat tests/receiver_scopes.lua
```

`focused.log`: ownership **170 checks / 56 VM executions**, access176/112 and
receiver407/384. Ownership executions are bounded cases in all four modes, optimized
and unoptimized; they do **not** exercise runtime counting or reclamation. New proof
cases exercise interior/self retention, closure/object cycles, joined mutually
exclusive edges, initialization/copy destinations, fresh roots through nested
factories, reference aliases, conditional formal self bounds, recursive forwarding
and rejected growing owning chains, module roots and raw-pointer exclusion. A checked-IR
factory tests address-bearing result-state transport. The shared solver also checks a
1200-root DAG/cycle, formal-backedge SCC counterexample, folded-family borrow rejection,
and insertion-order-independent summary canonicalization.

Full incremental validation passed in `full-validation-2.log`,
`full-validation-3.log` and `full-validation-final.log`:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

The final suite/focused run also covers diagnostic witness formatting and distinct
folded/unfolded callable-code identities. `source.sha256` records the final source
files. No clean build, sanitizer, counted resource/lifetime, native-image growth or
peak/RSS result.

Failures retained rather than counted as passes:

- `focused-attempt-1.log`/`-2.log`: fixture omitted the compiler's explicit static
  execution option / supplied it in the wrong argument. `-3.log`: the fixture attempted
  direct field access on an unbound call result, which existing place syntax rejects.
  `-4.log` is an intermediate 140/48 pass, superseded by `focused.log`.
- `full-validation-1.log`: initial recursive-family treatment over-rejected an existing
  frame-local recursive environment. Corrected with actual-activation formation
  evidence and boundary clearing, **not** a recursive safety exemption or runtime fallback.
- `cost-*-attempt-1.log`: measurement setup errors (missing baseline letkit path and
  reading stats from a copied function list). These contain no usable cost result.

## Cost evidence and limitations

`measure.lua` compiles the same sources seven times per case and reports medians.
Analysis includes access plus owner inference when present; the baseline has only
access inference. It also reports an after-return live Lua-memory delta, **not peak,
retained-memory or process-RSS measurement**. The baseline is the pre-edit working
checkpoint `b560dc1e50d3`, not the last published revision. It was reconstructed by
copying the current frontend support files, then restoring `let/access.lua`,
`let/check.lua`, `let/schema.lua` and generated `let/schema/ir.lua` from that checkpoint.
All other source/runtime files are shared unchanged. Temporary baseline path for this
run: `/tmp/let-owner-before.Wb5y9xSL`.

Run from either frontend directory (baseline also needs the repository tools/build
paths in `LUA_PATH` and `ABC_RUNTIME_LIBRARY` set to the same built library):

```sh
/tmp/lua-compat /home/cperion_ext/dev/let/research/experiments/frontend-syntax/ownership-inference/measure.lua
```

Early baseline/current probes were run serially, then repeated in reverse order
(`cost-before.log`, `cost-current-pre-final.log`, `cost-before-repeat.log`,
`cost-current-pre-final-repeat.log`). Those preceded final diagnostic/raw-pointer
filtering/helper cleanup and folded-code identity changes; they are not final-code
measurements. `cost-before-final.log` and `cost-current.log` provide later baseline
and final-source samples. These were separate processes with uncontrolled host
scheduling, not an alternating, pinned timing experiment. Selected analysis CPU
medians in milliseconds:

| Case | Early before/current | Early reverse-order repeat | Later before / final current |
| --- | ---: | ---: | ---: |
| scalar12 wrappers | 0.838 / 2.497 | 0.997 / 2.238 | 0.814 / 0.971 |
| scalar40 wrappers | 1.682 / 5.925 | 1.161 / 2.467 | 1.008 / 3.452 |
| callback12 wrappers | 39.280 / 41.841 | 27.011 / 37.551 | 19.871 / 36.115 |
| callback24 wrappers | 93.084 / 92.050 | 49.774 / 91.806 | 33.117 / 80.547 |

There is added analysis work and sampled scalar/callback regression; timings are
variable and do not establish a precise slowdown or acceptable performance. An
intermediate `cost-current-before-codeflag.log` is also retained. Scalar queries/evaluations remain14/14 and42/42. Callback queries/evaluations
increase120/263→121/264 and378/803→379/804. The logs retain total typing and live-memory
samples as well. These are small source probes, not universal costs, acceptable
performance proof, or runtime/count-traffic benchmarks. Efficiency remains deferred;
no performance improvement is claimed.
