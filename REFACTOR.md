# ABC VM and JIT refactor target

**Live project tracking has moved to [WORKLIST.md](WORKLIST.md).** It consolidates
older incomplete work and new features using stable checkbox IDs, dependencies,
acceptance conditions and a fresh code/test audit of `06ec9dc`. This document remains
the architectural rationale and chronological evidence record. Checkboxes below
are scoped historical/package records, not an independent live project backlog;
record new status in WORKLIST and append supporting evidence here when relevant.

Current crosswalk: Phase 5 → A; caller-owned regions → R; source staging/demands → S;
frontend gaps → F; ownership → O; containers/dynamics/libraries → C/D/L; one `.let`
→ U; tasks/pthreads/AOT → T/P/W; spread → X. Deferred work is explicitly in Z.
Current source specs supersede old GC/open-word target passages below; those passages
are not authorization to restore retired ownership or execution machinery.

## Implementer entry points

Start with WORKLIST's selected ID and its file table, then
[docs/implementation-map.md](docs/implementation-map.md) for exact existing/new paths,
consumer changes, tests and removals. Runtime implementation follows
[docs/runtime-interfaces.md](docs/runtime-interfaces.md): current concrete source
binding and C owner core (not its retired catalog/TypeOps sections); runtime/task/worker
split; request/ticket/wait-node
layouts; memory-order and lock hierarchy; backend enter/resume/park contract; image
publication; source owner-analysis entry points. Algorithms are in
[docs/runtime-primitives.md](docs/runtime-primitives.md). These are implementation
instructions, not optional competing architectures. Do not create unused scaffolding
or a compatibility facade; implement coherent producer/consumer slices.

Public encoding, dynamic schema identity, polymorphic owner generalization and
abort/foreign embedding semantics remain named hard gates. An agent must raise those
rather than invent semantics. Initial cross-worker allocation uses thread-safe
platform allocation/free, not an unmeasured worker-cache/remote-free subsystem.

## Status and latest decisions

### Removal-first lifetime correction — O03–O08/E01/E02

The user approved replacing blanket ownership lowering and explicitly requested its
removal before replacement coding. The checked source analysis and counted escaping-
root policy remain; blanket type-based holdings are not the target semantics.
Removed the source-to-physical orchestrator, whole-function borrowing switch,
unconditional publication/copy scratch, single-use-only move policy and empty
cleanup records/entries from `placement.lua`. Removed the program-wide owning-width
selector and ABC dispatch into that orchestrator. There is no forwarding alias or
retired execution fallback. Source with counted requirements explicitly rejects until
the replacement is integrated; the end-to-end source acceptance tests remain enabled
and intentionally fail at that gate.

The concrete field-drop algorithm is retained as `placement.drops`, separate from any
decision to acquire a holding. A temporary immutable pre-removal oracle reproduces
396 descriptor uses/87 concrete callbacks with identical executable drop bodies.
The C core and lifecycle delivery, packed tagged operations and address casts are
unchanged. Source proof tests no longer equate a counted requirement with a global
fat-reference ABI. Focused checks and exact limitations are recorded in
`research/experiments/runtime-owners/lifetime-lowering-removal/README.md`.
This is a removal checkpoint, not completion of the approved lifetime replacement.

### Packed owning tagged values and raw address casts — O04–O08/E01/E02

The separately approved extension is integrated: EXT10/11 ADDR2BITS/BITS2ADDR
preserve all64 bits and selected-bank placement through shared computation, without
new cell kinds, stencils or scratch memory for reinterpretation. The existing tag/
aligned union remains canonical for values and call transport. Owning results still
use caller-owned records; public/foreign packed-address contracts stay closed.

Compiler-only conditional holding traversal generates active-case acquire/move/drop
code. Concrete scratch unions are zeroed and tagged before publishing each acquisition;
failed partial copies unwind only established holdings. Generated C callbacks branch
and enqueue, never interpret a layout or enter source execution. Moves account for
statement-level variant uses as well as expression references. Duplicate carrier copies
and whole-payload reads for move cleanup were removed after the first integrated nested
fixture exceeded existing u8 C-slot limits. Proven borrowed bodies with unchanged types
and call contracts keep ordinary slot selection, not aggregate activation wrappers.

Evidence: `runtime-owners/tagged-values/`. Full incremental validation passes with
1763 source checks/568 VM calls and2508342 C cleanup checks, four modes, raw/optimized,
both lifecycle banks. Focused ASan/UBSan/leak checks pass on seven C runtime units and
the harness; generated code remains uninstrumented and JIT-incompatible function checks
are disabled. Separate C-built100001-node tagged chains/duplicate-child holdings drain
on a128KiB pthread stack without source TLS, recursive drain or allocation. This is not
task/race qualification. Pointer-free packed1894/496 regressions remain green.

The expanded corpus has92 lifecycle entries:131788 native body bytes in stack-A form,
134113 in stack-B form, maximum callback homes48 bytes excluding the ABI frame. A nested
variant uses3 owners but35 acquires; neither traffic nor code cost is zero. These counts
and peak owner bytes are measured, not timing, RSS or a like-for-like speedup comparison.
Context cloning, persistent module holdings, erasure/containers, public/FFI/task transport,
portable-C lifecycle delivery and executable `.let` remain separate incomplete work.

### D07 — dormant collector removed, active dependencies guarded

Deleted all81 tracked `vendor/whippet` files. The former dynamic/any/Whippet headers,
active collector build/CI wiring, root/collection calls and obsolete GC fixtures were
already absent. No owner-core, lifecycle, foreign synchronization, trap or stack-limit
implementation changed. The residual effect field named `safepoint` remains a generic
call barrier, not a GC hook. Historical archives and raw logs are untouched.

`tools/validate_no_collector.lua` now runs in `make validate`, with17 dependency
probes; eight additional filesystem controls qualify API/link/vendor/archive rejection
and allowed synchronization. Full incremental validation passes, including the existing
1110-check/352-call source matrix, C1043242 cleanup checks and lifetime/foreign tests.
Built runtime/tooling artifacts contain no collector symbols or dynamic dependency.
Evidence: `runtime-owners/collector-removal/`. No clean-build, new sanitizer, race or
performance claim. Collector absence is delivered; broader ownership/public/FFI/module
and task contracts remain separate incomplete work in WORKLIST.

### Connected source owning storage and C lifecycle delivery — E01/E02/O04–O08

The post-removal replacement now consumes the exact checked source graph into a
separate physical graph: concrete frames/payloads, retain-before-replace scratch,
limited moves, root-preserving references and caller-owned owning-result records.
Actual storage is the holding inventory. The small C core remains32 bytes; activation
headers are16 bytes. No slot registry, progress prefix, release cache, pinned register,
second allocator or runtime dependence on `abc-opt` returns.

All four execution modes eagerly prepare actual native `void(context, object)` C
entries for generated straight-line drops using the ordinary symbolic allocator.
Callbacks only enqueue concrete field releases. Failure cleanup walks concrete
activation records before ABC storage reset or result publication; ordinary image
writes survive. Borrowed pointer-free-reference specializations retain `InPlace`
physical lifetime constraints, avoiding a discovered plain-pointer tail-call hazard.
Known keyed partial supplies now elaborate through ordinary source captures rather
than manufacturing mutable `Any` words. Typed unfinished callable queries remain
lattice bottom rather than poisoning known factory results as opaque provenance.

`runtime-owners/source-cutover/validate-final.log` records full incremental validation:
source1110 checks/352 calls (raw/optimized, four modes, both lifecycle banks), C1043242
cleanup checks and broader regressions. The source builds a25-environment chain;
the100001-owner128KiB-stack test is a distinct C-built graph invoking the actual
source-generated callback without source TLS. Focused ASan/UBSan/leak checks pass on
seven runtime units plus the harness with JIT-incompatible function-type checks off;
ordinary generated code is not instrumented. No clean-build, race or performance
acceptance is claimed. The fixture incurs39083 native lifecycle-body bytes in40960
allocated bytes even in interpreted mode; code/storage cost is real, not a speedup.
Public owning/foreign/task transport, persistent owning modules, context-specific
physical instances, erasure/variants/containers, unified executable `.let` and Whippet
removal remain incomplete. WORKLIST alone tracks live completion.

### Lexical operator vocabulary — approved direction, not implemented

Libraries may export lexical protocol functions through ordinary import-spread.
Arithmetic/bitwise/concatenation resolve primitive, left member, right member, then
lexical op_name(left,right) for closed operand interfaces; unary negation/bitwise-not
follow primitive/member/lexical order. Selected failures never search another route.
No member installation, overload registry, hidden ref or runtime lexical fallback.
This shares lexical vocabulary principles with receiver-call sugar but must not use
a left-receiver rewrite that skips right-member precedence. Comparisons and index/
call lexical extensions remain explicit gates. Updated syntax/operator authority,
Q03 and file/test map; documentation only, with no runtime validation claimed.

### Generic invocation policies — explicit requirements, approved target only

`docs/spread.md` §3 now uses `logged(t: type, f: t, ...args)` rather than an
unannotated `f` falsely implying generics. The explicit requirement fixes the call
shape; known code identity enables direct specialization, otherwise a typed runtime
callable uses ordinary indirect transport. Static partial supply can bind only t
while f remains outstanding. Packs carry runtime components without runtime packing.
`defer ...; return f(...args)` supports post-call work without inspecting the result
vector, preserving live results/holdings before final return. It is not a tail transfer
past outstanding cleanup and does not run after abort. Arbitrary result inspection,
lambda rest, erased variadic ABI, retry and memoization contracts remain out of scope.
X03/X06 and the implementation map record the integrated acceptance tests. Documentation
only: no implementation, runtime validation or performance result is claimed.

### Literal-led fluent application — approved, not implemented

`docs/application-sugar.md` specifies `print "{}".fmt(n)` as
`print("{}".fmt(n))`; member/index/explicit-call postfixes belong to the literal-led
argument, while infix remains outside. Existing numeric-dot lexing already supports
`21.doubled()`. Q05 covers parsing; Q11 covers receiver-call resolution.

Existing members win. Only a closed interface lacking a member enables lexical
`name(receiver,args)`; incompatible/noncallable members error, never fall back.
Table/any remain dynamic member calls and module paths remain namespace lookup.
Generics resolve per specialization in definition-site scope; import-spread opts into
lexical fluent vocabulary. Copying/writing a by-value parameter remains valid; mutation
through a ref parameter requires an explicit reference. No hidden ref/write-back,
lexical bound closure, ambiguity-on-coexistence rule or runtime missing-key fallback.
This supersedes earlier exploratory ambiguity rejection; all lowering remains ordinary calls.

### Block-lambda and unit-inference refinements — approved, not implemented

Ungrouped block-lambda atoms stop postfix/self-delimited application at `end`;
immediate invocation/access requires grouping. Infix parsing is unchanged. Block
lambdas work as ordinary multi-line match/select handler expressions, now illustrated
in syntax/operator docs. Prefer named words for self-recursive/reusable definitions
and lambda bindings for callable values; export/recursion distinctions remain.

Before absent recursive result contracts default to `any`, infer unit for unconstrained
members of a resolved SCC only when all members have block bodies, only own bare
returns/fallthrough, intra-SCC calls used as discarded statements, and no non-unit
explicit/expected/export contract. Nested callable bodies are separate; expression
bodies and valued returns disqualify the shortcut. This needs SCC resolution, not
a result-type fixpoint. Supersedes the earlier blanket recursive-unit annotation
requirement below. Live implementation: WORKLIST Q08/Q10.

### Standalone block lambdas — approved target, not implemented

`let f = do ... end` constructs a nullary word; `do |p| ... end` constructs a
parameterized block lambda. Expression lambdas remain `|p| expression`. Ungrouped
`|p| do ... end` rejects; intentional returned block lambdas require grouping, e.g.
`|x| (do return x end)`. Direct `= do` on a named definition remains its executed
body. Trailing blocks supply ordinary block-lambda expressions. WORKLIST Q10 covers
parser/AST/capture handling and callable-binding exports/main discovery; main's
standalone u32 ABI and normal local-recursion/ownership rules do not change.
This supersedes the earlier pipe-plus-do block spelling in the arrow-removal record
below, without changing historical implementation evidence.

### Arrow-free lambdas — approved target, not implemented

Lambda syntax is `|parameters| body`: `|x| x + 1`, `|| unit()` and
`|x: u32| do ... end`. Closing pipes already delimit parameters; signatures retain
colon syntax and trailing blocks desugar to ordinary arrow-free lambdas. Remove
`->` from lexer tokens without compatibility spelling, future reservation or special
migration diagnostics. Preserve `--` comment handling. WORKLIST Q09 coordinates
lexer/parser, active fixtures/examples and source emitters; historical evidence is
not rewritten. This documentation does not change current compiler acceptance.

### Unit falls through; values are returned — approved target, not implemented

A named-word/method/lambda block with an established unit result contract can fall
through through the ordinary bare-return cleanup path. Unit comes from annotation,
expected callable type or unconstrained acyclic inference without value-returning
paths. Value-result paths still require explicit return; recursive/default contracts
are not silently weakened. Final calls discard results; inner block completion is
not a function return. Defer, ownership and structured-scope obligations remain.
This supersedes the earlier implicit-unit exclusion, not the prohibition on implicit
last-expression values. WORKLIST Q08 and syntax.md §5 own the implementation contract.

### Self-delimiting no-parentheses calls — approved target, not implemented

Accept one atomic literal (integer/float/byte/string/long-string/bool) or one `do`
block without argument parentheses: `a.push 21`, `log "hello"`, `g.spawn do ... end`.
Explicit calls still accept a final block. Parsing is grammatical, not arity-driven;
newlines remain whitespace. `f 1 + 2` is `f(1) + 2`; negative arguments use `f(-1)`.
Indexing and keyed braces retain their meanings. No general `f x`, implicit multi-
literal argument list. Unit fallthrough is separately approved above. Grammar/contracts: syntax.md §12 and
operators-and-blocks.md §7. WORKLIST Q05 implements; XP02 closes the arity experiment
as not adopted. The isolated experiment and its discovered frontend gap are preserved.

### Target syntax and library consolidation — documentation, not implementation

`docs/syntax.md` now integrates spread/rest/import-and-spread and trailing-block
productions, operator protocol summary and a complete target module inventory including
`std.task`. `docs/stdlib.md` replaces the nonexistent `stdlib/README.md` reference with
actual API contracts and explicit missing signatures/export-placement decisions.
String is no longer described as a byte-slice alias; builtin concatenation consistently
covers strings and same-element lists. No public formatting/pattern module is inferred
from implementation filenames. Library completion remains WORKLIST L01/F06/T; this
documentation does not close the whole-doc audit or claim executable support.

### Whippet removal — mandatory completion criterion

WORKLIST D07 removes Whippet entirely from the active project, including
`vendor/whippet`, Whippet headers, dependency/build/link integration, tracing
adapters/descriptors, GC root registration, collection safepoints and obsolete GC
tests/examples. There is no dormant collector fallback. Historical archives retain
evidence only, never active build inputs. Required lifetime, error, stack-limit and
foreign-boundary guarantees transfer to the collector-free contracts. This is an
explicit exit criterion; removal is not yet implemented by this documentation.

### Concrete runtime primitive baseline — approved; not implemented

`docs/runtime-primitives.md` now fixes the initial data structures and algorithms,
not just feature boundaries. Semantic holdings avoid counting register traffic;
TypeOps binds copy/release identities; dead-owner storage drives iterative release.
Lists/strings use specialized COW buffers; stores use fixed nonmoving segments.
Tasks have allocator-generated spill/resume bindings and a PARKING/PARKED/NOTIFIED
handshake. Channels use locked rings/intrusive waits; select uses explicit arbitration;
workers use locked deques, a shared timer heap and a generation-based idle protocol.
Native lazy publication becomes immutable per-realization code plus atomic entry
slots retained for the image lifetime, not whole-image RW/RX reopening under readers.
Live engineering items E01–E06 coordinate existing O/C/D/T/P/W responsibilities.
Exact cell/C/encoding bindings and lock/memory-order proofs remain implementation
work; no second allocator, host-stack suspension or generalized helper engine is added.

### Schema operators and trailing blocks — approved direction, not implemented

`docs/operators-and-blocks.md` records static schema-owned protocol methods and
trailing `do` sugar for a final ordinary lambda. Primitive/boolean behavior stays
fixed; normal effects, receiver places and ownership remain binding. Schema-interface
preservation across structural types and comparison/unordered policy are explicit
design gates. Dynamic `any` dispatch is a separate integration slice, not a new
backend scalar engine or table metatable feature. Live tasks are WORKLIST Q01–Q07;
no parser, runtime or ABI changes are claimed by this documentation.

### Collector-free source ownership — approved design, not implemented

