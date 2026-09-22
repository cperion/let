# Lua Word DSL — implementation architecture

Status: implementation outline for [word.md](word.md). Several bounded vertical slices are implemented;
see [README.md](README.md) for its exact scope, tests, and executable TODO catalogue.
The wider architecture below remains proposed, not a claim that all mechanisms exist.
The specialization spelling is `:of`. There is no `:with` compatibility alias.
The existing `let/` compiler is not a dependency or a migration target for this first implementation.

## 1. The implementation we should build

Use **LuaJIT** as the host and **C11** as the first residual target.
LuaJIT's Lua 5.1 function-environment model is the baseline, not stock Lua 5.4.

Build one evaluator with three execution purposes:

- **run**: execute concrete words against concrete storage; useful as the reference interpreter;
- **normalize**: demand a static result; runtime storage and runtime effects are forbidden;
- **residualize**: execute terminals with abstract inputs and build typed runtime operations.

These purposes share argument checking, specialization, member selection, arithmetic, and calls.
They differ in what happens at a storage/effect boundary, not in the meaning of a word.
Known operands alone never authorize performing a runtime effect during normalization.

The central path is:

```text
load Lua definitions
  -> immutable words and :of bindings
  -> demand an export or a static result
  -> execute its Lua terminal over language values
  -> Known result or typed residual function
  -> verify runtime storage, types, and operations
  -> C
```

No Lua parser, bytecode translator, general ownership checker, optimizer framework, or universal closure ABI.
`word/host.lua` inspects LuaJIT global-access instructions, including nested prototypes, solely to
validate function-environment dependencies. It discovers opcode IDs from tiny unexecuted functions;
it does not translate bytecode. Terminals execute in Lua. Foreign C terminals still require registration.

## 2. A concrete module tree

Proposed paths, not files already implemented:

```text
new/
  word.md
  architecture.md
  word/
    init.lua      public facade, sessions, loading and export entry points
    model.lua     definitions, handles, values, type descriptions, identities
    scope.lua     module environments, lexical owner bindings, invocation frames
    diagnostic.lua structured rejection, TODO, resource and bug diagnostics
    ops.lua       Lua metamethod adapters and primitive operation semantics
    data.lua      runtime record places, snapshots, and by-value boundaries
    eval.lua      supply, demand, calls, instance cache and result constraints
    trace.lua     branch oracle, replay scheduler and prefix assembly
    ir.lua        typed instructions, blocks, builder and verifier
    c.lua         representation closure and C emission
  test/
    host.lua      Lua hook and environment tests
    model.lua     evaluator, normalization and replay tests
    c.lua         compile-and-run differential tests
```

Keep the files small initially; do not create a subsystem for each heading below.
Primitive words and their intrinsic terminals can live in `ops.lua` until size justifies a split.

Dependency direction:

```text
init -> eval, c
eval -> model, scope, ops, trace
trace -> ir
scope, ops -> model
c -> model, ir
model, ir -> no evaluator or backend
```

`eval` supplies callbacks to operators and scope frames. Neither imports `eval` back.
The backend receives checked artifacts, not Lua terminal functions to reinterpret.

Suggested internal contracts:

```lua
-- model.lua
definition(spec)                   -- immutable ordered/keyed definition
word(definition, bindings, scope)   -- immutable specialization handle
known(value, type_word)
symbol(value_id, type_word)
place(storage_id, path, type_word)

-- eval.lua
specialize(word, packed_arguments) -- :of; no mutation or eager terminal execution
demand(word, purpose)              -- value, type, member, callable, layout
invoke(word, packed_arguments)     -- run or residualize in the active context
instance(call_description)        -- parameterized code identity, not runtime state

-- trace.lua / ir.lua
explore(instance, execute_path)
builder:emit(op, type_word, operands)
builder:terminate(exit)
verify(program)

-- c.lua
close(program, export_specs)
emit(closed_program)
```

These are internal Lua functions, not additional source-language constructs.

## 3. Public use and the actual Lua call protocol

A possible embedding API:

```lua
local compiler = require("word")
local session = compiler.new()
local module = session:load("example.lua")

local source = session:emit_c{
    functions = {
        transform = module.affine:of(3, 7),
        increment = module.Counter.increment,
    },
    types = {
        Counter = module.Counter,
    },
}
```

