# Let compiler

The compiler. It replaced the earlier one outright; nothing of that one remains.
[Let's specification](let-language-specification.md) remains authoritative.
`V.parse(text, file):build(options)` parses, constructs, and verifies a program;
`program:emit(options)` produces C and `V.print(unit)` renders it. Native
compilation of the covered language is tested end to end, so this is now a
compiler rather than a vocabulary sketch. See [COMPILER.md](COMPILER.md) for the
specification cross-check, API, implemented paths, and outstanding work.

## Three vocabularies

- `ast.lua`: Let syntax, including words, stages, preludes, aggregates, places, and
  structured control. Switch retains its subject and arms. No checked-AST clone.
  Match/pattern captures are intentionally not invented here.
- `belt.lua`: one semantic producer IR. Blocks have parameters, immutable producers,
  and an explicit exit. Values, effects, storage, ownership operations, and word
  preparation are represented here—not reconstructed from generated C.
- `c.lua`: output structures only. No binding-time domain, ownership state, or
  separate residual program. C spelling and integer-semantics helpers belong to
  the emitter; C signed arithmetic must not silently replace Let wrapping arithmetic.

`init.lua` loads these into one ASDL context. It reuses only the repository's ASDL
and List utilities, not `let.*`, its evaluator, or its residual backend.

## Number once

Within each block, producer positions are zero-based: block parameters first
(each produces one value), then instructions. Every instruction occupies one
position, regardless of output count. Its output slots are zero-based.

At consumer position `p`, `Ref(distance, output)` denotes output `output` of
producer `p - 1 - distance`. Distance zero means the preceding producer, not the
preceding live value. The exit's position is the end of the instruction sequence.
References cannot cross block boundaries or point forward. This is an unbounded
relative SSA representation, not a finite hardware belt.

Blocks and functions are indexed from **one** in their enclosing lists. Branch
edges explicitly pass values to block parameters. Backedges refer to block IDs,
not negative distances. Transfers are parallel: the emitter must not overwrite
one argument while another still needs its old value.

Keep producer numbering stable. Demand tables and cached evaluation answers live
outside ASDL nodes. Do not delete instructions and repeatedly renumber references.
Lexical name resolution and the current version of scalar locals belong to the
AST-to-belt construction context. Joins/loops use block parameters. Address-taken
and externally mutable state remains explicit storage.

## Observable roots

Effect tokens are semantic dependencies, not C values. Ordered calls, reads,
writes, ownership transitions, destruction, and potentially trapping arithmetic
consume an effect and produce its successor. A normal return carries the final
effect alongside any returned data. A trap carries prior effects but does not
request normal cleanup. Conditional edges forward the appropriate effect state.
Pure `Binary` must not represent a potentially trapping division/remainder; use
`CheckedBinary`, whose outputs include the effect successor.

`verify.lua` independently checks implemented opcode signatures, relative inputs,
edge/entry/return types, and an unbroken effect chain on every path. Each block
receives its effect first; ordered operations produce their successor last; returns
carry their final effect last. Bypassing a call's effect at an exit is rejected.
Ownership checks and cleanup insertion currently belong to AST construction; this
is not a proof of ownership for arbitrary hand-authored belt programs.

Pure hosts with Copy value arguments/results and no mutable borrow can become
`PureHostCall` producers. Their unused results do not root runtime work. Calls
involving memory or resource access retain ordering dependencies even when the
host has a pure declaration. No host code runs during construction.

`numbering.lua` validates relative references and block-target/packet arity.
`Block:demands()` remains a local dependency demonstration. `Function:demands()`
in `demand.lua` propagates demand through block parameters and backedges to a fixed
point. Dead loop-carried value cycles do not root themselves. Control decisions,
returns and effect interfaces are roots; this preserves effects in nonreturning
loops too. Unreachable blocks do not seed demand.

This pure CFG demand is conservative: both successors of a reachable branch are considered
possible, and it folds no condition. Binding-time evaluation is the separate `known.lua`
layer on top, which does fold known conditions and branches.
The representation remains immutable and is never renumbered. Feed verified flow
to demand analysis; it cannot repair an omitted effect dependency.

## Words and stages

[WORDS.md](WORDS.md) defines the lifecycle and implementation contracts for staged
words. `program.lua` now implements the shared advancement protocol:

- `V.parse(text, file):build(options)` returns a verified `Belt.Program`.
- The module initializer constructs bindings in source order; its result is the module
  namespace bundle, so the embedding host selects and invokes an exported word.
- A word value is a typed SSA field bundle (`Belt.Word`). Juxtaposition advances a
  persistent bundle; invocation advances transient stages and then enters the terminal.
- Initial and inter-stage preludes run in the caller at exactly the point §5.4 requires,
  so a reached prelude fires before the next argument is evaluated (§6.2).
- Terminal bodies become belt functions reached by `CallFunction`; a directly returned
  call becomes `TailCall`, so self recursion does not grow a continuation chain.
- Fields carry explicit retention: word-owned state persists and is written back after
  an invocation, while invocation-local prelude state dies with the activation.
- A record type states its own shape — member names, types and declared mutability — so
  projection, interior member assignment and projected word invocation are structural.
  An aggregate's owned members are destroyed in reverse initialization order (§8.5).

Immutability holds: `word.fields`/`supplied` are cloned per advancement, so a
specialized receiver keeps its own stage count and field list.

### Construction

Construction has one owner per decision:

- `resolve.lua` assigns lexical identities, capture sets and preparation ranges;
  `contract.lua` computes each template's interface — stage types and result type — before its
  body is built, reading the uses (including a word-valued callee's stages and a record's
  members), so a self-call or a host entry does not depend on construction order.
- `vocabulary.lua` owns the base scalar types, the registered resources and their destructors,
  and the runtime hosts, validated once so no phase rebuilds or re-checks them.
- `packet.lua` owns the word field bundle: whether a field is a place, who owns it, what an
  invocation writes back, and the key that interns an entry.
- `build.lua` is the construction context: lexical scopes, SSA values, ownership facts, pins and
  the draft CFG. `Context:finish_function` runs a terminal body and `Context:blocks` collects
  the immutable belt, so every driver builds a body the same way.
- `program.lua` advances words, builds entries and the module interface.

`belt.lua` owns the type questions (`same`, `key`, `copyable`, `owns`, `borrows`) so no consumer
restates them, and `op.lua` is the one definition of each pure operation, shared by the abstract
evaluator and the concrete test oracle.

The terminal builder still rejects preludes in the legacy `Chain:build_function` path
rather than moving them into a function that already received every argument.

## C output

`emit.lua` maps the verified belt to the `C` vocabulary and `print.lua` renders it.
The belt is already the semantic program, so emission chooses representations only.
The emitted C is kept to what the program actually needs:

- **Effects have no C representation.** An effect token is ordering evidence for the
  frontend, and the belt's statement order already carries that order. Dropping them
  removes the effect parameter from every signature, the effect field from every result,
  and every effect update, so the module initializer is `let_module_init(void)`.
- A function returning no value is `void`; one returning a single value returns that type
  directly. Only a genuine multiple result gets a struct.
- Names come from the belt: `let_module_init` and `let_<source name>_<id>`, so a function
  says what it is.
- `Int`/`Float`/`Bool`/`Unit` are `int64_t`/`double`/`bool`/`uint8_t`; a record with no fields
  is `uint8_t` because an empty struct is not ISO C.
- A word or aggregate value is a struct of its fields; `Construct`/`LoadField`/
  `StoreField` are value construction and field access.
- A `CallFunction` passes the effect token first and receives a result struct; a
  self `TailCall` assigns the entry packet and `goto`s the entry label, so tail
  recursion is a real loop rather than a C call.
- Signed overflow is undefined in C, so wrapping arithmetic goes through unsigned. These
  are one-line and branch-free, so they are macros (`LET_ADD`, `LET_SUB`, `LET_MUL`,
  `LET_NEG`, `LET_TEXT_EQ`) rather than functions. Division and remainder keep one shared
  static helper each, because inlining a trap check at every site would duplicate control
  flow instead of removing a function. Float arithmetic is native binary64; `float` is a
  `(double)` cast and `int` emits one `let_to_int` helper mirroring `scalar.to_int`'s
  truncation and saturation.
- Text is a `{data,size}` struct with byte-wise equality; a `Trap` calls the
  embedding host's `let_trap` hook.

Emission is demand-driven rather than print-everything, and demand now *computes* as well
as prunes. `let/known.lua` is an abstract evaluator over the belt whose domain is
`Known(v)` or `Runtime`; `let/scalar.lua` gives it the same exact §13.2 and §13.3 arithmetic the
concrete interpreter uses, so folding cannot disagree with execution. See
[DEMAND.md](DEMAND.md) for the design and its normative gates.

Folding is permitted only where the specification permits it. Pure operations fold;
ordered operations are scheduled, never executed, because their result types include
`Effect`. A known condition removes a branch, but a known zero divisor keeps a residual
trapping operation rather than becoming a compile-time diagnostic.

`Function:demands()` roots the pruning decision:

- A **pure** producer that is undemanded *or* whose answer is `Known` is never written
  out, and a `Known` value is inlined as a C constant at each use. The helper or struct it
  would have needed is not emitted either.
- A **known branch** emits only the taken edge, and blocks unreachable under the refined
  decisions are not emitted at all.
- A **fully known call** emits no call and no callee function; `multiply 6 7` followed by
  `a()` becomes the constant 42 with no entry emitted.
- **Loop packets are analyzed to a fixed point.** A loop-invariant value stays known even
  though the loop runs many times, so work on it folds; a value that varies is widened to a
  runtime value. Widening only ever moves toward `Runtime`, and it is verified against what
  the edges actually supply, so a varying value cannot be mistaken for a constant.
- **A binding becomes a place when its address is asked for** — by `mut place`, or because a
  nested word captures it (§9.3, §10.1). Two type forms carry the difference that matters:
  `Allocate` makes an **Address**, an owned cell destroyed with its owner; `BorrowPlace`
  makes a **Borrow**, temporary access that is never owned. A mutable stage is a pointer
  parameter reached through a borrow, a non-Copy capture is a borrow of the owner's storage
  (so a captured word and its owner share state), and `stable` says whether the place
  outlives any activation — which is precisely what decides escape. A member or constant
  index is a place too: `mut a.b` and `mut a[0]` are reached through a field address, so the
  callee writes the owner's field. A constant index is resolved statically, and a runtime
  index selects among the members with a trap for anything out of range — and in a borrowed
  path it selects a *place*, so the selection joins field addresses. A subplace can also be
  moved out on its own: the aggregate becomes partially initialized, so the hole cannot be
  read through and destruction releases only what still holds a value.
- **Module unload is a generated function.** The initializer returns the namespace and the
  state that owns it; `let_module_unload(state)` destroys that state in reverse successful-
  construction order (§15.1). One owner means a written terminal that moves an owned prelude
  into the namespace changes what the host can *see*, not who destroys it.
- **A file is a binding chain.** Its top-level `let` forms are the chain's items and its
  namespace is the terminal, so an import is just specialization at the import site:
  `import "codec.let" JPEG 90` yields the file's namespace aggregate (or a word, for a
  `do` terminal, which the importer invokes). Two imports are two instances, and an
  imported namespace is an ordinary value — projected, moved, and destroyed like any
  aggregate.