`docs/owners-references-ids.md` now defines one Let language with independent type,
count-free and allocation-free facts. Escaping root values (not entire activations)
are counted from creation; actual-owner rank constraints and immutable construction
prove strong graphs acyclic. Stores use ids and nonescaping slot borrows; COW
strings/lists/tables and frozen values share immutable storage. Shareable counters
are atomic from creation. No collector or runtime cycle detector is permitted.
The source syntax, memory/dynamic targets, task-sharing contract and frontend plan
are aligned; earlier GC documents are preserved in
`research/archive/ownership-before-counted-design/`. Inference/summary ABI, release
failure/concurrency, library edge cases and implementation of the approved `.let`-only
migration remain explicit gates.
No runtime, source-profile gate, bytecode encoding or VM ABI changed in this doc work.
These source memory owners are distinct from caller-owned execution regions below.

### Spread, packs and import sugar — documented target; not implemented

`docs/spread.md` specifies static ordered/keyed supply expansion, fixed-array
expansion, final ordered rest packs, `let ...e` and `use ...std.text` sugar. Packs
have static shape but may contain runtime values; they are not runtime tuples.
Explicit keys override record spread without suppressing evaluation; overlapping
spreads reject. Name spreads cannot shadow and become visible after declaration.
Import sugar retains qualified access and does not automatically re-export names.

- [ ] Approve concrete lexer/parser and elaboration interfaces, including callable
  specialization for generic forwarding and static pack indexing; no second evaluator.
- [ ] Implement source-order, nonrecursive expansion with ordinary IR and preserved
  owner/group bounds; retain existing implicit final-result forwarding.
- [ ] Implement keyed override/conflict checks, static-name introduction and import
  sugar through existing module initialization/discovery, with no duplicate initialization.
- [ ] Validate diagnostics, effects/copies, lexical visibility, rest saturation,
  import equivalence and all applicable execution modes; measure specialization growth.

Runtime list/table call expansion, concatenation spread, first-class packs, lambda
rest and erased variadic callable ABIs are outside this initial scope. Existing
compiler behavior is unchanged; documentation is not parser/runtime support.

### Structured tasks and channels — approved design; not implemented

`docs/tasks.md` now specifies idiomatic Let concurrency: ordinary `std.task` words,
structured groups, explicit `g.channel`, lightweight blocking tasks, scoped select,
yield and cooperative cancellation by marking/closing. Work stealing supplies worker
execution. Normal results represent recoverable failure; abort remains program-ending.
No async syntax, detached tasks, collector or public shared-mutable-reference API.

- [ ] Specify inferred group-capability and world/effect summaries; reject escape
  through `any`, wrappers, ancestor queues or retained results. Check mutable global
  reads as well as writes; separate allocation/counting/suspension/foreign effects.
- [ ] Design task parking and migration with explicit ABC continuations in all four
  bindings, without dependence on worker host stacks or a second allocator.
- [ ] Specify group teardown/repeated-result copies, channel commit/close/drain,
  exactly-once select and cancellation/registration protocols; implement and test.
- [ ] Implement atomic-from-creation sharing, cross-worker iterative releases and
  exact publication/reclamation protocols. Keep published code immutable; design
  synchronized lazy construction and atomic entry indirection before concurrency.
- [ ] Define foreign blocking/affinity, resource failure, coordinated program-abort
  shutdown and embedding behavior; validate races and original error/capacity policy.
- [ ] Validate controlled-clock/seed/event tests, lifetime rejection and effect facts;
  measure scheduling, contention, copy/count traffic and retained queue/result memory.

Cancellation does not force completion; non-yielding tasks can occupy all workers.
Random select has no absolute starvation guarantee. No blanket allocation-free
communication or single-worker real-time determinism claim is made. Concrete ABI
and protocol approval remains required before implementation; current runtime is
not made thread-safe by these docs. Architecture obligations: `docs/architecture.md`.

### Threading platform — pthreads approved; Emscripten deployment unvalidated

Implement runtime workers with pthreads behind a narrow internal wrapper, not a
general host scheduler facade. No direct JavaScript Web Worker backend, event-loop
pump or message-copying fallback is in scope. Lightweight Let tasks remain owned
by the Let scheduler, not mapped one-to-one onto pthreads.

For Wasm, application developers compile generated AOT C and the runtime through
Emscripten pthread support and own flags, worker-pool configuration, JS integration
and hosting/isolation requirements. Let retains responsibility for correct
synchronization, memory lifetime and task protocols. Keep the scheduler off the
browser main thread; document tested startup/blocking/proxying constraints.

- [ ] Specify the narrow pthread lifecycle/synchronization wrapper, including
  partial startup failure, idle/wakeup races and shutdown; no portability framework.
- [ ] Design and implement explicit suspension/resumption and runtime integration
  for task-capable AOT C. Current portable-C subset support is not sufficient.
- [ ] Validate a concrete Emscripten AOT/runtime configuration before claiming
  browser support; cover worker startup, parking, channels, releases and shutdown.

This records the approved scope, not an implemented pthread scheduler or Wasm port.
See `docs/tasks.md` §9.1 and `docs/architecture.md` for the responsibility boundary.

### One Let, one source extension — approved; implementation pending

`.let` is the sole target source extension. Retire SLet as a separate language/profile
and retire `.slet` without a compatibility alias. Type precision, count-free,
allocation-free and transferability remain independent facts; typed and dynamic
code can coexist in the same module. This is not permission to reinterpret old
bytecode or claim unavailable dynamic/ownership capabilities work.

- [ ] Remove filename-selected semantic profiles across parser/checker, compiler APIs,
  lowering and staging; enforce actual capabilities and unsupported features instead.
- [ ] Make imports discover `.let` only; remove `.slet` fallback, dual-extension
  ambiguity rules and source-profile import direction. Diagnose obsolete inputs.
- [ ] Migrate active source examples/fixtures, CLI/build tools, editor integration
  where present and runnable docs together. Preserve historical archives/raw evidence.
- [ ] Validate mixed typed/dynamic `.let` modules, capability rejection, imports,
  CLI/API/staging paths and obsolete `.slet` rejection; run all four execution modes.
- [ ] Audit for surviving semantic SLet dispatch/adapters before claiming unification.

The dependency plan is `docs/frontend-completion-plan.md` (O7). Concrete interfaces
still require the normal implementation design gate. Current `.slet` execution and
`.let` lowering rejection remain unchanged by this documentation update.

This document records the redesign target and phased implementation evidence. The revision-6 runtime and build-time tooling now build through the normal Makefile targets, with focused interpreter/native/optimizer/C checks passing as recorded below. The full active integration suite now passes, including a clean copied-source `all validate` build. Migration closure remains incomplete: phase-5 documentation alignment is underway, the whole-diff review is pending, and the audit has reproduced a native per-location version-budget violation (recorded below). The fixed old/new comparison is measured, with an interpreter Fibonacci regression and native code growth explicitly reported below. Historical typed-engine validation predates this migration and is not evidence for the new ISA.

- **A and B are semantically symmetric.** `.X` selects the relevant operand stack. A binary `OP.X` computes `X0 op Y0`, where Y is the other stack, and leaves its result on X. A and B have no permanent left/right roles.
- **C remains structured state.** Reads from C select their A/B destination; writes to C select their A/B source. Only operations touching neither operand stack are stack-neutral.
- **Bytecode quickening is deferred.** The immediate encoding design reserves no slots for internal quickened opcodes. Keep the existing ahead-of-time cache-state interpreter machinery; it is not bytecode quickening.
- **Observations and native specialization remain separate.** VM-local site state need not rewrite bytecode. Native residualization selects stencils directly from immutable instruction operands and proven facts; it does not need a bytecode quickening phase.
- **Symmetric calls are specified below as the proposed end-to-end contract.** `CALL.X` selects the caller's argument/result channel; `RET.Y` selects the callee's result source. This requires no implicit bank-orientation mode or mirrored function bodies.
- **Private native return-coordinate correction approved by “yes go ahead !”.** Native RET now transfers with C pointing at the existing continuation cell; the caller restores its original C coordinate from that cell rather than assuming the last callee's argument count. All single-result native returns use r0. This supersedes the earlier requirement to retain the old C restoration convention, but does not relocate the continuation cell, change frame storage, or adopt the archived physical-layout experiments. Native indirect integration and the clean full suite pass as recorded below; broader architectural acceptance remains open.
- **The concrete ISA design in [docs/symmetric-isa.md](docs/symmetric-isa.md) is approved for step-by-step implementation.** The complete byte map has 124 ordinary A/B families, EXT.A/EXT.B and six neutral instructions. Four C-operand arithmetic and ten immediate-branch families use EXT. Revision 6 is independent of capability profiles 1–4; indirect calls no longer serialize cache words. Approval is not a claim of implementation or validation.

The runtime, producers and verifier implement revision 6 and pass clean full validation. Core specification/architecture/profile documentation has been realigned; wider documentation and whole-diff review remain open. This document does not claim migration closure, caller-owned region accounting or lazy bytecode execution. The minimum shared interpreter/native observing-site binding is implemented and checked. Historical chunk records below describe their checkpoint at the time; later evidence supersedes their old build/validation blockers without erasing that history. The experimental private return-layout and eager-top C-cache changes remain unadopted.

### Current native threshold: 16 — user-selected default

After the existing-policy 8/16/32 control sweep, the user explicitly selected **16** for the current native default. `src/residualize.c` owns this threshold independently of `ABC_BLOCK_VERSION_LIMIT`, which remains 8 for build-time residual tooling. All four native family/continuation checks use 16; accounting, conformance, continuations and allocation policy are unchanged. The isolated 16 variant passed clean full validation before promotion. The active `make all` rebuild passes, and its debug-stripped native object exactly matches that tested 16 variant. This is not a new shared per-PC cap or implementation of caller-owned regions.

The short pilot reported benefits on some call-heavy workloads but approximately **68% slower lazy branching** at 16, and approximately **11% slower nested lazy calls**. These caveats remain; the selection is not a general performance-win claim. Evidence: `research/experiments/native-version-limits/run-01/README.md`. The architectural target below remains caller-owned region realizations, explicitly replacing the old per-callee-PC budget model; earlier audit records describe that older contract and must not be read as a requirement to implement it before regions.

### Threaded residual execution integration — functional validation passes; performance qualification open

**The expanded-validation capacity blocker is fixed.** This restores the existing frame-coordinate design rather than introducing a new capacity policy: signed frontiers reach the shared capacity comparison before narrowing, covered negative frontiers do not inflate knowledge, and positive requirements are checked against VM bounds before guard emission. Impossible positive requests retain runtime `ABC_STACK` at the original PC. No frame, continuation, allocator or guard-record redesign, and no backend truncation adapter. Full expanded validation passes, including 360 new capacity-frontier cases and 80 lambda executions. Evidence: `research/experiments/threaded-residual/integration/capacity-frontier/README.md`.

[docs/threaded-execution.md](docs/threaded-execution.md) records the implemented components: one execution residualizer and allocator, native output with eight value registers, and an eagerly prepared threaded tape with **seven**. Backend-independent labels and bound operand packets replace native addresses/relocations in common preparation. Native mapping/publication and lazy saved state are backend-owned. `--jit=off|threaded|lazy|eager`, `ABC_EXEC_THREADED=3`, and threaded staging are wired; existing modes/defaults remain intact. Both residual bindings use the existing threshold 16; tooling remains 8. This does not implement caller-owned regions or managed execution.

The earlier, narrower validation checkpoint passed both active and clean builds: 113 oracle cases / 904 mirrored four-mode executions, 660 continuations, 168 return-transport checks, 48 lifetime cases and 280 staging-session checks, plus native/threaded emission-contract tests. The corrected, rotated four-round pilot found threaded/off time ratios 0.439 loop, 0.463 branch, **1.256 Fibonacci**, and 0.825 memory. Fibonacci's 24–27% per-pair regression exceeds the roughly 10% tolerance; this is not a universal speedup or default-change justification. The post-capacity-fix rerun observed a smaller Fibonacci penalty (1.056 median), but substantial noise on other controls; this does not establish a speed improvement. All four tape and native body sizes were unchanged. Shared handler text/table/unwind costs and tape sizes are recorded, while full metadata/peak-preparation accounting and broader performance qualification remain open. Evidence: `research/experiments/threaded-residual/integration/`. Earlier catalog/emitter checkpoint claims remain historical, not claims that the entire current residualizer object is unchanged.

## Execution strategy and implementation checklist

### Governing rule

**Replace the assumption, finish the responsibility, delete the old path, then validate the boundary.**

The working strategy and specified revision-6 ISA are approved by the user's instruction to begin the A/B refactor step by step. Material departures still require discussion before implementation. The checkboxes below track the migration, not the already validated old-semantics checkpoint. The architecture sections following this plan explain the target; they do not expand the scope of an implementation phase automatically.

### Instructions for every implementation chunk

- Work by coherent responsibility and contract, not by the smallest possible diff. Prefer replacing an entire organizing section or file when its assumptions change; preserve correct algorithms and unrelated user work.
- Trace authoritative definitions, producers, consumers and relevant tests before editing. List the files and obsolete assumptions that the chunk replaces.
- Keep one authoritative semantic definition. Generate bindings from it rather than writing independent A and B algorithms or backend-specific semantic repairs.
- Delete replaced implementations, dead variants and obsolete orchestration in the same chunk. Do not retain the old implementation beneath a new facade.
- Do not introduce adapters, compatibility modes, opaque fallbacks, new allocators or new subsystems without discussing a material design change first.
- Keep changes within the approved scope. No opportunistic cleanup or new scheduling optimizations during the semantic migration.
- Temporary build breakage inside a coordinated chunk is acceptable. Record it plainly; do not mark that chunk complete or preserve an incorrect compatibility layer solely to make an intermediate build green.
- Implement substantial coherent replacements across definitions, producers, consumers and tests. Checklist boxes are responsibilities, not micro-patch or test gates; combine related items rather than stopping after each file or function.
- Build and run focused checks at integrated responsibility boundaries, not after each edit. Reserve full-suite/clean/sanitizer/performance runs for relevant milestones. Use an early targeted probe only when it resolves a concrete implementation blocker; diagnose and batch corrections before rerunning.
- Do not repeatedly revalidate the baseline, repair obsolete behavior to keep intermediate states green, or substitute reporting/documentation churn for implementation. Follow WORKLIST's execution policy.
- Preserve explicit ABC continuations, capture/liveness, result order, escaped storage, traps and the agreed stack-capacity policy.
- Do not silently switch to a new return-slot layout or host-recursive ABC execution.
- Do not use subagents or internal edit-plan sidecars without a separate explicit request. [WORKLIST.md](WORKLIST.md) is the live checklist; this file preserves chunk evidence.

Before a chunk, record its scope and expected exit condition. Afterward, record changed responsibilities, removed paths, checks actually run and their outcomes. Check a box only when that specific item is complete; use a short blocked/partial note otherwise. A passing output test is not evidence that an obsolete abstraction was removed.

### C naming and defensive-code policy

Prefer descriptive responsibility names, especially where multiple stack roles coexist:

```c
selected_stack
opposite_stack
return_result_source_stack
continuation_result_destination
capture_value_before_home_replacement()
```

Avoid ambiguous abbreviations such as `s`, `rs` or `fix()` for these roles. Names should explain what a value or operation means and, where useful, why it exists. Put deeper rationale and invariants in comments rather than making names narrate every implementation step. Established mathematical notation and fixed ABI names remain appropriate in their local contexts; do not perform unrelated renaming sweeps.

Validate at trust boundaries; rely on established invariants internally. Module verification, indirect target/ABI validation, allocation limits, required traps and effect boundaries are real obligations. Rechecking verifier guarantees throughout hot execution, speculative fallback paths and defensive layers for impossible states are not the default design. Use focused assertions where they help expose implementation errors without inventing new runtime behavior.

### Phase 0 — Freeze scope and baseline

- [x] Preserve the exact dirty typed checkpoint, including untracked source. Evidence: `research/archive/typed-before-ab-symmetry/source.tar.gz`, original status/HEAD/patch; matching build archive at `/tmp/abc-before-ab-symmetry.tdOxjk/build.tar.gz`. Active files were not restored or overwritten.
- [x] Record existing validation evidence without rerunning the full suite. Evidence: `research/experiments/ab-symmetry/typed-validation.log` and its README record the prior full pass and build command, explicitly not new-ISA validation.
- [x] Capture a fixed arithmetic/branch/recursive-call/memory baseline. Evidence: four workloads × interpreted/eager/lazy, seven timed samples each on CPU 0; `baseline-results.txt`, object sizes, host/artifact checksums and independent reference-result checks in that directory.
- [x] Scope this migration to symmetric typed execution, coordinated producers/consumers and removal of bytecode quickening.
- [x] Exclude dynamic reintegration, caller-owned region implementation, new lazy-bytecode execution, pressure-driven evaluation reordering and the experimental physical return ABI.

**Exit:** reproducible reference state and bounded scope. The broader JIT target remains documented, not bundled into this migration.

