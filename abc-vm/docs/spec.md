# ABC VM 2.0 — specification for a real language

Oct 3, 2026 · @Cedric PERION

## Overview

ABC VM 2.0 keeps the three-stack, single-byte core of the benchmark VM and adds typed arithmetic, memory, calls and foreign calls. Its dynamic-value profile adds one-cell tagged values, generic operations, collected open-word maps with non-owning layout tokens, collected objects and traced managed addresses. The VM remains low-level: verified bytecode selects capabilities, while source-language filenames and syntax are never VM inputs.

What stays the same:

- **True-top consumption on A and B.** Binary operations consume `A0` and `B0`; one opcode bit picks the stack that receives the result. Nothing reaches below a top of A or B.
- **C holds structured state.** Reads are addressed (`CGET n`), writes are explicit (`CSET n`, `CPUSH`), and arithmetic never writes C.
- **Single-byte opcodes**, with immediates where an instruction needs them.
- **Variable-depth register caching with no refill on pop**, with A and B sharing one four-register operand bank and C keeping its own.
- **First-class compare-and-branch.**

What changes:

| Area | Benchmark VM | ABC VM 2.0 |
| --- | --- | --- |
| Values | `int64` only | typed 64-bit cells plus the dynamic profile's one-cell `any` values |
| Memory | none | frame blocks on C, module storage, read-only data, loads and stores |
| Calls | `CALL`/`RET` with one value | multiple arguments and results, hidden result address, indirect, tail and foreign calls |
| Checks | none | division, index, range and conversion checks that abort |
| Loops | `FORPREP`/`FORLOOP` | removed: tail self-calls lower to `JMP`, and the JIT warms any loop header |

The guiding rule: **the VM knows cells, memory, calls and the dynamic operations explicitly present in bytecode; the compiler knows source-language constructs.** Typed records, sums and arrays remain layouts over memory. The dynamic profile adds only the runtime object model that cannot be erased before execution: tagged values, open words, generic calls and collected storage.

## Machine state and values

The machine state is an instruction pointer, three stacks of 64-bit cells and the module image. Every stack value is exactly one cell; aggregates live in memory and are reached by address.

| Part | Holds |
| --- | --- |
| `ip` | address of the next instruction |
| A, B | operand stacks: expression values, arguments, results |
| C | structured state: return addresses, immutable bindings, frame blocks (section on memory) |
| module image | writable module storage, followed by read-only data such as string literals; initialized once before the first call |

Cell contents by Let type:

| Type | Cells | Contents |
| --- | --- | --- |
| `u8`, `u16`, `u32` | 1 | value zero-extended to 64 bits |
| `i32` | 1 | value sign-extended to 64 bits |
| `u64`, `i64` | 1 | all 64 bits |
| `f64` | 1 | IEEE-754 bit pattern |
| `bool` | 1 | 0 or 1 |
| `unit` | 0 | erased |
| `ref(T)`, `ptr(T)` | 1 | native address; a null `ptr` is 0 |
| `slice(T)`, `string` | 2 | address, then length (the length is the upper cell) |
| callable view | 2 | code address, then environment address |
| records, arrays, sums | 0 | live in memory; the stack holds their address when needed |
| dynamic `any` | 1 | private tagged immediate or collected-object reference; see `dynamic-profile.md` |

**Normalization invariant.** Between instructions, every integer cell is normalized for its type: narrow unsigned values are zero-extended and `i32` is sign-extended. This is what lets one 64-bit ALU serve every width. The compiler restores the invariant after any operation that can leave garbage in the upper bits, as the next section describes.

## The operand bank

A and B do not have separate caches. They share one bank of four registers, `h0` to `h3`, and C keeps a bank of its own. Most stack operations change which stack owns a register rather than where a value lives, and the compiler's choice of stacks decides how the bank is split.

**The anchored layout.** A's cached cells fill the bank from `h0` upward and B's from `h3` downward, so the free registers always form one gap between the two tops. With a cells of A and b cells of B in registers (a + b ≤ 4), `A0` is `h[a−1]` and `B0` is `h[4−b]`. The state is just the pair (a, b): 15 states, against 9 for fixed caches of 2 and 2. C uses the same rule on its own bank, with `C0` in `c[k−1]`.

**It is a ring.** Close the four registers into a circle and the layout is two stacks sharing one ring: the two bottoms, `h0` and `h3`, meet on one side, and the two tops face each other across the gap. Each top is an independent frontier. A push, pop or binary operation moves only the frontier it concerns, and `MOVE` hands a register from one frontier to the other. Keeping each stack's cells contiguous is what holds the state count at 15; letting cells scatter would remove a few register moves at the cost of 261 states.

| State | `h0` | `h1` | `h2` | `h3` |
| --- | --- | --- | --- | --- |
| a = 2, b = 2 | `A1` | `A0` | `B0` | `B1` |
| a = 3, b = 1 | `A2` | `A1` | `A0` | `B0` |
| a = 1, b = 2 | `A0` | free | `B0` | `B1` |
| a = 4, b = 0 | `A3` | `A2` | `A1` | `A0` |

**The laws.** The B forms mirror the A forms.

| Operation | Native work | New state |
| --- | --- | --- |
| push onto A, gap not empty | write `h[a]` | a + 1 |
| pop A | none | a − 1 |
| `OP.A` | `h[a−1] = h[a−1] op h[4−b]` | b − 1 |
| `OP.B` | `h[4−b] = h[a−1] op h[4−b]` | a − 1 |
| `MOVE.AB` | none when the bank is full, one register copy otherwise | a − 1, b + 1 |
| `COPY.AB` | one register copy | b + 1 |
| push onto a full bank | spill the pushing stack's deepest cached cell (the other stack's, if it has none) and shift that stack's cells one register toward its anchor | unchanged |
| use a value that is not cached | read it in place from memory; nothing is refilled | unchanged |

Three rules summarize it: **`MOVE` changes ownership, `COPY` creates liveness, and only a full bank touches memory.** `MOVE` is free on a full bank because the two tops are then adjacent: A's top register becomes B's new top without moving.

**Why anchored, not fully renamed.** A bank where any register may hold any logical cell would never move a value, but its state would be the whole mapping: 261 states for A and B alone, about 47,000 handlers before C multiplies them. The anchored layout keeps 15 states and moves values only on overflow and in some `MOVE`s. Those are register copies, which modern cores largely remove at rename, while every extra state costs code size and branch-predictor room.

**The compiler allocates the bank.** `compile(E, dst)` puts left operands on A and right operands on B, so the shape of the expression decides the split: a subtree that keeps three values on A while B holds one simply runs as `AAA|B`. There is no separate register allocator; scheduling values onto stacks is the allocation.

**`FOLD2` (extension, not adopted: decision 10).** In state (2, 2) the four registers form a two-level tree: `(A0 op1 B0) op2 (A1 op1 B1)`. A small family, `FOLD2.ADDADD` and `FOLD2.MULADD` on either stack (4 opcodes, not counted in the 181), computes it in one dispatch: two-lane sums and dot products. These are the only instructions that consume second cells; they count as consuming the top two cells of each stack. The interpreter saves two dispatches; the JIT gains little, because the CPU already runs the independent halves in parallel.

**Handler shape in C.** Every handler is zero to three real operations plus the dispatch; the stack topology lives in the state, which the generator tracks.

```c
/* state (2, 2): A0 = h1, A1 = h0, B0 = h2, B1 = h3 */
PN V add_a_2_2(ARGS) {
  h1 = h1 + h2;                                  /* A0 = A0 + B0 */
  ip += 1;
  [[clang::musttail]] return T_2_1[*ip](PASS);   /* B0 is now h3; h2 is free */
}

/* state (2, 2): the bank is full, so the tops are adjacent */
PN V move_ab_2_2(ARGS) {
  ip += 1;
  [[clang::musttail]] return T_1_3[*ip](PASS);   /* h1 now belongs to B */
}
```

In the JIT the dispatch disappears, so `ADD.A` in this state is a single `add` and `MOVE.AB` is no code at all.

## Arithmetic

All integer arithmetic is 64-bit. Width comes from normalization instructions the compiler places after operations that can overflow a narrow type, and signedness appears only where it changes the result. This keeps the opcode count low while matching Let wrapping rules exactly.

**When the compiler must normalize.** After `ADD`, `SUB`, `MUL`, `NEG`, `SHL`, `POW` and bitwise `NOT` on a narrow type, the compiler emits the matching normalization: `ZX8`, `ZX16`, `ZX32` for unsigned types, `SX32` for `i32`. 64-bit types wrap natively and need nothing. `AND`, `OR`, `XOR`, logical `SHR` on unsigned values and `SAR` on signed values keep normalized inputs normalized. `DIVS` on `i32` needs `SX32` afterwards, because `-2147483648 / -1` produces 2147483648 in 64 bits and Let wraps it back to itself.

**Where signedness matters:**

