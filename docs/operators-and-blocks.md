# Schema operators and trailing blocks

**Status: approved design direction; not implemented.** This extends
[syntax.md](syntax.md), with implementation tracked in [WORKLIST.md](../WORKLIST.md)
under Q. Concrete schema-interface identity and comparison-result contracts remain
explicit gates. No new runtime method table, nominal type system or dynamic dispatch
ABI is authorized by the syntax alone.

## 1. Ordinary schema methods

User-defined operators use reserved protocol names on ordinary schema methods or,
under the lexical fallback rule below, visible ordinary functions.
They accept expression bodies or `do ... end`, obey normal receiver/place/capture
rules and retain normal allocation, counting, suspension, error and foreign effects.
Only the defining schema supplies its member operator interface. A library may
supply lexical operator functions without modifying that interface. No extension
registry, primitive replacement, metatable, implicit delegation or new operator
symbols are introduced. Precedence and associativity remain unchanged.

```let
let vec2 = {
  x: f64, y: f64,
  op_add(o: vec2): vec2 = vec2 { x = x + o.x, y = y + o.y },
  op_mul(k: f64): vec2 = vec2 { x = x * k, y = y * k },
  op_mul_right(k: f64): vec2 = vec2 { x = k * x, y = k * y },
  op_neg(): vec2 = vec2 { x = -x, y = -y },
  op_eq(o: vec2): bool = x == o.x and y == o.y,
}
```

These are target examples, not currently executable fixtures. A method may use a
block body instead; an operator does not require expression-only implementation.
One method signature per protocol name avoids overload candidate sets. Other operand
combinations can use named methods such as `dot` or `cross`.

## 2. Dispatch and evaluation

For a binary operation, use the fixed primitive contract when applicable. Otherwise
select the left operand's schema method, if present; only if absent, select the
right operand's corresponding `_right` method. Only when both member routes are
absent and both static operand interfaces have closed member sets, look up the
ordinary lexical protocol function (e.g. `op_add(left, right)`). A selected member
or function's type/signature failure is an error, not permission to try another
candidate. A present noncallable member is an error, not absence. No user code runs
to determine applicability, and there is no user-defined conversion search.

Evaluate the left operand then the right operand exactly once. Right dispatch
changes the receiver, not source evaluation order. The method receives the other
operand as its argument. Noncommutative right methods must explicitly implement
original-left op original-right, not blindly delegate with reversed operands.

Dispatch uses the statically available schema interface. The receiver may still be
a runtime value. Temporary receiver materialization and borrowing follow ordinary
method rules; overloads do not invent retained references to temporary storage.

### 2.1 Scope supplies operator vocabulary

```let
use ...geometry
let combined = a + b
```

If primitive and member routes do not apply, the visible `op_add(a, b)` implements
this addition. `use geometry` alone makes qualified words available but does not
bring `op_add` into lexical scope. Ordinary import-spread collision checks apply;
there is one visible binding, not an overload set indexed by operand types.

For arithmetic, bitwise and concatenation binary protocols, the exact priority is:

1. Fixed primitive contract.
2. Left member `op_name`.
3. Right member `op_name_right`.
4. Lexical `op_name(left, right)`, only with closed operand interfaces.
5. Otherwise reject with the ordinary missing-operation diagnostic.

There is no separate lexical `_right` search: lexical functions receive both operands
in source order. Do not implement this by blindly rewriting to `left.op_name(right)`:
receiver-call sugar would try a lexical function before checking the right member.
Share name/interface resolution machinery, but preserve the operator-specific priority.

For unary `op_neg`/`op_bnot`, the analogous order is fixed primitive, operand member,
then lexical `op_name(operand)` when the interface is closed. `and`, `or` and `not`
remain bool-only and do not acquire lexical hooks.

Selection does not automatically borrow a receiver or insert `ref`. Lexical functions
have ordinary parameter contracts, so a by-value record may be copied and transformed;
schema methods retain their receiver borrowing rules. Evaluate each operand once in
source order before ordinary parameter transport, preserving source errors and effects.
Existing compound-store rules still evaluate the target/index once and store the result.

Generic calls resolve per specialization using definition-site lexical scope; report
that instantiation when resolution/type checking fails. Table/any dynamic operations
never try a lexical hook after a runtime failure or missing member. Unknown interfaces
must be resolved by existing demands or diagnosed, not guessed from field layout.

