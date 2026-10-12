# Threaded residual execution

Implemented for the current typed profiles; expanded four-mode validation passes.
The capacity-frontier blocker exposed by unoptimized nullary lambdas is corrected
at the shared proof boundary: signed frontiers are compared before conversion,
negative frontiers cannot inflate capacity knowledge, and only checked positive
requirements reach guard emission. Frame layout, unsigned guard records and
physical-capacity policy are unchanged. There is no truncation adapter or fallback.
See `../research/experiments/threaded-residual/integration/capacity-frontier/README.md`.

Performance acceptance remains open. Short pilots are not a general speedup claim;
all raw runs, including an initial run-order mistake and its correction, are retained.

## Policies

| CLI | Preparation | Execution |
| --- | --- | --- |
| `--jit=off` | existing interpreter preparation | original ABC handlers |
| `--jit=threaded` | eager residualization | seven-register threaded handlers |
| `--jit=lazy` | lazy residualization | eight-register native stencils |
| `--jit=eager` | eager residualization | eight-register native stencils |

Existing `--interpreted`, `--lazy` and `--compiled` flags remain aliases. Default
execution is unchanged: interpreted. `ABC_EXEC_THREADED=3` appends to the public
C mode enum without renumbering existing values. Call `abc_vm_load` before residual
execution. Staging accepts `mode="threaded"`; source computation still uses the VM.

The shared family/continuation threshold is 16, not a total per-PC cap. Build-time
tooling remains at 8. This does not implement the caller-owned-region target in
`../REFACTOR.md`, nor the older proposed lazy residual-ABC representation.

## One residualizer, two output bindings

`src/residualize.c` owns symbolic execution, folding, captures, register/home
placement, spilling, virtual continuations, frame transport and version
conformance. Available registers come from the output binding: seven threaded,
eight native. Recursive argument transport and entry descriptors use that same
count. There is no second allocator, residual value IR, placement-reconstruction
pass, scalar fallback or runtime optimizer dependency.

`src/execution_emit.h` defines preparation-time labels and bound operand packets.
Emission consumes packets immediately into final output; they are not a stored
intermediate program. Labels do not expose machine addresses or tape offsets to
the residualizer. Frame transport remains separate from control transfer.

- `src/native_emit.c`: stencil copying and native relocations.
- `src/native_image.c`: native mappings, labels, fixups, W^X publication, lazy
  stubs and their private saved-register state.
- `src/threaded_emit.c`: tape construction, offset-based labels/fixups, publication
  and execution. No executable mappings or native-code generation.
- `gen/execution_forms.lua`: bound form identities, operands and availability.
- `gen/execution_compute.lua` and `gen/semantics.lua`: shared computations.
- `gen/stencils.lua` / `gen/threaded.lua`: native/threaded realizations.

There are 3,770 native forms and 2,950 threaded handlers. Eight-slot form-ID
coordinates are retained during preparation; threaded forms naming register 7
and native lazy-entry machinery are unavailable. Form IDs are not tape opcodes.

## Exact tape representation

Target: x86-64 little-endian, aligned 8-byte words. Every record begins with an
absolute handler function pointer and then its bound operands. Register identities
and record length are fixed by handler choice. No opcode, register-number, length
or ordinary next-pointer fields are stored.

| Form | Following words | Bytes |
| --- | --- | ---: |
| move / unchecked register arithmetic | none | 8 |
| constant / immediate arithmetic | u64 bits | 16 |
| HOME access / frame rebase | i64 byte offset | 16 |
| checked register arithmetic | u64 packed error | 16 |
| conditional/unconditional branch | tape pointer | 16 |
| store continuation | i64 C byte offset, tape pointer | 24 |
| continue through register | none | 8 |
| capacity guard | u64 required bytes, end pointer, packed error | 32 |

`form.operands` specifies the remaining memory, foreign, resolver and terminal
layouts. Bound operand packets omit the target pointer: that operand is an opaque
label until publication. Offsets in the common interface are bytes; native-only
cell-offset/immediate packing happens inside the native binding.

Packed errors: status [7:0], reason [15:8], original ABC PC [47:16], zero [63:48].
Builder relocation records hold word offsets, never pointers into movable tape.
Publication resolves targets after allocation is stable; published threaded tape
cannot be extended. Both bindings reject ordinary emission after publication;
native lazy preparation privately opens and republishes its mapping.

## ABI, calls and lifetime

Threaded handlers carry `ip, asp, bsp, csp, r0…r6` under `preserve_none`, with
`musttail` dispatch. Native retains three pointers plus eight values. The initial
seven-register ABI probe found no calls or stack spills in its tested pure
handlers; this does not assert spill-free code for every helper-calling form.

Real threaded calls store resume-tape addresses in existing continuation cells;
returns restore the frame and dispatch through them. ABC recursion does not use
recursive host execution. Native continuations remain native addresses. Public
callable identities remain exact module function entries, not private code/tape
addresses. Target/signature/capacity checking and observing-site histories remain
shared. CALL destination and RET source remain independent.

`abc_execution_image` owns either emitter; code and size fields are diagnostic
views, not additional storage owners. Eager preparation state is released after
entry publication. Native lazy preparation retains its common compiler state.
Image destruction precedes module release. Threaded persistent module data does
not inherit native low-address allocation constraints. Abort persistence, stack
reset, protected prefixes, original-PC diagnostics and foreign effects are unchanged.

Managed execution/GC support, lazy threading, mixed-tier frames, new fusion,
source virtual places/demands and region ownership remain separate work.

## Validation and measurements

Evidence: `../research/experiments/threaded-residual/integration/`.

- Full suite: 113 independent oracle cases / 904 mirrored four-mode executions;
  all 282 public forms assembled.
- 660 continuation executions; 168 return-transport checks including nine-argument
  recursion crossing the seven/eight-register boundary.
- 48 lifetime cases across all mode pairs; 280 staging-session checks.
- 360 capacity-frontier cases: A/B frame shrinking, subsequent allocation,
  tight physical limits, repeated calls and original error PCs. Lambda coverage
  now includes 80 four-mode executions, including unoptimized nullary functions.
- Native fragment byte checks, catalog/C addressing assertions, and native/threaded
  label, record-layout, builder-growth, continuation, publication and trap tests.
- Source/staging execution with the optimizer disabled remains supported.

Four rotated rounds, seven timed calls per batch, CPU 0, identical bytecode:
threaded/off paired median time ratios were loop **0.439**, branch **0.463**,
Fibonacci **1.256**, memory **0.825** (`rotated-final/`). Fibonacci was slower in every pair
(1.244–1.268), exceeding the roughly 10% tolerance. Native execution remained faster
on these controls. A post-fix pilot (`capacity-frontier/fixed/`) observed a smaller
Fibonacci penalty (1.056 median, 1.022–1.103 range), with substantial noise on other
workloads. All four tape/native body-size controls were unchanged; this is not
proof of a performance improvement from the capacity correction. No automatic
tier promotion or default-policy change is made.

Threaded tape sizes were 1,424 / 6,352 / 1,784 / 672 bytes respectively. The shared
handler object adds 111,043 bytes of text, 60,320 bytes of relocation-read-only
form-table data and 61,480 bytes of unwind data, excluding debug sections/alignment.
Those shared costs must not be omitted in favor of tape-only comparisons. Full
retained-metadata/peak-preparation accounting, exhaustive handler-placement testing,
fresh whole-runtime sanitizer coverage and broader performance attribution remain
open. Passing functional tests does not establish universal speed or architectural
completion beyond this backend integration.
