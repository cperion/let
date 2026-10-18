# Round 10 — the version graph's construction points: calls are effects, edges are keyed

**Mode:** experiment (code reading + a measured probe of the emitted ABC, the
generated C, and the native version count).

## Three candidate questions, ranked

**A (first).** What creates a **version** and what is a **version body's
boundary**? Specifically: is a residual (non-inlined) direct call an **in-body
effect** that resumes in the caller's own version body, or a **control transfer**
into the callee's entry version followed by a **separate return edge/version** at
the caller's return pc — and, independently, which machine events create the
keyed edges of a version graph (branch/switch arms, virtual returns, virtual call
entries, fallthrough into a leader)? Materiality: highest. The design's single
normative `run()` block (`ARCHITECTURE.md:316-339`) (i) ends the version and
"finishes" it when a call is residualized under the `K` bound
(`binding.residual_call(v,target); binding.finish(v); break`), silently dropping
every instruction after the call in the caller; (ii) tests "pc is a direct-call
target" *before* dispatch — that is the callee's entry pc, not the call
instruction; and (iii) has no site that creates a version for a control-transfer
arm, although every branch needs one. So the procedure as written cannot compile
a branchy function and cannot compile a residual call. The answer fixes the
algorithm, says whether a call-return pc is a version boundary (and therefore
whether a *return key* rule exists at all), and fixes the binding interface
(who computes a target version). The three incumbent sinks disagree in code:
ABC and the portable-C sink continue in-body; native marks every call-return pc a
block and creates a version there. Ranked above B and C because this is a
completeness/correctness defect in the normative procedure, not a policy choice.

**B (second).** What is the **residual-function set** — which functions get an
entry version and a body? `run()` iterates "each residual function f" but the
facts list never defines the set: an acyclic callee can be inlined at every call
site and needs no body, while an exported/address-taken function must have one,
and a recursive function is always reached by a residual call. Materiality:
medium-high (a module fact, the outer loop's definition, code size); the
incumbent's `live`/`mark_residual_callees` already derives it from facts the
design keeps, so it is likely a definition to write down rather than a design
change. Not investigated this round.

**C (third).** Q12's fact ownership (per-pc A/B/C heights, `CSET` targets,
successors, cycle bodies/may-write sets in one core pass). Materiality: medium
(compile cost, one-owner invariant); already scoped in Q12, no correctness answer
changes.

## What was read

- `src/symbolic.c:220-259` (`machine_call`). A **virtualized** call pushes the
  arguments to the C frame, pushes a continuation and emits a control edge
  (`ABC_SYM_EXIT_CONTROL`). A **residual** call pushes the sink's
  `effect.result[]` values — `HOME`/`BACKEND` descriptors at the call's result
  cells — and **returns 1**, so the symbolic walk continues at `return_pc` in
  the same body. `machine_foreign` (`:445-455`) and `machine_indirect` have the
  same shape: an effect with results, then continue.
- `gen/symbolic.lua:7` (`SYM_NEXT`): `ABC_SYM_EXIT_BLOCK` is returned iff
  `m->blocks && m->blocks[m->pc]` — the **sink's** block array decides body
  boundaries, so the three sinks can and do choose differently.
- `src/optimize.c:299-303` (`dag_call`): a recursive, non-`nested_eligible` call
  becomes an `N_CALL` node with `N_RESULT` nodes and `effect->virtualize` stays
  0. `src/optimize.c:364-385` (`simulate_tree`) rejects `ABC_SYM_EXIT_BLOCK` and
  keeps walking, so the ABC sink has **no** boundary at a call return.
- `src/residual_builder.c:1699-1758` (`on_call`): emits a `CALL` operation and no
  terminator; `discover_leaders` (`:2048-2113`) marks function entries, branch
  targets/fallthroughs and switch targets — **not** call-return pcs. A residual
  call and the code after it are one block.
- `src/residualize.c:445-462` (`discover_blocks`): `if(kind==K_CALL &&
  next<end) c->block[next]=1;` — native marks every call-return pc a block;
  `compile_version` (`:785-801`) ends the body at any `c->block[pc]` by
  `edge()` + `emit_jump` + `break`, so native creates a **version per residual
  call return**. By contrast `native_emit_foreign` (`:589`) emits an `FCALL` and
  continues in the body — native already continues in-body through a clobbering
  effect with results.
