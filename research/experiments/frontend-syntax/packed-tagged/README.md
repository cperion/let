# Packed tagged qualification

**Current update:** the approved explicit float-bitcast correction is implemented
and the packed suite is now integrated and passing. The earlier nested-extraction
shift defect is also corrected. See [float-bitcast evidence](float-bitcasts/README.md)
and `shift-fix/` logs. Broader resource/padding qualification and the independent
optimizer frame-access defect remain open. The text/logs below preserve the original
failed qualification, not current admission.

## Historical blocked qualification

The new `frontend/tests/packed_tagged.lua` is an unfinished qualification suite,
not integrated into `validate-slet`. It currently fails. No implementation changes
were made to `abc.lua` during this qualification step; its earlier edits remain WIP.

Run from `frontend`:

```sh
/tmp/lua-compat tests/packed_tagged.lua
/tmp/lua-compat ../research/experiments/frontend-syntax/packed-tagged/probe.lua
```

`qualification.log` preserves the suite failure. `probe.lua` independently checks
three minimal cases using the public raw-cell VM API, bypassing only the scalar-only
source staging transport restriction, not module verification or VM checks.

## Float kind boundary: design change required

The ABI carries sums in integer-kind u64 cells. Revision 6 distinguishes integer and
float kinds and has no register bit-reinterpretation operation (see symmetric-isa.md,
float contracts). Memory ST64/load-kind transitions were providing bit reinterpretation
in the old allocated representation.

- WIP f64 construction keeps a float-kind cell in a sum result declared as integers.
- WIP extraction keeps an integer-kind cell in a result declared as float.
- Both fail verification with `RET disagrees with frame or result contract`.
- Committed `9cfd7f65` lowering passes both exact negative-zero probes, optimized and
  unoptimized, in interpreted/threaded/eager/lazy modes.
- The WIP fails before execution in all configurations. Numeric conversion cannot
  replace bit reinterpretation without changing values (including NaN payloads).

Evidence: `current.log` and `baseline.log`. Baseline used a copied current frontend
with only `abc.lua` restored from `9cfd7f65`, and the same runtime build.

No temporary-memory fallback, numeric conversion, verifier weakening or new opcode
has been implemented. The frontend-only design cannot deliver its approved f64 scope
without revisiting this boundary. A selected-stack float/u64 bit-reinterpretation pair
is proposed, not approved or implemented; encoding/version policy must be explicit.

## Nested extraction: optimized execution mismatch

Inner sum payload: `{a:u8,b:u16,c:u32}`, size 12. Outer sum places this inner value at
byte offset 4. Extraction crosses cell boundaries and returns two packed cells.

Input: `0, 0x89abcdef34560012`.
Expected output: `0x3456001200000000, 0x89abcdef`.

- WIP unoptimized: passes all four modes.
- WIP optimized: interpreted passes; threaded, eager and lazy return zero for the
  second result cell. Root cause has not been established; no workaround added.
- Committed lowering rejects this particular fixture during assembly because it
  emits CALLOC under an insufficient capability profile. Thus baseline equivalence
  cannot be claimed for this case.

This is separate from the earlier preserved optimizer/frame-allocation failure.
Other planned coverage (complete storage boundaries, resource limits, repeated
construction, exact floating arithmetic, and measured performance) remains unfinished.
The previously passing integrated suite did not establish these contracts.
