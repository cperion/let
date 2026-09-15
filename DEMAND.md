# Demand-driven evaluation: design

Design target for the step after AST-to-belt construction and C emission. The
authoritative input is [the Let specification](let-language-specification.md);
this document does not redefine Let. Where an implementation limit is chosen, it says
so instead of presenting the limit as a language rule.

Related: [WORDS.md](WORDS.md) (staged words), [COMPILER.md](COMPILER.md) (construction),
[ARCHITECTURE.md](ARCHITECTURE.md) (current status).

## 1. Where we are

Emission is already demand-*pruning*: `Function:demands()` decides which producers are
written out. The layer this document designed adds demand's second job — **computing** —
and it is implemented as `let/known.lua` (Milestone A below). A value is now emitted as a
runtime variable, dropped, or inlined as a `Known` constant, and `multiply 6 7` followed
by `a()` becomes the constant 42 with no call, no entry function and no multiply.

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
all of that and drift from it. `let/known.lua` therefore takes a `Belt.Function`.

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
from, and it replaces an earlier compiler's single inferred callback contract (WORDS.md §7).

Memoization is keyed on `(context, block, position, output)`. The belt is never mutated and
never renumbered; answers live in side tables.

## 6. Evaluation rules

Requesting an answer for a producer may recursively request its inputs. Only demanded
producers are asked (§7).

| Operation | Rule |
| --- | --- |
| `IntegerLiteral`, `FloatLiteral`, `BooleanLiteral`, `UnitLiteral`, `TextLiteral` | `Known` |
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
`%`, and `INT_MIN / -1 == INT_MIN`. Float arithmetic reproduces §13.3 through the same
shared `scalar` layer, including the `float`/`int` conversions. Reusing the concrete
interpreter's operators guarantees this by construction.

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

**`break` and `continue` are ordinary edges.** A `break` leaves the loop's strongly connected
component and a `continue` returns to its header, so the same join, reachability and packet
verification rules apply, and `enumerate` follows either concretely as it follows a backedge.

**Decided: a loop that has effects stays a loop.** A decidable loop whose body demands ordered
work cannot be executed, so it is emitted as a loop rather than unrolled. That is deliberate: the
belt is the residual program the source expressed, and duplicating side-effecting work is a
size/space choice the C compiler makes with the whole function in view. Unrolling would need
block *instances* in the emitter -- the same block written once per iteration with its own packet
values and labels -- and no measured case asks for it.

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
`let/known.lua` is the abstract evaluator; `let/scalar.lua` is the exact scalar layer it
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

**B — partial bundles and summaries.**
Loop widening and enumeration from §8 are done, and so is the partial answer.

`Known.partial` is a record with a known shape and a known value in *some* members. It is
not one constant, so it is never substituted or pruned; `is_known` still means "one
constant" and that is what substitution, pruning and arithmetic ask for, while `answered`
also admits a partial record. Delivered behaviour, covered by `test/emit.lua`:

- a member read through a partial record is answered with that member, so reading a known
  member emits no record and no projection -- the member's value is inlined and the
  construction becomes undemanded, where one run-time member used to make every member
  opaque;
- a member read through a run-time member is still a projection, and the record still has a
  C representation;
- the join of two records that are not one constant is taken member by member, so a member
  every path agrees on stays known.

Two latent defects surfaced while extending this, both fixed here:

- `analysis.folded` could claim a function's body *is* the constant it computes while a
  value it returns was still run-time. Decided control flow is not enough: every value
  result must be one constant, or the body has to be emitted.
- `Emitter:declare` skips an instruction whose result is already known, which silently
  dropped a *kept* call whose result happened to be known. A call that runs must be
  evaluated even when none of its outputs are read, so a kept call now emits
  `C.Evaluate(call)` when its value is a constant. Unreachable today, because a usable
  summary still has all-constant results; it becomes reachable the moment one does not.

Summaries are shared now, and the constraint that blocked it turned out to be the thing
worth fixing rather than working around.