- `src/residualize.c:492-570` (`native_emit_control`/`native_emit_edge`) and
  `src/residual_builder.c:1212-1348` (`on_control`) + `make_edge` (`:1980-2046`):
  each sink computes target versions **inside its own hooks** (`edge`/
  `version_for` vs `make_edge`/`version_for`) — the drift the design centralizes.
- `src/symbolic.c:471-477` (`machine_return`): a virtual return pops the
  continuation, emits `emit_return` and `emit_edge(..., frame.return_pc)`; a
  terminal return terminates. So a virtual return is a keyed edge to the return
  pc, and the initiator is the machine, not a driver branch check.

## Measured probe

`experiments/10-call-continuation.lua` and its output
`experiments/10-call-continuation.out`; artifacts in
`experiments/10-call-continuation-out/` (`.raw.abc`, `.opt.abc`, `.dis`, `.c`).
Fixtures have only **non-tail recursive** calls, so the inline rule cannot
inline them:

- `mutual-nontail`: `ping(n) = pong(n-1)+1`, `pong(n) = ping(n-1)+2`,
  `main = ping(4)`.
- `self-nontail`: `f(n) = f(n-1)+3`, `main = f(5)`.

Measured (existing compiler, abc-opt, C writer, four execution modes; no source
change):

1. **ABC continues in-body.** `mutual-nontail`, abc-opt: `f0 0000000f CALL_A
   0x0000001b 1` is immediately followed by `00000015 ADDI_A 1` (the post-call
   computation), and `f1 0000002a CALL_A` by `ADDI_A 2`; the pre-optimizer module
   shows the same with `CSETN_A 1` as the successor. `self-nontail`: `CALL_A 1` →
   `ADDI_A 3`. No jump follows any residual call: the callee's return address
   (the next instruction, `CALL` is 6 bytes) is inside the same emitted
   sequence. abc-opt shrinks the module 58 → 24 instructions (mutual) and
   31 → 13 (self); values 13 and 15 in `off/threaded/eager/lazy` for both.
2. **The C sink continues in-body.** `mutual-nontail.c`:
   `block_9: v_19=abc_aot_function_1(v_17);` then `v_22=v_19+v_20;` in the same
   block; `block_31` likewise. `self-nontail.c`: `block_8: v_18=...;` then
   `v_21=v_18+v_19;`. The call is an operation, the return is not a block.
