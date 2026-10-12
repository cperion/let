# Words, bindings and keyed entries

## One computation, several spellings

A word owns its requirements, result contract, body, captures and code identity.
Names belong to bindings, not to a second kind of executable computation.

```let
let inc(x: u32) = x + 1
let inc = do(x: u32) = x + 1

let work(x: u32): u32 = do return x + 1 end
let work = do(x: u32): u32 return x + 1 end
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
let factorial = do(n: u32): u32 =
  if n == 0 then 1 else n * factorial(n - 1)
```

An ordinary initializer is not recursive: `let x = x + 1` cannot discover its own
new binding. Conditional/call-produced callable initializers do not gain recursive
scope merely because their result is callable. Keyed supplies do not create lexical
bindings for their keys.

File-scope literal-word bindings and named definitions are mutually visible, use
the same deferred result-contract demands and are equally exportable. Acyclic
results may be inferred. A recursive use that needs an unresolved result contract
currently requires an explicit annotation; no guessed `any` answer or general
result fixpoint is introduced. General unit/SCC completion remains a separate item.

Named keyed-requirement declarations use this same computation/elaborator, but a keyed
`do` surface form has **not** been added. The spelling equivalence demonstrated above is
for ordered definitions; a concrete keyed-literal grammar still needs approval before
claiming every named declaration has a literal spelling.

Final rest syntax is shared by named definitions and their literal-`do` bindings.
**Pack/spread elaboration is still unimplemented** and rejects explicitly. This
change does not implement runtime variadic signatures or runtime pack objects.

### Keep the named-body boundary

After a named definition's `=`, direct `do ... end` is its executed block body.
`do(` in that position rejects. Group a lambda returned by a named expression body:

```let
let make(x: u32) = (do() = x)
```

A lambda's own `=` always introduces an expression, so nesting needs no workaround:
`do(x: u32) = do(y: u32) = x + y`. Both returned examples remain subject to capture
lifetime/ownership support; their syntax does not authorize an escaping environment.

## Approved vocabulary-parameter sugar — deferred, not implemented

`ctx...` receives one ordinary parameter and expands its names; `...args` remains
an ordered rest requirement. There is no arity inference or type-dependent reinterpretation.

```let
window("Mini") do(ui...)
  title "Mini"
end
```

means `do(ui) let ...ui; title "Mini" end`. Named block definitions permit the
same marker: `let configure(ui...) = do ... end`. At most one parameter is marked;
expression bodies and foreign declarations reject it. The parameter remains available.

Expansion must reuse ordinary binding-spread elaboration: statically supported
record field snapshots or module-definition aliases, ordinary `spread-shadow`
checking against every visible name, and existing capture/lifetime/ownership rules.
No mutable aliases, detached receiver methods, dynamic namespace discovery or
invented callable identity are permitted. Receiving names does not invoke them:
a nullary pipeline step still needs `resolve_names()`.

**Implementation dependency:** the current frontend rejects `let ...value` with
`spread-unimplemented`; there is no binding-spread elaborator to reuse yet. The
marker approval does not establish implemented vocabulary expansion. Implementation is
deliberately deferred until the binding-spread work, rather than interrupting the
current word-unification checkpoint. Runtime record
snapshots and compile-time module namespaces need distinct, explicit producer
contracts before this can be reported as executable support.

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
let shape = oneof { circle: circle_shape, rect: rect_shape }
let area(s: shape): u32 = s {
  circle(c) = c.radius * c.radius,
  rect(r): u32 = do return r.width * r.height end,
}
```

In a keyed value supply, these entries mean:

```let
circle = do(c) = c.radius * c.radius
rect = do(r): u32 return r.width * r.height end
```

They are ordinary callable values: no implicit receiver, detached schema method,
lexical self-name, overload registry or special handler execution mechanism. Their
context supplies the usual expected signature. Evaluation/capture order is ordinary
supply order. The same `name(parameters): result = body` in a **schema literal** is
still a method, with its existing receiver binding.

`table { save(editor) = editor.save() }` illustrates the target table vocabulary;
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
