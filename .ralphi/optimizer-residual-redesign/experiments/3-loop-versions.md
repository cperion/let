# Round 3 — loops are ordinary versions; the second measured ABC cliff

**Question pursued (ranked first of three below):** are ABC loop headers —
local backward branches, recursive self/tail loops, and virtualized loops —
ordinary versions under the shared driver, so that the whole `loop_candidate` /
`loop_home` / `loop_prologue` / `backedge` machinery retires? Enabling facts
tested in the same probe: can a versioned loop/join emission be verified and
executed, how is the ABC location vocabulary fixed by the verifier, and does the
incumbent optimizer really refuse loops?

**Candidate questions and ranking (materiality first).**

| # | Question | Materiality | Verdict |
|---|----------|-------------|---------|
| A | Are loop headers ordinary versions, deleting the ABC loop machinery? | **high** — removes a subsystem plus its state, names a new measured coverage cliff, and fixes the driver's edge-key rule (what a `version_at` mode is). | **chosen** |
| B | What exactly is a key: C-slot locations only (A/B drained), or all stack positions; and does it carry the continuation chain? | high — changes the ABC value representation and the join; mostly implied by the verifier and the measured shapes, with one correction (continuations are in the key). | investigated as part of A. |
| C | The native version-budget value (8 vs 10/16). | medium — one owner is needed either way; a user gate, no concept change. | rejected for this round; stays Q2. |

**Method.** No implementation change. I hand-assembled ABC modules with the
existing `tools/assembler.lua`, ran them through the existing loader/verifier and
all four execution modes (`build/abc run … --interpreted | --jit=threaded |
--compiled | --lazy`), ran the incumbent optimizer (`frontend/let/optimize.lua`)
on the same inputs, and ran the portable-C sink (`build/abc c`). Script:
`experiments/3-loop-join-probe.lua`; artifacts in `experiments/3-loop-join-out/`
(not committed). All fixtures are new; no existing corpus was modified.

## 1. Measured results

| case | what it is | input instr | abc-opt output | retained | idem | interp / threaded / compiled / lazy |
|---|---|---|---|---|---|---|
| `sum-source` | `head: …; …; JMP head` local loop, accumulator on A | 11 | 11 | **yes** | yes | 6 / 6 / 6 / 6 |
| `sum-fold-source` | same loop with `PUSH 5; PUSH 6; ADD; DROP` inside | 15 | 15 | **yes** | yes | 6 / 6 / 6 / 6 |
| `sum-versioned` | hand-built versioned emission of that loop: A/B drained to C, one shared header body, backedge = ordinary edge | 15 | 15 | yes | yes | 6 / 6 / 6 / 6 |
| `sum-versioned` (n=1, n=0) | boundary cases | 15 | 15 | yes | yes | 1 / 0 all modes |
| `pick-source` | diamond, computed value on A at the join | 12 | **10** | no | yes | 14 / 14 / 14 / 14 (and 15 for the other arm) |
| `pick-versioned` | hand-built versioned emission: both arms `CPUSH` the value, one shared body `CGET`s it | 15 | **10** | no | yes | 14 / 14 / 14 / 14 |
| `mismatched-join` | one arm pushes a C cell, the other does not, both reach one target | 10 | — | — | — | **rejected by the verifier** (`incompatible stack kinds or C layouts at join`) |

Two further measurements not in the table:

- **`opt(pick-source)` and `opt(pick-versioned)` are byte-identical** (94 bytes,
  each idempotent). The C-slot-drained shape and the A/B-carried shape converge
  on exactly one canonical module, which is also the module the path tree emits
  for the source. So the versioned join emission is *semantically canonical*, not
  a second normal form.
- **The portable-C sink compiles all three inputs** (`abc c`), and for the local
  loop it emits a block-based CFG whose predecessor edges pass values as block
  arguments, including a second version of the loop header reached by the
  backedge (`experiments/3-loop-join-out/sum-source.c`, `pick-versioned.c`). The
  versioned traversal of a loop is not a proposal: it is the shipped C sink.

## 2. Findings

