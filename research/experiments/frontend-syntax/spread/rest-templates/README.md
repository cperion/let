# Source formation anchors and rest/template specialization

## Approved and implemented

The user explicitly approved extending existing source state with definition-point
anchors after the reference-retargeting probe exposed the need. This implements the
approved X03 route, not a runtime variadic representation or a second evaluator.

- `source_state.Context` owns qualified context/ordinal formation points and ordered
  statement-list copies. Selected snapshots splice ordinary IR occurrences at their
  original definition boundary. Different instances share the selected binding snapshot;
  unused captures emit nothing. Opened places remain live routes. Anchors are compiler
  metadata; no new executable IR node, backend allocator or placement pass exists.
- `semantic.lua` replaces fixed-signature-before-body assumptions for ordered rest/
  explicit static Type words with source templates. Every code/type/component/qualified
  face specialization invokes the same `elaborateWord` once. Instances reserve identities
  before recursion; unresolved recursive results still require annotations.
- Templates collect already-evaluated supplies into component recipes. Static Type
  arguments disappear from the executable ABI. Other components use ordinary typed
  inputs; known callable code uses direct calls and transports holdings through explicit
  inputs. Existing capture streams close late recursive holdings/layouts. Unknown code
  uses its declared fixed-signature indirect ABI. Recipes select metadata/components,
  never compute arithmetic or replay source bodies.
- Packs support expansion, static length and VM-demanded integer indexing. They retain
  ordinary component types/interfaces/provenance and may capture individual components.
  Empty packs contribute zero components; a Unit result remains one logical component.
  Pack assignment, storage, ordinary binding, return-as-object and erasure reject.
- Missing fixed requirements retain normal static partial rules. Consecutive suffixes
  keep pending runtime arguments until saturation; grouping restores the static partial
  boundary. Rest accepts zero or more components immediately when fixed requirements
  are satisfied. Bound rest methods retain their receiver through partial supply.
- Public/imported templates remain source definitions; no erased variadic ABC export
  is generated. Cached instances/dependencies attach to each importing compilation.
  Ordinary fixed words, module publication, access checks and ABC execution stay shared.

No ISA/ABI, scalar algorithm, continuation, collector/owner policy or escape permission
was added/relaxed. Whippet retirement, executable dynamic Let and broad ownership
admission remain separate unfinished work.

## Qualification

Integrated `frontend/tests/rest_templates.lua`: **616 checks / 276 executions**.
Admitted scalar probes run optimized/unoptimized in interpreted/threaded/eager/lazy
modes. Nine local aggregate/capture/interface probes use all four unoptimized modes;
these deliberately do not claim optimized frame-access qualification. Existing ordered/
keyed qualification still has eight optimized configurations blocked by the independently
reproduced optimizer defect (see parent README/frame-control evidence).

Tests cover empty/Unit/heterogeneous packs, arrays and multi-results, static computed
and U64 indexes, named/literal forms, partial saturation/grouping, known direct versus
unknown fixed indirect calls, component captures, definition-time reference snapshots,
live opening versus saved values, shared snapshots across shapes, reverse request order,
conditional-body anchors, method/lexical receivers and bound partial methods, dependent
result faces, unused templates, source-only public imports/exports across consumers,
repeated-shape reuse, recursion and late recursive callable-holding growth, deferred
post-call order with multi-results, and borrow-store/borrow-return/erasure rejection.

`focused.log`: initial focused rest/receiver/access/ordered-spread runs plus absolute
growth samples. `focused-final.log`: final616/276 rest coverage and repeated growth
samples; counts/code sizes agree, timings remain noisy. `full-validation-1.log`: incremental suite initially stopped on obsolete
`rest-unimplemented` expectations in word_bindings.lua; those are now source-only export
controls (107 checks/84 executions). `full-validation-2.log`: passed before the final
source-point/dependent-face/Unit/qualified-metatype/partial-method tests.
`full-validation-final.log`: final full incremental qualification.

Initial ad hoc drafts corrected invalid syntax (`0L`, `return ()`, bare `box...`) and an
incorrect saturation fixture: `add(n)(2)` already supplies every fixed requirement at
its first suffix, so rest is empty there. Another negative test initially expected a
borrow-return diagnostic in SLet where captured-view materialization rejects earlier;
the Let profile now checks that precise retention escape, without widening SLet.

No clean build, sanitizer, process-memory bound or performance speedup is claimed.

## Absolute growth evidence

Run from frontend:

```sh
/tmp/lua-compat ../research/experiments/frontend-syntax/spread/rest-templates/measure.lua
```

Seven fresh typing trials per case; medians include source parsing/IR/access checking.
No controlled pre-change comparison. Both families execute the resulting module.

| Calls | Same-shape instances / bytes | Distinct-length instances / bytes |
|---:|---:|---:|
| 1 | 1 / 105 | 1 / 105 |
| 2 | 1 / 133 | 2 / 155 |
| 4 | 1 / 167 | 4 / 239 |
| 8 | 1 / 235 | 8 / 431 |
| 16 | 1 / 371 | 16 / 911 |
| 32 | 1 / 643 | 32 / 2255 |

At32 calls, same shape has408 traversed IR nodes; distinct lengths have5244. The
second source itself supplies quadratically many total components. Distinct instances
are not bounded by this sample. Code bytes are raw assembled module sizes, not native
machine-code images. Sample median typing CPU at32:2.265ms versus16.736ms for those
different sources, not a frontend optimization result.

Remaining: keyed static Type templates/F02, general SCC/result inference, broader
recursive/overlap/control/resource coverage and holding publication cleanup, precise
copy/retain/native-image measurements and the independent frame-access optimizer defect.
Priority remains bitcast cost next, then collector-free cutover/final GC removal.
