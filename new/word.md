
# Lua Word DSL

## 1. Thesis

The language is a staged DSL embedded directly in Lua.
**LuaJIT is the baseline host**, using its Lua 5.1 function environments; stock Lua 5.4 is not the baseline.

Its central abstraction is the **word**.

A word describes shape and behaviour. Definition does not provide the values filling that shape.

There are exactly two recursive structural forms:

```lua
word(...)      -- ordered
word{ ... }    -- keyed
```

with one permanent law:

```text
()  = order / position
{}  = keys / names
```

Values enter words through:

```lua
w:of(...)        -- static positional supply + specialization
w:of{ ... }      -- static keyed supply + specialization

w(...)           -- runtime positional supply + execution
w{ ... }         -- runtime keyed supply / construction
```

Canonical formatting puts no space between a callee and its table-call brace:
`word{...}`, `w:of{...}`, and `w{...}`. Spaces inside the structure follow normal Lua readability.
Ordered forms remain `word(...)`, `w:of(...)`, and `w(...)`.
This is a visual convention, not new syntax: Lua treats `w{...}` exactly as `w({...})`.
The word's shape, not the punctuation alone, determines how the supplied table is used.

Types are words.

`Type` is itself a word.

The language therefore gets generics, recursive types, stateful objects, references, higher-order computation, sum types, and control flow largely through composition rather than dedicated syntax.

The runtime closure is **C-representability**:

> Anything surviving specialization must have a defined C representation and C runtime semantics.

Static-only words may be richer, provided they disappear before emission.

---

# 2. Design discipline

The language follows one rule:

> Use ordinary Lua whenever Lua already expresses the required behaviour correctly.

Therefore the core does not introduce separate constructs for:

```text
fn
let
var
tail
class
method
self
generic
template
move
currying
while
for
recursive-type
```

unless a concrete semantic requirement cannot be expressed correctly through Lua plus words.

Ordinary Lua remains available:

```lua
function(...) ... end
local x = ...
return ...
a + b
a.b
a.b = value
if ...
and
or
not
```

Compiler concepts such as:

```text
SSA values
symbolic values
basic blocks
backedges
tail edges
phi/block parameters
places
ownership analysis
```

remain implementation details unless source-level semantics eventually require them.

---

# 3. Ordered words

An ordered word has the form:

```lua
word(
    S1,
    S2,
    ...,
    Sn,
    terminal
)
```

`S1 ... Sn` are ordered requirements.

The last element is the **terminal**.

Only ordered words have terminals.

Example:

```lua
local add = word(
    U32,
    U32,

    function(a, b)
        return a + b
    end
)
```

This describes:

```text
position 1 : U32
position 2 : U32
terminal   : addition
```

Runtime execution:

```lua
local result = add(10, 20)
```

supplies every remaining positional requirement and invokes the terminal.

There is no automatic currying.

```lua
add(10)
```

is incomplete and therefore invalid.

Static partial supply is explicit:

```lua
local add10 = add:of(10)
local result = add10(20)
```

---

# 4. Terminal-less ordered words are positional signatures

An ordered word may have no terminal:

```lua
local BinOp = word(U32, U32)
```

This is a positional signature.

It describes:

```text
(U32, U32)
```

without supplying an implementation.

An executable word:

```lua
local add = word(
    U32,
    U32,

    function(a, b)
        return a + b
    end
)
```

satisfies that input signature.

This gives higher-order structure naturally:

```lua
local apply2 = word(
    BinOp,
    U32,
    U32,

    function(f, a, b)
        return f(a, b)
    end
)
```

A positional signature does not necessarily specify a result type. Result typing may be inferred by symbolic interpretation or constrained by context.

---

# 5. Keyed words

A keyed word has the form:

```lua
word{
    key1 = S1,
    key2 = S2,
    ...
}
```

A keyed word has no terminal.

Its named structure is its meaning.

Example:

```lua
local Point = word{
    x = F32,
    y = F32,
}
```

This describes:

```text
{
    x : F32,
    y : F32
}
```

Its fields have no semantic execution order.

Runtime construction:

```lua
local p = Point{
    x = 3,
    y = 4,
}
```

Static specialization:

```lua
local XAxisPoint = Point:of{
    y = 0,
}
```

removes `y` from the remaining input shape while retaining:

```text
y = 0
```

as static read-only knowledge.

Thus:

```lua
local p = XAxisPoint{
    x = 5,
}

local y = p.y   -- 0
```

while:

```lua
p.y = 3
```

is invalid if specialization erased `y` from runtime state.

---

# 6. The two-form algebra

The language has two structural constructors:

```text
ORDERED(S1, ..., Sn, terminal?)

KEYED {
    k1 : S1,
    ...
    kn : Sn
}
```

They compose recursively.

## Keyed inside keyed

```lua
local Rect = word{
    min = word{
        x = F32,
        y = F32,
    },

    max = word{
        x = F32,
        y = F32,
    },
}
```

## Ordered inside keyed

```lua
local Math = word{
    add = word(
        U32,
        U32,
        function(a, b)
            return a + b
        end
    ),

    mul = word(
        U32,
        U32,
        function(a, b)
            return a * b
        end
    ),
}
```

Usage:

```lua
Math.add(10, 20)
Math.mul(3, 7)
```

## Keyed inside ordered

```lua
local magnitude2 = word(
    Point,

    function(p)
        return p.x * p.x + p.y * p.y
    end
)
```

## Ordered inside ordered

An ordered word can itself be supplied to another ordered word.

Higher-order programming therefore requires no separate function-object syntax.

---

# 7. Structure never implies execution

Nesting a word does not execute it.

A keyed word may contain an executable child:

```lua
local Ops = word{
    normalize = normalize,
}
```

Selection:

```lua
local op = Ops.normalize
```

returns the word.

Application executes:

```lua
op(value)
```

Likewise, supplying a keyed value to an ordered word passes structured data rather than flattening it.

The permanent distinction is:

```text
structure != execution
selection != execution
```

---

# 8. Definition does not supply runtime values

Definitions describe requirements.

For:

```lua
local Point = word{
    x = F32,
    y = F32,
}
```

there is no runtime point yet.

For:

```lua
local add = word(
    U32,
    U32,
    terminal
)
```

there are no runtime integers yet.

Definition establishes:

```text
shape
types
keys or positions
nesting
lexical ownership relationships
terminal behaviour for ordered words
```

Actual values arrive through specialization or runtime application.

---

# 9. Runtime application

Runtime application satisfies the complete remaining shape.

Ordered:

```lua
add(10, 20)
```

Keyed:

```lua
Point{
    x = 10,
    y = 20,
}
```

Calls are complete by default.

A closed ordered word executes using:

```lua
w()
```

A keyed word with no remaining runtime requirements may still be instantiated using:

```lua
W{}
```

when creating a runtime instance remains meaningful.

---

# 10. Specialization

`:of` supplies values statically.

Ordered:

```lua
local add10 = add:of(10)
```

Keyed:

```lua
local Configured = Config:of{
    width = 32,
}
```

Specialization:

* returns another word;
* never mutates the original;
* removes supplied requirements from the remaining input shape;
* retains their values as static knowledge;
* partially evaluates every staging-safe consequence.

Compatible specializations compose.

---

# 11. Specialization is partial evaluation

Given:

```lua
local affine = word(
    U32,
    U32,
    U32,

    function(scale, offset, x)
        return scale * x + offset
    end
)
```

then:

```lua
local transform = affine:of(3, 7)
```

may normalize to a residual word equivalent to:

```text
x : U32

return 3 * x + 7
```

The original three-input implementation need not survive.

Thus:

```text
specialization
=
static binding
+
partial evaluation
```

---

# 12. Closed words normalize on demand

A closed staging-pure ordered word does not have to remain wrapped as an executable word.

For:

```lua
local thirty = add:of(10, 20)
```

normalization may produce directly:

```text
Known(30, U32)
```

However, normalization is **demand-driven**, not eager at definition construction time.

This is essential for forward references and recursive definitions.

A closed word normalizes when its result is semantically demanded, for example by:

```text
member selection
use as a Type
layout computation
specialization requiring its result
runtime construction through its result
C emission
type comparison
```

Definition construction itself does not force normalization.

This rule allows recursive definitions to use ordinary Lua forward declarations safely.

---

# 13. Forward references use ordinary Lua upvalues

This is valid:

```lua
local sum_to

sum_to = word(
    U32,
    U32,

    function(i, acc)
        if i:eq(0) then
            return acc
        end

        return sum_to(i - 1, acc + i)
    end
)
```

The function captures the Lua local `sum_to`.

The value is read only when the terminal runs, after the assignment has completed.

By contrast, this is eager and therefore invalid:

```lua
local List

List = word{
    head = U32,
    tail = Ref:of(List),
}
```

because Lua evaluates `Ref:of(List)` before assigning the completed word to `List`.

The general rule is:

> A forward self-reference is legal when the read is deferred into terminal execution.

No `rec` syntax or recursive-definition primitive is required.

---

# 14. Recursive types are closed ordered computations returning Type

A non-generic recursive type can be written:

```lua
local List

List = word(
    function()
        return word{
            head = U32,
            tail = Ref:of(List),
        }
    end
)
```

`List` is a zero-input ordered word.

Its terminal computes a `Type`.

Because closed normalization is demand-driven, the terminal runs only after the assignment to `List` has completed.

When `List` is required as a type, it normalizes to its recursive keyed type.

---

# 15. Recursive normalization ties the knot

Normalization is memoized by specialization identity.

The cache has conceptually three states:

```text
UNSEEN

IN_PROGRESS(identity)

DONE(value)
```

For:

```text
normalize(definition, static_arguments)
```

the evaluator:

```text
1. computes the specialization key;

2. if DONE:
       returns the cached value;

3. if IN_PROGRESS:
       returns the already-created recursive identity;

4. otherwise:
       creates a stable placeholder identity;
       stores IN_PROGRESS(identity);
       evaluates the terminal;
       fills the identity with the resulting definition;
       stores DONE(identity);
       returns the identity.
```

Installing the identity before terminal evaluation is what permits recursion.

For `List`:

```text
normalize List
    ↓
allocate identity L
    ↓
mark List as IN_PROGRESS(L)
    ↓
terminal returns {
    head = U32,
    tail = Ref(L)
}
    ↓
fill L
    ↓
DONE(L)
```

All recursive references point to the same type identity.

---

# 16. Generic recursive types work identically

Example:

```lua
local List

List = word(
    Type,

    function(T)
        return word{
            head = T,
            tail = Ref:of(
                List:of(T)
            ),
        }
    end
)
```

Specialization:

```lua
local U32List = List:of(U32)
```

uses the memo key:

```text
(List definition, U32)
```

Before evaluating the terminal, a recursive identity is installed.

The recursive:

```lua
List:of(T)
```

encounters the same specialization key and obtains that identity.

Thus:

```text
U32List =
{
    head : U32,
    tail : Ref(U32List)
}
```

without introducing recursive type syntax.

---

# 17. Recursive layout must cross an indirection boundary

A recursive C-representable type is valid only if every representation cycle crosses a boundary whose layout does not require recursively computing the target layout.

`Ref(T)` is the canonical initial boundary.

For:

```text
List =
{
    head : U32,
    tail : Ref(List)
}
```

the size of `Ref(List)` is known from the reference representation without knowing `sizeof(List)`.

Therefore the structure has finite size.

By contrast:

```text
Bad =
{
    child : Bad
}
```

is infinitely sized under by-value embedding.

C emission must reject such a cycle.

Conceptually:

```text
recursive by-value layout:

    Bad.child
      -> Bad

an indirection boundary is required
```

Other future opaque/fixed-size reference-like types may also break layout recursion.

`Ref` is simply the standard mechanism.

---

# 18. Recursive C emission uses forward declarations

The recursive type identity maps naturally to C incomplete struct declarations.

For:

```text
List =
{
    head : U32,
    tail : Ref(List)
}
```

emit:

```c
typedef struct List List;

struct List {
    uint32_t head;
    List *tail;
};
```

For:

```lua
local U32List = List:of(U32)
```

a specialization may emit:

```c
typedef struct U32List U32List;

struct U32List {
    uint32_t head;
    U32List *tail;
};
```

The staging placeholder identity and C's forward-declared struct solve the same recursive naming problem at different layers.

---

# 19. Terminals

The terminal concept exists only for ordered words.

A terminal is:

> The final component of an ordered definition; once all preceding requirements are supplied, it determines the result.

Two broad roles are useful.

## Runnable terminal

```lua
word(
    U32,
    U32,

    function(a, b)
        return a + b
    end
)
```

## Data terminal

An ordered word may end in a terminal constructing custom data such as:

```text
arrays
references
packed vectors
opaque handles
foreign resources
special numeric representations
```

Keyed words need no terminal because their transparent aggregate structure is explicit.

---

# 20. Types are words

`Type` is itself a word.

Primitive runtime types include words such as:

```text
Bool

U8
U16
U32
U64

I8
I16
I32
I64

F32
F64
```

with:

```text
U32 : Type
F32 : Type
...
```

Keyed words also produce types:

```lua
local Point = word{
    x = F32,
    y = F32,
}
```

so:

```text
Point : Type
```

---

# 21. `Type` is primarily static

`Type` itself need not have a runtime C representation.

Initially:

```text
Type
type constructors
schemas
word definitions
compiler metadata
specialization metadata
```

are staging-only.

Every live residual runtime value must instead have a C-representable type.

If `Type` itself survives as runtime data, emission fails unless an explicit runtime representation has been defined.

---

# 22. Generic programming is ordinary specialization

A generic computation accepts `Type` as an ordinary static input.