Adding an import cannot replace a primitive or member operator. Adding a schema
member can supersede a lexical route in clients; that is an API change, not a promise
of compatibility. To explicitly select a library operation, call its qualified word.
No global registry, descriptor patching or AST macro expansion is involved.

This lexical extension initially covers arithmetic, bitwise, concatenation and unary
protocols above. Comparison reverse-dispatch/order results remain a design gate;
index/set-index and callable protocols need an explicit lexical-extension contract
before extending their existing member behavior. Do not infer hooks for all syntax
merely because a function named `op_*` is visible. Dynamic operator ABI remains separate.

## 3. Protocol surface

| Methods | Source operation |
| --- | --- |
| `op_add`, `op_sub`, `op_mul`, `op_div`, `op_rem`, `op_pow` | `+`, `-`, `*`, `/`, `%`, `^` |
| `op_band`, `op_bor`, `op_bxor`, `op_shl`, `op_shr` | `&`, `\|`, binary `~`, `<<`, `>>` |
| `op_concat` | `..` |
| `op_neg`, `op_bnot` | unary `-`, unary `~` |
| `op_eq` | `==`; `!=` negates its bool result |
| `op_compare` | `<`, `<=`, `>`, `>=` by comparing its order result |
| `op_index`, `op_set_index` | indexed value read and indexed assignment |
| `op_call` | positional application of a schema instance |

Arithmetic, bitwise and concatenation binary methods have corresponding `_right`
forms. Unary methods have no explicit operand parameter; ordinary binary methods
have one. Value-producing arithmetic/index operations return one value. `op_eq`
returns exactly bool. `op_set_index` takes index and assigned value and returns unit.
`op_call` may have an ordinary declared result vector; its receiver is not an extra
source argument. It does not redefine schema construction or keyed initialization.

Equality/ordering reverse-dispatch names, order-result representation and handling
of partial orders (`unordered`) must be settled together before implementing those
protocols. Do not infer them from arithmetic `_right` naming or force float-containing
records into a total order accidentally. There is no independently overloadable
`!=`, `<`, `<=`, `>` or `>=` implementation that bypasses the selected equality/order
protocol. User methods can still violate mathematical laws or have effects; a common
protocol is not a proof of symmetry, transitivity or consistency with equality.

Protocol signature checking must give a direct diagnostic for malformed operator
methods. Exact generic signature checking and declaration-versus-use timing are part
of the elaboration design gate, not permission for runtime speculative dispatch.

## 4. Structural types and schema interfaces

Let's records are structurally typed and methods belong to schema interfaces. Equal
field layouts do not alone identify which schema's operators apply. Operator authority
must follow the same explicit interface information as ordinary method resolution,
not whichever declaration is found first or a global table keyed only by layout.

Before implementation, specify how that authority survives annotated bindings,
structural conversions, generic parameters, joins, imports and callable signatures.
If two equal-layout schemas define different operators, conversions must not silently
select one. Specify loss/selection/ambiguity diagnostics in the existing method model;
do not introduce nominal record identity as an accidental implementation shortcut.

This is an open concrete contract. In particular, generic operator code requires a
known applicable schema interface, not merely knowledge of field layout. Type
specialization can remove dispatch, but neither call elimination nor zero allocation
is a language guarantee.

## 5. Places, indexing and compound stores

`op_index` returns a value, not an addressable element place. `ref(x[i])` on an
overloaded value index rejects (`element-ref`). Native array/slice indexing keeps
its own place contracts; the rejection does not apply indiscriminately to all indexing.

`op_set_index` mutates through an actual writable receiver under ordinary method
rules. Assigning through a temporary copy must not appear to mutate its source.
Receiver validity/borrow requirements must be checked before accepting the store.

For compound indexed stores, evaluate the receiver and index once, read the indexed
value once, evaluate the RHS, apply the selected binary operation, then perform one
write. Preserve evaluation/error order and receiver lifetime across those steps.
Field compound stores similarly evaluate their target once and derive from the
ordinary binary operation. There are no separate `op_add_assign`-style protocols.
These are place-aware elaborations, not textual rewrites duplicating expressions.

No overload is permitted for assignment itself, member selection, `ref`, `and`,
`or`, `not` or the meaning of `do`.

## 6. Boolean control flow stays fixed

`and` and `or` require bool, produce bool and short-circuit. `not` evaluates its
single bool operand and negates it; it is not a short-circuiting binary operator.
No truthiness or hidden RHS thunk is introduced by overload resolution.

