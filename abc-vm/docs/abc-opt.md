# `abc-opt`: canonical ABC-to-ABC residualization

`abc-opt` is the one component allowed to change verified ABC bytecode for dispatch reduction. It is a C program over ABC modules, not a Let-only IR pass and not a JIT pass.

## Contract

Input is a verified ABC module plus optional conservative facts: pure function identities, non-aliasing references, exact/finite callable identities, non-escaping closure uses, capture ownership, and an inlining/version cap. Output is another verified ABC module with the same language-visible behavior, signatures, result layouts, memory effects and abort order. Missing facts only disable transformations. They never enable a less conservative assumption.

The optimizer must be:

- **meaning preserving:** it symbolically executes ABC semantics rather than recreating source-language rules;
- **verifier checked:** it reloads/verifies its own output before publishing it;
- **deterministic:** module bytes and facts determine output bytes completely;
- **canonical and idempotent:** `abc-opt(abc-opt(M))` is byte-identical to `abc-opt(M)`;
- **provenance preserving:** every emitted operation and abort maps to the original bytecode offset and, when supplied, the frontend source chain.

## Implementation

The implementation reuses the abstract execution already present in `src/residualize.c`: A/B/C symbolic values, constants, homes, context joins, call-graph recursion detection, virtual continuations and `VERSION_CAP`. This machinery must be factored into a shared internal symbolic core with two sinks:

1. the existing JIT sink maps residual operations directly to register-addressed stencils;
2. the `abc-opt` sink builds a residual dependency DAG and canonically schedules it back to ABC.

The ABC sink performs these steps once when producing a module:

3. Seed ABI-visible entries with unknown arguments, then symbolically execute the residual direct-call graph. Private recursive SCC argument headers use the finite `unreached → constant → unknown` lattice: recursive and external incoming edges join to a fixed point before canonical emission. Pure acyclic direct calls use virtual continuations; compatible self-tail SCCs become loops; a direct call whose complete continuation only returns its results becomes a tail transfer. Non-tail and mutual recursive transfers otherwise remain explicit calls with invariant arguments specialized.
2. Discover blocks, direct-call SCCs, signatures, effects and trap boundaries.
3. Seed ABI-visible entries with unknown arguments, then symbolically execute the residual direct-call graph. Private recursive SCC argument headers use the finite `unreached → constant → unknown` lattice: recursive and external incoming edges join to a fixed point before canonical emission. Pure acyclic direct calls use virtual continuations; compatible self-tail SCCs become loops; non-tail and mutual recursive transfers remain explicit calls with invariant arguments specialized.
4. Fold constants using the exact ABC operation semantics.
5. Propagate callable identities and captures. Eliminate exactly known non-escaping closures; defunctionalize finite non-escaping callable sets; retain genuinely unknown or escaping callables and their indirect/dynamic calls.
6. Keep single-use residual values in expression trees. Assign fixed C homes to ordered values, loop-carried values, and values used more than once on one execution path when storage is preferable to safe rematerialization. Cheap pure non-trapping expressions used once on each mutually exclusive path remain local to those paths. Adjacent identical operands may use `DUP`/`COPY`.
7. Compute Ershov numbers and schedule trees canonically onto A and B. Prefer `OPC` for a C-home operand and `OPI` for an encodable constant. Materialize join values with fixed `CSET`/`CGET` homes.
8. Emit functions, branches, calls, compacted reachable descriptor graphs, sections, relocation data and a new-offset to original-offset provenance map. Unknown extension sections disable descriptor compaction because their index-bearing semantics are not known.
9. Load and verify the output module before atomically publishing it.

Effectful operations, explicit traps, potentially trapping checks, foreign boundaries and managed-allocation safepoints are ordering barriers. The optimizer can propagate values through a barrier only when doing so cannot move or remove observable work. IEEE operations retain their original expression grouping. Function signatures and result-cell order never change.

VM stack checks remain defined by the optimized verified module's computed maxima. Stack exhaustion is a genuine host resource failure, not a language abort or observable language result; semantic differential tests run with sufficient stack and do not ignore unexpected resource failures. Tail-position conversion may reduce required call-stack storage. `abc-opt` does not add a fuel mechanism or synthesize logical resource failures. Provenance for a retained or folded trap points to the original abort/check offset, including its inlined call chain.

