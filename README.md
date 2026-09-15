# Let

Let language specification and LuaJIT compiler.

The compiler uses constructor-owned ASDL analysis, ownership checking, bounded
partial evaluation, and direct residual C emission. Let is defined by its language
specification; the compiler is an implementation in progress, with outstanding
features documented in [COMPILER.md](COMPILER.md).

- [Language specification](let-language-specification.md)
- [Compiler architecture, usage, and limitations](COMPILER.md)
- [Refactoring design and target structure](DESIGN.md)
- [Native benchmarks](bench/README.md)
- [Third-party notices](THIRD_PARTY.md)

## One file

`dist/let.lua` is the whole compiler: no installation, no `package.path`, nothing to link. It is
generated from the module tree by

```sh
luajit bundle.lua            # writes dist/let.lua
```

and it is read two ways. As a library it returns the same table the modules do, so
`local V = dofile('dist/let.lua')` is the compiler. As a script it compiles a file:

```sh
luajit dist/let.lua input.let output.c [options.lua]
```

A file whose exported word is `main` compiles to a complete C program: the command-line host
supplies the C vocabulary as the namespace `c`, emits `main`, and emits a trap hook. A pure
Let file can therefore call libc and become an executable with no C host of its own:

```let
let main = do
    c.puts(c.string("hello, world"))
end
```

```sh
luajit dist/let.lua examples/hello.let hello.c
cc -std=c11 -O2 hello.c -o hello && ./hello
```

`test/bundle.lua` keeps it honest: the committed file must equal what the generator produces, must
emit exactly what the module layout emits, and must compile a file when run.

## Surface

Juxtaposition supplies stages; parentheses invoke words. There is no `with` operator.
Whitespace is insignificant. `let`, `do`, `end`, `if`, `else`, and `return` provide
structural boundaries; use `;` where adjacent expressions would otherwise run
together (`f(x); g(y)`, not `f(x) g(y)`). Assignment remains `name = value`.

Structured control keeps its familiar spelling. Continuation words handle alternative
outcomes without forcing callback plumbing into every statement: a stage constrained only by
`Executable` takes the type of the word an argument supplies, so the callee is selected at the
call site. See [`examples/continuations.let`](examples/continuations.let).

## Run

Requires LuaJIT and a C11 compiler.

```sh
luajit letc.lua examples/scalars.let output.c
cc -std=c11 -O2 -fPIC -shared output.c -o output.so

luajit test/all.lua
```

Set `CC=clang` to run the tests with Clang. Benchmarks use LuaJIT orchestration
and native C timing loops: `luajit bench/run.lua`.

The compiler emits C11 and has no other backend. [COMPILER.md](COMPILER.md) records the covered
language and the remaining gaps.

