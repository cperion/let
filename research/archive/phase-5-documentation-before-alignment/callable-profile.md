# Milestone 3: callables (checked-runtime core)

**Status: historical milestone notes pending the phase-5 documentation audit.** The [revision-6 symmetric ISA](symmetric-isa.md) and current `REFACTOR.md` evidence supersede the old A-only argument, code-copy and quickening descriptions below. Those historical descriptions are not current runtime contracts. The separate bootstrap source compiler has been retired; its prior smoke results do not establish production source support.

`CALLI.A`, `CALLI.B` and `TCALLI.A/B` execute callable views without coupling the
VM to Let. `examples/callables.abcasm` demonstrates a captured environment.
The former `closures.slet` is an [archived bootstrap example](../research/archive/bootstrap-slet-before-retirement/examples/closures.slet),
not a working production source example: its runtime partial application rejects explicitly.

```sh
make
build/abc asm examples/callables.abcasm -o build/callables.abc
build/abc run build/callables.abc --compiled      # 42
```

## ABI and checked dispatch

A callable view consists of an opaque code address and a native environment
address. Arguments go on A in source order, with the environment as argument
zero (null for no captures); the code address goes on B. `CALLI.X n` consumes
code B and the n arguments, environment included. Results arrive on X in source
order. `TCALLI k n` replaces the full current frame and operand region, preserving
the original caller's result destination. In this profile-3 strict ABI, callers manage captured storage lifetime. Profile 5 extends the same call shape with traced managed environments for Let; a managed Let callable keeps its captures alive through GC rather than through a lexical caller obligation.

The checked interpreter accepts only exact function-entry addresses in the same
module. It never dereferences an arbitrary code pointer. Wrong-module, null,
interior and HALT targets report `ABC_INVALID`. A different argument/result-kind,
count or hidden-result contract reports `ABC_ARGUMENTS`. Output cells remain
untouched on failure. Environment/data-pointer accesses remain unchecked as in
the [memory profile](memory-profile.md); a valid code target does not validate
its environment. Code addresses are **not** data pointers or host C function pointers.

`abc_module_export_address` copies an exported entry's opaque address. The
module must remain retained while that address is used; instance images retain
it until VM destruction. There is no cross-module indirect dispatch in this profile.
Tagged callables need no runtime object type: explicit BEQ arms select direct or
indirect calls; `SWITCH` is not yet implemented.

## Persistent site knowledge, separate from immutable modules

Each callable module gets a private execution-code copy per VM, alongside its
private image. Serialized code is never rewritten. Every indirect cache is zero
on disk. The authoritative observation record is identified by VM/module instance
and original instruction location, not by compiled block version or continuation.
Separate VMs share immutable modules, never these records.

An observing dispatch follows this lifecycle:

```text
observing → monomorphic(validated target F) → final generic
```

On its first valid target, the cache records the function index and the interpreter
opcode becomes a same-length guarded direct-target variant. Validation includes
exact module/function-entry identity and the complete call-site ABI. A failed
initial validation does not establish a monomorphic case. Repeated matching
targets make no further changes. A guard mismatch changes the site to final
generic **before** validating the new target; it stays generic even if that call
fails. Final generic never restarts observation. The lifecycle is monotonic;
optimization assumptions may weaken. No hotness counters, global caches or
thrashing exist.

**Native realizations.** Each realization registers a patchable dispatch point
with that one site record. A transition updates all existing points, and a newly
compiled realization installs the current phase. Different block versions may
retain different physical layouts: sharing site state does not require a single
flushed-register helper ABI. All future observing dispatches must honor the phase,
including final generic. Obsolete site entrances must not keep selecting the old
monomorphic path merely because it still has a correct guard. A proof already
established for an active invocation remains valid; its code need not be discarded.

**Residualization and block versions.** A cached observation is not proof of the
current target. A successful target guard supplies a proven edge on which ordinary
direct-call residualization can operate. A target proven independently by program
facts requires no observing guard, but still requires ABI validation. Eligible
acyclic calls can use virtual continuations; other calls use explicit ABC frame
transport and transfer, never recursive host execution. Site phase is referenced
by dispatch points, not included in a block-version key.

The native budget is eight versions per original block-entry location, including
one reserved general version. Constants, physical layouts and virtual-continuation
variants consume that same budget; continuation families do not receive new
budgets. When a general entry is needed, materialize any virtual ABC continuation
and required live state before conforming to its physical contract.

