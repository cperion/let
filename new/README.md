# Lua Word DSL prototype

Independent of the existing `let/` compiler. **LuaJIT is the baseline host**, with **C11** as the residual target.
The implementation and suite run on the installed LuaJIT 2.1; stock Lua 5.4 is not the baseline.

```sh
luajit new/test/all.lua
luajit new/wordc.lua new/examples/affine.lua > /tmp/word-affine.c
cc -std=c11 -Wall -Wextra -Werror -pedantic -c /tmp/word-affine.c -o /tmp/word-affine.o
luajit new/wordc.lua --todos
```

The generated C is a library fragment, not a program with `main`. Export names are prefixed with
`word_`; non-alphanumeric bytes are escaped. For the example, call `word_affine(a, b, x)` or
`word_transform(x)`. The test runner compiles and executes temporary C programs outside the repository.
Set `CC` to select the test compiler.

## Implemented slices

- Ordered definitions, positional signatures, complete calls, immutable prefix specialization with `:of`.
- Keyed `:of{...}` supply for scalar, Type and aggregate fields, with static reads and runtime slot erasure.
- Grounded entry/helper recursion with typed calls; exact self-tail returns lower to loops.
- Boxed U32 constants, exact modular arithmetic/bitwise operations and checked integer division.
- Known and symbolic scalar comparisons.
- Bool and Unit values; symbolic Bool arguments/results and erased Unit parameters.
- Shared concrete/residual operations; bounded replay produces typed branch trees and C conditionals.
- By-value scalar/record composition by tracing/inlining, plus a bounded ordinary recursive-helper ABI.
- Concrete executable inputs checked against positional calling requirements; static callable erasure.
- Static `Type` inputs and demand-driven normalization of closed words, including word-valued results.
- Immutable keyed schemas, structural interning, deferred field types, and static member selection.
- Runtime records, nested field places, scalar snapshots, by-value calls/assignment, and C type exports.
- One specialization record with an optional lazy static result; separate structural type interning.
- Read-only LuaJIT function environments, coroutine-local frames, error restoration, and structural limits.
- Typed IR verification, deterministic C emission, explicit U32-width semantics.

### Multiple results

Terminals can return multiple values. Calls follow Lua's normal adjustment rules: `local a, b = f(x)`
receives both, `(f(x))` selects the first, and a final call in an argument/return list expands.
Zero results or one nil result retain the existing boxed Unit behavior. Multiple results retain
positional Unit slots. `session:normalize` also returns multiple boxed values for a static result pack.
Record results copy independently, even when the same record is returned twice.

C exports return a by-value struct named `wordresult_<escaped export name>`; use
`Word.c_result_type_name(name)` to obtain that name. Fields are `f_r1`, `f_r2`, etc.; Unit fields
are erased without renumbering later fields. All-Unit packs use the existing empty-record padding.
Arity and component types must agree across branches and recursive calls. Static word results can
be consumed locally; escaping executable C results still need the separate runtime closure ABI.
See `new/examples/results.lua`.

### U32 arithmetic

`+`, `-`, `*`, unary negation and `^` wrap modulo 2^32. `/` and `:idiv` produce
the unsigned integer quotient; `%` produces the remainder. A known zero divisor rejects with
`division-zero`; a dynamic zero divisor calls C `abort()` before any undefined operation.
`^` uses exact modular exponentiation; an exponent of zero gives one, including `0 ^ 0`.
`:band`, `:bor`, `:bxor`, `:bnot`, `:shl` and `:shr` operate on 32 bits.
Shifts are logical; U32 amounts at least 32 give zero. Negative raw amounts reject.
The installed LuaJIT accepts bitwise syntax on Lua numbers, but does not dispatch it on these
proxies. Use the methods for typed operations. `//` is not accepted by the installed parser.
Multiplication uses 16-bit limbs so floating-point multiplication cannot lose the low U32 bits.

