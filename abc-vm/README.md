# ABC VM

A three-stack virtual machine for low-level bytecode. Let (`.let`) is the main progressively typed language; SLet (`.slet`) is its static sublanguage, which disallows `any`, managed allocation and GC roots. The production frontend shares one ASDL parser and typed IR across both profiles and currently covers scalar control, aggregates, sums, references/views, typed callables, managed captures, generic `any`, dynamic calls, and profile-checked imports. Neither language is a dependency of the VM.

- **A** and **B** are pure operand stacks. A binary operation consumes their tops and its destination bit says which stack receives the result. Nothing ever reaches below a top of A or B.
- **C** holds structured state: return addresses, immutable bindings and frame blocks. It is read by depth, and because it is strictly last-in, first-out, the compiler knows every depth statically.
- The interpreter uses a shared four-register **operand bank** for A/B and a three-register C bank. Lua emits cache-state-specific `preserve_none` handlers and `T_state[opcode]` tables; handlers `musttail`-dispatch directly. Every executable opcode has explicit generated state handling; there is no synchronized fallback.
- The compiled tier has host-selected eager and lazy policies over the same residualizer and register-addressed stencils. Eager mode compiles every load-time-reachable context in `abc_vm_load`. Lazy mode installs stable entry stubs at load, compiles a context on first arrival, publishes a direct stub jump, and reuses it without counters or tier promotion. Small non-recursive known callees use virtual continuations in both policies.

The interpreter comes first. The compiled tier is a projection of it, not a separate public machine.

## Specification

The authoritative local specification is [docs/spec.md](docs/spec.md). Its **Decisions** section supersedes older examples and prose. The original Claude Doc is at:
https://claude.ai/code/artifact/557072c1-ef9a-4f32-8878-185ee6f6c3c0

## Layout

| Path | Contents |
| --- | --- |
| `include/abc.h`, `src/` | Embedding API, module loader/verifier and checked C VM host |
| `gen/` | Lua interpreter-handler, cache-state, and register-addressed stencil generators |
| `docs/architecture.md` | Target code architecture for the spec-derived, Lua-generated C VM |
| `frontend/` | Reused ASDL schemas, lexer/parser, structured IR helpers, analysis code, fixtures and licenses from the former Wordlet compiler snapshot |
| `tools/abc`, `tools/*.lua` | LuaJIT assembler, production Let/SLet frontend host and CLI dispatcher |
| `examples/` | Runnable bytecode and C embedding example |
| `vm/` | Historical optimized prototypes and measurements; not the product implementation foundation |
| `lab/` | ABC VM Lab, a single-file browser simulator with a compiler for an SLet subset |
| `experiments/` | The scripts behind the numbers in the spec |
| `docs/` | Design history, including the four-lane fork that was evaluated and not adopted |

## Building and running

### Usable VM toolchain

Needs a 64-bit Linux host, Clang with C11/preserve_none/musttail support, Make, and LuaJIT. The Lua generator emits eight independent C translation units so `make` compiles handlers in parallel. The C library has no runtime Lua dependency.

```sh
make
build/abc asm examples/divmod.abcasm -o build/divmod.abc
build/abc check build/divmod.abc
build/abc dis build/divmod.abc
build/abc run build/divmod.abc --interpreted              # 3 2
build/abc run build/divmod.abc divmod 100 7 --compiled    # 14 2
build/abc run build/divmod.abc divmod 100 7 --lazy        # 14 2
make build/embed
build/embed build/divmod.abc              # 3 2
build/embed build/divmod.abc              # 3 2
```

`abc-opt` is the standalone C residual-DAG optimizer. It runs the generated symbolic VM, folds and virtually inlines supported regions, and canonically re-projects the residual graph to verified ABC:

```sh
build/abc opt build/divmod.abc -o build/divmod.opt.abc
# equivalent direct entry point: build/abc-opt INPUT -o OUTPUT
```

Embedders call `abc_optimize` from `libabc.a`. LuaJIT compiler code loads `build/libabc-opt.so` through `frontend/let/optimize.lua`; both entry points compile the same `src/optimize.c` implementation and publish only reverified output.

