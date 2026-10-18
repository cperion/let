# Architecture

Status: candidate (round 12). Derived from `CONTRACT.md`, checked against the
code, and corrected by the round-2 … round-12 probes. Rationale and citations:
[experiments/1-rederive.md](experiments/1-rederive.md);
[experiments/2-abc-versioned-sink.md](experiments/2-abc-versioned-sink.md);
[experiments/3-loop-versions.md](experiments/3-loop-versions.md);
[experiments/4-entry-lattice.md](experiments/4-entry-lattice.md);
[experiments/5-loop-key.md](experiments/5-loop-key.md);
[experiments/6-may-write.md](experiments/6-may-write.md);
[experiments/7-budget.md](experiments/7-budget.md);
[experiments/8-key-identity.md](experiments/8-key-identity.md);
[experiments/9-tail-cycle.md](experiments/9-tail-cycle.md);
[experiments/10-call-continuation.md](experiments/10-call-continuation.md);
[experiments/11-residual-root-set.md](experiments/11-residual-root-set.md);
[experiments/12-refusal-owner.md](experiments/12-refusal-owner.md).

The one-line design: **execute ABC semantics once, symbolically, per version;
module facts and version identity have one owner; a sink owns only residue.**
A version body ends at a control transfer; **every control-transfer successor is
a keyed edge, and a call is an effect unless it is inlined.** **The set of
residual functions is derived, not precomputed: a binding-declared root set
(what that sink can be entered into from outside) plus every callee a residual
call or a retained body names.** A sink that cannot record a body may **retain**
its owner: the owner's entry version survives with the source body as residue,
the owner's other versions are dropped, and the owner's `CALL`/`TCALL` targets
become entry versions; a sink that cannot emit a source body (portable C,
native) rejects the build instead. A version key is
**constants plus the binding's locations plus the core's
continuation chain** — never sink residue identity and never a canonicalisation
mode: **identity is content.** A **family** is the key with the constants
removed: the stack shape, the frame coordinates and the continuation chain.
**A key is exact: a version is created when the content differs, never widened
by a fixpoint.** The all-location ("generic") key is a *value* key — every
component at its canonical position — and is therefore unique per family.
**Recursion is inlined only when it is a same-function tail cycle**, so a
recursive function that stays residual carries **no entry constants at all** —
the call ABI supplies locations, and the loop rule can only preserve constants
already present in a key.

There are exactly **two key rules and two bounds**:

1. **A residual function's entry version is the generic all-location key.** The
   entry key is the call ABI, not a canonicalization of an incoming edge key: a
   residual call (or the outside world) materializes argument values into
   binding-defined locations, so the callee's own residual function starts generic
   and has exactly one entry version. A virtual (inlined) entry is an ordinary
   version.
2. **Every edge into a loop header takes the loop-invariant key** (every component
   whose value can change on a cycle through the header becomes a location,
   everything else keeps its constant), including an inlined callee entry that is a
   cycle header. Both rules are static functions of the key and module facts, so
   nothing is ever rebuilt.
3. **The per-family version budget** replaces a key with its all-location value
   key. It is per family because a value widening can never merge two continuation
   chains: `versions(pc) <= families(pc) * budget`. The widened key is looked up
   before a version is created, so the family's general slot exists at most once.
4. **Inlining is bounded separately** by the number of distinct continuation
   families at the target pc (`K`); the fallback is a residual call, because only a
   call decision can remove a chain. `families(pc) <= K`.

That is what lets every sink keep residue per version, it makes **loops ordinary
versions**, and it makes **every version body execute exactly once, for the whole
module**.

## Essential model

A residualizing compiler is five things:

1. **Module facts** — immutable, computed once per module: function ranges and
   signatures, block leaders (function entries, branch/switch targets and their
   fallthrough pcs; **a call-return pc is not a leader**, round 10), direct-call
   graph, recursive/tail-only/nontail components (they also feed the inline rule),
   unknown-call reachability, **addressable entries** (the functions named by
   exports, code-address relocations and revision-7 lifecycle C-entry
   relocations — the only ways a function entry identity reaches outside the
   module), **loop headers** (a leader with an
   incoming edge whose source pc is at or after it) and, per loop header, its
   **backedge instructions** and **cycle
   body** (the pcs on a path from the header to a backedge source, excluding the
   backedge instructions), plus the per-pc A/B/C heights and `CSET` target slots
   it needs (Q12). The cycle body and the heights yield the loop's **may-write
   set**, which is what makes the loop-invariant key computable before the body
   is walked. The may-write set is a *heuristic*: exact keys keep any widening
   sound, so a conservative set costs code quality, never meaning.
2. **Symbolic machine** — A/B/C stacks of `constant | home | sink value`, C frame
   coordinates, explicit continuations, transfer dispatch. This is the only
   semantics and, for native, the register allocation.
3. **Context key** — canonical identity of a specialization: the constants, the
   positions of everything else, the frame coordinates and the continuation chain.
   Identity is **content**: how a key was produced is never part of it (so the
   all-location property is a derived predicate, not a stored flag). A **family**
   is the key with the constants removed (stack shape + frame coordinates +
   continuation chain); it is the unit of the version budget, because key widening
   only removes constants. The continuation chain is never widened: it names the
   return site of an inlined call, so it is identity, not a location. **The binding
   defines what a location is** (native: register/homing; portable C: version
   argument; ABC: C-frame slot) and supplies its **may-write predicate** for the
   loop-invariant canonicalization. Key equality is version identity and is
   exact; the binding also supplies one canonical all-location value form, used as a
   residual function's entry key and by the per-family budget. The continuation chain is
   core-owned because it identifies virtual (inlined) entries and return sites.
4. **Version** — `(pc, key, owning residual function)` plus the sink's residue for
   the straight-line run from `pc` and its outgoing edges. The unit of code and
   the unit of work. Residue is per version; **a key never contains sink residue
   identity**, so no sink needs a cross-version value graph to compare keys.
   A body ends at a control transfer (every successor is a keyed edge), at a
   leader reached by straight-line fallthrough, or at a terminator; **it does not
   end at a call** (round 10). **A loop is not a version shape**: its header is a
   version keyed by the loop-invariant key, its backedge is an edge, and
   loop-carried values cross as the key's constants or locations. A single-entry
   loop header has exactly one version per family (one for a function's own,
   non-inlined body). **A residual function is the owner of an entry version**:
   the binding's root set gets one before any body is walked, and every other
   entry version is created by the residual call (or retained body) that names it
   (round 11). **A retained owner has exactly one version — its entry — whose
   residue is the source body**; the owner's walk is abandoned at the refusing
   instruction (round 12).
5. **Binding (sink)** — the target mechanism: the location vocabulary, record/emit
   residue, materialize join values, emit a control transfer to a version handle,
   place and publish code, the **entry-root set** — the functions this sink
   must be able to enter from outside the traversal (ABC: the addressable
   entries, or every function when the module declares none; native: every
   function today, Q19; portable C: every function its profiles accept) — and
   whether it can emit a **verbatim source body** when it cannot record an owner
   (ABC: yes; portable C and native: no, a refusal fails the build; round 12).
   Never semantics and **never a key**: the binding
   receives version handles, it does not compute them (round 10).

Invariants:

- each version body is walked at most once and each **emitted** body exactly
  once, module-wide; a refused owner's bodies are discarded, never re-walked, and
  its entry's residue becomes the source body; residue is never rebuilt, so no
  SSA/IR round trip and no placement reconstruction can exist;
- **a key contains only constants, binding locations, the frame coordinates and
  the continuation chain**; sink value identity (`abc_symbolic_value.reg`) never
  reaches a key, and **no canonicalisation mode reaches a key** (the incumbent's
  `generic` flag is a stored duplicate of the derived "all components at their
  canonical positions" predicate, `symbolic.c:57-59, 74-85`), so residue can be
  per version and a sink never needs a function-wide value graph for key equality;
- the core never inspects residue; `abc_symbolic_value.reg` is opaque to it;
- version creation order is a function of module bytes and facts (deterministic):
  **every root entry version is created before any body is walked** — the sink's
  root set is what can be entered from outside, so it must exist up front (round
  11). Every other entry version is created by the construct that needs it: a
  residual call creates its callee's entry version at the call instruction, and a
  refused owner creates one for each of its direct `CALL`/`TCALL` targets from the
  direct-call-graph fact. Such a call
  names its target itself, so nothing depends on another walk's progress; the
  *set* of versions is order-independent (content keys) and the queue is FIFO
  with a fixed arm order, so the creation order is deterministic;
- **refusal is owner-granular and atomic**: a sink refusal is discovered by the
  walk (the same instruction set is recordable when its operands fold and
  unrecordable when they do not, measured round 12), so it is never predicted.
  When it happens, the driver abandons that owner: every version owned by it
  except its **entry** version is removed from the table and queue; the entry
  version keeps its handle and its residue becomes the source body (the binding
  emits it verbatim, with relocated `CALL`/`TCALL` displacements); and the driver
  creates entry versions for the owner's direct `CALL` and `TCALL` targets from
  the direct-call-graph fact (a refused body cannot inline, so each of its calls
  is residual). No other owner's body is rebuilt: a cross-owner reference is
  always an **entry** version, because a function is entered from outside only at
  its entry pc, and interior versions are created only by edges inside the
  owner's own walk. Publication is therefore **owner-granular**: a binding that
  can refuse stages an owner's regions until its walk (and all the versions it
  creates) completes, and a refused owner's regions are discarded before
  publication. A binding that cannot emit a verbatim source body cannot retain;
  its refusal fails the build (portable C rejects residue outside its recorded
  subset, native fails the image; round 12).