## Callable lattice and closure elimination

The symbolic value lattice includes callable knowledge in addition to constants, homes and dynamic tags:

1. **One exact target.** A known word, lambda, method or fully known partial application becomes a direct call or an inlined virtual continuation. Captures and a bound receiver remain ordinary symbolic values in registers or frame homes. No environment object is constructed and no closure allocation remains.
2. **A finite target set.** A control-flow join of known callable alternatives uses Reynolds-style defunctionalization. Internally the value is a canonical small tag plus the union of required plain captures. Invocation emits `SWITCH`; each arm restores that alternative's captures and performs a signature-checked direct call, which can then be residualized or inlined. The tag and capture union use fixed join homes.
3. **Unknown or observable target.** A callable loaded from unrestricted data, an open dynamic word, `any`, an escaping callable, or a value whose identity/allocation can be observed retains its real closure/word representation and `CALLI`/dynamic call. Existing VM site specialization remains responsible for it.

The finite representation is optimizer-private. It must not cross an export/import ABI, enter `any`, managed or foreign storage, reach an identity operation, or escape through an unknown call. At such a boundary the optimizer either materializes the original callable representation without changing capture evaluation order and ownership, or conservatively retains it from construction.

Closure elimination never erases capture computation or its effects. It preserves receiver binding, callable signatures, result-cell order, lexical ownership, managed roots and source provenance. Removing an allocation is legal only when closure identity, allocation and collection are unobservable. Each `SWITCH` arm is lowered under the invocation's existing continuation, so direct tail transfers remain continuation-derived rather than target- or recursion-derived.

## Division of labor

The Let frontend lowers typed IR to ordinary verified ABC and may attach optional facts and source provenance. It does not contain a second inliner or stack re-projector. Explicit compile-time evaluation is a separate frontend responsibility: it lowers a staging entry through the same backend and executes the verified module through `abc_vm`. `abc-opt` does not run recursion to completion or decide that a saturated source call is static. Automatic frontend evaluation is legal only at a language-mandated static boundary or with a sound totality, effect-freedom, and no-abort proof; it never uses fuel or timeout as a semantic guess.

The JIT does not invoke the ABC sink. It consumes the already compact bytecode and uses the same symbolic core only to emit register-addressed stencils with block-version context, constants, continuations, and eventually dynamic tags and layout tokens. Re-projecting to A/B/C inside the JIT would duplicate work and discard that context.

Thus the flow is:

```text
typed Let IR -> ABC lowering -> abc-opt -> verified canonical ABC
                                         |
                                         +-> interpreter
                                         +-> eager/lazy JIT -> register-addressed stencils
```

## Differential validation

For each optimizer fixture, validation runs both the input and optimized module under interpreted, eager and lazy policies and compares results, language abort reasons, persistent image changes and externally visible effects. It also verifies deterministic output, second-run byte identity, conservative behavior with facts removed, source/bytecode provenance, and rejection of malformed optimizer output. Callable fixtures cover known lambdas, branch-selected finite sets, captures, receivers, partial applications, tail and non-tail invocation, managed/identity escape barriers, and unknown dynamic words.

The motivating scalar fixture must canonicalize the inlined `sq(a) + sq(b)` region to:

```text
CGET.A 0
MULC.A 0
CGET.B 1
MULC.B 1
ADD.A
RET 2 1
```

That reduction exists for interpreter dispatch. The JIT benefits indirectly from fewer input instructions while retaining essentially the same final machine residual.

`src/optimize.c` is the C residual-DAG sink and module writer. `build/abc-opt`, the public `abc_optimize` API, `build/abc opt`, and the LuaJIT FFI module `frontend/let/optimize.lua` all invoke that implementation. The sink handles pure integer DAGs, shared constant folding, deterministic hash-consing, known control, bounded unknown branch/SWITCH paths, folding through converged paths, path-sensitive rematerialization of cheap pure values, fixed multi-result C phi homes, virtual direct-call continuations, ordered residual direct calls and result projections, iterative direct-call SCC discovery, recursive argument-header fixed points, residual mutual tail calls, stable self-tail backedges, symbolic function reachability, Ershov ordering, fixed C homes for same-path multi-use values, ordered memory/foreign/dynamic effects, trap/check/abort/frame effects, and canonical immediate/C operand forms. In every profile, only functions reachable from exports, ABI-visible code-address relocations, or residual direct calls are emitted; unreachable source functions fall out as a consequence of residual symbolic reachability. `ABC_SYMBOLIC_VERSION_CAP` is the sole path-duplication bound. Emission is verified, deterministic and byte-identical at fixpoint.

