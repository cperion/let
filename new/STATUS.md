# Implementation coverage

LuaJIT is the host baseline; C11 is the residual target. `README.md` describes working behavior.
`word.md` is the language design, not a claim that all its examples are implemented.

## Executable TODO categories

| Category | Required work before retirement |
| --- | --- |
| `keyed-words` | Signature-valued members, explicit lexical member occurrences and outer-owner bindings. Retain actual owners, never dynamic callers or inferred parent addresses. |
| `staged-definitions` | Stable construction events/code identities across replay with fresh, checked captures; no retained old-trace symbols. |
| `callable-inputs` | Checked runtime callable parameter/storage ABI, including result constraints and environments where needed. |
| `host-captures` | Explicit transitive freezing/registration and typed residual effects for foreign operations, not arbitrary Lua-effect replay. |

Direct unbound method exports and closed executable-child classification work. They do not finish
the keyed-word category. Static/local callable inlining does not finish the runtime callable ABI.

The counter/closure ownership experiment has been removed. Stateful factories return records by value;
borrowed methods are local/non-retaining only. See [closure-abi.md](closure-abi.md). Catalogue categories
remain roadmap areas even where their old TODO witnesses now have positive tests.

The `word-results` trap is retired: immutable executable results use typed by-value environments,
including nested captures, recursive code groups and outlined results. Mutable escapes remain forbidden.

## Specified facilities not covered by those four categories

- Receiver-free namespace calls such as the `Math.add` example need reconciliation with method binding.
- `Ref(Type)`, reference construction/selection and checked storage lifetimes (word.md sections 27–29, 56).
- Recursive type identities, finite-layout checking across indirection and forward C declarations (13–18).
- `OneOf`, variant construction, exhaustive keyed matching and guarded payload projection (49–52).
- Numeric families beyond U32/Bool/Unit, including exact conversions and floating-point rules (20, 25–26).
- Array/matrix and other data terminals, including their layouts and operations (19, 24).
- Broader recursive/method-bearing type equivalence and interoperability rules.

These are real remaining design/implementation obligations. Removing all catalogue entries
would not by itself establish completion of the full language design. General CFG joins and suffix
sharing are optional optimizations, not required for correct branch-tree execution.

## LuaJIT host contract

- No Lua instruction quota, compiler-installed debug hook, parser or bytecode translator.
- Arity helpers are module-local; Lua globals are not patched.
- Function environments are installed by the loader, checked at demand, and never switched per call.
- Typed ordering accepts two proxies; `:lt`, `:le`, `:gt`, `:ge` accept raw literal operands.
- Typed bitwise operations use methods; raw host bitwise syntax is not proxy dispatch.
- U32 multiplication uses 16-bit limbs rather than an inexact product of Lua doubles.
- Empty userdata own private payloads so LuaJIT can collect engine/word cycles.
