# Let-to-C bootstrap: scalars and owned resources

Run with LuaJIT and a C compiler. Neither Terra nor CBlock is required.

```sh
luajit letc.lua examples/scalars.let output.c
cc -std=c99 -O2 -fPIC -shared output.c -o output.so
luajit test/compiler.lua
luajit test/recursion.lua
luajit test/ownership.lua
luajit test/residual.lua
luajit test/partial.lua
```

The generated module exposes runtime words as `let_<source_name>` C functions.
There is no implicit `main`. The Lua API returns generated C, an export manifest,
the ASDL residual module, and per-function emission statistics:

```lua
local source, exports, residual, statistics = require('let').compile(text, 'example.let')
```

## Architecture

```text
source -> lexer -> parser -> Let Syntax ASDL
       -> constructor-owned scalar signature inference
       -> constructor-owned ownership and borrow checking
       -> partial evaluation with ordered activation/cleanup residualization
       -> Residual ASDL -> direct C emission
```

- `let/vocab.lua`: source, semantic, analysis, and residual ASDL constructors.
- `let/integer.lua`: shared exact literal validation, including dead source branches.
- `let/lexer.lua`: tokens with source spans.
- `let/parser.lua`: recursive descent, precedence, retained separators.
- `let/infer.lua`: signature constraints, recursive result inference, scoped analysis.
- `let/ownership.lua`: ASDL ownership meanings and flow-sensitive legality checks.
- `let/host.lua`: explicit host vocabulary and resource ABI declarations.
- `let/program.lua`: module construction, checking, and specialization context.
- `let/domain.lua`: explicit known/dynamic/place/resource/bottom binding-time values.
- `let/state.lua`: abstract cells, ownership initialization, and continuation joins.
- `let/evaluate.lua`: constructor-owned source evaluation and loop generalization.
- `let/specialize.lua`: memoized recursive entries, activation preparation, and widening.
- `let/codegen.lua`: printing the residual C vocabulary; no partial evaluation.
- `asdl.lua`, `terralist.lua`: standalone structural helpers (see `THIRD_PARTY.md`).
- `let/init.lua`: pipeline composition.
- `letc.lua`: command-line interface.

ASDL nodes own `infer`, `own`, `evaluate`, `prepare`, `pack`, `unpack`, and `emit` methods.
Contexts own scopes, unification cells, ownership flow state, IDs, and pending output.
`Analysis.Value` describes type variables or partially supplied words; resolved
`Semantic.Signature` and `ActivationField` nodes describe the callable boundary.
Activation fields own pack/unpack; capability and value constructors determine ABI. Ownership
abstract values also use an ASDL vocabulary; mutable initialization/borrow maps
stay in the checker context. No pass decorates or mutates the source AST.
Nodes are treated as immutable. Lists are frozen by convention after construction.
ASDL checks structure; it does not perform Let semantic checking automatically.

The old `residualize.lua`, `lifetime.lua`, and `residual.lua` implementations were
deleted. This evaluator does not classify residual expressions as a substitute for
binding-time values: `Known` contains a semantic atom, `Dynamic` contains residual
code, and `Place` identifies a cell in a separate abstract store. `Bottom` denotes
a computation that cannot return. No CBlock graph or runtime Let word objects remain.

Assignments to unescaped known cells update the abstract store without emitting C.
Branches preserve equal known values; differing states become residual storage.
Returning paths are joined at the invocation boundary so mutations reach callers.
Known finite loops execute during evaluation, appending rather than executing any
ordered operations. Unknown effects synchronize and invalidate escaped storage;
private unescaped state stays known. Known traps stop evaluation without cleanup.

Recursive entries are keyed by their known inputs. Invariant known arguments are
omitted from native helper parameters and tail-transfer packets. Pure known answers
are memoized only when the terminal has no residual effects; argument/prelude
preparation still occurs for every invocation. Changing recursive inputs widen to
dynamic values after eight contexts (or earlier when the shared evaluation budget
is exhausted). Static loop execution also has an eight-iteration local limit and
shares a 512-step budget with recursive specialization.

