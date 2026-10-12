# Investigation: interpreter calls and native body growth

Status: investigation only. No runtime/generator implementation or execution
policy was changed. Frozen baseline artifacts and comparison samples are intact.

## 1. Fibonacci executes the same bytecode work

`old-fib.dis` and `new-fib.dis` show identical function boundaries, branch targets,
argument/result counts and semantic instruction sequences. Both have 45 code
bytes. Differences are revision-6 selected spellings/encodings, not additional
CGETs, arithmetic, checks or calls. Fibonacci uses a core binary branch here, not
an EXT immediate branch. For fib(30), both algorithms perform 2,692,537 Fibonacci
activations (2,692,536 recursive direct calls), plus the main-to-fib tail transfer.

The old warm interpreter rewrites these direct calls to CALL_A_1 and returns to
RET_1_1. The current interpreter correctly has no such quickened bytecodes, and
uses count-dependent transport and outgoing cache-table selection.

### Handler evidence

Selected example, incoming cache state a1/b0/c3 (not a claim of measured frequency):

| Handler | Old bytes | New bytes |
| --- | ---: | ---: |
| CALL.A, one argument | 296 | 567 |
| RET.A, frame 1 / result 1 | 361 | 579 |

The four `*-a1b0c3.dis` files preserve machine code. In the current call handler,
argument count is loaded from the instruction and outgoing dispatch loads through
`abc_tables`; the old specialized handler directly addresses `T_a0b0c3`.
Capacity checks remain in both versions and must not be removed to regain speed.
The generic loop is not executed for arity one in this representative current
handler; Clang gives that case a short branch, but count selection still remains.

There is a **separate lost liveness optimization**: old `gen/banked.lua` calls
`B:forget_unused()`, assigning zero to dead operand/C ABI arguments before
statically known dispatches. Current `dispatch(state)` passes every h/c argument
unchanged. The cache state still proves those slots dead, but the C compiler must
preserve their incoming bits when they are forwarded through the handler ABI.
The displayed old call saves three bank values to its host stack; the new one
saves six ABI values, including rsi/rdx/rcx which are dead operand-bank slots for
this input state. This establishes extra preservation, not a cycle attribution.

### Controlled leaf probes

`probes.py` generates explicit old/new assembly for zero-, one- and two-argument
leaf calls and equivalent inline operations. Each repeats one million times;
every result is compared with 42 and aborts if incorrect. The same frozen/current
runners perform seven timed calls on CPU 0, with six rotated/interleaved rounds:
**72 processes / 504 timed calls**, all successful. These are investigation probes,
not replacements for the fixed baseline or an adopted operand-entry convention.

Median nanoseconds per loop iteration (batch medians):

| Arity | Old inline | New inline | Old call | New call |
| --- | ---: | ---: | ---: | ---: |
| 0 | 5.289 | 4.102 | 9.768 | 9.557 |
| 1 | 6.486 | 4.593 | 11.275 | 12.378 |
| 2 | 8.601 | 4.792 | 12.308 | 15.641 |

Paired difference-in-differences `(new call - new inline) - (old call - old inline)`:
**1.001 ns [0.560,1.289]**, **2.875 ns [2.443,3.155]**, and
**7.199 ns [6.844,7.426]**, respectively. Raw process results and CSV are retained.

This supports increased call-boundary cost despite improvements in the surrounding
loop. It does **not** isolate arity handling from dead-argument preservation,
cache occupancy, spills or code layout, and cannot assign the full Fibonacci 16%
regression to one cause. The probes are not Fibonacci's recursive cache history.
No hardware-counter profile was collected; perf/gdb executables are unavailable.

## 2. Memory native growth: exact body-byte decomposition

The original eager memory body grows **264 → 450 bytes (+186)**:

- Initial emitted prefix: **70 bytes in both**.
- An additional home-backed header/body/exit realization: **134 bytes**.
- Two existing register-resident exits grow **26 bytes each**: **52 bytes**.