| Operation | Unsigned | Signed |
| --- | --- | --- |
| division | `DIVU` | `DIVS` |
| remainder | `REMU` | `REMS` (takes the dividend's sign) |
| right shift | `SHR` (logical) | `SAR` (arithmetic) |
| ordered compare | `LTU`, `LEU` | `LT`, `LE` |
| compare-and-branch | `BLTU`, `BLEU` | `BLT`, `BLE` |
| power | `POW` | `POWS` (aborts on a negative exponent) |

Equality (`EQ`, `NE`, `BEQ`, `BNE`) is shared. There are no greater-than forms: `a > b` is `b < a` with the operands routed to the other stacks, which the two-stack design gives for free.

**Defined edge cases.** Division or remainder by zero aborts. `i64` `MIN / -1` wraps to `MIN` instead of trapping. A shift amount of 64 or more yields 0, or the sign fill for `SAR`; narrow types then come out right after normalization, so a `u32` shifted left by 40 is 0 as Let requires. `POW` wraps and defines `0 ^ 0 = 1`.

**Conversions.** Widening needs no instruction, or one `ZX`/`SX`. Reinterpreting at one width (`u32` to `i32`) is a single `SX32` or `ZX32`. A run-time narrowing conversion uses a check: `CHKU8`, `CHKU16`, `CHKU32` and `CHKI32` abort when the value does not fit, and `CHKNN` covers both `i64` to `u64` and `u64` to `i64`, since either way the value fits exactly when its top bit is clear.

**Floats.** `FADD`, `FSUB`, `FMUL`, `FDIV`, `FNEG`, and `FLT`, `FLE`, `FEQ` follow IEEE-754: division by zero gives an infinity or NaN, and any ordered comparison with NaN is false. `FBLT`, `FBLE` and `FBEQ` are the float compare-and-branch forms; negated conditions swap the branch targets so NaN stays exact. `I2FS` and `I2FU` round to nearest, ties to even; `F2IS` and `F2IU` truncate and abort on NaN or an out-of-range value.

## Dynamic values and generic operations

The dynamic-value profile is specified in [`dynamic-profile.md`](dynamic-profile.md). An `any` is one cell carrying its exact run-time type. Generic instructions are public `EXT` operations with generated stack effects; every one has a correct unspecialized implementation and applies the same typed arithmetic, comparison, conversion and call rules as the core instructions. A VM-private code copy may quicken a measured monomorphic checked-specific site to a same-length one-byte internal opcode; unquickened and polymorphic generic sites continue through `EXT`. Dynamic binary arithmetic and comparisons consume A0/B0 and select a result stack like typed operations; only dynamic calls gather multiple cells on A.

Dynamic values introduce collected objects for open words, captured closures, built strings, boxed wide integers/raw pointers, records or arrays copied into `any`, and boxes for managed references/views. `f64` uses offset encoding plus canonical NaN and never allocates. Managed strings retain their owner when boxed; only unowned SLet/foreign views copy. Residualized code keeps a proven wide integer unboxed across compatible compiled edges and materializes its canonical box only at a dynamic escape. Profile-5 metadata also marks typed managed address cells that keep Let backing storage alive. Raw pointers and unmanaged SLet borrows are not roots. The private representation is not a module or C ABI.

Every open word owns one collected ordered hash map containing its keys, values, index and insertion order. A nonzero process-local 64-bit layout token changes on structural mutation but owns no metadata and is never reused or serialized. Replacing a value keeps the token. Constant-key inline caches and capped lazy versions may guard on the token and use a cached slot; computed keys take generic hash lookup. There is no transition-shape tree, permanent key interning or dictionary-mode switch, so storage remains O(live fields) and dies with the word.

Dynamic calls discard surplus requested results but abort with `dynamic-signature` when results are missing; they never synthesize dynamic `unit`. Generic sites quicken monotonically, and tag or layout-token checks that dominate later operations may enter a lazy block context. The verifier computes a transitive `allocation-free` fact from each function and its callees. A host collection request can remain pending in an allocation-free loop and is honored at the next generic or allocating boundary.

Interpreter, eager-JIT and lazy-JIT policies execute the same dynamic bytecode. Eager mode compiles generic checked paths for facts unavailable at load. Lazy mode may compile a capped version from the tags and checked layout tokens present on first arrival. Allocation, collection and safepoints follow executed operations and do not select the JIT policy.

## Memory model

Memory is reached through four bases, and only one of them needs an address on a stack. Frame blocks on C and the module image have addresses the compiler knows, so an access is one instruction with an offset; pointer addresses are cells that stay in cache registers. The result: a field or element access is one dispatch, and one machine instruction in the JIT.

| Base | Address | Loads | Stores | Address form |
| --- | --- | --- | --- | --- |
| frame | C's top minus a static offset | `FLD.X` | `FST.X`, value from that stack | `FADDR.X` |
| image | image start plus a static offset | `GLD` | `GST`, value from A | `GADDR.X` |
| pointer | address on A or B plus a static offset | `LD.X`, which consumes the address | `ST`: address `A0`, value `B0` | the address itself |
| indexed | `A0 + B0 × width` | `LDX` | `IDX k`, then `ST` | `IDX k` |

Loads come in widths 8, 16, 32, 32 sign-extended (for `i32`) and 64 (also `f64`); stores in 8, 16, 32 and 64.

**Frame blocks.** `CALLOC n` flushes C's cache (state K0) and reserves n bytes, rounded up to 8, in C's memory; `CFREE n` releases them. A block has no address entry: the verifier knows where every block sits, so an access names a *frame offset*, the distance in bytes from C's logical top down to the byte. Blocks are released in reverse order, which implements SLet lexical lifetime, so a strict `ref` to an enclosing owner is the `FADDR` of an enclosing block. Let storage whose managed reference/view escapes instead uses an explicit profile-5 allocation/promotion path and trace metadata; it is not left in a released frame block.

**Why frame access costs nothing extra.** The physical address is `csp + 8k − offset`, where k is the number of C cells currently in registers. Both k and the offset are static in every specialized handler and stencil, so the JIT emits one `mov` relative to `csp`, and the interpreter one add. No frame pointer is needed, which matters because every argument register is already spoken for.

`FADDR` materializes a frame address only when one must exist as a value: a `ref`, a method receiver, `ptr(place)`, a hidden result block, or an aggregate argument.

C at a typical point inside a call, top first:

| C contents | Written by |
| --- | --- |
| immutable bindings of the current scope | `CPUSH`, `CPUSHN` |
| frame block bytes: records, arrays, hidden results | `CALLOC`, then `FST` |
| return address | `CALL` |
| the caller's contents | the caller |

**The module image.** Module storage and read-only data form one address range: the writable data segment, followed by rodata. `GLD` and `GST` take a 32-bit offset, and `GADDR` materializes an address, such as the start of a string literal or a `ref` to module storage. The verifier rejects any `GST` whose offset lands in the read-only part. The image starts from a snapshot produced by static execution, with equal string literals sharing one address. In the JIT the image sits in the low 2 GB, so its addresses are 32-bit immediates.

**Pointers.** A `ref`, `ptr` or slice address is a cell, usually in A's or B's registers. `LD` and `ST` add a static field offset; `LDX` loads element `B0` of the array at `A0`, scaled by the load width. `IDX k` covers elements whose size is not a load width, such as arrays of records, and an indexed store is `IDX` followed by `ST`.

What a field or element access costs:

| Access | Instructions | JIT machine code |
| --- | --- | --- |
| field of a local record | `FLD` | `mov off(%csp), reg` |
| module storage | `GLD` | `mov addr32, reg` |
| through a `ref` or `ptr` | `LD` | `mov off(%reg), reg` |
| array element | `LDX` | `mov (%base,%idx,8), reg` |

**What stays out of the VM.** Alias analysis belongs to the compiler: stencils never keep a memory value in a register across instructions, so every store is correct with no checks, and the partial evaluator keeps fields in cells when Let rules show nothing can alias them. Addresses are not checked at run time; bounds checks are explicit compare-and-branches to `ABORT 2`, which the compiler drops for known indexes or hoists out of loops.

**Copies.** `MEMCPY n` copies n bytes from `B0` to `A0`. In the JIT, a copy of up to 32 bytes is a few inline moves; only larger copies call `memcpy`.

**Layout and slices.** Record, array and sum layouts follow the target C ABI rules, so the VM, residual C emitter and foreign code agree on every offset; a sum is its tag at offset 0, then the largest payload. A slice is two cells, address and length, and a string literal is `GADDR` plus a pushed length.

## Instruction set

The public ISA has 223 opcodes in one byte, including `EXT`, leaving 33 encodings for internal quickening and later additions. The current prototype spends 30 on call quickening. Before profile 5 adds one-dispatch monomorphic dynamic forms, that allocation must be consolidated or rarely used public forms moved behind `EXT`; the design must not pretend the remaining three values suffice. Generic and polymorphic dynamic sites stay behind `EXT`. An instruction is its opcode byte followed by little-endian immediates; branch offsets count from its end. `.X` marks A/B opcode pairs.

| Group | Instructions | Immediate | Opcodes |
| --- | --- | --- | --- |
| Constants | `PUSH8.X`, `PUSH32.X`, `PUSH64.X` | i8, i32, i64 | 6 |
| Stack | `DUP.X`, `DROP.X`, `COPY.AB`, `COPY.BA`, `MOVE.AB`, `MOVE.BA` | none | 8 |
| Context | `CPUSH.X`, `CPUSHN`, `CPOP`, `CGET0.X`, `CGET1.X`, `CGETN.X`, `CGETR.X`, `CSET0.X`, `CSETN.X`, `CALLOC`, `CFREE` | `CPUSHN`: u8 count; `CGETN`/`CSETN`: u8 depth; `CGETR`: u8 depth, u8 count; `CALLOC`/`CFREE`: u16 bytes | 18 |
| Integer | `ADD`, `SUB`, `MUL`, `DIVU`, `DIVS`, `REMU`, `REMS`, `AND`, `OR`, `XOR`, `SHL`, `SHR`, `SAR`, each `.X` | none | 26 |
| Compare | `EQ`, `NE`, `LT`, `LE`, `LTU`, `LEU`, each `.X`, result 0 or 1 | none | 12 |
| Unary | `NEG.X`, `NOT.X` (bitwise), `LNOT.X` (bool) | none | 6 |
| Width and checks | `ZX32.X`, `SX32.X`, `ZX8`, `ZX16`, `POW`, `POWS`, `CHKU8`, `CHKU16`, `CHKU32`, `CHKI32`, `CHKNN` | none | 13 |
| Float | `FADD.X`, `FSUB.X`, `FMUL.X`, `FDIV.X`, `FLT.X`, `FLE.X`, `FEQ.X`, `FNEG`, `I2FS`, `I2FU`, `F2IS`, `F2IU` | none | 19 |
| Frame memory | `FLD8.X`, `FLD16.X`, `FLD32.X`, `FLD32S.X`, `FLD64.X`, `FST8.X`, `FST16.X`, `FST32.X`, `FST64.X`, `FADDR.X` | u16 frame offset | 20 |
| Image memory | `GLD8`, `GLD16`, `GLD32`, `GLD32S`, `GLD64`, `GST8`, `GST16`, `GST32`, `GST64`, `GADDR.X` | u32 image offset | 11 |
| Pointer memory | `LD8.X`, `LD16.X`, `LD32.X`, `LD32S.X`, `LD64.X`, `ST8`, `ST16`, `ST32`, `ST64`, `LDX8`, `LDX16`, `LDX32`, `LDX32S`, `LDX64`, `IDX`, `MEMCPY` | loads and stores: u16 offset; `IDX`: u16 size; `MEMCPY`: u32 bytes | 21 |
| Branches | `JMP`, `JMP32`, `JZ.X`, `JNZ.X`, `BEQ`, `BNE`, `BLT`, `BLE`, `BLTU`, `BLEU`, `FBLT`, `FBLE`, `FBEQ`, `SWITCH` | i16 offset (`JMP32`: i32); `SWITCH`: u16 count, then i32 offsets | 16 |
| Operand forms | `ADDI`, `SUBI`, `MULI`, `ANDI`, `ORI`, `XORI`, `SHLI`, `SHRI`, `SARI`, each `.X`; `ADDC`, `SUBC`, `MULC`, `XORC`, each `.X`; `BEQI`, `BNEI`, `BLTI`, `BLEI`, `BGTI`, `BGEI`, `BLTUI`, `BLEUI`, `BGTUI`, `BGEUI`, on A | `OPI`: i8; `OPC`: u8 depth; `BxxI`: i8, then i16 offset | 36 |
| Calls | `CALL.X`, `TCALL`, `CALLI.X`, `TCALLI`, `RET`, `FCALL`, `ABORT`, `HALT`, `EXT` | `CALL`: i32, u8 arguments; `TCALL`: i32, u8 frame cells, u8 arguments; `RET`: u8 frame cells, u8 results; `CALLI`/`TCALLI`: the same counts, then a u32 cache field written only by the VM; `FCALL`: u16 extern index; `ABORT`: u8 reason; `EXT`: u8 extended opcode, then that instruction's immediates | 11 |
| Dynamic extension | boxing/casting/tests, generic operators and calls, open-word, string and allocation operations | selector-specific; generated metadata fixes length, kinds and stack effect | behind `EXT`, no additional core opcode |

Rules that hold across groups:

- **Binary operations** consume `A0` and `B0` and compute `A0 op B0`; the result goes to the stack named by `.X`. Compare-and-branch consumes both and jumps when `A0 op B0` holds.
- **`CGETN` and `CSETN` count cells**, including the bytes of frame blocks in 8-byte cells; the compiler knows every block's size, so depths stay static. `CSETN` consumes the top of its stack and writes it in place.
- **One-cell forms** (`CGET0`, `CGET1`, `CSET0`) exist because loops read the newest bindings constantly; they cost one byte instead of two.
- **`SWITCH`** consumes `A0` and jumps to entry `A0`, or past the table when `A0` is out of range: the dispatch of a sum match with many alternatives.
- **`MOVE` and `COPY`** are the only cross-stack transfers. `COPY` is DAG fan-out: one value live on both frontiers.

**Operand forms.** A binary operation's first operand is always a stack top. Its second operand comes from one of three sources: the other stack's top, which is consumed; a C cell, which is only read; or an immediate, which is encoded.

| Form | Effect |
| --- | --- |
| `OP.X` | r = `A0` op `B0`; A and B pop; r is pushed on X |
| `OPI.X k` | r = `X0` op k; X pops; r is pushed on X, so the result replaces `X0` in place |
| `OPC.X n` | r = `X0` op `C[n]`; X pops; r is pushed on X; C is unchanged |
| `BxxI.A k, label` | compare `A0` with k; A pops; jump if the relation holds |

The immediate is exactly `PUSH8`'s value, an i8 sign-extended to 64 bits, and the compiler uses it only when that equals the constant normalized to the expression's type. `C[n]` follows `CGETN`'s rules, including verification rule 6. Wrapping and normalization are unchanged: the operation computes in 64 bits, and `ZX32` or `SX32` follows when the type needs it. Branch immediates come in both directions because an immediate cannot be routed to the other stack; binary operations need no reversed forms, because a commutative operation swaps its operands and a constant first operand of a non-commutative one is rare.

Each form is defined by a short sequence of existing instructions, which it performs in one dispatch:

- `OPI.A k` is `PUSH8.B k`, `OP.A`; `OPC.A n` is `CGETN.B n`, `OP.A`.
- `OPI.B k` is `MOVE.BA`, `PUSH8.B k`, `OP.B`; `OPC.B n` is `MOVE.BA`, `CGETN.B n`, `OP.B`.
- `BEQI`, `BNEI`, `BLTI`, `BLEI`, `BLTUI`, `BLEUI` with k are `PUSH8.B k` followed by the matching two-stack branch.
- `BGTI.A k` is `MOVE.AB`, `PUSH8.A k`, `BLT`, that is k < x; `BGEI`, `BGTUI` and `BGEUI` follow the same pattern.

`compile(E, dst)` gains one case: when the second operand is a constant or a binding, compile the first operand to dst and emit `OPI.dst` or `OPC.dst`, with no use of the other stack. Such a node's Ershov number is its first operand's.

## Calls

Arguments and results travel on A, the return address lives on C, and B belongs to the caller. A Let result vector maps directly onto A: `return a / b, a % b` leaves two cells, the last result on top.

**The convention.**

1. The caller pushes the arguments onto A in source order, so the last argument is `A0`.
2. `CALL.X f, n` pushes a return address that also records X, moves the top n cells of A into the new frame (as n `CPUSH`es would, so the first argument ends as `C0`) and jumps. The frame is every C cell above the return address, as verification rule 6 already defines it.
3. The callee reads its parameters with `CGET`. There is no prologue.
4. `RET k, r` drops the frame's k cells, pops the return address and jumps. The callee always leaves its r result cells on A in result-vector order; when the return address records B, `RET` moves them to B and keeps their order. The verifier checks k against the C depth it already tracks and r against the function table.
5. After the call, A has lost the arguments, the results are on X with the last on top, and the other operand stack is exactly as the caller left it. Unit results occupy no cells.

**Aggregates.** A record, array or sum result is written into a block the caller reserves; its address is a hidden first argument. An aggregate argument is passed as the address of a copy, which keeps Let value semantics; the compiler may skip the copy when the callee provably only reads. A method receiver is passed as the address of the actual instance with no copy, because a method borrows its receiver.

**Tail calls.** `TCALL f, k, n` drops the current frame's k cells, moves n cells from A into the frame and jumps, keeping the same return address. Because it keeps the return address, it also keeps the stack that address records, so a tail call delivers its results wherever the original caller asked, with no extra rule. A tail self-call is the same instruction aimed at the word's own entry: one instruction rebinds every parameter, which is how recursion in Let turns into loops. A block with a `defer` keeps its tail call as a real call, as the language requires.

**One primitive.** `CALL`, `TCALL` and `RET` are a single frame operation, drop k frame cells and take n cells from A, followed by a jump, with or without a return address. The bit on `CALL` makes a call name its destination stack like every other instruction that produces a value. `RET` is the one instruction whose effect depends on a run-time value, the bit in the return address; in the interpreter that is one branch inside its handler, and from the caller's side the effect stays static: n cells leave A, r cells arrive on X.

**Indirect calls.** A callable view is two cells: code address and environment address. The caller pushes the environment as the hidden first argument (0 for a closure with no captures), pushes the arguments, puts the code address on B and executes `CALLI.X n`, which consumes it, moves the n argument cells, environment included, into the frame, and delivers the results on X. `TCALLI k, n` is the tail form. Both carry a 32-bit cache field, zero in the bytecode and written only by the VM: the first call records its target and the site rewrites itself into a direct call guarded by a comparison with that target; a failed comparison makes the site generic for good (decision 13). A tagged callable needs nothing new: the compiler tests the tag with `SWITCH` or `BEQ` and makes a direct `CALL` per arm.

**Foreign calls.** `FCALL k` calls entry k of the module's extern table, which records the C symbol and its signature. It consumes the arguments from A, calls through the host's C ABI, and pushes the result. Unlike `CALL`, it requires every register cache to be flushed first, because foreign code knows nothing of the banks. The loader binds each extern to a native function and a bridge for its signature shape; shapes are limited to six integer or pointer arguments and four `f64` arguments. Since k is a site constant, a site rewrites itself into the variant for its shape on first execution, so the call goes straight to the right bridge (decision 13). Compile-time VM execution leaves foreigns unbound and rejects `FCALL` with `foreign-effect`.

**Entry from the host.** An exported word is a VM entry point. The host pushes its arguments onto A through the embedding API, the VM runs until the matching `RET` empties C, and the host reads the results off A.

## Control flow, checks and aborts

Control flow is structured by the compiler and checked by the verifier: every jump target has one stack shape, and every check that fails ends the run with an abort reason. There are no exceptions and no unwinding.

**Branching.** `JZ` and `JNZ` test a bool on top of A or B; the compare-and-branch forms test `A0` against `B0`. `and` and `or` in Let short-circuit with these. An expression conditional leaves its result in the same cells on both arms, so the join point has one shape. A sum match loads the tag and dispatches with `SWITCH`, or with a `BEQ` chain for two or three alternatives.

**Join shapes.** At every jump target, the depths of A, B and C, and the layout of C's frame blocks, are the same along every incoming edge. The compiler guarantees it and the verifier checks it. The JIT may still arrive with different register-cache states; it inserts conform code on those edges, which is invisible to the semantics.

**What aborts.**

| Reason | Raised by |
| --- | --- |
| 1 division by zero | `DIVU`, `DIVS`, `REMU`, `REMS` with a zero divisor |
| 2 index out of range | compiler-emitted compare-and-branch to `ABORT 2` |
| 3 conversion out of range | `CHKU8` through `CHKNN`, `F2IS`, `F2IU` |
| 4 negative exponent | `POWS` |
| 5 unreachable | `ABORT 5`, placed by the compiler after paths it proved terminating |
| 6 to 13 | dynamic-profile type, field, key, terminal, mutation and call failures; exact assignments are in `dynamic-profile.md` |
| 14 to 255 | reserved for the host and later language features |

**Abort semantics.** An abort stops the VM immediately and reports the reason and the instruction address to the host. Deferred actions do not run and nothing unwinds, matching the Let rule that an abort ends the process without cleanup.

**Aborts during static execution.** When the static evaluator hits an abort, the program is rejected at compile time at the source position of the failing operation. This is how known Let zero-divisor and known-index rejections fall out of the same instructions that check at run time.

## Why Let fits a stack VM

The statically typed core and SLet restrictions are the rules a stack machine wants: bindings are immutable, SLet lifetimes nest, results are ordered vectors, and anything the machine cannot do cheaply is either settled at compile time or written out explicitly. Main-profile Let retains that core while making dynamic calls, layouts and managed ownership explicit in profile-5 operations and metadata.

| Let rule | What it gives the VM |
| --- | --- |
| bindings are never reassigned | no variable allocation: a binding is one `CPUSH` and any number of `CGET`s, with no store traffic and nothing to merge at joins |
| lexical lifetimes nest in SLet code | SLet frame and checked-borrow storage stays stack-disciplined; Let emits explicit managed allocation/promotion and tracing where values escape |
| an SLet `ref` names only an enclosing owner or module storage | SLet references need no run-time lifetime check; profile-5 managed references keep promoted Let storage alive through GC roots |
| result vectors instead of tuples, with fixed adjustment rules | multiple results are cells on A; adjustment is dropping or pushing cells |
| static partial supply and represented dynamic supply | static environments can remain fixed-size values; open words and collected captures use the dynamic object model |
| strict left-to-right evaluation | argument order is push order, so postfix code generation is correct by construction |
| recursion instead of loop syntax | the only loop is a backward `JMP`, which the JIT warms and aligns |
| explicit widths, no implicit conversions | every arithmetic instruction is chosen statically, and normalization is placed by type |
| known calls execute while compiling; unknown dynamic calls remain explicit | typed residue stays direct, while dynamic bytecode uses checked generic calls |

**Forth's best idea, made principled.** Forth lets a word run at compile time and lets a program extend its own compiler, but the line between compile time and run time is drawn by hand and nothing checks it. Let draws that line automatically: whatever is known runs while compiling, and only the residue is emitted. The VM then plays both of Forth's roles, the interpreter that executes at compile time and the target that runs the residue.

**Where Let pushes back.** Records and arrays have identity, so a write through one local is visible through its alias, and methods mutate their receivers. Those values live in rmemory, which is what the memory model and `MEMCPY` exist for. Erased callables and tagged callables need `CALLI` or tag dispatch. Scalarizing records that provably have no identity (open question 3) keeps as much as possible on the stacks.

The one language question this review raised is how `!=` treats NaN (open question 4).

## Mapping Let onto the VM

Every core Let construct lowers onto the typed instructions below. Constructs whose run-time type, open-word layout or allocation cannot be erased lower to the public extended operations in `dynamic-profile.md`. The VM sees only those typed or dynamic bytecode operations, never the source filename.

| Let | VM lowering |
| --- | --- |
| word, specialization | one function per residual specialization |
| immutable `let` | `CPUSH` at the binding, `CGET` at each use, `CPOP` at scope end |
| multiple results | several cells on A, last result on top |
| expression conditional | branches that leave the result in the same cells on both arms |
| local record or array | a `CALLOC` block, initialized with `FST` |
| field of a local record | `FLD` and `FST` with the field's frame offset |
| field through a `ref` or `ptr` | `LD` and `ST` with the field's offset |
| array element | `LDX`, or `IDX` and then `LD` or `ST` |
| record argument and result | `FADDR` of a copy; `FADDR` of the hidden result block |
| method call | receiver address (`FADDR`, `GADDR` or a `ref`) as first argument, no copy |
| small record with no identity | scalarized into cells by the compiler |
| sum construction and match | tag and payload stores; tag load, then `SWITCH` or `BEQ` |
| `ref(T)` | SLet: `FADDR` of an enclosing block or `GADDR` of module storage; Let escaping reference: address of profile-5 managed storage plus descriptor/root metadata |
| `ptr(T)`, `null` | address cell; 0 |
| `slice(T)`, `string` | address and length; a literal is `GADDR` and a pushed length |
| lambda with captures | environment block plus code address; direct `CALL` when the code is known, `CALLI` otherwise |
| tagged callable | tag test, then one direct `CALL` per arm |
| tail self-call | `JMP` to the entry after rebinding the parameters with `CSET` |
| other tail call | `TCALL` |
| `defer` | the compiler copies the action onto every exit path of its block |
| `extern let` | `FCALL` through the extern table |
| module storage, `let_init` | `GLD` and `GST` on the module image; descriptor-rooted module ranges are declared by the dynamic profile |
| `any`, open words, built strings | dynamic-profile `EXT` operations and one-cell dynamic values |
| known zero divisor or bad index | an abort during static execution, reported as a compile error |

**Worked example.** Section 13's `skip` becomes a loop, because its recursive call is a tail self-call. `s` and `n` arrive on A with `n` on top:

```
skip:                 ; A: n s
  CPUSH.A             ; C: n
  CPUSH.A             ; C: s n
loop:
  CGET1.A             ; A: n
  PUSH8.B 0
  BEQ done            ; n == 0
  CGET0.A             ; A: s
  CALL next32         ; A: next32(s)
  CGET1.A             ; A: n  next32(s)
  PUSH8.B 1
  SUB.A               ; A: n - 1  next32(s)
  ZX32.A              ; u32 wrap
  CSET1.A             ; n = n - 1
  CSET0.A             ; s = next32(s)
  JMP loop
done:
  CGET0.A             ; A: s
  CPOP
  CPOP
  RET
```

Both new arguments are computed before either binding is overwritten, as the left-to-right evaluation order of Let requires. In the JIT, the loop header is warmed and aligned. If the compiler inlines the small `next32`, `s` and `n` stay in C's cache registers for the whole loop; with a real `CALL`, today's convention flushes them once per iteration.

## Implementation

One generator builds both execution engines from the same instruction semantics, and the register caching from the benchmark VM carries over unchanged. New instructions are new semantic functions in the generator; the interpreter handlers, JIT stencils, dead-write elimination and cache transitions follow automatically.

&#91;embedded content: Let compilation pipeline · two backends, one VM\]

The partial evaluator lowers known subprograms to verified ABC bytecode and executes them in a compile-time VM. The compiler, acting as the host, independently selects interpreted, eager-JIT or lazy-JIT policy for those staging modules: the interpreter is the low-startup baseline, while either JIT can accelerate larger or repeatedly executed static work. Residual code goes either to C for release builds or to VM bytecode for development runs. The execution policy later used for a residual module is a separate host choice. The VM receives modules, not source filenames, and never uses `.slet` or `.let` to choose a tier.

**Register budget on x86-64.** `preserve_none` gives 12 argument registers. The interpreter spends `ip`, three stack pointers and the four-register operand bank and three C cells, which is 11, leaving one register for the indirect dispatch jump. The JIT has no `ip` and jumps directly, so it keeps four C cells. ARM64, with 24 argument registers, can afford much deeper caches.

**Size.** 220 opcodes across 60 interpreter cache states make about 13,200 handlers; the JIT's 75 states make about 17,700 stencils. That is in the range already built and measured, which compiled in about 30 seconds.

**Slow paths.** Aborts and foreign calls leave the hot path. An abort calls a cold, never-returning C function. `FCALL` runs in the flushed cache state, like `CALL`, and calls its signature bridge as an ordinary C function.

**Addresses in stencils.** The JIT maps code and the module image in the low 2 GB, so `GLD`, `GST` and `GADDR` patch into 32-bit relocations like every other hole, and frame offsets become displacements from `csp`. The interpreter reads the image base from its VM context instead.

**Static execution.** The partial evaluator compiles fully known subprograms to verified bytecode and runs them in a compile-time `abc_vm`. Interpreted, eager-JIT and lazy-JIT staging must produce identical values, diagnostics and residual output; selecting among them changes compile time only. `FCALL` is disabled there and language aborts become compile errors. There is no instruction, fuel, specialization-count or logical-allocation budget: static execution runs until it returns, aborts, exhausts an actual machine resource, or the build is interrupted externally. A long-running evaluation reports its active binding and current source position; interrupting it reports the static-execution word stack with source positions. A refused speculative fold uses a disposable VM/image or checkpoint so its writes cannot leak; accepted module initialization keeps its image for the residual snapshot. VM-local addresses are copied or re-encoded and never serialized directly. The staging policy is independent of the policy selected later for the residual module.

**Testing.** The generated instruction-semantics table is the sole executable definition used to build interpreter handlers, JIT stencils and residual C operations. A test-only instruction model may check individual opcodes, but it is not a Let source evaluator and is not shipped as an execution path. Known-source execution is compared across all compile-time VM policies, and each must produce byte-identical residual modules. Residual modules then agree across interpreted, eager-JIT, lazy-JIT and residual-C execution.

## Versioning by site rewriting

Everything that specializes in this machine is a **version**: code for a **site** (an instruction, or the entry of a block) specialized to what is known when execution reaches it. What is known has two parts, and they behave differently.

- **The arrival context** is what the path brings: the cache state in the interpreter, the register map and known constants in compiled code, and, for a dynamic language, known type tags. It differs between paths and between executions, so a site has several versions at once, one per context, selected on arrival.
- **The site's knowledge** is what the site itself knows: its immediates, and values it has observed. It only grows, so it replaces the site's versions over time, monotonically.

The interpreter's dispatch lookup, `T_state[*ip]`, shows both axes: the table is selected by the arrival context, and the byte holds the site's knowledge.

**Rules.**

1. **Every site has a generic version that accepts any context and needs no knowledge.** It is always correct, so correctness never depends on specializing.
2. **Versions for different arrival contexts coexist.** The interpreter creates cache-state handlers ahead of time. In eager JIT mode, the loader creates every block version reachable from the contexts available at load and uses generic checked code where facts are not yet known. In lazy JIT mode, a block version is created when its context first reaches the block. Both use a small cap; at the cap, an edge conforms to an existing compatible version, ultimately the generic one.
3. **A site's knowledge replaces its versions, and only its own, monotonically:** generic, then specific, then, if a check fails, a final generic version. Knowledge therefore changes a site at most twice, which rules out thrashing by construction.
4. **Knowledge from an immediate needs no check;** knowledge from an observed value is checked, and a failed check moves the site to its final generic version.
5. **Replacing a version never changes meaning or layout.** In the interpreter only the opcode byte changes, so lengths, operands and branch offsets stay valid; in compiled code only patch sites change.
6. **A site that must remember an observed value has a field for it,** zero in the bytecode and written only by the VM.
7. **Internal opcodes never appear in verified bytecode.** The loader rejects them and copies a module's code before running it, so replacements touch only that copy.
8. **Nothing counts executions.** Eager versions are created at load; lazy versions are created on first arrival; site knowledge is applied at first execution. The host selects eager or lazy policy explicitly, never through a hotness threshold or source-file property.
9. **A version must earn its place.** An interpreter variant costs 60 handlers and one internal opcode (69 remain in the current build), so it must remove a loop or a dispatch; compiled block versions are capped per block.

| Mechanism | Axis | Created or replaced |
| --- | --- | --- |
| Interpreter handlers | context: the cache state | ahead of time, one per state |
| Compiled block versions | context: the register map, known constants, and any proven run-time type tags or layout tokens | eager mode at load; lazy mode on first arrival of a context; both up to the cap |
| Quickening: `CALL n`, `TCALL k, n`, `RET k, r` | knowledge: immediates | at first execution in the interpreter, at load in compiled code; no check |
| `FCALL` signature shape | knowledge: the extern entry the site names | likewise; no check |
| `EXT` sub-opcode | knowledge: an immediate | likewise; no check |
| Inline cache: `CALLI`, `TCALLI` | knowledge: the observed target | at first execution, in either tier; checked, with a final generic call if the check fails |

**The configured JIT policies differ only in when block versions are created.** The interpreter has one handler per cache state. Eager mode creates all versions reachable from load-time contexts and emits generic checked operations for unavailable facts. Lazy mode creates a version when a context first reaches a block, so observed tags and checked layout tokens can enter its key immediately. In either mode, a compiled block applies immediate knowledge directly, while knowledge from an observed value begins with a check. The bytecode and semantics are identical under both policies.

**The boundary.** Two questions decide which axis a piece of information belongs to: where it comes from, and who benefits from it.

|  | Site knowledge | Arrival context |
| --- | --- | --- |
| Source | the site itself: its immediates, or a value it just observed | the path: what earlier instructions established |
| Who benefits | only the site; nothing downstream learns from it | later instructions too: each version's output is the next block's context |
| Multiplicity | one current version, replaced at most twice | several versions at once, one per context, up to the cap |
| Choosing a case | commits to one case, with a check and a generic fallback for the rest | keeps a separately specialized version for every case it meets |
| Where it lives | inside one handler, or at one patch site | in which version runs: the dispatch table, or the block version |

**A check is knowledge; what it proves is context.** An observing site's check belongs to that site, but once it passes, its outcome is a fact for the rest of the block, and in compiled code that fact enters the register map as context. After an `ADD` has checked that both operands are integers, every later instruction in the block knows its result is an integer and checks nothing. The interpreter has no room for such facts, since its only context is the cache state, so there a check stays purely local. This is the one point where the two axes meet.

**Inline cache or context split.** The same questions settle information that could go either way, such as types in a dynamic language. Information only the site uses, such as a call's target, becomes an inline cache: knowledge, committing to one case. Information later code reuses, such as an operand's type, becomes a context split: a test that branches into versions specialized per case, so every following instruction benefits, as in lazy basic block versioning.

For statically typed operations the boundary is clean. Knowledge without a check includes quickened `CALL n`, `TCALL k, n`, `RET k, r`, the `FCALL` signature shape and `EXT`; checked knowledge includes `CALLI`/`TCALLI` targets. Dynamic operations add checked type tags and open-word layout tokens: a fact used only at its site is knowledge, while a passed check that benefits later operations enters the successor block's context. These distinctions come from bytecode and observed values, not a source extension.

Some handlers stay generic deliberately. `CGETN`, `CSETN` and `OPC` choose a register or memory by depth with a few branchless conditional moves, which costs less than the 60 handlers a variant would add (rule 8).

## Compiled tier: a projection of the interpreter

The compiled tier has two host-selected policies over the same verified bytecode. Eager mode propagates every context available at load, compiles all reachable block versions, and leaves unavailable run-time facts to generic checked operations. Lazy mode places stable entry and edge stubs and compiles a block when a context first reaches it; that context can include observed type tags and checked layout tokens. Both policies use the same residualizer, version cap and register-addressed stencils. There is no profiling threshold, trace recording or source-extension check.

**Principles.**

1. **Contexts hold facts, never guesses.** A context records only what the bytecode proves along the incoming edge. Observed values enter only through sites' checked versions, compiled with the same check and the same generic fallback, so there is no deoptimization.
2. **Emission is stencil selection.** Every specialization is a choice among precompiled stencils, so the tier never invents machine code and inherits the stencils' testing.
3. **Every context can degrade.** Forgetting a fact is always safe. A version needing facts F is usable from any context that has at least F, and the generic version, which needs no facts, is always usable. Correctness never depends on specializing.
4. **State stays semantically architectural at every block boundary.** Stack positions, depths and values match the interpreter. A compatible compiled-to-compiled edge may carry a proven wide dynamic integer as raw register bits with its tag in the target context; that is a private representation of the same cell, not an extra semantic value. Any edge to the interpreter, generic fallback, incompatible version, memory or host ABI materializes the canonical dynamic cell first.
5. **Compilation timing is configuration.** Eager mode compiles at load. Lazy mode compiles on first context arrival. This choice is made by the host for the bytecode module and is independent of source filenames and language profiles.
6. **Sites keep specializing.** A site replaces its own version by the same rules in either tier, so both tiers share one definition of every specialization.

**Contexts.**

| Component | Holds | Proven by |
| --- | --- | --- |
| block | the bytecode address of the block | the edge |
| cache state | the operand bank pair (a, b) and C's cached count | the edge |
| site versions | the versions chosen from immediates, and those the sites have reached by observation | compile time, and the sites' own first executions |
| constants | cells whose value is known: literals, bindings set from them, operations on known values | propagation along the edge |
| dynamic facts | checked run-time tags and open-word layout tokens, when bytecode uses them | a check on the incoming path |
| call targets | callees known at the call site | direct calls, and callable views whose code is a proven constant |
| virtual continuation | for an inlined call: the return point and the caller's context | the call being inlined (roadmap step 3) |

**Mechanics.**

- **Version creation.** In eager mode, the compiler walks functions from their entries at load, propagates contexts along every edge, and compiles every reachable version; unavailable run-time facts use generic checked code. In lazy mode, stable entry and edge stubs compile a block version from the context that first arrives, then publish and reuse it. A block gets versions up to a small cap; at the cap, an edge conforms to the most specific compatible version, ultimately the generic one. A failed guard reaches another version or the generic path with architectural state materialized; it does not deoptimize speculative code.
- **Constants and known facts.** Residualization folds them: arithmetic on known values emits nothing, a branch on a known condition follows one edge, and division by a known non-zero value drops its zero check.
- **Virtual and run-time continuations.** Residualization continues through every statically known acyclic direct call while the callee entry remains within the ordinary block-version cap; byte length and nesting depth add no separate policy. Every instruction such a call involves is a stack move, so it is a renaming that emits nothing: `CALL.X f, n` moves the arguments into the callee's frame, the callee reads them with `CGET`, and `RET k, r` drops the frame and moves the results back. No return address is pushed, and the callee's `RET` continues straight into the caller's next block. Continuation-specialized entry versions consume the same cap as other versions; once it is full, that call uses a run-time C-stack continuation. Recursive SCCs are shared cyclic CFGs rather than unrolled virtual continuations: their direct calls materialize the continuation and values live across the activation, conform arguments to a capped register-entry version, and jump back to the SCC entry; a one-cell result returns in the canonical result register before `RET` dispatches through the continuation. Tail recursion remains a return-address-preserving backedge. Indirect calls whose target is not proven use the run-time convention.

**Execution policies.** The host or CLI selects interpreted, eager-JIT or lazy-JIT execution whenever it runs a verified bytecode module. This includes the compiler acting as host for a staging module: its compile-time policy is configured independently of the policy later used for residual code. Interpreted mode emits no native code and provides the low-startup baseline; eager mode prepares every reachable load-time version before execution; lazy mode starts from stable stubs and compiles on first context arrival. Neither JIT policy is selected by `.slet`, `.let`, staticness or dynamism; the VM does not receive the source extension. Dynamic operations run generically in eager mode when their facts are unavailable and can specialize by observed context in lazy mode.

**Timing.** Eager mode pays compilation at load and avoids first-arrival compilation pauses. Lazy mode pays only for contexts execution reaches and can specialize immediately from observed facts. Allocation and collection are properties of executed bytecode operations, not JIT policy. The verifier computes a transitive `allocation-free` function fact; a path through only such functions cannot trigger collection in any mode. A host-requested collection may remain pending indefinitely in an allocation-free loop, which creates no collectible garbage, and runs at the next eligible boundary. Errors remain terminal aborts rather than exceptions with unwinding.

**Why virtual continuations are sound.** A function sees only its own part of C: the verifier rejects any `CGETN`, `CSETN` or frame access at or below the function's own return address (verification rule 6). So no callee can tell whether its return address physically exists, and leaving it out changes nothing observable.

**Roadmap.** Each step works on its own and is measured before the next.

1. **Versions keyed by cache state, compiled at load.** Done when the load-time pass creates versions per reached context, the benchmarks run without conform code on their hot paths, and nothing gets slower.
2. **Residualization of all code.** Compile every block version by running the stack cache across it with a symbolic map from stack cells to registers, and copy one register-addressed stencil per residual operation, with `u32` operations in their 32-bit forms. Constants fold as part of it, and the state-keyed JIT stencils retire. Done when `skip`'s loop executes about one machine instruction per residual operation (about 20 per iteration with the call, against about 100 today) and load-time compile cost stays within about twice today's 27 ns per instruction.
3. **Virtual continuations for known acyclic callees.** Done when the loop in section 13's `skip` contains no `CALL` to `next32`; with residualization, its loop should come to about 10 machine instructions, as native C does.
4. **Configured lazy versions.** Add a lazy execution policy with stable entry/edge stubs and persistent version state. Compile any block on first context arrival, including checked tags and layout tokens in the key when present. Guard failure selects another capped version or the generic version; no speculative deoptimization is required.

**Non-goals.** No IR beyond the symbolic stack of the block being residualized, no register allocator (the stack cache allocates, by renaming and copy-on-write), and no trace recorder.

**Why not meta-tracing.** A meta-tracing JIT records hot paths, speculates and needs deoptimization. ABC needs none of those mechanisms. The host explicitly chooses eager or lazy compilation for the same bytecode. Eager mode residualizes every load-time-reachable context. Lazy basic-block versioning residualizes contexts on first arrival, without execution counters; checked run-time tags and layout tokens enrich context naturally. Sites guard observed values, and failed guards reach another capped version or the generic path with architectural state intact. Virtual continuations recover straight paths through known acyclic callees in either policy until the ordinary version cap selects the real continuation path.

**Residualization.** The compiled tier compiles a block by partially evaluating the interpreter's handlers with respect to that block's bytecode. Everything about where values live is static: stack positions, the cache state, immediates and site versions. Only the values are dynamic. So stack moves, renamings and constants evaluate at compile time and produce no code, and only real work is residualized: arithmetic on unknown values, compare-and-branch, memory access and calls. The generator's builder already does this for one instruction at a time; running it across a whole block, with a symbolic map from stack cells to registers, is residualization.

**The residual program is a sequence of stencils.** Copy-and-patch stays the only emission path. The compiled tier's stencils are register-addressed, keyed only by the registers an operation touches: `ADD` from `r5` into `r3` is one stencil, and every other register passes through in its fixed argument position. Each compiles to a single machine instruction once the tail jump is stripped (`add %r8, %rdx`), and a `u32` operation in its 32-bit form needs no `ZX32` mask (`xor %r9d, %edi` zero-extends for free). Partial evaluation only chooses which stencil to copy. A full renaming of the operand bank, which an interpreter cannot afford (261 states), costs nothing here, because only the touched registers key a stencil. In two-operand form over 8 data registers that is about 64 variants per operation, a few thousand stencils in all. Every block is residualized, so the compiled tier needs no state-keyed stencils: conform code at block boundaries is register moves, and flushing at calls is register stores. State-keyed code stays where it belongs, in the interpreter's handlers. Shifts by an immediate are the one wrinkle: a patched hole is not a compile-time constant, so clang shifts through `CL` (4 instructions); they get one stencil per amount, or a sentinel amount whose byte the extractor locates and patches.

**The stack cache is the register allocator.** No separate allocator is needed, because in a stack machine liveness is explicit: a value dies when it is consumed. Residualization keeps a symbolic map from stack cells to registers and applies three rules. Renaming: `CGET`, `DUP`, `MOVE`, `CPUSH` and `CSET` change which register a cell names and emit nothing. Copy-on-write: an operation that overwrites a register still named by another live cell first copies it to a free register, the only place a move is emitted. Freeing by consumption: popped cells release their registers, and a full bank spills its deepest cell, the interpreter's own policy. At a block boundary, the map is conformed to the layout the next block's entry fixed. Applied mechanically to `skip`'s inlined loop, these rules produce 16 instructions per iteration, against 14 for a hand-written allocation, and run at the same speed (1.89 to 1.93 ns per iteration, against 1.94 to 1.97 hand-written and 1.96 for native C); the two extra moves restore the loop's entry layout at the back edge, and modern cores largely eliminate register moves.

The measurements (Status and measurements) show why this is the right target. Residualization removes only 11% of operations relative to the bytecode, because the frame instructions and operand forms have already made the bytecode nearly a residual program. The glue is in today's state-keyed stencils, which spend about five machine instructions per bytecode instruction; register-addressed stencils spend one per residual operation.

## Native tier: residual to C

The native tier emits C from the residual program, by string building, and leaves register allocation, inlining and instruction scheduling to a C compiler. It is a build-time product: nothing is generated at run time, which suits microcontrollers running from flash and platforms that forbid writable executable memory.

| Residual program | C |
| --- | --- |
| a value | a local `V` variable |
| a stack position that crosses a block boundary | a home variable; the C compiler removes the copies |
| a block version | a label, reached by `goto` |
| a `u32` operation | `uint32_t` arithmetic, so masks vanish |
| compare-and-branch | `if (...) goto label;` |
| a Let function | one C function: a single result as its return value, several as a small struct returned in registers |
| an abort | a call to a `noreturn` function that returns to the host with `longjmp`; aborts are terminal, so the normal path carries no error checks |
| a self tail call | the parameters rebound, then `goto` to the entry |
| a tail call to another function | `return g(...)` marked `musttail` when the signatures match; otherwise the functions that tail-call one another share one C function, with a label per function |
| `FCALL` | a direct call to the C function |
| `CALLI` | a C indirect call; no inline cache, since the branch predictor does that job |

**Why it is simple.** The VM already knows every stack position, every value's lifetime and the order of every value, so the emitter only prints. In production it is the generator's builder run across a function and emitting C, the same semantics table that produces the interpreter's handlers and the compiled tier's stencils, so all three targets can be checked against one another with the same differential tests.

**One function per word.** Each Let function becomes one C function, so the output is readable, works with ordinary debuggers, and links naturally with foreign C code, and the C compiler inlines small functions and handles recursion on the C stack. One function for a whole module would defeat inlining and make the C compiler's time grow badly with module size. The calling convention decides the speed: on recursive fib(32), returning results through an output array and checking a return code after every call costs 2.10 ns per call, while results in registers with `noreturn` aborts cost 1.03, the same as hand-written C.

**The canonical route to C.** The native tier replaces a separate C backend in the Let compiler: Let compiles to bytecode, and the VM derives the interpreter, the compiled tier and C from it. One semantics stands behind every target.

## Bytecode module format and verification

A module is one file of tagged sections, and the loader verifies it before anything runs. The verifier guarantees stack, control-flow and call safety; it does not guarantee memory safety, because the unchecked `ptr` of Let is deliberately unchecked.

| Section | Contents |
| --- | --- |
| header | magic `ABC2`, format version, target pointer size |
| header | magic `ABC2`, format version, target pointer size and capability profile |
| functions | per function: entry offset, argument cells, result cells, hidden result block size and cell kinds |
| code | the bytecode of every function |
| data | the writable part of the module image: its size and initial snapshot from static execution; the loader places rodata right after it |
| rodata | string literals and constant tables |
| externs | per foreign word: C symbol name, parameter kinds and result kind |
| exports | public name and function index |
| profile sections | load kinds and callable relocations, plus dynamic descriptors, constants and module-root offsets when enabled |
**What the verifier checks.**

1. Every instruction decodes completely, and every jump target is an instruction start.
2. An abstract run over stack depths finds the depths of A, B and C at every instruction, with no underflow and one shape at every join.
3. C's frame blocks are tracked as well. `CGETN` and `CSETN` may address entries but never the bytes inside a block; `FLD`, `FST` and `FADDR` offsets must land inside a live block; `GLD` and `GADDR` offsets must land inside the image, and `GST` offsets inside its writable part.
4. `CALL` and `TCALL` targets are function entries and their argument counts match the function table, as does the result count of every `RET`. The frame count of every `RET` and `TCALL` equals the C depth above the return address at that point, so every return finds its return address.
5. Cells carry a profile-defined kind. Core kinds are integer, float and address; the dynamic profile adds `any`. Each instruction requires exact input kinds and defines exact output kinds.
6. A function sees only its own part of C: no `CGETN`, `CSETN`, `FLD`, `FST` or `FADDR` reaches its return address or anything below it. Callers' state is reached only through addresses passed as arguments, which is what lets the compiled tier leave return addresses out.

**Internal opcodes.** Verification sees only specified instructions. The loader rejects any opcode outside the specified set, then copies the module's code before running it; site rewriting (decision 13) changes only that copy, and only by replacing an opcode byte with an internal variant of the same length.

Loads and stores through an address are trusted. An SLet producer emits only addresses its lifetime rules allow. A Let producer additionally ensures that escaping managed addresses refer to promoted collected storage and appear in all required trace metadata. Code built from raw `ptr` remains the programmer's responsibility.

## Milestones and open questions

Each milestone ends with a Let program that agrees across VM execution and residual C emitted from the same bytecode semantics.

1. **Integer core.** Typed arithmetic with normalization, signed and unsigned compare-and-branch, calls with multiple arguments and results, `TCALL` and tail-call loops. Done when section 13's worked example (`xorshift`, `skip`, `roll`, `d6`) agrees in interpreted execution and residual C.
2. **Memory.** `CALLOC`, `CFREE` and the four bases (frame, image, pointer, indexed), plus `MEMCPY`: records, arrays, sums, slices and strings.
3. **Callables.** `CALLI`, closure environments and tagged callables.
4. **Host boundary.** `FCALL` bridges, exported entry points and the image snapshot.
5. **Static execution on the VM.** The partial evaluator lowers known subprograms to verified bytecode and executes them without fuel accounting; compiler progress/interrupt diagnostics and the residual-image snapshot are part of this milestone.
6. **JIT for the full typed ISA and staging parity.** Permit the compiler host to select eager or lazy JIT for the same staging modules, require identical known results and residual bytes in all modes, then benchmark compile time against interpreted staging and benchmark residual C from the same bytecode.
7. **Dynamic-value profile in the interpreter:** profile-5 loading and verification, one-cell `any`, same-length quickened `EXT` operations, collected ordered-map open words with layout-token caches, allocation-free facts, managed storage and collection, checked against typed semantics.
8. **Dynamic compiled execution:** eager generic paths and configured lazy block versions over the same modules, with tag/layout-token contexts, stable stubs, version caps and GC-safe compiled safepoints.

## Status and measurements

**Milestone 1 is built.** `gen.lua` generates the interpreters and the JIT stencils, `jit.c` is the copy-and-patch compiler, and `harness.c` holds a test-only direct instruction model, the random tests and the benchmarks. It implements 100 opcodes: integer arithmetic with normalization, compares, branches, calls with `TCALL`, context access and checks that abort. Floats, memory, `SWITCH` and indirect and foreign calls belong to later milestones. All four builds match the test model on 30,000 random programs, 17% of which end in an abort. This model validates VM instructions; it is not a Let source evaluator or compiler execution path.

Time per executed instruction, in ns (best of five runs on a shared x86-64 VM):

| Benchmark | Interpreter, nothing cached | Interpreter, operand bank | JIT, nothing cached | JIT, operand bank |
| --- | --- | --- | --- | --- |
| sum | 0.93 | 0.75 | 0.32 | 0.11 |
| poly | 0.97 | 0.73 | 0.30 | 0.07 |
| chain | 1.03 | 0.78 | 0.56 | 0.24 |
| fib | 1.08 | 0.88 | 0.31 | 0.26 |
| skip (section 13) | 1.23 | 0.84 | 0.92 | 0.21 |

The operand bank makes the JIT 2.4 to 4.3 times faster on loops; fib gains only 1.2 times, because its cost is calls. `skip` takes 6.4 ns per iteration against 2.2 ns for native C with `next32` not inlined; the gap is the flush-everything call convention.

**The simulator.** ABC VM Lab is a single HTML file that shows the three stacks and the operand bank register by register. It compiles a subset of SLet: words with typed parameters and result contracts, multiple results, `do ... end` blocks, field stores, expression conditionals, `and`/`or`/`not`, static constants, static partial supply, and records with methods, scalarized as in question 3. Its fixed and randomized fixtures cover 19 example programs and about 7,400 random typed programs. The simulator is historical design evidence, not an evaluator retained by the production compiler.

**Range reads.** `CGETR.X d, n` (decision 6) copies the n cells from depth d onto X, shallowest first. A record on C has its first field on top, while on A its first field is deepest; copying one cell at a time reverses the order, which is exactly that layout change. With `CPUSHN` also reversing, pushing a block to C and reading it back restores its order. Measured after the frame instructions, range forms would remove 1.5% of executed instructions across the 19 examples, nearly all of it record copies (11% to 26% in the record programs); a store form would remove only 8 instructions in total, so only the read is adopted.

**Sharing the whole register budget.** The simulator takes the bank sizes as parameters, so splits of the same eight registers can be compared directly. Memory operations across the 19 examples:

| Operand bank / C bank | 4 / 4 | 3 / 5 | 5 / 3 | 6 / 2 | 2 / 6 |
| --- | --- | --- | --- | --- | --- |
| Memory operations | 546 | 756 | 644 | 1,055 | 1,445 |

The fixed 4/4 split is best overall. Choosing the best split for each program separately would save only 8.8% (498 operations), and a wrong split costs far more than a right one saves. If it is ever worth doing, the split should be chosen statically per function from a small menu and held fixed inside it.

**Calls.** Before the frame instructions, a call spelled its frame out one cell at a time: `CALL`, a `CPUSH` per argument, the body, a `CPOP` per frame cell, `RET`; a tail-call loop spent a `CSET` per parameter plus a `JMP`. With `CALL f, n`, `RET k` and `TCALL f, k, n`, the 19 compiled examples execute 16.2% fewer instructions (7,230 down to 6,056), and 22% to 29% fewer in the programs with calls, records and loops; code shrinks by 22% (903 instructions to 703) and memory operations fall by 9% (546 to 495), with every result unchanged. A separate consuming read (`CTAKE`) is no longer needed: `RET k` absorbs the pops it was saving. What remains per call is the inherent cost of values live across it. Fib(10) makes 178 calls and about 1.5 memory operations per call, nearly all of them preserving the one value that must survive the first recursive call, which any machine must pay.

**Result bit on calls.** Before `CALL.X`, a call compiled for B needed a `MOVE.AB` after it. Across the 19 examples that was 89 of 6,056 executed instructions (1.5%), nearly all in recursive fib, where it is 4.5%: recursion inside an expression is exactly where it appears. The bit removes it and makes the instruction set uniform, at no opcode cost beyond the two forms of `CALL` and `CALLI`.

**Operand forms.** Before them, the most frequent adjacent pairs were a constant push followed by an operation (10.9% of executed instructions) or by a compare-and-branch (5.6%), and a `CGET` followed by an operation (3.3%) or a branch (3.2%); an operation followed by `CSET` never occurred. With the adopted forms, the 19 examples execute 18.9% fewer instructions than with the frame instructions alone (6,056 down to 4,911) and 18% to 25% fewer in every loop and recursion program, code shrinks from 703 to 636 instructions, and every result is unchanged. Of the removed dispatches, 516 were branches against an immediate, 454 operations with an immediate and 176 operations with a C cell.

**Timed in the interpreter.** The frame instructions, the result bit and the operand forms are built into the generated interpreter. The spec forms of `CALL`, `TCALL` and `RET` quicken themselves on first execution, by the site rewriting of decision 13: the handler rewrites its opcode into an internal variant with the counts built in, so every handler knows its register moves statically and the bytecode format stays exactly as specified. This build quickens counts up to 4 and result counts up to 2, and aborts with reason 254 beyond that. All 30,000 random programs still agree across generated execution and the test-only instruction model, now including the operand forms, and two-result calls deliver correctly to A and to B. Time per iteration (per call for fib), each benchmark written before and after in the same build:

| Benchmark | Before | After | Speedup | Instructions |
| --- | --- | --- | --- | --- |
| sum | 8.1 ns | 6.7 ns | 1.22x | 10 → 8 |
| poly | 15.5 ns | 12.3 ns | 1.26x | 19 → 14 |
| chain | 19.0 ns | 12.3 ns | 1.54x | 24 → 15 |
| fib | 7.3 ns | 6.9 ns | 1.06x |  |
| skip (section 13) | 25.9 ns | 19.5 ns | 1.33x | 30 → 22 |

**Every opcode costs 60 handlers.** The interpreter grew from 100 to 187 internal opcodes (the quickened call forms account for 50) and from 6,000 handlers in 0.85 MB of code to 11,220 in 1.3 MB. That growth alone slowed unchanged programs by up to 25% until the rarely run handlers (aborts, checks, division, `POW` and the self-quickening spec forms) were marked cold, which moves them out of the hot code. Code layout still shifts individual results by about 10% between builds: marking handlers cold sped up every loop but slowed `skip` from 17.6 to 19.5 ns. This is the measured reason the opcode budget is guarded.

**Residualization measured.** A residualizer over the simulator's bytecode (experiments, `residual.js`) treats the stacks as static data, folds constants, and counts residual work, including one move per value that is not where the next block expects it. Across the 19 examples it leaves 4,307 operations for 4,821 executed bytecode instructions: calls with their argument moves 1,563, compute 960, `ZX32` masks 620, moves at block exits 620, branches 544. On `skip`, the same loop measured four ways:

| Per iteration | Operations |
| --- | --- |
| bytecode instructions | 22 |
| residual operations | 20: 7 compute, 3 masks, 1 branch, 6 for the call, 3 exit moves |
| residual, `next32` inlined and `u32` in 32-bit registers | about 10 |
| machine instructions of today's JIT | about 100 (136 for the program's 28 bytecode instructions) |
| native C (clang) | about 15 with the call, about 10 inlined |

