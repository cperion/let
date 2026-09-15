# AST-to-belt construction: specification grounding

The authoritative input is [the Let specification](../let-language-specification.md),
not the old compiler's accepted subset. The full specification was read before
this construction step. These implementation boundaries do not redefine Let.

## What is built now

`AST.Chain:build_function(name, options)` builds the **terminal body** of a runtime
word with already-bound stages. It returns an immutable `Belt.Function`, checked
by `verify_flow`. `V.parse(text, file)` independently parses source into the v2 AST;
neither parsing nor construction depends on `let.*`. The parser preserves stage
preludes, word-valued arguments/returns, aggregates, constraints and projected places
without claiming that all of them can already be lowered. It validates UTF-8 and
Text escapes and preserves exact integer spelling until sign-sensitive checking.
Whitespace has no grammatical force; `;` separates otherwise adjacent expressions.

```lua
package.path = './?.lua;./?/init.lua;' .. package.path
local V = require('v2')
local program = V.parse('let example = let n : Int do return n + 1 end', 'example.let')
local chain = program.bindings[1].value
local fn = chain:build_function('example', options)
local needed, reachable = fn:demands()
```

`options.parameters` may supply concrete stage types, including for unannotated
stages. Otherwise implemented scalar/resource annotations provide them. Inferring
unresolved parameter types from uses is pending; annotations are not a language
requirement. `options.result` optionally constrains the result; otherwise reachable
construction paths establish one result type. Pure infinite-loop path refinement
and answer-type specialization are not implemented yet.

Resource and host registration is an internal API, not Let syntax:

```lua
local A, B, L = V.AST, V.Belt, V.List
local options = {
  resources = { Box = { destroy = 'app_close' } },
  hosts = {
    open = {
      symbol = 'app_open', phase = 'runtime', purity = 'ordered',
      signature = B.Signature(
        L{B.Parameter(B.Int, A.Read)}, L{B.Named('Box')})
    }
  }
}
```

Host signatures describe source stages and one Let result, including Unit for
a void operation. The builder adds effect dependencies. A mutable Copy stage
arrives at terminal entry as an address; loads/stores update that actual place,
not a copied scalar with later copy-back. Hosts do not declare staged preludes
through this registration API. Resource-returning hosts promise a fresh owner.
Registered host/destructor contracts are trusted; no host implementation is
executed by the compiler.

## Normative obligations and mechanisms

| Spec | Obligation | Construction/check/test mechanism |
| --- | --- | --- |
| §§4.1–4.2 | Lexical scope, initializer-before-binding, source self name | Scope maps contain binding IDs; nested scopes may shadow; duplicate same-scope bindings fail. A source self name cannot silently fall back to an outer host word. |
| §4.3 | Left-to-right observable evaluation | Operands and arguments construct left to right; effect references serialize ordered work. Earlier operand values are pinned across CFG construction. |
| §§5–6.2 | Specialization is not invocation; preludes run between arguments | `program.lua` advances a word bundle one stage at a time and runs each reached prelude in the caller before the next argument is evaluated. A data terminal returns data; a `do` terminal yields a word, never implicit execution. |
| §6.4 | Preserve return before reverse cleanup | Return values are pinned across conditional cleanup blocks; the return carries the final effect. |
| §6.5 | Prepare tail arguments, then clean caller, then enter callee | A directly returned source call becomes `TailCall` after caller cleanup, so self recursion needs no return continuation. Host tail calls still order arguments and moves before caller destruction. |
| §§7, 13.1 | Inline control and short-circuiting | If, while, switch, and and/or become explicit blocks; arms do not become runtime closures. A loop's condition CFG belongs to its original header, not its preheader or last condition block. |
| §7.2 | Switch evaluates once, scopes arms, has no fallthrough | Subject pins, literal/type/duplicate checks, conditional edges, scoped arms; covering both Bool values is exhaustive. |
| §§9.2–9.4 | Moves, borrows, mutation | Binding-ID initialization/borrow state; explicit Move; ordered external Load/Store; plain resource stages cannot be consumed; overlapping reads are allowed but mutable borrowing excludes access. |
| §§9.5–9.6 | Reverse destruction, conditional initialization | Owned locals track initialization and alive facts; divergent alive facts become Bool block parameters; guarded Destroy consumes the effect. Replacement evaluates its RHS before destroying the old owner. |
| §§11, 13 | Static representation and exact scalar meaning | Concrete types are checked during construction and again on belt flow; literals are range-checked with split integer arithmetic. Arithmetic stays as typed operations, not Lua-number folding. |
| §§12.2, 14 | Purity, traps, and effects remain observable | Unused trapping arithmetic has an effect output. Test execution stops at traps without running later cleanup. Pure value-only hosts may be undemanded; memory/resource access remains ordered. |

Ordinary mutable Copy locals use new SSA values, not memory stores. Each block
interface initially carries all in-scope bindings and active expression pins.
Bindings get independent parameters even if their initial values alias: assignment
can make them diverge on different paths or iterations. Global demand later finds
which packet fields are needed; construction does not prematurely prune or renumber.

