# Source compilation and staging API

**Authority:** host compilation policy, checked-program ownership, VM session lifetime
and static-value/image transport. [Source partial evaluation](source-partial-evaluation.md)
and [virtual source contracts](source-virtual-contract.md) describe the broader
approved architecture; [WORKLIST](../WORKLIST.md) S/F/O owns its delivery status.

**Implemented:** required scalar source demands under explicit `staticMode`, in-process
VM sessions, supported pointer-free aggregate/module snapshots and the initial private
Rc checked-to-physical boundary. **Gated:** address-bearing/owning snapshot transport,
public/foreign owning interfaces, general virtual-value specialization and `.let`
execution. Passing a mode does not admit unsupported types or effects.

## Compilation policy

```lua
Compiler.source(options)             -- parsing/declaration indexing; no VM
Compiler.file(path)                  -- same boundary from a file
Compiler.typed(input, options)
Compiler.typedFile(path, options)
Compiler.compile(options)
Compiler.compileFile(path, options)
```

`typed` means a completed semantic product, not absence of backend work. Required
static values can be needed before dependent requirements/results can be checked;
they execute verified ABC through the VM. A `phase="typed-ir"` result cannot contain
unresolved required demands. Parsing stays backend-independent; no second semantic
checker or Lua evaluator is introduced for editor use.

The execution option is `staticMode = "interpreted" | "threaded" | "eager" | "lazy"`.
It selects a mechanism, not source semantics, permission to evaluate effects early,
or the residual program's runtime tier. Without it, typing that needs no execution
can complete; required execution rejects with `execution-policy`. Optional folding
without a policy leaves legal residual computation. A missing policy does not make
the source program semantically invalid.

`compile` forwards policy through the same semantic entry, not a second import or
binding-time pipeline. `tools/abc` defaults source `compile` and source `run` to
interpreted static execution; `--static-mode=MODE` (or `--static-mode MODE`) overrides
it independently of `--jit`. Invalid policies/static failures do not publish an
artifact over an existing output. Source profile restrictions still apply: current
`.slet` execution is not the approved `.let`-only migration.

Each compilation request owns its demand/import/initialization state and closes its
resources on success or failure. Recompiling a parsed unit creates request-local
annotations rather than reusing VM addresses or stale initialization. Code identities
are reserved before recursive elaboration; constructing recursive code is not executing
it. Initialization uses uninitialized/initializing/initialized states: demanding an
initializing value rejects a dependency cycle. Static execution itself uses explicit
ABC continuations, never recursive host evaluation of source bodies.

## Checked-program and physical lowering

`typed`/`typedFile` expose `.program`, owned by `let/program.lua`:

- dependency-inclusive function, module and foreign vectors;
- `.typeCells`, the named definitions needed by structural and owning-ABI checks;
- `.access[id]`, `.accessStats` and `.ownership[id].edges` for checked access/strong edges.

These are private compiler results, not a public serialized summary format. There is
no `.flow`, inferred counted summary or resource-mode Ref contract. `Check.program`
validates structure/types; access/lifetime/cycle validation follows at the program
boundary, without writing proofs onto shared `Ir.Fn` nodes.

The program captures its vectors, not deep copies of every IR/type node. Nodes are
frozen by caller contract after analysis. Transformations create a new graph and
analyze it explicitly. Lowering does not hash or silently refresh mutated source IR.
Raw-IR `Compiler.lower(functions, options)` analyzes a new program with its supplied
declarations; source compilation consumes its existing checked program.

