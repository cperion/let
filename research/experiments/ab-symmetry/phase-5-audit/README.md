# Phase-5 contract/documentation audit — partial

## Corrected in this chunk

`docs/module-format.md` now describes the actual revision-6 loader, all four typed
profiles and their nine possible sections, selected call/return contracts,
protected caller prefixes, exact indirect identities, immutable bytecode and
VM/module ownership. Removed claims that old revisions load, CALL defaults to A,
RET always reads A, indirect instructions carry writable cache words, profile 5
loads, or native execution is merely a separate prototype. Dynamic proposals
remain in their own document rather than being presented as current encodings.

`AGENTS.md` now states selected-stack-first binary semantics explicitly, including
SUB.B = B0 - A0. `docs/symmetric-isa.md` records the actual clean integration pass,
not just the historical concrete-only checkpoint. `docs/spec.md` now clearly
identifies its unaudited pre-revision-6 descriptions and points to the current
ISA/format authorities; its body has not been silently declared current.

## Checks

- Traced `src/module.c`, `src/memory_module.c`, relevant verifier paths and
  assembler selection behavior before updating the format contract.
- Independent serialized-header checks for profiles 1/2/3/4 establish revision 6,
  pointer size 8, reserved zero and section counts 3/6/8/9.
- The documented assembly returns 42 in interpreter/eager/lazy execution.
- Revisions 0–5 and 7 reject; profiles 0 and 5 reject. Exact output is preserved in
  `module-format-checks.log` (16 checks).
- A textual audit of active src/gen/manifest/frontend implementation finds no
  legacy COPY_AB/MOVE_AB/COPY_BA/MOVE_BA, quickened/quickening, reverse-stencil or
  A-only markers. Reverse-edge arrays in graph analysis are legitimate CFG data,
  not reversed arithmetic stencils. This search is not a complete semantic or
  dead-code audit.
- `git diff --check` passes. No runtime implementation changed, so the preceding
  clean full validation remains the implementation checkpoint; the complete
  suite was not rerun merely for documentation edits.

## Remaining

The body of `docs/spec.md`, `docs/architecture.md`, and memory/callable/foreign
profile pages still mix old call/cache/version descriptions with valid material.
They need coherent responsibility-by-responsibility updates, preserving historical
measurements while distinguishing future dynamic/region designs from current
support. Merely changing their status paragraphs is not audit completion.

Whole-diff review and a complete contract/dead-path audit remain outstanding.
Phase-5 fixed performance measurement is separately recorded in
`../final-comparison/README.md`, including regressions and native code growth.
Operand-entry calls were discussed and not adopted; ordinary function entry
still has empty private A/B stacks. Source virtual values/static-demand work is
separate and remains unfinished.
