# Let Core Language Specification

**Version:** 0.8 — whitespace-independent syntax, juxtaposition specialization, compact structured control, and file chains with imports

**Scope:** source syntax, source semantics, ownership, constraints, construction vocabulary, and embedding behavior

**Status:** Let language specification under active development

---

## 0. Authority and purpose

This document specifies what a Let program means. It does not prescribe a parser data structure, intermediate representation, instruction set, virtual machine, register organization, or compilation strategy.

The words **must**, **must not**, **should**, and **may** have their usual specification force. This document defines Let, independently of the current compiler's implementation coverage. Missing compiler features are implementation gaps, not a smaller language; they are tracked in `COMPILER.md`. Deferred language designs are identified explicitly.

Let is a small embeddable, word-oriented language built around five laws:

1. `let` introduces every program binding.
2. Unsatisfied `let` bindings form a curried word.
3. Juxtaposition specializes a word; it does not invoke it.
4. Postfix `()` invokes runtime behavior explicitly.
5. Owned state has one owner; borrowing and movement are visible at binding and use sites.

Juxtaposition supplies stable arguments and constructs a new specialized word. An existing receiver remains unchanged. A fresh owned receiver may transfer its state into the result because no earlier receiver owner remains observable. This source-level operation is defined independently of how an implementation represents or executes the result.

---

## 1. Semantic model

### 1.1 Three distinct operations

Let distinguishes value specialization, runtime invocation, and executable-code construction.

| Operation | Surface form | Meaning |
| --- | --- | --- |
| Specialization | `encoder JPEG 90` | Bind stable stages and produce a more specific value or word |
| Invocation | `jpeg(frame)` | Supply transient stages and enter the terminal runtime `do` |
| Construction control | `if ready do ... end` | Shape the enclosing word's control behavior during construction |

~~~mermaid
flowchart TD
    Template["Binding-chain template"]
    Stable["juxtaposition · stable bindings"]
    Word["Residual word or data"]
    Call["Postfix invocation"]
    Runtime["Runtime do body"]
    Template --> Stable --> Word --> Call --> Runtime
~~~

Specialization may execute when a module is initialized or while a runtime `do` body runs. “Construction” in *construction word* instead means compiler execution that shapes code. These are not the same phase.

### 1.2 Words

A **word** is a value containing:

- zero or more remaining binding stages;
- any stable state already attached by specialization;
- a terminal meaning, which is either data or executable `do` behavior;
- a phase: runtime, construction, or constraint.

A bare runtime word is a value. It does not execute:

~~~let
let callback = square
let mapped = map(values, square)
~~~

Only postfix invocation enters runtime behavior:

~~~let
let a = square(5)
let b = callback(5)
~~~

### 1.3 Values, places, and borrows

Let keeps three semantic categories distinct:

| Category | Meaning |
| --- | --- |
| Value | A scalar, aggregate, word, or owned resource that may be bound, copied when copyable, or moved |
| Place | A storage location such as a mutable binding, projected member, or indexed element |
| Borrow | Temporary access to a place; it is not independently storable or ownable |

An expression may read a place to obtain a copyable value or temporary read access. `mut place` creates temporary exclusive access. `move place` removes an owned value from the place.

---

## 2. Lexical form

### 2.1 Source text

The source encoding is UTF-8. Identifiers use ASCII letters, decimal digits, and `_`:

~~~text
NAME        := [A-Za-z_][A-Za-z0-9_]*
DECIMAL     := DIGIT { DIGIT | "_" DIGIT }
HEX         := "0x" HEXDIGIT { HEXDIGIT | "_" HEXDIGIT }
INT         := DECIMAL | HEX
FLOAT       := DECIMAL "." DIGIT { DIGIT | "_" DIGIT } [ EXPONENT ]
             | DECIMAL EXPONENT
EXPONENT    := ("e" | "E") [ "+" | "-" ] DIGIT { DIGIT | "_" DIGIT }
BOOL        := "true" | "false"
TEXT        := '"' { UTF8_CHAR | ESCAPE } '"'
~~~

Later Unicode identifier profiles may be added without changing the core semantics.

Names and keywords are case-sensitive. `Int`, `int`, and `INT` are distinct names.

`//` begins a line comment outside a string. A comment ends at newline.

All ASCII whitespace, including newlines, is ignored between tokens. Indentation and line breaks have no grammatical force. A line comment still ends at newline; whitespace inside a literal remains part of that literal's lexical rules. `;` is an explicit separator, needed only where adjacent forms would otherwise be parsed as a single expression. An underscore in an integer must occur between two digits; leading, trailing, and repeated underscores are invalid.

### 2.2 Literals

The grammar recognizes:

~~~text
true false                    Boolean
0 42 1_000                    decimal Int
0x2a 0xff                     hexadecimal Int
1.0 0.5 1_000.25 1e9 1.5e-3   Float
"text\n"                      UTF-8 text literal
{}                            empty aggregate / Unit
~~~

Underscores may occur between digits and are ignored. A Float literal has a digit on each side of its `.` and, when it carries an exponent, at least one digit after `e` or `E`; `1.` and `.5` are therefore not Float literals. `-7` is the unary `-` token applied to the literal `7`; the scanner never folds the sign into the literal token. String escapes are `\\`, `\"`, `\n`, `\r`, `\t`, and `\u{HEX}`. A Unicode escape contains one to six hexadecimal digits and must name a Unicode scalar value. An unescaped newline cannot occur inside a string.

### 2.3 Reserved spellings

The structural spellings are:

~~~text
let do end own mut move return if else while switch case and or not true false
~~~

These spellings cannot be used as binding names. `if`, `else`, `while`, `switch`, and `case` are structured control spellings in the language dictionary. They describe inline control regions rather than invoking runtime branch closures. `and`, `or`, and `not` are reserved operator spellings.

The scanner takes `//` before `/`, and takes `<=`, `>=`, `==`, and `!=` before their one-character prefixes. Whitespace may separate tokens but never changes `(` from postfix invocation into a different operator.

---

## 3. Grammar

This grammar uses `{x}` for repetition, `[x]` for an optional form, and `|` for alternatives. `SEP` is one or more semicolons. Newlines are never separators. Expressions consume the longest continuation permitted by their expression grammar; optional separators do not authorize an alternative split inside juxtaposition.

### 3.1 Program and binding chains

~~~text
program             := { SEP }
                       { top_binding { SEP } } EOF

top_binding         := "let" NAME completed_qualifiers annotation
                       binding_operator { SEP } binding_value

binding_value       := { chain_item { SEP } } terminal
chain_item          := binding_stage | prelude_binding

binding_stage       := "let" NAME stage_qualifiers annotation
prelude_binding     := "let" NAME completed_qualifiers annotation
                       binding_operator { SEP } binding_value

stage_qualifiers    := empty | "mut" | "own" | "own" "mut"
completed_qualifiers:= empty | "mut"
annotation          := empty | ":" constraint_expression
binding_operator    := "="

terminal            := do_block | transfer_value
transfer_value      := expression | "move" place

