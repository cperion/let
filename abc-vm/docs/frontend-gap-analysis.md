# Let frontend gap analysis

Status: implementation audit. The checked backend and the ordinary Let/SLet source path are now integrated; the remaining gaps are listed below.

## 1. Finding

The production compiler now follows the required path: profile-neutral ASDL parsing, source semantic
construction into checked `Ir.Fn`, shared ABC lowering, independent assembly/runtime verification,
the C `abc-opt` residual optimizer, and `abc_vm` execution. `tools/slet_frontend.lua` is only a
bootstrap validation oracle. The Lua evaluator and direct source-to-C path are not used.

Ordinary `.slet` and `.let` source now covers scalar control and calls, local records and arrays,
addressable places and stores, scalar-payload sums, slices and strings, references, typed lambdas,
Let managed captures, escaping Let references/slices with promoted backing storage, generic `any`, and
dynamic callable dispatch. Imports preserve the profile
asymmetry. End-to-end fixtures compare interpreted, eager, and lazy staging and optimizer fixpoints.

The difficult remaining work is narrower but still semantic: recursive type cells and type exports,
methods and keyed requirements, nested words, provenance through mutable/deeply nested owners and sums,
module initialization, foreign/defer syntax, managed/address-bearing sum ABIs, and the proof-driven
connection from source static boundaries to VM-backed evaluation.

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
| Source input | `.let`/`.slet`, spans, deterministic imports and asymmetric profile checks | Type exports and richer module interfaces |
| Parser | Shared ASDL parser for schemas, records, arrays, indexing, fields, lambdas, signatures, stores, matches, `use`, `extern`, and `defer` forms | Semantic construction for the still-listed forms |
| Names and captures | Module words, lexical locals, deterministic lambda capture discovery and lifted functions | Nested words, methods, recursive type cells, full interface lookup |
| Types | Scalars, `any`, records, arrays, sums, refs, ptr/slice constructors, strings, signatures and callable views | Recursive sealing, tagged/open source types, exported type names |
| Calls | Direct/tail calls, exact views, escaping managed captures, indirect and dynamic calls, recursively flattened record/array ABIs, and GC-free sum ABIs with aggregate payloads | Keyed/non-prefix supply, methods, and managed/address-bearing sum ABIs |
| Storage | Frame-backed records/arrays, projections, aliases, typed stores, bounds checks, refs/slices, promoted returned backing storage, and owner-retaining captures/aggregate calls | Module mutable storage, raw-pointer source operations, and provenance through mutation or deeply nested sums |
| Control IR | Checked conditionals, switches, loops, traps, joins and completion | General block-bodied handler/lambda construction |
| Dynamic Let | Boxing/casts/tests, generic unary/binary operators, strings, direct word boxing and dynamic calls | Open-word definitions and remaining managed aggregate source forms |
| Modules | Function exports, deterministic private IDs, Let→Let/SLet and SLet→SLet imports | Type/value exports, initialization and public ABI closure |
| Static execution | Explicit VM-backed staging/specialization under all three policies | Source static syntax/proofs and persistent staging images |
| Diagnostics/tests | Stable spans/codes, three-policy source fixtures, import fixtures and optimizer fixpoints | Broader negative lifetime suites and migrated legacy programs |

Two implementation details make incremental growth of the monolith particularly risky: it probes expression types by emitting and deleting assembly, and it has no typed representation between source and bytecode. Aggregate storage, effects, branch joins and borrowing need persistent semantic objects and an independent verifier; they cannot be made reliable by adding more cases to `Function:expression`.

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

The public API provides verified module loading, execution modes, calls and persistent per-VM images. It intentionally has no instruction-budget field or interruption API. Initial scalar staging now uses temporary exported entry points and exact cell arguments through `Compiler.stage`; each invocation currently starts a runtime process and therefore does not yet amortize eager/lazy preparation. Full module initialization will also need an in-process persistent staging host and a compiler-facing way to snapshot or copy the accepted private image without exposing mutable runtime internals as a language ABI.

### 5.2 Frontend and backend boundaries

Keep the current scalar frontend as a bootstrap and instruction-selection oracle, but stop adding language families to its direct source-to-assembly path. The complete compiler frontend must reuse the snapshotted ASDL lexer, parser, AST/type schemas, IR vocabulary, traversal, resolution and analysis code under `frontend/`, adapting those modules rather than rewriting them. Reuse applicable SLet verification when its remaining modules are migrated. The borrow checker applies only to SLet; Let requires GC promotion/provenance/root analysis instead. Do not migrate the Lua execution engine or direct source-to-C backend.

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

## 6. Staged roadmap

### Stage 0 — Freeze the scalar prototype

- Treat `tools/slet_frontend.lua` as a bootstrap frontend and instruction-selection oracle.
- Add positive and negative tests for every feature claimed in `slet-subset.md`.
- Add all four frontend examples to validation; currently only three are executed there.

### Stage 1 — Establish frontend structure

