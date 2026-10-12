# ABC2 revision-6 modules

This document specifies the typed formats implemented by `src/module.c`,
`src/memory_module.c` and `src/verify.c`. Instruction bytes and selected-stack
semantics are defined in [symmetric-isa.md](symmetric-isa.md), generated from
`tools/opcodes.lua`. Format revision and capability profile are independent.

Only **revision 6, profiles 1–4** load in the current runtime. Old revisions are
rejected, not translated or reinterpreted. Profile 5/dynamic execution is not
implemented by this loader. Profile-specific documents supplement, but do not override, this
header or the revision-6 instruction contracts.

## Header and sections

All serialized integers are little-endian, without padding. Code offsets are
relative to the code section. The header is 16 bytes:

| Offset | Field | Value |
| --- | --- | --- |
| 0 | 4 bytes magic | `ABC2` |
| 4 | u16 ISA/format revision | 6 |
| 6 | u8 target pointer size | 8 |
| 7 | u8 capability profile | 1, 2, 3 or 4 |
| 8 | u32 section count | as below |
| 12 | u32 reserved | 0 |

| Profile | Capabilities | Required section tags |
| --- | --- | --- |
| 1 | Integer cells | 1–3 |
| 2 | Typed memory, addresses and binary64 | 1–6 |
| 3 | Memory plus indirect callables | 1–8 |
| 4 | Callables plus named foreign calls | 1–9 |

Each section is a u32 tag, u32 payload length and that many payload bytes.
Exactly one of each required section is present; order is arbitrary. Unknown or
duplicate sections, truncation and trailing bytes reject. Modules are limited to
16 MiB. Function/export/indirect-site/relocation tables have at most 65,536 entries;
extern tables have at most 65,535. These are implementation limits, not ISA laws.
Memory profiles require little-endian host memory.

### 1. Functions

A u32 count followed by function records. Each starts with four u32 fields:

1. entry offset;
2. argument cell count;
3. result cell count;
4. hidden aggregate result byte size.

Entries strictly increase, starting at zero. Each function ends at the next entry
or the end of code. At least one function is required; argument/result counts
are each 0–255.

Profile 1 records end after those 16 bytes: every cell is integer-kind and the
hidden result size must be zero. Profiles 2–4 append one kind byte per argument,
then one per result: **0=integer, 1=address, 2=binary64**. A nonzero hidden result
size requires an address-kind first argument and cannot exceed 16 MiB.
Signatures describe raw cells, not source-level ownership or integer widths.

### 2. Code

Nonempty revision-6 instruction bytes. The core map contains 124 A/B pairs,
EXT.A/EXT.B, and six neutral instructions. Fourteen families use EXT selectors;
there are 282 public selected core/extended forms. An EXT prefix, selector and
operands form one instruction and one provenance PC.

There are no serialized internal quickened instructions or mutable cache words.
In particular, CALLI.X contains one count byte after its opcode (two bytes
total); TCALLI.X contains two (three bytes total). Their signatures are in section 7, not embedded observation records.
Instruction capability requirements must be satisfied by the module profile.

### 3. Exports

A u32 count followed by records of u32 function index, u16 name length, and
unterminated name bytes. Names are unique ASCII identifiers, 1–255 bytes long;
a digit cannot be the first character. The function index must exist.

### 4–5. Writable data and read-only data

Raw bytes, concatenated into one image: writable data first, then rodata. Either
section may be empty. Combined image size cannot exceed 16 MiB. Offsets in image
instructions refer to this concatenation. Direct image stores must stay within
the writable prefix; direct loads must stay within the image.

Each VM/module pair owns a separate initialized image, retained across calls.
Unsafe pointer operations remain subject to the memory profile's embedding
obligations; verification is not a native-memory sandbox.

### 6. Load-kind annotations

A u32 count followed by records of u32 instruction offset and u8 kind. Offsets
are unique and must identify an annotatable load. Without an annotation a load
has integer kind; address/float loads require valid width/kind metadata. These
are verifier facts, not runtime object tags.

### 7. Indirect-call signatures

A u32 count followed by records with the same field/kind layout as typed function
records, except that the first field is the original CALLI/TCALLI instruction
PC. PCs strictly increase and must correspond to the indirect instructions.
There must be at least one argument; the first is an address-kind environment.
Instruction counts and site metadata must agree.

CALLI.X gathers arguments, including the environment, from X and takes the target
from the opposite stack. The target must be an exact public entry address in the
same module with the matching complete ABI, not an arbitrary native entry or an
interior code address. A HALT-containing function is not bytecode-callable.

### 8. Code-address relocations