constraint_expression
                    := NAME { constraint_argument }
constraint_argument := NAME | literal | "(" constraint_expression ")"
~~~

Qualifier order is canonical: `own mut`. `mut own` is invalid. An initialized binding cannot carry `own`; its initializer already supplies the value owned by the new binding.

A chain item without `=` is an unsatisfied stage. A completed binding inside a chain is a prelude binding. There is no `let ... end` construct.

The right-hand side ends when its terminal form ends. `do ... end` and `{ ... }` are explicitly delimited. A simple terminal expression ends at a comma, closing delimiter, semicolon, or a structural keyword that cannot continue that expression. A following assignment place and `=` also establish a statement boundary. No separator is required between ordinary binding stages or before `do`. If a constraint application and a data terminal would run together, use `;` to delimit them.

### 3.2 Runtime bodies

~~~text
do_block            := "do" { SEP }
                       { statement { SEP } }
                       "end"

statement           := local_binding
                     | assignment
                     | return_statement
                     | if_form
                     | while_form
                     | switch_form
                     | expression

local_binding       := "let" NAME completed_qualifiers annotation
                       binding_operator { SEP } binding_value

assignment          := place "=" { SEP } binding_value
return_statement    := "return" [ binding_value ]

region              := { SEP } { statement { SEP } }
if_form             := "if" expression "do" region
                       { "else" "if" expression "do" region }
                       [ "else" region ] "end"
while_form          := "while" expression do_block
switch_form         := "switch" expression "do" { SEP }
                       case_arm { case_arm } [ "else" region ] "end"
case_arm            := "case" case_label { "," case_label } region
case_label          := BOOL | [ "-" ] INT
~~~

Inside a runtime body, an uninitialized `let name` is invalid. Unsatisfied stages occur only while constructing a binding-chain value.

One `end` closes an entire `if`/`else if`/`else` chain. Each `else if` has a condition followed by `do`; plain `else` starts its arm directly. Nested `if` forms have their own `end`. Line placement is irrelevant. Control arms introduce lexical scopes but not runtime invocation boundaries: `return` exits the enclosing invocation.

Structured control keeps its familiar spelling; it need not be expressed as runtime application of branch closures. Continuation words are the ordinary interface for alternative outcomes, not mandatory plumbing for every statement.

Juxtaposition takes precedence over splitting adjacent expressions. Write `f(x); g(y)` for two expression statements: `f(x) g(y)` is one specialization expression, even across a newline. Likewise, `let x = make(); observe(x)` needs `;`, whereas `let x = make() return x` does not. Assignment lookahead recognizes `place =` as the start of a new statement, not a specialization argument. Bare `return` must end at `;`, `end`, `else`, or `case`; write `return {}` when an explicit Unit result makes the boundary clearer.

### 3.3 Aggregates

~~~text
aggregate_literal   := named_aggregate
                     | positional_aggregate
                     | empty_aggregate

empty_aggregate     := "{" { SEP } "}"

named_aggregate     := "{" { SEP }
                       named_member { { SEP } named_member } { SEP }
                       "}"
named_member        := "let" NAME completed_qualifiers annotation
                       binding_operator { SEP } binding_value

positional_aggregate:= "{" binding_value
                       { "," binding_value } [ "," ] "}"
~~~

A non-empty aggregate is either entirely named or entirely positional. The forms cannot mix.

### 3.4 Expressions and precedence

Precedence from highest to lowest is:

| Level | Form | Associativity |
| ---: | --- | --- |
| 1 | postfix `value.name`, `value[index]`, `word(args...)` | left |
| 2 | specialization by juxtaposition | left |
| 3 | prefix `not`, unary `-` | right |
| 4 | `* / %` | left |
| 5 | `+ -` | left |
| 6 | `< <= > >=` | non-associative |
| 7 | `== !=` | non-associative |
| 8 | `and` | left, short-circuiting |
| 9 | `or` | left, short-circuiting |

Postfix invocation is recognized regardless of whitespace. `f(x)` and `f (x)` are identical. Prefix parentheses group an expression.

~~~text
expression           := or_expression
or_expression        := and_expression { "or" and_expression }
and_expression       := equality_expression { "and" equality_expression }
equality_expression  := comparison_expression
                        [ ("==" | "!=") comparison_expression ]
comparison_expression
                     := additive_expression
                        [ ("<" | "<=" | ">" | ">=")
                          additive_expression ]
additive_expression  := multiplicative_expression
                        { ("+" | "-") multiplicative_expression }
multiplicative_expression
                     := prefix_expression
                        { ("*" | "/" | "%") prefix_expression }

prefix_expression    := ("not" | "-") prefix_expression
                     | specialization
specialization       := postfix_expression
                        { specialization_argument }
postfix_expression   := primary { postfix_suffix }
primary              := literal
                     | NAME
                     | "(" expression ")"
                     | aggregate_literal

postfix_suffix       := "." NAME
                     | "[" expression "]"
                     | "(" [ call_argument { "," call_argument } ] ")"

call_argument        := binding_value | "mut" place
place               := NAME { "." NAME | "[" expression "]" }
specialization_argument
                    := specialization_atom
                     | "move" place

specialization_atom := literal
                     | NAME { postfix_suffix }
                     | aggregate_literal

literal              := BOOL | INT | FLOAT | TEXT
~~~

Specialization arguments are intentionally restricted.

An arbitrary compound expression cannot be a juxtaposed argument. Bind it first:

~~~let
let next_quality = quality + 1
let configured = encoder JPEG next_quality
~~~

For the same unambiguous rule, `f -7` is subtraction, not specialization by a negative literal. Bind the negative value first when it is meant to become stable state.

An invocation such as `current_format()` is a valid specialization atom. `mut place` is never a specialization argument because a mutable borrow cannot become persistent state.

Canonical parses are:

| Source | Parse |
| --- | --- |
| `f x + y` | `(f x) + y` |
| `f(x) y` | `(f(x)) y` |
| `f x(y)` | `f (x(y))` |
| `f (x)` | `f(x)`; whitespace never changes postfix invocation |
| `-f x` | `-(f x)` |
| `f - 7` | `f - 7` |

Assignment is a statement, not an expression. Chained comparisons and chained assignment are invalid.

### 3.5 Binding, specialization, and invocation surface

`=` completes a binding. Juxtaposition specializes a word. Postfix `()` invokes runtime behavior:

~~~let
let jpeg = encoder JPEG 90
let client = http base_url auth

let encoded = jpeg(frame)
~~~

The forms have these exact meanings:

| Surface | Meaning |
| --- | --- |
| `let x = value` | Completed binding |
| `word a b` | Supply two stable stages |
| `word(args)` | Transiently saturate and invoke |

Each juxtaposed argument supplies one stage and obeys the atom/move restrictions above. Assignment remains `place = value`; its statement form is distinct from a `let` binding.

There is one specialization spelling: juxtaposition. `with` is not a keyword or operator.

