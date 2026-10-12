# Let — syntax and semantic contract

Let is the main language. This document specifies its surface language for `architecture.md`.
Examples are specification examples, not claims that a parser/compiler already implements them.

Sections 1–14 define the statically typed core and the additional restrictions enforced by SLet `.slet`. Section 15 defines progressive typing, dynamic operations and GC-managed ownership for ordinary Let `.let`. SLet is a true sublanguage: every accepted `.slet` program is accepted as `.let` with the same observable results. SLet additionally guarantees that its module uses no `any`, managed allocation or GC roots.

The core is a word with ordered or keyed requirements, an optional result contract, and an optional
terminal. Application supplies requirements; saturation invokes an implementation. A signature has
requirements and a result contract but no implementation. A record schema has keyed requirements
and an intrinsic construction terminal. A method is an executable word with an implicitly bound
actual receiver.

Owning syntax changes application and control-flow elaboration, not just punctuation. This document
makes those changes explicit. There is no compatibility requirement with the old Lua grammar.

## 1. Lexical rules and item boundaries

The grammar is free-form. Newlines and indentation are whitespace. A `--` comment runs to the end
of the line and is otherwise whitespace. `--` immediately followed by a long bracket (below) is a
block comment instead, so a comment may span lines and may contain anything; a `--` followed by a
space is always the line form, so `-- [[1, 2]]` comments out a bracket. Keywords and delimiters
determine structure. Semicolons are optional separators between complete statements/declarations, not within
expressions. Commas separate parameters, arguments, fields and result-list items; trailing commas
are allowed in delimited lists.

Identifiers use ASCII letters or underscore followed by ASCII letters, digits or underscore. Names
are case-sensitive; capitalization never distinguishes a type from a value or a signature from a
lambda. Let spells its own vocabulary in lowercase for exactly that reason, and there is no
second, capitalized spelling of any of it.

Reserved keywords are `let`, `extern`, `do`, `defer`, `end`, `if`, `then`, `else`, `return`, `and`,
`or`, `not`, `true`, and `false`. Predefined bindings are the primitive types `u8`, `u16`, `u32`,
`u64`, `i32`, `i64`, `f64`, `bool`, `unit` and `type`, the byte slice `string`, and the type
constructors `oneof` (section 8.1), `ref` (section 8.2), `array` and `slice` (sections 8.3 and 8.4),
and `ptr` with its null pointer `null` (section 8.5).

Those predefined words are reserved at module level: a module-level `let`, `extern` or word
declaration may not bind one (`reserved`), because the name is already the language's own word and
rebinding it would silently change what `u32` or `oneof` means. A local binding inside a body may
shadow one, like any outer name. Everything else a program names is the program's own vocabulary;
GUIDE.md section 3 describes the spelling style Let source is written in.

Numeric literals are decimal, hexadecimal prefixed by 0x, or binary prefixed by 0b. A single
underscore may separate any two digits, so 1_000_000 and 0b1010_1010 read as they look; a separator
that leads, trails or doubles rejects rather than being ignored into a different value. A literal
that fits a
word is a u32 and one that does not is a u64, so 0xFFFFFFFFFFFFFFFF can be written directly; a
literal above 64 bits rejects rather than wrapping. A leading minus is an operator, not part of a
literal. There are no nil or implicit tuple literals. A string literal is a byte sequence, specified in
section 8.4.

The integer types are `u8`, `u16`, `u32`, `i32`, `u64` and `i64`. `i32` is
two's complement, so it wraps, its division truncates toward zero with the remainder taking the
dividend's sign, its right shift is arithmetic, and the most negative value divided by -1 wraps to
itself rather than being undefined. Its negation wraps too, and a signed power needs a power that is
not negative (a run-time one is checked).

An operation needs one integer type unless one operand is a literal, which adopts the other's type
when its value fits; mixed widths of one signedness widen to the wider one, and mixing signed and
unsigned rejects, so a conversion has to say which is meant. Changing signedness at one width
reinterprets the bits; any other conversion that cannot lose a value is implicit, and one that can is
checked, rejecting a known value outside the target and stopping a run-time one.

Arithmetic wraps at the width its type names, comparisons widen first, and a shift amount is a plain
u32. Assigning a run-time value to a narrower annotation rejects (`numeric-range`) rather than
truncating it silently.

`u64` and `i64` are 64 bits wide and follow the same rules, including the `i64` boundary cases above.
Their bounds are not Lua numbers, so a conversion that changes width is checked against the target's
range rather than truncated, and a conversion that only changes signedness at one width still
reinterprets.

`f64` is IEEE-754 double and follows IEEE 754 rather than the integer rules: division by zero is an
infinity or a NaN rather than a trap, a NaN comparison is false, an integer converts to a float by
rounding to nearest with ties to even and a float to an integer by truncation, with a value outside
the integer's range rejected when known and stopped when not. There is no `F32`.

A float literal is written with a point, an exponent, or both, and its type is f64: `1.5`, `1e5` and
`1.5e-3` are one value each. A point needs a digit on both sides, so `1.` is the integer 1 followed by
a `.` rather than a float, and a member selection never has to guess which was meant. A hexadecimal
literal keeps its `e` as a digit, so `0x1e5` is an integer. A digit separator may appear between any
two digits of the mantissa or the exponent, and an exponent needs at least one digit. A float literal
does not adopt another operand's type the way an integer literal does: `1.5` is f64 and stays f64.
`true` and `false` are bool. `unit()` is the unit value.

Comments begin with `--`. `--` followed immediately by a long bracket opens a block comment that ends
at that bracket's own closing form, so it may span lines and its body may contain anything; any other
`--` runs to the end of the line. A line comment is the only newline-sensitive lexical
rule. Operators use longest-token matching, so `!=`, `<<=` and `->` are single tokens.

An item boundary is grammatical, not visual. In a block, `let`, `return`, statement `if`, and `end`
cannot continue an ordinary expression. Adjacent names do not apply functions. A postfix `(` or `{`
CAN continue the preceding expression across a newline; use `;` if separation is intended. A return
of unit before an expression statement must be written `return;` (the following statement is then
unreachable), not inferred from a line break.

## 2. Bindings and named definitions

```
let x = 42
let flag: bool = true
let affine(a, b, x: u32) : u32 = a * x + b
```

`let` introduces an immutable lexical binding. An optional annotation checks its value; it is not a
conversion chosen by the backend. Bindings cannot be reassigned. A binding can hold a mutable record
instance, however: binding immutability does not freeze that instance's fields.

A named definition is sugar for binding a word. Parameters are ordered and have immutable bindings.
Adjacent names share the following annotation: `(a, b, x: u32)` declares three u32 parameters. Every
named-definition parameter must have an annotation. The result annotation is optional except where
section 10 requires it. Duplicate parameter names reject.

A named definition may take **keyed** requirements instead, written like a schema's members:

```
let distance { x: u32, y: u32 }: u32 = x * x + y * y
let d = distance { x = 3, y = 4 }
```

Every keyed requirement is annotated, because a key has no position to infer a type from. Supplying
every key invokes the body; supplying fewer returns a specialized word, exactly as ordered partial
supply does, and the supplied values must be static. Keyed requirements have no order, so supplies
may be written in any order, and the word is applied by name. A schema is the special case of a
keyed word whose terminal constructs an instance.

type requirements are evaluated left-to-right when arguments are supplied. An earlier parameter may
appear in a later requirement:

```
let identity(t: type, x: t) = x
```

`t` must be known before checking x's requirement. This is ordinary type demand, not an implicit type
parameter or a new `static` keyword.

Top-level binding names are mutually visible; their initializers are evaluated once, eagerly, during
module initialization in declaration order. A forward reference demands a later initializer early,
and a cycle demanding a value before its initializer completes rejects. Creating a word does not
execute its body, so mutually recursive word definitions need no forward declaration.

Local bindings are visible after their initializer, not throughout the block. A local named word
also sees its own name in its BODY, permitting self recursion; this does not make an arbitrary local
initializer self-referential. Mutually recursive local declarations are not introduced by this syntax.
Shadowing an outer binding is allowed; duplicate declarations in one lexical scope reject. Parameters
and body declarations follow that same rule.

## 3. Application and partial supply

Application uses parentheses, never juxtaposition:

```
let transform = affine(4, 3)
let nineteen = transform(4)
```

Evaluate the callee, then arguments left-to-right. Adjust result lists as in section 6, check the
supplied requirements, append those arguments, THEN test saturation.

- Fewer arguments than remaining requirements: return a specialized word. All supplied arguments
  must be static values, free of runtime captures and mutable storage bindings.
- Exactly the remaining requirements: invoke the word's terminal. Arguments may be static or runtime.
- More than the remaining requirements: reject. Arguments are not implicitly forwarded to a result.
- No arguments with outstanding requirements: return the same word; no terminal executes.
- No arguments with no outstanding requirements: invoke the nullary terminal once.

A signature without an implementation can describe/check a calling requirement but cannot be
invoked to fabricate a result. Fully supplying such a descriptor does not supply its missing code.

Partial supply is static specialization, not an implicit closure allocation. To capture an immutable
runtime value, write a lambda explicitly:

```
let add(a, b: u32) = a + b
let add_runtime(n: u32) = |x: u32| -> add(n, x)
```

Inside a residual function `add(n)` rejects if n is runtime; `add(n, x)` is a valid saturated call.
Capturing a borrowed method in a lambda yields a borrowed lambda, with the escape restrictions of
section 9. It does not make an owning closure by spelling the operation differently.

At a saturated call, known arguments specialize automatically. `affine(4, 3, x)` and `transform(x)`
share the same residual specialization when their other bindings agree. Staticness is a property of
the complete invocation, including receiver/captures. Empty-argument `r.draw()` is not static if r is
runtime storage. Known current contents do not make a mutable record a static argument.

## 4. Anonymous words and signatures

Every lambda uses pipes:

```
|x| -> x + 1
|a, b| -> a ~ b
|x: u32| -> x + 1
|a, b: u32| -> do let t = a * a  return t + b end
|| -> unit()
```

Bare `x -> ...` is NOT a lambda form: `->` only ever introduces a lambda body. A result is written
with `:`, and a signature's inputs are parenthesized, so a signature is unambiguous even when its
type aliases are lowercase and even inside a lambda's parameter list:

```
let number = u32
let endo = (number): number
```

Lambda parameters use the same grouping rule as named parameters. Missing annotations require an
expected callable signature, supplied by an annotated binding, a parameter requirement or a result
contract. Every missing parameter type must be determined by that context; arbitrary body-based
parameter inference is not performed. An untyped standalone lambda rejects.

```
let inc: (u32): u32 = |x| -> x + 1
let twice(f: (u32): u32, x: u32) = f(f(x))
let inc_2x = twice(|x| -> x + 1)
```

Expected callable types are passed to lambda arguments as their corresponding requirements become
known. This is checking, not permission to reorder argument effects. In a conditional checked against
a signature, propagate that expectation into both value-producing arms. Once a lambda's parameter
types are resolved, invocation uses those types; it does not evaluate their annotations again.

