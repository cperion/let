# Symmetric ABC ISA — revision 6 design

**Status: approved revision-6 contract; typed execution/tooling/frontend integration passes.** This document fixes the opcode allocation, instruction layouts and machine contracts implemented by the manifest, shared transfers, interpreter, symbolic/native bindings, assembler, loaders, verifier and typed producers. It supersedes the old A-left/destination-only interpretation; old executable revisions are rejected, not reinterpreted. A clean copied-source `all validate` passes; see [integration evidence](../research/experiments/ab-symmetry/phase-4-final-fixtures/README.md). `REFACTOR.md` tracks remaining migration closure: full contract/documentation/dead-path audit and performance follow-up. The [fixed old/new comparison](../research/experiments/ab-symmetry/final-comparison/README.md) is measured, including regressions and native code growth. Dynamic reintegration and broader native region redesign remain separate work.

## 1. Decisions

1. A and B are exchange-symmetric. `.X` selects the primary operand stack; Y denotes its opposite. Binary operations compute `X0 op Y0`, consume both operands and leave their result on X.
2. C retains structured state. C reads select an A/B destination; C writes select an A/B source.
3. `CALL.X` gathers arguments from X and records X as the continuation's result destination. `RET.X` identifies the callee's result source, independently of that destination.
4. No implicit bank-orientation mode, mirrored function bodies, A-only staging engine or operand-order repair adapter.
5. No internal quickened bytecodes and no opcode reservations for them. Existing cache-state handlers remain.
6. The core byte is completely allocated: **124 ordinary A/B families × 2 + 2 EXT prefixes + 6 neutral instructions = 256 bytes**.
7. Four C-operand arithmetic families, ten immediate-branch families and two raw integer/binary64 bitcasts use EXT. All other existing typed families retain direct core opcodes, now symmetric. No typed semantic operation is removed.
8. Module revision is **6**, with capability profile independently selected from 1–4. Old module revisions are not reinterpreted or supported by a second semantic engine in the migrated runtime.
9. Remove serialized indirect-call cache words. Observations belong to VM-local records keyed by original instruction identity, not mutable instruction operands.

The encoding trade-off is explicit: this retains a one-byte core opcode and all existing typed operations, but **does not give every historical fused operand form a one-byte operation encoding**. The fourteen extended families use a two-byte prefix/selector encoding. Calling these forms cold is not assumed; their interpreter cost must be measured. Keeping every mirrored historical form directly in the core would require 284 bytes, even without quickening.

## 2. Encoding conventions

- Cells are 64 bits. Typed profiles use integer, address and binary64 float kinds; the integer profile admits integers only.
- All multi-byte instruction fields are little-endian and unaligned. `i8`, `i16`, `i32` are two's-complement signed encodings; `u8`, `u16`, `u32` are unsigned.
- For core bytes `00`–`F9`, bit 0 selects A=0 or B=1. Exchanging A/B toggles that bit. Bytes `FA`–`FF` are neutral and mirror to themselves.
- `F8` is EXT.A; `F9` is EXT.B. The next byte selects an extended family and carries no second bank selector. The remaining fields belong to that family. EXT is not a stateful bank prefix for later instructions.
- An extended operation is one instruction with one original PC, one stack effect and one trap origin. Its PC is the prefix byte. Branches cannot target its selector or operand bytes.
- All relative displacements are measured from the end of the complete instruction. SWITCH offsets are measured from the end of the complete switch table.
- No alignment padding, instruction mode word, private arity opcode or mutable inline cache word is part of this ISA.
- Hexadecimal bytes in the following table are exact allocations, not examples.

### Complete core allocation

For selected forms, the first byte is `.A` and the second is `.B`. Operand layouts are specified in section 3.

