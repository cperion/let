# Let: design

## 0. Status

**This document is the specification.** It supersedes `ARCHITECTURE.md`, the previous `DESIGN.md`,
**and** [`let-language-specification.md`](let-language-specification.md). That draft was the input
this document re-derives, and it is kept only as the record of where the language came from: it has
remnants of designs that were abandoned, and reading it as authority is how those remnants come
back. Where the two disagree, this document is right, and §17 says why.

§17 is therefore a **ledger of decisions**, not a list of corrections proposed to something else.
It is still worth reading as deltas, because knowing what a rule replaced is what stops it being
quietly undone. [COMPILER.md](COMPILER.md) remains the coverage record.

The compiler is being rewritten against this document. The first phase's deliverable is **the
vocabularies and the context records** — not lowering code.

## 1. The language model

### 1.1 The thesis

> **One construct: the binding chain.** `with` applies it; invocation runs it; two executors
> evaluate it. Everything else is a consequence.

Three consequences, and they are the reason the model is small:

- **Types are words.** §11.1: a word's type is its chain read as unary right-nested arrows. There
  is no parameter list and no product type.
- **Records are aggregates.** §3.1: a record type and a value aggregate are the *same* form; a
  member is a stage (`let x : T`) or a prelude (`let x = v`).
- **Modules are chains.** §2.6: a source file *is* a binding chain; its top level is its items and
  its namespace is its terminal.

### 1.2 Two application forms

| Form | Meaning | Residual |
| --- | --- | --- |
| `with` `f with a with b` | stable specialization | **bound** |
| invocation `f(a, b)` | transient saturation | **a temporary** |

**Specialization is spelled, not juxtaposed.** Adjacency could not say where an argument *ended*, and
three things were paid for that. The grammar needed `;` to stop it, so a prelude followed by a written
terminal had to be written `let secret = 8;` before its `{ … }`. A parenthesized expression could not
GROUP after a word, because `(` there is the invocation suffix: `sum (square 3) (square 4)` is read as
`sum` invoked with the argument `square 3`, and the only way to pass a computed stage was to name it
first. And an accidental application was silent: `f a` applied, whether or not that was meant. `with`
says one argument at a time -- `f with a with b` is the left-associated chain adjacency was -- so a
parenthesized expression after it is a **group** (`f with (square 3)`), two adjacent expressions are a
mistake the parser REPORTS instead of applying, and an application can no longer be silent.
**`;` STAYS, and this is the correction the test suite made within one run** (§S88): it is not a
consequence of juxtaposition. `;` separates a prelude from a written TERMINAL, and both sides of that
boundary are expressions -- `let secret = 8` and then `{ … }` -- so a separator is needed however
application is spelled. What was never needed is `;` between two ITEMS, because `let`, `extern` and
`host` delimit themselves. The three uses of one mechanism keep their shape: values are `f with a`, a type is
`Box with Int`, and a module is `import with "codec.let" with JPEG with 90`.

They lower to the **same operations in the same order** (§1.2 already states the equivalence). They
differ in one thing: the lifetime of the intermediate residuals. That is what "invocation avoids a
separately persistent residual binding" means, and it is why argument/prelude interleaving falls
**out for free**: a chain's items interleave STAGES with PRELUDES, so a prelude that depends on a
supplied stage runs after that stage is supplied and before the next one is -- `g 1 2` for
`let p = a * 10` between two stages is `(1 * 10) + 2`. `test/native.lua` #26 reads that number,
which is the only thing that can tell the two orders apart, because both typecheck. This paragraph
used to end by claiming that case was still refused as `MissingWhy.PreludeBeforeNextArgument`: it
was not, the compiler lowered it correctly, and the name -- produced nowhere -- is deleted (§S72).

### 1.3 Two executors, two axes

```text
phase   Runtime | Construction      which executor runs the chain operations
purity  Pure    | Ordered           whether the compiler may fold them
```

- A **runtime** chain's operations are **emitted**.
- A **construction** chain's operations are **executed by the compiler**, shaping the enclosing code.

Phase is **declared**, never inferred, so §12.2's two directions are structural rather than
policed: a construction word has no emitted form to be retained as, and a runtime word cannot run in
the frontend because phase is not a function of its arguments. Purity is the separate axis that
permits folding.

This replaces §1.1's *"three distinct operations"* — which the spec itself undercuts with *"these are
not the same phase"*. The corrected form is **two application forms × two executors, plus forms**.

### 1.4 Values and references

**Values.** A non-Copy value has exactly one owner. It is moved or copied; a move leaves the source
unusable; destruction is reverse initialization order, at scope exit, on return, and on replacement.
There is no reference count, no tracing, and no collector.

**References are not values.** Let's surface has no reference concept. A reference appears only as a
*use*: a capability applied to a place at a point in the program.

| Use | Capability | Extent |
| --- | --- | --- |
| assignment destination `a.b = v` | write | the statement |
| read of a non-Copy place | read | the invocation |
| `mut x` | exclusive write | the invocation |
| a word's capture | read / mut | the enclosing lexical scope |
| a host-declared borrowed type | read | the scope that made it |
| self name / recursion | — | lexical, compile time |
| cycles | — | not a reference: a host arena (§1.4) |

**Recursion.** The self name is visible inside a terminal `do` body, which runs after the word is
constructed, and it is **not** visible in its own initializer or its stages, which are read while it
is being constructed. So `let a = a` is the design REFUSING a program -- there is no such name in
scope there -- while a word that names itself inside its body is an ordinary reference to an ordinary
definition. That is the whole of recursion: **no reference, no second instance, no new
representation.** The reference denotes the definition, `demand` reserves an instance's id before
lowering it (§12.3), and the recursive call is a call to the *same* instance -- `let fact_run` is
demanded once, and `fact 5` is 120. Mutual recursion is a forward reference and remains unknown: the
name of a definition is not visible in anything created before it.

**Every extent is a construct the compiler already computes.** Nothing is inferred, so no lifetime
appears anywhere in the language. That is the precise sense in which Let is simpler than Rust:
Rust's references are values with inferred lifetimes; Let's references are extents that are already
known.

Because a reference is never a value, its **representation is unobservable**, and the compiler is
free to represent it as a cell pointer or a handle.

### 1.5 The operators

The operators are a closed set -- §11.2 and §11.3 declare them -- and what each one **takes** is as
much a part of its typing as what it produces. The division is not the same one:

| Group | Takes | Produces |
| --- | --- | --- |
| `and` `or` `not` | `Bool` | `Bool` |
| `==` `!=` `<` `<=` `>` `>=` | `Int` | `Bool` |
| `+` `-` `*` `/` `%` `&` `\|` `^` `<<` `>>` | `Int` | `Int` |

Three things follow, and all three are what the compiler already does. **Arithmetic is `Int`**, whose
semantics are inline C rather than a helper function (§S33). **A comparison compares `Int`s** -- the
tag of a sum is an `Int` too (§3.5), which is why `switch` discriminates with the same operator a
program uses. And **truth is `Bool` to `Bool`**: `and` and `or` do not run their right operand when the
left decides, so they are control rather than arithmetic (§S35).

Precedence and associativity are **data** in the parser rather than a chain of functions (§S33), and
purity is the other axis: `/` and `%` trap on a zero divisor, so they are **ordered**
(`CheckedBinary`) while every other operator is pure and folds.

This rule is stated once, here, because three places must agree about it: §12.2 checks it, the belt
types the instruction by it, and `Known` folds by it. §1.5 is what they are agreeing *with*.

## 2. The chain

### 2.1 Structure

A template interleaves **prelude groups** and **stages**:

```text
group₀  stage₀  group₁  stage₁  …  stage_{n-1}  groupₙ  terminal
```

`group₀` runs at construction; `groupₖ` runs after stage `k-1` is supplied; `groupₙ` runs before the
terminal.

### 2.2 The residual

```text
R(t, k) = the record after k stable stages
          captures + stage values 0…k-1 + prelude bindings of groups 0…k
```

`R(t, k)` exists for `k ≤ p`, where `p` is the first `mut` stage's index — because a borrow is not
durable, so a `mut` stage cannot be stored. **A chain is transient from its first `mut` stage**, and
the remaining stage values and `mut` places are `run` parameters.

The *record* is structural. The *word type* is nominal in `(template, prefix)`:

```text
Semantic.Type  … | Word(number template, number prefix)
```

Nominality is required, not cosmetic: if `square` and `cube` had the same type, a word-typed stage
would admit either and the callee would need a uniform calling convention — a vtable. Nominal types
force monomorphization instead.

### 2.3 Operations

```text
construct_t   ()          -> R(t,0)      runs group₀
advance_k     R(t,k) × Dₖ -> R(t,k+1)    runs group_{k+1}, then constructs
run_t         R(t,n)      -> Result      runs the terminal
```

All three are **generated functions** built from `Construct`, ordered calls, and `CallFunction`. No
new belt operation exists for specialization.

### 2.4 Three uses, one mechanism

- **Values** — `scale with 2` is `advance₀`; `scale(2)` is the same transiently.
- **Types** — `Box with Int` (§11.2) is the same operations **evaluated at construction time and
  erased**. A type word is a chain with `Type` domains and a data terminal.
  `Type` is the NAME of the type a type value has -- a type value's type is already `Semantic.TypeWord`,
  so this is a name for an existing choice and not a new one -- which makes `let P : Type = { x : Int }`
  a name for a type; the surface is DECIDED and not yet built (the reference records the gap).
  **Erased is erased: there is no runtime type.** No `typeof`, no descriptor, no reflective tag --
  because erasure is what makes a type word vanish at construction time, and giving one runtime values
  would make erasure CONDITIONAL: every instantiation would carry a descriptor whether it uses one or
  not, and two instantiations could no longer be two words. What replaces each use of it: a runtime
  CHOICE is a sum plus `switch` (§S2); behaviour that VARIES is a continuation word bound at
  specialization (§S2 again -- pass the word, not the type); generic code is a `Type` domain applied
  with `with`, which MONOMORPHIZES; and printing, serialization and FFI are the HOST's (§3.6) or a
  word per type ("polymorphism is words").
- **Modules** — `import with "codec.let" with JPEG with 90` is
  `advance₀(advance₀(construct, JPEG), 90)`; the namespace is the terminal.

### 2.5 Copy is derived

`Copy` is not a choice and not a stored field. It is a method on a type:

```text
scalars, Unit, a Text literal        Copy
a record                             Copy iff every member is Copy and it declares no `mut` member
a sum                                Copy iff every alternative is Copy
```

The `is_copy` fields and §11.3's *"`Copy` is the `copy` capability"* are the remnant; §2.5 is the
correct reading, and the capability is `Read`.

### 2.6 The module

A file *is* a chain (§2), so its initializer is that chain's `run` (§2.3): the parameters are
the file's remaining stages, and the result is the module value.

```text
module value = { export : namespace,  state : whatever the namespace does not reach }
```

`state` is empty whenever the terminal is the implicit prelude aggregate -- the common case, and
the only one implemented -- so the module value **is** the namespace and nothing is added. (For a
WRITTEN terminal the module owns the terminal's value rather than the namespace's members, and `state`
is where what the namespace does not reach is kept: that half is not built, and `unload` is generated
only for the implicit namespace, because doing one half without the other would make the
written-terminal case leak silently -- which is worse than not offering it.)
The member exists because a written terminal may expose fewer bindings than the file has
preludes, and **every top-level binding stays alive until unload**: the returned value must own what
the namespace does not reach. A **written terminal chooses the export surface** -- a file with no
written terminal exposes the named aggregate of its own prelude bindings, in source order, and a
`do` terminal makes the file's result a word rather than a namespace.

```c
struct <namespace> <module>_init(<file stages>);   /* (void) when the file has no stages */
void <module>_unload(struct <module> module);       /* generated only when the module owns state */
```

- **Parameters** are the file chain's remaining stages. A root module with stages needs the host
  to supply them; that is the CLI's business, not the language's.
- **`unload`** takes the module value by value -- the host gives it up -- and destroys it in
  reverse successful-construction order. It is generated, and emitted only when the
  module owns something: a module owning nothing has no unload. It is a separate function rather than
  the tail of the initializer for the reason the sentence gives -- the initializer RETURNS the module
  value, so it cannot destroy what it returns -- and it is an ordinary belt function: its packet is the
  module value, its body binds the namespace's members from it and then runs the destruction pass §3.1
  rule 2 already asks for, and its result list is the effect ALONE, which is why its C prototype is the
  `void` above and why nothing in the emitter knows about it (§S80). It is a **third root** alongside
  the initializer and the entry points, demanded only when a namespace member's type has a destructor.
- **Host entry points** are separate functions, one per exported word, taking the module value
  plus that word's remaining stages; a word's fields come from the namespace. They are
  **roots of demand** (§S36): without that, an exported word nothing inside the module applies is
  demanded at prefix 0 only, so its terminal does not exist and the host cannot call it. The word
  value is read out of the namespace by its member index, which is why the initializer must
  construct it and why entries exist only for the implicit namespace.

In the belt the initializer is an ordinary function: parameter 0 is the effect, the result is the
namespace type plus the effect, and the entry packet **is** the ABI. The emitter drops the
effect, which is what makes the C signature `(<file stages>)` rather than carrying a token.

## 3. Ownership

### 3.1 The rules

```text
1. one owner       every non-Copy value has exactly one; a move leaves the source unusable
2. destruction     reverse initialization order, at scope exit / return / replacement
3. extents         a borrowed value's extent is the scope that made it;
                   no use may place it in a longer-lived position
4. borrowed        a derived property of a type, propagated structurally
```

That is the whole of ownership. There is no borrow checker, no aliasing analysis, no escape
inference, and no lifetime.

### 3.2 Captured state lives in a cell

A member reached by a sibling word is allocated as a **cell**; a view is a pointer to the cell;
moving, replacing, or destroying the owner while a view is live is a conflict. **A view is a pointer
into the storage**: a *capture* by a sibling word, or a field address inside the expression that took
it -- and a field address does not outlive its expression, so a cell whose binding is captured by
nobody can be moved out of, contents and all (§S71).

```text
captured by a sibling word       ⇒ celled (one indirection)
captured read of a Copy value    ⇒ copied; no cell
not captured                     ⇒ zero cost
```

A word's state is therefore its own preludes (owned) plus its captures (celled, opaque). This is the
mechanism the compiler already uses — a binding is address-taken when it is captured — with the
type-level borrow apparatus demoted to representation.

**A cell is read by a load, and a load is a copy.** So a celled binding whose content is not `Copy` has
two ways to fail, and they are two rules meeting rather than a third one: *reading* it is `NeedsMove`,
because a load would hand out a second owner of the same value, and *moving out of it* is
`ConflictingBorrow` -- **when a view of it is live**, which is exactly the condition above and not a
property of being a cell. A `mut` binding nobody captures can be moved out of, contents and all; a
**celled capture** is the view that forbids it, which is what §S71 restored and §S76 made real.
Destruction goes the other way: a cell's *value* is its address, so destroying what it holds is a load
of the content.

### 3.3 Uniformity, and why ownership is not a pass

> **At every join — a branch merge, a loop backedge, a scope exit — the ownership state of every
> outliving place must agree across incoming paths. Divergence is rejected.**

Uniformity makes the state at a program point **path-independent**: by induction over the join
structure, a place has exactly one state at each point. So ownership is not dataflow at all:

> **a sequential scan with an agreement check at every join.**

Which means there is no fixpoint, no dynamic boolean fact, no guard, and **no ownership phase**. The
insertion of `Move` and `Destroy` is determined by the source `move`s and by lexical scope exits, so
it belongs to `Lower`. `interface` allocates the SSA **value** phi — values genuinely differ per path
— and **asserts** that the ownership state agrees instead of computing a meet.

### 3.4 Assignment

§3.4's *"if the RHS itself moved from the destination, there is no old value left to destroy"* is the
same uniformity question, one statement wide: the RHS either definitely moved the destination or
definitely did not. So the destroy-or-not decision is static and

```text
b = append(move b, x)
```

is legal with no guard.

**And the representation makes the phi disappear entirely.** §3.4 needs a *location*, not a name
for a value, so an assignable binding is §3.2's **cell**: it is allocated once at its declaration
and the name denotes the cell (§11.7's `Cell`). A cell is a belt *value* whose identity is fixed
before any control flow can reach it, so it crosses a join unchanged and only its *contents*
differ per path — and contents are memory, not an SSA name. So there is nothing to merge:
§S28's "the phi arrives with assignment" is wrong, and happily so. It does not arrive.

Two consequences are worth naming. A read of a cell is a `Load` **where the read is**, so a loop's
condition is re-evaluated every iteration rather than hoisted — the earlier hoisting note in
§12.3 was a consequence of the read living in the enclosing block, and a cell removes the question.
And a cell is address-taken storage, so it cannot be moved out of while it is live (§3.2);
`move` on an assignable binding is a conflict, not a copy.

### 3.5 Sums

**A sum is a tag and one payload.** Its representation is `{ tag, payload }`, where the payload is a
union of the alternatives: the tag says which one is there, and only that one has ever been written.

**Construction is by the value's type, and it must be unambiguous.** A value whose type equals
exactly one alternative of a sum is injected into that alternative:

```text
let flag : Int | Bool = 1        # the Int alternative, and only it
```

This is a *derived* determination, not a guess: the alternative is the one whose type the value
already has, so there is nothing to choose and nothing to coerce. When the value's type equals **no**
alternative, or **more than one**, there is nothing to derive and the program is refused rather than
resolved by an arbitrary rule. Two alternatives of one type make a sum that cannot be constructed
implicitly — which is honest, because such a sum has two distinct values of the same type and no
value can say which it meant. (And it is reachable: §2.5 makes two same-shaped records *one* type, so
`{x: Int} | {x: Int}` is exactly that degenerate case.)

**And the determination is SEMANTIC, so it is made where the meanings are — and carried.** "Which
alternative does this value already have" is a question about *types*, not about layouts, and the two
can disagree: a word value's type is nominal in `(template, prefix)` (§S3) while its representation is
its *packet* (§2.2), and two word values with empty packets are both the unit byte. So `Lower`, whose
belt is a vocabulary of REPRESENTATIONS, cannot answer it by comparing — it must be told, and what
tells it is the alternative index `Contract` determined, since that is the phase holding the semantic
types. The same holds for a `switch` label: it is the label that "says which" (§S60), so the index
travels on the label rather than being re-derived from the subject's representation at the point of
use.

**An arm that matches BINDS what it matched.** A `switch` label is a type expression -- §2.4 makes a
type an expression -- so a label names the SHAPE an arm accepts, and the arm that accepts gets the
payload:

```text
switch s do
case Int as n   return n
case Bool       return 1
end
```

**Reaching a payload is not an operation.** There is no `s.Int`; the binder is the only way a value
comes out of a sum. That is the point rather than a restriction: a payload can only be taken by an arm
that has already established which alternative it is, so **a payload read cannot fail and needs no
trap** -- not because the compiler checks the tag cleverly, but because there is no way to write the
read without the check. `SelectField`, and the ordering §S55 gave it, existed to make an UNCHECKED read
safe. §S59 removed the unchecked read instead, which is the smaller thing of the two.

**The binder is a BOUND name, not an initialized one.** A match does not *compute* a value -- it
tells you what was already there -- so the arm binds a name whose declaration is `Judge.Bound(type)`,
the same vocabulary a word's stage binder uses (§11.6), and `Case.binds` is that definition's id.
Nothing is initialized, so there is no initializer to lower and no subject expression to evaluate a
second time. Writing this as
`let n = <the payload>` would have made the binder an *expression*, and an expression over the subject
is a second evaluation of a subject §12.3 says is evaluated exactly once.

**Whether the binder copies or takes is derived, and it is a decision about the SUBJECT.** §1.4 decides
it -- a payload that cannot be copied is moved -- so `case Handle as h` takes where `case Int as n`
copies, and nothing is spelled at the call site, exactly as a stage's declared capability decides
whether it borrows (§S45). Because taking a payload takes the *whole* sum, that is the subject's fate,
so the arms must agree about it (§3.3), and there are exactly three cases:

- **every arm takes** -- the subject is dead on every path, and the payload belongs to the arm that
  matched it, which destroys it at the arm's end like any binding;
- **some arms take** -- the subject is dead on one path and alive on another: `OwnershipDiverges`;
- **no arm takes** -- it is alive everywhere, and destroying a sum needs a destructor chosen by its
  tag, which the compiler does not have: `Missing(SumDestruction)` rather than a silent leak.

**A sum's fields are its tag and its payloads.** Field `0` is the tag -- the `LoadField(subject, 0)`
`switch` already reads to discriminate -- and field `1+K` is alternative `K`'s payload. Every field of a
sum is therefore at a **known offset**, so every read of one is a plain `LoadField`: pure, known,
duplicable, and impossible to get wrong. §3.5's representation is unchanged (`struct let_sumN { int64_t
tag; union let_uN payload; }`, where field `1+K` is `payload.fK`); what changes is that nothing but the
arm that matched ever names one.

Moving a payload out of a sum **consumes the whole sum** (state `Moved`) rather than leaving a
per-alternative hole. The sum is dead afterwards — its tag would otherwise name a value that is no
longer there — so this is both uniform and more honest. Records keep per-member holes because a
record is a value that can be reassembled; a sum is not. The *move* is therefore of the whole sum,
and that is a statement about ownership rather than about reading: it says a sum has no partial state
to be in. There is no trap anywhere in this, because §3.5 leaves no unchecked read to guard.

### 3.6 Views are host vocabulary

The core has **no view type**. §11.3: `Text` is an immutable **module-lifetime literal**; *"dynamically
allocated or host-owned strings use a separately declared vocabulary and ownership contract."* §3.6
says the same for buffers, arenas, and opaque handles. So a view is a **separately declared host
type**.

A host type may declare that it borrows argument *i*. It says so in source where `destroys` also
lives, because the declaration is the whole contract (§S44):

```text
host View borrows 1        # a value of View views argument 1 of the word that produced it
```

The index is the **1-based** position of that argument, and an index below one is refused where it is
read, because a declaration the compiler cannot act on is not a contract. A value of that type is then
a **borrowed type**, and §3.1's rules apply unchanged — there is no exception:

| Borrowed storage | Result |
| --- | --- |
| a literal (module lifetime) | fine — static storage outlives every view |
| a place | containment: the view's scope must be inside the owner's — `BorrowedEscapes` when it is not |
| a temporary | rejected — `BorrowOfTemporary` |
| foreign | the host's contract; Let holds nothing and checks nothing |

Rows one, three and four are decided where the argument is **supplied**, because that is where the
storage is named: a literal, a place and a host call's result pass, and everything else is a temporary
and is refused (`BorrowOfTemporary`).

The second row is the one about **scopes**, and the fact that decides which scope the owner lives in is
already in source: a `Judge.Bound` is a stage the *caller* supplies, a capture reaches storage the
enclosing instance owns (a module prelude is one, §S76), and a `Judge.Value` with its own initializer is
a **prelude of the chain being lowered**, which dies when the chain returns. So **nothing has to travel
from the call site to the return**: the compiler reads a declaration, which is exactly what §1.4 means
by "every extent is a construct the compiler already computes". A view of chain-owned storage that
leaves the chain is `BorrowedEscapes`, and because the borrow travels with the *value* (§3.1 rule 4),
binding it on the way does not launder it (§S79).

### 3.7 Interior mutability

A member declared `mut` inside an aggregate is **interior mutability**: it is a property of the VALUE
and not of the binding that names it, so `r.x = 2` is legal whether or not `r` is `mut` (§S26). Two
consequences follow from rules already stated, and neither is optional.

**A record with a `mut` member is not `Copy`** (§2.5): its mutability is part of its identity, because
two records that differ in it permit different things.

**A place is writable when the binding it starts at is `mut`, or when any step of its path names a
`mut` member.** That is one rule rather than two: a `mut` binding makes everything under it writable,
and a `mut` member does the same for its own subtree — `r.inner.x = 2` needs the `mut` on `inner` and
nothing about `r`.

Writing through a projected place needs its storage to be **addressable**, and the answer is that the
binding it starts at is a **cell** — the shape a `mut` binding has (§3.2). §S70 recorded this as an open
collision, because celling a record that is not `Copy` looked like it made the value unexportable,
unmovable and unreadable; §S71 found that the rule it was colliding with — "moving the owner while a
view is live is a conflict" — was being applied **without its condition**, and that a cell nobody
captures can be moved out of. So there is no gap here and no refusal: `let r = { let x mut = 1 }` with
`r` read-only takes `r.x = 9`, and such a record is exported, moved and destroyed once
(`test/native.lua` #25). Two derivations must agree for this to hold, and where they meet is
`Bug(UnaddressableDestination)`: `Contract` asks writability of the PATH, `is_cell` asks the TYPE for
interior mutability, and a writable place without an address would be the compiler disagreeing with
itself.

The cell then says what a read costs, and §3.2's rule applies unchanged: a read of a celled binding is
a load, so a `mut` binding of a non-Copy type is write-only. **Reading a MEMBER is a different question
from reading the RECORD**: a member of a place in storage is read through the storage — its address and
a `Load` — and never by loading the whole record into a temporary. That is what makes a member of a
non-`Copy` record readable at all, and a record with a `mut` member is not `Copy` (§2.5), which is the
case this section is about (§S69).

Two things follow for stores, and they are different. A store into a **nested path** of addressable
storage is one `FieldAddress` per step plus a single `StoreField` (§S68). A store through a `mut` MEMBER
of a **read-only binding** cells that binding (§S71), and a store into a place that is not writable at
all — no `mut` binding, no `mut` step — is `ReadOnlyDestination`.

## 4. The dictionary

§12.1: *"Names ultimately resolve to lexical bindings or dictionary entries."* A lexical binding
wins over an entry.

```text
Binder = Lexical(number id) | Entry(Chain.Template)
```

**An entry is a chain**, carrying phase (§1.3), purity, ordered stages with capabilities and
annotations, and a terminal meaning. So the dictionary adds no machinery: it is a name table over
templates.

**Forms.** A construction word with bespoke syntax declares which expressions and `do` regions its
form accepts, and its construction behavior shapes the enclosing control (§12.3):

- `if`, `while`, `switch` — bespoke syntax with region slots; their behavior is Lower's, not a
  runtime closure application (§7.2).
- `import` — a construction word applied by **`with`**: it supplies the path, which must be
  a constant `Text`, gives the file chain its stages, and its behavior is to construct that chain at
  the import site and emit its preludes there. Its result is the imported file's **terminal** --
  a namespace for a data terminal, a word for a `do` terminal -- and a **lexical binding of the
  name wins**, because `import` is not a reserved spelling (§S40).
- `break` / `continue` — **plain forms**, not construction words, and take no region (§12.3).

User-defined construction syntax is deferred, which is why forms are a fixed set here.

## 5. The compiler pattern

### 5.1 Three roles

```text
ASDL value             immutable, structural, selected by constructor
machine context        mutable, temporal, selected by control position
continuation arguments data flowing across a control edge
```

ASDL method dispatch removes `switch(node.kind)`; continuation identity removes
`switch(context.state)`.

### 5.2 The rules

1. A context is the only mutable state of its transition.
2. One context corresponds to one transition `IRᵢₙ → IRₒᵤₜ`.
3. ASDL methods return a value normally; only regions use continuations, and only by tail call.
4. Containment is lifetime; wiring is behavior. They are separate structures.
5. A child declares its exits; its parent supplies the successors.
6. A context field holds **progress**; a fact the machine learns leaves as a value.
7. A layer never references a layer above it.

### 5.3 Three kinds of choice

| Kind | Shape | Vehicle | Examples |
| --- | --- | --- | --- |
| Alternative | closed set, dispatched | sum + a method per case | `Capability`, `Purity`, `Phase`, `Diagnostic` |
| Dimension | independent axes, projected | record + derived methods | `Word.Field`, `Judge.Interface` |
| Lattice | combined at a merge | sum + a join method | `Judge.Answer` |

Rules for a type:

- a closed set is a sum — no string tags, no bare booleans, no `nil` as an alternative;
- a sum's alternative earns existence only if a method is installed on it (`isclassof` inside an
  `if` means the case was renamed, not removed);
- a product's axes may be booleans;
- a choice earns being a type iff a consumer distinguishes its cases, or it is joined at a merge.

## 6. The machine tree

Containment is lifetime, expressed as fields on contexts.

```text
Compiler                          the whole run
├── vocabulary                    ASDL classes, scalar semantics, hosts   (immutable)
├── options                       target, resources, hosts, paths         (immutable)
├── reports                       the diagnostic sink                     (mutable)
├── modules                       loaded units by name
└── Unit                          one source file
    ├── source                    text, tokens, syntax tree               (immutable)
    ├── resolved                  binders, captures, groups               (Judge.Resolved)
    ├── interfaces                per-template interfaces                 (Judge.Interface)
    └── Function                  one lowering instance, created on demand
        ├── belt                  the draft, then the frozen Belt.Function
        └── state                 the current region's progress
