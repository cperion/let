# Demand-driven evaluation: design

Design target for the step after AST-to-belt construction and C emission. The
authoritative input is [the Let specification](../let-language-specification.md);
this document does not redefine Let. Where an implementation limit is chosen, it says
so instead of presenting the limit as a language rule.

Related: [WORDS.md](WORDS.md) (staged words), [BUILD.md](BUILD.md) (construction),
[README.md](README.md) (current status).

## 1. Where we are

Emission is already demand-*pruning*: `Function:demands()` decides which producers are
written out. What is missing is demand's second job — **computing**. Today a value is
either emitted as a runtime variable or dropped; it is never *known*.

So the gap is precisely: **the compiler never executes the pure fragment.** That is why
`multiply 6 7` followed by `a()` still emits a call, an entry function and a multiply,
when the entire computation is a compile-time constant.

## 2. What folding is permitted to do

§4.3 is the charter:

> The compiler may fold, eliminate, or reorder only when the resulting behavior is
> observationally equivalent, including effects, traps, ownership transfer, and
> destruction order.

Four further rules pin down what "observationally equivalent" excludes:

| Rule | Source | Consequence for this design |
| --- | --- | --- |
| Ordered vocabulary stays in the dynamic context where the source placed it; known arguments do not change a word's declared phase. | §12.2 | A `ordered` call is **never executed at compile time** and never removed while reachable. Its result is opaque. |
| A check may be omitted when its failure is proved impossible; a possible and observable failure must not be removed. | §16.2 | Divisor known non-zero → fold and omit the check. Divisor known zero → **residual trap**, not a compile error. Divisor unknown → keep the checked operation. |
| A trap immediately leaves through the host hook; normal destructors are not run. | §14.2 | A residual trap terminates that path; already-scheduled work before it stays, cleanup after it is unreachable. |
| Pure operations may be simplified only while preserving their results; module-initialization effects occur at initialization, not during compilation. | §12.2, §15.1 | Module-initialization work is emitted, not performed by the compiler. The compiler may only *reason about* it. |

The single organizing consequence:

> **Pure operations fold. Ordered operations are scheduled.**

Executing a pure operation is not "running the program" — it is evaluating a function.
Executing an ordered operation would be running the program, and the spec forbids it at
compile time. Everything below follows from keeping those two apart.

## 3. Two machines, one opcode semantics

Let is easy to interpret, and there are two interpretations we need. They differ only in
whether the domain has a top element.

| Machine | Values | Use |
| --- | --- | --- |
| Concrete interpreter | exact | differential oracle against compiled C |
| Abstract evaluator | `Known(v)` or `Runtime` | this document |

`test/execute.lua` is already the concrete machine. The abstract evaluator should share
its per-opcode definitions so the two cannot drift: one table of `Op -> semantics` with a
domain parameter. Concretely, the concrete machine is the abstract machine with `Runtime`
removed and every input known.

**Evaluate the belt, never the AST.** The belt has already resolved stages, preludes,
ownership, lifetimes, word bundles and destinations. Re-interpreting source would rebuild
all of that and drift from it. `v2/known.lua` therefore takes a `Belt.Function`.

## 4. Domain

An **answer** is one of:

```
Known(v)     -- exact: Int64, Bool, Unit, Text, or a word/aggregate bundle
Runtime(T)   -- opaque runtime value of belt type T
```

`⊤` is `Runtime`. There is deliberately no `⊥` in the *fact* lattice: a producer's answer
is `Runtime` until some evaluation proves it `Known`, and only genuinely derived facts are
`Known` (§2 forbids guessing).

Word bundles are `Known` when every field is `Known`; a mixed bundle is not representable
in Milestone A and is `Runtime`. Milestone B replaces this with `Partial{template, fields}`
so a word with known template but runtime state stays precise.

**Joins.** At a merge, `Known(x) ⊔ Known(x) = Known(x)`; anything else is `Runtime`.
Joining is monotone and used only to move *toward* `Runtime`, never to invent `Known`.

**Effects are not values.** An effect token is the residual program's schedule position.
`Known` is never claimed for a producer whose results include `Effect`. This is what makes
the purity gate structural rather than a convention: an ordered operation's output type
list contains `Effect`, so it cannot be folded by construction.