Use eager `&`, `|` and `~` for masks, symbolic logic and value-building protocols.
Existing precedence applies, so comparison-valued operands need explicit grouping:

```let
(age > 18) & (name == "x")
```

Overloadability does not imply implicit conversion of the resulting value to bool.

## 7. Trailing block argument sugar

**Approved self-delimiting application forms; not implemented.** Parentheses can
be omitted for one literal-led argument or one block argument. This follows Lua's
self-delimiting-argument principle, not signature-aware or general whitespace
application. Parsing never asks for a callee's arity or type.

| Form | Exact ordinary application |
| --- | --- |
| `f 21`, `f 0xff`, `f 1.5` | `f(21)`, `f(0xff)`, `f(1.5)` |
| `f true`, `f false`, `f 'x'` | `f(true)`, `f(false)`, `f('x')` |
| `f "text"` | `f("text")` |
| `f do ... end` | `f(do ... end)` |
| `f do(x) ... end` | `f(do(x) ... end)` |
| `f do(x) = expression` | `f(do(x) = expression)` |
| `f(a, b) do ... end` | `f(a, b, do ... end)` |

Atomic literals are integer, float, byte, string (including existing long-bracket
forms) and `true`/`false`. Literal decoding and contextual numeric typing are unchanged.
A negative number is not an atomic literal: `-` is a unary operator, so write `f(-1)`.
A literal-led argument includes that literal's member selections, indexing and
explicit-call postfix chain; `print "{}".fmt(n)` means `print("{}".fmt(n))`. The
postfixes belong to the argument, not the outer call result. Infix remains outside.
The sugar does not begin with variables, array/schema literals or arbitrary expressions.
[application-sugar.md](application-sugar.md) specifies this refinement and closed-interface
member-first lexical receiver-call resolution.
`f 1 + 2` means `f(1) + 2`, not `f(1 + 2)`. Existing `f[1]` remains indexing;
pass an array explicitly with `f([1, 2])`. These forms work in bindings,
returns and other expression positions as well as call statements.

A parenthesized call followed by a block passes one final lambda argument:

```let
with_region(u32, 8) do(p)
  return compute(p)
end
```

means exactly:

```let
with_region(u32, 8, do(p)
  return compute(p)
end)
```

With no parameters, the appended block lambda is nullary:

```let
g.spawn do return work() end
```

This is **one application**, not an initial call followed by a second call or
partial-supply operation. Desugar before argument-result adjustment: an old final
argument becomes nonfinal and contributes one result unless explicitly spread.
Evaluate callee, written arguments and the final lambda's capture construction in
ordinary source order. The block body runs only when the callee invokes it.

Both lambda body kinds begin with `do`: `do(parameters): result = expression`,
`do(parameters): result ... end`, or nullary `do ... end`. Parameters and result
annotations use ordinary definition syntax; annotations are optional, but expression
lambdas require parentheses, including `do() = expression`. Trailing-lambda sugar
supplies this same ordinary expression. Pipe and arrow lambda forms have no aliases;
`|` is an infix operator only. Archived evidence retains its historical spelling.

Parameters use ordinary lambda grouping/annotation and expected-callable typing.
Return exits the block's lambda, not its enclosing function. Capture, escape,
borrowing and group restrictions remain normal callable restrictions: a block given
to `spawn` is not allowed mutable captures merely because the syntax resembles a loop.

An omitted argument list supplies exactly the block lambda. An explicit argument
list followed by a block appends the lambda to that same application before result
adjustment. `f(x) do ... end` does not mean `f(x)(lambda)`; write `(f(x)) do ... end`
when calling the result is intended. Likewise `(f "text") do ... end` explicitly
calls a string-call's result with a block. Multiple positional arguments otherwise
require parentheses: write `f("text", x)` or `f("text") do ... end`, not `f "text" x`.

One terminal literal/block sugar form attaches at each postfix level. Consecutive
unparenthesized literals do not form a multi-argument supply: `print "a" "b"` and
`f 1 2` reject; explicit grouping invokes the result, `(f 1) 2`.
A literal suffix followed directly by `do` likewise needs explicit grouping or a
parenthesized argument list. Postfix access to the outer sugar call's result requires
grouping; a literal-led argument's own postfixes bind inside the argument. Nested blocks attach syntactically, never by indentation.

