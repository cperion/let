# Types: the word is the type

Design record for the typing model. It is grounded in
[let-language-specification.md](let-language-specification.md) §3 and §11, and in
`let/ast.lua`, `let/parse.lua`, `let/belt.lua`, `let/contract.lua`, `let/vocabulary.lua`,
`let/resolve.lua`, `let/build.lua`, and `let/program.lua`. The specification is **sealed** for this
model; the compiler migration is tracked in §9.

## 1. The invariant

> A word is a chain of items whose last item is the terminal. Its type is that chain read as
> unary, right-nested arrows. There is one annotation form, `: W`, and its argument is a word.

```
WordType ::= T "->" WordType      -- one stage: a unary function
           | T                    -- data terminal
           | "do" T               -- runtime terminal
```

No parameter lists, no products in the type: `Int : Int : do R` is `Int -> (Int -> do R)`.

## 2. Types are words

A **type word** is a word built from primitives and constructors:

```
type-word ::= Int | U8 | U32 | Float | Bool | Unit | Text | CString | CPointer   -- atomic, not constructors
            | Type                                -- the classifier of type words
            | { let field : type-word ... }      -- product, keyed
            | type-word or type-word               -- sum (see §8)
            | type-word -> type-word              -- the unary arrow
            | do type-word                        -- the runtime terminal
            | Name                                -- a let-bound type word or constructor
```

A `let`-bound word used as a type denotes the type of its **terminal result**:

```let
let Point =
    let x : Int
    let y : Text
    do return { x, y } end
```

- as a type: `: Point` is the type of `{ x, y }`, nominal to `Point`.
- as a constructor: `Point(1, "a")` awaits `x`, then `y`, then returns the record.

The terminal kind makes construction pure or effectful with no new mechanism: a data terminal is a
pure constructor, a `do` terminal is a smart constructor / factory (allocation, invariants,
failure).

## 3. Surface

`annotation := empty | ":" type_expression`, and the existing `constraint_expression` is replaced:

```
type_expression := arrow_type
arrow_type      := sum_type [ "->" arrow_type ]        -- unary, right-nested
sum_type        := apply_type { "or" apply_type }      -- tagged union
apply_type      := atom_type { atom_type }             -- juxtaposition: List Int
atom_type       := NAME { literal }                    -- a type word, optional C spelling
                 | record_type
                 | "(" type_expression ")"
                 | "do" type_expression
result_type     := result_sum [ "->" result_type ]     -- a terminal result: no adjacency
result_sum      := atom_type { "|" atom_type }
record_type     := "{" { SEP } "}"
                 | "{" { SEP } named_type_member { { SEP } named_type_member } { SEP } "}"
                 | "{" type_expression { "," type_expression } [ "," ] "}"
named_type_member := "let" NAME [ "mut" ] ":" type_expression
```

A record type uses the **regular aggregate form**: the same braces and `let` members, with a type
where a value aggregate writes a value. A `let x : T` member is a stage, so the aggregate is a word
awaiting its fields -- the record's constructor and its type; a `let x = v` member is a prelude, so
the aggregate is the value. There is no separate `{ x : Int }` notation.

A stage **must** declare its type word, and a runtime terminal **must** state its result: `do : T`.
The result is parsed as `result_type` (arrows and `or`, no top-level juxtaposition) so a name-starting
body is not swallowed; write `do : (List Int)` for an applied result. A data terminal needs no
written result -- its type is the type of its terminal expression, composed from the declared stage
types (no unknowns, so not inference). The declaration makes the word's type readable without
reading the body, which is what removes inference and types self-recursion, mutual recursion and
host entries from the declaration alone. Control `do` regions (`if`/`while`/`switch`) state nothing.

`extern` keeps its boundary-only C spelling as a distinct argument (`Int "size_t"`), not part of
the type word.

## 4. AST (`let/ast.lua`)

Replace `Constraint = (string name, Expr* arguments)`:

```
TypeExpr = Ref(string name, Expr* arguments)      -- a type word by name, optional C spelling
         | Apply(TypeExpr constructor, TypeExpr argument)   -- `List Int`
         | Arrow(TypeExpr from, TypeExpr to)
         | Sum(TypeExpr left, TypeExpr right)      -- type position
         | Do(TypeExpr result)
         | Record(TypeField* fields)
         | Tuple(TypeExpr* elements)
         attributes (Source.Span span)
TypeField = (string name, boolean mutable, TypeExpr type, Source.Span span)
Expr = ... | SumType(TypeExpr left, TypeExpr right)  -- legacy `Int | Text` in value position; now `A.Or`
```

`Binding.constraint`, `Stage.constraint`, `Extern.result`, and `Extern` parameters all carry
`TypeExpr?`. `Terminal = Data(Expr) | Body(Stmt*, TypeExpr? result)`. The field keeps the name
`constraint`; the node it holds is a `TypeExpr`.

## 5. Belt (`let/belt.lua`)

Add the type forms and the classifier:

```
Type = ... | Named(string) | Aggregate(Field*, boolean, string? name) | Word(...)
     | Callable(Signature signature)
     | Arrow(Type from, Type to)      -- a stage holding a word
     | Do(Type result)                -- the runtime terminal modality
     | Sum(Type* alternatives, boolean is_copy)
     | TypeWord                       -- the compile-time classifier of type words
```

`Sum:record()` is the tagged shape (tag field first, then one field per alternative), so the
existing `Construct`/`LoadField` machinery builds and projects a sum and the C emitter writes it as
a struct. `Callable` is retained for hosts (not folded into `Arrow`), and `Function.signature` is
still the belt signature. Nominal identity is `B.Aggregate.name`; `Named` marks resources.

## 6. Checking

`contract.lua` stops estimating and starts **assembling and checking**:

- `: E` must be a compile-time-known type word. Evaluate `E` in the construction phase; a runtime
  dependency or a non-type value is a located error.
- A stage `let x : T` is the arrow `T ->`; every supplied argument and every use of `x` is checked
  against `T`. Modes `copy | own | mut | own mut` are the stage capability; `Copy` is `mode=copy`.
- A terminal `do : R` is checked against every `return`; a data terminal's type is its expression's
  type. Nominal references compare by binding.
- Errors are always *declared vs used*. A missing declaration is an error; nothing is inferred.

`Context:constraint` becomes `Context:check(annotation, type_, span)`. The `Copy` / `Executable`
branches are deleted: `Copy` is a mode and `Executable` is a stage whose type is an `Arrow`.

## 7. Runtime type values (deferred)

First-class runtime type values are **deferred** (specification §18; `code-emit` is deliberately
skipped): a program that uses a type word as a value is rejected, so nothing escapes to describe.
`Type` is implemented now as the compile-time classifier (`Belt.TypeWord`), not a runtime
descriptor.

If built, a type word may reach runtime and a **data** value never carries its type; the tag belongs
to the type value (primitive → tag, record → descriptor aggregate, arrow/do → spine descriptor,
sum → tag + payload descriptor, nominal → a unique id). Only types that escape are emitted.

## 8. Sums: tagged unions

Products come free from aggregates. Recursion (`Option`, `List`) needs a sum. A sum is a **tagged
union** `A or B or C`, named by a `let`: `let Opt = Int or Text`. A sum type is a word with derived
members:

- `T.left v` / `T.right v` are the **injections**, one per alternative (juxtaposition);
- `v.tag` is the tag and `v.left` / `v.right` project the active payload;
- **elimination is `switch` on `v.tag`** -- chosen over a generated `match` word because `switch`
  already branches on Int literals and the tag is an Int, so no new construction word or
  pattern-matching syntax is needed.

**Implemented** as a tagged record: the tag field first, then one field per alternative, built and
projected with the existing `Construct`/`LoadField`, emitted as a C struct. A sum is Copy exactly
when every alternative is Copy; inactive payloads are zero-filled, so a non-Copy alternative is
rejected. The tag is the runtime discriminator (§7). Generic sums (`Option a`) work through the
type-word application of §11.2. A generated `match` handler-fold and non-Copy payloads remain
future work.