| A / B opcode | Family |
| --- | --- |
| `00` / `01` | `HALT.X` |
| `02` / `03` | `PUSH8.X` |
| `04` / `05` | `PUSH32.X` |
| `06` / `07` | `PUSH64.X` |
| `08` / `09` | `DUP.X` |
| `0A` / `0B` | `DROP.X` |
| `0C` / `0D` | `COPY.X` |
| `0E` / `0F` | `MOVE.X` |
| `10` / `11` | `CPUSH.X` |
| `12` / `13` | `CPUSHN.X` |
| `14` / `15` | `CGET0.X` |
| `16` / `17` | `CGET1.X` |
| `18` / `19` | `CGETN.X` |
| `1A` / `1B` | `CGETR.X` |
| `1C` / `1D` | `CSET0.X` |
| `1E` / `1F` | `CSETN.X` |
| `20` / `21` | `ADD.X` |
| `22` / `23` | `SUB.X` |
| `24` / `25` | `MUL.X` |
| `26` / `27` | `DIVU.X` |
| `28` / `29` | `DIVS.X` |
| `2A` / `2B` | `REMU.X` |
| `2C` / `2D` | `REMS.X` |
| `2E` / `2F` | `AND.X` |
| `30` / `31` | `OR.X` |
| `32` / `33` | `XOR.X` |
| `34` / `35` | `SHL.X` |
| `36` / `37` | `SHR.X` |
| `38` / `39` | `SAR.X` |
| `3A` / `3B` | `EQ.X` |
| `3C` / `3D` | `NE.X` |
| `3E` / `3F` | `LT.X` |
| `40` / `41` | `LE.X` |
| `42` / `43` | `LTU.X` |
| `44` / `45` | `LEU.X` |
| `46` / `47` | `NEG.X` |
| `48` / `49` | `NOT.X` |
| `4A` / `4B` | `LNOT.X` |
| `4C` / `4D` | `ZX32.X` |
| `4E` / `4F` | `SX32.X` |
| `50` / `51` | `ZX8.X` |
| `52` / `53` | `ZX16.X` |
| `54` / `55` | `POW.X` |
| `56` / `57` | `POWS.X` |
| `58` / `59` | `CHKU8.X` |
| `5A` / `5B` | `CHKU16.X` |
| `5C` / `5D` | `CHKU32.X` |
| `5E` / `5F` | `CHKI32.X` |
| `60` / `61` | `CHKNN.X` |
| `62` / `63` | `SWITCH.X` |
| `64` / `65` | `JZ.X` |
| `66` / `67` | `JNZ.X` |
| `68` / `69` | `BEQ.X` |
| `6A` / `6B` | `BNE.X` |
| `6C` / `6D` | `BLT.X` |
| `6E` / `6F` | `BLE.X` |
| `70` / `71` | `BLTU.X` |
| `72` / `73` | `BLEU.X` |
| `74` / `75` | `ADDI.X` |
| `76` / `77` | `SUBI.X` |
| `78` / `79` | `MULI.X` |
| `7A` / `7B` | `ANDI.X` |
| `7C` / `7D` | `ORI.X` |
| `7E` / `7F` | `XORI.X` |
| `80` / `81` | `SHLI.X` |
| `82` / `83` | `SHRI.X` |
| `84` / `85` | `SARI.X` |
| `86` / `87` | `CALL.X` |
| `88` / `89` | `TCALL.X` |
| `8A` / `8B` | `RET.X` |
| `8C` / `8D` | `FLD8.X` |
| `8E` / `8F` | `FLD16.X` |
| `90` / `91` | `FLD32.X` |
| `92` / `93` | `FLD32S.X` |
| `94` / `95` | `FLD64.X` |
| `96` / `97` | `FST8.X` |
| `98` / `99` | `FST16.X` |
| `9A` / `9B` | `FST32.X` |
| `9C` / `9D` | `FST64.X` |
| `9E` / `9F` | `FADDR.X` |
| `A0` / `A1` | `GLD8.X` |
| `A2` / `A3` | `GLD16.X` |
| `A4` / `A5` | `GLD32.X` |
| `A6` / `A7` | `GLD32S.X` |
| `A8` / `A9` | `GLD64.X` |
| `AA` / `AB` | `GST8.X` |
| `AC` / `AD` | `GST16.X` |
| `AE` / `AF` | `GST32.X` |
| `B0` / `B1` | `GST64.X` |
| `B2` / `B3` | `GADDR.X` |
| `B4` / `B5` | `LD8.X` |
| `B6` / `B7` | `LD16.X` |
| `B8` / `B9` | `LD32.X` |
| `BA` / `BB` | `LD32S.X` |
| `BC` / `BD` | `LD64.X` |
| `BE` / `BF` | `ST8.X` |
| `C0` / `C1` | `ST16.X` |
| `C2` / `C3` | `ST32.X` |
| `C4` / `C5` | `ST64.X` |
| `C6` / `C7` | `LDX8.X` |
| `C8` / `C9` | `LDX16.X` |
| `CA` / `CB` | `LDX32.X` |
| `CC` / `CD` | `LDX32S.X` |
| `CE` / `CF` | `LDX64.X` |
| `D0` / `D1` | `IDX.X` |
| `D2` / `D3` | `MEMCPY.X` |
| `D4` / `D5` | `CALLI.X` |
| `D6` / `D7` | `TCALLI.X` |
| `D8` / `D9` | `FCALL.X` |
| `DA` / `DB` | `FADD.X` |
| `DC` / `DD` | `FSUB.X` |
| `DE` / `DF` | `FMUL.X` |
| `E0` / `E1` | `FDIV.X` |
| `E2` / `E3` | `FLT.X` |
| `E4` / `E5` | `FLE.X` |
| `E6` / `E7` | `FEQ.X` |
| `E8` / `E9` | `FNEG.X` |
| `EA` / `EB` | `I2FS.X` |
| `EC` / `ED` | `I2FU.X` |
| `EE` / `EF` | `F2IS.X` |
| `F0` / `F1` | `F2IU.X` |
| `F2` / `F3` | `FBLT.X` |
| `F4` / `F5` | `FBLE.X` |
| `F6` / `F7` | `FBEQ.X` |
| `F8` / `F9` | `EXT.X` |

