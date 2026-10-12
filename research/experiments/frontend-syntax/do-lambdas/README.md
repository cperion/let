# Unified do-lambda syntax boundary

Implemented in the active frontend batch: `do(parameters): result = expression`
and `do(parameters): result ... end`, with optional result annotations, omitted
nullary parameters for blocks, shared parameter parsing and no pipe/arrow aliases.
Named-definition `= do` remains an executed body; a returned lambda is grouped.
Active examples/tests and specification examples were migrated; archives were not.

## Validation

Command:

```sh
make -j4 -W Makefile LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-slet
```

`validation.log` records successful schema checks, parser 232 checks, syntax batch
98 checks/40 VM executions, compiler 276, lambdas 269/80 VM executions, lowering
100, optimizer 118, staging 27, source demands 52, sessions 280 and unoptimized
four-mode staging. Symmetric placement passed 43 executions; module/VM lifetime
passed 48 cases.

The target did **not** complete: `tools/validate_slet_frontend.lua` uses an implicit
`main(): i64`, rejected by the syntax batch's new `main(): u32` check. The earlier
claim that this restriction preserved the existing entry ABI was inaccurate.
At that checkpoint entry policy required discussion. The user subsequently approved
preserving existing entry behavior; see the follow-up below.

`initial-build.log` records an earlier link failure. Both static archives were found
empty; forcing their Makefile recipes regenerated them and resolved that failure.
No runtime-source change was needed. The cause of the empty archives was not proven.

No clean-build, sanitizer or performance qualification is claimed. Spread/rest
elaboration, general unit completion and owned escaping captures remain incomplete.
The parent source-demand checkpoint retains its separately recorded review/acceptance
obligations. This is partial integration evidence, not closure of all Q/F/X/S items.

## Approved entry-policy follow-up

Removed the new u32-only entry check and the now-unnecessary AST flag. Added named
and anonymous i64 entry execution tests and unit callable entry discovery. The syntax
suite now passes 106 checks/48 executions. `entry-policy-preserved.log` records all
frontend constituents passing before a publishing typo in the updated production
validator (`artifact.module`, a nonexistent field). Corrected publication to assemble
`artifact.assembly`, then ran `/tmp/lua-compat tools/validate_slet_frontend.lua`:

```text
validated production SLet frontend/optimizer: 112 executions, 2 explicit static-demand diagnostics
```

The validator now executes the previously unsupported top-level static partial and
VM-computed supply fixtures; negative cases use an actual runtime parameter and a
missing required static policy. The complete make target was not rerun after that
last publishing correction. Word/binding computational unification is a separate,
subsequently approved model, not implemented by this syntax checkpoint.
