# AST-to-belt construction: specification grounding

The authoritative input is [the Let specification](let-language-specification.md),
not an earlier compiler's accepted subset. The full specification was read before
this construction step. These implementation boundaries do not redefine Let.

## What is built now

`AST.Chain:build_function(name, options)` builds the **terminal body** of a runtime
word with already-bound stages. It returns an immutable `Belt.Function`, checked
by `verify_flow`. `V.parse(text, file)` independently parses source into the AST;
neither parsing nor construction depends on `let.*`. The parser preserves stage
preludes, word-valued arguments/returns, aggregates, constraints and projected places
without claiming that all of them can already be lowered. It validates UTF-8 and
Text escapes, preserves exact integer spelling until sign-sensitive checking, and rounds
Float spelling once, in `let/literal.lua`, for every consumer.

```lua
package.path = './?.lua;./?/init.lua;' .. package.path
local V = require('let')
local program = V.parse('let example = let n : Int do return n + 1 end', 'example.let')
local chain = program.file.items[1].binding.value
local fn = chain:build_function('example', options)
local needed, reachable = fn:demands()
```

`options.parameters` may supply concrete stage types, including for unannotated
stages. Otherwise implemented scalar/resource annotations provide them, and
`let/contract.lua` supplies a type for an unannotated stage whenever its uses force
one; annotations are not a language requirement. Inference is conservative: an
ambiguous stage keeps the existing "no type without an argument" outcome rather than
guessing. `options.result` optionally constrains the result; otherwise reachable
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

A host may also state the C prototype it calls, which is how a libc or any other external
function is reached with no shim:

```lua
puts = {
  symbol = 'puts', phase = 'runtime', purity = 'ordered',
  signature = B.Signature(L{B.Parameter(B.CString, A.Read)}, L{B.Int}),
  c = { result = 'int' },
}
```

`signature` is the Let contract the frontend checks; `c` states the C ABI where it differs from
the Let type's default spelling. The Let types map to C directly -- `CString` is `const char*`,
`Int` `int64_t`, `Float` `double`, `Bool` `bool`, `Unit` `void`, `Text` a `{data,size}` struct --
so `c` is needed only for an integer of another width (`int`, `size_t`, `long long`), which the
emitter casts. The emitted C declares `extern int puts(const char*);` and calls it directly.

`CString` is a borrowed `const char*` and a type of its own, not `Text`: the two are not the same
thing, and `c.string`/`c.text` are the explicit crossings. `c.string(text)` borrows the bytes of
a `Text` and requires them to be NUL-terminated (a literal is); `c.text(cstring)` measures a C
string at its terminator, and the result is a borrowed view, so the C storage must outlive it.
No call converts silently.

`CPointer` is an opaque `void*` with no Let operation -- it cannot be dereferenced, indexed,
compared, or turned into an integer -- so it is passed back to C. Owned C memory is instead a
**resource** with a declared C representation: `CAlloc = { destroy = 'free', representation =
'pointer' }`, so Let destroys it exactly once and there is no `c.free` to call. Only a borrowed
pointer result declares `ownership = 'borrowed'` and `nullable`; `Vocabulary` checks that those
describe a pointer result and that a representation is `value` or `pointer`. The declared set is
`c.strlen`, `c.strcmp`, `c.atoi`, `c.llabs`, `c.getenv`, `c.puts`, `c.putchar`, `c.malloc`,
`c.memcpy`, `c.memset`, `c.memcmp`, `c.write` and `c.read`. `c.string`/`c.text` cross between
`Text` and `CString`; `c.text_of` builds a `Text` over a pointer and a length; `c.byte_length`
states a `Text`'s byte length and `c.null` tests a borrowed
pointer, so a pointer-and-count call needs no terminator (`libc.lua`).

### The `c` namespace and a standalone program

The command-line host registers that vocabulary as the **namespace** `c` (`c.puts`, `c.strlen`,
`c.string`, ...), so a libc name never enters the program's own scope, and an options file may
define `c` itself. A namespace member resolves as a dictionary entry rather than a field of a
value, so `c.puts(x)` is an ordinary host call (`libc.lua`, `resolve.lua`).

A file whose exported word is `main` with no remaining stage compiles to a complete C program:
`letc.lua` emits a `main` that initializes the module and calls the entry, plus a default
`let_trap` hook, so

```let
let main = do
    c.puts(c.string("hello, world"))
end
```

becomes an executable with `luajit dist/let.lua hello.let hello.c && cc hello.c -o hello`
(`examples/hello.let`). The ABI stays an embedding detail (§15.3), not Let syntax.

