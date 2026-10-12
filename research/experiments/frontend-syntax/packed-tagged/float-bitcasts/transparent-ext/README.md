# Transparent EXT execution-binding experiment

**Outcome: approved design prototyped and validated, but NOT ADOPTED.** The active
`gen/banked.lua` and `gen/semantics.lua` are restored byte-for-byte to the pre-experiment
working-copy versions. The existing explicit kind-changing bitcasts remain correct;
this is not withdrawal of the ISA extension or restoration of scratch-memory lowering.
The interpreted packed-cost regression is **not fixed** by this work.

Only the stronger poisoned-cache payload tests, measurements, candidate patches and
documentation remain. No optimizer/allocator/ABI/layout/encoding change, extra runtime
fallback or publication. The candidate's failure is a performance result, not a
semantic failure. Ownership/cutover design is next; do not install a worse generic
EXT path merely to declare this optimization complete.

## Approved design and prototypes

Authority: symmetric ISA bitcast/EXT contracts, spec cache/handler ABI, and
`cost-investigation/README.md`. A raw-cell identity declaration was added to the
shared unary transfer metadata. The interpreter generator consumed it and manifest
lengths to retain exact cache state and all carried/home cells, advancing directly
from EXT to the next opcode. Dedicated cast handlers were removed, and private
selector-table slots for transparent operations were null. Typed verification and
all existing bytecode kind transitions remained unchanged. No lookahead skipping
loop or check on the global ordinary-dispatch path was added.

1. **Selector predicate:** test the metadata-generated identity selector set before
   selector-table dispatch (`selector-candidate.patch`).
2. **Existing table routing:** load the existing selector-table entry and use its
   null identity entry to select the transparent branch (`table-candidate.patch`).
   In verified code only declared identity selectors had those entries; this was
   neither accepting malformed code nor reinterpreting an unassigned selector.

Both use the same approved architectural shape, without a new subsystem. The second
binding refinement was measured because the first burdened ordinary EXT arithmetic.
Neither is retained in production.

## Correctness and footprint

- `full-validation-1.log`: selector candidate, complete incremental validation.
- `full-validation-table.log`: table-route candidate, complete incremental validation.
- `full-validation-restored.log`: original binding restored, complete incremental
  validation including stronger exact-state bit patterns.
- Runtime oracle143 cases/1144 four-mode executions/all286 public forms;
  poisoned-cache2880 exact handlers and655 transitions; residual315; the existing
  packed1894/496, continuation, lifetime, source, spread/rest and anonymous suites
  remain green. This is not a clean-build/sanitizer/resource-completeness claim.
- Cast cache probes now carry signaling-NaN payloads on A, signed quiet-NaN payloads
  on B and negative-zero/high-bit values on C, preserving all bits with poisoned
  dead registers across every cache state, including backing-only selected tops.
- Disassembly confirms no operand conversion/spill, one fewer indirect jump for
  casts, and an extra conditional on other EXT operations. Baseline uses240 separate
  cast-handler symbols (5520 summed symbol bytes, excluding padding).
- Selector candidate shared-library `size` text3700453→3684133 (−16320 bytes),
  data347216 unchanged. See `size-*.log` for both candidates and object details.
  These are code/data-section figures, not native realization-image or RSS bounds.
  The reduction was not retained after restoring the original binding.

## Measurements and controls

Host: virtualized i7-1255U, affinity CPU0; Clang20.1.2, existing -O2 PIC incremental
build. No fixed frequency or exclusive host. Raw public ABC calls, exact bits checked,
same bytecode images on both engines, no optimizer in the dispatch control streams.

`measure-runtime-paired.lua` locally loads both runtime libraries, runs current
packed roundtrip/add bytecode optimized/unoptimized in all modes, plus A/B streams
with0/1/8/32/128 pairs of integer/float casts, ORI0, FNEG pairs, ADDC and immediate
branches. Eleven alternating samples,10000 warmups. FFI results are mixed/noisy;
`runtime-paired-contended.log` also ran concurrently with validation and is retained
only as a contaminated preliminary sample, not controlled evidence.

`measure-runtime-paired.c` removes the Lua/FFI call layer, loads identical saved
bytecode images into both engines, uses15 alternating process-CPU-time samples,
20000 warmups and at least100000 timed calls per sample. Both engines are measured
through dynamic public API function pointers. `reverse` reverses the initial timing
order; `load-reverse` additionally reverses dynamic library load order.

Key interpreted observations:

- Selector candidate,128-pair cast streams: roughly11–28% faster in the first C run,
  20–27% faster in its timing-order repeat. ADDC128 regresses15–23% in these runs.
- Table route, B128: integer casts−20.44%, float casts−18.84%, ADDC+16.60%.
  Reverse-load run: casts−17.73%/−19.05%, ADDC+20.56%.
- Reverse-load packed roundtrip no/with optimization: +1.62%/−0.52%; packed add:
  −1.38%/+0.60%. This does not demonstrate a useful packed-program improvement.
  Other runs vary more. Repeated cast-only streams are not representative source
  programs and their gains do not justify the ordinary EXT regression.

**Critical identical-binary control:** `runtime-identical-control.log` compares two
separate, byte-identical copies of the BEFORE runtime. Native packed timings still
differ by about18–55% in several cases, and threaded timings also vary. Therefore
these dual-library native/threaded timings do **not establish candidate regressions
or improvements**; load placement/order or harness effects are unresolved. Do not
subtract that control numerically to manufacture corrected speedups. Interpreted
B128 identical controls are much closer: casts+1.36%/−2.81%, ADDC+0.93%, branch+1.96%.
The persistent interpreted ADDC regression materially exceeds those controls.

The extra general-EXT branch is real; its measured cost outweighs any demonstrated
benefit in these packed fixtures. Per the approved design's measurement gate, both
candidates were rejected rather than adding instruction encodings, per-module
predecoding, separate placement, opaque fallbacks or special compiler tricks.

## Reproduce

The pre-experiment library was saved as `/tmp/let-bitcast-fastpath-before.so`;
`baseline.sha256` records its identity. Source checkpoint before prototypes:
`b6c5f428` in the colocated jj history (already contains unrelated WIP). Candidate
patches are relative to that working version, not the last published commit.
Temporary libraries/modules are not committed artifacts.

```sh
/tmp/clang20 -O2 -std=c11 -Wall -Wextra -Wpedantic -Werror \
  -Wno-newline-eof -Iinclude \
  research/experiments/frontend-syntax/packed-tagged/float-bitcasts/transparent-ext/measure-runtime-paired.c \
  -ldl -o /tmp/let-bitcast-paired-c
mkdir -p /tmp/let-bitcast-images
cd frontend
/tmp/lua-compat ../research/experiments/frontend-syntax/packed-tagged/float-bitcasts/transparent-ext/measure-runtime-paired.lua \
  /tmp/let-bitcast-fastpath-before.so ../build/libabc.so /tmp/let-bitcast-images
cd ..
taskset -c 0 /tmp/let-bitcast-paired-c /tmp/let-bitcast-fastpath-before.so \
  "$PWD/build/libabc.so" /tmp/let-bitcast-images/manifest.txt
```

Rebuild a candidate in an isolated checkout before comparing it: the current library
is now the restored baseline. For identical controls copy the saved BEFORE .so to a
second path; passing the same path twice just reuses one dlopen object. No code-size,
performance or owner-lifetime claim can be inferred merely from green output tests.