```

**Instances are demanded, never enumerated** (§S23). The roots are the module initializer and each
exported word's entry point (§2.6). A root demands the words it applies; an application demands
its callee; and the **queue of demanded instances is progress on `Unit`**, because it outlives any
one `Function`. So the belt holds exactly the instances that exist: a word that nothing applies and
nothing exports has no instance at all, is never lowered, and can therefore never report a `Missing`
or a `Reject`. Unreachable code must not be able to fail compilation.

The placement test is one question: **how long does this fact live?** The whole run → `Compiler`; a
template table → `Unit`; the draft belt → `Function`; the current block, scopes and effect → a
region. Anything shorter than a node is a continuation argument, never a field.

`Resolve` and `Contract` are unit-scoped (templates, recursion, the module state record). `Lower`,
`Known` and `Emit` are function-scoped. Keeping those two scopes in one context is the error this
design removes.

## 7. Wiring

### 7.1 Exits

```text
Node : run(in, k_ok, k_diag)
k_ok(Value)              the transition produced its output
k_diag(Diagnostic)       it produced a diagnostic instead
```

### 7.2 The parent supplies successors

A node never decides whether its failure is fatal. That is the parent's wiring, so multi-error
collection, "stop after the first unit", and "continue after a missing mechanism" are each decided
once, in the parent.

### 7.3 Nodes and regions

A **node** is a containment level with a lifetime. A **region** is a control position inside one
transition, wired by a continuation, and never appears in the tree. `Specialize`, `Body` and `Seal`
are regions of `Lower`; one pass per instance is a region of `Emit`, and the remaining instances are
progress state.

## 8. The context record

A context is constructed, never cloned.

```lua
Node = {
    parent = <the containment parent>,      -- ambient is reached through it
    out    = <the draft this node owns>,    -- mutable; frozen at seal
    state  = <the current region's state>,  -- mutable; replaced at region entry
}
```

`state` is created by the region on entry. `out` is shared by every region of the transition and
frozen at the end. There is no allowlist of shared fields: a forgotten field is a nil error rather
than a silently shared fact.

## 9. The two call shapes

```lua
node:build(C)               -- ASDL method: structural dispatch, ordinary return
C:advance(..., k_next)      -- region: temporal, tail-calls its successor
```

An ASDL method calls a region when it must shape control; a region calls `node:build(C)` when it
must lower a node. There is no third shape.

## 10. Vocabulary layers

```text
Source(text) → Syntax → [Resolve] → [Contract] → Belt → C
                   ↘      Semantic      ↙
```

- `Semantic` is below `Syntax` and below `Belt`. It owns the shared choices, the operators, and the
  **type word**.
- `Chain` is above `Semantic` and owns templates, residuals, phases and purity.
- `Belt` uses `Semantic` and never references `Syntax`. It owns **representation** only.
- `Judge` holds what analyses produce: binders, captures, interfaces, answers, fates.
- `Report` holds diagnostics. Nothing else defines one.
- `C` is output only.

## 11. The ASDL

### 11.1 Source

```text
module Source {
    Span  = (string file, number line, number column)
    Range = (Span start, Span stop)
    Token = (string kind, string spelling, string? value, Span span)
}
```

### 11.2 Syntax

```text
module Syntax {
    UnaryOp   = Negate | Not | BitNot
    BinaryOp  = Add | Subtract | Multiply | Divide | Remainder
              | Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual
              | And | Or | BitAnd | BitOr | BitXor | ShiftLeft | ShiftRight
    Conversion = ToFloat | ToInt | ToU8 | ToU32 | ToF32 | ToCString | ToText | TextSize | IsNull

    TypeExpr  = Ref(string name)
              | Record(TypeField* fields)
              | Tuple(TypeExpr* elements)
              | Arrow(TypeExpr from, TypeExpr to)
              | Sum(TypeExpr left, TypeExpr right)
              | Do(TypeExpr result)
              | TypeApply(TypeExpr word, TypeExpr argument)
              attributes (Source.Span span)
    TypeField = (string name, boolean mutable, TypeExpr type, Source.Span span)

    Program   = (Chain file)
    Binding   = (string name, boolean mutable, TypeExpr? constraint, Chain value,
                 Source.Span span, Source.Range name_range)
    Chain     = (Item* items, Terminal? terminal, Source.Span span)
    StageSpec = (string name, Semantic.Capability capability, TypeExpr? constraint,
                 Source.Span span, Source.Range name_range)
    Item      = Stage(StageSpec stage)
              | Prelude(Binding binding)
              | Extern(string name, boolean pure, string? symbol, StageSpec* parameters,
                       TypeExpr? result, Source.Span span, Source.Range name_range)
              | Host(string name, string? destroys, string? borrows, Source.Span span,
                     Source.Range name_range)
    Terminal  = Data(Expr value) | Body(Stmt* statements, TypeExpr? result)
              attributes (Source.Span span)

    Expr      = Name(string name) | Integer(string spelling) | Float(string spelling)
              | Boolean(boolean value) | Text(string value) | Unit
              | Unary(UnaryOp operator, Expr operand)
              | Binary(BinaryOp operator, Expr left, Expr right)
              | Convert(Conversion kind, Expr value)
              | Specialize(Expr word, Expr argument)
              | Invoke(Expr word, Expr* arguments)
              | Word(Chain chain)
              | NamedAggregate(Binding* members) | PositionalAggregate(Chain* elements)
              | Project(Expr base, string name, Source.Range member_range)
              | Index(Expr base, Expr index)
              | Move(Expr place) | Borrow(Expr place)
              | TypeSum(TypeExpr left, TypeExpr right)
              | TypeValue(TypeExpr type)
              attributes (Source.Span span)

    Stmt      = Local(Binding binding) | Assign(Expr place, Expr value)
              | Return(Expr? value) | Discard(Expr value)
              | If(Expr condition, Stmt* yes, Stmt* no)
              | While(Expr condition, Stmt* body)
              | Break | Continue
              | Switch(Expr subject, Case* cases, Stmt* otherwise)
              attributes (Source.Span span)
    Label     = Shape(TypeExpr type) | Constant(Expr value)
    Case      = (Label* labels, string? binds, Stmt* body, Source.Span span)
}
```

Type application is **`with`** (`List with Int`), which §3.1 makes *"not a distinct form"* --
so it is the same `Construct`/`Advance`/`CallFunction` as any other application (§2.4), and a type
expression HAS an application form because a type is a word. (**The sentence that stood here --
"`TypeExpr` has no `Apply` alternative" -- is RETIRED: it contradicted §2.4, which makes application
the whole mechanism, and a type that cannot be applied is not a word.**) Conversions are their own
choice; the previous
`UnaryOp` mixed `Negate` with `ToFloat | ToInt | …`, which are dictionary words.

**A name in type position denotes the type of the value it denotes.** That is what `Ref(string name)`
means, and it is one rule rather than several: `Int` denotes a type word, so the annotation means the
type it *names*, while a name that denotes a **word** denotes a word *value*, so the annotation means
**the type of that word's value** -- §S3's `Word(template, 0)`, which is nominal and therefore names
that word and no other. This is what makes a word usable as a type without a second kind of name, and
it is the type half of *the callee is selected at the call site*: a **stage** whose declared type is a
word names its callee, so `g(x)` is invocable with no vtable, while a stage whose declared type is an
**arrow** names only a shape and is therefore not invocable at all -- the design's polymorphism is
words, not shapes.

**And which word a name denotes is ONE question with one answer.** A name that denotes a *partial
application* is a type for the same reason a word's own name is: `let add2 = add with 2` binds a word at
prefix 1, so `add2`'s type is `Word(add, 1)`, and a stage declared `f : add2` is invocable exactly as one
declared `f : square` is. The type is not *asked* for — `Resolve` runs before `Contract` — it is READ off
the declaration, which is why `Judge.word_of` is the one owner of the walk and `Lower` asks the same
function to select a callee: a copy of it that stopped at the application made `f : add2` an `UnknownType`
while `add2 with 3` lowered, which is one question with two answers.

### 11.3 Semantic

```text
module Semantic {
    Capability = Read | Mut | Own | OwnMut        -- a stage's declared capability
    Purity     = Pure | Ordered
    Phase      = Runtime | Construction

    UnaryOp    = Negate | Not | BitNot
    BinaryOp   = Add | Subtract | Multiply | Divide | Remainder
               | Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual
               | BitAnd | BitOr | BitXor | ShiftLeft | ShiftRight
               | And | Or
    Conversion = ToFloat | ToInt | ToU8 | ToU32 | ToF32 | ToCString | ToText | TextSize | IsNull

    Field      = (string? name, Type type, boolean mutable)
    Type       = Int | U8 | U32 | Float | Float32 | Bool | Unit | Text | Effect
               | CString | CPointer
               | Named(string name)
               | Aggregate(Field* fields, string? name)
               | Sum(Type* alternatives)
               | Arrow(Type from, Type to)
               | Do(Type result)
               | TypeWord
               | Word(number template, number prefix)
               | Variable(number stage)
}
```

There is no `Copy` alternative and no `is_copy` field: Copy is derived (§2.5). There is no
`Address`, `Borrow`, or `stable`: a reference is a use (§1.4), and a cell is representation.

### 11.4 Chain

```text
module Chain {
    Terminal = Data | Do | Form(Dict.Form form) | Host(string symbol)
             | Convert(Semantic.Conversion kind)
    Capture  = (number binder, string name, Semantic.Capability mode)
    Item     = Group(number at, number* preludes)     -- the preludes that run before stage `at`
             | Stage(number index, Semantic.Capability capability,
                     Semantic.Type type, number binder)
    Template = (string name, Item* items, number stages, number transient_from,
                Terminal terminal, Semantic.Type? result, Capture* captures,
                Semantic.Phase phase, Semantic.Purity purity)
    Residual = (Template template, number prefix)     -- R(t,k); a lowering fact
}
```

`Semantic.Type.Word` names a template by **number** — its index in `Belt.Program.templates` — and
not by object, because `Semantic` sits below `Chain` and must not reference it. That is the one
asymmetry the layering forces, and it is what keeps the word type nominal without a cycle.

### 11.5 Dictionary

```text
module Dict {
    Form = (string name, Slot* slots)
    Slot = Expression | Region
}
```

### 11.6 Judge

```text
module Judge {
    Binder         = Lexical(number id) | Entry(Chain.Template template)
    Declaration    = Value(Initializer value, boolean mutable, Semantic.Type? declared)
                   | Word(Chain.Template word, Terminal? terminal)
                   | Type(Semantic.Type denotes) | Host(string? destroys, number? borrows)
                   | Namespace | Bound(Semantic.Type declared)

    Terminal       = Data(Initializer value) | Body(Stmt* statements)
    Stmt           = Local(number definition)
                   | Return(Initializer? value, Source.Span span)
                   | Discard(Initializer value, Source.Span span)
                   | If(Initializer condition, Stmt* yes, Stmt* no, Source.Span span)
                   | While(Initializer condition, Stmt* body, Source.Span span)
                   | Break(Source.Span span) | Continue(Source.Span span)
                   | Assign(Initializer place, Initializer value, Source.Span span)
                   | Switch(Initializer subject, Case* cases, Stmt* otherwise, Source.Span span)
    Label          = Shape(Semantic.Type denotes, number? alternative)
                   | Constant(Initializer value)
    Case           = (Label* labels, number? binds, Stmt* body, Source.Span span)
    Definition     = (number id, string name, Declaration declaration, Binder? scope,
                      Source.Span span, Source.Range name_range)
    Initializer    = Literal(Syntax.Expr value)
                   | Reference(number definition, Source.Span span)
                   | Apply(Initializer callee, Initializer argument, Source.Span span)
                   | Invoke(Initializer callee, Initializer* arguments, Source.Span span)
                   | Unary(Semantic.UnaryOp operator, Initializer operand, Source.Span span)
                   | Binary(Semantic.BinaryOp operator, Initializer left, Initializer right,
                            Source.Span span)
                   | Aggregate(Member* members, Source.Span span)
                   | Move(Initializer place, Source.Span span)
                   | Project(Initializer base, string name, Source.Span span)
                   | Index(Initializer base, number offset, Source.Span span)
                   | Element(Initializer base, Initializer index, Source.Span span)
    Member         = (string? name, Initializer value, boolean mutable)
    Resolved       = (Definition* definitions, Initializer? namespace, Chain.Capture* captures)
    Parameter      = (string name, Semantic.Capability capability, Semantic.Type type)
    Interface      = (Parameter* stages, Semantic.Type result,
                      Chain.Terminal terminal, boolean borrowed)
    Typed          = (number definition, Interface interface)
    Program        = (Definition* definitions, Initializer? namespace,
                      Semantic.Type? namespace_type, Typed* typed)


    State          = Initialized | Moved

    Answer         = Known(Atom atom) | Runtime(Belt.Type type)
    Atom           = Int(number value) | Bool(boolean value) | Unit | Text(string value)
              | Bundle(Atom* fields)
    Fate           = Immediate | Materialized | Dropped
}
```

### 11.7 Belt

```text
module Belt {
    Ref       = (number distance, number output)
    PureOp    = IntegerLiteral(string spelling) | FloatLiteral(string spelling)
              | BooleanLiteral(boolean value) | UnitLiteral | TextLiteral(string value)
              | TextOf(Ref pointer, Ref size)
              | Unary(Semantic.UnaryOp operator, Ref operand)
              | Binary(Semantic.BinaryOp operator, Ref left, Ref right)
              | Convert(Semantic.Conversion kind, Ref value)
              | Construct(Ref* fields)
              | InjectSum(number index, Ref payload)
              | LoadField(Ref record, number field)
              | FieldAddress(Ref cell, number field)
              | PureHostCall(string symbol, Ref* arguments)
    OrderedOp = CheckedBinary(Semantic.BinaryOp operator, Ref effect, Ref left, Ref right)
              | CallFunction(number target, Ref effect, Ref* arguments)
              | HostCall(string symbol, Ref effect, Ref* arguments)
              | Allocate(Ref effect, Ref initial)
              | Load(Ref effect, Ref cell) | Store(Ref effect, Ref cell, Ref value)
              | StoreField(Ref record, number field, Ref value)
              | Move(Ref effect, Ref value) | Destroy(Ref effect, Ref value, string destructor)
    Op        = Pure(PureOp operation) | Ordered(OrderedOp operation)

    Type        = Int | U8 | U32 | Float | Float32 | Bool | Unit | Text | Effect
                | CString | CPointer
                | Named(string name) | Aggregate(Field* fields) | Sum(Type* alternatives)
                | Cell(Type contents)
    Field       = (string? name, Type type, boolean mutable)
    Instruction = (Op operation, Type* results, Source.Span? span)
    Parameter   = (Type type, Semantic.Capability capability)
    Signature   = (Parameter* parameters, Type* results)
    Edge        = (number target, Ref* arguments)
    Exit        = Return(Ref* values)
                | Jump(Edge edge)
                | Branch(Ref condition, Edge yes, Edge no)
                | TailCall(number target, Ref effect, Ref* arguments)
                | Trap(Ref effect, string reason)
    Block       = (Parameter* parameters, Instruction* instructions, Exit exit)
    Function    = (string name, Signature signature, Block* blocks, boolean exported)
    Program     = (string name, Chain.Template* templates, Function* functions)
}
```

Purity is `Op = Pure | Ordered`, so "pure folds, ordered schedules" is dispatch rather than a
convention. There is no `Callable`, `Word`, `Arrow`, `Do`, `TypeWord`, `Address` or `Borrow`: those
were type words or reference types (§11.3, §1.4). `Cell` is the one representation the ownership
model needs (§3.2).

### 11.8 Report

```text
module Report {
    RejectWhy  = UninitializedPlace | PartiallyInitialized | OwnershipDiverges | NeedsMove
               | IndexOutOfRange | UnstatedResult
               | ConflictingBorrow | BorrowedEscapes | BorrowOfTemporary
               | Oversaturated | Undersaturated | NotExecutable
               | DuplicateBinding | UnknownName | UseBeforeInitializer
               | ReadOnlyDestination | UnknownType | MismatchedType
               | MissingModule | ImportPath | ImportCycle
               | InvalidConversion | InvalidCaseLabel
               | Syntax(string detail)
    MissingWhy = ModuleState
    BugWhy     = UnresolvedWordValue | MissingProgramBuilder | NoLowering(string form)
               | UncarriedProducer | AnalysisExhausted | UnaddressableDestination

