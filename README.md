# Let

Let language specification and LuaJIT bootstrap compiler.

The compiler uses constructor-owned ASDL analysis, ownership checking, bounded
partial evaluation, and direct residual C emission. It implements a supported
subset, not the complete language specification.

- [Language specification](let-language-specification.md)
- [Compiler architecture, usage, and limitations](COMPILER.md)
- [Native benchmarks](bench/README.md)
- [Third-party notices](THIRD_PARTY.md)

## Run

Requires LuaJIT and a C99 compiler.

```sh
luajit letc.lua examples/scalars.let output.c
cc -std=c99 -O2 -fPIC -shared output.c -o output.so

luajit test/compiler.lua
luajit test/recursion.lua
luajit test/ownership.lua
luajit test/residual.lua
luajit test/partial.lua
```

Set `CC=clang` to run the tests with Clang. Benchmarks use LuaJIT orchestration
and native C timing loops: `luajit bench/run.lua`.

The specification references separate Sring design documents. Those companion
documents and the Sring workbench are not included in this compiler repository.

