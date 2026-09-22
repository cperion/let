# Word — implementation contract for the target compiler

Status: target contract for a hard replacement, not an implemented compiler. This revision specifies
the replacement architecture; it does not begin the code port. `target.asdl` is its checked data
vocabulary. No compatibility layer with the old evaluator or IR is required.

The language commitments are words, explicit `:of`, demand-driven normalization, execution-discovered
binding times, actual lexical owners, value copies and non-retaining borrows. This document makes the
compiler rules implementing those commitments explicit. Existing code and tests are evidence to
examine, not authority over the target. APIs, diagnostics, graph shapes and previously accepted or
rejected incidental cases may change. Host registration, public references, recursive data layouts,
variants, new numeric families and foreign aggregate layout remain separately specified facilities.

Normative terms: MUST is a correctness requirement; MAY identifies an optional optimization.
An implementation must not replace an unsupported semantic operation with a fabricated value.

## 1. Decisions, including the limits

1. LuaJIT executes source terminals. There is no translated Lua frontend, instruction quota,
   coroutine-local editing, or debug-hook scheduler.
2. ASDL defines the compiler data from the beginning. The schema is not a wrapper installed after
   building an untyped table IR.
3. Runtime functions contain explicit basic blocks, ordered instructions and terminators. Control
   flow is never recovered by the C emitter or a placement heuristic.
4. Every residual invocation of known source code names an independently compiled body specialization.
   There is no inline-first evaluator path, repeated-activation boundary discovery or `outline` policy.
   Primitive intrinsics emit their specified operations directly; they are not hidden Lua-body inlining.
5. One body is shared by equal specialization keys, including repeated calls in the SAME caller.
   Public and callable entry functions adapt that body to a runtime ABI. The C compiler may inline
   generated functions, but source elaboration does not import a callee's branches into its caller.
6. Call planning partitions arguments and captures into static facts and residual inputs. Known
   scalars, immutable snapshots and known code specialize automatically. Mutable places never become
   static because their present contents happen to be known. Explicit `:of` is a source-level static
   obligation, not the only way execution discovers a static argument.
7. Native symbolic branches use checked replay. The frontend shares prefixes, not guessed suffixes.
   The CFG admits joins, but this frontend does not manufacture them from Lua line numbers.
8. Each body has a source result profile: static result slots plus typed dynamic slots. A static
   result does not erase the call's effects. Published profiles are stable; unresolved calls block
   without fabricated values. Recursive groups may use conservative dynamic result contracts or
   checked explicit static contracts. There is no unrestricted inference through arbitrary Lua.
9. Owned executable values have inline by-value environments. Opaque callable views borrow their
   environments. Borrowed captures remain supported in compiler-only temporary bundles.
10. Instruction order is the memory order within a block. CFG edges determine effect order between
    blocks. No memory SSA, global expression interning or instruction placement pass is required.
11. Type/layout identities, source identities and compilation state are separate. In particular,
    equal C layouts do not erase static fields, methods or lexical-owner identity.
12. C emission consumes a closed, verified artifact and never source words or Lua functions.

Two guarantees are explicitly NOT made: arbitrary Lua truth tests on proxies are not interceptable,
and N independent symbolic decisions in a single terminal do not have guaranteed linear compilation.
Achieving those guarantees requires a different frontend contract, not more backend machinery.

Independent runtime compilation does not mean every invocation executes at runtime. Fully static,
staging-pure calls normalize separately. A residual body may also expose a proved static result while
retaining a runtime call for its effects or possible nontermination. Sections 7–9 define this split;
there is no fallback to contextual inlining when it is difficult.

## 2. Ownership of compiler state

| Lifetime | Owned state | May contain source terminals? |
| --- | --- | --- |
| Session | definitions, frozen capture witnesses, word/type meaning interning, completed static demands | yes, frontend only |
| Compilation | configuration, instance/entry registries, contracts, static-result atom pool, result profiles | frontend part only |
| Attempt | decision tapes, events, capture-template instances, fresh symbols, storage roots, temporary IR | frontend part only |
| Closed artifact | functions, runtime types, exports, provenance maps, ABI/layout plans, trap bindings | no |

Interning is global within one session's schema context, not process-global immortal storage.
A public Word proxy owns its private payload; collecting the session and its proxies must collect
that context. The current ASDL implementation uses strong interning caches, so putting source-related
interning in a module-global context would violate the collection contract.

An artifact may retain its immutable runtime type context. It must not retain the session, evaluator,
word proxies, source function environments, active frames, or mutable compilation registry.

Every abrupt exit restores the invocation stack to its entry depth. Failed compilation state is
abandoned; the same session can retry. Only completed, dependency-checked static values are cached
on session specializations. Runtime invocations are never memoized.

## 3. ASDL contract

`target.asdl` parses with the repository's actual `asdl.lua`. The standalone check is
`luajit new/test/target_schema.lua`; it is intentionally not registered in the current compiler's
suite because the target is not installed. It checks schema construction and actual vendor behavior,
not compiler semantics. Its namespaces are:

- `Identity`: frontend canonical keys and selectors;
- `Ty`: fully resolved runtime value types and input interfaces;
- `IR`: sealed functions, blocks and operations;
- `Source`: frontend definitions, values, frames and call plans, never artifact data;
- `Analysis`: result profiles, provenance atoms and tail decisions;
- `Policy`: normalized, data-only trap actions and bindings.

Mutable registries and builders own ASDL records; they are not themselves immutable graph nodes.
Only constructors marked `unique` are interned. Instruction occurrences, calls, allocations, blocks
and functions are never hash-consed.

The vendored ASDL behavior is part of the implementation contract:

- list fields require `terralist` instances, not arbitrary Lua arrays;
- `unique` list constructors intern sequences, not sets;
- interning does not freeze objects or lists;
- sum methods are copied to children; defining a parent method after child overrides overwrites them;
- sum variants have `.kind`; product records do not automatically have it;
- `__fields` describes fields, but is not an SSA-use or control-flow visitor.

Constructors MUST copy caller lists, canonicalize where required, and never expose mutable interned
lists to clients. No `init` method may attach contextual state to an interned object. Debug checks
may fingerprint supposedly immutable objects to detect mutation.

`schema.lua` is the sole installer of methods on ASDL classes, parents before children. Methods are
intrinsic: printing, constructor classification and structural metadata. Analyses use external tables.
Semantic visitors are explicit and exhaustive: `uses`, `definitions`, `successors`, `places`,
`referenced_functions`, and `rewrite_ids`. A reflective tree walk is not a substitute for these.
Tests must enumerate every instruction and terminator variant against these visitors.

All analysis maps are partitioned by function ID before indexing a function-local Value, Bundle,
allocation or Origin. An interned `IR.Value(1)` is an ID descriptor, not a global SSA definition or
an executable expression. Using that object alone as a whole-program liveness/type key is a bug.

Schema primitive `number` fields used as IDs/indices must be checked positive integers in the
constructors. Scalar UInt fields must be integers in 0..4294967295. ASDL's primitive checks alone
are not sufficient. All IR IDs are function-local; textual function IDs are compilation-wide.

## 4. Identity and type meaning

### 4.1 Definitions and static values