A literal used immediately as a callee, or as the selected handler of a known match, need not first
become a first-class callable value. During static execution, a saturated invocation with known
numeric, bool, unit or string arguments and no runtime/place captures prepares captures and parameter
types, then executes its body once. It checks the selected body path, like a fully static named word;
no generic result signature or unused C base is invented first. Captures and annotations still occur
at the literal's written position, before arguments or later handler expressions, and invocation waits
for argument evaluation or match coverage/handler checking. First-class lambda values, runtime calls,
partial supply and unsupported argument/environment shapes retain ordinary checked-base construction.
This is not result memoization or general lazy closure checking.

`->` introduces a lambda's BODY; it never denotes a result type. A lambda's result is declared by an
annotated binding or by the requirement it is passed to. Typed lambda parameters plus an inferred
result are also valid, and a lambda body may itself be a signature: `|x: u32| -> (u32): u32`.

Signature forms are:

```
(u32): u32                    -- one input, one result
(u32, u32): u32               -- two inputs
(): u32                       -- no inputs
(u32): (u32, u32)             -- two results
(u32): ()                     -- unit result contract
(u32): ((u32): u32)           -- one callable result
```

A parenthesized comma list before the `:` is the input list; a comma list after it is the result
list. Neither creates tuple values. An empty list denotes no inputs, or one unit result. A
parenthesized single type is grouping and is equivalent to that type, so `(u32): u32` has one input.

A signature is a calling requirement, not executable code. Checking known code against it verifies
parameter and result requirements without arbitrarily erasing known implementation identity. Unknown
runtime code needs a complete signature and uses the non-retaining callable ABI. A signature alone
is not an assertion that a callable owns an environment.

## 5. Bodies, blocks and conditionals

A word body is an expression or a `do ... end` block:

```
let square(x: u32) = x * x
let square_block(x: u32) = do
  let result = x * x
  return result
end
```

An expression body returns that expression's result vector. A block has no implicit last-expression
result: every reachable function path must return. A bare `return` returns unit. A declaration or
call statement at the end does not imply a return. Code after a definitely terminating statement in
the same list is rejected as unreachable.

Blocks may contain declarations, field assignments, compound field assignments, call statements,
statement conditionals, deferred actions and returns. A call statement must be saturated; it evaluates
the call and discards its result vector, and a deferred action is a call statement that runs when the
block it is written in is left (section 8.8). Discarding an incomplete word is an error, not a call
for effects. Arbitrary unused arithmetic expressions are not statements. `do ... end` is a body form,
not a standalone value expression or a declaration-scope statement.

Conditionals have two grammatical forms:

```
let chosen = if condition then a else b

if condition then
  r.draw()
else
  r.draw()
  r.draw()
end
```

An expression conditional requires else and has no trailing end. Its arms are expressions, each
producing a result vector. A statement conditional has statement-list arms, optional else, and a
terminating end. After then/else, statement versus expression parsing is determined by which form
was entered; a leading statement-position if is never guessed to be an expression statement.

Conditions must be bool. A known condition evaluates only the selected arm; the other arm is parsed
and lexically resolved but not semantically evaluated. An unknown condition elaborates both arms once.
Continuing expression arms must agree in source result arity and compatible component types. Identical
known components remain known; differing representable values require runtime result slots. Different
static-only type values cannot be turned into a runtime type.

Each arm has a child lexical scope. Declarations inside an arm do not escape. An arm that returns
from the enclosing word does not reach the continuation. A missing statement else is an empty
continuing arm. Thus this is complete without any fictitious value from the first arm:

```
let skip(s, n: u32) : u32 = do
  if n == 0 then return s end
  return skip(next32(s), n - 1)
end
```

## 6. Multiple results and adjustment

Multiple results are an ordered result vector, not a tuple value:

```
let divmod(a, b: u32) : (u32, u32) = do
  return a / b, a % b
end

let quotient, remainder = divmod(17, 5)
let q: u32, r: u32 = divmod(17, 5)
```

For ordinary bindings, each name has its OWN optional annotation. `let a, b: u32 = ...` annotates b
only; shared annotations are restricted to parameter lists. Each bound name is fresh and immutable.
This is result-list binding, not recursive destructuring or a pattern language.

Expression evaluation has a result vector. Scalar contexts take its first value: arithmetic,
comparison, condition, callee selection, field base, record-field initializer and a supplied type
requirement. Extra values are discarded AFTER the expression executes. Parenthesizing an ordinary
expression explicitly adjusts it to one result: `(divmod(a, b))` yields only the quotient.

In an argument list, return list or binding initializer list, all expressions except the final one
contribute one result. The final expression contributes its complete vector. Evaluate expressions
left-to-right before adjustment. Named record initializer items each contribute one value and never
expand a result vector across fields.

```
let forward(a, b: u32) = divmod(a, b)        -- forwards both results
let first(a, b: u32) = (divmod(a, b))        -- returns one result
```

Binding lists discard surplus values and fill missing values with unit. An annotation incompatible
with that unit rejects. Call argument lists do NOT fill missing parameters: after expansion they
follow partial/saturated application rules. Return vectors must match the enclosing declared or
inferred result contract exactly; they are not padded to satisfy it.

Zero results and a bare return denote one unit result in Let. Explicit unit slots in multiple
results remain logical slots even though C erases their payloads. `return unit(), 3` has arity two.
A callable expression returning multiple results as an expression body forwards all of them.

## 7. Operators and evaluation order

Tightest first:

| Level | Operators | Associativity |
| --- | --- | --- |
| postfix | `f(...)`, `T {...}`, `.name` | left |
| power | `^` | right |
| unary | `-`, `~`, `not` | prefix |
| multiplicative | `*`, `/`, `%` | left |
| additive | `+`, `-` | left |
| shift | `<<`, `>>` | left |
| bitwise and | `&` | left |
| bitwise xor | `~` | left |
| bitwise or | `\|` | left |
| comparison | `==`, `!=`, `<`, `<=`, `>`, `>=` | non-associative |
| logical and | `and` | left |
| logical or | `or` | left |

Pipes in prefix position introduce a lambda; infix pipe is bitwise-or. A lambda parameter annotation
stops at the closing pipe, so `|f: (u32): u32| -> f` reads as one parameter whose type is a signature.
The lambda body extends as a full body/expression to its enclosing delimiter. Signature arrows do
not introduce parameter names or executable bodies.

Power binds tighter than unary on its left: `-x ^ 2` means `-(x ^ 2)`. Unary is allowed on the right
of power, so `x ^ -1` means `x ^ (-1)`. Here -1 is modular u32 negation, not a signed exponent. Two
comparisons cannot chain without explicit grouping; `a < b < c` rejects.

Arithmetic and bitwise operators require one integer type, except that `+`, `-`, `*` and `/` also
apply to f64. As section 1 says, a literal adopts the other operand's type when its value fits,
mixed widths of one signedness widen to the wider one, and mixing signed and unsigned rejects.
Add/subtract/multiply/negate/power wrap at the width the type names.
`0 ^ 0` is 1. Division truncates toward zero, with the remainder taking the dividend's sign; a known
zero divisor rejects and a dynamic one aborts at runtime. A right shift is logical for an unsigned
type and arithmetic for a signed one, so it keeps the sign bit; a shift amount at least the width
yields zero, or the sign fill for an arithmetic right shift. No implicit bool/integer conversion
exists.

Ordered comparison requires one integer type or f64, and equality requires equal scalar types (one
integer type, bool, f64 or unit; unit equals unit). A comparison widens its operands to one integer
type the way an arithmetic operation does. Two `string` values compare by content, since a byte
sequence has no identity a program can observe. Record, word, type, slice and callable equality are
not added by the equality tokens.

`and`, `or`, `not` require bool and produce bool. There is no truthiness and no operand-valued Lua
and/or behavior. `and` and `or` short-circuit. Other binary operators evaluate operands left-to-right;
all source call and initializer evaluation order is preserved by generated C.

Supported compound field stores are exactly `+=`, `-=`, `*=`, `/=`, `%=`, `^=`, `&=`, `|=`, `~=`,
`<<=`, and `>>=`. Their operand rules are those of the corresponding operation. There is no comparison
assignment, logical assignment, `:=`, increment operator or rebinding assignment.

For `base.field op= rhs`, evaluate the target base/path once, read the old field value once, then
evaluate rhs, compute the operation and store. If rhs mutates that field, the final operation still
uses the earlier snapshot. Plain field assignment evaluates its target once, then rhs, then stores.

## 8. Records, keyed supply and methods

```
let point = { x: u32, y: u32 }
let p = point { x = 3, y = 4 }
let old = p.x
p.x = 20
```

A schema literal contains named data requirements and optional methods. A named initializer occurs
only AFTER a word expression, as postfix keyed application. Bare `{x=3}` is not an untyped record
value. Bare `{}` is the empty record schema; `point {}` is an empty keyed supply. Schema field order
does not determine identity or layout. Duplicate names and reserved-member collisions reject.

Keyed application accepts named supplies, not positional arguments. Unknown names and resupplying a
bound field reject. An incomplete keyed supply produces a specialized schema word and requires all
supplied values to be static. Bound fields are static, readable and non-writable. Saturation constructs
a fresh record with its remaining data fields initialized. Ordinary saturated constructor arguments
that happen to be known do NOT thereby turn those source fields into readonly static fields.

```
let at_x3 = point { x = 3 }
let p = at_x3 { y = 4 }           -- x is statically bound; y is an instance field
```

Initializer expressions execute in written order even though fields are stored canonically. Methods
are code members, not initializer fields or stored function pointers. Record arguments, assignments
into fields and returns have value-copy semantics; local aliases to an instance retain that instance.

A schema used as a declaration (`child: counter`, `c: counter`, a result `: counter`, or
`ref(counter)`) selects a **source interface** in addition to its structural data type. Selecting
`parent.child.bump()` invokes `counter`'s `bump` on the actual child field; selecting through a
reference declared `ref(counter)` borrows the place it names. Assignment checks the structural data
and retains the destination's declared interface, not the source's methods. Thus two schemas with
identical fields remain the same type and layout, but a field declared with one uses that one's
implementation even if initialized from the other. A field read copied to a local retains its
statically known interface but copies data; changing the local does not change the parent.
A bare structural type without an interface supplies no methods. An unannotated result can preserve
one interface when every returning path agrees; incompatible interfaces at a join are erased rather
than arbitrarily choosing one. A `type` parameter supplied with a schema conveys that schema as a
static requirement; distinct supplied implementations specialize independently. This information
is compile-time only: ordinary records have no runtime method table.

Partial keyed schema supply also promises static readonly data. A value constructed with that
specific supply may keep it; a structurally equal record from elsewhere cannot be annotated as the
partially supplied schema (`interface-supply`) merely because its layout fits, nor may a readonly
supplied field be assigned (`readonly-field`). An exported parameter or foreign result cannot prove
such a static supply from untrusted host data, so it cannot promise one; ordinary schema annotations
on foreign results can still choose method implementations.

```
let rng = {
  state: u32,
  draw() : u32 = do
    state = next32(state)
    return state
  end,
}

let draw_once(s: u32) : u32 = do
  let r = rng { state = s }
  let before = r.state
  r.draw()                      -- saturated call statement; result discarded
  return before
end
```

An immutable binding to r permits writes to r.state; `r = ...` rejects. Bare `state = ...` inside a
method resolves to its receiver field, not a local binding. Ordinary locals/parameters shadow field
names; assigning a shadowing immutable binding rejects rather than falling through to the field.
Explicit `r.state` selection uses r's actual instance.