**Exact Int64.** Known integers use LuaJIT `int64_t` cdata so arithmetic is exact and
matches the concrete interpreter. Structural equality of answers is decided by a
`same(a,b)` predicate, not by using cdata as a table key.

## 5. Answers, memoization and contexts

Producers are memoized per **demand context**:

```
Context = { function instance, abstract incoming packet, demanded outputs }
answer(context, block, position, output) -> Answer
```

Milestone A uses exactly one context per function: the incoming packet is all `Runtime`
(so a function is analyzed generically, as today). Milestone B adds one context per
distinct abstract packet at a call site — this is where answer-type specialization comes
from, and it replaces the old compiler's single inferred callback contract (WORDS.md §7).

Memoization is keyed on `(context, block, position, output)`. The belt is never mutated and
never renumbered; answers live in side tables.

## 6. Evaluation rules

Requesting an answer for a producer may recursively request its inputs. Only demanded
producers are asked (§7).

| Operation | Rule |
| --- | --- |
| `IntegerLiteral`, `BooleanLiteral`, `UnitLiteral`, `TextLiteral` | `Known` |
| `Unary` | fold iff operand `Known` |
| `Binary` | fold iff both operands `Known` |
| `CheckedBinary` | divisor `Known ≠ 0` → `Known`, check omitted; otherwise the residual checked operation is kept, so a known-zero divisor still traps at run time rather than becoming a compile-time diagnostic |
| `Pack`, `Project` | fold iff base `Known` |
| `Construct`, `LoadField`, `StoreField` | fold iff all inputs `Known` |
| `PureHostCall` | not folded; residual iff demanded; result `Runtime` |
| `HostCall` | always residual; advances the schedule; result `Runtime` |
| `Load`, `Store`, `Allocate` | not folded (memory identity is observable); residual iff demanded |
| `Move` | identity on the value; advances the schedule |
| `Destroy` | residual; advances the schedule |
| `CallFunction` | see §9 |
| `Ref` to a block parameter | the parameter's answer |
| `Ref` to an unsupplied word field | `Runtime` (Milestone A) |

Arithmetic must reproduce §13.2 exactly: wrapping `+ - *`, truncated `/`, dividend-sign
`%`, and `INT_MIN / -1 == INT_MIN`. Reusing the concrete interpreter's operators
guarantees this by construction.

## 7. Demand roots and the worklist

Roots are the observable obligations, not "every instruction":

- exit operands — return values, both branch conditions, trap and tail-call inputs;
- the entry effect, so ordered work in a nonreturning loop is preserved;
- any producer whose `Effect` output is demanded (transitively through the schedule).

`Function:demands()` already computes exactly this closure. Evaluation runs **backward to
discover** and **forward to schedule**: demand decides what to ask; the evaluator answers
in effect order so a scheduled operation is never reordered (§4.3).

## 8. Control flow

Ordered work on a falsified branch must not be emitted, so evaluation must know branch
decisions. Two rules keep this sound in Milestone A:

1. **Acyclic regions only.** Compute the function's cycles (SCCs). Every block parameter of
   a block inside a cycle is `Runtime`. A known condition still selects an edge, but values
   are not folded across a backedge. This is conservative and obviously sound; it avoids
   needing widening before the rest of the machinery is proven.
2. **Reachability follows decisions.** If a branch condition is `Known`, only the taken
   edge is live. A block is emitted iff some live edge reaches it.

**Implemented: fixed-point iteration with widening.** The earlier rule made every packet of
a block in a cycle `Runtime`, which discarded all loop-carried information. The evaluator now
runs an optimistic fixed point and then *verifies* it:

1. `incoming` joins the contributions of every live incoming edge. A predecessor packet
   field that has no value yet contributes nothing, which is what lets the first pass be
   optimistic about a loop-carried value.
2. `verify_packets` recomputes the true join from the settled answers. A stored `Known`
   packet that disagrees with what the edges actually supply was an unsound guess, so it is
   widened to `Runtime`.
3. A widened packet is remembered and stays widened, so the iteration moves only toward
   `Runtime` and cannot oscillate. `widen_cycles` is the sound fallback when the iteration
   budget runs out.

The result is that a loop-invariant value stays `Known` while a varying one widens:

