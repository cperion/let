# Phase-5 contract/documentation audit — partial closure

Documentation-only production changes. The hybrid C-cache experiment is parked.
The runtime is unchanged; a native version-budget deviation is now reproduced,
not repaired or excused by changing the target.

## Responsibilities checked and replaced

Read the prior specification/architecture/profile pages completely and traced:

- `tools/opcodes.lua`: selected roles, instruction layouts, capability profiles;
- `gen/semantics.lua`, `gen/banked.lua`, `gen/cache.lua`: selected computations,
  scalar/memory/call transport, actual C occupancy and synchronization;
- module-format reference plus `src/verify.c`: kinds, memory widths/blocks,
  instruction/layout and call-boundary checks;
- `src/vm.c`, `gen/cold.lua`: immutable code/images, module retention, checked
  indirect observations, host entry and foreign binding;
- `src/symbolic.c`, `src/residualize.c`: family identity, canonical descriptors,
  native versions, continuations and the backedge correction;
- `frontend/let/abc.lua`, compiler boundaries, staging/API status and Makefile
  runtime/tooling dependencies;
- existing component evidence and the latest clean full validation log under
  `../backedge-placement/clean-final-validate.log`.

Rewrote the mixed specification, architecture and memory/callable pages; corrected
foreign and module-format contracts; updated the document index, source-staging
anchor and refactor checklist/status. The six previous main pages are preserved
with hashes under `research/archive/phase-5-documentation-before-alignment/`.
Decision numbers and intended constraints remain; old measurements are historical.

Removed current-tense claims of old wire formats, serialized caches, bytecode or
native phase quickening, A-only arguments/foreign/image/pointer operations,
state-keyed native stencils, active managed Let execution and completed source
static-demand/snapshot support. Corrected CALLI/TCALLI to one/two operand count
bytes respectively, excluding their opcode. No ISA/API compatibility layer or
implementation behavior was changed.

Phase-3/4 migration boxes now cite actual integration evidence. Their chronological
failure/partial records remain intact. Checking these boxes does not establish the
broader native budget, caller-owned-region or source-virtualization targets.

## Native budget violation

The intended contract remains eight versions total per original bytecode block
entry, including one general slot and all continuation-specialized versions.

Current source instead does both:

1. `version_for()`/`edge()` count only versions whose contexts match
   `abc_symbolic_context_family_equal()`; that comparison includes the complete
   virtual-continuation chain, C coordinates and stack shapes.
2. `inline_candidate()` separately limits the number of continuation families.

`version-budget.abcasm` contains four call sites to one acyclic helper in a loop.
It returns **42 in all three unmodified active modes**. A temporary native object
built from an otherwise identical `src/residualize.c` adds only the diagnostic in
`audit-instrumentation.patch`. It records **10 versions at helper PC 50 (0x32)**
in both eager and lazy modes. The final family-local count there is just three,
so the current family cap does not prevent the aggregate violation.

The trace counts version entries as they are created, including a general entry
that may remain unexecuted in lazy mode. It is not a measurement of ten emitted
lazy bodies, native bytes, timing or arbitrary worst-case growth. The required
budget includes the general slot; the observed entries already exceed eight.
The active runtime archive was never replaced by the diagnostic object.

Raw traces, result lines and disassembly are preserved. The result files contain
incidental runner timings, **not usable performance measurements**: compiler
logging changes preparation/first-arrival costs. No timing conclusion is drawn.

To reproduce from this source checkpoint:

1. Copy `src/residualize.c` into a temporary directory and apply the small
   diagnostic-only patch (paths in its header identify the original temp copy).
2. Compile it with Clang 20, `-O2 -g -std=c11 -Wall -Wextra -Wpedantic -Werror
   -Wno-newline-eof -Iinclude -Isrc -Ibuild`.
3. Link `../final-comparison/runlet.c` with that object **before** `build/libabc.a`,
   using the same include/warning flags and `-lm -lpthread`, into a temp runner.
4. Assemble `version-budget.abcasm` with `build/abc`. Run the temp runner with
   `compiled MODULE 3` and `lazy MODULE 3`, capturing stdout/stderr separately.
   No diagnostic source/object belongs in the normal build.

A correct repair cannot simply reject the ninth valid context or allocate a
family-specific general slot. It must preserve the approved continuation,
placement, capacity/error and no-fallback contracts. Design/approval is separate.

## Checks and boundaries

`check.py` independently verifies:

- revision/profile/section headers for profiles 1–4;
- the specification's SUB.B example in all modes/profiles;
- documented memory/callable example outputs in all modes;
- foreign-example assembly/verification (host-bound execution remains covered by
  the existing API suite, not this script);
- both banks' CALLI/TCALLI manifest lengths/layouts;
- retained budget traces/results;
- local file links in the six main pages;
- unchanged implementation source hashes, including the Makefile.

**29 contract/evidence checks pass; 28 local links resolve.** The inbound source
partial-evaluation anchor was updated to the new staging section. `git diff
--check` passes. Full validation was not rerun for documentation-only edits; the
existing clean pass remains evidence for the unchanged runtime, not proof of the
single-budget requirement. Runtime/generator/header/frontend/tool/Makefile hashes
are preserved in `implementation-before.sha256` and all still match.

`legacy-search.txt` records the active-source search for old directional opcodes,
reverse-family and quickening/A-only markers. Its sole match is frontend prose
explicitly saying the obsolete emitter was removed. Absence of textual markers
is not a complete semantic or dead-code audit.

## Still open

- Single per-location native version-budget conformance and its regression suite.
- Complete migration diff/dead-path review, including untracked/pre-existing work.
- Remaining cross-document target/implementation alignment outside this chunk.
- Final performance acceptance/report consolidation, with interpreter Fibonacci
  and native lazy Fibonacci regressions still disclosed.
- Source virtual values/places/demands, snapshots and managed-profile execution.

Phase 5 stays open. No runtime policy change, C-top refill experiment, new
allocator, scalar engine, compatibility translator or source evaluator was added.
