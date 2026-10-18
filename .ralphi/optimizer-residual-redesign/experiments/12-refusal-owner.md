# Round 12 — a refusal belongs to the owner, and the entry version survives it

## Question (ranked first of three)

The design's refusal rule is the only place where a sink may *change its mind about
a function after the walk has started*, and it is written as if every sink can
retain and as if the refusal can arrive "at a later version of the same owner"
while only "unpublished versions" are discarded:

> A body the binding cannot record is **retained**: its entry version's residue is
> the verbatim body, every direct call in it is a residual call (no walk, hence no
> inline decision), and the binding reports those targets so the driver creates
> their entry versions. … A refusal is function-granular: if it arrives at a later
> version of the same owner, that owner's unpublished versions are discarded and
> replaced by the retained body. Nothing published is rebuilt.

Three things are undefined or false in that paragraph:

1. **When is the refusal known?** If it can be decided from module facts, the
   driver could classify before walking and the mid-walk machinery is dead. If it
   depends on the walk, "no walk" is wrong and the version queue must be cleaned
   up.
2. **What is the unit of publication?** `version_at` queues one version at a time
   and `run` finishes one body at a time. If publication is per version, an owner
   whose entry body was already published and whose interior body is refused is
   left *mixed* (a versioned entry plus a verbatim replacement, or a verbatim
   entry whose published interior bodies are no longer reachable).
3. **Which sinks can retain at all?** Verbatim residue is an ABC capability. The
   portable-C writer emits C for a subset and **rejects** residue outside it; the
   native residualizer has no per-function fallback and fails the image. A driver
   rule that says "retained" for every sink has no implementation for two of the
   three bindings.

Ranked above (B) the same paragraph's unstated call contract for calls that name
no version (indirect `CALLI`/`TCALLI`, foreign externs; see below, measured) and
above (C) Q19's native compile-set policy (compile time/code size, no correctness
claim), because a refused owner can be emitted with dangling interior references.

## What was read

- `src/optimize.c:726-780` (`residualize_function` builds the whole function into a
  **local** `Bytes code`; every failure path frees it and returns 0 — nothing of a
  failed function reaches the module), `:782-787` (`retain_function` replaces the
  whole `FunctionCode` with the source bytes and records every direct target),
  `:54-56` (`direct_target` accepts **`K_CALL` and `K_TCALL`**), `:871` (the driver
  calls `retain_function` on any `residualize_function` failure), `:826` (the
  writer emits all functions only after the walk loop), `:291-297`
  (`materializes_frame`), `:300`/`:310` (`dag_call`/`dag_tail` refuse a callee that
  materializes a frame).
- `src/symbolic.c:205-215` (a float binary with no sink handler sets
  `ABC_SYM_EXIT_BOUNDARY` **only when not folded**; folded constants proceed),
  `:443-457` (`machine_indirect`: the binding may resolve a known target and turn
  the `CALLI` into a direct call/tail; otherwise the target is a value and there is
  no symbolic successor), `:530-538` (`machine_foreign`: an effect, no target
  version).
- `src/residualize.c:598-650` (`native_emit_indirect`: saves the target and the
  arguments into their homes and calls `place_indirect_resolution`; no version, no
  static callee), `:780-801` (`compile_version` compiles one body; any symbolic
  failure goes to `failed` and fails the image), `:822-841` (the entry loop has no
  skip and no per-function fallback), `:845` (`publish` at the end).
- `src/residual_builder.c:2399-2400` (`supported` set only after the whole function
  IR is built), `:2469-2526` (`function_references_unsupported`,
  `remove_unsupported_dependencies`: a **post-walk** closure that clears
  `supported` for unsupported functions and every caller), `:2533` (`finalize_program`
  runs the closure), `:2537,2560` (unsupported functions are omitted),
  `src/residual_c.c:1232-1237` (portable C rejects the memory profile outright),
  `:1266-1272` (an export of an unsupported function is an error).
