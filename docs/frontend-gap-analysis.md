# Let frontend gap analysis

Status: implementation audit. The checked backend and the ordinary Let/SLet source path are now integrated; the remaining gaps are listed below.

## 1. Finding

The production compiler now follows the required path: profile-neutral ASDL parsing, source semantic
construction into checked `Ir.Fn`, shared ABC lowering, independent assembly/runtime verification,
the C `abc-opt` residual optimizer, and `abc_vm` execution. `tools/slet_frontend.lua` is only a
bootstrap validation oracle. The Lua evaluator and direct source-to-C path are not used.

Ordinary `.slet` and `.let` source now covers scalar control and calls, local records and arrays,
addressable places and stores, scalar-payload sums, slices and strings, checked references, raw pointers,
recursive type sealing, typed and nested words, schema methods with actual receivers, keyed full/static
partial supply, deferred actions, foreign declarations, Let managed captures, managed aggregate `any`
boxing/casts/tests, escaping Let references/slices with promoted backing storage, generic `any`, and
dynamic callable dispatch. Imports preserve the profile asymmetry. End-to-end fixtures compare
interpreted, eager, and lazy staging and optimizer fixpoints.

The difficult remaining work is narrower but still semantic: complete source-interface propagation for
nested/imported schema fields and complete interface-evidence proofs,
provenance through mutable/deeply nested owners and sums, module initialization, managed/address-bearing
sum ABIs, open words, and the proof-driven connection from source static boundaries to VM-backed evaluation.

The SLet core is not a different language that needs a second parser and type system: sections 1–14 of `docs/syntax.md` are textually identical to `../wordlet.lua/syntax.md` except for the title and `.slet`/`.let` framing. The mature compiler is valuable as a source-frontend design and a source of migration fixtures. Its Lua evaluator and direct source-to-C execution path must not be imported or retained: executable compile-time Let code lowers to verified ABC bytecode and runs only through the VM.

## 2. What the current frontend does well

The prototype already demonstrates several backend choices that should be retained as tests:

- exact LuaJIT integer parsing without conversion through a double;
- all strict integer widths, `bool`, erased `unit`, wrapping arithmetic and checked conversion;
- literal adoption, signed negative literals and the specified mixed-width rules;
- ordered multiple results, scalar adjustment and unit padding for bindings;
- direct calls, direct tail calls and lexical runtime supply of a known word through `CALLI`;
- known scalar folding and selected-arm folding for known conditions;
- lexical binding scopes, forward module references and immutable local bindings;
- useful ABC instruction selection: immediate operations, C-cell operations and fused compare branches;
- demand-driven emission of functions reachable from configured exports.

These are valuable lowering fixtures. They are not substitutes for a complete semantic pipeline.

## 3. Gap matrix

| Layer | Implemented now | Remaining work |
| --- | --- | --- |
| Source input | `.let`/`.slet`, spans, deterministic imports, exported types, foreign declarations, and asymmetric profile checks | Value exports and richer imported schema interfaces |
| Parser | Shared ASDL parser for schemas, records, arrays, indexing, fields, lambdas, signatures, stores, matches, `use`, `extern`, and `defer` forms | Semantic construction for open-word/static-boundary forms |
| Names and captures | Module words, lexical locals, nested words with explicit hidden capture inputs, deterministic lambda capture discovery, lifted functions, direct receiver methods, and retained Let method values across imported interfaces | Complete interface-evidence lookup |
| Types | Scalars, `any`, records, arrays, sums, refs, pointers/slices, strings, signatures, callable views, recursive named-cell sealing, and exported type names | Tagged/open source types and complete interface-supply identity |
| Calls | Direct/tail calls, exact views, escaping managed captures, indirect calls including retained runtime partial application, dynamic calls, canonical keyed full/static partial supply, methods, recursively flattened record/array ABIs, and GC-free sum ABIs | Managed/address-bearing sum ABIs |
| Storage | Frame/managed records and arrays, projections, aliases, typed stores, bounds checks, refs/slices/raw pointers including null identity comparisons, aggregate `any` boxing, promoted returned backing storage, and owner-retaining captures | Module mutable storage and provenance through mutation or deeply nested sums |
| Control IR | Checked conditionals, switches, loops, traps, joins, block-bodied lambdas/handlers with inferred or expected results, deferred cleanup, and completion | Broader static path agreement and provenance proofs |
| Dynamic Let | Boxing/casts/tests including managed aggregates, generic unary/binary operators, strings, direct word boxing, dynamic calls, retained runtime partial applications, and open-word construction/fields/computed keys/stores/aliasing/removal/freezing | Keyed runtime supply/copy, open-word methods, and complete dynamic boundary conversions |
| Modules | Function/type/schema exports, imported schema method interfaces, deterministic private IDs, Let→Let/SLet and SLet→SLet imports | Value initialization and public ABI closure |
| Static execution | Explicit VM-backed staging/specialization under all three policies | Source static syntax/proofs and persistent staging images |
| Diagnostics/tests | Stable spans/codes, three-policy source fixtures, import fixtures and optimizer fixpoints | Broader negative lifetime suites and migrated legacy programs |