A foreign word may also be declared in source, which needs no options file at all:

```let
extern pure strlen (text : CString) : Int
```

`let/extern.lua` turns each declaration into the same host descriptor an options file would have
written, so resolution, construction and emission see one vocabulary. The C prototype is derived
from the Let types (`Int` `int64_t`, `CString` `const char*`, ...); an embedding descriptor
refines a width that differs, and a source declaration states the same thing as a Text argument on
the type: `extern puts (text : CString) : Int "int"`. The spelling is checked against the Let
type and the value is converted at the boundary, so a C `int` is not silently declared as
`int64_t`. A dotted name adds a member to a namespace -- `extern c.puts ...` extends `c` -- while a
plain name is lexical. A symbol already registered with the same Let signature (libc's `strlen`,
say) is allowed and the first declaration wins; two different signatures for one symbol are a
declaration error.

## Normative obligations and mechanisms

| Spec | Obligation | Construction/check/test mechanism |
| --- | --- | --- |
| §§8.1–8.3 | Aggregates, projection, interior mutability | A record's shape (member names, types and declared mutability) is part of its belt type, so projection and interior assignment are structural rather than side-table facts. A member declared mut stays writable through an immutable owning binding; otherwise the binding must be mutable. |
| §8.4 | Positional indexing | A compile-time index resolves to a static field; a constant out-of-range index is diagnosed; a runtime index reports that it needs address-taken aggregate storage. |
| §8.5 | Aggregate ownership and destruction | An aggregate is Copy exactly when every member is Copy and none is declared mutable. Destroying one destroys its owned members in reverse initialization order, recursively, so a moved aggregate destroys its members once. |
| §10.3, §17.3 | Projected word members | A word member is rebuilt from the projected record so its field values belong to the invoked region, which is why `arithmetic.add(40, 2)` works even when the aggregate was captured. |
| §§15.1–15.2 | File chains, namespace, imports | A file is a chain: top-level `let` forms are its items, and its namespace is the terminal — the named record of its preludes, or a written terminal that chooses the export surface. `import` is a construction-phase dictionary entry whose one slot is a constant `Text` path; the file's preludes are constructed at the import site, its stages are supplied by the following arguments, and the result is its terminal value. Two imports are two specializations, so their state is independent (§5.2), and the namespace is destroyed with the binding the importer gave it. Cycles are diagnosed. |
| §15.1 | Module unload destroys owned state in reverse | The initializer returns the namespace plus the state record that owns every top-level value in construction order; `let_module_unload` destroys that record. A moved prelude stays at its original position in the state, so a written terminal cannot cause a double destruction or reorder it. |
| §9.2 | Partial moves | `move place` names a subplace as well as a binding: the moved subplace becomes uninitialized, the aggregate becomes partially initialized, and destruction releases only what still holds a value. A subplace containing the hole cannot be read or moved as a value, while a read *through* it to another subplace is allowed; assigning the hole reinitializes it. The path must be statically known. A path moved on only some branch is a run-time fact, carried and destroyed exactly like conditional ownership, so a destruction is guarded by it and reading it is impossible; assigning over it releases the old value only where one is still there. |
| §9.4 | Assignment to a place path | A destination is any path from a binding: names and constant indices resolve to member positions, one index may be computed at run time, and each level is rebuilt from the leaf up. A run-time index in the middle resolves the steps after it against the selected member's type -- which is why those alternatives must share one type -- and each arm writes through its own selection. Two run-time indices in one path are diagnosed, as is a write into an uninitialized subplace. Interior mutability reaches through the whole path (§8.3), while positional elements take capability from the base place (§8.4). |
| §9.2 | Moving a Copy place | A Copy value owns no state to remove, so `move place` for a Copy place is that value, copied: the place stays initialized, nothing is transferred, and the result is what reading the place would give. That is now stated in §9.2 rather than left to the implementation, and it applies to a whole binding and to a projected or constant-indexed member alike. |
| §§5.4, 9.2 | A plain stage borrows its argument | A non-Copy argument to a stage without `own` is a read-only borrow *for the invocation*: the caller keeps ownership, so the value is still usable afterwards and the caller releases it exactly once. Only `own`/`own mut` give the callee ownership, and a `mut` stage reaches the caller's place through an address. |
| §§6.5, 9.5 | A word body's locals are activation state | A word's own state lives in the field scopes that retain it; its body's locals get their own scope, so the return destroys them. Without that, a word with no stages ran its body in the retained construction scope and its locals were never released. |
| §§9.3, 10.1 | Places, borrows, captures | Two type forms, and the difference is ownership. `Allocate` makes an **Address**: an owned cell, part of the owner's state, destroyed with it. `BorrowPlace` makes a **Borrow(pointee, stable)**: temporary access to some place, never owned and therefore never destroyed. A mutable stage is a pointer parameter reached through a borrow; a non-Copy capture is a borrow of the owner's storage, so a captured word and its owner share state. `stable` says whether the place outlives any activation, which is exactly what decides escape — no exemption flags, and no blanket rule. |
| §8.4 | Runtime positional indexing | A runtime index selects among the members, which is a chain of comparisons ending in a trap; the members must share one type because the selection produces one value. A constant index, a member name and any constant path are resolved statically. Out of range traps. |
| §9.4 | Indexed assignment | Writing through a constant or runtime index updates the selected member, reusing the destination-then-right-hand-side order and the same storage rule as a projected assignment. |
| §9.4 | Assignment through a projected place | The aggregate lives in a place, so the updated record is stored back into that storage. Replacing the cell's value would put a record where its address belongs. |
| §15.1 | A `do` terminal is the initialization body | Its return is the namespace, and the module's preludes are still the state the host destroys, so every return inside the body is paired with the state record rather than returned as the state. The body's own locals are activation state in their own scope, destroyed by that return; new owned state in the *namespace* would have no unload path, so it is rejected while a prelude moved into the namespace is allowed. |
| §15.1 | A module's exported words are host entry points | An entry takes the word's own fields -- the construction it has been through, which the host reads from the namespace the initializer returned -- followed by the stages it still needs. Advancing uses the same protocol a call site uses, so the entry runs whatever preludes lie between those stages: a host supplies stages, not the values a call site would have computed. A parameter is shaped by its stage's capability -- a mutable stage is a place reached through a borrow, an owned stage arrives fresh -- because the entry *is* the contract. A stage whose type only an argument can determine (unannotated, or constrained only by `Copy`) has no entry, since there is no signature to publish, and the builder records why. Once every stage is bound, the entry runs the word's own entry -- the stages it supplied produced exactly that entry's fields -- so one template has one body and the host entry is a wrapper. Entries are roots of emission, and `statistics` reports each one's C name for the host to call. |
| §15.1 | Module state outlives the initializer | A module-lifetime cell is file-scope storage, because a captured word holds its address beyond the initializer's frame. The state record is built from each prelude's current binding at the return, so a terminal that split the CFG hands over live state rather than a value captured before it ran. |
| §3.2 | Statement boundaries and juxtaposition | Newlines are never separators: `f(x) g(y)` is one specialization even across a line break, so two expression statements need `;`, while a following `let`, `return` or assignment ends the previous value. A binding whose value swallowed the next statement is diagnosed as "not visible in its own initializer" with the `;` requirement, rather than as an unknown name. |
| §§4.1–4.2 | Lexical scope, initializer-before-binding, source self name | Scope maps contain binding IDs; nested scopes may shadow; duplicate same-scope bindings fail. A source self name cannot silently fall back to an outer host word. A self name is resolvable inside any nested control block, because a control split carries the defining word and the function under construction with it, and a self call takes the word's result type from the returns the terminal states, so construction order does not decide acceptance. |
| §4.3 | Left-to-right observable evaluation | Operands and arguments construct left to right; effect references serialize ordered work. Earlier operand values are pinned across CFG construction. |
| §§5–6.2 | Specialization is not invocation; preludes run between arguments | `program.lua` advances a word bundle one stage at a time and runs each reached prelude in the caller before the next argument is evaluated. A data terminal returns data; a `do` terminal yields a word, never implicit execution. |
| §6.4 | Preserve return before reverse cleanup | Return values are pinned across conditional cleanup blocks; the return carries the final effect. |
| §6.5 | Prepare tail arguments, then clean caller, then enter callee | A directly returned source call becomes `TailCall` after caller cleanup, so self recursion needs no return continuation. Host tail calls still order arguments and moves before caller destruction. |
| §§7, 13.1 | Inline control and short-circuiting | If, while, switch, and and/or become explicit blocks; arms do not become runtime closures. A loop's condition CFG belongs to its original header, not its preheader or last condition block. |
| §7.2 | Switch evaluates once, scopes arms, has no fallthrough | Subject pins, literal/type/duplicate checks, conditional edges, scoped arms; covering both Bool values is exhaustive. |
| §§9.2–9.4 | Moves, borrows, mutation | Binding-ID initialization/borrow state; explicit Move; ordered external Load/Store; plain resource stages cannot be consumed; overlapping reads are allowed but mutable borrowing excludes access. |
| §§9.5–9.6 | Reverse destruction, conditional initialization | Owned locals track initialization and alive facts; divergent alive facts become Bool block parameters; guarded Destroy consumes the effect. Replacement evaluates its RHS before destroying the old owner. |
| §§11, 13 | Static representation and exact scalar meaning | Concrete types are checked during construction and again on belt flow; literals are range-checked with split integer arithmetic. Arithmetic stays as typed operations, not Lua-number folding. |
| §13.3 | Float literals and IEEE arithmetic | A Float literal is validated and rounded once in `let/literal.lua`; folding and C emission take their bits from that same conversion, so they cannot round differently. Arithmetic is native binary64: division by zero yields an infinity or NaN rather than a trap, and a NaN is unequal to itself. Int and Float do not promote; the core's `float` and `int` words convert explicitly, both pure and total, with `int` truncating toward zero and saturating at the Int bounds while a NaN becomes zero. |
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
invocation; `contract.lua` computes each template's stage types and result type before its
body is built; `packet.lua` owns the word field bundle (place-ness, ownership, write-back and
the entry key); `vocabulary.lua` owns the scalar types, resources and hosts, validated once;
`program.lua` implements the shared advancement protocol.