`example.lua` runs in the loader's environment and returns an ordinary Lua export table.
It can use `word`, `Type`, `U32`, `Ref`, and the other installed words directly.
Export metadata is compiler API, not DSL syntax.
An exported stateful child receives explicit hidden receiver parameters in its C entry.
Exporting a child definition is not the same as calling it without an instance.
Outside a normalization/residualization frame, ordinary word calls use concrete `run`.
Loading a module executes Lua; it does not turn its top-level statements into a C initializer.
A concrete host-side instance is not implicitly a C global. Exporting such retained state requires
a separate explicit storage/initialization plan and is outside the first slice.

### Lua cannot distinguish parentheses from table-call sugar

```lua
w{ x = 1 }
w({ x = 1 })
```

are exactly the same Lua call. Likewise for `w:of{ ... }`.
The implementation receives values, not the punctuation used at the call site.

Use these rules:

- `word` given one plain schema table constructs a keyed definition.
- Otherwise `word(...)` constructs an ordered definition.
- A registered word proxy is not a plain schema table, even if implemented using a Lua table.
- An ordered word binds positional arguments; a keyed word accepts one named supply table.
- An ordered word can accept a table as one positional argument. Its requirement decides what that table means.
- Preserve arity with a local `pack(...) = {n = select("#", ...), ...}` helper and `unpack`; never use `#arguments` to count nil arguments.
- Reject mixed/ambiguous schema tables rather than guessing from Lua iteration order.

Thus `OneOf:of{ circle = Circle, rect = Rect }` is implementable: `OneOf` accepts one case schema.
Its intrinsic validates and freezes the named alternatives, equivalent to the explicit schema-word form.
That is a specified argument conversion, not a special Lua parser rule or general implicit flattening.

An ordered definition's trailing Lua function or registered intrinsic terminal is its terminal.
A trailing word is still a requirement: `word(U32, U32)` must remain a signature.
Runtime application fills the whole remaining shape. Only `:of` allows partial supply.

Reserve `of` on word handles; similarly reserve `eq` where the equality method is available.
Validate collisions at definition construction instead of silently hiding a user member.

## 4. Data structures: separate definitions, specializations, and storage

Use ordinary internal Lua records with explicit tags and constructors.
Public proxies should contain **no raw public fields**: otherwise Lua bypasses `__index` and `__newindex`.
LuaJIT proxies are empty userdata whose protected metatables privately own their payloads.
This allows engine/word cycles to be collected: weak-key tables are not ephemerons in this host.
Copy incoming schema/supply tables; do not retain mutable caller maps.

Conceptual records:

```lua
Definition = {
    id = DefId,
    shape = "ordered" or "keyed",
    requirements = ordered_requirements_or_named_members,
    terminal = nil or LuaTerminal or IntrinsicTerminal,
    module = ModuleId,
    source = SourceLocation,
}

Word = {
    definition = Definition,
    static = ImmutableBindings,
    scope = LexicalOccurrence,
}

BoundWord = {
    word = Word,
    owners = ActualOwnerBindings,
}

Known  = { tag = "known",  type = TypeWord, value = StaticPayload }
Symbol = { tag = "symbol", type = TypeWord, id = ValueId }
Place  = { tag = "place",  type = TypeWord, root = StorageId, path = FieldPath }
```

`BoundWord` is an implementation handle for a word plus its receiver bindings, not another source form.
Its receiver may be a runtime place even though the selected code is statically known.
Do not classify the whole handle as erasable merely because its definition is known.

A keyed definition classifies members once:

- runtime data requirements;
- supplied static values, visible but read-only;
- executable children, selected as words and absent from the data layout.

Use deterministic sorted string keys for the initial keyed layout and schema encoding.
This is representation order, not source field execution order.
Lua has already evaluated a supplied table's expressions before the constructor is invoked.

`TypeWord` points to a word's normalized type meaning. Internal descriptions can include scalar,
keyed, reference, sum, and static-only cases. Those are representation/semantic views of words,
not a competing source type-expression language.
Bootstrap `Type` and primitive words internally; do not require an infinite source-level construction.
The implementation gives each primitive definition its checked constructor input (self-typed, except
zero-input Unit) and an identity terminal. Its unsupplied handle denotes the primitive type; supplied
handles are ordinary value-producing specializations. The common evaluator handles their demand,
callable shape, factory forwarding and constant C export without a separate constructor cache.