A method borrows its actual receiver. Selecting it on an instance binds that receiver. Selecting it
on a schema produces an unbound method interface useful for export, but it cannot be called without
an actual receiver. No source `&T` parameter or guessed dynamic caller supplies one.

Nested lexical owners use actual enclosing records and explicit occurrence routes. Copying a child
record alone does not invent its former parent. Source definitions do not acquire mutable parent
pointers. Missing required owner bindings reject.

### 8.1 Sums

A sum type is a finite set of named alternatives, each with its own payload type. It is a keyed
schema read as a tag plus a payload, so it needs no new syntax of its own: the schema's field names
are the alternatives and the field types are their payloads.

```
let circle = { radius: u32 }
let rect = { width: u32, height: u32 }
let shape = oneof { circle: circle, rect: rect }
```

`oneof` takes one keyed schema and produces a type value. Its single requirement is a keyed one, so
the schema attaches with braces exactly as `point { x = 3 }` attaches a keyed supply, and the entry
separator decides whether an entry defines or supplies: `name: type` defines, `name = value`
supplies. There is no call parenthesis to write, because `oneof` is an ordinary word applied to a
keyed requirement. Passing the schema as an ordinary argument instead --
`oneof({ circle: circle, rect: rect })` -- is the same thing, and is what a schema held in a binding
needs.

Alternative order is canonical, not written order, so two spellings of the same alternatives are the
same type. `oneof` requires a schema with at least one named alternative; an empty schema, or a
non-schema argument, rejects.

Member selection on a sum type names a constructor for one alternative:

```
let round = shape.circle { radius = 3 }
let flat = shape.rect { width = 4, height = 5 }
```

An alternative whose payload is a record is constructed by keyed supply, checked and stored exactly
like the payload record itself. An alternative whose payload is not a record is applied to one value
positionally, and a `unit` alternative is applied to nothing (`Opt.none()`). Selecting a name that is
not an alternative of that sum rejects.

Matching is keyed application of a sum value with one handler per alternative. The handlers are
callable values, each receiving that alternative's payload:

```
let area(s: shape): u32 = s {
  circle = |c: circle| -> c.radius * c.radius,
  rect = |r: rect| -> r.width * r.height,
}
```

Every alternative must be handled exactly once; missing, duplicated or unknown alternatives reject,
including for a known tag. Handler expressions are evaluated in written order, with one exception:
an unselected lambda literal for a known tag is not constructed at all, so its captures, parameter
annotations and body are not elaborated for that occurrence. Other handler expressions still evaluate
and must produce callable values; only the selected handler is invoked. This is not general lazy
evaluation of arbitrary expressions that produce handlers.

A value whose alternative is only known at run time requires every handler to be elaborated and
callable, with matching result types. It becomes a tag test per alternative with the payload projected
inside the matching arm.

A sum value is immutable like a record; its alternatives have no selectable members. A payload is
reached by matching, not by naming an alternative in a member select. Sum values copy by value on
argument passing, assignment and return.

Recursive sums are not expressible without an indirection boundary: an alternative's payload type
must already be defined, so a sum cannot mention itself by value. Section 8.2 supplies that boundary.

### 8.2 References and recursive types

A reference names a place instead of copying it. It is one of the three indirection boundaries that
make a recursive type finite -- `ptr` (section 8.5) and `slice` (section 8.4) are the others -- and it
is what lets a sum mention
itself:

```
let node = { value: u32, next: link }
let link = oneof { none: unit, some: ref(node) }
```

`ref` is an ordinary word, so it needs no new syntax: applied to a type value it produces a type,
and applied to a place it produces a reference to that place.

```
let counter = { value: u32 }
let c = counter { value = 1 }
let r = ref(c)                 -- r : ref(counter)
r.value = 20                   -- writes c.value: selection through a reference is a place route
let again = ref(c)             -- a second reference to the same instance
```

A reference is an ordinary value: it may be a parameter, a result, a field or a local binding, and
passing or returning one passes the reference, not the instance. A function may therefore take
`ref(T)` and write through it, and a reference to module storage may be returned from a call and
followed there. A host that holds such a pointer may pass it directly.

`ref(T)` is not a copy of `T`. When `T` denotes a schema, that annotation also selects the
schema's methods; a method call through the reference borrows its actual referent. It does not
turn the reference into ownership or retarget the method to a copy. Reading or writing through a reference reaches the referenced
instance, exactly as selecting that instance directly would, and two references to one instance
observe each other's writes. A reference has stable identity under copying: copying a record that
holds a reference copies the reference, not the referenced instance. Assigning through a reference
to a field of a *binding* still rejects: `r = ...` is not a store, only a place beneath `r` is.

`ref` never means ownership, uniqueness, move or automatic destruction. A reference does not keep
its target alive, and it is not the mechanism by which a record owns a child.

#### What a reference may name

A reference may name an addressable place only when its storage outlives every use and retention
of the reference. Named local records and arrays, their addressable subobjects, caller-provided
places and module storage follow this same rule. A reference does not extend an allocation's life.

`ref-target` rejects a temporary or a value without an addressable target. A reference is not
itself another target: `ref(ref(x))` rejects rather than collapsing two indirections.

Passing a record or array by value creates separate owned storage. Returning a reference to that
parameter's own storage rejects, just like returning a reference to a local. Returning an existing
reference or slice from a copied parameter's field instead retains that field's original referent;
it may be returned when the referent belongs to the caller or the program.

The compiler checks uses, stores, returns and loop transfers, including checked access inside
records, arrays, variants and callable environments. A branch-local source cannot be stored in an
outer record. Replacing an owned subobject overwrites its existing backing storage: references to
it observe the replacement, while earlier by-value snapshots keep their data.

Violations report `borrow-use`, `borrow-store`, `borrow-return` or `borrow-next`. Missing origin,
alias or contract evidence reports `borrow-unknown`; unknown never means borrow-free. Direct calls
infer and discharge caller-relative retention requirements. This information belongs to occurrences
and function summaries, not to types or user-written lifetime parameters.

```
let counter = { value: u32 }
let shared = counter { value = 0 }              -- module storage

let node = { value: u32, next: ref(counter) }
let local(x: u32): u32 = do
  let n = node { value = x, next = ref(shared) }
  return n.next.value                            -- fine: the target is module storage
end

let bad(x: u32): node = do
  let c = counter { value = x }
  return node { value = x, next = ref(c) }        -- rejects: c dies with this activation
end
```

A recursive type definition must be a file-scope binding. File-scope names are mutually visible and
demanded lazily, which is what lets two definitions mention each other, but a local binding is
declared in order and its initializer cannot see its own name, so a local definition that names
itself rejects like any other forward reference.

#### Recursive type identity

A type whose definition needs itself is a **recursive type**. The first demand for such a
definition reserves its cell; a demand that arrives while the cell is still being computed yields an
indirection to that cell rather than forcing its layout. The cell is sealed with the finished
definition and the result must not change afterwards.

```
let bad = { child: bad }        -- rejects: by-value containment has no finite layout
let good = { child: ref(good) } -- accepted: the layout cycle crosses the reference boundary
```

A by-value cycle rejects (`type-cycle`) even when it passes through several definitions. A cycle
that crosses an indirection, a reference or a raw pointer, is finite: either has a representation
whose size does not depend on
its target. type equality is structural, except that a recursive definition compares by its reserved
identity, so two spellings of one recursive knot are one type and one layout.

#### Validation

Required reference tests include:

- reference construction from each legal target, selection and store through a reference, aliasing
  between two references, and copying a reference by value;
- safe local references and caller-derived results; temporary targets and local/by-value-storage escapes;
- branch and module retention, aliasing, adapters and unknown checked contracts;
- a finite recursive list built over module storage: construction, traversal, and a mutation seen
  through a stored reference;
- by-value cycles across one and several definitions (`type-cycle`), and a cycle broken only by a
  reference being accepted with a finite layout.

### 8.3 Arrays

An array is a fixed-length sequence of one element type. The type is `array(T, N)`, an ordinary word
applied to an element type and a length, and a literal is written with brackets:

```
let xs = [10, 20, 30]
let ys: array(u32, 3) = [10, 20, 30]
let first = xs[0]
let pick = |i: u32| -> xs[i]
xs[1] = 99
xs[0] += 5
```

The length is part of the type, so it is never inferred from a later assignment and a literal is
checked against it. A literal takes its element type from its elements, or from an annotation, which
is what an empty literal needs: `[]` with no element has nothing to infer from and rejects
(`type-required`). A literal whose length does not match, whose elements do not share one type, or an
`array` whose length is not a positive literal rejects (`array-length`, `type-mismatch`).

Indexing is `a[i]` for a `u32` `i`. A known index outside the array rejects while compiling
(`index-range`); any other index is checked at run time and a failure aborts, exactly as a run-time
zero divisor does. An element is assignable and every compound store form applies to it. Elements are
values: reading one copies it, and an array is copied by value when it is passed, returned or assigned
into a field.

An array is a value with an identity, like a record instance. A local binding to one is an alias, so a
write through either name is visible through both; passing an array to a word, returning it or storing
it into a field copies it. A record field or a parameter may be of array type, and an array element may
itself be an array, so `g[r][c]` indexes a grid.

### 8.4 Slices and strings

A slice is a runtime-length view of storage someone else owns. It is the one array-like type whose
length is not part of the type, which is what lets one word accept a sequence of any extent:

```
let sum_from(xs: slice(u32), i: u32, total: u32) : u32 = do
  if i == 0 then return total end
  return sum_from(xs, i - 1, total + xs[i - 1])
end

let sum(xs: slice(u32)) : u32 = sum_from(xs, xs.length, 0)
```

`slice(T)` is an ordinary word, like `ref`: applied to a type it produces a type, and applied to an
array it produces a view of that array.

```
let xs = [10, 20, 30]
let view = slice(xs)          -- slice(u32); view.length is three
let middle = view[1]          -- a run-time-checked element read
```

A view names storage, so section 8.2's lifetime rule applies unchanged. Local views are valid while
their arrays remain live; caller-derived and module-derived views may return. Returning a view of
the current invocation's own array rejects (`borrow-return`), and retaining it in longer-lived
storage rejects (`borrow-store`). A view never owns its target or keeps it alive.

A view is read-only. `xs[i] = v` writes the array; `view[i] = v` rejects (`not-a-place`), because the
view does not own the storage it names, and the bytes of a string literal are not writable.

Indexing is `view[i]` for a `u32` `i`. A known index outside the known length rejects while compiling
(`index-range`); any other index is checked when it runs and a failure aborts, exactly as a run-time
array index does. Reading an element copies it.


A **string** is a slice of bytes: `string` is `slice(u8)`. Text and bytes are therefore one mechanism
rather than two, and a string has a runtime length like any other view. Its bytes are bytes, not
characters: the source text is already the encoding, so a multi-byte character needs no escape and no
decoding. `"\xff"[0]` is the byte 255.

```
let greeting = "hello"
let count = greeting.length      -- 5
let second = u32(greeting[1])    -- 101
let same = "ab" == "ab"          -- true
```

A literal is written with double quotes. The escapes are `\\`, `\"`, `\n`, `\r`, `\t`, `\0` and `\xHH`,
which stands for one byte by its two hexadecimal digits. A raw newline inside a literal rejects, as
does an unterminated literal or an unknown escape (`lex-string`). A literal's bytes live in read-only
storage for the life of the program, so a literal is module storage: it may be copied, returned, stored
and compared freely, and two literals with the same bytes are one buffer.

