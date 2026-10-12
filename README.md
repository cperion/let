# Let

Let is a progressively typed language built around the ABC three-stack virtual machine.
The approved [collector-free design](docs/owners-references-ids.md) has one Let language:
implicit owners, proved borrows, acyclic counting, immutable value sharing and stores/ids.
Count-free, allocation-free and type precision are independent facts, not a SLet/Let
semantic split. `.let` is the sole target source extension; `.slet` is retired
without a compatibility alias. **This target is not implemented.** The current typed `.slet` path
retains executable lowering/staging; `.let` parsing/checking/IR are supported but
dynamic lowering and profile-5 execution reject. The former GC engine stays archived.
The VM does not depend on the language frontend.

- **A** and **B** are pure operand stacks. A binary operation consumes their tops and its destination bit says which stack receives the result. Nothing ever reaches below a top of A or B.
- **C** holds structured state: return addresses, immutable bindings and frame blocks. It is read by depth, and because it is strictly last-in, first-out, the compiler knows every depth statically.
- The interpreter uses a shared four-register **operand bank** for A/B and a three-register C bank. Lua emits cache-state-specific `preserve_none` handlers and `T_state[opcode]` tables; handlers `musttail`-dispatch directly. Every executable opcode has explicit generated state handling; there is no synchronized fallback.
- Threaded execution passes expanded four-mode validation; broader performance qualification remains open. See [current status and measured caveats](docs/threaded-execution.md).
- Residual execution shares one symbolic allocator: `--jit=threaded` eagerly prepares a seven-register handler tape, while native execution uses eight registers. Threaded execution generates no machine code. See [the integration and performance caveats](docs/threaded-execution.md).
- The compiled tier has host-selected eager and lazy policies over the same residualizer and register-addressed stencils. Eager mode compiles every load-time-reachable context in `abc_vm_load`. Lazy mode installs stable entry stubs at load, compiles a context on first arrival, publishes a direct stub jump, and reuses it without counters or tier promotion. Small non-recursive known callees use virtual continuations in both policies.

The interpreter comes first. The compiled tier is a projection of it, not a separate public machine.

## Specification

The authoritative local specification is [docs/spec.md](docs/spec.md). Its **Decisions** section supersedes older examples and prose. The original Claude Doc is at:
https://claude.ai/code/artifact/557072c1-ef9a-4f32-8878-185ee6f6c3c0

## Layout