| Neutral opcode | Instruction |
| --- | --- |
| `FA` | `CPOP` |
| `FB` | `CALLOC` |
| `FC` | `CFREE` |
| `FD` | `JMP` |
| `FE` | `JMP32` |
| `FF` | `ABORT` |

### Extended allocation

The selected bank comes from F8/F9. These selectors are revision-6 assignments; historical profile-5 selectors have no revision-6 meaning.

| Selector | Family | Fields after selector | Total bytes |
| --- | --- | --- | --- |
| `00` | `ADDC.X` | u8 depth | 3 |
| `01` | `SUBC.X` | u8 depth | 3 |
| `02` | `MULC.X` | u8 depth | 3 |
| `03` | `XORC.X` | u8 depth | 3 |
| `04` | `BEQI.X` | i8 constant, i16 displacement | 5 |
| `05` | `BNEI.X` | i8 constant, i16 displacement | 5 |
| `06` | `BLTI.X` | i8 constant, i16 displacement | 5 |
| `07` | `BLEI.X` | i8 constant, i16 displacement | 5 |
| `08` | `BGTI.X` | i8 constant, i16 displacement | 5 |
| `09` | `BGEI.X` | i8 constant, i16 displacement | 5 |
| `0A` | `BLTUI.X` | i8 constant, i16 displacement | 5 |
| `0B` | `BLEUI.X` | i8 constant, i16 displacement | 5 |
| `0C` | `BGTUI.X` | i8 constant, i16 displacement | 5 |
| `0D` | `BGEUI.X` | i8 constant, i16 displacement | 5 |
| `0E` | `F2BITS.X` | none | 2 |
| `0F` | `BITS2F.X` | none | 2 |

The bitcasts are additive revision-6 assignments, requiring profile 2+. Existing valid bytecode retains its meaning; earlier engines reject these previously unassigned selectors. Selectors 10–FF are unassigned. No dynamic, word, GC or fused-guard selectors are allocated in this typed revision. EXT executes declared typed operations through the same semantic definitions and cache bindings; it is not an opaque execution fallback. No separate EXT rejection subsystem or dedicated rejection project is part of this migration; normal format verification uses the declared instruction set.

## 3. Exact instruction layouts

`opcode` includes the selected bit where applicable. All lengths below include that byte; extended lengths above include both prefix and selector. Any core family not listed with fields here is exactly one byte.

