# The gap inventory, triaged

What is actually missing, what only *looked* missing, and which fixes are elegant — meaning they
reuse a mechanism the compiler already has rather than adding one.

The count was 63 `gap` sites. It is now **18**, and the difference is not progress in features: it is
that most of those sites were not gaps. Classifying them turned up three mislabelled classes, and the
discriminator between them is one question.

## The discriminator

> **Does the message name the program's fault, or a mechanism the compiler lacks?**

- *The program's fault* → `refuse`. `unreachable statements`, `a type word cannot take a literal
  argument`, `word values in data positions`, `stored host words`, `a place to move or borrow is a
  name, a member or a constant index`. A reader should rewrite the program.
- *A mechanism the compiler lacks* → `gap`. `two runtime indices in one place path`, `loop ownership
  states that require initialization fixed-point analysis`, `address-taken locals`. A reader should
  wait, or work around it.
- *The compiler's own broken invariant* → `internal`. A word value the resolver should have resolved,
  or a build driven without a program builder. Nine sites said `construction not yet implemented`
  about what are compiler bugs, which made the inventory look nine sites larger than it is.

Judging by the message alone is not reliable: of 28 sites I classified from their text, **three were
wrong**, and their own comments said so — "Carrying it through the tail result needs address-taken
state", and a capture path that *builds* the retained fields it claimed to refuse. So a message names
the fault only when it names *what the program did*; a message that names an *analysis* is a gap.

## The 18, by cause

### Cause 1 — a word value that carries its captures (5 sites)

`word-valued stages` · `non-Copy lexical captures` · `a non-Copy capture needs the owner to be a place`
· `source/indirect word invocation` · `source-word invocation and recursion`

**Elegant fix: yes, for a statically known template.** `resolve.lua` already computes the ordered
capture set per template (`template.captures`, `template.capture_set`, `template.capture_uses`), and
`Builder:self_value` already builds a word value's fields from `layout.captures`, while
`entry_function(template, fields)` already receives the bundle as parameters. So a word supplied at a
site where its template is known — a `Name`, a `Project`, or a literal, which is exactly the case
`Builder:invoke` already distinguishes with `inline = not (Name or Project)` — can be specialized with
its captures threaded as extra parameters. **Direct calls, monomorphic, no dispatch, and no new
representation.** The work is threading, not inventing.

What must *not* be built is the other half: a word whose template is not known until run time would
need a uniform calling convention across candidate templates, which is a vtable by another name. The
elegant move is to make that a *rule* — `refuse`, naming it — so the gap closes with the capability
that fits the model and the rest is stated as forbidden rather than pending.

This one cause closes five sites, and it is the same mechanism the deferred `T.match` handler-fold
wants: a word receiving a body word, specialized so the arms inline.

### Cause 2 — address-taken state and write-back (4 sites)

`conditional destruction of an address-taken binding` · `address-taken locals` ·
`tail invocation from a word with mutable state` · `mutable borrowed resource stages`

**Elegant fix: partly, and the mechanism already exists.** For a non-tail invocation the compiler
*already* writes a callee's mutable retained state back to the caller:
`Packet.written_back(record.field)` decides which fields are results, and the callee returns them
(`program.lua`, the `updated` list). A tail transfer is the same problem with the return path
replaced by the callee's return, so this is one mechanism extended rather than a new one — which is
the definition of elegant here.

`address-taken locals` looks like the same family but is probably smaller: the resolver already
records `definition.address_taken = 'mutable borrow'`, and `A.Binding:build` already allocates a cell
when it sees that. Reaching this site means the resolver missed a `mut` access, so it is a resolver
gap rather than a lowering one. Worth confirming with a repro before believing it.

### Cause 3 — analysis depth (3 sites)

`two runtime indices in one place path` · `loop ownership states that require initialization
fixed-point analysis` · `a partial move inside a loop needs path-sensitive initialization analysis`

**Elegant for one, not for the other two.**

`two runtime indices` is elegant: `Context:select_member(key, fields, result, build)` already selects
one member by comparing a runtime key against each position, with a `build(c, at)` callback per arm.
Nesting is that same recursion one level deeper — the second index is selected *inside* each arm of
the first. No new analysis.

The two loop sites are **not** elegant, and their own comments say why: "Breaking that circle needs
path-sensitive facts (or peeling the first iteration)". That is a real dataflow analysis, and the
design deliberately keeps ownership state exact rather than running a fixpoint. The honest options are
to implement path-sensitivity or to state the restriction as a rule — not to hope for a small fix.

### Cause 4 — a result type being inferred (2 sites)

`result type of a word whose only exit is a self tail call` · `the result type of a recursive call must
be fixed by another return in the same word`

**Elegant fix: deletion.** These exist only because a result type is being *inferred*. The model
requires a runtime terminal to state its result (`do : T`), and `contract.lua`'s inference is already
listed as deleted in `TYPES.md` §10 while the file still exists. Requiring the annotation for a
recursive word removes both sites and retires a mechanism the model says is gone — a fix that reduces
the compiler's surface rather than adding to it. The most elegant kind.

### Cause 5 — prelude ordering (1 site)

`stage preparation: preludes must run between arguments, not at terminal entry`

**Elegant enough, but not a reuse.** §6.2 says a prelude's value is reached *between* arguments.
`A.Prelude:bind_parameter` is called at terminal entry, so the fix is to run it in the argument
sequence. Real work in the invocation path, with no existing mechanism to lean on, which puts it
behind the four above.

### Cause 6 — fallbacks that should not be reachable (2 sites)

`this expression form` · `this statement form`

Every AST form is supposed to have a lowering, so these are a check that the AST and the builder
agree. **Cheap improvement: name the node's class in the message** (`no lowering for <class>`), so an
unhandled form is actionable. Making them genuinely unreachable is a review, not a fix.

### One already improved

`A.Borrow:build` passed `reason or 'this move place'`, and `place_path`'s only reason was the vague
`'this place form'`. It now reads `a place to move or borrow is a name, a member or a constant index`,
stated from the program's side, which is what the classifier needs to see.

## Order I would take them

1. **Cause 4, by deletion.** Two gaps closed, an inference path retired, no new code.
2. **Cause 3's `two runtime indices`.** Reuses `select_member`; small and self-contained.
3. **Cause 2's tail write-back.** Extends `written_back`; unblocks stateful continuations, which is
   what a stack machine wants.
4. **Cause 1, the statically known half.** Closes five sites and unlocks the callback-that-accumulates
   and `T.match`. Bigger than the three above, and the one with the most value.
5. **Cause 6's message.** Trivial, do it with whichever of the above touches that area.
6. Leave Cause 3's loop analysis and Cause 5 until the four above are done; both are real work whose
   absence is at least *stated* clearly now.

## What this changed about how I judge a gap

A message alone cannot be classified. Three of 28 were wrong, and each time the surrounding comment
had the answer. So the rule is: read the comment, ask the discriminator question, and when it names an
analysis rather than a fault, leave it a `gap` and say so.
