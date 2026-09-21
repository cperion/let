# The Let language — reference

This is the language as the compiler implements it: the syntax you can write and the semantics it
gives that syntax. **`DESIGN.md` is the specification** — it says why each rule exists, which
alternative was rejected, and how the compiler is built. This document says *what a program means*,
and it is checked rather than asserted: `test/reference.lua` extracts every fenced `let` block below
and compiles it, so an example here cannot rot without failing the suite.

The fence's info string is the contract for its block:

| fence | meaning |
| --- | --- |
| ```` ```let ```` | a **complete file** that must compile |
| ```` ```let refuse: Reason ```` | a complete file that must be refused as a `Reject`, with that reason |
| ```` ```let missing: Reason ```` | a complete file the compiler must report as a `Missing`, with that reason |
| ```` ```text ```` / ```` ```c ```` | an unchecked sketch — syntax shapes and the host's side |

Let is a small language with one large idea: **a program is a chain of bindings, and a value is either
a word or a datum.** There is no garbage collector; ownership is tracked and checked.

---

## 1. Source text

A file is UTF-8 bytes. Whitespace is insignificant; **`#` starts a comment** that runs to the end of
the line.

```let
# A comment, and the program is one binding.
let answer = 1
```

### 1.1 Names and keywords

A name matches `[A-Za-z_][A-Za-z0-9_]*`. These words are reserved and cannot be names:

```text
let  mut  own  move  return  if  else  while  break  continue  do  end
and  or   not  switch  case  as  extern  pure  host  borrows  with
```

`true` and `false` are **not** keywords — they are lexical names that the parser recognises as Boolean
literals. `import` is not a keyword either: it is a dictionary word, so a local binding named `import`
shadows it.

### 1.2 Integer literals

Decimal, hexadecimal (`0x`) and binary (`0b`), with `_` allowed anywhere among the digits. The
spelling is *not* the value: `16`, `0x10` and `0b10000` are one value, which matters because two labels
in a `switch` collide by value.

```let
let a = 16
let b = 0x10
let c = 0b1_0000
```

### 1.3 Float literals

A float needs a **leading digit** and either a fractional part or an exponent: `1.0`, `1.5e3`, `1e3`,
`1_0.5`. `.5` is not a literal, because `.` is the postfix projection — that is what keeps `a.b`
unambiguous. There is **no float arithmetic** (see §12).

```let
let a = 1.5
let b = 1.5e3
let c = 1e3
```

### 1.4 Text literals

Double quotes, with the escapes that change the meaning of the bytes: `\n`, `\t`, `\r`, `\0`, `\\`,
`\"`. Anything else is an error. A `Text` is an immutable, module-lifetime value — a pointer to static
storage — not a view into anything.

```let
let greeting = "hello\tthere\n"
let size = TextSize with greeting
```

### 1.5 Operators and punctuation

```text
==  !=  <=  >=  <<  >>  ->  +  -  *  /  %  <  >  &  |  ^  ~
=  ;  :  ,  (  )  {  }  .  [  ]
```

`!` exists only as part of `!=`. There is no `?`, no `++`, no compound assignment.

---

## 2. The shape of a file

A file **is a chain**: zero or more *items*, then an optional *terminal*.

An item is one of four things:

```text
let NAME [own] [mut] : TYPE          a STAGE      — an input the chain is waiting for
let NAME [mut] [: TYPE] = CHAIN      a PRELUDE    — a completed binding
extern [pure] NAME ["symbol"] (STAGES) [: TYPE]   a HOST WORD
host NAME [borrows N] [DESTRUCTOR]                a HOST TYPE
```

The split between a stage and a prelude is decided by the `=` alone. A stage **must** declare its
type: it has no value to read one from. `own` is only meaningful for a stage — a prelude with `own` is
refused.

Items are **greedy**: the parser keeps reading items while the next token can begin one, and the first
token that cannot begins the terminal. So no separator is needed *between* items:

```let
let a = 1
let b = 2
let c = a + b
```

`;` is a separator, and it is required in exactly one place: **between an item's value and a written
terminal**, because both sides are expressions. It is also accepted anywhere between items.

```let
let a = 1
let b = 2
; { let sum = a + b }
```

### 2.1 The terminal