### Phase 1 — Finalize the machine contract and encoding

Primary areas: `tools/opcodes.lua`, `gen/semantics.lua`, `docs/spec.md`, module/callable/foreign format contracts and the verification rules they imply.

- [x] Inventory every public instruction family, operand layout, stack effect and mirrored semantics. Evidence: `docs/symmetric-isa.md` covers the 145 existing typed families, including C/memory/control operations and host entry/exit.
- [x] Specify the proposed direct, indirect, tail, foreign and return contracts end to end. Evidence: the ISA design defines argument source, vector/C order, result source, continuation destination and protected prefixes. Approved for step-by-step implementation; implemented and validated by the later phase-2/3 and integration evidence.
- [x] Allocate the proposed 256-entry core opcode map without quickening reservations. Evidence: 124 ordinary pairs + two EXT prefixes + six neutral bytes; fourteen named families receive explicit EXT selectors. No typed operation is removed.
- [x] Specify the proposed module revision independently of capabilities. Evidence: revision 6, profiles 1–4, regenerated producers/offsets, no old-semantic compatibility engine; four serialized cache bytes are removed from each indirect call.
- [x] Trace bytecode quickening dependencies. Evidence: `research/experiments/ab-symmetry/quickening-audit.md` identifies all 30 internal variants, interpreter writers, serialized cache fields, mutable-code ownership, native phase patching, statistics and affected tooling/tests. Cache-state dispatch and ordinary native linkage remain distinct.
- [x] Specify the minimum shared observing-state binding. Evidence: that audit defines one VM/module observation word per original site, a common checked resolver and mode-independent public target identities. Old phase patch registries and permissive native target representations must be removed, not wrapped; broader region ownership remains excluded.
- [x] Present the concrete ISA contract, file responsibilities and encoding and obtain approval. Evidence: `docs/symmetric-isa.md`, this plan and the user's instruction to begin the A/B refactor step by step. New material design changes still require approval.

**Exit:** no unresolved operand-role, call-interface or encoding questions delegated to coding. If later inspection exposes a material incompatibility, stop and return to this gate.

### Phase 2 — Replace definitions and concrete execution

Primary areas: `tools/opcodes.lua`, `tools/gen_opcodes.lua`, `tools/assembler.lua`, `gen/semantics.lua`, `gen/banked.lua`, `gen/cache.lua`, relevant cold/foreign generation, `src/module.c`, `src/memory_module.c`, `src/vm.c` and their interfaces. This is a responsibility map, not permission to rewrite files whose responsibilities have not changed.

- [x] Replace authoritative definitions with selected-stack contracts. Evidence: revision-6 manifest plus `gen/semantics.lua` bank-independent transfers drive generated operation identities, transfer classes, profiles, roles and decoding layouts.
- [x] Generate mirrored interpreter bindings and cache transitions from one semantic definition. Evidence: rewritten `gen/banked.lua` uses me/other and the existing cache; duplicate `gen/banked_manifest.lua` removed. All eight generated partitions compile under strict warnings.
- [x] Update assembly, disassembly, decoding and verification together. Evidence: manifest-driven assembler/CLI and `src/verify.c` unify the former integer/memory verifiers; revision 6 is independent of profiles 1–4. Fourteen original/mirrored assembly-to-execution cases pass.
- [x] Implement symmetric concrete call/frame/return transport without a physical continuation ABI change. Evidence: all four caller/return-source combinations pass for one and two results with live caller prefixes; direct/indirect tail cases pass.
- [x] Remove internal bytecode quickening and interpreter rewriting. Evidence: no mutable interpreter code copy; direct targets bound at load; observation words retain first-failure/mismatch/final behavior and code bytes remain unchanged in tests. Native phase-patching removal is now implemented and checked in the phase-3 indirect chunk below.
- [x] Retain the cache-state interpreter and explicit transfers. Evidence: 2,400 existing exact-state cases with poisoned dead arguments pass, including selected-first B subtraction/division/shifts/power. This is focused evidence, not a claim of full continuation/capacity-suite conformance.
- [x] Build the complete affected runtime/tooling targets. **Build boundary completed during phase 3:** normal `make all` now succeeds, including runtime, static/shared tooling and CLI targets. Focused revision-6 checks use the normal artifacts. This is not a clean-from-empty rebuild, full-suite pass or frontend semantic validation. See `research/experiments/ab-symmetry/phase-3-optimizer.md`; `phase-2.md` remains the historical isolated-link checkpoint.

**Exit:** hand-written new-ISA programs run correctly in the interpreter; the concrete layer does not retain the old semantics as an alternative path. Downstream migration still pending is recorded explicitly, not hidden behind shims.

#### Phase 2, first chunk — authoritative encoding metadata

- Replaced: `tools/opcodes.lua` and `tools/gen_opcodes.lua`, rather than adding a new map alongside the old one.
- Removed from those definitions: all 30 internal quickening variants, the legacy integer opcode boundary, historical dynamic selectors and destination-only memory metadata. No old opcode aliases or metadata adapters were added.
- New contracts: semantic operation identity independent of byte encoding; explicit selected bank/role, operand layout, minimum profile, exact instruction length and memory properties. Core and EXT decoding return the same borrowed instruction view, not a residual representation.
- Checks run: the Lua manifest matches all 256 core bytes and 14 selectors in `docs/symmetric-isa.md`; standalone `tools/validate_isa.c` passes for mirror metadata, independent golden encodings, indirect-call lengths and complete switch decoding. Generated header compiled with Clang 20 under strict warnings.
- Integration boundary: the full runtime has **not** been rebuilt or validated. Old consumers still reference the removed metadata/opcodes and must be replaced next. Existing build artifacts remain the preserved old-ISA baseline; their successful execution is not revision-6 evidence.
- Reproduction: `luajit tools/gen_opcodes.lua /tmp/abc-symmetric-isa-check/opcodes.h`, then compile `tools/validate_isa.c` with that include directory. This check is not yet wired into the full build while its consumers remain on the old interface.
- At that first chunk, semantic bindings and execution were still pending. They have since been implemented and checked at the concrete boundary, as recorded below.

#### Phase 2, concrete execution and module boundary

Evidence and reproducible commands: `research/experiments/ab-symmetry/phase-2.md` and `phase-2-checks.log`. New revision-6 modules now assemble, load, verify and execute in the concrete engine, including EXT, float/memory forms, independent call/return banks, foreign transport and observing-site transitions. Old integer-only verification, the duplicate banked manifest and bytecode rewriting were deleted rather than retained under adapters.

The isolated test link uses new concrete/loader/verifier objects ahead of the preserved library for remaining dependencies; its inherited native backend is **not executed or validated**. The full build and native/frontend execution are still incomplete. Next work is the coordinated symbolic/native/tooling migration in phase 3, then frontend lowering and integrated validation.

### Phase 3 — Replace symbolic and residual bindings

Primary areas: `gen/symbolic.lua`, `src/symbolic.{c,h}`, `src/residualize.c`, `gen/stencils.lua`, `src/optimize.c`, `src/residual_builder.c`, residual analysis/validation and ABC/C emission, with their declared interfaces.

- [x] Make selected-stack-first operand ordering authoritative in symbolic execution, folding and callback contracts. Evidence: shared symbolic migration and float-relation correction; 28 selected-bank / 96 float contracts pass in clean integration.
- [x] Parameterize call argument gathering and return-result sources; keep the continuation destination distinct. Evidence: native return/indirect migration and 495 continuation executions.
- [x] Bind native operations directly to selected/other registers through the existing cache allocation state. Evidence: binary/memory bindings, direct stencil checks and mirrored three-mode integration.
- [x] Remove reverse stencil families and B-only fusion exceptions whose sole purpose was the old A-left convention; retain independently justified forms. Evidence: binary/normalization chunks and phase-5 active-path search; unrelated dead-code review is still open.
- [x] Update optimizer, residual ABC and portable-C producers/consumers consistently. Evidence: 50 mirrored optimizer modules / 234 execution pairs, 299 residual-IR checks and 12 portable-C cases within its supported subset; no A-only repacking adapter.
- [x] Preserve capture, consumed-operand liveness and error propagation through the existing symbolic cache. Evidence: 14 capture contracts plus continuation/alias/pressure integration; no separate native value IR or allocator introduced.
- [x] Build affected targets and run interpreter/native/tooling equivalence checks. Evidence: clean `all validate`, most recently `backedge-placement/clean-final-validate.log`. The broader single version-budget target remains a separate conformance gap, not covered by these ISA migration boxes.

**Exit:** concrete and residual execution share the new contract, with obsolete native orientation machinery removed. The result is not merely a manifest edit or a working facade over old internals.

#### Phase 3, binary orientation chunk — partial

Scope: selected-first integer/float binary transfers and their direct native primitive bindings; remove reverse families and the B-subtraction narrow-fusion exception without changing allocation or continuation layout.

Implemented: shared binary callbacks/folding now receive selected-first operands; the native binary bindings use ordinary stencils for either destination. Integer, narrow-integer and float reverse stencil families were deleted, and layout offsets now account for the current shared unary list. No alternative orientation path remains in these binary bindings.

Checks: all 3,800 generated stencils compile and extract; 17 layout assertions pass; 19 direct native primitive contracts pass with untouched-register checks. Added eight symbolic contract cases, but they have **not run**, since the shared dispatch and remaining symbolic/native interfaces still need migration. Whole-function eager/lazy execution is not validated. No phase-3 checkbox is marked complete from these partial results.

Details and commands: `research/experiments/ab-symmetry/phase-3-binary.md`. Next: finish shared symbolic dispatch/forms and operation identities, then call/return/site-state and tooling consumers, retaining capture and explicit continuation control.

#### Phase 3, instruction walkers — partial

Migrated residual call-graph discovery, optimizer call-kind classification and symbolic reachability walkers off the removed opcode-kind table. Native and residual-builder block discovery now uses complete decoded operand views and lengths, including EXT immediate branches and SWITCH tables. Existing recursion, nested-eligibility and block policies are unchanged.

The complete residual call-graph component compiles with strict warnings. Original and A/B-mirrored revision-6 modules pass independent checks for seven edges/components across nine functions, including compact indirect calls, tail-only and mixed recursion, EXT and opcode-looking literal bytes. Containing symbolic/native/optimizer components remain unbuildable; their changed walkers are not yet validated in integration. No phase-3 completion box is checked from this partial evidence.

Evidence and remaining limitations: `research/experiments/ab-symmetry/phase-3-call-graph.md` and `phase-3-call-graph.log`. A syntax-only symbolic diagnostic still identifies removed scalar/EXT names and the old memory metadata interface; next work must replace those contracts and the dispatch generator without aliases.

#### Phase 3, memory bindings — partial

Replaced the removed memory descriptor across symbolic transfers, native bindings, residual IR construction and optimizer memory emission. Selected addresses and opposite values/indices now retain their roles; IDX/LDX results remain on the selected stack. Optimized ABC memory results select their requested destination without orientation-repair moves.

Corrected two native MEMCPY deviations from the approved contract: u16 count truncation and forward-only copying. Native stencils now bind the same existing `memmove` operation as the interpreter, with an independent u32 count relocation. No new allocator, copy algorithm or continuation ABI was added.

Checks: all 3,800 stencils compile/extract; 27 direct native primitive cases and 16 original/mirrored interpreter cases pass, including overlapping copies larger than 65,535 bytes. Eight symbolic memory contracts were added but remain unrun. Full native/optimizer/residual-builder memory integration is not yet validated; scalar/control interfaces and the dispatch generator still block the coherent build. Phase-3 checkboxes remain open.

Evidence, commands and limits: `research/experiments/ab-symmetry/phase-3-memory.md` and `phase-3-memory.log`.

#### Phase 3, shared symbolic engine — implemented component, integration pending

Replaced symbolic dispatch with generated bindings from the revision-6 shared transfers, including typed EXT dispatch and selected scalar/control forms. Scalar callback identities and generated constant folds now use semantic operations, not canonical A opcode bytes. Shared call/return/tail/foreign transports distinguish selected argument/result sources from continuation destinations. Removed the obsolete rewritten-opcode effect interface rather than retaining it as a fallback.

The complete shared symbolic component compiles under strict warnings. Its validator passes 28 selected-bank contracts plus narrow-fold and existing context/control/fusion regressions; this includes the previously queued binary/memory tests and all four CALL/RET combinations with ordered multi-results and tail preservation. Native scalar binding syntax checks pass, but full native execution and optimizer/residual-builder consumer migration remain unvalidated.

**Native transport decision approved by the user's “i a pprove !”:** the existing general native return protocol publishes through A. Routing RET.B through an A scratch vector could require hidden A capacity; duplicating callees by destination is not the agreed design. A proposed explicit result-source tag in existing r2 at return transfer, preserving the current C continuation cell/layout and rebase convention, is documented in `research/experiments/ab-symmetry/phase-3-symbolic.md`. This private register protocol change is approved. The direct/host binding has since been implemented and checked as recorded below; native indirect integration is still pending. No extra ABC storage, permanently reserved register, or new return-slot layout is permitted.

Evidence: `phase-3-symbolic.md` and `phase-3-symbolic.log` in the same experiment directory. No whole-phase checkbox is marked complete from the component pass.

#### Phase 3, approved native return-source protocol — direct/host binding checked

Implemented the approved r2 source selector after result publication, retaining r1 continuation transport, the existing specialized r0 result path, and the physical C continuation slot/rebase convention. Direct calls gather from their selected bank and restore both prefix coordinates; real resumes transport vectors directly to the continuation destination without an A scratch vector. Direct tails preserve the original destination, and host RET/HALT accept either source. Native foreign bindings now select their argument/result bank for zero and one result.

Evidence: 33 interpreter/eager/lazy checks pass for real recursive multi-result calls across all four CALL/RET combinations, mixed return sources, changed-arity tails, single-register returns, host B delivery, and an exactly full opposite prefix with a below-limit trap. The existing banked/call validator passes 27 cases, including mirrored zero/one-result foreign calls in all modes. All 3,802 stencils compile/extract. No final performance claim or whole-phase completion is made.

Details and limits: `research/experiments/ab-symmetry/phase-3-native-returns.md` and its log. That chunk left the private indirect observation/patch registry and host-recursive helpers for the follow-up now completed below. Optimizer/residual-builder/frontend integration and full capture/continuation validation remain pending.

#### Phase 3, return-coordinate correction — implemented prerequisite

The user explicitly approved two corrections exposed by indirect-tail migration: return through the existing continuation-cell C coordinate, and use r0 uniformly for single-result native returns. A general indirect tail target can have a different argument count from the original callee; its return must not leave the caller guessing the old C frontier. It must also satisfy a caller that receives a singleton in r0.

Implemented in `src/residualize.c` and `src/symbolic.{c,h}`: native RET normalizes C before explicit transfer, real-call resumes restore C from their continuation-cell offset, and single-result returns no longer depend on an entry-specific `reg_return` flag. That flag and its context-copy/equality distinctions were removed, not retained as another ABI variant. The physical continuation cell, frame-address identities and host delivery remain unchanged.

Checks: strict compilation of the shared symbolic component and native binding; 36 interpreter/eager/lazy return checks, including a new live caller-C-prefix case; 27 banked/call cases; 28 selected-bank symbolic contracts plus existing regressions. Evidence: `research/experiments/ab-symmetry/phase-3-return-coordinates.log`. These remain isolated component links, not a whole-tree build or performance comparison.

At that checkpoint, native indirect resolution/observation ownership and the old host-recursive helpers still required replacement. That follow-up and its changed-arity tail checks are recorded below.

#### Phase 3, native indirect binding — implemented and boundary checked

Replaced the native indirect subsystem with the shared `vm_resolve_indirect()` owner and exact public target/ABI checks, followed by actual-target capacity checking, selected argument transport and explicit native transfer. CALLI stores a real resume label; TCALLI preserves the continuation and uses the approved normalized C return coordinate. Singletons use r0; multi-results retain selected-source/r2 transport. The symbolic unresolved-tail path now stops after its sink transfer rather than emitting unreachable capture/CPUSH work afterward.

Deleted private native site state, phase-specific patch registry/helpers, permissive target representations, host-recursive ABC calls, raw indirect stencil families, the synthetic return-sentinel stencil, duplicated site statistics and conservative maximum-over-all-candidates capacity checks. No new allocator, permanently reserved register, bytecode rewriting or public execution policy was introduced.

Evidence: 120 interpreter/eager/lazy return checks; 36 banked/call cases including mirrored histories, mixed-binding shared ownership, exact identity/full ABI errors, provenance, unchanged failure outputs, VM isolation and immutable eager native code; 28 symbolic selected-bank contracts plus existing regressions. Changed-arity tails cycle 2,000 times at four cells; indirect recursion reaches 2,000 levels. Actual-target capacity checks accept a small target despite an oversized same-signature alternative. All 3,770 stencils compile/extract (77,472 artifact bytes). No final performance claim or whole-phase completion is made.