Allocate a definition token at construction, but establish its capture freeze witness after module
construction or at first validated demand. Do not freeze an unassigned recursive Lua upvalue merely
because `word(...)` was called before its forward definition. Recheck the witness at subsequent uses;
changed captured bindings reject rather than silently changing an existing key's meaning.

A definition token names a frozen source definition/template, not just bytecode or source location.
Separate source definitions do not become equal merely because their bytecode matches. Captured
static metadata participates in template identity. Mutually recursive code links are finite tokens
in a checked code group, not recursively expanded Lua objects.

`Identity.Static` represents checked supplies: typed U32, Bool, Unit, a type meaning, a word key or
an immutable aggregate snapshot. Raw Lua captures additionally have a frontend freeze witness;
raw strings/numbers are not silently converted to typed runtime constants in that witness.
Arbitrary tables and unregistered host functions are not static values; they reject or reach an
explicit registered host-integration TODO. Identity is not a purity proof.

For a source key:

- positional bindings are sorted by logical argument index;
- keyed bindings are sorted by field-name bytes;
- duplicate bindings are checked during supply, not silently overwritten;
- aggregate snapshot values follow the semantic schema's canonical field order;
- tuple snapshot values follow logical position, including Unit;
- owners are in lexical outer-to-inner order, with explicit root meaning and selection path;
- immutable actual-owner snapshots contribute their contents;
- mutable owners contribute an interface, never an address or their current contents.

A definition or schema never acquires a mutable parent link. A child occurrence carries its actual
root and lexical path. A detached value does not rediscover an enclosing instance.

### 4.2 Semantic types versus runtime layouts

A source type meaning includes static supplies and executable members. `Ty.Record.meaning` is an
opaque, stable encoding of that meaning. Its runtime `fields` omit methods and erased static fields.
Records with different static meanings may share a C layout but are not interchangeable source types.

Runtime record fields are canonically sorted by name. The layout pass MAY share physically identical
layouts after semantic verification; that sharing never defines language type equality.

`Ty.Tuple` is ordered. This target uses it for compiler aggregate/result representations; it does
not introduce new `word{U32, Bool}` source syntax or change the existing keyed constructor rules.
There is no `packed` or explicit alignment promise in this schema. Foreign layout needs a separate
specified target contract; portable C11 cannot promise arbitrary packing.

`Ty.Sig` is structural after all its inputs/results are resolved. An input-only source callable
requirement is a frontend object, NOT an incomplete `Ty.Sig`. Thus callers can name an equivalent
source signature for `results[sig]` without inventing unresolved runtime types.

`Ty.Owned` includes concrete target identity, user-visible signature and owned environment type.
`Ty.View` includes only the user-visible signature. A `Ty.View` is not an owning existential closure.
InPlace and environment Reference roots are record/tuple storage in this target. Scalar fields can
be selected beneath those roots, but no new source scalar-reference facility or pointer-to-Unit ABI
is implied. The verifier rejects unsupported standalone root types.

### 4.3 Runtime instance identity

`Identity.Instance` contains definition identity, lexical owner descriptors, canonical specialization
facts and residual input sites/types. It is NOT the unmodified source word key plus the caller's SSA
operands. `Identity.Site` names an original argument, capture or owner and a stable subslot path.
KnownAt records a checked immutable value; CodeAt records known executable identity whose runtime
environment is partitioned separately. Runtime records identify the remaining sites and their ABIs.

The constructor expands explicit positional supplies into facts at original argument positions,
then merges execution-discovered facts at those positions. Thus `f:of(3)(x)` and `f(3, x)` share a
body key when all other facts/interfaces agree. Known non-prefix arguments also specialize: `f(x, 3)`
is legal without inventing a new source-level partial-supply syntax. Contradictory facts reject.
Known capture/environment subslots use their own sites, so two different captured constants cannot
accidentally share code after being erased from the ABI.

Facts and residual sites form a non-overlapping decomposition: a KnownAt covers its entire value;
a CodeAt may have residual or known environment children. Every unsupplied source slot is reconstructible
from that decomposition. Canonical order is OwnerRole, CaptureRole, Argument, then selector path;
argument paths retain original indices. Borrow sites never contain current contents or addresses.
Input callable result contracts participate through their resolved input types. Static-result atoms
and caller-local value IDs do not participate in the key.

The registry assigns a stable textual function ID to each instance. IDs are names, not Lua objects;
`Ty.Owned.target` and IR calls reference those names. A code ID must not be a sequential number reused
for different code in a session-level type cache. IDs may be session tokens, with separate deterministic
artifact-local C numbering. No persistent build cache is required by this target.

Before tracing, resolve receiver layouts against callable contracts while retaining their SOURCE
owner meaning and occurrence path. Runtime ABI resolution is not a new lexical owner. Contracts match
source meaning and static-binding refinements; they do not depend on ephemeral normalized method
handles. Two applicable contracts must agree. There is no outline alias table or routing epoch.

## 5. Frontend values and activation frames

`Source` in the ASDL schema defines the evaluator's private values, definitions, frames and call
plans. Mutable registries additionally hold freeze witnesses, work queues and concrete stores.
`Source.Terminal.Lua` may hold a function ONLY in frontend state. A definition with construction-trace
captures belongs to its attempt, not the session definition cache; promotion to a reusable template
clones out dynamic slots and retains only validated static metadata and the environment schema.

The evaluator's private value union has these cases:

| Case | Payload |
| --- | --- |
| Known | source type meaning and immutable/concrete payload |
| Word | frozen definition, static supplies, lexical occurrence, explicit bindings |
| Symbol | attempt token, IR value ID, resolved runtime type |
| RunPlace / ResidualPlace | concrete evaluator-owned store or attempt token, root and typed field path |
| Callable | concrete code, receiver/captures, resolved Owned/View type after callable coercion |
| RawValue | an uncoerced Lua scalar, used only by frontend conversion/capture logic |
| Results | ordered logical values with explicit arity |

Source.Ref binds the canonical key to fresh Owner/Capture values. A concrete RunPlace store is
created and owned by the evaluator; its table field does not authorize arbitrary host tables as
language storage. A Known snapshot can retain an actual-root occurrence without putting that mutable
root into Identity.Static. The occurrence is converted to the correct borrow or detached at a value
boundary before any static key/cache admission.

None of these proxy objects is stored in `IR.Program`. IR constants contain only typed scalar
literals. Known runtime aggregates are materialized through `Construct`; executable values through
`MakeOwned` or `MakeView`. Type meanings and word keys remain frontend metadata.

An activation frame contains purpose, selected word, actual lexical bindings, source location,
terminal identity, argument values, capture bindings and attempt context. Receiver lookup consults
only that frame's actual lexical chain and then its module. It never searches dynamic callers.

The stable module environment verifies the accessing function is the active word terminal before
providing receiver lookup. Ordinary raw Lua helpers do not inherit that receiver. Nested executable
construction records explicit lexical bindings. The loader is a staging environment, not a sandbox.

Every trace receives fresh symbols, local roots, cloned executable templates and capture payloads.
Symbols carry an attempt token; using a symbol from another attempt is a rejection. Source upvalues
are never overwritten to implement replay. Captured bindings cannot be reassigned.

