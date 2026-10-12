# Interpreted bitcast cost investigation

Initial state: measured/inspected, before runtime edits. The proposed binding was
subsequently approved, prototyped/validated and **not adopted** after generic EXT
regressions. See [the follow-up](../transparent-ext/README.md); the original runtime
binding is restored. The scripts use the incremental build, not clean-build qualification.

## Reproduction

From the repository root:

```sh
taskset -c 0 bash -c 'cd frontend && /tmp/lua-compat ../research/experiments/frontend-syntax/packed-tagged/float-bitcasts/measure-paired.lua /tmp/let-packed-memory-before.fgo5_4jd/frontend/let/abc.lua'
taskset -c 0 bash -c 'cd frontend && /tmp/lua-compat ../research/experiments/frontend-syntax/packed-tagged/float-bitcasts/cost-investigation/dispatch-cost.lua all'
```

The adapted baseline is the same temporary lowering described in the parent
README. Host: virtualized Intel i7-1255U; affinity CPU0, Clang20.1.2, existing
-O2 PIC runtime. CPU affinity does not fix frequency, scheduling or host load.
`perf` is not installed; this is disassembly plus CPU-time measurement, not
hardware-counter attribution.

## Measurements

Pinned paired lowering comparison (`paired-current.log`), median ns per raw FFI
call, before/current:

| Fixture | Optimized | Interpreted | Threaded | Eager | Lazy |
| --- | --- | --- | --- | --- | --- |
| Roundtrip | no | 35.2/38.4 | 26.9/18.6 | 17.3/16.9 | 17.9/17.8 |
| Roundtrip | yes | 35.2/39.3 | 26.3/18.1 | 18.1/17.6 | 18.0/17.0 |
| Add | no | 37.6/41.1 | 28.2/21.4 | 19.1/17.0 | 20.2/18.4 |
| Add | yes | 39.5/43.2 | 29.9/22.4 | 17.7/17.8 | 18.9/18.4 |

The interpreted regression reproduces at approximately 9–12% in this run;
absolute numbers differ considerably from earlier unpinned evidence. The same
runtime, IR and host execute both lowerings. Exact roundtrip/arithmetic bits
pass; raw/optimized module bytes remain145/144 and164/163; CALLOC1/0.

`dispatch-cost.lua` isolates verified, unoptimized bytecode: CGET into A or B,
0/1/8/32/128/512 pairs of operations, RET. Four families:

- Integer BITS2F/F2BITS, no physical change.
- Integer ORI0/ORI0: same instruction lengths, one core handler per operation.
- Float F2BITS/BITS2F, no physical change.
- Float FNEG/FNEG: toggles the sign twice, one-byte core operations. This is a
  different computation/encoding, not a replacement language bitcast.

Every family returns exactly `0x7ff0000000000001` in all four modes, including
float signaling-NaN input. Native/threaded cast runs stay close to their
no-operation baselines as length grows, consistent with existing zero-stencil
bindings. These timing samples do not measure native-image size or memory.

Nine alternating samples,1000 warmup calls, at least10000 timed calls per sample.
At eight pairs, interpreted medians in the first run:

| Bank | Integer casts | Integer ORI0 | Float casts | Float sign pair |
| --- | --- | --- | --- | --- |
| A | 39.337ns | 35.530ns | 39.311ns | 33.522ns |
| B | 41.731ns | 34.346ns | 42.497ns | 29.995ns |

An interpreted-only repeat (`dispatch-cost-repeat.log`) gives A integer
48.393/39.812ns and B45.201/38.570ns for casts/ORI0. Frequency/scheduling noise
is substantial, especially baseline-subtracted tiny samples: some reported
slopes are negative. Do not treat slopes as universal per-instruction costs.
Long repeated streams approach different predictor/cache regimes and cannot
be substituted for actual packed source programs.

## Structural finding

`dispatch.dis` shows the cached A statea1b0c2:

1. Ordinary dispatch enters EXT.A.
2. EXT.A reads the selector and indirectly tail-jumps through its selector table.
3. F2BITS.A/BITS2F.A only advance ip by2 and indirectly tail-jump to the next
   opcode in the **same cache state**. There is no conversion, load/store of the
   operand, cache spill or kind check in these handlers.

Thus the extra selector dispatch is real, not a supposed expensive binary64
conversion. `abc_decode_instruction` is the format/verification contract;
these execution handlers do not repeatedly invoke that decoder. Packed versus
memory lowering also changes surrounding instructions, so disassembly and
identity controls do **not** prove that every nanosecond of the packed regression
comes from this one dispatch.

Current shared library:240 dedicated cast-handler symbols,5520 summed symbol
bytes (excludes alignment); `size`:text3700453,data347216,bss16. These are absolute
current-build figures, not growth relative to the earlier runtime. Overall
code-size improvement from any proposed change remains unmeasured.

## Proposed design — subsequently approved, tested and not adopted

Preserve the typed ISA/verification contract and separate it from physical
execution. Mark raw unary cell identity explicitly in the authoritative
`gen/semantics.lua` transfer definition. `gen/banked.lua` derives the transparent
EXT selector set from that metadata and `tools/opcodes.lua`, not duplicated
selector numbers or a new scalar algorithm.

For these selectors only, the existing EXT.A/B entry binding advances by the
manifest length and dispatches directly to the next instruction in the same
cache state. All carried values, backing cells and frontiers remain untouched.
Other EXT operations keep their existing scalar bindings. Remove the now-unused
separate bitcast selector handlers; the private fallback selector table has
entries only for the operations routed through it. Identity-selector holes are
not new ISA rejection: verified casts take the explicit transparent branch.
No consecutive-cast skipping loop or global hot-dispatch check is proposed.

Files:authoritative metadata and interpreter generator, their generated outputs,
cache/ISA tests where necessary, evidence/docs/worklist. No frontend/ABI/layout,
optimizer, format decoder or native/threaded algorithm change. Bytecode still
contains both kind transitions; wrong kinds/profiles/selectors still reject at
verification. No new allocator, predecoded module image, residual IR, compatibility
encoding, safepoint or opaque fallback. Trap positions, stack limits, C and ABC
continuations remain unchanged.

Alternatives: accept the small interpreted cost and proceed directly to ownership;
change encoding (unnecessary compatibility break); predecode an execution image
(additional per-module memory/subsystem); check every dispatch for transparent
instructions (risks the ordinary hot path). None is implemented.

Validation after approval: exact-state poisoned cache oracle, both destinations
and backing-only states, live prefixes/C aliases, NaN payloads, profile/kind/
truncation/reserved-selector negatives, existing all-form and packed suites,
other EXT arithmetic/branches, full incremental validation. Performance: same
paired lowering probes and dispatch controls, plus ordinary core/EXT workloads
to detect branch/code-layout regressions; compare generated/shared-library code
sizes. A fast path is an expectation, not a measured improvement. Reject or
revisit it if the measurements do not support it. Ownership/final collector
removal remains the next priority, not the unrelated optimizer/access-efficiency
work.