Example:

```lua
local Identity = word(
    Type,

    function(T)
        return word(
            T,

            function(x)
                return x
            end
        )
    end
)
```

Then:

```lua
local IdentityU32 = Identity:of(U32)
```

specializes to an ordinary `U32` computation.

Therefore:

```text
generic parameter
    = static Type input

generic instantiation
    = :of

monomorphization
    = partial evaluation
```

No generic syntax is required.

---

# 23. Generic type constructors

A type constructor is an ordered word returning `Type`.

Example:

```lua
local Pair = word(
    Type,
    Type,

    function(A, B)
        return word{
            first = A,
            second = B,
        }
    end
)
```

Then:

```lua
local PairU32F32 = Pair:of(U32, F32)
```

normalizes to a concrete keyed type.

---

# 24. Types may depend on ordinary static values

Example:

```lua
local Array = word(
    Type,
    U32,
    array_type_terminal
)
```

Then:

```lua
local Buffer = Array:of(U8, 1024)
```

can statically determine:

```text
element type
length
size
alignment
layout
specialized operations
```

Likewise:

```lua
Matrix:of(F32, 4, 4)
```

may yield a fully concrete runtime type.

This provides value-dependent types without a separate type-expression language.

---

# 25. Runtime type closure is C-representability

Every residual runtime type must satisfy:

```text
lower_c_type(T) -> CType
```

Primitive mappings may include:

```text
Bool -> bool

U8   -> uint8_t
U16  -> uint16_t
U32  -> uint32_t
U64  -> uint64_t

I8   -> int8_t
I16  -> int16_t
I32  -> int32_t
I64  -> int64_t

F32  -> float
F64  -> double
```

Constructed runtime types may lower to:

```text
struct
array
pointer/reference
tagged union
opaque handle
```

Static-only types must disappear before emission.

---

# 26. Language semantics remain independent of accidental C semantics

For example:

```text
U32
    unsigned 32-bit integer
    modulo-2^32 arithmetic
```

is a language rule.

Lua staging and emitted C must both preserve it.

The same discipline applies to:

```text
signed arithmetic
floating-point behaviour
conversion rules
pointer behaviour
```

C is the runtime representation and execution substrate, not the source of unspecified language semantics.

---

# 27. Keyed nesting is by value

A keyed type nested inside another keyed type is embedded by value.

Example:

```lua
local Transform = word{
    position = Point,
    scale = F32,
}
```

naturally lowers to:

```c
typedef struct {
    Point position;
    float scale;
} Transform;
```

This makes value semantics the default.

Sharing and identity are explicit through reference-like types.

---

# 28. `Ref` is an ordinary type constructor

Conceptually:

```text
Ref : Type -> Type
```

Example:

```lua
local PointRef = Ref:of(Point)
```

lowers to a pointer-like C representation:

```c
Point *
```

`Ref(T)` means:

```text
reference to an instance of T
stable identity / aliasing semantics
member access through the target
```

It does not inherently mean:

```text
unique ownership
move semantics
exclusive borrowing
automatic destruction
```

Those guarantees are not part of the current core.

---

# 29. Member selection through Ref preserves receiver binding

Suppose `Node` exposes an ordered child:

```lua
local Node = word{
    value = U32,

    increment = word(
        U32,

        function(amount)
            value = value + amount
        end
    ),
}
```

If:

```text
node.next : Ref(Node)
```

then:

```lua
node.next.increment(5)
```

means:

```text
node.next
    -> referenced Node instance q

q.increment
    -> Node.increment bound to receiver q

q.increment(5)
    -> execute in q's lexical instance scope
```

Thus a reference behaves exactly like direct instance access with respect to member ownership.

Only its physical representation differs.

C may lower:

```lua
node.next.increment(5)
```

to:

```c
Node_increment(node.next, 5);
```

---

# 30. Keyed instances are state scopes

A keyed word may contain data and ordered executable children:

```lua
local Counter = word{
    count = U32,

    increment = word(
        U32,

        function(amount)
            count = count + amount
            return count
        end
    ),

    reset = word(
        function()
            count = 0
        end
    ),
}
```

Construct:

```lua
local c = Counter{
    count = 10,
}
```

Use:

```lua
c.increment(5)
c.reset()
```

No separate class or method construct exists.

---

# 31. Definition nesting establishes lexical receiver scope

For an ordered child nested in a keyed definition:

```lua
increment = word(
    U32,

    function(amount)
        count = count + amount
    end
)
```

the free name `count` refers lexically to the containing keyed scope.

The scope chain is established by definition nesting:

```text
increment
    -> Counter
    -> containing scopes/module
```