| Family | Bytes after opcode, in order | Total bytes |
| --- | --- | --- |
| PUSH8.X | i8 value | 2 |
| PUSH32.X | i32 value | 5 |
| PUSH64.X | u64 raw bits | 9 |
| CPUSHN.X | u8 count | 2 |
| CGETN.X, CSETN.X | u8 depth | 2 |
| CGETR.X | u8 depth, u8 count | 3 |
| ADDI/SUBI/MULI/ANDI/ORI/XORI/SHLI/SHRI/SARI.X | i8 constant | 2 |
| JZ/JNZ/BEQ/BNE/BLT/BLE/BLTU/BLEU/FBLT/FBLE/FBEQ.X | i16 displacement | 3 |
| SWITCH.X | u16 count, count × i32 displacement | 3 + 4 × count |
| CALL.X | i32 displacement, u8 arguments | 6 |
| TCALL.X | i32 displacement, u8 frame cells, u8 arguments | 7 |
| RET.X | u8 frame cells, u8 results | 3 |
| CALLI.X | u8 arguments | 2 |
| TCALLI.X | u8 frame cells, u8 arguments | 3 |
| FCALL.X | u16 extern index | 3 |
| FLD*/FST*/FADDR.X | u16 frame-byte offset | 3 |
| GLD*/GST*/GADDR.X | u32 image-byte offset | 5 |
| LD*/ST*.X | u16 pointer-byte offset | 3 |
| IDX.X | u16 element bytes | 3 |
| MEMCPY.X | u32 byte count | 5 |
| CALLOC, CFREE | u16 requested bytes | 3 |
| JMP | i16 displacement | 3 |
| JMP32 | i32 displacement | 5 |
| ABORT | u8 reason | 2 |

Encoding examples:

```text
PUSH8.A 10; PUSH8.B 3; SUB.B; RET.B 0,1
02 0A       03 03      23     8B 00 01
// returns -7 from B; both original operands were consumed

SUBC.B 2
F9 01 02
// B0 ← B0 - C[2], with A and C unchanged

BEQI.B 0, displacement=0
F9 04 00 00 00
// consumes B0; branch base is immediately after all five bytes
```

A CALLI signature is still supplied by the immutable indirect-site signature section at the original PC. It is not replaced by an untyped argument count. Removing four mutable cache bytes reduces CALLI from six to two bytes and TCALLI from seven to three; it does not remove ABI checks.

## 4. Operand and scalar contracts

Notation: `X0` is the top value on X before execution; Y is the opposite stack. Every consumed input must remain live until the operation has read it. Other operand values and unrelated C state remain unchanged unless the operation explicitly writes them.

### Stack and context operations

| Family | Contract |
| --- | --- |
| PUSH*.X | Push integer bits on X. PUSH8/32 sign-extend; PUSH64 preserves all bits. |
| DUP.X | Capture X0 and push another name/value on X. |
| DROP.X | Pop X0. |
| COPY.X | Capture X0 and push it on Y; retain X0. X selects the source. |
| MOVE.X | Pop X0 and push that captured value on Y. X selects the source. |
| CPUSH.X | Pop X0 and push it on C. |
| CPUSHN.X n | Perform n CPUSH.X transfers, top first. |
| CGET0/1/N.X | Capture C at the specified depth and push its value on X. C is unchanged. |
| CGETR.X d,n | Capture/push C[d], C[d+1], …, C[d+n-1], in that order. |
| CSET0/N.X | Pop X0 and replace the selected scalar C cell, including its verified kind. |
| CPOP | Pop one scalar C cell. |

C depths count physical frame cells, including cells occupied by blocks; scalar operations may only access actual scalar cells, never block bytes or the continuation. Range operations validate every cell actually accessed. Zero-count transfers/ranges access no cells. Copies preserve the value observed at that instruction, not a deferred reference to a mutable home.

### Integer computation

The selected stack supplies the left operand and the other stack supplies the right operand. Binary arithmetic consumes both and pushes one integer result on X. Thus X depth is unchanged and Y depth decreases by one.

