# Continuation-layout feasibility probe

Follow-up: [reserved-slot actual-transfer experiment](reserved-slots/README.md).
It validates fixed-arity transfers but retains tail-call/conformance failures;
it does not adopt a production layout.

Latest investigation: [return contract behind the two general contexts](return-contract/README.md).
Actual interpreter/native traces identify caller-side cleanup tied to the callee's
entry base; a coordinated projection of RET's frame pop is proposed, not implemented.

Previous result: [capture correction and successful reruns](capture-fix/README.md).
The focused capture/liveness fix is applied to active sources; executable archived
builds now pass the formerly failing tail/materialization cases. Two legacy general
contexts still remain at the tail location, so version-budget conformance is open.

The preceding [interpreter-versus-symbolic projection trace](projection-trace/README.md)
reproduced the home corruption in the original engine without any new frame or
return mechanism, and redirected the work to faithful cache-operation projection.

## Result: late insertion is not a valid general-entry mechanism

This is an isolated experiment against the pre-teardown snapshot, not production
runtime code and not a completed implementation of the clarified version policy.

The current native symbolic machine omits a virtual call's physical return cell.
Restoring that cell later by inserting space into C moves frame storage above it.
A valid `FADDR` into that storage has already escaped into another frame and/or
the module image. Moving the object invalidates those aliases. Updating only
symbolic register/home references cannot repair pointers stored in memory.

**The proposed general-entry transition therefore needs a frame-layout decision
before implementation.** The experiment disproves late insertion into the current
packed layout; it does not prove that all possible materialization designs fail.
No replacement layout or ABI was implemented.

## Fixture and method

`layout-A.abcasm` and `layout-B.abcasm` are typed memory-profile modules generated
by `probe_generate.py`. Each executes ten calls through `main → middle → leaf`.
They cover:

- two nested virtual calls and subsequent real-call paths under the old policy;
- a separately address-exposed frame object at each level, containing 101, 202,
  and 303, with addresses recorded in module memory while the objects are live;
- caller pointers passed to the leaf;
- surviving A values 111/333/555, B values 222/444/666 and C values 777/888/999;
- two ordered results, delivered to either A or B;
- verification of values after the return chain, with final result 101.

The explicit leaf jump targets bytecode PC 793 (`0x319`). The instrumentation
records incoming virtual continuations there. It uses the existing
`conform_generic` to publish constants, registers and aliases to physical homes
**within the same continuation family**, then executes a diagnostic stencil.
This is not the proposed cross-continuation general entry.

The diagnostic copies actual native C-stack contents. It inserts one marker per
omitted return cell into the copy, using offsets derived from the captured
`abc_symbolic_continuation` records. It checks object contents at their relocated
positions, evaluates where the unchanged pointers would refer, and checks that a
write through an old alias would not update the relocated object. The live VM
stacks and escaped addresses are never relocated. Execution resumes through the
old engine and the original fixture's assertions.

Thus these are real native-state observations plus a copied-memory insertion
counterexample, **not execution of a newly implemented virtual-to-general edge**.
No new eight-slot saturation policy was installed. The old admission policy
chooses real calls for later contexts; the probe tests the interior transition
that the proposed policy would need to support.

## Observed layout

For a two-virtual-call activation, offsets below are 64-bit cells from the VM's
C allocation. The original end is cell 12 (exclusive). The omitted return cells
would be inserted before old cells 3 and 7.

| Address-exposed object | Original cell | Cell after insertion | Address change |
| --- | ---: | ---: | ---: |
| main | 1 | 1 | none |
| middle | 5 | 6 | +8 bytes |
| leaf | 10 | 12 | +16 bytes |

The original pointers to middle/leaf then read other cells, not 202/303. Even
retaining an old copy of an object would not solve identity: a write through the
old alias would no longer update the location used by canonical frame access.
Raw addresses can be stored in arbitrary memory, so a stack-register rewrite is
not a general pointer-repair mechanism.

## Executions

