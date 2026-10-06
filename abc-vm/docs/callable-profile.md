# Milestone 3: callables (checked-runtime core)

`CALLI.A`, `CALLI.B` and `TCALLI` execute callable views without coupling the
VM to Let. `examples/callables.abcasm` demonstrates a captured environment.
`examples/closures.slet` demonstrates lexical runtime supply; it prints `42 43`.

```sh
make
build/abc run examples/closures.slet --interpreted  # 42 43
build/abc run examples/closures.slet --compiled    # 42 43
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
on disk. On a site's first valid target, its cache records the function index
and its opcode becomes a same-length guarded direct-target variant. Repeated
matching targets make no further changes. A guard mismatch changes that site
to a final generic variant **before** validating the new target; it stays generic
even if that call fails. No hotness counters, global caches or thrashing exist.

`abc_vm_site_stats` exposes generic/specific/final counts and knowledge transitions,
not execution counts. A site changes at most twice. Separate VMs share immutable
modules, never their knowledge. The uncached reference tier has no arrival-cache
contexts. Eager mode creates arrival-context versions at load; lazy mode creates reached versions on first arrival through stable stubs. Every version of one indirect bytecode site shares that site's monotonic knowledge. A version compiled after the site has specialized installs the site's current observing, specific, or final-generic helper immediately.

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
There is no full C-backend comparison yet. Current smoke validation covers exact callable results, observing/specific/final transitions, mismatch-before-validation behavior, and a 100,000-iteration indirect tail loop with an eight-cell VM stack. The deleted historical `tests/` suite is not present, so exhaustive randomized callable validation remains outstanding.