### 5.1 Definition and keyed-member classification

The source constructor protocol is: one plain named schema table constructs a
keyed word; otherwise ordered requirements plus an optional trailing Lua terminal construct an
ordered word. A trailing word is a requirement, not a terminal. Mixed/numeric schema keys and reserved
member collisions reject. Copy supplied Lua tables. `:of()` with no arguments is identity; runtime
application is not partial supply.

Keyed type demand first records all declared names, including lexical ancestor names reached through
explicit schema edges. It classifies each child in deterministic name order:

1. A primitive or keyed type requirement is a data field.
2. An ordered signature without a terminal is a callable data requirement.
3. An executable with outstanding inputs is a method.
4. A closed executable is probed under Normalize with the declared-name context. A primitive/keyed
   type or signature-without-terminal result makes it a data requirement. A non-type result makes
   the original child a method, not a stored result.
5. A probe needing an actual runtime owner/effect classifies as a method. This uses a private
   NeedsReceiver/NeedsRuntime classification signal, never a fabricated receiver. Unrelated Lua,
   capture or unknown-name errors propagate rather than being swallowed as classification results.

Seal the schema with separate data fields, static supplies and methods. Only runtime data fields
reach Ty.Record.fields. Method identity and static supplies remain in its semantic meaning token.
Cached probes record which lexical names they read, so a newly shadowing owner scope cannot reuse
a result classified under a different environment. A runtime-dependent choice of layout is not
made legal by probing: only a successful static type demand can establish a data requirement.

## 6. Purposes and demand

| Operation | Run | Normalize | Residualize |
| --- | --- | --- | --- |
| typed pure scalar operation | compute | compute | fold known operands, otherwise emit |
| immutable aggregate construction | concrete data | static snapshot | snapshot operands, Construct, local storage as needed |
| read mutable source storage | concrete read | reject | immediate Load |
| mutate source storage | concrete store | reject | Store |
| invoke source terminal | concrete frame | normalization frame | separate static demand or body call |
| runtime effect with known operands | execute if supported | reject | emit; knownness is not permission to execute |

Normalize returns a checked static value, which may be a type, word or aggregate. It is not defined
as “all IR nodes became scalar constants.” No runtime allocation or effect is emitted and then
silently discarded to claim successful normalization.

Demands are `value`, `type`, `member`, `callable`, and `layout`. Each demand states its required
result category. Definition construction and `:of` validate/freeze supplies but do not force a terminal
merely because its remaining arity becomes zero.

An empty call invokes the current terminal once. A nonempty call to a saturated, ownerless callable
factory normalizes its result and applies the arguments to that result. Export demand may follow a
returned producer; a private runtime invocation does not implicitly acquire that export behavior.

A static demand cache entry contains its source key, completed result and dependency witness.
Revalidation under result declarations checks nested calls again. If validation reconstructs a
fresh equivalent executable handle, the compilation retains a canonical target for that static
factory demand; it must not allocate a new runtime helper on every replay. This is the same
referential-stability obligation as successful static normalization, not equivalence by bytecode.
If the checked static dependency witness changed, reject; do not reuse a stale target.

## 7. Call planning: binding times and independent bodies

There is no `outline` section in the target API. Every residual source-code invocation has the same
boundary rule; exports and callbacks do not trigger a different source evaluator.

### 7.1 Argument partition

After source arity adjustment and requirement checking, recursively partition the call description:

| Input | Specialization fact | Residual input |
| --- | --- | --- |
| checked Known scalar or immutable snapshot | KnownAt(site, value) | none |
| type or fully static word | KnownAt(site, metadata) | none |
| known code with dynamic captures/receiver | CodeAt(site, source identity) | recursively partition its environment |
| scalar/owned-data Symbol | none | InValue(type) |
| actual receiver or captured place | only its lexical/type/path metadata | InPlace(root type), or a typed bundle reference |
| opaque callable Symbol | no invented code identity | InValue(View(signature)) |

A source by-value record argument is snapshotted before partition. A snapshot obtained by Load is
a runtime value, not a claim that the current memory is static. An immutable aggregate constant can
specialize, but a callee needing mutable parameter storage reconstructs a fresh local copy of it.
Known code arguments preserve their code identity even when their receiver/environment is dynamic.
Their source parameter is reconstructed as a bound word in the callee; it is not unnecessarily
converted to an opaque callback. Unknown code still requires a complete opaque signature contract.

The partition is driven by checked values and compiler-known capture schemas, not by examining a
runtime symbol's future value. No runtime address enters a key. Known scalar captures can erase just
like known scalar arguments; residual capture slots remain by-value or borrowed according to ownership.

### 7.2 Invocation algorithm

1. Check arity, requirements, frozen captures and actual lexical owners. Perform source value-copy
   boundaries. Apply the saturated-factory forwarding rule if this is a nonempty factory application.
2. In Run, execute concretely. In mandatory Normalize, require a completely static call description
   and execute under normalization permissions; a runtime dependency rejects that demand.
3. In Residualize, handle primitive intrinsics through their specified typed operation constructors.
   For an opaque callable, emit Indirect using its declared runtime interface; known actual arguments
   cannot specialize code that is not known.
4. For known source code, form the canonical instance partition. If every value/binding is static,
   try a SEPARATE normalization demand. A successful pure result returns checked Known values without
   a runtime call. It does not import a branch trace into the caller.
5. If that attempt encounters an operation requiring runtime storage or effects, it stops BEFORE
   performing the operation with private NeedsRuntime. Discard its temporary normalization state and
   request the residual body for the same partition. Do not catch arbitrary source failures, resource
   limits or static cycles as permission to fall back. Mandatory Normalize converts NeedsRuntime into
   a diagnostic instead of taking this fallback.
6. If the partition contains residual inputs, request its body directly. Reserve its key before any
   body exploration, and block the caller if its source result profile is not yet published.
7. Emit exactly one Call, then reconstruct source results from the published profile: static slots
   yield their checked values, dynamic slots yield fresh symbols. The call remains even if there are
   no dynamic results, because effects and nontermination must not be erased by result knowledge.

Only grow's scheduler starts that body's Lua terminal with its reconstructed static bindings and
fresh runtime inputs. There is no “first activation” exception, self-entry inlining exception or
retry with an inline callee. Recursive same-key calls name the reserved body. Recursion that changes
known arguments creates new keys, subject to the key/static-work limits.

Normalization of a fresh aggregate may construct an immutable snapshot. If source execution tries
to mutate it as local runtime storage, normalization reports NeedsRuntime before any mutation. The
residual body then reconstructs appropriate fresh storage. A mutable external/borrowed place never
qualifies for the speculative normalization attempt in the first place.

A helper doing `other:of(n)` therefore works for `helper(3, x)` without caller inlining: the callee's
instance binds n=3. `helper(runtime_n, x)` cannot use n as static supply and rejects. That distinction
is a binding-time rule, not a code-generation hint.

### 7.3 Static metadata returned by runtime code

Independent calls must not force every source result into a runtime representation. For example:

```
choose_type = word(U32, function(x) return U32 end)
use = word(U32, function(x) local T = choose_type(x); return T(x) end)
```