The explanatory surface is therefore: `=` says what a binding **is**; juxtaposition supplies stable stages; `()` makes a word **do**. Specialization never implicitly enters a runtime terminal, even when all stages have been supplied.

---

## 4. Names, scopes, and evaluation order

### 4.1 Lexical scope

Names are resolved lexically. A binding becomes visible after its initializer completes. Its initializer therefore sees any outer binding with the same name, not the binding being initialized.

Shadowing is permitted in a nested scope. Defining the same name twice in one scope is an error.

A control `do` region creates a nested lexical scope. Its names disappear when the region exits. An executable-value `do` additionally creates a runtime invocation scope when called.

### 4.2 Top-level order and recursion

Top-level bindings are constructed in source order. A name declared later is not visible earlier.

The name of a runtime word is visible inside its terminal `do` body, allowing direct recursion:

~~~let
let factorial =
    let n
    do
        if n <= 1 do
            return 1
        end
        return n * factorial(n - 1)
    end
~~~

The self name must not be read by its own initializer or specialization prelude before construction completes. Forward declarations for directly named mutual recursion are deferred; continuation arguments may establish indirect recursive cycles.

### 4.3 Evaluation order

Let evaluates observable source operations left to right.

- operator operands are evaluated left to right;
- projection evaluates its base first;
- indexing evaluates its base, then index;
- aggregate members/elements initialize in source order;
- specialization evaluates the word, then each argument from left to right;
- invocation evaluates the callee, then binds arguments from left to right as described in §6;
- assignment evaluates the destination place, then the right-hand side, then performs replacement;
- `and` and `or` short-circuit.

The compiler may fold, eliminate, or reorder only when the resulting behavior is observationally equivalent, including effects, traps, ownership transfer, and destruction order.

There is no implicit truthiness. Conditions consumed by `if`, `while`, `and`, `or`, and `not` must satisfy `Bool`.

---

## 5. Binding chains and specialization

### 5.1 Binding-chain state

A binding chain is an ordered sequence of:

- unsatisfied stages;
- completed prelude bindings;
- one terminal data expression, aggregate, or `do` body.

~~~mermaid
flowchart TD
    Stage["Next unsatisfied let stage"]
    Bind["Bind one supplied value"]
    Prelude["Run newly reached prelude"]
    Next{"Next item"}
    Residual["Residual word"]
    Data["Completed data"]
    Stage --> Bind --> Prelude --> Next
    Next -- stage --> Stage
    Next -- runtime do --> Residual
    Next -- data terminal --> Data
~~~

Supplying a stage advances through consecutive completed bindings until the next stage or terminal is reached. Each reached prelude initializer runs exactly once, in source order, for that specialization instance.

An initial prelude before the first stage runs when the outer binding is constructed. A prelude between two stages runs after all stages before it have been supplied.

### 5.2 Juxtaposition

Juxtaposition supplies stable bindings without entering a terminal `do`:

~~~let
let add =
    let x
    let y
    do
        return x + y
    end

let add10 = add 10
let computation = add 10 20
~~~

`add10` still awaits `y`. `computation` is a saturated zero-input runtime word. Neither has executed the body.

Each specialization constructs a new semantic result. In particular, mutable prelude state is never shared between two specialization results unless the program explicitly supplied a shared handle. An implementation may deduplicate a pure stateless representation only when no Let observation, ownership action, or destruction can distinguish it.

The receiver follows these ownership rules:

| Receiver | Specialization |
| --- | --- |
| Copy word | Copy its stable values into the new result; leave the original unchanged |
| Fresh non-copyable word | Transfer its state into the new result |
| Existing non-copyable word | Requires explicit vocabulary producing an independent copy first |

Specialization must not implicitly consume an existing receiver, share its private mutable state, clone opaque owned resources, or replay already reached preludes. For example, `clone_word(existing) argument` is valid when the declared vocabulary explicitly constructs a fresh independent word. No general clone operation is implied.

If a chain reaches a data terminal, specialization returns that data immediately:

~~~let
let pair =
    let left
    let right
    { left, right }

let p = pair 10 20
~~~

If another specialization argument remains after a data terminal is produced, normal specialization lookup applies to the produced value. It is an error unless that value is itself a word with a remaining stage.

If a runtime `do` terminal is reached while specialization arguments remain, specialization is oversaturated and is an error. The `do` body is never invoked implicitly to consume the excess.

### 5.3 Capability matching during specialization

| Next stage | Legal persistent argument |
| --- | --- |
| `let x` | A copyable stable value |
| `let x mut` | None |
| `let x own` | `move place` or a fresh owned value |
| `let x own mut` | `move place` or a fresh owned value; the residual binding is writable |

A read-only borrow cannot silently become persistent state. Non-copyable state must enter a persistent residual through an `own` stage and visible movement.

### 5.4 Prelude semantics

~~~let
let counter =
    let start
    let value mut = start
    do
        value = value + 1
        return value
    end

let errors = counter 0
let requests = counter 100
~~~

Binding `start` reaches and runs `let value mut = start`. `errors` and `requests` therefore own distinct `value` places. Their terminal bodies remain uninvoked.

A prelude binding inherits the lifetime of the binding operation that reached it:

- reached by top-level or local construction, it belongs to that constructed word;
- reached by juxtaposition, it belongs to the residual specialized word;
- reached while transiently saturating an invocation, it is an invocation local and is destroyed when that invocation exits.

A prelude initializer may contain an explicit invocation, allocation, mutation of already-owned construction state, or host effect. Such effects occur when that prelude is reached. The compiler must not perform them early merely because surrounding values are known. An unrecoverable trap follows §14.2; a recoverable alternative must be represented explicitly with values or continuations.

Prelude state is private to the residual word unless the chain terminates in a named aggregate that exposes selected bindings.

A prelude initializer constructs one value and must complete locally. It contains no statement-level `return`, `if`, or `while` escape. Recoverable branching away from construction belongs in an invoked runtime word and its ordinary continuation protocol.

---

## 6. Runtime invocation

### 6.1 Saturation rule

`callee(args...)` is valid only when the arguments satisfy exactly all remaining stages and the resulting terminal is runtime `do` behavior.

- Too few arguments: undersaturated invocation error.
- Too many arguments: oversaturated invocation error.
- Saturated data terminal: non-executable invocation error.
- Saturated runtime word: enter its `do` body.

Use juxtaposition when a persistent partial result is intended.

### 6.2 Argument and prelude order

Invocation preserves the currying semantics rather than evaluating all arguments first. It proceeds as follows:

~~~text
evaluate callee
for each argument from left to right:
    evaluate that argument
    bind exactly one remaining stage
    run every prelude binding newly reached by that stage
after the final stage:
    require a runtime-do terminal
    enter it
~~~

Consequently:

~~~text
f(a, b) ≡ transiently bind a, then bind b, then invoke
~~~

It has the same stage order as immediately constructing and invoking `(f a b)()`, while avoiding a separately persistent residual binding.

Prelude effects reached after `a` occur before evaluation of `b`. This is the precise observable consequence of treating invocation as transient saturation of the same binding chain.