Type equality and argument acceptance belong here and in the evaluator, never in C layout comparison.
A recursive identity names a graph node; it does not by itself establish nominal record branding.
The exact structural equality rules, including executable members, must be fixed before broad interoperability.
The first slice can use the same canonical primitive and normalized type handles without claiming this is settled.

## 5. One operation path for concrete and symbolic execution

Metamethods are adapters, not a second evaluator:

```lua
function value_mt.__add(a, b)
    return active_engine():binary("add", a, b)
end

function word_mt.__call(w, ...)
    return engine_of(w):invoke(w, pack(...))
end

function methods.of(w, ...)
    return engine_of(w):specialize(w, pack(...))
end
```

The operator implementation obtains types, checks/coerces raw literals, and then chooses:

```text
Known + Known -> typed constant evaluation
anything dynamic -> typed residual Add
storage read/write -> concrete cell operation or residual Load/Store
comparison -> concrete Lua boolean or branch-oracle decision
```

Box typed known scalars too. Raw Lua arithmetic must not accidentally define `U32` arithmetic.
Raw literals are checked against an expected type. Unconstrained numeric terminal results default
to U32 and must be finite integral values in 0..4294967295; this conversion does not wrap.
Raw Lua arithmetic executes before that check and retains Lua's own arithmetic semantics.
U32 implements wrapping addition, subtraction, multiplication, negation and power; integer quotient
through `/` or `:idiv`; remainder; and 32-bit logical operations through `:band`, `:bor`, `:bxor`,
:bnot, :shl and :shr. The installed LuaJIT's raw bitwise syntax does not dispatch on these proxies.
A known zero divisor rejects; a dynamic zero divisor explicitly aborts before C division/remainder.
Shift amounts are U32: amounts at least 32 yield zero, and negative raw amounts reject. Power uses
exact modular repeated squaring, with exponent zero producing one (including zero to zero).
These are typed U32 rules, not raw Lua-number rules. Other numeric families remain unimplemented.
LuaJIT U32 multiplication uses 16-bit limbs: multiplying two U32 Lua numbers directly loses low bits.
Bit operations use LuaJIT's `bit` library and normalize signed results to 0..4294967295.
Emitted C widens unsigned multiplication and avoids signed-promotion overflow.
Do not extend that claim to U64 or F32 without separate implementations and tests.

### Places are not delayed scalar reads

Selecting a mutable scalar field or resolving `count` reads it immediately:

```lua
local old = count
count = 20
return old
```

must return the earlier value. Returning a lazy `Place` for `old` would be wrong.
Aggregate instance handles can carry places; scalar expressions carry read results.
Every read after a store or potentially mutating call must observe current memory.
Initially, emit loads rather than implementing an alias-sensitive load cache.

Recommended storage boundary: Lua-local aliases of an instance handle retain that instance;
installing a keyed value into a by-value field or ordinary by-value parameter copies its data.
A `Ref` copies a reference instead. Binding performs these operations explicitly, including in `run`.
This recommendation needs language-level tests: ordinary Lua table aliasing alone is not a C value model.
Field-place aliases, replacement, and references to locals must be specified before general stateful programs.

## 6. Specialization, demand, and reusable artifacts

`:of` validates supplied static values and returns a new handle with accumulated immutable bindings.
A symbol or runtime place is not a static value. A bound executable with runtime receiver bindings
must retain those bindings explicitly; it cannot erase them by passing through `:of`.
Definition construction and specialization do not run a terminal merely because its arity becomes zero.

Demand resolves what is actually needed:

```text
value      -> staging-pure result, if available
type       -> a type meaning, possibly a recursive type reference
member     -> selection on the word or its demanded result
callable   -> checked remaining input shape and implementation
layout     -> concrete normalized runtime type
```

The factory example `Identity:of(U32)(42)` needs an explicit forwarding rule.
Recommended rule: a nonempty application to a saturated staging-pure factory can demand its word result
and apply the supplied arguments to that result. An empty `w()` invokes the current zero-input terminal
and returns its result; it does not additionally invoke a returned word.
Test this alongside `List{ ... }`, `add:of(10, 20)()`, and effectful zero-input children.
Do not hide this distinction inside a catch-all `__call`.

### Session-local instance keys

```text
demand kind (static result or residual code)
definition identity and frozen terminal captures
lexical occurrence and owner specializations
canonical known arguments
dynamic argument types and ABI roles
```