**Execution policies.** Eager mode prepares bounded load-time versions and checked
general paths before execution, including general callable entries for every valid
runtime target. It performs no runtime block compilation. An observing dispatch
can select existing code and patch linkage, but cannot request newly compiled
code. Lazy mode may compile a reached specialization through stable stubs within
the same budget, with guards establishing its entry requirements. Both share site
transitions. The interpreter uses ahead-of-time cache-state handlers and quickening,
not runtime fact-specialized blocks.

**Statistics.** `abc_vm_site_stats` exposes generic/specific/final site counts and
specialization-state transitions, not execution counts. A site changes at most
twice. If residualization proves an indirect target and eliminates its observing
dispatch, it does not manufacture an observation or transition. Statistics may
therefore differ between execution policies; language-visible results, effects
and errors must agree. Remaining observing dispatches still obey the exact
mismatch-before-validation rule.

## Experimental version 3

The header uses format version **3**, profile **3**, eight sections and 64-bit
pointer/cell size. All [version-2](memory-profile.md) sections and encodings remain
unchanged. Integer/address kinds are still the only supported scalar kinds.
Additional required sections (including zero-count tables):

7. **Indirect site signatures:** u32 count, then variable records: u32 code
   offset, argument count, result count and hidden-result byte count, followed
   by argument-kind and result-kind bytes. Sites strictly increase and must
   identify an indirect instruction. Counts are 1–255 arguments and 0–255
   results; first argument must be address kind. Every indirect instruction,
   including unreachable ones, needs a matching signature.
8. **Code-address image relocations:** u32 count, then u32 writable image offset
   and u32 function index per record. Eight-byte slots must fit the writable
   prefix, be sorted and not overlap. HALT targets reject. Addresses are inserted
   into each private snapshot, never serialized or inserted into the immutable
   module image.

Instruction encodings are exactly `opcode, u8 n, u32 cache` for CALLI and
`opcode, u8 k, u8 n, u32 cache` for TCALLI. All serialized caches must be zero;
internal specific/final opcode variants reject in saved modules. Version-1 and
version-2 modules retain their encodings and cannot contain indirect instructions.

Assembly uses `.profile callables`. `.codeaddr offset function` creates a relocation.
`.signature name args results argument_kinds result_kinds [hidden_bytes]` declares
a site contract. Alternatively, the name of a declared function supplies its
signature. The extra assembly signature operand is metadata, not an opcode operand:

```text
.signature op 2 1 ai i
CALLI.A 2 op
TCALLI 3 2 op
```

## SLet subset and remaining work

For the current strict subset, a single local binding can incompletely supply a **known word**, e.g. `let p =
add(seed())`; `p(2)` uses CALLI through an adapter with a borrowed environment.
Captures copy normalized scalar cells into a lexical C byte block, never a heap
closure in profile 3. Zero captures use a null environment. Child scopes release blocks in
reverse order; returning from a frame releases them with the frame.

Closure calls are not tail-lowered while their environments belong to the current
frame: dropping it before the adapter reads captures would violate lifetime.
Adapters can tail-call after loading captures. Unit arguments/results are erased,
multiple results and strict left-to-right evaluation are retained.

This is not a full higher-order Let frontend: returning/passing/aliasing callable
values, runtime supply of an already-local closure, runtime selection of callable
views and general typed callable contracts remain unsupported here. Escaping Let captures are profile-5 managed objects specified by `dynamic-profile.md`, not borrowed profile-3 environments.
There is no full C-backend comparison yet. Historical smoke validation covered exact callable results, observing/specific/final transitions, mismatch-before-validation behavior, and a 100,000-iteration indirect tail loop with an eight-cell VM stack. Those results do not validate the clarified architecture or the current teardown checkpoint. The deleted historical `tests/` suite is not present, so exhaustive randomized callable validation remains outstanding.

## Conformance checks required by the clarified design

- Several native versions of one indirect site must share the same transitions;
  versions realized later must begin in the current phase. Separate VM instances
  must remain independent.
- An invalid first target must not establish a monomorphic case. A mismatch to
  an invalid target must leave the site final generic before reporting failure.
- Following a final-generic transition, no old realization may keep selecting
  its monomorphic path. Already-entered guarded activations remain correct.
- Program-proven direct residualization must preserve ABI errors without inventing
  inline-cache observations; compare semantic outcomes across policies without
  requiring identical site statistics.
- Eager first arrivals, mismatches and indirect target changes must compile no new
  blocks. Lazy realization must reuse published versions and honor the shared cap.
- Many call sites, changing loop constants and virtual-continuation contexts must
  not evade the per-location budget. Saturation must preserve results, live cells,
  result destinations, stack limits and explicit ABC continuations.

These are acceptance requirements, not claims that the tests have been implemented
or passed.

