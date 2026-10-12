# Code architecture for the VM

This page describes the **current revision-6 implementation**, not every proposed
capability. [spec.md](spec.md) separates machine contracts, architectural targets
and remaining gaps. [symmetric-isa.md](symmetric-isa.md) owns selected-stack
semantics and instruction encoding; [module-format.md](module-format.md) owns the
supported serialization boundary. `REFACTOR.md` records implementation evidence.
An implementation deviation does not silently amend the intended architecture.

## Scope and dependency direction

```text
revision-6 contract + tools/opcodes.lua + gen/semantics.lua
  → generated metadata, concrete handlers and symbolic bindings
  → verified immutable modules
      → interpreted: generated cache-state handlers
      → native: shared symbolic execution → register-addressed stencils
      → build-time tools: shared symbolic execution → ABC DAG or semantic C residue
```

Runtime execution does not invoke `abc-opt`, the frontend, or a C compiler.
Portable C is a build-time peer sink, not the native JIT's intermediate language.
The VM receives bytecode, not source filenames or Let constructs.

## Structured task runtime target (not implemented)

[Tasks and channels](tasks.md) define the approved source direction: structured
groups, explicit `g.channel`, cooperative blocking tasks, select and cancellation
by marking/closing. Runtime work is separate from the current revision-6 checkpoint.

- Tasks own A/B/C stacks and explicit continuation state. Parking transports all
  live state and returns to the scheduler; no suspended task depends on a worker's
  host stack. Define suspension/resumption and migration for all four execution
  bindings without a second allocator, residual IR or recursive host execution.
- Workers use pthreads behind a narrow internal lifecycle/synchronization wrapper,
  not a general host concurrency API or direct JS-worker backend. Worker threads
  use work-stealing runnable queues. Blocking task operations park;
  CPU-bound work yields explicitly. Foreign blocking and affinity need declared
  policies. No progress guarantee applies to permanently non-yielding workers.
- Group-owned task/channel records and wait registrations have structural lifetimes.
  Specify atomic select commitment, losing-wait deregistration, no lost wakeups,
  rendezvous pairing and cancellation/registration races before implementation.
- Shareable buffers have atomic counts from creation, never a live mode upgrade.
  Cross-worker last release remains iterative and allocation-free; remote frees,
  count overflow, publication and borrowed-reader protection need exact protocols.
- Published native code stays immutable. Concurrent lazy construction uses
  synchronized version creation and atomic entry indirection; aligned writes alone
  do not justify patching executing code or changing W^X permissions beneath readers.
  Site observations, module/image lifetimes and target publication require a full
  concurrency audit, not just acquire/release flags.
- Source analysis distinguishes ordinary transferable values from group-bound
  capabilities, and allocation/counting/suspension/world/foreign effects. Mutable
  module reads as well as writes are excluded from other tasks.
- Abort remains program-ending without source unwinding. Worker shutdown, foreign
  calls in flight, embedding and allocation failures need a concrete protocol.

There are no GC safepoints or tracing scans in this target. Scheduling boundaries
and execution-state synchronization remain explicit. No task runtime, thread-safe
VM embedding, new bytecode or suspension ABI is implemented by this specification.
Test all bindings and race/failure paths; measure scheduling, copying/count traffic,
queue/result retention and contention independently of existing scalar benchmarks.

**Wasm deployment policy (approved, unvalidated):** application developers compile
generated AOT C and the runtime using Emscripten pthread support. Emscripten owns
pthread-to-Web-Worker/shared-memory adaptation; developers configure toolchain flags,
worker pools, hosting/isolation and JS integration. Let owns correct pthread/atomic
use and its task protocols. Run the scheduler off the browser main thread and
respect Emscripten startup/blocking/proxying constraints. No separate JS backend,
host-driven scheduler pump or silent non-shared-memory fallback is planned.
The current portable-C subset is not task-capable: explicit AOT suspension/resumption
and runtime linkage need design and implementation before browser task tests can
establish support. Emscripten does not provide ABC continuations or a native-JIT port.

## Current repository layout

| Owner | Responsibility |
| --- | --- |
| `tools/opcodes.lua`, `tools/gen_opcodes.lua` | Public forms, encoding, layouts, profiles and generated metadata |
| `gen/semantics.lua` | Shared bank-parametric typed instruction computations/effects |
| `gen/cache.lua` | Concrete interpreter cache topology and transitions |
| `gen/banked.lua` | State-specific concrete handlers, transport and dispatch |
| `gen/symbolic.lua`, `gen/fold.lua` | Generated symbolic bindings and constant computation |
| `gen/stencils.lua` | Register-addressed x86-64 operation and linkage stencils |
| `include/abc.h` | Runtime embedding API |
| `include/abc_tool.h` | Build-time optimization and portable-C API |
| `src/module.c`, `src/memory_module.c`, `src/verify.c` | Loading, module ownership and verification |
| `src/vm.c`, `src/vm_internal.h`, `gen/cold.lua`, `gen/foreign.lua` | VM/images, host boundary, shared checked indirect resolution, foreign bridges |
| `src/symbolic.c` | Shared ABC context, captures, folding, continuations and sink contracts |
| `src/residualize.c` | Native cache allocation, versions, stencil copying, relocation and lazy linkage |
| `src/optimize.c` | Build-time ordered DAG and canonical ABC re-projection |
| `src/residual_builder.c`, `src/residual_c.c` | Semantic residue and strict C writer |
| `frontend/let/` | Source parsing/checking, supported typed lowering, optimizer and staging clients |
| `tools/validate*`, `frontend/tests/` | Active validation |
| `research/` | Frozen historical implementations, experiments and evidence; not runtime dependencies |

