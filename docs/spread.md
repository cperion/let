# Supplies, spread and packs

**Status: vocabulary, ordered/keyed supplies and source-only rest/template
specialization are implemented within current admission and partially qualified.**
The spread suite passes all unoptimized four-mode cases; eight optimized configurations
are blocked by the independently reproduced optimizer frame-access defect. Other
optimized cases pass. Module binding vectors share one accepted initializer execution.
Rest templates use qualified formation anchors: selected value captures snapshot at
definition time; opened places remain live. The integrated rest suite validates direct/
indirect adapters, recursion, captures and source-only imports/exports. See
[spread evidence](../research/experiments/frontend-syntax/spread/README.md) and
[the vocabulary evidence](../research/experiments/frontend-syntax/vocabulary/README.md).
This document specifies
static spread, packs and name introduction for the unified `.let` language. It
extends [syntax.md](syntax.md), using the existing value/place/ownership contracts.
The ordered/keyed/rest architecture and its source formation-point extension were
approved and implemented. This does not enable runtime-arity calls or restore open-word machinery.

## 1. Principle and scope

Prefix `...e` expands an evaluated source into the enclosing supply. A final ordered
rest requirement `...args` collects remaining components into a static-shape pack.
Suffix `context...` introduces an existing or newly bound context's eligible names.
Spread is not a standalone value operator, tuple constructor or recursive flatten.

| Context | Accepted source | Contribution |
| --- | --- | --- |
| Ordered argument, return or binding-initializer list | Statically known result vector, pack, fixed array | Ordered components |
| Fixed-array construction | Same statically shaped ordered sources | Ordered elements, checked against element type and total length |
| Keyed initializer/application | Record with statically known data fields | Named data-field supplies |
| `let context...` / `let context... = e` | Module, record, sum type with statically known names | Local names as specified below |

Runtime-length list expansion is deferred, including its construction syntax.
Runtime table-key expansion into fixed keyed calls is not included. Neither
`f(...some_list)` nor spreading an opaque `Any` is a runtime argument dispatcher.
Spreading into concatenation `..` is also deferred: no implicit reduction, separator
or empty-input rule is invented. Builtin `..` concatenates two strings or two lists
of the same element type; it does not accept a runtime-length spread/reduction.

## 2. Evaluation and ordered expansion

Evaluate each supply expression once, left to right. Expansion neither reorders
operations nor suppresses effects of values ultimately discarded or overridden.
Every contributed component obeys ordinary value transport, copy/move, borrowing,
owner and group-lifetime rules. Expansion is not a source of mutable aliases.

For explicit ordered spread:

1. Multiple results contribute those results directly.
2. A single result expands according to its kind: a pack contributes its components,
   a fixed array contributes its elements. A scalar has no spreadable structure.
3. Components are not recursively expanded. An array among multiple results stays
   one argument. Records expand only in keyed or named-binding contexts, not by
   silently choosing a field order for positional calls.

Thus `...make_array()` expands a sole array result, while `...two_results()` contributes
exactly two components even if one is an array. Statically unknown result arity
rejects. Existing unit-result semantics are unchanged: spread does not invent an
empty result vector for a unit-returning call. An empty pack contributes zero
components. Spread does not introduce zero-length arrays: syntax.md's current target
requires positive fixed-array lengths. Accepting zero-length arrays needs a separate
explicit decision, not an inference from spread.

Explicit spread works at any list position:

```let
f(...pair(), last)
let a, b, c = first, ...pair()
return ...args
```

Unmarked expressions keep section 6's rules: nonfinal expressions contribute one
result, the final expression contributes its result vector. Explicit spread replaces
that adjustment for its own item; it is never expanded twice. A final unmarked array
is still one argument. Parenthesizing an expression adjusts its result vector before
spread inspects the resulting value, so `...(pair())` does not recover discarded
results. This preserves existing forwarding rather than changing all final values
into automatic container spreads.

