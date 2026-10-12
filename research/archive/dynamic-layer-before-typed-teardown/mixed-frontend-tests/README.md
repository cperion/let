# Mixed frontend suites before test separation

These are exact copies of `frontend/tests/{compiler,lowering,optimize}.lua` before separating retired profile-5 execution from active typed validation. They include working-tree changes made after the original pre-teardown snapshot. They are historical evidence, not active tests or a compatibility implementation.

The relative paths in these files assume their original locations in a matching pre-teardown repository. They cannot execute against the current typed-only runtime. No archived dynamic execution was rerun or validated during this separation.

## Active coverage

- `compiler.lua` continues checking both source frontends without changing their semantics. Mixed-profile fixtures execute only their SLet variants. Let-only semantic/lowering checks remain, but do not establish runtime support.
- Typed non-tail, public, mutual and Ackermann recursion fixtures now explicitly use SLet. Their execution, disassembly and optimization-fixpoint assertions remain.
- The typed portions of mixed import and numeric-conversion fixtures execute independently in all three policies. Managed ownership, escaping captures and `any` execution are not relabeled as typed storage.
- `lowering.lua` retains all typed execution and frontend assembly checks; managed/profile-5 execution and fixpoint checks are archived.
- `optimize.lua` retains typed integer/control/memory/foreign/callable/provenance tests. Dynamic scalar, descriptor and GC-root cases are archived.

No test dispatcher catches runtime failures or substitutes expected results. `make validate` still runs all three active suites normally.

## Validation

Using the active tree after a clean build with Clang 20.1.2 and LuaJIT (Lua 5.4 for `gen/foreign.lua`):

```sh
make LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

Full active validation passed. Frontend counts: parser 232, compiler 176, lowering 78, optimizer 105, staging 24. Runtime validation includes 14 capture contracts, 48 typed differential cases, 243 continuation executions, 1,800 exact-state handlers, 655 cache transitions, portable-C checks and callable/foreign API checks. See `typed-validation.log` for the complete output.

This establishes a tested typed baseline, not completion of the observing-site/version-manager refactor or validation of dynamic execution, strict eager publication, or the proposed return ABI. No performance measurements were taken.

## Snapshot checksums (SHA-256)

```text
84e8432b9132b31138dd10d443b9a01a081185eec7af6789a37ac351a9107777  compiler.lua
dc1d0211e2c086a6b5449b4010905790090caf7cbfddc5f9cb3be9ff38f0bf4f  lowering.lua
fa62fb24ccd05d303fa731cdad881488acf6e187a71313161b0b7b5a8033f305  optimize.lua
```
