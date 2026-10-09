# Unfused native continuation lowering

Baseline: `b84c37c`. Reference sources are archived under
`research/archive/native-continuations-b84c37c/` and are not built.

## Change

Native direct calls publish the resume label, rebase the live frame, and emit
an ordinary direct jump. The resume point uses the same rebase primitives with
inverse displacements. Zero rebases emit nothing. Terminal returns publish
results, load the continuation through the existing C-home load stencil, and
transfer through that register, checking the host sentinel.

This removes fused CALL_JUMP, CALL_RESUME and RETURN_CONT stencils, their packed
frame immediates, and their dedicated placement routines. Frame transport stencils
fall through after NEXT removal; there is no intermediate runtime dispatch.
The result register remains intact while the dead r1 register carries the
continuation. Local absolute label references and local branches share fixup
handling, including lazy compilation.

The symbolic VM, register-bearing entry contexts, virtual calls, concrete
interpreter, and indirect/foreign/dynamic helper conventions are unchanged.
This change does not generalize the existing unary recursive argument fast path
or introduce a separate register-allocation pass.

## Validation

- Full `make validate` passed, including the 21,711 type-version executions.
- New `tools/validate_continuations.lua`: 234 differential executions across
  interpreted/eager/lazy modes, covering A/B result routing, live caller values,
  0/1/2/9 arguments, 0/1/2 results, mutual recursion with tail transfer, and
  stack exhaustion. The test is part of `make validate`.
- Full nine-trial engine benchmark passed every result comparison.

Build environment: Intel i7-1255U, WSL2 x86-64, Clang 20.1.2, LuaJIT
2.1.1703358377. Build commands:

```sh
make -j8 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' all
make -j8 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
make -C research/experiments/engines CC=/tmp/clang20
make -C research/experiments/engines check CC=/tmp/clang20 LUA=luajit
```

The temporary wrappers are the same as in the preceding measurements:
`clang20` selects locally extracted Ubuntu Clang 20 packages; `lua-compat`
uses a LuaJIT-bit-library equivalent of `gen/foreign.lua` and runs all other
scripts unchanged. Newline warnings are disabled for generated `cold.inc`.
These existing build compatibility problems are not fixed by this refactor.

## Paired Fibonacci comparison

The baseline runner was copied before rebuilding. Both runners consumed the
same optimized `fib(30)` ABC module. Five alternating process pairs per mode,
each reporting nine internally timed trials after warmup, pinned to CPU 0:

```sh
taskset -c 0 /tmp/runlet-fused-b84c37c compiled /tmp/fib-new.abc 9
taskset -c 0 research/experiments/engines/runlet compiled /tmp/fib-new.abc 9
# repeat five times, then repeat with lazy instead of compiled
```

Median of the five process medians:

| mode | fused execution | split execution | fused body bytes | split body bytes |
| --- | ---: | ---: | ---: | ---: |
| eager | 6.987 ms | 6.789 ms | 1,210 | 1,072 |
| lazy | 9.182 ms | 8.631 ms | 806 | 715 |

This run suggests about 3%/6% lower execution time; these are not confidence
intervals. The reliable structural result is roughly 11% smaller emitted bodies.
Lazy body bytes exclude its separately allocated activation stubs.
Load/compilation timings were noisy; no compilation-latency improvement is claimed.
The full-suite run was subject to substantial frequency/load variation, so it
is not used as an A/B speedup measurement.
