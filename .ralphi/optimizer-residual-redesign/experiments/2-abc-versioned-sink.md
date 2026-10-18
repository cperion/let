# Round 2 — the ABC sink under versions: measured cost of the path tree, and the residue scope

**Question pursued (ranked first in `2-questions.md`):** under a versioned
traversal, is ABC residue a function-wide value DAG (versions select only
control), or per-version residue whose cross-edge values are constants and the
binding's locations? Sub-facts needed: is a versioned non-entry block
representable/verifiable, and what does the current path tree actually cost?

**Method.** No implementation change. I assembled ABC modules with the existing
`tools/assembler.lua` support code, ran the existing C optimizer through
`frontend/let/optimize.lua` (`abc_optimize_mapped`), decoded the emitted code
section with the opcode manifest, and executed original and optimized modules
with `build/abc run … --interpreted` and `--jit=threaded`. Script:
`experiments/2-abc-probe.lua` (regenerate with `luajit <script>` from the repo
root; artifacts are written to `experiments/2-abc-probe-out/` and are not
committed). All fixtures are new; none of the existing corpus was modified.

## 1. Measured results

| case | input instr | output instr | retained? | idempotent | max output copies of one input pc | compile |
|---|---|---|---|---|---|---|
| `motivating-f` (`sq(a)+sq(b)`) | 11 | 6 | no | yes | 2 (inlined `MUL`) | 0.1 ms |
| `diamond` (constant arms + shared suffix) | 8 | 6 | no | yes | 2 | 0.0 ms |
| `phi` (2-result diamond) | 8 | **19** | no | yes | 1 | 0.0 ms |
| `choices` (SWITCH + join) | 10 | 8 | no | yes | 3 | 0.0 ms |
| `effect-then-branch` (store, then branch) | 9 | 9 | **yes** | yes | 1 | 0.0 ms |
| `branch-then-effect` (branch, then store) | 7 | 7 | **yes** | yes | 1 | 0.0 ms |
| `branch-then-trap` (`DIVU` in one arm) | 8 | 8 | **yes** | yes | 1 | 0.0 ms |
| `branch-then-call` (direct call in one arm) | 8 | 8 | no | yes | 1 | 0.0 ms |
| `diamonds-4` (4 joins, suffix) | 40 | 62 | no | yes | 16 | 0.2 ms |
| `diamonds-8` | 64 | 1,022 | no | yes | 256 | 1.8 ms |
| `diamonds-10` | 76 | 4,094 | no | yes | 1,024 | 6.8 ms |
| `diamonds-12` | 88 | **16,382** | no | yes | **4,096** | 23.9 ms |
| `diamonds-13` | 94 | 94 | **yes** | yes | 1 | 21.7 ms |

Interpretation:

- **Representability is not the constraint.** The path tree already emits
  multiple copies of non-entry basic blocks (`maxdup` 2/3/16…4096) and the
  verifier and all four execution modes accept them; provenance is already an
  N:1 output→input offset map (`optimize.c:791-808`) and relocation already
  handles duplicated origins. "Multiple versions of a non-entry block" is
  duplicate code with relative jumps — nothing the encoding forbids. What the
  encoding does forbid is a second entry for one function: `CALL`/`TCALL` must
  target a function entry (`src/verify.c:131-134`).
- **The path tree's cost is control duplication, not value data.** `diamonds-n`
  has 2^n paths that all reconverge in the *same* symbolic state (A/B empty,
  C = arguments); the tree still duplicates the shared suffix per path. A
  versioned traversal would merge all those paths at the first join (equal key)
  and emit the canonical source shape, i.e. ≤ ~94 instructions for the N=12
  case that today emits 16,382. The input module is itself that shape, runs
  correctly, and is 94 instructions — the comparison is measured, not projected.
- **There is a coverage cliff, not just a size cliff.** Any function with an
  unknown branch and a non-call effect (store, trap, allocation, foreign
  operation) is *retained unoptimized*: `optimize.c:157` sets `noncall_effect`
  and `optimize.c:747` fails every effect node when `sink.paths>1`. Effects
  before the branch are equally refused (measured: `effect-then-branch`), and
  calls survive only as branch-local calls (`optimize.c:526-528`). So
  `if (c) { store }`, `if (c) { x = a/b }` lose all dispatch reduction — the
  opposite of the optimizer's purpose. Under versions each such effect lives in
  exactly one straight-line version body, so the restriction disappears.