After expansion, ordinary call saturation/partial-supply and arity checks apply.
Binding lists retain surplus-discard/unit-fill behavior; returns retain exact result
contracts. Fixed-array element checking follows expansion, with static total length.
No foreign variadic ABI is introduced.

## 3. Packs and rest requirements

A word may have one unannotated rest requirement, last in its ordered parameter list.
Named-definition sugar and an equivalent literal-do binding have the same privilege:

```let
let logged(T: Type, f: T, ...args) = do
  log "calling"
  return f(...args)
end

let result = logged((U32): U32, twice, 21)
```

`t` is an explicit static calling requirement; `f` supplies an implementation of
that requirement. Supplying a noncallable type does not make it callable: ordinary
checking rejects the application in the body. Known code identity permits direct
specialization; a runtime callable with that known signature uses ordinary indirect
transport. The signature fixes the ABI even when the implementation is unknown.

This is the approved generic adapter pattern, not `logged(f, ...args)` with a
silently generic `f`. An unannotated named parameter still defaults to `Any`, with
its normal dynamic/transferability restrictions. No implicit type parameter, new
`callable` keyword, runtime pack or special `Any` treatment is introduced. `log`
and `twice` above are illustrative definitions supplied by the program.

A pack has a statically known length and per-component types, but its values may
be runtime values. It is second-class source metadata plus component values, not
a runtime tuple or dynamically sized argument object.

Permitted operations:

- `...args`: contribute the components to an ordered supply;
- `args.length`: static length;
- `args[i]`: select a component using a static, in-range integer index.

Packs cannot be assigned as ordinary values, placed in records/arrays/`Any`, captured
as pack objects or returned as one object. Individual components may be used or
captured under their normal contracts; `return ...args` returns the components,
not the pack. No ordinary `pack` runtime type or layout is introduced. Each component
retains its owner provenance, borrow extent and scoped-capability bounds.

Once all preceding requirements are satisfied, the rest accepts zero or more
components and the call is saturated. If preceding requirements remain missing,
existing static partial-supply rules still apply. A rest requirement is not an
unfilled slot that delays invocation indefinitely. There is no keyed rest, rest
destructuring, C varargs or rest parameter annotation in this first scope.
Literal-do binding syntax shares this rest form, so naming sugar grants no extra pack capability.
Pack elaboration uses ordinary typed component inputs. Unspecialized templates remain
source definitions, including public imports/exports, not erased variadic ABC entries.
This does not specify first-class erased variadic signatures or foreign varargs.

Packs can support library formatting through specialization. They do not alone
make every format static: compile-time format checking additionally requires a
known format string and the VM-backed source evaluation machinery. Runtime format
strings retain runtime checks; no second compile-time string evaluator is authorized.

### 3.1 Invocation policies through ordinary specialization

An adapter specializes its static calling requirement and pack shape while retaining
runtime component values and their ownership/effect facts. For
`logged((U32): U32, twice, 21)`, the requirement and argument/result shapes are known;
if `twice` retains known code identity, lowering emits an ordinary direct call.
Otherwise a conforming runtime callable uses the same fixed-signature indirect ABI.
Neither case needs an allocated tuple, runtime varargs array or dynamic arity scan.
This does not guarantee call elimination, zero copies or allocation-free callee work.

Ordinary static partial supply specializes the policy's interface:

```let
let log_u32 = logged((U32): U32)
let a = log_u32(twice, 21)
let b = log_u32(square, 7)
```

Here `f` is still outstanding, so supplying `t` alone does not saturate the adapter
or consume a zero-length rest pack prematurely. Once the fixed requirements are
satisfied, rest accepts the remaining argument expressions under the normal rules.
The partial is static specialization, not a first-class erased variadic object.

### 3.2 Preserve results with return and defer

Pre-call work and exact tail-result forwarding use `return f(...args)`. Post-call
work that does not inspect the result components can use the existing defer contract:

```let
let traced(T: Type, f: T, ...args) = do
  print "enter"
  defer print "leave"
  return f(...args)
end
```