`src/optimize.c` is the C residual-DAG sink and module writer. `build/abc-opt`, the public `abc_optimize` API, `build/abc opt`, and the LuaJIT FFI module `frontend/let/optimize.lua` all invoke that implementation. The sink handles pure integer DAGs, shared constant folding, deterministic hash-consing, known control, bounded unknown branch/SWITCH paths, folding through converged paths, fixed multi-result C phi homes, virtual direct-call continuations, ordered residual direct calls and result projections, iterative direct-call SCC discovery, recursive argument-header fixed points, residual mutual tail calls, stable self-tail backedges, symbolic function reachability, Ershov ordering, fixed C homes for multi-use values, ordered memory/foreign/dynamic effects, trap/check/abort/frame effects, and canonical immediate/C operand forms. In every profile, only functions reachable from exports, ABI-visible code-address relocations, or residual direct calls are emitted; unreachable source functions fall out as a consequence of residual symbolic reachability. `ABC_SYMBOLIC_VERSION_CAP` is the sole path-duplication bound. Emission is verified, deterministic and byte-identical at fixpoint.

Dynamic scalar facts track semantic tag sets and widths independently from raw, encoded, boxed, or unknown representation. Proven singleton `u32`/`i32` boxes and immediate-representable constant `u64`/`i64` boxes, matching casts, and selected arithmetic or bitwise operations become ordinary typed DAG nodes; loop-carried raw values remain raw only across compatible homes. Wide operations fold only when their exact result remains directly encodable. Unknown or mixed facts and wide results requiring a runtime box retain the ordered dynamic instruction. If canonical ABC cannot safely materialize a raw value at a generic dynamic boundary, the optimizer retains that verified source function instead of emitting a partial specialization.

Unsupported functions are retained independently, with direct-call displacements relocated after supported functions shrink. Recursive argument facts are joined monotonically across every discovered entry and recursive transfer, including self-tail transfers that will later lower to backedges: an argument stays constant only when every edge agrees, while carried or conflicting values become unknown. A one-result, single-use non-tail recursive call can remain ordered inside an unknown control arm and feed the surrounding residual DAG. Compatible self-tail frames become residual backedges, direct self-calls whose sole continuation returns their results canonicalize to the same backedge form, and eligible self-tail callees inline into acyclic callers as nested loops. Direct-return transfers to other functions become `TCALL`; mutual or genuinely non-tail SCC transfers remain explicit `CALL`/`TCALL` operations while invariant arguments still specialize. More complex effectful joins, hidden results, incompatible or irreducible frames, dynamic tail/result shapes, and functions with live lexical frame blocks remain conservative without preventing unrelated functions from optimizing. Hidden-frame-result callees are not virtually inlined: optimizer C homes must never cross `CALLOC`/`CFREE` block boundaries. `FADDR` is ordered with frame effects. The full-profile writer preserves memory, callable, foreign, dynamic and GC sections, rebuilds typed function entries, relocates residual calls plus surviving load-kind and indirect-site PCs, and removes metadata for eliminated instructions. It roots dynamic descriptors from every surviving descriptor-bearing instruction and every retained GC root, traverses pointer, slice, signature, record, array, sum, and closure edges, then compacts and remaps the reachable graph. Exact non-escaping code-address closures become virtual direct continuations; finite alternatives discovered along bounded control paths become guarded direct arms. ABI-visible addresses, unrestricted storage, foreign/dynamic boundaries and unknown identities are escape barriers and retain their real representation. Because path guards already provide the private discriminator, no callable tag is materialized or allowed to escape. `abc_optimize_mapped` returns residual-PC to original-PC provenance; staging maps diagnostics directly without replaying user code.