- **The path limit is a whole-function cliff.** At 2^13 > `ABC_OPTIMIZER_PATH_LIMIT`
  (4096, `symbolic.h:5-10`) the function is retained: N=12 is optimized into
  53 KB, N=13 (one more branch, 94 instructions) gets no optimization at all —
  after spending 21.7 ms exploring. Compile time is exponential in branches
  (0.2 → 1.8 → 6.8 → 23.9 ms for 4 → 12 branches of an 88-instruction function).
- **The multi-result join machinery is expensive.** `phi` grows 8 → 19
  instructions: the tree must push zeros to C, `CSET` each arm's results, `JMP32`
  to one shared `RET`, then `CGET`/`RET` (disassembly in §2). Per-version RETs
  make that 2 specialized bodies of ~4 instructions and delete
  `emit_phi_tree`/`PhiPatches` (`optimize.c:705-723`).
- **The documented canonical fixture is exactly what the current optimizer
  emits.** `docs/abc-opt.md:82-91` requires the inlined `sq(a)+sq(b)` region to
  become `CGET.A 0; MULC.A 0; CGET.B 1; MULC.B 1; ADD.A; RET 2 1`. The
  disassembly is `CGET0_A; MULC_A 0; CGET1_B; MULC_B 1; ADD_A; RET_A 2 1` — the
  same instructions. This is a confirmed current behavior a versioned sink must
  preserve (it is straight-line, so no version boundary is involved).

## 2. Disassembly evidence

`diamond` (two constant arms, suffix `+1`; the join is duplicated per constant):

```
CGET0_A; JZ_A 0x9; PUSH8_A 11; RET_A 1 1; [0x9] PUSH8_A 21; RET_A 1 1
```

`phi` (multi-result join): 19 instructions with `PUSH8_A 0; CPUSH_A` ×2,
per-arm `CSETN_A`/`CSET0_A`, `JMP32`, then `CGET1_A; CGET0_A; RET_A 3 2`.

`motivating-f`: `CGET0_A; MULC_A 0; CGET1_B; MULC_B 1; ADD_A; RET_A 2 1`.

## 3. Which key/residue model do these numbers imply?

The path tree re-projects each path from a function-wide hash-consed value graph
(`DagSink.nodes`, `optimize.c:27-40`, hash-consed by `node()` at
`optimize.c:153-161`). A versioned sink can either keep that graph or make
residue per version. The evidence favours **per-version residue with keys made of
constants plus the binding's locations**:

1. **The existing C sink already implements exactly this policy**, and is the
   strongest available precedent. `canonicalize` (`residual_builder.c:851-877`)
   replaces every non-constant value in the key by a home (A/B logical slot, C
   logical home) and keeps constants when `forget_constants==0`;
   `create_version` (`:996-1062`) turns every non-constant key slot into a block
   argument and records the home→argument map; `version_for`
   (`:1083-1123`) uses homes+constants for edges, forgets constants only at loop
   entries, widens recursive keys, and at `ABC_BLOCK_VERSION_LIMIT-1` falls back
   to the all-home key. This is one algorithm, already written and tested, and
   it never puts a sink value identity in a key.
2. **The core equality compares `reg` (`symbolic.c:33-38`), which is sink-owned
   (`symbolic.h:15`) *only if* a key carries sink values. Canonicalizing every
   non-constant to a location makes `reg` irrelevant for version identity and is
   what lets residue be per version.** The alternative — a function-wide value
   graph with `reg` = DAG node id in keys — needs cross-version home reuse to be
   dominance-safe, which the path tree never had to solve (its uses/homes are
   tree-shaped: `mark_path_tree`, `branch_rematerializable`,
   `optimize.c:492-528`), and it keeps the O(n²) hash-consing scan and the
   path-use counting. The measured blow-up is *control* duplication, so the
   value graph buys nothing for the expensive cases.