### 6.3 Transient capability matching

| Stage | Invocation argument | Callee access |
| --- | --- | --- |
| `let x` | `value` or `place` | Copy when copyable; otherwise read-only borrow for the invocation |
| `let x mut` | `mut place` | Exclusive mutable borrow for the invocation |
| `let x own` | `move place` or fresh owned value | Callee owns the value |
| `let x own mut` | `move place` or fresh owned value | Callee owns a writable place containing the value |

An invocation may bind a fresh owned temporary directly without redundant `move` syntax because no earlier owner exists.

### 6.4 Return

`return expression` evaluates its expression, preserves the result, destroys remaining owned locals in reverse initialization order, and exits the current runtime invocation.

Returning an existing non-copyable owned binding requires `move`:

~~~let
return move result
~~~

A copyable result is copied. A fresh result is transferred directly. Bare `return` and falling through the end of a runtime body both return Unit.

A `return` inside an inline `if`, `while`, or `switch` region exits the enclosing runtime invocation, not merely that textual region.

### 6.5 Proper tail invocation

An invocation directly returned is a proper tail transfer:

~~~let
return next(value)
~~~

A proper tail invocation evaluates and preserves the callee and arguments, transfers any moved ownership, destroys the current invocation's remaining owned locals, and enters `next` without adding another return continuation. This has observable bounded-stack behavior.

The callee and every borrowed argument of a tail invocation must outlive the current activation's cleanup. Copy values and moved owned arguments are safe; a borrow derived from a local that cleanup would destroy is not. Such a direct-return call is an ownership error rather than silently becoming a non-tail call.

---

## 7. Executable bodies and control construction

### 7.1 Two uses of `do`

`do ... end` is the only source form containing runtime statements.

In a binding terminal, it creates an executable word value:

~~~let
let hello = do
    print("hello")
end
~~~

Following a construction word, it is an inline control region:

~~~let
if ready do
    start()
end
~~~

An inline region has lexical scope but no independent invocation or captured-word value.

A complete binding chain is also a value in a delimited argument position, so runtime higher-order code needs no lambda syntax:

~~~let
map(values,
    let value : Int
    do
        return value * value
    end
)
~~~

This constructs and passes an ordinary executable word. It is different from a construction word: `map` receives a runtime value and decides when to invoke it.

### 7.2 Structured control

The language dictionary supplies these control forms:

~~~text
if      ordered Bool conditions, one selected arm, optional else
else    starts an alternative arm in if or switch
while   one runtime Bool expression + one do region
switch  one evaluated subject + case arms + optional else
case    one or more literal labels + one inline arm
~~~

The compiler executes the construction word while building the enclosing runtime body. The condition and controlled operations remain runtime code.

~~~let
if condition do
    yes()
else
    no()
end
~~~

~~~let
while condition do
    body()
end
~~~

`while` places condition evaluation at the loop head, so it executes before every iteration. No predicate closure is created.

`switch` evaluates its subject exactly once, then executes the arm with an equal label. Labels are Int or Bool literals, including signed integer literals; all labels and the subject must have the same type. Duplicate labels are errors, including numerically equal spellings such as `1` and `0x1`. Case labels are not effectful expressions or patterns.

~~~let
switch code do
case 0
    success()
case 1, 2
    retry()
else
    failure(code)
end
~~~

There is no fallthrough: normal arm completion continues after the switch. With no matching label and no `else`, execution continues after the switch without entering an arm. Covering both Bool values is exhaustive. Each arm has its own lexical scope and follows the ordinary move, borrow, destruction, and enclosing-return rules. Match and pattern captures are deferred, not approximated by case labels.

User-defined source syntax for construction words is deferred. Hosts may register additional construction words with the syntax and construction behavior described in §12. They shape the enclosing word's control behavior without introducing an AST macro language.

### 7.3 Expression statements

An expression may appear as a statement. Its value is discarded after evaluation. Pure discarded expressions may be diagnosed or eliminated; their effects, traps, moves, and required destruction remain observable.

The designs of `break`, `continue`, matching, and pattern captures are deferred. Let has no exception channel (§14).

---

## 8. Aggregates, projection, and indexing

### 8.1 Named aggregates

~~~let
let point = {
    let x = 10
    let y = 20
}
~~~

Named members initialize from top to bottom. A member becomes visible to later member initializers after it completes. Member names are unique.

A named aggregate exposes exactly its direct named members through static projection. Prelude/captured implementation state of a word is not exposed automatically.

### 8.2 Positional aggregates

~~~let
let rgb = { 255, 128, 32 }
~~~

Positional elements initialize left to right and use zero-based indexing. `{}` is the unique empty aggregate and the Unit value.

### 8.3 Static projection

`.` selects a statically known named member and never invokes it:

~~~let
service.start       // word value
service.start()     // projection, then invocation
~~~

Projection has no implicit receiver, getter, dynamic lookup, or method dispatch. If a projected word uses containing state, that relationship comes from lexical capture.

Projection of a mutable member produces a place when the current access path permits mutation. Projection of a value member produces a value or read-only view according to its copyability.

A named member declared `mut` is an explicit interior mutable place and may remain writable through its owning aggregate binding even when that outer binding is not itself `mut`. A read-only borrow of the aggregate narrows the whole borrowed path and does not grant that write access.

### 8.4 Positional indexing

`base[index]` evaluates `base`, then `index`. The index must be a non-negative Int less than the known runtime length. An out-of-range index traps. Libraries may provide continuation-based checked lookup.

Indexing a mutable positional place yields a mutable element place. Indexing a read-only value yields a value or read-only view.

Positional elements have no individual declaration qualifier, so their write capability comes from the base place, for example `let values mut = { 10, 20, 30 }`.

`[]` cannot be overloaded and is not dynamic named lookup. Dynamic maps use explicit vocabulary such as `map.get` and `map.set`.

### 8.5 Aggregate ownership and destruction

An aggregate owns every owned member or element supplied during its construction. Moving the aggregate moves those resources together. Destroying it destroys owned contents in reverse initialization order.

An aggregate is Copy exactly when every contained value is Copy and it contains no declared mutable member. Otherwise it is non-copyable unless explicit vocabulary constructs an independent copy.

Named and positional aggregates have no mandatory header, hash table, metatable, method table, reference count, or GC metadata.

---

## 9. Ownership, borrowing, and mutation

### 9.1 One rule

Every non-copyable value has exactly one owner. The ownership checker is a frontend rule; it does not require reference counts, tracing, hidden retain/release traffic, or runtime borrow objects.

A value's vocabulary declares whether it is **Copy**. `Bool`, `Int`, Unit, and immutable text literals are Copy. A value containing owned state is non-copyable unless its vocabulary explicitly defines a real copy operation.

### 9.2 Bindings and capabilities

The qualifier belongs to the binding stage or place, not to the value's call-site spelling:

| Binding form | Meaning |
| --- | --- |
| `let x` | Read access; a completed local binding is immutable |
| `let x mut` | Exclusive writable place |
| `let x own` | Callee or residual word receives ownership |
| `let x own mut` | Callee or residual word receives ownership in a writable place |

`own` is meaningful only on an unsatisfied stage. A completed initializer already establishes the new binding as owner of a fresh or transferred non-copyable result.

Immutability forbids assignment and mutation through that binding; it does not forbid transferring an owned value with `move`.

The qualifier is an interface contract, not an inferred summary. A word body may use no stronger capability than the stage declares: a plain stage cannot mutate or consume its argument, and a `mut` stage cannot retain or consume the borrowed owner.

For a completed binding `let y = rhs`:

- a Copy result is copied into `y`;
- a fresh non-copyable result is installed directly in `y`;
- an existing non-copyable place must be written `move place`;
- after a move, the source place is uninitialized until explicitly assigned a new value.

Here **fresh** means a newly produced non-copyable result with no pre-existing source place and exactly one consuming destination in the expression. Freshness is established by the ownership checker, not by a runtime flag.

`move` names the removal of an owned value. A Copy value owns no state to remove, so `move place` for a Copy place is that value, copied: the place stays initialized, nothing is transferred, and the result is indistinguishable from reading the place. `move` is therefore required for an existing non-copyable place and optional everywhere else.

Reading, moving, or destroying an uninitialized place is a compile-time error.

`move place` may name a subplace as well as a whole binding. Moving out of a projected member or a constant positional index leaves that subplace uninitialized and makes the containing aggregate **partially initialized**. The value that was moved is owned by whatever receives it, exactly as for a whole move (§6.3), and the subplace must be assigned a new value before it is read, moved, or destroyed again.

A partially initialized aggregate is not a value. It may not be moved, and no subplace that contains the hole may be read or moved as a value, because either would carry a subplace that has no value. Reading *through* such a subplace to a different one is allowed, since that never touches the hole. Assigning the hole a new value, or assigning the whole aggregate, makes the place whole again. Destroying a partially initialized aggregate releases only the subplaces that are still initialized, in reverse initialization order.

The path must be statically known. An index computed at run time does not name a place that can be partially moved, because which subplace became uninitialized would not be known; a partially moved aggregate is otherwise still a statically resolved value (§11.3).

### 9.3 Call-site operations

The three call-site forms have exact meanings:

| Form | Meaning |
| --- | --- |
| `x` | Copy `x` when Copy; otherwise lend read access for this invocation |
| `mut x` | Lend exclusive write access for this invocation |
| `move x` | Transfer ownership out of `x` |

`mut` never means “copy back later.” The callee operates on the caller's place. A mutable borrow begins after that argument is evaluated and ends when the invocation returns or tail-transfers. During that interval there may be no other access through the owner or an alias, except a shorter reborrow derived from the same mutable borrow.

Read borrows may overlap other read borrows. They may not overlap a mutable borrow. Borrows are not first-class values: they cannot be stored in an aggregate, returned, placed in persistent specialization state, or retained by an escaping word.

An owner cannot be moved, replaced, or destroyed while any borrow derived from it is active. The same restriction applies to overlapping projected or indexed subplaces. Distinct named members and distinct compile-time indices are disjoint; runtime indices are treated as possibly equal. No general alias-analysis subsystem is required.

### 9.4 Assignment

Assignment requires a writable destination place:

~~~let
count = count + 1
buffer[index] = byte
~~~

Assignment first evaluates the destination base and any indices from left to right, establishing the place without replacing it. It then evaluates the right-hand side. If that completes and the destination still contains its old value, that value is destroyed; the new value is then installed. If the right-hand side itself moved from the destination, there is no old value left to destroy. If right-hand-side evaluation traps before such a move, replacement has not occurred. Assignment of an existing non-copyable value requires `move`.

Merely establishing the destination does not start a conflicting mutable borrow, so `x = x + 1` is legal. The write occurs only at the replacement step.

Assignment does not produce a value. Assigning through a read-only binding, through an active conflicting borrow, or to an uninitialized aggregate path is an error.

### 9.5 Destruction

Owned values are destroyed deterministically in reverse successful-initialization order:

- when a lexical scope exits normally;
- before its invocation returns;
- when assignment replaces an old owned value;
- when an explicit recoverable control path leaves partially constructed state.

A moved value is no longer destroyed at its old place. A returned or otherwise transferred value is preserved while the remaining locals are destroyed.

Destructors must complete: they cannot trap, suspend, or re-enter Let control. Their concrete work is vocabulary-defined. Pure scalars have no destructor.


### 9.6 Control-flow ownership state

At a join, a source place is usable only if it is initialized and owned by that place on every incoming path. If one path moved it and another did not, later use is rejected unless the moved path explicitly reinitializes it before the join.

Owned locals created only inside a branch or loop iteration are destroyed on every normal exit from that lexical scope. Current values of outer mutable locals are the values established by the selected path or completed loop iteration.

### 9.7 Cycles

The ownership graph must be acyclic. Cyclic structures use explicit indices, handles, or an arena supplied by a library or host. The core language does not silently add garbage collection to make cycles legal.

---

## 10. Capture and stateful words

### 10.1 Lexical capture

A word body may refer to lexically enclosing bindings without a capture list. It captures exactly the referenced bindings, not an entire scope.

Capture follows the same operations as an ordinary binding:

| Captured source | Non-escaping word | Escaping word |
| --- | --- | --- |
| Copy value | Copy | Copy |
| Immutable non-copyable owner | Read borrow | Rejected unless ownership is explicitly transferred into stable state |
| Mutable place | Mutable or read borrow, according to use | Rejected |
| State created by the word's own prelude | Owned by that residual word | Owned by that residual word |

A word **escapes** a scope if it is returned, moved into longer-lived state, or passed to an ownership-taking stage whose result may outlive the scope. Borrowed captures cannot cross that boundary.

This is an ownership check, not a mandatory heap-allocation rule. A non-escaping captured word may remain entirely lexical. An escaping stateful word owns only the state that actually entered it.

### 10.2 The normal stateful-word form

Specialization preludes are the direct way to create private owned state:

~~~let
let counter =
    let start
    let value mut = start
    do
        value = value + 1
        return value
    end

let requests = counter 0
~~~

`value` is initialized once when `start` is supplied, then belongs to `requests`. No closure-conversion syntax, environment object, retain operation, or receiver parameter is visible in the language.

### 10.3 Projected executable members

If a named aggregate exposes a word that refers to sibling private state, projection returns a word view tied to that aggregate owner. The view may be invoked while the owner lives. It cannot be moved out and outlive the owner unless it was independently constructed with its own owned state.

Moving the aggregate moves the owner and its state together. Destroying it invalidates its borrowed word views and destroys its owned members in the order defined by §8.5.

A stateless word or a word containing only Copy stable values is Copy. A word containing owned or mutable state is non-copyable unless its vocabulary defines an explicit independent copy operation.

### 10.4 Representation independence

Any representation of captured state must preserve the rules above. Let does not require a universal closure header or a single runtime closure layout.