## 4. Reference compiler assessment

The available reference is `../wordlet.lua`; no `../worlder.lua` path exists. It is a legacy LuaJIT Wordlet-to-C compiler for the same SLet core. Its suite passed during this audit, demonstrating broad parser, type, lifetime and source-fixture coverage. That result is evidence for ideas and test cases to migrate, not a second evaluator that ABC will keep running.

Its architecture remains useful as a separation-of-concerns example:

```text
source -> lexer -> ASDL AST -> lexical capture/name resolution
       -> semantic types and specialization planning
       -> typed structured residual representation
       -> structural verification + profile-specific ownership verification
       -> target ABI/layout closure -> target lowering
```

Reusable ideas include spans and diagnostics, complete AST/type schemas, capture and module resolution, specialization identities, structured effects, completed-program verification, strict-profile lifetime proofs, deterministic output, source rejection fixtures and programs with fixed expected results. The target-neutral `Ir.Fn` vocabulary is also a useful specification for the facts an ABC lowering must preserve. The legacy lifetime checker is not the Let ownership model and must not be applied wholesale to `.let`.

The Lua evaluator and direct source-to-C pipeline are explicitly outside the ABC compiler. They are neither imported, shipped nor invoked as an oracle during normal validation. Known executable Let code runs as verified ABC bytecode in an `abc_vm`; otherwise the compiler would preserve two implementations of arithmetic, control flow, calls, memory, aborts and dynamic semantics.

The reusable reference frontend is intentionally snapshotted under `frontend/` from base revision `4a4cbc023a4325be8f633734cca1653f7833b010`. The snapshot includes the reference worktree's documented local changes and records them in `frontend/README.md`. It has its own tests and licenses and has no runtime dependency on `../wordlet.lua`.

## 5. Required compilation architecture

The central invariant is: **all executable Let computation uses ABC semantics, including computation performed while compiling.** Compiler metadata operations—parsing, name lookup, type construction, layout, specialization keys and ownership proofs—remain in Lua. User-authored arithmetic, branches, loops, calls and memory effects that are known at compile time execute in the VM.

Ownership verification is profile-specific. SLet `.slet` uses lexical storage, borrow/escape proofs and non-retaining views. Let `.let` uses profile-5 managed storage: address-taken values may be heap-promoted, and managed references, slices and callable environments are traced rather than rejected for escaping. Raw pointers and external resources remain unmanaged in both profiles. This source choice affects lowering and metadata, never the VM's execution-policy selection.

There are two distinct partial-evaluation layers:

1. **Let binding-time evaluation.** The frontend decides which source inputs are static, executes fully known calls, and emits specializations for invocations containing runtime values.
2. **ABC interpreter residualization.** When eager or lazy JIT is selected for those compile-time modules, `src/residualize.c` partially evaluates the VM handlers with respect to bytecode, stack layout, constants and contexts, producing fast native stencil code.

The second layer accelerates the first; it does not replace source-level binding-time decisions. They derive from one bytecode semantics.

```text
source + host-selected source profile
    -> lex / parse / spans
    -> names, types, captures, layouts and profile-specific ownership checks
    -> binding-time and specialization planner
          |
          +-- fully known invocation
          |      -> staging ABC bytecode -> verify -> abc-opt -> verify -> compile-time abc_vm
          |           (interpreted, eager JIT or lazy JIT by compiler configuration)
          |      -> decoded known values / module-image state
          |
          +-- invocation with runtime inputs
                 -> specialized residual ABC bytecode -> verify -> abc-opt -> verify
                       -> VM module, or residual C from the same ABC semantics
```