A **byte literal** is one byte written readably: `'a'` is the byte 97, and it takes the same escapes
a string does, so `'\n'` is 10 and `'\x41'` is 65. It is a numeric literal, not a one-byte string, so
it adapts to the width it is used at and reports `u32` where no other operand decides. A byte literal
that is not exactly one byte rejects (`lex-string`): a multi-byte character is text, so it belongs in
a string.

A **long string** is written `[=[ ... ]=]` with any number of `=` signs, and the same number closes
it. It is raw (no escapes at all), it may span lines, and one newline immediately after the opening
bracket is dropped so a body can begin on the line below it. Because the level is chosen by the
writer, a body may contain any lower level's closing form. A long string needs at least one `=`: `[[`
is already an array whose first element is an array, and that must not become ambiguous.

Equality on `string` compares content rather than identity, and costs one length test before any byte
comparison. Ordering is not offered for `string`, and equality on any other slice type rejects: two
views may name overlapping storage, so identity is not observable and element-wise equality is not
offered by `==`.

No slice operation allocates, grows, frees or copies storage, and no string operation builds a new
string. Building a byte sequence writes into storage the program already has, which is what keeps a
view a view.

A slice is an indirection boundary, so a type may mention itself through one: `let node = { value:
u32, rest: slice(node) }` is finite for the same reason a pointer to itself is, because a view's own
size does not depend on its element.

### 8.5 Raw pointers

`ptr(T)` is an address the compiler does not track. It is deliberately a different type from `ref(T)`:
a reference keeps the guarantee of section 8.2, that its target outlives every use of it, and an
address that arrives from a host function cannot make that promise. Widening `ref` to carry both would
turn a checked borrow into a comment, so the two are separate types and a signature says which one it
means.

A pointer names no lifetime, so none of section 8.2's rules apply to it. It may be null, it may be
stored in module storage, it may be captured, returned, copied and compared, and it may outlive the
storage it points at. That is the point of the type: this is the part of the language where the
programmer is responsible, and the compiler says so by offering no rule to break.

```
extern let host_alloc(bytes: u32) : ptr(u8)
extern let host_free(p: ptr(u8)) : unit

let bytes(n: u32) : ptr(u8) = host_alloc(n * 4)
```

`p[i]` is the element at index `i` of `p`, for a `u32` `i`, and it has no bounds check: an unchecked
pointer does not carry a length. The element is assignable and every compound store form applies to
it, exactly as an array's element is. For `ptr(R)` whose `R` is a record, `p.field` selects a field and
a store through it writes that field, on the same route a reference uses.

A pointer is built in one of two ways. A foreign word may return one, and `ptr(place)` makes one from a
place the program already has:

```
let xs = [1, 2, 3]
let p = ptr(xs[0])          -- ptr(u32); the lifetime is written off here, deliberately
```

`ptr(place)` is the only place a lifetime is dropped, so it is the place to look for one. There is no
other conversion in either direction: `ref(p)` rejects, because an unchecked address must not become a
checked borrow. Equality on two pointers of one element type compares addresses, and `null(T)` is the
null `ptr(T)`.

```
let empty : ptr(u8) = null(u8)
let missing = bytes(4) == empty
```

Ordering, pointer arithmetic and any conversion between a pointer and an integer are not offered.
A pointer is an indirection boundary, so it is one of the ways a recursive type can be finite: `let
node = { value: u32, next: ptr(node) }` has the layout of a struct that holds a pointer to itself, and
a cycle that crosses only a `ptr` is accepted for the same reason one that crosses a `ref` is. A
by-value cycle that crosses none of them still rejects (`type-cycle`).

`p[i]` is the only arithmetic a pointer has, so one thing has one spelling. A pointer is not a
`slice`: a slice carries a length and a pointer does not.

### 8.6 Foreign declarations

A host function is declared with `extern`. It has no body, because its implementation is not written
in this language, so its result and every one of its requirements are written down:

```
extern let host_add(a: u32, b: u32) : u32
extern let host_scale(a: u32) : u32
```

The C symbol is exactly the name that is written. There is no alias and no `pub`, and the host
provides that symbol with that signature and C linkage. A requirement or a result must be a type this
language already has a C representation for, which is the same requirement an exported function's
signature meets, so a foreign declaration cannot invent a layout and "arbitrary foreign layouts" stays
excluded.

A foreign call is an effect the compiler cannot see into. It is never folded, so a constant argument
does not make it a compile-time value, and it exists only where there is code to emit: compile-time
VM execution leaves foreigns unbound and rejects the call (`foreign-effect`). A `unit` result is erased like
any other, so a call to a `unit` foreign word is a statement. There is no body to specialize, so a
partial supply rejects rather than producing a partial word.

A C prototype supplies no checked-borrow origin or retention contract. Foreign checked arguments
and checked results without such a contract reject (`borrow-unknown`); raw `ptr` interop remains
available and unchecked. The non-retaining callable-view ABI is not an implicit contract for
`extern`. Exported Let bodies have inferred contracts for Let callers. Their C prototypes do not
encode those contracts: C callers are responsible for argument lifetimes, retention requirements
and returned references.

A foreign declaration is not a Let callable body. Constructing a callable view or tagged callable
directly from one currently rejects (`foreign-callable`). An explicit Let wrapper supplies a body;
it is checked normally and cannot manufacture a borrowing contract for the foreign call.

### 8.7 Scoped resources

A callable requirement may be a word, so a resource can be acquired and released around a body without
an ownership system, a destructor or a keyword. This is the shape, not a built-in:

```
let with_region(r: type, bytes: u32, body: (ptr(u8)): r) : r = do
  let region = host_alloc(bytes)
  let result = body(region)
  host_free(region)
  return result
end

let sum() : u32 = with_region(u32, 8, |p: ptr(u8)| -> do
  p[0] = 7
  p[1] = 35
  return u32(p[0]) + u32(p[1])
end)
```

When the body is known code it is specialized, which is what keeps this cheap: the body's code is
emitted inside a per-invocation copy of the combinator, the call site is a direct call to that copy,
and no function pointer is involved. When the combinator's own body is foldable as well -- when it
has no effect of its own -- the whole call folds away and nothing at all is left, which is the case
measured for a body of pure arithmetic. So a known body costs at most one direct call; what it never
costs is a dynamic one. When the body arrives as a run-time view the combinator is an indirect call
and the release still runs. A `return` inside the body returns from the *body*, not from the
combinator, so the release runs on every normal path.

What this does not do is enforce anything. A pointer into the region may be returned, stored in module
storage or captured by a closure that outlives it, and the compiler accepts that, because a `ptr`
carries no lifetime to check and an abort does not unwind, so a release can be skipped. `with_region`
cleans up; it does not prevent misuse. This is the trade the design accepts, and it is the reason a
region's memory arrives as `ptr` and never as `ref`: a program that needs the guarantee writes its own
region type and keeps the pointer inside it.

The standard `std.memory` module supplies such a checked boundary: `with_buffer` keeps its raw
allocation private and lends a record of erased read/write method views. These views borrow real
local receivers/adapters and cannot escape the resource scope. Bounds failures are explicit results,
not raw accesses. Caller-derived results unrelated to the allocation may still return. This is the
ordinary storage-lifetime rule plus an audited acquire/lend/release implementation, not ownership
attached to a raw handle. Release runs on normal completion; aborts do not unwind.
`std.file.with_file` and `std.terminal.with_terminal` use the same rule for private descriptors
and terminal tokens. File close and terminal restore errors replace the body result. Shared
`std.bytes`/`std.stream` protocols and scoped string/argv readers do not add ownership types.
The fallible modules export `result(r)` type-producing words for explicit result annotations.

### 8.8 Deferred actions

`defer` attaches an action to the end of the block it appears in, so a release does not depend on
remembering it at every way out:

```
let sum() : u32 = do
  let p = host_alloc(8)
  defer host_free(p)
  p[0] = 7
  p[1] = 35
  return u32(p[0]) + u32(p[1])
end
```

The action is a call statement, and it is written where the bindings it uses are in scope. Its callee
and arguments are evaluated where the `defer` is written, so the action runs with the values the
program had at that point and not with whatever the names mean later: a mutable field read at the
`defer` is a snapshot, exactly as every other read is. The call itself happens when control leaves the
block, after the returned expression has been evaluated and before the value leaves, and several
deferred actions in one block run in reverse order of their `defer` statements.

Every way out of the block runs them: falling off the end, a `return`, the end of a statement
conditional's arm inside it, and a tail self-call. A block with a deferred action therefore does not
turn a tail self-call into a loop, because the action has to run after the call returns and before the
value leaves, which is not the order a back edge would give.

`defer` is a statement form and not a type, so it tracks nothing: it does not prevent the resource
from being used after the action runs, it does not follow a copy of anything, and it does not run at
all when an abort ends the process. It is section 8.7's shape, written where the resource is acquired.
Ownership, moves and automatic destruction remain excluded; a deferred action is a release point the
program placed, not one the compiler inferred.

## 9. Callables, captures and ownership

Known executable arguments retain code identity and specialize. Unknown runtime implementations
are checked against a complete calling signature and use a non-retaining callable view. There is
no `dyn` keyword; binding time and representation requirements decide which is needed.

A conditional whose two arms are callables of one signature but different code joins them into a
tagged callable: the tag names the code and the payload is that code's environment. A call on such a
value tests the tag and then runs that arm's own body, so the call is still direct and no function
pointer is involved. Both arms must be callable the same way; a word arm also needs declared result
types, because a tagged call site has no annotation to fall back on, and a partially applied arm
needs static arguments. An arm that borrows storage has no representation in a tagged value, because
the value holds its environments by value.

A tagged callable owns its environments like any other owned callable, so it may be returned or
stored. It cannot be erased into a bare signature: a view does not retain the environment that
carries the tag, so that conversion rejects (`callable-erase`) rather than dangling. Erasing a
callable whose arm is already known is ordinary erasure of that one callable.

Lambda captures follow lexical bindings. A captured scalar/read snapshot is an immutable value.
Capturing a mutable record instance or a method retains its actual place; copying its binding does
not secretly copy its state. Owned value captures form a by-value environment. A closure containing
any receiver/place borrow or another borrowed callable is borrowed.

Owned closures may return and copy when their retained access outlives the destination. A closure
with no captures is pure code: its invocation pointer has a null environment and needs no adapter.
By-value environments may contain checked references or slices, and nested owned closures follow
the same lifetime rule.

Place-capturing closures and method values can be invoked locally or passed to non-retaining
callable parameters. Returning or nesting a place-capture environment still needs an unsupported
representation and rejects (`callable-capture`); this is not a second lifetime rule.

A named word or schema method compiled in its own function cannot implicitly reuse another
function's runtime values or places. Such captures need a represented environment, such as lambda
captures or receiver fields; unsupported cases reject `callable-capture`. Module bindings and
static copied values remain usable. A hidden concrete capture must still be live when accessed.

A nonempty callable view has a separate local adapter, even when its receiver is global. A record
holding that view retains the adapter and cannot outlive it. Returning a caller-provided view
preserves its caller origin. An opaque signature does not supply an origin contract for a checked
result produced by calling the view; such an unproved result rejects.

