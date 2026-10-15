# Checked-program boundary cutover

Parent checkpoint: `939b911d`. This change reorganizes the frontend ownership
boundary; it does not add source counted execution or change the C runtime.

## Implemented

- `let/program.lua` owns a completed graph, declarations, access/ownership results
  and analysis statistics. No `fn.access`, `fn.ownership` or vector-level access
  statistics are published. The input vectors are copied, not the whole IR graph;
  callers must treat analyzed nodes as frozen and analyze transformed graphs anew.
- `Check.program` is structural/type-only. Access worklist/provenance and ownership
  fixed-point/SCC algorithms survive. Source, imports, required static demands,
  specialization and raw-IR compilation establish explicit checked programs.
- Private ABC lowering consumes the program without rerunning inference or accepting
  a separate declaration source. The public raw-function compiler API establishes a
  new program rather than trusting old annotations.
- `Layout.program` rejects counted requirements before selecting the currently
  implemented borrowed contract. Layout methods, reference widths and slice/view
  field offsets consume this contract. The old global implicit layout APIs are gone.
- Pointer-free snapshot/staging consumers use the scalar/aggregate layout contract,
  which cannot provide reference layout. Source empty-product handling no longer
  queries physical ABI widths before lifetime analysis.
- Valid counted programs can be typed/analyzed. They still cannot be lowered or
  executed. Cycles and unsafe-access errors remain proof failures.

## Actual checks

`frontend-1.log` failed on an input-offset counter shadowing the new layout argument.
`frontend-2.log` failed on the remaining semantic call to the removed implicit layout
API. The counter was renamed; source empty-product handling was separated from ABI
selection, and remaining staging callers were migrated.

`frontend-3.log`: incremental `make validate-slet` passed. This includes schema,
source/compiler, borrowing/ownership, captures, imports/staging, packed aggregates,
spreads, symmetric execution and portable C checks—not the full runtime `validate`.

Final review removed retained intermediate event sets/dead declaration options and
migrated duplicated slice/view offsets to the selected layout. `focused-final.log`
then passed the affected suites on the final code:

- checked-program boundary: **37 checks, 1 VM execution**;
- ownership inference: **170 checks, 56 VM executions**;
- access proofs: **176 checks, 112 VM executions**;
- checked-IR lowering: **101 checks**;
- lambdas: **269 checks, 80 VM executions**.

Boundary tests establish no inference during structural checking/re-emission,
program-local facts for transformed/shared functions, one analysis for an ordinary
source compile, captured declaration vectors and continued counted-execution rejection.
There is no timing/speedup, clean-build, sanitizer or new runtime ownership claim.
Known unsupported optimizer configurations remain excluded as before.

Commands (repository root):

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-slet
(cd frontend; for test in program ownership access_proofs lowering lambdas; do
  /tmp/lua-compat "tests/$test.lua" || exit
done)
```

Owning placement/representations, lifetime operations, release-code delivery and
failure cleanup are still missing. No result ABI or native callback proposal was
adopted by this structural cut. WORKLIST remains the live completion ledger.