Exclude actual SSA IDs, runtime addresses, current mutable field contents, and caller-stack identity.
Distinct owner instances can share code. Receiver addresses become parameters.
Do not assume different parameters are non-aliasing merely because they have different IDs.
A higher-order input retains its concrete word identity; bound receiver payloads become hidden parameters.
This gives direct specialized calls without a universal callable ABI.

Canonical static inputs include typed scalar constants, type/word handles, immutable schemas and checked
aggregate snapshots. Named aggregate :of fields convert plain tables recursively, never runtime places.
Snapshot payloads contain only checked immutable values; canonical keys include the schema and values.
Nested word/type dependencies are rechecked before reuse. Depth (32) and expanded payload-node (65,536)
limits bound snapshot/key expansion, including shared subrecords. Runtime copies and returns materialize
fresh places; normalization can retain only the immutable snapshot, never those places.
Use tagged keys, including scalar type and argument position/name; never serialize arbitrary tables with
`tostring`, depend on `pairs` order, or use a bare hash without collision checking.
Mutable host tables and opaque Lua closures are not freely memoizable static arguments.

Keep one specialization record with an optional successful lazy static result.
The current implementation uses scoped invocation frames to detect active static/type demands.
There is no persistent `building`/`failed` cache state, compiled-IR cache, or type-view cache.
Structural type interning is separate from evaluation. Rebuild cheap IR until measurements justify more.

Recursive residual functions use compilation-local reserved identities and checked constraints; recursive
types remain future work. This is not a general cache framework. Never publish partial IR. Interrupted
builds must leave no active frame or fake result.
Runtime invocations are not memoized: repeated calls must still perform their effects.

Lua upvalues require a freeze boundary after module construction, so forward references have been assigned.
Reachable captures are checked as immutable static captures or explicit dynamic environment inputs.
Arbitrary mutable host captures are outside the replay-safe subset. Their identity is not a valid purity proof.
For the first slice, reject dynamic Lua-upvalue captures; retain receiver state through `BoundWord` instead.
`Identity` capturing its static `T`, and recursion capturing its assigned word, remain supported.

## 7. Receiver scope and the loader

Load DSL chunks using:

```lua
local chunk = assert(loadfile(path, "t", module.proxy_env))
local exports = chunk()
```

Install a stable function environment at load time; never switch a terminal's environment per invocation.
Use a stable empty proxy per module and a per-coroutine invocation-frame stack.
A frame contains the selected word, its lexical occurrence, actual owners, and evaluation context.

Lookup examines **the top invocation's bound lexical owner chain**, then its definition module.
It must never search previous invocation frames for a matching name.
A previous frame is restored on return/error; it is not a lexical parent.
Ordinary Lua locals/upvalues continue to win because they bypass global environment lookup.
Use nil/presence checks, not truth tests, when finding a field whose value can be false.

Definition nesting must be represented explicitly as immutable member occurrences.
Attaching the same child word under two keyed definitions must not overwrite one mutable `parent` field.
A selected child carries the occurrence and corresponding owner bindings.

### A stable proxy alone is not sufficient

An ordinary Lua helper that uses the same proxy would otherwise inherit the active receiver accidentally.
For the first implementation:

- receiver-free helpers use explicit arguments, Lua upvalues, or module bindings;
- receiver lookup belongs to registered word terminals, not arbitrary dynamically called Lua functions;
- at the environment hook, verify the accessing Lua function against the active registered terminal;
- unregistered helper access uses module bindings, never the caller's receiver;
- nested raw helpers do not implicitly acquire receiver lookup merely by being created inside a terminal.

The installed LuaJIT exposes the caller function through `debug.getinfo` at the hook.
This restricted hook protocol handles immediate receivers and retained-root nested keyed occurrences,
not arbitrary Lua lexical scope. `word/owner.lua` carries occurrence paths without modifying definitions.
If this boundary proves unacceptable, change the loader/receiver design rather than silently introducing dynamic scope.
Executed word terminals always install their own frame, including concrete recursion; residual calls
emit typed operations rather than executing another host terminal.
Protect push/pop with an error-safe wrapper. Initially reject yielding during staged execution.

Only installed, staging-safe host facilities belong in the environment.
This is a trusted DSL execution environment, not a security sandbox: arbitrary Lua can bypass conventions.
Calling an uninstrumented host helper cannot be assumed replay-safe just because it uses known arguments.

### Hidden owner parameters have to exist somewhere