A result annotation that is a signature checks callable shape; it is not permission to erase an owned
environment into a dangling pointer. A concrete owned result also needs a known code/environment ABI.
If a recursive result contract cannot establish that ABI, compilation rejects the unresolved recursive
representation rather than pretending the signature alone specifies ownership or environment size.

## 10. Results, recursion and generics

Result annotations constrain every reachable result vector. Without an annotation, acyclic bodies
infer their result types and any common static components. A known condition need not evaluate an
unselected branch, but all returning arms of an unknown condition must agree as specified above.

Every word in a residual recursive strongly connected component requires a complete result contract,
from its definition/binding annotation or the module's results table. All applicable contracts must
agree. This intentionally replaces the earlier inference-only-when-ungrounded rule.

Static recursive evaluation can run without a residual result contract. A source recursive function whose static arguments change may produce distinct specialization keys; compilation continues until the evaluation terminates or the build is interrupted. There is no depth, step or specialization-count cutoff.

A long-running static evaluation reports the binding being evaluated and its current source position. Interrupting compilation reports the active static word stack with source positions. These are visibility and interruption diagnostics, not language limits; no timeout or work count changes whether source is accepted.

Generics are ordinary words with type parameters:

```
let identity(t: type, x: t) = x
let twice(t: type, f: (t): t, x: t) = f(f(x))
let identity_u32 = identity(u32)
```

There is no implicit generic parameter inference. A runtime value cannot supply type. Static types
are compile-time values and may be returned by private helpers when all their returning paths agree;
they cannot occupy an external C value slot. Public callable signatures must have a closed runtime ABI.

## 11. Modules and export configuration

A Let source file uses the `.let` extension. An SLet source file uses `.slet` and must satisfy the strict ownership and static-type restrictions in this document. Either file contains top-level let declarations followed by
exactly one final module export declaration:

A file that defines a top-level word `main` may instead omit the export configuration; `main` is
then the only export. That is what lets either source profile be written as a program rather than a
module, and a host runs it by calling `main`.

```
return {
  types = { rng },
  functions = { next32, seed, skip },
  results = { [endo] = u32 },
}
```

This final construct is MODULE CONFIGURATION, not a general source record expression or a runtime
return. Its brace/list/bracket forms are parsed by a separate configuration grammar. It is never
stored in a Let record or emitted as a C value. There are no strings, arrays or general indexing
operators introduced into source expressions by this notation.

Allowed sections are types, functions and results, each optional and present at most once. Unknown
sections reject. List entries in types/functions are names, or named aliases:

```
return {
  functions = { next32, d6 = roll(6) },
  types = { rng, counter = some_counter },
  results = { [helper] = (u32, bool) },
}
```

A bare identifier exports under its own spelling. `alias = expression` gives an explicit public name;
its expression must yield a known type or executable selection appropriate to the section. Duplicate
public names within a section reject. Qualified selections require aliases, such as `draw = rng.draw`.
Method exports expose their receiver as the C entry's receiver parameter, not as an invented source
argument. A view bound to mutable module-evaluation storage cannot be exported as implicit C global
state.

Results entries use `[word-or-signature-expression] = result-spec`. A result-spec is one type, an
ordered parenthesized type list, or () for unit. Known code contracts and structural signature contracts
are distinct: a signature entry constrains that calling interface; a code entry constrains that word
specialization and compiler-derived refinements. Explicitly partial-specialized words have their own
contracts; implementation must check all applicable contracts and reject contradictions, never silently
override an annotation. No static-result assertion syntax is introduced by this table.

Module initialization is compile-time execution over concrete values. In the ABC implementation, executable initializer code is verified bytecode run by a compile-time VM; interpreted, eager-JIT and lazy-JIT staging policies have identical semantics. An initializer
may read module storage and build temporary records. A module-level mutable instance that runtime
code refers to also gets named file-scope storage, and the artifact emits an exported
`void let_init(void)` that assigns each such object its start value. A custom host calls it
explicitly; the standalone `--program` profile invokes it before exported `main():u32`.
An initializer may also write module storage, so a mutable instance's start value can depend on the
initialization that preceded it.
Returned exported code cannot retain a mutable module instance without a specified runtime storage
interface. Immutable scalar snapshots and static definitions are valid captured metadata. Top-level
initializers are evaluated once, eagerly, in declaration order; a forward reference demands a later
initializer early. Dependency cycles reject.

A module may use another with `use <dotted name>` at the top of the file. The name is a path next to the importing file with dots as separators. An SLet importer resolves only `.slet`. A Let importer may resolve `.let` or `.slet`; if both files exist, import rejects with `import-ambiguous`. Thus `use util.helper` can read `util/helper.slet` from either profile, or `util/helper.let` from Let. The last segment is the namespace through which the module's exports are reached:

```
use util
let twice(n: u32): u32 = util.helper(n)
let origin(): util.point = util.point { x = 1, y = 2 }
```

What a module offers is exactly its export list, so `util.helper` and `util.point` work only if the
used file exports them; any other name stays private to that file. A used module's own imports are
resolved first, a module is loaded once however many files use it, and a cycle rejects
(`import-cycle`). Modules compiled together share one translation unit and one initialiser, so
file-scope mutable storage in a used module is initialized by the same `let_init()` call
(made by the custom host or the standalone program startup). Only a file can use an import,
because a source string has no directory to resolve against.

The reserved `std.*` namespace selects bundled standard modules instead of relative files.
`use std.memory` binds `memory` to the scoped-memory module. An unknown standard module rejects;
it cannot silently select a file from the working directory. Standard sources use the same frontend,
profile-specific ownership checks and VM-backed static execution as other modules. The bundled modules are `std.bytes`,
`std.memory`, `std.text`, `std.stream`, `std.file`, `std.terminal` and `std.program`; their APIs
and normal-completion cleanup contracts are documented in `stdlib/README.md`.
CLI `--program` / `artifact:program()` wraps an exported zero-runtime-input, single-`u32`-result
`main` with POSIX startup, module initialization and the embedded native runtime. This is an emission
profile, not new source syntax or permission to pass checked borrows to unknown foreign code.

There is no `pub` syntax in this version. There is no traps section: known zero division
rejects, dynamic zero division aborts. Configurable trap handling needs a separate language decision.

## 12. Grammar outline

This grammar fixes the previously overlapping forms. Expression productions use the precedence table
in section 7. Semantic arity/staticness/type checks are not disguised as parser decisions.

```
module          := top-let* export-config EOF
local-let       := named-definition | keyed-definition | value-binding | foreign-declaration
named-definition:= 'let' Name parameters result-annotation? '=' body
keyed-definition:= 'let' Name keyed-parameters result-annotation? '=' body
keyed-parameters:= '{' (Name ':' type-expression) (',' Name ':' type-expression)* ','? '}'
-- A host function: no body, so the result is required rather than optional.
foreign-declaration := 'extern' 'let' Name parameters ':' result-spec
value-binding   := 'let' binder (',' binder)* '=' expression-list
binder          := Name (':' type-expression)?
parameters      := '(' parameter-groups? ')'
parameter-group := Name (',' Name)* ':' type-expression
result-annotation := ':' result-spec
result-spec     := type-expression | '(' type-list? ')'
body            := expression | 'do' statement* 'end'
statement       := local-let | field-store | call-statement | return-statement | defer-statement
                 | 'if' expression 'then' statement* ('else' statement*)? 'end'
return-statement:= 'return' expression-list?
defer-statement := 'defer' call-statement
expression-list := expression (',' expression)*
lambda          := '|' lambda-parameters? '|' '->' body
lambda-parameters := parameter groups, with annotations optionally supplied by context
postfix         := atom (arguments | initializer | '.' Name)*
string-literal  := '"' (escape | byte-except-quote-or-newline)* '"'
float-literal   := digits ('.' digits)? exponent? | digits '.' digits exponent?
exponent        := ('e' | 'E') ('+' | '-')? digits
byte-literal    := "'" (escape | byte-except-quote-or-newline) "'"
long-bracket    := '[' '='+ '[' .* ']' '='+ ']'   (same number of '=' on each side)
long-comment    := '--' '[' '='* '[' .* ']' '='* ']'
arguments       := '(' expression-list? ')'
initializer     := '{' (Name '=' expression) (',' Name '=' expression)* ','? '}' | '{' '}'
schema          := '{' schema-members? '}'
schema-member   := Name ':' type-expression | Name parameters result-annotation? '=' body
if-expression   := 'if' expression 'then' expression 'else' expression
signature       := '(' type-list? ')' ':' result-spec
```

Top-let has local-let's syntax but module visibility rules. Optional semicolons delimit complete
items. Delimited comma lists permit a trailing comma; empty parameter/argument/lambda lists are valid.
Parameter groups end after an annotation; a following comma begins the next group. For instance,
`(a, b: u32, c: bool)` is two groups. In a binding list, annotations belong to individual binders.

A parenthesized comma sequence is legal only as a signature side/result-spec, never as a general
expression. Parser lookahead over balanced parentheses can recognize an input type list followed by
an arrow; scalar grouping otherwise adjusts its expression to one value. Pipe lambdas remove the need
to guess whether a name before an arrow binds a variable or denotes a type.

type expressions use expression syntax but must evaluate to a type/calling requirement. There is no
separate capitalization rule or implicit conversion of a value into its type. Their surrounding
colon, arrow or list delimiter determines where they end. A result-spec's comma list is distinct
from a single signature-valued result, e.g. `: ((u32): u32)`.

`if a then if b then x else y else z` associates each else with its structurally pending expression
conditional. Statement conditionals have explicit end tokens and cannot consume an expression's else
by switching grammar forms. Semicolons are required to prevent any otherwise valid postfix continuation
across an intended item boundary. Full grammar/parser tests must cover these boundary cases.

## 13. Worked example

```
let xorshift(a, b, c, s: u32) : u32 = do
  let s1 = s ~ (s << a)
  let s2 = s1 ~ (s1 >> b)
  return s2 ~ (s2 << c)
end

let next32 = xorshift(13, 17, 5)
let seed(s: u32) = if s == 0 then 2463534242 else s

let skip(s, n: u32) : u32 = do
  if n == 0 then return s end
  return skip(next32(s), n - 1)
end

let step(s: u32) : (u32, u32) = do
  let t = next32(s)
  return t, t
end

let roll(bound, s: u32) : (u32, u32) = do
  let t = next32(s)
  return t, t % bound + 1
end

let d6 = roll(6)
let d20 = roll(20)

let rng = {
  state: u32,
  draw() : u32 = do
    state = next32(state)
    return state
  end,
}

let roll_then_step(s: u32) : (u32, u32) = do
  let next, face = d6(s)
  return next32(next), face
end

return {
  types = { rng },
  functions = { seed, next32, skip, step, roll, d6, d20, roll_then_step },
}
```

## 14. Explicit exclusions and validation

No juxtaposition, layout blocks, implicit block returns, bare-name lambdas, mutable lexical bindings,
general borrow parameters, reference arithmetic, null or dangling references, ownership through a
reference, residual partial application, general tuple values, sparse or growing arrays or a
zero-length array, record-value literals without a
schema, non-exhaustive or recursive pattern matching, implicit type parameters, arbitrary foreign
layouts, `pub`, selective or re-exporting imports and configurable traps are implied by this syntax. A reference is a checked
borrow of a target that outlives it, not a pointer type a program may fabricate. A `ptr` is the type
that may be null or outlive its target, and it is not a `ref`; ownership, uniqueness, moves and
automatic destruction are not offered either, so a scoped resource is released by a word that takes a
body (section 8.7) rather than by a destructor.