Details, encountered failures/fixes, reproduction and limitations: `research/experiments/ab-symmetry/phase-3-native-indirect.md` and its log. **Next:** migrate optimizer/residual-builder and residual ABC/C consumers to the semantic-operation and selected-bank contracts; integrate full capture/continuation/resource checks before phase 4. Whole-tree build and final performance validation remain pending.

#### Closed tangent — eager C-cache experiment

Retain the current state-aware C cache. The approved isolated fixed-top-three experiment reduced handler text but did not establish a speed advantage; several workloads regressed substantially. Neither the candidate nor a new cache policy was promoted to the main VM. Evidence, raw measurements, patch and source snapshot references: `research/experiments/c-cache-eager/README.md`.

The experiment also provided fresh-build evidence for the current revision-6 runtime: its complete runtime library and CLI built from the preserved current-source snapshot, and the 36 banked/call cases, 28 symbolic contracts, 120 return checks and 16 mirrored interpreter cases passed without the earlier preserved-library dependency link. This does not establish whole-tree tooling/frontend integration or replace the phase-5 performance comparison.

Resume phase 3 at optimizer/residual-builder and residual ABC/C contract migration. C-cache redesign is not part of that work.

#### Pre-tooling current-VM performance checkpoint

At the user's request, benchmarked the unchanged current-policy VM before further tooling edits. Verified all 37 snapshot-listed runtime/header/generator/build/assembler sources match the fresh runtime build. Nine identical revision-6 workloads ran in interpreted/eager/lazy modes, with six counterbalanced rounds and seven steady-state calls per round, pinned to CPU 0. All 27 workload/mode combinations matched expected results. Recorded preparation, first call, steady-state samples and native bytes separately.

Evidence and reproduction: `research/experiments/pre-tooling-vm/README.md`, raw `timings.json`, source/artifact hashes and preserved modules. Example medians: fib28 10.252 / 2.552 / 3.364 ms (interpreter/eager/lazy); warm C reads 23.111 / 4.049 / 4.022 ms. Lazy fib28 is about 32% slower than eager in this checkpoint; no fix or causal explanation is claimed. This is not the phase-5 comparison against the fixed old-ISA frontend baseline, nor a representative application benchmark. Runtime implementation is unchanged. Next remains the phase-3 tooling consumers.

#### Phase 3, residual-builder callbacks — component checked; C binding issue exposed

Migrated `src/residual_builder.c` from scalar opcode-byte assumptions to semantic operation identities and selected-bank conversions/checks, direct/indirect/tail/foreign argument gathering, and RET/HALT result sources. The existing residual IR, capture/block transport and recursion policies remain. Removed A-only gathering/result selection in these callbacks; no compatibility adapter or runtime change was introduced. Also corrected the comparison classification that incorrectly included floating arithmetic and assigned it integer result types.

The expanded existing residual-IR validator passes **235 checks**, including **34 mirrored builder fixtures** for operand order, EXT/immediate forms, conversions/checks, all CALL/RET combinations, ordered vectors/live prefixes, C replacement capture, foreign/indirect transport and real/virtual tails. Relevant components compile strictly; the focused link uses the fresh revision-6 runtime, not the pre-migration library. Ordinary optimizer/tooling build remains pending.

Portable-C execution checks passed the two original/mirrored warm-read cases, then exposed an invalid call binding: a scalar/no-failure caller invokes a zero-result general-ABI helper with an undeclared `error` parameter. The helper also leaves its output parameter unused. This is not patched with fabricated failure facts or a fallback. Discuss the C binding before modifying it: preserve the existing scalar/vector ABIs, select error/status transport from the callee's actual failure proof, and test zero/multi-result and failing callees. Remaining C checks have not run. Existing ZX8/ZX16 residual support gaps, optimizer/ABC emission and full integration are still open.

Evidence, exact boundaries and reproduction: `research/experiments/ab-symmetry/phase-3-builder.md`, `phase-3-builder.log`, and `phase-3-builder-c.log`. No whole-phase checkbox or performance claim follows from this component pass.

**C-binding correction approved by “yes i approve !”.** Scope: retain the existing scalar and vector C ABIs and existing failure analysis; proven non-failing vector callees receive `NULL` without status propagation, while potentially failing callees retain error/status transport. Account for unused zero-result output parameters. Exit: compile and execute mirrored zero/multi-result calls plus genuinely failing callees, checking ordered outputs, status, trap provenance and unchanged failure outputs. Do not fabricate failure facts, introduce adapters or change the VM/native runtime.

#### Phase 3, approved portable-C call binding — implemented and checked

Implemented the approved correction in `src/residual_c.c`. Ordinary vector calls use `NULL` with no status propagation only when the existing analysis proves the callee non-failing. Potentially failing calls retain their error channel and early status return. Scalar/vector ABIs and failure facts are unchanged; zero-result output parameters are explicitly accounted for. No runtime/native change or fallback was introduced.

**26 mirrored portable-C execution cases pass**, including all twelve previously planned cases and fourteen focused zero/multi-result and failure cases. Tests inspect generated ABI/error-channel choices and execute success/failure through the same artifact, checking ordered results, exact abort provenance, null public error pointers and unchanged failed outputs. Emitter and generated code compile under the documented strict-warning policy. The old failure log remains historical, not a current blocker.

Evidence and reproduction: `research/experiments/ab-symmetry/phase-3-c-binding.md` and `phase-3-c-binding.log`. Portable C remains its integer/static subset. Next: optimizer semantic-operation consumption and selected-bank ABC emission, followed by whole-tooling integration. Whole-phase completion and final performance validation remain pending.

#### Phase 3, optimizer/ABC emission — implemented and focused integration checked

Migrated `src/optimize.c` scalar/check callback identities, selected argument/result capture and destination-parametric binary emission. Core/EXT bytes now bind through the generated manifest metadata; ordinary and joined control trees share one selected-bank emitter. Branch fixups use complete instruction ends and provenance rollback follows code rollback. RET result sources and HALT's host-only identity are retained. Existing DAG, classical Ershov scheduling, effect ordering, loop policy and verified original-function retention remain; no new allocator, compatibility engine or runtime optimizer dependency was introduced.

Independent checks exposed and corrected EXT bank lookup through bank-neutral selector metadata and an existing address-CSE bug that merged different image offsets. Both are corrected at their authoritative binding/identity points, without downstream repair layers.

Normal `make all` and focused tooling targets now build. **48 mirrored optimizer modules / 228 original-versus-optimized execution pairs pass** in interpreter/eager/lazy modes, including selected EXT encodings, nested noncommutative operations, capture, branch outcomes, joins, calls/tails, HALT, image addresses, traps/provenance and bound foreign effects. Tests establish actual optimizer emission rather than counting unchanged-function retention. Twelve additional existing workloads pass 36 mode checks; only fib28 rewrites, and the other eleven are explicitly reported as retained.

Focused regressions also pass: ISA metadata; 36 banked/call cases; 28 symbolic contracts and existing regressions; 235 builder/IR checks; 120 return/indirect checks; 16 mirrored interpreter cases; 14 capture contracts; 26 portable-C executions against the normal tooling archive. Evidence and limitations: `research/experiments/ab-symmetry/phase-3-optimizer.md` and its logs. This is not a clean whole-tree rebuild or full-suite validation; no performance improvement is claimed.

**Checkpoint next step (now implemented below):** close the residual-builder/C normalization gap and migrate the continuation, escaped-storage and resource regressions. Broader fixture/frontend integration remains open.

#### Phase 3, approved normalization and continuation integration — checked

Added explicit ZeroExtend8/ZeroExtend16 schema operations, direct builder bindings with the existing U32 representation, and unsigned narrowing casts in portable C. No new scalar algorithm, type, runtime dependency, bytecode encoding, GC policy or native continuation layout. **263 builder/IR checks and 32 mirrored portable-C cases pass**, including full-width/boundary inputs and preserved ordered values.

Migrated continuation fixtures by their selected argument/independent result-source contracts, removing historical vector reversal assumptions rather than renaming them. **495 executions pass** across interpreter/eager/lazy, including wide vectors, caller prefixes, HOME capture, mutual tails, stack exhaustion, escaped/partial/overlapping frame writes and callee traps. The suite runs early in `make validate`. Corrected the call-graph validator to link its owning tooling archive. Optimizer checks remain 48 mirrored modules / 228 execution pairs.

Normal builds pass. **Full validation still fails:** after the early migrated suites pass, `tools/validate.lua` emits historical `MOVE_BA`, rejected by the revision-6 assembler. Remaining legacy fixtures/frontend integration must not be reported complete. Evidence: `research/experiments/ab-symmetry/phase-3-normalization.md` and logs.

#### Phase 3 tooling benchmark checkpoint — measured, not final ISA comparison

Preserved earlier baselines and ran six interleaved rounds of frozen pre-tooling VM/current VM/current optimizer output on nine identical revision-6 workloads: **486 processes / 3,402 timed calls**, all correct. Only fib28 rewrites; the other eight modules are controls. Source checks show runtime sources unchanged; native sizes match baseline/current on original modules.

For fib28, current original → optimized median milliseconds are interpreted **18.846 → 16.793**, eager **4.529 → 4.315**, lazy **6.386 → 6.495**; native sizes **732 → 707** and **542 → 528** bytes. All three paired per-round ratio ranges cross parity, and identical-code controls show substantial variability. These medians do **not** establish speedups; the lazy median is slightly worse. Loading, preparation and first-call times are separately retained. This is not the final old/new ISA or near-C comparison. Evidence: `research/experiments/ab-symmetry/phase-3-tooling-bench/README.md`, raw measurements and hashes.

### Phase 4 — Replace frontend lowering

Primary areas: `frontend/let/abc.lua`, affected frontend/staging producers, active assembly examples and relevant compiler/lowering/optimizer fixtures.

- [x] Implement destination-parametric expression lowering with live prefixes on both stacks. Evidence: phase-4 frontend chunk, 33 symmetric executions and compiler/lowering integration.
- [x] Lower reversed comparisons by operand placement while preserving evaluation order and NaN behavior. Evidence: selected-first frontend binary lowering and mirrored float/branch regressions.
- [x] Update calls, conversions, checks, C transfers and memory operations. Evidence: production typed backend and 81 lowering checks plus three-mode source executions.
- [x] Delete obsolete A/B orientation repairs. Evidence: phase-4 destination-parametric lowering; remaining comparison-result moves are required by the selected destination, not the historical A-left convention.
- [x] Migrate active fixtures/examples with independent expectations; preserve old evidence in archives. Evidence: final cache/example migration and clean full validation; historical files are not accepted as current encodings.
- [x] Keep unsupported dynamic execution clearly separated. Approved boundary implemented: obsolete profile-5 text emission removed; Let parsing/typechecking/import IR remain; ABC lowering rejects explicitly. SLet execution/staging suites pass. See `phase-4-dynamic-boundary.md`; no dynamic runtime support is claimed.
- [x] Run frontend end-to-end cases through supported modes/tooling. Evidence: 78 production SLet executions, 209 lambda checks / 60 VM executions, optimizer/staging/session and portable-C subset suites in clean integration. This does not complete the source virtual-value/static-demand architecture.

**Exit:** frontend-produced typed programs exercise the new ISA end to end. Parametric placement is implemented; new Ershov scheduling/evaluation reordering remains a separately approved optimization follow-up.

#### Phase 4, typed destination-parametric lowering — first checked implementation

Implemented selected/opposite typed expression placement in `frontend/let/abc.lua`, including recursive loads/addresses, unary forms, normalization, conversions/checks, stores and argument/call helpers. Reversed comparisons preserve left-to-right evaluation and floating NaN behavior; only the boolean result is transferred when required. ANF statement boundaries retain their existing A default, C storage is unchanged, and functions retain one explicit RET.A body. No new scheduling model or runtime mechanism was introduced.

Checked: **33 new original/optimized/native/C execution processes**, **78 existing lowering checks**, **24 staging checks**, **50 mirrored optimizer modules / 234 execution pairs**, **263 builder/IR checks** and **495 continuation executions**. A frontend trap-order test exposed an optimizer known-failing-check terminator defect; it now emits the same numeric-range ABORT as the residual-IR binding, preserving earlier effects and provenance. Evidence: `research/experiments/ab-symmetry/phase-4-frontend.md` and logs. No benchmark rerun.

**Not complete:** optimizer/general fixtures still contain old-ISA text. The compiler suite also expects legacy profile-5 assembly-only output, and now stops at unsupported dynamic binary lowering. At this checkpoint, rejecting dynamic ABC lowering while retaining Let IR was proposed for discussion. It was subsequently approved and implemented as recorded below. Some existing lowering checks still inspect historical managed text and do not validate runtime support. Phase-4 boxes remain open.

#### Phase 4, approved dynamic boundary — implemented with SLet validation

Removed obsolete profile-5 emission, managed descriptors/storage promotion and A-only dynamic instruction paths from the ABC frontend. Let parsing/typechecking/semantic IR remain, with `Compiler.typedFile` exposing the existing checked import phase; `compileFile` uses that same pipeline. Executable Let lowering and staging report `dynamic-lowering`, including scalar-only Let, without silently changing language profiles. CLI failure preserves an existing output file.

SLet is retained and checked through `make validate-slet`: **259** source compiler/IR/boundary checks, **81** lowering checks (including real typed indirect adapters in all three modes), **24** staging checks, **33** symmetric execution processes, **12** mirrored portable-C cases, schema/walker/parser checks and spec operand-form validation. Normal strict build and the 50-module/234-pair optimizer suite pass. Full `make validate` reaches and passes these and 495 continuation executions, then still stops at historical `MOVE_BA` in `tools/validate.lua`. The legacy frontend optimizer fixtures also remain to migrate; neither suite was bypassed.

Evidence: `research/experiments/ab-symmetry/phase-4-dynamic-boundary.md` and logs. No runtime/native/GC changes or performance rerun. **Next:** migrate the remaining active bytecode fixtures/examples and complete whole-suite integration; this is not phase-4 or refactor completion.

#### Requested current-tier SLet benchmark — measured, not a final ISA baseline

Approved and completed an isolated fresh-build comparison through the production SLet frontend: interpreter, eager, lazy, portable C AOT, handwritten C, and LuaJIT on/off. Eight scalar-u32 workloads use runtime inputs; 290 preflight processes and 406 timed processes / 2,842 steady samples all match independent expectations. Frozen sources (202 hashes), raw samples, pipeline costs, sizes and disassembly are under `research/experiments/slet-tiers-r6/`; historical baselines remain untouched.

Measured eager/interpreter speedups span 4.08–22.13×. Eager is clearly ahead of LuaJIT on branch/multiply/divide/mix, but Fibonacci's eager/LuaJIT round range crosses parity. AOT is near handwritten C on several loops, yet multiply is 2.55× slower and ordinary Fibonacci 1.68× slower. The latter gap largely disappears with C sibling-call optimization disabled (paired AOT/C median 1.033, range 0.967–1.090). Generated Fibonacci retains two recursive calls and a uint64 private signature, while ordinary handwritten uint32 Fibonacci uses one recursive arm plus a loop. These are measurements/structural leads, not implemented fixes. No runtime changes or performance tuning were made.

This scalar-only current-tier comparison does not complete phase 4/5, validate dynamic/GC execution, or replace the fixed old/new ISA baseline. See the experiment README for host/noise limits and non-comparable historical workloads.

#### Phase 4, frontend optimizer fixtures and API examples — checked

Migrated `frontend/tests/optimize.lua` and the callable/virtual/foreign examples to selected-stack forms, preserving ordered counter vectors and independent results. Indirect targets load directly on the opposite bank; the B callable example gathers arguments on B and returns from B. Replaced obsolete zero-observation native API expectations with the shared unseen/monomorphic/final-generic contract across nine A/B/tail entry/mode histories, including failure-output preservation and no eager compilation during execution.

**105** frontend optimizer/FFI checks and the expanded API suite pass. They now run before the remaining legacy general-validator blocker in normal `make validate`; existing suites are retained. The integrated attempt also passes the 259 compiler, 81 lowering, 24 staging, 33 symmetric-execution and 495 continuation checks. **Full validation still stops at `MOVE_BA` in `tools/validate.lua`.** That validator's selected operands/calls, complete core/EXT coverage walk, memory/control forms and failure offsets are next; cache fixtures and remaining active examples still need audit. No runtime change, benchmark rerun or phase completion is claimed. Evidence: `research/experiments/ab-symmetry/phase-4-fixtures.md` and logs.

#### Phase 4, general validator — partial migration exposes a runtime contract defect

Reworked `tools/validate.lua` to produce selected-first revision-6 fixtures and their A/B mirrors, decode complete core/EXT/SWITCH instructions for 282-form assembly coverage, and verify real process statuses plus independent results/trap PCs. No old-syntax adapter or runtime change was introduced. **Not validated:** arithmetic passes, but the float fixture stops at a real native control defect before later cases/coverage/bootstrap dependencies execute.

