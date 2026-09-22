# Implementation coverage

LuaJIT is the host baseline; C11 is the residual target. `README.md` describes working behavior.
`word.md` is the language design, not a claim that all its examples are implemented.

## Remaining completion frontier

| Category | Working now | Remaining work / executable evidence |
| --- | --- | --- |
| `keyed-words` | Signature-valued members; immediate and locally constructed lexical methods; nested mutable record selections retain actual enclosing roots and lexical paths, including recursive sibling occurrences. | Complete nested immutable-snapshot owner binding and unbound nested interfaces requiring outer owners. `test/owners.lua` covers the retained-root slice, shadowing, replacement, copies and absence of dynamic caller inheritance. Missing detached owners are never inferred. |
| `staged-definitions` | Replay-stable local construction; immutable scalar/callable environments; recursive code groups; local lexical words with both receiver and scalar captures can inline. | Outlined lexical words still need an ABI carrying immutable runtime captures **alongside** the receiver. `H.gap` in `test/model.lua` captures a field snapshot plus the receiver in a local recursive word. It raises a precise TODO instead of retaining a construction-trace symbol. |
| `host-captures` | Checked primitive/word captures and typed immutable aggregate snapshots. | Explicit freezing/registration for host tables/helpers and typed residual foreign effects. The host-table capture in `test/model.lua` remains an executable TODO. Arbitrary Lua-effect replay is not an implementation strategy. |

`keyed-words` remains a roadmap category without a dedicated active TODO trap; successful retained-root
selection does not establish support for every owner-binding interface. The two active TODO categories
are witnessed in `test/model.lua`. No category is retired merely to make the ledger look complete.

## Retired callable-input trap

Runtime callable parameters, signature-valued fields and non-retaining environment ABIs exist.
Unknown code needs a result contract; an input-only signature cannot determine it. Missing contracts
now reject with `callable-result`, explaining `results[signature] = ResultType` (or a result-type list).
They do not claim the runtime ABI is unimplemented.

`test/runtime_contracts.lua` checks nested fields, higher-order interfaces, recursive callback helpers,
compilation-local declarations and preservation of static input-only callable requirements. Existing
C tests cover runtime callback invocation and immutable closure environments. The `callable-inputs`
catalogue entry is retired; remaining mixed receiver/capture ABI work is tracked above.

## State and executable results

The counter/closure ownership experiment has been removed. Stateful factories return records by value;
borrowed methods are local/non-retaining only. See [closure-abi.md](closure-abi.md).

The `word-results` trap is retired: immutable executable results use typed by-value environments,
including nested captures, recursive code groups and outlined results. Mutable escapes remain forbidden.

A nested mutable field place can retain its enclosing record root. Selected methods carry that root
and their lexical field path; outlining uses a root receiver parameter when outer names are needed.
Definitions acquire no mutable parent links. Copying a nested value does not reconstruct an owner;
copying the enclosing record supplies independent data and a new root. See `examples/lexical_owners.lua`.

## Specified facilities beyond this frontier

- `Ref(Type)`, reference construction/selection and checked storage lifetimes (word.md sections 27–29, 56).
- Recursive type identities, finite-layout checking across indirection and forward C declarations (13–18).
- `OneOf`, variant construction, exhaustive keyed matching and guarded payload projection (49–52).
- Numeric families beyond U32/Bool/Unit, including exact conversions and floating-point rules (20, 25–26).
- Array/matrix and other data terminals, including their layouts and operations (19, 24).
- Broader recursive/method-bearing type equivalence and interoperability rules.

Receiver-free namespaces already work (`test/namespaces.lua`). These other facilities remain real
obligations. Removing all catalogue entries would not establish completion of the full language design.
General CFG joins and suffix sharing are optional optimizations, not requirements for correct branch-tree
execution. Ordinary helper outlining is a separate scaling opportunity, not a replacement for this frontier.

## LuaJIT host contract

- No Lua instruction quota, compiler-installed debug hook, parser or bytecode translator.
- Arity helpers are module-local; Lua globals are not patched.
- Function environments are installed by the loader, checked at demand, and never switched per call.
- Typed ordering accepts two proxies; `:lt`, `:le`, `:gt`, `:ge` accept raw literal operands.
- Typed bitwise operations use methods; raw host bitwise syntax is not proxy dispatch.
- U32 multiplication uses 16-bit limbs rather than an inexact product of Lua doubles.
- Empty userdata own private payloads so LuaJIT can collect engine/word cycles.

Test subprocess deadlines are separate from this language contract; see `README.md`.
