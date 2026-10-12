# Suffix vocabulary syntax checkpoint

This checkpoint implements the approved **syntax change**, not vocabulary expansion.

Parsed forms:

```let
use std.text...
let context...
let context... = make()
do(context...) ... end
let configure(context...: Context) = do ... end
```

- Prefix import/binding spellings reject; prefix supply expansion and rest remain distinct.
- One vocabulary parameter maximum, block bodies only, no foreign vocabulary parameter.
- `VocabularyParam` is a canonical AST requirement variant.
- `SpreadDecl` / `SpreadStmt` carry the explicit name and optional initializer, rather
  than the obsolete arbitrary-expression prefix form.
- Module indexing registers an initialized context, but does not hoist unknown expanded names.
- Syntactic capture discovery reads an existing context or accounts for an initialized
  context's initializer and explicit binding. It does not discover expanded names.
- Semantic elaboration explicitly rejects these forms with `spread-unimplemented`;
  a marker cannot accidentally compile as an ordinary parameter with no expansion.

## Validation

`validation.log`: integrated `validate-slet` passed using:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate-slet
```

Syntax batch: **149 checks, 68 VM executions** (the VM executions cover existing
executable syntax, not the unimplemented expansion). Parser 232, compiler 280,
word bindings 105/84 executions, application chains 122/112 executions, lambdas
269/80 executions; canonical embedded schemas checked current. The integrated log
also records lowering, optimizer, staging, lifetime and portable-C validation.

The existing build and in-progress packed-value lowering were present. This is not
clean-build, sanitizer, performance or completed packed-value qualification.

## Still required

Shared binding-spread elaboration, eligible-name discovery, immutable record field
snapshots, module/type/constructor definition aliases, collision origins, declaration-
order visibility and corresponding capture resolution. Parameter/import sugar must
reuse that substrate; no callback-only expansion or implicit runtime namespace
transport is implemented here. The previously recorded optimizer frame-allocation
failure remains unresolved.