These are **typed U32** rules, not Lua-number rules. Raw Lua arithmetic still uses Lua semantics.
Unconstrained numeric terminal results default to U32: finite integral values in 0..4294967295.
This conversion does not wrap. Thus `return 0xffffffff + 1` rejects, while
`return U32(0xffffffff) + 1` yields zero. Bool and Unit result rules are unchanged.
See `new/examples/numeric.lua` for all operators.

The main embedding API is:

```lua
-- Add new/?.lua and new/?/init.lua to package.path first.
local Word = require("word")
local session = Word.new()
local module = session:load("new/examples/affine.lua")

local result = module.transform(4)
assert(session:value(result) == 19)

local ir = session:compile{ functions = { transform = module.transform } }
local c = session:emit_c{ functions = { transform = module.transform } }
```

`session:load_string(source, name)` is available for embedding and tests.
Primitive constructors (`U32(n)`, `Bool(b)`, `Unit()`) provide explicit typed values.
Unconstrained numeric return literals default to strictly representable U32 values.
Empty/nil returns mean Unit. Calls preserve arity, including explicitly supplied nil arguments.

## Primitive specialization

```lua
local Seven = U32:of(7)
local No = Bool:of(false)
local Number = Type:of(U32)
-- Seven() returns U32(7); No() returns Bool(false).
-- Number() returns the U32 word; Number(9) forwards to U32(9).
```

Primitive constructors use the same checked positional specialization as executable words.
`U32`, `Bool`, and `Type` each take one input; a supplied constructor has no remaining inputs.
Supply checks/coerces that input but does not execute the receiving terminal. Equal bindings intern
to the same word. Scalar demand or an empty call obtains its value; nonempty supply/calls forward
only if its demanded result is another word. Thus `Number:of(7)` is the same specialization as `Seven`.

`w:of()` is an identity, including for primitive words. Unit has no inputs, so `Unit:of()` is Unit
itself, and `Unit:of()()` constructs its value; `Unit:of(nil)` is an arity error, not empty supply.
A supplied scalar constructor such as Seven is not a type. Type-specialized aliases remain usable
in requirements, schemas, and type exports through normal type demand.

Closed scalar constructors can be exported directly as constant C functions or supplied as zero-input
callbacks. Unspecialized primitive type roots still belong in type exports, not function exports.
Runtime symbols cannot enter static bindings. Try `new/examples/primitives.lua`.

## Type factories and demand

In a loaded DSL module:

```lua
local Identity = word(Type, function(T)
    return word(T, function(x) return x end)
end)
local Pair = word(Type, Type, function(A, B)
    return word{ first = A, second = B }
end)

local id = Identity:of(U32)
local P = Pair:of(U32, Bool)
local answer = id(42)
local first_type = P.first -- U32
```

`word(...)` and `:of` do not execute the receiving terminal merely because it becomes closed.
Demand occurs through scalar operations, member selection, type checking, factory application, or C export.
Supplying an alias to a `Type` position is itself a type demand; it may normalize that argument.
`session:normalize(w)` explicitly demands a static result. `session:type(w)` requires a concrete type word,
not the type *of* a runtime value. `session:value(w)` can demand and unwrap a closed scalar computation.

Normalization follows closed staging-pure factory results until it obtains a scalar, a concrete type,
or a word with remaining inputs. Each specialization record retains only a successful static call result;
normalization follows returned words separately. A completed word-valued call is not a scalar placeholder.
Active builds live in scoped frames, not persistent `building` entries. Interrupted/failed evaluations
leave no cached failure and can be retried. IR is rebuilt per compilation; there is no persistent IR or type-view cache.
Static calls made during normalization use argument-sensitive keys, so bounded known recursion can fold.
Ordinary invocation does not memoize runtime results.

A nonempty call or `:of` on a closed factory forwards into its normalized word result.
An ordinary empty `id()` instead invokes that factory once and returns the resulting word, without invoking
the returned word again. It is distinct from `session:normalize(id)`.

Schema tables are copied at definition and seal their fields on type demand. Equal finite field
names/types/static bindings intern to the same type handle regardless of declaration/supply order.
Recursive reference types and record equality are not implemented.