A terminal is either a **data expression** or a **`do` body**:

```text
TERMINAL = EXPR
         | do [: TYPE] STMT* end
```

A chain with **no written terminal at all** is legal at the top level of a file, and its value is the
named aggregate of its own prelude bindings, in source order.

A chain with a `do` terminal is a **word**, and it must state its result: `do : Int`. A `do` without a
result is refused (`UnstatedResult`), because there is no term to read a type from.

```let
let add = let a : Int let b : Int do : Int
    return a + b
end
let seven = add(3, 4)
```

A chain with a **data** terminal and no stages is a value, not a word — it is inlined where it stands:

```let
let two = 1 + 1
```

---

## 3. Words, stages, application

A **word** is a chain that has stages or a `do` terminal. It is the language's only abstraction
mechanism, and it is deliberately simple: a word is a *template*, plus the values it has already been
given. Applying one argument at a time turns it into a word with one fewer free stage, and when no
stages are free the terminal runs.

**Application is the keyword `with`**, one argument at a time, left-associated:

```let
let add = let a : Int let b : Int do : Int return a + b end
let add2 = add with 2
let five = add2 with 3
```

Invocation is the **same operation** with a different spelling — `f(a, b)` — and `f()` runs a word
that has no stages left. `f with a with b` and `f(a, b)` lower to identical code; the `()` spelling is
the one `with` cannot write, because `with` always supplies an argument.

The operations are identical; what differs is **when the word runs**. Invocation is **transient
saturation** — `sum(1)` wants to run and still has a stage free, so it is `Undersaturated` — while
`sum with 1` is a partial application, which is a word. And invocation takes a **type argument** the same
way `with` does, so either spelling can instantiate a generic word:

```let
let sum = let a : Int let b : Int do : Int return a + b end
let partial = sum with 1                      # a word: one stage still free
let whole = sum(1, 2)                         # runs now
let id = let T : Type let x : T do : T return x end
let typed = id(Int, 42)                       # a Type argument works here too
```

```let
let add = let a : Int let b : Int do : Int return a + b end
let a = add with 3 with 4
let b = add(3, 4)
```

Two expressions **in a row are not an application** — that is a mistake the parser reports, and it
explains what you meant. A parenthesised expression after `with` is a *group*, so a word can be an
argument:

```let
let square = let x : Int do : Int return x * x end
let sum = let a : Int let b : Int do : Int return a + b end
let answer = sum with (square with 3) with (square with 4)
```

### 3.1 Stage capabilities