Order: register the action (evaluating its callee/arguments now), invoke `f`, obtain
its complete result vector, execute deferred work, then transport those results to
the caller. Preserve each result's live value and holding across the deferred call,
using ordinary return/defer machinery. There is no result-pack object or new hidden
calling convention. With outstanding deferred work, this is not a tail transfer that
can discard the adapter's continuation before running its action.

Deferred work runs only on normal completion, not after program-ending abort. If it
fails/aborts, normal result delivery does not occur. The adapter composes callee and
policy effects, including suspension where allowed; no effect or group-bound capture
is erased by the type requirement. `print` here is an illustrative library word.

`let result = f(...args)` does NOT name the complete result vector: ordinary binding
adjustment applies. Inspecting arbitrary returned components requires a separately
specified capability; argument packs do not imply result-pack bindings. Retrying
needs repeatability/failure policy; memoization needs keys, state and cacheability.
No generic purity, automatic replay or cache semantics are introduced by these examples.
Erased runtime variadic callable interfaces remain outside this scope; literal-do bindings
share the named form's source-level rest syntax and specialization path.

## 4. Keyed spread and record update

```let
point { ...p, x = 5 }
```

Each spread contributes only data fields, not methods. Names and field types are
statically known. The result uses ordinary construction and field-copy semantics,
not mutation of `p` or preservation of its instance identity.

- Explicit fields override spread fields regardless of textual position.
- Duplicate explicit fields reject.
- Two spreads contributing the same name reject, even if an explicit field would
  override that name later. There is no implicit first-wins or last-wins merge.
- Unknown fields reject, including fields that an explicit override would hide.
- All operands and initializer expressions execute in source order. Override chooses
  the supplied value, not which expressions execute. Observable copy/release effects
  cannot be silently removed; existing as-if/effect rules govern optimization.
- Already statically supplied or readonly requirements keep their existing protection.
  Spread cannot replace them by calling the operation a record update.
- The resulting effective supply follows existing type, missing-requirement and
  static partial-supply checks.

No bare `{ ...p }` record-value literal is introduced: keyed construction still
requires its schema/callee, such as `point { ...p }`. Dynamic tables retain their
separate COW value contract; table-to-table spreading is deferred, not implicitly
implemented by record spread.

## 5. Introducing names: `let context...`

Suffix `...` introduces vocabulary; prefix `...expression` expands supplies or
collects named rest requirements. Alone, `...` reads the current runtime home.
In parameters, `...: T` receives and opens one unnamed home. The forms are:

```let
let context...             -- expand an existing binding
let context... = make()    -- evaluate once, bind context normally, then expand
use std.text...            -- import, retain text, then expand
with_context(n) do(ctx...) -- receive one ordinary argument, then expand
  action()
end
with_context(n) do(...)    -- same operation, no user-visible context identifier
  action()
end
let squared(...: Point): F64 = x*x + y*y
```

A named context remains available for qualified access. An unnamed home is read
explicitly with `(...)`, including `(f)(..., other)` for ordinary explicit calls.
Type comes from its annotation or a checked callback signature, never from searching
values by type. One parameter may be opened, at the first runtime position after
leading static Type parameters; this applies equally to named and unnamed openings.
Opening is a word-entry operation, so both expression and block bodies are admitted.
Whole-home assignment rejects; the retained reference holder has no public address.
Record homes and field places retain ordinary checked borrow/lifetime rules. No
physical C0 placement, effect row or ownership-by-construction guarantee follows.

An initialized context uses
ordinary single-binding result adjustment, not a pack or a hidden namespace object.
To expand a computed expression, give it an explicit context name. The old prefix
binding/import spellings are rejected, not retained as aliases.

**Implemented within admitted typed contexts:** record opening exposes live field
places, not field-read snapshots. The rule is **open the context to work with it;
bind a value to remember it**. This intentionally supersedes the previous snapshot
contract; no parallel snapshot-opening mode or compatibility spelling is introduced.