Type parameters disappear from exported functions. Unsupplied Type inputs and runtime Type results reject.
Try `luajit new/wordc.lua new/examples/generics.lua` for scalar C entries derived from `Identity` and `Pair`.

These slices retire `static-types`, `closed-normalization`, `type-exports`, `branch-replay`, and
`primitive-specialization`. Remaining callable/capture work is tracked in
[STATUS.md](STATUS.md); the callable ABI and storage contract are described in
[closure-abi.md](closure-abi.md). The TODO catalogue is not a complete implementation inventory.

## Keyed data and C layouts

Canonical spelling has no space before a table-call brace: `word{...}`, `w:of{...}`, `w{...}`.
Ordered forms use parentheses. This is formatting, not a new parser: Lua still treats `w{...}`
as `w({...})`, and the word's shape determines how that table is used.

```lua
local Point = word{ x = U32, y = U32 }
local shift = word(Point, U32, function(p, amount)
    p.x = p.x + amount
    return p
end)
local p = Point{ x = 3, y = 4 }
local q = shift(p, 10) -- q.x is 13; p.x remains 3.
```

- A Lua alias (`local alias = p`) denotes the same place.
- Scalar field reads are immediate value snapshots.
- Nested record selection denotes a field place. It observes later replacement of that field.
- Record construction, assignment, argument binding, and returns copy aggregate values.
- `session:value(p)` produces a detached plain Lua snapshot; it does not expose compiler storage.
- Unit slots contain only nil and may be omitted. They disappear from C layouts; an empty record
  gets one padding byte because C11 has no standard empty struct.

Runtime storage is not static metadata. Explicit normalization rejects storage operations; C export
instead residualizes the runtime producer reached through the static factory chain. No mutable instance
is retained as a specialization result. Runtime places cannot be supplied through `:of`.

Try `luajit new/wordc.lua new/examples/records.lua`. Modules may return either a function table or an export
specification `{ types = {...}, functions = {...} }`. C type aliases use `wordtype_`, record members use
`f_`, and non-alphanumeric bytes are escaped as for function names. C controls struct padding/alignment.
Layout emission currently limits each aggregate to 65,536 scalar/empty slots (a resource limit).

## Keyed specialization

```lua
local XAxis = Point:of{ y = 0 }
local p = XAxis{ x = 3 }
-- p.y and XAxis.y are static U32(0); only x is a runtime input/field.
```

Scalar, Type, and aggregate fields can be bound. Static fields are read-only and must not be
resupplied at runtime. Supply order does not matter; compatible specializations compose. Repeating the
same static binding is harmless, while a different value rejects with `static-conflict`. The original
word remains unchanged. Specialization may demand field types and closed static value computations.

Use `Unit()` to supply a Unit field: a nil-valued table key is absent in Lua. Boxed false is retained
correctly. A static Type field remains available as a word but has no C slot; Lua snapshots retain that
immutable word handle. Static values participate in schema identity even when C layouts look identical.

Try `luajit new/wordc.lua new/examples/specialized.lua`. It exercises static branch selection, Type fields,
nested copies, and specialization inside residual execution. Mutable places and runtime symbols cannot
be static supplies; immutable aggregate snapshots are supported as described below.

## Static aggregate fields

```lua
local Point = word{x = U32, y = U32}
local Config = word{origin = Point, bias = U32}
local Fixed = Config:of{origin = {x = 3, y = 4}}
-- Fixed.origin.x is known U32(3); Config's origin slot disappears.
local cfg = Fixed{bias = 1}
```

A named static record supply recursively checks and copies a plain table against its field schema.
This creates an immutable typed snapshot, not a runtime record place. Nested records, Bool false, Unit,
Type values and empty records are supported. Existing snapshots and pure closed words returning them
can also be supplied. Semantic schema and value contents determine identity; equal repeated bindings
compose, conflicting bindings reject. Fields already bound in the nested schema cannot be resupplied.