It is not determined by the dynamic caller stack.

This preserves ordinary lexical intuition.

---

# 32. Bound child selection

Selection:

```lua
Counter.increment
```

returns the child definition.

Selection:

```lua
c.increment
```

returns that child bound to instance `c`.

Conceptually:

```text
bound executable =
    child definition
    +
    receiver instance
    +
    lexical owner chain
```

Thus:

```lua
local inc = c.increment
inc(5)
```

still modifies `c`.

---

# 33. LuaJIT function environments implement lexical owner lookup

A stable LuaJIT function environment provides free-name lookup. `_ENV` is not a special Lua 5.1 upvalue.

Inside:

```lua
function(amount)
    local next = count + amount
    count = next
    return next
end
```

`amount` is an ordinary parameter.

`next` is an ordinary local.

`count` resolves through the current bound lexical owner chain.

A practical implementation may use:

```text
one stable proxy function environment

+
a per-coroutine stack of active bound lexical scopes
```

Lookup follows definition nesting, not dynamic callers.

Nested calls must restore previous scope correctly even across errors.

---

# 34. State semantics

Keyed runtime instances have identity.

Assignments modify instance data:

```lua
c.count = 20
```

Definitions remain immutable.

Two references to the same stateful instance observe the same mutation.

Nested keyed fields are by value unless their type is explicitly `Ref(T)`.

---

# 35. Specialization of keyed state

Given:

```lua
local Filter = word{
    gain = F32,
    value = F32,

    step = word(
        F32,

        function(input)
            value = value + gain * input
            return value
        end
    ),
}
```

then:

```lua
local Gain2 = Filter:of{
    gain = 2,
}
```

produces:

```text
remaining runtime field:
    value

static binding:
    gain = 2
```

Owned executable `step` can specialize accordingly.

The specialized field may disappear from the C layout while remaining available as compile-time knowledge.

---

# 36. Tail calls use ordinary Lua

A terminal may write:

```lua
return next_word(args)
```

or:

```lua
return next_word{
    x = x,
}
```

No `tail` construct exists.

A directly returned call may be recognized internally as a tail edge.

If work follows the call, it is not tail.

---

# 37. Tail recursion provides loops

Example:

```lua
local sum_to

sum_to = word(
    U32,
    U32,

    function(i, acc)
        if i:eq(0) then
            return acc
        end

        return sum_to(i - 1, acc + i)
    end
)
```

When staging symbolic inputs, recursive re-entry with the same specialization signature becomes a residual backedge instead of another unfolding.

Thus source recursion can lower to:

```c
uint32_t sum_to(uint32_t i, uint32_t acc)
{
loop:
    if (i == 0)
        return acc;

    acc += i;
    i -= 1;
    goto loop;
}
```

Known recursive states may still require fuel/generalization if they change indefinitely.

---

# 38. Specialization memoization

The specialization identity includes approximately:

```text
word definition
receiver/owner specialization
known static arguments
dynamic argument types/shapes
```

It deliberately excludes individual SSA/symbol identities.

This permits:

```text
f(Symbol U32)
```

and recursive:

```text
f(Symbol U32)
```

to share one specialization block even though the runtime SSA values differ.

The same cache supports:

```text
generic monomorphization
recursive functions
recursive types
closed normalization
```

---

# 39. Abstract value domain

The partial evaluator begins with roughly:

```text
Known(value, Type)

Symbol(id, Type)

Place(id, Type)
```

`Known` is available during staging.

`Symbol` is a runtime value.

`Place` denotes runtime storage.

A symbolic value does not suspend interpretation.

It causes residual operations to be emitted.

---

# 40. Symbolic arithmetic

For:

```lua
local transform = affine:of(3, 7)
```

C staging may use:

```text
scale  = Known(3, U32)
offset = Known(7, U32)
x      = Symbol(arg0, U32)
```

Then:

```lua
return scale * x + offset
```

becomes:

```text
r1 = MulU32(3, arg0)
r2 = AddU32(r1, 7)
Return r2
```

---

# 41. Symbolic state

For:

```lua
c.increment(x)
```

staging may see:

```text
count  = Place(c.count, U32)
amount = Symbol(x, U32)
```

and emit:

```text
r1 = Load c.count
r2 = AddU32 r1, x
Store c.count, r2
Return r2
```

---

# 42. Lua is the staging language

The compiler does not translate arbitrary Lua source into C.

It executes Lua terminals using abstract language values.

For:

```lua
function(a, b)
    return a + b
end
```

the value operators determine:

```text
Known + Known
    -> compute

Known/Symbol + Symbol
    -> emit Add

Place read/write
    -> emit Load/Store
```

