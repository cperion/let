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

### Cause 2 — address-taken state and write-back (3 sites)

`conditional destruction of an address-taken binding` · `address-taken locals` ·
`mutable borrowed resource stages`

~~`tail invocation from a word with mutable state`~~ **Fixed**, and not by address-taking. State that
has to come back through the result does have somewhere to go when the transfer is to the *same*
entry: its packet *is* the state, so the recursion is a loop with the state as a loop variable, and
the write-back happens once, when the chain returns. That is sound for a self transfer and only for
one, so the gate is now the fact rather than an over-approximation of it — `ctx.state_written_back`
(`Packet.written_back`: state that really returns) *and* the target being a different entry. The old
`ctx.mutable_state` also covered state reached through a place, which returns nothing and needs no
continuation at all, so it refused a case that was already sound; the predicate is deleted rather
than left beside its replacement.

Measured both ways: `test/programs/tail_state.let` and a compiled `tail_state` case compute
3 + 2 + 1 = 6, and a transfer to a *different* word still gaps, now saying which half is missing.

**The rest of this cause is unchanged.** For a non-tail invocation the compiler already writes a
callee's mutable retained state back to the caller: `Packet.written_back(record.field)` decides which
fields are results, and the callee returns them (`program.lua`, the `updated` list).

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
guessed: a self call makes the abstract analysis create an instance per *packet*, a recursion with
no base case never repeats a packet, and `Run:instance` runs out of its 256-instance budget and
returns `nil` -- five exhaustions for this twelve-line program. `Emitter:specialized_instance`
handles that `nil` -- "which is how a cycle terminates" -- by falling back to the generic instance,
but `Emitter:generic_instance` did not: it built an instance whose `analysis` was `nil`, and
`emit_instance` dereferenced it.

**Fixed.** The obvious fix -- bound the analysis by *function* rather than by packet, so a recursive
call answers `nil` and widens -- is wrong, and measuring said so: it cost `fact(5)` its constant and
took the emitted C from 30 lines to 181, because a recursion that *does* converge folds today and
should keep doing so. The budget is only reached by a recursion that does not converge, so the
degradation there is correctly *no folding*: `Run:blank` gives the emitter an analysis that knows
nothing, every block stays live, and the demand pass still decides what is materialized. `fact(5)`
still folds to `INT64_C(120)`; the non-converging program now emits. Both are pinned in
`test/emit.lua`.

**Forward references do not resolve, so mutual recursion is impossible.** `is_even` referring to
`is_odd` defined below it is `unknown name is_odd`, at top level and inside a body alike. That is what
forces a real program to nest everything inside one word or into imports -- and it is what makes the
two result-type gaps above unreachable, because only mutual recursion would ask for a result the
terminal's `do : T` could not state.

**The fix is not the two-phase scope this document first proposed, and finding out why is the useful
part.** Pre-declaring every name in a statement list makes `let a = b + 1` before `let b = 2`
resolve, and that program reads `b` before its initializer runs. Forward references are only sound
for a *deferred* use -- one inside a word body, which runs at invocation -- and not for an immediate
one in a value initializer. `Context:lookup` would also have to check `ctx.resolving` *before*
`peek`, because once the name is pre-declared the self-visibility diagnostic stops firing.
So the change needs the deferred-versus-immediate distinction, which is a question about what the
language means (`let a = b` against `let a = let ... b ... end`), not a resolver refactor. It belongs
with the spec open, not in a gap-closing pass.

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