The body of choose_type has a static Type result and no runtime return payload. Its caller emits the
body call and receives the known U32 type in the evaluator. The public use entry returns a runtime
U32. If choose_type performed receiver effects before returning U32, those effects would still occur
in that body call. A function returning different static types on different runtime paths cannot
invent a runtime Type representation and rejects.

Static factory results are canonical demand results, not newly discovered global outline selections.
There is no routing epoch or invalidation of earlier inline bodies: no such bodies exist.

## 8. Body interfaces, source result profiles and runtime entries

### 8.1 Body inputs

A body receives the residual sites in its canonical partition, in OwnerRole, CaptureRole, Argument
order. Original argument indices and stable capture subslot paths determine order within each role.
There are no holes for erased Known facts. The input plan reconstructs source arguments and bound
words from facts plus those inputs. A known code argument can decompose into several environment
inputs; a source argument need not correspond to one body parameter.

Receiver roots use InPlace. Residual owned data use InValue. Borrowed capture bundles use InBundle.
An implementation may group adjacent environment slots into a declared capture record/bundle only
through a deterministic mapping included in the instance plan. The same key must never acquire two
input ABIs. Source mutable by-value parameters get fresh local storage initialized from their data,
including parameters reconstructed from static snapshots. Borrow inputs alias their incoming places.

IR.Function.hidden counts OwnerRole/CaptureRole inputs for a Body. Argument-environment inputs remain
mapped by their sites, not guessed from that count. C and check need only the fully resolved IR input
vector, not the source argument map. No receiver opcode or caller-stack owner inference is needed.

### 8.2 Source result profile

A profile has one slot per SOURCE result:

- StaticResult(atom, optional runtime representation type): the exact checked value is known;
- DynamicResult(type): the value is supplied by the runtime call.

Atoms are opaque identities in a frontend-owned constant pool. They may denote scalars, immutable
snapshots, types or completely static words. No atom hides a runtime environment or borrowed place.
`types.lua` compares atom identities and runtime types; it never looks up a source word or executes
Lua. Static-only metadata has no runtime representation type. A dynamic closure is never a static
atom merely because its code is known.

The body's IR signature returns ONLY DynamicResult slots, in source-slot order. Call result IDs map
back to those slots. Static source results are reintroduced by the frontend; their atoms never enter
IR.Program. Ordinary return-copy rules still apply: a returned aggregate's data does not authorize
making its subsequently mutable storage static.

Example profile `[Static(U32 type), Dynamic(U32), Static(Unit)]` has source arity three and one runtime
return value. The caller emits the call, receives a U32 symbol, and produces three source values.
A body with all-static results has an empty IR return vector but still has a runtime call site.

### 8.3 Public and callable entries

IR.Function.role is Body or Entry. A public export or materialized executable needs an Entry with a
fully runtime, externally usable signature. The frontend constructs this adapter as typed IR; it is
not an old-API compatibility wrapper and it does not execute the source body in the caller.

An Entry takes all remaining source runtime inputs (including logical Unit positions), supplies
explicit static bindings, requests/calls the body, and materializes its source results. Known scalar
and aggregate results become constants/constructs. A static executable result can become an owned
callable if its own entry and environment are representable. Static-only Type results reject at an
external runtime boundary. A body may therefore be useful internally but not exportable as a value.

Entry hidden inputs are, in order: runtime receiver root, owned capture record, borrowed capture
bundle, followed by the remaining user inputs. Absent roles occupy no slot. Entry.hidden records
that prefix. MakeOwned and MakeView target Entry functions, never specialized Body ABIs. Owned/View
signatures describe the Entry's user-visible inputs and full materialized result vector.

Opaque signatures have dynamic result contracts only. Known code arguments need only source calling
requirements and can retain static-result profiles through specialization; erasing them to View
requires a representable runtime entry and a complete opaque signature. Known arguments passed to
Indirect do not change its ABI.

Body sharing is independent of entry sharing. The five-decision helper example has two BODY keys
and a public entry; a wrapper must not be counted as another exploration of either body. Pure IR
forwarding entries may be coalesced during lowering, but that optimization is not necessary.

### 8.4 Source arity versus runtime arity

The evaluator preserves explicit source result vectors and Lua adjustment: nonfinal calls contribute
one value; final calls expand; assignments discard excess results and fill missing positions with
Unit. Runtime application must then satisfy the word's remaining arity. Preserve nil argument counts
with pack; do not infer arity from Lua's length operator or from a C tuple layout.

Word defines zero returns and one nil as one Unit result. Multiple returns retain all logical slots,
including Unit. An explicit empty result contract denotes one Unit slot. A single tuple value is not
confused with several returned values during source execution.

There are TWO projections: static source slots disappear at the body boundary; Unit runtime slots
disappear at C lowering. Neither projection may silently renumber source positions. Each IR Call
has exactly the outputs of its target IR signature, which may be empty. Each Indirect has all outputs
of its Entry signature. No guessed Result(call, i) is exposed to Lua.

## 9. Result discovery and the instance scheduler

A registry record has instance, function_id, input_plan, source_plan, status, published_profile,
path_evidence, generation and waiters. Status is queued/exploring/waiting/complete. The published
profile is initially Unknown and is assigned at most once. Building a body and publishing its
interface are distinct operations. Source plans, constant atoms and pending returns are frontend
state, not incomplete IR functions exposed to downstream passes.

### 9.1 Contracts

`results[word]` constrains a source specialization and all refinements of its static bindings,
including compiler-discovered argument facts. Explicit :of and automatic binding of the same value
therefore obey the same contract. Match definition and source owner/path meaning, and require the
contract's static bindings to be a subset of the instance's facts. More specific contracts do not
silently override less specific ones: all applicable contracts must agree.

Contract spelling is concrete:

```
results = {
    [f] = U32,                         -- one dynamic result
    [g] = {known = U32},               -- exactly the static U32 TYPE
    [h] = {known = U32(3)},            -- exactly the static scalar 3
    [k] = {U32, {known = Bool}, Unit}, -- ordered source result slots
}
```

A type requirement means DynamicContract. A plain table with exactly the key known means
StaticContract. Otherwise a table must be a dense list of slot contracts; a singleton known table
is not interpreted as a list. Empty lists denote one Unit result. Validate known values with the
same no-runtime-binding checks as static supply. Missing/static-only runtime representations reject
DynamicContract. Structural input-only signatures used for unknown code accept dynamic contracts
only; static result promises on opaque code are outside this target.

A dynamic contract fixes a slot to Dynamic even if a particular body path computes a constant.
A static contract fixes its exact value and is checked on EVERY normal or handler return. It is a
signature assertion, not a fabricated inference or proof of termination. Contracts also constrain
successful normalization results. An explicit static contract can ground recursive metadata results.

### 9.2 Collecting evidence without publishing guesses

Completed return paths produce vectors of candidates. A candidate is either an exact static atom
with an optional runtime representation type, or a dynamic runtime type. Static atoms must be free
of runtime captures/occurrences. An unresolved executable materialization blocks only if a runtime
representation is actually required; a checked entirely static word may be returned as metadata.

Candidate merge is:

- same static atom on all considered paths: static candidate;
- distinct static atoms with the same concrete runtime type: dynamic candidate of that type;
- static and dynamic candidates of the same runtime type: dynamic candidate;
- different arity, incompatible types, or differing unrepresentable metadata: conflict.

An explicit opaque result contract may supply a checked coercion to View; without such a contract,
different concrete closures are not unified into an implicitly owning existential. A merge never
widens U32 into Bool or invents a runtime Type.

DO NOT publish a static candidate from just one completing path. The other path might return another
value, and the caller could otherwise execute arbitrary Lua using a false constant assumption.

The deterministic scheduler first exhausts an instance's currently runnable paths. At quiescence:

1. If all paths and returning trap-handler contributions are complete, infer a profile from the full
   candidate merge, respecting explicit contracts. Publish it and finalize the body.
2. If paths are blocked, prioritize their not-yet-explored dependencies and recompute runnable work.
3. When the dependency component cannot otherwise progress, a node with completing-path evidence
   may publish a CONSERVATIVE dynamic profile if every unconstrained slot has a concrete runtime
   representation. Explicit static slots remain fixed by their contracts. Resume waiting calls.
4. If no such grounding exists, require a suitable result contract and report the blocked cycle.

Once published, a profile never changes. A conservatively dynamic slot is not later narrowed to
static; later return paths are checked and materialized against that fixed profile. This avoids
whole-program ABI invalidation and speculative compile-time values. Deterministic key/path ordering
and dependency-first scheduling make the conservative choice reproducible.

Thus `if n == 0 then return 3 else return f(n-1) end` can ground a dynamic U32 recursive result.
Proving that its result is always 3 is not required; a checked `{known=U32(3)}` contract can express
that stronger fact. A nonrecursive body returning 3 on every completed path can infer a static slot.

### 9.3 Driver protocol

```
prepare export/callable entry demands and explicit contracts
reserve requested body keys before executing their terminals

while dependency progress is possible:
    execute runnable instance paths from fresh activations
    Fork                  -> enqueue both decision tapes
    NeedProfile(callee)   -> register dependency, reserve callee, suspend this path
    Returned(values)      -> check source rules and merge candidate evidence
    Check with Handler    -> add the handler's logical result contribution/dependency
    source failure        -> abort compilation
    at quiescence         -> publish only according to section 9.2; wake waiters

require all reachable bodies, handler/ABI entries and contracts to complete
project static result slots out of body returns; finish typed IR
verify, close ABI/layouts, emit
```

A blocked call supplies neither a fake scalar nor an unknown-shape proxy to Lua. `r.field`, return
expansion and :of cannot execute past NeedProfile until a real interface is available. Retry the
whole activation, not a reconstructed stack continuation. No reservation executes a callee inside
its caller's residual trace.

Return evidence is recorded only after adjustment, value-copy and escape checks. Inferred profiles
are not published before their supporting returns are checked. A declared/conservatively grounded
profile may be used while bodies are pending, but no artifact escapes before all bodies validate.
A later contradiction aborts the compilation, never patches a cached signature.

There are finitely many body keys under the resource bound, and each publishes at most once.
Waiters retry only on actual dependency progress. Known-changing recursion is bounded by keys/static
work, not misclassified as a same-key cycle. Result discovery does not authorize runtime effects
inside mandatory normalization.

## 10. Replay protocol and construction identities

An attempt owns a fresh builder, activation stack view, decision tape, event stream and capture map.
Source storage effects are represented, not performed on concrete host instances during tracing.

Events include typed instructions, terminal enter/leave, executable construction and symbolic
decisions. Event operands use typed structural descriptors and trace-local IDs. Replay equality is
modulo a bijective renaming of values, storage roots and bundles. It is not equality of source lines,
fresh Lua closure addresses, instruction counts or untyped hashes.

At a known comparison, return its real Lua boolean. At a symbolic comparison:

1. emit the typed Bool predicate;
2. validate the recorded prefix if a tape choice exists;
3. record that choice and return the corresponding Lua boolean;
4. otherwise raise private `Fork(predicate, prefix)`.

The driver stores the prefix once, explores true and false from fresh executions, strips checked
replayed prefixes and assigns disjoint IDs to arm-local definitions. Prefix effects therefore execute
once in the generated function. All exit paths consume their full tapes. Divergence is a source
staging rejection, not silently accepted nondeterminism.

A blocked signature path may be retried, but provisional call events must not be compared with fully
typed call events. Prefix commitments belong to an attempt generation whose dependency facts are
fixed. On relevant signature progress, rebuild that instance's tentative tree and preserve only its
established result constraints. This is bounded replay, not continuation mutation.

For executable construction, a template site key contains enclosing template identity, construction
event ordinal and checked control prefix. A replayed site reuses its template metadata but receives
fresh runtime capture values. Different lexical occurrences or static capture bindings remain distinct.
No source upvalue is patched. Clone terminals and rebind compiler-owned capture slots per activation.

Default CFG production is a tree of blocks with empty block-parameter lists. It needs no guessed
join. `Jump` and block parameters are specified for ABI lowering and independently proven graph
transformations; their availability does not authorize frontend suffix merging.

`if symbol then` and mixed-category raw equality remain outside the supported symbolic protocol.
Prototype inspection validates environment access. It must not claim complete symbolic-branch
rejection without a separately specified abstract interpretation of LuaJIT bytecode.

## 11. IR construction and operation contracts

`target.asdl` is the complete initial instruction vocabulary. Builders track a type/category table
and source provenance, and produce fully typed instructions. There are no mutable type fields on
interned expression nodes.

| Instruction | Required behavior |
| --- | --- |
| Constant | checked U32, Bool or Unit literal; no source word payload |
| UnaryOp/BinaryOp | scalar operands; U32 arithmetic/bitwise semantics; Eq on supported scalar types; Lt/Le on U32 |
| Construct | ordered fields of the declared record/tuple; immutable value, not storage |
| Extract | immutable aggregate operand; selector kind and field type must match |
| Alloc | fresh local storage identity, fully initialized from a same-typed value |
| Load | immediate same-typed snapshot of the selected place |
| Store | same-typed assignment, after the RHS has been fully snapshotted |
| Call | complete target input/result signature; arguments include all hidden inputs |
| Indirect | callable must have Ty.View; operands match its user-visible signature |
| MakeOwned | concrete target and owned environment match Ty.Owned; no retained borrow |
| OwnedEnvironment | immutable extraction of an owned callable's by-value environment |
| MakeBundle | compiler-only environment; each Saved slot takes a value, Reference slot a place |
| BundleValue | read a Saved slot; references are accessed through Place.Captured |
| MakeView | allocate a temporary adapter environment from the target's entire hidden prefix |
| Check | if failure is true, invoke the bound trap policy; successful path continues |

A function's hidden prefix is supplied by `MakeView.bindings`; its remaining inputs/results must
exactly match the view signature. It cannot partially bind arbitrary user arguments implicitly.

Binary arithmetic folds only checked known operands using the existing U32 implementation. Integer
multiplication must not use an inexact Lua double product. Quotient/remainder on a known zero reject
at the source operation. A dynamic divisor gets an ordered `Check(divisor == 0, "division-zero")`
before Quot/Rem. The verifier checks the guard on every path reaching an unsafe operation, including
that it tests the same SSA divisor. An unchecked trap policy is an explicit precondition, not a
missing guard in the input IR.

