# Threaded residual execution: initial ABI feasibility gate

Status: **blocked at compiler register allocation; no runtime integration begun**.

The approved first experiment attempts eight live value registers plus the thread
cursor and three stack pointers: twelve carried arguments, with Clang
`preserve_none` handlers and `musttail` indirect dispatch. Each tape record has an
8-byte handler pointer followed by its exact bound operands. No opcode or register
number decoding is involved.

`probe.c` contains constants, immediate/register addition, HOME loads/stores,
conditional/unconditional transfers and a terminal handler. The intended tests
preserve all eight value arguments and all three pointers, exercise negative byte
offsets and unsigned wraparound, and run a long loop under a small host stack.
**None of these execution tests ran.**

## Observed result

With the current Clang 20 wrapper, compilation exits 1 and reports:

```
ran out of registers during register allocation in function 'const_r2'
```

The same diagnostic occurs for all eight dispatching handlers. `finish`, which
returns rather than dispatches, does not receive that diagnostic. See `build.log`
and `compiler.txt`. This establishes a failure of this proposed ABI with this
compiler, not a general impossibility for x86-64.

Reproduce from the repository root:

```
/tmp/clang20 -O3 -march=native -std=c11 -Wall -Wextra -Wpedantic -Werror \
  research/experiments/threaded-residual/abi-probe/probe.c \
  -o /tmp/abc-threaded-abi/probe
```

The existing ABC handler ABI carries eleven values: cursor + three pointers +
seven cached cells (`src/handler_abi.h`). Native stencil execution carries eleven:
three pointers + eight register cells. The proposed threaded ABI adds a twelfth.
A likely constraint is scratch-register availability for indirect tail transfer;
exact compiler lowering attribution has not been established.

## Decision required

Recommended next experiment: seven threaded value registers, keeping native at
eight. That restores eleven carried arguments and would require an explicit
available-register count in the **same** allocator, not another allocator or
placement reconstruction. It changes placement/spill behavior, so it needs design
approval before implementation. It has not been attempted here.

Alternatives include a different dispatch ABI/assembly implementation, or keeping
some state in memory. Neither is silently substituted for the approved probe.
Production files have not been edited by this experiment. All files in this
directory are experiment sources/evidence; there is no measured execution speed,
working threaded backend, or completed integration claim.