So the bytecode is already close to a residual program, and the cost lies in per-instruction stencils; residualized code should land near native.

**Residual stencils prototyped.** A prototype (experiments, `residual_stencils/`) generates 161 register-addressed stencils with the real toolchain (clang, then the extractor), copy-and-patches the residual program for `skip`'s inlined loop into executable memory with `jit.c`'s rules, and checks the result against native C. Timed back to back on the same machine, in ns per iteration: LuaJIT 1.84, residual stencils 1.90, native C 1.96 (1.99 inlined), today's JIT with `next32` inlined by hand 4.07. Concatenated register-addressed stencils therefore reach native speed on this loop, 2.1 times faster than today's JIT. With registers chosen mechanically by the stack cache (renaming and copy-on-write), the loop runs at the same speed as with a hand-written allocation. Two limits remain. The loop is latency-bound, which hides extra instructions, so a throughput-bound loop and a branchy one still need measuring. And two clang quirks cost instructions (a zero test takes 4 instead of 2, a subtract-immediate goes through a register); both are fixable with per-constant stencils or sentinel bytes.

**Native tier prototyped.** An emitter of about 250 lines (experiments, `emitc.js`) prints the residual program of each block as C, with home variables at block boundaries, labels for blocks and one C function per Let function. All 19 fixed examples produce their specified results, including multiple results, records, methods, the result bit, tail calls and the division-by-zero abort. Section 13's `skip` running 12.5 million iterations, taken from Let source through bytecode and residual C, runs at 2.14 ns per iteration, the same as hand-written C in the same run (2.14 with `next32` inlined or not). Recursive fib(32), where no inlining can hide the calling convention, runs at 1.03 ns per call with results in registers and noreturn aborts, the same as hand-written C, against 2.10 with results through an output array and a return-code check after every call.