    Diagnostic = Reject(RejectWhy why, Source.Span span)
               | Missing(MissingWhy why, Source.Span span)
               | Bug(BugWhy why, Source.Span span)
}
```

`MissingWhy` **is** the gap inventory: the count is the number of alternatives, a site names its
constructor, and a new gap cannot be added silently.

### 11.9 C

`C.Type`, `C.Expr`, `C.Stmt`, `C.Declaration`, `C.Unit`. Output only.

## 12. The phases

Every phase is a node with a context, regions wired by continuations, one uniform exit, and a
decision record that is its output vocabulary.

### 12.0 Parse — text → `Syntax`

State: lexer cursor, token buffer, parser position. Exits: `k_ok(Syntax.Program)` | `k_diag`.

**Adjacency is not application.** Two expressions next to each other are a parse error, and the only way
one value is applied to another is `with` (or invocation). That is what makes `;` unnecessary, what makes
an accidental application visible, and what lets a parenthesized expression GROUP after a word -- so the
parser needs no `starts_expression` predicate, because there is no question of whether an adjacent
expression CONTINUES something. §S40 had to teach that predicate `{` and `text`, and a literal form it was
not told about would have silently inverted the grammar.

### 12.1 Resolve — `Syntax` → `Judge.Resolved`

Unit-scoped. State: scope stack, binder table, module pending list, capture accumulation.

| Question | Vocabulary |
| --- | --- |
| which declaration does this name denote? | `Judge.Binder` |
| may this use reach a later declaration? | immediate vs deferred; a `Reject` when it may not |
| which bindings does this word capture, in what order? | `Chain.Capture*` |
| which preludes does each stage reach? | `Chain.Item.Group` |

### 12.2 Contract — `Syntax` + `Resolved` → `Judge.Interface`

Unit-scoped. State: the interface table, and nothing else -- there is no cycle stack, because there
are no cycles to detect. It **checks** rather than infers: §3.1 and §11.3 require a stage to declare
its type word and a runtime terminal to state its result, and *"reading a type off a term is not
inference."* So it resolves declared types, reads types off terms where permitted, and checks every
use.

**An interface is a fact about a DECLARATION, so it is PUBLISHED before the body is checked.** A
word's stages and its declared result are the whole contract, so `types[id]` is filled as soon as
they are read -- and a body that names its own word then reads the published interface on the way in
rather than re-entering the derivation. That is the whole of what recursion needs from Contract: a
declaration is complete even while its definition is not. The re-entry guard that used to sit here was
a guess about the future and is deleted; what replaces it is a **place**, and the place is the
publish (§S74).

**`Interface.borrowed` is derived, and it is the one answer to two questions.** §3.6's `borrows` index
is a fact about a host type's declaration, so `borrow_of(type)` reads it — propagating structurally,
because §3.1 rule 4 gives a record or a sum the borrow of what it holds — and `Interface.borrowed` is
whether that answer exists. Two owners would let the flag and the index disagree about which argument a
view names, so there is one.

**A check reads a DECLARATION, never a derived interface that may not exist yet.** Definitions are
walked in creation order, and a word's stages — and any type word a `case` names — are created
*inside* the word's own chain, so they routinely have **higher** ids than the word that owns them.
`types[id]` is therefore empty for them while that word is being checked, and three separate reads
had the same hole: `type_of` on a stage, and `case_key` on a type word. A declaration owns its fact
(a `Judge.Bound` carries its declared type, a `Judge.Type` carries what it denotes); the interface is
**derived** from it. So a check asks the declaration, and `types[]` is only for asking about another
unit of the same kind — a callee — which the walk has already reached.

### 12.3 Lower — `Syntax` + `Resolved` + `Interface` → `Belt.Function`

Function-scoped. `out` is the draft belt; `state` is the current block, scopes, effects and the
per-place ownership state.

Regions: `Demand` (the queue of instances the roots and their applications demand), `Specialize`
(advance a chain: stage, group, terminal), `Body` (statements and control), `Seal` (freeze the
blocks into an immutable `Belt.Function`). `Lower` returns the set of instances it produced, not
one function: `Lower.run(unit, program, syntax, k_ok, k_diag)`.

| Question | Vocabulary |
| --- | --- |
| how does this value enter that binding? | the call-site form (`Syntax.Expr.Move`, `Borrow`, or plain) and the type's Copy property |
| is this destination a value or a place? | the place `Lower` builds (`lower_place`) |
| is this step a constant or a runtime index? | derived: a constant is `Judge.Index`, a runtime value is `Judge.Element`, and as a destination it is a dispatch of stores |
| which fields does this word bundle carry? | `Chain.Residual` |
| does ownership state agree at this join? | `Report.RejectWhy.OwnershipDiverges` |
| is this operator's result known? | `Judge.Answer`, folded in §12.4 |

**`switch`.** One `end` closes the chain. The subject is evaluated **exactly once**, so it crosses
every edge and `Lower` binds it to a synthetic definition — the only binding it invents, because an
edge argument must be nameable. One test block per LABEL branches to its arm or on to the next test,
which is what a label LIST means and why `case 1, 2` needs no `or` — an `or` short-circuits and would
need the value phi this design has avoided (§S35). There is no fallthrough: an arm's body simply ends.
An arm that matches nothing continues after the switch, so a `switch` terminates only when every value
is caught — an `else`, or a Bool subject whose labels cover both values. A `switch` is not a loop, so
`break` inside an arm belongs to the enclosing `while`.

**A label is a SHAPE or a CONSTANT, and it SAYS which.** §11.2's `Case(Label* labels)` is that
sentence: an arm matches a shape — a TYPE, which it may then bind — or a constant, which it compares.
There are two cases, and the kind is read off the label rather than inferred from what a name denotes:

- **A SHAPE** — a type, and for a sum subject one of its **alternatives**: `case Int`, `case Bool`. A
  structural shape is a label too: `case { x : Int } as r` says the same kind of thing, and it is the
  alternative a by-name projection could not reach, because a record type has no name. A shape that is
  not an alternative of that sum is `InvalidCaseLabel`.
- **A CONSTANT** — a literal of a scalar subject's own type, where two labels collide by **value**: `1`
  and `0x1` are one label, so a repeat is an `InvalidCaseLabel` rather than a silent second arm. A
  label that is not a constant is `InvalidCaseLabel` too, because there is nothing to compare.

`Syntax.Label` is therefore `Shape(TypeExpr) | Constant(Expr)` and `Judge.Label` is
`Shape(Semantic.Type, number? alternative) | Constant(Initializer)`. **This is the ASDL catching up
with the design, not adding to it:** `Label = Expr` was a misdescription — a shape has no expression
spelling at all, which is why `{ x : Int }` could not be written as a label — and the misdescription
*was* the gap. It also removes a hazard: `case_key` used to read what a label's name was DECLARED to
be, and §S52 exists because a type word's declaration is created while resolving the very switch that
labels it.

**And the label carries WHICH alternative it is**, which is what "says which" costs when two
alternatives can share one representation. A shape label is an alternative of the subject's sum, and
`Contract` is the phase that can name the index, because it is the phase holding the SUBJECT's type;
`Lower` holds the subject's *belt* type, and the belt can be ONE type for two alternatives — two word
values with empty packets are both `uint8_t` (an empty record IS the unit byte) — so re-deriving the
index there matched the **last** alternative and every arm of the switch dispatched to one body. The
index is therefore filled in where it is known and READ where it is needed, and the same field feeds
the arm's binder, whose payload IS that alternative. §S60's sentence is the reason the carrier is the
label: it is the thing that says which.

The second case is what S2 means by *"a runtime tag is a sum plus `switch`"*: the tag is what the
switch discriminates, and the alternatives are what it names. Nothing exposes the tag as a field.

**§1.5's operators are one table, and the table is the spec's.** `Syntax` and `Semantic` each own
a `UnaryOp`/`BinaryOp` sum, so the parser reads the spec's precedence table as data and `Resolve`
maps one sum onto the other by name. That is what made the missing `And`/`Or` visible: the two
lists are the same list, and a level that named an operator the semantic sum did not have would
have failed at the first `and`.

**Control flow adds a second rule with the same shape, and it too was got wrong once.** A region's
`state.block` is **progress**: it moves on as the region builds nested control. So the block an
arm or a loop body was *given* must be kept by whoever allocated it, and never read back off the
region afterwards. Reading it back wires the edge to wherever the arm **ended**, which for a
nested `while` is the inner loop's exit.

**The numbering rule has a corollary that is easy to get wrong, and it has now been got wrong
three times.** Within a block, a producer's position is its index among the parameters followed by
the instructions. A `Ref` is relative to the **consumer's** position. So:

1. every parameter must exist before any instruction is emitted, or an instruction and a later
   parameter share a position;
2. and every operand's ref must be computed only once **all** operands have been emitted --
   computing a ref inside the loop that emits them makes it relative to wherever the loop had
   reached, which is not the consumer.

All three fail silently: the belt verifies, the C compiles, and the wrong producer is read. So does
the block rule above: the C compiles, every label exists, and the loop simply never terminates or
terminates early. Every one of them is caught by asserting that an edge's arguments and its
target's parameters agree one for one, and by running the emitted C rather than reading it.

Ownership is **inside** this phase (§3.3): moves are written by the source, destruction is inserted
at lexical scope exits, and joins assert agreement. There is no ownership pass.

**A control form builds a block graph, and the edges are the interface.** `if` builds its arms and
its join, `while` builds its header, body and exit, and `break`/`continue` are jumps into the loop
they belong to. A block's parameters are `[Effect] + the values live at the split`, and an edge's
arguments match them one for one — an edge that omits the effect leaves the target's first
parameter unwritten, which is a read of an uninitialized C variable and exactly the silent failure
the numbering rule below warns about.

**An assignable binding is a cell, and the cell is what keeps the graph simple.** §3.4 needs a
location, so a `mut` binding is allocated once (§11.7's `Cell`) and the name denotes the cell. Its
identity is fixed before any control flow can reach it, so it crosses a join unchanged — nothing
to merge, and no phi (§3.4). A read is a `Load` *where the read is*, so a loop's condition is
re-evaluated every iteration rather than hoisted, which is what §7.2's "condition evaluation at
the loop head" actually asks for. A store is a `Store` *where the store is*, so it is a C
statement rather than an expression; the emitter asks for a statement when the opcode is a store
and for an expression otherwise. And because a cell is address-taken storage, it cannot be moved
out of while it is live (§3.2).

### 12.4 Known — `Belt.Function` → `Answer*` + `Fate*` per block

A split makes the belt a block *graph*, so the answer list is **per block**: a block's parameters
arrive on its edges, and they are answered by them. §12.4's `⊔` is that join.

With no assignment every edge into a merge passes the **same value** (§S28), so `⊔` is idempotent
and one pass in **reverse postorder** reaches the fixpoint — a block is answered after the edges
that can teach it, and a backedge, which is the one edge that violates the order, teaches the
header nothing it did not already know. When assignment lands the same shape becomes a real
worklist; the order is what makes it a single pass today.

A block no edge reaches is not answered, because it is not part of the program — and for the same
reason §12.5 does not emit it (§S30). Both phases read the reachable set from this walk.

**`Fate` is decided here, not in the emitter.** §12.5 *consumes* it, and that is the whole reason
it lives on this side: deciding whether a producer needs a C variable is a walk over the block, and
having the emitter redo it would be two owners for one question.

Function-scoped, per instance. State: memo keyed by `(instance, block, position, output)`, demand
roots, worklist.
The opcode semantics table is shared with the concrete interpreter, so folding cannot disagree with
execution.

### 12.5 Emit — `Belt.Function` × `Answer*` → `C.Function`

Function-scoped, per instance. State: instance queue, C builders, name map, emitted structs. One
region per instance; emission is the discovery, so the walk that guessed liveness does not exist.
`Judge.Fate` is **consumed** here, not recomputed.

Five consequences of demand-driven lowering and of the block graph reach the output, and they are
worth stating because each one looks like a defect until it is read as a rule:

- **An ordered opcode roots itself only if it has C work.** `Op.emits` says which do; a `Move`
  does not, because an ownership transition's runtime representation is nothing -- the value is
  already in hand and the source is simply not destroyed. So the liveness rule is *ordered and
  emits*, or *pure and used*, and a move is recorded in the belt without becoming a statement.
  The `used` half must not apply to an ordered instruction: a move's effect is consumed
  downstream, which would otherwise make it look demanded.
- **Demand order is not dependency order.** The root is lowered first and calls what it demanded,
  so a definition can precede its callee. Every instance therefore gets a **prototype** first, and
  a prototype and its definition must agree on linkage -- which is why a body-less `static`
  function prints as `static` and not as `extern`.
- **A struct is declared after the bodies, not before.** A signature names the packet and the
  result, but a *body* can be the first place a record type appears, because a value carried
  across a split is a parameter of the target block and no signature mentions it. The declaration
  order is therefore structs, prototypes, definitions — all three assembled after every body is
  built. Emitting the struct list early leaves those structs undefined, which compiles fine until
  control flow carries a record.
- **Linkage is a property of the instance.** The module initializer is exported, and so is each
  top-level word's entry point, because §2.6 has the host invoke both; every other instance is
  `static`. Which of them is exported is carried on `Belt.Function` and not inferred from the name,
  because a name comparison is a string standing in for a closed set.
- **A record is one `struct` per shape.** The residual identity (`Chain.Residual`) is a lowering
  fact, so the representation is structural: two packets with the same members are one type. A
  name derived from the word it came from would read better and needs the identity threaded into
  the belt type, which is a naming change rather than a representation one.

### 12.6 Verify

Not a phase: an independent check over each vocabulary, producing `Report` values only. It never
repairs. Numbering and arity for `Belt`; well-formedness for `Resolved`, `Interface`, `Answer` and
`C`.

## 13. Diagnostics

One sum, `Report.Diagnostic`, and one sink, `Compiler.reports`. Only the parent that wires a
`k_diag` decides the policy. The three constructors are never conflated in a message string, because
they are never a string:

- `Reject` — the program is wrong;
- `Missing` — the compiler lacks a mechanism (`MissingWhy` is the inventory);
- `Bug` — a compiler invariant broke.

## 14. Build order

1. Vocabularies: `Semantic`, `Chain`, `Dict`, `Judge`, `Report`, `Source`, `Syntax`, plus verifiers.
2. One vertical slice: a literal from text to C, through real contexts, real exits, and the real
   `Compiler → Unit → Function` tree.
3. `Resolve`, then `Contract`, then `Lower`, then `Known`, then `Emit` — each as a complete
   transition with its own context and exits before the next begins.
4. Only then widen syntax and ownership coverage.

Nothing is built from a special case: a construct gains support by gaining a constructor and a
method.

## 15. Testing

- **Per context.** A transition is tested by feeding an input value and comparing the output value or
  the diagnostic. The choice space is finite, so the test is a decision table.
- **Per vocabulary.** The gap inventory is `MissingWhy`; `test/gaps.lua` asserts which alternatives
  are reachable and from where -- one program per alternative, the phase that must report it, and the
  set of alternatives reached required to equal `R.missing_reasons`, so an alternative can be added
  only WITH a program that reaches it and one that becomes unreachable fails rather than sitting in
  the inventory looking like work (§S72).
- **Conformance.** `test/execute.lua` (the concrete interpreter) and the native witnesses are the
  differential oracle for the rewrite. They are not deleted; they are what makes the rewrite safe.

## 16. Rules for new code

1. Define the vocabulary before the machine. No new field on a context without a type.
2. New behavior is a new constructor plus a method — never a new `if` over a tag, never a string or
   boolean standing for a closed set.
3. A context field holds progress, never a fact.
4. A node never decides whether its own diagnostic is fatal.
5. No layer references a layer above it.
6. Every patch names its transition and the vocabulary it produces or consumes.

## 17. Decisions and specification deltas

The specification is a draft; a delta here is a proposed correction to it.

| # | Decision | Specification delta |
| --- | --- | --- |
| S1 | **Specialization is a move.** A word is an operand; freshness is the ordinary ownership rule. | §5.2's receiver table is deleted (it restates §9); "must not implicitly consume an existing receiver" is deleted — move semantics *is* implicit consumption. |
| S2 | **Words are monomorphic; polymorphism is words.** A runtime tag is a sum plus `switch`; stable policy is a continuation word bound at specialization. The compiler only monomorphizes. | `Belt.Type.Callable` is deleted. An unknown template at a use site is refused. A closure layout is not needed for staged words at all. |
| S3 | **A word value is a record; its word type is nominal in `(template, prefix)`.** `construct` / `advanceₖ` / `run` are generated functions. | §11.1's structural arrow type is the *shape*; nominality is required for monomorphization. No special belt type. |
| S4 | **`Capability = Read \| Mut \| Own \| OwnMut`; `Copy` is derived.** | §11.3's "`Copy` is the `copy` capability" is deleted; §2.5 is the reading. The `is_copy` fields are deleted. |
| S5 | **Type words and representations are separate layers.** | `Belt.Type` loses `Word`, `Arrow`, `Do`, `TypeWord`, `Callable`. `Belt.Parameter(Type, AST.Capability)` disappears. |
| S6 | **Let's surface has no reference concept.** A reference is a use with a capability and an extent; every extent is a construct the compiler already has. | `Address`, `Borrow`, `stable` leave the semantic vocabulary. No lifetime appears in the language. |
| S7 | **Captured state lives in a cell.** A view is a pointer to the cell; moving, replacing or destroying the owner while a view is live is a conflict. | §1.4 stands; §10's "moving the aggregate moves the owner and its state together" is deleted, and §10 becomes derived. |
| S8 | **A word's state is its own preludes plus its captures.** | §10's normal stateful-word form is primary; §10's borrow rows are celled captures. |
| S9 | **One `Diagnostic` sum.** `Reject` / `Missing` / `Bug`; `MissingWhy` is the gap inventory. | Replaces `GAPS.md` and the `refuse`/`gap`/`internal` message prefixes. |
| S10 | **Containment is lifetime; wiring is behavior.** `Compiler → Unit → Function`; `Function` owns `Lower`, `Known`, `Emit`. A nested context is a field, never a clone. | Deletes `Context:clone` and the ambient allowlist. |
| S11 | **Regions create their own state on entry.** | Instantiates the deferred DESIGN step 3 (Frame) structurally. |
| S12 | **Escape is lexical containment**, and *borrowed* is a derived property of a type. | §12.4's "a view that escapes that scope is no longer held" is unsound and must read "is rejected". |
| S13 | **`with` and invocation are the same operations**, differing only in residual lifetime. **A chain is transient from its first `mut` stage.** | §1.2's equivalence is the definition, not an optimization note. |
| S14 | **Phase is the executor; purity is foldability.** An entry is a chain plus phase and purity. | §1.2's "a word contains a phase" becomes "its template has a phase"; §12.1 is the owner. |
| S15 | **§1.1's "three operations" become two application forms × two executors, plus forms.** | The sentence "these are not the same phase" is the tell that the framing was wrong. |
| S16 | **Ownership state is uniform at every join; divergence is rejected.** Ownership is a sequential scan, not a pass. | §12.3's join rule is strengthened: it applies to destruction and scope exit, not only to later use. No fixpoint, no dynamic facts, no guards. |
| S17 | **Assignment's replaced-value question is the same uniformity, one statement wide.** | §3.4's "if the RHS itself moved from the destination" is static, not dynamic. |
| S18 | **Moving a sum's payload consumes the sum.** | §11.5's per-alternative hole is replaced: a sum is not a value that can be reassembled. |
| — | **`S19` is not present.** The numbering has a hole: no row was ever written for it and nothing refers to it. It is recorded rather than renumbered, because a number is a reference and renumbering every later row to close a hole would silently change what other text points at. |
| S20 | **Resolve produces *definitions*, not just references; every definition gets an interface.** | §11.6's `Resolved` had `Binder*` but nothing to bind to. A value binding is not a special case: a data terminal with no stages *is* a value, so its interface is a zero-stage data word (§11.1). Two renames fall out of the same rule as the four collisions: `Judge.Stage` → `Judge.Parameter` (freeing `Stage` for `DefinitionKind`), and `Fate.Value` → `Materialized` (freeing `Value`). |
| S21 | **The module initializer returns the module value; the state collapses into the namespace when nothing is left over.** | §2.6's "live until module unload" plus §2.6's written terminal is why the `state` member exists at all. `let_module_unload` is generated only when the module owns something. |
| S22 | **`Judge.Answer.Runtime` carries a `Belt.Type`, so Judge sits above Belt.** | DEMAND §4: the abstract evaluator's domain is "an opaque runtime value of **belt** type `T`" -- it evaluates the belt, never the source. §11.6's `Runtime(Semantic.Type)` was the source type leaking into a judgment about a representation. |
| S23 | **`Lower` is demand-driven from the roots, not a walk over every template.** | §5.2's "each specialization constructs a new semantic result" makes an instance exist *because something demanded it*. A word nothing applies and nothing exports has no instance, so it is never lowered -- and therefore can never report a `Missing` or a `Reject`. §6's "one lowering instance per template" was the eager reading of the same sentence; it now reads *created on demand*. |
| S24 | **A group names its preludes; a declaration carries its payload and its resolved initializer.** | §11.4's `Group(number at)` said *where* a group runs but not *which* preludes are in it. §11.6's `Resolved` had definitions with no body, so nothing carried a name use's target: `Initializer` makes resolution a value instead of a table keyed by node identity. And three optional fields on `Definition` would be a product with variant-specific axes, so the *declaration* carries the payload and `Definition` stays flat. |
| S25 | **Demand is per prefix, not per word.** A word *value* is `R(t,0)`, demanded by the definition that binds it; `advance_k` and `run` are demanded by applications. | Refines S23. §5.2's "each specialization constructs a new semantic result" makes the instance a `(word, prefix)` pair. So a word nothing applies is demanded at prefix 0 only -- its value exists, its later prefixes and its terminal do not. |
| S26 | **An aggregate is a chain.** A named aggregate's members are chain items and its terminal is the record of them; an aggregate with any stage member is a `Word` expression whose chain carries the stages. | §3.1 already says it; §11.2's `NamedAggregate(Binding* members)` is right, because the members are the *record's* members with value expressions and the **stages belong to the enclosing chain**. New rule: **inside braces `mut` means interior mutability of the member** (§3.7), not a supply qualifier -- the stage is supplied like a read one and the qualifier lands on the member. Outside braces it is §5.3's invocation-only mutable stage. |
| S27 | **A `let` after `{` is ambiguous, so the parser backtracks.** It tries the named form and restores the position on failure. | §3.3's "entirely named or entirely positional; the forms cannot mix" is a constraint, not a decision procedure, and a positional element may itself begin with `let`. This is the one place the parser needs backtracking, and it is worth stating so it is not mistaken for an accident. |
| S28 | **A split transports values; it does not carry ownership.** An arm is a block whose parameters are the values live at the split, and the join is a block whose parameters are the same values. Ownership crosses as an *agreement*, never as a parameter. | §12.3's "continuation identity is control state" plus §3.3's uniformity: a place has one state at each point, so a join has nothing to merge. And with no assignment (C8) no *value* differs per path either, so every edge passes on exactly what it received — the interface is an **identity, not a phi**; the phi arrives with assignment. Two consequences are named rather than hidden: the live set is the region's environment and not a liveness analysis, so a value already dead at the split is still carried (imprecise, never wrong); and a transport copies the representation, so a partially-moved value's hole travels with it — harmless while nothing is destroyed, and the mask C6's destruction must follow. |
| S29 | **Withdrawn.** It recorded refusing a block graph with `Missing(BlockGraph)`, and giving `Belt.Function` a `Source.Span` so that refusal had somewhere to point. Both were wrong: §12.4 already specified the walk over `(instance, block, position)`, and §11.7's `Function` has no span. The graph is now lowered, so there is no gap, no reason in the inventory, and no field. | The tell is that the row justified a *field* by a *diagnostic*. A vocabulary change that exists only to make a refusal locatable is a refusal that should not exist. |
| S30 | **An unreachable block is not answered and not emitted.** Reachability from the entry is the block-level form of §12.3's demand, and it is the same walk for both phases. | A split whose arms both `return` creates a join no edge reaches. `Lower` must create it — the join block exists before the arms, because an `Edge` names its target by block id — and only the CFG says whether anything arrives. `Known` walks reachable blocks and labels the order, so §12.5 emits exactly those. That keeps "the compiler emits only what is demanded" true one level below words. |
| S31 | **A loop's edges are joins too, and its exit is always reachable.** The backedge, every `break` and every `continue` must agree with the header; a `break` records the ownership state it leaves in and the loop checks all sites at once. | §3.3 applies "at a loop backedge" and the spec adds `break`/`continue` to the same rule. It stays a *local* check rather than a fixed point because the header's state is the state on entry, which is already known — the same reason there is no ownership pass. And because the condition may be false first, the exit is always reachable, which is why a loop joins the enclosing code instead of ending it. |
| S32 | **An assignable binding is a cell, and assignment therefore needs no phi.** A `mut` binding is allocated once at its declaration and the name denotes the cell; reads `Load`, writes `Store`. `Declaration.Value` carries the mutability, and `Stmt.Assign` carries the place and the value. | Corrects S28, which said "the phi arrives with assignment". It does not: a cell is a value whose identity is fixed before control flow reaches it, so it crosses a join unchanged and only memory changes. §3.2's cell was introduced for captures; assignment is the same question — address-taken storage — with a second reason, and it is why §3.4 is *static*: with the destination's old value destroyed only when the RHS did not move it, and a cell that cannot be moved out of at all (§3.2), the replaced-value question has no case left to guard. Two consequences: `mut` inside braces still means interior mutability of the *member* (§S26) and does NOT make the member's declaration assignable, and a store is a C *statement* because the C vocabulary has no assignment expression. |
| S33 | **The draft's §3.4 precedence is DATA, and its §1.5 integer semantics are INLINE C with no helper function.** The parser holds `{ associativity, { token = operator } }` per level; C gains `Expr.Comma` so a trapping division can be written `(right == 0 ? (abort(), 0) : left / right)`. | Two corrections to the vocabulary fall out. `Semantic.BinaryOp` was missing `And`/`Or`, which `Syntax.BinaryOp` had — the two sums are the same list, and the table made that checkable. And a folded `Bool` emits `true`, so draft §12.5's "an include is demanded by a representation" means where the *representation* is used, not only where `ctype` runs: demanding `stdbool.h` only in `ctype` left `true` undefined and the output silently uncompilable. |
| S34 | **`switch` is a chain of tests, and its subject gets a SYNTHETIC binding.** One test block per LABEL branches to its arm or on to the next test, so `case 1, 2` is two tests into one arm; the subject is evaluated once and carried, which is why Lower invents a definition for it — the only binding it invents, because an edge argument must be nameable. | §12.3's subject is evaluated exactly once, so it has to cross every edge, and `live` is keyed by definition id. A label LIST needs no `or`, which short-circuits and would need the value phi this design has avoided. Two smaller corrections fell out: `terminates` has to know that an exhaustive `switch` terminates — an `else`, or a Bool subject whose labels cover both values — or a `do : Int` body ending in one looks like a fall-through; and Resolve's statement fallback became a `Bug`, because every form is handled now and a new one costs a constructor AND a case. |
| S35 | **`and`/`or` are the ONE place the value phi appears, and they are control rather than arithmetic.** The condition branches; the arm that does not run the right operand passes the LEFT value into the join, the arm that does passes the right operand, and the join's last parameter is the merged value. | `and`/`or` short-circuit, so the right operand must not run when the left decides — which is a control decision and not a `Binary` at all. The two escapes the rest of the design uses for per-path difference are both unavailable: it cannot be made memory (§S32's cell, whose identity is fixed) and it cannot be made to agree (§S28's identity interface), because *not running* the right operand is the operator's meaning. So the phi §S28 postponed arrives exactly here and nowhere else. The short arm needs the left value as a parameter, because that value lives in the parent's block and a block names only its own positions. Two bugs fell out: a multi-stage application never lowered its inner application, so `advance_1` was handed `construct()` — invisible in the belt, where both are belt values, and caught only by the emitted C refusing the argument type; and `ShortCircuit` left the gap inventory. |
| S36 | **An exported word is a ROOT, and its entry point is what makes it reachable.** The initializer CONSTRUCTS every top-level word value, because §2.6 puts every top-level name in the namespace; each top-level word then gets an entry point taking the module value plus its remaining stages, and that entry point is a second kind of root alongside the initializer. `Belt.Function` carries `exported`, and the emitter consumes it instead of comparing the name to `let_module_init`. | §S23 said the roots are "the module initializer and each exported word's entry point" — and only the first was implemented, so an exported word was demanded at prefix 0 and no further (§S25): it existed as a value, its `run` was never lowered, and the host had nothing to call. Being a root is exactly what fixes that, and it is why a word the module never applies still produces its `advance_k` and `run`. Two consequences: the initializer must construct word values, which is why the namespace grew a member and `construct` runs twice for an applied word (once for the namespace, once for the application — folding them is unsound the moment a word has a prelude with effects), and entries are generated only for the implicit namespace, because a written terminal CHOOSES the export surface (§2.6) and which names it exposes is therefore not a structural fact. |
| S37 | **Assignment's lookahead is the postfix grammar, not a token.** The parser decides a statement is an assignment by scanning a place forward: a name, then any sequence of `.name` and `[...]`, then `=`. | `n = 1` needs one token, but `r.x = 1` has its `=` past the suffix, and a one-token lookahead read `r` as a juxtaposition argument of the previous statement — so a projected assignment failed to parse at all. The scan is exactly what `parse_postfix` accepts, so it is the postfix grammar run without consuming rather than an ad-hoc rule. A one-level field store then lowers to `StoreField` into the cell; deeper needs a chained address the opcode cannot spell, and an unaddressable place is §3.7's interior mutability, which needs its own celling rule and is a separate increment. |
| S38 | **Text and integer literals reach the whole pipeline, and an integer's VALUE has one owner.** `Semantic.integer_value(spelling)` knows `0x`/`0b`/decimal/underscores; the lexer matches hex and binary before decimal; `Text` is spelled `const char *` in C, and a string literal carries its unescaped bytes rather than its spelling. `C.Type` gains `CString`. | Three things were declared and unreachable. `Semantic.Text` had no lexer token, no contract rule, no representation — and `import "x.let"` (§4) cannot even be written without it. `Syntax.Text` therefore had a `value` field nothing produced, which is exactly the separation that keeps an escape out of a judgment. And integer literals were decimal-only, so §12.3's own example — "duplicate labels are errors, including numerically equal spellings such as 1 and 0x1" — could not arise: the check was on the spelling because there was only one spelling per value. Now the label key is the value, and three places that need a literal's number (the folder's atom, the label key, the C constant) share one conversion instead of three copies of a base conversion. `uint8_t *` for Text was also a representation disagreeing with itself: a string literal is a `char *`, so `-Wall` warned on every one. |
| S39 | **A module is loaded once, and a missing one is a Reject.** `Compiler` gains `modules` (§6's "loaded units by name"), `V.load(compiler, path, span)` lexes and parses a file and caches the `Syntax.Program`, and `RejectWhy` gains `MissingModule`. | Loading is compiler-scoped because that file's resolution must be ONE resolution: two loads could disagree about the same bytes. And a file the program names but that is not there is a `Reject` rather than a `Missing` — the program is wrong, not the compiler — which is the distinction §13 exists to keep. This is the first piece `import` needs; the loader has no other caller and is here because the alternative is writing the I/O inside `Resolve`, where it would be a second place that knows what a unit is. |
| S40 | **`import` is a dictionary entry whose result is the imported file's TERMINAL, so it reuses `resolve_value`.** A lexical binding of the name wins (draft §2.6 says it is not a reserved spelling); the one expression slot is the path, which must be a constant `Text`; the file's stages are supplied by the specialization arguments that follow; and the result is the file's terminal — its namespace for a data terminal, a word for a `do` terminal. `RejectWhy` gains `MissingModule`, `ImportPath` and `ImportCycle`. | The reason this is small is that **a file is a chain** (draft §2.6), so resolving one is `resolve_value` applied to another file's chain — the same `Chain.Template`, the same stage machinery, the same terminal judgement. Two things fell out. `starts_expression` had to learn `{` and `text`: the draft's §3.4 `specialization_atom` is "literal | NAME {suffix} | aggregate_literal", and leaving Text out silently inverted the grammar the moment Text literals existed — `f "x"` stopped being an application and the file parser read the `"x"` as its own terminal. And a written terminal that follows a prelude needs `;`, which is draft §2.6's own note and not a parser defect: `let secret = 8;` then `{ ... }`, because juxtaposition would otherwise take the aggregate as an argument of `8`. A file with no written terminal now resolves to the named aggregate of its own preludes (`resolve_value`'s no-terminal case), so both terminal kinds import — but that rule has **two implementations**, because the entry file is a module rather than a definition: its namespace is a `Belt` record assembled in `Lower`, and building it in `Resolve` would need `rep` to map a WORD type, which is `Lower`'s `residual_type` and not `rep`'s business. Unifying them is a change to the semantic-to-belt mapping, not to this rule. |
| S41 | **A host word is declared in source, and its C prototype is DERIVED.** `Chain.Terminal` gains `Host(string symbol)`; `Judge.Word`'s terminal becomes optional, because a host word has no body and no data to judge -- the symbol is on the template and the declaration's stages and result are the whole contract. Resolve turns an `Extern` item into a word like any other, Lower's `run` for such a word *is* the host call (`PureHostCall` when the template is pure, `HostCall` when it is ordered), and §12.5 emits the prototype from the Let types with `external` linkage. | §3.6 says "the declaration, not the implementation, is what the compiler holds a host to", so nothing about the host is knowable beyond what source states -- which is why the prototype is generated rather than registered, and why `pure` is a property of the TEMPLATE (`Semantic.Purity`) and not a flag on the call: purity is foldability, so it decides whether the op takes an effect. Two things fell out. `PRIMITIVE` in Resolve had only `Int`, `Bool` and `Unit`, so `CString`, `CPointer`, `U8`, `U32`, `Float`, `Float32` and `Text` were declared and UNWRITABLE -- a host stage could not be declared at all. And `Text` is not `CString` (§3.6): a literal cannot be passed to a `CString` stage, so the conversion words (`Semantic.Conversion`'s `ToCString`/`ToText`) are the next gap, not a workaround. |
| S42 | **A conversion is a DICTIONARY word, not an operator.** `Chain.Terminal` gains `Convert(Semantic.Conversion kind)`, `Semantic.conversions` is the table that declares each one's `from` and `to`, Resolve falls back to it when no lexical binding has the name, and Lower's `run` for such a word is one `Pure.Convert`. | §11.2 already said conversions are dictionary words, so this is that sentence implemented rather than designed: the name resolves through §12.1's fallback, and §12.1's "a lexical binding wins over an entry" is what makes `let ToInt = ...` shadow it. Two omissions are deliberate. `ToText` is absent because a `Text` has a known length and no terminator guarantee while a `CString` is terminated and borrowed — going that way needs a length the source does not have, which is a representation question and not a table entry. And `Known`'s folding rule for `Convert` currently fires for nothing, because the conversion is a WORD: `ToCString "x"` passes its argument through a packet, so inside the word's `run` the operand is a `LoadField` and therefore `Runtime`. That is the demand model working, not a missing optimisation — the rule is there for when a conversion's operand IS known. Numeric conversions cannot fold at all, because an `Atom` has no Float. |
| S43 | **A host word whose C prototype differs from the derived one is wrapped by the host.** The prototype is derived from the Let types, and there is deliberately no per-declaration "exact spelling" escape: `extern pure span (s : CString) : Int` compiles to `extern int64_t span(const char *)`, and a host that has a real `size_t strlen(const char *)` defines that wrapper. | §3.6's "the declaration, not the implementation, is what the compiler holds a host to" cuts both ways: the compiler states the prototype, so the host satisfies it. A spelling escape would move part of the contract back out of the declaration and into a string the compiler cannot check against anything -- and the wrapper it replaces is one line that the host was writing anyway. What this costs is that libc functions cannot be named directly when their prototypes differ (`strlen` returns `size_t`, so it is not `Int -> Int`), which is honest: they are not Let words, they are C functions, and the boundary is where the two vocabularies meet. |
| S44 | **A host type is declared, nominal, and carries its destructor.** `Syntax.Item.Host(name, destroys)` declares one; `Judge.Declaration.Host(string? destroys)` carries what destroys a value of it, because §3.6 makes the declaration the whole contract and §3.3 puts destruction in `Lower`; `Lower` inserts `Destroy` at a scope exit for every binding THIS region bound, in reverse initialization order, skipping the ones whose place is `Moved`. | §3.1's rule 2 is "reverse initialization order, at scope exit / return / replacement", and §3.3 says `Lower` inserts it "because it is determined by the source's moves and by lexical scope exits" — so it is a scan of the region's environment, not an analysis, exactly like ownership itself. Three things had to be right for it to work. A host type must be **interned**: `resolve_type` built a fresh `Semantic.Named('Handle')` per use, and since a nominal type is compared by identity, `touch(h)` was a type error against the declaration that produced `h`. Destroyability is read off the TYPE's declaration and not the call site, so a `move` out of a scope is not a leak -- the new owner has the one destruction. And "this region bound it" is the same distinction the interface draws: a carried value is a parameter, and a parameter belongs to whoever created it. The borrow half of this is S45, and the record-member half is S46. |
| S45 | **A stage's CAPABILITY decides whether it borrows, and `Lower` no longer demands `move` for a view.** `Read` and `Mut` borrow their argument; `Own` and `OwnMut` take it. A borrow lowers to the value itself, and the only thing that makes it a borrow is that the source's place is NOT marked moved -- so the scope that made the value still destroys it. | §3.6's table is the rule: "a host-declared borrowed type \| read \| the scope that made it", and "a borrowing stage may not retain its argument". So the borrower writes `f h` and the owner writes `f (move h)`, and demanding the second from the first was a genuine wrong-refusal that only showed up once a host stage existed to be borrowed against. A borrow has no representation (§3.6: "a reference is never a value, its representation is unobservable"), which is why it is the value with an unchanged place rather than a belt node -- and why no escape check is needed for a HOST word: "foreign \| the host's contract; Let holds nothing and checks nothing". The capability comes from the declaration and never from the call site, which is the same rule as the prototype: the compiler states it, the host satisfies it. |
| S46 | **Destructibility is a derived property of a type, and a record destroys its members.** `destroys(type)` is structural -- a declared host type says so in its declaration, a record says so if ANY member does, a scalar owns nothing -- and destruction walks the value in reverse member order, skipping a member whose place is `Moved`. | It is the mirror image of `Copy` (§2.5): Copy asks whether EVERY member is Copy, destroyability asks whether ANY member is destroyable, and both are read off the type rather than stored. This is what closes the leak S44 named -- before it, a record destroyed only itself and its members leaked, because members are not bindings and the scan only walked bindings. The place state already had the answer for the moved case: `moved` is keyed by a dotted path, so checking one path deeper is the same check, not a new one. |
| S47 | **`TypeExpr` is implemented, a declared annotation is CHECKED, and type equality is derived.** `parse_type` grows from one token to §11.2's six alternatives (`Ref`, `Record`, `Tuple`, `Arrow`, `Sum`, `Do`), `resolve_type` builds each, `Judge.Declaration.Value` carries the resolved annotation so Contract can compare it against the value's type, and `Semantic.Type:equals` is a derived method the way `copyable` is. | Two defects, one cause. Only `Ref` resolved, so a record VALUE was expressible and a record TYPE was not -- nor a tuple, an arrow, a sum or a `do` -- and separately the annotation was resolved to *nothing*: `let x : Int = true` was accepted, because Contract reads the type off the value and never looked at the claim, while §12.2 says it "checks rather than infers" and a check needs both sides. Equality had to be derived for the same reason a nominal type had to be interned (S44): a type is a WORD, so two occurrences of one type word are one type, and `==` on two tables says they are not -- which made every annotation mismatch once the comparison was finally reached. A tuple is a record with unnamed members (§3.3: a positional element has no declaration to be named by), so a tuple and a same-shaped record are ONE type; mutability is part of a record's identity because §3.7 changes what a value of it permits; and a sum is inhabited by a member whose type matches exactly one alternative -- see S48, which reverses that inference. |
| S48 | **A sum is `{tag, payload}` and is constructed by an UNAMBIGUOUS type match.** A value whose type equals exactly one alternative is injected into it; no match, or more than one, is refused. Extraction is ordered and consumes the whole sum. | §11.2 has `TypeSum` as a TYPE expression and no value form at all, and §11.7 assumes a tag exists — so the spec was silent on how a sum value is ever made, which is why `Semantic.Sum` and `Belt.InjectSum` were declared and constructed zero times. The determination is derived rather than chosen: the alternative is the one whose type the value already has, so there is nothing to coerce. Ambiguity is refused rather than resolved arbitrarily, and it is reachable — §2.5 makes two same-shaped records ONE type, so `{x: Int} \| {x: Int}` is a sum with two distinct values of one type and no value can say which it meant. **This reverses the consequence I recorded in S47**: `let s : Int \| Bool = 1` is now LEGAL, because the Int alternative is the only one that matches. S47's refusal was my inference from the silence, not a rule — and the silence is what this entry fills. Extraction reads through a tag the compiler cannot check, so it is ordered and can trap, which is the same distinction §12.4 draws between a fold and a schedule. |
| S49 | **A sum is built in ONE place, and the belt has its own type equality.** The injection is in `lower_initializer`, because every construct that expects a type goes through it -- a binding, a stage argument, a return, a record member -- so it is one rule rather than a case at each site. `Belt.Type:equals` mirrors `Semantic.Type:equals`, including `Belt.Sum:alternative`, because `Lower` compares BELT types. The C is a `union let_uN` for the payload plus a `struct let_sumN` carrying the tag, deduplicated by shape like a record; `InjectSum` writes a designated initializer for exactly the tagged alternative. | §11.7 already had `Sum` on both sides and `InjectSum`, so this is the mapping (`rep`, `ctype`) plus the insertion point. Two defects fell out, both of the same kind -- a mapping applied twice or not at all. `rep(Semantic.Sum)` had no case, so a sum-typed binding crashed in the emitter; and the injection was SILENTLY skipped because I applied `rep` to `term_type`, which already returns a BELT type, so the value's type came back nil and the condition simply did not fire. Silent is the operative word: the program compiled and produced the payload without a tag. Three smaller things are worth their lines. The constructor-collision rule caught me again -- `Union` cannot live in both `C.Type` and `C.Declaration` -- and `C.Named` already prints verbatim, so the union type needed no new case at all. The tags are 0-based, because a tag is an offset like every field index the belt and emitter use. And `term_type` was a *second* owner of "read a type off a term" alongside `Contract.type_of` -- the duplication this increment walked into again, renamed `belt_type_of_term` by §S57, made loud by §S60, and **deleted by §S61**. |
| S50 | **`switch`'s rules are now stated here, and a label is a LITERAL compared by value.** The subject is evaluated once and carried; one test block per label; no fallthrough; exhaustive means every value caught; `break` belongs to the enclosing loop. | None of this was in this document. It was in `let-language-specification.md` §9.6 — the draft — and my code cited "§9.6" in ten places, including four where the rule is Contract's and one where it is draft §3.3's. draft §9 of THIS document is "The two call shapes", so those citations pointed at a section that says something else, which is worse than pointing at nothing: it makes an imported rule look specified. The rules are now written above, in draft §12.3, where `Lower`'s behaviour lives. One thing is deliberately NOT settled by that move: draft §11.2's `Case` takes `Initializer*` labels — EXPRESSIONS — while the implementation accepts only Int and Bool literals. That narrowing is the draft's, it is what would prevent `switch` from discriminating a sum, and it is an open question rather than a rule. |
| S51 | **A label is an expression, and for a sum subject it is an alternative written as a type name.** No ASDL change: draft §2.4 already makes a type an expression, so `case Int` is a `Reference` to a type definition like any other label. | S50 left this open with three readings. Two of them are not in conflict: "labels are expressions" (draft §11.2/draft §11.6) and "labels name the subject's alternatives" (S2) — the second is a USE of the first. The conflict was between the spec and my implementation, which narrowed labels to Int and Bool literals; that narrowing came from the draft, and it was the entire obstacle to discriminating a sum. So the fix is to REMOVE a restriction rather than add a rule. `InvalidCaseLabel` keeps its meaning in both cases: not a constant for a scalar subject, not an alternative for a sum subject, or a repeat of one either way. |
| S52 | **A check reads a DECLARATION, never an interface that may not exist yet.** `type_of` on a stage reads `Judge.Bound`'s declared type; `case_key` on a type word reads `Judge.Type.denotes`; `types[]` is for asking about a callee, which the walk has already reached. | Definitions are walked in creation order and a word's stages -- and any type word a `case` names -- are created INSIDE the word's own chain, so they have HIGHER ids and their interfaces are empty while that word is checked. Three separate reads had the hole, which makes it a class rather than an instance: the fix is the rule plus a sweep, not another targeted patch. This is §5.2's "a context field holds progress; a fact the machine learns leaves as a value" seen from the consumer's side -- an interface is something the machine LEARNS, so a check that depends on one is depending on progress. **The note that stood here -- "known to be incomplete: an exhaustive `switch` over a sum is still refused, one read in the `terminates` path that I have not found" -- was STALE and §S66 removed it: `terminates` handles a sum subject, and the refusal it recorded was the CFG's agreement comparing an unreachable fall-through, which is a different phase's question. |
| S53 | **`switch` over a sum discriminates by the TAG, and "does this value fit" is ONE rule.** A sum subject's labels are its alternatives, and each test is `LoadField(subject, 0) == <index>` — field 0 of §3.5's `{tag, payload}`, which no other part of the language names. And a value meeting an expected type asks `accepts`, which is equality OR injection, at every such site: a stage argument, a binding, a return, an assignment, a record member. | The tag is an implementation detail the language never exposes, so exactly one place knows where it lives, and it is the emitter's `LoadField` case plus this test. `accepts` is the rule I should have taken from §3.5 first: asking plain `equals` at each site is how a sum-typed stage came to refuse the very values it is built to hold — `f 1` where `f : (Int \| Bool) -> Int` was a `MismatchedType`. One rule at every site, rather than a correct answer at one and a wrong one at another. Two smaller things: the tag is `int64_t` and not the `uint8_t` it could be, because §1.5's comparisons take Int and there is no `U8 -> Int` conversion word — a narrower tag would need one invented to compare against; and the payload is a `union let_uN` with a `struct let_sumN` carrying the tag, because C has no anonymous union member in this vocabulary. **Not yet done, and it is a gap in the SPEC rather than the code:** there is no syntax for reaching a sum's payload. §3.5 says extraction is ordered and consumes the whole sum, and §11.7 has `SelectField(Ref record, Ref key)`, but nothing in §11.2 lets a program NAME the payload — so an arm can return a constant and not the value it matched. |
| S54 | **A projection on a sum selects an alternative by name, and it is ordered.** `s.Int` -- `Project` with the alternative's type name, lowered to `SelectField`, which §11.7 already makes ordered while a record's `LoadField` is pure. `move s.Int` consumes the whole sum (§3.5). | The spec was silent on how a payload is ever REACHED, which made `switch` over a sum useless: an arm could return a constant but not the value it matched. The silence was only in saying it -- both halves of the vocabulary were already there, and §11.7's pure/ordered split is the design having said it earlier without a paragraph. An alternative is a declaration and therefore has a name, exactly as a record member is a declaration and therefore has one; so `Project` needs no new field and `Case` needs no binder. The trap is §3.5's: a projection reads through a tag, so it can fail, and the belt op that can fail is ordered. |
| S55 | **`SelectField` is ORDERED, not pure -- a correction to §11.7's own ASDL.** It takes the effect, because a select reads through a tag the compiler cannot check, so it can fail. `SelectStore` was already ordered while `SelectField` was not, which was the inconsistency made visible by writing §3.5 out. | The compiler caught this: `Lower` wrapped the op and `Belt.Ordered` rejected it, because §11.7 listed `SelectField` among `PureOp`. §3.5's argument is the sound one -- a read that can fail is not a fold -- and a language whose payload read is "pure" has an undefined value instead of a trap exactly when the tag disagrees. The same paragraph also produced the double-mapping trap twice more (`rep` applied to a value that was already a belt type, once in Lower's projection and once before in the injection), which is worth recording as a pattern rather than an accident: `term_type` and `ordered` differ by one mapping and nothing in the types says which. |
| S56 | **A projection on a sum reaches a NAMED alternative, and only a non-Copy payload is consumed.** §3.5's consume-the-whole-sum applies when the move actually moves: `move s.Int` where the payload is Copy is a copy (§1.4), so a Copy sum survives its own projection. And a projection is BY NAME, so a record alternative -- which has no name, because a record type is structural -- cannot be projected at all. | Both are consequences rather than choices, and both fell out of writing the test. A sum of records is therefore a sum whose payload cannot be reached, which is worth knowing: it is reachable in the type system (`Int \| { x : Int }` is a legal type) and unreachable in the language, and the honest reading of §S54 is that only alternatives whose type has a NAME are projectable. The implementation also had a guard I invented (`base.type.named`, a field a sum does not have) rather than the rule -- a lookup that is a primitive name, else a nominal one -- which is the same derivation the injection and a `case` label already use. |
| S57 | **`rep` is the only mapping, and it REFUSES a belt type.** Anything that maps meaning to representation goes through it, and it asserts that its argument is a `Semantic.Type` -- because everything else is a caller mistake and it used to be a silent one. | Three times the same bug: a value that was ALREADY a belt type was mapped a second time, and since `rep` fell through to nil, the check that asks whether a type has a representation answered *no*. That is the worst shape a bug can have -- a wrong answer with no symptom -- and it is why this is fixed in the vocabulary rather than at the call sites that happened to be wrong. Adding the guard immediately found a FOURTH instance, in `lower_switch`, that I had introduced and missed while "fixing" the third. The naming half is the same point: `belt_type_of` and `term_type` asked the same question with one name that said which layer and one that did not, so `term_type` is now `belt_type_of_term`. And the convention is worth stating because the two layers meet in `Lower`: an EXPECTED type -- `lower_initializer`'s fourth parameter -- is a BELT type, while a place's `.type` is SEMANTIC, because it is what `copyable` is asked of. |
| S58 | **A design argument must not cite the specification as independent evidence for itself, and a sum's subject must be a NAMED binding before an arm can name its payload.** draft §3.5 claimed draft §11.7 "already" made `SelectField` ordered; draft §11.7 had been edited in the same session (S55), so the citation was circular -- a paragraph agreeing with its own draft. | The circularity is the finding; the CONCLUSION survives on other evidence, and that is the part worth keeping rather than the part worth reverting. The authority is §1.5: `/` and `%` have pure operands and lower to `CheckedBinary`, an ordered op, because a step that can trap is not a fold. `SelectField` is the same shape, so S55 stands and draft §3.5 now says so without the false citation. The second half is the binder, and it is BLOCKED on a real thing: S34 makes the `switch` subject a synthetic id that only `Lower` knows (`L_.synthetic`, a negative id in `C.state.values`), so no arm can refer to it. An arm's `case Int as n` is therefore not expressible as `let n = <subject>.Int`, because `<subject>` has no name to write. **The fix is the subtraction S34 should have been:** the subject becomes an ordinary declaration created by `Resolve` in a scope enclosing the arms, so `Lower` invents nothing, `Project` on it needs no common-subexpression rule, and `case Int as n` is plain desugaring to `let n = <subject>.Int` with the belt, the emitter, and the ASDL all unchanged. Binder vocabulary, for whoever picks this up: `Judge.Case` gains `binds :: Declaration?`, `Resolve` owns the subject declaration, `Contract` checks the binder's type is the alternative the label denotes, and `Lower` drops `L_.synthetic`. |
| S59 | **An arm that matches BINDS what it matched; reaching a payload is not an operation; and the ASDL is a DESCRIPTION, not a constraint.** draft §11.2's `Case` gains `binds` -- a `string?` in Syntax and a `Parameter?` in Judge, because a match does not COMPUTE; a sum's fields become field `0` = tag and field `1+K` = alternative `K`'s payload, every one a known offset, so `SelectField` is **deleted** from draft §11.7 and every payload read becomes a pure `LoadField`; and `Project` on a sum stops being something a source can write. **S54, S55 and S56 are superseded.** | The reasoning behind those three was wrong in a way worth naming, because it recurred: **the ASDL was treated as the authority on the design.** Every justification in the sequence was about what the notation already had -- S54 "no new vocabulary, `Project` already carries a name"; S53 "both halves of the vocabulary were already there"; S51 "no ASDL change"; S34 a synthetic id for a subject the ASDL had made an expression; and my own S55 "correction", citing draft §11.7 -- a line of ASDL -- as authority for a claim about the language. The remedy draft §0 applied to the draft had been undone one level down: the draft was demoted from authority and **its ASDL was promoted into the seat**. Both are notation, both written after a decision. Three moves produced the cascade. (1) *"The vocabulary already exists" used as a justification* -- an existing word is evidence the notation is old, not that the design is right. (2) *"This needs no ASDL change" used as a tiebreaker* -- which lets a field list decide what the language can say: `Project(base, string name)` is what made a payload reached BY NAME, and a name is exactly what a record type does not have. (3) *A self-imposed limit recorded as a consequence* -- S56's "reachable in the type system and unreachable in the language" is not a property of sums, it is S54's choice resurfacing, and calling it a consequence is what turned a patch into a law and made a second patch look necessary. The discipline that replaces it: **write the sentence in words about what a program must do; the ASDL is whatever makes that sentence true, and needing to change it is the design speaking rather than a cost.** The sentence here is *every alternative of a sum must be reachable from an arm that matches it*, and it is met by matching by SHAPE with a binder -- ONE mechanism, covering named and structural alternatives alike, needing no trap because it leaves no unchecked read to make safe. The test that would have caught all three moves, and is cheap enough to apply every time: **if the justification is "X already exists", it is not a justification; and if a limit appears, ask whether it was imposed -- if it was, remove the imposition rather than adding a mechanism that works around it.** S58 is corrected rather than withdrawn: its first half (a paragraph must not cite the spec as evidence for itself) stands and is the same disease; its second half -- that the binder is BLOCKED because S34's subject has no name -- was an artefact of assuming the binder must be an *initializer*, because the declaration ASDL says `Value(Init, ...)`. As a **parameter** it needs no subject name at all: `Lower` already holds the subject's value and its tag at the arm. **Implemented, end to end.** `SelectField` is deleted; a payload read is a pure `LoadField` at field `1+K`; `Project` on a sum is refused as an unknown name (a sum has no members to name); and `lower_switch` binds the arm's payload where it already holds the subject -- so `L_.synthetic` needed no change at all, which is what S58 got wrong. `Declaration.Stage` was renamed **`Declaration.Bound`**: "bound by the enclosing form" is what all of its uses already meant (a word's stage binder, a conversion's argument, and now a case arm), so the description got truer rather than wider. **Two gaps remain, both upstream of the mechanism.** (1) *The label grammar.* A label is parsed as an EXPRESSION, so `case Int as n` works and `case { x : Int } as r` does not parse at all -- `{ x : Int }` is a TYPE and the parser has no spelling for one there. *(Closed by §S60.)* S56's "a sum of records is unreachable" is therefore a GRAMMAR gap now and not a semantic one: the semantics admit every alternative and the surface cannot write a structural one. The fix is a label position that accepts a type expression (try `parse_type`, fall back to the expression), which is a design question about what a label IS -- a shape, or a value -- and not a parser detail. (2) *A non-Copy payload.* Binding one has to MOVE it out, and a move of a payload is a move of the whole sum (draft §3.5), because a sum has no partial state to be in. That spelling does not exist yet, so a binder on a non-Copy alternative is refused with `NeedsMove` rather than silently copied -- the honest answer, and what the ownership suite now asserts. |
| S60 | **A label is a SHAPE or a CONSTANT -- and the label SAYS which.** §11.2's `Syntax.Label = Shape(TypeExpr) | Constant(Expr)` (Judge: `Shape(Semantic.Type) | Constant(Initializer)`), so `Case`'s labels stop being `Expr*`; in label position the parser tries a TYPE first and falls back to an expression, the way §S27 backtracks for an ambiguous `{`. S59's gap 1 is closed and **S56 is now fully fixed: `case { x : Int } as r` compiles and runs** (`test/native.lua` #20 prints `7 3`). | `Label = Expr` was not a simplification -- it was a **misdescription**, and the misdescription WAS the gap: a shape has no expression spelling at all, so `{ x : Int }` could not be written as a label, and §S51's "a label is an expression, so no ASDL change is needed" is the very move S59 diagnosed -- the notation deciding what the language can say. Naming the two kinds pays for itself twice: `case_key` no longer reads what a name is DECLARED to be (the §S52 hazard for labels, gone), and `lower_switch`'s `binding_of` reads `label.denotes` instead of a declaration. Three things fell out, and each was worth recording. (1) **A collision, caught by the rule that has caught every one:** `Judge.Constant` was already a `Fate` case, so the label's value kind took the name and `Fate.Constant` became **`Fate.Immediate`** -- the truer word anyway, since the fate says "no C variable is written" rather than "the value is a constant". (2) **`true` is a lexical NAME (§12.0), so a type-first parse silently reads `case true` as a shape for a type named `true`** -- a Bool label turned into a shape. The guard is the same test the expression parser already used, extracted as `is_boolean` so there is one owner of what a Bool literal is spelled like. (3) **The increment found a latent defect of §S57's exact shape, in a function nobody was looking at.** `belt_type_of_term` is a second, PARTIAL owner of "the type of a term": it answered for `Literal` and `Reference` and returned **nil for everything else**, and the injection read that nil as *"nothing to inject"* -- so a record value meeting a sum-typed stage was never injected, was given the SUM as its result type, and the mistake surfaced only as an unprintable `Construct` in the emitter. That is §S57 one layer over: a mapping that cannot answer must SAY so. The fix handles `Aggregate` (mirroring `Contract.type_of`'s field construction) and turns the unknown case into `Missing(TermType(form))` -- the compiler reporting the mechanism it lacks instead of guessing -- with the three call sites propagating it rather than reading nil as a fact. **The debt this recorded is now FIXED rather than carried:** §S61 deleted `Lower.belt_type_of_term` and the `TermType` report with it, so `Contract.type_of` is the one owner of a term's type and `Lower` never asks -- it produces. |
| S61 | **A term's type is not a question `Lower` asks -- it is what lowering the term PRODUCES.** `belt_type_of_term` is DELETED, and with it the `Missing(TermType)` report it had just needed and the `Aggregate` branch it had just grown; `lower_initializer`'s `type_` parameter now means one thing only -- **the type the value must BECOME** -- and the injection lowers the value FIRST and reads the alternative off `value.type`. Every other branch names the type it produces: a literal its own form, an aggregate from its members' produced types, a comparison or `Not` `Bool` via one `BOOLEAN_RESULT` table. The `switch`'s subject and an assignment's value are lowered with no expected type at all. | The debt §S60 recorded was real, and the fix was not to unify the two owners but to **delete the asker**. §11.7's `Instruction` already carries its results, so a value in `Lower` has always SAID its type -- `type_` was only ever used to *set* that field, never to learn anything, which is why removing it changed no behaviour and all 783 checks passed untouched. That is the test of this kind of redesign: **a change that removes a rule and breaks nothing was not a rule, it was a transcription.** What remains is §10's shape and not a defect: `Contract.type_of` decides a term's type in the semantic vocabulary and `Lower` produces it in the belt vocabulary, exactly as `copyable` and `Belt.Type:equals` both answer "is this Copy" -- each layer derives the fact from the same ASDL semantics, and **neither asks the other**, which is the thing the deleted function was doing wrong. `belt_type_of(L_, id)` survives because it answers a different question -- the type of a DEFINITION, read from the interfaces `Lower` builds for itself -- so no term-level question is asked anywhere in the phase. Two details worth their lines: the injection's recursion (`lower_initializer(..., value_type)`) is gone, so a payload is lowered exactly once instead of once per level of nesting; and a Lua rule caught a real mistake in the edit -- `return` must be the last statement of its block, so the injection's `return value` had to move *inside* the branch, which is also where it belongs semantically. **The redesign was not complete until the LAST use was gone, and removing it found a crash.** The aggregate branch still read a member's expected type from `type_.fields[i].type` -- precisely the reading of `type_` as "the type it has" that this entry deletes -- and it survived the first pass because a NAMED member is always a `Reference` (Resolve binds it as its own definition), so the branch that reads `fields` is reached only by a POSITIONAL aggregate. `Contract` refuses a positional aggregate against a named record alternative (`MismatchedType`), so no ordinary program got there; a sum with a **tuple** alternative accepts it, and `let s : Int | (Int, Int) = { 1, 2 }` died with `attempt to index local 'type_' (a nil value)` -- the expected type there is the SUM, which has no `fields`. The fix is to pass nothing and let the member produce its own type, and `test/control.lua` now asserts that both the binding and the argument reach the alternative by injection. That is the shape of this whole entry: **each surviving "ask" was either dead code or a crash, and neither was visible while the ask looked harmless.** **One note in this entry was WRONG and is corrected by §S64:** it claimed a comparison's operands were being typed `Int` where they should be `Bool`. `Int` is exactly what a comparison takes -- only `and`, `or` and `not` are Bool to Bool -- so there was no defect there, and the real one was `not`'s operand, which this entry did not look at. |
| S62 | **Invocation is not desugared, because `f()` is not juxtaposition.** `Judge.Initializer` gains `Invoke(callee, arguments, span)`; Lower folds the arguments into `Apply`s so that `f(a, b)` and `f a b` are the same operations (§S13), and handles the empty argument list as the one case that supplies no stage -- legal exactly where the word has none, and otherwise `Undersaturated`. | §1.2 says the two forms differ only in the residual's lifetime, which is true for every non-empty argument list and false for the empty one: `f()` runs the terminal, whereas `f` is the word *value* at prefix 0. Without it a zero-stage word's `run` is unreachable, so its body is never lowered at all -- the demand-driven rule (§S23) turning a missing spelling into silently-absent code. **Written as `S33` and renumbered here**, because `S33` is §3.4's precedence row and two rows may not claim one number; nothing cited the number, so the number yielded rather than the row. |
| S63 | **The specification is checked by rereading it -- and now by a suite that compares it with the code -- so maintaining it is part of the work.** Ten defects were found and fixed. In the document: §2.5 had a duplicated line; §3.5 still said a payload read was "the *ordered* operation ... a failure is a trap" two paragraphs after saying there is no unchecked read to guard, so the section contradicted itself; §11.6's `Declaration` sum had `Label`/`Case` spliced into the middle of it by an earlier edit; §11.8 listed `MissingWhy.TermType` after §S61 deleted its only producer; §12.3 lost a duplicated `Seal` line, kept two orphaned table rows (one of which already existed in the table, and the other was re-added where it belongs) and repeated a sentence; §12.5 said "Four consequences" and listed five; and the ledger was in two orders at once -- rows inserted above their anchor are descending while the table is ascending -- with one row carrying a number that was already taken (`S33` twice, once for §3.4's precedence and once for invocation). Then `test/spec.lua`, which compares the document's ASDL with the vocabularies' declaration by declaration, found three more that reading had missed: §11.6's `Initializer` had no `Unary` and no `Binary`, both of which Contract and Lower construct; §11.6's `Stmt` was missing the `Source.Span` on `If`, `While`, `Break` and `Continue`; and §11.8's `RejectWhy` was missing the three import reasons §S39 and §S40 added. `Belt.SelectStore` was deleted as dead vocabulary -- nothing could produce a dynamic key, which is the `MissingWhy.TwoRuntimeIndices` gap rather than an opcode. | **Every one of those defects came from an edit that only ADDED**, and each is the kind that reading catches and running cannot: nothing in the suite read the document, and the compiler does not read it either, so a corrupted specification is invisible to every other test. Two rules follow. **Edit for the shape of the whole, not the site of the change:** after a constructor is added to a sum, re-read the sum; before a row is inserted into a table, check the table's order convention. And **a number is a reference**, so a collision is repaired by renumbering the row and never by reusing the number -- `S19` is a recorded hole for the same reason, and nothing cited `S33`, which is the only thing that made the repair safe. The suite is the durable half. It compares the ASDL as a **token sequence per declaration**, ignoring `--` comments and layout (the document's copy is allowed prose and to line its `= ` up) and ignoring declaration **order** (the document groups for a reader, the code orders by dependency, and neither is wrong) -- so a constructor that moved from one sum to another, a renamed type, a field only one side has and a declaration only one side has are all caught, while alignment churn is not. **It was verified by making it fail**, because its first version overwrote the document's copy with the code's and passed while comparing the code with itself: a check that cannot fail is worse than no check, and the same test -- mutate the thing the check is about, and watch it break -- is what the belt's three silent-failure rules have taught all session. |
| S64 | **draft §1.5 states the operator typing, because three places must agree on it and the spec had no home for it.** `and`/`or`/`not` are `Bool` to `Bool`, a comparison is `Int` to `Bool`, and every other operator is `Int` to `Int`. In the code the rule is now two tables in `Lower` -- one for operands and one for results, because those are not the same division -- and `Known` folds `not` as well as `Negate`. | The rule was never in this document. It lived in the DRAFT's draft §3.4 and §1.5 and was cited from the body as if those sections were here, where draft §3.4 is Assignment and draft §13 has no subsections at all -- §S50's disease with a different number, and the tell is the same: a citation to a section that says something else is worse than no citation, because it makes an imported rule look specified. The code was right about comparisons all along (a comparison compares **Ints** -- a sum's tag is one too, which is why `switch` uses the same operator a program uses) and wrong about `not`, whose operand was lowered with the `Int` that arithmetic asks for: draft §12.2 required a `Bool`, the belt typed the literal `Int`, and `Known` -- which folded only Int unaries -- left `not true` unfolded. Three statements of one rule with one of them disagreeing, which is exactly what stating it in one place prevents. **§S61's note is corrected rather than carried:** it recorded “a comparison's operands are still lowered as `Int` rather than `Bool`” as a follow-on defect, and that was never a defect. The false note is why this row exists: a ledger entry naming the wrong thing is the same class of defect as a paragraph citing the wrong section. |
| S65 | **Whether a `case` binder copies or takes is DERIVED from the payload's type -- and because taking a payload is a decision about the SUBJECT, every arm must take it or the program is refused.** `Contract` counts the arms that move (an arm binding a non-Copy payload) and requires that count to be *every* arm with no `else`; a subject that no arm takes is `Missing(SumDestruction)`, because destroying a sum needs a destructor chosen by its tag. `Lower` derives the same thing per arm (`denotes:copyable()`), emits the `Move`, marks the subject's root as moved, and hands the payload to the binder -- which the arm's own scope destroys, since a `Bound` declaration lives in the region's `values` and does not cross the join. | This is §3.5's *"moving a payload out of a sum consumes the whole sum"* made checkable. It had been refused wholesale -- every binder on a non-Copy payload was `NeedsMove` -- which made the case unreachable rather than handled, and that is why the work is worth recording: **it found a latent defect in the belt's type equality.** `Belt.Named` had no `equals`, so it fell back to identity and two `B.Named('Handle')` values never matched. `Semantic.Named:equals` has compared by name since §S44, and §S49 says the belt MIRRORS the semantic equality -- `Belt.Sum:alternative` being the site that needs it -- so any sum with a host alternative could neither inject nor discriminate, and nothing had reached it because the only tests using one stopped at a `NeedsMove` refusal. Two smaller findings, both about the agreement check: it could not see the subject at all, because `agree` walks the PARENT's places and the subject had no entry there; and registering one made an *exhaustive* all-non-Copy switch diverge on its unreachable fall-through path. So the check belongs in `Contract`, where the fact is static -- the arms' forms -- and the belt-level registration was removed rather than kept, which is the shape of the whole entry: the mechanism was already there, and what was missing was the rule. The rule is three cases with a test for each, and the native one has the host count its own allocations and releases: `made=1 released=1 slot=1 dropped=1` is what says the payload is owned by the arm that matched it and released exactly once. |
| S66 | **Exhaustiveness is a fact about the subject's type and the labels, and two things follow from it: an exhaustive `switch` has no fall-through path, and the agreement check compares the UNION of what its paths know about.** In `Lower`, `covers_everything()` derives it from the belt's types -- a sum whose every alternative is labelled, or a `Bool` whose both values are -- and the tests are compared only when it is false. In `agreement`, the ids come from `yes` and `no` and the parent rather than the parent alone. | §S65 hit this and recorded the symptom: an exhaustive switch over a non-Copy sum diverged "against its own unreachable fall-through". Two defects were behind it, and the second is the serious one. (1) The fall-through of an exhaustive switch **cannot be taken** -- that is the same fact §12.3 states as *"a switch terminates only when every value is caught"*, and `Contract` already derives it for the statement -- but `agree` compared it as a path, so a correct program was refused. (2) **`agree` iterated the PARENT's places, and a place's entry is created when something first marks it -- which usually happens inside an arm.** So the check silently skipped exactly the place the arms disagreed about: `let w = made(1)` at the top level and `move w` in one arm of an exhaustive switch was ACCEPTED, because the parent had no entry for `w` to compare. That is the worst shape this class of bug has -- a soundness hole with no symptom -- and it was found by trying to make a *fix* fail: the first mutation of (1) changed nothing, because (2) was hiding the case. The two fixes are now each verified by mutating the other's absence: removing (1) breaks the accepted all-non-Copy sum, and removing (2) accepts a program that moves an outer place on one path only. **The general lesson is the one §S57 already recorded**: a lookup that falls back to `{}` for "absent" is a lookup that cannot tell "nothing is moved" from "I never looked", so the id set has to be the one the *question* is about -- the paths -- and not the one the previous phase happened to leave behind. `Contract`'s `terminates` also already handled sums, so §S52's "known to be incomplete: an exhaustive `switch` over a sum is still refused" was stale and is corrected here rather than carried. |
| S67 | **A `mut` member is interior mutability -- that rule is draft §3.7 now, and the cell and the load are spelled out with it.** Writing through a projected place needs the record's storage to be addressable, so the binding that holds it is a cell (draft §3.2); a cell is read by a `Load`, and a load of something that cannot be copied hands out a second owner -- so a `mut` binding of a non-Copy type is **write-only**: reading it is `NeedsMove`, and moving out of it is `ConflictingBorrow`. Implemented here: draft §3.7, the read refusal, and the destruction of a cell through a load of its content. | The read refusal and the destruction are both **soundness defects the cell path has carried since §S32**, and neither had a test because every `mut` binding in the suite holds an `Int`. (1) `let h mut = made(1)` followed by `let v = h` loaded the cell -- a COPY of an owning value -- and destroyed the copy, so the host released one handle twice. It is now `NeedsMove`, which is the honest answer: the value cannot be copied, and draft §3.2 forbids moving out of a live cell. (2) `destroy_all` handed the destructor `C.state.values[id]`, which for a cell IS its address, so the emitter printed `release(&v6)` -- **invalid C**, and for a record a destroy of members read off an address. It loads the content first now, and the native test says `made=1 released=1`. One tell covers both, and it is the one this session keeps meeting: **a cell's value is its address**, so code written for a value silently becomes code about a location. **Decided here and not implemented: the store half.** `r.x = 2` through a non-`mut` binding is still `ReadOnlyDestination`, because the representation it needs is reading and writing a member *through* the storage rather than loading the whole record into a temporary -- exactly the "chained address the opcode cannot spell" §S37 named, and the reason draft §3.7 states the rule before the mechanism exists. `§3.7` was a dangling citation to the draft in three sections of this document and eleven code comments; the rule lives in draft §3.7 and every citation now points there. |
| S68 | **An address CHAINS: a place's address is the address of the record that CONTAINS its field, and `Belt.FieldAddress` takes it one step further in.** So a nested store works at any depth -- `r.inner.x = 9` reaches the inner record through the cell and stores through that address -- and `FieldAddress`, declared in §11.7 and produced nowhere since, is now produced, typed and emitted. | The opcode existed because §11.7 asked for it and nothing had needed it. Two conventions had to agree for it to work and neither was written down. (1) `StoreField`'s operand is a **pointer**: the emitter already prints `(*addr).field = v`, and a one-level store was `StoreField(cell, field, value)` -- which is what the chain rests on, because it means a projection's address is the address of the record *containing* its field rather than the field's own. (2) `FieldAddress` produces `B.Cell(field_type)`: a cell is the belt's only "address of something" type, so an address of an address is still a cell, and `StoreField` reads `.contents.fields` off it without knowing whether it came from a binding or a chain. The dead vocabulary is worth recording as a *pattern*, because this session has now met both kinds: `SelectStore` was declared by nothing and deleted (§S63), while `FieldAddress` was named by a *design sentence* -- §S37's "deeper needs a chained address the opcode cannot spell" -- and only needed producing. **Named by a sentence, keep; named by nothing, delete.** Two smaller notes. The chained address is built for the READ path too, because an address is a fact about the *place*; it is pure and unused there, so `Known` drops it and nothing is emitted, which is why the test counts two rather than one and says so. And what is left is now the only thing §3.7 waits on: a read of a *member* still loads the whole record into a temporary, so a member of a non-Copy record cannot be read through a cell -- and such a record is non-Copy by §2.5, which is exactly why §3.7's store half needs that read path before it can be legal. |
| S69 | **A MEMBER of a place in storage is read through its address, not by loading the record.** `read_place` builds `Load(FieldAddress(address, offset))` when the place has an address, and `lower_place` builds a value ONLY for the path that has none -- a field of a VALUE -- which is also what stops a store destination from building a value it never uses. | §3.7 named this as the piece it was waiting on, and §2.5 is why: a record with a `mut` member is not `Copy`, so loading the whole record to read one field fabricates a second owner of everything else the record holds. The native test is the evidence -- a `mut` record holding a host `Handle` beside a `mut` `Int`: `r.i = 7` then `return r.i` prints `7 made=1 released=1`, and `released=1` is what says no duplicate owner was made. The same change removed a defect the STORE path had carried: `lower_place` built the place's read value for both callers, so every projected store carried an unused whole-record copy -- `struct let_s4 v8 = (*v7);`, emitted, because a `Load` is ordered and ordered ops are emitted. The tell is this entry's own sentence -- **a place is a LOCATION and a value is what reading it gives** -- so building a value where a location is wanted is a mistake no test can see until the value it copies owns something, which is exactly the shape §S65 and §S66 kept meeting. It also settled §S68's arrival: the chained address is now built once per projection per caller -- three in the assignment test, each doing work -- where the first version left one dead. What is still unbuilt is the other half of §3.7: a store through a `mut` MEMBER of a read-only binding, refused as `ReadOnlyDestination` because that binding was never address-taken, and it now needs only the celling rule rather than the read path as well. |
| S70 | **Writability through a `mut` member is a rule of the PATH, and it is enforced in `Contract`: a place is writable when the binding it starts at is `mut` OR when any step of its path names a `mut` member.** The celling that would STORE it is not settled, and this entry records the collision rather than a decision. | §3.7's first half now has a mechanism -- `writes_through_a_member` walks the place and asks each step's type -- and it is one rule rather than two, because a `mut` binding makes everything under it writable and a `mut` member does the same for its own subtree. The second half was tried and REVERTED: making such a binding a cell is the shape a `mut` binding has (§3.2), and it is what addressable storage means, but it collides with two rules at once. §2.5 makes a record with a `mut` member **non-`Copy`**, and §3.2 forbids moving out of a live cell -- so `let m = { let x mut = 1 }`'s whole value could no longer be **exported**, nor moved, nor read as a whole (a cell read is a load, §S67). Four tests failed, the canonical example among them, and that is three rules meeting rather than a missing mechanism. So the honest report for a store through a `mut` member of a read-only binding is `Missing(FieldStore)` -- *the rule is settled, the mechanism is not* -- which replaces a `ReadOnlyDestination` that called a correct program wrong; §13's distinction between `Reject` and `Missing` is exactly this, and getting it wrong here was saying the program is broken when the compiler is. **The question this recorded -- what storage a `mut` member lives in -- is ANSWERED by §S71**: the binding is a cell, because §3.2's conflict is conditional and no view of it is live, so the record stays movable, exportable and readable by its owner. What the collision actually was, and the reason this entry is worth reading before the next one: one of the three rules was being applied **without its condition**. |
| S71 | **§3.2's conflict is CONDITIONAL, and that condition is the design solution to §S70's collision.** *"Moving, replacing or destroying the owner WHILE A VIEW IS LIVE is a conflict"* -- and a **view is a pointer into the storage**. `Lower` builds no capture at all, and the field addresses `FieldAddress` builds do not outlive the expression that takes one, so the condition is not met and a cell CAN be moved out of: `take_place` hands over the cell's CONTENT (a cell's value is its address) and marks the place moved. With that, §3.7's celling lands -- a binding whose type has a `mut` member anywhere is a cell, derived as `Semantic.Type:interior_mutability()` beside `copyable` -- and a whole-value move is what lets such a record be owned, exported and destroyed once instead of being write-only. | The collision §S70 recorded was between three rules, and the fix was to notice that one of them was **being applied without its condition**. The implementation had equated "celled" with "viewed" -- `take_place`'s comment said so in as many words -- and that equation is what made every `mut` binding immovable, which is what made a non-`Copy` record in a cell unreadable, unmovable and unexportable, which is what the four failing tests said when the celling was first tried. Restoring the sentence's condition fixed all four at once: the canonical `{ let x mut = 1 }` is exported again, and the two tests that asserted `ConflictingBorrow` for `move n` now assert it is LEGAL -- for a Copy type §1.4 makes the move a copy, so nothing is emitted, and for a non-Copy one it is a real `Move`, which is what an owner needs. Three things fell out. (1) **`place_value` is now the one owner of "what does this place hold"**: a read and a move had already disagreed the moment §S69 stopped building a value for a place that has an address, and `take_place` was reading `p.value`, which is nil. (2) **The rule was written in two places and only one was changed**: `materialize` decided the cell with `declaration.mutable` while `lower_place` asked `is_cell`, so a §3.7 binding had an address for reads and not for writes -- the same defect class as §S57 and §S66, caught this time by asking the compiler to emit C rather than by a test. (3) `ConflictingBorrow` stays in the inventory and stays correct: it is what a **captured** cell must return, and captures are the piece that will make this condition real rather than vacuously satisfied. **§S70's open question is answered**, and the acceptance test it named is the native one: `let r = { let h = made(n) let i mut = 0 }` with `r` READ-ONLY, then `r.i = 7` and `return r.i`, prints `7 made=1 released=1`. |
| S72 | **The gap inventory is a checked claim, and four of its six entries were not.** §15 says "the gap inventory is `MissingWhy`; a test asserts which alternatives are reachable and from where" -- and no such test existed, so every entry was a claim nothing could falsify. `test/gaps.lua` is that rule made checkable: one program per alternative, the phase that must report it, and the exact reason, with the set of alternatives reached required to equal `R.missing_reasons` -- so an alternative can be added only WITH a program that reaches it, and one that becomes unreachable fails here. The audit removed four names, each for a different reason. `PreludeBeforeNextArgument`'s sentence was **false**: §1.2 said a prelude between two supplied arguments "is still refused", and the compiler had been lowering it correctly -- `test/native.lua` #26 reads `12` from `(1 * 10) + 2`, which is the only evidence there can be, because both orders typecheck. `FieldStore`'s producer became unreachable in §S71: `Contract` accepts a projected destination by walking the PATH (`writes_through_a_member`) and `is_cell` makes storage addressable by asking the TYPE (`interior_mutability`), so writable implies addressable and no program can be a writable place without an address; the guard stays as `Bug(UnaddressableDestination)` because it is where those two derivations have to agree. `ModuleStateCell` was named by nothing at all -- no sentence, no producer. `IndirectWordInvocation` had **three producers with three different meanings** and appeared in no sentence of the document: the two aggregate sites are one sentence (§3.1's "a record type and a value aggregate are the same form") and are now `MemberPrelude`, and the re-entered interface deriver is the compiler disagreeing with itself, now `Bug(InterfaceCycle)`. **One gap was found by asking the question the other way round**: `Recursion` had no name because the resolver answered `UnknownName` for a self name -- but §1.4's row makes the self name visible inside the terminal `do` body, so `let a = a` (the initializer: the design refusing a program) and `f(a)` inside `f`'s own body (the name resolving, the USE being the gap) are two answers to two different sentences. `Resolve` now binds the self name in the body's scope to a sentinel and reports `Missing(Recursion)`, and `test/gaps.lua` reaches it. | Every entry in this inventory had **zero** programs reaching it, which is the same failure mode as a belt rule with no consumer: it reads like work and it is not. The reason to audit an inventory rather than trust it is that a `Missing` **never fires**, so nothing can disagree with it -- a wrong entry is invisible, and while it sits there it describes a compiler that does not exist. The four removals are four different kinds of wrong, which is why the audit earns its own row: a sentence that is false (the mechanism exists), a producer that a later fix removed (§S71), a name with no sentence, and a name with three meanings. The rule that comes out is the one §S68 already had -- **named by a sentence, keep; named by nothing, delete** -- now applied to the diagnostics themselves, where "named by a sentence" also has to mean "and a program reaches it". §15 was already the place that said exactly that; the test that did it did not exist. |
| S73 | **A citation to a section DESIGN.md does not have is a citation to the DRAFT, and the class is now impossible.** §S67 repaired one such citation by hand and this audit found **149 more**, across **24 draft sections** -- draft §9.2 alone was cited 34 times -- in the document and in every source file, several of them written the same day. The repairing rule is one sentence: **a citation is to this document unless it says `draft`** -- and `test/spec.lua` now checks it, by requiring every `§N.M` in the document and in every source file to name a section the document HAS, while a citation whose preceding characters say `draft` (or name the draft file) is history and is allowed. The repairs are per RULE and not per number: draft §9.2 ("a read of a non-Copy place") is §1.4 here, draft §9.3 (a borrow is not a value) and draft §9.7 (cycles) are §1.4, draft §9.4 (assignment) is §3.4, draft §9.6 (`switch`) is §12.3, draft §8.5 (`Copy` is structural) and draft §6.3 (`Copy` is the `copy` capability) are §2.5, draft §8.3 (interior mutability) is §3.7, draft §6.2 (the two application forms) is §1.2, draft §6.4 (falling off the end returns `Unit`) and draft the reference's type section (no implicit truthiness) are §12.3, draft §13.3 and draft §13.4 (operator typing and no conversions) are §1.5, draft §13.5 (`Text` is a module-lifetime literal) is §11.3, draft §13.6 and draft §15.3 (host vocabulary) are §3.6, draft §8.2 and draft §8.4 (the aggregate forms, unnamed tuple members) are §3.3, draft §9.1 (the primitives) is §11.3, and draft §10.1-§10.3 (the vocabulary layers) are §10. **Five rules turned out to exist ONLY in the draft**, which is what a dangling citation promises and does not deliver, so they are now written where they belong: `true` and `false` are lexical NAMES (§12.0); there are no implicit conversions between the operator domains (§1.5); a condition is `Bool` with no implicit truthiness, statements and members run top to bottom with destruction the reverse, and falling off the end of a body returns `Unit` (§12.3). | The tell is §S50's and §S64's, at scale: **a dangling citation is worse than none**, because §9 of this document is "The two call shapes" while a comment citing draft §9.2 means a rule about reads -- so the comment LOOKS sourced, and a reader who follows it lands on a section about something else. What made this repairable in one pass is that the mapping is per rule rather than per number: the code was right about all of these rules, so every repair was "where does this document state this", never "what should this do" -- which is why not one behaviour changed and the check is the only new thing. It is deliberately partial, and says so: it can only catch a section number the document does not HAVE, so a citation to an existing section that states something else is outside it -- draft §7.1 ("`do ... end` is the only source form with runtime statements") points at §7.1 here, which is *Exits*. Catching that one needs the other half of this suite: reading the cited section. draft `§18` needed a different repair from the rest -- it was cited twice for DEFERRED work, and this design has no deferral section because **deferral IS `MissingWhy`** -- so those citations are deleted rather than re-pointed and the sentences stand without them. |
| S74 | **Recursion is built, and what it took was a PLACE, not a mechanism.** The self name is an ordinary reference to the definition (§1.4), so `let fact = ... fact(n - 1) ...` demands the instance that is already being lowered; `demand` reserves an instance's id before lowering it -- §12.3 already said that "is what makes a cycle terminate" -- and the recursive call is a call to the **same** `run`. `fact 5` is `120` and `let fact_run` exists once (`test/native.lua` #27). Two edits, both the removal of an assumption rather than the addition of a feature: `Resolve` binds the self name in the terminal body's scope to the definition's own id -- the caller already reserves it before resolving the chain, so no new vocabulary was needed -- and `Contract` publishes the interface from the DECLARATION before checking the body, so a self-reference reads it instead of re-entering the derivation. **`MissingWhy.Recursion` leaves the inventory, one increment after it was added, and `BugWhy.InterfaceCycle` is deleted** -- the whole of it is that `building[id]` no longer exists. | This is the one entry in the audit whose removal is *progress* rather than a correction, and it is worth a row because of how it went. §S72 found the gap by asking why `Recursion` had no name and answered it with a sentinel and a diagnostic: the name resolved and the USE was the gap. That was right about the sentence and wrong about the work -- **the gap was not that recursion was unnamed, it was that the name was bound to nothing.** Binding it to the definition made Resolve correct on its own, and the only thing left was Contract's guard, which existed because the interface was published *after* the body. §S52 had already stated the rule that fixes it -- "a check reads a DECLARATION, never a derived interface that may not exist yet" -- and the guard was the compiler violating it: the deriver re-entered because the fact was published late. So the repair is §S52 applied literally, and the tell is that **a check disappears and a behaviour appears**: a `Bug` cannot fire any more, and recursion works. What is left in the inventory is three entries, each of which is a *representation* the compiler does not have (a runtime index, a member's prelude, a tag-chosen destructor) rather than a rule it cannot apply. |
| S75 | **FOUND, and FIXED by §S76: a word's read of the module's state was not the module's state, because the capture vocabulary that would make it one was declared and produced NOWHERE.** §2.6 says "a word's fields come from the namespace", so a file-level prelude is the module's storage, constructed once by the initializer. `Lower` has no such mechanism -- `packet_of` carries a word's OWN chain's stage values and prelude bindings and nothing else -- so `materialize` on a reference to a module prelude falls back to lowering that prelude's INITIALIZER inside the WORD's instance. Two programs say what that does. (1) `extern tick (n : Int) : Int` + `let k = tick(1)` + a word returning `n + k` prints `41 tick_calls=2`: the prelude is constructed a second time, and the value agreed only because `tick` is deterministic. (2) `let c mut = 0` + a word that does `c = c + 1`, applied twice, emits C that does not compile -- `int64_t v11 = (*INT64_C(0));` -- because the word's instance holds the prelude's VALUE where the store path needs its ADDRESS; and had it compiled, the two applications would each have incremented a private copy, so `a` and `b` would both be 1 rather than 1 and 2. **The acceptance test is exactly those two programs: `a=1 b=2` from two applications of a word that increments a module `mut`, and `tick_calls=1`.** | The cause is not a missing rule but a missing PRODUCER: `Chain.Capture = (number binder, string name, Semantic.Capability mode)`, `Chain.Template.captures`, `Resolved.captures` and §12.1's table row "which bindings does this word capture, in what order?" are all in this document, and `resolve_value` constructs its Template with a literal `L{}` in the slot. §3.2 says what a capture IS -- "captured state lives in a cell", "a word's state is its own preludes plus its captures (celled, opaque)" -- and §2.2 says where it goes: the residual is "captures + stage values 0…k-1 + prelude bindings", so the captures are the frame the rest of the packet lives in. So the fix is four places and no new vocabulary: **Resolve** notices that a reference crosses a chain boundary (§1.4's table gives a capture the enclosing lexical scope as its extent) and declares a binder whose value is the outer binding; **`packet_of`** prepends the template's captures; **`construct`** takes them as parameters and binds them to their binders, so `run`'s existing `unpack` reaches them; and the captured binding is **celled**, which is what makes §3.2's "while a view is live" condition real instead of vacuous and restores `ConflictingBorrow` as a live check -- §S71 predicted exactly this and this row is where the prediction comes due. It is also why a NESTED word naming an enclosing word answers `UseBeforeInitializer`: a wrong reason for a name that exists. The Resolve half was written, verified to produce captures, and REVERTED rather than landed, because it changes what every top-level word produces and so is only correct together with the `Lower` half -- and a half-landed pervasive change is worse than none. |
| S76 | **Captures are built, and the fix is the packet's FRAME -- no new vocabulary, four places.** `Resolve` notices that a reference crosses a chain boundary -- a boundary is a chain that becomes a WORD, a new INSTANCE, and NOT merely a new scope: a value chain like `let a = f 1` is inlined where it stands, and treating it as a boundary made every file-level binding a capture on the first attempt -- and declares a binder whose value is the outer binding, collecting them in first-mention order into `Chain.Template.captures`. `Lower`'s `packet_of` prepends them (§2.2's "captures + stage values 0…k-1 + prelude bindings"), `build_construct` takes them as parameters and binds them to their binders, `unpack` refills them at every advance, and `packet_of`'s new order makes `run`'s existing binding machinery reach them. A capture is **celled** unless §3.2's cheap row applies ("captured read of a Copy value ⇒ copied; no cell"), and a CELLED capture is the owner's own cell -- one indirection, the same storage -- so `is_cell` returns true for both the capture's binder and the binding it captures, `capture_arguments` passes the owner's address when celled and its value when not, and `destroyable` skips a capture because the owner's scope exit is what destroys it. **§S75's two programs are the acceptance test and both pass**: `a=1 b=2` from two applications of a word that increments a module `mut`, and `tick_calls=1`. | Six things fell out, and five are the session's recurring defect -- **one question asked in two places**. (1) `field_type_of` is now the one owner of "what does this name's SLOT hold", because a celled capture's slot is a POINTER while `belt_type_of` answers what reading the place GIVES; without it the emitted C declared an `int64_t` and then dereferenced it. (2) The module namespace builder duplicated `materialize`'s cell logic, so a top-level `mut` prelude held its VALUE where every word's capture expected the ADDRESS -- and it now calls `materialize`, which is the owner. (3) `destroyable` owned a capture, so a borrowing frame destroyed the owner's value -- and it owned a WORD, whose interface result is what its `run` RETURNS and not what its packet HOLDS, so a host destructor was handed a struct where it wanted a handle. (4) `materialize` refused a WORD declaration, which made a capture of a word unreachable -- a word is a value too, `R(t,0)`, and materializing one constructs it. (5) A captured word must be READ and not constructed: that is what §3.2's one indirection means, and `base_of` is the one place that decides between constructing `R(t,0)` and reading what the frame already holds. (6) A capture of a capture passes on what the frame was given rather than rebuilding it, which is what stopped a recursive call from constructing the module's state again. **And the condition §S71 put back is now REAL rather than vacuous**: `take_place` refuses a real move of a celled owner, because a celled capture is exactly the live view the sentence is about -- the check sits AFTER the Copy test, since `move c` for a Copy `c` is a copy and refreshing an old value to destroy it is not a move. One test had to change for the right reason: §S66's agreement test moved a FILE-level place, which is now a capture and therefore refused as `ConflictingBorrow` before the arms are compared, so it moves the word's own prelude instead -- the rule it tests is the agreement check, and the place it moves must be one nothing views. |
| S77 | **The `RejectWhy` inventory is audited with §S72's rule, and it had never been.** §S72 made the GAP inventory a checked claim; the REJECT inventory -- 24 alternatives, and the rules a program is wrong for -- was never asked the same question. Asked now, one alternative is **named by nothing at all**: `UnsatisfiedStage` appears in the ASDL and nowhere else in this document, while `Undersaturated` is the name for the concept, so the ASDL was the only thing keeping it alive and it is deleted. Two more -- `BorrowedEscapes` and `BorrowOfTemporary` -- are named by §3.6's own table ("a place → containment: the view's scope must be inside the owner's", "a temporary → rejected") and are produced NOWHERE: the rules are stated and unenforced. That is the remaining ownership soundness hole, and implementing it needs the declaration §3.6 already describes but the ASDL cannot express -- "a host type may declare that it borrows argument *i*", while `Syntax.Host`/`Judge.Host` carry only `(name, destroys)`. | Reading the document found this, which is the point: a `Missing` never fires, so §S72 had to construct programs to reach one -- but a `Reject` that never fires is invisible in a different way, because a Reject is what a *wrong* program gets, and a rule that is never checked simply accepts the program. So the two inventories need the same treatment for different reasons, and the reason to do the Reject one first is that it audits the rules the compiler ENFORCES rather than the mechanisms it lacks. The same reading found two paragraphs of the document carrying decisions that were superseded: §3.2 still said moving out of a cell is a conflict "because the cell is a live view of the storage" -- the equation §S71 removed, since a cell nobody captures is movable and a **celled capture** is what the sentence is about -- and §3.7 still called the celling "the one thing here still unbuilt" and reported `Missing(FieldStore)`, both of which §S71 and §S76 answered. A stale paragraph is the same defect class as a dangling citation (§S73): it makes a rule look settled in a way that is no longer true, and nothing reads the document except a person. |
| S78 | **§3.6's borrowed types are declared, and one of their four rows is enforced.** `host View borrows 1` says which argument of the producing word a value of that type views; `Resolve` reads it exactly where `destroys` is read (the declaration is the whole contract, §3.6/S44), the index is the 1-based argument position, and an index below one is refused where it is read because a declaration the compiler cannot act on is not a contract. `Contract` derives `borrow_of(type)` -- structurally, because §3.1 rule 4 gives a record or a sum the borrow of what it holds -- and **`Interface.borrowed` is produced for the first time in its life**: the field was in the ASDL with `false` written at all four of its sites, which is §S72's class exactly. The row refused where the argument is SUPPLIED is a **temporary**: a literal is module-lifetime storage that outlives every view, a place is the containment case, a HOST call's result is foreign ("the host's contract; Let holds nothing and checks nothing"), and everything else is `BorrowOfTemporary`. `test/extern.lua` has one check per row, and the temporary one asserts the refusal. | The check was made deliberately NARROW, for the reason this project has learned about refusals: **a row that refuses too much calls a correct program wrong, which is worse than a row that is not yet checked**, so `Slice(host_text())` is allowed even though a host call's result is a temporary in the C sense -- §3.6 gives foreign storage its own row and the row is taken at its word. That leaves the containment row, and it is worth being exact about why it is not here: `BorrowedEscapes` compares two SCOPES ("the view's scope must be inside the owner's"), and the owner of a stage or a capture is not the chain being lowered -- so the fact that decides it is *whether the borrowed storage is chain-owned or caller-owned*, which source already says (`Judge.Value` is a prelude of this chain, `Judge.Bound` is a stage the caller supplied) and which has nowhere to travel from the call site that makes the view to the return that would escape it. So the fix is not a rule to invent but a place to put a fact, and §S77 named this row as unproduced; this entry produces one of the two, and records the other with its shape rather than with a guess. |
| S79 | **§3.6's containment row is enforced, and now every row of its table has a producer.** "The view's scope must be inside the owner's" is a statement about scopes, and the fact that decides *which* scope the owner lives in is already in source: a `Judge.Bound` is a stage the CALLER supplies, a capture reaches storage the enclosing instance owns (a module prelude is one, because §S76 makes it a capture), and a `Judge.Value` with its own initializer is a PRELUDE of the chain being lowered, which dies when the chain returns. So `chain_owned` READS A DECLARATION rather than carrying a lifetime -- which is what §1.4 means by "every extent is a construct the compiler already computes" -- and `borrows_chain_storage` reads declarations too, so the answer never depends on the order the checks happen to run in. The borrow travels with the value (§3.1 rule 4), so binding it does not launder it; a `Return` of one is `BorrowedEscapes`. `test/extern.lua` has the escape, the three fine cases (a stage, a module prelude, a literal), the laundering case, and one regression below. | §S78 recorded this row as "not a rule to invent but a place to put a fact", and the place turned out to be **no place at all**: the fact is a read of the declaration, so nothing travels. That is §S74's shape again -- recursion needed no mechanism either, once the interface was published rather than carried -- and it is the reason to look for the *place* before inventing the *mechanism*. **Probing then found a false refusal, which is the one outcome a check must never produce**: `view_of(make_text())` became `BorrowOfTemporary` inside any word, because §S76 makes a module-level host word a CAPTURE in every word that uses it -- so §3.6's foreign row silently became its temporary row for the commonest host call there is. `declaration_of` follows a capture to what it captures, exactly as `word_of` does in `Lower`, and the two are deliberately different functions: `chain_owned` needs the capture visible AS a capture, and following it would erase the distinction the containment row is made of. §S77 named this row as unproduced; this entry produces it. |
| S80 | **`unload` is generated, and it is the third root.** §2.6 gives the signature and the rule -- "takes the module value by value, destroys it in reverse successful-construction order, and is emitted only when the module owns something" -- and none of it existed. The unloader is a **belt function** like any other: its packet is the module value, its body binds the namespace's members from that value (`LoadField` per member, the shape `unpack` already uses) and then runs the ORDINARY destruction pass, and its result list is the effect ALONE -- so `signature_of` finds no non-effect result, prints `C.Void`, and **nothing in the emitter had to learn about unload at all**. It is a third root alongside the initializer and the entry points (§S23, §S36), demanded only when the module owns something, and "owning" is §3.1's own question: a namespace member whose type has a destructor. `let h = made(1)` prints `made=1 released=1` with the host calling it, the prototype is `void let_module_unload(struct let_s1 p1)`, and `let n = 7` / `let c mut = 0` produce no unloader at all. | Why it is a separate function rather than the tail of the initializer is the sentence itself: the initializer RETURNS the module value, so it cannot destroy what it returns -- which is exactly why the host has to give it back. The reuse is the interesting part: `destroy_all` already implements "reverse initialization order" (§3.1 rule 2) and a cell is already destroyed by loading its content (§S67), so the unloader needed no new op and no new rule, only a new ROOT -- and the prototype fell out of a declaration (a result list with no value in it) rather than out of a special case in the emitter. A `mut` Int is storage of something with nothing to release, so it is not "something" to give back. **§2.6's `state` member is the other half and is deliberately not here**: for a written terminal the module owns the terminal's value rather than the namespace's members, and "the returned value must own what the namespace does not reach" is the same sentence as the unloader's. Doing one without the other would make the written-terminal case leak silently, which is worse than not offering it. |
| S81 | **FOUND, NOT YET FIXED: a sum that owns something is never destroyed -- which is the last item in the gap inventory, found by looking rather than by testing. (Its claim stands; its EVIDENCE was wrong, and §S82 says why: the program it used was never a sum, because a body `let` was dropping its annotation. §S83 has the proof.)** `destroy_value` handles `Semantic.Named` (a destructor call) and `Semantic.Aggregate` (reverse member order) and then returns; a `Semantic.Sum` is neither, so it falls through the `if not Semantic.Aggregate:isclassof(type_) then return end` and nothing is emitted for it at all. The evidence is the emitted C for `let h = made(n)` then `let s : Int | Handle = move h` then `return n`: `let_f_run` releases `v5`, which is the MOVED-FROM local, and returns -- with no destruction of `s` anywhere, because `Known` drops the `InjectSum` whose result nothing reads and `destroy_value` emitted no `Destroy` to keep. **Three native probes were written for this and they PASSED for the wrong reason**, so they are deleted rather than kept: a host that counts calls cannot tell "the sum was destroyed" from "the local was destroyed and the sum leaked", and `made=1 released=1` reads perfectly correct on a leaking program. | §3.5 already says what the fix is -- "destroying a sum needs a destructor chosen by its tag" -- so the work is a `destroy_value` case for `Semantic.Sum` that reads the tag (`LoadField(value, 0)`), branches once per alternative, destroys the payload of the live one (`LoadField(value, 1+K)`) and joins. That makes **destruction a block-splitting operation for the first time**: the place §3.3's scope-exit destruction and §12.3's block graph have to meet, and the reason every previous destructor could be straight-line is that no value before this one had a member whose *type* is not known from its own type. **The probe exposed a second question that has to be settled with it**: the moved-from local was still released, so `move h` into a sum either did not mark the source or the marking is not what `destroy_all` reads -- and the two are not separable, because the moment the sum IS destroyed, a source that is also destroyed releases the same value twice. The decisive test is the program above with the sum as the ONLY owner: today it prints `released=1` for the other reason, a fix to the marking alone makes it print `0`, and both halves together must print exactly `1`. |
| S82 | **A `let`'s annotation is resolved in ONE place, and two of the three binding sites had been dropping it.** `resolve_body`'s `Local` and the aggregate-member path both passed `nil` where the file-level prelude passed the resolved type, so `let s : Int \| Handle = 5` INSIDE A BODY was typed as the PAYLOAD and never injected -- the annotation was not merely unchecked, it changed what the value WAS, which makes it a wrong type rather than a missing check. All three sites now ask `annotation_of`, and the mismatch that becomes checkable (`let x : Bool = 1` in a body is `MismatchedType`) is a check that could not fire before. | This is the session's recurring defect -- one rule in several places, and one of them forgot -- found the way these are always found: by *probing* a different question and getting an answer that made no sense. The tell was `DESTROY root=s type=Semantic.Named(name = Handle)` for a binding the source declared as `Int \| Handle`: a destruction that names the payload is a type that IS the payload, and no sum was ever built. Writing the annotation's resolution as a function rather than repeating three lines is exactly because two of the three were wrong -- and it is the same reason §S76 wrote `field_type_of` and §S79 wrote `declaration_of`. |
| S83 | **FOUND, NOT YET FIXED: a sum that owns something still is not destroyed, and the fix is a CARRYING problem rather than a dispatch.** Two halves had to be true and neither was: `destroys` answers `Named` and `Aggregate` and returns false for a `Semantic.Sum`, so a sum is never even CONSIDERED destructible -- and the mirror of §2.5's `Copy` rule for a sum ("every alternative") is "ANY alternative", which the design already says; and `destroy_value` returns at `if not Semantic.Aggregate:isclassof(type_)`, so a sum that did reach it would emit nothing at all. With both fixed in a scratch tree, `let h = made(n)` then `let s : Int \| Handle = move h` then `return n` prints `made=1 released=0` -- the leak, PROVEN, with the sum as the only owner so that nothing else can release it. | The dispatch itself is not the hard part: §3.5 puts the tag at field 0 and alternative K's payload at field 1+K, so it is a chain of tests over pure `LoadField`s and no opcode is needed -- and the ONE convention that had to be read off the code rather than guessed is that the tag is ZERO-based (`InjectSum` writes it, `switch` compares it, and `lower_switch` reads `1 + binds.tag` for a payload), which a first attempt got wrong by comparing the 1-based position. **What blocks it is the block graph.** A dispatch SPLITS the block, and the caller of `destroy_all` still holds SSA values the split cannot see: the `Return` branch lowers its value BEFORE the destruction -- it must, or the value would be read after its own destroy -- and then refers to it from the join, where a `Ref` is relative to the join and resolves to a different producer. The compiler said so exactly: `incompatible types when returning type 'Handle' but 'int64_t' was expected`. So the increment is a decision about how a tail-shaped dispatch meets a block whose values are already built, and the shapes it could take are: carry the caller's live producers as parameters (which needs them NAMED -- the same reason §S34's switch subject and this dispatch's subject need synthetic bindings), give the destruction a continuation so the exit is built INSIDE the join, or destroy a sum only where nothing follows it. |
| S84 | **The rewrite has a DOOR, and the first real program through it found a false refusal.** Until this there was no way to compile a FILE with the new compiler: the pipeline was assembled by hand inside `test/native.lua`, so the only caller was a test and `legacy/` was the only usable compiler. `let/compile.lua` is now the one owner of "text to `C.Unit`" (Resolve, Contract, Lower, Known per demanded instance, Emit -- the order §12 states), `let/cli.lua` is the command line, and `letc.lua` is the launcher. `luajit letc.lua fact.let -o fact.c` writes a unit that `cc` links against a host and that prints `120`; the exit codes are §13's three kinds (0 ok, 1 Reject, 2 Missing or Bug) and a diagnostic carries `file:line:column`. The unit is a MODULE and does not invent a `main`, because §2.6 makes the host a separate thing that supplies one -- and the test asserts both halves of that. | The first program worth writing in it is one that uses the module's own state, and it is refused: `let h = made(5)` plus a word that calls `peek(h)` gives `ConflictingBorrow` at the `let`, while the same program without the word compiles. **The check is FLOW-INSENSITIVE and §3.2's condition is not** -- "moving the owner WHILE A VIEW IS LIVE is a conflict" is a statement about a moment, and `take_place` asks whether the binding is captured ANYWHERE. In this program the view does not exist yet: the capture is created when `run`'s word value is constructed, which is after `h` is taken into the namespace, in source order. So the fix is to ask the question at the right TIME -- Lower knows when it emits a capture (`capture_arguments`), so the set of viewed bindings is progress state rather than a static map. **And it exposes the operation underneath**: a CAPTURED module member is celled (§3.2), so `take`ing it into the namespace should take its CELL -- one indirection, the same storage, exactly as §S76's captures do -- rather than move its content out from under a pointer that a word already holds. The acceptance test is the program above, which is the shape a real program has and a probe does not. |
| S85 | **§S84's fix landed, and the door found two more things on its first three programs.** A celled module member is now kept as its **CELL** rather than moved -- the emitted namespace says `Handle* h`, one indirection and the same storage a capture holds -- and `field_type_of` asks `is_cell` instead of "is a celled capture": one rule, the same one `materialize` asks before it allocates, so a slot and its value cannot disagree about which of the two it is. The program §S84 was refused on now compiles AND runs: `answer=11 made=1 released=0`, and after `let_module_unload(m)` exactly `released=1` -- a module-owned resource, a capture, recursion and an unload, end to end through the CLI. **The second thing is a defect the door found simply by being used**: `B.Destroy` emitted the destructor call and never registered the symbol, so the unit called `release` before declaring it and did not compile on its own -- the host had to write a prototype the SOURCE had already written in its `host` line, which is exactly what §S41 forbids ("the declaration, not the implementation, is what the compiler holds a host to"). It is fixed, and `test/cli.lua` now links a module that owns a Handle with the host supplying nothing but the TYPE. | **A door finds what a test cannot, because a test is written by somebody who already knows what works.** Both of these were invisible until a real program went through the CLI: the first as a refusal that turned out to be about the NAMESPACE's take rather than the source's move, the second as a `cc` error in the host. **Two more are named and not yet chased to the end.** (1) Assignment to a `mut` binding of a NON-Copy type is refused with `NeedsMove`: §3.1 and §S71 make such a binding **write-only**, and writing is precisely what write-only permits, so a store should be legal -- and the same sentence says a *read* is what it forbids. (2) §S84's TIMING question is still unreached, because the program that would answer it stops at that assignment first; the program is `let h mut = made(n)` / `move h` / `h = made(n)` / a nested word that moves `h` again, and at the first move no view exists yet. |
| S86 | **§3.1 rule 2's third occasion landed: assignment DESTROYS what it replaces.** The assignment path said in its own comment that this half was missing -- "a plain store until C6 gives destruction a representation" -- and C6 landed without it, so a `mut` binding of a host type leaked whatever it was assigned over. `lower_assign` now destroys the old value before the store, through `place_value` (the one owner of what a place holds: the cell's content for a root, the member read through its address for a projection), and only when the destination is not already MOVED -- `move h` then `h = made(n)` must not release the handle the move handed over. `made=2 released=2` is the test; it printed `released=1` before. **The same statement had a second defect, and it is the one a probe reached first**: Contract refused `h = made(n)` with `NeedsMove` because it read the TYPE where §3.4's sentence is about an EXISTING value -- a call's result owns itself and is stored as it stands, while a PLACE of a non-Copy type has to be taken. Both halves are pinned by `test/native.lua` #35 and #35b: the fresh value compiles, the existing place is still refused. | §S84's timing question is real, and it was implemented and then REVERTED, which is what the row is mostly for. `take_place` asking whether a view has been created YET -- a set Lower fills in `capture_arguments`, the one place a view is made -- makes the §S84 program compile while `test/assign.lua` 5b is still refused, which is exactly the pair the fix was for. But landing it broke two programs that had been fine (`test/extern.lua`'s "a scope that owns one" and native #22), so the check was refusing a move that §3.2 PERMITS -- and the likely reason is that `capture_arguments` marks an owner viewed even when the capture is a COPY, while §3.2's cheap row says a copied capture holds no pointer, so moving the owner conflicts with nothing. So the fix is to mark only what `capture_is_celled` calls a pointer, and the pair to land together is that marking plus the check at the OTHER end of the same sentence (a capture of storage already moved out views nothing) -- which is unreachable without it and was reverted WITH it, rather than left in the tree as a check that cannot fail. Acceptance: the §S84 program must compile and 5b must not. |
| S88 | **Specialization is the keyword `with`, not adjacency.** **`;` STAYS, and this row is corrected rather than carried:** the first draft claimed `;` was a consequence of juxtaposition and could go, and the test suite was the counterexample within one run -- see the delta column. `f with a with b` is the stable specialization `f a b` was, one argument at a time and left-associated; `f(a, b)` is unchanged. Adjacency could not say where an argument ENDED, and three things were paid for that: the grammar needed `;` to stop the greedy loop (`let y = x; y` needed it because `x y` was an application, and a prelude before a written terminal had to be `let secret = 8;`); a parenthesized expression could not GROUP after a word, because `(` there is the invocation suffix, which is why `sum (square 3) (square 4)` read as `sum` invoked with the argument `square 3` and reported `Undersaturated`; and an accidental application was SILENT. Now a parenthesized expression after `with` is a group and two adjacent expressions are a parse error the diagnostic explains (`application is \`with\``, and `a chain's TERMINAL is separated from the items before it by \`;\``). `;` stays for that second meaning: it separates a prelude from a WRITTEN TERMINAL, both of which are expressions. The three uses of one mechanism keep their shape -- values `f with a`, types `Box with Int`, modules `import with "codec.let" with JPEG with 90` -- and the parser loses `starts_expression`, the predicate §S40 had to teach `{` and `text` and which existed only to answer a question adjacency created. | This is a surface change with a design reason, and the reason is worth separating from the churn it costs: **every program in the suite has to be re-spelled**, which is the honest price of not keeping a compatibility path. It is right anyway because all three payments trace to one thing -- an application with no spelling -- and each is a defect this compiler has already hit: §S40's `starts_expression` (a predicate that must be told about every new literal form or the grammar silently inverts), the `Undersaturated` on a grouped stage, and `;` in the first program anybody writes. §S37 is the same shape from the other side: assignment's lookahead had to run the postfix grammar without consuming, because a one-token lookahead read `r` as a juxtaposition argument of the previous statement. A language whose application is a keyword has none of those questions. |
| S89 | **The test suite is rewritten as PROGRAMS, and it found four defects in its first hour.** The old suite asserted things about the phases -- what the belt looked like after Lower, how many definitions Resolve created -- and 990 of those checks did not notice that nobody could compile a FILE (§S84), that a module's state was rebuilt inside every word (§S85), or that assignment never destroyed what it replaced (§S86). A check is now a PROGRAM: it goes through the real pipeline (`let.compile`, which owns it), through the same `cc` a user would use, it RUNS, and its stdout is compared -- with `refuses`/`lacks` for the programs that must be turned away, so §13's three kinds are tested too. Sixteen checks cover `with` and grouping, invocation equivalence, a prelude between stages, the operators, aggregates, control flow with `continue`, `switch` with labels and `else`, a sum, interior mutability, `Text` and a conversion, an annotation, and an unsaturated invocation. **Four things fell out, three of them fixed here.** (1) A WORD-TYPED value -- a partial application, `sum with 1` -- has a layout: its packet. `belt_type_of`/`field_type_of` say so now, and the module NAMESPACE's member loop called `rep` directly instead of asking them, so binding one was `Bug(NoLowering(form = representation))`. (2) `word_of` could not see through a BINDING, so applying a bound partial application was `NotExecutable` -- and §1.2 makes a partial application a word, so it must. (3) `word_of` could not see through a `move`, which is the same word. | The fourth is a recorded gap and it is why the rewrite was worth doing. **A word value's COPYABILITY has no owner that can answer it**: §2.5 makes a record Copy iff every member is, and §2.2 makes a word's value a record -- but `Semantic.Word(template, prefix)` names a template by NUMBER because `Semantic` sits below `Chain` (§11.4), so it cannot see the members, and the implementation answers "not Copy", which is why the test says `move add_one`. And **that number is not what §11.4 says it is**: the sentence says "its index in `Belt.Program.templates`", `Belt.Program` does declare `templates`, and NOTHING FILLS IT -- what the number is in the implementation is a word's DEFINITION ID, which is what every reader in `Lower` already assumes. Both are the same shape as everything else this session has found: a sentence in the document that the code quietly reads differently, and the only reason it was invisible is that the tests were about the phases rather than about programs. The corpus is two suites and wants three more -- ownership and destruction, modules and captures, and the diagnostics with the CLI's exit codes. |
| S90 | **The bundler is restored from the legacy tree, and it is tested against the thing a user gets.** `luajit bundle.lua` writes `dist/let.lua`: the compiler and everything it requires in one file, so it can be used without the checkout (`luajit dist/let.lua program.let -o program.c`), and requiring it returns the vocabulary table instead of starting a command line. The module set is DISCOVERED -- start at the entry, read the `require` calls, follow them -- because a hand-kept list is a second place that knows what the compiler is made of, and its failure is the worst kind: the bundle keeps building, every test inside the tree keeps passing (the tree is still on `package.path`), and the missing module shows up only where nobody is looking. Two pieces of the legacy version have no work to do here and are gone: the compiler uses nothing but the standard library, so there are no host-specific backends to carry as text, and there is no `let/numeric` to choose between them. | The test is the interesting half, and it is why the bundler belongs in the suite rather than beside it. Every other suite runs the compiler **from the tree**, so a module the bundle forgot is invisible to all of them; `test/bundle.lua` uses ONLY the bundle -- it builds it, compiles a program with it, runs the `cc` the harness would have run, and compares what the program prints (`25`, the grouped-argument program). It also checks the two things the bundle adds to the CLI's contract: §13's exit codes survive the bundling (a `Reject` is 1, a `Missing` is 2), and requiring the file returns the compiler without running a command line -- which is the launcher asking whether the chunk IS the running script, and getting that test wrong turns a library into a program that reads `arg`. |
| S91 | **Stale comments in the CODE -- and in `README.md`, which is the front door.** §S88 changed the application form and `let/parse.lua`'s header still said *"Parsing is greedy... Juxtaposition is greedy too, so `f(x); g(y)` needs the `;` -- the grammar says so, and README says so"*, with the same claim repeated in §S37's assignment-lookahead comment: a reader of the parser was told a rule the parser no longer implements and the language no longer has. Thirteen sites in `let/`, all fixed, and the tests were carrying it too -- `parse.lua` still had the temporary `V.greedy_specialization` hook, scaffolding for a migration that no longer exists because the suite was thrown out and rewritten (§S89), and the tool that used it is deleted with it. **README was the worst of them and it said the opposite of the truth**: *"Juxtaposition supplies stages; parentheses invoke words. **There is no `with` operator.**"*, a `;` rule spelled `f(x); g(y)`, generic types by juxtaposition (`Box Int`), sums spelled `A or B`, a word with no stated result (`let main = do`), a libc namespace, an `examples/` directory and a `bench/` directory that are not in this tree. It is rewritten to describe what the compiler IS. | §S77 established that a stale paragraph is a defect because it makes a rule look settled in a way that is no longer true, and fixed the DOCUMENT by rereading it. **Code comments and the README are worse, and for a reason worth naming: a comment is checked by NOTHING.** `test/spec.lua` reads the document's declarations and its citations; no test reads prose, and the compiler does not either, so the only instrument is rereading -- and the tell is specific: **a comment that describes a mechanism the code no longer contains**. Two of the eleven were kept deliberately, because they are true in the past tense AND they are why a rule exists ("the predicate the old greediness used"; "greedy juxtaposition was never the reason", which is §S88's own correction of its first draft). That is exactly the line §S77 draws for the document -- a citation to the draft must SAY it is the draft -- so the rule for both is one sentence: **a mention of a retired rule must say it is retired, and everything else is a claim about the present that the code has to keep true.** The README section is also where the retired surface was still being TAUGHT, which is worse than a stale aside: it is the first thing a reader meets, and it was instructing them to write programs that no longer parse. |
| S92 | **`import` works, and it took four fixes in one chain -- which is what "a word's value is its packet" costs when a layer cannot see a template.** (1) **`rep` takes the lowerer**, and maps a `Semantic.Word` to `residual_type(L_, template, prefix)`: a word's LAYOUT is its packet (§2.2), `Semantic.Word` names its template by number and `Semantic` sits below `Chain` (§11.4), so the one mapping between meaning and representation is the only layer that can answer -- and with one argument it could not, which made an aggregate CONTAINING a word unmappable and `import` a `Bug(NoLowering(form = representation))`. (2) **The packet's members moved to `Chain.Template:members(k)`**, where the fields are: two phases need the layout for two different questions (`Lower` for what a name's slot holds, `Contract` for what a value's type is). (3) **§2.5's Copy rule for a word value -- its packet -- is derived in BOTH layers**, reaching THROUGH records and sums, because `Semantic.Aggregate:copyable` recurses by asking `Semantic.Word`, which cannot see a template; so an imported namespace, whose only member is an `Int`-staged word, was refused with `NeedsMove` and could not be bound at all. (4) **`word_of` reaches a word through a record PROJECTION**, following names, because §2.6 reaches an imported word as `other.twice` and Resolve makes a definition to hold the file's terminal, so the binding is a name for the aggregate rather than the aggregate. And the bound partial application fell out of (3): `let add_one = sum with 1` then `add_one with 2` is 3 -- it had been `NeedsMove`, and before that `NotExecutable` and a `Bug`. | The shape is one sentence from §2.2 -- *a word's value is its packet* -- meeting §11.4's layering (a word type names its template by NUMBER, because `Semantic` must not reference `Chain`). Every defect here is that sentence arriving somewhere that could not see both halves: `rep` without the lowerer, a copyability rule without the template, a structural walk without the name it had to follow, and `read_place` without `L_`. Two layers now derive §2.5 from the declaration and neither asks the other, which is §S61's shape rather than a second owner -- the same relationship `copyable` and `Belt.Type:equals` already have. Acceptance: `test/language.lua` #14 (a bound partial application) and #15 (`import` + `other.twice with 21` -> `42`). |
| S93 | **A sum is destroyed by its TAG, and the leak is closed.** `destroy_value` had no case for a `Semantic.Sum`: it fell through `if not Semantic.Aggregate:isclassof(type_) then return end` and NOTHING was emitted, so a sum that owned a resource leaked it silently -- visible only to a host counting its own allocations (§S81, §S83). Three pieces, all of them the design's own: **`destroys` says a sum is destructible when ANY alternative is** (the exact mirror of §2.5's `Copy` rule for a sum, "every alternative", and they cannot be one rule because destruction is chosen by the TAG); **`destroy_sum`** builds the chain of tests §3.5 describes -- read the tag at field 0, branch per destructible alternative, destroy `LoadField(value, 1+K)` in the arm that matched, join -- with no new opcode, because the tag and the payloads are at known offsets and the ops are the ones the graph already has; and **the value has to be NAMEABLE**, because §12.3 says a block's parameters are `[Effect] + the values live at the split` and an edge's arguments match them one for one -- the same reason §S34's switch subject is bound, now for a second reason, which is the only way a value that is not a definition crosses a split. **`test/language.lua` #16 is the acceptance test**: a dropped `Int | Handle` prints `made=1 released=1` (it printed `made=1 released=0`), and §S81's "a host counting its own allocations is the only thing that can see it" is exactly the test. | Landing the mechanism *retired two things*, which is the interesting part. `MissingWhy.SumDestruction` is DELETED -- three gaps became two -- because the report existed only to say "destroying a sum needs a destructor chosen by its tag, a mechanism the compiler does not have", and it now has it: a sum nobody takes is destroyed at its scope exit like anything else. And Contract's whole switch rule went with it (§S65/S87): what a path leaves alive is no longer Contract's business, because the destruction handles it. **What remains is one conservatism, and it is honest rather than stale**: a MIXED switch -- one arm taking the payload, another copying it -- is still `OwnershipDiverges` from `Lower`'s `agree`, because the arms genuinely leave the subject in two states. It is harmless in this program (destruction dispatches, so both states are correct at a scope exit) but NOT in general: a `move v` after the join would be legal on the copying path and `UninitializedPlace` on the taking one, so the compiler cannot accept it without knowing whether anything uses the join -- and that is liveness, which §3.3 refuses to compute ("no fixpoint, no dynamic boolean fact"). So a sum's divergence is refused conservatively, and the price is a program the design would allow if it could see that nothing reads the subject afterwards. |
| S94 | **Floats are writable, which is the S41 class again: declared in every layer, produced by none.** §11.2, §11.3 and §11.7 all declare a `Float` (and a `Float32`), `rep` maps both, `C.F64`/`C.F32` render both -- and the LEXER had no float token, so no program could name a value of either type. Four seams had to be filled, and two of them were *not* where the vocabulary is: `Syntax.Float` was referenced NOWHERE in the compiler, and the derived type is asked in TWO places -- `Contract.type_of` and `Lower`'s literal branch both answer "what type does this literal have" (§S61's shape: each derives it from the same form and neither asks the other) -- so adding the case to one of them produced `Bug(NoLowering(form = literal))` from the other. The value has one owner, `Semantic.float_value`, beside `integer_value` (§S38), and the literal prints through `C.Float`, which uses `%a` -- a hex float -- so a value cannot be rounded by its own spelling. `test/language.lua` #17 is the acceptance test: `half with 5.0` prints `2.5`. | Two things about the rule are worth stating because they are CHOICES rather than oversights. A float literal needs a LEADING DIGIT: `.` is the postfix projection, so `.5` is not a literal, and requiring the digit is what keeps `a.b` unambiguous. And there is no float ARITHMETIC, because §1.5 says every operator but comparison and truth is `Int -> Int` -- so `1.5 + 2.5` is a `MismatchedType` rather than an operation, and a float reaches a program through a literal, a host word, or a conversion, which is the same shape `Text` has (§3.6: the core has no view type and the host owns what it owns). |
| S95 | **A member's value is a chain, so `MemberPrelude` was never a gap -- the member path resolved the TERMINAL and refused anything before it.** §3.1 says "a record type and a value aggregate are the same form", and `resolve_value` is the machinery that resolves a chain: items, stages, terminal. So a member with a prelude, or with STAGES -- which makes the member a WORD -- is not a special case at all: it is a binding whose value is a chain, the same thing a file's prelude is. Both sites (`NamedAggregate`'s members and `PositionalAggregate`'s elements) now call `resolve_value` and declare the result, and a positional element needs no name because §11.6's `Member(string? name, ...)` says a positional member has none. **`MissingWhy.MemberPrelude` is deleted: the inventory is ONE entry, `TwoRuntimeIndices`.** | The lesson is one §S72 named and this increment keeps re-learning: a `Missing` is a claim that the compiler lacks a MECHANISM, and this one was a claim that a path did not exist -- while the path did, one function away, already used by every chain in the language. What made it look like a mechanism is that the member path had its own resolution of a member's value (`resolve_initializer` on the chain's terminal) instead of asking `resolve_value` for the chain. **So the fix is a deletion, not an addition**: two special cases and their diagnostic removed, and the same six lines now serve a member, an element, a file prelude and a word. Acceptance: `test/language.lua` #18 and #19, the pair the inventory claimed to need. And it is worth recording that the FIRST attempt at the positional test was `{ { let b = 2; b }, 3 }`, which compiled to `MismatchedType` -- correctly, because inside braces a leading `let` begins a NAMED aggregate (§S27), so that element is a nested record and not a chain. The reachable positional form is the one where the named parse FAILS: `{ let a = 2; a, 3 }`. |
| S96 | **`TwoRuntimeIndices` is DERIVED, and the inventory is down to the STORE half.** §12.1's row -- "is this step a constant or a runtime index?" -- is now a derivation: `Resolve` builds `Judge.Index` for a constant offset and `Judge.Element` for an expression; `Contract` says the member's type is the one type every member shares, or `MismatchedType` (the same question §3.5 asks of a sum's alternatives, asked of a record's members); and `Lower`'s `lower_element` builds a DISPATCH -- one test per member, each arm reading the constant offset it is about -- with no new opcode, exactly like §3.5's destructor dispatch on a tag. **The value crosses the join in a CELL, and that is the design's answer rather than a workaround:** §S35 says the value phi appears in exactly one place (`and`/`or`), and §11.7 says why a cell is the alternative -- "a cell is a belt value whose identity is fixed before any control flow can reach it, so it crosses a join unchanged and only its contents differ per path -- and contents are memory, not an SSA name". Arm 0 stores nothing, because the cell is initialised with member 0, and an index that names no member TRAPS, which is §1.5's rule for what C leaves undefined (`/` by zero) rather than a new one. `test/language.lua` #20 reads `{10, 20, 30}` at 0 and at 2 and prints `10 30`. | Three things fell out, and two are the defect classes this session keeps meeting. (1) **`Judge.Place` is DELETED -- it was produced NOWHERE**, the same class as `Syntax.Float` and `Belt.SelectStore`: a sum declared in the ASDL and by no phase, whose name collided with the one this increment needed (a module's constructors share one namespace). The §12.3 table row that named it now points at what actually answers the question, `lower_place`. (2) **The inventory's entry is RENAMED to what is left**: `TwoRuntimeIndices` meant "a step that is a runtime index", and a runtime index as a VALUE works now -- what remains is a runtime index as a DESTINATION (`a[i] = v`), which `lower_place` reports as `Missing(RuntimeIndexStore)`. A name covering two things after one of them is done is the same defect as a name with two meanings. (3) **`Known`'s fate rule was inlining a compound constant at EVERY use**: `Immediate` was given to any known value, so the tuple in the dispatch was spelled once per test, per arm and per edge -- seven copies here, and N^2 for a tuple of N members. A scalar is `Immediate`; a `Bundle` is written once and named. |
| S97 | **A runtime index as a DESTINATION, and the dispatch now has ONE owner.** `lower_element_store` is the same dispatch as the read -- a `StoreField` per arm instead of a `LoadField` -- and it is answered BEFORE `lower_place`, because it is the one destination that is not a place: a place is one address, and the index decides WHICH address at run time. Adding the third user is what made the shape visible, so the three are now one function, `dispatch(L_, C, count, subject, reason, build_arm)`, which §3.5's destructor, §12.1's read and §12.1's write all call: a value known only at run time chooses among N alternatives by comparison, and a value that names none TRAPS. `a[i] = 9` on `{1, 2, 3}` gives `14` at i=0 and `12` at i=2 (`test/language.lua` #21), and the C is a chain of tests with a store in each arm. | **The inventory is now `MissingWhy.ModuleState`, and that is a finding rather than a leftover.** With the store landed there was no gap left to name -- and an ASDL sum needs an alternative -- so the question became "is the inventory EMPTY, or was something never in it?", and §S80 had already answered it: for a WRITTEN terminal the module owns the terminal's value, "the returned value must own what the namespace does not reach", and the `state` member with its `unload` is the mechanism. Nothing reported it, so such a module **leaked its resource at unload in silence** -- the same class as §S83's sum leak, and found the same way: by looking for what has no name. The report is where it applies, a written terminal whose result is destructible; a terminal that owns nothing needs neither the member nor the unload. That is also the shape of the whole increment: §12.1's runtime index is DERIVED (a constant is an offset, a runtime value is a dispatch, a destination is a dispatch of stores), and what replaced it in the inventory is the thing that was silently missing all along. |
| S98 | **A written terminal's module OWNS its value, and `unload` destroys it -- §2.6's other half.** `unload` was generated only for the IMPLICIT namespace (§S80), so a written terminal holding a resource **leaked it at unload in silence**: §2.6 says "the returned value must own what the namespace does not reach", and nothing owned it. The unloader now destroys the module VALUE when the terminal is written -- the root is synthetic, because destruction is the one place that asks a PLACE for its state and this value is a parameter rather than a binding -- `Lower.run`'s "does the module own something" asks about the terminal's value as well as the namespace's members, and the resource is released exactly once (`test/language.lua` #22: `made=1 released=1`). | Two things had to be got right, and both are the trap §S89 named: **a word's interface result is not what its value holds.** (1) **"What the namespace does not reach" is §2.6's own phrase and it is a COMPUTATION**: the terminal's value reaches a definition when it names it -- *including through the declarations it names*, because `{ let x = move h }` reaches `h` -- so the members it reaches are owned by the terminal and the rest are the module's. (2) **A WORD member was counted as a resource**, because `destroys(interface.result)` sees a word's interface result, which is what its `run` RETURNS: `made` looked like a `Handle` and was reported "left over". A word owns what its PACKET owns, so the test is over `word:members(0)` -- the same correction as §S89 and §S92, arriving a third time from a different direction, which is the argument for answering that question in ONE place instead of wherever it is asked. **`MissingWhy.ModuleState` is now precisely the `state` member**: a top-level binding the terminal does not reach would have to be carried in the module value, which makes it a PAIR rather than the terminal's value -- and that is the one mechanism this phase still does not build. |
| S99 | **Three defects, one of them a Bug that named the wrong layer, and two of them one mechanism.** `let Pair = let T : Int { let a : Int let b : Int }` was `internal: NoLowering(form = initializer)` -- which *reads* like a message from `Lower` and is not: it is the rendering `<kind>(<field> = <value>)` of `BugWhy.NoLowering(string form)`, so the value is the string `initializer` and the producer is **Resolve**. Four things were behind it, all fixed. (1) **`resolve_initializer` had no branch for `Syntax.Word`**: braces around STAGES are a word, "a word literal is a value" (§1.4/§3.1), and the parser builds it on purpose as a record constructor -- so a shape the grammar accepts fell through to an internal error. It now resolves to a definition holding the word, with a GENERATED name, because a word's name reaches `let_<name>_run` and two anonymous words would be one C function defined twice. (2) **A name that denotes a word may be used as a TYPE**: the type position asked `type_of_name`, which knows primitives and host types, so `let f : square` was `UnknownType`. The rule is the one `Int` already follows -- a name in type position denotes the type of the value it denotes -- and the walk follows a CAPTURE, because a capture is a second name for the same storage and stopping there would invent a second, unequal nominal type. (3) **`Semantic.Word` had no `equals`**: `S.Type:equals` is identity (right for a scalar and for an interned `Named`) and each structural type overrides it, so `let f : square = square` compared two equal-valued `Word(1, 0)`s, called them different types, and refused a program whose annotation and value disagreed about nothing. (4) **A word whose terminal is a word yields one when it SATURATES** -- and this one was a Lua CRASH: `word_of` walked the DECLARATION and returned `Pair` one prefix further along, a stage that does not exist, while `Contract` read the callee off the TYPE and accepted the program. The walk now reads the declared RESULT, and the application path reports `Oversaturated` rather than indexing. | Two of the three defects are ONE MECHANISM, and it is the one the slogan is about: **the callee of an application is a fact about the TYPE, and `Lower` was deriving it structurally.** A stage whose declared type is a word names that word, so `g(x)` HAS a callee -- "words are monomorphic; polymorphism is words" is exactly this, and no vtable is needed because the nominal type carries the template. `word_of` had no branch for a `Bound` and `base_of` built a packet from source instead of handing over the one the caller passed, so `let apply = let g : square ... return g(x) end` was `NotExecutable` about a call the design says is selected at the call site; both are fixed and it RUNS (`9`). What remains is the shape that names NOTHING: an ARROW-typed stage, since `Int -> Int` is a shape and there is no callee in it -- recorded as honest rather than broken, and the reason is visible in the inventory: **`Semantic.Arrow` is produced by the type position and consumed by nothing.** Six programs pin all of it (`test/language.lua` #23-#28, ten checks), one of them verified by mutation (`Word:equals` back to identity breaks #25). The register of the day: **a Bug's own text can point at the wrong layer**, and a count of programs that "all pass" is worth nothing if the loop reads `$?` after a `$(...)` -- both of this session's wrong turns were measurements, not code. |
| S100 | **The tag is a semantic fact, and the belt cannot carry it -- reported as a C type error at a borrowed stage and as a WRONG ANSWER everywhere else.** `let twice = let f : square | inc ...` with `case square as g ... case inc as g ...` was accepted, then emitted C that did not compile, and once the missing injection was added it printed the SQUARE arm's answer for `inc`: `Belt.Sum:alternative` compared REPRESENTATIONS, and two word values with empty packets are both the unit byte (an empty record IS `uint8_t`), so it matched the last alternative and every label got tag 1. Three fixes, one sentence: **which alternative a value inhabits is a question about MEANING, not about layout.** (1) **The injection is decided semantically.** A word value's identity is nominal in `(template, prefix)` and `Lower` derives it from the DECLARATION (`word_of`, the same answer that selects a callee -- §S99), so `Semantic.Word(t, k)` is matched against the SEMANTIC sum; every other type's equality is mirrored by the belt (§S49), so the representation is asked only after the declaration. When neither can say, that is a disagreement with `Contract` -- which accepted the program, so it decided an alternative -- and it is now a `Bug` rather than a silently skipped injection. (2) **A borrowed stage injects too.** `Read`/`Mut` lowered the argument to the value itself, which is right for ownership and wrong for the callee, whose stage has the SUM's type -- the tag is part of what it reads. (3) **The label carries WHICH alternative it is.** §S60 already says a label "says which"; what was missing is that `Contract` is the phase that can say it -- it holds the SUBJECT's type -- so `Judge.Label.Shape` grew an `alternative` field that the label check fills in and `Lower` READS, for the test and for the arm's binder alike. One more defect fell out of probing the shape rather than the report: `belt_type_of` followed "a Value whose value is a Reference" as if it were a CAPTURE, which also matches an ordinary binding holding a word value, so `let chosen : square | inc = inc` was typed as the PACKET and the sum was never built; `L_.capture_of_binder` is the real question and it is answered before anything is lowered. | The trade-off the report asks about is the intended one, and this session is the argument for it: a stage whose type is a **word** names its callee, so `g(x)` is instantiated with no tag and no dispatch (`f : square` -- §S99); a stage whose type is a **sum** says the choice is a runtime value, so the tag is the honest representation and `switch` is the only thing that can select -- which is §S2's "a runtime tag is a sum plus `switch`", and the reason a `switch` over two words is not a failure to specialize but the spelling of a decision that is genuinely made at run time. What was NOT intended is that the two paths disagreed about the tag, and the shape of the fix is why that happened: `Semantic` and `Belt` are separate vocabularies by design (§10), so every question whose answer lives on the semantic side must be answered there and CARRIED -- `rep` is a function, not an isomorphism. Acceptance: `test/language.lua` #29-#31 (`86`, `10`, `5`), one of them verified by mutation (restoring the belt derivation breaks #29). |
| S101 | **A partial application is a type, and the walk that says so has ONE owner.** `let add2 = add with 2` then `let f : add2 | mul3 ...` was `UnknownType`: §S3 makes `add2`'s type nominal in `(template, prefix)` -- `Word(add, 1)`, which `Contract` already computes -- but the type position is resolved by `Resolve`, which runs BEFORE `Contract`, so the type cannot be asked for; it is derived from the DECLARATION. The walk that did that knew a word's own name and a plain alias and stopped at an `Apply`, so `f : add2` was refused while `add2 with 3` lowered -- one question with two answers. The fix is not a second walk with one more case: `word_of` moved into `Judge` as `J.word_of(lookup, initializer)`, and BOTH layers ask it -- `Resolve` for a name in type position and `Lower` to select a callee -- with `lookup` because the two keep the declaration table in different shapes (Resolve's `by_id` holds the definition; `Lookup`/`Lower` hold the declaration). The move also folded two cases away: a CAPTURE's binder declaration is a `Value` holding a `Reference`, so the general value-following branch already answers it, and the saturation case now reads the word's own TERMINAL (`word_of` of a data terminal's value, or a `do`/host terminal's declared result) instead of `L_.types[template].result`, so the walk no longer needs a type at all. Acceptance: `test/language.lua` #32 -- `apply(add2, 5) + apply(mul3, 5)` is `22`, which is §S100's collision in its strongest form: `add2` and `mul3` hold packets of the SAME shape `{a: Int}`, so the sum's alternatives have one representation between them and only a semantic tag and a carried label survive. | The decision the report asks for is that a partial application IS a type, and the argument is the rule rather than the convenience: *a name in type position denotes the type of the value it denotes* is one rule, and it already gives the right answer for `Int` (a type word, so the type it NAMES), for `square` (§S99) and for `add2` -- refusing the last would be a special case with no sentence behind it, and "only a word's own name is a type" is not a rule the design has. What makes the answer *derivable* is that the value's type is a fact about the DECLARATION: the template is named by the definition and the prefix is the number of stages already bound, so a walk over declarations answers it before any type exists -- and the moment that walk exists it has two callers, which is why it lives in the vocabulary rather than in either phase. |
| S102 | **Writing a reference found three defects in the door, and the reference is now CHECKED.** `LANGUAGE_REFERENCE.md` is the language a reader can write, and `test/reference.lua` extracts every fenced `let` block and compiles it (a fence says what it claims: a file that must compile, a `refuse: Reason`, a `missing: Reason`), which is the same discipline the language suite follows -- a check is a PROGRAM -- applied to the document that describes the programs. It earned its keep on the first run, catching an example of this author's own that mixed the named and positional aggregate forms the same page says cannot mix. Three defects fell out while checking the claims, and NONE of them was visible from the suite, because no test had a typo, a missing import, or an arrow-typed stage. (1) **A syntax error exited 2.** The lexer and the parser signal one by RAISING -- a malformed token stream has no judgment to return -- and it escaped to the launcher, which says "the compiler is broken": exactly the confusion §13's three kinds exist to prevent. `compile.run` now catches it and returns `Reject(Syntax(detail))`, so a typo exits 1 with `file:line:column`; the span is the unit's start because the position is in the detail, and the CLI prints the detail alone. (2) **A missing import reported NOTHING.** `resolve_import` called `V.load`, got `(nil, Reject(MissingModule))` and returned nil WITHOUT the diagnostic -- so the door reported "the compiler stopped without a diagnostic" and exited 2 for a program that named a file which is not there. A dropped diagnostic is the worst kind of defect: it is silent. (3) **An arrow- or `do`-typed STAGE crashed the compiler.** A stage is a value the caller supplies, so its type must be one a value can have; an arrow and a `do` are SHAPES (§11.1/§S3) whose `rep` is nil, and the nil reached `Belt.Parameter` -- so the same program crashed in the entry point and was a `Bug` in the packet. `Contract` now refuses both where the DECLARATION is, with `NotExecutable`, which is the same refusal invoking such a stage already got (§S99). | The pattern is the point. **A suite is checked by someone's imagination and a document is checked by the language's claims**, so the act of writing down what you believe finds the places where you believe something the compiler does not do -- and the fix for *that* is to make the document executable rather than to trust the prose. Two of the three defects were exit codes and a silent drop: nothing a program's OUTPUT would ever show, and nothing a reader of the source would notice, which is why they survived 149 checks. What the reference does NOT claim is also now explicit: a stage's type cannot be a shape; `ToText` does not exist; there is no float arithmetic; type-level words (`Box with Int`) are described in §11.2 and NOT expressible -- a recorded divergence rather than an oversight; and a written terminal that leaves a top-level binding behind is `Missing(ModuleState)`. |
| S103 | **The committed artifact was checked by nothing, and a stale one was handed to a reader.** A reader compiled `LANGUAGE_REFERENCE.md`'s `let` blocks against the uploaded `dist/let.lua`: 37 of 40 passed, and the three failures were exactly the three defects §S102 had just fixed -- an arrow-typed stage crashing, a missing import reporting nothing, a syntax error exiting 2. In the tree the bundle is CURRENT (all three now behave: `NotExecutable`, `MissingModule`, the parser's message, each exit 1), so the defect was never the bundle: it was the CLAIM that it is current. `test/bundle.lua` BUILDS the bundle and tests the build, which by construction cannot see a stale file -- a rebuild that never happened is invisible to a suite that always rebuilds. It now also builds to a second path and requires **byte equality** with `dist/let.lua`, which is safe because the bundler is deterministic (it discovers the modules by following `require` from the entry, and the output carries no timestamp); the failure message names the fix. Verified by mutation: one appended byte fails it, and restoring the file passes. | (1) **An artifact is a fact, not a by-product.** `dist/let.lua` is the file a user runs, and the only thing that could previously tell whether it was current was a person remembering to rebuild -- the same shape as §S102's finding that a document is checked by nothing, one level down, and the same reason: a check that cannot fail is worse than no check. (2) **The reader's method was right and mine was not.** They did what `test/reference.lua` does -- extract every block, compile it -- but against the ARTIFACT rather than the tree, which is precisely the axis the suite did not cover: a suite is a claim about the compiler, and *against what* it is run is a second question that a suite cannot ask about itself. (3) The §12 bullet the reader could not parse was mine and is also fixed: it stated a restriction that does NOT exist (probed -- a word-typed stage takes a word whose packet holds a capture, borrowed or owned, and moving one is accepted), so the bullet is DELETED rather than reworded, and the fact it was groping for is now stated in `LANGUAGE_REFERENCE.md`'s type section with two checked examples: a word's own name is a type for the WORD, not for what the word builds, so `take_pair(Pair, n)` compiles and passing the constructed record is `MismatchedType`. |
| S104 | **"Names are types" has a boundary, and it is the layering rather than a choice.** A reader asked why `let origin = Point with 0 with 0` then `p : origin` is `UnknownType` while `p : Point` works. Measured: the type position answers from the DECLARATION (it is resolved before `Contract` runs), so it answers for a word -- nominal in `(template, prefix)`, including a PARTIAL application (§S101) -- and it answers for a type WORD, and it CANNOT answer for a datum, whose type is what the checker computes. That is not a restriction anyone imposed: it is the phase order, and the workaround (write the record type out) is what the reader had already done. Probing the neighbouring case found the REAL gap, and it is the one the reference already records as unimplemented: `let P = Int` *parses*, and binding `P` ends in `Bug(NoLowering(representation))` -- because §2.4 says a type word is "evaluated at construction time and ERASED", `rep` has no answer for `TypeWord` (correctly: a type word is not a layout), and nothing erases it. Type words and their erasure are ONE missing mechanism, and a type word is exactly what would let a name denote a *type* rather than a value. An attempt to close it (a type-position walk for type words plus a `Missing(TypeWordValue)` where a type word is materialized) was implemented, measured, and REVERTED: the walk worked but the Bug comes from the place path, so `let P = Int` went from the reader's `UnknownType` to an internal error -- a half-landed mechanism is worse than a named gap, and the reference now states both edges instead. | Two things worth keeping. (1) **A rule stated as one sentence had a boundary the sentence hid**: "a name in type position denotes the type of the value it denotes" reads as *any* value, and the reference's type section now says which values it can answer for and WHY (the declaration, before the checker) -- the fix for an over-broad sentence is the sentence, not the mechanism. (2) **The artifact check paid for itself within the hour**: the reader's report was a stale bundle, §S103 pinned the committed file to the sources, and this session's own un-rebuilt bundle was caught by it twice while these reverts were being measured. A check is worth most on the axis nobody thinks to test. |
| S105 | **"Names as types" ended with one half landed as a NAME and the other as a NAME FOR THE GAP.** A reader asked why `let origin = Point with 0 with 0` then `p : origin` is `UnknownType` while `p : Point` works, and whether the same idea could be taken one step further. It splits in two. (1) **The data case is the layering, permanently**: the type position answers from the DECLARATION because it is resolved before `Contract` runs, so a word (including a partial application) and a type word answer, and the type of a DATUM does not -- the workaround is to write the record type out, and the reference now says why. (2) **The type-word case is a GAP, and it is now NAMED rather than internal.** `let P = Int` -- a name for a *type* -- used to end in `Bug(NoLowering(representation))`: exit 2, "internal", the compiler blaming itself for a program the grammar accepts (§S99's lesson). It is now `Missing(TypeWordValue)`, a second entry in the gap inventory with a producer in `Lower` and a `missing:` example in the reference that CHECKS it. The erasure §2.4 describes is still not landed, and the reason is measured: `rep` has no answer for `TypeWord` (correctly -- a type word is not a layout), a word that CAPTURES such a binding still lists it, so `residual_type` returns nil and the emitter indexes a nil field (`emit.lua:31`, `field_name`). The erasure is one rule that must hold in FOUR places -- the namespace, the packet, `construct`, `unpack` -- or none, which is the "one rule written in several places" class this design keeps meeting. So: renamed, not landed, with the edge written down. | Three lessons, all mine. (1) **An edit must INSERT, not restructure.** Wrapping the namespace loop's body in an `else` produced an `elseif` after `end` and a module that would not load, and finding that took far longer than the feature would have; the version that works inserts four lines and changes nothing else. (2) **The bundler does not load what it bundles** -- it wrote a `dist/let.lua` containing the broken `lower.lua`, and `test/bundle.lua` caught it within one run, which is the argument FOR the artifact check rather than against the bundler. (3) **A fence with no user is a check that cannot fail**: the reference's `missing:` tags had none until now, and using one restored the per-reason inventory check that the deleted `test/gaps.lua` used to provide. |
| S106 | **A type is ERASED, so there is no `typeof` -- and each thing `typeof` is for already has a sentence.** The decision, taken with the reader who asked for it: (1) implement §2.4's type words, with `let P : Type = <a type>` as the surface for a NAME FOR A TYPE, and `Box with Int` as the same application as any other; (2) `Type` is not new vocabulary -- a type value's type is already `Semantic.TypeWord`, so it is a name for an existing choice; (3) a type word stays ERASED, so a runtime type is refused, and §11.2's sentence "`TypeExpr` has no `Apply` alternative" is RETIRED because §2.4 makes application the mechanism and the two cannot both be true. The alternatives, one per use: a runtime CHOICE is a sum plus `switch` (§S2, and §S93/§S100 made the tag exact); behaviour that VARIES is a continuation word bound at specialization (§S2's own sentence -- pass the word, not the type); generic code is a `Type` domain applied with `with`, which MONOMORPHIZES, so `Box with Int` and `Box with Text` are two words and need no descriptor; printing, serialization and FFI are the HOST's vocabulary (§3.6) or a word per type ("polymorphism is words"). | The reason to refuse runtime types is the reason `: Type` is cheap: erasure is what makes a type word vanish at construction time, so giving one runtime values makes erasure CONDITIONAL -- every instantiation pays for a descriptor whether it uses one or not, and two instantiations can no longer be separate words. The reader's instinct was right and only the TENSE was wrong: "a word that at runtime can give you its values" IS a word that at CONSTRUCTION time gives you its values -- a type word applied to a type yields a type, and a CONSTRUCTOR word (a `Type` domain with a *value* terminal) yields a value -- which is why a type and its constructor are two words, and why no runtime type is needed to tell them apart. That also settles the surface's one ambiguity: a chain with a `Type` domain is a TYPE word (its terminal is a type, and it is erased), and without one braces are a value aggregate -- so `let Pair = { let a : Int let b : Int }` stays a constructor (§S99) while `let Box = let T : Type { a : T }` is a type. |
| S107 | **§2.4's erasure landed as ONE question, and it took two more answers out of the code.** `let P = Int` then `x : P` compiles and RUNS (`twice with 21` is `42`): a name for a bare type word is a name for a type, `P` never becomes a value, and `Missing(TypeWordValue)` is GONE from the inventory -- it named a gap, and the mechanism is here. Two rules had been written in more than one place, and both were found by MEASURING rather than by reading. (1) **"Is this definition erased?" is one question** -- a definition whose interface result is `TypeWord` -- so it is one function (`erased`), and the three BUILDERS ask it: a chain item's prelude is not a group member (and so not a packet member), a definition with no scope is not a namespace member, and a local that names a type is not initialized. `materialize` keeps the question as a `Bug` backstop, because an erased definition arriving there is now the compiler disagreeing with itself -- the one shape that is a `Bug`. (2) **The ENTRY POINT re-derived "which definitions are members"** -- counting `Judge.Value`/`Judge.Word` in `L_.definitions` -- while `lower_module` built the record from its own list, so the two disagreed the moment one of them learned the erasure: the index counted `P`, the struct did not have it, and the host loaded a field PAST THE END (`emit.lua:31`, `field_name`). The index now asks `L_.namespace_members`, the list the record was built from. | The pair is this session's thesis in miniature: **a rule that must hold in several places will be forgotten in one of them**, and the fix is to make the QUESTION single rather than to repeat the answer. It also shows where a second copy comes from -- the entry point's scan carried a comment saying it was "the same order `lower_module` builds the record in", true when written and false once the erasure changed one side, and a comment is checked by nothing (§S91). Acceptance: `test/language.lua` #33 (it RUNS, `42`), and the reference's block in its type section, which was a `missing: TypeWordValue` example until this landed -- the suite failed the moment it stopped being reported, which is the mechanism working. Also cleared: two stray duplicated lines my own edits had left in `README.md` and the reference (the recurring slip -- an edit that replaces a paragraph's head and leaves its tail). |
| S108 | **Steps 2 and 3 landed: `: Type`, `Type` domains, and type application -- all of it in the TYPE language, so no runtime machinery and one filter of Lower work.** `let Point : Type = { x : Int, y : Int }` names a record type (`p : Point` works, and the binding is erased by §S107); `let Box = let T : Type { a : T }` is a type word and `Box with Int` is a type. The mechanism is §2.4 read literally: a chain with a `Type` domain is a TYPE word, "evaluated at construction time and erased" -- so its body is kept UNRESOLVED (in `type_bodies`, `Resolve`'s own map) and resolved PER APPLICATION, with `type_env` binding the stage names to the argument types. The application therefore happens in `Resolve`, in the type language, and never reaches the belt: `Box with Int` IS `{ a: Int }` by the time `Contract` sees it -- which is why this needed no new judge vocabulary (`Judge.Word(template, nil)` is what a host word already is -- a word with no runtime terminal), no belt type, and no Lower work beyond one filter: a type word gets no ENTRY POINT, because the host calls words and a type is not one. Four small pieces: `Type` as a NAME for the existing `TypeWord` choice (§11.1), `Syntax.TypeValue` and `Syntax.TypeApply` (§11.2's retired sentence made concrete -- a type expression HAS an application form), and the parser's two rules (a `: Type` binding's value is a type; a chain whose item is a `Type` domain has a type terminal). | Two things worth keeping. (1) **The design's sentence did the work** -- "the same operations, evaluated at construction time and erased" needed no new vocabulary once the erasure existed (§S107): a type word is `Judge.Word(template, nil)`, a type VALUE is a `Judge.Type`, and the application is a type-level computation in Resolve. The alternative I nearly took (deferring the type position to `Contract`) would have inverted the phases for the same result. (2) **The ASDL caught the shortcut**: the first cut reused `Syntax.Specialize` (an `Expr`) for a type application and `asdl.lua` refused it at the next parse -- `expected 'Syntax.TypeExpr' but found Class(Syntax.Specialize)` -- which enforces the retired-sentence rule mechanically: §11.2 said a type expression has an application form, so it now HAS one, as its own alternative. Acceptance: `test/language.lua` #34 (a named record type, `3`) and #35 (a type word applied with `with`, `1`), both RUN. Documented rather than half-built: an unapplied or partially applied type word is not a type (`p : Box` is a `MismatchedType`), because `Box` there denotes the nominal word type of §3.2 and not what it builds. |
| S109 | **A parenthesised TYPE is a group, and generic words are scoped.** (1) **The bug.** `let c : Box with (Box with Int)` was a `MismatchedType` while both the aliased and the structural spelling worked: `parse_type_atom`'s `(` built a `Syntax.Tuple` for ANY parenthesised type, so `(Box with Int)` was a record with one UNNAMED field -- a different type, spelled with brackets nobody writes brackets for. Expressions have treated `( … )` as a group since §S88, so the type grammar does now too: one element and no comma is the element itself, and a one-element TUPLE has no spelling (which matches a one-element aggregate in the expression grammar, where the braces are what make it one). (2) **Generic words, scoped rather than started.** `let id = let T : Type let x : T do : T return x end` is refused today because S106's rule -- "a chain with a `Type` domain is a TYPE word" -- is too strong: it forces the terminal to be a type. The rule becomes: a `Type` domain with a TYPE terminal is a type word, and with a `do`/value terminal it is a GENERIC word. Four pieces are needed and they are now known: (a) a `Semantic.Variable(stage)` alternative, because a VALUE word's stages are resolved ONCE at declaration -- the trick that let type words dodge variables (resolve the body per application) does not exist here; (b) the parser rule above, where `{ let a = 1 }` and `{ a : Int }` are already distinguishable by the `let`; (c) substitution at the APPLICATION, which is what monomorphization is -- `id with Int` binds `T := Int` and the remaining stage types are the declaration's under that substitution, so the instance is keyed by the type arguments; (d) the CHAIN-side erasure §S107 deferred -- a `Type` stage is not a packet member (`Chain.Template:members(k)`), which is what keeps the emitted arity honest. | The reader's own example says why (c) matters: `let F : Type let f : F` gives each WORD TYPE its own instance of `twice`, which closes the gap left after §S100 -- `twice(square, x) + twice(inc, x)` needed a shared body and a tag, and a generic word needs neither, because the nominal type names the callee (§S99). One surface question is the reader's to settle before (c) is written: whether a `Type` stage's argument may be a name read AS A TYPE (`twice with square` meaning `F := Word(square,0)`), which is exactly what the `: Type` binding rule does for a value -- and which is the difference between writing `f : F` and writing `f : square`. Acceptance for (1): `test/language.lua` #36, which RUNS (`c.value.value` is `1`). |
| S110 | **Generics are the `: Type` route, and the ONE surface question is answered by the readings themselves.** Decision taken with the reader: keep §2.4's mechanism -- a `Type` domain is a stage, and the chain is instantiated per type -- because "no generics" would mean IMPOSING a limit (a `Type` domain allowed on a chain whose terminal is a type and forbidden on one whose terminal is a body), which is the shape the design says to remove rather than build around. The argument for needing them here is internal: a word's LAYOUT is part of its type (its value is its packet, §2.2) and types are NOMINAL (§S3), so a container's packet depends on `T` and "a container" cannot be one word -- the choice is a `Type` stage (write it once) or a word per `T` (write it N times), and nothing else changes. (1) **The surface: the argument of a `Type` stage is read as a TYPE**, exactly as the value of a `: Type` binding is -- and this is not context-sensitivity, because the two readings COINCIDE for the case that matters: for a word name, `square` as a value has type `Word(square,0)` (§S3) and `square` in a type position denotes `Word(square,0)` (§S99), so both give the same instance; and for a primitive only the type reading is right at all (`Int`'s value type is `TypeWord`, while the type it NAMES is `Int`). So `twice with square` and `id with Int` are one rule, not two. (2) **An instance is a COPY with substitution**, and that is the piece the next step is: re-resolving the word's SYNTAX is impossible (the lexical scope it was declared in is gone by the time an application is seen), but substituting the ALREADY-RESOLVED subtree is not -- one walk over `Semantic.Type` replacing `Variable(stage)` with the argument type, applied to the places a type lives (a `Bound`'s declared type, a `Value`'s annotation, a template's stage types and result) plus a copy of the body's definitions with new ids. The instance's `Type` stages are then DROPPED -- §S109's Chain-side erasure -- which is what keeps the emitted arity honest. | Three things worth keeping. (1) **The three polymorphism mechanisms are now a closed story**, and each is named by a sentence: a static choice is a monomorphized instance (no tag, no dispatch); a runtime choice is a sum plus `switch` (§S100); varying behaviour is a word bound at specialization (§S2). (2) **Constraints are stages**: a generic word that needs an operation takes the WORD that does it ("polymorphism is words"), and because a word's type is nominal the callee is selected at the instantiation -- zero-cost dictionary passing, with no dictionary. Where the dictionary must genuinely be dynamic, it is a sum of word types plus `switch`, which is §S100 again. (3) **The limit to state in the reference**: generics are monomorphization ONLY -- there is no runtime genericity, no erased container, no `typeof` -- because there is no runtime type (§S106). Where the type is known only at run time, the DATA must say what it is: a sum. That is not a shortfall; it is the same sentence that makes a type parameter free. **Nothing is landed for generics yet, deliberately**: (a)+(b) alone would make a generic word DECLARABLE and still unusable -- a declaration you cannot use is not a feature -- so the first landing must be (a)+(b)+(c)+(d) together, with the reader's `twice` (`let F : Type` + `f : F`, one instance per word type, no tag) as the acceptance test. |
| S111 | **Generic words landed -- and the mechanism was RE-RESOLUTION, not copying.** `let twice = let F : Type let f : F let x : Int do : Int return f(f(x)) end` then `twice with square with square with 3` is `81` and `twice with inc with inc with 3` is `5`: ONE word in the source, TWO instances in the output, each with its own callee, no tag and no dispatch. That is the static half of §S100's trade arriving, and it closes the gap §S100 left. Four pieces, and the third is the one S110 got wrong: `Semantic.Variable(stage)` (a type parameter's identity is its stage, so it needs `equals` for the same reason `Word` did -- §S99's class), the parser's rule (a `Type` domain with a BODY terminal is a generic word; with a type terminal it is a type word, so `do` decides -- and a `Type` stage must come FIRST, which is a grammar rule because an instance drops it), **the instance**, and the erasure. The instance is NOT a copy of the resolved tree with the variables substituted (S110's design): it is the stored SYNTAX resolved AGAIN with the parameter bound, because that is exact by construction -- every nested binding, capture and annotation comes out of the same code that made the original, with `type_env` applied -- and it needs only a shallow snapshot of the scope stack, since a re-resolution only READS the outer scopes (a `resolve_value` pushes its own). The env ACCUMULATES (`generic_bodies[id].env`), so a second parameter sees what the first bound, and the cache is keyed by `(definition, argument type)` with `Semantic.Type:equals`. The erasure then needed one more question: `erased` asked only about the RESULT, while a generic word's STAGES are what have no layout -- a `Type` stage is a parameter and a stage typed by a variable is not concrete yet -- so `S.Type:mentions_variable()` became a derived method beside `copyable`, asked by `Lower` (is this definition erased?) and by `Contract` (a generic word's BODY cannot be checked, because `f(x)` on an `f : T` has no meaning until an instantiation supplies the type -- and that is not a hole: every INSTANCE is concrete and `Contract` checks each one as `Resolve` builds it). | Three things worth keeping. (1) **The design meeting the code changed the design**: S110 said an instance is a copy with substitution, and the moment I looked for where the copy would go, re-resolving was obviously right -- the syntax and the scope are all the copy needs, and re-resolution cannot disagree with the original because it IS the original's code. A plan written in the ledger is a hypothesis, and this one was half wrong in a way only implementation could show. (2) **The spelling tells the truth about the cost**: the word arrives TWICE -- once as the TYPE (which names the callee, §S99) and once as the VALUE (whose packet the call carries) -- because a type parameter is erased. An inferred form (`twice with square` reading the type off the argument) would hide a monomorphization decision behind one word, and this design's rule is that a check reads a DECLARATION (§12.2), so the type is written. (3) **What is still not built**: a `Type` stage's argument cannot be a type APPLICATION in a value position (`id with (Box with Int)`), because the parser reads `Box with Int` there as a value application; and the type argument is not inferred from the value. Both are refusals rather than crashes, and both are the next step if a program wants them. Acceptance: `test/language.lua` #37, which RUNS (`81 5`), and the reference's generic-words block, which is compiled by `test/reference.lua`. |
| S112 | **"Specialize on an AGGREGATE of continuation words" was NO, and it was ONE hole.** A reader asked whether a word can take, as the input it specializes on, an aggregate of continuation words — the dictionary `{ add : …, mul : … }` that "polymorphism is words" implies. Measured: a continuation word as a STAGE works (`let with_k = let k : inc1 ... k(x) ...`, §S99); a word reached through a record VALUE works (`pair.op(21)`, §S92); and a word reached through a record TYPE did NOT -- `let p : { op : inc1 } ... p.op(x)` was `NotExecutable`, so a dictionary could not be a stage's type and therefore could not be a generic word's type argument either. The cause is one branch: `Judge.word_of` knew a record two ways -- an aggregate VALUE and a chain of references -- and not the way that matters for a PARAMETER, which is what the record **IS**. A record TYPE's field whose type is a WORD names that word, and the declared type is in the DECLARATION (`Judge.Bound``(declared)`, or a `Value`'s annotation), so this is still structural: no interface of `Contract`'s is read (§S52). Fifteen lines, and the pattern works end to end: `use with Dict with dict with 21` is `44` for a two-field dictionary, `22` for one, and the continuation-passing shape still works. | Two things worth keeping. (1) **The two ways a record can be known are what it HOLDS and what it IS**, and `word_of` only had the first -- which is invisible until a record arrives as a PARAMETER (a stage or a type variable), because a parameter has no value to look through. That is the same shape as §S89/§S92/§S98: a question asked of the value when only the declaration can answer. (2) **It costs nothing at run time**, and that is the point of the pattern: the field's TYPE names the callee, so `d.fold(d.bump(x))` is two direct calls with no lookup, no tag and no dictionary -- the dictionary exists only in the source, and the instantiation removes even that. Acceptance: `test/language.lua` #38 (a two-field dictionary, `44`) and the reference's dictionary block. |
| S113 | **The call form takes a TYPE argument, because the two forms are one path -- and the fix was to give the instantiation ONE owner.** `id(Bool, true)` and `twice(square, square, n)` were `MismatchedType` while `id with Bool with true` worked: the `with` form asks "is the next stage a `Type` stage?" and instantiates, while `Syntax.Invoke` resolved EVERY argument as a VALUE -- so the type argument consumed a value stage and the next one landed on the wrong type. The reference's own sentence is the specification (`f with a with b` and `f(a, b)` lower to identical code, §S88), so the instantiation moved out of the `Specialize` branch into `instantiate(callee, argument, span)`, which answers two things: whether the argument was a TYPE argument at all (`is_type`, which STAYS TRUE when the instantiation failed, so a caller never falls back to reading a type as a value) and the node the expression denotes (the instance). Both branches ask it. | The one design question the fix had to answer is why the call form does NOT simply desugar into `Specialize` -- which is what §S88's sentence suggests and what I tried first: because invocation is transient SATURATION (§1.2/§S62), so `sum(1)` must stay `Undersaturated` and must not become a PARTIAL application. Test #13 says exactly that, and it is the reason the desugaring is wrong: the two forms share the OPERATIONS (construct/advance/run, §1.2) but not the residual's lifetime, and the type argument is the one place where that difference is visible in the SOURCE rather than in the belt. So the call form instantiates IN PLACE and keeps its own shape. Acceptance: `test/language.lua` #39 (`id(Int, 42)` is `42` and `twice(square, square, 3)` is `81`), with #13 still refusing `sum(1)`. |
| S114 | **The reader is right: a `Type` argument must be DEDUCED, and the deduction is built and MEASURED but not landed.** The rule, as the reader stated it and as it fits the design: "a `Type` stage that appears in the declared type of a later stage is deduced from that stage's argument" -- so `divide with { let ok = on_ok let err = on_err }` mentions each continuation ONCE instead of writing the types again, which is the "same fact written twice" class this design keeps removing. Two pieces were written; their mechanism RAN ONCE, in a state where the explicit forms were broken -- so the evidence is that it can work, not that it did: `derived_type` (the type of a VALUE without asking `Contract` -- a word by nominality through `word_of`, a record of those, a literal by its form) and `deduce_into` (fill `Semantic.Variable`s from the DECLARED type of the first stage that is not a `Type` stage, field by field, requiring names to match and everything else to be equal -- so §S52 holds: nothing reads an interface). Measured, with the deduction in place: `divide with { let ok = on_ok let err = on_err }` **compiled**; `twice with square with square with 3`, `id(Int, 42)` and `sum(1)` (`Undersaturated`) all kept working. Two things stopped it, both small and named. (1) **A deduced argument must NOT be consumed**: `id(true)` has to deduce `T := Bool` AND pass `true` to `x`, so `instantiate` needs a THREE-way answer -- "not an instantiation", "a type argument (consumed)", "deduced (apply the argument to the instance)" -- and today it answers a boolean. (2) **`word.items` are CHAIN stages (`.type`, `.binder`) while `body.items` are SYNTAX (`.stage`)**, and mixing them crashed the explicit path -- a regression I introduced, **(LANDED in §S115 -- the four-state protocol was the design that was missing.)** which is why the change was REVERTED rather than patched further at the end of a long session. | What IS landed from this turn is the diagnostic: omitting a type argument used to be `Bug(NoLowering('type form'))` -- the compiler blaming itself for a program the grammar accepts (§S99's lesson) -- and is now `Reject(UnknownType)`, which is true (the argument is not a type) until deduction makes it unnecessary. The lesson is the one this session keeps re-learning from the other side: **a plan that fits the mechanism is not the same as a plan that fits the CALLERS**, and the three-way protocol is the part I did not design before writing code. The remaining work is those ~15 lines: the protocol, and the field-access discipline, after which `id(true)` and `divide with {…}` both work and `test/language.lua` gets a #40 for each. |
| S115 | **The deduction LANDED, and the missing design was the caller protocol -- not the unification.** A type argument is now DEDUCED when it can be: `divide with { let ok = on_ok let err = on_err } with 41` is `42`, `id(42)` is `42`, and the SAME shape with the continuations swapped is `-41` -- which is the proof that the deduction reads the VALUE and not just the shape, so two dictionaries of one type-shape with different words are two instances. The mechanism is S114's (`derived_type` + `deduce_into`, both structural, nothing reading an interface -- §S52 holds) and it needed no change; what it needed was for `instantiate` to answer FOUR states instead of a boolean: 'none' (not an instantiation -- the caller applies the argument as a value), 'consumed' (the argument WAS the type argument; nothing left to apply, and `node == nil` means it failed so the caller must not fall back), and 'deduced' (the parameters came from this argument's TYPE, so `node` is the instance AND the caller must still apply the argument to it -- `id(true)`/`id(42)` is this case). Both callers -- the `with` form and the call form -- then read the same three answers, and the call form keeps its `Invoke` shape so §1.2's transient SATURATION still refuses `sum(1)`. | The lesson is the one §S114 recorded from the wrong side: **a plan that fits the mechanism is not a plan that fits the CALLERS**, and writing the protocol down BEFORE the code is what made this pass one atomic change instead of eight surgical ones. Two hazards were named in advance this time and both held: the deduced argument must not be consumed, and `word.items` are CHAIN stages (`.type`, `.binder`) while `body.items` are SYNTAX (`.stage`) -- so the item list a loop walks is a decision, not a detail. Acceptance: `test/language.lua` #40 (the dictionary, run) and #41 (`id(42)`), with #13 still refusing `sum(1)` and every earlier form unchanged. |
| S116 | **A destructured stage: `let { ok : Ok, err : Err }` binds a record's FIELDS by name.** The reader asked why the surface was heavy -- `let provide : DivK with Ok with Err ... provide.ok(n)` -- and the answer split three ways. (1) The type NAME was already optional (`{ ok : Ok, err : Err }` inline works). (2) The `Type` stages CANNOT go: §3.1 makes a stage declare its type, and §2.6 makes the declaration the whole contract -- an exported word's entry point is a C prototype the HOST calls, so it cannot depend on its call sites. (3) The remaining weight was the stage NAME and the PROJECTION, and that is what this removes: an item `let` with no name and a record type is ONE stage of that type, with each field bound as a name -- so the body reads `ok(n)`. Measured, both spellings: `divide with { let ok = on_ok let err = on_err } with 41` is `42` and the same shape with the continuations SWAPPED is `-41`, with `let_divide_15_run` and `let_divide_23_run` in the emitted C. | The change is PARSER AND RESOLVE ONLY -- no `Lower`, no `Contract`, no belt -- and that is a property of the design rather than luck: the anonymous stage gets a generated name for the emitted C (the packet's field), and each FIELD is a definition whose value is a `Project` of that stage, which `word_of` already follows to a declared record type (§S112) and which the deduction already fills the type parameters of (§S114/§S115). So the three pieces of this arc compose: types are values (§S108), a type argument is deduced when it can be (§S115), and a record's fields can be the names you write (§S116) -- one mention per continuation, one protocol shape, two monomorphic instances. The reader's sketch was `let { let ok, let err }` with `let` inside; the spelling that landed is `let { ok : Ok, err : Err }`, because the braces are a RECORD TYPE and the stage is one argument -- which is exactly what makes the deduction possible, since the evidence for every parameter then arrives at once. |
| S117 | **Is the destructured stage good design? No -- and the incoherence is specific, and the design already had the feature.** Asked to reflect on §S116, the honest answer is three measurements and one sentence. (1) **The design already had it, with NO new syntax**: a stage of the record type plus a PRELUDE per field whose value is a projection -- `let provide : { ok : Ok, err : Err }` / `let ok = provide.ok` / `let err = provide.err` / `return ok(n)` -- compiles and runs (`42`) with the deduction filling `Ok`/`Err` from the aggregate. So the new item form is SUGAR. (2) **What it breaks**: every other `let` in the language binds exactly ONE name, and the aggregate syntax makes that explicit -- `{ let a = 1 let b = 2 }` is two `let`s for two names -- while `let { ok : Ok, err : Err }` binds several. It is coherent in its TYPES (the braces are a record type in both positions) and incoherent in its BINDINGS, so it introduces the language's FIRST binder pattern, and a pattern is a concept rather than a spelling. (3) **The reader's own sketch is worse**: `let { let ok : Ok, let err : Err }` collides with an existing meaning -- `{ let a : T }` is a WORD (a constructor, §S99) -- so it would read as "a stage whose type is a constructor". The sentence is therefore: **the braces may mean a record type, and a `let` may bind one name; the form that does both at once is the one that needs a sentence of its own.** | The recommendation is to DROP the sugar and document the projection form, because (a) the coherent spelling costs two lines and needs nothing new, (b) a binder pattern is a large concept to introduce for a two-line saving, and (c) the design's own rule -- "named by a sentence, keep; named by nothing, delete" -- asks which sentence the form is named by, and the answer would be a NEW one about `let`, not a consequence of the existing ones. What is NOT in question is the feature: one mention per continuation, the protocol's shape named once, and two monomorphic instances all follow from §S114/§S115 and the projection form. The reflection is recorded HERE and the reference's dictionary section teaches the projection form. |
| S118 | **The sugar was DROPPED, and the language is smaller for it.** §S116's destructured stage (`let { ok : Ok, err : Err }`) is removed -- the parser branch, the Resolve field-bindings, and the test -- and the reference's section now teaches the coherent form it desugars to: a record-typed stage plus a prelude per field that PROJECTS from it. Nothing is lost but two lines, because §S115's deduction and §S112's projection walk were doing the work all along: `divide with { let ok = on_ok let err = on_err } with 41` is `42`, the swapped dictionary is `-41`, and the emitted C holds two instances. | Why dropping is the right call rather than a retreat: the incoherence was not cosmetic. **Every `let` in the language binds exactly one name**, and the aggregate syntax makes that explicit (`{ let a = 1 let b = 2 }` is two `let`s for two names) -- so the sugar introduced the language's FIRST binder pattern, which is a concept rather than a spelling, for a two-line saving. The design's own test applies: "named by a sentence, keep; named by nothing, delete" -- and the sentence for that form would have been a new one ABOUT `let`, not a consequence of the existing ones. The reader's original sketch (`let { let ok : Ok, let err : Err }`) was worse still: `{ let a : T }` is already a WORD (§S99), so it read as "a stage whose type is a constructor". What survives is the useful half: the IDIOM is now documented (a dictionary is a record you name and project), which is what a reader actually needs, and the grammar did not grow. |
| S119 | **"Can I type the continuations?" -- yes, three ways, and the interesting one needs no type parameters at all.** Measured, all running `42`: (1) **by the WORD NAMES** -- `let provide : { ok : on_ok, err : on_err }`, with no `Type` stages anywhere, because a name that denotes a word IS a type (§3.2) -- so the record type is the dictionary, and the trade is that this word accepts exactly those continuations; (2) **by ANNOTATION on a projected name** -- `let ok : Ok = provide.ok` -- which is a claim the compiler CHECKS rather than infers (§12.2), and it works because the projection's type and the annotation are one type; (3) **as a STAGE type** -- `let f : on_ok` -- which is the direct case, §S99's rule. | The consequence worth keeping: **a monomorphic dictionary needs no `Type` stage** -- the parameters exist only so that ONE word can take DIFFERENT dictionaries, which is the polymorphism case. That is "polymorphism is words" appearing in the TYPE system rather than in the calling convention: the type of a dictionary is the record of the words it holds, so writing the types by name is not a workaround for the parameters -- it is the same mechanism with the parameters resolved. Acceptance: `test/language.lua` #43 (the word-name-typed dictionary, run), and the reference's dictionary section now shows both forms and says which is for what. |
| S121 | **Three defects from a real program, and all three are the session's oldest class: a rule that holds somewhere and was not applied where it was needed.** A reader wrote a calculator -- precedence climbing over a C string, ASan-clean -- and found: (1) **`or` was a MISCOMPILE.** `lower_short_circuit` builds `short_arguments` (the carried values plus the LEFT value) but the `Branch` was emitted BEFORE it, so the short arm read an uninitialised parameter. `and` passed by luck -- its short value is false, which is what a fresh parameter held -- and `or` returned false where it owed true. In the wild it showed up as `if q == 0 or q < min do break end` never breaking at end of input, so the reader ran past the string. (2) **An impossible path emitted a DEFAULT VALUE.** A word whose result is a sum and whose body ends in an exhaustive `switch` got `return INT64_C(0)` from the fall-through: for a sum result `cc` refuses it ("incompatible types when returning type 'long int' but 'struct let_s2' was expected") and for an `Int` result it silently returned 0. It is a `B.Trap` now -- the operation §3.5's destructor already uses for a tag that names nothing -- and that is sound because `Contract` refuses a non-Unit body that does not return, so the path is unreachable by construction. (3) **`return` did not INJECT.** `check_body` compared with `equals` where §3.5 says a value whose type equals exactly ONE alternative is injected, so `return { let at = p }` was `MismatchedType` while the IDENTICAL value bound first (`let r : Ok | Err = ...` then `return r`) worked -- and every parser grew `ok`/`fail` constructor words to say what the language already knew. It is `accepts` now, the one place that rule lives, so an AMBIGUOUS sum is still refused. | Two things worth keeping. (1) **A miscompile has no diagnostic to find it with**, which is why the check for (1) is the ANSWER (`1 1 0`) rather than the shape, and why the mutation is part of the record: reverting the short edge gives `got 0 1 0`. (2) Each defect is a different face of one habit: the short arm's parameters existed and its EDGE did not carry them; the fall-through's impossibility was known to `Contract` and unknown to `Lower`; and §3.5's injection was implemented for a binding and a stage argument and forgotten at `return`. The reader diagnosed all three correctly, including that (3) was "the same rule as §9, just not applied at `return`". Acceptance: `test/language.lua` #45, #46, #47. Also recorded from the same report, as LIMITS rather than gaps: mutual recursion is `UnknownName` (a later item's declaration does not exist when an earlier body is resolved -- §S74's own rule, one level up), and there is no character literal (purely lexical, not built). |
| S122 | **The corpus is REVIVED, and reviving it found three things a writer hits immediately.** `examples/` held eight programs written against older surfaces -- `Int -> do Int` arrows, application by juxtaposition, `c.puts`, an undeclared `Buffer`, `let_answer` as an entry point -- and NOTHING ran them, so six had silently rotted. They are current now (a continuation dictionary typed by the words' own NAMES, `with` instead of juxtaposition, self-recursion plus a second accumulating STAGE where mutual recursion is unavailable, a declared host type with the host's destructor, a host word for output) and every `.let` in `examples/` is compiled and RUN by `test/examples.lua` with its host. `calc.let` also lost its `ok`/`fail` constructors: they were a workaround for §S121's `accepts` bug, and with the bug gone the same program returns the records directly and prints the same eight answers -- the clearest evidence yet that a workaround in a real program is a bug report about the compiler. | Reviving found three things, and the first is a DEFECT. (1) **A Let name reaches the emitted C, so a C KEYWORD produces invalid C with NO diagnostic**: the example's word was `double` and the unit contained `struct let_s2 double;` -- `cc` refused it and the compiler said nothing. The name is the host's contract (the struct member, `let_<name>_entry`), so the fix is a NAMING decision rather than a parse rule -- mangle it, or refuse it -- and it is NOT made here, because it changes what every host writes. (2) **A word with no result returns the Unit BYTE, not `void`**: an `extern` with no result derives `uint8_t say(const char *)` (§S41), so the host must return the byte; the example gives `say` an `Int` result and discards it, which is the natural spelling. (3) **A host TYPE must be declared by the HOST before the unit** (§S44): the unit names `Buffer` and cannot define it, which is exactly what the harness's header argument is for -- and a duplicated `typedef` to the same type is legal C11, so the host file stays self-contained when a person compiles it too. |