Snapshot aliases stay read-only at every depth. `session:value` returns detached tables, including for
nested static fields; it never exposes the stored payload. Read-only method calls may use a snapshot
receiver during execution/tracing and normalization. Writes still reject.

Construction, assignment, ordinary record parameters and runtime returns copy snapshots into fresh
mutable places. An existing snapshot can also be bound as a positional static argument; each invocation
still makes its own by-value parameter copy. Such storage operations remain forbidden during explicit
normalization, and C export residualizes the producer instead. Pure snapshot reads/returns can normalize
and cache immutable aggregate results. Representable constants materialize through typed Construct IR.

Type-valued slots can exist inside a wholly static aggregate without a C representation. Attempting
to copy or emit that aggregate as runtime data rejects unless its schema itself erases those slots.
No runtime place or symbol is accepted as a static supply, including nested leaves. This does not add
general freezing of arbitrary captured host tables. Payload depth is limited to 32 and expanded payload
size to 65,536 nodes, counting shared subrecords each time to bound key/materialization expansion.
Try `new/examples/aggregate_constants.lua`.

## Immediate-receiver methods

```lua
local Counter = word{
    count = U32,
    increment = word(U32, function(amount)
        count = count + amount
        return count
    end),
}
local c = Counter{count = 3}
local inc = c.increment
inc(2) -- c.count is 5; the extracted method retains c.
```

Open executable children are methods, not data fields or constructor inputs. Their word identities
participate in schema identity. Methods see the immediate receiver's fields and sibling methods;
Lua parameters/locals/upvalues still take precedence. Ordinary words and raw helpers do not inherit
the caller's receiver. Static fields remain readable and reject writes. Method selection itself does
not run the method.

Extracted methods can be called, locally specialized (`inc:of(2)()`), and supplied to callable inputs
during ordinary execution or tracing. Their receivers are not copied at method calls; ordinary record
arguments/results still copy. Nested receivers retain field places and observe field replacement.
Methods start inline through Load/Store IR. Recursive methods can use typed, nonescaping receiver
storage parameters in private C functions; this is not a general C closure representation.
`session:value(record)` snapshots data fields only, not executable children.

Closed executable children now support `word(function() return count end)` getters and
`word(function() count = 0 end)` resetters without a dummy Unit input. Classification demands the
closed child's meaning: a type result supplies a data requirement; a receiver/storage dependency
or a non-type result makes it an executable child. Known value constructors such as `U32:of(7)`
are closed executable children, not implicit initialized data fields. Genuine Lua/capture errors
propagate rather than becoming methods. This normalization can execute ordinary Lua code.

Successful normalization retains the immediate terminal's environment-read names. Classification
reuses its result only when the prospective owner does not shadow those names; it retains no
runtime receiver or trace in that metadata. Ordinary helper functions still do not inherit the receiver.

Selecting `Counter.step` gives an unbound method. It needs an instance for a Lua call, but can be
exported directly: the C function takes a typed receiver pointer before its ordinary parameters.
The caller supplies valid live storage; calls mutate it without copying. Aliases share code.
A method on an immutable snapshot can instead export with its receiver erased. A method bound to
mutable Lua storage cannot export; choose the unbound method or an ordinary by-value wrapper.
Extracted mutable methods are borrowed views for local calls and non-retaining callback parameters.
They cannot be returned or stored in record fields: return the stateful record instead.
Immutable receiver metadata can still be captured.
Signature-valued data members work with declared result types. A word constructed lexically inside a
method binds that defining receiver when its free names require the receiver's fields or siblings.
Prototype nesting establishes this relationship; calling a module-level word does not give it the
caller's receiver. Local self-recursive words keep the same typed receiver ABI.

Such mutable receiver views remain borrowed. To return an immutable snapshot closure, first read the
field into a Lua local and capture that scalar value instead. See `new/examples/lexical_locals.lua`.
Lexical member occurrences across nested keyed record definitions remain incomplete.
See `new/examples/method_exports.lua` and `new/examples/closed_methods.lua`.

## Executable inputs