Ownership initialization is tracked as known true, known false, or dynamic.
Only genuinely differing initialization states require runtime alive flags.
Normal cleanup and proper tail transfer preserve their specified order.

`statistics.partial_evaluation` exposes cache counts, remaining fuel, and native
specialization masks. This is bounded partial evaluation, not maximal optimization:
dynamic control can still require C slots/labels, and large known computations can
be residualized when the budget is exhausted.

## Supported

- Top-level words with `Int`, `Bool`, `Unit`, or registered resource annotations.
- `own`, `own mut`, and `mut` stages; visible `move` and mutable-borrow arguments.
- Resource returns, replacement, conditional ownership, and reverse-order cleanup.
- Exact signed 64-bit literals, wrapping arithmetic, comparisons, and Booleans.
- Division/remainder checks and the `INT_MIN / -1` exceptional result.
- `let`, scalar `mut` locals, assignment, lexical shadowing, `return`.
- `if`/`else`, `while`, and short-circuit `and`/`or`.
- Exact invocation saturation and scalar first-order calls.
- Direct recursion, including non-tail calls, and inferred scalar result shapes.
- Proper self-tail transfers with parallel stage rebinding and bounded native stack.
- Scalar specialization with `with` or juxtaposition, including saturated words.
- Top-level literals/aliases and scalar local word aliases/specializations.
- Transient preludes in stage/argument order, including recursive words.
- Scalar, resource, borrowed-place, and Copy-word-alias prelude bindings.

Ordinary calls are expanded inline with explicit return continuations. Direct-return
self calls become block backedges with ordered argument snapshots and simultaneous
parameter rebinding; no compiler tail-call optimization or `musttail` ABI is required.
Non-tail recursive calls use lazily emitted native helpers and retain the native
return stack required by those source calls. Preparation evaluates arguments and
reached preludes in order, then packs all terminal inputs (including prelude state).
Both recursive helpers and tail backedges enter the terminal body with that packet;
they do not replay the preludes. Resource fields carry initialization flags so a
move between stages and preludes cannot introduce a second destructor.

On a tail transfer, the new packet is prepared first, moved ownership is preserved,
the old activation is cleaned up, and only then is the new terminal entered.
On a non-tail call, caller resources remain alive until that caller exits.
Specialization still supports Copy scalar state on words without preludes.

Result inference establishes scalar signatures before code emission, including when
a recursive use appears before a base-case return. It does not invent a result shape
for an unconstrained recursive cycle: `let spin = do return spin() end` is diagnosed
unless surrounding uses determine the shape. Mutual recursion remains outside the
language bootstrap profile; later top-level names are still invisible earlier.

Large non-recursive call trees can still produce large C output. Non-tail recursion
can exhaust the native stack; only tail transfers promise bounded stack usage.

