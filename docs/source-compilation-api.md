# Source compilation and static execution API

**Status: API policy approved; scalar source-demand boundary implemented.** This
supplies the API boundary needed by [source-virtual-contract.md](source-virtual-contract.md).
Required demands now execute verified ABC under explicit `staticMode`; completed
`typed`/`typedFile` no longer promise absence of backend work. Broader source
specialization/ownership remains incomplete. Pointer-free module snapshots have
working-tree qualification, with a known higher-order proof blocker; see
[module image copying](module-image-copy.md) and `frontend/README.md`.

## 1. Meaning of typing

Proposed rule: `typed` identifies the completed semantic product, not the absence
of execution during its construction. Complete source elaboration can require
static values before dependent requirements or result contracts can be checked.
Those demands execute verified ABC through the VM; the frontend does not evaluate
source operations itself.

A `phase="typed-ir"` result must never contain unresolved required static demands.
Do not return a partially typed unit under the existing completed-phase name, and
do not replace a required static value with an unknown runtime value.

`Compiler.source` / `Compiler.file` remain backend-independent parsing and
semantic checking/declaration indexing. The collector-free target checks owner and
capability facts, not filename-selected ownership semantics; current profile
restrictions remain until the migration is implemented. This proposal does not add a second semantic
checker for editor use. A future incomplete-analysis API would need an explicit
result contract and is not a substitute for completed typing.

### 1.1 Checked-program and executable boundaries (implemented)

`typed` and `typedFile` expose `.program`: the completed, dependency-inclusive IR
functions, module/foreign declaration vectors, `.access[id]`,
`.ownership[id].summary` and `.accessStats`. `let/program.lua` owns this analysis.
`Check.program` only validates IR structure/types; it does not infer lifetimes or
attach proofs to `Ir.Fn` nodes. Source compilation lowers its existing program;
demand fragments and specialization create and analyze their own completed graphs.
The public raw-IR `Compiler.lower(functions, options)` explicitly analyzes a new
program, including its supplied module/foreign declarations.

The program captures its vectors, not deep copies of every IR/type node. Nodes are
frozen by caller contract after analysis. A transformation constructs a new graph
and obtains a new program; lowering does not hash, revalidate or silently refresh an
old program after in-place mutation. Private `ABC.lower` consumes that program, not
a bare function list or a separate set of proof annotations.

`Layout.program` is the ownership-related executable-admission boundary. It rejects
counted requirements before selecting the currently implemented borrowed contract.
Layout consumers use that contract for cells, byte layouts and ABI components;
pointer-free staging/snapshots use `Layout.scalar`, which cannot select a reference
representation. Typing a valid counted program is consequently supported without
claiming it can execute. Cycles and unsafe-access proof failures still reject during
analysis. Owning placement, lifetime emission and runtime cleanup remain unimplemented.

## 2. Proposed call shapes

```lua
Compiler.typed(input, options)
Compiler.typedFile(path, options)
Compiler.compile(options)
Compiler.compileFile(path, options)
```

The existing one-argument `typed` and `typedFile` forms remain usable for programs
that need no VM execution to complete elaboration. `input` retains its current
source-options/parsed-unit meaning. Runtime service configuration belongs in the
new explicit options argument, not mutable annotations on a parsed source unit.
`compile` forwards its configuration to the same semantic entry rather than
creating a separate binding-time/import pipeline.

Proposed source-compilation execution option:

```lua
{ staticMode = "interpreted" } -- also "threaded", "eager" or "lazy"
```

This setting selects execution mechanism, not source semantics, residual runtime
mode, permission to evaluate effects early, or a request to run every known call.
Existing explicit `Compiler.stage(functions, {mode=...})` remains a distinct host
API with its existing mode spelling; it must ultimately use the same staging
service, not retain a second execution implementation.

For library calls without `staticMode`:

- Parsing and semantic construction that need no execution can complete.
- Optional VM folding is not attempted; legal residual code is retained.
- A required static demand reports a host configuration diagnostic identifying
  the binding/source location and need for a static execution policy.

That diagnostic is not a judgment that the program is invalid SLet/Let. No
implicit Lua evaluator or reinterpretation under a different source profile is
permitted. A host-selected mode does not grant access to an unavailable backend.

## 3. CLI policy

The CLI is the host and should select `interpreted` as its default static policy,
independently of the selected residual execution tier. A proposed
`--static-mode=interpreted|threaded|eager|lazy` option overrides that host policy for source
compilation. This is a CLI option, not new language syntax.