- Keep the intentional frontend snapshot under `frontend/` self-contained and validated; its parser, ASDL schemas, IR helpers, traversal, resolver, analysis and fixtures are the starting implementation, not merely a reference. **Done.**
- Migrate the remaining strict type/capture/lifetime logic in reviewable pieces, retaining its tests while separating profile-neutral facts from strict-only borrow proofs.
- Define an ABC typed-lowering interface over the reused structured representation, with source mapping and an explicit unsupported-node result. **Done for the scalar typed boundary; aggregate/dynamic extensions remain.**
- Migrate type rejection fixtures and fixed expected program results without importing the legacy evaluator or direct source-to-C path.

### Stage 2 — Build VM-backed scalar static execution

- Lower a fully known scalar word to a temporary verified ABC module. **Done for verified `Ir.Fn` input.**
- Execute it through `abc_vm_call` in interpreted, eager and lazy compile-time modes. **Done through the runtime host.**
- Decode integer, bool and multiple results back into exact compiler-known cells. **Done; richer aggregate values remain.**
- Map language aborts and actual VM resource failures to the correct source-level outcome. **Done for scalar entries, including bytecode-to-IR mapping.** Delayed progress and Ctrl-C static-stack diagnostics remain.
- Cache staging modules so compiled policies amortize their preparation cost. **Not yet; the temporary process bridge deliberately establishes semantics first.**

### Stage 3 — Reach scalar specialization parity

- Use VM-produced known values for explicit static bindings and module initializers. Automatically evaluated saturated calls additionally require a sound totality, effect-freedom, and no-abort proof; ordinary known calls remain residual without that proof.
- Emit residual scalar specializations for invocations containing runtime inputs.
- Match the current frontend's integer, multi-result, direct-call, closure and tail-call behavior.
- Require byte-identical residual modules under every compile-time execution policy.

### Stage 4 — Implement the strict memory profile

- Add f64 and complete conversion lowering.
- Close layouts for records, arrays, sums, slices and strings.
- Lower places, frame blocks, module storage, field/index operations, copies, checks, refs and raw pointers.
- Execute known aggregate code and module initialization in persistent staging images.
- Add transactional speculative folds and accepted-image snapshotting.
- Make completed-program lifetime verification mandatory for SLet before staging or residual bytecode execution.

### Stage 5 — Complete strict calls and modules

- Lower owned callables, non-retaining views, closures, tagged callables and indirect calls to profile 3.
- Lower `extern` declarations and calls to profile 4, while keeping them disabled in static execution.
- Implement export configuration, imports, namespaces, aliases, result contracts and specialization across modules.
- Preserve optional result inference, methods, keyed supply and defer.

At the end of this stage, sections 1–14 should compile without executing user code in Lua or relying on the direct C backend.

### Stage 6 — Add progressive Let and profile 5

Do this only after VM profile 5 is implemented. Staging and residual modules then use the same `any`, generic-operation, open-word, dynamic-call and GC semantics. Implement Let ownership as GC reachability, not SLet borrow rejection: promote escaping storage and trace managed `ref`/slice/callable cells. Give every open word one collected ordered hash map and a non-owning, non-reused 64-bit layout token; structural mutation changes the token, value replacement preserves it, constant-key caches guard it, and capped lazy versions may carry it. Do not build transition-shape trees or a second dictionary mode. Missing dynamic results abort; managed strings retain owners; `f64` never boxes; compiled wide integers materialize only on escape; and the verifier computes transitive allocation-free functions.

### Stage 7 — Cross-mode acceptance

For every accepted source program, compare observable results and aborts across:

- fixed expected results and diagnostics from source fixtures;
- ABC compile-time execution in interpreted, eager and lazy modes;
- residual ABC execution in interpreted, eager and lazy modes;
- residual C emitted from ABC semantics.

The emitted residual module must be identical regardless of the staging execution policy. Tests must also prove that filename changes do not select VM policy and that malformed bytecode is rejected independently of frontend checks.

## 7. Immediate next implementation task

The VM-backed scalar execution boundary is now established in `frontend/let/stage.lua`. Validation evaluates known functions under interpreted, eager and lazy policies, requires byte-identical staging modules, preserves exact 64-bit cells, maps a language abort to its typed IR/source hook, and classifies a real VM stack limit as a resource failure. There is no instruction or fuel cutoff.

The explicit source-to-VM boundary is available through `Compiler.stage`, and `Compiler.specialize` consumes typed values already produced by that boundary. Ordinary compilation deliberately leaves saturated calls residual because the current source syntax and analysis do not mark a mandatory static binding or prove totality: purity by itself does not prove termination, and speculative fuel is not language semantics. A future source example such as `add(20, 22)` may become a residual constant `42` only under an explicit static construct or a sound totality, effect-freedom, and no-abort proof; the invocation must then lower to verified `Ir.Fn`, run through `Compiler.stage`, and re-enter residual typed IR. Lua must not compute the addition.

After that semantic connection, replace the temporary process bridge with a persistent in-process staging host so eager/lazy preparation is cached, module-image writes can be committed or discarded transactionally, and external interruption can report the static word stack with source positions. `FCALL` must remain unavailable to staging code.