A u32 count followed by pairs of u32 writable-image offset and u32 function index.
Each relocation occupies eight bytes entirely within writable data. Relocations
are sorted and nonoverlapping; target functions must exist and be callable.
Runtime initialization writes their public module-code entry addresses, not
native stencil addresses. Native/heap pointers are not serialized as relocations.

### 9. Foreign declarations

A u32 count followed by records of u8 argument count, u8 result count, u16 name
length, argument kind bytes, result kind bytes, then unterminated name bytes.
Names obey the export identifier rules and are unique within the extern table.
Kinds are integer/address/binary64. Supported signatures have at most ten
arguments (at most six integer/address and four float arguments) and at most one
result. Bindings are supplied by the embedding API; bytecode cannot resolve
arbitrary host symbols. FCALL.X consumes arguments and produces results on X.

## Verification and call boundaries

Loading copies and verifies input before publishing a module; no input-buffer
pointer is retained. Every instruction decodes completely inside its function.
Branches remain within that function and land on instruction starts. Unreachable
instructions and encoded edges still validate; stack effects are checked on
reachable paths, with compatible typed A/B/C shapes at joins.

At function entry, **private A and B are empty**. C contains the argument vector;
argument zero is C0. Caller operand prefixes and continuation state are not
accessible to the callee. This is true even for `CALL.X f 0`: caller operands do
not become implicit callee arguments. There is no operand-entry function ABI.

- `CALL.X f n` consumes the ordered argument vector from X, establishes C
  arguments and a continuation whose result destination is X.
- `RET.Y k r` removes the complete k-cell local C frame and supplies exactly the
  declared ordered r-result vector from Y; the other private operand stack must
  be empty. The continuation destination and return source are independent.
- `TCALL.X f k n` replaces the complete private operands/C frame with the new
  arguments and preserves the original continuation. Tail result signatures
  must match, including typed kinds and hidden-result metadata.
- Indirect calls follow the same transport and add exact-target/full-ABI checks.
- `HALT.X` is permitted only in host-entry-only functions, with an empty local C
  frame, the declared result vector on X, and the other private stack empty.
- `ABORT 0` rejects.

Counts include visible C cells/frame blocks under their layout contracts, not
access to the protected continuation. Capacity checks and unsafe-memory rules
remain part of their existing runtime contracts.

## Assembly and execution

```text
.function main 0 1
    PUSH.A 6
    PUSH.B 7
    MUL.A
    RET.A 0 1
.export main
```

`.function name argument_cells result_cells` begins an integer-signature function.
Memory-capable profiles support explicit argument/result kind strings and hidden
result size. `.export name [function_name]` exports a function; absent explicit
exports, `main` is exported if present. Labels are function-local. Calls name
functions and branches name labels; semicolons begin comments. Commas between
operands are optional. Mnemonics are case-insensitive; identifiers are not.

Generated names (`PUSH8_A`) and dotted forms (`PUSH8.A`) are accepted. `PUSH.X`
selects an 8-, 32- or 64-bit encoding without changing the specified bits;
`CGET.X`/`CSET.X` select short or general depth forms. Selected instructions require
an explicit bank: bare CALL/RET and old COPY.AB/MOVE.BA spellings are not aliases.
Decimal, hexadecimal and binary integers are supported; out-of-range operands
reject rather than truncate. Output is verified before atomic replacement.
`abc dis` is an annotated listing, not round-trippable assembly.

Execution mode is host configuration, not a module field: interpreted, eager
native or lazy native. Runtime execution does not require the build-time
optimizer. Modules remain immutable; per-VM/module indirect observations are
separate from bytecode and native linkage. No bytecode quickening occurs.

Calls reset operand/control stacks, including after errors, but do not roll back
image writes. The API returns raw cell bits in declared vector order and leaves
result outputs unchanged on failure; the CLI prints cells as signed integers.
Modules may be shared by separate VMs; a VM may not execute concurrently with
itself. Runtime ownership retains modules while VM images need them, and native
image state is destroyed before releasing that module reference.

ABC calls use explicit continuations, not recursive host execution. Stack limits
include the required continuation resources. There is no semantic instruction
fuel budget. Language aborts retain their reason and original bytecode offset.

## Compatibility and deferred work

This remains a development format, not a promised stable interchange ABI.
Incompatible encodings require an explicit revision change. Historical optimized
instruction buffers are not current module files.

The collector-free dynamic/ownership target is documented in
[dynamic-profile.md](dynamic-profile.md) and [owners-references-ids.md](owners-references-ids.md).
It supersedes GC/trace-descriptor proposals but does not make profile 5 loadable,
assign revision-6 dynamic selectors or reinterpret old tracing metadata as releases. Source partial evaluation and its staging
policy are separate frontend work, not additional VM capability profiles.