- ADD, SUB, MUL and NEG wrap modulo 2^64. AND/OR/XOR/NOT operate on all 64 bits.
- DIVU/REMU use unsigned division. DIVS/REMS use signed division truncated toward zero; signed remainder follows the dividend. A zero right operand aborts with reason 1. INT64_MIN divided by -1 produces INT64_MIN bits, with remainder zero.
- SHL/SHR shift by the unsigned Y0 count, producing zero for counts at least 64. SAR sign-fills, including all sign bits for counts at least 64.
- POW uses an unsigned exponent Y0 and modular integer multiplication; exponent zero produces 1, including 0^0. POWS first rejects a negative signed Y0 with reason 4, then uses the same power computation.
- EQ/NE compare integer bits, or address identity when both kinds are address. LT/LE are signed integer comparisons; LTU/LEU are unsigned. All comparisons produce canonical integer 0 or 1. Mixed kinds are not implicitly converted.
- LNOT preserves the existing boolean-inversion operation `x XOR 1`; it is not a new arbitrary-integer zero test. On canonical booleans it complements the truth value.
- ZX8/16/32 clear bits above the selected width. SX32 sign-extends the low 32 bits. These are unary X0 replacements.
- CHKU8/16/32 require the unsigned value to fit that width. CHKI32 requires the signed value to fit i32. CHKNN requires bit 63 clear. A failed check aborts with reason 3; success leaves X0 unchanged.

Immediate arithmetic computes `X0 op sign_extend(i8)`, without touching Y. C-operand arithmetic computes `X0 op C[depth]`, capturing that integer value and leaving C and Y unchanged. No normalization is implicit in either form.

### Floating-point computation and conversion

- FADD/FSUB/FMUL/FDIV read binary64 X0 and Y0 and return binary64 on X. Floating division by zero follows IEEE-754; it is not integer abort reason 1.
- FLT/FLE/FEQ compare X0 against Y0 and return integer 0 or 1 on X. All three comparisons are false for NaN operands. No float NE/GT/GE core family is needed.
- FNEG toggles the sign bit on X0 without changing the other payload bits.
- I2FS/I2FU convert signed/unsigned integer X0 to binary64, round-to-nearest ties-to-even.
- F2IS accepts finite X0 in [-2^63, 2^63); F2IU accepts finite X0 in [0, 2^64). They truncate toward zero and return integer bits on X. Outside the specified input interval, including NaN and infinities, abort reason is 3. This preserves the existing interval check before conversion.
- There is no implicit boxing, tagging, float normalization or reinterpret cast. `F2BITS.X` explicitly replaces float-kind X0 with integer-kind X0; `BITS2F.X` performs the inverse. Both preserve all 64 bits, including negative zero and signalling/quiet NaN payloads, without arithmetic, allocation, traps, safepoints or changes to Y/C/live prefixes. Empty or incorrectly typed selected operands reject. Existing memory load-kind annotations and ABI kinds also supply floating literals/values.

These rules retain the existing typed numeric policy while changing operand orientation and providing missing mirrored forms. They do not adopt a new floating environment or error ABI.

## 5. Control flow

- JMP/JMP32 transfer unconditionally within the current function. They touch no stack.
- JZ.X/JNZ.X consume one integer on X and test zero/nonzero. No implicit boolean normalization or new dynamic type check is performed.
- BEQ/BNE/BLT/BLE/BLTU/BLEU.X consume X0 and Y0, compare selected-first using the matching scalar relation, and branch if true. EQ/NE address-identity permission matches scalar EQ/NE.
- FBLT/FBLE/FBEQ.X do the same with binary64 operands and the corresponding IEEE comparison. Neither stack receives a comparison result.
- Extended BxxI.X consumes X0 and compares it against the sign-extended i8 constant, interpreted signed or unsigned as named. BGTI/BGEI/BGTUI/BGEUI explicitly mean `X0 >/>= constant`; these directions remain useful because the constant is not on an operand stack.
- SWITCH.X consumes an integer selector. If its unsigned value is below count, take that indexed displacement; otherwise fall through to the end of the table. Zero count consumes the selector and falls through.
- Every conditional branch consumes its declared operands on both outcomes. Joins require identical verified operand kinds and C layouts.
- ABORT reason stops execution with the original PC and nonzero reason. It does not unwind or roll back effects. Existing reason codes and host status/error reporting are retained.

For `a > b`, evaluate a into the opposite stack, then b into the destination and emit LT.dst. This reverses operand placement, not source evaluation order. Float greater-than uses FLT in the same way, never logical negation of FLE. Negated float conditions may swap control-flow successors so that NaN behavior remains exact.

## 6. Memory and frame storage

X always denotes the selected bank; Y its opposite. C is unchanged except for explicit frame allocation/free.