- Every argument has an answer, a run-time one included, so asking for a summary is
  unconditional. What bounds the work is the budget and the in-progress mark, not a guess
  about which calls can fold.
- A summary answers and a summary *folds* are different questions. `answered` means every
  value result has an answer; `foldable` means every one is a constant and the callee
  demanded no ordered work. A precise but unfolded summary leaves the call in place and
  replaces only the uses.
- The fold mark rides on the answers array itself, written by the same call that fills it.
  A side table outlived them -- an answer table is rebuilt every pass -- and emission then
  removed a call whose result another expression still referred to by name.
- Consequently emission must evaluate a call it kept, even when every result it returns is
  a constant: the answer replaces the uses, never the call.

The limit that remains here is narrow and measured: an *ordered* call whose result no
consumer demands (a `PureHostCall` in a folded argument position, say) is emitted rather than
folded, because the analysis records answers only for the positions demand reaches. Evaluating
every instruction would fix it, and was tried: it also makes a pure producer in a folded
position disappear, which is correct per the host's `pure` declaration but changes what
`demands()` is for. Revisiting that rule is the prerequisite, and it is a smaller question
than this one was.

Specialized ABIs are started from the same place. An entry packet is the function's ABI, but
a stage the body never *reads* is not part of it: the signature drops that parameter and every
call passes one argument fewer. The scan is local to block 1 -- anything read elsewhere is
copied there by an edge, and that copy is itself a reference -- and it is recomputed from the
belt rather than read from the demand pass, because a callee and its call sites must reach the
same answer. An argument that is dropped is still *evaluated* when its own value is ordered;
only the passing stops.

Asking the demand pass instead was tried first and abandoned: it reports the module unload's
state parameter as unneeded although a `Destroy` consumes it, and two measurements of the
same table disagreed, so it is not yet a sound basis for an ABI. Dropping parameters whose
value is *known* at the call site is the rest of the feature and needs the other half of the
plan: a callee specialized -- and analysed -- per argument-knownness pattern, since the
emitted body's substitution of a parameter by a constant requires the seeded analysis, not
just a filter over the signature.

## 14a. One question, asked once

The emitter used to decide an output's fate in five places: `ref` for substitution, `known`
for a declaration, `folded_call` for a call, `needed_parameter` for an edge, and a second copy
of the last rule inside `function_parameters`. They had to agree, and nothing made them.

They are now one function. `Emitter:disposition(analysis,belt,block_id,position,output)`
answers with one of three fates:

| fate | meaning |
| --- | --- |
| `constant` | the value is known, so every use is that constant |
| `value` | it is materialized, and uses read it by name |
| `dropped` | nothing needs it, so neither it nor its producer is written out |

A parameter asks the same question with `position` equal to its 0-based index, which is where
its value lives in the entry packet; that, and where the answer is looked up, is the *only*
difference between a parameter and an instruction output, and it is stated once inside the
rule. The rule returns the answer it found, so no caller re-derives where an answer lives --
which is exactly the bug the first consolidation attempt introduced.

Alongside it:

- `Emitter:requirements(belt)` is the one demand input: the demand pass over the instruction
  positions, merged with the entry parameters block 1 reads (see below).
- `Emitter:instruction_runs(analysis,belt,block_id,position,instruction)` is the one answer to
  "is this instruction written out", and the body filter, the liveness walk and the call site
  all ask it.
- `Emitter:parameter_live(analysis,belt,block_id,index)` is the one answer to "does this
  parameter exist in C", asked by the signature, every call site and every edge copy. An
  effect never does: statement order carries it, so it is neither declared, nor passed, nor
  copied.

Two clauses were *removed* rather than added while doing this. An "ordered instruction is
always a value" clause turned out to be redundant -- every reachable block roots its own
effect parameter, so an ordered output is always demanded -- and the suite is green without
it. `Emitter:answer` and `Emitter:parameter_answer` went the same way. The count of rules went
down, not up.

### Why this is the shape the rest needs