Word values are `Belt.Word` SSA field bundles. Because advancement clones the bundle,
a specialized receiver keeps its own stage count and fields, and `multiply 2` followed
by `multiply 6 7` produces two independent words. Fields record retention: word-owned
state is written back after invocation. A field a call site built is handed to the entry that
receives it -- the callee for an invocation, the word bundle for a specialization -- and that
entry releases it: an own-stage argument and a non-Copy prelude alike, at the transfer for a
tail call and at the return otherwise. A host entry keeps and releases its own parameters.
`Belt.Program:verify_flow` re-checks every generated function
independently of construction, including `CallFunction`/`TailCall` contracts.

## Work still required

One specified behaviour is not provided:

- A partial move introduced inside a loop whose path is still a hole at the backedge
  (`while ... do if c do move a.b end end`) needs the hole fact correlated with the guard that
  created it. A dynamic fact at the loop entry is not enough on its own: the body's `move` then
  reads a *maybe* initialized place, which stays rejected. Divergence at an ordinary join is
  supported, and so is loop-carried reinitialization (`move a.b` followed by `a.b = fresh` in
  the body restores the entry's facts). The rest of §9.2 is implemented, including a bare
  `move place` statement.

Two optimizations are knowingly absent; the compiler is correct without them:

- **Mutual-recursion summaries.** Mutual recursion itself needs declarations, which §18 defers,
  so there is no call-graph cycle for the evaluator to reach a fixed point over. Direct
  recursion is summarized, and a withdrawn cycle is emitted normally.
- **Block instances.** A decidable loop that carries ordered work is emitted as a loop rather
  than unrolled, because unrolling would need one emitted block instance per iteration. This
  changes the emitted C, not its behaviour.

Demand-driven folding, pruning and specialized ABIs are implemented; [DEMAND.md](DEMAND.md)
describes them and ARCHITECTURE.md's C-output section states what they deliver. The runtime
benchmark carries the resource-pressure workload and links; a fresh measurement is
`luajit bench/run.lua`, and `bench/README.md` says how to read the artifacts.

## Deliberately outside the implementation

These are not gaps. The specification fixes no behaviour to implement, or defers it.

- Text concatenation, Unicode indexing, normalization, formatting and allocation policy:
  §13.5 specifies a Text literal as an immutable module-lifetime byte sequence and says the
  core specifies none of these. Dynamically allocated or host-owned strings use separately
  declared vocabulary and an ownership contract.
- Tail invocations that borrow an argument for the call: §6.5 makes this an ownership
  error, and it is reported as one. The same applies to a borrow of a local that cleanup
  would destroy.
- Mutual recursion beyond what direct recursion needs: §18 defers the declarations. The
  evaluator's missing piece is an optimization (a fixed point over a strongly connected
  component), not a behaviour.
