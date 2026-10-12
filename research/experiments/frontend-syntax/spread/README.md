# Ordered/keyed spread — first qualification checkpoint

User approved the language-focused design: X02/X04 ordered/keyed supplies followed
by X03 rest/template specialization, then bitcast cost and collector-free GC removal.
This checkpoint did not complete rest packs, F02 or X06. The user subsequently
approved formation anchors; [rest-template follow-up](rest-templates/README.md)
records their implementation and current qualification. Historical logs below
remain unchanged.

## Implemented

- Shared result-list elaboration: explicit spread at any position, full result vectors,
  sole fixed-array expansion, nonrecursive flattening, parenthesized adjustment,
  unchanged unmarked final forwarding and binding/return arity policies.
- Fixed-array constructors check expanded element types/counts. Positive lengths remain
  required. Arrays used as ordinary final arguments are not automatically expanded.
- Canonical Ir.Selector = Field | Element. Pure Get supports checked static array
  elements; Project remains restricted to named record fields. Builder/checker/access/
  ABC consumers updated together and generated schema regenerated. Array loans remain
  conservatively joined under the existing Borrow.Element path. No unpacking block.
- Supplies snapshot computations before later items. Zero-width values do not gain
  artificial scalar slots. Existing instance aliases and live opening remain separate.
- Shared keyed contribution records for records/alternative constructors/keyed words/
  sum handlers. Evaluate in source order, then select effective supplies. Explicit
  fields override spreads independent of position; duplicate explicit fields and
  overlapping spreads reject; unknown fields are checked even if overridden. Only data
  fields contribute. Effective values retain ordinary type/requirement checks; existing
  supplied-key protections remain. Runtime table-key expansion still rejects.
- Module binding lists share one initializer, dependency state and accepted VM result
  publication. Demand.requireValues transports the whole selected vector once, and
  publishes module bytes only after every result transports successfully. Scalar
  require uses the same boundary. Removed one-AST-value-per-module-binder restriction.
  Discarded computations still execute; no host source evaluator added.

No runtime representation, ABC ISA/ABI, backend allocator, continuation, root/GC or
escape policy was added/relaxed.

## Qualification

```sh
cd frontend
/tmp/lua-compat tests/spread.lua --unoptimized
/tmp/lua-compat tests/spread.lua
```

`unoptimized.log`: **379 checks / 108 four-mode executions**. This boundary is
integrated into Makefile validation. Includes ordered/keyed effects, arrays, partial
list adjustment, module single-publication state, record copy versus aliases,
nonrecursive expansion, overridden divide-by-zero aborts, invalid selectors and
borrow-return rejection through expanded reference components.

`qualification.log`: **719 checks / 208 executions; eight optimized configurations
BLOCKED**, not counted as executions. All other optimized/unoptimized cases pass.
The optional expanded qualification reports those failures explicitly, not as passes.

`frame-control.{lua,log}` isolates the failure WITHOUT spread syntax. With the semantic
frontend from 4a347dc7 (pre-spread, copied to /tmp/let-spread-before.93p27p89/frontend),
and with current semantics, unoptimized returns42 and optimization rejects at byte0xd:
`frame access outside a live byte block`. Both use current runtime/schema/lowering;
this is an isolated semantic baseline, not a clean build. The optimizer was not
patched or bypassed to hide it.

`full-validation-attempt-1.log`: failed because the new snapshot helper attempted an
ordinary scalar holder for a zero-width Array(Unit,1). Fixed by respecting existing
zero-component value layout, without allocating dummy storage or suppressing effects.
`full-validation-attempt-2.log`: full incremental validation passed before the final
selector/abort tests and integrated unoptimized spread boundary were added.
`full-validation.log`: final validation. No clean-build/sanitizer/performance claim.

Initial focused drafts are preserved in `qualification-attempt-{1,2}.log`. One fixture
used unsupported direct indexing of Ref(Array); corrected to admitted record/array
place access. The abort fixture initially expected raw VM division status, while the
source lowerer intentionally emits language abort1; the final expectation follows that
existing source contract. No production error policy changed.

## Historical rest-template formation design discussion

At this checkpoint rest rejected `rest-unimplemented`; no templates, source-only
template exports or unsafe fallback were implemented. That rejection has since been
removed by the approved [rest-template follow-up](rest-templates/README.md).

`formation-point.{lua,log}` verifies an ordinary nested word formed while `r=Ref(a)`:
after `r=Ref(b)`, calling the word returns a.n, not b.n, in all four unoptimized modes.
IR shows a selected capture Read **before** the Store retargeting r. Deferred generic
checking cannot simply import bindings at first invocation; that would read b instead.
Reading/capturing every visible name at formation is also wrong and revives the removed
capture-candidate heuristic.

The proposed additional concrete mechanism is qualified source formation points and
compiler-owned source emission anchors. Binding-resolved instance checking can request
selected value snapshots at those anchors; opened field/place captures remain live
qualified routes. Seal ordered source occurrences to ordinary IR before verification.
Use the same word elaborator/capture streams, not replay of checked bodies, new runtime
instructions, a second evaluator or native placement reconstruction. Unused captures
must not gain reads, storage or environments. This extension needs discussion before
implementation; the broader template design approval was not treated as permission
for an undisclosed orchestration subsystem.

Remaining: X03, source-only template imports/exports, more keyed partial/protected-key/
handler tests, shared-publication failure cleanup, broader resource/control/owner
coverage, specialization/code growth measurements and the independent optimizer bug.