Keyed braces retain their existing meaning: `point { x = 3 }` supplies keyed
requirements, not one positional Lua-style table. Pass a table value explicitly
with `f(table { x = 3 })`. To call a keyed application's result with a block, group
it; no block is implicitly added to the keyed supply. Standalone `do` in expression
position is a block lambda, not an immediately executed block or a declaration-scope
statement. Direct `do` after a named-definition `=` is that definition's executed body.

Grammar additions (integrated in syntax.md §12):

```text
postfix         := atom postfix-suffix* self-delimited-call?
self-delimited-call := literal-argument | trailing-block
literal-argument := atomic-literal literal-postfix*
literal-postfix := '.' Name | '[' expression ']' | arguments
atomic-literal  := integer-literal | float-literal | byte-literal
                 | string-literal | long-string-literal | 'true' | 'false'
block-lambda   := 'do' ('(' lambda-parameters? ')')? (':' result-spec)? statement* 'end'
expression-lambda := 'do' '(' lambda-parameters? ')' (':' result-spec)? '=' expression
trailing-block := block-lambda | expression-lambda
```

A trailing block appends to a final parenthesized argument suffix, or creates a
single-lambda application when no ungrouped call/initializer suffix is at the end.
A literal-led suffix creates a one-argument application to the preceding callee,
using ordinary final-argument result adjustment after the literal's postfix chain.
Newlines remain whitespace; use existing semicolon boundaries when a following
self-delimited argument would otherwise continue the preceding expression.
Bare `f x`, multi-argument `f 1 2` and arity-directed parsing are excluded.
`f - 1` retains subtraction syntax, not a negative argument.

### Standalone block lambdas

```let
let work = do(x: u32)
  return x + 1
end
let main = do
  print "starting"
  return 0
end
```

These bindings construct words. `let x = do return 3 end` binds a nullary word,
not 3; call it with `x()`. Existing capture/lifetime and binding-recursion rules
apply. A lambda's `=` introduces an expression: `do(x: u32) = do return x end`
returns a block lambda without grouping. A named definition's `= do` is instead
its executed body; `= do(...)` rejects there. Return a lambda with explicit grouping:
`let make(x: u32) = (do() = x)`.

Callable-value exports and main discovery must recognize valid block-lambda bindings.
This is not just token sugar over the current direct-word export path. Main's existing
standalone u32 result contract remains; implicit unit completion does not invent exit
code zero. Illustrative `print` is not an added standard API.

An ungrouped block-lambda atom takes no postfix or self-delimited-call suffix after
`end`; immediate invocation is `(do return 3 end)()`. Group likewise for indexing or
member access. Infix continuation is unchanged. This prevents an expression on the
next line attaching as a call to a block-lambda initializer without making newlines
significant.

Prefer named definitions for reusable/self-recursive words, and block-lambda bindings
for callable values, callbacks, handlers and entry bindings. The two forms retain
different local recursion/export rules.

Block lambdas are ordinary keyed handler values too:

```let
let await_value(ch: task.chan(u32)): u32 = task.select {
  ready = ch.on_receive(do(r)
    return r {
      item = do(value) = value,
      closed = do() = 0,
    }
  end),
  timeout = task.on_after(1000, do(u: unit)
    return 0
  end),
}
```

The example assumes `use std.task`; callback result types and unit alternatives
obey the ordinary match contract. No select-specific block syntax is introduced.

### Unit completion, not last-expression return

A callable block with an established unit result contract can fall through, exactly
as if it ended with bare `return`. This applies to methods and named words as well
as lambdas. Context/annotations establish unit; otherwise unconstrained acyclic
bodies with no reachable value returns infer unit. Resolved recursive SCCs also infer
unit for unconstrained members when every member has a block body with only bare
returns/fallthrough, all intra-component calls are discarded call statements and no
member has a non-unit explicit/expected/export contract. Ignore nested callable
bodies when inspecting returns. This precedes absent-contract `any` defaults; it does
not override established contracts. Valued recursive returns and expression bodies
remain outside this shortcut. Full rules are in syntax.md §10. Value-returning paths cannot coexist with an implicit
unit exit merely to avoid `missing-return`.

```let
html.render do(h)
  h.heading "Inventory"
  h.section do
    h.paragraph "Nothing to display"
  end
end
```

