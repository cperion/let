# Native byte-emitter extraction and allocator parameterization

This is another partial integration checkpoint, not an executable threaded mode.

## Implemented

- `src/native_emit.c/.h` owns stencil copying, native relocation encoding, local
  reference binding, memory-copy/foreign/guard/indirect operand binding and lazy
  stub emission/activation. Production `src/residualize.c` no longer includes
  generated stencil bytes or interprets relocation kinds/holes.
- Reference tokens are opaque to the residualizer. Mapping allocation/protection,
  cursors and version addresses still reside in residualization; these must move
  behind the final emission interface before threaded integration is complete.
- Removed unused `LazyFn`, saved lazy relocation fields and dead `GuardFix`
  machinery. Inspection showed no deferred guard caller; guard semantics and
  placement remain unchanged.
- One allocator's available-register count now governs free/spill selection,
  recursive argument transport and entry descriptors. Production native uses 8.
  Isolated validation sets that count to 7 while retaining the native execution
  ABI; it does not claim to test threaded handlers.
- Added nine-argument recursive return tests for A/B calls, with an independent
  expected sum of 36, crossing both register-count boundaries.

## Validation

`native-emitter-final-validation.log`: final `make all validate` passes, including
113 oracle cases / 678 mirrored three-mode executions, 495 continuation
executions and 126 return-transport checks.

`tools/validate_native_emit.c` independently applies relocations byte-by-byte from
stencil metadata. All 3,770 forms with four payload patterns, all specialized
binding families, copied reference tokens, surrounding canaries and invalid-input
checks pass (4,230,894 assertions). It checks emitted bytes, not their execution;
the existing runtime suites supply execution validation.

`seven-register-allocation.log` and `eight-register-allocation.log`: 126 checks
pass with either register count. The initial new fixture mistakenly reversed the
argument vector and returned 31 in the interpreter. Its construction was corrected
to the declared first-argument-first convention; the independent expected result
remained 36. No runtime change was made to accommodate that fixture error.

The seven-register experiment is reproduced by applying `seven-register-test.patch`
to a separate copy of `src/residualize.c`, compiling that object with the usual
runtime flags, and linking it before `build/libabc.a` with `src/cli.c`. Then run:

```
/tmp/lua-compat tools/validate_native_returns.lua PATH-TO-ISOLATED-RUNTIME
```

Working binary: `/tmp/abc-native-emitter-before/seven-register-runtime`. Source and
binary hashes are in `native-emitter-sources.sha256`.

## Native controls

At the byte-emitter extraction checkpoint (before the subsequent register-count
parameterization), both old/new libraries returned the independent expected
results for loop, branch, Fibonacci and memory. Body sizes were unchanged:

| Workload | Eager bytes, both | Lazy bytes, both |
| --- | ---: | ---: |
| loop | 581 | 404 |
| branch | 2779 | 1321 |
| Fibonacci | 1024 | 789 |
| memory | 309 | 246 |

Raw output: `native-emitter-controls.jsonl`. These short runs are correctness/body
checks, not a timing study. Extracting host preparation functions can change
preparation costs; those costs have not been meaningfully measured. No full
residualizer-object identity or performance-equivalence claim is made here.
The earlier catalog checkpoint's byte identity remains historical evidence.

Pre-extraction source/library/stencils are frozen in
`research/archive/threaded-residual/native-emitter-before.tar.gz`.

## Still outstanding

Binding-independent control labels and typed operand emission, native mapping and
publication ownership, threaded handlers and tape emission, execution-image
lifecycle/API/CLI/staging wiring, and four-mode correctness/performance evidence.
No new VM mode, fallback, scalar engine or allocator has been introduced.
