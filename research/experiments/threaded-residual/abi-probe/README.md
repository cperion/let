# Threaded residual execution: seven-register ABI probe

Status: **ABI feasibility gate passes; production integration is not implemented**.

The user confirmed seven threaded value registers. The carried arguments are:

```
ip, asp, bsp, csp, r0, r1, r2, r3, r4, r5, r6
```

This is eleven arguments, like the existing interpreter ABI. Native execution
keeps eight value registers and three pointers. Integration will use one allocator
with a binding-specific available-register count, not two allocators.

## Test and measured result

`probe.c` is a standalone dispatch probe, not an ABC execution engine. It emits
8-byte handler pointers and bound operand words with no runtime opcode/register
number decoding. The 96-byte loop tape exercises constants, HOME loads (including
a negative byte offset), register addition, conditional transfer and HOME store.
Additional cases cover immediate unsigned wraparound and forward jumps skipping
records. The terminal handler exposes all seven value registers and three stack
pointers for independent checks; surrounding data has preservation checks.

Clang 20 builds with warnings as errors. Eight correctness cases and seven timed
calls pass. Each timed call executes ten million iterations under a **128 KiB host
stack limit**. Every timed call checks all final value registers, pointers and the
store result. There are 2N+5 executed records per loop invocation.

Observed on CPU 0: **0.9756 ns per executed record**, median across seven calls
(range 0.8939–1.0731). This is a tiny hot-loop feasibility measurement, **not a
comparison against native or ABC interpretation, nor a backend speedup claim**.
Compilation, tape preparation and handler-library footprint are not included.

`dispatch-audit.txt` records all eight dispatching handlers. They contain indirect
jumps and **no calls, pushes, pops, or references to rsp/rbp**. Thus no handler
stack spills are present in these tested dispatch paths. The host-entry adapter
and terminal return are outside this claim. Constant and HOME-load handlers still
have some scratch-register moves; absence of spills does not mean optimal code.

Example actual `add_r2_r5` code:

```
add %r9, %rdx
mov 8(%r12), %rax
add $8, %r12
jmp *%rax
```

## Reproduction

From the repository root, choose a fresh output directory:

```
out=$(mktemp -d /tmp/abc-threaded-seven.XXXXXX)
/tmp/clang20 -O3 -march=native -std=c11 -Wall -Wextra -Wpedantic -Werror \
  research/experiments/threaded-residual/abi-probe/probe.c -o "$out/probe"
objdump -d "$out/probe" > "$out/probe.dis"
(ulimit -s 128; taskset -c 0 "$out/probe" 10000000) > "$out/results.txt"
```

Recorded binary: `/tmp/abc-threaded-abi/probe`. Compiler, host, source checksum,
disassembly and raw timing output are retained in this directory.

## Earlier attempt and next integration step

`eight-register-attempt/` preserves the initial twelve-argument source and compiler
failure. Its blocked status is historical, superseded by the approved seven-value
ABI. Eight values plus cursor and three pointers failed register allocation in
Clang 20; no timings were produced for that attempt.

Next: extract shared execution forms and native emission from `src/residualize.c`
while preserving native behavior, then implement threaded emission using the same
symbolic placement machinery with seven available registers. The approved native
threshold remains 16; tooling remains 8. Caller-owned-region budgeting, managed
execution, lazy threading and new fusion machinery are outside this integration.
Production files have not been edited by this probe.
