# Round 2 — candidate questions (ranked before investigation)

| # | Question | Materiality | Verdict |
|---|----------|-------------|---------|
| A | **Residue scope under a versioned ABC sink:** is ABC residue a function-wide value DAG (versions only select control/emission) or a per-version DAG (values cross version edges only as constants/C-homes)? | **high** — changes the ABC data representation, whether the shared key can be location-only, whether `binding.join` is transport or scheduling, and whether hash-consing, global use counting, hoisting and `mark_path_tree` survive at all. | **chosen** |
| B | Is a versioned (multi-copy) non-entry block representable and verifier-accepted, and does it avoid the path tree's growth (`ABC_OPTIMIZER_PATH_LIMIT`, ≤4096 leaves)? | high — if not representable, Q1 is answered "no" without a policy decision; if representable, it is the enabling fact for A. | investigated as part of A (encoding is not the constraint; the path limit is). |
| C | Is the approved native version budget (8 vs 10 at one PC) material to the architecture, or only a number to hand to the user? | medium — one owner is required either way, no concept changes. | rejected for this round; stays an explicit hard gate (Q2). |

A dominates because it decides the shape of the ABC binding and the meaning of the
shared key, and because the round-1 design asserted a per-version residue DAG for
ABC without evidence. B is a prerequisite fact, not an independent design choice.