Direct `outer.inner.method` selection can retain both inner and outer places in its bound handle.
A plain `Ref(Inner)` carrying only `Inner *` cannot reconstruct an arbitrary outer instance.
Pass required owners explicitly when available; reject a missing owner binding.
Do not add hidden back-pointers to every record or infer parent objects from C addresses.
Nested mutable field places now retain their actual aggregate root and occurrence path. When outer
names are required, private functions receive that root and select the lexical scopes along the path.
Closed child classification receives ancestor names explicitly along declared field edges, not from the
dynamic invocation or type-demand stack. Nested immutable snapshot selections carry transient actual-root
bindings, while direct nested schema selections carry explicit unbound root/path interfaces. Both preserve
lexical occurrence identity; by-value boundaries discard the route and never reconstruct a missing owner.
Escaping bound words and references to dead local storage are not made safe by C-representability.
Initially reject unsupported escapes rather than adding implicit allocation or claiming ownership safety.

## 8. Replay as an executable protocol

The comparison/branch-tree protocol below is now implemented in `trace.lua`. It validates typed
instruction and word-call events, uses fresh deterministic trace-local numbering, and renames values
when assembling shared prefixes and disjoint suffix blocks. C emits nested conditionals. Defaults are
128 potential leaf paths, depth 32, and 10,000 residual values/instructions across the assembled tree.
General joins, feasibility solving and sums remain outside this implemented slice. Executable
construction during tracing has stable construction events and checked immutable capture conversion. Grounded entry calls are supported separately as described in section 9.

A terminal execution creates a trace containing ordered instructions and decision events.
On a symbolic comparison, create a typed predicate and consult a boolean decision tape.
Known comparisons return their ordinary Lua boolean without consulting the tape.

```lua
function Oracle:choose(predicate)
    self.index = self.index + 1
    local decision = self.tape[self.index]
    if decision == nil then
        error({ tag = "fork", predicate = predicate, trace = self.trace }, 0)
    end
    self.trace:decision(predicate, decision)
    return decision
end
```

A private fork signal is control for the staging driver, not a source error.
The restricted environment must not let source `pcall` silently swallow it.
Every re-execution gets fresh trace-local symbols, local storage descriptions, and frame state.
Compilation never mutates the concrete receiver's memory to simulate a residual store.

A depth-first driver is sufficient:

```text
execute path []
  on first unknown decision: preserve prefix P and predicate q
  replay [true], replay [false]
  recursively explore later unknown decisions
  assemble P; Branch(q, true_suffix, false_suffix)
```

During replay, compare the re-executed prefix against the preserved prefix.
Match typed operations, operands, calls, allocations, stores, and predicate events modulo local ID renaming.
Do not match by source line, instruction count alone, or raw freshly allocated Lua identity.
Strip duplicated replay prefixes when assembling the tree.
An effect before a branch must appear once before that branch in emitted code, not once per explored path.
Effects inside an arm remain inside that arm.

Initially do not merge suffixes. Each arm can carry its own continuation to return.
This avoids general phi construction without pretending it avoids exponential path growth.
Apply explicit limits to residual IR size, explored paths, recursion depth, and generated instances.
Symbolic loops that extend the trace reach these structural limits. Ordinary Lua execution has no
instruction quota; loops that emit no trace events can run indefinitely.

Definition construction during replay is also an event. Stable construction keys identify replayed
occurrences; capture templates retain static code metadata while each trace receives fresh capture values.
Locally constructed lexical words pass immutable runtime captures in a separate by-value environment
parameter alongside their borrowed receiver. Graph signatures, typed Call/FunctionRef IR and replay
renaming preserve both operands. Self tails snapshot the next capture environment with ordinary inputs.
Callback adapters use caller-local bundles containing the receiver pointer and copied environment;
non-retention checks prevent their escape. Frozen lexical owners remain checked static metadata and
can disappear into ordinary owned closure environments. Additional callbacks, bound methods and
record places use explicitly non-retaining environments. Compiler-only `Capture` IR allows borrowed
bindings without weakening source record construction. `Address` and `Deref` carry actual root storage
with typed references; field paths remain code metadata. Borrow checks reject retention and block
unsafe tail replacement through capture operands. No public `Ref` or allocator interface is implied.

All runtime effects must be residual operations. Arbitrary host-upvalue mutation, I/O, randomness, and time
are not rolled back by this algorithm. Prefix comparison can detect some divergence, not prove purity.
Keep staging terminals within the declared replay-safe subset.

