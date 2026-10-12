# Phase 3 — native indirect resolution and explicit transfer

Status: native indirect binding replaced and focused checks passed. Whole-phase/tooling/frontend integration and full regression/performance validation remain unfinished.

## Responsibility replaced

`src/residualize.c` now calls the existing `vm_resolve_indirect()` through one generated resolution stencil. Resolution validates the public bytecode-entry identity and full site signature and updates the authoritative VM/module observation word. Only then does the native binding check the actual target's A/B/C requirements. The helper returns a private entry address and status; it never executes ABC.

The native sink publishes consumed arguments and target, preserves surviving values through the existing cache machinery, resolves, transports arguments to C, and performs an explicit native transfer. CALLI installs a real resume label in the existing continuation cell. Its resume uses the selected result destination, the uniform r0 singleton convention, and r2 for multi-result source selection. TCALLI retains the existing continuation cell and uses the approved C-coordinate normalization to support changed argument counts.

The symbolic unresolved-tail path now terminates after its sink transfer instead of emitting unreachable capture/CPUSH work after that transfer. There is no symbolic successor in that activation. Proven-direct paths retain the shared direct-call/tail handling.

## Deleted, not wrapped

- private native `abc_ic_state`, observation phases, patch lists and lifecycle/statistics;
- permissive function-index, byte-offset and native-pointer public target identities;
- phase-specific call/tail helpers and their host-recursive ABC execution;
- separate raw-call resolver and raw CALLI/TCALLI stencil families;
- synthetic host-return-sentinel stencil for ordinary indirect calls;
- maximum-over-all-signature-compatible-targets capacity checking;
- obsolete native entry-count field and function-pointer typedef.

Ordinary copy-and-patch linkage and lazy entry compilation remain. No public bytecode quickening, second allocator, permanent scratch register, extra continuation cell or new public execution-policy API was added.

## Validation actually run

Strict Clang 20 compilation of changed native/VM/symbolic components and isolated executable links, using new component objects ahead of the preserved library for unchanged dependencies. No old native residualizer was linked into these checks.

- **120 interpreter/eager/lazy return-transport checks**: existing direct-return regressions plus all four indirect CALL/RET combinations; zero results; changed-arity indirect tails with both argument banks, both return banks, singleton/multi-result delivery and live A/B/C prefixes; 2,000-level indirect recursion; a 2,000-step changed-arity indirect-tail cycle at four cells (and rejection at three); actual-target capacity selection with an oversized unselected compatible callee; selected oversized-target rejection.
- **36 banked/call C cases**: mirrored indirect histories in every mode, invalid first targets, repeated monomorphic targets, mismatch-before-failure finalization, persistent final-generic state, same-count/wrong-kind ABI rejection, null/index/offset/interior/out-of-module/native-entry/HALT target rejection, original error PC, unchanged failure outputs, VM isolation, immutable module code and immutable eager native code. Existing mirrored zero/one-result foreign checks remain included.
- The C validator also prepares both existing execution bindings on one image for an internal ownership probe: interpreter establishes monomorphic state, native finalizes it, and interpreter observes final state. This is test-only setup, not a public policy-switching feature.
- **28 symbolic selected-bank contracts**, plus existing narrow-fold/control/context/fusion regressions.
- Dead-path search finds no old IC state/helpers, raw indirect families, native observation-statistics owner or return-sentinel stencil in active `src/`, `gen/`, `tools/`.
- `git diff --check` passed on implementation/test changes.

Output: `phase-3-native-indirect.log`. Reproduction uses the isolated build commands from `phase-3-native-returns.md`, regenerating stencils and recompiling `src/vm.c` as well as `src/residualize.c` after the private native-image structure changes.

Generated artifacts: **3,770 stencils, 77,472 extracted code bytes, 3,090 tail jumps removed**. The preceding artifact had 3,802 stencils and 82,332 bytes. This is an intermediate stencil-artifact comparison, not a native-program throughput or final migration performance result.

## Failures found during development

The first ordered-argument test exposed that ordinary `flush_context()` intentionally retains symbolic constants. Transport was reading an unpublished constant argument as zero. The binding now explicitly publishes all consumed arguments and the target before resolution; it does not force unrelated constants into stack homes.

An initial mixed-engine test switched a native-only VM image to interpreter execution without preparing interpreter call tables and crashed. The test now prepares the interpreter image through its normal loader, then attaches the existing native binding for the internal shared-owner probe. Runtime allocation/policy behavior was not changed to accommodate the test.

## Remaining work

Optimizer/residual-builder/ABC/C consumers, frontend lowering and fixtures, full capture/escaped-address/continuation/resource suites, whole-tree clean validation, fixed workload performance comparison and final documentation/dead-path audit. Native inlining eligibility and broader JIT ownership/version-budget policies were not redesigned.
