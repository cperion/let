# V03: ring-cache refill traffic experiment

This is an isolated Python model of the [VM 3 ring topology](../../DESIGN.md),
not executable VM 3 bytecode or a native benchmark. No copied VM source, instruction
encoding or production policy is changed. The design's demand-only baseline stays
in force. [WORKLIST V03](../../../WORKLIST.md#v--vm-3-isolated-experiments) owns
work status; this directory contains reproducible experimental evidence.

## Question and fixed policies

All three models use the same N=8 register ring, deepest-cell single spills, and
identical logical operations. No surviving register moves merely to align the ring.

- **demand:** never refill. Read uncached cells directly from backing memory.
- **eager:** after a completed operation whose final A depth is smaller than its
  entry depth, refill all free slots from the surviving backing prefix, up to N.
- **return-only:** refill all free slots after completed return/result transport;
  otherwise behave like demand.

Refill prepends cells by decrementing R and loading the new deepest register. It
neither shifts existing cached cells nor copies cells into a second backing home.
No refill happens in the middle of a compound operation. GET therefore reads and
pushes its copy without any refill; return captures its target/result, removes the
frame and delivers the result before the refill decision. DROP and dead frame
removal do not need to read the discarded bits.

These definitions are deliberately precise. They do **not** test every possible
meaning of eager refill: there is no low-water threshold, one-cell/top-only refill,
blocking prefetch, adaptive policy, return-block-size tuning or dirty-bit store
elision. Full pushes always store the displaced deepest cell, even if an eager
load had just fetched it unchanged. Timing results cannot be inferred from this.

## Model and correctness

`model.py` has a physical ring model and an independent uncached list oracle.
Each logical event is replayed through all policies. After every event, assertions
check returned values, the entire logical A sequence, B validity/value and cache
bounds against the oracle. Inspection does not call instrumented reads and adds
no modeled traffic. Scalar additions wrap to 64 bits.

The trace surface is not a new ISA:

- `read` observes a cell without changing logical depth; `get` pushes a copy.
- `write` replaces an existing depth cell; it is not an assignment of SET's future
  encoded depth convention. `pop` consumes bits; `drop` discards without a load.
- `to_b`, `get_b`, `from_b`, `add` and `addi` express scalar-B arithmetic rather
  than substituting two-operands-on-A arithmetic for the topology.
- The call-shaped workload leaves arguments in place and pushes an opaque target
  marker. Its trace convention requires empty B at call entry and one result. Its
  Fibonacci frame is one argument plus one marker, with no locals. Return reads
  the marker and result, drops the frame and delivers to A or B. Marker values
  have no public pointer/continuation encoding or ABI meaning.

Frame/control legality, pointer stability, ownership, foreign effects, verifier
admission, general result vectors and full compiler scheduling are **not** validated
by this model. Python recursion generates the Fibonacci trace; it does not propose
recursive host execution for the VM or contribute a timing result.

`test_model.py` covers every rotation/occupancy for N=1,2,3,4,8 with short backing
prefixes, all valid read/write depths and small return layouts/destinations. It
poisons inactive registers, checks atomic return refill and input capture, and
checks that full push/refill keep surviving register objects in place. Other
cases distinguish pop from drop, expose refill/respill churn, check B liveness,
wrapping arithmetic and all refill-use accounting categories. Multiple seeded
mixed traces and Fibonacci run at N=1,2,3,8,9.

## Workloads

All six traces are generated independently of cache policy. The N=8 run executes
123,645 logical events per policy (370,935 policy/event comparisons).

| Trace | Construction | Limits |
| --- | --- | --- |
| `fib16` | Fibonacci(16), explicit argument/target/result traffic, A/B return destinations, expected result 987 | One chosen scalar call layout, not all continuation implementations |
| `expressions` | Right-deep sums at depths 4,8,16,32,64, 32 repetitions each; left values accumulate and combine via B | Not a claim about the current compiler's optimal scheduling |
| `locals` | 12 locals under 12 temporaries; drop temporaries, read each local eight times, discard locals; 128 repetitions | Read primitive isolates access traffic, not exact frontend instruction count |
| `oscillation` | Start at depth 32, then 4,096 pop/push pairs, finally drop all | Intentionally stresses immediate refill followed by re-spill |
| `pop-drop-streams` | 128-cell streams, 64 consumed by pop and 64 discarded by drop | Combines useful-pop and useless-drop refill cases; tests also separate them |
| `mixed` | 30,000 seeded legal events plus drain, depth bounded around 96, seed 20261019 | Synthetic distribution, no claim of application representativeness |

## What the counters mean

- **Demand loads:** explicit reads of an uncached logical cell, including return
  target/result reads. Already cached reads do not count as loads.
- **Refill loads:** backing cells brought into free ring slots by policy.
- **Spill stores:** deepest cells stored on full pushes.
- **Explicit stores:** writes to existing uncached cells (including arithmetic
  results); distinguish these from spills.
- **Refill used:** a refill residency read at least once before it ends. Repeated
  reads count once for usefulness, not once per access. A later reload starts a
  new residency. A used refill is not proof of a net performance benefit.
- **Unused refill:** partitioned into spilled, discarded, overwritten, or still
  live at trace end. Used plus all unused categories must equal refill loads.
- **States/transitions:** actual event-entry `(R,T)` frequencies, occupancy
  histograms and `(operation,R,T,R',T')` transitions, not hypothetical handler
  counts. Compound-event internal states are not counted as extra dispatches.

No instruction fetches, physical CPU cache misses, stalls, prefetching, native
register pressure, branch prediction, register-move cost or allocation cost are
modeled. Counts are logical backing accesses, not DRAM accesses. No wall-clock
performance estimate or weighted aggregate score is produced.

## Reproduce

From the repository root, with Python 3.12 (no external packages):

```sh
python3 next/experiments/refill/test_model.py
python3 next/experiments/refill/model.py \
  --registers 8 --output next/experiments/refill/runs/n8-NEW
```

Choose a **new** output directory: the runner refuses to overwrite evidence.
`results.json` records the model source SHA-256, trace hashes, final stack results,
all counters, state frequencies and transition frequencies. `summary.csv` provides
the compact traffic table. There is no dependence on the VM's currently blocked
Lua/native build toolchain.

## N=8 results

Raw evidence: [`runs/n8-001/results.json`](runs/n8-001/results.json),
[`summary.csv`](runs/n8-001/summary.csv), [`run.log`](runs/n8-001/run.log),
[`tests-final.log`](runs/n8-001/tests-final.log), and
[`provenance.json`](runs/n8-001/provenance.json). The earlier nine-test run before
expanding exhaustive coverage to N=8 is retained as `tests-initial.log`.

Each entry below is **total loads / total stores**, including explicit stores.
These are measured model counts, not time or hardware-counter results.

| Trace | Demand | Eager | Return-only |
| --- | ---: | ---: | ---: |
| fib16 | 1,970 / 1,970 | 11,151 / 11,151 | 7,964 / 7,964 |
| expressions | 5,632 / 5,632 | 2,816 / 2,816 | 5,632 / 5,632 |
| locals | 12,288 / 2,048 | 6,144 / 2,048 | 12,288 / 2,048 |
| oscillation | 0 / 24 | 4,120 / 4,120 | 0 / 24 |
| pop-drop-streams | 7,680 / 15,360 | 15,360 / 15,360 | 7,680 / 15,360 |
| mixed | 6,561 / 3,498 | 15,249 / 12,165 | 6,561 / 3,498 |

### Interpretation

- **Eager has real wins in this model.** Deep expressions halve both loads and
  stores: refilling lets subsequent arithmetic update registers instead of backing
  cells. Repeated local reads halve loads. All 2,816 expression refill residencies
  are used; the locals trace uses 1,024 of 2,048 refills.
- **Recursion does not automatically favor return refill.** In this Fibonacci
  layout, eager uses only 1,594 of 11,151 refills (14.3%); return-only uses 1,594
  of 7,964 (20.0%). Most refilled cells get spilled/discarded before a useful read.
  This contradicts a blanket recursion benefit, not every possible return policy.
- **Oscillation exposes churn:** eager performs 4,120 refill loads, none used,
  and 4,120 stores versus demand's initial 24 stores. Filling a freed slot can
  undo the very capacity the next push needs.
- **Discard streams matter:** loading bits about to be dropped adds traffic with
  no semantic use. Mixed traffic likewise uses only 147 of 8,861 eager refills.
- **Inventory is not hot-state footprint.** Fibonacci visits 72 demand states,
  16 eager states and 23 return-only states. Mixed traffic visits 69, 16 and 69.
  Eager's fuller bank can reduce state diversity even while increasing memory
  traffic. These counts do not establish instruction-cache pressure or speed.

The experiment does not select a universal winner. It supports keeping demand-only
as the documented baseline while identifying expression/local-read workloads where
an eager policy deserves actual execution measurement. A register-specialized
native/interpreter experiment would be a separate approved slice; timing this
Python model would measure Python, not ABC dispatch or load latency.
