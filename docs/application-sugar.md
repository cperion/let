# Disciplined application sugar

**Status: literal/postfix application implemented; lexical receiver fallback remains a target.** Extends [syntax.md](syntax.md) and
[operators-and-blocks.md](operators-and-blocks.md). Ordinary application remains the
semantic operation. No signature-aware parser, implicit conversion search, extension
registry or additional execution engine is introduced. Live work: Q05 and Q11.

## 1. Literal-led arguments

A call without argument parentheses accepts one atomic literal **and that literal's
postfix chain**, or one block lambda. Atomic literals are integer, float, byte, string,
long-string and boolean literals. A literal's chain contains only member selection,
indexing and explicit parenthesized application; it does not absorb infix operations,
keyed supplies, another bare literal or a trailing block.

```let
print "{}".fmt(n)          -- print("{}".fmt(n))
print "hello".length       -- print("hello".length)
print "{}".fmt(n).upper()  -- print("{}".fmt(n).upper())
a.push 21                 -- a.push(21)
```

`print` and `upper` here illustrate suitable library words, not additional predefined
APIs. The complete literal-led expression is one ordinary argument. If its final
call returns multiple results, existing final-argument adjustment applies exactly as
in the parenthesized spelling; do not import the arity probe's scalar-only convention.

All postfixes after the literal belong to its argument, not the outer call result:

```let
print "{}".fmt(n) .. "!"    -- print("{}".fmt(n)) .. "!"
print("{}".fmt(n) .. "!")  -- print the concatenated value
(print "hello").inspect()   -- explicitly operate on print's result
```

Keep the syntactic boundary small:

- `f x` rejects. `f 1 2` means `f(1)(2)`: consecutive suffixes associate left, not by arity.
- `f(-1)` supplies a negative value. In `f - 1`, minus remains subtraction.
- `f[1]` remains indexing; pass array literals with `f([1, 2])`.
- `point { x = 3 }` remains keyed supply; pass a table value with `f(table { x = 3 })`.
- `f "x".g() do ... end` means `f("x".g())(lambda)`. Likewise `f(x) do ... end`
  extends pending requirements or calls f(x)'s result once saturated; no argument list
  is reopened. Use `f(x, do ... end)`
  for one application with both arguments.
- An ungrouped block-lambda atom still takes no postfix continuation after `end`.
- Newlines remain whitespace. Semicolons delimit otherwise continuing statements.

Target grammar refinement:

```text
self-delimited-call := literal-argument | trailing-block
literal-argument    := atomic-literal literal-postfix*
literal-postfix     := '.' Name | '[' expression ']' | arguments
```

Bind a literal and all these postfixes before completing the surrounding application.
This supersedes the earlier literal-only/no-postfix restriction, not ordinary operator
precedence. Numeric tokenization is already specified: a decimal point requires a
digit on both sides, so `21.member()` is integer 21, selection dot, then member.
Test that contract rather than reopening it or changing float literal acceptance.

### 1.1 Pending requirements within a chain

Parsing remains left-associated, but an unsaturated ordered application is not yet a
word value. Elaboration carries its target and supplied arguments until a later
consecutive application suffix saturates it. No runtime partial object is created.

```let
with_file(path) do(f) ... end  -- runtime path may wait for the callback
add(n)(2)                     -- one invocation when add has two requirements
adder(n)(2)                   -- two invocations when adder is unary and returns a word
```

Evaluate the callee once, then each suffix's arguments in source order. Snapshot
argument computations before evaluating later arguments/suffixes, preserving reads,
traps and effects. Invoke immediately upon saturation; later suffixes then target the
result. This applies to known words and runtime callables with known signatures.
Unknown dynamic interfaces do not acquire inferred arity or generic semantics.

Each suffix adjusts its own results. `f(divmod(a, b)) do ... end` supplies both
results of divmod in the first suffix, then the lambda in the second. It does not
reopen the first list and make divmod nonfinal. One list cannot over-apply:
`unary(1, 2)` rejects rather than forwarding 2 to a returned callable.