**Compile cost measured.** Compiling and running a 15,000-instruction straight-line program once takes 26.8 ns per instruction on the JIT, against 0.7 ns on the interpreter. Each JIT run also spends about 115 µs mapping its code region and allocating 64K-entry decode tables, a fixed cost to remove from `jit.c`; it dominated the 20,000 tiny programs of the random test suite (2.4 s on the JIT against 0.13 s on the interpreter).

**The four-lane fork.** A separate design (four identical lanes of two cached cells, a routing byte with keep bits, continuations as buried tokens exposed by `UNWIND`) was compiled from the same Let programs and run on a model of its cache rules. All 12 test programs give identical results on both machines.

| Total over the 12 programs | Four-lane | A/B/C |
| --- | --- | --- |
| Instructions executed | 40,737 | 58,225 |
| Memory operations | 9,122 | 5,389 |
| `UNWIND` instructions | 2,310 | none |
| Lane-to-lane moves | 7,220 | none |

Specialized on opcode, routing byte and cache state, the fork would need about 330,000 stencils for the integer core, yet the programs reach only 187 combinations, 119 of which cover 99% of execution; a handler specialized on the routing byte alone runs at about 1.0 ns per instruction without any cache state. So it is buildable, and it executes 30% fewer instructions. A/B/C stays the design: the fork moves 69% more memory and spends 18% of its instructions placing arguments and results, and it exists only as an experiment, while A/B/C is built, tested and has small fixed state counts. What carries over is the idea that a call moves state instead of copying it, which the frame instructions now do.

