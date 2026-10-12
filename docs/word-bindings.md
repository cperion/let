# Words, bindings and keyed entries

## One computation, several spellings

A word owns its requirements, result contract, body, captures and code identity.
Names belong to bindings, not to a second kind of executable computation.

```let
let inc(x: U32) = x + 1
let inc = do(x: U32) = x + 1

let work(x: U32): U32 = do return x + 1 end
let work = do(x: U32): U32 return x + 1 end
```

Each pair is equivalent, including parameter/result checking, capture treatment,
recursive visibility and export eligibility. An alias refers to the same word;
adding a name or a matching signature annotation does not construct another body
or force an environment allocation. Actual first-class transport remains a separate
representation boundary. Export aliases may still require the existing ABI entry
forwarders; this does not grant a different source computation to value aliases.

`do` uses the same parameter grouping and annotations as definitions and methods.
Expression bodies require parentheses, including `do() = expression`. Nullary block
words may omit them: `do ... end`. Optional result annotations use `:`, including
vectors, and must agree with contextual signatures. There are no pipe/arrow aliases.

### Recursive binding, not a spelling privilege

A lexical binding whose initializer is a literal `do` establishes its own name for
that word's body. Transparent grouping of that literal does not change the rule.
Named-definition syntax establishes precisely the same binding.

```let
let factorial = do(n: U32): U32 =
  if n == 0 then 1 else n * factorial(n - 1)
```

An ordinary initializer is not recursive: `let x = x + 1` cannot discover its own
new binding. Conditional/call-produced callable initializers do not gain recursive
scope merely because their result is callable. Keyed supplies do not create lexical
bindings for their keys.

File-scope literal-word bindings and named definitions are mutually visible, use
the same deferred result-contract demands and are equally exportable. Acyclic
results may be inferred. A recursive use that needs an unresolved result contract
currently requires an explicit annotation; no guessed `Any` answer or general
result fixpoint is introduced. General unit/SCC completion remains a separate item.

Named keyed-requirement declarations use this same computation/elaborator, but a keyed
`do` surface form has **not** been added. The spelling equivalence demonstrated above is
for ordered definitions; a concrete keyed-literal grammar still needs approval before
claiming every named declaration has a literal spelling.

Final rest syntax is shared by named definitions and their literal-`do` bindings.
Rest-pack and supply-spread elaboration now use the same word elaborator through
source-only specialization. An explicit `T: Type` requirement can fix a following
`f: T` interface; known code remains direct and an unknown implementation uses that
fixed indirect ABI. Selected captures form at definition time, not first invocation.
Templates are source-importable/exportable but have no erased variadic ABC entry.
This does not implement runtime variadic signatures or runtime pack objects.

### Keep the named-body boundary

After a named definition's `=`, bare `do ... end` is its executed block body.
`do(...)`, including `do()`, instead constructs a returned lambda. Grouping is optional
for a parenthesized lambda constructor:

```let
let make(x: U32) = do() = x
```

A lambda's own `=` always introduces an expression, so nesting needs no workaround:
`do(x: U32) = do(y: U32) = x + y`. Both returned examples remain subject to capture
lifetime/ownership support; their syntax does not authorize an escaping environment.

## Uniform application suffixes

Suffixes parse left-associatively: `f 1 2` is `f(1)(2)`. Elaboration carries
unsaturated requirements across consecutive application suffixes, rather than
materializing each intermediate partial. `f(x) do ... end` can therefore complete
an ordinary two-argument f even when x is runtime; when f is unary, the block applies
to its returned value. The same holds for `f x_literal do ... end`.
Here `x_literal` denotes a literal, not a bare identifier. Argument lists are never
reopened: write `f(x, do ... end)` for one application with both arguments.

