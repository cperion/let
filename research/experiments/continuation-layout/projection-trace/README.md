# Trace the interpreter projection, not a replacement transport system

## Result

The interpreter captures argument values before reusing their old C frame.
The symbolic transfer path instead carries deferred references to those C homes.
Existing native home conformance subsequently writes a destination over an unread
source. This reproduces in the **original archived engine**, with no reserved
slots, no changed continuation ABI, and no new materialization mechanism.

This isolates the source-value/capture problem. It does not establish that deferred
home references are always invalid: they are safe while the referenced contents
remain unchanged. The problem is treating their transport like stable register
renaming without preserving the old contents before replacement.

No production source was edited. The diagnostic copy is
`/tmp/abc-projection-trace.wG6CZY`, based on the pre-teardown archive. The prior
reserved-slot and return experiments were not applied to this copy.

## Actual trace

The module is `../reserved-slots/tail-A.abcasm`. The relevant instructions are:

```text
0x2f3  CGET0.A
0x2f4  CGET1.A
0x2f5  CGETN.A 2
0x2f7  PUSH8.A 123
0x2f9  TCALL leafwide 3 4
0x300  CALLOC 8
...
0x323  JMP 0x326
```

The interpreter begins this diagnostic at `leaf` with its three arguments in C
memory, matching the native generic entry's incoming homes. Its arguments are
`MAIN_REF`, `MIDDLE_REF`, and 7. `trace_interpreter.c` executes the actual generated
handlers, independently from that entry for each of 16 stops. It replaces only
the stop instruction in a private execution copy with HALT, so HALT publishes a
snapshot without executing the replaced instruction. These are logical values
following cache publication, not a trace of the pre-HALT physical register map.

`interpreter-trace.txt` shows:

| Point | A, bottom first | C frame, bottom first, omitting return |
| --- | --- | --- |
| initial | empty | `7, MIDDLE_REF, MAIN_REF` |
| after three CGETs | `MAIN_REF, MIDDLE_REF, 7` | unchanged |
| before TCALL | `MAIN_REF, MIDDLE_REF, 7, 123` | unchanged |
| after TCALL | empty | `123, 7, MIDDLE_REF, MAIN_REF` |
| after CALLOC | empty | same arguments, then a zeroed block cell |

The generated interpreter explains why this is safe:

- `gen/banked.lua`: `B:push` captures its input before cache spill/shift/write.
- `gen/cache.lua`: transfer inputs are captured before consuming or spilling.
- Generic TCALL publishes A, then replaces C from those already captured A
  values. The small-count specialized form similarly captures arguments before
  dropping the old C cells.

The actual symbolic dispatcher trace (`symbolic-trace.txt`) shows instead:

```text
A after CGETs:
    HOME(C,-1) → A0
    HOME(C,-2) → A1
    HOME(C,-3) → A2

C after TCALL, source → destination:
    constant 123 → C[-3]
    HOME(C,-3)   → C[-2]
    HOME(C,-2)   → C[-1]
    HOME(C,-1)   → C[ 0]
```

These deferred sources remain through CALLOC and the jump. In the shared symbolic
implementation, `abc_symbolic_machine_cget` copies a value descriptor and changes
its destination. It does not capture a home read through a native cache operation.
`abc_symbolic_machine_tail` snapshots those descriptors, drops the old logical C
region and assigns new destinations. That snapshots references, not the memory
contents they refer to.

Native `conform_context` then walks C in ascending index order. Its first store
writes 123 to C[-3]. The next pending read of C[-3] consequently gets 123 instead
of 7, and the corruption propagates into the pointer arguments. A copied
register value or constant can safely participate in renaming; a reference to
mutable storage cannot be assumed equivalent.

## Countercheck in the original engine

The only execution-affecting diagnostic hook asks the existing `conform_generic`
to run at the edge to `0x326` when there are no virtual continuations:

```text
ABC_FORCE_HOME_PC=0x326
```

It does not introduce a general-entry adapter, change return layout, or move
frame blocks. This tests whether the already-existing conformance operation is
valid for the symbolic state reaching that location.

For both A and B destination fixtures:

| Configuration | Interpreter | Eager | Lazy |
| --- | --- | --- | --- |
| original behavior, no forcing | 101 | 101 | 101 |
| existing conformance forced at the edge | 101 | ABORT 12 | ABORT 12 |

All four native failures are at byte `0x33d`, the middle-pointer equality check.
There are six successful unforced controls, two successful interpreted forced
controls, and four failing native forced cases. Exact outputs/diagnostics are
retained in `control-*` and `forced-*` files. These runs used stack capacity 1024.
The unforced full native run also returns 101 with symbolic tracing enabled.

This is an induced conformance failure, not a claim that this particular module
fails under ordinary original execution. It independently reproduces the same
invalid transport that the earlier materialization experiment exposed.

## Focused next direction

Restore the interpreter's capture/consume/spill/push obligations in the symbolic
cache projection. In particular, a read from memory needs a stable captured
value before its source storage can be reused. Already-captured register values
and constants may still rename without extra work.

Audit the whole family of transfers using the same rule (`CGET`, memory-backed
DUP/MOVE/COPY, frame replacement and spills), rather than adding a special repair
for this TCALL fixture. Do not implement a new copy scheduler, exchange subsystem,
allocator or return ABI on the basis of this trace. A concrete primitive-level
projection design and validation are still required before production changes.

## Reproduction

In a disposable copy of the pre-teardown snapshot with vendor sources, build the
archived runtime/tool wrapper as described by the parent experiment. Copy
`../reserved-slots/tail-A.abcasm` and `tail-B.abcasm` into the copy. Apply
`diagnostic.patch`, copy `projection_trace.inc` to `src/`, and copy
`trace_interpreter.c` into the copy's root.

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' build/abc-runtime
build/abc asm tail-A.abcasm -o tail-A.abc
build/abc asm tail-B.abcasm -o tail-B.abc
/tmp/clang20 -std=c11 -O2 -Wall -Wextra -Werror -Iinclude -Isrc -Ibuild \
  trace_interpreter.c build/libabc.a -lm -lpthread -o trace-interpreter
./trace-interpreter tail-A.abc
ABC_PROJECTION_TRACE=1 build/abc-runtime run tail-A.abc main --lazy --stack=1024
# Expected failure: original conformance, no new return/frame mechanism.
ABC_FORCE_HOME_PC=0x326 build/abc-runtime run tail-A.abc main --lazy --stack=1024
```

The fixed PCs are deliberately tied to this verified fixture. No benchmark,
complete architecture validation or production fix is claimed.