**Spec questions found while building.** All three are settled under Decisions: negative literals (decision 8), the duplicate check `CHKI63` (decision 7) and how `!=` treats NaN (decision 4).

**Decisions.** These questions were open in earlier drafts. Each is now settled, with the evidence behind it.

**1. Calls and registers.** Decided: no register convention is part of the machine. Calls are defined on the stacks by the frame instructions, and the interpreter's handlers carry the cache state straight through `CALL` and `RET`: nothing is flushed, and the callee starts in whatever state its caller left. A compiled tier must produce the same stacks and may hold them in registers however it likes. What a call still costs is measured under Status and measurements: the values live across it, which any machine pays.

**2. How parameters reach C.** Decided: `CALL.X f, n` moves the argument cells into the callee's frame, so there is no prologue. `CPUSHN n` stays for binding several results at once and reverses its cells exactly as n `CPUSH`es would, so `CGETR` (decision 6) reads them back in order. Frame blocks hold only what needs an address: arrays, and records named by a `ref` or `ptr` (decision 3).

**3. Small records in cells.** Decided, and implemented in the simulator's compiler, more widely than first proposed, with no change to the VM. A record is its fields' cells in canonical (name) order, nested records flatten, and passing and returning copy the cells. A method on such a record compiles copy-in/copy-out: the receiver's cells go in as leading arguments and come back as trailing results, which the caller writes back with `CSET`. A local alias (`let c = b` on a record) shares the cells and emits no code. Verification rule 6 makes this sound, because a callee never reaches its caller's C and so cannot observe the copy. Only a record that a `ref` or `ptr` names must live in memory. A size cutoff is a JIT tuning choice, not a rule: cells beyond the bank spill like any other.