---

## 11. Constraints: typing by words

### 11.1 Constraint phase

A constraint is a word in the **constraint phase**. An annotation applies such a word to the semantic description of a binding:

~~~let
let add =
    let x : Int
    let y : Int
    do
        return x + y
    end
~~~

Constraint expressions use the same stable-specialization idea as ordinary words:

~~~text
constraint_expression := NAME { specialization_argument }
~~~

They are evaluated by the frontend, never invoked as runtime code merely because they appear after `:`.

### 11.2 What a constraint proves

A constraint may inspect the frontend-known semantic shape of a value and either accept it or issue a construction diagnostic. It may constrain representation, available vocabulary, Copy status, aggregate members, or executable stages. It does not by itself create a runtime tag, object header, vtable, or dynamic test.

The language dictionary includes these constraints:

| Constraint | Accepted meaning |
| --- | --- |
| `Bool` | Boolean |
| `Int` | Signed 64-bit integer |
| `Unit` | Empty aggregate `{}` |
| `Text` | Immutable UTF-8 text value |
| `Copy` | A value that may be duplicated with its defined value semantics |
| `Executable` | A word whose eventual terminal is runtime `do` |

`Executable` alone does not promise a particular remaining-stage count or result. An invocation imposes those additional structural requirements, which must be resolved statically for the concrete word use.

An executable word has no implicit Bool, Int, Text, address, or display value. It can be stored, specialized, passed, projected, moved when stateful, and invoked; any other observation requires explicit vocabulary.

Named shape constraints are structural: required member names and their nested constraints must be present; additional members are allowed. Positional shape constraints require the declared arity. A later library may provide the surface vocabulary for constructing such constraints.

### 11.3 Static boundary

Every concrete operation must have a statically resolved representation and primitive meaning. Annotations and vocabulary choices that determine those meanings are settled before runtime execution. If a required constraint cannot be proved, the program has a compile-time error.

Unannotated bindings are legal when their meaning follows from the initializer and uses. Let does not require nominal class declarations or a universal type-inference subsystem. Generic behavior is expressed by words whose constraints accept more than one semantic shape; each concrete specialization or invocation must satisfy its applicable constraints statically. This does not introduce an implicit runtime type-dispatch layer.

Constraints are erased by default after they have done this work. A runtime predicate or tag test exists only when the program explicitly asks for runtime vocabulary that performs one.

An explicit tagged runtime representation may be supplied by vocabulary. It is not an implicit tag added to every Let value.

---

## 12. Dictionary entries and construction words

### 12.1 One dictionary, phased entries

Names ultimately resolve to lexical bindings or dictionary entries. A dictionary entry declares:

- its name;
- its phase: runtime, construction, or constraint;
- its ordered binding stages, with qualifiers and optional constraints;
- its terminal meaning: data, runtime `do`, construction behavior, or constraint behavior;
- whether its behavior is `pure` or `ordered`.

These are semantic properties, not a prescribed record layout or registration API.

The phase is part of the entry. A construction or constraint word cannot accidentally be retained as a runtime call, and a runtime word cannot execute inside the frontend merely because its arguments happen to be known.

### 12.2 Purity is deliberately small

Let uses one operational distinction:

| Purity | Promise |
| --- | --- |
| `pure` | No observable effect, mutation, ownership release, host interaction, or trap; safe to omit when its result is not demanded |
| `ordered` | Must remain in source-observable order even when its result is unused |

This is not a source-level effect system. It is a vocabulary promise governing observable behavior. An implementation may internally know more, but it must not weaken observable ordering.

Evaluating, omitting, or simplifying pure operations must preserve their specified results. Ordered vocabulary remains in the dynamic context where the source placed it. A specialization prelude controls *when* its ordered operations occur; it does not give the compiler permission to perform runtime effects during compilation. Known arguments do not change a word's declared phase.

### 12.3 Construction descriptor

A construction word declares which expressions and `do` regions its source form accepts, and how those pieces determine the enclosing word's control behavior. It does not introduce a second runtime meaning.

| Property | Meaning |
| --- | --- |
| Name | The construction-word spelling |
| Expression slots | The source expressions accepted by the form |
| Region slots | The inline `do` regions accepted by the form |
| Construction behavior | How those expressions and regions shape the enclosing word |

The control forms have these meanings:

- `if` evaluates its Bool condition and executes the corresponding region. A false condition with no `else` executes neither region. Normal completion continues after the form.
- `while` evaluates its Bool condition before every iteration. A true condition executes the body and repeats; a false condition continues after the form.
- `switch` evaluates its subject once and selects one case arm or its default; no arm falls through into another.

Construction does not execute the conditions or controlled runtime effects. The regions remain inline in the enclosing invocation, with the scope, return, and ownership rules already specified.

Hosts may register another descriptor. Source syntax for defining a construction word in Let itself is deferred; construction must not become a hidden textual macro language.

---

## 13. Scalar semantics

### 13.1 Unit and Bool

`{}` is the single Unit value. `true` and `false` are the only Bool values. Boolean operations accept Bool and return Bool:

~~~text
not x
x and y       // short-circuit
x or y        // short-circuit
~~~

### 13.2 Int

`Int` is a signed 64-bit two's-complement value. Decimal and hexadecimal literals must fit its range after applying their literal sign; otherwise the frontend reports an error.

Unary `-` and the five arithmetic operators accept only Int operands and return Int. Relational operators accept two Int values and return Bool.

Arithmetic is defined exactly:

| Operation | Result |
| --- | --- |
| `+`, `-`, `*`, unary `-` | Low 64 bits; two's-complement wraparound |
| `/` | Signed quotient truncated toward zero |
| `%` | Signed remainder with the dividend's sign |

Division or remainder by zero traps. `INT_MIN / -1` wraps to `INT_MIN`; `INT_MIN % -1` is zero. Signed comparisons implement `<`, `<=`, `>`, and `>=`.

There are no implicit numeric conversions or promotion rules. Additional numeric vocabularies use distinct constraints and explicit conversion words.

### 13.3 Float

`Float` is an IEEE 754 binary64 value. A Float literal is correctly rounded to nearest, ties to
even by the embedding's decimal conversion; hexadecimal floating literals are not part of the
source. Division by zero does not trap: it produces the IEEE infinity or NaN the operation
defines. A NaN is unequal to every value including itself, and every ordered comparison
involving a NaN is false. Positive and negative zero compare equal.

Unary `-` and the four arithmetic operators `+`, `-`, `*`, and `/` accept only Float operands
and return Float. `%` is not defined for Float. Relational operators accept two Float values
and return Bool. There are no implicit conversions between Int and Float. The core provides
two conversion words. `float x` converts an Int to the Float nearest to it, rounding to
nearest, ties to even, and is total. `int x` converts a Float to an Int by truncating toward
zero; a NaN converts to zero, and a value at or beyond an Int bound converts to that bound.
Both are pure, take one argument, and are ordinary names a lexical binding or host may
shadow. Other numeric vocabularies convert with explicit vocabulary (§13.2, §13.6).

