# First staging-session implementation slice

**Status: approved, implemented and validated at the scalar-session boundary.**
The exposed public-runtime lazy teardown use-after-free was separately approved
and corrected; 27 ASan lifetime cases and 217 session/ABI checks pass, including
abandoned-session GC. The source API policy
in [source-compilation-api.md](source-compilation-api.md) is approved but its source
integration remains pending. This slice resolves its first infrastructure dependency;
it does not implement source-demand elaboration or virtual values by itself.
Evidence and remaining integration failures are recorded in the
[session report](../research/experiments/source-partial-evaluation/staging-session/lifetime-fix/README.md).

**Working-tree extension:** supported pointer-free aggregate products and persistent
module-root bytes now have focused/full-suite qualification; reference/environment
snapshot transport remains unsupported. The access proof is still incomplete due
to a higher-order retention hole. See [module image copying](module-image-copy.md)
and the [current WIP evidence](../research/experiments/frontend-syntax/module-aggregate-access/README.md).
The scalar slice's historical guarantees/results below remain distinct.

## Pre-implementation finding

The public VM API already supports the required owned state:

- `abc_module_load` independently verifies module bytes.
- `abc_vm_create` selects interpreter/threaded/eager/lazy and stack resource limits.
- `abc_vm_load` associates a module/image with that VM.
- Repeated `abc_vm_call` calls reset operand stacks but retain module-image writes.
- VM images retain their modules; explicit VM/module destruction releases them.

The current build supplies only a static runtime library. The shared optimizer
library is not a runtime and must not become one. `stage.lua` currently serializes
through temporary files, starts a subprocess per call and parses text errors.

## Implemented boundary

### Runtime binding, no runtime semantics change

Build `build/libabc.so` from PIC versions of the existing runtime sources and
same generated handlers/stencils. Keep `libabc.a`, the CLI executable and
`libabc-opt.so` separate. Add precise generated-header prerequisites so clean and
parallel builds work. No new public C API, instruction or VM algorithm is needed.

Use a shared frontend FFI declaration module for the existing public ABI types;
`optimize.lua` and the new staging binding must not independently redefine
`abc_error`. This is type binding, not shared execution orchestration: runtime
execution never calls the optimizer. Library loading failures are explicit.

### Session API

```lua
local session = Stage.open {
    mode = "interpreted", -- also threaded/eager/lazy policies
    stackCells = optional_resource_limit,
    optimize = false,     -- optional bytecode optimization, not an evaluator
}
local program = session:prepare(artifact, checkedFunctions)
local result = program:call {
    entry = "main",
    arguments = exactTypedCells,
    progress = optionalCallback,
}
session:close()
```

- A session owns one VM and its prepared program handles.
- A prepared handle owns verified module identity plus source/provenance maps.
- Reuse of that handle retains its image; separate prepared modules/sessions must
  not be merged solely because their serialized bytes happen to be equal.
- Mode/stack/optimization policy is fixed for the session. No per-call policy
  switch may silently create a fresh image.
- Deterministic close releases VM then module ownership; close is idempotent.
  Calls on closed handles fail explicitly. GC finalizers are defensive cleanup,
  not the primary lifetime protocol.
- A module's public export signature is checked against the requested typed scalar
  transport contract before a call. Address-bearing/aggregate transport is not
  guessed from one-cell-per-source-value counting.
- Errors come from structured `abc_error`, not parsing CLI output. Preserve status,
  abort reason, bytecode provenance, IR node/span and resource/error categories.
- Foreign execution is unavailable, matching current staging policy. There is no
  foreign-binding API exposed by this staging session.

The initial transport is the existing exact raw-cell scalar product: integer,
bool, unit omission and f64 bit patterns. The shared runtime is selected with
`ABC_RUNTIME_LIBRARY` when a host override is needed. Do not perform source arithmetic or
conversions in Lua. Aggregate snapshots, pointer relocation and managed values
remain explicit unsupported capabilities until designed.

### Replace the old bridge

`Stage.execute` and `Compiler.stage` retain their existing one-shot behavior by
opening a session, preparing/calling once and closing on every exit. They use the
new service, not the old subprocess code hidden underneath. Remove temporary-file
execution and text result/error parsing from `stage.lua`.

The old custom runtime-executable option cannot select an in-process library.
Reject that obsolete option explicitly rather than silently ignoring it or keeping
a second execution path. Any library override has its own clearly named host
configuration, not the old executable name with a new interpretation.

Optional optimization may call `abc-opt` before loading, exactly as today; the
unoptimized path must work without loading the optimizer shared library.

## Files

- `Makefile`: separate PIC runtime shared target and frontend-test dependencies.
- `frontend/let/stage.lua`: session/program lifecycle and replacement execution.
- New frontend ABI binding module; `frontend/let/optimize.lua` consumes its shared
  error declaration while retaining the existing optimizer implementation.
- `frontend/tests/staging.lua` and dedicated bridge fixtures as needed.
- Frontend/API documentation: distinguish implemented session support from pending
  source static demands and persistent initialization snapshots.

No changes to symbolic scalar algorithms, A/B contracts, Ershov scheduling, native
cache allocation, explicit ABC continuations, safepoints or GC policy.

## Acceptance

1. Existing 24 staging checks pass, including exact u64, ordered vectors, mapped
   source abort, native modes and real VM stack-limit failure.
2. Repeated calls on a stateful module retain writes in one prepared handle;
   identical bytes loaded into a separate identity/session do not share writes.
3. Calls after abort follow the public VM reset/persistent-image contract; do not
   claim an abort rolls back prior stores.
4. Isolated disposable sessions do not publish failed/speculative state elsewhere.
5. Close/failure/callback-error paths release owned resources; no use-after-close.
6. Arithmetic and checks run with optimization disabled in all four modes; scalar
   float/integer bits cross the boundary unchanged.
7. Invalid modules, signature mismatches and unsupported transport fail explicitly.
8. Verify runtime-library linkage does not acquire an optimizer dependency; run
   unoptimized staging in a process where optimizer loading is unavailable.
9. Clean/shared build and `make validate-slet` pass. Full integration failures are
   reported separately rather than attributed to this slice without evidence.

This completes only the VM session foundation. Source-required requests,
`staticMode` propagation, the proposed CLI policy, virtual callable construction,
source-state materialization and initialization snapshot transport remain later
parts of the approved architecture, not outcomes of this infrastructure change.
