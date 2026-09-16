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

**Correction after trying it: these two sites are unreachable in the shapes that matter.** Tried
against the current compiler, a word whose only exit is `return loop(n - 1)` is accepted, and so is
`let r = loop(n - 1); return r + 1`, and `contract.lua` already prefers a stated `do : T` over what
it can infer (its `constraint_type(types, terminal.result)` branch). So the inference path is not
infer (its `constraint_type(types, terminal.result)` branch). So the inference path is not what keeps
these alive. What does is reachable only through **mutual** recursion, which a forward reference
blocks before the result type is ever asked for (see the finding below). Neither site is a deletion
candidate; the cause is elsewhere.

### Found while starting item 1: two bugs behind these gaps

**A self-recursive word whose result passes through a binding crashes the emitter.**

```let
let loop = let n : Int do : Int
    let r = loop(n - 1);
    return r
end
let answer = loop(3)
```

`emit.lua:729: attempt to index local 'analysis' (a nil value)`. The chain, measured rather than
guessed: a self call makes the abstract analysis create an instance per *packet*, the packets do not
converge, and `Run:instance` runs out of its 256-instance budget and returns `nil` (five exhaustions
for this twelve-line program). `Emitter:specialized_instance` handles that `nil` -- "which is how a
cycle terminates" -- by falling back to the generic instance, but `Emitter:generic_instance` does not:
it memoises *after* recursing, so a re-entrant lookup recomputes and builds an instance whose
`analysis` is `nil`, and `emit_instance` dereferences it.

The elegant fix is the one the compiler already has: `known.lua` carries **loop widening**, which is
exactly the mechanism that stops a packet from spawning new instances forever, so a recursive call
should widen to a fixpoint the same way a loop does. The second half is small and independent: an
instance must never be built without an analysis.

**Forward references do not resolve, so mutual recursion is impossible.** `is_even` referring to
`is_odd` defined below it is `unknown name is_odd`, at top level and inside a body alike. That is what
forces a real program to nest everything inside one word or into imports -- and it is what makes the
two result-type gaps above unreachable, because only mutual recursion would ask for a result the
terminal's `do : T` could not state.

The elegant fix is another reuse: `resolve.lua` already separates *declaring* a name
(`Context:definition`, `publish`) from *resolving* a body, so a statement list can declare every
binding's name before resolving any initialiser, with the existing `ctx.resolving` check keeping "a
binding is not visible in its own initializer" true. That is a two-phase scope, and it is the shape
the resolver is already built from.

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

0. **The two bugs found while starting item 1**, because they come first by measurement rather than by
   guess: the recursive-call crash (packet widening, which `known.lua` already has for loops, plus
   never building an instance without an analysis) and forward references (a two-phase statement
   scope, which the resolver's declare-then-resolve split already implies). Until forward references
   resolve, mutual recursion is impossible and the two result-type gaps below stay unreachable.
1. ~~Cause 4, by deletion.~~ **Withdrawn**: those two sites are not reachable by the shapes that
   would exercise them, and the inference path is not what keeps them alive.
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
