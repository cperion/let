# Ordered callable access-summary composition

User approved correction of the existing live-place/callable retention contracts.
No runtime, ABC encoding, continuation, allocator, parser/sugar or scalar computation
change. No source-body replay or compatibility adapter was added.

## Implemented

- Canonical Borrow points/code origins qualify formals and invocation results.
- Checked bodies produce provenance/state relations once; finite metadata queries
  compose summaries at each invocation's state. Scalar operators are not represented
  or evaluated. These are analysis relations, not executable/residual value IR.
- Callable facts survive parameters, returned values and record components. Concrete
  holding nodes retain value snapshots or live target routes and close finite cycles.
- Physical `Borrow.Target` routes are distinct from retained `Borrow.Source` loans;
  ValueInput/CallOutput are never footprint addresses.
- Removed unordered transfer-only call composition and the opaque-effect substitute
  for formal callback invocation. Opaque supplied borrows without contracts reject.
- Existing legacy Any partial supply is described as callable formation/holdings,
  not mistakenly analyzed as executing a body with missing inputs; runtime behavior
  and its existing unavailable dynamic-lowering admission remain unchanged.

## Evidence

`focused.log`: access **176 checks/112 executions**, aggregate438/422,
receiver407/384, compiler270, lambda269/80. Direct and higher-order retained stores
both reject borrow-store. Forwarding, returned callbacks, record components,
recursive wrappers and block sugar retain that bound. Safe callbacks, interleaved
live-field reads and independent saved snapshots execute in all four modes,
optimized/unoptimized. Returned callback loans and stores have negative controls;
opaque retained arguments/projected results reject. Module alias remains42/one root.

`full-validation-2.log`: final full incremental validation exits0. The earlier
`full-validation-1.log` is retained. `validation-attempt-1.log` records the initial
full-run failure when legacy Any partial supply was incorrectly treated as a full
invocation; the formation semantics were corrected, not the runtime or admission.
Fixture mistakes corrected before focused qualification: ordinary value captures
are snapshots (the negative live test must open a field), grouped free invocation
is required inside a receiver context, and reference-result field access needs an
addressable binding under current admission.

## Measured cost regression

`cost.log`, `../composition-cost.lua`: seven runs of a 12-wrapper callback fixture,
pre-correction working snapshot5040c978 versus current frontend, same runtime.
Median access-analysis CPU: **4.342ms → 11.681ms (~2.7x)**. Median sampled peak Lua
allocation delta: **745.3 → 1588.6KiB**. Last-run retained Lua delta with summaries
alive: **94.0 → 124.3KiB**. Current query counts:120 contexts,36 provenance/state
points,263 evaluations. These tiny noisy measurements are not process peaks or
whole-compilation/runtime performance. An earlier exploratory run varied substantially;
no universal ratio or acceptable preparation-performance claim is made.

## Subsequent investigation (no implementation change)

`investigate.lua` and `scale-{before,current}.log` compare identical sources and
repeated access-only/total typed compilation; warmed, batched medians. Source-known
callback wrapper contexts grow quadratically:120 at12 wrappers,378 at24,1326 at48.
Full input-state copying/keying also tracks unrelated pointer-free locals. At12
scalar wrappers, adding64 unused arrays grows current access time0.290→27.660ms
(baseline0.317→0.681ms). Callback12/64 current146.705ms versus baseline8.421ms.
These are sampled runs, not universal ratios: scaling measurements overlapped a
profiling process, so timings are exploratory, not controlled performance gates.
Context counts and the copying/keying implementation independently expose the issue.

`profile-{callback,scalar,before}.txt`: eight CPU-second LuaJIT line samples;
current copyState/joinState account for32% of callback samples and39% of scalar
samples, with additional recursive schema encoding, empty-fact allocation and
state-key construction costs. Entire states are copied per point/context/call;
formal callback origins generate distinct contexts through each forwarding chain.

A draft counter-only instrumentation probe failed its source-match assertion and
was removed rather than retained as an untested helper. No checker optimization
was implemented; user accepted stopping after these findings.

## Remaining

S05/S06 remain partial: broader recursion/alias overlap, resource/publication,
counted/frozen ownership and serialized/public summaries are not completed by this
fix. Preparation/context/metadata efficiency needs work. No fresh clean build,
sanitizer or pre-packed isolation qualification. Cyclic metadata convergence is not
runtime environment storage reuse/lifetime proof. Packed-float lowering remains
blocked. Historical failed-admission and two-root logs are unchanged. Nothing pushed.

Command:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```