`ABC.lower` uses `Program.select` for independent Call/View/Code reachability, then
`Placement.program` and `Layout.physical` for declared Rc operations and owning slots.
Structural physical checking does not repeat ownership inference. Artifacts retain
the original `.program` and `.functions`, plus a separate `.materialized` graph whose
source-node mapping preserves original diagnostics. Pointer-free snapshots use
`Layout.scalar`. See [runtime interfaces](runtime-interfaces.md#3-explicit-rc-layout-and-private-handoff)
for the private ABI and [§9](runtime-interfaces.md#9-source-analysis-interfaces) for
the checker contract.

## VM staging sessions

```lua
local session = require('let.stage').open {
    mode = 'interpreted', -- also threaded/eager/lazy; required
    optimize = false,    -- defaults to true; optional ABC optimization only
    -- stackCells = positive_exact_cell_limit,
}
local ok, result = pcall(function()
    local program = session:prepare(artifact, checkedFunctions)
    return program:call { entry = 'main', arguments = {} }
end)
session:close() -- also on failure
if not ok then error(result, 0) end
```

The session owns one VM and prepared module handles. Each prepare owns a distinct
verified module identity and source/provenance maps; equal module bytes do not imply
shared image state. Reusing a prepared handle preserves its image writes. Separate
identities/sessions isolate them. Aborts reset execution stacks but **do not roll back
previous image writes**; speculative work must not publish failed session state.

Mode, stack and optimization policy are fixed per session. Closed/unready handles,
reentry, and close during a progress callback reject. Close is idempotent and frees
the VM before releasing prepared module references. GC finalizers are defensive
cleanup, not the primary lifetime protocol. The runtime binding loads `build/libabc.so`
(or `ABC_RUNTIME_LIBRARY`), not the optimizer library. With `optimize=false`, staging
must work without loading `abc-opt`.

`Compiler.stage` / `Stage.execute` prepare, call and close through this same service.
The obsolete runtime-executable option rejects; no subprocess/text-result fallback
remains. `Program:call` accepts an optional `progress` callback for start/finish/abort
notifications, not an instruction-budget or resumable-source interface. VM errors
retain structured status, reason, bytecode/optimizer provenance and original source
spans. The VM is not a sandbox for unchecked native pointers.

## Static value and module snapshots

Export signatures are checked against the typed transport contract before calling.
Integer/bool/f64 values use exact raw cells (f64 IEEE bits, not host conversions);
Unit has no cell. Supported pointer-free fixed-layout records, arrays and sums use
`{type=Ty, image=bytes}`. `layout.lua` defines layout/ABI; `snapshot.lua` marshals
bits; `stage.lua` returns raw `cells`, typed `values` and `moduleData` images.
Specialization materializes snapshots as checked `Ir.Bytes`, not host computation.

Address-bearing values, borrowed refs/slices, Rc and callable environments are not
snapshot transport. Copying pointer bits would not establish lifetime or relocation.
No counted/frozen owner or erased owning interface follows from this API.

A demand copies persistent module-root extents only after successful VM execution
and typed result transport. Compiler-owned bytes are accepted after all copies
succeed, then ordinary residual data/rodata lowering publishes them. Returned bytes
survive session teardown. Module instance aliases preserve their original root;
field reads/function results remain copies. Equal bytes are not alias evidence.
The earlier higher-order retention hole is corrected; general proof/transport
qualification remains open in WORKLIST, not excused by snapshot copying.

### Loaded-image copy

```c
abc_status abc_vm_read_image(
    const abc_vm *vm, const abc_module *module,
    size_t offset, void *output, size_t size, abc_error *error);
```

Copies `size` bytes at a module-image-relative offset from this module identity's
already-loaded persistent image in `vm`. It does not execute code, load an image,
retain an output owner, relocate addresses or synchronize concurrent access. The
caller provides valid live handles and writable nonoverlapping output storage,
and serializes copying against execution/image mutation. `error` may be null.

| Result | Contract |
| --- | --- |
| `ABC_OK` | copied; zero size permits null output and an offset at image end |
| `ABC_INVALID` | null VM/module, or null output with nonzero size |
| `ABC_ARGUMENTS` | invalid offset/extent, checked without addition overflow |
| `ABC_NOT_FOUND` | no image of that module identity is loaded in this VM |

Input/extent checks precede image lookup/copy. Failure leaves destination bytes
unchanged and sets/clears error normally. This is neither an atomic snapshot nor
rollback for an earlier aborted VM call.

## Errors, gates and qualification

Keep source/VM aborts, missing host policy, unsupported lowering/transport, actual
resource failure and compiler invariant failures distinct. None becomes a successful
unknown value to satisfy a required demand. A declined optional fold publishes no
state; this is not permission to swallow execution or infrastructure errors.

Foreign effects are unavailable in staging, including source lifetime bindings.
Runtime Rc execution does not imply compile-time Rc construction support. No source
fuel, specialization-count or logical-allocation budget is introduced. Host stack
limits are resource policy, not language acceptance heuristics.

Tests live in `frontend/tests/{source_demands,staging,staging_sessions,
staging_no_optimizer,aggregate_staging,program}.lua` and `tools/validate_api.c`.
They distinguish no-policy typing, required demands, all four execution modes,
exact bits, state persistence/isolation, failure publication, cleanup and unsupported
transport. WORKLIST and linked experiment reports own actual outcomes and performance;
this contract does not assert full virtual-value, owning-snapshot or `.let` completion.
