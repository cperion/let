# Investigating composition versus mandatory call frames

Status: investigation; no compiler/runtime implementation change. The user's
approval was to investigate reuse of existing composition/continuation machinery.

## Measured probe

`composition-probe.lua`, run from each checkout's frontend directory, compiles a
sum dispatcher and a scalar direct call, assembles them, runs the existing shared
optimizer and checks optimized execution in all four modes. The baseline is
2e82c27f; the current implementation is fe042d9f. Both use the current runtime build.
`composition-probe.log` includes current unoptimized sum assembly.

| Fixture | Baseline raw / optimized bytes | Current raw / optimized bytes |
| --- | ---: | ---: |
| Sum dispatcher | 222 / 222 | 290 / 289 |
| Scalar direct call | 109 / 81 | 109 / 81 |

All recorded executions return 42. No timings were measured.

## Existing machinery and the actual barrier

- `frontend/let/abc.lua:continuation` describes a statement suffix for local
  CALL/TCALL selection. It is not a general checked-body substitution API.
- `src/optimize.c:dag_call` already virtualizes eligible acyclic calls through the
  existing symbolic machine. Adding a new source inliner would duplicate an existing
  responsibility unless a separate necessity is established.
- `residualize_function` explicitly declines functions containing memory ALLOC/FREE
  operations. `CALLOC` has the ALLOC action. Both `main` and `unwrap` in the sum
  fixture contain `CALLOC 8`; their handler call sites therefore cannot benefit
  from this function-level optimization attempt.
- `frontend/let/abc.lua:valueComponents` has no tagged-value representation, while
  `abiComponents` already transports supported address-free tagged values as packed
  u64 cells. Parameter setup reconstructs these cells in a frame block. Construction
  also reserves a block. `VariantPayload` and `Switch` then use memory accesses.

Thus the earlier suggestion that another composition mechanism is necessarily
needed was premature. The boundary to investigate first is **value representation
versus addressable storage**, not special treatment of sum-handler source bodies.

## Proposed direction, not approved implementation

Keep immutable supported tagged values in their existing packed ABI cells, and
materialize frame storage only where an actual place/address is required. Reuse
ordinary frontend value slots and existing scalar instructions, not a new native
value IR, allocator or AST evaluator. Keep shared word elaboration and ordinary
calls; let the existing optional optimizer perform eligible call composition.

Before implementation, specify all construction/extraction/copy and place-boundary
consumers, packed layout/padding, signed and floating bit transport, nested payloads,
and diagnostics for currently unsupported address-bearing sums. The public ABI and
bytecode encoding should remain unchanged. Float/NaN payload preservation must be
proved, not inferred from the integer probe.

Do not remove the optimizer's allocation guard just to make this fixture optimize.
Real allocation effects and address lifetimes still matter. Frame resource/stack-limit
behavior needs explicit review before choosing storage elision policy. Runtime must
remain independent of build-time abc-opt; unoptimized output must remain correct.

Validation must include optimized/unoptimized four-mode equivalence, both alternatives,
parameter/result transport, live neighbors, explicit storage/address use, exact bits,
traps and resource boundaries. Measure code size and preparation/execution costs.
No compactness or speed guarantee for arbitrary handlers follows from this probe.