Minimal runtime-input probes in both banks show FBLT/FBEQ returning incorrect native booleans and FBLE failing native compilation. The symbolic generator and constant folder use float-specific relation ordinals 0/1/2; native emission and the residual builder consume the shared EQ/LT/LE enum. Proposed authoritative correction: generate named shared relations and update the common float folder, retaining existing native/IR consumers and adding folded/runtime/NaN/mirrored regressions. At that checkpoint, approval was pending before runtime edits. The correction was subsequently approved and implemented below. No encoding, placement, continuation, GC or optimizer eligibility change was proposed.

Evidence and exact scope: `research/experiments/ab-symmetry/phase-4-general-blocker.md`, logs and minimal float-branch probes. Full validation is now blocked earlier in the migrated general suite by this demonstrated runtime defect, not merely old MOVE syntax. The retained legacy bootstrap frontend still emits old instructions and remains a later boundary to resolve. Phase 4 remains incomplete.

#### Phase 4, approved floating-branch correction — implemented and checked

Unified symbolic branch generation and float constant folding on named `ABC_SYM_*` relations, removing the competing float-specific numbering. Native and residual-IR consumers already used the correct enum and remain unchanged. The callback invariant is documented; no new scalar algorithm, fallback, bytecode/ABI or placement/effect policy was introduced.

**96** generated float dispatch/fold contracts pass, covering both banks, known/unknown inputs, ordered/equal/NaN/signed-zero/infinite values and preserved prefixes. Residual-IR checks now total **299**, including six independently encoded branch/operand-order cases. The migrated general validator passes **92 oracle cases / 552 mirrored three-mode executions**, including 288 new folded/runtime float-branch executions, and assembles all **282** public core/EXT forms. All 18 minimal wrong-answer/failure probes now succeed.

The integrated strict `make validate` attempt also passes SLet/compiler/lowering/staging, 105 frontend optimizer checks, the 50-module/234-pair optimizer suite, API, capture and 495 continuation executions. **The next failure is the retained legacy bootstrap frontend emitting bare `BGEUI` for bootstrap-fibonacci.** That boundary and later cache/example integration remain unresolved; full validation and phase 4 are not complete. No suite was bypassed, and no benchmark rerun or floating portable-C support is claimed.

Evidence: `research/experiments/ab-symmetry/phase-4-float-correction.md` and logs. Historical float-branch failure evidence is preserved.

#### Phase 4 integration checkpoint and separate source-compilation foundation

The approved bootstrap retirement is implemented: its compiler and original fixtures are archived under `research/archive/bootstrap-slet-before-retirement/`; build distribution no longer includes it. Production-source integration now checks **78 executions** plus current rejection diagnostics. Historical `seed(40)`/`seed(41)` calls are not inherently runtime values: the source-knowledge work may establish them as static without changing SLet's partial-supply rule.

The separately approved VM staging-session foundation is implemented. `build/libabc.so` contains the existing runtime, independent of `libabc-opt.so`. The frontend now owns in-process VM/module sessions with exact scalar transport and structured diagnostics; one-shot staging uses the same service and its old subprocess path is removed. No ISA, scalar algorithm, native continuation, cache allocator or Ershov scheduling policy changed. Source virtual values/places, required-static demands, the approved `staticMode` API policy, initialization snapshots and managed Let execution remain pending.

Checked: **24 existing staging checks + 211 new session/ABI checks**, including all three modes, optimized/unoptimized preparation, persistent and isolated images, stores surviving aborts, cleanup, exact floating bits, signature/transport rejection, and execution with optimizer loading and subprocess helpers disabled. A clean copied-source `all validate-slet` build passes. Full `make validate` passes the frontend, API, continuation and **552 general executions / 282 assembled forms**, then fails assembling the still-legacy cache fixture: `line 3: unknown instruction RET; selected forms require .A or .B`. Full validation and phase 4 remain incomplete.

Evidence and narrow bridge-overhead measurements: `research/experiments/source-partial-evaluation/staging-session/README.md`. These measurements are not the final old/new ISA comparison or a source-partial-evaluator performance claim.

**Subsequent validation blocker:** adding abandoned-session GC coverage exposed an existing lazy-VM teardown use-after-free. `abc_vm_free` releases the image's module before freeing native lazy state, which still reads `module->code_size`. A standalone public-C-API ASan probe reproduces it after the caller releases its module reference before VM destruction (a supported ownership pattern). The current session suite now segfaults on this path; the earlier clean run/211 checks did not cover it. The session slice is therefore incomplete. No Lua ordering workaround or runtime fix has been applied; the proposed correction is to destroy image/native state before dropping its retained module reference, with all-mode lifetime/GC/ASan regressions.

#### Approved staging lifetime correction — validated

Corrected the authoritative teardown dependency in `src/vm.c`: image/native lazy state is destroyed before its retained module reference is released, including the native-preparation failure cleanup order. No Lua finalizer ordering workaround was added. **27 public-API lifetime cases** cover all mode pairs and calls before/after releasing caller ownership; they pass under ASan with leak detection enabled (vm/residualize/test instrumented, not the whole runtime). **217 session/ABI checks** now pass, including abandoned-session GC in all three modes, alongside the original 24 staging checks.

A new copied-source clean `all validate-slet` build passes. Full `make validate` again reaches the separate legacy cache fixture and stops on its bare `RET`; the GC teardown blocker is resolved, but full integration remains incomplete. Source partial-evaluation APIs/virtualization and initialization snapshots are still pending. Current evidence and a noisy, narrowly scoped bridge-overhead rerun: `research/experiments/source-partial-evaluation/staging-session/lifetime-fix/README.md`. The prior failure logs and ASan reproduction are retained.

#### Source-compiler follow-up: lambda annotations — validated

Ordinary lambdas now accept explicit parameter annotations without a repeated binding signature, inferring results through the existing return-contract path. Contextual parameter typing remains unchanged. Annotation types are resolved once; no provisional result contract is emitted, and no capture/ownership, representation, scheduling or source-evaluation policy changed.

`frontend/tests/lambdas.lua` passes **209 checks / 60 VM executions** across original/optimized SLet in all three modes, plus Let semantic-IR checks. Equivalent annotation spellings emit identical assembly; nullary/unit/f64/vector/block forms and expected-signature contexts are covered alongside rejection diagnostics. `make validate-slet` passes. Full validation was not rerun for this chunk; the prior legacy cache-fixture blocker remains unresolved. Source virtual values and static-demand integration remain pending. Evidence: `research/experiments/source-partial-evaluation/lambda-signatures/README.md`.

#### Phase 4, cache fixtures and remaining shipped examples — clean integration passed

Replaced historical directional COPY/MOVE spellings in `tools/validate_cache.lua` with source-selected forms and explicit RET.A, retaining its independent logical-stack oracle and all 655 cases. Migrated the remaining `examples/memory.abcasm` and `examples/divmod.abcasm` selected forms without reordering operands. The existing general validator now permanently executes these examples and their mirrors, including ordered division results, aggregate frame results, image/address loads and the large-frame entry. No runtime, ABI, cache policy, compatibility adapter or scalar algorithm changed.

**Full `make validate` passes.** A fresh copied-source **`all validate` also passes** with no reused generated build files: **2,400 poisoned-register exact-state checks**, **655 cache-transition cases** (two public calls each), **97 general oracle cases / 582 mirrored three-mode executions**, all **282 assembled forms**, 495 continuation executions, and the frontend/optimizer/staging/lifetime suites. Earlier cache failures are historical, not current blockers. Evidence: `research/experiments/ab-symmetry/phase-4-final-fixtures/README.md` and raw logs.

This closes the observed active-suite blocker, not the whole refactor. Phase-5 contract/dead-path/documentation audit, complete-diff review and fixed baseline comparison remain pending; the separate source virtual-value/static-demand work is also still incomplete. No performance claim follows from fixture migration.

### Phase 5 — Close the migration

- [x] Run the full active validation suite after integration. Evidence: clean copied-source `all validate` passes after the final cache/example migration; see `phase-4-final-fixtures/clean-full.log`. Rerun affected checks if subsequent fixes alter their contracts; do not treat an earlier pass as covering later edits.
- [x] Run the fixed performance comparison against the preserved typed baseline, with the same tools and workloads. Evidence: `research/experiments/ab-symmetry/final-comparison/README.md`; six paired rounds, unchanged workload sizes and timing logic, one documented private-API adjustment in optional runner dump code. Measurement is complete, not performance acceptance: interpreter Fibonacci regresses and several native images grow.
- [ ] Audit for old A-left/A-only assumptions, quickened opcode paths, dead reverse families, duplicated semantics and hidden adapters.
- [ ] Align documentation with implemented/validated behavior. **Partial; tracked as A02:** core runtime and new collector-free/task/spread docs have been aligned, but the complete cross-document audit remains open. Historical GC/open-word target passages are superseded, not future packages to implement.
- [ ] Report code/metadata size, interpreter and native performance changes, incomplete work and untested paths. Distinguish structural expectations from measurements.
- [ ] Review the complete migration diff for unrelated changes and preserve user work.

**Exit:** a coherent new-ISA checkpoint with evidence, not a collection of partial patches. Resume the broader JIT redesign only as a separate approved phase.

#### Phase 5, format audit and fixed comparison — partial closure

Corrected `docs/module-format.md` against the actual revision-6 loader/verifier and all typed profile sections, including independent selected CALL/RET banks and protected caller operands even at zero arity. Removed old-version acceptance, serialized call-cache words, A-only results and current profile-5 claims. Corrected the selected-first operand rule in `AGENTS.md`, updated the symmetric-ISA status, and explicitly marked the broad `docs/spec.md` body as awaiting audit rather than normative where it conflicts. Sixteen independent header/rejection/example checks pass. Broader profile/architecture pages and complete-diff/dead-path review remain pending; see `research/experiments/ab-symmetry/phase-5-audit/README.md`.

Ran the fixed phase-0 old/new comparison on CPU 0 with seven-call batches: 24 preflight processes, six paired rounds / 144 measured processes / 1,008 timed steady-state calls. Every process succeeds with the expected final result. Frozen runner/module/source hashes remain unchanged. Current runtime objects match the clean-validation build after stripping debug data. The current runner changes only the removed private entry-count field in optional dump labeling; measured execution/timing code is unchanged.

**Measured regressions and gains:** interpreter Fibonacci has paired new/old median **1.160**, range **1.149–1.172**; memory interpreter **0.768**, range **0.707–0.798**. All other paired ranges cross parity, including eager Fibonacci despite its worse median. Banked-handler text shrinks **15.5%**, but its data grows **10.9%**. Native images often grow: eager loop **416→627 bytes**, eager memory **264→450**, lazy memory **227→324**. Disassembly shows additional memory-workload entry/home handling and return sequences; no complete causal explanation or fix is claimed. Preparation, first-call times, code sizes, raw process evidence and noise limitations are retained in `research/experiments/ab-symmetry/final-comparison/README.md`.

No runtime tuning or operand-entry ABI was introduced. The comparison measures migration as a whole, not an isolated benefit of symmetry. Performance acceptance, documentation/diff review and separate source partial-evaluation work remain open.

#### Phase 5, requested performance investigation — causes narrowed, no fix adopted

Fibonacci's old/new bytecode has the same 45-byte size and semantic instruction sequence; extra bytecode work is not the regression. Old warmed CALL_A_1/RET_1_1 handlers specialize counts, while current transport and outgoing state selection depend on immutable counts at runtime. A separate dropped optimization is confirmed: old generated known-state dispatch clears dead ABI arguments; current dispatch forwards all slots, causing additional register preservation. Six-round old/new leaf-versus-inline probes (72 processes / 504 timed calls, all successful) show increased incremental call-boundary cost, but do not isolate those two causes or attribute the whole 16% regression.

Memory native body growth is fully decomposed: eager **+186 = 134** bytes of an extra home-backed realization **+ 2×26** bytes of enlarged exits; lazy **+97 = 71** extra header/body bytes **+26** exit bytes. Correct immediate folding now retains the initial counter as a constant; the pre-existing backedge rule materializes, stores and rehomes that constant, creating an extra context. Old immediate emission ignored the folded flag and accidentally produced a register instead. An independent writable-image counter probe removes this distinction and leaves exactly **+52 eager / +26 lazy** return overhead. Do not restore redundant arithmetic or undo the explicit return contract as a workaround.

The benchmark native-byte metric counts emitted body bytes, **not lazy stubs, heap metadata or reserved mapping capacity**. Broader size/cycle attribution remains open. No implementation was changed. Proposed next discussions are dead-slot argument binding through existing cache occupancy, then placement-preserving knowledge weakening with canonical descriptor review; neither is yet implemented or approved as a fix. Evidence: `research/experiments/ab-symmetry/investigation/README.md`.

#### Phase 5, approved dead-slot candidate — measured and rejected

Implemented the first proposed experiment: known outgoing cache states bind dead h/c handler arguments to zero, including EXT entry, while preserving live values and leaving dynamic-count transfers unchanged. The independent generator check covered **16,020 direct / 120 EXT bindings**; full `all validate` passed.

The isolated six-round comparison against the preserved pre-fix revision-6 binary rejects the candidate: interpreter paired medians are **1.063 branch**, **1.067 Fibonacci**, and **1.537 memory**, with every paired sample slower for those workloads. Loop is noisy; native controls cross parity and native body sizes are unchanged. Handler text grows **40,364 bytes (~2%)**. A simple load handler gains five zeroing instructions: imposing zero on semantically dead slots adds work without correcting the untouched dynamic call/return binding.

Preserved candidate source, validation and raw measurements in `research/experiments/ab-symmetry/dead-slot-binding/README.md`, then removed only the candidate's exact edits. The generator/cache-validator hashes and Makefile match the pre-experiment state; rebuilt **restored `all validate` passes**. No dead-slot performance fix is adopted. A narrower binding design requires discussion; the separate native constant/backedge placement issue remains unchanged.

#### Phase 5, approved native backedge placement correction — validated

`src/residualize.c:edge()` now weakens constant knowledge without unconditionally forcing memory placement: materialize through the existing cache allocator and construct the canonical register descriptor at the same destination home. This removes the save/rehome path for this case; genuine spills and generic-entry conformance remain. Canonical construction clears inactive constant payload fields used by context equality. No new allocator, IR, register reservation, interpreter policy, version budget or continuation change was introduced.

Added mirrored A/B/C constant, live-alias, register-pressure and conditional/unconditional backedge cases: the general validator now passes **113 oracle cases / 678 executions**. A structural native version-bound regression fails on the pre-fix runtime and on a temporary stale-payload mutation, and passes on the corrected runtime. Full `all validate` passes, as does a fresh copied-source build; the final strengthened fixture also passes the full suite in that clean build. Existing 495 continuation, 2,400 poisoned-register, 655 cache-transition, source/optimizer/staging/lifetime and other active checks remain passing.

Measured identical-module native body sizes shrink on all four fixed workloads. Memory is **450→309 eager / 324→246 lazy**, removing the predicted extra context and initial home store. Loop is **627→581 / 446→404**; branch **1818→1790 / 1172→1126**; Fibonacci **1040→1024 / 798→789**. These counts exclude lazy stubs, heap metadata and reserved mapping capacity.

Six paired rounds show eager Fibonacci ratio **0.878**, lazy **1.070**; an independent eight-round repeat shows **0.860** and **1.112**, respectively. Lazy's roughly **7–11% median regression** remains explicit, with noisy ranges; the user indicated tolerance around 10%, not a requirement to recover every percentage point. Other native ranges cross parity. No interpreter performance fix or general speedup is claimed. Raw evidence, precise test boundaries and reproduction: `research/experiments/ab-symmetry/backedge-placement/README.md`. Broader audit, interpreter regression and source static-demand work remain open.

#### Phase 5, contract/documentation audit — partial, budget violation reproduced

Aligned the current specification, architecture and memory/callable/foreign profile pages with revision-6 selected-first behavior, independent CALL/RET banks, immutable code, shared observation records, current cache/native placement and the actual source/staging/profile-5 support boundaries. Replaced the mixed current/historical prose with explicit current contracts and labeled targets; six original pages and their measurements/decision rationale are preserved with hashes in `research/archive/phase-5-documentation-before-alignment/`. Stable specification decision numbers remain. Corrected the module-format typo: CALLI has **one** count byte after its opcode (two total), TCALLI **two** (three total). Updated the document index and the inbound source-staging anchor. Existing project instructions already state selected-first semantics and were left unchanged.

Reconciled phase-3/4 checkboxes against their component records, actual bindings and the latest clean full validation. These boxes establish the typed ISA/frontend migration, not completion of virtual-place/source-demand work or the broader native target. Historical partial-build/failure records remain chronological evidence. Current active-path search finds no old directional opcode/reverse-family/quickening implementation markers; a textual search is not a complete dead-code or whole-diff review.