A slice is a view, not a container. No operation allocates, grows, frees or copies storage, so a
zero-length *type* still rejects even though a runtime length of zero is an ordinary empty view.

Required syntax/semantic tests include:

- whitespace/one-line equivalence, explicit separators, maximal tokens and comments;
- pipe lambdas versus lowercase type aliases/signatures; grouped and nested signature arrows;
- shared parameter annotations versus per-binder annotations; contextual lambda typing;
- static partial supply, residual saturated calls, overapplication and nullary calls;
- multiple-result forwarding/grouping, unit fill, exact return contracts and result annotations;
- expression/statement conditionals, early returns, short circuit and child lexical scopes;
- immutable bindings versus record stores; compound target/RHS evaluation order;
- sum construction by supply and by positional application, exhaustive matching, known versus
  runtime tags, erased `unit` alternatives and payload type mismatches;
- keyed partial supply versus mutable fields initialized by a saturated constructor;
- owned scalar captures, borrowed receiver captures and invalid escapes;
- lazy mutually visible module definitions, initializer cycles and exported runtime ABI demands;
- recursive contract requirements and conflicting annotation/configuration contracts;
- configuration forms rejected in runtime expressions and unknown module sections rejected.

This specifies the language choices; it does not replace executable parser, evaluator and C differential
tests. `architecture.md` defines the implementation obligations supporting them.

## 15. Progressive typing and managed ownership (`.let`)

Let `.let` is the main language profile. It inherits the grammar, values and operation semantics of the statically typed core, adds progressively optional annotations and dynamic operations, and replaces the lexical ownership restrictions of SLet with managed GC reachability where storage can escape.

SLet `.slet` is the strict static sublanguage. The two profiles have one grammar, arithmetic and call semantics. Let permits default-`any` annotations, open words and GC-managed ownership; SLet rejects those capabilities and therefore needs no managed allocation or GC roots. A program pays for dynamism and collection only when its selected source profile requires them.

The collector is a semantic feature, not merely an optimization. Let code is not subject to SLet borrow-escape restrictions for Let-owned storage: address-taken values can be allocated or promoted into collected storage, and managed references, views and closures can be returned, stored and captured. SLet keeps stack-disciplined ownership and lifetime proofs.

### 15.1 Let files and the `any` type

A `.let` file accepts all SLet constructs with the same observable operation semantics. Section 15.8 replaces SLet storage-lifetime rejection with GC reachability for Let-owned values, and the profile adds the predefined binding `any` and the forms in this section.

`any` is the type of a dynamic value: a value whose type is carried with it at run time instead of being known while compiling. It is a predefined binding like `u32` or `string`, not a keyword, so section 9 still holds: there is no `dyn` keyword. `any` is predefined only in `.let` files. An `.slet` file that names it rejects (`slet-forbidden`), so no SLet module can hold a dynamic value by accident.

SLet is a restriction of Let, and profile changes preserve accepted behavior:

- **Renaming `.slet` to `.let`** preserves observable results, although address-taken storage may use a collected representation.
- **Renaming `.let` to `.slet`** either preserves observable results or rejects. It rejects code that relies on `any`, a Let-only form, managed allocation, or a reference/view/closure escaping its lexical SLet lifetime.
Porting Let to SLet therefore requires annotations and removal or redesign of every GC-dependent escape; renaming alone is not sufficient.

### 15.2 Unannotated parameters, keys and lambdas

In a `.let` file, `any` fills exactly the places where the statically typed core requires an annotation and none is written. Everything that the core already infers is still inferred. Adding an annotation replaces a default-dynamic boundary with an earlier check and enables specialization or unboxing; it does not select another evaluator or VM execution policy. If the added checks succeed, observable operation semantics remain unchanged.

| Place | `.slet` file | `.let` file |
| --- | --- | --- |
| Named-definition parameter group (section 2) | must be annotated | an unannotated group is `any` |
| Keyed requirement (section 2) | must be annotated | an unannotated key is `any` |
| Schema field (section 8) | must be annotated | a field name without `:` is `any` |
| Lambda parameter with no expected signature (section 4) | rejects | `any` |
| Result contract of a recursive word (section 10) | required | defaults to one `any` result |
| Local binding initializer | inferred | inferred, unchanged |

The grouping rule is unchanged: adjacent names share the following annotation. In a `.let` file, trailing names with no annotation form one more group, typed `any`. So `(a, b: u32, c)` declares two `u32` parameters and one `any` parameter.

```
let add(a, b) = a + b                 -- (a, b: any)
let scale(k: u32, v) = v * k          -- v is any, k is u32
let distance { x, y } = x * x + y * y -- keys x and y are any
let enemy = { hp, speed: u32 }        -- hp is an any field
let inc = |x| -> x + 1                -- standalone lambda, x is any
```

A local binding keeps the type of its initializer. `let t = next32(s)` is `u32` in Let exactly as in SLet, and only an initializer of type `any` makes an `any` binding. `let v: any = 5` converts explicitly. Bindings stay immutable, as section 2 says: Let keeps changing state in open words (section 15.4), never in rebound names.

### 15.3 What an `any` holds and how it behaves

An `any` holds one typed value together with its type. A `u8` stored in an `any` is still a `u8`, and every operation on it follows the core language's rules for `u8`. Dynamic values do not bring a second arithmetic.

**What it may hold.** Every value with a run-time representation: each integer type, `f64`, `bool`, `unit`, strings, sum values, records and arrays (copied in, by value), words, open or closed (sections 15.4 and 15.5), managed `ref` and slice values, and raw `ptr` values. Every `ref` or owned-storage slice that is visible to Let is managed, and boxing it retains its collected owner. A SLet or foreign borrowed view cannot enter managed Let storage as such: the boundary copies/promotes its data or rejects the conversion. A `type` value may not be held, as section 10 already says for every run-time slot.

**Literals.** A literal that becomes an `any` with no other operand to adopt takes `i64`, or `f64` for a float literal. Where the core language's adoption rule applies, it still decides: in `x + 1` with `x` holding a `u8`, the `1` is a `u8`. Mixing stays as strict as in static Let: an `i64` and a `u32` meet only through an explicit conversion, such as `i64(face)`, because silent signedness mixing is exactly what the core language rules out.

**Static rejections become run-time aborts.** An operation with an `any` operand checks, when it runs, exactly the rules the core language checks while compiling. What would reject aborts, under the same code name: mixing signed and unsigned is `type-mismatch` either way. An accepted operation means the same thing it would mean statically, and its result is an `any`.

**Conditions.** A condition that is an `any` must hold a `bool`, or it aborts. There is no truthiness, as section 7 says.

**Equality.** `==` and `!=` on `any` values compare type first: values of different types are unequal, without an abort. Integers compare by numeric value whatever their width or signedness, so a u32 3 equals an i64 3, matching how integer keys work (section 15.4). An integer and an f64 are unequal. Other values of one scalar type compare as section 7 says, strings by content, and words by identity. Ordering still requires one type, so `<` on values of different types aborts.

**Calls.** Calling an `any` checks that it holds a word and that the supply fits, then follows section 3. Too many arguments abort, as overapplication rejects statically. A dynamic terminal may declare surplus results, which a scalar or shorter binding context discards after execution. If it declares fewer results than the context requests, callable metadata causes `dynamic-signature` before the terminal runs; dynamic calls never invent `unit` as a nil-like missing value. Section 6's binding-list unit padding applies only when the expression's result vector is statically known.

### 15.4 Open words

Let needs values whose fields change at run time, and they are not a new concept: they are words. In the core language a word already has fields, its supplied requirements, and an optional terminal, its behaviour. An **open word** is a word whose fields may be read, stored and added at run time. Every word the core language describes is a closed word.

```
let e = { hp = 10, name = "golem" }   -- an open word: two fields, no terminal
let p = point { x = 3, y = 4 }         -- still a record, exactly as in the core language
```

**Building one.** In section 8, a keyed supply needs a word before it, which is why a bare `{x=3}` is excluded. In Let, a bare supply supplies a new, empty open word, so `{ hp = 10 }` builds an open word with one field. `open()` builds one with no fields. Bare `{}` stays the empty record schema.

The separator still decides, as section 8.1 puts it: `name: type` defines a requirement and `name = value` supplies one. So `{ hp: u32 }` is a schema in both kinds of file, and `{ hp = 10 }` is an open word only in Let.

**Open words are references; records are values.** Passing, returning or storing an open word passes the same word, and two names for it observe each other's writes. A record keeps the core language's value-copy semantics in Let too. This difference is why open words are collected (section 15.8).

**Fields.** `w.x` reads a field and `w.x = v` stores one; storing to a name the word lacks adds it. Every compound store from section 7 applies, with the same evaluation order. A field holds any value an `any` may hold, including another word.

**Computed keys.** `w[k]` selects by a run-time key, and `w.name` is `w["name"]`. A key is a string, an integer or a `bool`. Integer keys compare by numeric value whatever their width, so `w[1]` names one field however the `1` was typed. Any other key aborts (`key-type`).

**Missing fields.** Reading a field the word lacks aborts (`field-missing`), consistent with Let having no nil. Let code tests first with `has(w, k)`.

**Field order and storage.** An open word is one collected ordered map. It keeps keys, values, a hash index and insertion order in storage owned by the word; there is no separate shape-tree or dictionary-mode transition. `key(w, i)` returns the key at zero-based insertion index `i`, so iteration is deterministic. Adding a missing key appends it, replacing a value preserves its position, and removal closes the insertion-order gap. All key storage dies with the word. A VM-private numeric layout token changes after structural mutation and permits constant-field caches without owning or interning the keys.

| Predefined word | Result |
| --- | --- |
| `open()` | a new open word with no fields and no terminal |
| `has(w, k)` | `true` when `w` has a field under key `k` |
| `remove(w, k)` | removes that field; `unit` |
| `count(w)` | the number of fields, as `u32` |
| `key(w, i)` | the key of the `i`-th field in insertion order; an `i` at or past `count(w)` aborts (`index-range`) |

### 15.5 Behaviour: words that hold state and run code

An open word may also have a terminal, so one value can hold state and run code, the way a callable table does in other languages. Let needs no separate callable kind for this: it is a word whose fields happen to be open.

**Run-time supply opens a word.** Section 3 requires partially supplied values to be static, because partial supply is specialization and never allocates. Let may also supply run-time values, positionally or by key. Doing so builds an open word: the supplied requirements become its fields, and it keeps the word's terminal and its remaining requirements.

```
let next32 = xorshift(13, 17, 5)               -- static supply: a closed word, as in the core language
let gen = xorshift { a = pick(), b = 17, c = 5 } -- run-time supply: an open word
let shift = gen.a                              -- a supplied requirement is a field
gen.a = 7                                      -- changes what gen computes from now on
let t = gen(s)                                 -- supplies s and runs the terminal
```

The terminal reads its supplied requirements from the word's fields at each call, so storing to one changes what the word computes. A static supply still specializes exactly as the core language says and allocates nothing. A closed word's supplied requirements stay readable and non-writable (`readonly-field`), as section 8 already says for keyed words.