Draft blocks and mutable scope/ownership tables exist only in construction contexts.
ASDL instructions, references and final blocks are not patched after construction.
Relative references are frozen after an instruction/exit's complete operand set is
prepared—adding an alive-flag literal must not invalidate an earlier edge distance.

`verify_flow(hosts)` checks implemented opcode/result contracts, branch conditions,
edge types, entry/return signatures, and effect continuity independently of construction.
It rejects a pure Binary division and a return that bypasses an ordered effect.
It does not independently re-prove ownership for arbitrary manually constructed IR.

## Staged words and program construction

`A.Program:build(options)` returns a verified `Belt.Program` with a module initializer
and one belt function per concrete terminal. `resolve.lua` assigns binding IDs and
derives initial/inter-stage preparation ranges from the original AST; `binding.lua`
decides capability and destination for both persistent specialization and transient
invocation; `program.lua` implements the shared advancement protocol.

Word values are `Belt.Word` SSA field bundles. Because advancement clones the bundle,
a specialized receiver keeps its own stage count and fields, and `multiply 2` followed
by `multiply 6 7` produces two independent words. Fields record retention: word-owned
state is written back after invocation; invocation-local prelude state is destroyed by
the activation. `Belt.Program:verify_flow` re-checks every generated function
independently of construction, including `CallFunction`/`TailCall` contracts.

## Work still required

- Module unload/destruction of word-owned module state (initialization exists).
- Non-Copy lexical captures: capturing an owned or borrowed binding requires the
  escape analysis of §10.1 and is currently diagnosed, not silently copied.
- Mutable borrowed stage storage for `mut place` invocation arguments, which needs
  address-taken object lifetimes rather than SSA scalars.
- Aggregate owned members and their reverse destruction (§8.5); Copy members work.
- Projection, indexing, and projected/indexed assignment places.
- General recursive and mutual call contracts and dynamically selected words.
- Consumer-driven known evaluation and scheduling. C emission itself now exists
  (`emit.lua`/`print.lua`); it prints the whole verified belt, so demand is currently
  handled only by the C compiler rather than by the frontend.
  and higher-order words, returned words, and lexical capture lifetimes.
- Remaining constraint words and inference/specialization from concrete uses.
- Aggregate construction, projection, indexing, and associated ownership paths.
- Address-taken locals, projected borrows, mutable borrowed resource stages, and
  construction of stored/returned word values.
- A precise lowering for explicit moves of Copy bindings. This path is diagnosed
  rather than inheriting an undocumented old-compiler exception.
- Loop ownership states requiring initialization fixed-point analysis. For now an
  accepted backedge must restore the incoming initialization facts; other cases
  are diagnosed as implementation gaps, not declared illegal Let programs.
- Text now has a C layout and byte-wise equality, but no concatenation, indexing, or
  dynamic ownership vocabulary.
- Tail calls borrowing newly created resource temporaries need invocation-owned
  temporary storage; they are explicitly diagnosed as an implementation gap.
- Consumer-driven known evaluation, specialization stabilization, and C scheduling.
  Emission consumes `Function:demands()` and `v2/known.lua`'s answers: unneeded pure
  producers, known producers, their helpers, unused non-entry packet fields and
  unreachable blocks are not written out, known values are inlined and known branches are
  selected. Ordered effects are always kept, and a fully known call emits no callee.
  Still missing: partial bundles, specialized ABIs, mutual-recursion summaries, loop
  widening, and shared-result materialization (DEMAND.md milestones B and C). No residual
  AST or old evaluator is introduced.

## Tests and their limits

`test/build.lua` uses v2 AST fixtures annotated with relevant specification sections.
It checks scalar snapshots, control, expression pins, parallel loop transfers,
host ordering, source-located diagnostics, mutable external places, resource moves,
replacement, conditional cleanup and traps. `test/execute.lua` is a small test-only
belt interpreter with exact LuaJIT integer operations and traceable mock hosts.
It is not used during construction or demand analysis and is not the new partial
evaluator. These are semantic/structural tests, not native C tests.

`test/native.lua` is the end-to-end witness: it builds each program, emits C, compiles
it with `cc -std=c11 -O1`, links host implementations, runs the module initializer, and
compares process output. It covers native currying/invocation, persistent interior
mutable state, prelude ordering, 200000-deep proper tail transfer, 64-bit wrapping and
truncation, Text equality, and the division trap. Generated C lives in `test/out/`.
This is real native execution, not the interpreter.

`test/emit.lua` checks that demand actually shapes the C: dead pure producers and their
helpers are absent, an unused pure host call is absent, both ordered host calls survive in
order, an unused loop-packet field with its literal is dropped while the demanded loop body
remains, pure and cross-function folding produce constants with no callee function, a
known branch removes the branch, a known zero divisor keeps a trapping operation, and a
runtime argument keeps the emitted call path.

`test/demand.lua` checks unused pure calls across joins, dead loop-carried value
cycles, ordered calls whose data is unused, and effects in nonreturning cycles.
Actual known-branch specialization and C emission remain later steps.

