# Round 8 — key identity and the version-creation step

## Candidate questions (ranked)

**(A) Is a version key's identity its *value content* — constants plus binding
locations plus the continuation chain — or also the canonicalisation *mode*?
And does the creation step find an existing version after the budget widens the
key?** Materiality: **high**. The answer decides whether the design's central
bound (`versions(pc) <= families(pc) * budget`) and its invariant "each version
body is executed exactly once, module-wide" are true, and whether a
residual-function entry that is a loop header has one body or two. Both halves
are resolved by the incumbent's code and a small model.

**(B) Should the design inline a cross-function (mutual) tail-recursion cycle at
all?** (Q14.) Materiality: high for the concept count — inlining one needs a
module-wide cycle body with tail-call edges in the CFG, or exact keys at the
header with budget bloat. Evidence in passing (not pursued this round):
`optimize.c:108-114` defines `nested_eligible = recursive && component size == 1
&& !nontail`, so the incumbent inlines only the *same-function* self-tail cycle
and residualizes every mutual call, tail or not (`dag_tail`: `recursive &&
nested_eligible[fi]` is the only non-root inline path). That sharpens Q14: the
canonical output is a residual tail call, so the design is free to choose the
simple answer, but the choice is a policy question, not evidence.

**(C) Where do the per-pc heights, `CSET` targets and cycle-body/may-write sets
live (Q12)?** Materiality: medium (one-owner rule, compile cost). No new data;
not pursued.

Ranking: A first because it decides whether the stated algorithm can violate
the stated bound and invariant; B second; C third.

## Evidence read

### The incumbent's key equality compares a canonicalisation *mode*

`abc_symbolic_context_equal` (`src/symbolic.c:51-62`) compares `c_origin`,
`c_bias`, **`generic`**, the continuation chain and every value. `generic` is
not a value: `canonicalize` sets it from the *argument* (`context->generic =
(uint8_t)forget_constants`, `src/residual_builder.c:851-866`), and
`conform_generic` sets it to 1 (`src/residualize.c:161-169`). It is therefore a
"this key was produced by the widening" bit, not a property of the key's
content.

`abc_symbolic_context_family_equal` (`src/symbolic.c:64-72`) compares
`c_origin`/`c_bias`, the stack shape and the chain, and *not* `generic` or
`limit`. So the mode bit splits exact keys but not families: two versions can
live in one family with the same value vector.

The property the flag is supposed to mark is already derivable:
`canonical_generic_context` recomputes "every component is at its canonical
position" from the values (`src/symbolic.c:74-81`), and
`abc_symbolic_generic_context_equal` = that predicate + family equality
(`:83-85`). The incumbent stores the same fact twice and makes the stored copy
part of identity.

### The C sink's canonical forms are modes

`version_for` (`src/residual_builder.c:1088-1121`):

- `VERSION_LOOP_ENTRY` → `canonicalize(&key, 1)`: **all constants forgotten and
  `generic=1`**. So the C sink's loop entry *is* its generic key — the code
  reason round 5/6 measured that the C sink forgets loop invariants
  (`if(v_8 < v_5)`).
- `VERSION_RECURSIVE` (every backward edge, `edge_version_mode:1200-1206`) →
  `canonicalize(&key, 0)`, then `widen_recursive_key`, then the budget check →
  `canonicalize(&key, 1)` **and a second `find_version`**.
- exact edge → `canonicalize(&key, 0)`.

So the incumbent's general slot *is* looked up after widening, and the general
slot is a value vector (`all constants → homes`) plus the mode bit.

### Native looks up the derived predicate first

`version_for` (`src/residualize.c:408-419`) checks
`generic_context_equal(&v->in, in)` before exact equality; `edge()`
(`:424-438`) calls `conform_generic` (values → canonical homes, `generic=1`,
`limit` zeroed) when the family already holds `LIMIT-1` versions, then
`version_for`. So native also looks up after widening. Native additionally
requires `in->limit[s] >= v->in.limit[s]` for exact matches (`:411`): proven
stack headroom is a native **resource condition** that only *splits* a core key
(two versions, same core key, same family). It is not core identity and it is
counted by the same per-family budget.

### The design's algorithm block does neither

ARCHITECTURE round 7:

```
if a version with this exact key exists: return it
if family_count(pc, family(key)) >= budget - 1:
    key = all_locations(key)
v = create(pc, key); queue.push(v); return v
```

- The all-location key is never looked up. Past the budget, every *new* incoming
  key creates another version whose key is the all-location key — a duplicate
  key in the version table, growing without bound. The invariant "a version is
  created whenever an edge key differs from every existing version's key"
  (`ARCHITECTURE.md:96-98`) is violated by the algorithm that is supposed to
  implement it.