A stage's `own`/`mut` qualifiers are its **capability**, and they say what the word does with the
argument (this is §7's ownership story; the spellings are these):

| spelling | capability | meaning |
| --- | --- | --- |
| `let x : T` | read | the word **borrows** `x` for the call |
| `let x mut : T` | mut | the word borrows `x` and may write through it |
| `let x own : T` | own | the word **takes** `x`; the caller must write `move` |
| `let x own mut : T` | own+mut | takes it, and may write |

The declaration is the whole contract: the compiler holds the word to the capability and does not
infer one from the call site.

### 3.2 A word's type is nominal

A word value's type names **the word and how many stages it already holds** — not its shape. So a
stage declared with one specific word's type accepts that word (at that prefix) and no other, however
alike another word looks. The type is selected at the call site, with no dispatch at run time.

```let
let add = let a : Int let b : Int do : Int return a + b end
let add2 = add with 2
let apply = let f : add2 let x : Int do : Int
    return f(x)
end
let seven = apply(add2, 5)
```

A word whose *result* is a word is how a record constructor is written:

```let
let Pair = { let a : Int let b : Int }
let p = Pair with 1 with 2
let a = p.a
```

### 3.3 A stage's type must be a value's type

A stage is a value the caller supplies, so a type with no representation cannot be a stage's type. An
**arrow** (`A -> B`) and a **`do`** type are *shapes* — they describe a word and not a datum — and a
stage declared with one is refused (`NotExecutable`). What you want instead is either a **nominal word
type** (§3.2) or a **sum** (§9), and both select a callee without a vtable.

```let refuse: NotExecutable
let f = let g : Int -> Int do : Int
    return 1
end
```

### 3.4 Recursion

A word's own name is visible inside its `do` body, and only there. It is not visible to its own stages
or to the items before the terminal, which run while the word is being built.

```let
let fact = let n : Int do : Int
    if n <= 1 do return 1 end
    return n * fact(n - 1)
end
let answer = fact(5)
```

---

### 3.5 A dictionary is a record of words

A word that needs several operations takes them as a **record of words** — one stage of that record
type — and binds each one with a prelude whose value is a **projection** of the stage. That is
"polymorphism is words" with no dictionary object, and because a field whose type is a word NAMES that
word, `ok(n)` has a callee with no lookup at run time:

```let
let on_ok  = let n : Int do : Int return n + 1 end
let on_err = let n : Int do : Int return 0 - n end
let divide = let Ok : Type let Err : Type
    let provide : { ok : Ok, err : Err }
    let ok = provide.ok
    let err = provide.err
    let n : Int do : Int
    return ok(n)
end
let a = divide with { let ok = on_ok  let err = on_err } with 41
let b = divide with { let ok = on_err let err = on_ok  } with 41
```

The record is **borrowed** (a `Read` stage), so nothing is moved out of the caller's aggregate, and
the type parameters are **deduced** from it (§12) — which is why each continuation is mentioned once,
and why the two calls above are two instances (`42` and `-41`).

One `let` per name, always: a dictionary is a record you name and project, not a pattern that binds
several names at once.

**A dictionary can be typed by the words themselves**, which needs no type parameters at all — a name
that denotes a word is a type (§3.2), so the record type IS the dictionary:

```let
let on_ok  = let n : Int do : Int return n + 1 end
let on_err = let n : Int do : Int return 0 - n end
let divide = let provide : { ok : on_ok, err : on_err }
    let ok = provide.ok
    let err = provide.err
    let n : Int do : Int
    return ok(n)
end
```

That `divide` accepts exactly those two continuations, because its TYPE names them; the parameterised
form above is what you write when ONE word must take different dictionaries. And a projected name may be
**annotated** like any binding — `let ok : Ok = provide.ok` — which is checked rather than inferred.

### 3.6 Generic words

A `Type` domain on a chain whose terminal is a **body** is a generic word — one word in the source, one
**INSTANCE** per type argument in the output, with no tag and no dispatch:

```let
let twice = let F : Type let f : F let x : Int do : Int
    return f(f(x))
end
let square = let x : Int do : Int return x * x end
let inc = let x : Int do : Int return x + 1 end
let a = twice with square with square with 3
let b = twice with inc with inc with 3
```

The type parameter is **erased**, and the word arrives TWICE: once as the *type* — which names the
callee (§3.2), so there is no vtable — and once as the *value*, whose packet the call carries. A `Type`
stage must come **first** (an instance drops it, and the stages after it are what remain), and the generic
word itself has no runtime form: what runs is the instance, and an instance is concrete. **There is no
runtime genericity** — the type must be known statically, and where it is not, the *data* must say what it
is: a sum.

The type argument may also be **deduced** from the value, so each continuation is mentioned once:

```let
let on_ok = let n : Int do : Int return n + 1 end
let on_err = let n : Int do : Int return 0 - n end
let DivK = let Ok : Type let Err : Type { ok : Ok, err : Err }
let divide = let Ok : Type let Err : Type let provide : DivK with Ok with Err let n : Int do : Int
    return provide.ok(n)
end
let a = divide with { let ok = on_ok let err = on_err } with 41
```

The rule: a `Type` stage that appears in the declared type of a **later** stage is filled from that
stage's argument — here `provide : DivK with Ok with Err` is where `Ok` and `Err` appear, so the
aggregate's own type names them. The deduction reads the **value**, so two dictionaries of one shape with
different words are two instances; a deduced argument is **not consumed** — it is passed on to the stage
it was deduced from, which is why `id(42)` is `42`. Where the argument's type is not derivable (a call's
result, say), write the type.

A dictionary is a **record of words**, and a `Type` parameter can be one — a field whose type is a word
NAMES that word, so the callee comes from the type and costs nothing at run time:

```let
let inc1 = let x : Int do : Int return x + 1 end
let dbl  = let x : Int do : Int return x * 2 end
let Dict : Type = { bump : inc1, fold : dbl }
let dict = { let bump = inc1 let fold = dbl }
let use = let D : Type let d : D let x : Int do : Int return d.fold(d.bump(x)) end
let answer = use with Dict with dict with 21
```
## 4. Types

