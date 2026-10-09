# ABC2 dynamic-value profile

> Status: normative profile contract. The loader, scalar `any` representation, generic scalar operations, GC roots, stack-conservative Whippet/Nofl integration, collected ordered-map open words, descriptor-driven aggregate boxing, managed typed allocation/copy and mutation ownership barriers, direct/captured callable construction, partial open-word calls, saturated calls, dynamic tail calls, and result adjustment are implemented for interpreted/eager/lazy execution and conservative canonical ABC optimization. Eager and lazy native execution also implement check-driven primitive-tag/numeric block versions. Complete portable-C lowering, keyed requirement metadata, methods, constant-key caches, same-length quickening, compiled escape-based wide integers, and checked layout-token block-version propagation remain in progress.

> Current specialization scope: the JIT exposes existing numeric operations, not a new public opcode family or frontend rewrite. Narrow integer arms can become helper-free; wide/float operations retain their arithmetic helper. Primitive branch refinement currently requires an adjacent test and branch. See [symbolic VM implementation](symbolic-vm.md#check-driven-scalar-specialization) and [measurements and limits](../research/experiments/type-versions/README.md).

This profile extends the foreign-call profile with dynamic values, open words, collected objects, managed references/views and generic operations. It is a bytecode capability profile. It has no relationship to a source filename: the VM never receives or tests `.slet` or `.let`. The source compiler uses these capabilities for managed ownership in Let, while SLet uses checked lexical borrows and emits no managed roots. The host independently selects interpreted, eager-JIT or lazy-JIT execution for any loaded module.

## 1. Required invariants

- An `any` occupies exactly one VM cell.
- Its semantic type is carried at run time and preserves the exact source type. A stored `u8` remains a `u8`; it does not become an untyped integer.
- Generic operations implement the same arithmetic, conversion, comparison, call and abort rules as their typed counterparts.
- Every generic instruction has a correct unspecialized implementation. JIT specialization may remove repeated checks but may not change behavior.
- Eager and lazy JIT modes execute identical bytecode. Eager mode uses generic checked code for unavailable facts. Lazy mode may include observed tags and open-word layout tokens in a capped block-version context.
- Allocation permission and collector safepoints are properties of bytecode operations, not JIT policy. Compiled code may elide an unobservable scalar box, but it must preserve all observable values and explicit managed allocations.
- Managed references, slices and callable environments keep Let-owned backing objects alive; the producer emits trace metadata for every such stored cell.
- Raw pointers and unmanaged borrows are never reclassified as managed roots.
- No `any` or managed address/environment value appears in a C export or foreign signature; crossing to C requires a copy, raw pointer with an explicit host contract, or an embedding handle.

## 2. Dynamic cell representation

The representation is VM-private and is not serialized in a module or exposed as the C ABI. Implementations may change tag assignments without changing the module format. They must satisfy these observable invariants:

1. Immediate values encode `unit`, `bool`, all integer widths when the value fits the immediate payload, and every `f64` after the required NaN canonicalization and offset encoding.
2. A collected-object reference is the object's plain aligned address. The selected heap must keep such addresses in the implementation's conservative-address range; on the initial x86-64 target their top 16 bits are zero. Because stack roots are conservative plain addresses, this profile's collector does not move published objects. A future moving collector requires a different precise-root or handle representation but cannot change language behavior.
3. Immediate encodings cannot be mistaken for a collected address by the conservative scanner.
4. An integer value that does not fit the immediate payload has a canonical boxed form with its exact width and bits. The interpreter materializes that form when it must store a dynamic cell; compiled code follows the escape rule below.
5. `f64` never allocates. The encoding offsets non-NaN double bits away from the immediate/address spaces. All NaNs canonicalize to one non-colliding quiet NaN because NaN payload identity is not observable; signed zero and infinities retain their IEEE-754 behavior.
6. A raw `ptr` stored in `any` is boxed as an unchecked pointer value. It is never reclassified as a collected reference.
7. Boxing a permanent-rodata string keeps that permanent reference. Boxing a Let managed string or managed string slice retains its collected owner without copying bytes. Only a SLet or foreign string view without a traceable owner is copied into a collected built-string object before it can enter `any`.
8. Open words, closures with collected captures, records, arrays or sums copied into `any`, and boxes for managed references or views are represented by collected objects. Aggregate boxing recursively copies the value, retains nested managed strings/references/views, and copies only SLet or foreign borrowed data; its descriptor identifies every dynamic cell and managed-reference/view field that must be traced.
9. A Let-owned `ref` or slice can be boxed as `any`; boxing retains its collected owner, and unboxing restores the typed managed value. A reference/view into foreign memory or an unpromoted SLet stack, a borrowed callable view, and a `type` value cannot be retained this way. The producer must distinguish managed provenance from an unmanaged borrow.

The runtime centralizes these rules in generated `any_tag`, `any_box_*`, `any_unbox_*` and tracing helpers. Interpreter handlers, JIT stencils and the C emitter use those helpers rather than reproducing tag arithmetic.

**Compiled wide integers use escape-based materialization.** Once a valid dominating check proves an integer tag, residualized code carries the exact raw integer bits in a register while the tag remains compile-time/block-context knowledge. It must preserve that unboxed form across compatible compiled edges, including loop backedges. A heap box is materialized only when the value escapes to an interpreter-visible dynamic stack/image/object cell, an unknown generic or dynamic-call ABI, the embedding API, or an incompatible fallback edge. A compatible specialized call or block edge is not an escape. This prevents a `u64` arithmetic or hashing loop from allocating per operation.

## 3. Heap objects and tracing

Every collected object begins with a private header containing an object kind and enough size or descriptor information to trace it. Required object kinds are:

- open word with ordered-map storage;
- captured closure;
- built string;
- boxed integer or raw pointer;
- boxed managed reference or slice view;
- boxed record, array or sum.

A record or array descriptor gives its byte size and the offsets of fields containing dynamic cells, managed references, managed view bases or collected object references. An open word traces every key and value in its ordered map plus terminal/closure state. Managed string keys retain their collected bytes through the map. Managed-view boxes trace their owner or managed base. Strings and boxed scalars trace nothing. Object headers and numeric layout tokens are VM-private and not language-visible. The conservative scanner and precise trace helper must recognize a managed interior address and retain the allocation containing it.

Module writable storage can contain descriptor-rooted values listed in the module's GC-root section. Descriptor traversal traces their dynamic cells and typed managed reference/view/callable cells while skipping raw pointers and SLet borrows. Frame and operand stacks are conservative root ranges. Heap objects and module roots are traced with descriptor-derived knowledge where available. Code addresses and raw pointers are not semantic heap roots.

A collection can begin in an allocation slow path. The host can also request collection; the VM then switches to safepoint dispatch and honors the request at the next generic or allocating instruction boundary, never in the middle of an ordinary typed instruction. Before collection, interpreter or compiled code saves every live root in scanner-visible form; an unboxed proven integer is not a root and needs no box solely for collection. Collection never observes a half-initialized object: allocation initializes the header and zeroes traceable slots before publishing the reference. A host request can remain pending indefinitely in a loop whose verified path has no generic call or allocating instruction. That is intentional: the loop creates no collectible garbage, and the request is honored when execution next reaches an eligible boundary.

Out-of-memory is `ABC_NOMEM`, an actual host resource failure. It is not a language abort and does not retry the instruction invisibly. Cross-mode semantic equality is required when execution completes with sufficient resources; a physical OOM may occur in one policy and not another because compiled code can elide boxes. The compiler does not replace that fact with a logical allocation or work budget.

### 3.1 Managed typed storage

Profile 5 supports GC ownership even when a Let value has a fully static type and never enters `any`. A managed typed allocation carries a descriptor for its size and traceable fields. `ref(T)` remains one address cell and `slice(T)` remains address plus length; when produced by Let they point into managed storage and are roots. Captured callable environments use the same rule.

The producer decides that storage can escape before publishing any address and allocates it as managed from the start. “Promotion” is this lowering decision or an allocate-and-copy performed before aliases escape; the runtime never silently moves a published SLet stack object into the heap. Managed interior addresses retain their containing allocation. This permits local references, slices and place captures to escape in Let without importing SLet lexical borrow restrictions.

The VM does not infer ownership from a filename or source type. Allocation selectors, descriptor classes and GC-root metadata state whether an address is managed. A raw pointer or strict-borrow descriptor never becomes a managed root merely because its bits fall in the heap range.

## 4. Open words, ordered maps and layout tokens

Every open word has one representation: a collected ordered hash map. The word owns and traces its key storage, hash index, insertion-order entries, value slots, terminal/remaining-requirement metadata and frozen state. There is no transition-shape tree, process-lifetime key interning, field-count threshold or dictionary-mode conversion.

String keys compare by bytes, integer keys compare by mathematical value across widths and signedness, and boolean keys are distinct; every other key aborts with `key-type`. Get and remove on an absent key abort with `field-missing`; setting an absent key appends it. Count returns `u32`. Key-at-index uses zero-based insertion order and aborts with core reason 2 out of range. Removing a key closes the gap in insertion order. Dynamic supply preserves the terminal and remaining requirements. Calling without a terminal aborts with `no-terminal`; overapplication and result adjustment follow section 5. A store through a closed supplied-word view aborts with `readonly-field`.

Each word also carries a nonzero 64-bit **layout token**. The token is an opaque process-local generation, never serialized and never observable by the program. It owns no metadata and keeps no key or object alive. The VM never reuses a token during its lifetime; exhausting the token space is a host resource failure.

Replacing an existing field value preserves the token. Any structural change assigns a fresh token: adding/removing a key, adding/changing a method, changing terminal or remaining-requirement layout, or freezing. A shallow copy may retain the token only when key-to-slot order, callable layout and frozen state are identical. Because equal tokens imply equal slot layout, a cache can trust a slot after one token check without consulting a global shape object.

A constant-key field inline cache records `(site, layout-token, key, slot-or-method)`. A matching token selects the cached slot; a mismatch performs generic hash lookup and follows the site's specialization rules. Computed/data-derived keys use the generic map path and are never retained by an inline cache merely because they were observed. Lazy block contexts may contain a checked layout token, but the one local block-version limit bounds duplication at that block; it does not impose a module-wide generated-code budget, and tokens retain no storage.

A word with `n` live fields therefore uses O(n) collected map storage. Hash/index and slot capacities stay within a fixed load-factor multiple of `max(1,n)`; removals rebuild or shrink when necessary, so historical peak size and mutation count do not remain retained. When the word becomes unreachable, its keys, values and index are reclaimable. Obsolete numeric tokens require no reclamation and no transition graph grows with key history.

## 5. Extended dynamic instructions

Dynamic instructions live behind `EXT`; they do not consume the scarce one-byte public core opcode space. Numeric selectors are generated metadata. Serialized modules use only public selectors; internal quickened opcodes reject on load. In a VM-private mutable code copy, a monomorphic checked-specific site may replace the leading `EXT` byte with an operation-specific one-byte internal opcode whose generated total length equals the original extended instruction; selector/immediate bytes remain as operands or padding. An unquickened observing site and a polymorphic final-generic site continue through `EXT` and pay selector dispatch. Thus stable monomorphic interpreted sites dispatch once, generic sites retain the compact two-level path, and compiled stencils dispatch neither byte. Profile 5 implementation must reserve or reclaim enough internal opcode values for these measured hot specific forms rather than assuming the three values left by the current prototype are sufficient.

Unless stated otherwise, values are dynamic cells. Unary and literal operations have `.A`/`.B` forms over one stack top. Binary arithmetic and comparisons follow the core two-stack convention: they consume `A0` and `B0`, compute `A0 op B0`, and put the result on the stack named by `.X`. Dynamic calls remain the bounded multi-cell exception: the callable and arguments are placed on A in source order, with the last argument on top. This keeps one scheduling model for typed and dynamic expressions instead of forcing extra same-stack moves in the interpreter.

| Family | Required operations | Stack/result contract |
| --- | --- | --- |
| boxing and tests | `ANY_BOX descriptor`, `ANY_CAST descriptor`, `ANY_IS descriptor` | box permitted typed value layouts; checked conversion from `any`; or produce typed bool |
| generic unary | negate, bitwise not, logical not | one `any` from `.X` to one result on `.X`, except logical not produces bool |
| generic binary | arithmetic, remainder, power, shifts, bitwise operations | consume `A0` and `B0`; one `any` result to `.X` |
| literal binary | the same operations with a dynamic-constant index and operand-order bit | consume one `any` from `.X`; one `any` result to `.X` |
| comparisons | equality, inequality and ordered comparisons | consume `A0` and `B0`; typed bool result to `.X` |
| condition | require-bool | one `any` to typed bool; non-bool aborts |
| dynamic call | call and tail call with encoded argument count, requested-result count, result-adjustment mode and a zero cache field | consumes callable `any` and boxed arguments; produces the encoded number of `any` results |
| open word | new, get, set, has, remove, count, key, shallow supply, add method, freeze | fixed stack effects from generated metadata |
| strings | concatenate and text conversion | allocating operations returning `any` string |
| callable construction | direct word and captured closure | a function index plus signature/closure descriptor; consumes only descriptor-declared owned captures and returns callable `any` |
| aggregate allocation | box record, array or sum | descriptor-indexed copying operations |
| managed typed storage | allocate/copy a descriptor-sized object; derive managed reference or slice | returns typed address cells and publishes descriptor-governed tracing |

A descriptor identifies the typed source or destination layout for boxing, conversion, a managed reference/view or a callable. `ANY_BOX` does not accept an unmanaged-borrow or opaque borrowed-callable descriptor. Direct-word and captured-closure constructors remain the only ways typed code creates callable `any`. Managed reference/view boxing is permitted only when the producer has established collected backing provenance and supplies the corresponding traceable descriptor. A dynamic constant records an exact literal kind and bits plus whether it participates in integer-literal adoption. Literal adoption must occur before the generic operation; boxing every source integer literal as `i64` would be incorrect.

### Dynamic calls and result arity

The verifier must know every stack depth, so each dynamic call site encodes its argument count, requested result count and result-adjustment mode. Mode byte `0` is `exact`; mode byte `1` is `adjust`; the trailing four-byte cache field is zero in serialized code. The runtime callable object carries requirement and result metadata.

- Fewer arguments than remaining requirements produce one `any` word result; such a site must request one result.
- Exact saturation executes the terminal.
- Too many arguments abort with `overapplication`.
- `adjust` mode discards surplus results. If callable metadata declares fewer than the requested count, the site aborts with `dynamic-signature` before entering the terminal; it never synthesizes dynamic `unit`. The compiler uses this mode for scalar and binding-list contexts that permit surplus results.
- `exact` mode requires the terminal's declared result count to equal the requested count and otherwise aborts with `dynamic-signature` before terminal effects; the compiler uses it where the language requires an exact return contract.
- An unconstrained dynamic call defaults to one requested `any` result in `adjust` mode; a zero-result terminal therefore aborts rather than producing `unit`.
- The encoded fields, not a source filename or source annotation, determine the bytecode stack effect.

## 6. Generic operation semantics

Generic arithmetic dispatches on the stored tags and then applies the typed rules. Integer-literal operands adopt the other integer width when representable. Mixed widths of one signedness widen; mixed signedness rejects unless an explicit conversion occurred. Float literals and values remain `f64`. Division, remainder, shifts, powers and conversions use the same edge cases and abort reasons as typed instructions.

`==` and `!=` first apply the dynamic equality contract: integer values compare numerically across integer widths and signedness, other unequal types are unequal, strings compare by bytes, and words compare by identity. Ordered comparison requires compatible numeric types. Conditions require `bool`; there is no truthiness.

A generic instruction that proves tags can transfer those facts to the rest of a lazy block version. In the interpreter the proof remains local to the quickened handler. In eager JIT mode it remains local unless all successor versions were prepared at load. No mode may assume a tag without executing or dominating a valid check.

## 7. Quickening and block versions

Each generic site starts correct and unspecialized. It may move monotonically from observing to checked-specific and then to final generic, sharing one knowledge state across all block versions of that bytecode site. It never oscillates between observed types.

Lazy block contexts may include only proven facts: dynamic tags, checked layout tokens, frozen state, known constants, register homes and virtual continuations. Values do not enter a context merely because they were observed. A proven wide integer may travel as raw register bits only on an edge whose target context carries its tag. Versions are capped per compatible ABI/context family; overflow conforms to a compatible generic version. A failed entry/edge guard runs before guarded effects and materializes any virtual scalar representation before transferring to the stable dispatcher, which selects a compatible version or generic path. This is representation normalization, not mid-block deoptimization or stack reconstruction.

Eager mode performs no block compilation after execution begins. It may install precompiled checked-specific internal handlers or stencils for sites whose facts are available, but unavailable or polymorphic facts continue through generic checked `EXT` code. Lazy mode compiles on first context arrival through stable stubs. Interpreted mode may quicken monomorphic sites to same-length single-dispatch internal opcodes but emits no native code.

## 8. Abort and host-failure mapping

The dynamic profile assigns these language abort reasons in addition to the core table:

| Reason | Meaning |
| --- | --- |
| 6 | `type-mismatch`, including a non-bool condition |
| 7 | `field-missing` |
| 8 | `key-type` |
| 9 | `no-terminal` |
| 10 | `frozen-store` |
| 11 | `overapplication` or incompatible dynamic argument arity |
| 12 | `dynamic-signature`, including missing requested results or callable-signature mismatch |
| 13 | `readonly-field` |
Core reasons remain unchanged: division by zero is 1, index range is 2, conversion range is 3, negative exponent is 4 and unreachable is 5. `ptr-collected`, `slet-forbidden`, `abi-any` and `abi-managed` are producer or verifier rejections, not runtime aborts. SLet retains its `borrow-*` diagnostics; Let uses them only at a boundary that attempts to retain an unmanaged SLet/foreign borrow rather than Let-owned managed storage.

## 9. Verification

The dynamic scalar kind is distinct from integer, address and float. The verifier:

1. checks every dynamic instruction's generated length, immediate fields and fixed stack effect;
2. requires `any` operands for generic operations and exact permitted descriptor layouts for boxing/casting;
3. validates each direct-word or closure constructor's function index, signature, owned-capture layout and capture stack effect;
4. checks encoded dynamic-call argument and requested-result counts and its result-adjustment mode;
5. requires joins to agree on scalar kinds and complete C layout, while not requiring equal run-time tags;
6. validates descriptor and dynamic-constant indices, object sizes, trace offsets, and module-root ranges plus their descriptor traversal;
7. forbids dynamic kinds in exports and extern signatures;
8. forbids internal quickened selectors in all serialized code, including unreachable code;
9. accepts managed-reference/view descriptor combinations only for traceable collected provenance, and rejects unmanaged references, borrowed callable views or `type`; the source producer separately proves raw-pointer provenance and all promotion/ownership requirements;
10. treats allocating instructions and safepoint-eligible generic instructions as full register-root synchronization boundaries;
11. computes an `allocation-free` fact for every function as a call-graph fixed point: the function contains no allocating or potentially boxing/generic instruction and every reachable direct callee is allocation-free; indirect, dynamic and foreign calls conservatively prevent the fact.

The verifier proves representation safety and stack shape, not the run-time tag of an `any`. Generic handlers perform those checks.

## 10. Required differential tests

- Every generic operation against the corresponding typed operation for every valid tag combination and every invalid combination.
- Exact-width integer boxing, deferred wide-integer materialization across compatible compiled loop edges, canonical nonallocating NaNs, signed zero and infinities; allocation instrumentation must show zero float boxes and no per-iteration wide box before escape.
- Literal adoption versus ordinary boxed `i64` values.
- Dynamic equality across integer widths and signedness, string content and word identity; repeatedly boxing a managed large string/slice retains its owner without recopying bytes, while a SLet/foreign view copies.
- Open-word insertion order, ordered-map growth/removal, shallow supply, methods, missing fields and deep freeze including cycles; thousands of data-derived keys and repeated structural churn must use O(live fields) collected storage and leave no key-owning global metadata.
- Dynamic partial, saturated and over-applied calls with every requested result count in `adjust` and `exact` modes, including surplus discard and missing-result `dynamic-signature` before terminal side effects, without synthesized `unit`.
- Direct-word, owned-closure and managed-reference/view construction, including escaping Let locals, captures and slices; plus rejection of unmanaged-borrow boxing and mismatched capture/trace layouts.
- Interpreter, eager JIT, lazy JIT and residual C agreement on the same module; monomorphic internal `EXT` forms use one dispatch after quickening, while polymorphic final-generic sites retain correct two-level dispatch.
- Generated opcode allocation proves every internal quickened form has a unique reclaimed byte and the public/internal maps fit 256 entries; no profile-5 implementation may rely on the prototype's three currently free internal values.
- Eager mode performing no runtime block compilation; lazy mode compiling only reached contexts and respecting the local block-version limit.
- Conservative stack roots and precise heap/module tracing of `any` and typed managed references/views across every allocating instruction and host-requested collection; requests remain pending across verified allocation-free loops and run at the next eligible boundary.
- Filename changes having no effect on module loading, mode selection or execution.

