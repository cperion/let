# Refactor plan: one authority per fact

Status: **in progress.** Steps 1, 2 and 5 are done and pushed; step 3 is done in mechanism with 28
of its 63 sites classified; step 4 is done in the half that does not change a representation. Two
steps were corrected by measuring them, and both corrections are recorded below rather than
quietly applied. No step here changes the language or the specification. Every step removes a
representation or sharpens an error class; none adds a mechanism.

This document exists because a session of writing *real programs* — an iterator, a state machine, a
buffer walk — turned up a run of defects, and they were not independent. Each one was **the same
fact stored in more than one place, with no single authority**, so the copies drifted:

| Found | Where two authorities disagreed |
| --- | --- |
| `B.Sum:owns` was a hardcoded `false` | a per-type method beside the central `owns()` rule |
| `{ let at mut : Int }` silently dropped `mut` | `A.Binding.mutable`, `A.Stage.capability`, `B.Field.mutable` |
| `mut` on a member demanded a mutable place from the supplier | the same qualifier read as a *borrow capability* by `aggregate_word` |
| `ownership = 'borrowed'` / `nullable` declared and ignored | `libc.lua` declares, `vocabulary.lua` validates, nobody reads |
| `gap` used for a deliberate ownership rule | two error classes in one constructor |

The design has held up: four separate questions this session resolved to "these were already the
same thing". So the refactor is in the implementation, not the model.

## Invariants

Every step obeys all of these. A step that cannot is the wrong step.

1. **No language change.** The specification is sealed for this model. If a step would change what a
   program means, it is a separate decision, documented as such, and not part of this refactor.
2. **Green on both runtimes after every step.** `luajit test/all.lua` and `lua test/all.lua`. The
   bundle suite is LuaJIT-only by design, so the expected counts differ by 7.
3. **One commit per step**, in the order below, each with the reason and the evidence in the message.
4. **A step removes a representation or splits an error class.** No new abstraction layers, no new
   indirection, no "prettier" rewrites that a bug does not justify.
5. **Behaviour-preserving, and shown to be.** Where a step collapses two authorities, a test must
   demonstrate that the surviving authority gives the same answers before and after. Where a step
   changes an error class, a test must name the new class.
6. **`dist/let.lua` regenerated** with `luajit bundle.lua` in the same commit.

Baseline when the plan was written: `luajit test/all.lua` → 912 checks in 20 suites; `lua
test/all.lua` → 905 in 19. After steps 1, 2, 3, 4-half and 5: **926 in 21** and **919 in 20**.

## Order

Ordered by (value ÷ risk), and deliberately safety-net first, because the net is what found all of
this.

| # | Step | Size | Risk | Status |
| --- | --- | --- | --- | --- |
| 1 | Real-program corpus | small to start | none (additive) | **done** (5 programs, 2 refusals) |
| 2 | Descriptor-field audit | tiny | none | **done** |
| 3 | `refuse` versus `gap` | medium | low | **mechanism done, 28 of 63 sites classified** |
| 4 | Qualifiers read once | medium to large | medium | **half done; see the correction** |
| 5 | `owns`/`borrows` un-overridable | small | low | **done** |

Step 5 was originally first. It is last now because the measurement moved it: see the correction
below.

---

## Step 1 — Real-program corpus

**Why.** Every defect in the table above was found by trying to write a program, not by reading
code. The existing suites prove each mechanism in isolation and never prove that mechanisms
compose, which is exactly where all of these lived.

**What.** A directory of Let programs that must build, emit, and **run**, in `test/all.lua`, under
both runtimes. Start with the programs this session actually wanted:

- `fold`/`each` with a word-typed body stage; body named, inline, and through a variable.
- A state machine: a record with an interior mutable member, a `next` word returning a sum, driven
  by `while` and a `switch` on the tag.
- A buffer walk through a view (`c.text_of`, `c.load_byte`, `c.store_byte`).
- A sum tree with an owned payload, injected, projected and dropped.
- A place/borrow sequence: move, partial move, borrow, write through a mutable field.
- A Text view whose owner outlives it, and the same with the owner moved (must be refused).

**Where.** `test/programs/*.let` as sources, and a driver `test/programs.lua` that runs each through
`build` → `verify_flow` → `emit` → `test.execute`, comparing observable results. Interpreter-only
keeps it fast and needs no C compiler; a couple of cases may be promoted to `test/native.lua` when
the emitted C is the thing under test.

**Acceptance.** The driver is in `test/all.lua`; each program states its expected result inline; the
suite fails if a program stops building or its result changes.

**Note.** This corpus is the acceptance test for steps 3, 4 and 5. Those steps should be landed
*behind* it, and it will grow as gaps close.

---

## Step 2 — Descriptor-field audit

**Why.** `ownership = 'borrowed'` and `nullable` were declared in `libc.lua`, validated in
`vocabulary.lua`, and read by nothing. A declaration the compiler ignores is worse than no
declaration: it reads as a promise. `ownership` is now half-honoured (`borrows` is read;
`ownership` itself still is not). `nullable` appears **only** in the assert that validates it.

