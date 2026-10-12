# Packed tagged values and explicit storage

Status: **packed lowering and approved explicit float-bitcast extension implemented;
focused and full incremental validation passed**. The earlier nested-extraction
shift defect is corrected. F2BITS/BITS2F now supply exact integer/binary64 kind
transitions, using additive revision-6 EXT selectors 0E/0F (profile 2+); earlier
engines reject those selectors. No numeric conversion or scratch-memory fallback
is used. The user approved this ISA extension after the original frontend-only
qualification exposed the missing contract.
The focused suite is integrated; broader resource/padding/loop qualification and
the separate optimizer frame-access defect remain open. Measurements show mixed
runtime results, including interpreted regressions; this is not a universal speedup
or completion of F04. See WORKLIST.md and
[qualification evidence](../research/experiments/frontend-syntax/packed-tagged/float-bitcasts/README.md).
This is not a new source feature, bytecode revision or replacement optimizer.
Investigation and measured probes:
[composition investigation](../research/experiments/frontend-syntax/word-bindings/composition-investigation.md).

## Problem and invariant

Supported address-free tagged values already cross the ABC call ABI as packed u64
cells. `frontend/let/abc.lua` nevertheless copies tagged value parameters into frame
blocks and reserves blocks for construction, reads and call results. Tag tests and
payload extraction then use addresses. These representation-induced CALLOC operations
prevent the existing build-time optimizer from virtualizing the containing functions.

**Values stay in cells; storage belongs to places.** A tagged type is not by itself
an allocation requirement. Actual addressable objects remain explicit frame storage.
Keep the single word elaborator, ordinary Ir.Call/Indirect, existing native/threaded
register allocation and the existing optional ABC optimizer.

## Scope and authoritative representation

Use the existing `abiComponents` admission and packed-cell contract for internal
values as well as call transport. Do not separately invent an internal sum format.
Retain existing type layout as the authority for tags, payload offsets, alignment,
field offsets, array strides and logical byte size.

This covers the currently admitted raw/address-free tagged ABI, including supported
integer, bool, f64, record, fixed-array and nested tagged payloads. It must not
silently admit previously rejected address-bearing/managed sums or additional
aggregate call ABIs. Existing other aggregate representations remain unchanged.
No fixed-size-only shortcut for the measured option(u32) fixture.

## Producers, consumers and data flow

1. **Value parameters:** bind packed cells directly to their incoming C parameter
   slots. Remove the tagged-parameter block allocation and initial copy.
2. **Value definitions:** reserve ordinary component slots for tagged Let/Read,
   ConstructVariant, direct/indirect call results and tagged VariantPayload results.
   Copies, aliases, argument gathering and returns use those same components.
3. **Construction:** initialize a new packed result, insert the numeric tag and
   encode the supplied payload according to the existing byte layout. Evaluate the
   payload once; do not re-evaluate its fields for each destination cell.
4. **Inspection:** VariantMatches and Switch extract the low-width tag. Preserve
   existing switch fallback behavior; do not introduce new invalid-tag semantics.
   VariantPayload decodes the selected payload to its existing value representation.
5. **Unaddressed local tagged storage:** whole-value reads/writes can use mutable
   component slots, like existing scalar locals. A local whose address or borrow
   is taken keeps an actual frame block, selected by existing address-use analysis.
6. **Real places:** reads pack bytes into values; writes unpack values into bytes.
   BorrowArg, Addr, pointer access, record/array storage and receiver lifetime rules
   remain explicit. A value is not assigned a hidden stable address.

Remove the tagged-value `valueBlock` assumption and the `initialParameters` frame
copy path. Retain frame blocks for real storage; do not put a new facade over the
old mandatory tagged-value allocation path. Local slot selection must precede
emission, not require a new placement-reconstruction pass.

## Packing and bit preservation

One set of layout-driven packing/extraction helpers serves construction, payload
access and value/place bridges. These are static layout operations emitted using
ABC instructions, including the approved raw-kind bitcasts, not host evaluation of source values.

- Preserve the existing little-endian layout, tag numbering and packed ABI order.
- Match existing narrow-load zero/sign extension and store truncation exactly.
- Treat f64 payloads as 64 bits during transport. Never convert them numerically
  through integers or host Lua numbers. Test arithmetic on extracted floats as
  well as negative-zero and NaN-payload round trips in every backend.