### Boolean and sum boundaries

`__lt` and `__le` return oracle-selected booleans when both operands are typed proxies.
LuaJIT rejects mixed proxy/number ordering; `:lt`, `:le`, `:gt` and `:ge` use the same operation path.
`:eq` remains the explicit equality adapter.
`if symbol then` cannot be intercepted. Neither can reliably treating `symbol == 3` as language equality.
Keep those exclusions explicit; do not claim the compiler can diagnose every accidental use.
A comparison returned or stored as a value produces branch leaves containing true/false; those become Bool values.
Short-circuit `and`/`or` follow the explored Lua path naturally.

A symbolic sum match is another controlled decision event: its known case schema determines the alternatives.
Invoke only the selected handler per replay, project only its guarded payload, and check all result types.
The backend may use a switch; the evaluator does not need a separate pattern-matching language.

## 9. Recursion: one reservation mechanism, different obligations

### Static type results

Reserve a result cell before demanding a recursive type factory.
`Ref` can retain a reference to that cell without forcing the target's layout.
Seal the cell with the factory's type result, then validate the reachable type graph.
An in-progress result is not an arbitrary usable constant:

```text
Ref(pending type)           permitted indirection
sizeof(pending type)        unresolved obligation, not a guessed size
pending scalar + 1          not a recursive-type knot
closed scalar self-demand  cycle/resource diagnostic, not success
```

`List:of(U32)` must reuse the same cell on recursive re-entry.
Do not normalize `Ref`'s target eagerly enough to recurse indefinitely.

### Runtime recursive calls

**Implemented subset:** compilation reserves a scoped `self` identity for the current entry, with its
static prefix and remaining input ABI. A completed recursion-free path grounds its result. If an
unknown call is reached first, a private unwind suspends that path; bounded discovery explores other
arms before replaying the whole body with typed calls. No provisional scalar or record value escapes
to the terminal. Result/use agreement is checked before emitting C. Prefixes are validated within each
replay/discovery pass; this remains subject to the staging capture contract, not a purity proof.

Calls with the same definition and equal erased prefix use that entry even if the caller passes the
bound arguments explicitly. Other calls inline; cycles returning to the entry can close after finite
inlining. Ordinary helper cycles now suspend the caller and compile a separate helper entry. The caller
then retries from fresh traces/result facts; a numeric typed Call closes the repeated activation.
First activations stay inline to retain known call-site facts, including facts used in :of supply.
Helpers share ordinary open export identities where applicable. Closed export demand remains distinct
from a helper's single invocation: only export demand may follow a returned producer.

All registry/reservation/result facts are local to the compilation. No partial IR is returned, and no
failed state survives interruption. Defaults allow 128 function instances; helper demand depth is 32.
Pending helper groups now publish parameter declarations and result facts grounded in completed paths.
A monotone discovery pass suspends unknown calls and propagates only already-established types. Typed
calls can reference these pending declarations, but program verification requires every body to seal.
Later return conflicts reject the compilation; circular assumptions alone cannot bootstrap a result.
Compile-spec `results[word]` declarations now seed runtime result signatures explicitly. A declaration
is a runtime type or a dense list of result types, including erased Unit slots. It constrains the exact
word instance, including local/static calls; cached outer normalization results are rechecked by
re-execution when declarations are present. Closed declared exports denote a single runtime invocation.
Unannotated ambiguous cycles reject with `recursive-result`, explaining how to provide a declaration.
Remaining helper Type inputs require :of. Runtime callable inputs use the checked callable ABI;
undetermined callable results reject with `callable-result` and require a result declaration.
Changing-instance graphs remain subject to structural function/depth limits.
Concrete recursion has an invocation-depth limit, but no Lua VM instruction quota.

IR keeps typed `Call(target=self)` operations, including payload-free Unit calls. C rewrites only a
self call returned unchanged, possibly through proven copies/projections/exact record reconstruction.
No post-call stores, other calls, arithmetic or changed components may disappear. Next arguments are
snapshotted simultaneously. Ordinary runtime values cannot retain local addresses. A receiver-bearing
tail must keep the exact incoming receiver root and empty path; a caller-local receiver forbids rewriting.
Host invocation depth limits
are not runtime C guards; neither finite C stack use nor termination is guaranteed.