- The entry version is created outside `version_at`
  (`create(f.entry, generic_key(f))`) even though the entry key is a value key
  and the loop rule is a no-op on it (every component is already a location; a
  key with no constants has no constant to widen). The special path is
  unnecessary *and*, together with the mode bit, produces the duplicate below.

## Model

`experiments/8-version-model.py` (output `8-version-model.out`) abstracts a key
to one family + a 2-component value vector; a component is a constant (0, 7) or
the location at its position (L0, L1) — exactly what `canonicalize` produces.
`loop_invariant` replaces a constant in a may-write component; `all_locations`
replaces every constant by its position. It enumerates all arrival sequences
(all 9 vectors, any order, up to length 6) and walks the reachable version-table
states. Budget 3. (Excerpt; the full table, including the no-loop-rule
`content`/`as_written` row and the both-components may-write header, is in
`8-version-model.out`.)

```
scenario                                       identity algorithm   states max versions  same-value versions
plain edge, no loop rule                       mode     as_written     190            6                    5
plain edge, no loop rule                       mode     looked_up       82            3                    2
plain edge, no loop rule                       content  as_written     190            6                    5
plain edge, no loop rule                       content  looked_up       74            3                    1
loop header, may-write {1}                     mode     as_written      19            6                    5
loop header, may-write {1}                     mode     looked_up       10            3                    2
loop header, may-write {1}                     content  looked_up        8            3                    1
loop-header entry (residual entry at header pc) mode     as_written       2            2                    2
loop-header entry (residual entry at header pc) mode     looked_up        2            2                    2
loop-header entry (residual entry at header pc) content  looked_up        1            1                    0
```

Growth check for the lookup defect (plain edge, as-written, mode): arrival
sequences of length 4/6/8/10 reach 4/6/8/10 versions; the corrected content +
looked-up rule saturates at 3 = budget for every length.

Two independent defects, one identity question:

1. **Missing lookup after widening** — unbounded versions in a family; the
   "general slot" is not total. Fixed by looking up the widened key (the
   incumbent does this in both sinks).
2. **Mode bit in identity** — value-identical keys become distinct versions.
   Fixed by defining identity by content: constants, positions, frame
   coordinates, chain. The all-location property is the derived predicate
   "every component sits at its canonical position"; it is unique per family,
   so the budget fallback is a lookup of a value key.

The second defect is the one with a *design* consequence: when a residual
function's entry pc is a loop header (the documented counter's `loop` is function
2 and its header is that function's entry), the entry key is all-location and
the loop-invariant backedge key is all-location too (every component is already
a location, and may-write widening can only remove constants). Content identity
makes them the same version: **one body**, the entry version is the loop-header
version. The mode bit keeps them apart: two bodies, one family. The loop rule is
a projection that fixes the all-location key, so the two key rules compose with
no special case; the entry can be created through `version_at`.

Under the corrected rule the four properties the design claims hold:

- lookup-then-create at most once per key per pc (the version table is a
  function);
- at most `budget - 1` exact keys plus one all-location key per family, so
  `versions(pc) <= families(pc) * budget`;
- a function entry that is a loop header is one version and one body;
- native's headroom refinement splits a core key inside one family, so it is
  counted by the same budget and does not change the bound.

## Decision

Replace the round-7 algorithm block and key definition:

- **Key identity is content**: constants or the binding's location at each
  position, the frame coordinates, the continuation chain. No canonicalisation
  mode; "all-location/generic" is the derived predicate over the values, and the
  binding's two canonical descriptors produce value keys.
- **`version_at` looks up after every widening**, including the budget fallback;
  the all-location key is created at most once per family. The residual-function
  entry is created through `version_at` with the all-location value key (no
  special path), which is the loop-header version when the entry is a header.
- **The binding may refine the core key with a resource condition that only
  splits** (native: proven stack headroom, `residualize.c:411`), never merges;
  the split stays in one family and is bounded by the per-family budget.
- Record the two rejected formulations with the model numbers: lookup-before-
  widening, and the mode bit in identity.

Rejected/unchanged: Q2's per-family budget and Q15's answer stand (the family
is still shape + chain + frame coordinates); Q14's evidence is sharpened
(`nested_eligible` is size-1-only, so the incumbent residualizes mutual calls)
but its design choice stays open; Q12 is untouched.

Not established: whether any corpus module reaches the second defect's
configuration other than the documented counter's residual (non-inlined) entry
(that case is representable by hand-building a two-root module); the exact
native `limit` semantics (proven headroom vs required headroom — the code sets
it to the maximum required cells, `require_cells` `residualize.c:84-92`); and
the compile-cost share of the family scan (O(versions) per lookup, native's
`version_for` already linear).
