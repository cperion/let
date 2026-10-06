# ABC VM

A three-stack virtual machine for low-level bytecode. Let (`.let`) is the main progressively typed language; SLet (`.slet`) is its static sublanguage, which disallows `any`, managed allocation and GC roots. The current bootstrap frontend implements the scalar SLet subset. Neither language is a dependency of the VM.

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
| `tools/abc`, `tools/*.lua` | LuaJIT assembler, scalar bootstrap SLet frontend and CLI dispatcher |
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

**Current scope:** typed integer/IEEE-754 binary64 bytecode, direct and indirect calls, context range forms, memory, typed foreign calls, a reserved `EXT` decoder, and a scalar SLet frontend. Lua generates cache-state-specialized interpreter handlers, offline native stencils, and finite foreign ABI bridges. Eager and lazy compiled policies use one capped context-versioning residualizer; lazy versions are persistent, first-arrival compiled, and reached through stable copy-and-patch stubs. Repository validation runs identical modules under interpreted, eager, and lazy policies. Dynamic profile 5 remains normative future work.

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

- **Milestone 1 (integer core): built in the checked runtime.** Typed integer arithmetic with normalization, compare-and-branch, checks that abort, context range forms (`CPUSHN`, `CGETR.X`), frame instructions (`CALL.X f, n`, `TCALL f, k, n`, `RET k, r`) with the result bit, and operand forms (`OPI`, `OPC`, `BxxI`).
- **Public opcode metadata is spec-owned.** `tools/opcodes.lua` is now the source for `build/opcodes.h`; the public runtime no longer imports opcode layout from `vm/gen.lua`.
- **Compiled-tier target:** eager and lazy capped context versions with independent monotonic site knowledge. Eager mode finishes compilation at load; lazy mode compiles reached contexts on first arrival through stable stubs. Neither uses hotness, tracing, speculative deoptimization, source filenames, or tier switching.
- **Native-tier target:** emit C from verified bytecode's residual program at build time, the canonical C route (Decision 16), not a separate Let backend. Interpreter, residual stencils and C must eventually share one semantics table.
- **The simulator** (`lab/`) implements the same instructions, and its SLet compiler emits them, including `CALL.B` for calls compiled for B.
- **Milestone 2 (memory): built in the public checked runtime.** All 54 frame/image/pointer/indexed/copy instructions; explicit integer/address signatures; live padded frame-block verification; private persistent image snapshots; hidden aggregate-result destinations; native pointer and byte-string embedding tests. The source frontend uses frame blocks for closure captures; general records/arrays/sums remain to be lowered.
- **Milestone 3 (callables): checked-runtime core built.** CALLI.A/B, TCALLI, environment-inclusive signatures, image code-address relocations, guarded same-module targets and per-instance execution copies. Site knowledge changes at most twice, with no hotness counters. Lexical runtime supply runs in `examples/closures.slet`; full higher-order source typing and C-backend comparison remain open.
- **Next milestone: 4, host boundary.** Foreign ABI bridges remain unimplemented. Floats, `SWITCH`, `EXT`, full memory/callable optimized-tier support and the canonical native C tier are also not yet built.
- **Optimized prototype limits:** call and frame counts up to 4 and result counts up to 2; larger counts abort with reason 254 in that interpreter and are rejected by its JIT. The public reference runtime supports counts up to 255.

## License

WTFPL, version 2: do what you want. See `LICENSE`.