- **a key is exact, and the version table is a function.** A version is created
  whenever an edge key differs from every existing version's key at that `pc`;
  **every widening is followed by a lookup**, so a widened key that already has a
  version returns it and the key is never created twice. No version key is widened
  by a fixpoint. There are two key rules, one budget and one non-key bound:
  (i) **a residual function's entry version is the binding's generic
  all-location key.** This is the call ABI, not an edge canonicalization: a
  residual call (or the outside world) materializes argument values into
  binding-defined locations, so the callee's own residual function starts generic
  and has exactly one entry version — correct for every caller and every entry
  address (`verify.c:131-134`). A virtual (inlined) entry is an ordinary version;
  (ii) **every edge into a loop header** takes the **loop-invariant key**: the key
  with every component whose value can change on a cycle through the header
  replaced by a location, and every other component unchanged, because the header
  body is one version that runs every iteration (see below). This includes a
  virtual entry into an inlined callee whose entry pc is a cycle header — the
  documented counter's `loop` is function 2 and its header is that function's
  entry, so a pc-scoped entry rule would make the measured P shape unreachable;
  **the two rules compose**: the all-location key is a fixed point of the
  loop-invariant rule (it has no constant to widen and every component is already
  a location), so a residual function whose entry pc is a loop header has **one**
  version there, which is both its entry version and its loop-header version, one
  body. The entry is created through `version_at` like every other version (a
  root's before any body is walked, a residual callee's at its call, round 11);
  (iii) at the **per-family version budget** a key is replaced by its all-location
  value key, which is looked up before creation. This is total inside a family,
  because the stack shape, the frame coordinates and the continuation chain are
  family identity and are never widened; it cannot merge two families, so it
  bounds only `versions per family`: at most `budget - 1` exact keys plus one
  general slot per family (model: an arrival sequence of any length saturates at
  `budget`; without the lookup it grows without bound,
  `experiments/8-key-identity.md`);
  (iv) **inlining is bounded separately.** A non-tail direct call is inlined only
  while its target pc has fewer than `K` distinct continuation families (the
  driver counts families; the binding supplies call eligibility); otherwise the
  call is emitted as an **in-body residual call** to the callee's entry version
  (result values come back as binding locations; no continuation is pushed and no
  key crosses). No key widening can
  remove a continuation chain, so this is the only bound on the number of families
  at a pc: `families(pc) <= K` and `versions(pc) <= K * budget`.
  **There is no entry join, no entry-fact lattice, no call facts, no widening
  fixpoint and no residue rebuild.** The measured specialization that the old
  lattice provided comes from inlining instead: an inlined call is a **virtual
  entry**, an ordinary version whose key carries the caller's constants and whose
  continuation chain identifies the return site;
- **bodies, edges and effects**: a version body is one straight-line walk and
  ends at (a) a control transfer — every successor (branch taken *and*
  fallthrough, switch arms, a virtual call's callee entry, a virtual return's
  return pc) is a **keyed edge** created by the driver's one
  `edge_to(target, context)` — (b) a leader reached by straight-line fallthrough,
  which is also an edge, or (c) a terminator. **A direct call is not a control
  transfer and creates no keyed edge**: it is an **effect inside the body**, like
  a foreign call, whose target is the callee's single entry version (arguments by
  the call ABI), whose result values are binding locations, and after which the
  walk continues at the call's return pc in the *same* body. For a residual call
  there is no return edge, no return-pc version and no return key, and a
  call-return pc is not a leader (round 10; measured: ABC emits the post-call
  computation directly after
  `CALL_A` and the C sink keeps the call and its use in one block — native's
  call-return block and post-call version body are retired,
  `experiments/10-call-continuation.md`). Only an **inlined** call transfers
  control: the machine pushes the continuation, the driver calls `edge_to` for the
  callee entry, and the binding jumps. The continuation chain therefore names only
  inlined call return sites;