| Family | Contract |
| --- | --- |
| CALLOC n | Reserve ceil(n/8) C cells for a zero-initialized block of n requested bytes. Zero is a no-op. |
| CFREE n | Release the complete top byte block with exactly that requested byte count. Zero is a no-op. |
| FLD*.X d | Read at C end-byte-pointer minus d; push loaded value on X. |
| FST*.X d | Pop X0 and store at C end-byte-pointer minus d. |
| FADDR.X d | Push the address at C end-byte-pointer minus d on X. |
| GLD*.X d | Read image-base plus d; push on X. |
| GST*.X d | Pop X0 and write image-base plus d. |
| GADDR.X d | Push image-base plus d on X. |
| LD*.X d | Replace address X0 with the value loaded at X0+d. |
| ST*.X d | Store Y0 at address X0+d; pop both. |
| LDX*.X | Load from base X0 + index Y0 × load width; pop both, push result on X. |
| IDX.X size | Replace address X0 with X0 + Y0 × size and consume integer Y0. |
| MEMCPY.X n | Copy n bytes from address Y0 to address X0; consume both. Overlap is safe. |

Loads/stores are unaligned, exact-width, little-endian. Width suffixes are 8/16/32/64 bits; 32S loads sign-extend and other narrow loads zero-extend. Stores truncate low bits. Narrow stores require integers; 64-bit stores preserve integer, address or float bits under the existing kind contract. Loads default to integer; existing 64-bit load annotations may declare address or float.

Frame accesses must lie inside one live block's requested bytes, not padding, scalar cells or the continuation. Scalar C operations cannot split blocks. Image loads/addresses stay within the image and direct image stores within the writable prefix, verified even in unreachable code. Pointer arithmetic remains modular 64-bit arithmetic. Pointer loads/stores and copies retain the existing producer/host responsibility for valid addresses, lifetimes and bounds; this ISA is not a new sandbox. A zero-byte copy performs no dereference.

Frame storage with escaped addresses does not move merely because an activation is virtualized. Return/tail-call capture must precede any overwrite of values needed for transport. No GC or allocation policy beyond existing typed C-stack allocation is introduced here.

## 7. Calls, returns and host boundary

### Vectors and private regions

An argument vector `[arg0, …, arg(n-1)]` occupies the top n cells on the selected stack, with arg0 deepest and arg(n-1) at the top. CALL gathers top first, so the callee receives arg0 at C0, arg1 at C1, etc. A callee begins with empty private A/B regions and its arguments in C above its inaccessible continuation. Both caller operand prefixes remain protected.

A result vector `[result0, …, result(r-1)]` has the same deepest-to-top order on the RET-selected source. It is appended in that order to the continuation's destination stack. The last result is therefore on top after return. Function signatures describe vector counts/kinds and hidden-result bytes, not an A/B orientation.

### Direct calls and returns

`CALL.X target,n`:

1. Verify n and the ordered argument kinds against the target function.
2. Gather the top n values from X, preserving all other caller operands.
3. Establish the explicit continuation with return PC, activation coordinates and result destination X.
4. Expose the argument vector in C and transfer to the callee entry.
5. On return, append its result vector to caller X. Caller Y is unchanged.

`RET.X k,r`:

1. X contains exactly r private results of the declared kinds/order; the opposite private operand region is empty.
2. k matches the complete private C frame, including allocated block cells but not the continuation. r matches the function signature.
3. Capture the result vector as necessary before removing/reusing its frame homes.
4. Remove the frame and transport the vector from X to the destination in the continuation.
5. Restore the required caller coordinates and continue explicitly.

CALL's selected stack and RET's selected stack are independent. All four source/destination combinations are valid. Different return paths of a function may use different selected result sources if each meets the signature and frame contract. The callee does not inherit a bank mode from the caller and does not need two compiled bodies.

`TCALL.X target,k,n` gathers n arguments from X and replaces the complete k-cell frame. Its private selected region must contain exactly those arguments; the other private region must be empty. The callee result signature, including the applicable hidden-result ABI contract, must match the current function's return contract. Preserve the existing continuation and its destination; X chooses argument source, not a new result destination.

These are semantic obligations. Continue using explicit ABC transport and control transfer, not recursive host execution.

