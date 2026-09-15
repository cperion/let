# Design: one owner per decision

This is the refactoring record for the compiler. [ARCHITECTURE.md](ARCHITECTURE.md) states what
the compiler *is*; this document states the problem it had and the plan that removed it.
**Status: implemented in full.** Every step below is done with the evidence it was accepted on,
and each one kept `luajit test/all.lua` green and `dist/let.lua` current.

## The problem

The compiler's complexity is not concentrated in a long function. It is that **one decision has
several owners**, so the owners must be kept in agreement by hand:

| Decision | Owners before | Consequence |
| --- | --- | --- |
| Belt type identity | `program.lua` `typekey`, `emit.lua` `typekey` | Two formats; the aggregate branch of one keys every aggregate the same |
| Does a type own / borrow state | `build.lua` `owns`, `borrows`, `validate_ownership` | Three or four walks of one shape |
| Word field packet: shape, place-ness, ownership, write-back | six descriptor literals and four write-back predicates in `program.lua` | Already diverged |
| Stage capability to parameter shape | `A.Stage:bind_parameter`, `Builder:host_parameter` | Already diverged on `own mut` |
| Template stage and result types | `resolve`, `options.parameters`, `peek_type`, `typing.lua` | No declaration phase; types discovered while emitting |
| Terminal body construction | `Chain:build_function`, `Builder:build_entry`/`advance` | Two engines |
| Construction state per block | `Context` with a blacklist `clone` | A new field silently becomes per-block |
| Opcode semantics and verification | `verify`, `known`, `emit`, `execute`, `numbering` | Folding can silently disagree with the oracle |

## The rule

**Every template's interface is computed before any body is built.**

```
resolve ──▶ Contract ──▶ define ──▶ Belt ──▶ Op ──▶ {verify, demand, known, emit}
 (names)    (types/ABI)   (lowering)         (one opcode owner)
```

Four concepts own the decisions, and everything else is a client.

### Contract

A template's published interface: ordered stages `{name, capability, type}`, captures
`{name, type, mode}`, terminal kind (data or do), result type, and the owned/place shape. A stage
type comes from an annotation, from the argument, or from inference over the body. One rule says
what an untyped stage means.

Subsumes `peek_type`/`peek_result_type`, `options.parameters` special-casing, the self-call result
workaround, and `typing.lua`. It is where mutual-recursion declarations and full stage inference
belong.

### Packet

The ordered field bundle of a word, as a value:

```text
Packet.key(packet)            -- Belt.Type:key
Packet.written_back(packet)   -- the one write-back rule
Packet.bind(frame, packet)    -- bind every field into a construction frame
Packet.declare(entry, packet) -- the ABI parameters
```

Subsumes the descriptor literals, the rebind loops, the write-back predicates, and the entry
parameter scan. The creation trace is no longer an untyped table built at six call sites.

### Frame

The construction state of one belt block, split explicitly:

```text
Frame.ambient   -- vocabulary, builder, resolved source, function id, self name
Frame.state     -- draft block, scopes, facts, pins, effect
Frame:child()   -- fresh state, same ambient
```

`ambient` is shared and immutable for the region; `state` is per block. Facts
(`value`/`initialized`/`alive`/`moved`) are one value with named operations, not fields poked from
call sites. Subsumes the blacklist `clone` and the duplicated block-packet enumeration in
`Context:interface` and `A.While:build`.

### Op

`belt.lua` keeps its shape. Each opcode gets one owner for `inputs`, `verify`, abstract
semantics, concrete semantics and emission. `numbering.lua` and `verify.lua` already organize this
way. The urgent part is the drift pair: `known.lua` and `test/execute.lua` must share one
semantics definition, as [DEMAND.md §3](DEMAND.md) requires. Moving the emitter onto the registry
is optional and later.

## What gets deleted

- `A.Chain:build_function` and the second construction engine.
- `Context:peek_type` and `peek_result_type`.
- `typing.lua` (absorbed into Contract).
- Both `typekey` functions.
- `Context:owns` and `Context:borrows`.
- The field descriptor literals, rebind loops and write-back predicates.
- The `Context:clone` blacklist.
- `A.Stage:bind_parameter` against `Builder:host_parameter`.
- Optionally, the `known`/`execute` opcode chains.

## Steps

Each step keeps the suite green and regenerates `dist/let.lua`. Where a step adds a module, the
module is the one owner and the call sites shrink; the measure that matters is that a decision
no longer lives in several places, not the raw line count.

1. **[done]** Type identity and ownership move to the belt. `Belt.Type:key` and `Belt.Field:key`
   replace both `typekey`s; `Belt.Type:owns` and `Belt.Type:borrows` replace the two walks.
   Verified: 466 checks green, bundle current, emitted C identical for every example that
   builds and all 36 native witnesses.