```text
TYPE = Int | U8 | U32 | Float | Float32 | Bool | Unit | Text | CString | CPointer
     | NAME                     a host type, or a name that denotes a word/value (§4.3)
     | { FIELD, ... }           a record       FIELD = NAME [mut] : TYPE
     | ( TYPE, ... )            a tuple (a record with unnamed fields)
     | ( TYPE )                 a GROUP: `(T)` is `T`, exactly as in an expression
     | TYPE with TYPE           a type application (`Box with Int`), §4.3
     | TYPE | TYPE              a sum
     | TYPE -> TYPE             an arrow  — a SHAPE (§3.3)
     | do TYPE                  a chain's type — a SHAPE (§3.3)
```

```let
let f = let whole : Int let byte : U8 let wide : U32 let real : Float32
        let flag : Bool let nothing : Unit let text : Text
        let r : { a : Int, b mut : Bool } let pair : (Int, Bool)
        let either : Int | Bool
    do : Int
    return whole
end
```

`mut` inside braces is **interior mutability**: the member is writable through a binding whatever the
binding's own mutability says (§7.3).

### 4.1 `Text` and the foreign pair

`Text` is an immutable module-lifetime value. `CString` and `CPointer` are **host types**: the host
owns what they mean and Let only names them. A host type is declared, never registered from outside:

```let
host Handle release
host View borrows 1
```

`release` names the destructor, `borrows 1` says a value of this type is a **borrow** whose owner is
argument 1 of the word that produced it (§7.4). Both are optional.

### 4.2 Conversions

Conversions are **dictionary words** — names that resolve when no lexical binding shadows them — and
each is a one-stage word. This is the whole set:

| word | from → to |
| --- | --- |
| `ToInt` | `Float → Int` |
| `ToFloat` | `Int → Float` |
| `ToU8` | `Int → U8` |
| `ToU32` | `Int → U32` |
| `ToF32` | `Float → Float32` |
| `ToCString` | `Text → CString` |
| `TextSize` | `Text → Int` |
| `IsNull` | `CPointer → Bool` |

There are **no implicit conversions**: `ToInt with 1` is a `MismatchedType`, not a conversion. `ToText`
is deliberately absent — a `Text` has a length and a `CString` does not, so the reverse direction needs
a representation decision the compiler does not make for you.

```let
let as_float = ToFloat with 1
let back = ToInt with 1.5
let small = ToU8 with 200
```

### 4.3 A name that denotes a value is a type

A name in type position denotes a type, and the derivation is **structural** — it answers from what
the DECLARATION already says, because the type position is read before the type checker runs:

- `Int` denotes a *type word*, so `x : Int` means the type it **names**.
- a name that denotes a **word** — including a **partial application** — denotes that word's
  nominal type in `(template, prefix)` (§3.2).

**What it cannot answer is the type of a datum.** `origin = Point with 0 with 0` is a value, and its
type is what the checker computes, so `p : origin` is `UnknownType`: write the record type out.

```let
let Point = { let x : Int let y : Int }
let origin = Point with 0 with 0
let f = let p : { x : Int, y : Int } let n : Int do : Int return p.x end
```

```let refuse: UnknownType
let Point = { let x : Int let y : Int }
let origin = Point with 0 with 0
let f = let p : origin let n : Int do : Int return p.x end
```

**A name for a bare type word works.** `let P = Int` binds a name for a type — §2.4's *erasure*: the
name is static, so `P` never becomes a value and nothing is emitted for it — and `P` is usable wherever
a type goes:

```let
let P = Int
let twice = let x : P do : P return x * 2 end
let answer = twice with 21
```

**And the general form works.** `let P : Type = <a type>` names a type, and a chain with a `Type`
domain is a **type word**, applied with `with` — §2.4's *"evaluated at construction time and
erased"*, so the application happens in the type language and nothing about it reaches the emitted
code:

```let
let Point : Type = { x : Int, y : Int }
let p : Point = { let x = 1 let y = 2 }

let Box = let T : Type { a : T }
let b : Box with Int = { let a = 1 }
```