Allowed initial simplifications are constant arithmetic/comparison, Extract(Construct(...)), and
eliminating a branch whose condition is known. No Load, Store, Call, Check, Alloc or bundle-allocating
operation is eliminated or moved by hash-consing. CSE across control flow is optional separate work.

### Places and copies

A Place is rooted in this function's Alloc, a place input, or a Reference slot of a live bundle.
A field path is type-checked at every step. Capturing a nested field records its actual root plus
path: replacing that field later must be visible through the capture. Do not capture the address of
an old detached child snapshot or infer a parent from an address.

A scalar field selection immediately emits Load. An aggregate handle can retain a place until a
by-value boundary. Construction, assignment, value argument binding and return snapshot records.
Snapshotting a place may use one whole-record Load; recursively expanded Loads/Constructs are not
required. An SSA aggregate value is already a snapshot and can be reused without another copy.

Source local aliases of a place still alias; copying a record into another data location does not.
Occurrence routes detach at the existing construction, parameter, result and static-supply boundaries.
The copied data has no hidden parent pointer. The source-level adapter, not C layout, enforces this.

## 12. Closure and borrowing contract

### Capture conversion algorithm

At a residual executable-construction site, enumerate captured bindings by stable upvalue index.
Classify each binding before producing a runtime environment:

1. Static type/word metadata and checked raw Lua scalar captures remain frozen template metadata.
   They must not recursively hide symbols, places, or mutable actual-owner routes.
2. Typed scalar captures, whether Known or Symbol, become by-value environment slots of the same
   runtime type. Constantness must not randomly change that site's environment layout across paths.
3. Owned executable captures become by-value owned fields after their callable type is established.
4. A mutable aggregate place, a bound mutable method, an opaque callback, or a snapshot occurrence
   still rooted in mutable owner storage becomes a non-retaining binding. Preserve actual root/path;
   do not misclassify the occurrence as static merely because its visible payload is known.
5. Recursive executable links within the same template group become code-link metadata. Acyclic
   executable captures become value fields. Compute the group's stable slot ordering once; each
   activation supplies new values. Never create runtime self-pointers for those links.
6. If a required captured executable's result is unresolved, issue a signature dependency. If the
   group cannot be grounded, require a result declaration; do not recursively fabricate environments.

Separate immutable value slots from borrowed slots as required by the function interface. Clone each
terminal from its validated prototype and bind slots from this activation's environment. Conversion
is bounded at depth 32. Source record methods still cannot hide mutable state in arbitrary captures;
that state belongs in their explicit receiver. Reaching graph sealing with an unconverted trace-bound
capture is a compiler bug.

### Owned code

An owned callable has one concrete `Ty.Owned(target, signature, environment)` type. Its environment
is Unit for capture-free code, otherwise an owned capture record. Its target has no borrowed hidden
inputs: zero hidden inputs for Unit, otherwise one by-value environment input. Immutable lexical
owners may have been erased into the static code identity.

Captures include snapshots of mutable storage when the source captured the VALUE. Such a Load is
not a borrow. Capturing the PLACE instead creates a borrowed callable. The distinction is explicit
before IR construction and checked again through operand provenance.

Recursive code links live in the template group, not as pointers inside an owned environment.
Acyclic captured owned callables are by-value fields. Recursive environment layouts needing an
infinite by-value type are rejected; a code cycle does not license an infinite value layout.

### Borrowed code and adapter environments

A temporary `Ty.Env` is not a source record and cannot be a result type or Ty.Owned environment.
Its Reference slots can retain places for a non-retaining call. Saved slots can carry owned values
or non-retaining callable views. A bundle is a separate IR category: it cannot accidentally enter
Construct, Store or Return as an ordinary value.

`MakeView` creates an adapter record containing copies of all bound by-value hidden inputs and
references for borrowed inputs. The view's pointer refers to that stable temporary record. There
is no bitcast from a temporary value expression and no reference to a callee's dead environment.

Opaque View inputs/symbols are conservatively borrowed, including when nested in aggregates.
A capture-free known MakeView has no environment borrow, and source construction can use that
established fact where current rules allow. Extracting/loading an opaque callable does not infer
ownership from its signature. The target does not broaden opaque callable result ownership.

### Analysis domain

For each value and bundle, maintain a borrowed flag and origin set from Analysis.Origin. Roots are
incoming places, incoming bundle references, local allocations, temporary adapter environments or
Unknown. Construction unions component origins. Field projection propagates origin information;
loads producing an opaque callable remain conservatively borrowed. Scalar/owned-data snapshots do
not inherit a borrow merely because their source was mutable.

Reject a borrowed value at a retaining source boundary, including Return and ordinary record Store
or Construct. MakeBundle/MakeView are explicitly non-retaining exceptions. Local compiler bundle
storage is not a source retaining store. Calls must honor the non-retaining interface contract.
Foreign implementations eventually registered for that ABI must promise the same contract.

Provenance controls lifetime, not alias-based load optimization. All potentially aliasing memory
operations retain their original order. No general owner inference or heap allocation is introduced.

## 13. Verification and diagnostics

Frontend user errors are rejected before sealing. The graph verifier treats surviving contradictions
as bugs. It does not convert an ordinary bad source branch into an unexplained compiler bug.

For every complete program, verify:

1. unique function/block/definition IDs; declared entry; no incomplete reachable target;
2. input records exactly match signature inputs, including the hidden-prefix count;
3. every value, place root and bundle definition dominates its use and belongs to this function;
4. ordered instructions and exactly one terminator per block; CFG successor existence;
5. edge argument count/types equal destination block parameters;
6. every operation satisfies section 11, including exact call TARGET signatures;
7. every return vector matches the whole declared vector, including logical Unit positions;
8. selector kind, bounds and recursively selected field types;
9. allocation initialization and place-root validity;
10. no static-only meanings, word proxies, Lua functions or frontend keys in runtime operands;
11. all Owned/View target bindings and environment layouts agree with their signatures;
12. no escaping borrowed value, place or bundle; bundle reference roots remain live;
13. every required dynamic safety check dominates its unsafe operation on the successful path;
14. finite by-value layouts; opaque view pointers do not imply owned recursive environments;
15. every used trap reason has a normalized policy and every handler target is complete.

`check.uses`, `check.definitions` and `check.successors` drive dominance rather than ASDL reflection.
Use the ordinary reachable-CFG dominator fixed point; with a branch tree it specializes naturally.
Unreachable builder blocks must be removed before final verification, not used to hide invalid
reachable operations. All source paths actually explored must still satisfy source result checks.

Diagnostics preserve current kinds/statuses: reject=1, bug=2, todo=3, resource=4, lua=1.
Private Fork/NeedSignature/RoutingChange signals are unforgeable driver control values, not public
diagnostics, and never leak through the CLI. Source error locations live in side tables keyed by
function/block/instruction or frontend event, not in interned types or keys.

## 14. Tail lowering and write effects

Tail recognition consumes verified functions and produces side-table decisions; it does not execute
Lua. A candidate is a self Call followed only by transparent result forwarding to Return. No Store,
Check, other Call or arithmetic after it may disappear. Logical result slots and order must match.
Exact aggregate reconstruction may count as transparent only after proving every component comes
unchanged from the corresponding call result.