A literal retains its own member/index/explicit-call chain. Variables and arbitrary
expressions still require parentheses. Each suffix performs its own result adjustment;
static partial checks occur when an unsaturated word leaves the chain. Grouping is a
boundary: `(f(runtime_x))(callback)` cannot complete the inner partial. See
[application-sugar.md §1.1](application-sugar.md#11-pending-requirements-within-a-chain)
for evaluation snapshots, other boundaries and defer. There is no arity-driven parser or
implicit generic specialization is added. Currying through `= do(...) = do(...)`
needs only the innermost block's `end`, if there is a block at all. It does not imply
last-expression returns or a guarantee that captures disappear. Separately, `endall`
is implemented as bounded trailing-block closing sugar; see
[operators-and-blocks.md](operators-and-blocks.md#endall-flat-continuation-spines).
Current conservative captured-word materialization limits still apply, even with
literal arguments. This deliberately replaces the earlier trailing-block append rule.

## Vocabulary parameters — shared live-place opening

`ctx...` receives one ordinary parameter and expands its names. `...: T` receives
and opens one unnamed home; `...args` remains an ordered rest requirement. There
is no arity inference or type-dependent reinterpretation.

```let
window("Mini") do(ui...)
  title "Mini"
end
```

means `do(ui) let ui...; title "Mini" end`. Named definitions and expression bodies
permit the same marker. At most one parameter is opened, at the first runtime
requirement after leading static `Type` requirements. Foreign declarations reject
opening. Named parameters remain available; unnamed homes introduce no identifier.

```let
let configure(...: Ref(Window), title_text: String): Unit = do
  set_title(title_text)
  return
end
let squared(...: Point): F64 = x*x + y*y
window("Mini") do(...) set_title "Mini" return end
```

Opening occurs at word entry for both body forms. Its type must be known from an
annotation or checked callback signature; an anonymous home does not default to
`Any`. Bare `...`, normally grouped as `(...)`, reads the innermost retained runtime
home. `(configure)(..., text)` is explicit ordinary argument passing; grouping the
callee bypasses receiver insertion. `...expression` still expands supplies.
Parenthesize a bare home before a following expression-start token, or terminate
its supply with a comma, semicolon or closing token. Newlines are not separators.

Whole-home assignment rejects `context-use`. For a reference home, `Ref(...)` or
`Ptr(...)` cannot expose its private retained pointer holder; pass `(...)` itself
or borrow a field place. For a by-value record home, `Ref(...)` borrows the ordinary
parameter place with its normal lifetime limits. Field writes, snapshots and
captures retain ordinary permission/ownership rules. Home is an argument/place
identity, not an address guaranteed to be physical C0. Module/sum name expansion
creates no runtime home; bare `...` without a runtime receiver rejects `context-required`.

Opening must reuse ordinary binding-spread elaboration, `spread-shadow` checking
against every visible name, and existing capture/lifetime/ownership rules. The
**implemented live-place revision** replaces record field snapshots
with immutable names denoting the retained receiver's actual field places. Module
and sum aliases continue to expose existing definitions. There is no new permission
to mutate frozen/readonly state, detach a method, discover a dynamic namespace or
invent a callable identity. Receiving names does not invoke them: a nullary pipeline
step still needs `resolve_names()`.

Receiver routing is implemented: an otherwise-unbound `nudge(10)` can mean
`ui.nudge(10)`. The selected first parameter decides value copy or reference borrowing;
ordinary arguments remain explicit. Opening a reference context keeps its actual
referent; opening a by-value parameter concerns that copy. Local callables stay
ordinary; opened callable fields keep their signatures and, under the new contract,
are read from their current field places. Nested words using an opened field must
retain that place, even for a scalar field. Explicit saved values retain normal value
capture behavior. Binding-resolved capture machinery now preserves that distinction
using existing place inputs, including through intervening and recursive words.
See [spread.md](spread.md#5-introducing-names-let-context) and
[application-sugar.md](application-sugar.md#31-receiver-scopes).

**Implemented:** `ctx...`, `let context...`,
`let context... = expression` and `use module...` share semantic expansion; prefix
binding/import spellings reject. Runtime record/callable-field DSLs, namespace aliases
and sum-constructor aliases have four-mode execution coverage. Initialized contexts
retain their ordinary explicit binding; a bare `let context...` reads an existing one.
Type/function exports now share one public namespace: duplicate public names reject
across sections, an approved source compatibility change. Module aliases carry definition
identity, not runtime objects. Record opening now projects actual field places; module
aggregate storage now has bounded pointer-free working-tree qualification, but
higher-order retention proofs remain incomplete; see
[module image copying](module-image-copy.md). No implicit module-valued parameter
transport is added. Updated vocabulary validation: 92 checks / 64 four-mode executions,
including a separate run with pre-packed lowering. Existing capture ownership and aggregate
staging restrictions remain; illustrative resource DSLs still depend on their library and
closure support. See WORKLIST.md and the vocabulary evidence for scope and code-size costs.

## Braces have explicit contexts

- Bare schema braces define data requirements and methods.
- Reserved `oneof { ... }` defines a sum schema.
- Other headed braces supply values; their contents never select schema-argument
  application by lookahead.
- To pass a schema to an ordinary word, write `f({ ... })`.

`oneof` is a reserved keyword, not a callable, aliasable or shadowable binding.
Its form is `oneof { name: type, ... }`; the old `oneof({...})` spelling is not an
alias. Alternatives remain a nonempty, statically known set of payload types;
methods are not alternatives. Existing sum representation and matching semantics
are unchanged.

```let
let Shape = oneof { circle: CircleShape, rect: RectShape }
let area(s: Shape): U32 = s {
  circle(c) = c.radius * c.radius,
  rect(r): U32 = do return r.width * r.height end,
}
```

In a keyed value supply, these entries mean:

```let
circle = do(c) = c.radius * c.radius
rect = do(r): U32 return r.width * r.height end
```

They are ordinary callable values: no implicit receiver, detached schema method,
lexical self-name, overload registry or special handler execution mechanism. Their
context supplies the usual expected signature. Evaluation/capture order is ordinary
supply order. The same `name(parameters): result = body` in a **schema literal** is
still a method, with its existing receiver binding.

`Table { save(editor) = editor.save() }` illustrates the target table vocabulary;
this sugar does not implement the COW table runtime. Legacy dynamic/open-word IR
paths remain assigned to D03, not a new implementation of tables or packs. The
current frontend still parses legacy bare open supplies; they are not the target
record-schema/value-table contract.

## Compiler ownership of the responsibility

`source_state.lua:word` creates the name-free computation description. Its contract
and inferred results are request-local, not annotations written into reusable ASTs.
`semantic.lua:wordContract` checks interfaces; `elaborateWord` owns parameter storage,
lexical captures, body checking, normal return/defer handling and ordinary `Ir.Fn`
emission. Module/local bindings supply visibility and recursive names; schema method
bindings supply receiver state. The legacy dynamic-method binding also reuses that
body elaborator without extending its runtime contract.

Capture commitment now follows actual binding lookup. Visibility/interface queries are
noncapturing; a selected outer runtime binding is transported through each intervening
lexical frame, with shared holdings deduplicated. Compile-time definition aliases remain
identities. The implicit receiver uses this same mechanism. The old syntactic
`resolve.lua` capture pass and receiver-call candidate heuristic are removed.

Visible contracts and word identities are reserved first. Bodies elaborate once; finite
capture dependencies on enclosing recursive words settle when their bodies finish.
Hidden parameter prefixes, call/defer arguments and view/adapter layouts then finish
consistently. Pending transport is barred from verification and static execution.
First-class ownership checks run against the complete capture set, not an earlier empty
prefix. Capture-free words inside receiver scopes need no receiver environment.

Sum handlers use this same elaborator, including expression bodies; handler values are
constructed in written order before dispatch and invoked by ordinary direct/indirect calls.
This replaces the old expression-handler inline path, so code size and call overhead can grow.
There is no new source inliner or handler evaluator.

The separate named/lambda parameter and body builders and the lambda-only capture
permission flag are removed. In the executable typed profile, materializing captures
is conservatively rejected for either spelling until owned capture support exists.
Direct known calls can use ordinary frame transport without materializing a callable.
This is not a claim that owned/escaping closures are implemented in the dynamic
profile: its runtime lowering boundary remains in place.

Oneof has a dedicated `SumSchema` AST node. Keyed callable-entry syntax produces the
same `FieldSupply` containing `Lambda` as the explicit spelling. Syntax nodes may
retain their written binding form for diagnostics; they do not choose different
word computation algorithms. ABC encoding, continuations, operand banks, scalar
computation and allocator ownership are unchanged.

## Validation

`frontend/tests/word_bindings.lua` covers spelling equivalence, inferred/recursive
contracts, forward references, aliases and shadowing, nested captures, by-value
record parameters, identical conservative capture rejections, imports/exports,
keyed handler sugar, schema receiver behavior, reserved-oneof rejection and deferred
rest elaboration. It checks ordinary IR counts as well as four-mode VM outputs.
The worklist and experiment evidence own actual run results, not this specification.
No formatter implementation or performance guarantee is implied by canonical spelling.