2. **[done]** Packet. One value owns the word field bundle: `place`, `entry_owned`,
   `written_back`, `mutable_state`, `key`, `field`, `bind`, `bind_all`, `bind_parameter`.
   Verified: no field descriptor literal and no write-back predicate remains outside
   `let/packet.lua`; 466 checks green, bundle current, all 36 native witnesses and every
   example that builds emit identical C. `program.lua` lost 32 net lines to the module.
3. **[done]** Frame. `Context:clone` now carries an explicit `ambient(frame)` list and creates the
   state fields itself, so a new ambient field is a nil error rather than a fact silently
   shared by every block. `interface` records the ordered fact slots on the target and
   `Context:pack(endpoint)` supplies them, so the loop backedge no longer restates the packet
   order that `interface` declares. Verified: 466 checks green, bundle current, all 36 native
   witnesses and every example emit identical C; `test/build.lua`'s `resource_loop` carries an
   owned resource across a backedge and is unchanged. Deferred to the Contract rewrite, which
   touches every method anyway: renaming `Context` to `Frame`, the `ambient` sub-table, and
   encapsulating each cell behind named operations.
4. **[done]** Contract. `let/contract.lua` is the one type estimator: it computes a template's
   stage types from its uses and its result type from its returns, before the body is built.
   `Context:peek_type`/`peek_result_type` and `let/typing.lua` are deleted; `invoke` reads
   `ctx.fn.result` with no forward-scan fallback, and `build_entry` seeds it from a Contract
   computed with the packet's capture types. Verified: 468 checks green, bundle current, all 36
   native witnesses and every example emit identical C. Mutable-local and capture fixing
   returns now have tests in `test/program.lua`. Still open, and moved to Step 4b: inference
   through a word-valued callee or an aggregate, which still yields no type.
5. **[done]** One terminal engine. `Context:finish_function` runs a terminal body and builds its
   function, and `Context:blocks` collects the immutable belt; `build_function`, `build_entry`,
   `module_function`, `build_unload` and `host_entry` all use them, so no driver has its own
   body/finish/block-collection. `A.Stage:bind_parameter` binds through `Packet.stage_field` /
   `Packet.bind_parameter`, and `Builder:host_parameter` is deleted, so `mut` and `own mut` have
   one shape everywhere (the old generic path delivered `own mut` as a plain value, which could
   not be returned or moved at all). Verified: 468 checks green, bundle current, all 36 native
   witnesses and every example emit identical C. Not merged, deliberately: `build_function`
   remains a resolve-less convenience API, and its option/type-table setup still duplicates
   `Builder:types`; that belongs with a single vocabulary owner, not with the terminal engine.
6. **[done]** One opcode semantics. `let/op.lua` is the only place that maps an operator to its
   meaning: `Op.unary`, `Op.binary` (non-trapping Float division) and `Op.checked` (trapping
   Int division/remainder). `known.lua` and `test/execute.lua` both index it, and neither maps
   an operator to a `scalar` function any more, so folding cannot disagree with execution.
   Verified: 468 checks green, bundle current, all 36 native witnesses emit identical C, and
   `grep` finds no `scalar.add`/`scalar.divide`/`scalar.less` outside `let/op.lua`.

Two follow-ons, taken after the six steps and kept out of them because they add capability
rather than move ownership:

7. **[done]** Single vocabulary owner. `let/vocabulary.lua` validates and owns the base scalar
   types, the registered resources and their destructors, and the runtime hosts. `Context`
   takes one vocabulary instead of `resources`/`hosts`/`types`; `Builder:types` and
   `build_function`'s inline table and assertions are deleted. Verified: 468 checks green,
   bundle current, all 36 native witnesses emit identical C.
8. **[done]** Contract inference through word callees and aggregates. A named callee's stage
   types now type its arguments, a record result or host parameter types the members a stage
   supplies, and `Project`/`Index` read a known record. Cycles yield no interface rather than
   recursing. Verified: 473 checks green, bundle current, all 36 native witnesses emit
   identical C; `test/host_entry.lua` and `test/program.lua` carry the witnesses. Still open:
   an argument-determined (`Executable`) stage and a word-typed value with no call.

## Not in this design

- A universal tagged value, closure layout, or dynamic dispatch for word values. §18 defers the
  layout, so this is a language decision.
- Constraint words with specialization arguments. §11.2 defers the surface.
- Replacing the belt or the C vocabulary. They are the good parts.
- Unrolling an effect-carrying loop by unrolling the emitter. That is block instances, a separate
  feature, and it waits for Frame.
- Accepting a partial move introduced inside a loop. Loop peeling alone does not solve it: the
  peeled remainder still contains the guarded move, so it needs guard-correlated facts. Until then
  the diagnostic stays.