- **A decidable pure loop is enumerated and disappears.** `enumerate` follows one iteration
  at a time while every decision stays decidable, so `while i < 5 do ... end` over known
  state folds to its result and the function becomes a constant. It gives up on an
  undecidable branch, demanded ordered work, a repeated instance, or the step budget, and
  widening takes over — so a million-iteration loop is still emitted as a loop.
- An **ordered** operation always carries a demanded effect output, so it is kept even
  when its result is unused — this is how §12.2 purity stays observable.
- Block packets other than the entry block drop fields no consumer demands, together
  with the matching edge copies. The entry packet is the function ABI and is kept whole.
- Entry functions and structs were already created on demand at real call sites.

Pruning never renumbers or mutates the belt: a skipped producer simply has no emitted
variable. A call whose callee demands ordered work is never folded, so effects keep their
source order and count, and a runtime argument keeps the whole emitted call path. Cross-function tail calls still compile to `return callee(...)`
rather than a shared dispatcher, so bounded behaviour for them relies on the C
compiler.

## Next implementation steps

Follow the connected implementation sequence in [WORDS.md §10](WORDS.md#10-build-sequence-connected-contracts-not-supported-case-shortcuts).
Steps 1–5 are implemented for the covered shapes: the shared advancement protocol, the
binding-time evaluator (`known.lua`), and demand-driven C emission are in place and tested
natively. Remaining work is the list in COMPILER.md's "Work still required"; COMPILER.md is
authoritative for coverage, so it is not repeated here. The refactoring that gave each
construction decision one owner is recorded in [DESIGN.md](DESIGN.md).

Reuse the scalar/control machinery where it fits these contracts, rather than
adding a separate limited source-call path. Existing coverage and remaining gaps
are described in COMPILER.md. There is no second compiler to keep in step.

Run from the repository root (the execution oracle is test-only, not a compiler
evaluator or a claim of native-code validation):

```sh
luajit test/all.lua
```

`let/file.lua` is a default import resolver — reading files, assuming an extension, and
searching paths are host policy (§15.2), so they live beside the compiler rather than inside
the language. `test/native.lua` builds each witness, emits C, compiles it with `cc`, links the
host implementations, runs the module initializer, and compares the process output.
Generated C and executables go to `test/out/`.
