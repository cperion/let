# Explicit Rc cutover qualification

This records the initial §8 implementation, not completion of WORKLIST O01–O08/E01/E02 or admission of the remaining owning interfaces. Earlier experiments are unchanged.

`source.sha256` records the final frontend/test files and relevant native ownership/optimizer boundaries (62 files), not the complete build dependency closure. `artifacts.sha256` records eight local images, assembly, validator and libraries. Both manifests use repository-relative paths and passed `sha256sum -c`. Earlier measurement logs are retained as their own observations; the source manifest identifies the reviewed checkpoint, not every intermediate measurement.

## Architectural replacement

`access.lua` now checks the original typed IR through a local CFG. It does not build the former expression/ownership dependency IR. A call-site binding has one joined input and result, never an identity containing caller memory. Only argument-reachable contents and named globals cross calls. Scalar register values are not analysis facts. Private reads/writes stay private, including effects of callees borrowing a local. Scalar-only boundaries without named globals are checked once, including their local allocations; other boundaries retain finite call-site contexts where alias/provenance relations matter.

The remaining facts serve borrow protection, readonly permission, actual callable environments, active alternatives and strong edges. CFG joins preserve possible invalidation; copied field values do not become later field contents. Captured values are read from the actual invocation environment. Missing/opaque checked provenance rejects. Ref escape does not create a holding, and erasure does not remove known borrow obligations.

The old whole-caller-state query keys, before/after publication, contents-version/carrier/dependency graph, loan-demand/capability/preservation solver and inferred resource ABI are removed. `Lifetime` and its unused schema contracts are removed. `Ty.Owned` is unchanged in meaning. Placement selects actual declared owning fields, caller-visible owning-value slots and active-tag drops. Pure/nonowning transport does not gain synthetic cleanup captures. Physical diagnostics map back to original source nodes; named type definitions accompany the checked program for ABI gates.

The C owner core and six bindings are unchanged. The native validator's former extra preservation field was replaced by the actual one-cell `Box.child: Rc(Point)` layout. The private-recursion regression checks that an unrelated recursive child's allocation does not invalidate a borrow into the caller's allocation merely because they share a source site.

## Checks actually run

- `make validate-source-owners`: **1,718 checks / 560 VM executions**, raw/optimized, four modes and both lifecycle banks. Native qualification: **2,560,862 checks**, including allocation and every nonnull-acquire failure, partial aggregate cleanup, replacement/self-replacement, trap/stack failure, publication failure and 100,001-object generated-C drains on a small pthread stack outside VM TLS. Exact holdings and peak owner bytes are asserted for 21 cases. See `structural-source-owners.log`; earlier passes are retained.
- `make validate-slet`: passed the complete frontend target, staging sessions, 112 source/optimizer executions and 12 mirrored portable-C cases. Borrow/effect tests: **172 checks / 120 executions**; ownership checking: **55 checks**, including actual named-payload type validation and unique allocation identities. The loop scaling test has **7 bindings / 13 iterations**; scalar call diamonds have one binding per function. See `acceptance-frontend.log`.
- `make validate-optimizer-isa`: **58 mirrored modules / 340 execution pairs**. New regressions cover frame-bearing call/tail wrappers and branch/effect expansion without Rc or frame allocation. See `optimizer-isa.log`.
- `make validate-c-entries validate-owner-core validate-no-collector`: passed; see `runtime-boundaries.log`.

The optimizer changes enforce its existing frame-materialization boundary during inlining too, and decline already-unsupported multi-path non-call effects before path expansion. Ordered nodes no longer undergo a guaranteed-failing common-expression search. No Rc-specific optimizer mode or disabled optimization was added. The unchanged 427-byte reproduction now finishes in **0.000791 CPU seconds**, under the original three-second bound (`optimizer-reproduction.log`).

## Measurements and remaining costs

`measure.lua`, run from `frontend/`, compiles the unchanged diagnostic fixture:

- 79 functions; **281 bindings / 561 iterations**, 537 source CFG points;
- **2.544576 CPU seconds** compilation, including **0.958663 seconds** access checking;
- Lua heap: 1.524 MiB before, 17.519 MiB after compilation, **9.189 MiB after collection**;
- 305,985 assembly bytes; 63,794 raw / 63,776 optimized image bytes; optimizer **0.010879 seconds**. See `final-frozen-measure.log`; earlier samples are retained in the other logs.

These are local observations, not pinned repeated benchmarks or a guaranteed complexity bound. The previous instrumented fixture had 3,258 bindings / 6,257 iterations and 28.445 seconds in access checking; the interrupted broad run had 51.4 seconds total frontend time. Instrumentation, JIT and collection conditions differ.

The expanded current fixture additionally checks private recursion and borrowing through a named recursive Rc field: 289 bindings / 583 iterations, 2.565 frontend CPU seconds, 314,006 assembly bytes and a 65,525-byte raw image. Its cleanup declarations total **5,576 bytes / 235 typed slots**, largest frame **424 bytes**. These are static declarations, not peak stack storage. Count traffic is deliberately not called optimal: `variant_replace`, for example, performs **47 holds**, allocates four owners and peaks at 200 owner bytes. Proven copy/move elimination remains separate work; correctness does not depend on it.

The final structural review also rejects a named Rc borrowed as an unrelated payload layout and allocation identities colliding with local storage. The named recursive-field borrow executes in the native fixture, not just a hand-built IR test. The full frontend and source/native target were rerun after these checks (`structural-review.log`, `structural-source-owners.log`, `acceptance-frontend.log`).

## Qualification limits

The focused ASan/UBSan/LSan build was attempted and **blocked before execution**: installed Clang 18 does not support the required `preserve_none` handler ABI. See `sanitizer-blocked.log`. No warning, ABI attribute or check was disabled to obtain a pass. `validate-sanitizer.sh` accepts `CC_SANITIZE` for a suitable compiler and `SANITIZER_LINK_CC` for its sanitizer-runtime linker. Its intended instrumentation is the validator, owner/lifetime, VM, native image/emitter, threaded emitter, residualizer and memory-module boundary; generated engines/machine code and other archive objects are not instrumented. No sanitizer acceptance is claimed.

The entire top-level `make validate` target, clean rebuild, TSan, wasm/browser, owning public/foreign/erased/callable/task/container contracts and `.let` execution are not qualified here. Borrowed/erased escape fixtures now reject instead of expecting implicit promotion; admitted owning scenarios execute as Rc. Owning callable scenarios remain explicit interface-gate tests, not claimed runtime coverage.

Code/document whitespace checks pass excluding the immutable diagnostic `optimizer-trace.patch`, whose raw patch context contains a whitespace-only line. That archived evidence was not rewritten to silence `git diff --check`.