**Keyed supply on every word.** Let may supply any word's requirements by name, in any order: `xorshift { a = 13, b = 17, c = 5 }` is the same word as `xorshift(13, 17, 5)`. Supplying a name that is not a requirement adds a field.

**Supplying an open word copies it.** `w { hp = 50 }` on an open word builds a new open word: a shallow copy of `w`'s fields and terminal, with the supplied fields replaced or added. `w` itself is unchanged. In Let supply never mutates, and storing already has its own form, `w.x = v`. The copy does not refer back to `w`: there is no delegation between words.

```
let slime = { hp = 10, name = "slime" }
let big = slime { hp = 40 }         -- a new word; slime.hp is still 10
```

**Calling.** Calling an open word supplies its remaining requirements and runs its terminal. An open word without a terminal aborts when called (`no-terminal`).

**Methods.** Let may add a method to an open word with a field path as the name. The body sees the word's fields by bare name, exactly as a schema method sees its receiver's fields in section 8, and selecting the method binds the word as its receiver:

```
let enemy = { hp = 10, speed = 2 }

let enemy.hit(damage) = do
  hp -= damage
  return hp <= 0
end
```

A plain word stored in a field is called with no receiver.

**One concept, three states.**

| Word | Fields | Terminal | Example |
| --- | --- | --- | --- |
| closed | fixed when compiling; readable | a body, or a schema's constructor | `next32`, `point` |
| open, no terminal | run-time; stored and added | none | `{ hp = 10 }` |
| open, with a terminal | run-time; stored and added | the body it was opened from | `xorshift { a = x, b = 17, c = 5 }` |

Freezing an open word closes it again (section 15.7).

### 15.6 Type tests, conversions and the boundary

Let adds no keywords for types. Tests and conversions are ordinary words, as `ref`, `slice` and `oneof` are in the core language.

**Tests.** `is(x, t)` is `true` when the `any` `x` holds a value of type `t`. `t` is any type expression: `is(x, u32)`, `is(x, string)`, `is(x, point)`. `open` is also a type, so `is(x, open)` tests for an open word.

**Conversions.** the core language already writes a conversion as type application, as in `u32(greeting[1])`. Applied to an `any`, the same form converts at run time by the same rules: a range check where a conversion can lose a value, a reinterpretation where only signedness changes. A value that cannot convert aborts (`type-mismatch`). `point(w)` with `w` an open word builds a fresh record by copying the schema's data fields out of the word, each converted to its field's type; a missing field aborts (`field-missing`).

**Annotated bindings convert.** `let p: point = t` means `let p = point(t)`, and an annotated parameter converts its argument the same way. A value of any static type converts to `any` implicitly wherever an `any` is expected.

**The boundary.** A dynamic value reaches typed code through a checked conversion, and every conversion that produces a record copies. Typed code defined in a `.let` module remains GC-aware even when none of its source types contains `any`: its references, slices, strings and callable environments are managed and traced. An SLet callee keeps its ordinary borrow contract internally. The adapter roots Let arguments for the call and converts a returned SLet borrow into Let ownership only by preserving a traceable owner or materializing a collected copy; an unowned borrow is not exposed as a Let `ref`.

| Direction | How | Cost |
| --- | --- | --- |
| static to `any` | implicit, wherever an `any` is expected | a tag; a record or array is copied in |
| `any` to static scalar | `u32(x)`, an annotated binding or parameter | one run-time check |
| open word to record | `point(w)` | a checked copy of each data field |
| `any` to word with a signature | an annotated binding: `let f: (u32): u32 = x` | an arity/signature check and a managed typed callable handle |

A callable converted inside Let keeps its collected environment reachable and may be returned or stored. When passed to an SLet parameter explicitly declared non-retaining, the boundary lends that callable only for the call; this SLet ABI fact does not impose a lifetime restriction on the Let handle.

### 15.7 Freezing

`freeze(w)` closes an open word: its fields become fixed, and it is a closed word from then on, exactly like one the core language describes. Every open word reachable from its fields is closed with it. Freezing is how Let turns what it built into constants.

```
let config = freeze {
  rate = 48000,
  gain = 3,
  voices = { lead = 4, pad = 8 },   -- closed too: reachable from config
}
```

After freezing, a store, an added field or a `remove` aborts (`frozen-store`). A frozen word keeps its terminal, so a frozen word with behaviour is an ordinary closed word whose supplied requirements are fixed. Freezing a closed word does nothing.

**Frozen fields are constants.** Nothing can change a frozen word, so reading its fields is a known value wherever the word itself is known. A word frozen during module initialization is a compile-time constant, folded like any other module constant. A word frozen at run time is constant from that point on. There is no separate end-of-initialization marker: module initialization is the boundary between building and running.

**Freezing preserves managed ownership.** A frozen word remains collected when created at run time and may still contain managed references to other frozen values. Freezing removes mutation and permits constant reads; it does not convert GC ownership into a SLet borrow or require a copy merely to keep the value alive. A conversion to an SLet record still copies at the language boundary.

### 15.8 Memory: the collector

Let files may allocate, and a stop-the-world tracing collector reclaims what they allocate. This is the deliberate Let ownership model, not an implementation convenience. SLet lifetime rejection is not applied to Let-owned references merely because the same `ref`, slice or callable syntax also exists in `.slet`.

**What is collected.** Open words, capturing lambdas, built strings, values copied into `any`, and typed Let storage whose reference, view or capture can escape. The compiler allocates such backing storage in the collected heap before publishing an address; it does not relocate an already exposed stack address. A managed reference, slice or callable traces its backing object or environment, so reachability—not lexical nesting—sets its lifetime.

**What the collector guarantees.** A managed value lives while reachable through an `any`, managed typed value, stack, closure, open word or module root. Its address is not observable. The initial ABC collector is non-moving, but language semantics also permit a future collector to update managed references and views. `ptr(place)` on collected storage rejects (`ptr-collected`) because raw pointers are untraced and cannot be updated. The collector runs no finalizers; files and other external resources still require the scoped words of section 8.7 or `defer`.

**How this loosens the core language.**

| SLet `.slet` rule | In Let `.let` |
| --- | --- |
| No operation allocates implicitly | building an open word, a capturing lambda, a string, a boxed record or escaping typed storage allocates |
| Partial supply never allocates (section 3) | a run-time supply allocates an open word |
| Nothing outlives its activation except module storage | Let-owned address-taken storage is promoted and lives while reachable |
| Returning or storing a local `ref` or slice rejects | a managed reference or view retains its promoted backing object and may escape |
| A place-capturing closure cannot escape (section 9) | captures of Let-owned places are represented in a collected environment and may be returned or stored |

For example, this is valid Let; the same body in SLet rejects with `borrow-return`:

```text
let cell = { value: u32 }
let keep(): ref(cell) = do
  let x = cell { value = 1 }
  return ref(x)                 -- x was allocated in managed storage
end
```

**What remains unmanaged.** A raw `ptr` never becomes a GC root. Foreign memory is exposed to Let as `ptr` or copied into managed storage, not represented as a managed Let `ref`. Likewise, an unowned borrow returned by SLet code must be tied to a traceable owner or copied before it becomes a Let value. `defer`, scoped external resources and abort behavior are unchanged; collection supplies memory lifetime, not finalization or resource ownership.

**When collection runs.** A collection starts in an allocation slow path. If the host requests collection, the VM starts it at the next generic or allocating bytecode boundary by switching dispatch state; it does not stop in the middle of a nonallocating typed instruction. The verifier computes a transitive `allocation-free` fact for each function from its instructions and callees, so this guarantee is checkable and is not inferred from the absence of `any` in source types. Typed `.let` code can contain managed allocation even without `any`; a statically typed Let function can still call an allocating Let callee. A host request may remain pending indefinitely in a verified allocation-free loop, which is harmless because that loop creates no collectible garbage. The request runs at the next eligible boundary. A pause lasts in proportion to the live collected data.

### 15.9 Managed strings

Let may build strings, and a built string is collected. It is still a `string`, so everything section 8.4 says about reading one still holds: bytes not characters, `s.length`, `s[i]`, and equality by content. Converting a managed Let string or substring to `any` retains its owner and does not copy its bytes. A SLet or foreign borrowed string is copied once before entering managed Let storage.

**Concatenation.** `a .. b` builds a new collected string from two strings. Both operands must be strings; there is no implicit conversion, as everywhere in Let. `text(x)` is a predefined Let word that builds the decimal text of a number, or `true` and `false` for a `bool`.

```
let label(e) = e.name .. " has " .. text(e.hp) .. " hp"
```

`..` binds looser than additive operators and tighter than shifts, and it is right-associative. It lexes unambiguously: by longest-token matching `..` is one token, and `1..2` is `1`, `..`, `2`, because section 1 already requires a digit on both sides of a float's point.

**Into typed code.** A collected string or slice used by typed code in the same Let module retains its backing object and may be stored or returned under the managed ownership rules of Let. Across a call into an SLet word, the adapter roots the backing object for the call and satisfies that word's borrow contract. A result crossing back into Let retains a traceable owner or is copied; SLet borrowed storage is never exposed as an unowned Let reference.

### 15.10 Modules and exports

Both kinds of file use the module system from section 11, with three additions.

**Finding a module.** An SLet importer resolves `use util.helper` only as `util/helper.slet`. A Let importer considers `util/helper.let` and `util/helper.slet`; if both exist, import rejects (`import-ambiguous`) instead of choosing silently.

**Profile direction.** A `.let` file may import either profile. An `.slet` file may import only `.slet`; importing `.let` rejects (`slet-import`). Let-to-SLet calls use an ownership adapter: managed arguments and results stay rooted for the call, while the SLet body keeps its verified borrow contract and cannot retain a view beyond that contract. A future explicit embedding adapter may expose selected Let operations to SLet, but ordinary SLet imports never acquire `any`, managed references or GC obligations.

**Exports to C.** An `any` has no C representation, so a C export's signature may not contain one (`abi-any`). A managed `ref`, slice backing pointer or collected callable environment also cannot cross as a naked C pointer (`abi-managed`); an export must copy data, use raw `ptr` under an explicit host lifetime contract, or expose an embedding handle API. A host otherwise calls Let code through static value signatures. The `--program` profile still requires an exported `main` returning one `u32`.

**Module storage.** A module-level open word follows section 11's rule for mutable module instances: it gets file-scope storage, and `let_init` gives it its start value. A module-level frozen word is a constant instead, like any other immutable module value.

### 15.11 Grammar additions

These productions extend section 12 in `.let` files only. A `.slet` file parses exactly as section 12 says, and a form below rejects there (`slet-forbidden`).

```
-- a trailing parameter group may omit its annotation; it is then any
parameter-group   := Name (',' Name)* (':' type-expression)?
keyed-parameters  := '{' keyed-param (',' keyed-param)* ','? '}'
keyed-param       := Name (':' type-expression)?
schema-member     := Name (':' type-expression)? | Name parameters result-annotation? '=' body
-- a method added to an open word by a field path
method-definition := 'let' Name '.' Name parameters result-annotation? '=' body
local-let         += method-definition
-- a bare initializer supplies a new open word
atom              += initializer
-- concatenation, between additive and shift
concat            := additive ('..' concat)?
```

The precedence table in section 7 gains one row:

| Level | Operators | Associativity |
| --- | --- | --- |
| concatenation (between additive and shift) | `..` | right |