**4. Float branches.** Decided: add `FBEQ` and stop there. `a != b` compiles to `FBEQ` with the two targets swapped, and `not (a < b)` to `FBLT` with swapped targets. Comparisons follow IEEE-754: `==` and every ordered comparison are false when an operand is NaN, and `!=` is the negation of `==`, so `NaN != NaN` is true. That keeps `a != b` and `not (a == b)` the same expression, which the compiler relies on. The Let sentence "a NaN comparison is false" should be read as covering `==`, `<`, `<=`, `>` and `>=`.

**5. Targets.** Decided: x86-64 first, ARM64 next. ARM64's 24 argument registers leave room for larger banks, sized by the same measurements as on x86-64. A 32-bit target is not planned: `u64`, `i64` and `f64` assume 64-bit cells, and the native tier's C output (decision 16) covers small machines.

**6. Range reads.** Decided: adopt `CGETR.X d, n`, which copies the n cells from depth d of C onto X, shallowest first. It copies a whole record off C in one instruction. Measured after the frame instructions, it removes 1.5% of executed instructions across the 19 examples and 11% to 26% in the record programs. A store form, `CSETR`, would remove only 8 instructions in total, so it is not adopted.

**7. Duplicate check.** Decided: `CHKI63` is merged into `CHKNN`. Converting `i64` to `u64` and `u64` to `i64` is the same test, because either way the value fits exactly when its top bit is clear.