**What.**

1. For every field a host or conversion descriptor may carry, name its consumer in a table in
   `vocabulary.lua` — `purity`, `phase`, `symbol`, `signature`, `c`, `ownership`, `nullable`,
   `borrows`, `helper`, `conversion`, `resource`, `representation`, `destroy`. Validation asserts
   that every key present in a descriptor has a consumer, so a field cannot be added without one.
2. Decide `nullable`'s fate: honour it (a non-nullable pointer result may not be tested for null)
   or delete it.
3. Re-decide `ownership`: either it is the boundary's statement that Let must not free the result,
   and it is used by the destructor path, or it is subsumed by `borrows` and deleted.

**Acceptance.** No descriptor field is accepted without a consumer; the assertion fails if one is
added. A test asserts the failure.

**Trap.** A word-based `grep` cannot do this audit: `ownership` is also an English word used
throughout `let/` and in comments. The consumer table must be explicit rather than inferred.

---

## Step 3 — `refuse` versus `gap`

**Why.** `gap` means "not implemented". It is also used for deliberate rules, and the two are
indistinguishable from outside — which cost real time this session:

```lua
-- program.lua, before the call
-- §6.5: ... That is an ownership error, not a missing lowering.
gap(span,'transient read borrow of owned state')
```

A rule reported as an omission means a reader cannot tell whether a program should be rewritten or a
compiler feature is absent. That distinction is the whole difference between the language and the
implementation.

**What.**

1. Two constructors: `gap(span, message)` for "the compiler has not built this" and
   `refuse(span, message)` for "the language forbids this". They may share a mechanism; they must not
   share a name.
2. Classify all **62** `gap(` sites — 46 in `build.lua`, 16 in `program.lua`. Each becomes `refuse`
   (a rule), stays `gap` (an omission), or is deleted. Sites whose surrounding comment already says
   "ownership error", "the specification does not define", or similar are `refuse` by construction.
3. A test that every remaining `gap` corresponds to an entry in `COMPILER.md`'s gap list, so the
   inventory is checkable rather than remembered.

**Acceptance.** A program that violates a rule reports a refusal; an unimplemented combination
reports a gap; the gap list in `COMPILER.md` matches the `gap` sites.

**Size.** 62 sites is mechanical, but each needs a judgement. Do it in two commits if the diff is
unwieldy: `program.lua` first (16), then `build.lua` (46).

---

## Step 4 — Qualifiers read once

**Correction, measured before starting.** The plan said to carry `own` and `mut` as two bits on
`Binding` and `Stage` and derive the capability in one function. The first half of that stops short
of the truth: the enum is not only `A.Stage`'s field, it is also `B.Parameter`'s, and
`B.Parameter(Type, Capability)` is constructed at 39 sites across `let/` and `test/`. So changing
the representation means changing the belt and the whole test corpus with it, which is not a step
to slip into a sequence of small ones.

**What landed instead** is the half that removes the duplication without moving the enum: both
directions now live in one place, `A.capability(own, mutable)`, `A.owns(capability)` and
`A.places(capability)` in `ast.lua`, and the sites that decoded the enum by hand use them -- the two
identical derivations in `parse.lua` and the five in `packet.lua` that asked "is this a place" or
"does this own". The sites that genuinely distinguish `Mut` from `OwnMut` keep comparing the enum,
because that is a different question.

**Still to do** is the representation change, and it should be scoped on its own with the corpus in
place: `B.Parameter`'s field, `libc.lua`'s declarations, and the 39 construction sites.

**Why.** This is the real structural item, and it produced two of the defects above. One qualifier,
`mut`, is stored in three places and re-derived in about eight:

- `A.Capability = Read | Mut | Own | OwnMut` (`ast.lua`) — a four-way enum encoding the **product**
  of two independent questions: *who owns* and *may it be written*.
- Derived from `(own, mutable)` by the **same expression in two places** —
  `parse.lua:125` (`items`) and `parse.lua:156` (`extern_parameter`).
- Decoded back into its two bits at `packet.lua:30,37-40,47-50,92-93`, and again in
  `aggregate_word` (`parse.lua:289-291`), which has to *rewrite* the enum because a member's `mut` is
  a fact about the record while a stage's is a fact about how it is supplied.
- `.capability` is read at 29 sites across the compiler; `A.Binding.mutable` and `B.Field.mutable`
  are two further homes for the same question.
- `bind_argument` (`binding.lua:11-24`) is the enum's functional semantics: `Own` and `OwnMut` share
  one implementation, which is the product showing through.

**What.**

1. Carry the two bits: `own` and `mut` as booleans on `Binding` and `Stage` — or one small record
   with a name, so `item.own` reads as plainly as `item.capability` does now.
2. Derive `capability` (if a label is still wanted for `bind_argument`) in **one** function, and keep
   `bind_argument` as a function of the two bits rather than a method on a four-way enum.
3. Replace the inline decodings with named predicates — `owns(qualifiers)`, `places(qualifiers)` —
   so no site re-derives them. `packet.lua`'s five sites are the reason.