A type word must be applied to **all** of its parameters, and an *unapplied* one is not a type —
`p : Box` is a `MismatchedType`, because `Box` there denotes the nominal WORD type (§3.2) and not
what it builds.

- `Int` denotes a *type word*, so `x : Int` means the type it **names**.
- `square` denotes a **word** whose type is nominal in `(template, prefix)` (§3.2).
- `add2`, a **partial application**, denotes a word one stage further along — so it is a type too.

```let
let add = let a : Int let b : Int do : Int return a + b end
let add2 = add with 2
let f : add2 = add2
let five = f with 3
```

**A word's own name is a type for the WORD, not for what the word builds.** `Pair` denotes the
constructor, so a stage declared `p : Pair` takes the word value — and the *record* `Pair with 1 with
2` produces has the record's type, not the word's:

```let
let Pair = { let a : Int let b : Int }
let take_pair = let p : Pair let n : Int do : Int return 0 end
let f = let n : Int do : Int
    return take_pair(Pair, n)
end
```

```let refuse: MismatchedType
let Pair = { let a : Int let b : Int }
let use = let p : Pair let n : Int do : Int return 0 end
let f = let n : Int do : Int
    let p = Pair with 1 with 2
    return use(p, n)
end
```

---

## 5. Expressions

```text
EXPR = LITERAL | NAME | move POSTFIX | ( EXPR )
     | EXPR . NAME | EXPR [ EXPR ] | EXPR ( EXPR, ... )
     | EXPR with EXPR
     | UNARY EXPR | EXPR BINARY EXPR
     | { ... }              an aggregate
```

Literals are integers, floats, text, `true`, `false`, and `{}` — the **Unit** value.

### 5.1 Precedence

From loosest to tightest. Comparisons are **non-associative**, so `a < b < c` is a parse error rather
than a silent `(a < b) < c`.

| level | operators | associativity |
| --- | --- | --- |
| 1 | `or` | left |
| 2 | `and` | left |
| 3 | `==` `!=` | none |
| 4 | `<` `<=` `>` `>=` | none |
| 5 | `\|` | left |
| 6 | `^` | left |
| 7 | `&` | left |
| 8 | `<<` `>>` | left |
| 9 | `+` `-` | left |
| 10 | `*` `/` `%` | left |
| 11 | prefix `not` `-` `~` | right |
| 12 | `with` | left |
| 13 | `.` `[]` `()` | postfix |

So `f with x + 1` is `(f with x) + 1`, `f with -1` applies `f` to a negative literal, and `f(x).y[0]`
is a place. `and` and `or` **short-circuit**: the right side runs only when it decides the answer.
`not` is the only boolean unary operator; `-` and `~` are `Int`-only; every operator except the
comparisons and `and`/`or`/`not` is `Int → Int`.

```let
let f = let x : Int do : Int return 0 - x end
let a = f with -1
let b = (1 + 2) * 3 - 4 % 2
let c = 1 < 2 and not (3 == 4)
```

### 5.2 Places: projection and index

`e.name` reads a record's member; `e[i]` reads the element the index names. A **constant** index names
a member at compile time, so `t[0]` on a positional aggregate is an ordinary member read. A **runtime**
index is a dispatch: the members must share one type, and a value that names no member traps.

```let
let tuple = { 10, 20, 30 }
let first = tuple[0]
let record = { let a = 1 let b = 2 }
let second = record.b
```

### 5.3 Aggregates

`{}` is Unit. `{ let a = v ... }` is a **named** aggregate; `{ v, v, ... }` is **positional**; the two
cannot mix. A positional element may itself be a chain, so an element can have preludes:

```let
let positional = { 1, 2, 3 }
let named = { let a = 1 let b = 2 }
let computed = { { let n = 2; n * n }, 3 }
```

Inside braces, `let NAME : TYPE` with **no value** makes the whole form a *word* — a record
constructor whose stages are the fields:

```let
let Pair = { let a : Int let b : Int }
let pair = Pair with 1 with 2
```

### 5.4 `move`

`move place` transfers ownership out of a place. See §7.2 for when that matters: a move of a value that
is already Copy is just that value.

```let
let f = let n : Int do : Int
    let a = { let x = n }
    let b = move a
    return b.x
end
```

### 5.5 `import`