0a. ~~The recursive-call crash.~~ **Fixed**.
0b. **Forward references: the resolver half is done, the builder half is not.** The rule that makes
    them sound turned out to be two conditions plus a check, and all three are now implemented and
    tested: a use may reach a pending declaration only from inside a word's body *and* only when the
    declaration is module-level, whose storage is allocated with the module's state record; and a
    word that makes such a reference may not itself be invoked while the module is initializing,
    which is checked after the module resolves because the word's template is not known until its
    binding does.

    What lands with it: a statement list and a chain now *declare* their names before resolving any
    of them, so `unknown name` is no longer what an early use reports -- `b is used before its
    initializer runs` is -- and the duplicate-binding report is idempotent across the two passes.
    Recursion still works, because §4.2 makes the defining word visible inside its own terminal.

    What remains for mutual recursion to actually build: a forward capture needs a cell that exists
    before the statement that initializes it. Working out how gives a narrower route than
    "pre-allocate module state", and two obstacles worth stating.

    **The route.** A module binding that a word captures is already given *global* storage
    (`Allocate` uses `C.Global` when the binding is a module cell), and a C global's address is valid
    from program start -- so the reference is sound before initialization, which is exactly the
    premise the resolver's rule relies on. What is missing is that the builder cannot *name* that
    cell yet: it allocates it where its statement appears, and a capture reaches it through the
    cell's value reference. So the fix is a forward-declared module cell: allocate it before the
    chain's items resolve, and bind the name to it, so the capture finds storage instead of nothing.

    **Obstacle one: the cell's type must be known before the value is built.** For a general binding
    it is not -- an unannotated one has no type until its initializer is built. For the case that
    matters, a *word* binding, it is: a word's belt type follows from its template (`Do` or `Arrow`
    over it), so a word-to-word forward reference can pre-allocate with a type in hand. That is
    exactly mutual recursion, which is why the narrow version is worth having.

    **Obstacle two: the cell's C name must be stable.** Names come from instruction position
    (`v<block>_<index>_c`), which is not known until the cell is emitted. Pre-allocating needs a name
    derived from the binding instead -- `let_mod_<name>` -- which is a small emitter change but
    touches every module cell, so it wants the corpus as its net.

    So: feasible, scoped, and not landed here. `Builder:instantiate` refuses with `a word cannot
    capture X yet: it is declared later, and its storage is not allocated up front` until it is.


0. ~~The recursive-call crash.~~ **Fixed**, by letting the analysis answer `nil` and having the
   emitter degrade to no folding rather than to an instance with no analysis. Testing the obvious
   fix first is what stopped it: bounding the analysis by function cost `fact(5)` its constant.
   Pinned in `test/emit.lua`.
1. **Forward references, with the spec open.** Not the two-phase scope this document first
   proposed: pre-declaring names makes `let a = b + 1` before `let b = 2` resolve, and that reads
   `b` before its initializer runs. It needs the deferred-versus-immediate distinction. Until it is
   decided, mutual recursion stays impossible and Cause 4's two sites stay unreachable.
2. ~~Cause 4, by deletion.~~ **Withdrawn**: those two sites are not reachable by the shapes that
   would exercise them, and the inference path is not what keeps them alive.
1. ~~Cause 4, by deletion.~~ **Withdrawn**: those two sites are not reachable by the shapes that
   would exercise them, and the inference path is not what keeps them alive.
2. **Cause 3's `two runtime indices`.** Reuses `select_member`; small and self-contained.
3. ~~Cause 2's tail write-back.~~ **Done**, and it needed less than this list assumed. The write-back
   already existed for a non-tail call; what was missing was noticing that a *self* transfer carries
   the state as its own packet, and that the gate was an over-approximation of what returns.
4. **Cause 1, the statically known half.** Closes five sites and unlocks the callback-that-accumulates
   and `T.match`. Bigger than the three above, and the one with the most value.
5. **Cause 6's message.** Trivial, do it with whichever of the above touches that area.
6. Leave Cause 3's loop analysis and Cause 5 until the four above are done; both are real work whose
   absence is at least *stated* clearly now.

## What this changed about how I judge a gap

A message alone cannot be classified. Three of 28 were wrong, and each time the surrounding comment
had the answer. So the rule is: read the comment, ask the discriminator question, and when it names an
analysis rather than a fault, leave it a `gap` and say so.