4. Keep `A.Binding.mutable` (the value form) and `B.Field.mutable` (the type form) as distinct
   questions — they genuinely are — but ensure `mut` reaches both from a single reading, which is
   what `aggregate_word` + `word_terminal_type` now do by hand and should do by construction.

**Proof.** Step 1's corpus plus the existing suites, unchanged. Step 5's belt test covers the belt
half.

**Acceptance.** The derivation expression appears once. No site compares `capability` against a
constructor to answer "is it writable" or "does it own". `aggregate_word` no longer rewrites a
capability; it reads `mut` and `own` for the two different questions they answer.

**Risk.** 29 sites in `parse.lua`, `packet.lua`, `build.lua`, `program.lua`, `binding.lua`,
`verify.lua`. Land it in two commits: introduce the two bits alongside the enum, migrate consumers,
then delete the enum. The intermediate state is ugly and is the point — it makes the migration
reviewable.

---

## Step 5 — `owns` and `borrows` un-overridable

**Why, and a correction.** The original diagnosis was that `owns`/`borrows` have two authorities —
a per-type method and a central function — and that a new constructor could silently inherit a wrong
default. **The measurement disagreed.** There are no per-type overrides left: `B.Type.owns ==
B.Named.owns` is `true`, because the union's methods are attached to every class table as one shared
function. Deleting `B.Sum:owns` earlier in this session already collapsed the duplication. The
scalars correctly rely on the central function's fallback, and the structural constructors are
answered explicitly *inside* that function.

So this step is small and is about keeping it that way.

**What.**

1. Keep one authority: the central `owns`/`borrows` functions, reached through `B.Type`. The 10
   method call sites (`build.lua` 7, `program.lua` 3) may stay as methods or become explicit calls to
   the helper; either is fine, provided there is one implementation.
2. Make drift impossible rather than merely detected. An assertion where the belt is defined that no
   class table carries its own `owns`/`borrows` — i.e. `rawget(class,'owns') == B.Type.owns` for
   every constructor — turns a silent override into a load-time failure.
3. Keep `test/belt.lua`, which pins the agreement for all 21 constructors. Note precisely what it
   buys: it is **tautological today** (it compares the shared function with itself) and it is
   **sensitive to the failure mode** — reintroducing `B.Sum:owns` makes `type_:owns()` call the
   override while `B.Type.owns(type_)` calls the central one, and the test fails. That is the right
   property for a regression guard, but it must not be described as proof that the two currently
   differ.

**Acceptance.** A reintroduced per-type override fails either at load (the assertion) or in
`test/belt.lua`.

**Already done.** `test/belt.lua` also guards the union's completeness: `B.Type.members` enumerates
the constructors, so a constructor added without a sample fails the test. Writing it caught two
vacuous guards — a hardcoded count comparing two hardcoded lists, and a regex that never matched
because a class prints as `Class(Belt.Sum)`. An explicit "was the list actually read" assertion is
what found the second.

---

## Out of scope: the gap inventory

These are **not** this refactor. They are unimplemented combinations, they are declared as `gap`
calls, and they are worth planning separately because they are what stands between Let and the
programs people will want to write. Step 3 is what makes this list checkable.

| Gap | Consequence |
| --- | --- |
| `word-valued stages` | a body that captures non-Copy or mutable state cannot be passed to a word-typed stage, so the callback-that-accumulates is unavailable |
| `source/indirect word invocation` | a word chosen at run time cannot be called |
| `non-Copy lexical captures` | a closure cannot hold owned state |
| `transient read borrow of owned state` | an owned stage cannot be lent to another call |
| `conditional destruction of an address-taken binding` | an owned binding that is borrowed inside a loop cannot be released |
| `tail invocation borrow does not outlive caller cleanup` | `return f(borrowed)` must be written `let r = f(x); return r` |
| word signature inference | a word passed as an argument whose result is a nominal aggregate infers `do Unit` (observed; not yet reduced) |
| no `for`, no arrays | iteration is `while` plus a handler; data lives in host buffers |
| `T.match` handler-fold | sum elimination is `switch` on the tag plus a projection |
| runtime type values | decided against; a descriptor is the price and the model does not pay it |
| C-union sum layout | a sum is tag plus every alternative inline, so a sum value is as wide as the sum of its alternatives |

The first four are one project, not four: a word value that carries its captures. `resolve.lua`
already computes the ordered capture set per template (`template.captures`), so a statically known
word can be specialized with its captures threaded as parameters — direct calls, no dispatch. The
line to hold is that a word whose template is **not** statically known stays refused, which keeps
runtime vtables out of the language by construction.

## How to measure progress

- `luajit test/all.lua` and `lua test/all.lua` green, counts reported in every commit message.
- `test/belt.lua` passing with no constructor missing a sample.
- No descriptor field without a consumer (step 2's assertion).
- `grep -c 'gap(' let/` decreasing only as sites are classified, and the remainder matching
  `COMPILER.md`.
- The corpus growing, and the specific defects above each having a test that fails without its fix.