```let
let run = do
    let bias = 7
    let total mut = 0
    let i mut = 0
    while i < 3 do
        total = total + bias * 2    // folds to `total + 14`
        i = i + 1                    // widens
    end
    return total
end
```

`bias * 2` is folded away and no multiplication helper is emitted, while the loop itself is
still emitted as a loop. Soundness is checked by execution, not by inspecting the C: a
witness whose accumulator varies must print the value the loop computes, because an unsound
fold would print a plausible wrong constant.

**Implemented: enumeration.** Widening deliberately forgets an induction variable, so a loop
whose result is a constant still gets emitted. Before falling back to widening, `analyze`
first tries `enumerate`: concrete-abstract execution that follows one iteration at a time
while every control decision stays decidable. Each visit seeds a block's packet from the
edge that reached it, so the header is entered with `i = 0`, then `1`, then `2`, and the
condition is decidable at every step. If a `Return` is reached with every value result exact
and nothing ordered was demanded, the function is *folded*: `folded` is set and the emitter
writes the body as the constant it computes — no blocks, no labels, no gotos.

Enumeration gives up, and widening takes over, on anything it cannot decide: an undecidable
branch, demanded ordered work, an instance it has already visited (a period, or an
unbounded loop), or the step budget (`options.unroll_limit`, default 32). Giving up is
always sound because the fallback is the widening analysis, and widening is sound.

The budget is what keeps this honest. A loop of five iterations folds to nothing; a loop of
a million falls back and is emitted as a loop, which is correct and which the C compiler
then reduces on its own.

**Still open: unrolling a loop that has effects.** A decidable loop whose body demands
ordered work cannot be executed, so it is emitted as a loop rather than unrolled. Unrolling
it would need block *instances* in the emitter — the same block written once per iteration
with its own packet values and labels.

Nontermination: the compiler must always terminate. Fuel and widening exist for that, and a
budget exhaustion is an **implementation limit**, not a proof about the program (§2, and
see §12).

## 9. Calls, summaries and recursion

A `CallFunction` needs the callee's answer. Options, in order of increasing power:

- **Fold when the packet is fully known and the callee has no demanded effects.**
  Evaluate the callee body with its parameters seeded from the call's argument answers. If
  every demanded result is `Known` and no ordered work is demanded, substitute the known
  results and do not emit the call or the entry.
- **Otherwise emit the call as today**, with the entry built for runtime parameters.

Milestone A implements the first case with a guard: a target is foldable only if its
evaluation demands no ordered work and yields known results, and the foldability of a
recursive cycle is decided by a worklist that starts optimistic and withdraws on
non-termination. A withdrawn cycle is emitted normally.

Milestone B generalizes this to **summaries** keyed by `(entry, abstract packet)`, so the
callee can be partially specialized: known fields are baked in and dropped from the
specialized ABI, unknown fields remain parameters. Different packets produce different
specializations, which is where answer-type polymorphism (WORDS.md §7) finally appears.
A summary is a fixed point over the call graph's SCCs, seeded with "result unknown".

## 10. Word state, places and invalidation

Interior mutable state is currently carried as SSA `StoreField` chains, so a known bundle
stays known through a store. That yields the counter case:

```let
let counter = let start:Int let value mut = start
              do value = value + 1; return value end
let errors = counter 0     // state known 0
let a = errors()           // 1
let b = errors()           // 2
```

Folding this is sound because the state is private and reachable only through those calls
(§5.2: deduplication is allowed when no observation, ownership action or destruction can
distinguish the results). Two *distinct* owners with the same template and the same known
starting value are still distinct owners: the instance identity, not just the template and
value, is part of the context.

Invalidation: a value whose address is taken, that is borrowed, or that is captured across
an escaping boundary must not keep a known-content assumption. Milestone A does not have
address-taken state, so the rule is simply: any `Load`/`Store`/`Allocate` result is
`Runtime`, and a bundle whose field is written by a non-foldable operation becomes
`Runtime`.

## 11. Emission contract

**No residual AST and no second semantic IR.** The emitter walks the original belt and uses
answers as an oracle, which is already how demand-pruning works. The changes are small:

| Today | With answers |
| --- | --- |
| skip a pure producer when undemanded | skip when undemanded **or** `Known` |
| `ref` yields a variable name | yields a C literal when the answer is `Known` |
| all reachable blocks emitted | blocks unreachable under known decisions are not emitted |
| every targeted entry emitted | an entry folded into its call site is not emitted |
| no effect on helpers/structs | a helper or struct only a folded producer needed is not emitted |

Because a folded producer emits nothing and its consumers inline the literal, the emitted C
shrinks along with the residual work. Correctness of the schedule is unaffected: ordered
operations are never folded, so their order and count are exactly the source order.

## 12. Honest limits

- A program whose inputs all come from the host folds almost nothing, and that is correct.
  Partial evaluation pays off for specialization, not for general programs. Reporting
  otherwise would be dishonest.
- An implementation budget (fuel, widening depth, summary-context count) is a compiler
  limit. When it is reached the compiler emits the residual program; it must not report a
  language error, because the program is not in error (§2, §16.1).
- Known-value reasoning is not a proof system. Every `Known` answer must be derivable from
  the rules in §6; "probably constant" is `Runtime`.

## 13. Testing

- **Differential oracle.** The concrete interpreter is the reference for behavior.
  Randomized programs are run both ways — belt interpretation and compiled C — and their
  observable output compared. This catches folding that changes effects, traps or
  destruction order.
- **Focused witnesses.** Each §6 rule gets a witness asserting the *emitted C shape*:
  folded arithmetic absent, helper absent, ordered call present and ordered, known branch
  arm absent, `1/0` still a residual trap, `INT_MIN / -1` folded to `INT_MIN`.
- **Non-regression.** Every surviving native test must keep printing the same output.

## 14. Milestones

**A — known evaluation and folding. — implemented.**
`v2/known.lua` is the abstract evaluator; `v2/scalar.lua` is the exact scalar layer it
shares with the concrete interpreter; `emit.lua` consults answers for constant
substitution, output pruning, known-branch selection, live-block filtering and live-entry
filtering. Call folding is keyed by `(target, abstract packet)` inside one shared run, with
a call cycle withdrawing foldability rather than recursing.

Delivered behaviour, all covered by `test/emit.lua`:

- pure arithmetic, comparison and bundles fold to constants, and the producers, helpers
  and structs they needed are not emitted;
- a known condition removes the branch, and the untaken arm's blocks are not emitted;
- a known non-zero divisor folds and its check is omitted (§16.2), while a known zero
  divisor keeps the residual trapping operation;
- a fully known call emits no callee function at all — `multiply 6 7` followed by `a()`
  becomes the constant 42, and two invocations of a known-state counter become 1 then 2
  with the state threaded through the fold;
- an ordered call inside an otherwise-known packet keeps its entry and its call;
- a runtime argument keeps the whole emitted call path.

Two real defects were found by this work and fixed: invoking a partial word no longer
rewrites the receiver binding (only interior mutable state is written back, and only into
the receiver's own bundle), and joins ignore edges from unreachable predecessors rather
than only falsified ones.

**B — partial bundles, summaries and loop unrolling.**
Loop widening and enumeration from §8 are done. What remains for B: `Partial{template,
fields}` so a word with a known template but runtime state stays precise, specialized ABIs
that drop known fields from the parameter list, SCC fixed points for mutually recursive
summaries, and block instances so a loop that carries effects can be unrolled rather than
left as a loop.

**C — scheduling and sharing.**
Deliverable: shared-result materialization (one C temporary for a producer with several
consumers), order-safe scheduling of demanded effectful results, and specialization
stability reporting in `statistics`. Acceptance: no duplicated side-effecting evaluation,
and a benchmark comparison against the old compiler.

## 15. Open questions

- Should a `Known` bundle with all-`Known` fields be interned so two structurally equal
  words share one emitted constant? §5.2 permits deduplication only when nothing can
  distinguish them; interning must therefore not merge two distinct mutable owners.
- How much of the acyclic restriction in §8 is worth keeping once widening exists? The
  conservative rule is safe but leaves known values unfolded inside loops that clearly do
  not modify them.
- Whether `PureHostCall` should ever be folded requires a host-supplied pure model. The
  language does not require one, and inventing one from the C symbol would be unsound.