`import` is the dictionary word that loads another file. Its one argument is a constant `Text` path,
and the value is the imported file's **terminal** — its namespace, or its written terminal. A lexical
binding named `import` shadows it. A file is loaded **once**, however many times it is imported, and an
import cycle is refused (`ImportCycle`).

```text
let codec = import with "codec.let"
```

A path is opened **as given** -- relative to the process's working directory, not to the importing
file -- so what a real imported module does is checked by the suite instead: `test/language.lua` #15
imports a file and calls a word inside it (`other.twice with 21` is `42`).

A file that is not there is `MissingModule`; a path that is not a constant `Text` is `ImportPath`.

```let refuse: MissingModule
let nope = import with "this-file-does-not-exist.let"
```

---

## 6. Statements

Statements appear inside a `do` body and nowhere else — a file's top level holds items, not statements.

```text
STMT = let NAME [mut] [: TYPE] = CHAIN
     | PLACE = EXPR                    assignment
     | EXPR                            evaluate and discard
     | return [EXPR]
     | if EXPR do STMT* [else if EXPR do STMT*]* [else STMT*] end
     | while EXPR do STMT* end
     | switch EXPR do CASE* [else STMT*] end
     | break | continue
CASE = case LABEL, ... [as NAME] STMT*
LABEL = TYPE | EXPR
```

`let` inside a body is a binding like any other, and it may carry an annotation, which is **checked**
rather than inferred.

```let
let f = let n : Int do : Int
    let double = n * 2
    let label : Int = double + 1
    return label
end
```

### 6.1 Assignment

Assignment is a **statement**, so it lives in a body. The destination must be writable: a `mut` binding
or a `mut` member. Assigning to something read-only is `ReadOnlyDestination`.

```let
let f = let n : Int do : Int
    let total mut = 0
    total = total + n
    return total
end
```

Assigning **destroys the value being replaced** — but only when that value is still there: assigning
over a place that was already moved out of is not a second destruction.

### 6.2 `if` and `while`

`if`, `else if` and `else` form ONE chain closed by one `end`, and the condition must be `Bool`. A
chain that falls off the end returns Unit.

```let
let classify = let n : Int do : Int
    if n < 0 do return 0 - 1
    else if n == 0 do return 0
    else return 1 end
end
```

`break` and `continue` belong to the nearest `while`. A `break` inside a `switch` arm belongs to the
enclosing loop — a `switch` is not a loop.

```let
let count = let limit : Int do : Int
    let i mut = 0
    let seen mut = 0
    while i < limit do
        i = i + 1
        if i % 2 == 0 do continue end
        if i > 100 do break end
        seen = seen + 1
    end
    return seen
end
```

### 6.3 `switch`

A `switch` evaluates its subject **exactly once** and compares it with each arm's labels in order.
There is no fallthrough: an arm's body simply ends when it reaches the next `case`, `else`, or `end`.
`else` catches everything the labels did not.

A label is either a **shape** (a type, for a sum subject) or a **constant** (a value, for a scalar
subject). The kind is read off the label, not guessed. An arm that matched **by shape** may bind what
it matched with `as NAME`, and the binder's type is that alternative's payload.

```let
let describe = let v : Int | Bool do : Int
    switch v do
    case Int as n return n
    case Bool return 0
    end
end

let name = let n : Int do : Int
    switch n do
    case 1 return 10
    case 2, 3 return 20
    else return 0
    end
end
```

Two labels that name the same alternative, or the same constant value (`1` and `0x1`), are one label:
a repeat is `InvalidCaseLabel`. A label that is not an alternative of the subject is also
`InvalidCaseLabel`.

---

## 7. Ownership

There is no garbage collector. Every value has exactly one owner at a time, and the compiler checks
that no owner is used after it has given its value away.

### 7.1 Copy and move

A type is **Copy** or not, and the rule is structural: the scalars (`Int`, `U8`, `U32`, `Float`,
`Float32`, `Bool`, `Unit`) and `Text` are Copy; a record is Copy when every member is; a sum is Copy
when every alternative is. A **host type** is never Copy — the host owns what it owns — and neither is
a word value whose packet holds something that is not.

Using a Copy value twice is fine: a move of a Copy value is just that value.

```let
let f = let n : Int do : Int
    let a = n
    let b = a
    let c = a
    return c + b
end
```