The subsequently approved private native binding retains the physical continuation cell and frame-storage layout, but normalizes C to that cell before a native return transfer. The caller restores its C coordinate from the cell, independently of argument-count changes in a tail chain. Every single-result native return supplies r0; general multi-result vectors remain in the RET-selected bank, with r2 identifying that source during transfer and r1 carrying the continuation. These registers are not permanently reserved during ordinary execution. Host delivery remains the existing embedding boundary. This does not adopt the archived experimental return-slot layouts. Implementation coverage and remaining integration are tracked separately in `REFACTOR.md`.

### Indirect calls

`CALLI.X n` takes n arguments from X and one code address from Y. The callable convention includes the environment as argument zero, counted in n. The target cell is separate from the argument vector. CALLI consumes the target, gathers the arguments into C and records result destination X. Other caller prefixes are preserved.

`TCALLI.X k,n` uses the same operand orientation but replaces the complete frame and preserves the existing continuation. Before consuming its target, the opposite private region contains exactly that target and the selected private region exactly n arguments.

Each indirect site retains its immutable full signature record: counts, argument/result kinds and hidden-result byte contract. The encoded n must match the signature. The target must be an exact callable function entry in the same module with the complete matching ABI; no null, interior, other-module or HALT target is accepted. Invalid identity reports ABC_INVALID; ABI mismatch reports ABC_ARGUMENTS. Checking a code target does not validate its environment pointer. Code addresses remain opaque identities, not host C function pointers.

Observation is VM-local, shared by original PC across interpreter/native/inlined realizations:

- unseen: validate; success records the target; failure leaves the site unseen;
- monomorphic: the actual target must match the recorded identity before using that proof;
- mismatch: enter final generic before validating the new target, including failing validation;
- final generic: validate each dispatch without restarting the history.

No phase is encoded by changing CALLI's opcode or operands. Native emission may eliminate an independently proven dispatch after ABI validation; an observed target alone is not proof. Site-record representation is an execution binding, not a serialized instruction field or permission to redesign region ownership in this migration. The inspected minimum binding is recorded in [the quickening audit](../research/experiments/ab-symmetry/quickening-audit.md): one observation word per VM/module site, shared checked resolution and no phase-specific opcode or native patch registry. Public code-address relocations use the same exact module-entry identity in every mode; private native entry pointers are resolved control-transfer destinations, not alternative public callable representations.

### Foreign and host calls

`FCALL.X extern` consumes the declared argument vector from X and appends the declared result, if any, to X. The opposite caller prefix is preserved. The existing foreign ABI limits remain: at most six integer/address arguments, four float arguments and zero or one result. Extern binding, effects, synchronization, re-entry policy and staging prohibition remain unchanged. The bridge reads the selected bank directly, not a bytecode shim through A.

The host API still passes/receives ordered raw-cell vectors and signatures, without an operand-bank parameter. Host entry establishes the same callee-private regions and argument C layout. A RET from either stack can complete the host continuation. A fixed internal host-delivery bank is an embedding choice, not an ISA privilege.

`HALT.X` completes a host-entry-only function using its r declared results on X, with the opposite private region empty and C empty. Functions containing HALT remain non-callable from bytecode. Result publication occurs only on successful completion; failure does not modify the host's output cells. Status/error structures, image persistence and resource-limit behavior are unchanged.

## 8. Module revision and capability profiles

Retain the 16-byte header shape:

| Offset | Field | Revision-6 value |
| --- | --- | --- |
| 0 | four-byte magic | `ABC2` |
| 4 | u16 format/ISA revision | 6 |
| 6 | u8 pointer size | 8 |
| 7 | u8 capability profile | 1, 2, 3 or 4 |
| 8 | u32 section count | determined by profile |
| 12 | u32 reserved | 0 |

Revision 6 is chosen because historical revisions 1–5 already have meanings. Profile and revision are no longer equated in loaders or producers. There is no new profile 6.

Retain the existing profile-specific section payload structures, except that code bytes use this ISA and code offsets/relocations must be regenerated:

| Profile | Capabilities | Required section tags |
| --- | --- | --- |
| 1 | Integer cells, C scalar bindings, direct calls and integer control flow | 1 functions, 2 code, 3 exports |
| 2 | Profile 1 plus address/float kinds, frame/image/pointer memory and float operations | 1–6, adding writable image, rodata and load-kind annotations |
| 3 | Profile 2 plus indirect callable views | 1–8, adding indirect-site signatures and code-address relocations |
| 4 | Profile 3 plus named typed foreign calls | 1–9, adding extern signatures |

