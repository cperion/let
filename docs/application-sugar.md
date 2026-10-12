# Disciplined application sugar

**Status: approved direction; not implemented.** Extends [syntax.md](syntax.md) and
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

- `f x` and `f 1 2` reject; no general expression adjacency or multiple bare arguments.
- `f(-1)` supplies a negative value. In `f - 1`, minus remains subtraction.
- `f[1]` remains indexing; pass array literals with `f([1, 2])`.
- `point { x = 3 }` remains keyed supply; pass a table value with `f(table { x = 3 })`.
- Literal-led argument plus a block requires explicit parentheses: `f("x".g()) do ... end`.
  To invoke the outer result with a block, write `(f "x".g()) do ... end`.
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
`use ...std.text` brings exported `trim` into scope and enables `s.trim()` if no member
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
