# Validation contract

## Checks that run now

```
timeout --kill-after=2s 30s luajit tests/run.lua
```

The runner verifies ASDL interning/type checks, non-interned occurrences, actual copied-method
behavior, corrected List equality selectors, and concrete U32 arithmetic against edge cases and an
independent bit-serial multiplication reference. It copies this project's declared files to a
temporary path containing spaces and a quote, then builds there from another working directory.
It compares repeated bundle bytes and loads the bundle with Lua search paths cleared. Fixture modules
exercise real require-mode embedding, optional CLI dispatch, private package.loaded compatibility,
failed-load retry, cycles, unlisted dependencies, missing/syntactically invalid source and write errors.
The runner cleans its temporary directory and reports failures with nonzero exit status.

These are bootstrap tests, not Wordlet compiler tests. No parser/evaluator/C correctness claim follows
from a passing bundle or ASDL constructor check. Tests need POSIX tools; they are not a sandbox for
untrusted module source or manifest code.

## Source fixtures (not executable yet)

- examples/arithmetic.let: transform(4)=19; divmod(17,5)=(3,2); consume(17,5)=17. Unknown zero
  divisor aborts; statically evaluating a zero divisor rejects.
- examples/receivers.let: observe(7,false)=(7,7); observe(7,true)=(7,8). The first result must
  remain a snapshot despite the method call. At U32 maximum, increment wraps to zero.
- examples/captures.let: run(5,7)=12. An exported make_adder result must remain callable after
  its creator returns and copy its captured value by value.

## Implementation gates for the owned-syntax compiler

Each gate needs executable positive and negative cases. No gate means “keep an old suite green.”

Gates 1–5 and 8–10 have their first executable form in `tests/parse.lua`, `tests/eval.lua` and
`tests/c.lua`; gates 6 and 7 are partial (no records, closures or loop rewrite yet).

1. **Concrete schemas:** `ast.asdl`/`ir.asdl` parse and construct (tests/schemas.lua); stable source
   spans; every semantic visitor covers every AST/IR variant; immutable canonical lists; no effect
   occurrence interning; builder-level per-function expression interning.
2. **Grammar:** free-form equivalence, comments/tokens, operator precedence, `:` results versus `->` lambda bodies, parenthesized signature inputs,
   named/shared parameters, per-binding annotations, schemas/initializers/configuration, separators.
3. **Interpreter:** U32 rules, Bool-only short circuit, exact application adjustment, static partial
   supply, Type-dependent requirements, lexical scope and lazy top-level dependencies.
4. **Storage:** immutable bindings versus mutable fields, immediate reads, record value copies,
   compound-target evaluation once, receiver effects through calls and actual nested owner routes.
5. **Structured branches:** each arm elaborated once, correct early-return completion, result-vector
   joins, initialization on every continuing arm, no arm-local definitions leaked outside scope.
6. **Instances:** canonical known argument/code/capture bindings, shared helper bodies, no caller path
   multiplication, bounded changing-specialization recursion and complete annotated residual cycles.
7. **Callables:** owned environments survive creator return (make_adder/run/compose/snap); a captured
   field is a snapshot while a captured receiver is a live borrow; distinct lambdas are distinct code
   identities; escaping a borrowed closure is rejected; an opaque callable uses a signature-specific
   invocation pointer, and a callable with no known code and no view is rejected rather than
   mis-compiled.
8. **IR/checking:** storage/value distinction, scope and definite assignment, target signature checks,
   module storage seeded outside every function,
   dynamic failure guards, transitive borrow provenance, finite layouts, no metadata runtime slots.
9. **C:** strict C11 compile/run, arithmetic boundary values, side-effect order, safe tail permutations,
   constant-stack self-tails (5,000,000 iterations),
   no dangling environment, separate header/source consumer, stable names and Unit erasure.
10. **Distribution:** replace wordletkit with the REAL facade/CLI in the manifest; bundle parity with the
    checkout implementation; clean relocated builds and runtime execution without source search paths.

Use concrete interpreter behavior and generated C on the same programs, comparing returned vectors
AND ordered state changes. Retain IR structure tests for invariants, not arbitrary temporary spelling.
Use bounded compiler/execution subprocesses and report wall-clock time. A static interpreter work
budget counts work even when no residual instruction is emitted.

## Initial resource settings to implement

These are explicit starting configuration defaults, not measured limits or language type rules:
source size 16 MiB per file; lexical tokens 1,000,000 per file; static depth 64; static evaluator
steps 1,000,000 per root demand; source/AST nesting 256; residual
statements 100,000 per instance; residual body keys 1,024 per program; aggregate depth 64 and expanded
components 1,000,000 per value. Keep counters cumulative across dependent work in the corresponding
root scope; retries must not reset the counter that is supposed to bound them. Limit exhaustion is a
resource diagnostic naming the scope. There is no exponential replay-path counter.

Diagnostic status convention for the new CLI: reject=1, bug=2, todo=3, resource=4, internal=2.
Compiler bugs and unexpected implementation exceptions are not mislabeled as user type failures.
Every source diagnostic carries a span; source-independent loader/I/O failures identify their path.

## Standalone audit

All active documentation links and source require paths must resolve inside this directory, except
explicit host tools/external modules. Historical origins in THIRD_PARTY.md are informational only.
Do not import the old evaluator, borrow checker, schemas or tests by relative parent path. Preserve
the verified MIT notices in LICENSE and vendor/LICENSE. Tests check that the default bundle embeds
both, so attribution survives standalone distribution.
