# Why the scalar interpreter still does too much work

Audit of the shared-control-flow build measured in `shared-scalar-pairs.txt`:
Clang 20.1.2, banked handlers compiled at `-O2`, x86-64. This is generated-code
inspection and native-stencil accounting, **not a hardware-counter profile**.
No runtime code was changed for this audit.

## Finding: sharing the computation did not make its execution economical

The definition is shared, but the concrete binding still mixes three different
things in each large handler:

1. immutable instruction/descriptor interpretation;
2. runtime representation checks and the actual value operation;
3. preparation for collection, allocation failure and other cold outcomes.

The native binding stages much of the first category away, but copies a large
collection fragment at every scalar boundary. These are distinct implementation
costs; neither follows merely from having dynamic values.

## One actual immediate-u32 addition

Inspect:

```sh
objdump -d --disassemble=h_a2b0c2_EXT_DADD build/banked_6.o
objdump -d --disassemble=h_a2b0c2_EXT build/banked_6.o
objdump -d --disassemble=h_a1b1c2_ADD_A build/banked_2.o
```

For two immediate u32 operands and no collection request, the selected `DADD`
path executes **68 machine instructions**, plus **4** in the EXT dispatcher.
The arithmetic and re-tagging themselves are only three:

```asm
add    %r11d,%esi
movabs $0xffff040000000000,%rdi
or     %rsi,%rdi
```

The path accounting is:

| Portion | Instructions |
|---|---:|
| Entry, frame, VM/error context and pending-request test | 18 |
| Tag projection, promotion, type-arm dispatch and IP advance | 29 |
| Rechecking representation, addition, re-tagging, exit jump | 8 |
| Next-op dispatch, ABI restoration/clearing and frame teardown | 13 |
| EXT-selector dispatch before entry | 4 |

For audit reproducibility, the DADD object-code ranges followed were
`7c320..7c35f`, `7c408..7c43a`, `7c61b..7c631`, `7c648..7c669`,
`7c70c..7c70f`, `7c715..7c718`, `7c71e..7c72e`, and `7ca21..7ca4a`.
Wrapped instruction bytes in objdump output are not extra instructions.

The register-input typed `ADD.A` handler is 10 instructions, including its
next-op dispatch and dead-argument clearing, with no stack frame. Its inputs
are on A/B rather than both on A, so this is not a whole-bytecode-sequence or
cycle-ratio comparison: typed code also needs operand transport.

### Cold preparation happens on the hot path

The DADD handler starts with `push %rbp; sub $0x40,%rsp`. Before checking the
request flag it loads the error pointer, computes the bytecode PC and saves
both to the C stack. It restores the frame even on the immediate-u32 path.
`ANY_BOX` similarly takes a 48-byte frame in this cache state.

The source is `gen/scalar_banked.lua`: `emit_handlers` eagerly declares `e` and
`pc`, although this scalar binding uses them for allocation failure; `finish`
contains the allocating alternative in the same generated function. Collection
and heap-object inspection are also reachable inside that function. The emitted
code consequently pays frame/context overhead without taking those edges.
**Neither collection nor allocation nor `gc_heap_contains` is called on the
traced immediate-u32 path.** Their surrounding preparation/layout still costs.

Moving error-context construction to the failure edge is an immediate cleanup.
Making the whole ordinary path frameless additionally requires arranging the
effectful alternatives so they do not dictate its register/frame requirements;
merely putting everything in an inline function did not achieve that.

### Checks discard useful facts

The binding does:

```text
abc_repr_tag(x), abc_repr_tag(y)
→ abc_scalar_promote(tag_x, tag_y)
→ switch(result_tag)
→ abc_repr_bits(x, result_tag), abc_repr_bits(y, result_tag)
```

`abc_repr_tag` established immediate-versus-object representation, but returns
only the semantic tag. After those paths merge, `abc_repr_bits` tests the
immediate prefix again. Both repeats are visible in the chosen u32 arm.

A tag alone is insufficient to remove them: nominal u32 can contain a preserved
non-normalized payload and can be boxed. The missing information is the
**checked representation**, not a license to assume normalization from a tag.
Checks should refine the values used by the subsequent payload access rather
than erase the proof into a class number and ask another generic decoder.

### Immutable descriptors are interpreted again on every box

`gen/scalar_semantics.lua`'s `layout` reads the descriptor index, follows the
module descriptor and projects `abc_any_descriptor_layout`. The concrete
binding runs that code for every `ANY_BOX`, `ANY_IS` and `ANY_CAST`; the native
binding runs it during compilation.

