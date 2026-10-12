# Quickening dependency audit and minimal replacement binding

Status: inspected before implementation. The revision-6 ISA is approved for the step-by-step migration; this audit records the execution bindings required by its removal of bytecode quickening. It does not claim that any old path has been deleted yet.

## Existing dependency chain

| Responsibility | Current files and behavior | Revision-6 action |
| --- | --- | --- |
| Opcode definitions | `tools/opcodes.lua`: 6 arity-specialized CALL bytes, 9 TCALL bytes, 9 RET bytes, and 6 observed/final indirect bytes | Delete all 30 internal variants; no replacement opcode reservation |
| Dispatch metadata | `tools/gen_opcodes.lua`: K_INTERNAL and old opcode ranges; `gen/banked.lua` generates their handlers | Replace with revision-6 operation/selected-bank metadata and mirrored public handlers |
| Direct-call rewriting | `gen/banked.lua`: generic CALL/TCALL/RET rewrite `image->code[pc]`; fixed-count variants depend on that rewrite | Delete rewriting and fixed-count opcode handlers; implement the public parameterized transport directly |
| Direct target binding | `gen/banked.lua` lazily fills `direct_callees[pc]`, then quickened handlers assume it exists; `src/vm.c` allocates it | Retain useful immutable call metadata, bind direct targets at load, remove first-execution coupling to rewritten opcodes |
| Interpreter indirect state | `gen/cold.lua`: phase inferred from opcode, target function index stored in four code bytes | Put observation state in the VM/module image site record, not the byte stream |
| Serialized indirect words | `tools/assembler.lua` emits four zero bytes; `src/memory_module.c` verifies they are zero | Remove these fields and their checks; signatures remain mandatory |
| Length/offset consumers | Verifiers, symbolic dispatch, residual builder/ABC emission, optimizer relocation and disassembly consume old lengths | Decode declared layouts, including complete EXT instructions; regenerate every code-relative offset |
| Mutable execution copy | `src/vm.c` allocates/copies/frees `image->code`; interpreter `abc_run` executes it | Interpreter reads immutable module code directly; remove execution-copy ownership once no bytecode writer remains |
| Interpreter statistics | `src/vm.c` determines generic/specific/final by reading rewritten opcodes | Read the shared site records instead |
| Native observation | `src/residualize.c` keeps separate phase/observed fields, six phase-specific call/tail helpers, ICPatch registries and `ic_rewrite()` | Bind to the same VM-local site state; remove phase patch registries, not native code generation/linkage in general |
| Native statistics | `src/residualize.c` / `src/residualize.h` maintain native-owned observing counters/state | Report from the VM/module observation owner rather than duplicating history |
| Persistent tooling boundary | `src/residual_builder.c` rejects rewritten opcodes; generators/verifiers distinguish K_INTERNAL | Retire obsolete internal-bytecode paths, without weakening normal format verification |
| Validation assumptions | `tools/validate_cache.c` mentions post-RET quickening; opcode coverage skips INTERNAL; API tests inspect site statistics | Keep repeated-call/capture/statistics contracts; remove assumptions that execution rewrites instructions |

FCALL currently binds bridge shapes at VM/module load and synchronizes at its foreign boundary; there is no active FCALL opcode quickening to preserve. EXT has no active typed selector implementation at this checkpoint. Existing cache-state dispatch tables are not quickening and remain the interpreter's fast mechanism.

## Minimal shared observation binding

This is the concrete execution representation of the already specified original-PC site lifecycle, not a new inference engine:

- The immutable module retains its sorted indirect-site signatures, indexed by original PC.
- Each VM/module image owns one zero-initialized observation word per signature/site.
- Word 0 means unseen; UINT32_MAX means final generic; word `function_index + 1` means the validated monomorphic function. The existing function-count limit keeps these encodings disjoint.
- The module/signature supplies the identity and ABI context. No second opcode, shape descriptor or separately allocated target object is needed.
- One checked resolver owns target identity, ABI checks and unseen/monomorphic/final transitions. Interpreter and native bindings use it; a native binding may consume its validated function index to obtain a native entry, but the resolver never executes ABC.
- An invalid first target leaves zero unchanged. A monomorphic mismatch writes final generic and records the transition before validating the new target. A matching monomorphic target reuses its site-specific ABI validation. Final generic validates every target.
- Statistics count these words and the owner's transitions, not mutable instruction bytes or native patch-point phases.
- Native code refers to the record for the original instruction, including inline copies. It consults current state rather than relying on a frozen phase-specific helper entrance. Program-proven direct calls need no fabricated observation.

The exact lookup optimization from interpreter PC to the existing signature index is an execution detail, not a reason to add a serialized cache/site operand. Native bindings can patch the address of the record they already know. There is no concurrent-VM execution requirement and no lock protocol to introduce.

Remove the old native phase patch registry when replacing its ownership; do not leave it beneath a shared-state facade. Ordinary native relocation, lazy entry linking and executable-code publication remain separate responsibilities and are not removed by this change.

## Target identity correction required by the approved ISA

The audit confirms existing native drift: `ic_validate()` accepts function indices, raw entry offsets, native entry addresses and public bytecode-entry identities, while the interpreter accepts exact module code-entry identities. `src/vm.c` also currently installs mode-dependent code-address relocations.

Revision 6 uses one public opaque identity, the exact module bytecode function-entry address, in every execution mode. Code-address relocations and the embedding API expose that identity. Native execution resolves it to a private native entry after validation; native entry pointers, small integers and offsets are not additional public representations. This replaces the old permissive rule rather than adapting all its representations.

This is already required by the approved ISA's exact same-module target rule, but must be implemented in producer/relocation, validation and native dispatch together. Known-function symbolic facts remain function identities; public pointer representation and native control-transfer labels must not be conflated.

## Call-control boundary to preserve during phase 3

The old native `ic_observe_call`, `ic_specific_call` and `ic_final_call` helpers directly invoke native ABC entries through host calls. The raw-target resolver path and explicit continuation primitives also exist. Porting the six old helpers to a selected-bank parameter would preserve the wrong orchestration.

Replace that path with resolve/validate, argument transport, explicit continuation establishment and transfer. Tail calls retain the inherited continuation. The resolver returns linkage information only. This follows the approved call contract; it is not approval of the separate experimental return-slot/C-base ABI or the broader caller-owned region redesign.

## Scope boundary

Included: the public symmetric ISA, immutable code, removal of internal quickening, one observation owner, exact target identities and correct selected-bank transport/control transfer.

Excluded: new region budgets, convergence algorithms, lazy bytecode execution, dynamic scalar execution, new GC policies, pressure-driven expression reordering and a replacement physical return ABI. If replacing the call bindings proves to require changing that physical ABI, stop and discuss it rather than adding a workaround.