**Architectural gap confirmed, not fixed:** `abc_symbolic_context_family_equal()` includes the virtual continuation chain. `version_for()`/`edge()` count matching families, while `inline_candidate()` caps continuation families separately. This differs from the approved **eight total versions per original PC**, including the general slot. A four-call-site loop returns **42 in all three active modes**, but an isolated audit-only native build records **10 versions at helper entry PC 50** in both eager and lazy modes. Raw traces, assembly and the diagnostic-only patch are preserved. No production implementation was modified, and the required budget was not weakened to bless existing behavior.

**Checks:** 29 encoding/header/example/budget-evidence checks pass; local links in the six main pages resolve. All recorded runtime/generator/header/frontend/tool/Makefile hashes are unchanged. Full validation was not rerun for documentation edits; the recent clean pass remains evidence for the unchanged runtime, not proof of budget conformance. No new performance results are claimed. See `research/experiments/ab-symmetry/phase-5-contract-audit/README.md`.

**Remaining:** discuss a coherent single-budget correction before runtime edits; complete wider target-document and whole-diff/dead-path review; retain explicit performance caveats and incomplete source/managed work. Phase 5 stays open. Hybrid C-top caching remains parked and unimplemented.

### Validation budget and completion evidence

Use a small decisive contract set during implementation:

- mirrored noncommutative arithmetic, correct divisor/shift count/exponent and representative comparisons;
- live-prefix preservation, mutable-HOME capture and full-bank/spill transitions;
- all four CALL.X/RET.Y combinations, ordered multiple results and preserved continuations;
- representative indirect, tail and foreign calls;
- selected-stack C/memory transfers, conversions and checks;
- representative traps, stack limits and source provenance.

Reuse and adapt existing validators where they already cover the contract. Add missing architectural cases rather than creating overlapping suites. Run the relevant subset at each chunk boundary and the full active suite at integration. A generator and tests derived from that same generator are not independent evidence: retain explicit expected results and mirrored execution checks.

Measure baseline/final performance rather than benchmarking every intermediate edit. Investigate unexpected regressions with targeted measurements. Record preparation time, steady-state time, emitted code/handler bytes and relevant transport/dispatch counts separately; do not claim that fewer source definitions necessarily mean less emitted code or faster execution.

Suggested chunk completion record:

```text
Chunk:
Contract replaced:
Files/responsibilities changed:
Old paths removed:
Checks run and outcome:
Performance evidence, if relevant:
Remaining work or design questions:
```

---

## Architectural target

 The redesign should make the fast core the center of the architecture, not a backend hidden underneath an increasingly elaborate JIT.

 Here is the target for the specification, building on the validated typed engine—not a claim that every part is already implemented.

 The governing idea is:

 │ Execute the shared ABC semantics with symbolic values. Let the existing cache determine placement. Emit the remaining work directly into the chosen target.

 Everything else exists to establish valid entry facts, connect those emitted pieces, and bound specialization.

 ────────────────────────────────────────────────────────────────────────────────

 1. The whole machine

 There are two ways to execute the instruction semantics:

 ```text
                              ABC instruction semantics
                                         │
                       ┌─────────────────┴─────────────────┐
                       ▼                                   ▼
                concrete execution                  symbolic execution
                       │                                   │
            values in the stack cache           constants, captured values,
                       │                         homes, proofs and placement
                       ▼                                   │
             interpreter handlers              ┌───────────┼───────────┐
                                               ▼           ▼           ▼
                                              ABC        native        C
                                            bytecode    stencils
 ```

 The interpreter and residualizer are not independent implementations of the language.

 They differ in what they know:

 ```text
   Interpreter:
       A0 contains 40.
       B0 contains 2.
       Execute the addition.

   Residualizer:
       A0 is the value held in r3.
       B0 is the known constant 2.
       Emit an add-immediate stencil.

   Residualizer, stronger facts:
       A0 is known to be 40.
       B0 is known to be 2.
       Record the constant 42; emit no addition.
 ```

 The native path is deliberately short:

 ```text
   verified ABC + entry contract
                │
                ▼
   shared symbolic instruction execution
                │
                ├── update stack names and cache placement
                ├── fold proven computations
                ├── preserve checks and effects that remain
                └── copy and patch register-addressed stencils
 ```

 abc-opt is not a prerequisite. It may improve the bytecode beforehand, but the runtime must accept verified ABC without invoking the build-time optimizer.

 The ABC and C sinks may use their own build-time representations. Those representations must not become an intermediate stage in native stencil emission.

 ────────────────────────────────────────────────────────────────────────────────

 2. Why ABC gives this compiler so much for free

 The architecture should begin with the machine, rather than with a generic compiler diagram.

 ```text
   Selected stack X          Other stack Y
   ┌──────────────┐          ┌───────────────┐
   │ left operand │ X0       │ right operand │ Y0
   └──────────────┘          └───────────────┘
              \                 /
               \   operation   /
                └──────┬──────┘
                       │
                  result on X

   .A selects X=A, Y=B
   .B selects X=B, Y=A

   C
   ┌─────────────────────────┐
   │ bindings                │
   │ frame blocks            │
   │ arguments               │
   │ explicit continuations  │
   └─────────────────────────┘
 ```

 For a binary operation:

 ```text
   SUB.A:
       result = A0 - B0
       consume both operands
       put result on A

   SUB.B:
       result = B0 - A0
       consume both operands
       put result on B
 ```

 `.X` selects the primary operand stack, not merely the result destination. Operand order is always selected stack first, other stack second. The same orientation applies to division, remainder, shifts, powers, floating-point operations and comparisons.

 ```text
   SUB.X:     X0 ← X0 - Y0
   SUBI.X k:  X0 ← X0 - k
   SUBC.X d:  X0 ← X0 - C[d]
 ```

 These are operand forms of one semantic operation. Dynamic scalar operations must use the same selected-stack-first rule, not two operands on A or B forms implemented by repacking through A.

 C reads and writes are symmetric with respect to the operand stacks:

 ```text
   CGET.A d:  A.push(C[d])       CGET.B d:  B.push(C[d])
   CPUSH.A:   C.push(A.pop())   CPUSH.B:   C.push(B.pop())
   CSET.A d:  C[d] = A.pop()    CSET.B d:  C[d] = B.pop()
 ```

 CGET/CGETR and frame-address/load forms select an A/B destination. CPUSH/CPUSHN, CSET and frame stores select an A/B source. C itself is not exchanged with either operand stack. CPOP, CALLOC, CFREE, unconditional jumps and aborts are stack-neutral.

 The remaining families follow the same explicit orientation:

 | Family | Selected-stack contract, with Y opposite X |
 | --- | --- |
 | Unary, conversion, normalization, check `.X` | Operate on X0 |
 | Binary branch `.X` | Consume and compare X0 against Y0 |
 | Immediate branch `.X` | Consume and compare X0 against the immediate |
 | SWITCH.X | Consume the selector from X |
 | GLD.X / GST.X | Load onto / store from X |
 | LD.X | Address and loaded result on X |
 | ST.X | Address on X, value on Y; consume both |
 | IDX.X / LDX.X | Base on X, index on Y, result on X |
 | MEMCPY.X | Destination address on X, source address on Y |
 | HALT.X | Supply host-entry results from X under the verified halt contract |

 These are target contracts, not assertions that the mirrored opcode forms already exist. Source evaluation order is unchanged: placement choices must not reorder effects, checks or traps.

 The symmetry law is: exchanging A and B in the program and machine state, including continuation destination selectors, produces the corresponding exchanged execution. It does not exchange C's role or require identical physical register assignments or timings.

 The compiler already knows:

 - which values an instruction reads;
 - which operand cells it consumes;
 - where its result belongs;
 - which C locations it accesses;
 - the verified stack shape at control-flow boundaries.

 It therefore does not have to recover those properties from an unstructured instruction stream.

 The symbolic cache is already the allocation state.

### Parametric expression lowering

 Symmetry replaces A-shaped and B-shaped lowering cases with one destination-parametric rule:

 ```text
   compile(left op right, dst):
       compile(left, dst)
       compile(right, other(dst))
       emit OP.dst
 ```

 This applies to noncommutative operations too. There is no reverse-operation case for a B destination, and no MOVE whose purpose is to repair the old permanent-A-left operand convention.

 The recursive contract is essential: compile(E, dst) produces E's result on dst while preserving pre-existing live operand values on both stacks. The existing cache owns capture, alias preservation and spills. Necessary transport for those obligations, calls, returns and edge conformance does not disappear.

 Greater-than needs no extra comparison or operand-order repair:

 ```text
   compile(a > b, dst):
       compile(a, other(dst))   // evaluate a first
       compile(b, dst)          // evaluate b second
       emit LT.dst             // compute b < a
 ```

 Likewise, a >= b uses b <= a. Use the corresponding signed, unsigned or floating-point comparison. In particular, floating-point greater-than is a reversed less-than, not a negated less-or-equal: NaN behavior must be preserved. Operand placement is independent of evaluation order; reversing the comparison does not authorize evaluating b before a.

### The two cached tops are the binary-operation interface

 Relative roles connect expression lowering directly to the divided stack cache:

 ```text
   left   = top(me)
   right  = top(other)
   result replaces top(me)
   consume top(other), exposing its next value
 ```

 Both stack tops have a useful role in every two-stack binary computation. When both operands are resident and the selected register is safely writable, the operation binds directly to `selected_register OP= other_register`. There is no rearrangement merely to repair operand orientation.

 Recursive me/other lowering naturally distributes intermediate values across the banks. For example, compile a - (b - c) into A, preserving evaluation order:

 ```text
   evaluate a → A
   evaluate b → B
   evaluate c → A     // above the preserved a
   SUB.B              // b - c on B; exposes a on A
   SUB.A              // a - (b - c) on A
 ```

 Divided stacks, destination-parametric lowering, cached tops and destructive native operations therefore reinforce one another. This is a structural benefit, not a guarantee of optimal balance or minimum register pressure. Tree shape and live prefixes still matter; aliases may require capture, and deeper values may require spills or refills. Caching both tops does not mean replacing the existing bank with only two registers. No new allocator or scheduling pass is implied.

### One handler definition, mirrored bank bindings

 The existing operand bank has A anchored at h0 and B at h3. Its mirror transformation is:

 ```text
   selected stack:  A ↔ B
   cache counts:    (a, b) ↔ (b, a)
   bank registers: h[i] ↔ h[3-i]   for i = 0..3
   C state:        unchanged
 ```

 Generate the selected-stack operation once and derive both bindings, including their cache-state transitions and operand-home accesses. Do not maintain a separately handwritten B algorithm. The transformation applies to operand-bank registers, not to all native ABI registers or C's cache registers. Continuation destination selectors mirror where the instruction contract requires them.

 This removes a class of B-only semantic and placement drift by construction. Mirrored-state execution tests must still check the generator and its bindings; generated code is not its own correctness oracle.

 In this sense the compiler and generator's A/B-specific logic halves: two directional implementations collapse into one parametric definition. This is not a promise that the entire compiler or emitted handler text halves. Distinct concrete cache-state handlers still exist. Removing reverse native stencil families required solely by the old operand convention is a separate code-size opportunity to measure.

### Ershov scheduling without a privileged side

 Subtree pressure can guide scheduling independently of operand-bank identity. For example, if the right subtree is heavier and evaluation reordering is proven safe:

 ```text
   compile(right, other(dst))
   compile(left, dst)
   emit OP.dst
 ```

 The results are already on their semantic sides even though the right subtree was evaluated first. Either stack can hold the heavier subtree; neither has a permanently privileged position in the operation.

 Ershov-style pressure estimates inform the existing compiler's scheduling; they do not introduce another allocator or override the symbolic cache's placement state. Classical single-pool estimates are not by themselves a complete cost model for the divided stacks and live prefixes. Preserve required effect and trap order, including resource-failure behavior under the agreed policy; purity alone is not sufficient proof that reordering is harmless. Compare actual spills, captures, transport and execution costs before claiming a scheduling improvement.