A value that is **not** Copy can be used once. A second use without a `move` is `NeedsMove`, and a use
*after* a move is `UninitializedPlace`.

```let refuse: NeedsMove
host Handle release
extern make (n : Int) : Handle
let f = let n : Int do : Int
    let h = make(n)
    let a = h
    let b = h
    return n
end
```

```let refuse: UninitializedPlace
host Handle release
extern make (n : Int) : Handle
let f = let n : Int do : Int
    let h = make(n)
    let a = move h
    let b = move h
    return n
end
```

### 7.2 Places, and partial moves

Ownership is tracked **per place**, and a place is a name plus a path: `r`, `r.a`, `r.a.b`. Moving a
subplace leaves a hole exactly there, and the rule that follows is: a hole makes every place that
*contains* it unusable until something is assigned back into it, and every place *inside* it.

```let
let f = let n : Int do : Int
    let r = { let a = 1 let b = 2 }
    let x = move r.a
    return r.b + x
end
```

A path must be statically known to be moved; a **runtime** index names no subplace, which is why
`move t[i]` is not something the language offers.

### 7.3 Cells and interior mutability

An assignable binding is allocated once, at its declaration, and every read and write goes through
that storage. That is what makes assignment need no special treatment at a join.

A `mut` **member** is interior mutability: `r.x = 9` is legal even when `r` itself is bound
read-only, because the writability is a property of the member's type and not of the name holding it.

```let
let f = let n : Int do : Int
    let r = { let x mut = 0 }
    r.x = n
    return r.x
end
```

A binding that holds (or captures) a value like this keeps its storage addressable, which is why it
cannot be moved out of while a **view** of it — a capture, a pointer — is live. Moving it when nothing
is looking is fine.

### 7.4 Borrows

A `read` or `mut` stage **borrows** its argument: the word promises not to keep it, and the caller
still owns it afterwards. An `own` stage **takes** it, so the caller must say `move`. Calling a `read`
word and then moving the value is legal; the borrow does not outlive the call.

```let
host Handle release
extern make (n : Int) : Handle
extern peek (h : Handle) : Int
let f = let n : Int do : Int
    let h = make(n)
    let a = peek(h)
    let b = peek(h)
    return a + b
end
```

A word may not **return** a borrow it was given — that would be a view outliving what it points at
(`BorrowedEscapes`) — and a view may not be made of a temporary (`BorrowOfTemporary`). A host type
declares that it *is* a borrow with `borrows N` (§4.1).

---

## 8. Destruction

Destroying a value means running the destructor of the host types inside it, once, at the end of the
scope that owns it, **in reverse order of construction**. A record destroys its members in reverse; a
sum is destroyed by its **tag**, so only the alternative that is actually there is destroyed. Nothing
that was moved away is destroyed twice.

```let
host Handle release
extern make (n : Int) : Handle
let h = make(1)
```

A module is a scope too: if the module owns anything at the end of its initializer, the compiler emits
`let_module_unload`, and the host is expected to call it (§10).

---

## 9. Sums

A sum `A | B` holds exactly one of its alternatives, plus a tag saying which. Construction is **by type
match**: a value whose type is exactly one alternative is injected into it. A value that matches *no*
alternative, or *more than one*, is refused — two alternatives of the same type make a sum no value can
inhabit unambiguously.

```let
let flag : Int | Bool = 1
```

The match that decides which alternative is made on the value's **type**, not on its representation:
two alternatives can share a layout (two word values with empty packets are both a single byte), so the
decision is carried from where the types are known.

A `switch` on a sum compares the tag (§6.3), and the arm that matched binds the payload.

---

## 10. Modules, the host, and the ABI

A file compiles to a **C translation unit** that is a *module*, not a program. The host supplies
`main`. The unit is the source file's terminal (§2.1), and the compiler emits:

- `let_module_init(void)` — runs the initializer and returns the module value.
- one **entry point** per exported word: `let_<name>_entry(module, stage...)`, so the host can call a
  word the module never calls itself.
- `let_module_unload(module)` — **only when the module owns something**; it runs the destruction pass.

