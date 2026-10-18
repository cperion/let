# Round 11 — the residual-function set is a root set plus lazy calls, not a pre-pass

**Mode:** experiment (code reading + a measured probe of abc-opt's emitted
function table, the native execution image's entry table, and the portable-C
writer's emitted functions).

## Three candidate questions, ranked

**A (first).** What is the **residual-function set** — which functions get a
residual entry version and a body, and when can the set be computed? Materiality:
highest. `ARCHITECTURE.md:359-362` starts `run()` with

```text
for each residual function f:
    version_at(f.entry, all_locations, f)
```

and the deterministic-order invariant (`ARCHITECTURE.md:119-122`) says every
residual function's entry version is created before any body is walked, "so a
call can name its target version regardless of walk order". But *residual
function* is never defined, and it cannot be computed before walking: a function
is residual exactly when some call to it stays residual, which is the walk's
output. The incumbent resolves that circle with a second, function-level worklist
(`optimize.c:862-873`: `needed`/`dirty`/`ArgumentFact` activation, each residual
callee activated through `join_call_facts` and re-walked) — the very worklist the
design claims to delete ("no fixpoint over functions, so no function is ever
walked twice", `ARCHITECTURE.md:474-476`). The answer also decides the emitted
ABC module's function table (code size, CALL renumbering, provenance) and the
native compile set (compile time).

**B (second).** May native's entry set shrink from "every module function" to
the module's externally addressable entries? Materiality: compile time and code
size (measured below: 2 of 4 eager bodies on a raw two-function fixture are never
entered), plus the runtime image's entry table contents. It is a compile-set
policy, not a key rule, but it uses the same fact as A, so it was priced in the
same probe and recorded as its own question (Q19).

**C (third).** Q12's fact ownership (per-pc heights, `CSET` targets, cycle-body
and may-write sets). Materiality: medium — one-owner rule and compile cost, no
correctness change, recommendation already recorded. Not pursued.

## What was read

- `ARCHITECTURE.md:119-122` (entry-before-walking invariant), `:359-386`
  (`run()`), `:489-505` (driver `run(binding, function)`), `:64-73` (module facts
  already list "entry roots", but nothing uses it).
- `src/optimize.c:809-817` (`mark_residual_callees` / `mark_live_functions`:
  roots + transitive closure over the **emitted** call lists), `:781-785`
  (`retain_function` records every direct call of a retained function through
  `append_unknown_call`), `:826-846` (`write_module`: renumber surviving
  functions, rewrite CALL/TCALL displacements to the new entries, rewrite pc
  sections and entry relocations, fail if an emitted call targets a non-live
  function; `else memset(live,1,...)` when the module declares no roots),
  `:862-873` (`activate_function_facts` for roots or all functions, then the
  dirty-function loop).
- `docs/abc-opt.md:95` — the documented rule: "In modules with explicit roots,
  only functions reachable from exports, ABI-visible code-address relocations,
  revision-7 lifecycle C-entry relocations, or residual direct calls are emitted;
  unreachable source functions fall out as a consequence of residual symbolic
  reachability."
- `src/residualize.c:822-841` (native creates an entry version for **every**
  module function, split by `c_entry` into execution vs lifecycle image),
  `:96-106` (`resolve_execution_target` resolves a public ABC entry address to a
  function index and enters `image->entries[index]`), `src/vm.c:214,253-263`
  (host calls reach a native entry via an export name), `gen/cold.lua:19-29`
  (`vm_resolve_indirect` accepts **any** function entry with a matching
  signature, rejecting only `has_halt`/`c_entry`).
- `docs/module-format.md:116-122` (code-address relocations carry public entry
  identities into writable data; the only serialized way a code address enters a
  program), `docs/callable-profile.md:81` (same).
- `src/residual_builder.c:2704-2712` (portable C builds every source function),
  `src/residual_c.c:222-240, 1058-1130, 1254-1280` (only exports become
  wrappers; everything else is `static inline`).

## Measured

Probe: `experiments/11-residual-root-set.lua`, output
`experiments/11-residual-root-set.out`, artifacts in
`experiments/11-residual-root-set-out/`; native entry-table probe
`experiments/11-entry-table.c` (built against `build/libabc.a`). Four hand-built
modules through the existing assembler, verifier, abc-opt and all four execution
modes.

| fixture | module shape | abc-opt functions | result |
|---|---|---|---|
| `acyclic-export` | `entry` exported, calls acyclic `helper` | **2 → 1** | helper inlined **and deleted**; 42 in all four modes; `opt` fixpoint |
| `acyclic-no-export` | same, no `.export` at all | **2 → 2** | helper inlined into `entry` (`PUSH8_A 42`) but its own body is still emitted verbatim |
| `recursive-export` | `entry` exported, nontail self-recursive `rec` | **2 → 2** | `CALL_A` survives in both functions; 15 in all four modes; the caller's body continues after the call (`CALL_A; CPUSH_A; CGET0_A; RET`) |
| `reloc-root` | `.codeaddr 0 target` relocation + `CALLI`; `dead` unreferenced | **3 → 2** | `dead` (PUSH 99) dropped; `target` kept although no direct call reaches it; 42 in all four modes |

Native (eager) entries and bodies:

| module | functions | entries | bodies | virtual/real calls |
|---|---|---|---|---|
| `acyclic-export.raw` | 2 | 2 | 4 | 1 virtual call, 1 virtual return |
| `acyclic-export.opt` | 1 | 1 | 1 | 0 |
| `acyclic-no-export.opt` | 2 | 2 | 2 | 0 |
| `reloc-root.opt` | 2 | 2 | 2 | 1 real (indirect) call |
| `recursive-export.raw` | 2 | 2 | 9 | 3 real calls |

So native installs an entry for a function that no export, relocation or
emitted call reaches (`acyclic-no-export` function 0), compiles a body for it,
and enters a non-exported function whose only name is a code-address relocation
(`reloc-root`, 42 in `compiled`/`lazy`/`jit=threaded`).

Portable C: 1 body for `acyclic-export.opt`, 2 for `acyclic-no-export.opt`, 2 for
`recursive-export.opt` (every function in its input module); the callable-profile
fixture is rejected ("portable C currently supports only the integer/static
profile"), which is Q3's known scope.

## Answers

1. **The ABC set is a static root set plus a post-walk residual-call closure.**
   Roots: exports ∪ code-address relocations ∪ revision-7 lifecycle C-entry
   relocations; if all three tables are empty, every function (`optimize.c:826`;
   measured 2 → 2). Closure: the target list of the *emitted* code, i.e. residual
   (non-inlined) direct calls, plus **every direct call of a retained function**
   (`retain_function`'s `append_unknown_call`: a body the sink refuses to walk is
   emitted verbatim, so none of its calls can be inlined), closed transitively.
   The optimizer is already root-closed in its work: `activate_function_facts` is
   called for roots and, through `join_call_facts`, for residual callees only, so
   functions outside the closure are never walked (`optimize.c:864-873`). The
   writer emits exactly that set, renumbers it, and rewrites CALL/TCALL
   displacements; an emitted call to a non-live function is a hard failure
   (`optimize.c:826-846`).

2. **Native's set is every function of its input module** (split by `c_entry`
   into the execution and lifecycle images, `residualize.c:822-841`). The runtime
   reaches a native entry only by (a) an export name from the host
   (`vm.c:214,253`) or (ii) an indirect call whose public ABC entry address is
   resolved to a function index (`residualize.c:96-106`), and the resolver
   accepts *any* function entry with a matching signature (`gen/cold.lua:19-29`).
   Code addresses enter a module only through code-address relocations
   (`docs/module-format.md:116-122`), so the runtime-reachable set is a subset of
   roots ∪ direct-call closure; the incumbent compiles the whole function table.
   This is why a raw two-function module costs 4 eager bodies while the
   abc-opt output for the same program costs 1.

3. **The portable-C sink emits every function** (source-level; exports only add
   wrappers). Unreferenced `static inline` functions are removed by the C
   compiler, so the set has no compile-time meaning here.

4. **Consequence for the design: the residual-function set is derived, not
   declared, and it needs no pre-pass.** The design's requirement that all entry
   versions exist before walking is only needed for functions that can be entered
   **from outside the traversal** — the binding's root set. A residual callee is
   entered from inside the traversal, and its call site can create its entry
   version itself:
   - `entry_roots(module)` is the only pre-pass; it is a binding fact because
     "what can enter this code from outside" is per-sink (ABC: the module's
     addressable entries, or every function when the module declares none;
     native: every function today, Q19; portable C: every function).
   - a residual call site executes `t = version_at(callee.entry,
     all_locations, callee)` and then `binding.residual_call(v, t)`. This is
     deterministic: the key is content, and version creation order is a function
     of the walk order (FIFO queue, fixed arm order). The round-10 statement "every
     residual-function entry version is created before any body is walked"
     weakens to "every **root** entry version is created before any body is
     walked"; no call depends on another walk's progress.
   - a **retained** body is the third and last way an entry version appears: the
     binding refused to record a body, so it reports the refused body's direct
     call targets, which are residual by definition (no inline decision is
     possible without a walk). The driver creates each target's entry version.
     This is exactly `retain_function` + `append_unknown_call`.
   - the residual-function set is then *the owners of entry versions*, and the
     ABC writer emits exactly those functions (measured 2 → 1 for a fully
     inlined callee, 3 → 2 with a relocation root): the same output the
     incumbent's `mark_live_functions` computes, without a closure pass and
     without the function-level worklist. The writer's "call target must be
     live" check becomes unreachable by construction.

5. **The incumbent's function-level worklist retires completely.** With generic
   entry keys (Q7) the `ArgumentFact **facts` array, `activate_function_facts`,
   `join_call_facts`, `needed` and `dirty` have no remaining job: roots are the
   root set, callees appear on demand, and the version table is the only worklist.
   `abc_residual_run(binding, function)` becomes `abc_residual_run(binding,
   module)`; `owner` still selects the code region of a version (the ABC/C
   per-function placement).

## Not established

Whether native may shrink its entry set to the addressable entries (exports ∪
relocations ∪ C-entry relocations, or every function when none) plus residual
calls. The probe prices the possible win only indirectly: on the raw
`acyclic-export` module, 2 of the 4 eager bodies are (i) the inlined callee's own
entry body, which nothing enters (`virtual_calls=1`, `real_calls=0`), and (ii) the
call-return body round 10 already retires. No image was built with a restricted
set. Code evidence says the restriction is sound — the resolver only sees
addresses materialized by relocations and the host only names exports — but the
public API has no "call function by index" path to test against. Recorded as Q19
(open, recommendation: yes) rather than adopted, because it changes the runtime
image's entry table and no measurement of the restricted build exists.

Also not established: whether an ABC retained body can need an entry version for
a *tail* call target that the symbolic machine would otherwise have inlined
(`retain_function` records both `CALL` and `TCALL`, so the incumbent says yes);
and whether a per-function refusal could leave an abandoned walk's callee entry
version unreferenced — the retained body still calls it, so no.