### 13.4 Equality

`==` and `!=` are defined for Unit, Bool, Int, Float, and Text. Both operands must have the same semantic kind. Unit values are always equal; Bool, Int, and Float compare by value, with Float following §13.3; Text compares its UTF-8 byte sequence.

Aggregate, word, handle, and owned-resource equality is not implicit. A vocabulary may provide an explicit pure or ordered equality word for such a value.

### 13.5 Text

A Text literal denotes an immutable, module-lifetime UTF-8 byte sequence with a known byte length. It is Copy; this does not require copying its bytes on every binding. Dynamically allocated or host-owned strings use a separately declared vocabulary and ownership contract. The core specifies no concatenation, Unicode indexing, normalization, formatting, or allocation policy.

### 13.6 Primitive spelling

The operator spellings in §3.4 resolve to language dictionary entries. They are not user-overloadable. Host I/O, allocation, buffers, arenas, and opaque handles are ordinary named vocabulary with explicit constraints, ownership behavior, and purity metadata.

---

## 14. Failure, traps, and continuations

### 14.1 Recoverable failure is ordinary control

Let has no language exception channel. A recoverable operation accepts or returns ordinary words or data that describe both continuations:

~~~let
let checked_divide =
    let ok
    let fail
    let numerator : Int
    let denominator : Int
    do
        if denominator == 0 do
            return fail("division by zero")
        end
        return ok(numerator / denominator)
    end

let divide_for_cli = checked_divide print_value print_error
~~~

`ok` and `fail` are stable policy in `divide_for_cli`; its two numeric stages remain transient invocation inputs. They are ordinary values, invocation remains explicit, and proper tail transfer prevents a growing call stack. A library may instead return a named aggregate or tagged value; neither representation is privileged by the language.

### 14.2 Traps

A trap is reserved for an operation whose contract was violated and for which the program did not request a recoverable form. Traps include:

- division or remainder by zero;
- positional indexing outside the valid range;
- an explicitly trapping host operation;
- a corrupted or unsupported external value detected by a host binding.

A trap immediately leaves Let execution through the embedding host's trap hook. Let code cannot catch or resume it, and normal Let destructors are not run after the trap. No exception object or stack-unwinding mechanism is implied. A host may terminate the Let execution context or process and reclaim its storage as one unit. An operation that must recover, release selected resources, or continue execution must expose that outcome through ordinary values or continuation words instead of trapping.

Compile-time syntax, name, constraint, phase, ownership, and saturation failures are diagnostics, not runtime traps.

---

## 15. Programs, modules, and embedding

### 15.1 Module construction

A source file constructs one module namespace. Its top-level bindings are evaluated in source order during module initialization. Their runtime effects occur at initialization, not during compilation. The file does not run an implicit `main`; an embedding host selects and invokes an exported top-level word after initialization completes.

All top-level names are visible through the module namespace. A later module system may add explicit export control without changing binding semantics.

Top-level data and specialized words live until module unload. Their owned state is destroyed in reverse successful-construction order when the host unloads the module.

A module's namespace may hold words. Each is a **host entry point**: invoking one supplies the stages the word still needs, and the entry runs whatever preludes lie between those stages, since the host supplies stages rather than the values a call site would have computed. The word's own fields -- the state it already carries, which is the construction it has been through -- come from the namespace the initializer returned.

A word whose remaining stage has no type of its own -- an unannotated stage, or one constrained only by `Copy` -- has no entry point, because there is no signature for the host to satisfy. The word remains legal; it is simply not callable from outside.

### 15.2 File chains and imports

A source file **is** a binding chain. Its top-level `let` forms are that chain's items and its namespace is that chain's terminal:

| Chain part | File meaning |
| --- | --- |
| unsatisfied stage (`let x`, `let x mut`, `let x own`) | an input the file's namespace is constructed from |
| completed prelude (`let x = …`) | initialization, evaluated in source order |
| terminal | the module namespace |

A file with no written terminal exposes the named aggregate of its own prelude bindings, in source order; that is the namespace of §15.1. A written terminal replaces it, which is how a file chooses its export surface:

~~~let
let internal = load_key()
{ let open = open_with(internal)
  let close = close_with(internal) }
~~~

Because juxtaposition takes precedence over splitting adjacent expressions (§3.2), a written terminal that follows a prelude needs `;` after that prelude's value.

`import` is a dictionary entry in the **construction** phase (§12.1), not a reserved spelling, so a lexical binding of that name still wins. Its one expression slot is the file path, which must be a constant `Text`; where that path is looked up is an embedding decision, not a language rule. Importing constructs the named file's chain **at the import site**:

- The file's stages are supplied by the specialization arguments that follow, so a configurable file is an ordinary word: `import "codec.let" JPEG 90`.
- The file's preludes are evaluated there, in source order, which is when their runtime effects occur (§15.1).
- The result is the file's terminal: its namespace aggregate for a data terminal, or an executable word for a `do` terminal, which the importer invokes explicitly with `()`.

Each `import` is its own specialization, so §5.2 applies unchanged: **two imports of the same file are two independent instances**, with independent state, and importing a file twice evaluates its initialization twice. Sharing is explicit — bind the namespace once and pass that binding.

The namespace is an ordinary value:

- it is projected and invoked like any other aggregate (§8.3, §6);
- a member declared `mut` is writable through the owning binding (§8.3);
- exposing an owned resource requires moving it into the namespace, because a read of a non-copyable binding is a borrow (`{ let handle = move buffer }`);
- its lifetime is the lifetime of the binding the importer gave it, so an import inside a runtime body is destroyed when that body's scope exits, while top-level imports live until module unload.

A file that imports itself, directly or transitively, is a construction cycle and is a compile-time diagnostic (§4.2 defers mutual recursion).

### 15.3 Host vocabulary contract

A host-provided word must declare its name, phase, ordered stages and their qualifiers and constraints, result constraint, and purity. Its supplied behavior must satisfy those declarations.

How the host registers or implements that behavior is outside the language specification. The declared phase and source semantics do not depend on that interface.

An ownership-taking host stage becomes owner on successful entry. A borrowing stage may not retain its argument. A host word marked pure must satisfy the full promise in §12.2.

### 15.4 No prescribed object ABI

This specification fixes source behavior, not an in-memory object model or calling convention. Any representation must satisfy the static requirements of §11.3 and preserve the same constraints, evaluation order, and ownership transfers.

---

## 16. Required diagnostics and runtime checks

### 16.1 Compile-time diagnostics

A conforming implementation rejects at least:

| Condition | Phase |
| --- | --- |
| Invalid UTF-8, escape, integer or Float spelling, or out-of-range literal | scanning/parsing |
| Unknown name or duplicate name in one scope | binding |
| Wrong-phase use of runtime, construction, or constraint word | construction |
| Invalid qualifier order or `own` on a completed binding | parsing/elaboration |
| Unsatisfied stage in a runtime body | elaboration |
| `return` outside a runtime `do` body | elaboration |
| Too few/many invocation arguments or invocation of data | elaboration |
| Persistent mutable borrow | ownership |
| Conflicting read/mutable borrows | ownership |
| Use after move, double move, or double destruction | ownership |
| Escape of a borrowed capture | ownership |
| Tail invocation borrowing state destroyed by caller cleanup | ownership |
| Assignment to an immutable place | ownership |
| Unproved constraint or unresolved concrete operation representation | constraints |
| Mixed named and positional aggregate members | parsing |
| Duplicate named aggregate member | binding |
| Chained comparison or assignment expression | parsing |

An implementation should attach the diagnostic to the narrowest source span and identify the original binding or move when relevant.

### 16.2 Runtime checks

Only genuinely runtime information needs a runtime check: positional bounds, zero divisor, and contracts of ordered host primitives. A check may be omitted when its failure is proved impossible. A possible and observable failure must not be removed, and checks must preserve the evaluation and effect order specified by the language.

---

## 17. Canonical examples

### 17.1 Currying versus calling

~~~let
let multiply =
    let x : Int
    let y : Int
    do
        return x * y
    end

let double = multiply 2
let pending = multiply 6 7

let a = double(21)       // 42
let b = pending()        // 42
let c = multiply(6, 7)   // 42
~~~

`multiply 6 7` creates a saturated zero-input word. Only `pending()` runs it.

### 17.2 Specialization prelude

~~~let
let affine =
    let scale : Int
    let bias : Int
    let twice_bias = bias * 2
    do
        return scale + twice_bias
    end

let configured = affine 10 16
let result = configured()       // 42
~~~

`twice_bias` is computed when `bias` is supplied, not when `configured()` is invoked.

### 17.3 Named aggregate of words

~~~let
let arithmetic = {
    let add =
        let x : Int
        let y : Int
        do return x + y end

    let negate =
        let x : Int
        do return -x end
}

let result = arithmetic.add(40, 2)
~~~

Projection returns `add`; the following `()` invokes it. There is no receiver argument.

### 17.4 Visible ownership transfer

The following assumes host vocabulary `open_buffer`, `write_byte`, and `consume_buffer` with their declared capabilities:

~~~let
let example = do
    let buffer mut = open_buffer(1024);
    write_byte(mut buffer, 0, 42);
    consume_buffer(move buffer)
    // buffer is now uninitialized
end
~~~

No retain, reference count, or implicit copy is inserted.

---

## 18. Deliberately deferred features

These language extensions remain explicitly deferred. Note that partial moves *are* part of the language; only their interaction with run-time-computed paths is excluded above.

- source-defined construction-word syntax;
- private exports and package resolution (file chains and imports are specified in §15.2);
- mutual-recursion declarations;
- non-escaping partial specialization that retains a `mut` borrow;
- storing a borrow in an aggregate, which is what §20's vector was reaching for: the grammar admits
  a value or `move place` as a member (§3.3) and confines `mut place` to a call argument (§3.4), so
  a program that tries it is rejected while parsing rather than by the ownership rules;
- mixed numeric promotion and implicit numeric conversion;
- dynamic constraint tests and reflection;
- pattern matching, `break`, and `continue`;
- catchable exceptions;
- coroutines, async suspension, and generators;
- raw pointers and a stable foreign-function ABI;
- a built-in cyclic collector;
- operator overloading;
- a mandatory universal aggregate or closure layout.

An extension must state its source semantics explicitly. The features above are not implicitly supplied by an implementation technique, runtime library, or embedding.

---

## 19. Conformance checklist

An implementation conforms to Let only when all of the following hold:

1. Every program binding is introduced by `let`.
2. `=` completes a binding; a chain `let` without `=` creates a stage.
3. Juxtaposition binds stable stages and never enters `do`.
4. Postfix `()` alone invokes runtime behavior.
5. Prelude bindings fire exactly when the preceding stages become satisfied.
6. Argument evaluation and prelude firing obey §6.2.
7. `do` is either a word terminal or an inline construction region.
8. `if`, `while`, and `switch` are inline control constructions, not runtime branch closures.
9. Projection never invokes and supplies no implicit receiver.
10. Evaluation order is left to right, with Boolean short-circuiting.
11. Non-copyable values have one owner and transfer only through a visible move or fresh result.
12. Mutable borrows are transient and cannot escape.
13. Destruction on normal and explicit recoverable exits is deterministic and reverse ordered.
14. Constraints run in the frontend and add no implicit runtime tags.
15. Every dictionary primitive truthfully declares `pure` or `ordered`.

These obligations define language conformance. Passing the language tests alone does not establish machine conformance.

---


## 20. Minimum semantic test vectors

These tests are normative even if a test harness uses different spelling for the host `mark` primitive.

| Test | Required observation |
| --- | --- |
| `let w = multiply 6 7` | Constructs a zero-input word; no terminal-body effect occurs at the binding |
| `w()` | Runs the terminal body once and returns `42` |
| `false and trapping_word()` | Returns `false`; the right operand is not invoked |
| `true or trapping_word()` | Returns `true`; the right operand is not invoked |
| `{ mark("a"), mark("b") }` | Event order is `a`, then `b` |
| Read after `consume(move x)` | Ownership diagnostic at the read |
| Store a `mut x` borrow in an aggregate | Parse error: §3.3 admits a value or `move place` as a member, and §3.4 confines `mut place` to a call argument. A borrow cannot be stored; see the deferred borrow-in-aggregate design in §18 |

Prelude and invocation order use this definition:

~~~let
let staged =
    let first
    let prelude = mark("prelude")
    let second
    do
        return {}
    end

let result = staged(mark("first"), mark("second"))
~~~

The required event order is:

~~~text
first
prelude
second
~~~

The prelude is reached after the first stage and therefore runs before the second argument is evaluated.

---

## 21. Semantic closure and representation independence

The specified semantics govern token boundaries, expression precedence, stage advancement, invocation, control scope, evaluation order, ownership transfer, borrow lifetime, normal destruction, and primitive integer and Float behavior. Compiler implementation gaps do not redefine those semantics.

Object layouts, internal compiler data structures, source-map compression, diagnostic presentation, and execution techniques are not language semantics. The host's action after an unrecoverable trap is governed by §14.2.

Such choices may change size, speed, and embedding policy. They must not change Let-visible results, ordered effects, traps, ownership, or required diagnostics.

---

## Appendix A. Glossary

| Term | Definition |
| --- | --- |
| Binding stage | An uninitialized `let` in a binding chain, awaiting one supplied meaning |
| Prelude | A completed `let` between stages; it runs when execution reaches it |
| Word | A value containing remaining stages, stable state, and a terminal meaning |
| Specialization | Persistent stage binding by juxtaposition; never terminal-body invocation |
| Invocation | Transient saturation followed by entry into runtime `do` |
| Construction word | Construction-phase word that shapes the enclosing word's control behavior from source expressions and regions |
| Place | Writable or readable storage named by a binding, projection, or index |
