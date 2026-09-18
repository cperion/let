# Let

A small language and a LuaJIT compiler for it, with direct residual C.

The thesis is one construct: **the binding chain**. `with` applies it, invocation runs it, two executors
evaluate it. Everything else follows — types are words, records are aggregates, modules are chains.

**`DESIGN.md` is the specification.** It supersedes `let-language-specification.md`, `ARCHITECTURE.md`
and the earlier design notes, which are kept only as the record of where the language came from: reading
them as authority is how abandoned designs come back. §17 is the decision ledger, and it is the part
worth reading first.

## Surface

**Application is the keyword `with`.** One argument at a time, left-associated:

```let
let sum = let a : Int let b : Int do : Int
    return a + b
end
let answer = sum with 1 with 2
```

Adjacency is **not** application: two expressions in a row are a parse error the compiler explains. That
is what makes a parenthesized expression after `with` a **group** — `sum with (square with 3)` — and what
makes `;` mean exactly one thing: it separates a prelude from a written **terminal**, because both sides
of that boundary are expressions.

**Invocation `f(a, b)`** is the transient form: it supplies every stage at once and runs the terminal.
`f()` is the one thing `with` cannot write.

**Types are words.** `:` annotates a binder, `do : T` states a runtime terminal's result, a type word is
applied with `with` (`Box with Int`), and `A | B` is a tagged union. A `switch` matches a type —
applied with `with` (`Box with Int`), and `A | B` is a tagged union. A `switch` matches a type —
`case Int as n` — and the arm that matched binds the payload.

A name that denotes a word is itself a type, and it is **nominal**: `let f : square = square` is legal
and `let f : square = other` is refused however alike the two are. That nominality is what lets a
**stage** be typed by a word — `let g : square` — because the type then carries the callee, so `g(x)`
needs no vtable. A stage typed by an *arrow* names only a shape, so it has no callee and is refused.

## Build and run

Requires LuaJIT and a C11 compiler.

```sh
luajit letc.lua input.let -o output.c      # text -> C
cc -std=c11 -O2 output.c host.c -o program # the HOST supplies main
./program
```

The compiler emits a **module**: `let_module_init`, one entry point per exported word, and
`let_module_unload` when the module owns something. `main` is the host's business (§2.6), so a program is
a `.let` file plus the C that drives it. Diagnostics carry `file:line:column`, and the exit codes are
§13's three kinds — `0` ok, `1` the program is wrong, `2` the compiler lacks the mechanism or is broken.

## One file

`dist/let.lua` is the whole compiler: no installation, no `package.path`, nothing to link. It is
generated from the module tree by

```sh
luajit bundle.lua            # writes dist/let.lua (or: luajit bundle.lua some/other.lua)
```

The committed `dist/let.lua` is **checked, not trusted**: `test/bundle.lua` builds a second copy and
requires it to be byte-identical, because a rebuild that never happened is invisible to a suite that
always rebuilds. If that check fails, the fix is the command above.

and it is read two ways. As a library it returns the same table the modules do, so
`local V = dofile('dist/let.lua')` is the compiler. As a script it compiles a file:

```sh
luajit dist/let.lua input.let -o output.c
```

The module set is **discovered** by following `require` from the entry point, so a module added later
cannot be forgotten. `test/bundle.lua` uses only the bundle — building it, compiling a program with it,
and running what comes out — because every other suite runs the compiler from the tree, where a missing
module is invisible.

## Tests

```sh
luajit test/all.lua
```

Four suites, and every check is a **program** rather than an assertion about a phase:

- `test/spec.lua` — the document and the vocabularies agree, declaration by declaration, as token
  sequences. It is what keeps `DESIGN.md`'s ASDL from drifting away from the code.
- `test/language.lua` — one program per construct: compiled, linked, run, stdout compared.
- `test/bundle.lua` — the same compiler in one file, with no checkout on `package.path`.
- `test/reference.lua` — every fenced example in `LANGUAGE_REFERENCE.md`, compiled (and each
  `refuse:`/`missing:` block checked for the reason it claims). The reference is a document you can
  read, and its examples cannot rot: **`LANGUAGE_REFERENCE.md`** is the language's syntax and
  semantics, while `DESIGN.md` is the specification behind it.

## What is not built

The gap inventory is `Report.MissingWhy`: a `Missing` names a mechanism the compiler lacks, and §13
keeps it apart from a `Reject`, which names a program that is wrong. The suite that reaches one program
per alternative is part of the corpus still being rebuilt. The one entry is `ModuleState`: §2.6's `state`
member, needed when a written terminal leaves behind a top-level binding that owns a resource. The open
questions and every decision that produced them are in `DESIGN.md` §17.
produced them are in `DESIGN.md` §17.

`legacy/` is the previous compiler. It is not a dependency and it is not the specification; it is kept
because knowing what a rule replaced is what stops it being quietly undone.
