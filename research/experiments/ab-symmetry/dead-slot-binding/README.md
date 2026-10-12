# Known-state dead-slot binding — tested and rejected

The user approved implementing and measuring the first proposed dead-slot fix.
The candidate is **not retained**: correctness passed, but performance regressed.
This is not a completed performance fix.

## Candidate

The generator used `cache.register()` and existing outgoing occupancy to pass
literal zero for dead h/c ABI arguments on statically known dispatches, including
EXT entry. Live values and stack pointers were unchanged. Dynamic-count transfers
remained conservative and unmodified. No new cache, allocator, opcode, ABI,
quickening, capacity policy or native implementation was introduced.

`candidate-banked.lua` and `candidate-validate-cache.lua` preserve the exact
candidate sources. Its Makefile change supplied `build/generated` as the cache
validator's third argument. `SHA256SUMS` records the candidate checkpoint (paths
there referring to active source/build files need not match after restoration).

The independent generator-contract check verified **16,020 direct and 120 EXT**
argument lists against explicit occupancy formulas. Candidate full `all validate`
passed, including 2,400 poisoned-register cases, 655 cache cases, 495 continuation
executions, 582 mirrored general executions, frontend and staging/lifetime suites.
See `validate.log`.

## Isolated measurement

The comparison's `old` label means **pre-fix revision 6**, not the phase-0 engine.
The preserved `../final-comparison/runlet` is linked to the pre-fix runtime. The
candidate runner uses identical runner source/flags and identical copied bytecode.
No workloads were recompiled. CPU 0, seven-call batches, six rotated paired rounds:
24 preflight processes, 144 measurement processes / 1,008 timed steady-state calls.
All processes succeeded and reported the expected final result.

Interpreter candidate/pre-fix paired ratios:

| Workload | Median | Six-pair range |
| --- | ---: | --- |
| loop | 1.073 | 0.808–1.083 |
| branch | **1.063** | **1.044–1.096** |
| fib | **1.067** | **1.028–1.076** |
| memory | **1.537** | **1.292–1.595** |

Greater than one is slower. Native control ranges cross parity; native body-byte
counts are unchanged. Raw commands/stdout/stderr, CSV and phase-specific medians
are in `raw.jsonl`, `timings.csv` and `summary.json`. As before, affinity does not
control frequency or background load; these are batch medians, not retained
individual-call samples. The loop result is noisy, but branch/fib/memory all lose
in every paired round. No speedup is established.

Banked-handler text also grows **2,008,368 → 2,048,732 bytes (+40,364, about 2%)**;
data stays 137,120 bytes. The candidate does not satisfy the performance objective.

## What the experiment teaches

**Dead is not the same as required-zero.** `candidate-load.dis` shows five added
zeroing instructions in a simple GLD64 handler compared with `before-load.dis`.
Those instructions establish values that no semantic consumer requires. Applying
this to every simple dispatch adds work, while the dynamic CALL/RET paths where
preservation was observed remain unchanged. Code layout and other generated-code
differences may also contribute; no exact cycle attribution is claimed.

The previous source/disassembly evidence of needless call-handler preservation
remains valid. This experiment rejects broad known-state zero binding as its
remedy. A narrower boundary-specific binding design needs discussion before a new
candidate; it must not merely trade saved registers for zeroing on every opcode.
The native backedge placement issue remains separate and was not changed.

## Restoration

Only this candidate's generator, validator and Makefile changes were removed using
exact edits. Earlier user work was not restored or reset. Generator/validator
hashes match the pre-experiment checkpoint; Makefile matches the prior clean
build. The active artifacts were rebuilt, and **restored `all validate` passes**;
see `restored-validate.log` and `restoration-and-size.txt`.

To reproduce the candidate, use an isolated source copy, place the archived Lua
files at their original paths, add the documented third validator argument, and
build with the same strict Clang 20 command as the main comparison. Do not overwrite
this candidate runner or either earlier frozen runner. For another timing run,
use a fresh sibling evidence directory: `measure.py` opens raw files exclusively.