3. **Native disagrees, at a measurable cost.** `experiments/10-version-count.c`
   (one-off probe against `build/libabc.a`) reports compiled version bodies:
   `mutual-nontail` eager 19 / lazy 11 (`real_calls` 5), `self-nontail` eager
   12 / lazy 8 (`real_calls` 3), identical for the raw and abc-opt modules. The
   fixture has 2 (mutual) and 1 (self) **non-tail** residual call sites (the
   remaining call in each fixture is `main`'s tail call, which has no return pc)
   — each one a call-return block under `discover_blocks` — so at least that many
   version bodies exist only because native splits at the return pc. (Per-kind
   attribution is structural, not instrumented; the measured total is the
   incumbent's count, not a delta.)

## Answers

1. **A residual direct call is an effect in the body, not a control transfer.**
   The shared machine already models it that way: `machine_call` with
   `virtualize == 0` returns the result values as binding locations and returns
   1, and the caller's walk continues at `return_pc` in the same version body.
   There is no return edge, no return key and no post-call version. The call
   reaches the callee's entry version by the **call ABI** (arguments materialized
   into binding locations), not by a keyed edge; the runtime continuation is a
   binding mechanism (ABC's `CALL` return address, C's call expression, native's
   stored resume label) inside the body. A foreign call is the same shape, which
   is the decisive argument that native's return-pc boundary is not required:
   native already continues in-body after an `FCALL` that clobbers its cache.
   The design's `binding.finish(v)` on the residual-call branch is a defect, and
   native's `K_CALL`-return block marking / post-call version bodies are a
   retired private boundary.
2. **Every keyed edge is created by one driver function.**
   `edge_to(target, context)` = binding canonicalization + loop-invariant rule if
   `target` is a loop header + family-budget replacement (with lookup) +
   content lookup/creation. It is called for (a) a branch/switch arm — **both**
   the taken target and the fallthrough (a body ends at a control transfer, so
   both arms are versions, exactly as the C and native sinks emit today);
   (b) a virtual return to `frame.return_pc`; (c) a virtual call's callee entry
   (the machine has already pushed the continuation, so the key is the callee
   context); (d) straight-line fallthrough into a leader (the pre-dispatch check
   in the old block); (e) every residual function's entry, created before any
   body is walked so a call can name its target independent of walk order. The
   binding never computes or compares a key: its transfer hooks receive version
   handles and emit `jump`/`branch`/`switch`/`return`/`call`. This makes the
   design's prose ("a backedge calls `version_at` exactly like a forward edge")
   implementable and removes the three private edge/key computations
   (`edge`/`version_for`, `make_edge`, the path tree).
3. **The inline/residual decision is made at the call instruction**, inside the
   driver-owned call hook, not by a pre-dispatch test for "pc is a direct-call
   target" (that pc is the callee's entry). Inline: the machine pushes the
   continuation and the driver calls `edge_to(callee entry, callee context)`, then
   the binding jumps. Residual: `binding.residual_call(call)` emits the call and
   supplies the result locations; the walk continues at `return_pc`. The `K`
   fallback is exactly this residual form, so the fallback "drops the chain"
   without ending the caller's body.

## Consequence for the design

- The algorithm block is replaced by `version_at`/`edge_to` + a walk that ends
  only at a control transfer, a leader reached by fallthrough, or a terminator;
  the call hook owns the inline/residual decision; the residual-call branch
  continues instead of finishing.
- The calls-and-edges invariant is split in two: a **call** (inline or residual)
  is not a keyed control edge; an **edge** is a keyed control transfer between
  bodies. The continuation chain therefore names only inlined call return sites.
- Native's call-return block marking and the post-call version body retire; the
  binding's post-call obligations are "materialize values live across the call,
  hand back the results as locations, reset placement state" — the same
  obligations an `FCALL` already has.
- All residual-function entry versions are created up front (deterministic
  target naming).

## Rejected alternatives

- **Residual call ends the body; the return pc gets a version keyed by the
  post-call context** (native today). The return pc of a call is reached by
  exactly one call site, so it is not a join: the boundary buys no sharing, adds
  one label + key + join per residual call, and the caller could not distinguish
  it from straight-line continuation. It is also inconsistent with the shared
  machine's residual-call form and with two of the three sinks (measured above);
  native's own `FCALL` shows the cache reset does not need a boundary. Retired.
- **Residual call as a keyed edge into the callee entry plus a return edge**
  (a literal reading of "a residual call into the callee's single generic-key
  entry version" as a version jump). One entry version serves every caller, so
  the return cannot be encoded in the entry's key; the return site would have to
  be a body-specific label chosen by the call site, i.e. a return-key rule that
  the call ABI already supplies (result cells are known locations). Rejected.
- **Let each binding compute the target version of a control arm** (the
  incumbent's model). Three rule copies with drifted behavior
  (`native_emit_control`'s `edge`, the C sink's `make_edge`, the ABC path tree),
  and it contradicts the design's one-owner key rule. Rejected; the binding
  receives version handles.
- **Let a body continue through the fallthrough arm of a branch** (trace layout).
  It would save one version per branch, but the taken arm still needs a version,
  so the body would have two kinds of successors and the "one walk per body"
  model would need intra-body labels; the C and native sinks already emit both
  arms as versions, and the per-family budget accounts for them. Not adopted;
  recorded as a possible binding-side layout choice, not a key rule.

## Not established

- The per-kind native version delta (only the total is measured; the
  call-return attribution is code-structural).
- Candidate B: the residual-function set's exact definition (entry roots,
  address-taken/indirect targets, the closure over non-inlined calls).
- Whether a virtual return's `return_pc` could be an intra-body local label
  rather than a version; the design keeps it a version (the C and native precedent),
  and that is a layout question, not a key rule.
