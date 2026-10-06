# ABC2 module profiles (experimental)

This document specifies the formats implemented by `src/module.c` and
`src/memory_module.c`, not a claim that the full ISA in `spec.md` is complete.
All serialized fields are little-endian, without padding. Code offsets are
relative to the code section. Existing version-1 integer modules remain valid.
The version-2 memory profile adds explicit kinds, frame blocks and image sections; version 3 adds indirect callables; version 4 adds typed named foreign calls. Proposed profile 5 adds dynamic cells, generic operations and GC metadata. See [memory-profile.md](memory-profile.md), [callable-profile.md](callable-profile.md), [foreign-profile.md](foreign-profile.md), and [dynamic-profile.md](dynamic-profile.md) for their formats and safety contracts.

## Version 1: integer profile

This profile has no addresses, floats, memory image or externs. All parameter
and result cells are integers (including normalized bools).

## Header: 16 bytes

| Offset | Field | Value |
| --- | --- | --- |
| 0 | 4 bytes magic | `ABC2` |
| 4 | u16 format version | 1 |
| 6 | u8 target pointer size | 8 |
| 7 | u8 profile | 1 (integer-only) |
| 8 | u32 section count | 3 |
| 12 | u32 reserved | 0 |

Each section has a u32 tag and a u32 payload length, followed by the payload.
Exactly one of each section below is required. Order is arbitrary. Unknown
sections, duplicate sections, truncation and trailing file bytes reject.
Modules are limited to 16 MiB; function/export tables to 65,536 entries.
These are loader limits, not ISA laws. Future profiles must introduce explicit
kind metadata rather than treating unknown types as integers.

## Sections

1. **Functions:** u32 count, then `count` records of four u32 fields: entry
   offset, argument cells, result cells, hidden aggregate result size.
   Entries are strictly increasing; the first is zero. A function ends at the
   next entry or code-section end. Counts are 0–255. Hidden result size must
   be zero in this profile.
2. **Code:** instruction bytes. Opcode values, lengths and kinds come from
   `vm/gen.lua`'s integer metadata, extended by `tools/gen_opcodes.lua` for the
   public runtime. This profile accepts only public integer-core instructions.
   Internal quickened opcodes reject even in unreachable code.
3. **Exports:** u32 count, then records of u32 function index, u16 name length,
   and un-terminated ASCII name bytes. Names are unique ASCII identifiers,
   1–255 bytes; the first character cannot be a digit.

**Stability:** this is a development format, not yet a promised interchange ABI.
Any opcode renumbering or incompatible section change must increment the format
version and update loader/producer tests. Optimized prototype instruction buffers
are not module files and must not be passed directly to the loader.

## Verification and entry contracts

The loader copies and verifies code before publishing a module. It retains no
pointer into the caller's input. Every instruction must decode inside its
function. Branches stay inside that function and target instruction starts.
Direct calls target function entries with matching argument counts. Tail callees
must have the same result count as the current function.

At function entry, private A and B are empty and C contains the argument cells
above an inaccessible return address. Abstract depths are relative to those
private regions, not the caller's operands. Integer instructions cannot reach
a caller's A/B prefix or its C frame. Every reachable join has identical A/B/C
depths. `RET k r` must consume the complete C frame and leave exactly r cells
on A, zero on B, with r matching the function table. `TCALL` must similarly
consume the entire current operand region and replace its complete C frame.
Unreachable bytes still decode and their encoded edges still validate; stack
effects are checked along reachable paths.

`HALT` is allowed only in host-entry-only functions, with an empty local C frame
and exactly the declared A results. A function containing `HALT` cannot be called
or tail-called from bytecode: use `RET` for callable functions. `ABORT 0` rejects.
No memory instructions are enabled; this profile does not implement the full
specification's block-layout/address-kind verifier yet.

The public runtime does not quicken or mutate modules. Future optimized-engine
integration must use a separate execution copy for site rewriting; internal
opcodes must never leak into a saved module.

## Assembly

```text
.function main 0 1
    PUSH.A 6
    PUSH.B 7
    MUL.A
    RET 0 1
.export main
```

`.function name argument_cells result_cells` begins a function. `.export name
[function_name]` exports a function; when no exports are written, a function
named `main` is automatically exported. Labels are local to each function.
Calls name functions; branches name local labels. Semicolons begin comments.
Commas between operands are optional. Case matters for labels and function
names; instruction mnemonics are case-insensitive.

The assembler accepts generated opcode names (`PUSH8_A`, `CGET0_A`) or dotted
forms (`PUSH8.A`, `CGET0.A`). `PUSH.X` selects a sign-extended 8-, 32-, or 64-bit
encoding without changing the input's bits. `CGET.X`/`CSET.X` select short or
depth forms. `CALL` defaults to `CALL.A`; `BxxI.A` is accepted for the A-only
immediate branches. Decimal, hexadecimal and binary integers are supported.
An operand that does not fit its encoded width rejects; nothing silently
truncates. Output is verified before atomically replacing the destination.

`abc dis` is a human-readable annotated listing, not round-trippable assembly.
CLI results are printed as signed 64-bit integers in source order. The embedding
API exposes raw uint64_t bits and writes no outputs on failure.

## Proposed profile 5: dynamic values and managed storage

