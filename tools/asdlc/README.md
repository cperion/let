# abc-asdlc

`abc-asdlc` is ABC's small, libc-only ASDL compiler. It exists to keep the residual IR schema
declarative without adding a scripting-language or SML dependency to that pipeline.

The tool deliberately implements a restricted language:

```text
schema       := module+
module       := "module" Identifier "{" definition+ "}"
definition   := Identifier "=" (product | sum)
product      := "(" fields? ")"
sum          := constructor ("|" constructor)* ("attributes" product)?
constructor  := Identifier product?
fields       := field ("," field)*
field        := qualified-type ("?" | "*")? Identifier
qualified-type := Identifier ("." Identifier)?
```

`#` starts a line comment. Built-in field types are `number`, `string`, `boolean`, and `any`.
`?` is an optional reference and `*` is a sequence. Unsupported ASDL features are syntax errors
rather than silently changing meaning.

## Structure

- `parser.c` contains the lexer and recursive-descent parser.
- `validate.c` resolves names and checks declarations, fields, constructors, and by-value ordering.
- `emit_c.c` emits deterministic C11 tagged unions, products, sequences, and checked tag names.
- `arena.c` owns parser strings and common dynamic-array support.
- `main.c` implements diagnostics, atomic output files, and the command-line interface.
- `asdlc.h` is the intentionally small boundary shared by those stages.

The generated representation does not allocate nodes. Products and tagged unions are ordinary C
values; optional references are pointers, and sequences are a count plus contiguous items. The
residual builder will own those objects in its arena.

## Usage

```sh
make build/abc-asdlc
build/abc-asdlc --check schema/residual.asdl
build/abc-asdlc schema/residual.asdl \
  --header build/generated/residual_ir.h \
  --source build/generated/residual_ir.c
```

`make validate` runs focused parser, semantic-analysis, diagnostic, keyword-sanitization, and
emission tests, then compiles the generated residual model with the project's strict C flags.

