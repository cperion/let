# Supplies, spread and packs

**Status: agreed source design direction; not implemented.** This document specifies
static spread, packs and name introduction for the unified `.let` language. It
extends [syntax.md](syntax.md), using the existing value/place/ownership contracts.
Concrete elaboration interfaces and the open details below require approval before
implementation. It does not enable runtime-arity calls or restore open-word machinery.

## 1. Principle and scope

`...e` expands an evaluated source into the enclosing supply. A final ordered rest
requirement `...args` collects remaining components into a static-shape pack.
Spread is not a standalone value operator, tuple constructor or recursive flatten.

| Context | Accepted source | Contribution |
| --- | --- | --- |
| Ordered argument, return or binding-initializer list | Statically known result vector, pack, fixed array | Ordered components |
| Fixed-array construction | Same statically shaped ordered sources | Ordered elements, checked against element type and total length |
| Keyed initializer/application | Record with statically known data fields | Named data-field supplies |
| `let ...e` | Module, record, sum type with statically known names | Local names as specified below |

Runtime-length list expansion is deferred, including its construction syntax.
Runtime table-key expansion into fixed keyed calls is not included. Neither
`f(...some_list)` nor spreading an opaque `any` is a runtime argument dispatcher.
Spreading into concatenation `..` is also deferred: no implicit reduction, separator
or empty-input rule is invented. Existing `..` remains a binary string operation.

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
empty result vector for a unit-returning call. A zero-length array or empty pack
can contribute zero components.

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

A named word may have one unannotated rest requirement, last in its ordered
parameter list:

```let
let logged(f, ...args) = do
  log("calling")
  return f(...args)
end
```

This example requires `f` to retain a statically known callable identity/signature
through specialization. An opaque dynamic `any` does not acquire that knowledge
from pack syntax; automatic generic callable specialization is not implemented by
this declaration alone.

A pack has a statically known length and per-component types, but its values may
be runtime values. It is second-class source metadata plus component values, not
a runtime tuple or dynamically sized argument object.

Permitted operations:

- `...args`: contribute the components to an ordered supply;
- `args.length`: static length;
- `args[i]`: select a component using a static, in-range integer index.

Packs cannot be assigned as ordinary values, placed in records/arrays/`any`, captured
as pack objects or returned as one object. Individual components may be used or
captured under their normal contracts; `return ...args` returns the components,
not the pack. No ordinary `pack` runtime type or layout is introduced. Each component
retains its owner provenance, borrow extent and scoped-capability bounds.

Once all preceding requirements are satisfied, the rest accepts zero or more
components and the call is saturated. If preceding requirements remain missing,
existing static partial-supply rules still apply. A rest requirement is not an
unfilled slot that delays invocation indefinitely. There is no keyed rest, rest
destructuring, C varargs or rest parameter annotation in this first scope.
Lambda rest parameters and first-class erased variadic callable signatures are
not specified by the named-word form; they require an explicit follow-up contract.

Packs can support library formatting through specialization. They do not alone
make every format static: compile-time format checking additionally requires a
known format string and the VM-backed source evaluation machinery. Runtime format
strings retain runtime checks; no second compile-time string evaluator is authorized.

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

## 5. Introducing names: `let ...e`

Evaluate `e` once and introduce all eligible names into the current lexical scope:

| Source | Names introduced |
| --- | --- |
| Module | Public exported words, types and values, resolving to the same exported definitions |
| Record | Data fields as immutable bindings holding ordinary field-read copies |
| Sum type | Its alternative constructors |

Methods are not detached from record receivers. Runtime tables, result vectors,
packs and arrays cannot introduce names. Record snapshots do not observe later
writes to the original fields. Modules do not expose private declarations or names
of their own imports unless those names are explicitly part of the export contract.

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
aliases require no runtime copying, but record snapshots may allocate or retain.
No blanket zero-cost claim is made.

## 6. Import and spread sugar

```let
use ...std.text
```

is exactly:

```let
use std.text
let ...text
```

`text` remains available for qualified access. Import resolution, module initialization,
export filtering and import-cycle checking are unchanged; the module is not imported
or initialized twice. The namespace binding must satisfy ordinary import collision
rules, and its expanded names satisfy `spread-shadow` (including collision with the
namespace itself). Names are visible after the declaration and are not automatically
re-exported.

Like ordinary `use`, this is file-scope only. No selective list, renaming syntax,
local import or dynamic module discovery is introduced. `let ...record` remains
available inside function bodies. Target discovery uses `.let` only.

## 7. Grammar additions

These extend, rather than replace, the grammar outline in `syntax.md`:

```text
spread-item       := '...' expression
supply-item       := expression | spread-item
supply-list       := supply-item (',' supply-item)* ','?
keyed-item        := Name '=' expression | spread-item
binding-spread    := 'let' '...' expression
rest-requirement  := '...' Name
use-declaration   := 'use' '...'? dotted-name
```

Argument/return/binding-initializer lists admit `supply-list`; keyed initializers
admit `keyed-item`. Existing array construction admits spread elements without
changing its type/length or empty-construction rules. Named ordered parameters admit
one optional final rest requirement, including a rest-only list. Ordinary parameter
grouping remains unchanged. Binding spread is a declaration, not `let a, ...rest = e`.

Lexing must distinguish `...` from `..` and `.` by longest token matching outside
strings/comments, without accidentally changing numeric literal tokenization. Exact
number/dot edge cases need lexer tests before implementation. Spread is not added
to the general expression precedence table.

## 8. Diagnostics and conformance

Proposed new diagnostic names (not implemented):

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
multiple-result expansion, nonrecursive flattening, parentheses, empty arrays/packs,
implicit final forwarding, unit results, return/binding differences, partial versus
rest-saturated calls, heterogeneous runtime pack components and rejected pack erasure.
Test keyed overlaps/unknown keys/readonly requirements; snapshots versus aliases;
methods excluded; all module export kinds and sum constructors; builtin/namespace/
forward-declaration collisions; lexical visibility; sugar equivalence and single
module initialization. Include hidden owner/group bounds in components and rejected
runtime lists/tables/`any` call expansion. Verify resulting ordinary IR and all
applicable execution bindings, not just parser acceptance.

Source elaboration must reuse existing value/place, demand and specialization
machinery, preserve existing scheduling and VM-only computation, and emit ordinary
checked IR. No runtime pack object, hidden ABC cells, new scalar engine or allocator
is authorized. Measure specialization/code growth, copies, retains and initialization
costs before making performance claims.
