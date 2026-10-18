# Designing and writing Let

**Status: guide to the approved language design, not an executable-subset manual.**
This document sits beside [syntax.md](syntax.md),
[application-sugar.md](application-sugar.md), [spread.md](spread.md) and
[operators-and-blocks.md](operators-and-blocks.md). Those documents own language
rules; this guide describes how to use them well.

The guide has two halves. Part I is about design: how to shape data, words and
programs. Part II is about style: how to name things and how to spell them.

Examples illustrate contracts and library design. They do not promise that every
library shown is bundled or that every target feature executes today. Ellipses in
example bodies stand for omitted code, not an additional statement form. The short
[availability note](#18-design-and-implementation-status) keeps that distinction
out of the main narrative. See [stdlib.md](stdlib.md) for the library inventory.

## 0. Forms this guide relies on

| Form | Used for |
| --- | --- |
| `do(x) = e`, `do(x) ... end`, named sugar over `do` | words and lambdas |
| unit fallthrough, values explicitly `return`ed | block completion |
| `f "lit"`, literal postfix chains, `f 1 2` = `f(1)(2)` | readable fixed arguments |
| saturating application chains | `with_file(path) do(file) ... end` with a runtime path |
| `history.undo()` | an explicit nullary invocation |
| lexical receiver calls, member wins | fluent words over values |
| `name(params) = body` in headed supplies | handlers and protocols |
| `use m...`, `let context...`, `do(context...)` | opening vocabularies |
| live field projections and a retained receiver | working inside an opened context |
| `spread-shadow` | diagnosing colliding introduced names |
| `endall` | closing a spine of trailing callback blocks |

---

# Part I — Design

## 1. The stance

Let puts **specialization** at the center: a word supplied with known information
can become a more specific word. The useful design question is **what is known,
and when?**

Factor for meaning. Keep known information available. Require and measure the
costs that matter. Known inputs are an opportunity to simplify a program, not a
promise that every call, allocation or ownership operation disappears.

Three commitments guide the rest:

1. **Say it as you think it.** A program is words for the domain, spoken in the
   contexts where they make sense.
2. **Never hide what matters.** Make ownership, mutation, lifetime, failure and
   cost understandable from the contracts and the places where they are used.
3. **Grow the vocabulary, not the language.** Scopes, builders, tests, iteration,
   concurrency and domain-specific languages are expressed through words. New
   syntax is a last resort.

## 2. The method

| Step | Question | Let answer |
| --- | --- | --- |
| Values | What does the program talk about? | records and sums |
| Ownership | What exists, and who owns it? | fields for trees, stores and ids for graphs |
| Activities | What bounded work happens? | activity words and context schemas |
| Vocabularies | What can be done here? | cohesive modules and activity interfaces |
| Pure core | What is decided? | computations from values to values |
| Composition root | Who connects the parts? | one parent word |
| Edges | Where does the world come in? | resources supplied at the outside |
| Tests | How do we know? | drive the core with data |
| Costs | What must stay fast? | explicit requirements and measurements |

**Draft top-down.** Write the word you wish you had, ask what it needs, and draft
those words. Sketch their signatures before their machinery. A sketch need not be
an accepted signature-only source declaration: do not confuse a design technique
with a compiler feature.

## 3. Data

### 3.1 Values first

Model records and sums before behavior. Prefer data to calls for anything that
must be stored, replayed, logged, undone or tested:

```let
let Direction = oneof { left: Unit, right: Unit, up: Unit, down: Unit }
let Edit = { at: U32, text: String }
let Change = oneof { inserted: Edit, deleted: Edit }
let Command = oneof { move: Direction, insert: U8, undo: Unit, quit: Unit }
```

Commands represented as data give undo, macros, replay and testing a common
foundation. They do not implement those features by themselves.

### 3.2 Ownership

- **Give mutable state an owner.** Other parts receive the access they need
  explicitly; do not hide shared mutation in module state.
- **Trees are fields; graphs are stores.** Use `Store(T)` and `Id(T)` for stable
  identity, cycles and graph relationships under their ownership contracts.
- **Distinguish values from access.** Copying a reference does not copy its
  referent. An id is not ownership of the store it identifies an element in.
- **Tables are for open data.** Use them when the shape is genuinely dynamic;
  prefer records when the shape and interface are settled.

### 3.3 Outcomes and failures

An outcome a caller can act on is a sum: `found`/`missing`, `sent`/`closed`.
A broken invariant aborts. Do not use magic sentinel values or binding-list unit
padding to represent absence.

## 4. Words

### 4.1 Subject, objects, continuation

A signature should read like a sentence:

```text
subject . verb        objects        continuation
editor  . open        "notes.txt"
file    . read_lines                 do(line) ... end
rows    . fold        (0, do(acc, row) = acc + row.size)
```

- Put the **subject first**: the thing the operation is about.
- Put the other inputs next. Prefer one meaningful value to several unexplained
  primitives, but do not invent a wrapper record merely to avoid parentheses.
- Put the **body last** when the word establishes structure.
- Give a public phrase one clear trailing role. Rest forwarding and callback
  protocols should not compete to explain where the sentence ends.

Prefer trailing block lambdas for structure and parenthesized expression lambdas
for small computations. This is a reading convention, not arity-directed parsing.

### 4.2 Let the contract say copy or borrow

| Operation | Usual design | Example |
| --- | --- | --- |
| maintain a component's own invariants | schema method | `editor.history.record(change)` |
| query or transform a value | free word taking `T` | `text.trimmed()`, `point.translated(10)` |
| coordinate mutation from outside a component | free word taking `Ref(T)` | `document.transaction do(editing...) ... end` |

Methods can query; free words can mutate. The table is design advice, not a division
of the language into two kinds of computation.

Receiver passing follows the selected contract:

```let
point.nudge(10)           -- borrows point if nudge's first parameter is Ref(Point)
nudge(Ref(point), 10)     -- ordinary argument positions remain explicit
let moved = point.translated(10)  -- a value transformation returns its result
```

A by-value receiver is not silently written back. A temporary is not made into a
persistent mutable receiver merely to make a call fit. Inside a receiver scope,
`(nudge)(Ref(point), 10)` explicitly selects the ordinary function-value route.

### 4.3 An unnamed home, named roles

When a context name adds no information, open the first runtime parameter anonymously:

```let
let squared(...: Point): F64 = x*x + y*y
let run_session(...: Ref(Terminal), editor: Ref(Editor)): Unit = do
  draw(editor)
  return
end
```

`...: T` receives one home, not a pack. Leading static Type parameters may precede
it. A signature opens one context; other collaborators are named roles. A checked
callback signature can supply its type in `do(...)`; a standalone unnamed parameter
still needs an annotation. Opening belongs to word entry, whether the body is an
expression or a block.

Before an expression, `...e` supplies values; after a name, `ctx...` opens names;
alone, `(...)` reads home. Use `(run_session)(..., editor)` for explicit ordinary
argument passing. Normal bare receiver calls retain their existing routing rules,
including the local-callable exception. No argument-type search is involved.

Home is the actual qualified argument/place, not just its type and not a promise
of physical C0 placement. It cannot be rebound. Its fields remain live; explicit
reads can take snapshots. Borrow and lifetime checks still govern references and
captures—this syntax is not safety or ownership by construction.

### 4.4 One word, one job

A word should have a short, useful promise. Factor along domain boundaries, not
arbitrary line counts. Small helpers are worthwhile when their names reveal an
idea; they are not worthwhile when they merely rename syntax.

### 4.5 Keep known information available

Configuration, grammars, layouts and schemas are often known before execution.
Pass descriptions in forms that specialization can inspect. Use keyed partial
supply for configured families where its contract fits. Avoid erasing useful type
or value information through `Any` or runtime callable boundaries on hot paths.

Do not maintain a second, hand-specialized implementation unless measurements and
an explicit design decision justify it.

### 4.6 Put types at definitions

Write parameter contracts where reusable words are defined. Let expected callable
signatures supply types at callback use sites where the contract is unambiguous.

```let
let step(particle: Particle, delta: F64): Particle = advance(particle, delta)
```

**Typed is not the same as known.** A `Particle` can be a runtime input. An `Any`
can contain a known value. Neither annotation alone proves purity or absence of
allocation. Do not rely on omitted annotations to manufacture implicit generics.

## 5. Activities as architectural units

> **Entities own what persists. Activities own or borrow what is needed for a
> purpose. Words express what happens inside.**

An activity is a central design role, expressed using ordinary words, contexts
and callbacks. It needs no special activity type or separate execution mechanism.

### 5.1 Entities and activities

An editor is something that exists. Editing is something that happens.

| Entity | Activity |
| --- | --- |
| may have persistent identity | has a bounded purpose and lifetime |
| owns long-lived state | owns temporary state or borrows existing state |
| supplies general capabilities | exposes operations appropriate to its purpose |
| participates in many activities | coordinates one piece of work |

A `Document` can participate in editing, searching, formatting and saving without
acquiring one giant interface containing every workflow.

For each activity, name its purpose, temporary state, borrowed access, vocabulary
and completion policy. State whether it writes through immediately or commits a
working value at the end.

### 5.2 Enter an activity and speak its verbs

```let
document.transaction do(editing...)
  insert "hello"
  move_left()
  insert "!"
end

compiler.optimize do(optimizing...)
  constant_fold()
  simplify_branches()
  eliminate_dead_code()
end
```

The activity word controls setup and finishing. Its context can hold a change log,
worklist, caches, diagnostics or other temporary state.

`do(editing...)` opens that context. Otherwise-unbound receiver calls use it;
local callable bindings remain ordinary calls. Namespace-qualified helpers remain
explicit. There is no search through outer receivers for a signature that fits.

### 5.3 Open to work; bind to remember

Opening exposes live field places and retains the receiver:

```let
document.transaction do(editing...)
  let before = cursor
  move_left()
  diagnostics.show(cursor)  -- the current field
  diagnostics.show(before)  -- the deliberately saved value
end
```

Introduced field names denote the context's fields, not copies made when it was
opened. Writing a writable field writes that place. Opening frozen or readonly
state does not grant permission to mutate it.

An explicit binding reads an ordinary value. `let saved = field` has the same
value-read semantics as `let saved = context.field`; it is not another live field
projection. This does not deep-copy objects reached through reference or id values,
nor redefine ordinary instance-alias rules elsewhere in the language.

A nested word using an opened field retains access to its place under ordinary
capture/lifetime rules. Save a value explicitly when that is what the nested word
should remember. Do not silently copy an entire context to make a borrowed capture
escape.

### 5.4 The activity author owns completion

An activity can live outside the entity it operates on. Signature-directed borrowing
lets that free word still read naturally at the call site:

```let
let transaction(document: Ref(Document), body: (Ref(Editing)): Unit): Unit = do
  let editing = Editing { text = document.text, cursor = document.cursor }
  body(Ref(editing))
  document.text = editing.text
  document.cursor = editing.cursor
end
```

This example assumes an `Editing` schema with the appropriate operations. It commits
a working value after normal callback completion. A transactional outcome protocol
can instead decide whether to commit. Copy-on-write storage may make the initial
value copy cheap; it does not make all subsequent edits free.

Three boundaries matter:

- The callback's `return` returns from the callback, not the enclosing activity word.
- Cleanup, commit, cancellation and rollback are the activity's explicit contract;
  opening syntax does not provide them automatically.
- Borrowed access cannot outlive its owner. An ordinary owned result may leave an
  activity when its contract permits it; there is no blanket ban on returning data.

### 5.5 Stack activities instead of adding unrelated options

```let
traced "import" do
retry 3 do
database.transaction do(importing...)
  load_rows(rows)
endall
```

Here `load_rows` is part of the importing context's interface. Each surrounding
word owns its policy. Order is visible; retry must explicitly permit repeating the
body's effects. A word need not grow tracing and retry flags just because callers
want to compose those activities around it.

### 5.6 Dialects

A dialect is a vocabulary on Let's grammar: words, context schemas and engines
that turn descriptions into results. Notes, builds, UI layouts, key maps and tests
can each have a dialect without acquiring a parser of their own.

Keep descriptions pure where possible and effects in engines. A build description
can store a glob pattern; its engine reads the filesystem when it runs.

A pure-looking vocabulary is not an enforced security boundary. Imports alone do
not prove safety, termination or resource bounds. Loading untrusted descriptions
requires actual enforcement, not a naming convention.

Give common library words short names and stable contracts. Keep the always-visible
prelude small: every predefined name constrains the vocabularies people can open.

## 6. Connecting behavior

| Connection | Use |
| --- | --- |
| ordinary result | a computation producing a value: the default |
| subject-oriented block | a block receiving a thing to act on |
| activity block | a block receiving a vocabulary |
| keyed protocol | several named behaviors supplied together |
| channel | values crossing tasks under their transfer contracts |

### 6.1 Subjects are not vocabularies

```let
editor.on_change do(change)
  editor.history.record(change)
  editor.view.render(change)
end
```

The change is the object of the actions. The mutated components are their subjects.
Do not write `change.record()` when history is what changes.

### 6.2 Keyed protocols

```let
editor.run {
  on_key(key) = interpret(key),
  on_quit() = do cleanup() end,
}
```

A bare word in an expression is a value: `on_quit() = cleanup` returns the word.
Invoke it when invocation is intended. These entries are ordinary handler words,
not schema methods receiving an invented receiver.

### 6.3 Flat continuation spines

When callbacks genuinely nest, their opening lines can remain flat:

```let
let main = do
  with_terminal do(terminal)
  with_file(path) do(file)
  read_lines(file) do(line)
    terminal.show(line)
  endall
  return 0
end
```

`endall` abbreviates the three callback-closing `end`s here. It leaves the enclosing
word body open. It stops at a different enclosing block or explicit delimiter;
indentation has no semantic role. It does not return, invoke a callback or perform
cleanup. Those effects are exactly the effects of the expanded program.

See the [precise boundary rule](operators-and-blocks.md#endall-flat-continuation-spines).
Do not turn ordinary result flow into callbacks merely to use this spelling.

### 6.4 Saturating chains

For a word with three ordered requirements, these can be the same invocation:

```let
range(0, 10, do(index) ... end)
range(0, 10) do(index) ... end
range 0 10 do(index) ... end
```

The parser sees left-associated applications. Elaboration accumulates arguments
until the word is saturated, invokes it, and applies later suffixes to its result.
**The signature determines invocation points, not parsing.**

Only the specified literal/block forms omit argument parentheses. `f x` rejects;
computed arguments remain explicit. A pending runtime argument can stay inside a
chain, as in `with_file(path) do(file) ... end`, without becoming a first-class
runtime partial word.

Once a partial leaves its chain, its ordinary specialization, representation and
capture rules apply. An explicit lambda makes capture visible; it does not exempt
that capture from ownership checks.

A prefix is a complete command only if it actually invokes a word. For a binary
`todo`, `todo "text"` is not automatically an undated todo. Optional information is
better expressed by a deliberate result-word protocol or a keyed configuration.

## 7. Composition

- **The parent is the composition root.** Let the owner of several components wire
  them together instead of making siblings discover one another through hidden state.
- **Effects enter through contracts.** Supply terminal, files, network and time at
  the edges; keep decisions testable without them.
- **The pure core decides.** Interpret, plan, validate and transform values. The
  parent applies the resulting actions.

```let
let session(terminal: Ref(Terminal), editor: Ref(Editor)): Unit = do
  editor.apply(interpret(editor.mode, terminal.read_key()))
  terminal.draw(editor)
  if editor.running then session(terminal, editor) end
end
```

## 8. Describe, then run

When a problem has structure—a grammar, state machine, key map or protocol—write
the structure as a value and an engine that consumes it.

```let
let normal_keys = keymap.build do(binding_normal_mode...)
  bind('h', Command.move(Direction.left()))
  bind('u', Command.undo())
end
```

Known descriptions give specialization something to work with. Runtime descriptions
can use the same engine where its contracts permit them. Keep one semantic
implementation; measure whether the intended specialization actually removes the
interpretive work.

## 9. Operators

Give a type operators when the symbol communicates a genuine algebra. Document
its laws and limitations. Floating-point addition, for example, is not associative;
a familiar spelling is not a proof that reassociation is valid.

Vectors, units and symbolic predicates can benefit from operators. I/O and “send
to” usually benefit from named words. `and`, `or` and `not` stay boolean; `&`, `|`
and `~` serve masks or the explicitly supported symbolic protocols.

## 10. Iteration, concurrency and cost

- Prefer a named traversal, search or fold to hand-written control plumbing.
- Use tail recursion when the changing state is the point of the computation.
- Compose adapters and a consumer when that expresses the algorithm. Check that
  the intended fusion and allocation behavior actually occur.
- Put tasks inside a scope with explicit transfer, sharing and completion contracts.
  Do not describe concurrency as unrestricted shared mutation—or assume every value
  has the same transfer policy.
- Put cost requirements on the inner steps, codecs, scanners and engines that
  matter. Inspect residual code and measure. A script need not carry blanket claims.

---

# Part II — Style

## 11. Naming

> **A name is a promise. A vocabulary is a set of promises spoken together.**

### 11.1 Types look like types

Use **PascalCase for all types and schemas, including built-ins**, and **snake_case for ordinary
words and values**:

```let
let Document = { text: String, cursor: U32 }
let Editing = { text: String, cursor: U32 }
let Command = oneof { insert: String, undo: Unit }

let save(document: Ref(Document)): Unit = write_document(document)
let active_document = Document { text = "", cursor = 0 }
```

| Role | Convention | Examples |
| --- | --- | --- |
| entity or value type | PascalCase noun | `Document`, `Cursor`, `Edit`, `Command` |
| activity context type | PascalCase activity name | `Editing`, `Rendering`, `Checking` |
| instance or parameter | snake_case role | `document`, `active`, `source`, `editing` |
| action | imperative verb | `insert`, `save`, `publish` |
| value transformation | participle or adjective | `sorted`, `translated`, `trimmed` |
| query | the thing returned | `length`, `line_count`, `current_mode` |
| predicate | proposition | `is_dirty`, `has_selection`, `can_undo` |
| activity word | purposeful verb/noun, or `with_` + resource | `transaction`, `render`, `with_file` |
| activity block parameter | gerund | `editing`, `configuring`, `listing_entries` |
| event handler key | `on_` + event | `on_key`, `on_change`, `on_quit` |
| alternative | snake_case action or outcome | `insert`, `inserted`, `closed`, `missing` |
| module | snake_case domain name | `document_editing`, `editor_keys` |

Built-ins follow the same convention: `U32`, `F64`, `Bool`, `Unit`, `Any`,
`String`, `Ref(Document)`, `List(Change)` and `Store(Node)`. Constructors are
capitalized in both forms: `Ref(Document)` names a type and `Ref(document)`
constructs a reference; likewise `Ptr`, `Slice`, `Array` and numeric conversions
such as `U32(value)`. Lowercase built-in aliases are not retained. Capitalization
still does not determine a user binding's grammatical role.

Underscores join concepts; they do not pad. Avoid kind suffixes such as `_t`, `_rec`
and `_obj`. Abbreviate only what readers already abbreviate: `id`, `min`, `max`.

### 11.2 Let the receiver carry the subject

```let
document.save()       -- not document.save_document()
cursor.move_left()    -- not cursor.move_cursor_left()
history.undo()        -- not history.history_undo()
```

Read the call aloud. If it stutters, shorten the name.

### 11.3 Name for the call site

Avoid unexplained flags such as `render(true, 1)`. Prefer distinct operations,
a meaningful sum or a keyed configuration. A clearly named configuration word
such as `relative_numbers true` is different: its name explains the boolean.

Be suspicious of `data`, `info`, `manager`, `helper`, `util`, `process`, `handle`,
`update`, `temp` and `misc`. Replace shape names with domain meaning:
`rename`, `move_to`, `mark_saved`, `Session`, `Pool`, `Registry`.

### 11.4 Collisions are design feedback

When `spread-shadow` fires, ask:

1. Are unrelated activities mixed together?
2. Is a name too generic for its domain?
3. Did a private helper leak into the public vocabulary?
4. Is this a genuine homonym that should stay qualified?

Do not silently shadow an introduced name. But qualification is a legitimate
composition tool, not an admission of failure. A composition root may quite
properly use two vocabularies that both say `clear`.

### 11.5 Open vocabularies deliberately

**Open cohesive activity vocabularies by default; qualify by choice.**
`do(editing...)` makes a block read in the language of editing. `do(editing)` is
useful when explicit origins make a mixed block clearer.

Module opening is also a deliberate import of names, not a universal preference
for unqualified library code. Library boundaries and genuine homonyms often read
better with qualification.

A subject parameter such as `do(change)` is usually a value to act on, not an
interface to open. Do not spread every parameter.

### 11.6 Nouns receive; gerunds do

```let
items.each do(item) ... end
editor.on_change do(change) ... end

document.transaction do(editing...) ... end
editor.configure do(configuring...) ... end
release.prepare do(shipping...) ... end
column do(listing_entries...) ... end
```

Use the vocabulary parameter as a short section heading: what activity is this,
and which one? Prefer `listing_entries` to `ctx`, `c` or `s`. Keep it a role, not
an entire sentence. It remains available for qualification.

Names can support useful diagnostics and tooling; do not claim an outline or
formatter feature exists just because this convention would make it possible.

### 11.7 Literal phrases

Use literal chains when argument roles are obvious. A reasonable house limit is
three literals; beyond that, prefer keyed supply. Do not hide optional-argument
semantics in an unsaturated prefix.

References to words are values and take parentheses: `see(apply)`, not `see apply`.
Single-letter names belong in short lambdas and familiar mathematics, not long-lived
activity contexts.

## 12. Spelling forms

| Form | Use |
| --- | --- |
| literal argument | readable fixed configuration: `tab_width 4` |
| parentheses | computed values or explicit argument lists |
| `word()` | nullary invocation |
| trailing block | scopes, iteration, activities |
| headed keyed braces | construction or a multi-arm protocol |
| operators | a documented algebra |
| `do(x) = e` | a small expression lambda |
| `do(x) ... end` | a callback with statements |
| `endall` | the closing run of a trailing-block spine |

Commands act; expressions compute. Prefer explicit parenthesized calls when a
computed result is central to the surrounding expression. Literal postfix chains
still obey their specified precedence: `print "{}".fmt(n) .. "!"` concatenates
after the call, not inside its argument.

Use named definitions for reusable vocabulary and literal `do` where treating the
word as a value is the point. Both have the same computation and capture rules.
Return values explicitly; the target unit-completion rule supplies unit fallthrough.

### 12.1 Which side of `...`

> **Before is about values. After is about names.**

| Form | Meaning |
| --- | --- |
| `f(...values)` | expand a supply |
| `Point { ...point, x = 5 }` | expand data into construction |
| `let f(first, ...rest)` | collect remaining requirements |
| `use geometry...` | introduce exported definitions |
| `let editing...` | open an existing context |
| `let editing... = make_editing()` | bind once, then open |
| `do(editing...)` | receive an ordinary argument, then open it |

`f(values...)` is not the supply spelling. A computed context needs a binding;
`let make_editing()...` is not an alternative form.

### 12.2 Opening is access, not a field-copy operation

Opening preserves the receiver and exposes its field places. Method calls stay
attached to that receiver; callable fields keep their ordinary callable signatures.
Opening does not itself manufacture bound closures or upgrade permissions.

A by-value parameter may already be a copy before it is opened. A reference
parameter retains its referent. Initializers, ordinary value reads and captures
still have their normal effects and ownership costs. “Opening does not copy the
fields” is not “this whole activity costs nothing.”

Uninvoked lexical fallback does not invent a bound word. Existing genuine bound
method behavior is a separate language contract, not abolished by this convention.

## 13. Formatting

Use these as house rules; formatter implementation is separate work:

- Two-space indentation, roughly 100 columns, one blank line between top-level words.
- Keep `do` on its owning call's line. Align ordinary `end` with its opener.
- For a flat continuation spine, align its opening calls and its final `endall`;
  indent the innermost body once. Never rely on indentation to determine closure.
- Space binary operators; keep unary operators, spread markers and calls tight.
- Use spaced headed braces, with a trailing comma for multiline entries.
- Break fluent chains before `.`, and long argument lists after `(`.
- Put imports first, standard modules before local ones, alphabetically within groups.
- Do not align columns of `=` or comments.

Formatting should preserve the author's meaningful choice of call form. A future
`letfmt` can own whitespace without deciding whether a word should be presented as
an activity, a literal phrase or an ordinary computation.

## 14. Files and modules

### 14.1 Organize by reason to change

A file should name a vocabulary: `document_editing`, not `utils` or `helpers`.
Keep small programs small. A larger application can distinguish:

| Area | Responsibility |
| --- | --- |
| `program/` | entry points, configuration, descriptions and cross-component scenarios |
| `words/` | domain values, entities, activities and reusable computations |
| `engines/` | interpreters/runners for the package's descriptions |

Create an area only when it contains something. Prefer flat files named
`subject_role` before adding deep directory hierarchies:

```text
mini/
  program/
    main.let
    editor_config.let
    editor_scenarios.let
  words/
    document.let
    document_editing.let
    document_search.let
    editor.let
    editor_apply.let
    editor_keys.let
    history.let
```

This is an organizational sketch, not a module-search rule or a ready-to-build
layout for the current resolver. Module lookup remains explicit under
[syntax.md](syntax.md#11-modules-and-export-configuration). Folders are not silently transparent;
a package/build mapping for a layout like this must be specified separately.

### 14.2 Dependencies point toward the domain

The composition root uses activities and engines. Activities use entities and
values; entities should not need to import every activity that can operate on them.
A free `transaction(document: Ref(Document), body: ...)` is useful precisely because
it can live beside `Document` without growing its defining schema.

Keep effects out of descriptions by contract, not merely by placing files in a
folder named `program`. A directory name is not an enforced effect profile.

### 14.3 Newspaper order

Within a vocabulary file:

1. imports;
2. exported schemas and context types;
3. exported words, each with its promise;
4. private helpers.

A reader should understand the public surface before reaching its machinery. Keep
rationale, examples and properties close to what they describe using available
documentation/test facilities. A notes dialect may eventually make those ordinary
data; the guide does not assume that facility is bundled today.

### 14.4 Packages with dialects

A knowledge-base package might have `kb_notes` and `kb_query` vocabularies, plus
`kb_index`, `kb_check` and `kb_render` engines. Its documents describe notes; its
entry word asks the engines to index, check and render them.

A UI package might similarly separate `tui_layout`, `tui_style` and `tui_screen`
from `tui_diff` and `tui_run`. Examples are both a reader's first encounter with the
vocabulary and useful executable tests once those APIs exist.

The distinction is **description versus execution**, not a second grammar.

## 15. Comments

Explain why when the code already says what. Name invariants and obligations the
signature cannot express. Give each exported word one sentence stating its promise
and any important ownership, failure or cost conditions.

Do not forbid explanations of what a subtle algorithm does. A good overview can
save a reader from reconstructing the design. Prefer useful information to a rigid
ban on particular kinds of comments.

## 16. Anti-patterns

| Anti-pattern | Prefer |
| --- | --- |
| behavior attached to an event rather than its owner | make the affected component the subject |
| giant schemas containing every workflow | cohesive methods plus external activity words |
| hidden sibling/module coupling | parent-level composition and explicit access |
| unexplained flags | named operations, meaningful sums or keyed configuration |
| erasing settled information on a hot path | retain useful types and known values |
| everything expressed as callbacks | results for computations, blocks for activities |
| opening every parameter | distinguish subjects from vocabularies |
| hand-specialized copies of an engine | one description-driven implementation |
| qualification used to conceal muddled responsibilities | improve the design, then qualify genuine homonyms |
| `do(ctx...)` everywhere | a gerund that names this activity |
| effects hidden in descriptions | explicit engine contracts |
| assuming a borrowed context can escape | preserve its lifetime or return an independent result |
| asserting that factoring must be free | inspect and measure important costs |

## 17. Review checklist

- **Names:** are types visually distinct? Do calls read naturally? Are activity
  parameters gerunds and subject parameters nouns?
- **Vocabularies:** is opening useful here? Are collisions understood rather than
  silently shadowed?
- **Ownership:** who owns each mutable thing? What does each reference retain?
- **Opening:** should this use observe a live field or an explicitly saved value?
- **Activities:** who implements setup, completion and any rollback/retry policy?
- **Effects:** can decisions be tested without real resources?
- **Failure:** are actionable outcomes explicit?
- **Knowledge:** is known configuration still available to specialization?
- **Cost:** have important requirements been checked and measured?
- **Form:** is this an invocation, a word value, a pending chain or an activity?
- **Tests:** do examples exercise the contracts, not just convenient outputs?

## 18. Design and implementation status

This guide deliberately describes the direction of Let, not just today's executable
subset. [WORKLIST.md](../WORKLIST.md) is the authoritative implementation ledger.

- **Implemented within current admission:** shared words, saturating chains, literal
  application, receiver-only borrowing, receiver scopes and binding-resolved captures.
- **Implemented within admitted typed contexts:** opened record fields are live places,
  including scalar place captures; explicit saved values keep ordinary read semantics.
  Pointer-free module snapshots have bounded support; owning module transport and
  broader proofs remain incomplete.
- **Implemented:** `endall` with its bounded trailing-block expansion. WORKLIST owns
  qualification and historical isolation results.
- **Implemented and partially qualified:** ordered/keyed supplies and source-only
  rest/template specialization, including definition-point captures and fixed-ABI
  direct/indirect adapters. No runtime pack or erased variadic ABC signature.
- **Implemented initial ownership slice:** explicit `Rc(value)`, named `r.borrow()`,
  retain-on-copy and private owning calls; invalid borrowed escape rejects.
- **Target or incomplete:** unit fallthrough, broader spread/resource qualification,
  owning public/foreign/erased/environment interfaces, operators, containers, tasks
  and library realization.
- **Guide conventions:** PascalCase types including built-ins/constructors, snake_case values/words, activity
  naming, formatting and suggested project organization. These are not grammar rules.
- **Not established by this guide:** bare nullary invocation, signature-only stubs,
  folder-transparent imports, an enforced pure-dialect profile, or formatter/LSP
  features. They need their own decisions and implementation.

The implementation uses existing place transport and ordinary block ASTs; it does not
broaden ownership admission, borrowing or escape permissions.

## Maxim

> **Model the values. Own the state. Name the words. Enter the activity. Open the
> context to work with it; bind a value to remember it. Specialize what is known;
> measure what matters.**