**8. Negative literals.** Decided, as a change to the Let literal rule: a minus written directly before a literal makes a signed literal, which adopts the type of the typed operand or slot it meets like any literal, and is an `i64` when nothing gives it a type. So `-5` is -5 whether it meets an `i32` or an `i64`. Negating anything else stays modular in its operand's type. This replaces the reading of `-1` as modular `u32` negation, under which `-5` passed to an `i64` became 4294967291. The simulator's compiler still follows the old rule until it is updated.

**9. Register budget.** Decided: A and B keep one bank of four registers, C keeps its own bank, and C stays a single lane. Every alternative measured under Status and measurements loses overall: other splits of eight registers, two C lanes (402 memory operations at best, against 402 for one lane) and per-site hot and cold placement. Even a perfect per-program choice would save only 9% to 11%.

**Why a stack cache is the right cache for C.** C is addressed by depth, like memory, but its order is not arbitrary: a cell's depth changes only when something is pushed or popped above it, so `C[n]` is always the n-th most recently pushed live cell. Lexical scoping in Let is lexical, so the most recently bound values are almost always the next ones read. Caching the newest cells therefore caches the cells most likely to be used, with no bookkeeping: the cache policy is the stack discipline itself. The measurements agree: 98% of C reads are at depth 2 or less, and every attempt to outsmart the policy lost (static lanes, other register splits, per-site hot and cold placement, and a cache state fixed by frame depth, which cost 73% more traffic). The only better placement is the perfect-foresight bound (72% less traffic), which depends on the path taken and is therefore a compilation question, not a caching one. The one case recency cannot help, a value that must survive a deep call, is inherent, and the lazy bank already pays the minimum for it. So C is addressed by depth, which is free because every depth is static, and it is fast because its semantics already sort it by likelihood of use.