**Broader target (not implemented):** reserve a function identity and a result-type variable before tracing its body.
Same-key re-entry emits a call to that identity, never recursively unfolds another body.
All returns and uses contribute constraints to the result-type variable.
Solve mutually recursive groups before sealing signatures or lowering C.

For `sum_to`, the base return constrains the result to U32 and the recursive return agrees.
A recursion cycle with no information determining a concrete result type needs a diagnostic or an explicit
API-level result constraint; an empty provisional signature is not evidence.
Initially support grounded recursive groups and report the remaining inference limitation honestly.

A recursive call is not automatically a backedge.
Keep it as `Call`; when a path returns exactly that call's result with no intervening work or effects,
and the ABI/storage lifetimes permit it, rewrite it as a tail edge.
A self-tail edge can become a loop with simultaneous parameter replacement.
Non-tail and incompatible calls remain ordinary C calls.
Do not jump back into scopes that own address-observable locals still needed by the callee.
Changing known arguments creates new keys and remains subject to a specialization budget.

## 10. Residual IR and the C boundary

Use stable explicit value/block IDs, not relative stack positions.
A simple block record is enough:

```lua
Function = { id = FunctionId, parameters = Parameters, result = TypeWord, blocks = Blocks }
Block = { id = BlockId, instructions = Instructions, exit = Exit }
Instruction = { id = ValueIdOrNil, op = Op, type = TypeWordOrNil, args = Operands, source = SourceLocation }
```

Initial operations:

```text
Constant, Add, Sub, Mul, Compare
Construct, Project
Local, FieldAddress, Load, Store
Call
ConstructVariant, VariantTag, VariantPayload       (when sums are implemented)

Return, Branch, Switch, Jump, TailCall             (block exits)
```

An ordered instruction list preserves effects. No optimizer may treat Store/Call as freely reorderable.
Calls, stores, and loads carry their checked types and targets forward.
Use explicit temporaries in C so C argument evaluation order cannot reorder staged operations.
For a tail loop, compute all next arguments before replacing any current parameter.

The IR verifier checks:

- every use is defined and dominates its use;
- branch-prefix values are available in descendants;
- argument, result, field, and storage types agree;
- all blocks terminate and all call targets/signatures are sealed;
- variant payload accesses are guarded by the matching alternative;
- static-only objects do not survive as runtime operands;
- every place has a declared storage source and supported escape/lifetime treatment.

`c.close` assigns concrete representations and reports an unsupported one before printing C.
Ignore method children and erased static fields when laying out keyed data.
Walk by-value layout edges to reject cycles; a reference edge does not require the target's size.
Emit forward declarations for referenced aggregates, then complete definitions in by-value dependency order.
Handle empty runtime layouts explicitly: standard C11 has no empty struct.
A single private padding byte is a possible initial representation, not a source-visible field.
Do not hand-compute target sizeof/alignment without a target model; use the C toolchain where possible.

Exported C names are deterministic and mangled independently of source field spelling.
C now emits function prototypes before bodies, including private `wordfn_` helper entries. Calls are
verified against their target signatures; only self calls qualify for the implemented tail-loop rewrite.
Reachability starts at explicit export roots; unused definitions need not be traced or emitted.
Foreign operations require registered type/effect/lowering implementations; an arbitrary Lua call is not an FFI declaration.
Signature-valued fields use the explicit borrowed callable ABI; immutable executable results use
by-value environments. Non-retention checks enforce the storage/lifetime contract.

## 11. The first vertical slices

Implement and run each slice before expanding the next.

| Slice | Must demonstrate | Must also reject/check |
| --- | --- | --- |
| 1. Ordered arithmetic | `affine:of(3, 7)`, concrete run, typed IR, compiled C agreement | wrong arity, non-static `:of`, U32 wraparound |
| 2. Static factories | `Identity:of(U32)`, `Pair:of(U32, U32)`, demand caching | no eager forward-reference read; scalar normalization cycle |
| 3. One receiver | two Counters, extracted `inc`, specialization erasing a field | no receiver leakage across words/helpers/errors; erased-field write |
| 4. Replay | nested comparisons, short circuit, returned Bool, branch-local stores | one prefix effect; divergent replay; path limit |
| 5. Recursion | `sum_to`, a non-tail recursive call, grounded mutual recursion | recursive code identity ignores SSA IDs; unresolved result type |
| 6. Recursive data | generic List through Ref, keyed C layout, then OneOf | by-value cycle; missing owner; unsupported escape |
| 7. Composition | higher-order concrete words, bound methods as arguments | code sharing without receiver sharing; aliasing receivers |

