# Blanket lifetime-lowering removal checkpoint

Design/order approval: `fd81f206`, following implementation `80a4bfc8`.
WORKLIST O03–O08/E01/E02 remains the live ledger. This is the requested removal
before replacement, not a completed lifetime fix.

Removed the source-to-physical orchestrator, type-implies-holding publication and
results, unconditional scratch copies, whole-function ownership switch, single-use-
only move policy, empty cleanup records, program-wide reference widths, and ABC
routing into that path. No compatibility alias or alternate owning engine remains.
`placement.lua` retains only concrete field-drop generation. The C core, six lifetime
bindings, lifecycle delivery, packed values and address casts are unchanged.

Counted source explicitly rejects pending replacement. Borrowed address-bearing
sums also await the replacement. Positive source integration tests remain enabled;
only tests asserting a program-wide fat-reference policy were removed or changed
to check actual source proof requirements instead.

## Checks

- `check-final.log`: checked-program/raw-IR counted admission rejects, borrowed sum
  admission rejects, and ordinary borrowed source executes 42 without lifetime
  imports or C entries. The retained drop generator matches the entire executable
  body of 396 descriptor uses / 87 callbacks from the pre-removal implementation.
  This is an emitter comparison, not fresh source lifecycle execution.
- `retained-frontend.log`: ownership 168 checks/56 executions, access 176/112,
  packed tagged 1894/496 pass.
- `retained-runtime.log`: owner core 113 checks, C-entry format 180 and boundary 193
  checks, collector guard 234 active files/17 probes pass. These retain their own
  stated scope; they do not qualify the missing materializer.
- `source-integration-blocked.log`: `make validate-source-owners` exits 2 at the
  explicit `ownership-materialization` gate, as expected. The full suite is not
  green. No fresh sanitizer or performance acceptance was run.

Historical generated images in `build/` are not fresh source evidence. Failed
`check-1.log` used the public raw-function lowering API with a checked-program
object; `check-2.log` corrects that probe. The final probe also checks borrowed tags.
No production fix was needed for that probe mistake.

## Reproduction

From the repository root:

```sh
jj file show -r 80a4bfc8 frontend/let/placement.lua > /tmp/let-pre-removal-placement.lua
(cd frontend && /tmp/lua-compat ../research/experiments/runtime-owners/lifetime-lowering-removal/check.lua /tmp/let-pre-removal-placement.lua)
(cd frontend && /tmp/lua-compat tests/ownership.lua && /tmp/lua-compat tests/access_proofs.lua && /tmp/lua-compat tests/packed_tagged.lua)
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' \
  validate-owner-core validate-c-entries validate-no-collector
# Expected failure until replacement:
make LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-source-owners
```

The historical Lua file is used solely as a temporary test oracle. It is not copied
back into active compiler sources, packaged, or used by production lowering.