At chain exit, existing partial-specialization/retention checks apply. Thus
`let g = add(runtime_n)` rejects in SLet while `add(runtime_n)(2)` can saturate.
Grouping is a boundary: `(add(runtime_n))(2)` also rejects; grouping the complete
chain, `(add(runtime_n)(2))`, is fine. Argument, binding and return contexts, member/index
selection and keyed supplies do not carry an ordered pending application across
their boundary. Intrinsic special forms retain their existing argument contracts.

For `defer`, earlier saturated prefixes execute during preparation; only the final
saturated invocation is deferred. All its supplied arguments and receiver binding
are established at preparation time. Ordinary capture/lifetime restrictions remain.
This does not implement escaping runtime closures or the lexical-receiver fallback below.

## 2. Lexical receiver-call sugar

For an invoked value member:

```let
receiver.name(args)
```

resolve in this order:

1. **Member wins.** If the statically known interface contains `name`, use its normal
   invocation contract. A bad signature or noncallable field errors; do not fall back.
2. **Closed-interface lexical fallback.** Only if no member exists and the static
   receiver interface is closed, look up ordinary callable `name` in lexical scope
   and supply `receiver` as its first ordered argument.
3. If no applicable lexical binding exists, report the ordinary missing-name/callable
   error. Do not search candidates by argument types or insert conversions.
4. A table or `any` receiver keeps dynamic member invocation, never lexical fallback,
   whether or not a runtime key happens to exist. See §4.

Presence is decided before argument checking. There is no `call-ambiguity` error
merely because a member and lexical word share a name. Thus store `s.remove(i)`
keeps its member behavior even with predefined lexical `remove` in scope.

Examples when there is no same-named member:

```let
"{}".fmt(n)              -- fmt("{}", n)
xs.sorted()              -- sorted(xs)
value.encode(options)    -- encode(value, options)
```

The first parameter really is first. No argument reordering or automatic receiver
insertion elsewhere in the signature. Lexical scope/import visibility determines
which word is named; ordinary shadowing rules remain authoritative. No global
extension registry or argument-dependent lookup. Adding a lexical binding/import
cannot hijack an existing member. Adding a member in the defining schema can redirect
former lexical calls: this is a schema API change affecting clients, not a compatibility
guarantee merely because schemas are closed.

`use std.text` makes `text.trim(s)` available but does not introduce lexical `trim`.
`use std.text...` brings exported `trim` into scope and enables `s.trim()` if no member
already supplies it. Import-spread collision checks still apply. Do not install module
exports globally or synthesize extension registrations.

Module qualification such as `task.scope(...)` is namespace lookup, not an instance
receiver to insert as an argument. Keep the compiler's namespace/interface distinction;
this sugar applies to value receiver calls. Callable fields retain their defined member
semantics (including the separately specified table receiver convention), not a guessed
free-function convention.

The explicit `name(receiver, args)` form always selects the lexical callable.
Member syntax selects an existing member without any qualification workaround.
This proposal adds no method-disambiguation operator.

## 3. Ownership, evaluation and effects

The lexical route is an ordinary call, including its parameter rules:

- A by-value record parameter copies under ordinary value semantics.
- A reference parameter requires an actual compatible reference; no hidden `ref(receiver)`.
- No method-style receiver borrow is invented for a free function.
- Actual schema methods retain their own receiver borrowing semantics.
- Evaluate receiver and written arguments once, in source order, preserving captures,
  errors, allocation/count/suspension effects and source locations.
- A lexical callable binding is resolved by normal name lookup; do not execute a
  candidate to determine applicability or synthesize an allocating adapter closure.

Writing a copied parameter is legal and does not trigger `receiver-copy-write`:

```let
let translated(p: point, dx: i64): point = do
  p.x += dx
  return p
end
let q = p.translated(10)  -- translated(p, 10); p is unchanged
```