Before rewriting, ensure that replacing the activation cannot invalidate any operand:

- no next value argument contains an opaque/borrowed callable or local environment borrow;
- no next bundle contains a local/temporary/unknown lifetime dependency;
- each forwarded borrowed root is the corresponding unchanged incoming root with no field offset;
- receiver/capture bindings preserve their checked code and interface identity.

The conservative implementation may leave additional safe cases as calls. It must never optimize
through an uncertain lifetime. Nonself tail calls remain ordinary C calls; proper general tail calls
are not a portable C11 promise.

For a rewritten self call, evaluate every next value/environment into temporaries first. Then assign
parameters simultaneously and reinitialize source by-value parameter locals before restarting the
body. No old local whose address remains live may be reused. Unit positions require no temporary.

Write effects are a separate monotone summary over the call graph. Direct stores contribute writes
to their underlying incoming roots/bundle references. Direct calls map callee effects through actual
arguments. Unknown indirect calls conservatively may mutate aliased incoming storage, including via
their environment; merely finding no syntactic Store is not proof of readonly behavior.

C `const` qualification is optional. If inferred, it uses this transitive summary. Conservatively
emitting a mutable pointer is correct; unsound const qualification is not.

## 15. Closed artifact and ABI lowering

The frontend produces a VerifiedProgram plus normalized trap policies and export metadata. `abi.lua`
then assigns C layouts, result transports, adapter records and legal tail rewrites. The artifact is:

```
Artifact = {
  verified_program,
  function_names, type_names,
  layouts, signatures, result_transports,
  adapters, tails, trap_actions,
  public_type_closure, public_prototypes,
  source_map
}
```

These are side tables with no source words/functions. IDs and runtime types are sufficient to emit
all calls, closures and fields. ABI-created adapter bodies are typed lowering plans with fixed
operations, not callbacks into the evaluator. The lowered plans receive their own validation.

The portable C11 baseline is:

| Runtime entity | Representation |
| --- | --- |
| U32 / Bool | uint32_t / bool |
| Unit | no field, parameter, temporary or result payload |
| Record | struct fields in canonical name order |
| Tuple | struct fields in logical position order |
| Owned | inline environment struct; code selected statically by type |
| View | signature-specific invoke pointer and const void *environment |
| InPlace | typed pointer; optional proven const qualification |
| InBundle | compiler-private by-value bundle struct containing saved values and typed pointers |

All-Unit/empty aggregates and capture-free owned values receive one private padding byte. Logical
positions are never renumbered by erasure. The target requires a C implementation providing uint32_t.

Unit field accesses/stores have no C memory operation, but their already-evaluated operand effects
remain. Equality between Unit operands is constant true, including during lowering of otherwise
valid hand-built IR. No expression may reference a nonexistent Unit C variable.

Multiple logical returns use a tuple transport after Unit erasure; a single logical return preserves
its own aggregate identity. A single Unit returns void. A multi-result all-Unit vector may use void
transport while its logical vector remains available to callers. No user code sees a fabricated
runtime Unit field.

A concrete owned call extracts its environment by value and emits a direct call. Converting it to
View creates a caller-local adapter containing a COPY of that environment, not a pointer to an
unmaterialized C expression. A target with a borrowed receiver and owned captures gets an adapter
containing the receiver pointer and copied captures. Nested borrowed captures remain live by the
same local non-retention checks.

For a View, the adapter has `R invoke(const void *environment, ...)`, casts to its exact private
adapter struct, and forwards typed bindings plus user arguments. Different capture layouts share
the same View signature but not the same adapter layout. A borrowed referent can be mutable even
though the adapter record itself is accessed through const void *.

Instruction order is emitted explicitly. C expressions cannot be used to reorder argument evaluation
or memory reads. A Load that must precede a Store is materialized in a temporary before that Store.
Binary operands are already SSA temporaries or proven safe constants.

Backend-only elimination of redundant copies is optional and conservative: it cannot alias a snapshot
to mutable/addressed storage or remove simultaneous tail-update temporaries. The C compiler is free
to optimize the resulting program further.

## 16. Traps, headers and source

`Check` records a reason and a failure predicate. The normalized artifact binds every used reason.
The frontend, not the backend, compiles any handler words needed by those bindings before closing
reachability. The handler is never invoked as Lua by lowering.

Policies:

- Abort: emit a guarded abort; include stdlib.h in source.
- Unreachable: an unchecked caller precondition that the failure predicate is false. Portable C11
  emission erases the check; it does not pretend to emit a standard optimizer-assume intrinsic.
- Handler: a zero-input, zero-hidden-input runtime function whose complete logical result vector
  equals the enclosing function's. Failure calls it and returns its results from that function.
  Different result signatures require compatible per-function bindings or reject. No handler argument
  payload or implicit conversion is invented.

A Check with Handler is lowered to explicit conditional control before the unsafe instruction.
The success arm continues; the failure arm calls and returns. Abort similarly terminates its failure
arm. This preserves earlier effects and prevents later effects on failure.

The low-level emitter never guesses a trap policy. For compatibility, the existing public facade's
omitted policy normalizes to its current division-zero Abort behavior. A strict facade MAY require
explicit bindings, but changing the existing default is a separate API decision, not a silent port
change. Artifact identity includes target configuration and normalized trap bindings; source word
identity does not.

```
c.header(artifact, header_name) -> bytes
c.source(artifact, header_name) -> bytes
c.translation_unit(artifact)   -> bytes
```

The current emit_c facade uses translation_unit. Header/source are two views of the SAME closed
artifact, not two separate elaborations. Header names are validated/escaped for includes and guards.

Headers contain public reachable data layouts, callback ABIs, exported type aliases, public function
prototypes and invocation helpers for owned executable results. Private function prototypes remain
in source. Public reachability traverses exported values' environments and signatures; a closure
result's invocation helper is part of its public interface even when its code target is private.

Export prefixes are word_, private function prefixes wordfn_. Encode all non-ASCII-alphanumeric bytes,
including underscore, as _XX. Prefixing makes leading digits safe. Field prefixes are f_; tuple field
suffixes retain logical positions. Naming traversal is deterministic and independent of Lua hash order.
Exported types get wordtype_<name> aliases; preserve the current owned-result helper conventions through
the public facade. Header guards and extern "C" wrappers belong to header emission.

## 17. Module contracts and dependency direction

| Module | Inputs | Outputs / authority |
| --- | --- | --- |
| schema | ASDL text, vendored ASDL/List | classes and intrinsic methods only |
| model | schema | source definitions, proxies, meaning/key constructors |
| scope | host, model | protected frames, module environment, actual-owner lookup |
| host | LuaJIT inspection facilities | freeze/dependency witnesses, terminal cloning primitives |
| ops | typed semantic service | checked operation descriptors or known results |
| data | typed semantic service | copies, places, member selections, snapshots |
| owner | model | actual-root occurrence keys and receiver plans |
| closure | model, host, owner | templates, owned/capture plans, clone bindings |
| callable | model | calling requirements, matching and concrete ABI requests |
| eval | frontend modules, grow | source demand/call plans and normalized compilation specification |
| grow | graph, types, supplied semantic services | execution, replay, scheduler, completed program |
| types | schema, diagnostic | concrete result cells and conflict/merge operations |
| graph | schema, diagnostic | builders, exhaustive visitors, ID renaming, local folding |
| borrow | graph, schema | provenance, escape validation, tail-lifetime facts |
| check | graph, borrow | verified program; no source execution |
| abi | graph, check | layout closure, adapters, effects, tail decisions, artifact |
| c | artifact schema, names | deterministic header/source/translation-unit bytes |
| init | eval, check, abi, c | public facade, compatibility defaults and orchestration |