### Union formation moved onto `or`

`|` is the loosest expression operator (§3.4) and cannot also be bitwise OR, which must bind
tighter than comparison: one token cannot have two precedences. `or` is already the loosest
left-associative operator, so the union moves onto it. `or` is *disjunction*, and the phase
decides what disjunction means: `Bool or Bool` short-circuits at runtime (§13.1), while
`Int or Text` forms the tagged union at construction. This is the phased dictionary doing its
job, not a second meaning: the operator is one, the phase selects the entry.

Consequences: the grammar in §3 reads `sum_type := apply_type { "or" apply_type }`, and the
`|` row is removed from the expression precedence table, freeing `|` for bitwise OR. The parser
no longer coerces `|` operands to type-word `Ref`s; `A.Or:build` dispatches on the operand
types (Bool versus type words), so the union decision moves from parse time to construction.
The union is therefore not a distinct AST node; it is an `A.Or` resolved by phase.

`|`, `&`, `^`, unary `~`, `<<` and `>>` are now the bitwise operators (§13.2). They bind tighter
than comparison and looser than `+`; a shift count is reduced modulo 64 and `<<` keeps the low
bits, so no shift is undefined and no shift traps.

## 9. Migration

Each step keeps `luajit test/all.lua` green, regenerates `dist/let.lua`, and emits identical C where
semantics are unchanged (the DESIGN.md acceptance rule).

1. **[done] TypeExpr + parser.** `TypeExpr` replaces `Constraint`; the §3 grammar parses; `->` and
   `->`, `or`, and the bitwise spellings are tokenized; `do : T` parses.
2. **[done] Resolve / vocabulary.** `resolve.lua` resolves `TypeExpr` names like any word;
   `vocabulary.lua` is a type registry with `resolve_type`; the third phase is gone.
3. **[done] Contract → checker.** `Context:constraint` → `Context:check`; a declared `do : T` is
   authoritative and checked; a data terminal has a result.
4. **[done] Word type in belt.** `Arrow`/`Do`/`Sum` exist; `host_entry` errors instead of skipping.
5. **[done] Explicit annotations.** A stage must declare its type word and a runtime terminal must
   state its result; the parser enforces both and the corpus carries them. `options.parameters` is
   gone.
6. **[open] Runtime type values.** Type values are not yet values; nothing escapes to describe.
7. **[done] Sums.** §8: tagged unions, injections `T.left`/`T.right`, tag/projection, `switch`
   elimination, Copy alternatives.
8. **[done] Nominal records.** A stage aggregate's constructor brands its record, so same-shaped
   constructors are distinct types; a `let`-bound word names a type.
9. **[done] Bitwise operators.** `& | ^ ~ << >>` are Int-only across `verify`, `build`, `op`, and
   `emit`, with `LET_SHL`/`let_shr` fixing the shift semantics.
10. **[done] Fixed-width integers.** `U8` and `U32` are atomic type words (§13.2): Copy, never
    implicitly converted, and every operation reduces modulo `2^width`. `u8 x`/`u32 x` are the
    explicit crossings. `Op.kind` is the one place the width of a result type is read, so
    folding, the interpreter oracle, and the emitted C agree.

## 10. Deleted

- specification §11 as a constraint-word phase; the third dictionary phase in §12.1;
- `Copy` and `Executable` as vocabulary/phase words;
- `contract.lua` inference (the `memo` fixpoint, `.inferred`, `options.parameters`);
- `program.lua` `host_entry_skips` and the "no type without an argument" path;
- `build.lua` `Context:constraint_type` and the shadowing diagnostic.

## 11. Open decisions

1. Descriptor representation and comparison for runtime type values (deferred with `code-emit`).
2. A generated sum `T.match` handler-fold, and non-Copy sum payloads -- the current elimination is
   `switch` on the tag, and inactive payloads are zero-filled.

Decided and implemented: explicit annotations with no inference; `Type` and generic type words
applied by juxtaposition; nominal record identity; tagged unions by injection + tag + `switch`.