For `ANY_BOX U`, assembly still fetches the descriptor, tests its form, reads
its primitive kind and selects a boxing arm every time. The module descriptor
and instruction operand are immutable and already verified. This is instruction
preparation work being performed repeatedly during interpretation.

Any staging of this information should belong to existing module/image
preparation, not an observation-based quickening system or runtime `abc-opt`.
A bit-preserving payload-fit check remains necessary unless separately proved.

### Some trivial typed primitives still cross a C call boundary

The signed-i32 arm of this DADD function contains a call relocation to
`abc_i32_from_u64` merely to normalize/sign-extend the result. That routine is
out-of-line in `src/semantics.c`; the stencil generator emits an always-inline
version of the same operation. This older primitive-binding inconsistency is
another avoidable ABI boundary, not a necessary dynamic-language effect. It is
**not on the unsigned path counted above** and cannot explain that path's cost.

## Native code growth: mostly repeated collection code

`M.emit` in `gen/scalar_semantics.lua` calls `safepoint` for every scalar
instruction. `native_emit_safepoint` copies the complete GC_POLL stencil.
The extracted stencil is **227 bytes**: 20 for the flag load/test/branch and
207 for the cold path. Its cold path preserves the register bank and calls the
collector with site-specific physical home extents.

I dumped the final runner's eager and warmed lazy bodies for all seven workloads
and matched the **entire stencil**, ignoring only its six relocation fields:

| Workload | Eager body bytes | Matched poll sites | Poll bytes | Other bytes |
|---|---:|---:|---:|---:|
| u32-known | 9,653 | 40 | 9,080 | 573 |
| u32-carried | 14,424 | 57 | 12,939 | 1,485 |
| u32-checked | 8,369 | 33 | 7,491 | 878 |
| u32-unproven | 14,398 | 57 | 12,939 | 1,459 |
| u32-reload | 20,327 | 63 | 14,301 | 6,026 |
| width-alternate | 37,727 | 116 | 26,332 | 11,395 |
| f64-carried | 4,195 | 12 | 2,724 | 1,471 |

Thus **94% of u32-known's emitted body consists of collection-poll stencils**.
8,280 bytes are their cold portions alone. These are counts across emitted
versions/paths, **not 40 polls executed on each loop iteration**. The matching
lazy counts are 38, 29, 32, 29, 31, 63 and 10 respectively.

This quantitatively identifies the code-size problem. It does **not** establish
that the checked-lazy timing regression is exclusively due to these copies.

There is also duplicate preservation within that fragment: it stores the eight
register values in the published root array, but `NEXT` still forwards the
original register variables. The generated code separately keeps those values
alive across the C collector call through more register moves/stack saves,
rather than restoring from the published snapshot. Under the existing nonmoving
collector contract, one saved bank should serve both purposes; that change would
need ABI/root validation, not a new representation or allocator.

The current profile requires pending requests to be honored at eligible scalar
boundaries. Deleting checks to improve a benchmark would change that behavior.
The implementation should separate the small check from collection machinery
and avoid duplicating the latter. If eligibility itself is reconsidered under
“allocation is an effect, dynamic is not,” that is an explicit policy decision,
not a silent optimization.

## Benchmark work that is not inherent to the algorithm

The carried integer kernel executes four `ANY_BOX` instructions and five
arithmetic EXT instructions per iteration. Three boxes construct the constants
7, 5 and 65535 anew. ABC already has literal arithmetic forms, but this test
intentionally uses unfused verified ABC to expose runtime type costs. The float
kernel similarly reconstructs 0.5 through typed division on every iteration.

These are real executed instructions, not necessary mathematical work. Add
literal/prepared-constant comparisons if investigating their cost; do not replace
the original workload and present that change as a runtime speedup. They also
do not excuse the unnecessarily expensive ordinary DADD path above.

## Design conclusion

The problem is not primarily the three instructions for arithmetic/re-tagging.
We centralized semantics but failed to sufficiently separate static instruction
facts, checked representation facts and effect preparation in the concrete
execution shape.

The intended shape should be:

```text
prepared instruction
→ check operand representations once, retaining what was established
→ ordinary typed operation and required result encoding
→ next instruction
```

Collection, allocation and diagnostics should be separate edges with context
prepared on demand. Native collection bodies should not be copied wholesale at
every point. This calls for removing work and preserving proofs—not another
scalar engine, allocator, value IR or specialization subsystem.