These are illustrative library APIs: both callback signatures require unit, while
`html.render` itself can return a string. A final call still discards its result;
no arbitrary expression statement, implicit value return or nonlocal return is
introduced. Inner statement-block fallthrough does not exit the callable. Deferred
actions, holding releases and structured-scope completion use the ordinary exit path.
See syntax.md §5; this target change is not implemented by the current parser alone.
The arity experiment remains historical evidence, not a production parser dependency.

No schema can overload block construction/control flow. Inlining or avoiding closure
allocation is an optimization subject to the same proofs as the explicit lambda.

## 8. Dynamic integration is a separate slice

Static schema dispatch is the initial implementation scope. `any` holding a record
must not silently lose or invent operator authority. A later dynamic slice must
specify the preserved schema interface, descriptor entries, operand checks, reverse
dispatch and ownership-safe invocation consistently with the static rules.

Only types actually requiring dynamic dispatch need descriptor operator entries;
ordinary record instances do not acquire per-instance runtime method tables. Tables
do not gain user-defined operator/metatable hooks. Their existing builtin operations
remain governed by their own contracts. Immutable boxes cannot expose writable
receivers to mutating operators by bypassing value-copy/frozen rules.

Dynamic scalar execution remains one authoritative computation composed with resolved
ordinary calls, not an independent backend implementation. No ABI/encoding or fallback
is authorized until its concrete design is approved.

## 9. Diagnostics and acceptance

Proposed protocol diagnostics: `operator-missing` when no supported implementation
exists and `operator-signature` for an invalid selected protocol. Existing type,
place, readonly, element-ref, effect and group-escape diagnostics remain authoritative.
Interface ambiguity/loss diagnostics await section 4's concrete contract.

Required evidence:

- Lexical fallback: primitive/left/right priorities ahead of lexical functions;
  right member wins even when a left-style lexical function is visible. Import-spread
  opt-in/collisions, definition-site generic scope, per-instantiation errors, absent
  versus malformed members, noncommutative source order, exactly-once effects and
  ordinary copy/ref semantics. Dynamic table/any failures never call lexical hooks.
- Primitive behavior unchanged; static left/right dispatch, absent versus ill-typed
  method distinction, noncommutative order and one-time operand evaluation.
- Expression/block bodies; ordinary effects, errors and callable ownership preserved.
- Equal-layout schemas, conversion/import/generic joins and explicit interface authority.
- Equality negation, order/unordered policy and no implied mathematical law enforcement.
- Read/store index contracts, rejected element refs, receiver/index/RHS ordering,
  temporary receivers and no duplicated effects in compound stores.
- `op_call` result vectors, signatures and normal application semantics.
- Boolean short-circuiting unchanged; eager mask operators and precedence unchanged.
- Atomic-literal calls equivalent to explicit one-argument calls: integer widths,
  hex/binary forms, f64, byte/string/long-string decoding and bool; contextual literal
  typing, infix precedence, expression/binding positions, comments/newlines and
  semicolon boundaries. Reject variable/multiple-literal adjacency; preserve unary
  minus, array indexing and keyed construction rather than guessing by callee type.
- Block-only and trailing-block calls equivalent to explicit lambdas, including
  capture evaluation, local return, empty args, result-vector adjustment, explicit
  spread and nested calls. Distinguish append-to-call from calling a grouped result;
  preserve keyed supply semantics and reject unsupported mixed sugar forms.
- Standalone blocks construct without executing; nullary/parameterized captures and
  lifetimes follow ordinary rules. Reject named-definition `= do(...)`; accept grouped
  nested blocks. Distinguish named executed bodies from returned block lambdas, preserve
  local recursion rules, and validate callable-binding exports/main's actual ABI.
- Unit completion for named words/methods/lambdas via annotation, expected signature
  and acyclic inference; retained rejection of value/mixed-path fallthrough and
  recursive contract violations, plus accepted bare-return recursive SCCs and rejected
  valued-return/non-unit-contract shortcut candidates. Test nested callable returns
  separately and preserve ordinary checking when the shortcut does not apply.
  Final calls discard results, inner blocks do not
  return, and defer/release/scope obligations match explicit bare return.
- Rejected escaping/group-invalid blocks and preserved source diagnostics.
- Ordinary checked IR and all applicable execution modes; no new scalar engine,
  allocator or host evaluator. Measure call/copy/count/allocation and code growth.

Follow WORKLIST's substantial-chunk policy: integrate the contract and its consumers
before validation, rather than micro-testing each syntax or lowering edit.