```lua
local BinOp = word(U32, U32)
local add = word(U32, U32, function(a, b) return a + b end)
local apply2 = word(BinOp, U32, U32, function(f, a, b) return f(a, b) end)
local addition = apply2:of(add) -- exported C takes just two U32 inputs.
```

Calling requirements compare the remaining positional inputs. Data requirements match exactly; nested
calling requirements match structurally. Open executable words may also provide their input shape as
a requirement, without executing their body. Results are inferred when an actual implementation runs,
not guessed from the input types. An unimplemented signature or raw Lua function is not an implementation.

Binding validates captures and input compatibility without executing the supplied implementation.
A closed factory may be demanded to satisfy a nonempty calling requirement, as with ordinary factory
application. Zero-argument implementations are not invoked merely by binding. Primitive constructors
can satisfy their own calling shapes (`U32` takes U32; `Unit` takes no inputs).

Concrete executable arguments remain known and their calls inline through the evaluator. Runtime
callable inputs and fields use a signature-specific borrowed calling ABI; declare `results[signature]`
when the signature alone does not determine a result. See `new/examples/runtime_callables.lua` and
`new/examples/callable_members.lua`.

Concrete executable results retain code identity in their type; capture-free results need no environment.
Stateful factories return ordinary records by value. There are no closure output-storage bundles, implicit
allocations or allocator parameters. Borrowed methods cannot escape: return their receiver instead.
See `new/examples/stateful_objects.lua` and [the callable contract](closure-abi.md).
Immutable scalar and executable captures now travel in by-value environments, including nested factories
and recursive code groups. See `new/examples/immutable_closures.lua`. Captured bindings are immutable;
record methods put runtime state in receiver fields rather than hidden captures.

## Symbolic branch replay

```lua
local piecewise = word(U32, function(x)
    if x:lt(10) then return x * 2 else return x + 5 end
end)
```

U32 ordering and scalar `:eq` comparisons return real Lua booleans. Known operands compute normally;
symbolic operands use a decision tape. Each unexplored decision forks compilation into fresh traces.
Ordinary `if`, short-circuit `and`/`or`, and `not` work on those comparison results. Comparisons returned
or stored as values become Bool results at branch leaves.

The driver validates typed instruction, storage, word-call, and decision prefixes before sharing them.
Fresh builders number equivalent prefixes deterministically; assembly renames suffix values into
globally unique IR IDs. A prefix store appears once before its branch, and arm effects remain guarded.
The verifier checks dominance, storage paths, Bool conditions, tree edges, and consistent return types.
No joins/phi nodes or suffix sharing are needed: each arm carries its own continuation to return.

`max_paths` limits potential leaf paths per replay/result-discovery pass (default 128); decision depth is capped at 32.
`max_values` bounds both individual traces and the assembled function, including stores, calls and branches.
Symbolic Lua loops that keep emitting decisions or IR eventually reach those limits; they are not
lowered to loops. Ordinary Lua execution has no instruction quota. Branches are explored without a feasibility
solver, so even contradictory symbolic paths must type-check.

Receiver storage is recreated per trace, never simulated by mutating a host instance. Capture checks
also run when a fork unwinds a terminal. Arbitrary host effects, mutation, helpers, and user exception
handlers remain outside the supported staging subset. Prefix validation is not a general purity proof
or rollback mechanism. Runtime executable-definition construction still traps `staged-definitions`.
Try `new/examples/branches.lua` for scalar, Bool, Unit, record, and receiver-effect branches.

## Executable TODOs as a progress ledger

Unsupported mechanisms call:

```lua
local todo = require("word.diagnostic").todo
todo("host-captures", "Foreign Lua effects need explicit registration")
```

Every feature ID is registered once in `word/diagnostic.lua` with its next implementation step.
The trap raises a structured diagnostic containing `kind = "todo"`, `id`, context, location, and `next`.
It never returns a fake value or emits a stub. `Word.todos()` and `wordc.lua --todos` list the catalogue.

Each live ID must have an executable `H.gap` witness in `test/model.lua`. Tests report:

```text
PASS ...
TODO host-captures
... passed; ... TODO diagnostics exercised; ... open implementation areas; ... failed
```

A wrong diagnostic is a failure. A TODO witness that starts succeeding is also a failure: promote it
to positive semantic tests and retire or narrow the corresponding trap. Partially implemented roadmap
categories can remain open without an active trap; they are reported separately, not counted as failures.
There is no percentage-complete claim.
It is not full coverage of `word.md`; [STATUS.md](STATUS.md) tracks additional specified facilities.

Diagnostics distinguish `reject`, `todo`, `resource`, `lua`, and `bug`. CLI exit codes are respectively
1, 3, 4, 1, and 2; success is 0. Arbitrary Lua execution errors are not mislabeled as compiler bugs.

## Grounded recursion

```lua
local sum_to
sum_to = word(U32, U32, function(n, total)
    if n:eq(0) then return total end
    return sum_to(n - 1, total + n)
end)
```

Compilation reserves the current entry identity. A completed, recursion-free return path grounds
its result type. If replay reaches an unknown recursive result first, that path suspends without a
placeholder value. A bounded search finds a base return, then compilation replays the full tree with
typed calls. All paths and uses must agree; branch order does not choose a guessed type. This is a
bounded inference subset, not a general recursive type-constraint solver or termination proof.

Calls to the entry's definition can use its ABI only when the bound static prefix matches.
For example, recursive calls may pass an erased Type or callable input explicitly, or repeat `:of`.
The verifier checks the self target, result, operand types, arity and dominance. Unit arguments/results
have no payload, but void calls remain ordered operations. Records cross ordinary by-value boundaries.
Other words start inline; a cycle through them can close back to the entry. Ordinary recursive helpers
can now be outlined as described below, including recursive receiver methods and grounded mutual groups.
Results that cannot be grounded need an explicit compile-time result declaration:
```lua
session:compile{functions = {f = f}, results = {[f] = U32}}
session:compile{functions = {pair = pair}, results = {[pair] = {U32, Bool, Unit}}}
```
`results` maps exact word instances, including helper words and receiver selections, to a runtime
type or a dense ordered list of runtime types. Empty/singleton lists mean Unit/the single type.
Declarations seed checked signatures, not fabricated values. All return paths and inlined/static
calls must agree. Explicit `:of` instances have their own identities. Declaring a closed export checks
that invocation instead of following a returned factory word. Constraints on a factory's runtime
producer also apply when ordinary export demand reaches that producer.

Without either a grounding return or a declaration, compilation rejects with `recursive-result`
and identifies the required declaration. No result type is guessed from input types. Declarations
do not prove termination; `new/examples/result_constraints.lua` intentionally contains nonterminating
entries that can compile but must not be called in a terminating test.

The C backend turns a final self call followed immediately by return of its result into a loop.
It snapshots every next argument before replacing any parameter. Current runtime types contain no
address-retaining references, so this rewrite does not preserve dead invocation locals. Intervening
work or stores prevent the rewrite. Transparent record/tuple forwarding is checked as described below.
Export aliases each self-call their own emitted entry. Cross-function calls are never rewritten as self loops.

Concrete calls permit recursion within the existing 32-invocation depth limit. Fully known
static demands still normalize with argument-sensitive keys. Compiled C does not install that host
depth guard: non-tail recursion can exhaust the C stack, and a tail loop can run forever. Recursion-free
grounding means a path completes without calling the current entry, not that runtime termination is proven.
See `new/examples/recursion.lua` for scalar, Bool, record, Unit and static-prefix examples.

### Recursive helpers behind wrappers

An ordinary helper's first activation stays inline. On repeated activation with residual arguments
or a symbolic decision inside that activation, compilation suspends the caller, reserves the helper,
grounds and verifies its body, then retries the caller with a typed call closing that cycle. No result
placeholder is fed to source code. Keeping the first activation inline preserves call-site facts:
a known base call can still feed `:of`, even when another branch/export outlines that same helper.
Known recursive calls without residual decisions can unfold within the ordinary invocation budget.