Testing needs three views of the same supported word: concrete `run`, inspected/verified IR, and compiled C.
Exercise several inputs, including boundaries and both sides of every branch.
Compare returned values and ordered effects, not just C source snapshots.
Run known folding against C for arithmetic edge cases.
Keep negative tests for Lua mechanisms we cannot intercept, documenting their actual behavior.

Before slice 3, settle aggregate copy/alias and local-reference lifetime rules.
Before general type interchange, settle normalized type equality for the additional type families.
Before allowing arbitrary helper libraries, settle replay purity and function-environment access policy.
Mutable closures do not acquire hidden ownership: return stateful records, and keep method views borrowed.
`word/borrow.lua` checks non-retention in evaluation and typed IR; see `closure-abi.md`.

These are implementation gates, not invitations to rebuild the earlier ownership proposal.

## 12. What has actually been checked

The original outline probes ran under Lua 5.4.8. They were not LuaJIT validation.
The implementation now runs under LuaJIT, with separate host regression tests.
They confirmed:

- table-call sugar and parenthesized table arguments are indistinguishable;
- mixed table/number relational hooks worked under Lua 5.4, but do not work under the LuaJIT baseline;
- table truthiness and mixed-category equality bypass the desired symbolic behavior;
- an empty module environment proxy can intercept repeated field reads and writes;
- a protected invocation wrapper can restore scope after an error;
- a naive active receiver proxy also affects ordinary Lua helpers;
- the environment hook can inspect the immediate accessing Lua function.

Those probes established host hooks only. The arithmetic/type-factory/record prototype now tests
concrete/compiled C agreement, static demand, interruption-safe retry, nested field places, value-copy
boundaries, keyed scalar/Type specialization, concrete higher-order inputs with callable erasure, type exports,
and explicit layout limits;
see README.md for the implemented subset. Canonical schema identity includes static bindings, not merely
the surviving C layout. Sealed schemas carry complete data-field order and remaining runtime field order;
methods are a separate map, included in semantic identity but excluded from storage.
Record places bind executable children to immediate receivers, including extracted callable arguments
and nested field receivers. Closed children normalize to a data type requirement or classify as methods
when they require receiver/storage access or yield a non-type result. Private control unwinding supplies
no dummy receiver value. Immediate-terminal environment-read names accompany successful normalization
results so owner shadowing cannot reuse an inappropriate cached meaning; no trace/storage is retained.
Signature members have a typed callable ABI. Retained mutable roots, immutable nested snapshots and
explicit unbound nested interfaces support lexical outer owners without inferred parents or caller inheritance.
Escaping mutable receiver views are forbidden by the language; factories return their records by value.
Unbound methods export with a typed receiver pointer; immutable snapshot receivers can erase it.
Mutable bound Lua receivers cannot export. Methods start inline, while recursive selections use the
same typed receiver-storage ABI in private functions. That parameter
is a storage root in IR, never an ordinary SSA value. Calls carry a checked root/path receiver operand;
C passes its address, without copying the receiver. Ordinary arguments and returns remain by value.
Code identity includes owner schema and static method inputs, but excludes mutable receiver identity.
Immutable receiver snapshots specialize by contents without acquiring a writable storage parameter.
Replay remaps receiver roots and verifies their dominance, paths and schemas. No receiver pointer can
be represented in a returned/stored DSL value. Receiver self tails require the unchanged incoming pointer.
This is a synchronous local-call ABI, not a general pointer or closure facility.
Comparison replay now tests nested branches, returned/stored Bool, short-circuit receiver effects,
prefix divergence, dominance, resource limits, and same-session retry after interruption.
Grounded entry recursion now tests concrete/C agreement, static-prefix erasure, void/record calls,
base-arm ordering, typed call verification, simultaneous tail-loop replacement and interruption retries.
Outlined helpers now test wrappers, known-call preservation, static/callable prefix erasure, different
caller/callee signatures, zero/Unit payloads, export sharing, budgets and clean reservation retries.
General recursive-group inference, capture freezing, recursive type equality, and lifetime rules
remain unvalidated.

The implementation still follows a vertical-slice approach: one working word all the way to C is more
useful than building every module's empty framework first.