Lua therefore acts as the partial-evaluation host.

C is the residual execution language.

---

# 43. Replay-safe staged terminals

Branch exploration may execute a terminal multiple times.

Therefore staged terminal execution must be replay-safe:

> Given the same abstract inputs and branch-oracle decisions, staging must reproduce the same abstract computation.

Runtime-observable effects must flow through staged operations.

Unsafe examples include uncontrolled:

```lua
io.write(...)
math.random()
mutation of arbitrary host upvalues
clock-dependent staging logic
```

unless intentionally defined as compile-time effects.

---

# 44. Ordinary symbolic `if` through branch replay

LuaJIT relational metamethods on two typed proxies record predicates and return an oracle-selected Lua boolean.
A mixed proxy/raw-number comparison does not dispatch. Use `x < U32(10)` or `x:lt(10)`.
The `:lt`, `:le`, `:gt` and `:ge` adapters preserve the same semantics without requiring a boxed literal.

Therefore this can remain ordinary Lua:

```lua
function(x)
    if x:lt(10) then
        return x * 2
    else
        return x + 5
    end
end
```

For symbolic `x`, staging explores both oracle choices.

Residual result:

```text
if x < 10:
    return x * 2
else:
    return x + 5
```

Known comparisons do not fork.

---

# 45. Boolean composition

Because symbolic comparisons return actual oracle-selected booleans during staging, ordinary Lua short-circuit operators work for expressions such as:

```lua
if x:lt(10) and y:gt(3) then
```

A direct symbolic Boolean:

```lua
if flag then
```

cannot work automatically because Lua tables are truthy.

Until another natural mechanism appears, use:

```lua
if flag:eq(true) then
```

---

# 46. Equality

Lua cannot reliably intercept:

```lua
symbol == 3
```

when operands have incompatible host categories.

Therefore language equality uses:

```lua
x:eq(3)
```

This is a justified escape hatch because Lua does not expose the necessary hook.

`:eq` participates in branch replay like `<` and `<=`.

---

# 47. Path exploration

A simple correct implementation may:

```text
execute terminal once per oracle path
record one straight-line residual trace per path
assemble the traces into a branch tree
```

Each path may carry its own continuation to return.

Therefore the first implementation does not require phi nodes.

This can duplicate suffixes exponentially.

That is acceptable initially.

---

# 48. Join recovery

Common residual suffixes may later be hash-consed.

When two branches converge on an identical tail:

```text
branch A --\
            -> shared suffix
branch B --/
```

the compiler may share one residual block.

If different values enter that shared block, block parameters or phi-like semantics may be introduced internally.

This is an optimization.

It requires no source syntax.

---

# 49. Sum types

The two native forms describe products:

```text
(A, B)
{x:A, y:B}
```

A sum is a separate `Type` constructor rather than new syntax.

Example:

```lua
local ShapeCases = word{
    circle = Circle,
    rect   = Rect,
}

local Shape = OneOf:of(ShapeCases)
```

Conceptually:

```text
Shape =
    circle Circle
  | rect Rect
```

C may lower it to an enum plus union.

---

# 50. Sum construction

A sum type may expose variant constructors:

```lua
local c = Shape.circle{
    radius = 10,
}

local r = Shape.rect{
    width = 10,
    height = 20,
}
```

No dedicated constructor syntax is required.

---

# 51. Sum matching

A sum value may support keyed application:

```lua
local area = shape{
    circle = circle_area,
    rect   = rect_area,
}
```

The keyed argument is a named case table.

If the tag is statically known, specialization selects one branch.

If symbolic, residualization produces branch/switch control flow.

Again, `{}` continues to mean named structure.

---

# 52. Finite recursive structures

A recursive pointer-like structure can use `Ref` plus a sum type.

For example, conceptually:

```lua
local List

List = word(
    function()
        return word{
            head = U32,

            tail = OneOf:of(
                word{
                    end_ = Unit,
                    next = Ref:of(List),
                }
            ),
        }
    end
)
```

This provides:

```text
empty termination
or
reference to another node
```

without introducing recursive-type syntax.

---

# 53. Residual IR

The stager produces typed residual structure rather than C strings.

A minimal IR may include:

```text
Parameter
Constant

Add
Sub
Mul
Div

Compare
Eq

ConstructAggregate
Project

ConstructVariant
ProjectVariant

Load
Store

Call

Block
Branch
Jump

Return
```

Every residual value carries a `Type`.

---

# 54. C type lowering

Every residual type must lower to C.

Examples:

```text
Bool -> bool

U8   -> uint8_t
U16  -> uint16_t
U32  -> uint32_t
U64  -> uint64_t

I8   -> int8_t
I16  -> int16_t
I32  -> int32_t
I64  -> int64_t

F32  -> float
F64  -> double
```

Constructed types may become:

```text
struct
array
pointer/reference
tagged union
opaque handle
```

Static-only types must disappear.

---

# 55. Keyed C emission

A keyed type:

```lua
local Point = word{
    x = F32,
    y = F32,
}
```

may emit:

```c
typedef struct {
    float x;
    float y;
} Point;
```

Nested keyed types lower recursively by value.

Ordered executable children are not struct fields.

---

# 56. Ref C emission

```lua
Ref:of(Point)
```

may lower to:

```c
Point *
```

Recursive references use C forward declarations where necessary.

Selection through the pointer still binds nested ordered children to the pointed-to instance.

---

# 57. Owned executable C emission

For:

```lua
c.increment(5)
```

the backend may emit:

```c
Counter_increment(&c, 5);
```

with:

```c
uint32_t Counter_increment(
    Counter *self,
    uint32_t amount
) {
    self->count += amount;
    return self->count;
}
```

`self` is backend representation, not source syntax.

If specialization can inline the call, even that representation may disappear.

---

# 58. Generic C emission

Given:

```lua
local Pair = word(
    Type,
    Type,

    function(A, B)
        return word{
            first = A,
            second = B,
        }
    end
)
```

then:

```lua
local P = Pair:of(U32, F32)
```

can emit only:

```c
typedef struct {
    uint32_t first;
    float second;
} P;
```

The generic machinery disappears entirely.

---

# 59. Specialized stateful C emission

Given:

```lua
local Filter = word{
    gain = F32,
    value = F32,

    step = word(
        F32,

        function(input)
            value = value + gain * input
            return value
        end
    ),
}

local Gain2 = Filter:of{
    gain = 2,
}
```

the residual C representation may be:

```c
typedef struct {
    float value;
} Gain2;
```

with:

```c
float Gain2_step(Gain2 *self, float input)
{
    self->value += 2.0f * input;
    return self->value;
}
```

The static field remains semantically visible but occupies no runtime storage.

---

# 60. C closure criterion

A residual program is C-emittable iff:

```text
1. Every live residual value has a C-representable Type.

2. Every residual operation has defined C lowering.

3. Every live state place has defined storage.

4. Every control-flow edge has a valid lowering.

5. Every recursive layout has finite representation.

6. No static-only value remains as runtime data.

7. Every runtime effect has explicit residual semantics.
```

---

# 61. Emission pipeline

## Stage 1 — construct definitions

Lua executes the DSL module and creates word definitions.

No semantic normalization is forced merely by construction.

## Stage 2 — explicit specialization

User-requested `:of` operations establish static bindings.

Normalization remains demand-driven.

## Stage 3 — demand-driven normalization

When a word's result is required:

```text
look up specialization identity
install recursive placeholder if unseen
evaluate terminal
fill placeholder
memoize result
```

This handles ordinary specialization and recursive knot tying uniformly.

## Stage 4 — establish symbolic runtime inputs

Remaining positional or keyed runtime requirements become `Symbol` values.

Runtime storage becomes `Place`.

## Stage 5 — interpret terminals

Lua terminal functions execute over abstract values.

Known work computes.

Dynamic work emits residual IR.

Branch comparisons may invoke oracle replay.

Recursive re-entry may create residual calls or backedges.

## Stage 6 — normalize residual IR

Initially keep this minimal:

```text
remove unreachable code
remove unused pure values
canonicalize constants
optionally share identical suffixes
```

## Stage 7 — close types and layouts

Verify C-representability.

Detect illegal by-value recursive cycles.

Assign layouts.

Create forward declarations for recursive reference types.

## Stage 8 — emit C

Emit:

```text
includes
forward declarations
typedefs
structs
enums/unions
function declarations
function bodies
constants
```

in dependency order.

---

# 62. Export roots

Compilation starts from explicit export roots.

An ordered word may become a C function.

A keyed `Type` may become a C type.

Reachable owned executable children are emitted only if they survive specialization and are needed.

Thus:

```text
export roots
    ->
reachable normalized words
    ->
reachable residual types/operations
    ->
C
```

Unused staging definitions vanish naturally.

---

# 63. First-class executable runtime values

Ordered words do not inherently need runtime closure representations.

They may lower to:

```text
direct C function
inline code
tail edge
```

Known code remains static: direct calls do not require function pointers.
Unknown runtime code may use a signature-specific function pointer and borrowed environment.

## Stateful objects and borrowed methods

