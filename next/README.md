# ABC VM 3 experiment workspace

This directory starts as an unchanged source copy of the current ABC VM at
`54b964dc5c40d5705b8686e4744a30d88271bac0` (`master`, `arch_loop round 12`).
**It still implements VM 2; no VM 3 semantics have been implemented here.**

## Isolation

Runtime, generators, headers, schema, tools, frontend/test support, examples, lab
and vendor sources are independent regular files, not links to the originals.
The copied Makefile resolves inputs and outputs relative to this directory:

```sh
make -C next all
make -C next validate
make -C next clean
```

Build output goes to `next/build/`, ignored by `next/.gitignore`. The root build
does not use these copies. Run the experimental CLI as `next/build/abc`.
Do not run the copied Makefile with `make -f next/Makefile` from the root: use
`make -C next` so paths stay inside this workspace.

Generated build products, VCS/agent state, research archives, and `.ralphi/`
experiments were not copied. There is no nested repository. Source changes here
are tracked by the parent jj repository. `BASELINE.sha256` records the 193 copied
files; before experimentation, verify them with:

```sh
(cd next && sha256sum -c BASELINE.sha256)
```

The manifest is a frozen starting point: later intentional edits will differ.
The original VM contracts remain in [`../docs/`](../docs/), and
[`../WORKLIST.md`](../WORKLIST.md) remains the single live work ledger (V01–V03).
Existing test results elsewhere are not fresh validation of this copy.
`VALIDATION.log` records the initial checks: source equality, ISA metadata,
execution forms and the local collector-free audit pass. The full build is blocked:
this host's default LuaJIT rejects the existing bitwise syntax in `gen/foreign.lua`.
No source workaround was applied; runtime execution has not been revalidated.

## VM 3 design

[DESIGN.md](DESIGN.md) is the experimental VM 3 topology/design authority: unified
A, scalar B, and a ring cache with dynamic occupancy and no eager refill, including
at returns. It separates agreed decisions from the original sketch's proposals,
records the unresolved ABI/encoding gates, maps cutover responsibilities and
specifies correctness/performance evidence. It is not a claim of executable VM 3
support or approval to implement unresolved contracts.

The root VM specifications remain authoritative for the original VM and this
unchanged source baseline; the experimental design does not amend them.

## Experiments

[Ring-cache refill](experiments/refill/README.md) compares demand-only, eager and
return-only refill with identical checked traces. It records modeled traffic and
state frequencies, not native timings, and does not change the no-refill baseline.