- Shape constraints written with arguments, pattern matching, exceptions,
  coroutines, a stable foreign-function ABI, operator overloading and a built-in cyclic
  collector: all deferred by §18.
- An argument-determined (`Executable`) stage, and a word-typed value with no call to read its
  stages from: the word an argument supplies *is* the stage's type, so a generic word with such
  a stage has no signature to publish. The specialization does have one -- `let divide =
  checked_divide success failure` offers an entry -- and the host calls that. A generic entry
  would need an ABI for a word value, which is the closure-layout decision below.
- Dynamically selected words: a word value may be stored, passed and invoked (§11.2), but a
  dispatch needs a representation for a value whose word identity is not statically known, and
  §18 defers any mandatory universal aggregate or closure layout.
- The result type of a self-call that is the only return of its own word: nothing in the
  program determines it, so it is diagnosed rather than guessed. A word with any other return
  is typed from that return.
- An owned word value crossing a call boundary: the ownership rules would have to be stated
  before they could be honoured. A Copy word returned from a call is already reconstructed from
  its type.
- Package resolution policy: `let/file.lua` provides a default resolver, but §15.2 leaves the
  lookup to the embedding, so a host with its own layout passes its own resolver.

## Tests and their limits

`luajit test/all.lua` runs every suite and reports the total check count; that total is
the number to quote, rather than one counted by hand.