Profile 5 extends profile 4. It is a bytecode capability profile, not a source-language profile, and loading it never selects eager or lazy execution. The 16-byte header uses format version 5, pointer size 8, profile 5, section count 12 and reserved zero.

Sections 1–9 retain the foreign profile's encoding. Cell-kind bytes add `3=any`; integer, address and float remain 0, 1 and 2. Kind 3 is valid in internal function arguments/results and verifier states. Exports and extern signatures containing kind 3 reject with `abi-any`. A conforming Let producer also rejects managed references, slice bases or callable environments in a C ABI with `abi-managed`; the module's scalar address kind alone cannot distinguish that source-level provenance from an explicitly unsafe raw pointer. A dynamic `any` access is one aligned 64-bit kind-3 access. Managed `ref`, slice-base and callable-environment cells retain address kind 1, but profile-5 descriptors and GC-root records distinguish them from raw or strict-borrowed addresses inside the module. Overlapping, narrow or ownership-inconsistent accesses reject. Core instructions do not silently accept kind 3; only public dynamic `EXT` selectors and kind-checked image loads/stores consume or produce it.

The additional required sections are:

10. **Dynamic descriptors.** A u32 count followed by length-delimited records. Every record starts with u8 tag, u8 flags and u16 payload length. Descriptor tags are primitive, pointer, slice, signature, record, array, sum and closure-layout. A primitive payload is one u8 code naming unit, bool, each exact integer width, f64, string, `any` or open word; the code determines its typed stack-cell count (`unit=0`, `string=2`, open word and `any=1`, all other primitives=1). A pointer payload contains u8 ownership class (`raw-ptr`, `strict-borrow` or `managed-ref`), three zero bytes and one u32 target-descriptor index. A slice payload has the same ownership-class field and one u32 element-descriptor index; a managed slice traces its backing allocation through its address cell. A signature contains u8 requirement count, u8 result count and one u32 descriptor index per component. A record contains u32 byte size and u32 field count, then for each data field a rodata name offset and length, byte offset and descriptor index. An array contains u32 byte size, u32 element count and one element-descriptor index. A sum contains u32 byte size, u32 discriminant offset, u8 discriminant width, u8 case count, u16 zero, then per case the discriminant bits, payload offset and payload-descriptor index. A closure layout contains a signature-descriptor index and a record-descriptor index for captures. All integers are little-endian; reserved flags, fields and padding are zero. Names and ranges must lie in rodata; layouts, alignments and recursively derived dynamic/managed-reference trace locations must be valid. Descriptor references are in range and acyclic except when a pointer or slice descriptor crosses the cycle. The generated descriptor table defines which descriptor tags and ownership classes each dynamic selector accepts.
11. **Dynamic constants.** A u32 count followed by records of u8 kind, u8 flags, u16 payload length and payload bytes. Kinds are exact integers, f64, bool, unit and permanent string. Flag bit 0 marks an integer source literal as adoptable by a generic literal operation; every other flag bit is zero. Numeric payloads are canonical little-endian bits; every NaN payload must use the profile's single canonical quiet-NaN encoding, and noncanonical NaN constants reject. A string payload is u32 rodata offset plus u32 byte length. No heap or native address is serialized.
12. **GC roots.** A u32 count followed by records of u32 writable-image offset and u32 descriptor index. Each record names a complete descriptor-sized value in writable data; descriptor traversal identifies its `any` cells, managed references, managed slice bases and managed callable environments. Ranges lie wholly in writable data, are sorted, unique and non-overlapping. On-disk `any` slots contain zero and the loader replaces them with the VM-private canonical dynamic `unit`; managed address slots contain zero until module initialization or a relocation supplies a live object. No heap or native address is serialized. Raw pointers and strict-borrow descriptor paths are skipped, and rodata or unlisted image cells are never traced as collected roots.

Public dynamic selectors, descriptor meanings, stack effects, aborts and tracing obligations are normative in `dynamic-profile.md`. The loader uses generated extended-opcode metadata to decode and verify them, including unreachable instructions. Internal quickened selectors remain forbidden.

The verifier requires joins to agree on the scalar kind `any`, not on a run-time tag. Boxing and casting descriptor indices must exist, the selector must permit that descriptor class, and its derived cell count must match the surrounding stack effect. Dynamic-call argument count, requested-result count and result-adjustment mode are part of the instruction and therefore remain statically verifiable.

A module contains no execution-policy field. The embedding API or CLI selects interpreted, eager-JIT or lazy-JIT execution after loading; changing a path or filename cannot alter that selection.

## Execution and errors

The checked C engine uses no native recursion and has per-instance A/B/C and
control stacks. Limits count cells per stack, including return tokens on C. There is no
instruction/fuel budget and no budget error. Language aborts include the reason and
failing bytecode offset. Every call resets the operand/control stacks, including after
a previous error. Memory-profile
module images persist across calls, including writes before a failure. Modules
can be shared among separate VMs; a VM cannot execute concurrently with itself.
No process-global mutable runtime state is used.

This is a correctness baseline, not a sandbox or the high-performance tier.
The benchmark generators/JIT remain separately runnable in `vm/`. Native pointer
instructions are available only in the explicit memory profile and carry the
safety obligations documented there. Typed memory/callable/foreign profiles enable IEEE-754 binary64 operations, and version 4 enables explicitly bound host calls.

