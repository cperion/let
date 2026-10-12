# Why the tail location still has two general contexts

## Status

Investigation only. No active runtime changes, merged entry contracts, new return
convention or version-budget implementation were made in this step.

The preceding [capture correction](../capture-fix/README.md) remains intact. This
trace examines the **successful** corrected executions, rather than reviving the
old value-corruption failure.

Disposable tree: `/tmp/abc-return-trace.o73Oho`, copied from the corrected
reserved-slot experiment. Diagnostics call no ABC functions and do not change
frame transport. The existing event stencil was reused.

## Actual execution

Both A/B fixtures return 101 under eager and lazy execution with tracing enabled.
The checker validates 40 leaf-return/caller-resume pairs across those four runs.

For the leafwide block at PC `0x326`, the logical C frame has four arguments,
one address-exposed block cell and one live scalar. The continuation is at
physical cell 8. All six frame cells occupy physical cells 9 through 14.

| Path | Native C base at general entry and RET | Bias | Continuation cell | Resume C movement | Caller native C base |
| --- | ---: | ---: | ---: | ---: | ---: |
| Materialized virtual call | 13 | 0 | 8 | −7 | 6 |
| Real call, standalone middle | 12 | 1 | 8 | −6 | 6 |
| Real call, middle still inlined into main | 12 | 1 | 8 | −11 | 1 |

The third row occurs in eager execution. It matters: a caller's native base is
not necessarily its function-local argument end. Its existing symbolic cache
can still include an outer virtual activation. A correction must restore the
caller's actual cache coordinates, not hard-code the middle function's base.

Observed distribution across both destinations:

- eager: 18 materialized returns and 2 real returns;
- lazy: 14 materialized returns and 6 real returns.

Every return locates the **same physical continuation cell 8**. Frame-address
identity and the fixture's write-through-escaped-pointer assertions still pass.
The difference is a coordinate/return obligation, not relocated object storage.

### Interpreter reference

`trace_interpreter_return.c` runs the actual generated interpreter handlers from
`leaf`, through CGET, the 3→4 TCALL, leafwide's frame allocation/body and RET. It
seeds the same live caller frame and operands. A HALT substituted only at the
private caller-resume PC publishes the state immediately after RET.

Both result destinations pass:

```text
original argument end = 12
new tail argument end = 13
continuation cell     = 8
C top after RET       = 8
results               = 607, 17, in the selected stack
caller A/B values     = preserved
```

The generic interpreter RET explicitly performs `csp -= k + 1` after cache
publication. Its specialized forms pop the same cells through the cache. Thus
the architectural return drops the current frame and its continuation; it does
not require the caller to know the final callee's argument count.

## The native discrepancy

In `src/residualize.c`, terminal `native_emit_return` currently computes:

```c
return_offset = (c_bias - c_origin - 1) * 8;
```

It uses that offset to load the continuation, then transfers **without changing
C**. The ordinary caller resume subtracts the C displacement originally used
for CALL:

```text
caller_ctop + original_argument_count + 1
```

The materialization probe instead restores from the actual child's origin. Both
paths execute correctly with their separate entry contracts, but those contracts
encode different outgoing C expectations.

The old version manager also includes `c_bias` in context-family identity.
Consequently it creates a zero-bias general context and a bias-one general
context at the same location. Removing that distinction from the key without
changing the return obligation is not valid conformance.

## Coordinate check, not execution of a proposed fix

The checker separately evaluates the coordinate arithmetic:

- Legacy real entry: base 12, bias 1, origin 4; homes `-3..2`.
- Normalize the base to 13 and bias to zero; homes become `-4..1`.
- Both describe **the same physical cells 9..14**. No object or pointer payload
  has to move.
- If RET still leaves C at that normalized base, the old real caller resumes
  **one cell too high**: 7 instead of 6, or 2 instead of 1.

Therefore pure entry-pointer normalization is insufficient. These are model
checks over observed addresses, not a claim that a modified return convention
or merged general entry has been executed.

## Proposed focused correction — pending approval

Project the interpreter's RET frame-pop operation in the native return path,
then normalize the two compatible general C contracts.

### Invariants and flow

1. Publish/capture results using the existing cache rules.
2. Load the continuation before retiring its cell.
3. Rebase C by the same `return_offset` already used for that load. C then
   identifies the caller's logical C top: cell 8 in this fixture.