`test/build.lua` uses AST fixtures annotated with relevant specification sections.
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
truncation, Text equality, the division trap, aggregates, owned resources (including a user
word with an `own` stage), a recursive call inside a control block, and a module `do` terminal
with control flow and a prelude. Generated C lives in `test/out/`.
This is real native execution, not the interpreter.

The emitted C contains only what the program needs: the module initializer, live word
entries, the trap hook, and, when used, one shared helper for division, one for remainder,
and `let_to_int` for the Float narrowing.
Effects are erased, single results return directly, and wrapping arithmetic is a macro.

`test/aggregate.lua` covers §8.1 named projection, §8.2 positional and nested indexing,
§8.3 projection through a capture and both interior-mutability forms, §8.5 reverse and
nested member destruction plus single destruction of a moved aggregate, §17.3 projected
word invocation at module level and through a capture, and the four diagnostics.

`test/native.lua` also covers a conditional partial move in both directions -- the moved
subplace released by its new owner, and the one that was not moved still released by the
aggregate -- and non-tail self recursion (`factorial`, and `fib` with two
recursive calls), and module unload: owned top-level state is destroyed in reverse
successful-construction order; a written terminal that moves an owned prelude into the
namespace still destroys it exactly once at its original position; and a `do` terminal
returns its namespace to the host while its own locals are destroyed by that return and its
preludes are handed over as the state.

`test/place.lua` covers §17.4's canonical ownership example, a plain stage borrowing a
non-Copy argument that the caller then uses and releases, a word with no stages releasing
its locals, the two §6.5 tail-invocation ownership errors, a mutable stage writing the
caller's place, an address-taken Copy local, borrowed members and constant and runtime
indices (including a nested path), indexed and projected assignment, partial moves with the
uninitialized-subplace diagnostics they raise and the run-time facts a conditional move
produces, the borrow diagnostics, and §10.1's shared-state capture with its escape
rejections. Native witnesses (`mut_place`,
`ownership_lend`, `capture`, `partial_move`) execute the same cases, and the own-stage and
resource-prelude cases run through the belt interpreter with their close traces checked.

`test/import.lua` covers the implicit namespace, a written terminal, a configurable file,
word members of an imported namespace, two imports as independent instances, an owned
resource moved into a namespace and destroyed exactly once at scope exit, a `do`-terminal
file yielding a word, an import cycle, a non-Text path, an unresolvable path, a missing
resolver, and a lexical binding shadowing `import`. A native witness (`modules`) compiles
imports through to C.

`test/known.lua` covers loop analysis: a loop whose trip count is decidable and whose body is
pure is enumerated away (`no goto`, no loop arithmetic, the final value as a constant), a
run-time bound leaves a real loop with its invariant still folded inside it, an induction
variable and an accumulator widen and still compute the right values, nested loops settle,
and a never-entered loop leaves its variables alone. Native witnesses (`loop_widening`,
`loop_invariant`, `loop_stateful`) execute the same cases, so an unsound fold would print a
wrong number rather than merely look wrong.

`test/emit.lua` checks that demand actually shapes the C: dead pure producers and their
helpers are absent, an unused pure host call is absent, both ordered host calls survive in
order, an unused loop-packet field with its literal is dropped while the demanded loop body
remains, pure and cross-function folding produce constants with no callee function, a
known branch removes the branch, a known zero divisor keeps a trapping operation, and a
runtime argument keeps the emitted call path.

`test/demand.lua` checks unused pure calls across joins, dead loop-carried value
cycles, ordered calls whose data is unused, and effects in nonreturning cycles.

`test/float.lua` covers §13.3: the four literal spellings, the arithmetic and comparison
operators, the `float`/`int` conversions and their saturation, division by zero as an
infinity, signed zero, and NaN inequality. It executes each case through the belt
interpreter and compiles a native witness, so a fold and native execution that disagreed
about an IEEE case would print different results rather than merely look wrong.

