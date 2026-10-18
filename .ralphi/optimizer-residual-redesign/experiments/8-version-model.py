#!/usr/bin/env python3
"""Round 8: a model of the version-creation rule.

Question: is a version key's identity its *value content* (constants plus
binding positions plus the continuation chain), or also the canonicalisation
*mode* (`generic` in the incumbent's equality)?  And does the creation step
actually find an existing all-location version after widening?

The model abstracts a key to one fixed family (shape + continuation chain, so
family identity is constant here) and a 2-component value vector.  A component
is either a constant (0 or 7) or the binding location at that position (L0, L1)
-- exactly the incumbent's `canonicalize`, which maps every non-constant at
index i to home i (`src/residual_builder.c:851-866`).

Rules modelled:

  exact(v)                 identity
  loop_invariant(v, mask)  for i in mask: CONST -> L_i; others keep the value
  all_locations(v)         every CONST -> L_i (the incumbent also sets generic=1)

Identity variants:
  "mode"     key = (values, generic)   -- incumbent equality, symbolic.c:57-59
  "content"  key = values              -- generic derived from the values

Algorithm variants:
  "as_written"  lookup(key); if family_count >= budget-1: key = all_locations(key)
                create(key)                     <-- no lookup after widening
  "looked_up"   lookup(key); if family_count >= budget-1:
                key = all_locations(key); lookup(key); create(key)

Exhaustive search over arrival sequences (all 9 vectors, arbitrary order,
breadth-first over version-table states) reports the reachable maximum of
versions in one family and of versions that share the same value vector.
"""

from itertools import product
from collections import deque

CONSTANTS = (0, 7)
POSITIONS = (0, 1)
VECTORS = list(product(*(CONSTANTS + (f"L{p}",) for p in POSITIONS)))  # 9
BUDGET = 3
MAX_STEPS = 6


def is_const(v):
    return isinstance(v, int)


def positions(v):
    return tuple(v)


def loop_invariant(v, mask):
    return tuple(f"L{i}" if i in mask else x for i, x in enumerate(v))


def all_locations(v):
    return tuple(f"L{i}" for i in range(len(v)))


def generic(values):
    return all(not is_const(x) for x in values)


class Table:
    def __init__(self, identity):
        # (values, flag) -> version id; flag is 1 when created by a widening.
        self.identity = identity
        self.versions = []          # [(values, flag)]
        self.by_key = {}

    def key(self, values, flag):
        return (values, flag) if self.identity == "mode" else values

    def lookup(self, values, flag):
        return self.by_key.get(self.key(values, flag))

    def family_count(self):
        return len(self.versions)

    def create(self, values, flag):
        vid = len(self.versions)
        self.versions.append((values, flag))
        self.by_key[self.key(values, flag)] = vid
        return vid

    def snapshot(self):
        return tuple(sorted(((repr(v), f) for v, f in self.versions)))


def version_at(t, v, header_mask, variant):
    if header_mask is not None:
        v = loop_invariant(v, header_mask)
    if t.lookup(v, 0) is not None:
        return
    if t.family_count() >= BUDGET - 1:
        v = all_locations(v)
        if variant == "looked_up" and t.lookup(v, 1) is not None:
            return
        t.create(v, 1)
    else:
        t.create(v, 0)


def entry(t, v):
    """A residual function's entry version: the all-location key."""
    t.create(all_locations(v), 1)


def explore(identity, variant, header_mask, with_entry):
    start = Table(identity)
    if with_entry:
        entry(start, VECTORS[0])       # all arguments are binding locations
    seen = {start.snapshot()}
    frontier = deque([(start, 0)])
    max_versions = len(start.versions)
    max_duplicate_values = 0
    while frontier:
        table, depth = frontier.popleft()
        if depth == MAX_STEPS:
            continue
        for v in VECTORS:
            nxt = Table(identity)
            nxt.versions = list(table.versions)
            nxt.by_key = dict(table.by_key)
            version_at(nxt, v, header_mask, variant)
            state = nxt.snapshot()
            if state in seen:
                continue
            seen.add(state)
            frontier.append((nxt, depth + 1))
            max_versions = max(max_versions, len(nxt.versions))
            value_counts = {}
            for values, _flag in nxt.versions:
                value_counts[values] = value_counts.get(values, 0) + 1
            max_duplicate_values = max(max_duplicate_values,
                                       max(value_counts.values()))
    return len(seen), max_versions, max_duplicate_values


SCENARIOS = [
    ("plain edge, no loop rule", None, False),
    ("loop header, may-write {0,1}", (0, 1), False),
    ("loop header, may-write {1}", (1,), False),
    ("loop-header entry (residual entry at header pc)", (0, 1), True),
]

print(f"budget={BUDGET}  arrival vectors={len(VECTORS)}  "
      f"max sequence length={MAX_STEPS}\n")
header = f"{'scenario':46} {'identity':8} {'algorithm':11} " \
         f"{'states':>6} {'max versions':>12} {'same-value versions':>20}"
print(header)
print("-" * len(header))
for name, mask, with_entry in SCENARIOS:
    for identity in ("mode", "content"):
        for variant in ("as_written", "looked_up"):
            states, mv, md = explore(identity, variant, mask, with_entry)
            print(f"{name:46} {identity:8} {variant:11} {states:6d} "
                  f"{mv:12d} {md:20d}")
    print()

# The design's headline: versions(sc p) <= families x budget.  With one family
# and one arrival universe, a correct rule can never exceed BUDGET versions.
print("interpretation: 'as_written' grows with arrival variety because the")
print("all-location version is never looked up; 'mode' identity adds a second")
print("version that has the same value vector (the entry version and the")
print("loop-invariant backedge version).")