- **only a direct call names a version.** A call whose target is not a static
  function entry is an in-body effect with **no** target version: an indirect
  `CALLI`/`TCALLI` whose target the binding can resolve statically becomes the
  corresponding direct call (`symbolic.c:443-457`, the `effect.direct` path);
  otherwise its target is a binding location and the callee is entered at runtime
  through the image's entry table, which is why code-address relocations are
  entry roots (native: `residualize.c:598-650`, measured 42 in all four modes on
  round 11's `reloc-root`; round 12). A foreign call is the same kind of effect
  and names the binding's extern (`symbolic.c:530-538`). Neither is ever inlined
  and neither creates or names a version; an ABC body containing an unresolved
  indirect call is refused and therefore retained (the ABC sink has no
  indirect-call residue, `optimize.c:305-306,726-749`);
- **call decision**: a direct call is either an inlined virtual entry (the
  callee's pc becomes a version in the caller's residual function, under the
  caller's continuation chain) or a residual in-body call reaching the callee's
  single generic-key entry version. **The core owns the recursion decision:** a
  call is inlined only when (i) its callee is acyclic, or (ii) it is a tail call whose
  callee is the calling function itself, in a call component of size 1 that
  contains no nontail call (the incumbent's derived `nested_eligible`,
  `optimize.c:108-114`). Every other
  recursive call — same-function or mutual, tail or not — is a residual call.
  The binding's rule may only *narrow* this (frame materialization, effects,
  hidden results); acyclic inlining is bounded by the driver's family count at
  the target pc (Q10), and the fallback is a residual call, which drops the
  chain. A recursive cycle that contains a nontail call cannot be inlined: every
  inlined layer grows the continuation chain, which is part of key identity, so
  the family never converges (`symbolic.c:39-75`). Tail calls push no
  continuation, so a same-function self-tail loop inlines as a loop header and
  keeps its invariant constants under the loop rule. A **cross-function**
  (mutual) tail cycle is not inlined: it has no per-function cycle body or
  transport fact, so the exact/budget rule would widen its invariants away, and
  inlining it changes the documented three-function/`TCALL` shape; a residual
  cross-function cycle is an ordinary residual call (round 9,
  `experiments/9-tail-cycle.md`). The resulting rule is part of the design, not
  a limitation of one sink: **only inlined recursion keeps constants; a residual
  recursive function's entry is the all-location key and its loop rule is a
  no-op.** The measured cost of not keeping that precision: the canonical
  mutual fixture's `odd` body goes 9 → 11 instructions (module 21 → 23) and the
  `PUSH8_A 9`/`PUSH8_A 10` assertions at `frontend/tests/compiler.lua:803`
  stop holding — part of Q1/Q7's output gate;
- **edge-key modes are the whole loop rule**: a plain forward edge keeps
  constants; an edge into a loop header takes the loop-invariant key; at the
  per-family version budget the key becomes the all-location key. The
  loop-invariant key keeps the entry key's constant on a component iff the loop
  cannot change the value the header sees there. Its **body is the cycle body,
  not a pc interval** (measured: an interval includes live exit code and the
  frame-replacing backedge; `experiments/6-may-write.md` §2–3), and the
  **backedge instruction is the join, not a body write**: a self-tail `TCALL`
  replaces the local frame from its argument vector (`docs/spec.md` "Calls"), so
  its writes define the target key exactly like `binding.join`. The static
  predicate is binding-owned and one pass: **ABC** — C slot `k` is may-write iff
  the cycle body's minimum C height is `<= k` or the cycle body contains a `CSET`
  targeting `k` (ABC keys are C-only, and a call cannot touch the caller's slots
  below its base: a callee frame starts at the caller's call-time C height and a
  callee addresses only its own frame, `symbolic.c:467-484`, so no call clause is
  needed); **native** — the same C clause plus A/B depth `d` iff the cycle body's
  minimum A/B height is `<= d` (native loop backedges are plain jumps).
  A same-function self-tail backedge is position-preserving (measured: the callee
  `C_k` receives selected-stack depth `k`, all four modes); a computed or
  re-ordered argument vector is widened at the edge. The may-write set is a
  **heuristic, not a correctness condition**: over-widening loses constants,
  under-widening only makes the backedge create another version, bounded by the
  per-family budget and the inline bound, and exact keys keep every version body
  correct either way. **A
  loop header is a version like any other**: one version per distinct
  loop-invariant key per family (one for a function's own, non-inlined body), its backedge is an edge, and
  its body keeps every constant the loop does not overwrite (measured: the
  documented counter's one body with `BLTUI_A 50`/`ADDI_A 7`). There is no loop
  state, no loop prologue, no backedge lowering and no path-shaped
  control-flow representation;
- **a residual-function entry has exactly one version**, keyed by the generic
  all-location value key because the call ABI materializes arguments into
  locations; the same is true of a module entry (export, relocation, C entry).
  The entry key is not a canonicalization of any incoming edge key. Root entries
  exist before any body is walked; a residual call creates its callee's entry
  version at the call, so the callee's body is queued then and walked once. No
  join is computed, so no re-execution and no publish-then-modify exists, and
  **the residual-function set needs no separate computation**: it is exactly the
  set of functions that own an entry version. A body the binding cannot record is
  **retained at owner granularity**: the walk is abandoned, the entry version is
  the owner's only surviving version and its residue is the source body, every
  direct call in that body is a residual call (a refused body cannot inline, hence
  no inline decision), and the driver creates entry versions for the body's
  direct `CALL` and `TCALL` targets from the direct-call-graph fact (round 12;
  `direct_target` accepts both kinds, `optimize.c:54-56,782-787`). A binding that
  cannot emit a verbatim source body (portable C, native) rejects the build
  instead of retaining. The ABC writer emits exactly the entry-version owners,
  renumbers them and rewrites CALL/TCALL displacements (measured: 2 → 1 function
  when a callee is fully inlined, 3 → 2 with a relocation root, round 11; a
  retained owner keeps its verbatim body while a sibling owner still optimizes,
  round 12);
- native consumes the symbolic cache directly: no stored native residual IR.

## Concepts

The reader must hold exactly these five, in this order: **facts → machine →
key → version → binding**. Everything currently spelled "path tree", "version
table", "directive driver", "leader discovery", "loop prologue" is an instance of
one of them; "argument fact fixpoint", "call facts" and the dynamic loop join
(`loop_captured`/`loop_stable`) are not — they are deleted mechanisms, because
every key is computed statically: entries at the all-location key (the call
ABI), loop headers at the loop-invariant key, everything else exact, and the
number of inlined call instances is bounded separately (the only non-key bound).

## Data representation

- `abc_symbolic_context` unchanged in shape: three stacks of
  `abc_symbolic_value {kind, stack, dst_stack, reg, home, dst_home, constant}`,
  `c_origin/c_bias`, continuation stack, limits, `generic` (the last is a
  *derived* flag, see below).
- **Key** = the context after the binding's canonicalization: **constants,
  locations, frame coordinates (`c_origin`/`c_bias`) and the continuation chain**.
  Non-constant values are replaced by the binding's location descriptor before any
  lookup or comparison; the continuation list survives canonicalization (it is not
  a location). Keys are compared for **content**: how a key was produced is never
  part of it. The incumbent's `generic` flag is not an identity field; it is the
  derived predicate "every component sits at its canonical position" — the
  all-location form — which the core can recompute (`symbolic.c:74-85` first
  computes exactly that, and `symbolic.c:57-59` then compares the stored flag as
  well). The binding supplies two descriptors: its **canonical all-location value
  key** (the entry key and the per-family budget; unique per family) and its
  **loop-entry form** (the loop-invariant key: a component the loop's cycle body
  may write or the backedge transports non-identically becomes a location,
  everything else keeps its constant).
  The core does not assume `HOME(stack,index)` for every slot (that is the native
  form only).
  A binding may add a **resource condition that only splits** a core key (native:
  a version created with proven headroom `L` is reused only by a context with at
  least `L` headroom, `residualize.c:411`); a split stays inside one family and is
  therefore counted by the same per-family budget. A binding never merges two core
  keys.
- **ABC canonical form**: A/B empty, every value either a constant or a **C-frame
  slot**. This is forced, not chosen: join targets must arrive with identical
  A/B/C shapes (`verify.c:284`), so the set of live values at a target is a
  property of the input pc; the body is emitted once per version and the ABC
  emitter can only address the C frame (`dag_value` accepts only
  `CONST`/`BACKEND`, `optimize.c:165-170`), so the join drains live A/B values
  into the target key's slots and the body reads them with `CGET`. Because the
  verifier fixes the join shape, the number and kinds of live values agree on
  every edge. The **layout** (which of them are C slots) is per version: a
  version is its own emitted label, so two versions at the same pc may keep
  different components as constants, and each emits its own prologue.
- **Version table** keyed by (owning residual function, pc, key); the owning
  function is identity for sinks whose code is placed in per-function ranges
  (ABC, portable C: one run per module, `owner` selects the code region), and is
  implicit for native (one code arena; a module-scope table). The set of
  (owner, entry pc) pairs **is** the residual-function set: a residual function
  has exactly one entry version; a single-entry loop header has exactly one
  version per family (its loop-invariant key, which *is* the entry version when
  the entry pc is the header); every other version at a pc exists because some
  edge's exact key differed. A **family** is (stack shape, frame coordinates,
  continuation chain) — the key with the constants removed; it is the unit of the
  version budget and of the inlining bound. The version table has at most
  `budget - 1` exact keys plus one all-location key per family per (owner, pc).
  The ABC/C binding emits one function per entry-version owner (the emitted
  module's function table); native's entry table is its `entry_roots`. A
  **retained owner** has exactly one version, its entry, whose residue is the
  source instruction stream; its direct `CALL`/`TCALL` targets are entry-version
  owners too, so they survive renumbering.
- **Residue is sink-owned, per version, and never shared**: native — none
  (emitter packets are consumed immediately; locations are registers); portable
  C — one `residual.asdl` block per version with block arguments as the join
  representation; ABC — one bytecode region per version, with that body's
  expression DAG scheduled locally, plus provenance and residual calls. ABC's
  only stable location is a **C-frame slot**; the join writes it (`CPUSH`/`CSET`)
  and the target body reads it (`CGET`). Constants stay in the key and need no
  store. Residue is staged **per owner**: a refused owner's staged versions are
  discarded and its entry's residue is replaced by the source body; no region
  belonging to another owner is rebuilt.
- Invalid states: a version without an owner, a key containing sink residue
  identity, a key whose identity depends on how it was canonicalized (a mode bit),
  two versions with the same key at one pc, an edge whose target key does not
  match the materialized location set, a sink value inspected by the core, a
  loop-specific version shape, a join that bypasses `binding.join`, a
  residual-function entry version that is not the all-location key, a function
  emitted without an entry version, an entry version for a function that no root,
  residual call or retained body names, **a keyed
  edge or a version at the return pc of a *residual* call (it is an effect; a
  virtual return's return pc is an ordinary edge target)**, an indirect or
  foreign call naming a target version, a version of a retained owner other than
  its entry, a cross-owner edge to an interior version, a body of an owner
  published before a refusal of that owner is resolved, a binding that computes
  or compares a key, or a residue region **outside a refused owner** rebuilt
  after publish are unrepresentable by construction.

## Operations and algorithms

```text
version_at(pc, key, owner):                     # the only version constructor;
    # key is already canonical (constants, locations, frame, chain)
    v = lookup(pc, key)                         # content identity
    if v exists: return v
    if versions_in_family(pc, family(key)) >= budget - 1:
        key = all_locations(key)                # a value key, unique per family
        v = lookup(pc, key)                     # the general slot may exist
        if v exists: return v
    v = create(pc, key); queue.push(v); return v

edge_to(target, x, owner):                      # the only keyed-edge constructor
    key = canonicalize(x)
    if target is a loop header: key = loop_invariant(key)   # may-write heuristic
    return version_at(target, key, owner)

# family(key) = stack shape + frame coordinates + continuation chain; constants
# are the only part a widening can remove, so a budget is per family, never per
# pc.  Every widening is followed by a lookup: the version table is a function.
# binding predicate used by loop_invariant:
#   may_write(component, header) -- true iff the loop's cycle body can change the
#   value the header sees at that component.  Static, from module facts: the
#   cycle body, per-pc A/B/C heights, CSET targets and the backedge transport
#   identity.  A heuristic: exact keys keep it sound either way.

entry_version(f):                               # the call ABI's key; the loop
    return version_at(f.entry, all_locations, f)  # rule is a no-op on it, so a
    # header entry is this same version.  Idempotent: one entry version per f.

run(module):
    for each f in binding.entry_roots(module):   # the only pre-pass: what the
        entry_version(f)                         # sink can be entered into from
        # outside (root set; Q18).  Non-root callees need no pre-pass.
    while queue not empty:
        v = queue.pop(); x = copy(v.key); pc = v.pc; owner = v.owner
        loop:
            if pc != v.pc and leader[pc]:       # straight-line fallthrough
                t = edge_to(pc, x, owner); binding.join(v, t); binding.jump(t); break
            exit = symbolic_dispatch(pc, x, ALL)
            CONTROL|TERMINATED -> binding.finish(v); break
            BLOCK|BOUNDARY     -> pc = machine.pc; continue
            FAILURE            -> fail(v)           # allocation/limit/verifier error
            REFUSED            -> if binding.retain(owner):   # ABC: entry residue
                                      # becomes the source bytes (binding-owned)
                                      drop_versions(owner, except = entry(owner))
                                      for c in direct_targets(owner):   # CALL+TCALL,
                                          entry_version(c)              # module fact
                                      break
                                  else: fail(v)   # C/native: no verbatim residue

# driver-owned transfer hooks; the binding supplies values and code placement and
# receives version handles (it never computes a key):
#   control:  taken = edge_to(taken_pc, x, owner); fall = edge_to(fallthrough, x, owner)
#             binding.branch(v, relation, taken, fall)   (jump: one arm; switch:
#             one edge per arm plus the fallthrough)
#   return:   virtual:  binding.return(v); t = edge_to(frame.return_pc, x, owner);
#                       binding.jump(t)                   (continuation popped)
#             terminal: binding.finish(v)
#   call:     decide at the call instruction (core rule + binding narrowing +
#             distinct_families(callee entry) < K):
#               inline:   the machine pushes the continuation; t = edge_to(callee
#                         entry, x, owner); binding.join(v, t); binding.jump(t)
#               residual: t = entry_version(callee); binding.residual_call(v, t);
#                         the results are binding locations; pc = return_pc;
#                         continue in this body.  The call creates its own target,
#                         so no entry pre-pass is needed and no walk-order
#                         dependency exists.
#               indirect: if the binding resolves the target to a known function
#                         entry, the machine turns CALLI/TCALLI into the direct
#                         call/tail above and this rule applies; otherwise
#                         binding.indirect_call(v) -- NO target version, the
#                         results are binding locations, the callee is resolved at
#                         runtime through the entry table, and the walk continues
#                         (a tail form just ends this body).
#               foreign:  binding.foreign_call(v) -- NO target version, the extern
#                         is the binding's; results are binding locations.
#   refuse:   a binding refused the body's residue (unsupported operation, not an
#             allocation/limit failure).  The owner is the unit: binding.retain
#             installs the source bytes as the owner entry's residue and returns
#             true (ABC), and the driver drops every other version of that owner
#             and expands the owner's direct CALL/TCALL targets from module facts;
#             a binding with no verbatim body returns false and the build fails
#             (portable C, native).  Publication is per owner, so nothing of the
#             refused owner was published and no other owner's body is rebuilt.
```

- **One edge constructor, one version constructor.** `edge_to` applies the
  binding's canonicalization, the loop-invariant rule for a loop-header target,
  the per-family budget (with the lookup-after-widening), and content identity;
  `version_at` is the table operation. The binding never sees an edge key: a
  control transfer, a virtual return, a virtual call and a fallthrough all arrive
  at it as version handles (`binding.branch/switch/return/jump`). The incumbent
  computes target versions in three private places (`native_emit_control`'s
  `edge`, the C sink's `make_edge`, the ABC path tree), which is the drift the
  shared rule replaces (round 10, `experiments/10-call-continuation.md`).
- **A direct call never ends a body.** The machine's residual-call form returns
  the result values (binding locations) and continues at the return pc
  (`symbolic.c:220-259`); a foreign call has the same shape. Only an inlined call
  transfers control (continuation pushed, `edge_to` for the callee entry). So the
  caller's body is emitted with the call in the middle, no return-pc version, no
  return key, and the binding's post-call obligations are exactly the foreign
  call's: materialize values live across the call, hand back result locations,
  reset its placement state. Native's `K_CALL`-return block marking
  (`discover_blocks`) and the post-call version bodies it creates are retired.
- **Only a direct call has a target version.** An unresolved indirect call and a
  foreign call are in-body effects with no target version
  (`binding.indirect_call`/`binding.foreign_call`): the target is a binding
  location and the callee is resolved at runtime through the entry table, which is
  why code-address relocations are roots (round 12; measured native `CALLI`
  execution in all four modes, `experiments/12-refusal-owner.md`). A statically
  resolved `CALLI`/`TCALLI` is turned into the corresponding direct call by the
  machine (`symbolic.c:443-457`) and then follows the direct-call rule. Neither
  form is ever inlined; the ABC sink records no unresolved indirect call, so such
  a body is refused and retained. The driver must never receive a key, a version
  or an inline decision for them.
- **Entry versions are created where they are needed.** The binding's
  `entry_roots` are entered from outside the traversal, so their versions exist
  before any body is walked; a residual call creates its callee's entry version at
  the call (`entry_version`). Nothing else is precomputed, so the
  residual-function set has no separate computation and no function-level worklist
  (`experiments/11-residual-root-set.md`). A refused owner is emitted verbatim, so
  its direct `CALL`/`TCALL` targets are created from the direct-call-graph fact
  (both kinds: `optimize.c:54-56,782-787`) and every one of them is residual by
  definition — this is the incumbent's `retain_function` + `append_unknown_call`
  rule (`optimize.c:781-787`), and it is what keeps the ABC writer's "call target
  must be live" check unreachable.
- **Refusal is owner-granular and publication is per owner.** A refusal may arrive
  after some versions of the owner were already built (the entry body may have
  completed; an interior body is where the unsupported operation is), so the
  driver drops every version of that owner except its entry, which keeps its
  handle and receives the source body as residue. The driver then expands the
  owner's direct `CALL`/`TCALL` targets from the direct-call-graph fact, and the
  owner is never walked again. No other owner's body is rebuilt because the only
  cross-owner version is an entry version (a function is entered from outside only
  at its entry pc; interior versions are created only inside its own walk). A
  binding that can refuse must therefore stage an owner's regions until its walk
  completes; the incumbent ABC/C sinks already do (the ABC sink builds one
  function in a local buffer and replaces or discards it as a unit,
  `optimize.c:726-787`; the C builder finalizes all of a function's versions
  together, `residual_builder.c:2399-2400`). Native may publish per body because
  it cannot refuse. A binding with no verbatim residue (portable C, native) fails
  the build on a refusal (round 12).
- **Join materialization** (`binding.join`) is where incoming symbolic values
  meet the target key: native homes/re-homes registers, C emits block arguments,
  ABC arranges the target's C-frame slots (push a drained A/B value or store it
  in place) and the target body reads them with `CGET`. It may change the
  operand-stack shape to the target key's canonical shape. It consumes symbolic
  values and emits target transport — it is not a second allocator. No join ever
  changes an existing version's key.
- **Loops are ordinary versions**: a backedge is an edge through `edge_to`
  exactly like a forward edge. Every edge into a loop header is canonicalized to the
  loop-invariant key, so a single-entry loop header has one body per family; a
  function's own non-inlined body has exactly one, and when the entry pc *is* the
  header that body is the entry version (the all-location key is a fixed point of
  the loop rule). The join stores the loop-carried values for the next iteration,
  and the body keeps every constant whose storage the loop does not touch
  (`experiments/5-loop-key.md`). The invariant is a static join, not a fixpoint:
  no version is ever widened after creation, so nothing is rebuilt.
- **Call policy** (the core owns recursion; the binding narrows eligibility; the
  driver supplies the bound): a direct call is inlined as a virtual entry (an
  ordinary version at the callee's pc under the caller's continuation chain —
  constants cross) exactly when it is **acyclic** (the binding may still refuse:
  frame materialization, effects, hidden results) or a **same-function
  self-tail** call — callee == calling function — in a component of size 1 with
  no nontail call. Every other recursive
  call is an **in-body residual call** to the callee's single all-location entry
  version, which the call site itself creates (`entry_version`; round 11);
  **no constants cross**, so recursion that stays residual has no entry
  constants at all (round 9). Nontail recursive cycles must be residualized because inlining
  grows the continuation chain without bound; a cross-function tail cycle is
  residualized for the same reason plus the missing cross-function cycle body
  (Q14). Acyclic inlining is bounded by the number of distinct continuation
  families already at the target pc: below `K` the call inlines, at `K` it
  becomes a residual call (Q10). That is the only bound on families, and
  therefore on versions, at a pc. A **self-tail** call creates no new family
  (tail calls push no continuation, `symbolic.c:486-499`): it becomes a loop
  header whose backedge canonicalizes to the loop-invariant key, i.e. a
  one-version cycle (this derives the incumbent's self-recursive inline rule).
  The ABC sink must inline pure acyclic direct calls: `docs/abc-opt.md:82-91`
  fixes that canonical output. **This rule is about direct calls only**: an
  unresolved indirect call or a foreign call is never inlined and never names a
  version (above); a call inside a retained body is emitted verbatim and is
  residual by construction.
- **Entry keys**: a residual-call entry, and every root entry (export,
  code-address relocation, C entry), is a single version keyed by the
  all-location value key, because the call or the outside world supplies the
  argument values in binding-defined locations and the body must be correct for
  all callers. Root entries are created through `version_at` before any body is
  walked; a residual call creates its callee's entry through the same function at
  the call, and a refused owner's entry does so for each of its direct
  `CALL`/`TCALL` targets (from the direct-call-graph fact). The loop rule
  leaves an all-location key unchanged, so an entry that is a cycle header has
  one body, not two. The set of residual functions is therefore derived (the
  entry-version owners) and is never computed; **only the root set is declared**,
  because only it can be entered from outside the traversal. This is the call ABI, not a
  canonicalization of an incoming key; no join, no per-argument lattice, no
  re-execution. A virtual entry (inlined call) is a normal version (exact or
  loop-invariant key); an inlined self-tail loop is a self-edge on it and keeps
  the invariant constants. A **residual** self-tail function is the same rule
  with no constants to keep: its entry is the all-location key, so its backedge
  returns to the same version and its invariants are read from locations. This
  is the price of one body per entry (round 9, `experiments/9-tail-cycle.md`);
  it is not recoverable by a key rule, because a key holds only what the call
  ABI supplied and the loop rule can only preserve constants already present.
- **Bounds**: three independent limits, each with an explicit fallback. (1) The
  **per-family version budget** (the approved policy number; the all-location
  value key is the family's "general slot"; Q2 decides number *and* scope) —
  fallback: the all-location key, looked up so it exists at most once and is
  total inside the family (at most `budget - 1` exact keys plus the general slot).
  (2) The **inlining bound `K`** on distinct continuation families per target pc
  — fallback: a residual call, because no key widening can remove a chain.
  (3) The binding's own vtable/state limits. Together: `families(pc) <= K`,
  `versions(pc) <= K * budget`, and total work is bounded by
  `sum_functions (1 + K) * code(f) * budget`. The ABC
  `ABC_OPTIMIZER_PATH_LIMIT` is a path-tree bound and retires with the path tree
  if Q1 is approved; it is not a module code-size budget either way.
- **Complexity**: facts O(V+E) plus one reverse walk per loop header bounded by
  its cycle body (a nested loop is walked once per enclosing header); one walk per
  version body; per-body key comparison and scheduling; the family count and the
  inlining bound are version-table queries, not passes; **one module-scope
  version worklist, no function-level worklist and no fixpoint over functions**,
  so no function is ever walked twice and a function outside the root set costs
  nothing until a residual call or retained body names it. No pass re-walks
  emitted code and no pass is exponential in branches or loop iterations.

## Interfaces and naming

- Core: `symbolic.c` (+ generated handlers) owns machine, folding, captures,
  continuations, module facts (loop headers, backedge instructions, cycle bodies,
  per-pc heights and `CSET` targets, loop may-write sets), and the key *rule*:
  content equality (constants, locations, frame coordinates, chain), family
  counting (shape + frame coordinates + chain), the lookup-after-widening
  discipline, the loop-invariant canonicalization, the per-family budget, the
  **recursion/inline decision** (acyclic, or same-function self-tail; every other
  recursive call is residual), and the two canonical descriptors (all-location
  value key and loop-entry).
- Driver: one sink-agnostic unit, conceptually
  `abc_residual_binding { canonicalize(key), all_locations(key),
  loop_entry(key, facts), may_write(component, loop), key_refinement(key),
  entry_roots(module), open/join/finish, jump(version),
  branch(relation, taken, fallthrough), switch(arms, fallthrough), return,
  publish(owner), call_eligible(call), residual_call(call, target_version),
  indirect_call(call), foreign_call(call), retain(owner) -> bool }` +
  `abc_residual_run(binding, module)`. The binding supplies its location
  vocabulary (which also defines what "may write" means), its two canonical
  value forms, an optional resource refinement that only splits a core key
  (native headroom), whether an acyclic call may be inlined (effect and frame
  exclusions — recursion is the core's decision), its **root set**
  (`entry_roots`: the functions it must be able to enter from outside the
  traversal), and whether it can emit a **verbatim source body** (`retain`: true
  only for ABC). The driver owns traversal, content equality, the family count,
  the lookup order, the inlining bound (`K`), **every version lookup, the set of
  residual functions, and the owner-granular refusal** — it supplies
  `version_at`/`edge_to`/`entry_version` to its own control/return/call/refuse
  hooks, so the binding receives version handles and never computes or compares a
  key (`edge_to` applies the loop rule and the budget). `residual_call` is for a
  **direct** call only; `indirect_call`/`foreign_call` name no version. The name
  is the guarantee: a binding binds mechanisms, the driver owns specialization.
  The binding's `publish` is per owner: a refused owner's staged regions are
  discarded and its entry gets the source body; nothing another owner holds is
  rebuilt.
- Bindings: native/threaded emitter (two output bindings of one residualizer),
  portable-C residue builder → C writer, ABC emitter/writer. The ABC writer emits
  exactly the functions that own an entry version and renumbers them (its
  function table is the residual-function set); native's entry table is its
  `entry_roots` (every function today, Q19).
- Retired paths (named now, deleted in the cutover):
  the ABC **argument-fact machinery**: `ArgumentFact`, `argument_fact`,
  `record_call`/`ResidualCall.facts`, `activate_function_facts`,
  `join_call_facts` and the `dirty` fixpoint loop in `optimize.c:850-873`, because
  a residual-call entry is the generic key (the call ABI) and no key widens; the dead
  `abc_residual_analysis_activate_facts`/`_join_call_facts` lattice and the
  `abc_residual_options.argument_facts` hook in the portable-C builder (no caller
  today); `optimize.c`'s call-graph copy; and — conditional on Q1 — the
  whole path-tree machinery: `simulate_tree`/`DagTree`/`emit_tree`/
  `emit_phi_tree`/`mark_path_tree`/`branch_rematerializable`/
  `ABC_OPTIMIZER_PATH_LIMIT`, and the `noncall_effect` refusal of branchy
  effectful functions; **the ABC loop machinery** (`loop_candidate`/
  `loop_target`/`loop_initial`/`loop_header`/`loop_home`/`loop_count`/
  `loop_captured`/`loop_stable`/`loop_temps`/`loop_prologue`/`backedge`/
  `nested_backedge`/`backedge_target`, `N_LOOP_HOME`, `emit_tree`'s backedge
  arms and `emit_root_backedge_operands`), because loops are ordinary versions
  and the loop-invariant key replaces the dynamic loop capture;
  `residual_analysis.c` as a separate owner; the optimizer's **function-level
  worklist** (`needed`/`dirty` and the per-function loop in `optimize.c:862-873`)
  and the ABC writer's `mark_live_functions` closure pass (`optimize.c:809-817`),
  because the entry-version owners are the residual-function set (round 11;
  `experiments/11-residual-root-set.md`); `symbolic.c` DFS reachability
  helpers; `residualize.c` and `residual_builder.c` private drivers, leader
  discovery, loop-header scan and key canonicalization (their policy becomes the
  shared rule; each keeps only its location vocabulary); and the traversal-time
  continuation scan inside native's `inline_candidate` (`residualize.c:401-406`),
  which becomes the driver's family count with the same `K` fallback. **The
  per-sink computation of edge targets**: native's `edge`/`version_for` calls
  inside `native_emit_control`/`native_emit_edge`/`native_emit_return`
  (`residualize.c:492-570, 592-598`) and the C sink's `make_edge`/`version_for`
  inside `on_control`/`on_edge`/`on_return`/`on_tail`
  (`residual_builder.c:1212-1348, 1980-2046`), because the driver's single
  `edge_to` owns every keyed edge and the binding receives version handles.
  **Native's call-return block marking and the post-call version bodies it
  creates**: `discover_blocks` sets `block[next]=1` after every `K_CALL`
  (`residualize.c:445-462`) and `compile_version` ends the body at any block, but
  a residual call is an in-body effect (round 10,
  `experiments/10-call-continuation.md`). **The
  stored canonicalisation-mode bit in key identity**: `abc_symbolic_context_equal`
  compares `generic` (`symbolic.c:57-59`), which `canonicalize`/`conform_generic`
  set from the widening argument (`residual_builder.c:856`,
  `residualize.c:168`); the design keeps the value transformation (constants →
  positions) and drops the bit from identity, recomputing the all-location
  property from the values (as `canonical_generic_context` already does,
  `symbolic.c:74-85`). **The portable-C builder's post-walk function salvage**:
  the per-function `supported` flag as a build product
  (`residual_builder.c:2400`), `function_references_unsupported` and
  `remove_unsupported_dependencies` (`:2469-2526`) and the `finalize_program`
  omission of unsupported functions (`:2533,2537,2560`), because the target
  policy is rejection, not omission (`docs/symbolic-vm.md:164`), and a walked body
  must never name a function the sink did not emit (round 12). The round-11
  `retain(function, direct_targets)` target list retires too: the driver derives
  a retained owner's `CALL`/`TCALL` targets from the direct-call-graph fact.
  `docs/abc-opt.md:25,100`
  documents the retired call-fact behavior and must be updated in the same
  cutover; that is part of Q1's gate, not a silent policy change.
- Kept, because it is required, not duplication: the single-entry-version rule for
  address-only calls (ABC `CALL` can only target a function entry); the per-sink
  location vocabulary; sink residue itself; the bounded inline rule.

## Rejected alternatives

- **Shared generic residue IR for all sinks** — violates the native constraint
  and the approved REFACTOR target (ABC/C may hold build-time residue; it must
  never stage native emission).
- **Keep three independent traversals** — one idea in three implementations;
  already drifted (leaders, version budget), compile-time cost not block-bounded.
- **Keep the ABC path tree as a "policy" inside the shared driver** — path
  layout is recursive (contiguous per-path emission, local displacements), so
  the traversal would not actually be shared. Measured: 2^n suffix duplication
  and a whole-function cliff at 4096 paths.
- **Function-wide ABC value graph with sink value identity in version keys** —
  rejected round 2. It needs dominance-safe cross-version home reuse
  (`mark_path_tree`/`branch_rematerializable` are tree-shaped), keeps O(n²)
  hash-consing and per-path use counting, and buys nothing for the measured
  blow-up, which is control duplication. The portable-C sink already proves that
  constants + locations dominate the same cases (`diamond`, `choices`) with
  per-version residue.
- **Per-edge rematerialization/hoisting of pure expressions across versions** —
  deferred, not needed for the measured corpus. Reintroducing it would
  reintroduce the dominance question the per-version model exists to avoid;
  only a measurement showing added C traffic on real modules would justify it.
- **Keying ABC A/B stack positions as locations (no C-slot drain)** — rejected
  round 3. The verifier fixes the shape at every join (`verify.c:284`), so the
  input's A/B positions *are* available, but the body is emitted once for all
  predecessors and a value below the entry top can only be consumed after the
  values above it, so the emitter would need a new entry-stack value kind and
  give up scheduled placement of multi-use values; the drain costs one push per
  live A/B value per edge and buys a clean, addressable entry frame. Measured:
  `opt(source)` and `opt(C-slot-drained)` are byte-identical
  (`experiments/3-loop-versions.md` §1), so the drain loses nothing.
- **A loop-specific version shape or prologue** — rejected round 3: measured
  representability and execution of loops as ordinary versions
  (`experiments/3-loop-versions.md` §1–2), and the C sink already emits loops as
  versioned blocks. Keeping `loop_home`/`loop_prologue` would re-introduce
  path-shaped state that only exists because the path tree cannot represent a
  backedge.
- **Generic (all-location) key at a loop header** — the round-3 choice,
  rejected round 5. It is sound and one body, but it forgets every constant whose
  value is known before the loop and invariant inside it, including the documented
  counter's bound and step: measured 12 vs 10 instructions per iteration in the
  probe loop, and the shipped C sink emits `if(v_8 < v_5)` where the invariant
  version emits `BLTUI 120` (`experiments/5-loop-key.md` §1–2). ABC bytecode and
  native code have no downstream optimizer to recover it.
- **Exact keys at a loop header** — the round-4 rule, rejected round 5
  for ABC and native. A constant loop-carried component produces one version per
  iteration until the per-family budget, at which point the all-location key makes the
  *hot* body generic: the documented fixture's `BLTUI_A 50` / `ADDI_A 7` then
  disappear from the emitted loop and `frontend/tests/optimize.lua:502,505`
  fails. Measured emission: 7 folded header versions + a generic tail, 29
  instructions vs 16 for the loop-invariant key, and its executed-instruction
  advantage (152 vs 188 at trip count 18) vanishes above about 36 iterations
  (`experiments/5-loop-key.md` §2).
- **The pc-interval body plus a CALL/TCALL argument clause (round 5's concrete
  predicate)** — rejected round 6. An interval `[header .. largest backedge
  source]` contains live exit code (measured: a loop whose exit path pops the
  frame marks every slot may-write while the cycle writes one,
  `experiments/6-may-write.md` §3) and contains the self-tail `TCALL` whose frame
  replacement gathers arguments at C base 0, so the clause marks all four slots
  of the documented counter may-write and the loop-invariant key collapses to the
  all-location key (0 constants kept vs 2 under the cycle-body rule, §2) — i.e.
  the documented P shape round 5 used as its justification becomes unreachable.
  The call clause is also unnecessary: callee frames start at the caller's
  call-time C height and are frame-local. The interval's only surviving
  justification was that dead code over-widens, but the exit path is not dead.
- **Widen the continuation chain so that the per-pc budget can merge call
  instances** — rejected round 7. The chain names the return site of an inlined
  call; widening it would change where the body returns, and every
  canonicalization in the tree is value-only (`symbolic.c:45-53`;
  `residual_builder.c:851-868`). The budget is therefore per family (shape +
  chain), and families need a separate inline bound.
- **A literal "total versions per pc" budget enforced by key widening** —
  unenforceable: a total cap must be shared between constant families and chains,
  which changes what the all-location fallback guarantees. Raised as Q2's scope
  decision; the design's recommendation is the per-family budget plus `K`.
- **A pc-scoped residual-call-entry canonicalization** — rejected round 7. The
  documented counter's loop header *is* the inlined callee's function entry
  (`experiments/6-may-write-out/counter.dis`: function 2 starts at the header pc
  `0x29`), so a rule keyed on "the target pc is somebody's function entry" would
  take the all-location key there and make the measured P shape
  (`BLTUI_A 50`/`ADDI_A 7`) unreachable. The generic key belongs to the callee's
  own residual-function entry, which is the call ABI.
- **Look up the incoming key only, then create the widened key (the round-7
  algorithm block)** — rejected round 8, measured. The family's general slot is
  never found, so each distinct incoming key past the budget creates another
  version whose key is the all-location key: a duplicate key in the version
  table, and `versions per family` grows without bound (model: 4, 6, 8, 10
  versions for arrival sequences of length 4, 6, 8, 10 at budget 3, against 3 for
  the corrected rule; `experiments/8-key-identity.md`). Both incumbent sinks look
  up after widening (`residual_builder.c:1110-1119`; `residualize.c:410, 436`).
  This also falsified the invariant "a version is created whenever an edge key
  differs from every existing version's key", which the algorithm failed to
  implement.
- **Keep the incumbent's `generic` canonicalisation-mode bit in key identity** —
  rejected round 8, measured. `abc_symbolic_context_equal` compares the stored
  flag (`symbolic.c:57-59`) although `canonical_generic_context` recomputes the
  same property from the values (`:74-85`). Value-identical keys then differ:
  at a loop-header PC entered by a residual call, the all-location entry key and
  the loop-invariant backedge key have the same value vector (a residual entry
  supplies only locations, and may-write widening can only remove constants) and
  differ only in the flag → two bodies for one family (model: 2 versions, 2
  sharing a value vector, against 1 / 0 with content identity). The design makes
  "all-location" a predicate over the values, so the entry version *is* the
  loop-header version.
- **Put native's proven-headroom condition into the core key** — rejected
  round 8: it is a binding-owned resource fact (a version body compiled with
  headroom `L` may only be entered where `L` cells are proven available,
  `residualize.c:411`). It only splits a core key, so it belongs to the binding;
  the split stays in one family and is counted by the same per-family budget.
  Core identity stays content-only, so the driver can compare keys without
  knowing a sink's resource model.
- **A static capped call-path multiplicity fact as the inlining bound** —
  recorded alternative (round 7): order-independent and no version-table scan,
  but a new module fact plus a saturating DP over the call DAG, over-counting
  paths that will be residualized for other reasons. The driver's local family
  count at the target pc gives the same invariant (`families(pc) <= K`) with one
  counter; revisit only if the order-dependence matters.
- **A per-residual-function version budget as the only inlining bound** — the
  round-6 sketch: it does bound total work, but it stops unrelated calls once the
  function is large and is not the quantity the incumbent measures
  (`inline_candidate` counts continuations at the target pc). Kept as the
  coarser fallback if the per-pc count proves awkward.
- **Unroll a constant-trip loop up to the per-family budget (exact prefix + 
  loop-invariant tail)** — the best measured code for small constant loops
  (152 vs 188 executed instructions at trip 18) but it deliberately emits up to
  `budget` loop-header bodies, which contradicts the compile-time and code-size
  goals and the "one version per loop header family" invariant. Recorded as a possible
  later *binding-side unrolling choice* with its own bound, not as the key rule.
- **A single lattice-keyed entry (monotone join + function-granular rebuild)** —
  rejected round 4. It is the only mechanism that can carry constants across a
  residual call into a function with one entry address (measured: `mutual`
  folds `100-7` and `200-7`, widens `i`; `experiments/4-entry-lattice.md` §2.2–3),
  and it costs a second worklist level over residual functions, per-argument
  call facts, and whole-function discard/rebuild when the join widens (the
  incumbent: `optimize.c:850-873`; measured that a first-key-only design would
  have folded `i == 0` and been wrong). Its cited witness (the documented
  recursive counter) is invalid: the counter is fully inlined (53→18
  instructions, one function, no `CALL_A`), and a two-root module produces two
  independent specializations rather than a join. A generic entry key deletes the
  whole mechanism and keeps every version body single-execution; the lost
  cross-call constants are recoverable at virtual entries (inlined calls), which
  the ABC sink must have anyway for `docs/abc-opt.md:82-91` — **but only for
  calls the design inlines**. Round 9 corrects that justification with a live
  in-repo witness: `frontend/tests/compiler.lua:790-804` (and
  `docs/abc-opt.md:100`) pins a residual mutual tail SCC whose invariant argument
  is folded at both callee entries (`PUSH8_A 9`, `PUSH8_A 10`). A residual entry
  is the all-location key, and the loop rule can only preserve constants already
  in a key, so no key rule recovers those constants; inlining the SCC would
  change the documented three-function/`TCALL` shape. The measured price of
  deleting the lattice is the fixture's `odd` body 9 → 11 instructions (module
  21 → 23) and the two immediate assertions at `compiler.lua:803`; that output
  change is part of Q1/Q7's gate. The lattice nevertheless remains the only
  mechanism that carries caller constants across a residual call, so it stays
  the explicit fallback if the user requires `docs/abc-opt.md:100` for
  non-inlinable recursive calls. Round 5 separates the *loop-granular* part: the
  join a loop header needs is computed statically from the loop's may-write set,
  so no dynamic join or rebuild is needed anywhere, including loops.
- **Inline every direct call, unbounded** — the canonical `sq(a)+sq(b)` fixture
  requires inlining pure acyclic calls, and a same-function tail cycle can be
  inlined, but any other recursive layer grows the continuation chain that is
  part of key identity (`symbolic.c:39-75`), so those calls must stay residual;
  and because each nontail call site is a distinct key family at the callee's pc,
  inlining across a call chain multiplies. A per-residual-function version budget
  with a residual-call fallback is required (Q10).
- **Inline a cross-function (mutual) tail cycle as a version cycle** — the
  round-7/8 option left open as Q14; rejected round 9, measured. It is the only
  way inlining could carry the SCC's invariant constants (a residual call's entry
  is all-location, so a residual entry has none and the loop rule is a no-op
  there), but it needs a module-wide cycle body plus a cross-function transport
  relation to keep the constants in the hot body — the per-family budget's
  all-location slot would otherwise widen them, exactly as round 5's exact-key
  loop does (7 folded header versions + a generic tail, 29 instructions vs 16)
  — and it replaces the documented three-function/`TCALL` output with one
  function and a duplicated cycle per call site. Measured on the canonical
  mutual fixture: the residualized form keeps 3 functions/3 `TCALL` and costs 2
  instructions for the unfolded invariant when the entry is generic
  (`experiments/9-tail-cycle.md`). The design keeps the incumbent's derived
  rule instead: the only inlined recursion is a same-function self-tail cycle.
- **A residual call ends the body; the return pc gets a version keyed by the
  post-call context** — rejected round 10, measured. Today's native sink does
  exactly this (`discover_blocks` marks every `K_CALL` return pc; `compile_version`
  ends the body at any block), but the return pc of a call is reached by that one
  call site, so the boundary is not a join and buys no sharing; it adds one label,
  key and join per residual call (the fixture's 2 / 1 non-tail residual calls
  are 2 / 1 post-call version bodies inside the measured 19 / 12 eager bodies,
  `experiments/10-call-continuation.md`). The shared machine's residual-call form
  already continues in the body with result locations, and native already
  continues in-body after a clobbering `FCALL`, so the cache reset does not need a
  boundary. It would also add a return-key rule that the call ABI already supplies.
- **A residual call as a keyed edge into the callee entry plus a return edge** —
  rejected round 10. One entry version serves every caller, so the return cannot be
  encoded in its key; the return site would have to be a body-specific label
  chosen by the call site. Only an inlined call is a control transfer with a
  keyed edge (continuation pushed, callee entry version).
- **Let each binding compute the target version of a control arm** (the
  incumbent's model) — rejected round 10: `native_emit_control`/`native_emit_edge`
  call `edge`/`version_for`, the C sink's `on_control`/`on_edge`/`on_return`
  call `make_edge`/`version_for`, and the ABC path tree duplicates arms as paths;
  three copies of the key rule, already drifted, against the design's one-owner
  invariant. The driver's `edge_to` owns every arm and the binding receives
  version handles.
- **Let a body continue through the fallthrough arm of a branch** (trace layout) —
  not adopted round 10: it would save one version per branch, but the taken arm
  still needs a version, so the body would have two kinds of successors and need
  intra-body labels; the C and native sinks already emit both arms as versions,
  and the per-family budget accounts for them. Recorded as a possible binding-side
  layout choice, not a key rule.
- **Precompute the residual-function set as a static closure over the call
  graph** (root set plus every direct callee) — rejected round 11, measured. It
  keeps functions that end up fully inlined: the ABC sink's own rule is the
  *post-walk* set (a fully inlined callee is deleted, measured 2 → 1 functions),
  so a static closure would change output and compile bodies nothing can enter.
  The same fixture's raw native image shows the cost: 4 eager bodies for a
  two-function module whose only call is inlined, against 1 body for the
  optimized one-function module (`experiments/11-residual-root-set.md`).
- **Walk every module function and let the writer drop the dead ones** — the
  static-closure failure in its worst form: it pays a full symbolic walk for every
  function that can never be emitted, contradicting the compile-time goal; the
  incumbent already avoids it by walking only root-activated functions
  (`optimize.c:862-873`). The one case where every function really is a root is a
  module that declares no export/relocation/C entry (measured 2 → 2), and there
  the design keeps every function.
- **Require all entry versions to exist before any body is walked (round 10's
  form)** — superseded round 11: it needs the residual-function set up front,
  which is the walk's output, and the incumbent pays for it with a second,
  function-level worklist. Only the binding's root set needs to exist up front;
  a residual call can create its own target because its key is fixed (the call
  ABI) and content identity makes the lookup order-independent.
- **Clone a residual function per entry key** — gives residual calls constants
  without a join, but adds a function-cloning concept, duplicate exports and
  relocation/identity questions for code addresses, callables and provenance for
  a bounded gain.
- **Decide recordability before the walk with a function-level predicate** —
  rejected round 12, measured. The same float instruction kinds are recordable
  when the walk folds their operands (`fold-float`: 10 → 4 instructions,
  `PUSH8_A 8; RET`) and unrecordable when it does not (`retain-float`: the whole
  owner is byte-identical, including an independently foldable `3+4` witness). A
  pre-walk "contains a float/pow operation" predicate would retain the foldable
  function and lose the fold; the ABC sink's float/pow handlers are absent and
  the machine turns only the *folded* path into a successful emission
  (`symbolic.c:205-215,304-310`, `optimize.c:744-749`). The refusal is therefore
  discovered mid-walk and must be handled at owner granularity.
- **Publish each version body immediately and revoke the owner's bodies on a
  later refusal** — rejected round 12. An owner's entry body may already be
  published when an interior body is refused; revoking the interior bodies leaves
  a mixed function (a versioned entry or a verbatim entry with unreachable
  interior labels), and revoking published code violates the "no rebuild after
  publish" invariant. The incumbent ABC and C sinks already build a function's
  residue as one unit (`optimize.c:726-787`, `residual_builder.c:2399-2400`), so
  publication is per owner.
- **Retain verbatim in every binding** — rejected round 12. Verbatim residue is
  an ABC capability: the portable-C writer has no source-body mode and rejects
  the residue it cannot record (measured exit 1 on the memory/callable modules;
  `docs/symbolic-vm.md:164`, `residual_c.c:1232-1237`), and the native residualizer
  has no per-function fallback (any failure fails the image,
  `residualize.c:794-799,822-841`). The driver rule is "retain only if the binding
  declares the capability, otherwise fail".
- **Silently omit a function the sink cannot record and every caller (the
  incumbent portable-C salvage)** — rejected round 12. It is a **post-walk**
  closure over functions and call lists (`residual_builder.c:2502-2533`), the same
  shape round 11 deleted for the ABC writer; it changes the emitted program's
  function set silently, and the documented portable-C policy is rejection, not
  omission. Under the driver contract, a refusal is either a verbatim owner
  (ABC) or a build failure, so no walked body can name an absent function.
- **ABC stored SSA/IR + normalization** — forbidden by the contract.
- **Delete the portable-C sink** — plausible simplification, but a scope decision;
  raised as a question, not decided.

## Evidence

- Round-12 measured refusal/publication probe (four hand-built modules through the
  existing assembler, verifier, abc-opt, the C writer and all four execution
  modes): `experiments/12-refusal-owner.md`, `.lua`, `.out`, artifacts in
  `experiments/12-refusal-owner-out/`. Key facts: a function whose float operands
  are non-constant (`FADD`/`F2IS` over float arguments) is emitted **byte-identically**
  (raw == opt, a fixpoint) and its independently foldable `3 + 4` witness stays
  unfolded — the whole owner is retained — and it executes in
  interpreted/compiled/lazy/threaded (`8`); the **same** float instruction kinds
  with constant operands optimize 10 → **4** instructions (`PUSH8_A 8; RET_A 0 1`),
  so recordability depends on the walk, not on a function-level instruction scan;
  a module with a retained float owner next to a foldable sibling emits the owner
  verbatim (2 → 2 functions) while the sibling optimizes to `PUSH8_A 7; RET_A 0 1`,
  and both exports execute in all four modes (`calc = 8`, `good = 7`) — refusal is
  owner-granular and publication is per owner; round 11's `CALLI` body is retained
  byte-identically and native executes it in all four modes (`42`), while the ABC
  sink has no indirect-call residue (`dag_indirect` succeeds only for a statically
  known callable and `callable_safe` is 0, `optimize.c:305-306`). The C writer
  **rejects** every one of these modules (exit 1, "portable C currently supports
  only the integer/static profile"), so it never retains and never reaches the
  incumbent's silent per-function drop; native has no per-function fallback
  (`residualize.c:794-799,822-841`). Code: the ABC function is built in a local
  buffer and replaced or discarded as a unit (`optimize.c:726-787`), the C builder
  finalizes a function's versions together (`residual_builder.c:2399-2400`) and
  its `supported` drop/closure is a post-walk salvage (`:2469-2533,2537,2560`),
  and `direct_target` records both `K_CALL` and `K_TCALL`
  (`optimize.c:54-56,782-787`), closing round 11's open `TCALL`-root item.
- Round-11 measured root-set probe (four hand-built modules through the existing
  assembler, verifier, abc-opt, the portable-C writer and all four execution
  modes, plus a native entry-table probe against `build/libabc.a`):
  `experiments/11-residual-root-set.md`, `.lua`, `.out`, artifacts in
  `experiments/11-residual-root-set-out/`, `experiments/11-entry-table.c`. Key
  facts: abc-opt emits 2 → **1** function when the only call is an inlined acyclic
  helper (helper deleted, value 42 in all four modes), 2 → **2** when the same
  module declares no export (all functions kept, helper body still emitted
  verbatim although its call folded to `PUSH8_A 42`), 2 → **2** for a nontail
  self-recursive callee (the `CALL_A` survives and the caller continues after it
  with `CPUSH_A; CGET0_A`), and 3 → **2** for a code-address relocation: the
  unreferenced `dead` function is dropped while `target`, reachable only through
  `CALLI`, is kept (42 in all four modes). The incumbent's rule is
  `mark_live_functions` = exports ∪ code-address relocations ∪ revision-7 C-entry
  relocations, then a transitive closure over the *emitted* call lists, where a
  retained function contributes every direct call (`retain_function` →
  `append_unknown_call`, `optimize.c:781-785, 809-817`); with all three root
  tables empty every function is live (`:826`); the documented rule is
  `docs/abc-opt.md:95`. Native instead creates an entry version for every module
  function, split by `c_entry` into the execution and lifecycle images
  (`residualize.c:822-841`): measured 2/2 entries and 4 eager bodies for the raw
  two-function fixture (1 virtual call, 1 virtual return, 0 real calls) against
  1 body for the optimized one-function module; a non-exported function named
  only by a relocation is entered through `image->entries[index]`
  (`residualize.c:96-106`) and executes in all four modes. The portable-C writer
  emits every function of its input module (1/2/2 bodies for the 1/2/2-function
  optimized modules) and only exports add wrappers (`residual_c.c:222-240,
  1254-1280`). Consequently the design's pre-pass is the binding's root set, a
  residual call creates its callee's entry version itself, a refused owner creates
  one per direct `CALL`/`TCALL` target (round 12, from the direct-call-graph fact),
  and the residual-function set is derived — the incumbent's function-level
  worklist and the ABC writer's closure pass retire.
- Round-10 measured call-continuation probe (mutual and same-function **non-tail**
  recursive fixtures through the existing compiler, abc-opt, C writer and four
  execution modes; plus a one-off version-count probe against `build/libabc.a`):
  `experiments/10-call-continuation.md`, `.lua`, `.out`, `10-version-count.c`,
  artifacts in `experiments/10-call-continuation-out/`. Key facts: ABC emits the
  post-call computation immediately after `CALL_A` (abc-opt `f0 0f CALL_A` →
  `15 ADDI_A 1`; `f1 2a CALL_A` → `30 ADDI_A 2`; self variant → `ADDI_A 3`), the
  pre-optimizer module likewise (`CSETN_A`), and abc-opt shrinks 58 → 24 /
  31 → 13 instructions with values 13 / 15 in all four modes; the C sink puts the
  call and its used result in one block (`block_9: v_19=abc_aot_function_1(...)`
  then `v_22=v_19+v_20`). The shared machine's residual-call form pushes result
  locations and continues (`symbolic.c:220-259`); native instead marks every
  `K_CALL` return pc a block and splits the body there
  (`residualize.c:445-462, 785-801`), while its `FCALL` path already continues
  in-body; measured compiled version bodies: mutual-nontail eager 19 / lazy 11,
  self-nontail eager 12 / lazy 8, identical for the raw and abc-opt modules, with
  2 / 1 non-tail residual call sites (each fixture's remaining call is a tail
  call, which has no return pc). Consequently the design's algorithm block is
  corrected: `edge_to` is the only keyed-edge constructor (branch/switch arms,
  virtual returns, virtual call entries, fallthrough into a leader), a direct call
  is an in-body effect, and the call decision happens at the call instruction.
  (The same round's "all entry versions are created before any body is walked" is
  superseded by round 11: only the binding's root set is a pre-pass, and a
  residual call creates its callee's entry version itself.)
- Ownership audit with file:line citations, duplicate-SCC diff, leader-discovery
  drift, version-budget divergence: `experiments/1-rederive.md` §3.
- Round-2 measured ABC probe (new fixtures, existing assembler/optimizer/runtime):
  `experiments/2-abc-versioned-sink.md` §1–2 and `experiments/2-abc-probe.lua`.
  Key numbers: an 88-instruction branch chain optimizes to 16,382 instructions
  (186×, one input pc duplicated 4,096×, 23.9 ms); one more branch (94
  instructions) exceeds `ABC_OPTIMIZER_PATH_LIMIT` and the whole function is
  retained; functions with a branch and any non-call effect (`store`, `trap`)
  are retained unoptimized; the multi-result join grows 8 → 19 instructions;
  the documented canonical fixture (`docs/abc-opt.md:82-91`) is emitted exactly;
  every case is idempotent and executes identically interpreted/threaded.
- The C sink's per-version homes+constants policy:
  `src/residual_builder.c:851-877, 996-1062, 1083-1123`; key equality over
  sink-owned values `src/symbolic.c:33-38`; native form only
  `src/symbolic.c:62-75`; ABC `dag_value` rejects `HOME` `src/optimize.c:165-170`;
  `CALL`/`TCALL` must target a function entry `src/verify.c:131-134`.
- Code (round 1): `src/symbolic.c:45-75,180-538,553-578`;
  `src/residualize.c:408-463,776-801,822-826`;
  `src/residual_builder.c:851-978,979-1200,2047-2110`;
  `src/optimize.c:57-118,153-161,157,361-387,705-779,850-873`;
  `src/residual_analysis.c:24-85`; `REFACTOR.md:811`.
- Round-3 measured loop/join probe (hand-built ABC through the existing
  assembler, verifier, four execution modes, incumbent optimizer and C sink):
  `experiments/3-loop-versions.md` §1–4 and `experiments/3-loop-join-probe.lua`.
  Key numbers: a function with a local backward branch is retained
  byte-identically (`sum-fold-source` 15 → 15, foldable `5+6` untouched; the same
  shape without the backedge optimizes 12 → 10); hand-built versioned loop/join
  emissions verify and execute in interpreted/threaded/compiled/lazy for
  n = 3,1,0; `opt(source)` and `opt(versioned)` are byte-identical (94 bytes) and
  idempotent; a join with mismatched C shapes is rejected; the C sink compiles
  loops as versioned blocks with edge arguments; native compiles the same loop.
  Verifier facts: backward targets legal (`verify.c:122-125`), identical A/B/C
  shapes at joins (`:284`). Rule evidence: C sink
  `residual_builder.c:1195-1207, 1090-1091, 1102-1118`, native
  `residualize.c:424-438`; continuation equality `symbolic.c:39-54`.
- Round-4 measured entry/call boundary probe (new mutual-recursion fixtures and
  the documented counter through the existing assembler, four execution modes,
  incumbent optimizer and portable-C sink): `experiments/4-entry-lattice.md`
  §1–2.5 and `experiments/4-entry-lattice.lua`. Key numbers: the counter is fully
  inlined (53 → 18 instructions, **one** function, no `CALL_A`); two roots with
  limits 50/40 produce two independent specializations (2 functions,
  `BLTUI_A 50` and `BLTUI_A 40`), not a join; mutual recursion keeps residual
  calls and folds `step = 7` into both callees (`93`, `193`, `PUSH 8·7` at the
  call sites) while widening `i`; two roots with steps 7/9 widen `step` and the
  folds disappear (per-argument join); 40 roots cost 0.06–0.07 ms either way;
  `opt⁴ == opt` (166 bytes); the portable-C output for the same module folds
  nothing (generic entries). Mechanism citations: inline rule `optimize.c:299-318`,
  SCC eligibility `:108-114`; call facts + dirty rebuild loop `:850-873`; module
  write-time call encoding `:826-833`; C sink generic entries
  `residual_c.c:1239`, `residual_builder.c:2177-2210, 898-933`; dead lattice
  `residual_analysis.c:215-266`; continuation in key identity `symbolic.c:39-75`.
- Round-8 key-identity probe: `experiments/8-key-identity.md` and
  `experiments/8-version-model.py` / `.out`. Key facts: `abc_symbolic_context_equal`
  compares the stored `generic` canonicalisation-mode bit (`symbolic.c:57-59`)
  which `canonicalize`/`conform_generic` set from the widening argument
  (`residual_builder.c:856`, `residualize.c:168`), while the derived predicate is
  recomputed from the values (`symbolic.c:74-85`) and family equality ignores the
  bit (`:64-72`); the C sink's `VERSION_LOOP_ENTRY` *is* `canonicalize(key,1)`
  (all constants forgotten + the bit), which is the code reason its loop entry
  forgets invariants, and both sinks look up after widening
  (`residual_builder.c:1110-1119`; `residualize.c:410, 436`). Model: the
  round-7 lookup-before-widening rule reaches 4/6/8/10 versions for arrival
  sequences of length 4/6/8/10 at budget 3 (unbounded, with duplicate keys);
  content identity + lookup-after-widening saturates at 3 = budget, one version
  per value vector; the loop-header-entry configuration is 2 versions (2 with the
  same value vector) with the mode bit and 1 version with content identity.
  Incumbent recursion rule: `nested_eligible` requires call-component size 1, so
  mutual (tail) calls are residual calls (`optimize.c:108-114, 299-318`).
- Round-9 measured residual-entry probe: `experiments/9-tail-cycle.md` and
  `experiments/9-tail-cycle.lua`, artifacts in `experiments/9-tail-cycle-out/`.
  The live fixture `frontend/tests/compiler.lua:790-804` (mutual `even`/`odd`,
  staged with the default `optimize=true`, so abc-opt output; part of
  `Makefile:212`, suite passes) pins 3 functions, a `TCALL`, and `PUSH8_A 9` +
  `PUSH8_A 10`. Measured: the pre-optimizer module (48 instructions) reads the
  parameter and adds; abc-opt (21 instructions) folds it (`even` returns/stores
  9, `odd` returns `marker+1` → 10), so the fold is the residual-entry argument
  join (`optimize.c:850-873`), not frontend lowering; value 9 in all four
  modes; `opt` is a byte-identical fixpoint. The two-caller variant
  (`even(4,9) + even(4,7)`, value 16) widens `marker` and emits the generic-entry
  body shape: `even` unchanged at 9 instructions, `odd` 9 → 11
  (`CGET1_A; ADDI_A 1; ZX32_A` instead of `PUSH8_A 10`). That is the measured
  cost of the design's all-location entry on the canonical source, and the two
  `compiler.lua:803` assertions are what stop holding. The ABC call ABI is the
  all-location entry form (`docs/spec.md:167-170`: `CALL` gathers argument zero
  at `C0`, the callee has empty private A/B stacks), so no entry prologue is
  needed; `nested_eligible` (`optimize.c:108-114`) and `dag_call`/`dag_tail`
  (`:299-318`) are the derived form of the design's inline rule (acyclic or
  same-function self-tail only).
- Round-7 measured budget/chain probe: `experiments/7-budget.md` §1–§6 and
  `experiments/7-call-paths.py` (artifacts in `7-call-paths-out/`, not committed).
  Key facts: key equality compares the continuation chain (`src/symbolic.c:45-53`)
  and family equality adds the stack shape (`:56-66`), while every
  canonicalization is value-only (`src/residual_builder.c:851-868, 936-963`), so
  the all-location fallback is total inside a family and cannot merge call
  instances; the only code that removes a chain is a call decision
  (`src/residualize.c:395-406`). Measured on a branch-free doubling call ladder:
  the ABC sink's output doubles with the number of syntactic non-tail call
  instances (2^depth) — 22, 46, 94, 190, 382, 766 instructions for 8…256
  instances, ~1.75–3 instructions per instance — until ABC's 255-cell C-frame
  limit stops the outer inlining at depth 9 (`src/optimize.c:753, 762`); the
  versioned sink emits one body per inlined instance because the chain differs,
  so this is the multiplicity its inline bound must cut. `REFACTOR.md:811`
  records the incumbent's 10-versions-at-one-entry-PC divergence. Rule citations:
  `src/symbolic.c:471-477, 486-499` (call continuation; tail pushes none), `src/verify.c:284`
  (shape fixed per pc), `src/residual_builder.c:965-1004, 1108-1117`.
- Round-6 measured may-write probe (the documented counter and an exit-path-pop
  loop through the existing assembler, disassembler and the verifier's join rule
  as the height oracle): `experiments/6-may-write.md` §1–7 and
  `experiments/6-may-write.lua`, artifacts in `experiments/6-may-write-out/`.
  Key numbers: the documented counter's `loop` (header pc 41, C height 4,
  self-tail `TCALL` backedge at pc 72, body `CSET`s slots 2 and 3) is marked
  may-write `{0,1,2,3}` by round 5's interval + CALL/TCALL rule (0 constants kept)
  and `{2,3}` by the cycle-body rule (2 constants kept — the incumbent's
  two-unknown-slot body); the exit-path fixture goes `{0,1,2}` → `{0}` (min C
  height 0 → 3); argument 0 is the first pushed value (`f(1,2,3)` returns
  `1 2 3`), so a self-tail transport is position-preserving. Rule citations:
  `src/symbolic.c:467-484` (a call's frame starts at the caller's C height and
  does not change `n[C]` when residualized), `docs/spec.md` "Calls" (`TCALL`
  replaces the complete frame), `src/verify.c` C cases (a callee addresses only
  its own C frame), `gen/banked.lua:234` (gather).
- Round-5 measured loop-key probe (hand-built ABC through the existing assembler,
  verifier, four execution modes, incumbent optimizer and portable-C sink):
  `experiments/5-loop-key.md` §1–3 and `experiments/5-loop-key.lua`. Key numbers:
  the documented counter's optimized loop is one body at pc 6 with `BLTUI_A 50`
  and `ADDI_A 7` and both loop slots unknown — the incumbent's loop header is a
  join that keeps unwritten constants; the loop-invariant-key emission of the same
  loop returns 1071 in all four modes at 16 instructions with 10
  instructions/iteration; the generic-key emission costs 22 and 12/iteration; the
  exact-key emission with budget 8 is 29 instructions (7 folded header versions +
  4 constant stores + a generic tail) with 12/iteration in the hot tail.
  `frontend/tests/optimize.lua:502,505` pins the immediates, so exact keys at a
  loop header would fail it. The portable-C sink's loop entry compares
  block-argument copies (`if(v_8 < v_5)`) although the bound is materialized
  before the loop. Rule citations: `residual_builder.c:1090-1091, 1195-1207`
  (loop entry forgets constants), `residualize.c:414-438` (native weakens all
  constants on a backward edge), `verify.c:284` (join shapes),
  `docs/symmetric-isa.md:183-187` for the i8 immediate forms.

## Open questions

See `QUESTIONS.md` (Q1 ABC version policy gate; Q2 version-budget authority —
now number **and scope**, because a key widening cannot merge continuation
chains; Q3 portable-C scope; Q9 native loop-header policy; Q10 the value of the
continuation-family bound `K`; Q12 layout/cycle-body fact ownership; Q19 whether
native's entry set may shrink to the addressable entries). Q11 is
answered (the loop-invariant key), Q13 answers what its body is (the cycle body,
backedge as join), Q14 is answered round 9 (every cross-function recursive call
is residualized; the only inlined recursion is a same-function self-tail cycle,
so the documented residual-entry invariant precision is surrendered with Q7),
Q15 is answered round 7 (the budget is per family; families are bounded by the
inline rule), Q16 is answered round 8 (key identity is content; every
widening is followed by a lookup; the entry is created through `version_at`, so
an entry that is a loop header has one body), and Q17 is answered round 10 (a
version body ends at a control transfer, every control-transfer successor is a
keyed edge through the driver's `edge_to`, a direct call is an in-body effect
unless it is inlined, and a call-return pc is not a version boundary), and Q18 is
answered round 11 (the residual-function set is derived: the binding's root set
exists before any walk, a residual call creates its callee's entry version at the
call, a refused owner creates one per direct `CALL`/`TCALL` target from the
direct-call-graph fact, and the entry-version owners are the residual functions —
no function-level worklist, no closure pass), Q20 is answered round 12 (a refusal is owner-granular and discovered by the walk;
the owner's entry version survives with the source body as residue, its other
versions are dropped, its `CALL`/`TCALL` targets are entry versions derived from
the direct-call-graph fact, and publication is per owner; only ABC can retain —
portable C and native fail the build), and Q21 is answered round 12 (an indirect
or foreign call is an in-body effect with no target version; only a direct call is
inlined or names a version). Round 12 also closes round 11's open item: a retained
body's `TCALL` targets are recorded exactly like `CALL` (`direct_target` accepts
both, `optimize.c:54-56`). Do not duplicate them here.

Q1 is the one remaining scope gate for this design. Round-2, round-3 and round-4
measurements make the recommendation explicit: **adopt versioned blocks for
`abc-opt`**, because the path tree's duplication is exponential in branches, has
a whole-function cliff at 4096 paths, refuses any branch-plus-effect function,
refuses any function containing a local loop (measured, with foldable arithmetic
left untouched), and its argument-fact lattice exists only to patch the calls the
path tree cannot inline (round 4). The gate is the user's because output bytes
and the analysis policy change; the measured evidence, the representability
argument and the validation plan are in `experiments/2-abc-versioned-sink.md`,
`experiments/3-loop-versions.md`, `experiments/4-entry-lattice.md` and
`experiments/5-loop-key.md`. If the
gate is refused, the driver is shared by native and C only, the ABC sink keeps a
declared sink-owned path emitter with its path limit (and keeps the loop
machinery, since a path tree cannot represent a backedge), and everything else in
this document stands. Q2 must be answered before the version budget can have a
single owner: the approved number alone does not determine behavior, because
"total versions per original PC" and "versions per family per PC" are different
quantities (`experiments/7-budget.md` §4.2–§4.4). Q9 decides whether native adopts the loop-invariant header key
(round 5's recommendation: yes — one header version instead of two, invariant
C-frame constants kept, the one-iteration peel dropped); the rule is otherwise
fixed by Q11. Q10 decides the value of the continuation-family bound `K` (its
rule is fixed round 9: acyclic calls inline, a same-function self-tail cycle is a
loop header bounded by the loop rule, every other recursive call is residual).
Q12
decides where per-pc heights, `CSET` targets and cycle-body/may-write sets are
computed (round 6 pins the required data: heights, `CSET` targets, successors and
backedges; the verifier's discarded `Shape` records the same heights but must not
become an optimizer dependency). Q3 decides
whether the binding set is two or three (the C sink's policy is already the
precedent for Q5/Q6 either way). Q19 is the one remaining input-free
compile-set choice: native currently installs an entry for every module function
(`residualize.c:822-841`) although the runtime reaches an entry only through an
export name or a public code address materialized by a relocation
(`residualize.c:96-106`, `gen/cold.lua:19-29`, `src/vm.c:214,253`); the measured
cost is one never-entered body for an inlined callee on a raw module (4 eager
bodies vs 1 for the optimized module, `experiments/11-residual-root-set.md`), and
the same addressable-root rule is already the ABC writer's set
(`optimize.c:812-817,826`). Recommendation: adopt it; it changes the runtime
image's entry table contents, so it is recorded as a question rather than decided
silently.