```c
/* The host's side: declare what the module's types are, supply main. */
#include <stdint.h>
#include <stdio.h>
typedef struct { int64_t tag; } Handle;     /* the host type it declared */

int main(void) {
    struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)let_main_entry(m, 5));
    let_module_unload(m);                   /* only if the unit declares it */
    return 0;
}
```

The struct names (`let_s1`, ...) and the entry points are the ABI; the compiler does not invent a
`main`, and it does not guess how you link.

---

## 11. Diagnostics and exit codes

A diagnostic is a value with a **position** — `file:line:column` — and one of three kinds. The exit
code is the kind, because a script that cannot tell "your program is wrong" from "the compiler is
wrong" cannot report either.

| exit | kind | meaning |
| --- | --- | --- |
| 0 | — | the unit was written |
| 1 | `error` | **Reject**: the program is wrong — a bad type, a moved value, a syntax error |
| 2 | `unimplemented` / `internal` | **Missing**: a mechanism the compiler lacks; **Bug**: a broken invariant |

A syntax error is a Reject like any other, and its message carries the position:

```let refuse: Syntax
let = 1
```

`Missing` is the compiler's own gap inventory, and it is a closed set of reasons rather than free text —
so "the compiler cannot do this yet" is distinguishable from "this can never work".

---

## 12. What is not implemented

These are the language's edges, stated here so that a reader does not have to discover them:

- **A stage's type cannot be an arrow or a `do` type** (§3.3). Those are shapes, not layouts. Use a
  nominal word type or a sum.
- **No float arithmetic**, and no implicit conversions of any kind (§4.2).
- **No garbage collection**, by design: §7 is the whole story, and it is checked rather than inferred.
- **`ToText` does not exist** (§4.2).
- **A name that denotes DATA is not a type** (§4.3). `let origin = Point with 0 with 0` then
  `p : origin` is `UnknownType`, because the type position is resolved before the type checker runs
  and only what a *declaration* says can be answered there. Write the record type out — or NAME the
  type, which is what a type word is for.
- **Generic words** (`Type` domains, and the deduction of a type argument) are not a gap — they WORK, and
  §3.6 describes them. This section is the LIMITS, and a capability does not belong in it.
- **A written terminal that leaves a top-level binding behind** is `Missing(ModuleState)`: the module
  value would have to become a pair rather than the terminal's value. A written terminal that *takes*
  everything it owns is fine and gets an `unload`.
- **A `switch` whose arms disagree** about whether the subject is moved is refused rather than tracked
  per-path; the disagreement is only corrected where the paths rejoin.
- **A word's name is visible only in its own body** (§3.4), so two words that call each other are
  `UnknownName` — there is no forward declaration. A recursive-descent parser with several rules
  therefore cannot be written directly: precedence climbing fits in one word, and a rule can be
  reached through a stage. The way in is §S74's own rule one level up — a word's declaration is in the
  SOURCE (a stage states its type, a `do` states its result), so a pass that published every
  top-level declaration before resolving any body would make this work.

```let refuse: UnknownName
let even = let n : Int do : Bool
    if n == 0 do return true end
    return odd(n - 1)
end
let odd = let n : Int do : Bool
    if n == 0 do return false end
    return even(n - 1)
end
```

- **There is no character literal.** A character is its code point — `c == 40` for `(`, `48`–`57` for
  digits — so lexing code is written in numbers. It would be purely lexical (`'('` is another spelling
  of `40`), and it is not built.

Each entry in the inventory has a program here, so the claim that it is a closed set is checked rather
than asserted -- and a `missing:` block that stops being reported fails the suite.

```let missing: ModuleState
host Handle release
extern pure made (n : Int) : Handle
let h = made with 1
; { let x = 1 }
```

---

## 13. A complete example

```let
# A module that owns a resource, exports a word, and destroys what it owns.

host Handle release
extern pure make (n : Int) : Handle
extern peek (h : Handle) : Int

let scale = 3

let doubled = let h own : Handle do : Int
    return peek(h) * 2
end

let main = let n : Int do : Int
    let h = make(n)
    let a = doubled(move h)
    let again = make(scale)
    return a + peek(again)
end
```

Compiled with `luajit letc.lua example.let -o example.c`, this produces a module whose initializer
builds `main` and whose `unload` releases what the module still owns. The host calls
`let_main_entry(m, 5)` to run it.
