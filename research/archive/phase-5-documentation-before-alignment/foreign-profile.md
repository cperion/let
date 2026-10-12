# Foreign-call profile

ABC2 version 4 extends the callable profile with typed, named host externs and the `FCALL` instruction.

## Module declarations

Assembly selects the profile and declares externs before functions:

```text
.profile foreign
.extern host_mix if f
.extern host_note i -
```

The arguments are listed in source order. Kind letters are `i` for an integer cell, `a` for a native address, and `f` for an IEEE-754 binary64 cell. `-` denotes no arguments or no result. An extern has at most six integer/address arguments, four float arguments, and zero or one result. `FCALL name` consumes the declared arguments from A and pushes the result on A when one exists.

Version 4 contains the eight callable-profile sections plus section 9. The extern section is a u32 count followed by variable records: u8 argument count, u8 result count, u16 symbol-name bytes, argument kind bytes, result kind bytes, then the ASCII identifier. Serialized `FCALL` stores the extern's u16 table index.

## Binding and execution

Bindings are VM-local and must be installed before any module is loaded:

```c
abc_vm_bind_foreign(vm, "host_mix",
                    (abc_foreign_address)host_mix, &error);
abc_vm_load(vm, module, &error);
```

`abc_vm_load` rejects a module if any named extern is unbound. Bindings cannot change after a module has been loaded into that VM. The host function's actual C signature must exactly match the module declaration. Integer cells use `uint64_t`, address cells use the platform's 64-bit integer/pointer argument class, and float cells use `double`. Results use the corresponding return class.

The build generates a finite C-ABI bridge for every permitted integer/float register shape. No compiler or dynamic symbol lookup runs while loading a module. `FCALL` is a full cache synchronization boundary in the interpreter. The compiled tier flushes symbolic homes and emits an eager helper stencil with the extern descriptor and VM-local target patched at load.

Foreign calls are host effects: the host function is responsible for pointer validity, termination and side effects. A static evaluator must reject or leave externs unbound rather than execute `FCALL`.
