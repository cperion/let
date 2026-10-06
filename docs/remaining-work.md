# Remaining implementation work

This is the short restart checklist for unfinished Let work. The detailed semantic contract remains `syntax.md`; `frontend-gap-analysis.md` contains the longer audit. Do not weaken effect ordering, traps, ownership, GC-root visibility, ABI verification, deterministic output, or optimizer fixpoints to complete these items.

Current baseline: the repository builds from a clean tree and `make validate` passes with 264 compiler, 100 lowering, 127 optimizer, and 23 staging checks. Block-handler result inference, indirect partial application, retained schema methods, recursive named types, foreign calls, raw pointers, defer, checked static/dynamic integer–`f64` conversions, and the first open-word slice are complete.

## 1. Finish semantic construction

### Open words

- Add runtime keyed supply for closed words and typed indirect callables.
- Add open-word methods with receiver binding. Keep these distinct from the completed retained schema-method values.
- Complete dynamic structural conversions: open-word-to-record and `any`-to-signature conversion.
- Preserve open-word identity and copy semantics while making supplied fields read-only where required.
- Support indirect runtime supply as an open word, plus module-level open and frozen words.
- Keep SLet rejection for ownership-requiring dynamic callables and retained receivers.

### Interface and requirement evidence

- Prove schema/interface evidence through aliases, mutation, deeply nested fields, sums, captures, and imported module boundaries.
- Preserve canonical requirement keys, schema identity, supplied evidence, callable identity, binding time, and occurrence-sensitive borrow provenance.
- Complete value exports and richer imported schema interfaces without replacing nominal evidence with structural guesses.
- Finish this after module storage gives imported and mutable values durable identities.

## 2. Finish modules and static semantics

- Add nonliteral module values and declaration-ordered, exactly-once initialization.
- Add persistent mutable module storage, relocations, trace metadata, and deterministic public ABI closure.
- Carry initialized values, open/frozen words, schemas, types, and callable identities correctly across imports and exports.
- Implement explicit source static boundaries, or sound total/effect-free/no-abort proofs where implicit evaluation is allowed.
- Residualize calls with runtime inputs while executing fully known source computation only as verified ABC in `abc_vm`.
- Reject foreign effects and nonserializable VM-local addresses at static boundaries.

## 3. Close ownership and ABI proofs

- Complete SLet borrow/provenance checking through mutation, aliases, nested aggregate owners, sums, calls, matches, and stores.
- Complete Let managed provenance and root visibility for the same deep shapes.
- Implement verified call and return ABIs for managed or address-bearing sums and remaining managed aggregate forms.
- Ensure descriptors trace environments and managed addresses, never code pointers or hidden raw cells.

## 4. Replace the temporary staging host

- Cache verified staging modules and eager/lazy preparation in-process.
- Maintain persistent per-module VM images and snapshot accepted initialization state.
- Run speculative folds transactionally so refused folds cannot leak writes.
- Re-encode results through type/layout metadata; never serialize VM-local, callable, or collected-object addresses.
- Add delayed progress and interrupted static-stack diagnostics with source positions.

## 5. Final acceptance

For each new source family:

1. Add positive and negative source tests with stable diagnostic codes and spans.
2. Compare compile-time behavior under interpreted, eager, and lazy VM policies.
3. Require byte-identical residual modules across those policies.
4. Execute residual modules under all VM policies and compare results and traps.
5. Run optimizer growth/fallback/fixpoint checks and `make validate`.
6. Run `git diff --check` and update `slet-subset.md`, `frontend-gap-analysis.md`, and user-facing examples.

Portable C intentionally remains an SLet-only product. `ABC_BLOCK_VERSION_LIMIT` continues to bound local compatible block versions, while `ABC_OPTIMIZER_PATH_LIMIT` independently bounds speculative optimizer paths. Crossing the optimizer path limit must retain the verified input function.

## Recommended order

1. Complete open-word semantics needed by module values.
2. Implement module initialization, persistent storage, and static boundaries.
3. Complete interface-evidence proofs using those durable module identities.
4. Close deep ownership and managed/address-bearing ABI proofs.
5. Replace the staging process bridge with the persistent transactional host.
6. Perform cross-mode acceptance and documentation closure.