1. **abc-opt refuses every function containing a local backward branch.** The
   refusal is structural, not incidental: `dag_control` rejects any control
   transfer with `control->fallthrough <= origin` or `target <= origin`
   (`src/optimize.c:281, 288`). The foldable `5 + 6` inside the loop is left
   untouched (15 → 15), while the same shape without the backward edge is fully
   optimized (`pick-source` 12 → 10). Loops are therefore a *second* measured
   coverage cliff, independent of the reported path-limit and
   branch-plus-effect cliffs: a function with one loop loses **all** dispatch
   reduction and folding.
2. **Native already runs the same loop; only abc-opt cannot.** `sum-source`
   executes correctly in `--compiled` and `--lazy`, and those modes have no
   interpreter fallback: `vm_image` calls `abc_residualize_module` and fails the
   load on error (`src/vm.c:168-171`). Native's `edge()` weakens constants for
   `target <= from` and has no loop-specific state
   (`src/residualize.c:424-438`); `discover_blocks` marks branch targets in both
   directions (`src/residualize.c:440-463`).
3. **A versioned loop/join shape is representable, verifiable and executable.**
   The hand-built `sum-versioned` has empty A/B at every version boundary, the
   loop-carried accumulator and counter in C frame slots, and one shared header
   body that reads `CGET1`; the backedge is an ordinary edge that rewrites the
   two slots. It verifies and returns 6/1/0 in all four modes. `pick-versioned`
   does the same for a join with a computed value. Nothing about loops requires
   the input's A/B stack layout, a prologue, or a named loop block.
4. **The verifier fixes the shape at every join, which is what makes the ABC
   location vocabulary well defined.** Branch targets may be backward
   (`src/verify.c:122-125`), but all incoming edges to a pc must arrive with
   identical A/B/C shapes (`src/verify.c:284`); the deliberately mismatched
   `mismatched-join` is rejected. Consequences: (a) at any version boundary the
   location of every value is fixed by the input program, not by the path, so
   the target key's C layout is a property of the target pc; (b) the number and
   kinds of A/B values drained into C slots are identical for every predecessor,
   so the join's arrangement is canonical; (c) no path-dependent placement
   choice can leak into a key.
5. **The C sink already implements the exact rule the driver needs.** Its
   `edge_version_mode` (`src/residual_builder.c:1195-1207`) classifies each edge
   as `PRESERVE` (constants + logical locations), `LOOP_ENTRY` (forget all
   constants when the target is a loop header, `:1090-1091`), or `RECURSIVE`
   (widen against an existing family, `:1102-1109`); `version_for` falls back to
   the canonical all-location key at `ABC_BLOCK_VERSION_LIMIT-1` (`:1110-1118`);
   `create_version` turns every non-constant key slot into a block argument
   (`:992-1062`). Its generated C for `sum-source` shows the loop as ordinary
   versioned blocks with edge arguments. The C sink computes loop headers in a
   private scan (`:2047-2110`); the shared driver must own that one boolean
   (derivable in the same pass as leaders/successors: a leader with an incoming
   edge whose source pc is >= it), not a second analysis.
6. **Continuations belong in the key, and the architecture says so incompletely.**
   Native's `version_for` compares the whole context, continuations included
   (`src/symbolic.c:39-54`); the key rule in `ARCHITECTURE.md` currently reads
   "constants plus binding locations", which omits the core-owned continuation
   chain. A virtual (inlined) entry is identified by its caller continuation
   chain; without that term two inline sites collide. The corrected key is
   **constants + binding locations + the continuation chain**.

## 3. Consequence for the design

