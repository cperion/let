# Callable profile — revision 6, profile 3

Profile 3 adds checked indirect calls to the typed memory profile. It is a
capability profile, **not format revision 3**. All current modules use revision 6;
see [module-format.md](module-format.md) for section layouts and
[symmetric-isa.md](symmetric-isa.md) for the instruction contract.

```sh
build/abc asm examples/callables.abcasm -o build/callables.abc
build/abc run build/callables.abc --compiled   # 42
```

## ABI and checked dispatch

A callable view contains a public code address and an environment address. It is
not a managed runtime closure object. The code identity is an exact function
entry in the same immutable module, not a native entry, host function or arbitrary
data pointer. Captured storage lifetime remains the producer/caller's obligation.

`CALLI.X n` takes the ordered n-argument vector from X and the target from the
opposite stack Y. The address-kind environment is argument zero, included in n;
the target is separate. Argument zero is deepest in X and becomes C0 after
transport. The callee's private A/B regions start empty; both caller prefixes are
protected. Its signature contains argument/result kinds and hidden-result bytes,
not an A/B orientation.

`RET.Y k r` supplies its ordered result vector from Y to the saved continuation's
destination X. CALL destination and RET source are independent. `TCALLI.X k n`
replaces the complete local C/operand frame and preserves the original
continuation and its result destination; X selects only the new argument source.
Its opposite private operand region contains exactly the target before transfer.

All three execution modes use the same checked resolver:

- Null, wrong-module, interior and HALT-containing targets report `ABC_INVALID`.
- Mismatched argument/result counts, kinds or hidden-result metadata report
  `ABC_ARGUMENTS`.
- A valid code address does not validate the environment's bounds or lifetime.
- Host result outputs remain untouched on failure; image writes are not rolled
  back. Pointer access remains unsafe under the memory-profile contract.

`abc_module_export_address` returns the public entry identity. VM images retain
module metadata until destruction; an address without such an owner requires the
caller to retain its module. There is no cross-module indirect dispatch.
Explicit `SWITCH.X` or compare-and-branch can implement tagged dispatch without a
new callable object type.

## Persistent site knowledge, separate from code

Each VM/module image owns one record per original indirect instruction PC:

```text
unseen → monomorphic(validated function) → final generic
```

Only a valid first target establishes the monomorphic state. Repeated matching
targets do not transition. A mismatch records final generic **before** checking
the replacement target, even if that validation fails. Final generic never
restarts observation. Separate VMs do not share this state.

The interpreter and remaining native observing dispatches use the common resolver.
There is **no rewritten code copy, quickened opcode, serialized cache word or
phase-specific native patch registry**. Stable native entry/linkage stubs are
separate from this observation history.

A program-proven target may be ABI-validated and residualized as a direct call,
without manufacturing an observation. Merely reading a monomorphic record is not
proof that the current target matches. Known acyclic calls may use virtual
continuations; other calls use explicit ABC transport/control, never recursive
host execution.

`abc_vm_site_stats` reports generic/specific/final site counts and actual state
transitions, not execution counts. Eliminated dispatches can make statistics
differ between modes; results, effects and errors must still agree.

## Encoding and assembly

Revision 6/profile 3 requires sections 1–8, including empty indirect-signature and
relocation tables when unused. Integer, address and binary64 scalar kinds are
supported. Every indirect instruction, including unreachable instructions, needs
its immutable site signature. Code-address relocations write public entry
identities into each VM's writable image; process addresses are not serialized.

- `CALLI.X`: opcode + u8 argument count (**2 bytes total**).
- `TCALLI.X`: opcode + u8 frame cells + u8 argument count (**3 bytes total**).

There is no cache field or old-format compatibility decoder. Assembly signature
names refer to metadata, not an extra bytecode operand:

```text
.profile callables
.signature op 2 1 ai i
; Inside an appropriately shaped function:
; CALLI.A 2 op
; TCALLI.B 3 2 op
```

`.codeaddr offset function` declares a writable-image relocation. A declared
function name can also supply an indirect call's signature. See the runnable
example above for environment storage, ordinary calls, both destinations and tails.

## Source support and remaining conformance work

The production typed SLet backend uses frame storage, adapters and indirect calls
where supported. This VM capability does not imply full higher-order source
support or completed static partial evaluation. Historical bootstrap closure
examples are archived, not active frontend guarantees. Use
[slet-subset.md](slet-subset.md) and [source-partial-evaluation.md](source-partial-evaluation.md)
for that boundary. Managed Let environments/profile 5 remain unavailable.

Active API and continuation tests cover both destinations, target validation,
shared observations, tails, result order, live prefixes and resource behavior;
full validation passes. See `REFACTOR.md` for evidence.

The current native family/continuation threshold is **16**, selected by the user
after the existing-policy control sweep. It is not a total per-PC cap. The broader
`REFACTOR.md` target replaces shared-callee budgeting with caller-owned region
realizations; changing this threshold does not implement regions. Eager/lazy
version ownership and the whole-diff audit must not be marked complete merely
because callable output tests pass.