### Encoding: compact public operations first

 The complete proposed allocation and instruction layouts are in [the revision-6 ISA design](docs/symmetric-isa.md). The map fits exactly:

 ```text
   00–F7: 124 ordinary selected-stack families, even=A / odd=B
   F8/F9: EXT.A / EXT.B; followed by one family-selector byte
   FA–FF: six neutral operations, with no bank selector

   124 × 2 + 2 + 6 = 256 core bytes
 ```

 Neutral bytes encode CPOP, CALLOC, CFREE, JMP, JMP32 and ABORT individually, rather than wasting a pair on each. All selected core operations use bit 0 consistently. CGET.A and CGET.B are one family with two destinations, and their short-depth forms remain in the core.

 The existing manifest has 145 public typed families after pairing. All are represented: 124 ordinary core families + one EXT family + six neutral families + fourteen extended families. ADDC/SUBC/MULC/XORC and the ten immediate-branch relations receive EXT selectors 00–0D. Their one extra operation byte and interpreter dispatch cost are explicit trade-offs to measure, not assumed negligible. Ordinary integer/float comparisons and fused two-stack branches retain direct core encodings.

 This is a one-byte core ISA, not a claim that all historical fused forms have a single-byte operation encoding. No extra bank mode, quickened variant or hidden A-only execution path is introduced. The exact allocation is approved for the step-by-step migration, but has not yet been implemented.

 **No opcode slots are reserved for bytecode quickening in this design stage.** Do not add internal arity, signature-shape or observed-target opcode families merely to preserve the old quickening scheme. EXT remains an escape for extended operations, not a reason to add a new rejection subsystem. No new dynamic selectors or guard encodings are allocated by this document.

 The new meaning of SUB.B and CALL.B is incompatible with old bytecode. The proposal assigns module revision 6 with independent profiles 1–4, retains the existing profile-specific metadata layouts and regenerates code offsets and active fixtures. CALLI/TCALLI lose their four-byte mutable cache field; immutable signatures and VM-local observing state remain. Old modules are not reinterpreted under the new rules or executed through a compatibility engine. The complete byte layouts and migration policy are specified in the linked ISA design.

 ────────────────────────────────────────────────────────────────────────────────

 3. Keep three identities separate

 This is important enough to make explicit in the spec.

 ┌─────────────────────┬───────────────────────────────────────────────────────────┐
 │ Identity            │ Answers                                                   │
 ├─────────────────────┼───────────────────────────────────────────────────────────┤
 │ Source origin       │ Which original ABC instruction is this?                   │
 ├─────────────────────┼───────────────────────────────────────────────────────────┤
 │ Region owner        │ Whose specialization budget pays for this emitted code?   │
 ├─────────────────────┼───────────────────────────────────────────────────────────┤
 │ Local control point │ Where are we inside this particular residual realization? │
 └─────────────────────┴───────────────────────────────────────────────────────────┘

 They are not interchangeable.

 Suppose main inlines helper twice:

 ```text
   main region, version 2
       ...
       first inline copy of helper
           original helper PC 0x120
       ...
       second inline copy of helper
           original helper PC 0x120
 ```

 Those two instructions have:

 - the same source origin;
 - the same region owner;
 - different local control points because their continuations differ.

 Consequences:

 - Traps still report original PC 0x120.
 - An observing instruction at that PC still refers to one shared site history.
 - The two inline copies do not consume the standalone helper’s version budget.
 - Their branches and returns cannot be confused merely because their original PCs match.

 The local distinction can use the existing virtual-continuation path. It does not require a new value IR.

 ────────────────────────────────────────────────────────────────────────────────

 4. Caller-owned residual regions

 This is the substantial correction to the old “eight versions per callee block” rule.

 What a region is

 I propose this definition:

 │ A residual region is a compilation unit rooted at a declared entry in the caller’s original control flow. A region realization includes the internal control flow of the acyclic callees it virtualizes.

 A straight-line caller can therefore include several calls:

 ```text
   Region R, rooted in caller A

       caller computation
       CALL helper_B       ── virtualized
           B's computation
           B's branch
           B's join
           RET
       caller computation
       CALL helper_C       ── virtualized
           C's computation
           RET
       caller branch       ── edges to successor regions
 ```

 A practical boundary rule is:

 - Original function entries and ordinary caller control-flow entries provide region roots.
 - A virtual call and its matching return do not, by themselves, create a new owner.
 - Control flow inside an inlined activation remains owned by the enclosing region.
 - A real call transfers into independently compiled callee code; its return resumes the existing caller realization.
 - Caller control-flow exits connect to successor region entries.

 That gives caller ownership a concrete meaning without making an entire program one region.

 What consumes a slot

 ```text
   Owner: (VM/module instance, region root R)

       slot 0: general realization
       slot 1: specialized realization
       slot 2: specialized realization
       ...
       slot 7: specialized realization
 ```

 A realization consumes one slot. Its constituent blocks do not each consume another slot.

 ```text
   R, specialization 1
       caller block
       inline B
           3 internal blocks
           inline C
               2 internal blocks
       inline D
           5 internal blocks

   Total: one region realization
   Not: eleven versions charged separately
 ```

 Twenty known small helpers can belong to one realization.

 Another caller has its own owner:

 ```text
   Caller A ── owns its inline copies of helper
   Caller B ── owns its inline copies of helper
   Caller C ── owns its inline copies of helper

   helper's standalone owner
       covers separately entered helper code
 ```

 This removes the cross-caller cliff.

 It does not make all specialization order irrelevant: the first seven distinct specialized arrival contracts at one owner can still depend on eager scheduling or lazy arrival order. What disappears is competition between unrelated callers of a
 popular helper.

 No hidden internal version families

 There is an essential companion rule:

 │ Internal labels are not independent, unlimited specialization tables.

 Within one realization, arrivals at the same local control point must converge on compatible contracts. Branches merge facts; loops widen changing facts.

 An interior observation does not silently create an unbudgeted family of native blocks. New externally selectable entries require an explicit region boundary and ownership rule.

 This is how “a large realization counts once” avoids becoming a loophole.

 ────────────────────────────────────────────────────────────────────────────────

 5. An entry contract is a proof obligation

 A version’s contract describes what must be true when that version is entered.

 Conceptually:

 ```c
   struct EntryContract {
       VerifiedStackShape shape;
       SymbolicCache placement;
       ProvenFacts facts;
       ContinuationContract continuation;
   };
 ```

 These names illustrate the responsibilities. They are not a proposal for another collection of runtime value objects.

 The facts can include:

 ```text
   A0:
       captured value in r3
       exact constant unknown
       represented as raw integer bits
       upper 32 bits proven zero

   B0:
       exact constant 7

   C2:
       aliases the same captured value as A0

   call target:
       exact function F, with this site's ABI validated
 ```

 Things that do not belong in the contract:

 ```text
   "this site was monomorphic last time"
   "the first sample happened to be a u32"
   "this block has executed 200 times"
 ```

 An observation can suggest which contract is worth compiling. It cannot establish that contract for subsequent arrivals.

 Compatibility first, conformance second

 Suppose a target requires:

 ```text
   value x: normalized u32 in r1
   value y: arbitrary integer in r4
 ```

 An arrival provides:

 ```text
   x: exact constant 12
   y: arbitrary integer in r2
 ```

 The proof requirements are satisfied:

 ```text
   12 is a normalized u32.
   y meets the unrestricted integer requirement.
 ```

 But the placement is not:

 ```text
   materialize 12 into r1
   place y into r4
 ```

 Conversely, having the right registers does not compensate for a missing proof.

 This distinction prevents both unsafe specialization and unnecessary rejection of arrivals that know more than the target requires.

 ────────────────────────────────────────────────────────────────────────────────

 6. Native emission remains copy-and-patch

 The existing native signature already captures the intended shape:

 ```c
   #define JIT_ARGS                      \
       uint64_t *asp,                    \
       uint64_t *bsp,                    \
       uint64_t *csp,                    \
       uint64_t r0, uint64_t r1,          \
       uint64_t r2, uint64_t r3,          \
       uint64_t r4, uint64_t r5,          \
       uint64_t r6, uint64_t r7
 ```

 There is no bytecode instruction pointer in the running native stream.

 A stencil binds an operation to the registers it touches:

 ```c
   /* Illustrative stencil source. */
   JIT_CC uint64_t add_r3_r5(JIT_ARGS)
   {
       r3 = r3 + r5;
       MUSTTAIL return HOLE_NEXT(JIT_PASS);
   }
 ```

 Other registers remain in their fixed argument positions.

 With symmetric operands, both A and B bind the same destructive operation shape:

 ```text
   rd = writable(selected stack's value)
   rs = materialize(other stack's value)
   emit(operation, rd, rs)      // rd ← rd op rs
 ```

 The old native emitter selects reverse-operation stencil families specifically for B destinations, and contains a B-specific SUB/ZX32 fusion exception. The corrected semantics removes that semantic reason for reverse families and B-only fusion rules. Alias preservation, capture and valid normalization proofs still apply. This is a structural simplification to implement and measure, not a claim of an already achieved code-size or speed improvement.

 Native emission already consumes immutable operands, signatures and proven facts. It selects their stencil bindings directly; it neither waits for nor performs bytecode opcode quickening.

 Offline:

 ```text
   shared operation definition
             │
             ▼
   register-bound stencil C
             │
             ▼
   Clang optimization and instruction selection
             │
             ▼
   extracted machine bytes + relocation descriptions
 ```

 At runtime compilation:

 ```text
   choose stencil
   copy bytes
   patch operands and destinations
   connect control flow
 ```

 That is where the speed comes from: the expensive backend work has already happened.

 We should not promise that every stencil is one machine instruction. Simple arithmetic frequently is; division, conversions, checks, calls and error paths may not be.

 Nor should we reserve a new scratch register merely because a generic parallel-copy algorithm uses one. The allocation and conformance mechanisms should continue to use the existing cache model.

 ────────────────────────────────────────────────────────────────────────────────

 7. Value capture is part of semantics

 This is the lesson from the bug we actually fixed.

 These are different:

 ```text
   "the value that was read from home H"

   "whatever is currently stored in home H"
 ```

 Consider:

 ```text
   C0 initially refers to mutable home H, containing 42

   CGET.A 0
   PUSH.B 99
   CSET0.B
 ```

 The required result is:

 ```text
   A0 = 42
   C0 = 99
 ```

 A symbolic implementation must not leave A0 as a deferred request to reread H after H has been reused.

 Correct projection:

 ```text
   Instruction       Symbolic action                 Native work

   CGET.A 0          capture H's current value        load H → r2
                     A0 names r2

   PUSH.B 99         B0 names constant 99             none yet

   CSET0.B           C0 names constant 99             store when required
                     A0 still names r2
 ```

 If C0 already names an immutable captured register value, CGET can simply add another name for it.

 So the rule is:

 │ Rename captured values. Capture mutable storage reads before their sources can be overwritten.

 The same applies to call arguments, tail-frame replacement and returned values.

 Liveness must also extend through the consuming operation. Popping an operand from the symbolic stack does not make its register disposable before the emitted comparison or arithmetic instruction has read it.

 This is why the correct architecture is not “all stack moves disappear.” It is:

 │ Stack transport disappears when semantic value preservation permits renaming; otherwise the existing cache emits the necessary capture or transport.

 ────────────────────────────────────────────────────────────────────────────────

 8. Residualization is direct, but control flow must converge

 An illustrative compiler driver is:

 ```c
   compile_region(owner, entry_contract, sink)
   {
       state = enter_symbolically(entry_contract);

       while (there_is_pending_control_flow()) {
           select_pending_entry(&state);

           execute_shared_semantics(
               &state,
               sink,
               /* fold known work;
                  update cache names;
                  emit residual operations directly */);
       }

       finalize_links_and_publish();
   }
 ```

 The pending entries describe control flow and symbolic cache states. They are not a second instruction representation waiting for a register-allocation pass.

 Branches

 For a known condition:

 ```text
   fold condition
   follow the selected successor
 ```

 For an unknown condition:

 ```text
   emit the comparison and branch
   derive the facts valid on each successor
   compile those successors
 ```

 At a join, only facts established on every incoming path survive without an additional check.

 Loops

 Suppose a loop initially arrives with:

 ```text
   value = 0
   steps = 0
   limit = 50
   increment = 7
 ```

 A backedge provides:

 ```text
   value = 7
   steps = 1
   limit = 50
   increment = 7
 ```

 The useful widening is:

 ```text
   value = unknown
   steps = unknown
   limit = 50
   increment = 7
 ```

 Not:

 ```text
   forget everything
 ```

 The physical values of value and steps still have to reach the loop header. Forgetting their constants does not discard those values.

 For internal cyclic control flow, provisional contracts may need weakening before publication. If that invalidates already emitted private draft code, the affected draft must be regenerated through the same emitter. Published assumptions are
 never silently weakened.

 This need not impose a separate analysis-and-allocation pipeline on ordinary straight-line regions. But its compile-time cost must be measured; “direct emission” is not permission to publish code before its entry assumptions are sound.

 ────────────────────────────────────────────────────────────────────────────────

 9. Calls are transport followed by control transfer

 Keep the semantic and physical descriptions separate.

### Proposed symmetric call contract

 ```text
   CALL.X f, n:
       consume n arguments from X in the declared vector convention
       establish the continuation, recording result destination X
       transport arguments into C and transfer to f

   RET.Y k, r:
       take the ordered r-result vector from the callee's Y
       remove the complete k-cell frame
       deliver results to the destination recorded by the continuation
       continue at its return point
 ```

 Here X and Y are independent selectors belonging to two different instructions; Y is not necessarily the opposite of X. The callee reads its arguments from C and may compute on either operand stack. There is no implicit A/B execution mode and no requirement to compile two mirrored bodies of each function.

 ```text
   .function twice 1 1
       CGET.B 0
       MULI.B 2
       RET.B 1 1

   PUSH.A 21; CALL.A twice 1    // receives 42 on A
   PUSH.B 21; CALL.B twice 1    // receives 42 on B
 ```

 | Caller | Callee return | Result transport |
 | --- | --- | --- |
 | CALL.A | RET.A | callee A → caller A |
 | CALL.A | RET.B | callee B → caller A |
 | CALL.B | RET.A | callee A → caller B |
 | CALL.B | RET.B | callee B → caller B |

 Argument order and C parameter depths remain the declared vector convention: repeated CPUSH.X transfers place the first argument at C0. At entry both private operand regions are empty. At RET.Y, Y contains exactly the declared local results, the other local operand region is empty, and the complete C frame is removed. The verifier checks result kinds/order against the function signature, independently of the selected source stack. Caller operand prefixes on both stacks remain protected.

 ```text
   TCALL.X f, k, n:
       take new arguments from X
       replace the current frame
       preserve the existing continuation and its result destination
       transfer to f

   CALLI.X:
       arguments, including the environment, on X
       target on the opposite stack
       results delivered to X

   TCALLI.X:
       the same argument/target orientation
       preserve the original continuation

   FCALL.X:
       consume arguments from X
       marshal through the declared foreign ABI
       deliver results to X
 ```

 Indirect target identity and full ABI validation remain mandatory. Foreign bridges consume the selected stack directly; B forms must not route through an A-only bytecode path. A host adapter may choose a fixed boundary convention without making that stack privileged inside the machine.

 This contract changes argument gathering and result-source semantics. It does not adopt a new physical return-slot layout or C-base restoration ABI. Such implementation decisions require a coordinated audit of all producers and consumers.

 Virtual call

 ```text
   caller symbolic state
           │
           ├── capture arguments from the selected source where necessary
           ├── rename them into callee-visible C frame positions
           ├── record a virtual continuation
           ▼
   callee symbolic execution
           │
           ├── capture results from the RET-selected source where necessary
           ├── preserve result order and route to the continuation's destination
           └── resume caller symbolic execution
 ```

 When all the transport is renaming, no call protocol remains in the native stream.

 But virtualization does not authorize:

 - moving addressed storage;
 - changing what escaped pointers identify;
 - forgetting live caller values;
 - weakening stack-capacity guarantees;
 - assuming every frame exists only as register names.

 Real call

 ```text
   preserve values live across the activation
   establish the explicit ABC continuation
   conform callee arguments
   transfer to the callee entry
 ```

 Return:

 ```text
   obtain the explicit continuation
   capture the RET-selected result vector
   deliver results under the continuation's A/B destination contract
   restore the caller's required coordinates
   continue at its native resume label
 ```

 These are operations in the ABC execution model. They do not become recursive calls to a C function that executes ABC.

 A resolver helper may:

 ```text
   validate a target
   find or prepare its entry
   return transport/linkage information
 ```

 It must not:

 ```text
   recursively execute the callee
   then return its ABC results through the host stack
 ```

 Recursion

 Recursive activations use the real continuation convention. Tail recursion preserves the existing continuation and becomes a backedge or tail transfer.

 ```text
   fib:
       compute first argument
       save continuation k1
       transfer to fib

   k1:
       preserve first result
       compute second argument
       save continuation k2
       transfer to fib

   k2:
       combine results
       continue through caller's continuation
 ```

 The exact C-base restoration convention remains a separate ABI decision. This redesign should not silently adopt the experimental return-layout proposal.

 Why region ownership helps here

 Budget selection happens at a region’s entry, before that realization executes.

 We no longer need to discover halfway through a known helper that “this callee has already been inlined seven times elsewhere” and suddenly reconstruct a real call.

 That removes an artificial reason for mid-inline materialization. It does not eliminate the genuine transport obligations of real calls inside an inlined region.

 ────────────────────────────────────────────────────────────────────────────────

 10. Shared observing sites are small, authoritative state

 For CALLI, I favor the proposed shared-table design over a registry of native patch points.

 ```text
   VM/module instance
       │
       └── observing sites indexed by original PC
               │
               ├── unseen
               ├── monomorphic(validated F)
               └── final generic
 ```

 All realizations refer to that state:

 ```text
   interpreter handler ─────┐
   native region version ───┼──► same original observing site
   inlined native copy ─────┤
   future bytecode version ┘
 ```

 The logical transition procedure is:

 ```c
   ValidatedTarget observe_call(Site *site, Target actual, ABI expected)
   {
       switch (site->state) {
       case UNSEEN:
           F = validate_exact_target(actual, expected);
           /* Failure leaves the site unseen. */
           site->state = MONOMORPHIC(F);
           return F;

       case MONOMORPHIC:
           if (actual == public_identity(site->target))
               return previously_validated_target(site);

           site->state = FINAL_GENERIC;
           /* Transition happens before validation, including failure. */
           return validate_exact_target(actual, expected);

       case FINAL_GENERIC:
           return validate_exact_target(actual, expected);
       }
   }
 ```

 That is semantic pseudocode, not a prescribed C representation. CALLI.X selects the actual target from the opposite operand stack; bank selection is immutable instruction information, not observing-site state.

 **Site observation does not require opcode rewriting.** The interpreter and native realizations consult VM-local site state while the public instruction retains its meaning and encoding. Deferring bytecode quickening does not defer target validation or erase the site's lifecycle. Native region linkage is also distinct from quickening a bytecode opcode.

 For callable sites, an encoded target plus reserved markers may fit in one word. We should not assume that every possible future observation kind has the same encoding.

 Specialization still needs a guard

 An observation-controlled native path for F must establish:

 ```text
   the site still permits its F-specific entrance
   AND
   this invocation's actual target is F
 ```

 Only then can the successor use F as a proven callee.

 If the site becomes final generic, old code can remain allocated, but its obsolete observing entrance cannot keep selecting the monomorphic path.

 An invocation already past its successful guard retains its proof.

 An independently program-proven direct target is different: it can bypass observing dispatch entirely, after the required ABI validation.

 No invented concurrency requirement

 The present API does not permit concurrent use of one VM. The design therefore does not require per-location compilation locks or lock-free patching protocols for simultaneous execution.

 Code publication still needs correct relocation, executable-memory and instruction-cache handling for the target platform. That is a different obligation.

 And the extra site-table load is a cost to measure—not something to declare negligible in the spec.

 ────────────────────────────────────────────────────────────────────────────────

 11. Eager and lazy differ in scheduling, not semantics

 The execution-policy table should be stated once.

 ┌──────────────────────────┬────────────────────────────────────────┬──────────────────────────────────┐
 │ Policy                   │ What executes                          │ When residual code is produced   │
 ├──────────────────────────┼────────────────────────────────────────┼──────────────────────────────────┤
 │ Interpreted              │ Ahead-of-time generated cache handlers │ No runtime residual code         │
 ├──────────────────────────┼────────────────────────────────────────┼──────────────────────────────────┤
 │ Eager native             │ Register-addressed stencil regions     │ Before execution                 │
 ├──────────────────────────┼────────────────────────────────────────┼──────────────────────────────────┤
 │ Lazy native              │ The same kind of stencil regions       │ On first required region arrival │
 ├──────────────────────────┼────────────────────────────────────────┼──────────────────────────────────┤
 │ Lazy bytecode — proposed │ VM-private residual ABC regions        │ On first required region arrival │
 └──────────────────────────┴────────────────────────────────────────┴──────────────────────────────────┘

 Build-time ABC optimization and portable-C generation are separate uses of the symbolic semantics, not additional automatic runtime tiers.