4. Transfer using the existing CONTINUE primitive.
5. The caller restores its own cache coordinate with `-caller_ctop`, rather than
   subtracting the original callee argument area again. Here that is −2 or −7,
   yielding the observed caller bases 6 or 1.

This changes the **private native return contract**, so return producers and
consumers must change together. It is not a new bytecode operation or a public
ABI change. It makes the native return boundary express an existing ABC effect.
There must be no compatibility shim retaining the old child-origin convention.

### Existing components to change in the isolated experiment

- `src/residualize.c`, terminal return: compose the existing LOAD, REBASE(C) and
  CONTINUE stencils. No new stencil or allocator is required.
- Same file, ordinary direct-call resume: retain the A/B restoration but change
  C restoration from `-c_bytes` to `-ctop * 8`. Entry transport remains unchanged.
- Existing probe resume labels: remove the `child_bias` restoration dependency.
  From the popped continuation boundary, the C adjustment is
  `(frame.old_origin - frame.cbase) * 8`. Preserve existing result routing.
  Do not add more adapters or a second transport system.
- Existing probe general edge: after safe cache publication, normalize C's base
  by `c_bias`, translate C home offsets by the opposite amount, and set bias to
  zero. Reuse the existing canonical general context. Invalidate/recompute any
  C capacity proof relative to the old base; do not carry it over unchanged.
- Audit sentinel/host entry, indirect normal/tail transfers and recursive r0
  results as consumers of native return. Their payload conventions must not be
  silently changed. The current indirect host-recursive execution is a separate
  known refactor issue, not a fallback introduced by this experiment.

Virtual returns that remain wholly symbolic already pop their frame in the
symbolic context. They do not need an additional runtime pop merely because the
terminal native return is corrected.

### Preservation obligations

- No frame-object relocation or rewriting of escaped pointer payloads.
- No added ABC cells, allocations or host-recursive ABC execution.
- Same result ordering/destinations and live caller operands.
- Same trap PCs and stack-capacity behavior; generalization cannot invent extra
  required capacity. C guard proofs must use the rebased coordinate.
- No new safepoint in the transient return/continuation transfer. Typed tests
  cannot establish future GC/root-map correctness.
- Public encoding and API remain unchanged. No timing or code-size improvement
  is assumed; an additional C rebase can remain when caller_ctop is nonzero.

### Acceptance

Run the existing capture, continuation and stack-sweep suites. Require all ten
forced entries to execute and **one general context at `0x326`**, including eager
execution's real return into an inlined caller. Keep explicit checks for stable
frame addresses, ordered A/B results and 0/1/multiple result paths. Cover indirect
and host sentinel return consumers before applying a private convention change
to active code.

This experiment only addresses the two C-origin contracts demonstrated here.
Other entry-contract dimensions, notably `reg_return`, general callable coverage,
strict eager publication and accounting for all resume code, still need the
broader versioning design. No uncounted adapter budget is assumed.

## Reproduction

Start from the corrected reserved-slot experiment described in
`../capture-fix/README.md`. Apply `diagnostic.patch`, then:

```sh
make -j4 -W src/residualize.c LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' build/abc-runtime
ABC_RETURN_TRACE=1 ABC_RESERVED_PROBE_PC=0x326 \
  build/abc-runtime run tail-A.abc main --lazy --stack=1024
```

Repeat for both destinations and both native policies, retaining outputs under
`return-{A,B}-{compiled,lazy}.{log,out}`. Compile the interpreter diagnostic:

```sh
/tmp/clang20 -std=c11 -O2 -Wall -Wextra -Werror -Iinclude -Isrc -Ibuild \
  trace_interpreter_return.c build/libabc.a -lm -lpthread -o trace-interpreter-return
./trace-interpreter-return tail-A.abc A > interpreter-return-A.txt
./trace-interpreter-return tail-B.abc B > interpreter-return-B.txt
python3 check_return_trace.py
```

The event stencil carries a 32-bit immediate, so its diagnostic displacement is
signed 24-bit after the kind byte. An initial unsigned decode was corrected
before collecting these final logs. No execution transport changed during that
correction. The first checker also assumed every caller base was 6; the observed
eager inlined caller correctly required base 1. The final checker uses the
recorded caller cache contract and the interpreter's logical C-top reference.
