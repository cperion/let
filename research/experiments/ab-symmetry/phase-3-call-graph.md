# Phase 3 — revision-6 instruction walkers

Status: residual call-graph component migrated and checked; whole symbolic/native/tooling integration remains incomplete.

## Changes

- `src/residual_analysis.c`: direct-call discovery and recursive-component classification now read authoritative decoded instruction metadata instead of the removed `op_kind` table. Existing graph algorithms and tail-only component eligibility are unchanged.
- `src/optimize.c`: migrated its direct-call and intra-component call-kind lookups. Its existing singleton-only nested eligibility policy is unchanged; this chunk does not merge the optimizer and residual-builder policies.
- `src/symbolic.c`: migrated the recursive reachability/unknown-call walkers to the same metadata contract.
- `src/residualize.c` and `src/residual_builder.c`: block/leader discovery now uses complete decoded lengths and operand views. EXT immediate-branch operands start after the selector; SWITCH offsets remain relative to the complete table. Unconditional jumps are identified by semantic operation identity. Existing block/loop policies are preserved.

No bytecode aliases, compatibility decoder, new control-flow representation or region-budget policy was added.

## Checks actually run

- Compiled the entire current `src/residual_analysis.c` with Clang 20, strict warnings and the revision-6 generated header.
- Assembled and verified `tools/validate_call_graph.abcasm` and an A/B-mirrored copy using the new assembler and loaders.
- Ran `tools/validate_call_graph.c` against both modules. Each contains nine functions: direct calls, mutually tail-recursive functions, non-tail self-recursion, mixed tail/non-tail recursion, a leaf with SWITCH, and compact indirect call/tail forms. An EXT branch precedes a direct call; a 64-bit literal contains opcode-looking bytes; a direct call follows a two-byte CALLI.
- Independent expectations check all seven edges, seven components, recursion flags, nested eligibility and actual instruction boundaries. Both modules pass; output is in `phase-3-call-graph.log`.
- Registered the original fixture/validator in the full Makefile validation target.
- `git diff --check` passed on changed implementation/test files.

The isolated validator links newly compiled analysis/loader/verifier objects before the preserved library to provide remaining dependencies. No old native or optimizer execution is used as evidence.

## Validation limits

The full optimizer, symbolic and native components still cannot be built. A syntax-only diagnostic of `src/symbolic.c` confirms outstanding old scalar/EXT opcode names and memory metadata interfaces; its log is `/tmp/abc-symmetric-isa-check/symbolic-migration-errors.log`. These must be replaced, not aliased.

Consequently the changed symbolic walkers, optimizer graph walk and native/residual block-discovery functions are **not yet validated through their containing components**. The passing call-graph tests do not establish complete native leader discovery, symbolic execution, capture conformance or whole-program compilation.

## Reproduction boundary

Artifacts are in `/tmp/abc-symmetric-isa-check`. Generate the original and mirrored modules by applying this lexical mirror to the fixture before `assembler.assemble`:

```lua
source:gsub('%.([AB])', function(bank) return bank=='A' and '.B' or '.A' end)
```

Compile `src/residual_analysis.c` and `tools/validate_call_graph.c` with:

```sh
-O1 -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
-I/tmp/abc-symmetric-isa-check -Iinclude -Isrc
```

Link the validator with the new `residual_analysis.o`, `module.o`, `memory_module.o`, `verify.o`, then the preserved `build/libabc.a -lm -lpthread`. Run:

```sh
/tmp/abc-symmetric-isa-check/validate-call-graph \
  /tmp/abc-symmetric-isa-check/call-graph-0.abc \
  /tmp/abc-symmetric-isa-check/call-graph-1.abc
```

No performance comparison or full suite was run. Phase 3 remains open.