To mutate through a lexical function, declare its first parameter as `ref(point)`
and pass that reference explicitly, e.g. `ref(p).nudge(10)` or `nudge(ref(p), 10)`.
Neither spelling repairs a function still declared with a by-value `point` parameter.
No implicit write-back or blanket rejection of value transformations is introduced.

Receiver-call sugar is not itself operator rewriting or implicit delegation.
[operators-and-blocks.md](operators-and-blocks.md#21-scope-supplies-operator-vocabulary)
now specifies a related lexical operator fallback. Its binary order is primitive,
left member, right member, then lexical function—not a blind rewrite to a left-receiver
call, which would put lexical lookup ahead of the right member. `receiver.name` **without
invocation** remains ordinary member selection; it does not bind a lexical function
into a closure or create a new first-class method value. Existing genuine bound
method behavior is unchanged.

## 4. Dynamic and unresolved interfaces: no runtime fallback

Closed interfaces include ordinary scalar/string interfaces, schema-backed records,
sums, stores and lists where their static member set is known. Closure of a type's
member set is a semantic fact, not a successful lookup on one runtime instance.
For `table` and `any`, `.name(...)` always follows dynamic member semantics; a missing
member stays that operation's error. Write `sorted(t)` to select a lexical function.
An opaque `any` lexical binding is not a statically proven callable candidate; use
explicit ordinary call syntax to request dynamic invocation of that binding.

In generic code resolve per specialization using the substituted receiver interface.
One instantiation can select a member while another selects a lexical word. Keep
lexical lookup anchored at the generic definition's scope, not the caller's imports.
Diagnostics report the source call and failing instantiation. If the interface remains
unknown, retain the demand or reject at the required boundary; never guess or search
runtime keys. No parsing step depends on arity, specialization results or runtime values.

## 5. Formatting is an application example, not a new method system

`fmt(format, ...args)` keeps its predefined ordinary-word spelling. If string has no
actual member named `fmt`, `"{}".fmt(n)` takes the lexical route to that same word.
No builtin string `fmt` member is needed: the lexical word already supplies this
spelling. Do not add a redundant formatting engine or special parser transformation. Formatting implementation, checks and allocation behavior
remain shared; a known literal format still supports static checking through normal
specialization. It is not a special parser rewrite limited to formatting.

## 6. Compiler integration and tests

- Parser builds one normal Apply over a literal-led postfix argument. No lookup is
  needed for this syntax. Preserve original spans for the literal and every suffix.
- Semantic invoked-member resolution checks the receiver interface first, then lexical
  scope only when the closed interface lacks that member. Create an ordinary member
  call or ordered call with receiver inserted first; no extra runtime dispatch node.
  Apply the same rule after literal/block call-sugar desugaring.
- Noninvoked FieldSelect behavior remains untouched. Module-qualified paths retain
  their existing namespace resolution. Ref/copy semantics follow selected parameters.
- Static preparation, partial supply, spread/result adjustment and callable metadata
  continue through the existing application pipeline. A rest callable such as fmt
  needs no arity-aware parsing because its actual arguments are explicitly delimited.
- Validate exact lowering of literal-led chains and infix boundary, negative values,
  numeric-dot lexing, long strings, indexing and explicit grouping.
- Test member-only, lexical-only, neither and both (member wins), wrong selected
  signature/noncallable member without fallback, namespace lookup, import opt-in,
  definition-site generic scope, specialization diagnostics and schema-member additions.
- Test receiver evaluation once, copy versus ref/borrow, failed-call effects, ownership
  and group bounds, and no lexical binding closure for uninvoked `.name`.
- Test table/any dynamic member calls never try a lexical fallback; include missing
  keys and an identically named lexical callable. Test pure copy-writing transforms
  and explicitly referenced mutation; neither inserts hidden borrows/write-back.

This feature adds source resolution/elaboration, not new bytecodes, a second allocator
or backend-specific algorithms. Performance claims require ordinary call/copy/allocation
measurements, not a promise that fluent spelling is always free.