- Baseline, ample stack: **6/6 pass**, two destinations × three policies.
- Instrumented native runs: **4/4 pass** their original result/live-state checks.
- Native snapshots: **40**, of which **26** have two virtual continuations.
- Copied insertion moves addressed objects in **32/40** snapshots. The other
  eight have no virtual continuation to insert and are negative controls.
- Stack sweep: **192 executions**, capacities 1–32 × two destinations × three
  policies, against the uninstrumented archived engine.

### Independent stack-limit mismatch

At capacity 14, for both destinations:

| Policy | Outcome |
| --- | --- |
| interpreted | `ABC_STACK`, byte `0x2c0` |
| eager | succeeds, result 101 |
| lazy | `ABC_STACK`, byte `0x2c0` |

First successful capacities were 15, 14 and 15 respectively. Other tested
capacities agreed on success versus stack failure. Exact diagnostic equality was
not asserted throughout the sweep; the full diagnostics are retained in
`results.json`. The cause of the discrepancy has not been isolated. It predates
this probe and must not be presented as a regression caused by instrumentation.

## Evidence and limitations

- `summary.txt`, `results.json`: checked outcomes and complete stack sweep.
- `probe-*.log`: compile-time entry counts and runtime stack/root observations.
- `probe-*.out`: final outputs.
- `layout-*.dis`: verified module disassembly.
- `instrumentation.patch`, `layout_probe.inc`: experiment-only native changes.
- `checksums.txt`: measured executables and archived source identifiers.

The disposable source/build directory for this run is
`/tmp/abc-cont-layout.kgZBMc`. It was copied from
`research/archive/dynamic-layer-before-typed-teardown/snapshot/`, with Whippet
vendor sources and a copied build cache. The build regenerated opcode/banked/
symbolic artifacts and rebuilt the affected runtime/tool objects. The initial
runtime was preserved before instrumentation as `baseline-runtime`.

The instrumented build publishes more state and adds diagnostic calls. It is not
performance evidence. It does not validate new version selection, native site
patching, a replacement continuation ABI, or the current incomplete working tree.
No production source files were changed by this experiment.

## Reproduction

From the repository root, using the previously established Clang/Lua wrappers:

```sh
repo=$PWD
probe=$repo/research/experiments/continuation-layout
work=$(mktemp -d /tmp/abc-cont-layout-repro.XXXXXX)
cp -a "$repo/research/archive/dynamic-layer-before-typed-teardown/snapshot/." "$work/"
cp -a "$repo/vendor" "$work/"
cp "$probe/probe_generate.py" "$probe/check_probe.py" "$work/"
cd "$work"
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' build/abc
cp build/abc-runtime baseline-runtime
python3 probe_generate.py
patch -p1 < "$probe/instrumentation.patch"
cp "$probe/layout_probe.inc" src/
make -j4 -W src/residualize.c LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' build/abc-runtime
for dst in A B; do
  for mode in compiled lazy; do
    ABC_LAYOUT_PROBE_PC=0x319 build/abc-runtime run "layout-$dst.abc" main \
      "--$mode" --stack=1024 > "probe-$dst-$mode.out" 2> "probe-$dst-$mode.log"
  done
done
python3 check_probe.py
```

`layout_probe.inc` is intentionally not integrated into production dependencies;
use `-W src/residualize.c` when rebuilding after changing it. The probe uses fixed
bounded diagnostic storage, not a proposed runtime data structure.

## Design discussion required next

A viable general-entry transition must preserve the physical identity of every
address-exposed frame block. Options to discuss include reserving architectural
continuation slots from the start of virtual calls (without necessarily storing
return targets), or a different general-entry/continuation layout that can use
existing storage without moving it. Rejecting virtualization early is another
possible policy, but would change the current promise about acyclic calls and
must not be silently substituted.

The next approved experiment should test one chosen layout through an actual
native transfer and return, including the stack-limit boundary. It must not
merely make this copied-memory diagnostic pass.