The six neutral instructions are not automatically legal in every profile: CALLOC/CFREE require profile 2 or higher. Float/memory operations require profile 2, CALLI/TCALLI profile 3, FCALL profile 4. The C-operand arithmetic and immediate-branch EXT forms are legal in profile 1 and higher; F2BITS/BITS2F require profile 2 and higher. Profile 1 retains integer-only function records; profiles 2–4 retain their explicit kind vectors. Existing section framing, loader size limits, export names, hidden-result storage responsibilities and relocation payload structures are otherwise unchanged.

All function entries, branch targets, site signatures and load-kind annotations refer to the new instruction starts. Indirect signatures cover every CALLI/TCALLI, including unreachable ones. Code-address relocations continue to refer to functions rather than serialized process addresses. They do not become native entry pointers in a portable module.

The migrated runtime accepts revision 6 with profiles 1–4. Historical revision-1–5 modules are diagnosed as unsupported revision through the ordinary version check, not translated or reinterpreted. Historical archives remain old-format evidence. A future dynamic capability revision must define its selectors and contracts explicitly rather than reusing the old profile-5 interpretation.

### Assembly surface

Selected operations require an explicit `.A` or `.B`; neutral operations have no bank suffix. Canonical directional transfers are COPY.A (A to B), COPY.B (B to A), MOVE.A and MOVE.B. Generated underscore spellings may represent the same exact instruction; no omitted-bank default chooses A.

PUSH.X still chooses PUSH8/32/64 according to the exact integer bits. CGET.X/CSET.X choose their existing short or depth forms. ADDC.X and BxxI.X spell their extended operations directly; programmers do not write a separate EXT instruction. Calls name functions, branches name labels and indirect calls name an immutable signature as before. The new assembler produces revision 6; it does not guess or implement a historical dialect. No separate mandatory assembly-version directive is introduced.

## 9. Binding and migration rules

The manifest must describe operation identity, selected-stack role, operand layout, length, profile and effect class. It must not use the serialized byte as the only semantic operation identity, nor infer arbitrary instruction families from old contiguous opcode ranges. Decoding yields the declared operation and selected bank for both core and EXT forms; this is instruction decoding, not a residual IR or compatibility adapter.

Authoritative semantic operations bind X and Y directly. Interpreter generation mirrors `(a,b)` and `h[i] ↔ h[3-i]` for operand-bank registers, keeping C's role fixed. Symbolic execution uses the same logical operand order. Native emission selects register-addressed stencils directly; the old B-only reverse-operation path is deleted. Optimizer, ABC/C emission and frontend lowering consume the same contracts.

The compiler rule is `compile(left,dst); compile(right,other(dst)); OP.dst`, preserving live prefixes and source evaluation order. No new Ershov scheduling pass or evaluation reordering is required to implement the ISA. Capture, spills and call/edge transport remain legitimate; moves solely compensating for the old A-left convention do not.

This design does not allocate quickening opcodes, implement dynamic execution, change GC, adopt the experimental return layout, or implement caller-owned region accounting. The minimal site-state binding needed to remove instruction rewriting must preserve current validation and observation contracts without growing into a second compiler.

## 10. Decisive validation

The design allocation must cover each existing public typed family exactly once, after pairing directional forms, with six neutral instructions, 124 direct selected families and fourteen extended selected families. All 256 core bytes are uniquely accounted for. This is a design-table check, not evidence of runtime correctness.

At implementation boundaries, use the existing focused contract validators for:

- mirrored noncommutative arithmetic, divisor/exponent order and representative floating comparisons;
- C transfers, immutable captures and full-bank/spill transitions;
- all four CALL/RET bank combinations, ordered vectors and preserved caller prefixes;
- tail continuation preservation, indirect target/ABI validation and selected-bank foreign transport;
- branches to complete instruction boundaries, regenerated offsets and representative traps/limits.

Run the full active suite at integration and the fixed baseline/final performance comparison. In particular, measure the extra EXT decoding for the fourteen operand forms and two bitcasts and the removal of call quickening; neither is assumed free. Native steady-state operation selection should not require an extra runtime layer for EXT, but code size and timing must be measured rather than inferred from the source design.