The lexer is the same for both kinds of file: `..` is one token everywhere, and only the parser decides whether it is allowed. A schema member and a method member still differ by the `(` that follows the name.

Let predefines these bindings, reserved at module level as section 1 reserves the core bindings:

| Binding | Section |
| --- | --- |
| `any` | 1 |
| `open`, `has`, `remove`, `count`, `key` | 4 |
| `is` | 6 |
| `freeze` | 7 |
| `text` | 9 |

### 15.12 Worked example

An SLet module keeps the words from section 13 exactly as written, and a Let module uses it. The dice stay static and allocation-free; the game around them is dynamic.

```
-- dice.slet: strict, as in section 13
let xorshift(a, b, c, s: u32) : u32 = do
  let s1 = s ~ (s << a)
  let s2 = s1 ~ (s1 >> b)
  return s2 ~ (s2 << c)
end

let next32 = xorshift(13, 17, 5)

let roll(bound, s: u32) : (u32, u32) = do
  let t = next32(s)
  return t, t % bound + 1
end

return { functions = { next32, roll } }
```

```
-- game.let: a Let module using it
use diceyes

let config = freeze { rounds = 3, seed = 2463534242 }

let new_enemy(name, health) = do
  let e = { name = name, hp = health }
  let e.hit(damage) = do
    hp -= damage
    return hp <= 0
  end
  return e
end

let fight(e, s, round) = do
  if round == 0 then return s end
  let next, face = dice.roll(6, s)   -- s converts to u32 at the annotated parameter
  e.hit(i64(face))                   -- hp holds an i64, so the u32 face converts explicitly
  return fight(e, next, round - 1)
end

let main() : u32 = do
  let slime = new_enemy("slime", 10)
  fight(slime, config.seed, config.rounds)
  return if slime.hp <= 0 then 1 else 0
end
```

What each part relies on:

- **`config`** is frozen during module initialization, so `config.seed` and `config.rounds` are compile-time constants (section 15.7).
- **`new_enemy`** builds an open word and adds a method to it (sections 15.4 and 15.5). Its parameter is named `health`, not `hp`, because a parameter would shadow the field inside the method, as section 8 says.
- **`fight`** has no annotations, so its parameters are `any` and its recursive result is one `any` (section 15.2). Its tail self-call is still a loop.
- **`dice.roll`** comes from SLet code and its transitive body is verifier-proven `allocation-free`; its arguments convert at annotated parameters, and no collection boundary occurs inside that call (sections 15.6 and 15.8). SLet types alone would not prove this for a `.let` body.
- **`hp`** starts as the literal 10, so it holds an `i64` (section 15.3), and subtracting a `u32` face would abort with `type-mismatch`. The explicit `i64(face)` is the boundary made visible.

### 15.13 Let exclusions and validation

Section 14 remains the SLet `.slet` contract. Let intentionally permits GC-owned escaping references/views, escaping Let place captures and ownership through managed references, in addition to adding bare open-word literals and run-time partial supply. Let still excludes:

- nil, null or undefined values: a missing field aborts;
- truthiness: a condition must hold a `bool`;
- implicit conversions beyond the core language's, including between numbers and strings;
- mutable bindings: state lives in open words;
- exceptions and unwinding: errors are aborts, as everywhere in Let;
- operator overloading, metatables and implicit delegation between words;
- finalizers and destructors;
- a `ptr` to collected storage: a collected value's address is never observable (`ptr-collected`);
- coroutines, in this version: each could own its own three stacks, but the language needs syntax for them first;
- `any` in a `.slet` file or in a C export; retaining an unmanaged SLet/foreign borrow in `any` also rejects.

Required tests, beyond section 14's:

- renaming a fully annotated `.slet` file to `.let` gives identical observable behaviour; renaming back rejects every use of `any`, managed allocation or GC-dependent escape;
- unannotated groups, keys and schema fields typed `any`, next to annotated ones, and locals keeping inference;
- each static rejection's run-time abort under the same code name, for every operator on `any`;
- literal typing when entering an `any`, and literal adoption when another operand decides;
- dynamic calls discarding surplus results but aborting with `dynamic-signature` on every missing requested result, without synthesizing `unit`;
- canonical NaNs and nonallocating `f64`, plus compiled wide-integer loops that defer boxing until an actual dynamic escape;
- equality across types, identity of words, and integer keys of different widths naming one field;
- open words: building, adding, removing, computed keys, `field-missing`, `key-type`, aliasing through two names, thousands of data-derived keys and repeated structural churn leaving only O(live fields) collected storage;
- run-time supply opening a word, stores to supplied fields changing its behaviour, `readonly-field` on closed words, and `no-terminal`;
- same-length `EXT` quickening and A0/B0 routing producing the same results as unquickened generic dispatch;
- methods added by field path: bare field names, receiver binding, shadowing;
- conversions from `any` to scalars, records and signatures, including checked failures; managed strings retain backing storage while SLet/foreign string views copy;
- freezing: deep closure, `frozen-store`, frozen fields folded as constants;
- verifier-computed transitive `allocation-free` functions, SLet callees receiving no `any`, managed Let roots across calls, and host collection requests remaining pending across allocation-free loops;
- local `ref`, slice and place-capturing closure escapes in `.let`, including heap promotion, aliasing, module storage and tracing through `any`;
- rejection when an unmanaged SLet/foreign borrow is retained, plus `ptr-collected` and managed values staying valid across collections whether or not the collector moves them;
- Let files importing SLet successfully, SLet rejecting Let imports with `slet-import`, plus `import-ambiguous`, `abi-any` and `abi-managed`.

### 15.14 Implementation notes for the ABC VM

These notes say how the ABC VM is meant to run Let code. They are not part of the language contract.

**The collector is Whippet's mostly-marking collector.** ABC embeds [Whippet](https://github.com/wingo/whippet), a C collector library by Andy Wingo that is built into the host's source tree with no dependencies. Its license is MIT, so its copyright notice ships with ABC's code. Its design is described in [Nofl: A Precise Immix](https://arxiv.org/html/2503.16971). ABC uses the `stack-conservative-mmc` configuration: serial, non-generational, conservative stack roots and precise heap tracing. The paper calls the library a work in progress and evaluates it on microbenchmarks only, so ABC's own workloads must be measured.

An in-house collector with size-class pages was designed first. Whippet has the same properties, plus finer reclamation, lazy sweeping and optional defragmentation, so ABC uses it instead.

| Whippet provides | ABC uses it for |
| --- | --- |
| The Nofl space: 64 KB blocks with a side table of one mark byte per 16-byte granule, 6.25% overhead | object headers carry no collector bits |
| Bump-pointer allocation into holes, found by lazy sweeping during allocation | the inline fast path `gc_allocate_small_fast_bump_pointer`, generated into the allocating handlers |
| Conservative roots, pinned for the duration of a collection | the three stacks and the native stack, scanned without per-site maps |
| Optional evacuation of objects no root references, to defragment | off: the heap is strictly non-moving. Addresses are unobservable (section 15.8), so enabling it later is a configuration change, made only if measured fragmentation demands it |
| Serial, non-generational collection | the chosen configuration: the VM is single-threaded, embedded targets want no collector threads, and freezing already keeps long-lived data out of each trace |
| A separate space for objects above 8 KB | large open words and long strings |
| The `gc_extern_space_*` hooks | frozen module data kept outside the collected heap |
| Cooperative safepoints (`gc_safepoint` polls a flag) | replaced by a dispatch-table switch, so no handler polls |

**What ABC provides as the embedder.**

- **`gc_trace_object` for each object kind.** An open word reports every key and value in its ordered map plus terminal/capture state; a closure environment reports captures; a managed reference/view box reports its backing object; and a boxed record or array reports fields of type `any` plus descriptor-marked managed references, slice bases and callable environments. Strings and boxed integers/raw pointers report nothing.
- **Roots.** The A, B and C stack regions are registered as conservative ranges. The native stack, where handler registers are saved across a call, is scanned conservatively. Module storage is reported through `gc_trace_heap_roots`.
- **No forwarding functions yet.** They are needed only if evacuation is enabled, which it is not at first.

**Managed addresses and scalar encodings stay recognizable.** Conservative scanning recognizes both an allocation base and a managed interior address and retains the containing allocation. An `any` that refers to a collected object stores the object's plain address; an `any` containing a managed `ref` or slice uses a descriptor-bearing box when needed to preserve its exact type and owner. Doubles use an offset encoding and canonical NaN, so `f64` never allocates. Integers carry a tag in the top bits when they fit; a wider value has a canonical box, but residualized code keeps proven wide integers as unboxed register bits across compatible edges and materializes only when they escape. Raw `ptr` values are tagged/boxed as raw and never traced.

**When collections run.** Automatic collection runs in the allocation slow path, as Whippet arranges. A host request switches dispatch state and is honored at the next generic or allocating operation. The verifier's transitive `allocation-free` fact identifies functions and loops that contain no such boundary. A request can remain pending while they run because they produce no new collectible garbage. At the next eligible boundary, live handler roots are saved in scanner-visible storage before collection. Source filenames and JIT policy are irrelevant.

Dispatch switches to a safepoint table that diverts generic and allocating operations; nonallocating typed operations continue until the next eligible boundary. The safepoint handler is specialized to its cache state, saves every live root, and collects. Collecting at an instruction boundary means a collection never sees a half-built object.

**In compiled code,** an allocation is a call that saves every live register, and residualization knows the register map at that site. The same conservative scan applies, so no stack maps are generated.

**Frozen data.** Words frozen during module initialization are placed in an extern space, outside the collected heap, so a collection never traces or sweeps them. Words frozen at run time stay in the heap and are traced like any other. Because a frozen word references only frozen words and is never written, a future generational configuration could treat it as old data that needs no write barrier.

**Monomorphic generic opcodes can quicken into same-length internal versions.** Serialized dynamic operations use `EXT selector ...`. After observation, a measured monomorphic checked-specific site may replace its leading `EXT` byte in the VM-private code copy with an operation-specific internal opcode whose total generated length is unchanged. Unquickened and polymorphic generic sites keep the compact selector dispatch; internal opcodes remain invalid in serialized modules. Passed checks become context for compiled blocks. Dynamic unary operations have A/B forms, while binary arithmetic/comparisons consume A0 and B0 and choose the result stack exactly like typed operations, so the frontend keeps one two-stack scheduling model.

**JIT policy is host configuration.** The ABC VM does not inspect `.slet` or `.let` filenames. A host can run the same bytecode in interpreted, eager-JIT or lazy-JIT mode. Eager mode compiles load-time-reachable versions and leaves unavailable dynamic facts to generic checked operations. Lazy mode compiles when a context first reaches a block and may key capped versions by observed type tags and checked open-word layout tokens. A token is only a non-owning structural generation: it contains no keys and retains no map storage. A frozen word's field can fold only when the word object/value itself is known, not merely because its layout token is known.

### 15.15 Open questions

Every question that blocked implementation is decided in the sections above. Two things are deliberately deferred:

- [ ] **Coroutines.** Excluded from this version (section 15.13). Each coroutine could own its own three stacks; the open part is the syntax.
- [ ] **A run-time initialization marker.** Module initialization is the boundary today (section 15.7). A marker that lets compilation fold constants frozen at run time can come later, if real programs need it.