Link `build/libabc.a` and include `include/abc.h` to embed the VM; see [examples/embed.c](examples/embed.c). Set `abc_limits.mode`, create a VM, and call `abc_vm_load` before execution; eager mode prepares native code during load, while lazy mode compiles reached contexts on first arrival. Each VM owns its stacks; loaded modules are immutable and shareable. Calls return structured errors, including abort reason and bytecode offset, rather than exiting the host. The VM has no instruction/fuel budget API: execution continues until completion, language abort, actual resource failure or external process interruption. All execution policies default to 65,536 cells per stack; override stack capacity with `abc_limits` or CLI `--stack=N`.

**Current scope:** typed integer/IEEE-754 binary64 bytecode, memory, direct/indirect/dynamic calls, typed foreign calls, profile-5 managed values and GC, eager/lazy native execution, canonical ABC optimization, and strict self-contained portable-C emission for the integer/direct-call residual subset. Lua generates cache-state-specialized interpreter handlers, the shared symbolic dispatcher, offline register-addressed native stencils, and finite foreign ABI bridges. Repository validation compares interpreted, eager, lazy, and optimized-ABC behavior across the full implemented VM profiles; portable-C differential validation currently covers integer arithmetic, control flow, loops, checks, direct calls and export adapters. Full float, memory, indirect/foreign, managed and dynamic portable-C lowering remains work.

```sh
build/abc run examples/fibonacci.slet       # 55
build/abc compile examples/fibonacci.slet -o build/fib.abc --export fib
build/abc run build/fib.abc fib 15          # 610
build/abc run examples/countdown.slet --stack=32
build/abc run examples/closures.slet        # 42 43
build/abc asm examples/memory.abcasm -o build/memory.abc
build/abc run build/memory.abc             # 99 1 72
```

### Optimized engines and benchmarks

The old `vm/` programs are measurement prototypes requiring clang with `preserve_none`/`musttail` plus LuaJIT/Lua. They are useful for evidence, not as the architecture foundation:

```sh
cd vm
make            # builds all four optimized engines, including the JITs
./abc_bank      # 20,000 random differential tests, call tests, then benchmarks
./abc_bank 30000 notime   # tests only
```

Every benchmark runs twice, written before and after the frame instructions and operand forms, so each line shows the speedup on the same build.

The simulator needs nothing: open `lab/abc_vm_lab.html` in a browser. After editing `lab/core.js` or `lab/ui.js`, run `luajit lab/build.lua` to reassemble it.

## Status

- **Core VM and profiles 1–5 are built.** Integer and float operations, memory and frame blocks, direct/indirect/dynamic callables, foreign bridges, managed storage, ordered open-word maps, GC roots, and allocation-free verification run in the checked runtime.
- **One generated symbolic executor drives peer sinks.** `src/residualize.c` emits register-addressed native stencils directly; `src/optimize.c` emits canonical verified ABC; `src/residual_builder.c` and `src/residual_c.c` emit validated strict C11. Native placement remains the symbolic stack cache and never passes through residual SSA or an all-home allocator.
- **Portable C is a public build product.** Pure known internal calls use typed scalar parameters, returns, and ordinary C locals. Export wrappers and genuinely generic, trapping, or multi-result boundaries retain the stable pointer-array/status ABI.
- **The production Let/SLet frontend is integrated.** It covers the source paths listed in `docs/slet-subset.md`; `docs/frontend-gap-analysis.md` tracks the narrower remaining language, ownership, module, and persistent-staging work.
- **Still open:** recursive/exported source types, methods and keyed requirements, nested words, general block lambdas, raw-pointer syntax, `extern`/`defer`, module initialization/storage, managed/address-bearing sum ABIs, complete provenance/lifetime proofs, source static-boundary proofs, persistent staging images, dynamic quickening caches, and lazy tag/token propagation.

## License

WTFPL, version 2: do what you want. See `LICENSE`.