- Support byte spans crossing cell boundaries, particularly nested sums whose
  logical size or alignment is not a multiple of eight. No shift-by-64 shortcut.
- Memory bridges access only the type's logical bytes. A rounded ABI cell is not
  permission to read or overwrite the following field or allocation padding.
- Forwarding an existing packed value copies its cells unchanged. Fresh construction
  starts from zero and writes the tag and active payload. Nested packed payloads
  contribute their logical bytes, not bytes beyond their logical extent.

**Approved padding policy:** unused bytes introduced by fresh construction,
and ABI tail padding introduced by a bounded memory read, become zero. They do not
inherit stale bytes from a previously used constructor frame slot. Active payload
bits are preserved. This is deliberate canonicalization of unused representation
bits, not a promise of bitwise equivalence with old stale-padding behavior. Existing
packed-value forwarding remains bit-for-bit; materialization can discard ABI-only
padding that is not part of the memory object.

## Control, effects and resource policy

Word bodies, local returns, defers, captures and handler supply evaluation order are
unchanged. Do not compose ASTs or duplicate continuation suffixes. Recursive and
unknown callable execution retains ordinary calls and explicit ABC continuations.

The optimizer's ALLOC/FREE exclusion remains unchanged. Actual allocation effects
are not discarded. Pure packed operations use existing typed scalar operations;
no second scalar algorithm, native value IR, allocator or GC root mechanism is added.
Runtime execution remains independent of abc-opt, including optimizer-disabled builds.

**Approved resource policy:** generated programs may have different A/B/C
high-water marks and consequently different minimum stack capacities/failure PCs.
Fewer artificial frame copies do not imply that every case uses less stack: packing
has operand-stack costs. All cells, temporaries and calls remain accounted for by
ordinary verification and runtime limits. Keep existing checks/statuses, real block
bounds, safepoints and trapping operations. Do not retain dummy allocations or weaken
checks to simulate the old compiler's resource footprint.

## Files and integration

- `frontend/let/abc.lua`: representation/slot selection, packing and extraction,
  construction/matching, value/place bridges, parameter setup and obsolete-path removal.
- `frontend/tests/lowering.lua` and focused packed-tagged tests: structural and exact
  representation contracts, including real-storage boundaries and unsupported types.
- `frontend/tests/symmetric.lua` or equivalent focused tests: both operand destinations,
  untouched live neighbors and multi-result/argument transport.
- `Makefile`: integrate focused tests into the existing validation boundary.
- `docs/slet-subset.md`, this document, `WORKLIST.md` and experiment evidence: actual
  support, compatibility decisions, measured results and unresolved failures.

The approved extension updates `tools/opcodes.lua`, `gen/semantics.lua` and generated
metadata/folding, verifier, existing unary backend bindings, optimizer emission,
`schema/residual.asdl` and its builder/validator. Native/threaded casts retain the
same symbolic value and placement without emitting a stencil. The optimizer must
retain explicit bytecode kind transitions even for folded raw constants. Residual
tooling exposes typed FloatToBits/BitsToFloat operations; portable C still rejects
float operations rather than implying general float support.
Canonical source/IR schemas, optimizer eligibility, public ABI/layout, continuations
and GC/root policies are unchanged.

## Validation and measurement

Validate both optimized and unoptimized programs in interpreted, threaded, eager and
lazy modes. Cover every alternative; unit-only sums; narrow/signed/full-width scalar
payloads; f64 arithmetic and exact bits; record/array/nested payloads; odd logical sizes;
forwarding; direct/indirect calls; results; local assignment; explicit address/borrow;
neighbor fields and guarded memory boundaries; and currently unsupported ABI cases.
Test construction in repeated control flow so unused bytes cannot retain a previous
payload. Test nonzero incoming padding separately from fresh construction.

Structural checks must prove that value-only cases have no CALLOC/FADDR/indirect memory
traffic, while actual addressable objects still do. Check packed cells against known
ABI encodings, not just final scalar answers. Run tight-capacity, trap and lifetime
checks without asserting identical old resource thresholds. Re-run full validate-slet.

Measure raw and optimized module sizes, remaining call sites and actual execution and
preparation costs against fe042d9f and the earlier syntax baseline. Include runtime
inputs and both alternatives so constant folding to 42 is not the only benchmark.
Do not promise that every handler disappears or that every payload becomes faster.
