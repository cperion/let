# Phase 2 concrete execution checkpoint

Status: concrete instruction execution, module loading/verification and assembly/disassembly have been migrated. Symbolic/native/tooling/frontend integration is still incomplete. This is not a working full-build checkpoint or an end-to-end completion claim.

## Replaced responsibilities

- `gen/semantics.lua`: one bank-independent transfer definition per semantic family; x is selected and y is opposite. Scalar expressions remain shared.
- `gen/banked.lua`: complete selected-stack handler generation, including concrete typed EXT dispatch, memory, foreign, direct/indirect/tail calls and independent return-result sources. Dynamic argument/context counts use transitions generated from the existing cache, without opcode quickening or a second allocator. Ordinary calls retain cached operands/context rather than universally flushing them.
- Deleted `gen/banked_manifest.lua`: no second handwritten opcode catalogue.
- `gen/cold.lua`: exact target validation and observation-word transitions, with no opcode writes; selected-stack foreign argument/result marshalling.
- `src/vm.c` / `src/vm_internal.h`: removed mutable code-copy ownership, moved direct target binding to load, introduced VM-local observation words, made code-address relocations mode-independent and separated host-vector entry from bytecode argument gathering.
- `src/verify.c`: the existing persistent kind/block-shape model now verifies every typed profile through decoded operation/selected-bank metadata. Both old verifier implementations were removed rather than retained beneath a dispatcher.
- `src/module.c` / `src/memory_module.c`: revision 6 and independent capability profiles 1–4; profile-specific payload parsing retained. Indirect cache words and their old serialization checks are gone.
- `tools/assembler.lua`: manifest-driven encoding, explicit selectors, typed EXT layouts, compact indirect calls and regenerated branch/call offsets. No runtime JSON metadata subprocess, old-bank defaults or historical dynamic selector implementation remains in this producer.
- `src/cli.c`: decoded metadata drives disassembly and opcode listings; indirect listings no longer display serialized caches.

The new generated metadata also carries the semantic transfer class from `gen/semantics.lua`, so verification does not infer operation classes from old byte ranges.

## Checks run

See `phase-2-checks.log`:

- Revision-6 metadata validator: exact encodings, mirror contracts and bounded decode layouts.
- Concrete/verifier C validator: 16 contracts covering arithmetic, C ranges, typed EXT, all four CALL/RET combinations with one/two ordered results and live caller prefixes, selected-bank foreign transport, and indirect observation history with failed targets and unchanged code bytes. Repeated execution is exercised where applicable.
- Existing cache validator adapted to revision 6: 2,400 exact-state handler cases with poisoned dead ABI arguments, now including noncommutative B operations.
- Assembly → module loader/verifier → interpreter: 14 original/mirrored cases covering integer, memory, float conversion, direct/indirect/tail transport and extended immediate branch offsets.
- All eight generated handler partitions and the VM, module loaders, verifier and CLI compile with Clang 20 and strict warnings in the isolated check directory.
- No full-suite or performance rerun; the full build still has unmigrated consumers.

## Isolated build boundary

Checks were built in `/tmp/abc-symmetric-isa-check` using the newly generated opcode header, banked handlers and cold boundary. New `vm.o`, `module.o`, `memory_module.o` and `verify.o` were linked before the preserved `build/libabc.a` to supply remaining, unchanged or unexercised dependencies while the whole-tree migration is incomplete. **The inherited native backend was not executed.** This temporary link is test scaffolding, not a production compatibility path or evidence of native conformance. Do not run its `--compiled` or `--lazy` modes.

Representative commands from the repository root:

```sh
check=/tmp/abc-symmetric-isa-check
luajit tools/gen_opcodes.lua "$check/opcodes.h"
luajit gen/banked.lua "$check/generated"
luajit gen/cold.lua "$check/generated/cold.inc"

# Compile generated/banked_0.c through banked_7.c and src/{vm,module,memory_module,verify}.c
# into $check using:
# /tmp/clang20 -O1 -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof \
#   -I"$check" -Iinclude -Isrc -c SOURCE -o OBJECT

# Link each of tools/validate_banked_isa.c, tools/validate_cache.c and src/cli.c
# with the new objects and then build/libabc.a -lm -lpthread.
"$check/validate_isa"
"$check/validate_banked_isa"
"$check/validate_cache"
luajit tools/validate_symmetric_interpreter.lua "$check/abc-runtime"
```

The new validators are registered in the full Makefile for the eventual integrated build. Existing build artifacts in `build/` still belong to the old typed baseline and must not be mistaken for current-source binaries.

## Remaining work

- Migrate `gen/symbolic.lua`, `src/symbolic.{c,h}` and every symbolic sink to operation identities, selected-first inputs and explicit call/return source roles.
- Replace native reverse-operation/old call orchestration and bind native indirect execution to the new site owner. Native phase patch registries and its old permissive identities still exist and are not hidden by the concrete work.
- Migrate persistent residual IR/ABC output, optimizer/C sinks and frontend lowering; regenerate their fixtures.
- Run integrated capture/continuation/resource-limit/API checks and the full active suite after those consumers are coherent.
- Measure the completed implementation against the preserved baseline. No speed or code-size improvement is claimed from these focused functional checks.
