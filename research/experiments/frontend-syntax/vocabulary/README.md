# Vocabulary elaboration — scoped implementation and validation

The shared semantic path executes record vocabulary, definition namespaces and
sum-constructor aliases. This is executable support within existing source-value,
capture and profile admission, not completion of aggregate staging or closure ownership.

## Implemented

- Ordinary declarations and initialized vocabulary use shared binding installation.
- Record expansion reads one context value and installs field snapshots, not place aliases.
  Callable data fields work; receiver methods are not detached.
- Parameter expansion runs after all parameters are bound and uses the same expander.
- Module loading produces public definition namespaces instead of flattened qualified
  strings. Qualified selection, local/file expansion and definition aliases use those
  namespaces. Ordinary imports and explicit export filtering remain in force. Dependency
  foreign ABI declarations do not implicitly expose source names; explicit public foreign
  aliases retain their ABI contracts (compile-time checks, no host calls executed).
- File scopes retain declaration-position lookup boundaries, including forward static
  demands. Later expansion cannot retroactively bind names in earlier function bodies.
- The syntactic resolver supplies capture candidates; semantic binding lookup chooses
  actual captures. No-shadow checking includes uncaptured outer names and predefined/
  explicit module bindings. Definition aliases do not acquire runtime environments.
- Constructor aliases share constructor definitions. Positional/materialized constructors
  use cached ordinary checked IR functions; keyed construction uses the existing variant
  construction operation. This can add functions/code; no zero-cost claim is made.
- Imported schema methods retain their defining module environment, not their caller's
  namespace, including private helpers and earlier vocabulary aliases.
- Compile-time namespaces/types cannot be passed or returned as runtime values. Existing
  capture, initializer transport and executable-profile restrictions are not relaxed.

## Validation

`validation.log` records successful integrated `validate-slet`:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-slet
```

Vocabulary suite: **92 checks / 64 VM executions** in interpreted, threaded, eager
and lazy modes. New execution tests are unoptimized. They cover runtime DSL callbacks,
snapshot independence, single initialization, nested direct captures, escaping-capture
rejection, receiver-method exclusion, collisions, imports, constructor aliases,
declaration-order visibility, forward initializer demands, re-export identity/filtering,
private method environments, namespace non-transport and import cycles. Export tests
cover cross-section overlap in both section orders, bare/alias overlap, repeated names
within sections, early rejection before alias resolution, and valid distinct aliases.
Private type/word spellings may be public aliases in the opposite category when the
public names are unique; the rule does not conflate private and public namespaces.

The integrated suite also passes parser 232, syntax 149/68 executions, word bindings
105/84, application chains 122/112, compiler 281, lambdas 269/80, lowering 100,
optimizer 118, staging 27, demands 52, staging sessions 280, symmetric 43, lifetime 48,
production frontend 112 executions plus 2 demand diagnostics, and portable C 12 cases.

This reused the existing build and includes the separately pending packed-value edits.
`isolation.log` separately records passing vocabulary, compiler, word-binding,
application-chain, demand and lambda suites with `abc.lua` restored from `228fc551`.
That run uses the current runtime build; it is not clean-build or sanitizer qualification.
No timing or broad performance qualification has been run. The existing optimizer/frame-allocation failure remains
unresolved. Global aggregate staging and escaping owned closures are not completed by
vocabulary expansion.

## Approved source compatibility change

The previous spec permitted duplicate public spellings across export sections
(prohibiting duplicates only *within* each section). The previous frontend accepts:

```let
return { types = { Thing = Record }, functions = { Thing = answer } }
```

The user explicitly approved **one public binding per spelling**. The semantic boundary
now validates both sections together before resolving this module's aliases/initializers.
`duplicate-name` rejects overlap; `results` contracts do not introduce public bindings.
Distinct names can alias the same definition. `docs/syntax.md` records this intentional
source compatibility tightening. No runtime namespace or bytecode encoding is added.

`export-name-probe.lua` and `.log` preserve the previous-frontend/current comparison;
the new regression cases enforce the approved rule.

## Structural code-size comparison

`composition.log` runs the existing word-bindings composition probe against `228fc551`
semantics and current vocabulary semantics, both with the same pending packed lowering:

| Probe | Previous raw bytes | Current raw bytes | Previous/current optimized bytes |
| --- | ---: | ---: | ---: |
| Sum | 275 | 306 | 108 / 108 |
| Scalar | 109 | 109 | 81 / 81 |

Ordinary constructor-word generation adds 31 unoptimized bytes on this sum probe;
the existing optimizer removes the extra composition cost here. Optimized probe outputs
are checked in all four modes. This is not a general zero-cost or timing claim, nor a
fix for the separately preserved optimizer/frame-allocation failure.