- `docs/symbolic-vm.md:164` ("Portable C … emits strict self-contained C11 for its
  current integer/control/direct-call subset; float, memory, indirect/foreign,
  managed and dynamic operations currently reject rather than falling back to
  another backend"), `docs/architecture.md:208` (same policy),
  `docs/abc-opt.md:100` (ABC: "Unsupported functions are retained independently").

## What was measured

`experiments/12-refusal-owner.lua` / `.out`, artifacts in
`experiments/12-refusal-owner-out/` (raw/opt `.abc`, `.dis`, `.c`). Four hand-built
modules through the existing assembler, verifier, `abc-opt`, the C writer and all
four execution modes.

1. **`retain-float`** — a function whose `FADD.A`/`F2IS.A` operands are
   non-constant (float arguments), followed by an independently foldable `3 + 4`
   witness:

   ```
   00000000 CGET0_A   00000001 CGET1_B   00000002 FADD_A   00000003 F2IS_A
   00000004 PUSH8_A 3 00000006 PUSH8_B 4 00000008 ADD_A    00000009 DROP_A
   0000000a ADDI_A 5  0000000c RET_A 2 1
   ```

   `abc-opt` output is **byte-identical** (`raw == opt`, opt is a fixpoint), so the
   whole owner was retained: the `3 + 4` witness is still two pushes and `ADD_A`.
   The retained body executes in interpreted/compiled/lazy/threaded (`8` for
   arguments 1.0/2.0).
2. **`fold-float`** — the *same* float instruction kinds (`I2FS`, `FADD`, `F2IS`)
   with constant operands: 10 instructions → **4** (`PUSH8_A 8; RET_A 0 1`), value
   `8` in all four modes. So the same instruction set is recordable or not
   depending on whether the walk folds the operands. **Recordability is a property
   of the walk, not of the function.**
3. **`mixed`** — a retained float owner (`calc`) next to a foldable sibling
   (`good`) in one module: functions 2 → 2, `calc` byte-identical, `good`
   optimized to `PUSH8_A 7; RET_A 0 1`. Both run in all four modes (`good = 7`,
   `calc = 8`). Retention is per owner and does not disturb another owner's code;
   the owner's entry version is emitted and callable.
4. **`calli`** — round 11's callable fixture: the `CALLI_A` body is retained
   byte-identically while its relocation-rooted target survives; native executes
   it in all four modes (`42`). The ABC sink has **no** indirect-call residue
   (`dag_indirect` only succeeds for a statically known callable and
   `callable_safe` is 0, `optimize.c:305-306`), so an indirect call is exactly a
   mid-walk refusal.
5. **The C writer rejects all four modules** (exit 1, `portable C currently
   supports only the integer/static profile`; the float modules carry the memory
   profile and `calli` carries the image that `.codeaddr`/signatures require). It
   never retains and, for every module it can reach, never sees an unsupported
   body. The silence of `remove_unsupported_dependencies` is a legacy salvage
   path outside the documented policy, not a binding mode.

## Answers

1. **A refusal is discovered by the walk, so it cannot be pre-classified.** The
   measured pair (`retain-float` byte-identical vs `fold-float` 10 → 4) contains
   the same float operations; only folding decides. A module-fact predicate
   ("this function contains a float/pow operation") would retain `fold-float` and
   lose its whole fold. `pow` has the same shape (`symbolic.c:304-310`), and the
   `DagSink`'s float/pow handlers are absent (`optimize.c:744-749` sets only the
   integer/check/memory/effect hooks). So the mid-walk refusal stays.
2. **The refusal is owner-granular and the entry version is the survivor.**
   - A function is entered from outside only at its entry pc (`verify.c:131-134`;
     a call targets a function entry, and code addresses enter through
     relocations), and every interior version is created by an edge inside that
     function's own walk. The **only cross-owner version handle is an entry
     version**, so discarding a refused owner's interior versions cannot
     invalidate another owner's body. (`mixed` is the measured form: the sibling
     is emitted and correct.)
   - The incumbent already implements exactly this unit: the ABC sink builds the
     whole function in a local buffer and replaces or discards it as a unit
     (`optimize.c:726-780,782-787`), and the C builder builds all versions of a
     function before `finalize_function` copies them (`residual_builder.c:2399-2400`).
   - Therefore: on a refusal, the owner's **entry version keeps its handle** and
     its residue becomes the source body; the owner's other versions are dropped
     from the table and the queue; publication is owner-granular, so a body of the
     refused owner is never published before the refusal is resolved. "Nothing
     published is rebuilt" holds for every *other* owner and for the refused
     owner's staged region; the only replacement is the owner's own entry residue.