Private functions use `wordfn_` names. Calls carry numeric program targets and are checked against the
callee's signature, not the caller's. C emits forward declarations, retains ordered void calls, copies
record arguments/results by value, and emits only reachable private bodies. Ordinary open exports
and helpers can share an identity; export aliases keep their public names. The closed export-demand
registry is separate from one-invocation helper entries because export demand may follow a factory
to a different producer. These registries are compilation-local and discarded on failure/interruption.

Bind helper Type/callable prefixes with `:of` before outlining; no implicit metadata ABI is invented.
Finite inlining can still close mutual cycles, and a changed scalar prefix can use a separate ordinary
helper with runtime arguments. Mutually pending helpers can use signatures grounded by completed
return paths while their bodies are still being checked. Discovery propagates only established type
facts; it never seeds a cycle with guessed values or result types. All bodies must seal and verify
before the program is returned. Conflicting later returns reject the whole compilation.
See `new/examples/recursive_groups.lua`. Unbounded changing-specialization graphs reach the
existing structural instance/depth limits rather than producing incomplete functions.
A helper must have one representable result type. No runtime function-pointer/closure ABI is added.

Recursive methods share code by owner schema and static method inputs, not by receiver identity.
Their private functions receive a typed storage pointer; calls pass the selected place, including
nested fields. Sibling/mutual recursion preserves writes to that same storage. Ordinary record
parameters and results still copy. Immutable snapshot receivers instead specialize by snapshot
contents, remain read-only, and need no runtime receiver pointer.

Receiver pointers are not DSL values: they cannot be stored, returned, or captured in escaping
closures. A self-tail loop can keep the exact incoming receiver, but cannot switch it to caller-local
storage. Record/tuple return copies can be eliminated only when copies, projections and reconstruction
provably return the callee's value unchanged. Stores, further calls, changed components and arithmetic
after the call prevent this rewrite. See `new/examples/recursive_methods.lua`.

`max_functions` bounds residual instances per program (default 128), including exports and helpers.
Nested helper demands are capped at 32. Trace/path limits apply per attempt/function.
There is no Lua execution budget or persistent partial function cache.
Try `new/examples/recursive_helpers.lua`.

## Deliberate limits

Escaping receiver/closure support, recursive reference types,
and runtime closures are not implemented. See `--todos` for executable gaps.

Use `x:eq(y)` for equality. Ordering operators work with two typed operands, e.g. `x < U32(10)`.
LuaJIT does not dispatch mixed proxy/number comparisons: use `x:lt(10)`, `:le`, `:gt` or `:ge`.
These adapters use exactly the same known/replay path as typed `<` and `<=`.
Lua cannot intercept `symbol == 3` or `if symbol then`:
these can silently use Lua identity/truthiness. Boxed known Bool values are also Lua-truthy,
even when they contain false. Direct Boolean tests on these proxies are outside the supported subset.
Use `flag:eq(true)` for Bool conditions; symbolic comparisons participate in replay.

Loaded module code uses locals and returns an export table. Its environment provides only `word`,
`U32`, `Bool`, `Unit`, and `Type`. Host I/O, arbitrary helper libraries, yields, and mutable host captures
are outside the staging contract. This is not a security sandbox; raw Lua can bypass conventions.
Frozen primitive/word captures are checked again before cache reuse and after terminal execution.
Detected host mutations are rejected, not rolled back. Recursive dependencies are checked before cache hits.

The compiler does not impose a Lua instruction quota or install/replace the thread's debug hook.
Ordinary Lua loops can run indefinitely; an external debugger or process interruption remains available.
`max_normalizations` bounds uncached static work per demand (default 1000). Nested static demand is also
limited to 32 levels to stop before Lua's C-stack limit. Word invocation nesting has a separate 32-level
guard, including distinct callable specializations. These are resource limits, not type errors.

`architecture.md` describes the wider proposed architecture. This prototype intentionally omits empty
modules and unimplemented frameworks. The replay driver is now implemented; general CFG joins are not.