The compiler should lower a source operation only once. A staging function and its residual specialization use the same typed lowering tables, layouts, abort mapping and instruction selection. Static execution is not a second Lua implementation of the language.

### 5.1 Compile-time VM contract

The compiler is an ABC host and independently selects the execution policy for staging modules. This setting is separate from the policy later used to run the emitted residual module and is unrelated to `.slet` or `.let`. Interpreted mode is the low-startup baseline; eager or lazy JIT can accelerate large or repeatedly invoked static programs. No hotness counter or automatic semantic tier change is required.

A compile-time execution service must enforce these rules:

- Every staging module is assembled and verified before execution.
- `FCALL` is unavailable during static execution; encountering a foreign effect is a source rejection or leaves the invocation residual where the language permits that.
- Language aborts become compile diagnostics carrying the originating source span and bytecode offset.
- Static execution has no instruction, fuel, specialization-count or logical-allocation budget. It runs until completion, a language abort, actual resource exhaustion or external interruption. After a delay the compiler reports the active binding and source position; Ctrl-C reports the static-execution word stack and source positions.
- A speculative fold that is abandoned runs in a disposable VM/image or against a checkpoint. VM image writes must not leak from a refused fold into compilation state.
- Mandatory module initialization executes once, in declaration order, in its module's persistent compile-time VM image. Its accepted final image is the source for residual module initialization.
- VM-local addresses, callable addresses and collected-object addresses never enter a serialized residual module. Results are copied or re-encoded through type/layout metadata.
- Static-only values such as `type`, schema/interface identity and specialization descriptors stay compiler metadata. Operations on executable represented values run in the VM.
- Staging modules and their eager/lazy native images may be cached by deterministic specialization identity so JIT preparation is amortized.
- Switching the compile-time VM among interpreted, eager and lazy policies must not change known results, diagnostics, accepted residual code or emitted module bytes.

The public API provides verified module loading, execution modes, calls and persistent per-VM images. It intentionally has no instruction-budget field or interruption API. Current staging uses temporary exported entries and exact typed cells through `Compiler.stage`; each invocation starts a runtime process and therefore does not amortize eager/lazy preparation. Full module initialization needs an in-process persistent staging host and a compiler-facing way to snapshot or copy the accepted private image without exposing mutable runtime internals as a language ABI.

### 5.2 Frontend and backend boundaries

Keep `tools/slet_frontend.lua` only as a bootstrap validation oracle. The production compiler is the reused ASDL pipeline under `frontend/`; extend its parser, typed IR, resolver, analysis and checked lowering rather than adding language families to any direct source-to-assembly path. Reuse applicable SLet verification as it is migrated, but keep strict borrow proofs separate from Let GC promotion/provenance/root analysis. Do not migrate the legacy Lua execution engine or direct source-to-C backend.

The reused ASDL `Ir` representation is the typed structured boundary between source and bytecode. It preserves places, effects, joins and source spans, while executable folding goes through a staging module. Extend that schema when ABC or Let needs additional explicit facts; do not replace it with another ad-hoc IR. The ABC-specific side has these responsibilities:

1. **Layout closure.** Map each semantic type to cells, memory size/alignment, call signatures, callable metadata, module image offsets and relocations.
2. **Typed bytecode lowering.** Map values, places, ordered effects and structured control to correct ordinary A/B/C operations and verified basic-block stack shapes. Lowering does not inline and re-project its own output.
3. **Optimizer facts.** Attach optional purity, non-aliasing, exact/finite callable identity, non-escape, capture ownership/receiver and source-provenance facts. Missing facts must only make `abc-opt` more conservative.
4. **Static execution bridge.** Build/cache optimized staging modules, encode arguments, select the configured VM mode, execute until completion or external interruption, and decode results or diagnostics.
5. **Specialization driver.** Combine static metadata and VM-produced values into deterministic keys; reserve recursive specializations before construction; emit residual functions for runtime inputs.
6. **Module emission.** Produce profile sections, exports, externs, image snapshots and relocations. Textual assembly is acceptable initially because the assembler and loader verifier remain independent checks.
7. **Source mapping.** Preserve source spans and inlined provenance for bytecode generated for both staging and residual modules.

