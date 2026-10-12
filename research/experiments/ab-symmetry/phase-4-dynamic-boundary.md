# Phase 4 — approved dynamic-lowering boundary, SLet retained

User approved removing obsolete profile-5 output provided SLet continues working.

## Implemented

- `frontend/let/abc.lua` rejects Let ABC lowering with `dynamic-lowering`, including scalar-only Let. It does not reinterpret Let source as SLet.
- Removed the profile-5 text emitter: managed storage reservation/promotion, tracing descriptor generation, word/dynamic-call emission, boxing/casting/type-test emission and the old A-only aggregate-unboxing path. No compatibility emitter remains behind the rejection gate. Dynamic IR reaching typed-only helpers also rejects.
- Kept the typed memory/callable backend: addressable frame storage, borrowed arguments, typed code/environment pairs, exact callable adapters, indirect signatures, explicit tails and scalar operations.
- Extracted the existing import/semantic phase into `Compiler.typedFile(path)`. It returns the root `unit`, dependency-inclusive `functions`, `foreigns`, `modules` and `phase="typed-ir"`. `compileFile` delegates to that same import pipeline before ABC lowering, preserving its existing artifact/source-unit boundary. Let parsing, typechecking, imports and semantic IR remain supported.
- Updated compiler tests to check actual Let IR operations and explicit lowering rejection, rather than expected strings for unavailable runtime instructions. No fake assembly artifacts or bypass of SLet execution checks were introduced. CLI rejection is checked to preserve an existing output file. Staging cannot bypass the boundary.
- Added a real typed SLet indirect-call adapter test in all three VM modes.
- Migrated the portable-C fixture to explicit revision-6 selected forms and mirrored it. Added independent expected values, rather than relying solely on agreement between two engines. Generated C uses strict warnings with the existing unused-generic-helper exception.
- Added `make validate-slet`, also required by `make validate`, so the migrated source/IR/lowering/staging/C checks run before still-unmigrated legacy bytecode fixtures.

No runtime/native/GC changes, no new source evaluation policy, and no benchmark rerun.

## Validation

The final full-suite attempt executes these successfully before reaching its known legacy-fixture blocker:

- ASDL frontend schema/construction checks;
- **4** schema-walker checks;
- **232** lexer/parser checks;
- **259** source compiler / semantic IR / boundary checks, including SLet execution across interpreted/eager/lazy, imports, aggregates, sums, pointers, borrows, recursion, vectors, typed conversions and staging;
- **81** IR-to-ABC lowering checks, including the new typed indirect adapter executing in all three modes;
- **24** VM-backed staging checks;
- **33** symmetric frontend/optimizer/runtime/C execution processes;
- **12** mirrored portable-C differential cases;
- spec operand-form SLet frontend validation;
- **50** mirrored optimizer modules / **234** original-optimized execution pairs;
- early runtime/IR validators and **495** continuation executions.

Normal strict build succeeds. Reproduction:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
 WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' \
 all validate-slet validate-optimizer-isa
```

`make validate` is **not a full pass**: after the migrated checks above pass, `tools/validate.lua` still emits historical `MOVE_BA`, rejected by the assembler. `frontend/tests/optimize.lua` also still contains old-ISA fixtures. Neither suite was removed or silently skipped. Active fixture/example migration and the remaining whole-suite integration are next.

Evidence: `phase-4-boundary-validation.log` (initial focused run, before the four final CLI/staging checks), `phase-4-boundary-full-validate.log` (final 259-check source suite and current failure boundary), and `phase-4-boundary-c-aot.log`. Earlier phase-4 documents describe historical checkpoints; this approval supersedes their proposed dynamic-boundary decision.

The removed assembly-only managed tests never established GC/ownership execution correctness. Their replacement establishes preserved semantic construction and explicit unavailability, not restored dynamic execution. SLet test passes cover the supported cases above, not every possible source program or completion of the entire refactor.
