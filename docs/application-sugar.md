# Disciplined application sugar

**Status: literal/postfix application, typed receiver calls/scopes and binding-resolved
captures implemented within current admission.** Opening exposes live places, not
snapshots. [WORKLIST](../WORKLIST.md) Q05/Q11 and X07 owns qualification and remaining
frozen-place, discarded-copy-write and owning-interface work. Extends [syntax.md](syntax.md) and
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
- `point { x = 3 }` remains keyed supply; pass a table value with `f(Table { x = 3 })`.
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
This does not implement escaping runtime closures.

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
4. A table or `Any` receiver keeps dynamic member invocation, never lexical fallback,
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

Outside a receiver scope, explicit `name(receiver, args)` selects the lexical callable.
Inside one, use `(name)(receiver, args)` or namespace qualification for an ordinary
call when the bare name would select the receiver route below. Member syntax selects
an existing member without a qualification workaround. No new disambiguation operator
is introduced.

## 3. Ownership, evaluation and effects

The lexical route is an ordinary call, including its parameter rules:

- A by-value record parameter copies under ordinary value semantics.
- A first parameter `Ref(T)` borrows an actual writable `T` receiver place implicitly.
  An already-compatible reference passes unchanged; never manufacture `Ref(Ref(T))`.
- This lifting is confined to the receiver position. Ordinary `nudge(p, 10)` still
  rejects when `Ref(T)` is required; `nudge(Ref(p), 10)` remains explicit.
- Borrowing a temporary rejects: bind it first. A frozen receiver must reject with
  `Frozen-write`; typed frozen-place enforcement remains part of the ownership work,
  not a capability claimed by this receiver implementation.
- Actual schema methods retain their own receiver borrowing semantics.
- Evaluate receiver and written arguments once, in source order, preserving captures,
  errors, allocation/count/suspension effects and source locations.
- A lexical callable binding is resolved by normal name lookup; do not execute a
  candidate to determine applicability or synthesize an allocating adapter closure.

Writing a copied parameter is legal and does not trigger `receiver-copy-write`:

```let
let translated(p: point, dx: I64): point = do
  p.x += dx
  return p
end
let q = p.translated(10)  -- translated(p, 10); p is unchanged
```

To mutate through a lexical function, declare its first parameter as `Ref(point)`.
Then `p.nudge(10)` borrows writable `p`; `Ref(p).nudge(10)` and
`nudge(Ref(p), 10)` remain valid. None repairs a word declared with a by-value `point`
parameter. There is no implicit write-back or blanket rejection of value transformations.
`discarded-receiver-write` remains planned only for a by-value receiver whose copy is
written and discarded without a result. Writes through references stored inside the
copy are not writes merely to that copy. Effect checking is not implemented by this
receiver implementation.

Receiver-call sugar is not itself operator rewriting or implicit delegation.
[operators-and-blocks.md](operators-and-blocks.md#21-scope-supplies-operator-vocabulary)
now specifies a related lexical operator fallback. Its binary order is primitive,
left member, right member, then lexical function—not a blind rewrite to a left-receiver
call, which would put lexical lookup ahead of the right member. `receiver.name` **without
invocation** remains ordinary member selection; it does not bind a lexical function
into a closure or create a new first-class method value. Existing genuine bound
method behavior is unchanged.

### 3.1 Receiver scopes

**Live-place contract implemented within admitted typed contexts.** Opening a record or
reference-to-record with `let ctx...`, `do(ctx...)` or an unnamed parameter
`...: T`/contextual `do(...)` retains one receiver and introduces names for its live
field places. A signature opens at most one parameter, first after leading static
Type parameters. Entry opening works in expression bodies as well as blocks.
`(...)` explicitly reads the retained runtime home; `(helper)(..., args)` bypasses
receiver insertion and explicitly supplies that home. The home cannot be rebound,
and its private reference holder is not a public addressable variable. Names remain bound to those places; their reads observe
current field contents and writes obey the existing place permissions. Schema methods
remain attached to that receiver; no detached closure binding is introduced.

A bare call that is not supplied by a local binding or callable field uses
the innermost receiver: `nudge 10` means `ctx.nudge(10)`. Resolve members before
lexical words, using the same signature-directed receiver supply as explicit dot calls.
A selected incompatible word errors: do not retry an ordinary call or another receiver.
Nested scopes replace the implicit receiver; there is no search through outer scopes.
Ordinary parameters and locally bound callables retain ordinary invocation semantics.
`(helper)(args)` selects a function value explicitly and bypasses receiver insertion;
namespace-qualified calls do too. Intrinsic special forms retain their own contracts.

Parameter passing into the scope is independent. Opening a by-value parameter borrows
that parameter's copy, not the caller's object. Receive `Ref(T)` to mutate its referent.
Reference contexts retain their referent once; their field projections observe later
writes. Opening does not eagerly read/copy fields. `let saved = field` takes an ordinary
field-read value, not another projection, and does not deep-copy reference referents.
Module and sum expansion introduce definitions only. Receiver scope is lexical, never
inherited dynamically from a caller. Nested words using opened fields must transport
actual place dependencies, including scalar projections, under ordinary lifetime and
escape restrictions. Selecting an opened callable field reads its current callable
value without adding a receiver argument. See [spread.md §5](spread.md#5-introducing-names-let-context)
for the authoritative opening contract. No new owned closure admission is implied.

Capture registration follows selected bindings, not identifier spellings. Interface
and visibility queries do not capture; actual lookup transports the selected binding
through intervening lexical frames. Compile-time definitions retain identity without
runtime captures. The syntactic candidate pass has been removed.

A word reserves its identity and visible signature before body elaboration. Capture
holdings are deduplicated; nested references to unfinished recursive words retain finite
capture dependencies. After participating bodies finish, word completion finalizes hidden
parameters, direct/deferred call arguments and first-class view layouts together. Pending
transport cannot reach verification or VM execution. This changes no ABI or ownership
permission and does not replay semantic elaboration.

## 4. Dynamic and unresolved interfaces: no runtime fallback

Closed interfaces include ordinary scalar/string interfaces, schema-backed records,
sums, stores and lists where their static member set is known. Closure of a type's
member set is a semantic fact, not a successful lookup on one runtime instance.
For `Table` and `Any`, `.name(...)` always follows dynamic member semantics; a missing
member stays that operation's error. Write `sorted(t)` to select a lexical function.
An opaque `Any` lexical binding is not a statically proven callable candidate; use
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
  and receiver-only reference lifting; ordinary arguments stay explicit and neither
  route inserts write-back. Test scope nesting, local callable priority, function-value
  bypass, reference contexts, actual capture dependencies and member-wins noncaptures.
  Live-opening tests additionally cover qualified/opened read-write equivalence,
  explicit snapshots, scalar/aggregate/callable/reference place captures and existing
  escape rejections. Broader frozen/readonly proof remains pending; earlier snapshot
  logs are not evidence for the replacement semantics.

This feature adds source resolution/elaboration, not new bytecodes, a second allocator
or backend-specific algorithms. Performance claims require ordinary call/copy/allocation
measurements, not a promise that fluent spelling is always free.