`grow` is the only module that calls a SOURCE terminal. Ordinary compiler helper functions naturally
execute throughout the compiler. Loading the module chunk is an explicit loader operation, not a
runtime terminal invocation.

`eval` creates semantic services and supplies them to grow. Services return values, plans or private
control requests. Metamethods dispatch through the active service; they do not import eval or create
an alternate execution engine. Grow owns `execute_terminal(frame, clone, packed_args)` and restores
frames on success, fork, dependency wait and error. Scope/host may inspect or clone functions, not
invoke them to discover semantics independently.

No static require cycle is permitted. `types`, `check`, `borrow`, `abi` and `c` do not import frontend
modules. The graph's selector type is just Name/Index data, not access to Identity.Source keys.
Public type meanings are converted to runtime types by the frontend before reaching those modules.

Essential internal entry points:

```
eval.prepare(spec)                    -> CompilationPlan
eval.prepare_call(frame, word, args)  -> InlinePlan | RuntimePlan | StaticDemand
 grow.compile(plan, semantic_services)-> CompleteProgram + NormalizedPolicies
 types.declare(id, results, evidence) -> changed | same | diagnostic
 graph.builder(signature, limits)     -> Builder
 graph.rewrite_ids(fragment, mapping) -> fragment
 check.program(program, policies)     -> VerifiedProgram
 borrow.analyze(verified)             -> Provenance + EscapeFacts
 abi.close(verified, policies, exports)-> Artifact
 c.header/source/translation_unit     -> bytes
```

Names express ownership, not a requirement to allocate an empty module for every function. The port
must implement these contracts without letting backend modules inspect frontend proxy payloads.

## 18. Resource and determinism contracts

Retain the public limits and diagnostics currently exercised: max_functions=128, max_paths=128,
max_values=10000, max_normalizations=1000; symbolic decision depth and invocation/helper/static-demand
depth are bounded at 32. Snapshot expansion retains depth 32 and expanded payload limit 65536.

- paths bound an instance's potential leaf paths in an exploration generation, including blocked paths;
- values count assembled instructions/definitions and terminators, including effects without results;
- keys count every distinct requested runtime instance, including pending instances;
- declaration/factory/routing retries do not erase the distinct-key ledger;
- waiters retry only after actual dependency progress;
- routing restarts must add a new boundary; no zero-progress restart loop is permitted;
- uncached static work is charged to its enclosing static demand, not reset by recursive subcalls.

Additional cumulative work budgets may be introduced explicitly, but must not masquerade as type
errors or silent timeouts. There is no source Lua instruction quota. A pure Lua loop that generates
no observable compiler work can still run indefinitely; bounded subprocesses belong to the harness.

Visit exported names in bytewise sorted order, branch choices in a documented fixed order, and
capture slots in stable template order. Use canonical sorted encodings rather than pairs traversal
for names or identities. Two compilations of the same specification produce identical bytes even
after an interrupted compilation or a prior compilation with a different outline policy.

## 19. Acceptance obligations before a replacement is usable

The existing suite is the semantic baseline: 324 passing tests at commit 0bcbaa7. IR-shape assertions
must be translated to the new representation, not discarded to obtain a green count. Generated C
need not retain temporary names; observable results, effects, rejection categories and ownership
rules must remain. Bundle output must match the checkout compiler's output for the same target.

| Obligation | Positive evidence | Required negative / invariant evidence |
| --- | --- | --- |
| ASDL | parse target.asdl; canonical types/keys; every visitor covers every variant | mutation/cache isolation; list validation; parent/child method order |
| Staging | no eager factory execution; :of and required normalization; same-session retry | runtime value/effect in normalization; cyclic static demand |
| Identity | keyed supply permutation; exact static prefixes; actual nested/frozen owners | no caller-derived owner; no runtime address in key |
| Boundaries | five-decision helper twice plus five-decision caller: one helper body, two calls | unoutlined baseline still reaches its documented budget; missing requested ABI rejects |
| Factory routing | Type-erased callable forwarding, constraint revalidation, prior use of target | no endlessly fresh helper identities; no stale-epoch body/prefix reuse |
| Receiver ABI | mutable receiver effects; readonly frozen erasure; signature-valued fields | result declarations survive normalized-owner aliasing |
| Replay | one prefix effect; effects on only one arm; nested short circuit; returned Bool | divergent allocation/call/construction events; expired symbols |
| Results | nil/Unit slots; multiple returns and Lua adjustment; records returned twice | conflicting arity/type; no guessed result shape |
| Recursion | base-arm order independence; grounded mutual groups; declared ungrounded cycle | circular assumptions without evidence; signature conflict after a provisional result |
| Copies | old scalar and aggregate snapshots survive later stores/calls | assigning/copying data must not retarget existing method views |
| Owned closures | return/copy nested scalar/record/owned captures; recursive code groups | no source upvalue mutation; no unconverted construction-trace capture |
| Borrowed closures | extra callbacks, actual-root paths, child replacement, receiver plus captures | return/store/tuple escape; forged bundle root; dangling adapter environment |
| Tail calls | simultaneous permutations, Unit, exact record forwarding, unchanged receiver | local receiver/capture prevents replacement; post-call effects remain |
| C | strict C11 warnings-as-errors; differential arithmetic and state tests | divisor guard; no invalid empty structs, undefined shifts or reordered arguments |
| API | standalone bundle CLI/embedding; translation unit; separately compiled header/source | unknown sections/policies; malformed signatures; unavailable foreign effects |
| Limits | bounded instances/paths/values; clean failure and retry | no leaked frames, fake bodies, source hooks or immortal source interning |

Concrete differential examples belong in `examples/` and executable tests. Inspect IR, run the concrete
interpreter and compile/run C for the same supported program. Include ordered state observations, not
only final arithmetic results. Full suites and C subprocesses remain bounded externally, with wall time
reported.

## 20. What this contract does not leave to an implementer

The port must not independently choose: automatic scalar specialization, always-outlined calls,
coroutine joins, an owning void-pointer closure ABI, readonly inference from local syntax alone,
implicit parent pointers, changed tuple syntax, implicit allocations, an unchecked default trap policy,
or inferred values for pending calls. Those are either explicitly excluded or resolved above.

This is a complete contract for replacing the current supported compiler with ASDL-defined compiler
data and the stated frontend/backend separation. It is NOT a claim that general Lua continuation
joining, all of `word.md`, or the schema alone have been implemented or proven. A port is acceptable
only when the executable obligations above are met; passing the ASDL parser proves the schema's
syntax, not the compiler's semantics.