### Bytecode quickening is deferred, not moved into another engine

 The interpreter initially executes public instructions through the existing ahead-of-time cache-state-specialized handlers. Those handlers encode register-cache occupancy and placement; they are not observed-type versions or rewritten instruction sites. Preserve that fast core rather than replacing it with a synchronized generic interpreter.

 Counts and signatures remain immutable operands/metadata. Interpreter handlers execute their declared forms without internal quickened opcode variants; native residualization can use the same information to select transport and operation stencils directly. Shared observing-site records remain independent of either mechanism.

 Removing existing quickening paths is implementation work still to do. Measure interpreter dispatch, calls, handler text size and native emission against the isolated typed baseline. Do not claim postponement is performance-neutral before those measurements. Reconsider bytecode quickening only if evidence justifies it; it is not a prerequisite for the symmetric ISA or native JIT.

 Strict eager

 Before execution:

 ```text
   prepare bounded specialized regions that load-time facts justify
   prepare general coverage for unavailable facts
   prepare callable general entries for every valid runtime target
   publish complete executable code
 ```

 During execution:

 ```text
   execute
   validate targets
   update observing-site state
   select already prepared code
 ```

 No new block or region compilation.

 If a newly observed target has no prepared specialized path, eager mode uses its prepared general execution. It does not quietly call the compiler.

 Lazy

 On an unresolved region entry:

 ```text
   preserve the incoming machine state
   derive a valid entry contract
   select an existing compatible realization,
   or compile one if the budget permits,
   or select the reserved general realization
   publish and link
   enter it
 ```

 An initial sample is not enough to authorize an unchecked reusable specialization. Subsequent arrivals must establish its requirements.

 Ordinary established edges should transfer directly. They should not search the whole version table every time.

 Guard failure is not restart

 If effects have already occurred:

 ```text
   store something
   perform a check
   check fails
 ```

 the failure path cannot jump back to a general region entry that repeats the store.

 It must take a checked alternative at the current semantic point, or a successor entry whose contract represents that point.

 This is one reason general checked branches remain part of region code even when specialized paths exist.

 ────────────────────────────────────────────────────────────────────────────────

 12. Lazy bytecode is a proposed peer target—not a hidden second interpreter

 Lazy bytecode remains future design work. It is neither implemented by the current checkpoint nor required to compensate for deferred bytecode quickening. Residualizing a private bytecode region under checked facts is distinct from replacing an instruction opcode with an internal quickened variant.

 Its useful shape is:

 ```text
   original verified ABC
            │
   shared symbolic semantics
            │
   VM-private residual ABC
            │
   existing cache-state interpreter handlers
 ```

 No executable memory is required.

 But several contracts are essential:

 - Residual instructions retain their original source provenance.
 - Observing instructions still reference the original shared site.
 - Entry guards establish the facts used by the residual bytecode.
 - Branch offsets and continuation destinations refer to the correct private code.
 - Private generated code is validated under its declared entry contract.
 - The runtime does not start invoking the existing whole-module abc-opt pipeline.

 Specialized bytecode can contain typed operations after checks:

 ```text
   check operand representations and tags
       success:
           typed operations
       failure:
           checked general computation
 ```

 Whether checks need fused EXT forms is an encoding decision. It is not necessary to settle the architecture.

 The version-accounting rule should be shared across versioning sinks. That means one definition of ownership and limits—not one physical pool mixing a build-time C artifact with code in unrelated VM instances.

 The optimizer’s speculative analysis limit remains a different concept.

 ────────────────────────────────────────────────────────────────────────────────

 13. Dynamic reintegration plugs into this core

 The future dynamic layer should contribute semantic computations, not another execution engine.

 For a dynamic binary operation:

 ```text
   X0: left dynamic value, on the selected stack
   Y0: right dynamic value, on the opposite stack
                 │
                 ▼
   shared semantic computation
       classify representations
       establish type cases
       apply conversion/promotion rules
       perform typed computation
       handle errors
       choose result representation
       perform required allocation, if any
                 │
                 ▼
   result on selected stack X
 ```

 The opcode selects X; no dynamic scalar family hard-codes A as its left operand or gathers both operands on A. Unary, boxing, cast and test forms likewise operate on their selected stack under explicit layout contracts. Dynamic call argument/result transport must follow the symmetric call contract rather than reinstate the retired A-only convention.

 The same computation supplies:

 - concrete interpreter execution;
 - symbolic folding;
 - checked residual branches;
 - typed stencil emission;
 - future residual bytecode;
 - supported C emission.

 A schematic semantic definition might read:

 ```text
   dynamic_add(left, right):
       determine the applicable numeric or other defined case
       validate that case
       obtain its typed operands
       invoke the shared typed addition semantics
       construct the required semantic result
 ```

 The concrete binding performs the operations.

 The symbolic binding:

 - removes checks already proved;
 - follows known branches;
 - emits unknown checks and their successors;
 - emits the remaining typed work;
 - retains required effects.

 There must not be one interpreter algorithm and a separately handwritten native algorithm for promotion, overflow, error ordering or boxing.

 Tag, representation and normalization remain distinct

 ```text
   tag:
       what semantic type does this value have?

   representation:
       how are its bits currently carried?

   normalization:
       which bit-level properties are established?
 ```

 A u32 tag does not automatically prove that a register is raw and zero-extended.

 A boolean tag does not automatically prove arbitrary incoming bits are 0 or 1.

 Boxing must not silently normalize a payload that the language says to preserve.

 Keeping these distinctions in the core is what lets dynamic execution recover typed speed without inventing unsafe shortcuts.

 ────────────────────────────────────────────────────────────────────────────────

 14. Memory facts are proofs, not cached memory semantics

 The right distinction is:

 │ Every emitted load loads, and every emitted store stores. Residualization may omit an access only when a valid fact proves that omission correct.

 A useful fact has a shape like:

 ```text
   at location:
       base identity + byte offset + width

   the current contents equal:
       captured value V

   valid until:
       an effect that may change or invalidate that location
 ```

 Examples:

 ┌─────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────┐
 │ Memory category                                             │ Possible optimization                               │
 ├─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
 │ Immutable, non-relocated image bytes                        │ Fold a known load                                   │
 ├─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
 │ Storage proved unobservable except through tracked accesses │ Promote tracked contents                            │
 ├─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
 │ Writable image or escaped storage                           │ Forward only while alias/effect proofs remain valid │
 ├─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
 │ Unknown pointer memory                                      │ Emit the access unless a sufficient proof exists    │
 └─────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────┘

 A constant offset alone does not make a relocated address a portable constant.

 Calls and foreign effects invalidate facts according to justified footprints. Unknown effects require conservative invalidation.

 Allocation being nonmoving does not prove it preserves every memory fact: its slow path and associated runtime effects still matter.

 Also:

 ```text
   invalidate "memory H currently contains V"
 ```

 does not mean:

 ```text
   invalidate the previously captured value V
 ```

 The old loaded value can remain perfectly valid in a register after H changes.

 That is the same value-versus-storage distinction as the capture fix.

 ────────────────────────────────────────────────────────────────────────────────

 15. Allocation, GC and foreign effects stay explicit

 These boundaries must not be inferred merely from the word “dynamic.”

 For an operation that may collect:

 ```text
   complete required captures
   publish all live roots in the supported root representation
   perform the effect
   restore or continue with a valid cache state
 ```

 Roots may reside in A, B, C and the register bank. “Store everything to C” is not a complete root contract.

 A proven raw integer need not be boxed merely so that collection can occur. A managed address must remain visible as a root.

 The exact safepoint and pending-collection policy belongs in the GC contract. Reintegrating dynamic values must not silently add polling overhead to ordinary typed instructions.

 For foreign calls:

 ```text
   shared call semantics
       + declared foreign ABI
       + existing synchronization requirements
       → argument transport, host call, result transport
 ```

 A leaf-foreign optimization could be useful later, but needs a declared effect and re-entry contract. It should not appear in the spec as though that interface already exists.

 ────────────────────────────────────────────────────────────────────────────────

 16. What the resulting code can look like

 For a counter with known limit 50 and increment 7, the useful arithmetic kernel is:

 ```asm
   top:
       cmp  value, 50
       jae  done
       add  value, 7
       add  steps, 1
       jmp  top
   done:
 ```

 That is the shape we want to approach.

 But the specification should distinguish:

 ```text
   essential arithmetic/control work
 ```

 from:

 ```text
   capture, alias-preservation, transport and edge-placement work
 ```

 Knowing limit and increment does not itself prove that the old value and steps registers can be overwritten. That follows from actual liveness and alias obligations.

 A valid emitted stream might therefore contain:

 ```text
   copy an aliased operand
   perform the arithmetic
   rename the updated binding
   restore the next entry's placement
 ```

 Those extra moves are not automatically evidence of a bad architecture. The important questions are:

 - Are they required by the current contract?
 - Can the shared cache avoid them without violating value preservation?
 - Do they affect measured throughput or latency?
 - Would eliminating them require a disproportionate new subsystem?

 The existing experiments already show why this distinction matters: a mechanically allocated stencil loop can perform very well without matching a hand-written register schedule instruction for instruction.

 ────────────────────────────────────────────────────────────────────────────────

 17. What must be tested and measured

 Architectural correctness

 Not just final answers:

 - Selected-stack-first operand order: OP.A computes A0 op B0; OP.B computes B0 op A0.
 - Both selected stacks, including noncommutative integer/float operations and the correct divisor, shift count and exponent.
 - Whole-machine A/B exchange tests over mirrored programs, operand states and continuation selectors, with corresponding effects, results and failures.
 - C reads to both destinations and C writes from both sources; C retains its structured-state role.
 - Selected-stack conversions, checks, branches, memory operations and host-entry results.
 - All four CALL.X/RET.Y source/destination combinations; indirect targets on the opposite stack and tail calls preserving the original destination.
 - Foreign argument/result transport on either stack, without an A-only staging path.
 - Destination-parametric expression lowering preserves pre-existing live values on both stacks, including nested noncommutative expressions.
 - Greater-than/greater-or-equal use reversed comparisons without changing source evaluation order; test effects, traps and floating-point NaNs.
 - Mirrored handler bindings exchange (a, b) and h[i]/h[3-i] while retaining C's role, across full-bank and spill transitions.
 - Operand orientation introduces no repair MOVE; distinguish this from legitimate capture, alias and conformance transport.
 - Pressure-driven reordering occurs only when permitted by effect, trap and resource-failure semantics.
 - Untouched live values on the other stack.
 - HOME capture before replacement.
 - Consumed operands remaining live until their operation finishes.
 - Ordered multi-result returns.
 - Escaped addresses surviving calls and conformance.
 - Guard failures not replaying effects.
 - Original trap provenance.
 - Stack-capacity behavior under the agreed policy.

 Region accounting

 ```text
   one helper called from many unrelated callers
       → no shared helper-budget cliff

   many helpers inside one caller realization
       → one slot

   many distinct caller entry contracts
       → at most seven specialized realizations

   internal loops and joins
       → converge, not free hidden version families
 ```

 Site behavior

 - Shared history across interpreted, native and inlined realizations.
 - Invalid first target leaves the site unseen.
 - Mismatch transitions before validation.
 - Final generic never restarts.
 - Later realizations see the current state.
 - VM instances remain isolated.
 - Observing-state transitions remain correct without rewriting public instruction opcodes.

 Encoding and migration

 - Enumerate the complete one-byte opcode allocation, including EXT, without reserving internal quickening variants.
 - Keep mirrored forms structurally consistent and verify their operand layouts independently of native register placement.
 - A new ISA/module revision prevents old SUB.B/CALL.B semantics from being silently reinterpreted.
 - Regenerated frontend, assembler, optimizer and C-sink output agrees with the authoritative selected-stack contracts.
 - Independent expected-value tests accompany metamorphic symmetry tests; updating a shared generator alone is not sufficient evidence.

 Compilation policy

 - Eager execution performs zero region compilation.
 - Lazy first arrival compiles only through the declared compiler path.
 - Repeated arrivals reuse published code.
 - Failed publication leaves no callable partial code.

 Performance

 Keep separate measurements for:

 ```text
   load/preparation time
   first-arrival latency
   steady-state execution
   generated code bytes
   metadata bytes
 ```

 Use the isolated typed core as the baseline. Measure source-definition reduction separately from emitted handler/stencil bytes. For parametric lowering and pressure-driven scheduling, compare bytecode size, dispatch count, spills, captures and transport as well as execution time; symmetry alone does not prove a performance improvement.

 Measure tiny helpers, recursive calls, branchy code, throughput-heavy arithmetic and memory—not only a latency-bound loop. Later, compare dynamic code with equivalent typed computations, separating proven, checked and allocating paths.

 ────────────────────────────────────────────────────────────────────────────────

 The final picture

 ```text
                          ONE ABC MACHINE
                     A/B operands, explicit C state
                                 │
                          ONE SEMANTIC CORE
                                 │
                    proven facts + symbolic cache
                                 │
                 ┌───────────────┼────────────────┐
                 ▼               ▼                ▼
            residual ABC    copied stencils    portable C
                                 │
                       caller-owned regions
                       bounded realizations
                                 │
                   explicit guards and continuations

   Operand roles:
       selected stack first; the other stack is its symmetric partner
       C reads select a destination; C writes select a source

   Call transport:
       CALL.X selects arguments and caller results
       RET.Y selects the callee's result source
       the explicit continuation connects them

   Observing-site state:
       shared by original instruction identity, without opcode rewriting

   Bytecode quickening:
       deferred; no internal opcode budget reserved

   Placement:
       owned by the existing symbolic cache

   Dynamic behavior:
       shared checked computations and explicit effects

   Execution policy:
       decides when compilation occurs, not what ABC means
 ```

 The redesign is not about making the compiler more general by adding machinery. It is about making ownership, proofs and effects precise enough that the fast existing machinery can do more work directly.

 That is the base on which dynamic operations should return.

## Explicit Rc replaces implicit reference ownership

The user stopped the implicit lifetime cutover and chose explicit `Rc(T)` with
**copy retains**. The stated goal is developer-visible, typechecked ownership and
an efficient, simple compiler. `Ref(T)` remains borrowed; invalid escape or loss of
protection rejects instead of causing promotion or hidden acquisitions. Rc copies
share the target allocation, and drops release their actual holdings. Proven moves
may eliminate redundant count operations without changing source semantics.

This retires the organizing responsibilities of counted-root inference, owner-
capability propagation, inferred snapshot preservation/reuse promotion and hidden
reference-result resource contracts. Necessary borrow/effect/callable facts and
actual strong-edge cycle checking remain. The C core, six lifecycle bindings,
concrete drops, packed-tag machinery and shared ABC allocator/continuations survive.
The existing callable `Ty.Owned` is not the new Rc type.

The interrupted implementation is preserved at `4a9da5db`, separately from this
specification revision. It includes an incomplete rooted materializer and a narrow
private pointer-free-root probe, not a completed source-lifetime implementation.
The replacement contract is `docs/source-lifetime-lowering.md`; source semantics,
syntax, runtime-interface references and the implementation map now point to the
explicit design. WORKLIST O01–O08/E01/E02 retains all delivery status and open gates.

Construction/borrow syntax, borrowed payload admission, failure-safe private Rc
transport and explicitly owning environment/snapshot APIs must be bound before
implementation. No public ABI, new encoding or implicit compatibility path is
approved by the type decision. This documentation change does not implement Rc or
claim speedups. Compiler time/memory, count traffic, emitted code and retained-memory
measurements belong to integrated qualification; immutable historical logs remain
unchanged.

## Explicit-Rc implementation: remove the analysis engine, not just its solver

The first migration removed promotion/capability decisions but retained whole-caller-
state query identities and their snapshot/version machinery. That was an incorrect
architectural cut, not merely a cache-performance problem.

The replacement operates on original typed-IR CFG nodes. It retains only borrow
protection, permissions, active alternatives, invocation-environment contents and
actual strong edges. Call-site bindings join relevant inputs; caller frame state is
not an identity. Scalar contents are not proof facts. Private effects, including
callee effects on borrowed locals, do not leak into an external contract. A scalar-
only boundary without named globals checks its own local allocations once, rather
than multiplying unrelated activation contexts. A recursive-child regression guards
against confusing a source-site family with shared runtime storage.

Rc placement is independent of these facts: declared types select holdings,
semantic copies retain, and typed private slots protect call/result failure paths.
Actual-field/active-tag drops and the six C bindings remain. Nonowning transport no
longer acquires synthetic cleanup captures; physical source maps retain original
trap nodes. Recursive ABI gates use the checked program's named definitions rather
than treating every named pointee as owning.

The optimizer's pre-existing frame restriction now also applies while inlining.
Already-unsupported multi-path non-call effects decline before enumeration, rather
than after producing an enormous ordered DAG. Generic non-Rc tests exercise both
boundaries; this is not a second Rc optimizer mode.

The initial slice passes frontend, source/native ownership, optimizer-ISA and core/
C-entry qualification. Focused sanitizer compilation is blocked by the installed
compiler's missing `preserve_none` ABI support; it was not bypassed. Exact outcomes,
remaining gates, measurements and status live in WORKLIST and
`research/experiments/runtime-owners/explicit-rc-cutover/README.md`. No broad O/E
completion or optimal count/storage claim follows from this checkpoint.