The original lazy body grows **227 → 324 bytes (+97)**:

- Additional home-backed header and body: **31 + 40 = 71 bytes**.
- The one executed/compiled exit grows **26 bytes**.

These sums account for the entire measured body-size differences. Native binaries
and disassemblies are retained in the preceding `final-comparison` directory.

### Why the extra context appears

1. The old `native_emit_immediate` ignored its `folded` flag. For the first known
   decrement, it emitted `1000000; SUB 1` and returned a register descriptor.
2. The revision-6 callback correctly returns immediately when the shared semantics
   already folded the operation, retaining constant **999999** instead.
3. The existing `edge()` backedge rule handles a constant by **materializing it,
   saving it to its home, then replacing its descriptor with HOME**.
4. The first widened loop context is consequently home-backed. Executing its
   decrement produces a register-backed context, followed by the same two
   alternating register placements seen in the old steady loop.

Thus improved folding exposed an old coupling between forgetting a constant and
forcing memory placement. Reintroducing the old redundant arithmetic would hide,
not fix, that organizing problem.

### Independent control

The `memory-runtime-counter` probe first writes the count to a second writable
image cell and then loads it. Native compilation must treat that load as runtime;
source instruction/control order within the loop is unchanged. This removes the
known-first-decrement distinction without altering compiler code.

| Probe body | Old | New | Difference |
| --- | ---: | ---: | ---: |
| eager | 240 | 292 | **52 = 2 × 26** |
| lazy | 203 | 229 | **26** |

All four executions return 1,000,000. There is no extra home-backed context in the
new result; only the enlarged exits remain. Probe sources/modules, result logs
and disassemblies are retained here. This is stronger evidence for the specific
memory-workload mechanism, not an explanation of every loop/branch size change.

The return-size difference reflects the current explicit source/continuation
protocol: load/check host continuation, normalize the C coordinate for a native
return, publish the source selector, and handle host delivery separately. Those
correctness obligations must not be reverted merely to match old sizes.

### Measurement limit discovered

The runner's native byte metric is `abc_native_image.code_size`: the emitted
**body region**, not the entire executable mapping. Lazy stubs are allocated
separately from the high end of that mapping and are excluded, as are heap
metadata and unused mapping capacity. Old and new use this same metric. The
reported body growth is valid; it is not a complete native-memory comparison.

## Next design discussion, not implementation approval

Two bounded candidates deserve separate experiments:

1. Restore dead-slot liveness in generated handler argument binding, using the
   existing cache's proven occupancy. Preserve live prefixes, both banks and C;
   do not change the ABI, cache capacity, quickening policy or resource checks.
   Start with known outgoing states rather than adding costly dynamic clearing.
   Measure Fibonacci, leaf probes, memory/branch controls and handler bytes;
   rerun poisoned-dead-argument/cache and continuation contracts.
2. Separate backedge knowledge weakening from physical placement. Forget the same
   facts at the same boundaries but retain register placement when legal through
   the existing allocator; preserve actual captures, escaped storage, limits and
   version budgets. Audit descriptor canonicalization first: `value_equal` compares
   all fields, and merely changing a value's kind can retain stale payload fields.
   A one-line removal of the home store is not yet a reviewed design.

Investigate count-specialized transport only after the dead-slot effect is
isolated. Neither new opcodes, operand-entry functions, resurrected quickening,
new allocators nor changed native continuation layouts are proposed by this
investigation. Broader benchmark size/cycle attribution remains incomplete.

## Reproduction

`probes.py` expects historical assembler files extracted into
`/tmp/abc-r6-investigate/old-build/` from the frozen `build.tar.gz`: `abc`,
`abc-runtime`, `assembler.lua`, `opcodes.lua`, `int64.lua`, `tool_util.lua`.
Make that extracted `abc-runtime` executable. The source snapshots remain archived;
no old code is installed in the active runtime. Re-run in a new evidence directory
with the same relative placement, since raw files use exclusive creation.