| Path | Contents |
| --- | --- |
| `frontend/` | Let/SLet lexer, parser, semantic construction, typed IR, lowering, staging, and language tests |
| `src/`, `include/` | ABC runtime and peer symbolic sinks; `abc.h` is the runtime API and `abc_tool.h` is the build-time optimizer/C-emitter API |
| `schema/`, `gen/` | Durable VM schemas and Lua generators for handlers, symbolic dispatch, foreign bridges, and native stencils |
| `tools/` | CLI, assembler, code-generation helpers, validators, and the standalone optimizer host |
| `docs/` | Language syntax, VM specification, architecture, profiles, and implementation status |
| `examples/` | Runnable Let/SLet, ABC assembly, and C embedding examples |
| `lab/` | Browser simulator with an SLet subset compiler |
| `research/` | Historical experiments and VM prototypes; not production dependencies |
| `vendor/` | Audited third-party source dependencies and license material |

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
build/abc run build/divmod.abc divmod 100 7 --jit=threaded # 14 2
make build/embed
build/embed build/divmod.abc              # 3 2
build/embed build/divmod.abc              # 3 2
```

`abc-opt` is the standalone C residual-DAG optimizer. It runs the generated symbolic VM, folds and virtually inlines supported regions, and canonically re-projects the residual graph to verified ABC:

```sh
build/abc opt build/divmod.abc -o build/divmod.opt.abc
# equivalent direct entry point: build/abc-opt INPUT -o OUTPUT
```

The optimizer is build-time tooling, not part of the runtime library. `abc compile` runs it when producing a module, while `abc run SOURCE.slet` lowers and executes directly without an ABC-to-ABC optimization pass. LuaJIT compiler code loads `build/libabc-opt.so` through `frontend/let/optimize.lua`; C tooling may include `include/abc_tool.h` and link `build/libabc-tool.a`. Both use the same `src/optimize.c` implementation and publish only reverified output.

Link `build/libabc.a` and include `include/abc.h` to embed the VM; see [examples/embed.c](examples/embed.c). The runtime verifies and executes the ABC it receives and never invokes `abc-opt`. Set `abc_limits.mode`, create a VM, and call `abc_vm_load` before execution; threaded mode prepares a handler tape during load, eager mode prepares native code, and lazy mode compiles reached contexts on first arrival. Each VM owns its stacks; loaded modules are immutable and shareable. Calls return structured errors, including abort reason and bytecode offset, rather than exiting the host. The VM has no instruction/fuel budget API: execution continues until completion, language abort, actual resource failure or external process interruption. All execution policies default to 65,536 cells per stack; override stack capacity with `abc_limits` or CLI `--stack=N`.

**Current scope:** typed integer/IEEE-754 binary64 bytecode, memory, direct/indirect calls, typed foreign calls, threaded residual execution, eager/lazy native execution, canonical ABC optimization, and strict self-contained portable-C emission for the integer/direct-call residual subset. Lua generates cache-state-specialized interpreter handlers, the shared symbolic dispatcher, offline register-addressed native stencils, and finite foreign ABI bridges. `make validate` checks the typed runtime and frontend semantics/lowering; retired profile-5 execution tests are [preserved separately](research/archive/dynamic-layer-before-typed-teardown/mixed-frontend-tests/README.md). Passing this suite does not establish dynamic/GC support or completion of the shared observing-site and bounded-version refactor. Portable-C differential validation covers integer arithmetic, control flow, loops, checks, direct calls and export adapters.

```sh
build/abc run examples/fibonacci.slet       # 55
build/abc compile examples/fibonacci.slet -o build/fib.abc --export fib
build/abc run build/fib.abc fib 15          # 610
build/abc run examples/countdown.slet --stack=32
build/abc asm examples/callables.abcasm -o build/callables.abc
build/abc run build/callables.abc           # 42
build/abc asm examples/memory.abcasm -o build/memory.abc
build/abc run build/memory.abc             # 99 1 72
```

The retired bootstrap source compiler and its partial-application examples are
[preserved as historical material](research/archive/bootstrap-slet-before-retirement/README.md).
They are not production SLet capabilities or a fallback compiler.

### Research prototypes

Historical benchmark programs live under `research/`. They are retained as design evidence and are not part of the production toolchain:

```sh
make -C research/vm-prototypes
make -C research/vm-prototypes run
```

Every benchmark runs twice, written before and after the frame instructions and operand forms, so each line shows the speedup on the same build.

The simulator needs nothing: open `lab/abc_vm_lab.html` in a browser. After editing `lab/core.js` or `lab/ui.js`, run `luajit lab/build.lua` to reassemble it.

## Status

- **The typed VM baseline builds and validates.** Profiles 1–4 provide integer and float operations, memory and frame blocks, direct/indirect callables and foreign bridges. Profile-5 managed/dynamic execution is archived.
- **One generated symbolic executor drives peer sinks.** `src/residualize.c` emits register-addressed native stencils directly; `src/optimize.c` emits canonical verified ABC; `src/residual_builder.c` and `src/residual_c.c` emit validated strict C11. Native placement remains the symbolic stack cache and never passes through residual SSA or an all-home allocator.
- **Portable C is a public build product.** Pure known internal calls use typed scalar parameters, returns, and ordinary C locals. Export wrappers and genuinely generic, trapping, or multi-result boundaries retain the stable pointer-array/status ABI.
- **Typed/SLet execution remains integrated.** Active tests cover aggregates and sums, references and raw pointers, typed callables, foreign lowering, compile-time staging and imports. The unified collector-free target remains design work; non-executing Let checks are not evidence of counted-owner or dynamic runtime support.
- **Implementation status is explicit.** `docs/frontend-gap-analysis.md` tracks remaining language, ownership, module-initialization, and persistent-staging work.

## License

WTFPL, version 2: do what you want. See `LICENSE`.
