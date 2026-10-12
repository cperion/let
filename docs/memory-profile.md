# Typed memory profile — revision 6, profile 2

Profile 2 adds typed memory/address/binary64 operations to the integer profile.
Profiles 3–4 include it. Format revision is **6**, independent of profile number;
old revision-2 files are not accepted. Interpreted, threaded and eager/lazy native
execution are bindings of the runtime, not separate prototype engines.

**Source design versus runtime:** [owners-references-ids.md](owners-references-ids.md)
adds a collector-free target with counted roots, stores/ids, COW value buffers and
immutable sharing. It replaces the proposed GC memory model, not these implemented
raw memory instructions. Safe source storage needs producer proofs and lowering;
profile 2 does not itself enforce reference ownership or make unsafe pointers safe.

```sh
build/abc asm examples/memory.abcasm -o build/memory.abc
build/abc check build/memory.abc
build/abc run build/memory.abc   # 99 1 72
```

## Instruction contracts

X is the selected operand stack; Y is the opposite stack. C0 is the top C cell.
Exact encodings belong to [symmetric-isa.md](symmetric-isa.md).

- `CALLOC n16` reserves `ceil(n/8)` zero-initialized C cells for a byte block.
  `CFREE n16` releases exactly the top live block with its original requested
  byte count. Zero counts are no-ops. Continuations consume capacity too.
- `FLD8/16/32/32S/64.X d16`, `FST8/16/32/64.X d16`, and `FADDR.X d16`
  address backward from C's **end byte pointer**, not its last cell's start.
  An access must fit inside one live block's requested bytes, not padding,
  scalar bindings or the protected continuation/caller frame. For a 16-byte
  top block, offsets 16 and 8 identify its first and second u64 cells.
- C cell operations cannot reinterpret, split or pop byte blocks. Scalar cells
  above a block shift its frame offsets. RET.X/TCALL.X may release a whole frame
  including blocks when their frame count matches the verified layout.
- `GLD8/16/32/32S/64.X off32` loads onto X; `GST8/16/32/64.X off32`
  consumes X0. Direct loads access the image; stores access only its writable
  prefix. `GADDR.X off32` produces an interior image address. Encoded image
  accesses are checked even in unreachable instructions.
- `LD8/16/32/32S/64.X off16` replaces address X0 with its loaded value.
  `ST8/16/32/64.X off16` consumes **address X0 and value Y0**.
- `LDX8/16/32/32S/64.X` consumes base X0 and index Y0, leaving the loaded
  value on X; the scale is the load width. `IDX.X k16` consumes index Y0 and
  replaces address X0 with `X0 + Y0*k`, using raw modular address bits.
- `MEMCPY.X n32` consumes destination X0 and source Y0. Overlap is safe;
  zero-byte copies do not dereference either pointer. Its semantic contract is
  not the host C `memcpy` restriction on overlap.
- Accesses support unaligned little-endian widths. `32S` sign-extends; other
  narrow loads zero-extend. Stores truncate low bits. Full-width stores accept
  integer/address/float bits; narrow stores require integers.

## Kinds, signatures and verification

Scalar kinds are integer, address and binary64. Frame blocks are opaque byte
regions, not scalar cells. Integer arithmetic/checks reject addresses and floats;
pointer operations require addresses; float operations require floats. Integer
EQ/NE and BEQ/BNE permit address identity when both operands are addresses.
Float equality uses FEQ/FBEQ with IEEE-754 NaN behavior.

Joins agree on both operand stacks and the scalar/block C layout, including
requested block sizes. Call/tail/return counts and kinds must match signatures.
The verifier interns persistent stack states and limits complexity to 1,048,576
nodes. This implementation limit is not an extra language stack rule.

Loads default to integer kind. `.loadkind addr` or `.loadkind float` before a
64-bit load supplies a producer assertion about the stored bits, not pointer
validation or a dynamic tag. `.loadkind int` is also valid; invalid annotations,
duplicates and non-instruction offsets reject.

## Format and assembly

The revision-6/profile-2 module has sections 1–6: typed functions, code, exports,
writable bytes, rodata and load-kind annotations. See
[module-format.md](module-format.md) for exact records and limits; it is the
single serialization reference.

```text
.profile memory
; Typed signatures (i=integer, a=address, f=binary64; -=zero cells):
; .function pair 1 0 a - 16
; .function greet 0 2 - ai
```

`.data HEX`, `.rodata HEX` and `.datazero n` construct initial image bytes.
The runtime concatenates writable bytes then rodata, regardless of directive
order. A nonzero hidden-result size requires argument zero to be an address; that
argument is included in the count. The caller supplies adequate live storage.
There is no automatic serialization of native addresses or aggregate staging
snapshots. Omitted kind strings default to integer cells.

## Embedding, persistence and safety

Each VM/module pair owns a separate initialized image. Use `abc_vm_load` before
native execution; interpreted calls may initialize their image on first use.
Images retain their module and survive subsequent calls, resource failures and
language aborts. Writes are not transactional; operand/control stacks reset
between calls and result outputs remain untouched on failure. Separate VM
instances never share mutable images.

`abc_module_export_signature` copies the cell kinds/counts and hidden-result size
into caller-owned storage. Host arguments/results are raw uint64_t cells. Address
bits are not handles: frame addresses must not outlive their frame/block, image
addresses remain valid only while the owning VM image lives, and native buffers
must remain live and large enough for all accesses.

**This is not a sandbox.** Pointer loads/stores, indexing and copies do not check
native bounds, ownership or lifetime. Direct GST enforces the writable prefix;
unchecked pointer stores are not stopped by hardware image protection. Invalid
pointer bytecode can corrupt or crash the host. Bounds/null/tag checks required by
a source language must be emitted explicitly.

The current typed `.slet` path uses supported frame/borrowed storage. Counted
source owners, growable value containers and unified Let lowering are not
implemented by profile 2 or the current runtime. Tracing GC is no longer the target. See
[slet-subset.md](slet-subset.md) for source limitations.

Active general, continuation, API, capture and frontend suites cover selected
forms, overlapping/partial writes, escaped caller-frame accesses while live,
persistence, return sources and stack limits. Full validation passes; exact
counts/evidence are in `REFACTOR.md`, not the removed historical `tests/` suite.
