# Signed capacity frontiers — fixed within the existing design

The user approved correcting implementation drift after auditing the existing
frame-coordinate and capacity-knowledge design. Expanded `all validate` now
passes. No new capacity policy, frame layout, guard encoding, backend fallback
or truncation adapter was introduced.

## Applied correction and validation

`src/residualize.c` retains signed 64-bit frontier arithmetic through the capacity
comparison for allocation, direct calls and tail calls. Covered negative frontiers
leave nonnegative `Context.limit[]` unchanged. Uncovered positive frontiers are
checked against the VM's capacity before conversion to unsigned bound bytes.
Requests exceeding the entire VM capacity emit the existing runtime abort form
with the original stack-error PC, without recording unsupported capacity facts.
The existing maximum of 16,777,216 cells guarantees emitted positive guard byte
displacements fit native signed 32-bit addressing (enforced by a static assertion).

`max_c` includes arguments. Entry knowledge remains `max_c - arguments` relative
to the physical C base. Virtual calls/tails change logical bias/origin, not that
physical base; real calls restore their caller base. These existing conventions
were preserved, as were generic-context weakening and version admission rules.

New `tools/validate_capacity_frontiers.c/.abcasm`, wired into `make validate`,
check **360 cases**: both banks, nullary frame shrinking, a subsequent allocation
that must not inherit bogus knowledge, impossible positive requests, just-fitting
and one-short limits, original error PCs, unchanged failure outputs and repeated
calls. The inner physical continuation gives the interpreter a six-cell minimum
versus five for the virtual residual call; tests explicitly preserve that existing
physical-resource distinction rather than changing policy for artificial parity.

`fixed/validation.log` and `fixed/clean-validation.log`: expanded full suite
passes in both the active tree and a fresh source-only extraction, including 904 mirrored oracle
executions, 660 continuations, 168 return checks, 80 lambda executions, 280 session
checks and 48 lifetime cases. The full suite reaches the expanded lowering and
optimizer matrices too (100 and 118 checks respectively). The clean source
archive and location are identified by `fixed/source-archive.sha256` and
`fixed/clean-build-root.txt`.

`fixed/` also retains a new rotated four-round / 512-call pilot and artifact hashes.
All tape and native body sizes match the pre-fix controls. Threaded/off paired
median ratios: loop 0.415, branch 0.435, Fibonacci 1.056, memory 0.817. Noise was
substantial (branch ratio range 0.408–0.748, memory 0.421–0.913). Fibonacci remained
slower (1.022–1.103); the earlier pilot measured 1.256. Do not attribute that timing
change to this correction or declare performance acceptance from these short runs.

## Historical failure

Broader frontend coverage exposed this after the earlier passing checkpoint:
`frontend/tests/lambdas.lua` failed on its unoptimized nullary case.

## Reproducer and evidence

```
build/abc asm research/experiments/threaded-residual/integration/capacity-frontier/repro.abcasm -o /tmp/frontier.abc
build/abc run /tmp/frontier.abc run 40 --jit=threaded
```

Expected result: **42**. Before the fix, interpreted, native eager and native lazy
returned 42; threaded returned `stack-limit at byte 0x3`. Historical `results.jsonl`
records all four runs; the command now succeeds.
The source counterpart is `let value = || -> 42; return value()` inside a function
with one otherwise unused argument. Optimization hides the bug by eliminating
the call; optimizer-disabled staging exposes it.

`probe.c` reads the emitted threaded records (not executing an alternative
interpreter). `guard-words.txt` records:

```
guard C: bytes=34359738360 packed_error=30007
```

`expanded-validation-failure.log` preserves the failing suite output. Its compiler
matrix passed 275 checks before the lambda test failed; later expanded frontend
matrices were not reached and are not claimed validated.

## Broken shared contract

`native_emit_tail()` computes the C capacity frontier as
`coff + callee->max_c`, then casts it to `uint32_t`. Here the frontier is **−1**:
it refers to space below the current C base, not 4,294,967,295 additional cells.
`ensure_capacity()` and `place_guard()` currently accept unsigned cell counts,
so the emitted requirement becomes `(2^32−1)*8 = 34,359,738,360` bytes.

Native's signed 32-bit machine displacement accidentally truncates this to −8.
Threaded's full-width bound operand correctly preserves the supplied bits and
therefore incorrectly rejects the valid program. Teaching threading to truncate
would conceal the wrong shared definition. The common path also assigns this
unsigned count to `Context.limit[C]`, potentially overstating proven capacity;
that knowledge must be audited, not just the emitted comparison.

## Original proposal, superseded by the audited implementation above

1. Define preparation-time capacity requests as **signed relative cell frontiers**.
   Preserve signed arithmetic at every producer: allocation, direct call and tail
   call. Do not cast a negative C frontier into an unsigned requirement.
2. Keep `Context.limit[]` as nonnegative, already-proven capacity relative to the
   current physical base. A negative frontier is already covered and must neither
   emit a guard nor increase that knowledge.
3. Only convert an uncovered positive frontier into checked bound bytes. Audit
   positive overflow/range handling against the existing VM maximum (16,777,216
   cells) and native displacement range. A provably impossible request should
   produce the existing runtime `ABC_STACK` failure at its original PC, not a
   preparation rejection, wrapping displacement or new compatibility path.
4. Keep the existing 32-byte guard record, error packing, VM capacity policy,
   continuations, root layout, allocator and backend boundaries. No new IR,
   extra cells, wider native ABI, GC behavior or default-mode change is needed.
5. Add independent A/B nullary-tail fixtures, nested follow-on capacity checks,
   just-fits/one-short capacities, and assertions that negative frontiers do not
   inflate capacity knowledge. Run all four modes, expanded frontend/staging and
   fresh full validation; remeasure native body-size/performance changes honestly.

The blocker above is resolved; the earlier failure logs remain unchanged.
Broader performance acceptance and whole-runtime sanitizer coverage remain open.