- **Loops are ordinary versions.** The driver needs no loop concept: a loop
  header is one version for all its incoming edges (the generic key); a backedge
  is an edge; loop-carried values cross as the key's constants/locations (ABC: C
  frame slots written by the join and read by the target body). This deletes the
  ABC-only state and code: `loop_candidate`, `loop_target`, `loop_initial`,
  `loop_header[]`, `loop_home[]`, `loop_count`, `loop_captured`, `loop_stable`,
  `loop_temps`, `loop_prologue`, `backedge`, `nested_backedge`,
  `backedge_target` (`src/optimize.c:35-36, 334-347, 671-681, 752-765`), the
  root-backedge operand lowering (`:615-622`) and the DAG's `N_LOOP_HOME` node
  kind. Virtualized recursive loops become version edges to the callee's pcs
  inside the caller's residual function, identified by the continuation chain
  (the architecture's virtual-entry rule), not a local loop prologue.
- **The driver gains one concrete edge rule**, normalized from the two shipped
  variants (native `edge()` and the C sink's three modes): a plain forward edge
  keeps constants in the key; **an edge whose target is a function-entry pc
  (real, or virtual inside another residual function) joins that entry's
  lattice-keyed version** (`unreached → constant → unknown` per argument,
  re-executed until stable; the continuation chain distinguishes virtual
  entries, each with its own single version); **an edge into any other non-entry
  loop header uses the generic
  all-location key** (no constants); every other edge preserves constants; at
  the version budget the key becomes the same generic all-location key. Two
  triggers (loop header, budget overflow) share one canonical key form, so the
  C sink's per-slot `RECURSIVE` widening (`residual_builder.c:1102-1109`) and
  native's constant-weakening loop in `edge()` reduce to the same rule. The only
  specialization this can lose is a loop-carried constant, which is loop
  invariant by definition and belongs to an entry key anyway. The loop-header
  boolean is a shared module fact (one derivation in the same pass as
  leaders/successors: a leader with an incoming edge whose source pc is >= it),
  replacing the C sink's private scan (`residual_builder.c:2047-2110`). Native's
  forward edge into a loop header currently keeps constants and peels one
  iteration; both rules are correct and budget-bounded, so adopting the uniform
  one is raised as Q9 rather than decided silently.
- **The ABC location vocabulary is C frame slots, with A/B drained at the
  boundary.** This is now justified rather than asserted: the emitted body is
  shared by every predecessor and the ABC emitter can only address the C frame
  (`dag_value` rejects non-`CONST`/`BACKEND`, `src/optimize.c:165-170`;
  `emit_node` has no "already on the A/B stack" leaf, `:583-587`), while a body
  entered with a non-empty A/B stack would consume stack positions in the
  input's order and lose the scheduler's freedom to materialize multi-use
  values. Draining costs one push per live A/B value per edge, buys an empty,
  addressable entry frame, and — because the verifier fixes the join shapes — is
  identical on every predecessor. Rejected alternative: key A/B positions as
  locations and let the body read them in place; it needs a new entry-stack
  value kind, gives up scheduled placement, and buys no measured code quality.
- **Q1's case strengthens**: the recommendation to adopt versioned blocks now
  also removes the refusal to optimize any function with a local loop (measured
  above), not just the 2^n path duplication and the branch+effect cliff.
- **No new hard gate for ABC's loops**; the loop-entry rule is a narrow
  version-policy refinement for native (native currently keeps constants on a
  forward edge into a loop header and peels one iteration; the C sink forgets
  them there). Both are correct and budget-bounded; the uniform rule is simpler
  and already shipped in the C sink. This is raised as Q9 rather than decided
  silently, because it changes native's version selection.

## 4. What the numbers do and do not establish

- Established: representability and execution of versioned loop/join emissions;
  the loop coverage cliff; the verifier's join-shape constraint; the C sink's
  existing versioned loop; the canonical byte identity of the two join shapes.
- Not established: a versioned ABC *emitter*'s byte determinism/idempotence in
  general. The strongest available evidence is structural: after one versioned
  pass every block has exactly one incoming key (versions partition edges by
  key), so a second pass finds the same version per block and, with a
  deterministic worklist and the same emitter, emits the same bytes; the
  measured byte identity above shows the two boundary conventions converge on
  one canonical module, and every measured incumbent output remains idempotent.
  A prototype versioned sink is still the only way to prove this end to end.
- Not established: the exact join instruction sequence for the ABC C-slot drain
  (push vs in-place store) and its C-traffic cost on real modules. The join must
  set the target key's layout; whether it pushes once and stores later, or
  pushes per edge, is an emission choice with a measurable code-size/traffic
  tradeoff, and the target layout is now known to be a function of the target pc
  and A/B shape (finding 4).
- Budget authority (Q2) is unchanged and now bites the shared driver: the C sink
  uses `ABC_BLOCK_VERSION_LIMIT-1 = 7` family slots (`src/residual_builder.c:1111`),
  native uses `ABC_EXECUTION_VERSION_LIMIT = 16` (`src/residualize.c:10,414`),
  and the approved policy is 8 total per original PC (`REFACTOR.md:811`).
