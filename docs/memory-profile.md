# Milestone 2: memory (checked runtime)

The public C runtime implements all 54 integer/address memory instructions
from `spec.md`. The optimized engines in `research/vm-prototypes/` are separate; their
integer-only opcode buffers are not serialized public modules. The production Let/SLet
frontend lowers local records, arrays, sums, references, slices and strings through
checked frame or managed storage. Module storage, raw-pointer source forms and complete
deep ownership/provenance analysis remain frontend work. See
[callable-profile.md](callable-profile.md).

```sh
make test
build/abc asm examples/memory.abcasm -o build/memory.abc
build/abc check build/memory.abc
build/abc run build/memory.abc          # 99 1 72
build/abc dis build/memory.abc
```

## Instruction contracts

- `CALLOC n16` reserves `ceil(n/8)` C cells for a byte block; `CFREE n16`
  releases exactly the top live block, with the original requested byte count.
  Zero counts are no-ops. The generated VM semantics zero allocated bytes.
  Allocation is charged against the C stack limit; return tokens count too.
- `FLD8/16/32/32S/64.X d16`, `FST8/16/32/64.X d16`, and `FADDR.X d16`
  address backward from C's **end byte pointer**, not from the last cell's start.
  Accesses must lie wholly within one live block's requested bytes, not its
  padding, scalar bindings, return address or caller frame. For a 16-byte block
  with no cells above it, offsets 16 and 8 identify its first and second u64.
- C cell operations cannot reinterpret, split or pop byte blocks. Scalar cells
  above blocks shift frame offsets normally. `RET`/`TCALL` may release a complete
  frame including blocks when its encoded cell count matches the verifier.
- `GLD8/16/32/32S/64 off32` reads the full image; `GST8/16/32/64 off32` writes
  only its writable prefix; `GADDR.X off32` returns an interior image address.
  Every encoded image access is checked, including unreachable instructions.
- `LD8/16/32/32S/64.X off16` replaces an address on X with its loaded value.
  `ST8/16/32/64 off16` consumes the address on A and value on B.
- `LDX8/16/32/32S/64` consumes base A and index B and leaves the value on A,
  using the load width as its scale. `IDX k16` consumes index B and changes
  address A by `index*k`; address arithmetic uses raw modular 64-bit bits.
- `MEMCPY n32` consumes destination A and source B. The reference engine uses
  `memmove`, so overlapping copies are safe; zero-byte copies do not dereference.
- Loads/stores handle unaligned addresses and exact little-endian widths.
  `32S` sign-extends; other narrow loads zero-extend; stores truncate low bits.
  Full 64-bit stores can carry integer or address bits; narrow stores need integers.

## Kinds and verifier

A/B and scalar C cells have explicit `integer`, `address`, or `float` kinds. Memory blocks are opaque byte regions, not scalar cells. Arithmetic and integer checks reject addresses and floats; pointer instructions require addresses; float instructions require floats. Integer `EQ`/`NE` and `BEQ`/`BNE` support address identity only when both operands are addresses. Float equality uses `FEQ`/`FBEQ`, preserving IEEE-754 NaN behavior. Calls, tail calls and returns must match the function table's kinds and counts. All joins must agree on A/B kinds and the complete scalar/block C layout, including requested block sizes.
Canonical persistent stacks make join comparison constant-time. The verifier
limits interned states to 1,048,576 nodes and rejects excessive complexity.

Memory loads default to integer kind. `.loadkind addr` before a 64-bit memory load declares that the field contains address bits; `.loadkind float` declares IEEE-754 binary64 bits; `.loadkind int` is also valid.
These are type assertions by the producer, not pointer validation or dynamic tags.
Annotations on other instructions, duplicates or non-instruction offsets reject.


## Experimental version-2 encoding

The 16-byte header is `ABC2`, u16 version **2**, u8 pointer size **8**, u8 profile
**2**, u32 section count **6**, u32 reserved **0**. Section framing, 16 MiB file
limit and export encoding are unchanged from [version 1](module-format.md).
Exactly one of each tag is required, in arbitrary order, including empty images:

1. **Functions:** u32 count, then variable records: four u32 fields (entry,
   argument count, result count, hidden aggregate-result bytes), followed by
   one u8 kind per argument and then per result (`0=integer`, `1=address`, `2=float`).
   Counts remain 0–255. Entries strictly increase; the first is zero.
2. **Code:** public integer, float, branch, call, and memory-profile opcodes.
   Original integer opcode values are unchanged; internal quickened values remain
   forbidden. `tools/gen_opcodes.lua` extends seed metadata for the public runtime
   without changing optimized-engine generation. `abc opcodes` exposes metadata.
3. **Exports:** unchanged u32 count and function-index/name records.
4. **Writable data:** raw initial snapshot bytes, including zero-filled space.
5. **Rodata:** raw bytes appended immediately after writable data.
6. **Load kinds:** u32 count; each record is u32 code offset and u8 kind.

A nonzero hidden-result byte count requires argument zero to be an address; it
is the conventional caller-owned aggregate destination. The producer/caller must
supply enough valid storage. It is part of the argument count, not a scalar return.
No native addresses are serialized automatically; image addresses are materialized
at execution time and may be stored into the private writable image.

Assembly begins with `.profile memory`, before functions. `.data HEX` and
.rodata HEX` append hexadecimal byte pairs; `.datazero n` appends writable zeros.
Image offsets are byte offsets into data followed by rodata, regardless of directive
order. Extended function syntax is:

```text
.function pair 1 0 a - 16       ; address argument, no scalar results, 16 hidden bytes
.function greet 0 2 - ai        ; no arguments, address + integer results
.function example 2 1 ia i      ; integer/address arguments, integer result
```

Kind strings contain one `i`/`a`/`f` per cell; `-` denotes zero cells. Omitting kind strings defaults every cell to integer.


## Embedding, persistence and safety

Each VM lazily creates a **private snapshot per module** on its first valid call.
Snapshots survive subsequent calls, stack/resource errors and language aborts. Image writes
are not transactional; result publication still is. Separate modules within a VM
have separate images; separate VMs never share image mutations. Images retain the
immutable module metadata until VM destruction, preventing dangling image keys.
Only operand/control stacks reset between calls. There is no global mutable state.

`abc_module_export_signature` copies counts, integer/address/float kinds and hidden result size into caller-owned `abc_signature`; version-1 kinds are all integers.
result size into caller-owned `abc_signature`; version-1 kinds are all integers.
The embedding API passes raw uint64_t cells. Address arguments are native pointer
bits, not handles; address results are valid only for their actual backing storage's
lifetime. Image addresses stay stable until that VM is freed; frame addresses must
not escape their live block/frame. Callers must keep native buffers live and large
enough for every access. The profile requires a 64-bit little-endian host.

**This is not a sandbox.** LD/ST, indexed access, IDX and MEMCPY deliberately do
not check pointer bounds, ownership or lifetime. Bytecode can corrupt or crash the
host through invalid addresses, including producer-declared address loads. Rodata
is enforced for direct GST accesses and is read-only by producer/native-caller
contract; the private snapshot is not hardware write-protected against unchecked
pointer stores. Never execute untrusted pointer bytecode. Compiler-generated view
bounds/tag/null guards will use branches and `ABORT`; there is no implicit runtime
object model, GC, string representation or array descriptor.

`tests/memory_api.c` checks snapshot isolation, persistence, module retention,
native unaligned access, failure recovery and 1,000 loader mutations. Mutated memory
modules are **loaded, not executed**, because pointer operations are unchecked.
`tests/test_memory.lua` covers every new opcode and 100 random bounded programs.