Both `abc compile source` and implicit compilation in `abc run source` must pass
the same option through the production compiler. Selecting `--compiled` for the
resulting program must not silently select eager compilation for static work.
Invalid policy options fail before publishing an artifact. Existing output files
remain untouched on any compilation/static-execution failure.

Exact option-parser integration and diagnostics must be tested; these options
are not currently implemented by this proposal.

## 4. One owned compilation session

A public source compilation request owns one internal session. Its import graph,
initialization state, static identities and specialization records are shared
across that request. Public functions are not chained in a way that creates a
fresh session for every demand or imported module.

Conceptual internal flow:

```text
compile(request):
    open compilation session with explicit host policy/capabilities
    parse/resolve requested source/import graph
    elaborate using virtual values and demand-driven static requests
    materialize completed checked IR and required source data state
    lower residual product through normal ABC backend
    export durable artifact
    close session on every success/failure path
```

`typed` stops after materializing the completed semantic product. It still closes
its execution resources. Returned values cannot retain dangling VM-local pointers;
any retained static state must have an explicitly owned, transportable compiler
representation. That representation and snapshot API are design dependencies,
not assumed capabilities of the current scalar bridge.

Compilation of a parsed unit more than once must not reuse stale initialization
state or VM addresses. Cross-compilation caching, if later added, requires an
explicit ownership/state key and is not implied by value interning.

## 5. Two forms of recursion, two different checks

- Elaboration/specialization reserves code identities before elaborating recursive
  bodies. Forming mutually recursive code does not execute it.
- Required initialization uses `uninitialized/initializing/initialized` binding
  state. A value demand that re-enters `initializing` rejects as a dependency cycle.

Static calls themselves execute on the ABC VM with explicit ABC continuations.
Do not implement them using recursive host invocation of source bodies.

## 6. Errors and resource ownership

Distinguish:

1. Source errors and VM language aborts, with source provenance.
2. Missing execution policy (host configuration).
3. Unsupported lowering/transport/profile capability.
4. Actual VM resource failure.
5. Compiler invariant failure.

No category becomes a successful unknown value to satisfy a required demand.
A declined optional fold retains the original computation and publishes no state;
this is not blanket permission to swallow execution or infrastructure errors.

Current implementation profile restrictions remain in force. The unified
[collector-free target](owners-references-ids.md) replaces their language-level
ownership split, but selecting a staging mode does not implement that migration,
restore profile-5 execution or permit silently compiling Let as the typed subset.
Foreign effects remain unavailable in static execution under the current contract.
No instruction, recursion, specialization-count or logical-allocation budget is
introduced. Host stack-capacity controls and interruption remain resource policy,
not source acceptance heuristics.

## 7. Compatibility and replacement

This intentionally revises the documented promise that complete typing never
needs backend execution. Keep the result's meaning (fully checked semantic IR),
not a facade pretending required evaluation did not occur.

Do not change executable behavior until the policy and session bridge exist.
At implementation time, update `compiler.lua`, `stage.lua`, both CLI source entry
paths, frontend API documentation and callers/tests together. Do not update the
current API documentation to describe unimplemented behavior as available.

The scalar explicit-stage API and its exact-cell tests remain useful. Replace its
execution mechanism with the common VM service when ready rather than introducing
a separate source evaluator next to it.

## 8. First implementation acceptance boundary

The API policy is approved. Define the concrete staging-service implementation
boundary, then implement a vertical slice that reaches an actual source static
demand, the VM, a returned known value and residual checked IR. An isolated unused virtual-value library does not close
the gap.

For that slice, specify supported value transport explicitly. Scalar-only support
must not be reported as complete persistent module initialization, aggregate
snapshotting, owned closure transport or dynamic Let execution.

Tests must distinguish:

- No-static-demand typing without a policy: succeeds as before.
- Required demand without a policy: clear host configuration failure.
- Required demand with each mode: equal typed values and source diagnostics.
- Parsing the same source: still requires no execution service.
- Optional evaluation without a policy: legal residual behavior, no host evaluator.
- Compile and implicit source run: same default static policy; independent runtime tier.
- Repeated compilation/imports: correct once-per-session initialization and cleanup.
- Static failure: existing output preserved; resources released; no published partial state.

This API decision does not modify Ershov scheduling, the ABC ISA/calling convention,
`abc-opt` or the native symbolic allocator.