Generated files are disposable build products. Some historical source files still
exist outside the active build graph; their presence is not executable support.
The Makefile's runtime/tooling object lists establish what is actually linked.

## Ownership rules

- **Definitions and consumers.** The manifest defines instruction identity,
  selected roles, layout and capability requirements. The assembler, decoder,
  verifier and execution bindings consume those definitions. Semantic checks and
  computations must not be independently reinvented by each backend.
- **Semantics versus placement.** A binary `OP.X` computes X0 op Y0 and returns on
  X. A/B are symmetric operand stacks; C holds explicitly addressed state.
  Placement is not a serialized or public callable ABI.
- **Interpreter cache.** A/B share four anchored registers; C has three cached
  registers, with occupancy 0–3. All pops remain demand-based: no eager refill.
  There are 15 A/B combinations × 4 C states = 60 combined states. EXT uses the
  same cache bindings. Calls carry cache state; frame allocation/free and foreign
  synchronization have their declared boundaries. The discussed hybrid eager-top
  C experiment is parked and is not implemented.
- **Immutable ABC.** Public instructions are not rewritten or quickened and carry
  no serialized indirect cache words. Threaded tapes are final VM-private
  register-addressed execution records, not rewritten ABC. Native relocation/lazy
  linkage and tape target binding are not bytecode quickening.
- **Observations.** One VM/module record per original indirect site follows
  unseen → validated monomorphic → final generic. The shared resolver validates
  exact public target identity and complete ABI; mismatch records final generic
  before validating the new target. A program-proven target can eliminate the
  observing dispatch after validation without inventing a transition.
- **Residual placement.** The symbolic cache is the allocator for both bindings:
  eight native value registers or seven threaded value registers. Constants, register
  values and memory homes remain ABC cell descriptors, not a second residual
  value IR. Captures preserve values before mutable homes are overwritten.
  Backedge weakening materializes constants through that allocator and canonicalizes
  their register descriptors; it does not unconditionally force a memory home.
  Real pressure spills and generic-edge conformance still apply.
- **Calls and continuations.** Argument gathering, frame storage and control
  transfer are separate. CALL.X chooses argument/result destination; RET.Y chooses
  result source independently. Eligible acyclic calls use virtual continuations;
  real calls and recursion use explicit ABC continuations, not recursive host
  execution. Native singleton results use r0; general result vectors retain their
  selected source, with r1/r2 providing continuation/source at transfer. These
  registers are not permanently reserved during ordinary execution.
- **Execution modes.** `--jit=off` executes original ABC. `--jit=threaded` eagerly
  prepares a register-specialized handler tape without executable mappings.
  `--jit=eager` prepares native versions at load; `--jit=lazy` compiles reached
  versions through persistent stable stubs. The host selects policy; there is no
  hotness threshold, automatic promotion, source-extension policy or semantic
  instruction fuel. See [threaded-execution.md](threaded-execution.md) for exact
  records, backend ownership, validation and performance caveats.
- **Version policy.** The current shared residual execution threshold is **16**.
  `version_for()`/`edge()` count matching context families; `inline_candidate()`
  separately limits continuation families. This is not a total per-PC bound.
  Build-time residual tooling retains its separate threshold of 8. The control
  sweep's 16 variant passed full validation but regressed lazy branching; see
  `REFACTOR.md` for the explicit default decision and measurements. The broader
  target is caller-owned region realizations, replacing the older shared-helper
  budget model, not legitimizing existing family-local ownership. Regions remain
  unimplemented and require a separate coordinated change.
- **Tooling boundary.** `libabc.a`/`libabc.so` execute verified modules without the
  optimizer. `libabc-tool.a` and `libabc-opt.so` own build-time rewriting/C emission.
  Native code never passes through their DAG or semantic residual IR. Portable C
  rejects unsupported residue rather than falling back to a separate evaluator.
- **Source status.** Typed SLet lowering is executable; Let parsing/checking and IR
  remain available, but managed/dynamic Let lowering rejects with
  `dynamic-lowering`. Source virtual values/places, backward demands and delayed
  materialization are approved work, not completed by the current staging bridge.
- **Staging status.** In-process scalar sessions prepare verified ABC and run the
  same VM in any mode, with owned module/image lifetimes and exact scalar transport.
  Foreign execution is prohibited. Prepared image writes persist; aborts do not
  roll them back. The proposed `staticMode` API/CLI, progress/interrupt reporting,
  aggregate snapshots/relocations and initialization transport remain future work.
  See [staging-session-implementation.md](staging-session-implementation.md) and
  [source-compilation-api.md](source-compilation-api.md).
- **Collector-free source target.** Profiles 1–4 remain active. The approved
  [owner design](owners-references-ids.md) replaces tracing GC/profile-5 ownership:
  separate counted escaping roots, actual-owner rank constraints, immutable value
  DAGs, stores/ids and value tables. Source place/provenance analysis owns lifetime
  proofs; the execution allocator does not reconstruct them. One Let language has
  independent capability facts, but legacy `.slet`/`.let` implementation behavior
  has not yet migrated. No collector, old tracing engine, quickening or opaque
  scalar fallback is authorized. Allocation remains an effect, not dynamic typing.

## Validation and remaining work

The active suite passes, including a clean copied-source build after the native
backedge correction. It checks selected operand order, A/B destinations, exact
cache states with poisoned dead arguments, captures, explicit continuations,
indirect observations, traps/capacity, optimizer/C contracts and frontend/staging
boundaries. See `REFACTOR.md` for exact counts and retained logs.

Passing these tests does not establish the single-budget target above, complete
source static-demand support, profile-5 execution or completion of the whole-diff
review. The old/new performance comparison and isolated backedge measurements
report regressions as well as gains; smaller code is not automatically faster.