**10. `FOLD2`.** Decided: not adopted. It saves interpreter dispatches only where the compiler finds pairs of independent operations, and no measured program needs it. It stays described in the operand bank section as an extension.

**11. Operand forms.** Decided: a binary operation's second operand may be the other stack's top, a C cell or an i8 immediate (section on the instruction set). The adopted set is `OPI.X` for `ADD`, `SUB`, `MUL`, `AND`, `OR`, `XOR`, `SHL`, `SHR` and `SAR`; `OPC.X` for `ADD`, `SUB`, `MUL` and `XOR`, which cover nearly all measured uses; and compare-and-branch against an immediate on A, in both directions and both signednesses: 36 opcodes. On the 19 examples they remove 18.9% of executed instructions on top of the frame instructions. Not adopted, for lack of measured need: a C cell as the first operand, a result stack different from X, and branches against a C cell (3.2% of executed instructions).

**12. Escape prefix.** Decided: one opcode, `EXT`, is reserved as an escape: the byte after it selects an extended instruction, whose own immediates follow. Rare public instructions do not consume the scarce core byte map. In the interpreter's private code copy, a monomorphic checked-specific hot site may replace `EXT` with an operation-specific internal opcode of the same total instruction length; unquickened and final-generic sites keep the compact two-level dispatch, and compiled stencils pay no byte dispatch. Serialized internal opcodes reject. Profile 5 must first reclaim enough internal encodings from the prototype's oversized call-quickening set and then allocate only measured hot dynamic forms.

**13. Versions.** Decided: every specialization is a version of a site, specialized along two axes (section on site rewriting). The arrival context selects among coexisting versions up to a cap, then a compatible generic version. Interpreter cache-state handlers are generated ahead of time. In eager JIT mode, compiled block versions are created at load from every reachable context then available; in lazy JIT mode, they are created when a context first reaches the block. The site's own knowledge replaces its versions monotonically, at most twice. Nothing counts executions: first arrival is a deterministic linkage event, not a hotness threshold.

**14. Compiled tier by residualization.** Decided: the compiled tier partially evaluates the interpreter's handlers with respect to every block, so stack moves and constants vanish at compile time, and expresses each block's residual program as a sequence of register-addressed stencils, each a single machine instruction. Registers are allocated by the stack cache itself, through renaming and copy-on-write, so the tier has no register allocator, and it needs no state-keyed stencils: those remain the interpreter's handlers. Copy-and-patch remains the only way code is emitted, and no tracer is needed. It is the same principle as source-level partial evaluation in Let, one level down: Let folds away types and known values, the compiled tier folds away stack positions.

**15. Execution policy is configuration.** Decided: the VM does not inspect source filenames or distinguish `.slet` from `.let`; it executes verified bytecode under a policy selected by its host. The Let compiler may independently select interpreted, eager-JIT or lazy-JIT for staging and residual modules. Interpreted mode emits no native code. Eager JIT compiles every block version reachable from load-time contexts before execution and uses generic checked operations for unavailable facts. Lazy JIT creates capped versions on first context arrival through stable stubs, including checked tags and layout tokens when present. There are no hotness counters, automatic tier promotion or speculative deoptimization.

**16. Native tier: residual to C.** Decided: the VM emits C from the residual program by string building, as a build-time product, and that is the canonical route to C, replacing a separate C backend in the Let compiler, so every target derives from one semantics. The C output preserves generic checked operations required by run-time dynamism; it is independent of the interpreter/eager/lazy policy chosen when bytecode runs in the VM.

**17. Dynamic-value and managed-ownership profile.** Decided: profile 5 adds scalar kind `any`, descriptor/constant tables, precise module-root metadata, managed reference/view tracing, collected ordered-map open words with non-owning layout tokens, allocation-free verification and public generic operations behind quickenable `EXT`. Generic operations reuse typed semantics and A/B routing; missing dynamic results abort rather than becoming `unit`; `f64` never boxes; and compiled proven wide integers box only on escape. Open-word keys and values are reclaimed with the word; layout tokens contain no key metadata, change on structural mutation, and may guard constant-field caches and capped block versions. A source compiler uses profile 5 for reachability-based ownership in Let. The capability profile neither selects execution policy nor depends on a source extension. `dynamic-profile.md` is normative.

These decisions add `CPUSHN`, `FBEQ`, `CGETR.X`, the frame immediates, the result bit on `CALL` and `CALLI`, the 36 operand forms, the escape prefix and the profile-5 dynamic metadata and operations, and remove `CHKI63`: the public core ISA has 223 opcodes, reserving 33 core encodings for internal quickening and later additions, plus generated public dynamic selectors behind `EXT`.
