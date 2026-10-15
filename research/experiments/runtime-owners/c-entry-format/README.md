# Revision-7 lifecycle C-entry encoding boundary

Scope: WORKLIST E01, minimal format approved separately from the withdrawn large
revision7/v4 ownership-runtime proposal. Approved format is recorded in change
`02409657`; implementation is its child. Parent frontend boundary: `c39887af`.

## Coded and built

- `.centry writable_offset function` in the foreign profile selects revision 7
  and section 10. Revision-6 profiles 1–4 retain their existing bytes. The opcode
  map, selected-stack semantics, ordinary signatures and `.codeaddr` are unchanged.
- Section 10 is a counted table of `(u32 offset, u32 function index)` records.
  Loader checks extent/order/overlap (including section 8), index validity, and
  the two-address/no-results/no-hidden-storage signature. Multiple destinations
  may identify one entry; an empty section introduces no C-entry roles.
- Verified C entries cannot contain HALT, be exports, section-8 targets or direct
  ABC call/tail targets. The shared indirect resolver excludes them even when
  their signatures match an ordinary callable. Encoded unreachable edges are
  checked too. Structural verification does not establish non-failing cleanup.
- Optimizer roots include C entries, independently of exports/ABC relocations.
  Pruning remaps section-10 indices and preserves destinations, annotations and
  ordinary data. No reinterpretation of a C address as an ABC identity.
- VM image creation and direct execution residualization reject C-entry delivery
  before publication. Tooling residual IR and portable-C emission reject the ABI
  explicitly rather than emitting ordinary-function substitutes.
- Private-header dependencies now cover explicit generated/PIC build rules too.
  No owner core, native calling convention or source ownership lowering changed.

## Tested boundary

`integration-1.log` records the first focused build/run: 179 Lua checks and 193 C
checks passed. Review then found missing private-header dependencies in existing
explicit generated/PIC rules. These were repaired; a CLI role-display check was
also added. Treat the rebuilt second integration as final qualification.

`integration-2.log` records incremental `all`, `validate-c-entries`,
`validate-optimizer-isa`, and construction of the API/residual/ISA validators:

- **180** assembler/loader/optimizer checks. Both runtime and tooling loaders are
  exercised. Malformed revisions/profiles/tables/extents/overlaps/signatures and
  forbidden uses reject without publishing outputs. Valid section permutations,
  multiple destinations naming one function, empty tables, two successive optimizer
  runs, pruning before/between roots, C-entry-only roots and direct callees are
  covered. Disassembly identifies the new role.
- **193** C boundary checks over original and optimized modules. The actual shared
  resolver is called directly with a private fixture context (no bytecode execution)
  to test cold/specific/generic ABC target exclusion. All four VM modes reject
  C-entry preparation without publishing images, retaining modules, disturbing an
  existing image or publishing results. Direct residualization, tooling IR and
  portable-C rejection are checked. Ordinary revision-6 and empty-section revision-7
  modules still execute normally.
- Existing optimizer ISA tests: **50** mirrored modules, **308** original/optimized
  execution pairs, including foreign ordering and live-prefix contracts.

`regressions.log` records:

- revision-6 ISA metadata checks and **24** original/mirrored interpreter contracts;
- **143** oracle cases / **1144** mirrored four-mode executions and all **286**
  public core/EXT forms assembled;
- residual IR **315** checks;
- public API image copies, callable A/B/tail observations, foreign calls and linkage;
- portable C **12** mirrored residual cases;
- frontend checked-program **37** checks / **1** execution;
- ownership inference **170** checks / **56** executions, including the continuing
  counted-execution admission rejection.

`revision-6-bytes.log` compares assembly against the assembler from `c39887af`:
profiles 1–4 representative modules and the nine-function ordinary fixture are
byte-identical. This is a specific comparison, not an exhaustive compatibility proof.

Build configuration:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' \
  all validate-c-entries validate-optimizer-isa \
  build/validate-api build/validate-residual-ir build/validate-isa
```

The Lua wrapper uses LuaJIT except for foreign-bridge generation, which uses Lua
5.4; Clang is 20.1.2. `validate-c-entries` is wired into `validate`. The full
`validate` target was **not** run for this chunk. No clean build, sanitizer run,
performance measurement, browser/wasm or task qualification is claimed.
`source.sha256` identifies the changed implementation/test inputs and opcode manifest,
not the entire build closure.

## Still unimplemented

No lifecycle body was executed. There are no prepared C-callable lifecycle entries,
source owning representations/placement, lifetime operations, appended owning-result
storage arguments, activation cleanup records or unwind-before-reset integration.
The standalone C owner core remains separate; reserved runtime imports still reject.
Source counted admission remains closed. No retired runtime dispatcher/catalog,
release cache, scope registry, fixed release register or field-plan interpreter was
restored. This milestone qualifies the format boundary, not source ownership.