3. **The retained body's direct targets are `CALL` and `TCALL`, and the driver can
   derive them from module facts.** `direct_target` accepts both
   (`optimize.c:54-56`) and `retain_function` records both (`:782-787`), which
   closes round 11's open item. Because the direct-call graph already covers every
   `CALL`/`TCALL` (`optimize.c:57-118`, `:291-318`), the driver expands a refused
   owner's targets from that fact; the round-11 hook argument
   `retain(function, direct_targets)` is unnecessary.
4. **Only ABC can retain.** The retained body is the source instruction stream
   with rewritten displacements (`optimize.c:782-787`, `write_module` `:826-846`).
   Portable C has no source-body residue and rejects what it cannot record
   (measured; `docs/symbolic-vm.md:164`; `residual_c.c:1232-1237`). Native has no
   per-function fallback: a symbolic failure fails the whole image
   (`residualize.c:794-799`), and `residualize()` installs entries for every
   function without a skip (`:822-841`). So a binding must answer "can I emit this
   owner verbatim?" — ABC yes, C no, native no — and the driver fails the build
   when the answer is no. The C builder's `supported`-drop and
   `remove_unsupported_dependencies` closure (`residual_builder.c:2502-2533`) are
   a legacy post-walk salvage of unreachable functions; they are not a target
   mechanism.
5. **A call that names no version is an effect.** `CALLI`/`TCALLI`: if the binding
   resolves the target to a known function entry, the machine turns it into the
   corresponding direct call (`symbolic.c:443-457`, the `effect.direct` path) and
   the direct-call rule applies; otherwise it is an in-body effect whose target is
   a binding location and whose callee is resolved **at runtime** through the
   image's entry table (native: `residualize.c:598-650`,
   `place_indirect_resolution`; measured `42` in all four modes on `calli`). That
   is why code-address relocations are entry roots (round 11). `TCALLI` is the
   same with no successor. Foreign calls are effects too (`symbolic.c:530-538`):
   they name the binding's extern, never a version. The design must therefore add
   `indirect_call`/`foreign_call` to the binding interface (or state that
   `residual_call`'s target is optional) and say that only a direct call is
   inlined or names a version.

## Decision

- Refusal is **owner-granular**: the walk abandons the owner, its non-entry
  versions are dropped, its entry version keeps its handle and gets the source
  body as residue, and the driver creates entry versions for the owner's
  `CALL`/`TCALL` targets from the direct-call-graph fact. Publication is
  owner-granular for a binding that can refuse.
- Retention is a **binding capability** (`retain(owner) -> bool`): ABC true
  (verbatim source body), portable C and native false (build/image failure). The
  driver's rule is "retain if the binding can, otherwise the refusal is fatal".
- The design adds the call-effect contract: direct = inline/residual with a target
  version; indirect = statically-known target becomes a direct call, otherwise an
  effect with no version; foreign = effect with no version. Only a direct call is
  ever inlined or names a version.
- Retired: the round-11 `retain(function, direct_targets)` argument (facts supply
  the targets), the "no walk" wording, the "only unpublished versions are
  discarded" special case, and the portable-C builder's post-walk
  `supported`/`remove_unsupported_dependencies` salvage pass (rejection is the
  documented policy).

## Not established

- The portable-C binding's exact scope under Q3: reject the whole module versus
  emitting a statically recordable subset. The driver contract above is
  independent of that choice; the measured C entry point rejects the profiles that
  carry the residue it does not support.
- Whether any refusal reachable from a *verified* integer-profile module exists
  (the builder's type-compatibility/unmapped-`HOME` paths were not constructed).
- Corpus-wide retention frequency and the compile-time share of retained
  functions (not measured).