Unsigned C arithmetic implements wrapping, followed by a `memcpy` bit reinterpretation
to `int64_t` (an exact-width two's-complement type). Constants are emitted exactly
with `INT64_C`/`UINT64_C`, not reconstructed through arithmetic trees. Compile-time
folding uses exact LuaJIT 64-bit integers. Division/remainder guard zero and the
exceptional signed pair explicitly. Zero divisors call `abort()` without cleanup.

## Host resource vocabulary

The optional third API argument declares resources and runtime host words:

```lua
local options = {
    resources = { Buffer = { destroy = 'app_close' } },
    hosts = {
        open_buffer = { symbol = 'app_open', result = 'Buffer',
            stages = { { constraint = 'Int' } } },
        buffer_size = { symbol = 'app_size', result = 'Int',
            stages = { { constraint = 'Buffer', capability = 'read' } } },
    },
}
local c = require('let').compile(text, 'buffers.let', options)
```

Stage capabilities are `read` (default), `mut`, `own`, and `own mut`. Host operations
are currently ordered, synchronous, and non-reentrant. They are never executed by
the compiler. Registering a host word is a trusted contract: a borrowing host must
not retain or consume the borrowed owner; an owning result must be fresh.

Resources are opaque `int64_t` handles in this embedding ABI. `mut` stages receive
a pointer to the caller's slot. Other stages receive values; an `own` stage takes
ownership on entry. Host Unit results and destructors use C `void`; source Unit
exports use `uint8_t` with the sole valid value zero. Destructors must return normally
and must not trap, suspend, or re-enter Let. Host symbols must be unique and avoid
the compiler's `let_`/`letbody_` prefixes.

A complete example can be compiled and linked as follows:

```sh
luajit letc.lua examples/resources.let /tmp/resources.c examples/resources-host.lua
cc -std=c99 -O2 /tmp/resources.c examples/resources-host.c -o /tmp/resources
/tmp/resources  # 48
```

The CLI's optional third path is a trusted Lua configuration file evaluated with
`dofile`. It returns the same options table accepted by the Lua API.

## Ownership boundary

The checker rejects borrowing conflicts, moves from borrowed stages, reads after
moves, implicit non-copyable copies, and borrows that would outlive tail cleanup.
Read borrows may overlap. Mutable borrows are exclusive, and invocation argument
borrows remain active while subsequent arguments are evaluated. Moves on only one
incoming live path make the place unusable after the join. Normal loop backedges
must restore the initialization state of outer bindings; this is a conservative
bootstrap check.

Cleanup is emitted at lexical exits, returns, replacement, and tail transfer.
Alive flags permit conditional destruction without inspecting moved values.
Fresh borrowed argument temporaries are destroyed when the invocation returns.
A trap still skips normal cleanup. There is no reference counting, garbage
collector, or runtime borrow checker.

## Deliberate limits

This is **not yet a conforming implementation of the complete Let profile**.
Unsupported forms produce diagnostics, including:

- higher-order stage arguments, returned words, local word construction;
- unannotated remaining stages on exported words;
- persistent specialization retaining resources or mutable owned word state;
- aggregates other than Unit, projection, indexing, and Text;
- initial construction preludes and persistent specialization with preludes;
- data-terminal templates, mutable module state, and effectful module initialization;
- module unload and an embedding trap hook;
- construction/constraint extension descriptors and the MillK/Sring backend.

Top-level scalar data is currently compile-time-only and is not exported through
a C namespace. The manifest lists callable exports. A word must have one consistent
scalar return shape; normal fallthrough returns Unit. Unreachable statements are
currently diagnosed rather than accepted. Keep these restrictions explicit as the
compiler grows; C representability is not proof of Let ownership legality.

## Tests

`test/compiler.lua` executes generated native code at `-O0` and `-O2` with UBSan.
It checks exact integer boundaries, wrapping, traps, control flow, specialization,
lexical snapshots, deterministic output, and source-located rejection diagnostics.
`test/recursion.lua` checks scalar result inference, factorial and recursive Fibonacci,
mixed tail/non-tail paths, specialized recursive words, and parameter permutations.
It also checks residual call counts on tail-only paths and runs a million
tail transfers in a native `-O0` executable with a 256 KiB stack limit.
`test/ownership.lua` checks exact native allocation/effect/destruction traces, moves,
borrowed replacement, early returns, conditional cleanup, transient argument
lifetimes, recursive owned preludes, and stage/prelude event order. Tail resource
recursion also checks that only two resource activations overlap during preparation.
All three suites run at `-O0`/`-O2` with UBSan checks (trap mode, no sanitizer runtime
library required). Set `CC=clang` to test another compiler. Artifacts are removed.
`test/residual.lua` additionally checks literal residual returns, exact compile-time
arithmetic against native arithmetic, stable snapshots across mutation, retained
host effects, and runtime constant traps at `-O0`/`-O2`/`-O3`.
`test/partial.lua` checks the residual before GCC: static mutation and loops become
literal returns, recursive invariant parameters disappear, memoization preserves
prelude effects, return-state joins preserve mutation, unknown effects invalidate
escaped cells, bottom values stop evaluation, and only dynamic ownership joins
introduce alive flags. It also checks that the obsolete implementation files are absent.

## Native code-quality probes

Run `luajit bench/run.lua` to compare generated programs with handwritten C under
GCC `-O0`, `-O2`, and `-O3`. Native timing loops exclude Lua/FFI overhead; the runner
retains emitted C, assembly, GCC optimization reports, and loadable Lua results.
See [`bench/README.md`](bench/README.md) for methodology and initial findings.