3. **Constants in the key preserve all the measured specialization.** The
   `diamond` and `choices` arms stay folded into `PUSH8 11/21` or `10/11/12`
   because constants cross the edge in the key (`canonicalize(...,0)`), exactly
   as today. Only *computed* values are materialized into the target key's
   homes, which is also where the current scheduler puts a cross-path multi-use
   node (a C home). No measured case regresses; `phi` improves.
4. **ABC's location vocabulary cannot be `HOME(A,i)`.** The core's canonical
   generic check (`symbolic.c:62-75`) accepts only `abc_symbolic_home(s,i)` for
   every stack slot, but the ABC sink's `dag_value` rejects anything that is not
   `CONST`/`BACKEND` (`optimize.c:165-170`), and an A/B slot is not addressable
   in ABC. The only stable ABC location is a **C-frame slot**; the join writes
   it with `CPUSH/CSET` and the target version reads it with `CGET`. This is the
   existing loop-home/phi mechanism (`optimize.c:752-763, 710-723`) generalized
   to every version edge; what must go is the path tree's need to choose between
   rematerializing and homing per path.
5. **Recursion keeps the entry-fact lattice**, but as a driver rule, not a
   private fixpoint: `CALL/TCALL` can only target the function entry
   (`verify.c:131-134`), so a function entry has exactly one version and its key
   must be the monotone join of all incoming keys (constant only when every edge
   agrees). This is why `ArgumentFact`/`activate_function_facts`/
   `join_call_facts` (`optimize.c:850-855`) exist; the *lattice* stays, the
   per-function dirty loop (`optimize.c:870-873`) becomes the driver's
   re-execution of a widened entry key. The counter fixture's documented
   `BLTUI_A 50` / `ADDI_A 7` specialization depends on it
   (`frontend/tests/optimize.lua`).

## 4. Consequence for the design (what changes from round 1)

- Round 1's "ABC — one bytecode region per version, with the per-version
  expression DAG scheduled locally" is **right about version scope** but only
  now justified, and it needs the complementary rule: **a version key contains
  no sink residue identity — only constants and binding-defined locations.**
  Without that rule a sink needs a function-wide value graph for key equality,
  and "per-version residue" is false.
- The binding owns the location vocabulary and the canonical generic form; the
  core owns equality, family counting, the budget rule, recursion widening and
  the entry-widening order. The C sink's `canonicalize`/`family_count` become
  the core's single implementation with the binding's location hook, not two
  implementations.
- Q1 recommendation (still the user's hard gate): adopt versioned blocks for
  `abc-opt`. Measured basis: 186× code growth and a 24 ms compile for an
  88-instruction function, a hard cliff at 4096 paths that disables the
  optimizer, and whole-function refusal of every branch-plus-effect function.
  Projected/structural basis for the versioned sink: output ≤ blocks × budget,
  path limit and `simulate_tree`/`DagTree`/`emit_tree`/`emit_phi_tree`/
  `mark_path_tree`/`branch_rematerializable` retire; `phi` join shrinks.
- Risks not settled here: byte determinism and idempotence of a versioned ABC
  sink (the current output is idempotent on every measured case, including the
  16 KB case); the exact ABC canonical key shape (C slots only) needs a
  prototype; and the version budget value for ABC (Q2's authority question
  applies to native, but ABC inherits whatever budget the shared driver uses).

## 5. Validation plan for the implementation

1. Re-run this probe corpus plus `frontend/tests/optimize.lua` and
   `tools/validate_optimizer_isa.lua`; require byte-identity of the second
   optimization and execution agreement in all four modes.
2. Assert the documented canonical fixture exactly (`docs/abc-opt.md:82-91`).
3. Assert the effect/trap coverage cases become optimized (not retained) and
   that the emitted modules still verify.
4. Assert `diamonds-13` no longer hits a path limit, and that output size is
   O(blocks × keys) on `diamonds-n` for n up to 16.
5. Keep the provenance invariant: every output instruction maps to an input
   instruction, and trap diagnostics map to the same input offset in both
   images.
