# Experiments

Node scripts that produced the measurements recorded in the specification. Each loads one variant of the simulator core and the 19 example programs from `../../lab/ui.js`. Run them from this folder; deep recursion needs `node --stack-size=60000`.

| Script | Measures |
| --- | --- |
| `test.js`, `test2.js`, `test3.js`, `fuzz.js` | Correctness: the operand-bank machine against a plain three-stack reference, and the Let compiler against a reference evaluator on hand-written and random programs |
| `banks2.js` | Splits of the eight registers between the operand bank and the C bank |
| `clanes.js` | C spread over physical lanes, per-site hot and cold placement, and the perfect-foresight bound |
| `cstatic.js` | A C cache state fixed by frame depth against the lazy policy |
| `frames.js` | The frame instructions (`CALL n`, `RET k`, `TCALL k n`) against the milestone-1 call forms |
| `callbit.js` | How often a call's result needs a `MOVE.AB`, the case for the result bit |
| `fuse.js`, `fuse2.js` | Adjacent instruction pairs, then the operand forms (`OPI`, `OPC`, `BxxI`) |
| `runs2.js` | What range reads (`CGETR`) still save once the frame instructions exist |
| `residual.js` | Residualization: partial evaluation of the bytecode with the stacks as static data, counting the residual operations a compiled tier would emit |
| `stencils/regstencil.c` | Register-addressed residual stencils: build with the stencil flags from `../vm-prototypes/Makefile` and disassemble to see one machine instruction per operation |
| `residual_stencils/` | Prototype: register-addressed stencils copy-and-patched into `skip`'s inlined loop. Generator translated from the refreshed seed to LuaJIT; run `make -C residual_stencils check`. This is a fixed example, not a general bytecode residualizer. |
| `fourlane.js`, `explode.js`, `growth.js` | The four-lane fork: a compiler and cache-state model, its reached combinations against its static total, and how they grow |
| `lanes/` | The four-lane interpreter in C: run `luajit gen.lua`, then build `main.c` with `lanes_gen.c` |
| `engines/` | One compiled `.slet` module on every execution tier: the reference runtime, the operand-bank interpreter and the copy-and-patch JIT, against Lua and LuaJIT, with exact instruction counts. Run `make -C engines check`. |

The core variants are snapshots taken while each experiment was run (the simulator's current core is `../../lab/core.js`): `core.js` is the simulator's core, `core_exp.js` adds configurable bank sizes, `core_frame.js` adds the frame instructions and `core_fuse.js` adds the operand forms.