The implementation has suffix forms, namespace/constructor aliases, receiver scopes
and binding-resolved place captures. Updated vocabulary tests pass 92 checks / 64
executions; receiver tests pass 407 checks / 384 optimized/unoptimized executions.
Full validation and isolation with pre-packed lowering pass. Evidence:
`research/experiments/frontend-syntax/live-opening-endall/`. Historical snapshot logs
remain historical. WORKLIST X07 records remaining admission limits: module aggregate
storage, broader owned closures and frozen/readonly proofs are not added by opening.

Otherwise-unbound bare calls use the retained receiver; actual members win over lexical
words, and the selected first parameter determines copy versus borrow. Locally bound
callables stay ordinary. An opened callable field is read from its live place and
invoked with its own signature, without an inserted receiver argument. Nested openings
choose the innermost receiver, never search for a matching signature. `(name)(args)`
or namespace qualification bypasses implicit receiver insertion. Module/sum openings
introduce definitions, not runtime receivers or namespaces.
See [application-sugar.md](application-sugar.md#31-receiver-scopes).

Introduce all eligible names from the context into the current lexical scope:

| Source | Names introduced |
| --- | --- |
| Module | Public exported words, types and values, resolving to the same exported definitions |
| Record or reference-to-record | Immutable names for live field places of the retained receiver |
| Sum type | Its alternative constructors |

A field name is bound to a logical place, not to its contents at opening time. Reading
it has the same value-read semantics as qualified access through the retained context.
Writing it stores to that field if the place is writable; it does not rebind the name.
Readonly/frozen access remains readonly/frozen. Opening itself does not eagerly read
or copy all fields. Methods remain attached to the receiver; opening does not introduce
detached method bindings or change existing explicit bound-method behavior.

Establish the context once. An initializer runs once and a reference context retains
its actual referent; field access does not reevaluate the initializer. Opening a
by-value parameter still concerns that parameter's copy, not the caller's object.
Use a reference parameter when the activity must operate on the caller's actual state.
Place identity, owner retention and copy-on-write behavior follow ordinary place rules;
do not freeze a backing-store address or manufacture an independently owned copy.

`let saved = field` reads an ordinary value, like `let saved = context.field`; it
introduces no second live projection. This does not deep-copy reference referents or
change ordinary instance-alias rules outside field reading. A nested word using an
opened field retains access to that field's place, even for a scalar field. Captures
must preserve the place/owner/lifetime dependency rather than silently snapshotting its
contents. Existing escape restrictions still apply. Capture a deliberately saved value
when snapshot behavior is wanted; do not copy a context to bypass borrowing limits.

Runtime tables, result vectors, packs and arrays cannot introduce names. Modules do
not expose private declarations or their imports unless explicitly exported. Public
type/function exports share one namespace: repeated public spellings reject across
both sections.

Spread may not shadow. A collision with any visible name—including builtins,
parameters and earlier spread names—rejects `spread-shadow`; diagnostics name both
origins. File-scope collision checking also includes explicit declarations elsewhere
in that module, which are ordinarily mutually visible.

Spread-introduced names become visible **after** their declaration, including at
file scope; they are not automatically hoisted like explicit top-level declarations.
This prevents name discovery from recursively depending on evaluation of a later
spread. References in earlier function bodies cannot acquire later spread names
merely because the function is eventually called later. Existing initializer cycle
rules continue to apply to the spread source itself.

A binding spread does not automatically export anything. Ordinary explicit export
configuration still applies; no wildcard/re-export syntax is added. Module-definition
aliases require no runtime copying. Opening a record does not copy its fields, but
initialization, parameter passing, owner retention, value reads and captures still have
their ordinary effects and costs. No blanket zero-cost claim is made.

## 6. Import and spread sugar

```let
use std.text...
```

is exactly:

```let
use std.text
let text...
```

`text` remains available for qualified access. Import resolution, module initialization,
export filtering and import-cycle checking are unchanged; the module is not imported
or initialized twice. The namespace binding must satisfy ordinary import collision
rules, and its expanded names satisfy `spread-shadow` (including collision with the
namespace itself). Names are visible after the declaration and are not automatically
re-exported.

Like ordinary `use`, this is file-scope only. No selective list, renaming syntax,
local import or dynamic module discovery is introduced. `let record...` remains
available inside function bodies. Target discovery uses `.let` only.

## 7. Grammar additions

These extend, rather than replace, the grammar outline in `syntax.md`:

```text
spread-item       := '...' expression
supply-item       := expression | spread-item
supply-list       := supply-item (',' supply-item)* ','?
keyed-item        := Name '=' expression | spread-item
binding-spread    := 'let' Name '...' ('=' expression)?
vocabulary-param := (Name '...' | '...') (':' expression)?
rest-requirement  := '...' Name
current-context   := '...' (bare expression; group before an expression-start token)
use-declaration   := 'use' dotted-name '...'?
```

Argument/return/binding-initializer lists admit `supply-List`; keyed initializers
admit `keyed-item`. Existing array construction admits spread elements without
changing its type/length or empty-construction rules. Named ordered parameters admit
one optional final rest requirement, including a rest-only list. Ordinary parameter
grouping remains unchanged. Binding spread is a declaration, not `let a, ...rest = e`.

Lexing must distinguish `...` from `..` and `.` by longest token matching outside
strings/comments, without accidentally changing numeric literal tokenization. Exact
number/dot edge cases need lexer tests before implementation. Spread is not added
to the general expression precedence table.

## 8. Diagnostics and conformance

Diagnostic contracts (ordered/keyed spread and vocabulary diagnostics are implemented;
pack diagnostics are implemented in rest-template elaboration):

| Diagnostic | Cause |
| --- | --- |
| `spread-context` | Spread where no supported supply/declaration exists |
| `spread-source` | Unsupported source kind, opaque dynamic source or unknown arity/names |
| `spread-overlap` | Two keyed spreads contribute the same field |
| `spread-shadow` | Name introduction collides with an existing binding |
| `rest-position` | Repeated/nonfinal rest or unsupported requirement form |
| `pack-use` | Pack treated as an ordinary first-class value |
| `pack-index` | Nonstatic, noninteger or out-of-range component index |

Existing diagnostics remain authoritative for unknown keys, duplicate explicit keys,
arity, type mismatch, readonly/static requirements, imports and owner/group escape.
Do not replace those checks with a generic spread error.

Tests must cover one-time ordered evaluation, overridden effects, single-array versus
multiple-result expansion, nonrecursive flattening, parentheses, empty packs and
preserved rejection of invalid empty-array construction,
implicit final forwarding, unit results, return/binding differences, partial versus
rest-saturated calls, heterogeneous runtime pack components and rejected pack erasure.
Test keyed overlaps/unknown keys/readonly requirements; live opened field places versus
explicit saved values, nested mutation visibility, scalar/aggregate place captures,
reference-context identity and escape restrictions;
methods excluded; all module export kinds and sum constructors; builtin/namespace/
forward-declaration collisions; lexical visibility; sugar equivalence and single
module initialization. Include hidden owner/group bounds in components and rejected
runtime lists/tables/`Any` call expansion. Verify resulting ordinary IR and all
applicable execution bindings, not just parser acceptance.

Adapter acceptance additionally covers explicit callable requirements with known and
runtime callee identities; heterogeneous runtime argument components; single/unit/
multi-result forwarding; static type-only partial supply; wrong argument/signature
rejection; captures/ref/group bounds without any boxing; and deferred work that
clobbers registers, allocates or suspends while returned values remain live. Check
normal return/defer order and unchanged abort semantics with independent expectations.
Unannotated `f` must not be silently promoted to the explicit-requirement behavior.

Source elaboration must reuse existing value/place, demand and specialization
machinery, preserve existing scheduling and VM-only computation, and emit ordinary
checked IR. No runtime pack object, hidden ABC cells, new scalar engine or allocator
is authorized. Absolute specialization/code-growth samples are recorded in
[rest-template evidence](../research/experiments/frontend-syntax/spread/rest-templates/README.md).
They are not resource or speedup bounds. Measure copies, retains and initialization
costs before making performance claims.
