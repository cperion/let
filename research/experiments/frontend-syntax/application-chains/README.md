# Pending application chains

Implemented scope: consecutive ordered Apply nodes share pending requirements until
saturation. Each suffix retains its own result adjustment. Grouping, argument/binding/
return contexts, member/index selection and keyed supplies close the ordered chain.
No runtime partial object is created by an intermediate suffix.

`Function:call` collects the chain; `callSuffix` owns the existing resolution,
argument checking and invocation path. Argument computations are snapped in source
order before later arguments/suffixes. Nontrivial schema receiver addresses are
established when the method is bound, rather than after argument effects or defer.
At chain exit the existing static-partial/retention restrictions apply. Earlier
saturated prefixes of a deferred chain execute during preparation; only its final
saturated invocation is deferred.

## Validation

`frontend/tests/application_chains.lua`: **122 checks, 112 VM executions**, covering
optimized/unoptimized execution in interpreted, threaded, eager and lazy modes:

- runtime arguments, computed arguments and repeated empty suffixes;
- typed runtime callees, with one indirect call and no partial adapter in the caller;
- capture-free curried results and ordinary static partials leaving a chain;
- per-suffix multi-result expansion before a following callback;
- callee/argument evaluation order, field snapshots and receiver retargeting;
- defer, grouping boundaries, escaping runtime partial rejection and over-application;
- an earlier division trap winning over a later explicit checked-IR trap.

`validation.log` records successful integrated `validate-slet`, including the new
suite, syntax 127/68 executions, word bindings 105/84, parser 232, compiler 280,
lambdas 269/80, lowering 100, optimizer 118, staging 27, source demands 52,
sessions 280, symmetric 43, lifetime 48, production frontend 112 executions plus
2 static-demand diagnostics, and portable C 12 cases.

Command:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-slet
```

The integrated run reused the current build and includes the in-progress packed-tagged
lowering edits. Separately, `isolation.log` records the chain, syntax and word-binding
suites run against a copy of the frontend with abc.lua restored from fe042d9f. All
three pass without the packed-value changes. Neither run establishes a completed
packed-value migration, clean build, sanitizer run or performance qualification.

## Unresolved optimizer failure, not hidden by the suite

The initial trap-order test used a callee with an array frame and a bounds failure.
The optimizer failed before execution with `abc-opt-invalid: frame access outside
a live byte block`. A flat-call repro also fails on the earlier 2e82c27f frontend,
using the same current runtime/optimizer build:

- Current, unoptimized: earlier division-zero wins.
- Baseline, unoptimized: later argument's index-range wins (old ordering bug).
- Both optimized: invalid frame-access output is rejected.

Repro and results are in `../word-bindings/chain-memory-probe.lua` and `.log`.
The focused chain suite uses an explicit IR trap to isolate ordering without that
optimizer failure. This does not resolve or waive the memory-backed failure;
optimizer call virtualization with frame-allocating callees needs separate review.
No runtime or optimizer changes were made for application chains.

## Remaining work

Escaping/runtime closure ownership, general source-demand acceptance, lexical
receiver fallback and its proposed discarded-receiver-write diagnostic are not
implemented by this change. The targeted returned-word/named-body diagnostic also
remains separate. Packed-tagged lowering still needs its dedicated exact-bit,
nested-layout, padding, resource and performance qualification.