Every rule above takes `(analysis, belt)` explicitly instead of reaching for the function
being emitted. That is not incidental: it means the unit of emission can become an
**instance** -- a belt function together with the answers of the entry packet it is called
with -- without touching any rule. `Run:summary` already keys its cache by exactly that pair,
so the instance key exists and is already deduplicated.

They are not just ready for it; emission works this way now. `Emitter:generic_instance(id)` is the
instance with no information about the packet -- which is what "one function per belt id" always
was -- and it is what the module interface itself uses. `Emitter:callee_instance` derives a call's
packet from the caller's own answers: a packet with no constant is the generic instance, one with
a constant gets an instance of its own, and a self-tail-recursive callee or an exhausted budget
falls back to the generic one, so every call resolves and the graph terminates. Emission *is* the
discovery: the roots are emitted first and writing their calls is what makes the rest live, so the
walk that guessed liveness is gone.

The value this already delivers, measured:

    let scale = let by : Int let x : Int do return by * x end
    let double = scale 2
    let r = double(n)                     -- n run-time

emits a specialized instance whose body is `LET_MUL(INT64_C(2), p1_2)`: the known stage is
inlined rather than passed, which is the point of specializing an ABI.

That also closed the ABI: a parameter exists in C exactly when its fate is `value`. `constant`
means every use of it is that constant, and `dropped` means nothing reads it, so neither belongs
in a signature -- and saying so in one place is what the five-way split could not do. The first
attempt at this unification asked `~= 'dropped'` instead, which keeps a substituted parameter in
the ABI; the measurement that found it was a specialized instance whose body inlined a constant
while its signature still passed it.

Both directions now specialize:

    let scale = let by : Int let x : Int do return by * x end

    let double = scale 2          -- by is known
    let r = double(n)             -- let_scale_3_2(int64_t p1_2) { return LET_MUL(INT64_C(2), p1_2); }

    let r = scale(n, 5)           -- x is known
                                  -- let_scale_3_2(int64_t p1_1) { return LET_MUL(p1_1, INT64_C(5)); }

with the generic instance unchanged beside them, because a call site whose packet carries no
constant still needs the ABI that passes everything.

The remaining items stop being separate features:

- **ABIs specialized per argument-knownness pattern**: emit one instance per key instead of
  one function per belt id. A parameter whose seeded answer is a constant is then `constant`
  in that instance and drops out of its signature by the rule that already exists.

What remains for B is otherwise unchanged:

- specialized ABIs per argument-knownness pattern, with the seeded analysis that implies;

**C — scheduling and sharing. — implemented.**
A pure producer with several consumers is materialized once and read by name; ordered results
are scheduled in source order and never duplicated; and `statistics` reports each instance's
specialized and folded flags and its widened field count, so specialization stability is
observable. The benchmark harness compiles, links (the embedding provides the `let_trap`
hook the emitted C calls) and validates every probe against the handwritten C reference:
`luajit bench/run.lua`.

## 15. Resolved questions

Each was open during Milestone A and the implementation settled it, so the decision is
recorded here rather than left implicit.

- **A `Known` bundle is not interned.** Two structurally equal bundles can still be distinct
  owners: §5.2 permits deduplication only when nothing can distinguish them, and an owned
  mutable value's identity is observable. `Known.same` decides equality for joins and cache
  keys; it never shares emitted storage. Revisit only for a case proved indistinguishable.
- **The acyclic restriction of §8 is not in force.** `let/known.lua` runs an optimistic fixed
  point and `verify_packets` widens any packet that disagrees with what the edges actually
  supply, with `enumerate` for a decidable loop and `widen_cycles` as the sound fallback. A
  loop-invariant value therefore stays `Known` while a varying one widens; the conservative
  rule is historical.
- **`PureHostCall` is never folded.** Folding a host call at compile time needs a host-supplied
  pure model; the language does not require one, and inferring purity from the C symbol would
  be unsound. A `PureHostCall` result is `Runtime` and the call is emitted, which
  `test/emit.lua` covers.