Records own their mutable state and preserve the ordinary by-value boundaries. Return the record
from a stateful factory, then select its methods at the call site. Methods are static code operating
on that receiver, not independently owned mutable closures.

Selecting or copying a method view preserves its reference to the original receiver. Copying the
record itself creates independent data; existing method views still refer to the original.

Borrowed methods and callbacks may be used locally or passed to non-retaining callback parameters.
They must not be returned (including in multiple results) or retained in record fields. A closure
capturing mutable storage or a borrowed callable is also borrowed. Methods must not hide borrowed
mutable state outside their receiver fields.

Thus `return c.increment, c.read` is invalid for mutable `c`. Use `return c` instead. The same
rule applies to interpreted execution and residual C; the implementation must not silently allocate
or introduce caller-owned closure storage to make the invalid escape work.

Immutable captures may travel by value, provided they contain no borrowed mutable state. A generic
borrowed callable signature does not establish that property. Unknown callback implementations,
including foreign C callbacks, must honor the non-retaining contract.

These rules do not require an ownership framework, recursive environment layouts or relocation fixups.
Immutable runtime captures use by-value environments. Recursive code references are static links,
not self-pointers inside those environments. Captured bindings cannot be reassigned. Method/type
metadata must remain static: record methods place runtime state in explicit receiver fields.

---

# 64. Correctness laws

For word `W`, static inputs `S`, and remaining runtime inputs `R`:

```text
Run(
    Specialize(W, S),
    R
)
```

must be observationally equivalent to:

```text
Run(
    W,
    S combined with R
)
```

including:

```text
returned values
state mutations
runtime effects
specified failures
```

Repeated compatible specialization must compose.

Demand-driven normalization must be observationally equivalent to eager normalization wherever eager normalization would be well-defined.

Recursive placeholders must preserve one stable definition identity per specialization key.

C execution must preserve residual word semantics.

---

# 65. Complete source surface

The essential DSL remains:

```lua
word(...)          -- ordered definition or positional signature

word{ ... }        -- keyed definition


w:of(...)          -- positional specialization

w:of{ ... }        -- keyed specialization


w(...)             -- positional execution

w{ ... }           -- keyed construction / keyed application


w.member            -- selection

w.member = value    -- state update


x:eq(y)             -- staged equality
```

plus ordinary Lua:

```lua
function(...) ... end

local x = ...

return ...

a + b
a * b

if ...
and
or
not
```

The permanent law remains:

```text
() = ordered
{} = keyed
```

---

# 66. What emerges from the core

Without dedicated syntax we obtain:

```text
records
    keyed words

nested values
    nested keyed words

modules/namespaces
    keyed words containing words

procedures
    ordered words with terminals

positional signatures
    terminal-less ordered words

higher-order programming
    words satisfying signatures

state
    keyed runtime instances

objects
    keyed instances containing ordered children

methods
    receiver-bound nested ordered words

references
    Ref(Type)

recursive types
    deferred terminal self-reference + knot-tying normalization

generic recursive types
    recursive specialization identities

loops
    tail-recursive ordered words

tail calls
    ordinary returned calls

types
    words satisfying Type

generic functions
    ordered words accepting Type

generic types
    ordered words returning Type

value-dependent types
    static ordinary inputs to type constructors

sum types
    OneOf(keyed alternatives)

matching
    keyed case application

compile-time computation
    Known-value evaluation

runtime generation
    Symbol/Place residualization
```

---

# 67. Final architecture

```text
                         LUA
                          |
                          v
                  WORD DEFINITIONS
                  /              \
             ordered ()        keyed {}
               |                  |
               |                  +--> named data / state / scope
               |
               +--> terminal computation
                          |
                    demand / :of
                          |
                          v
                  NORMALIZATION CACHE
                  /               \
             recursive          ordinary
             placeholder        specialization
                  \               /
                   v             v
                  ABSTRACT EXECUTION
                /        |         \
             Known     Symbol      Place
               |          |          |
           compute     residual    residual
                \         |          /
                 \        |         /
                    TYPED IR
                       |
                  TYPE/LAYOUT
                    CLOSURE
                       |
                       v
                      C
```

Branching is recovered through replay of ordinary Lua `if`.

Loops arise from recursive words plus specialization memoization.

Recursive types arise from forward-declared Lua upvalues plus demand-driven knot tying.

`Ref` breaks recursive layout cycles and carries receiver identity through referenced instances.

Generics arise from specialization over `Type`.

State arises from keyed instances with bound ordered children.

The core remains:

> **`()` means order. `{}` means names. `:of` supplies static knowledge. Calls supply runtime values. Lua terminals describe computation. Demand-driven partial evaluation normalizes what can disappear; symbolic residual structure closes into C.**