The typed IR is already ANF/SSA: calls are ordered `Ir.Call` effects and their results are named values, so the continuation at a call site is its remaining statement suffix plus the enclosing continuation. Lowering passes that continuation explicitly. If it is the function's existing return continuation unchanged, the transfer is `TCALL`; if work remains, it is `CALL` and the suffix is the return continuation. Defunctionalization gives a known continuation a block label and explicit live cells; runtime-selected or recursive transfers use the VM's C-stack continuation mechanism. The frontend backend never asks whether a target is recursive, computes no call-graph SCC for tailness, and has no function-level `tailCalls()` prepass. Self recursion, mutual recursion and ordinary calls follow the same local tailness rule. Separately, standalone `abc-opt` computes direct-call SCCs only to decide which verified bytecode calls may be virtually inlined; SCC membership never defines tailness.

Tail call modulo accumulation is a separate optional optimization. It may reassociate only a proven pure associative operation with a valid identity under the exact source semantics. Modular integer addition can qualify; `f64`, checked arithmetic, dynamic dispatch and effectful calls do not qualify merely because their operator is spelled `+`.

ABC's stack layout and generated opcode semantics make typed bytecode lowering small. The standalone C `abc-opt` then uses ABC symbolic semantics to inline eligible acyclic calls, eliminate non-escaping known closures, Reynolds-defunctionalize finite callable sets, fold and canonically re-project residual DAGs onto A/B/C once per produced module. Known captures and receivers remain ordinary symbolic values/homes; only genuinely escaping or dynamic callables retain allocation and indirect dispatch. The interpreter benefits from fewer dispatches and allocations. The JIT consumes that compact bytecode and residualizes directly to register-addressed stencils; it never schedules a residual back to ABC. See `abc-opt.md`.

## 6. Implementation status and remaining sequence

The old stage numbering became misleading once aggregate, callable and profile-5 work landed in parallel. The current dependency order is:

1. **Completed foundation.** The reused ASDL frontend, typed `Ir.Fn` boundary, checked ABC lowering, source maps, deterministic imports, scalar and aggregate ABIs, sums, checked references, raw pointer/null construction and pointer indexing/stores, typed and block-bodied lambdas, block-bodied sum handlers with an expected result, managed captures, generic `any`, dynamic calls, source `extern` declarations and `FCALL`, exported types, three-policy staging, specialization wrappers and optimizer fixpoint checks are integrated.
2. **Close semantic construction.** Complete interface-evidence proofs and the remaining open-word method/supply/conversion forms. Preserve stable unsupported diagnostics until each form has semantic IR and checked lowering.
3. **Close ownership and ABI proofs.** Complete SLet lifetime/provenance verification through mutation and deeply nested owners; complete managed/address-bearing sum call ABIs and remaining managed aggregate forms without hiding roots in raw cells.
4. **Close modules and static semantics.** Implement mutable module storage, declaration-ordered initialization, explicit source static boundaries or sound total/effect-free/no-abort proofs, residual specialization for runtime inputs, and deterministic public ABI closure.
5. **Replace the temporary staging host.** Cache verified modules and eager/lazy preparation in-process, maintain persistent module images, support transactional speculative folds and accepted-image snapshots, and report delayed progress or interrupted static word stacks with source positions.
6. **Cross-mode acceptance.** For every newly accepted source family, compare fixed outcomes, compile-time execution under interpreted/eager/lazy policies, byte-identical residual modules, residual execution under all VM policies, and portable C emitted from the same symbolic semantics.

## 7. Immediate next implementation task

The VM-backed scalar execution boundary is now established in `frontend/let/stage.lua`. Validation evaluates known functions under interpreted, eager and lazy policies, requires byte-identical staging modules, preserves exact 64-bit cells, maps a language abort to its typed IR/source hook, and classifies a real VM stack limit as a resource failure. There is no instruction or fuel cutoff.

The next semantic connection is explicit source-level static binding. `Compiler.stage` and `Compiler.specialize` already establish the VM boundary, but ordinary saturated calls correctly remain residual until syntax or analysis requires evaluation and proves the necessary totality, effect-freedom and no-abort conditions. A known invocation must lower to verified `Ir.Fn`, execute through `Compiler.stage`, and re-enter residual typed IR; Lua must never compute the user operation.

In parallel, complete recursive/exported type and module-interface construction because it unlocks methods, keyed supply and stable public ABI closure without adding another IR. After those semantics are fixed, replace the temporary process bridge with the persistent staging host described above.
