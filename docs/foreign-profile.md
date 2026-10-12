# Foreign-call profile

Revision-6 **profile 4** extends the callable profile with typed, named host externs and selected `FCALL.A/B`. Profile and format revision are independent; old revision-4 modules reject. See [module-format.md](module-format.md) for exact serialization and [symmetric-isa.md](symmetric-isa.md) for instruction semantics.

## Module declarations

Assembly selects the profile and declares externs before functions:

```text
.profile foreign
.extern host_mix if f
.extern host_note i -
```

The arguments are listed in source order. Kind letters are `i` for an integer cell, `a` for a native address, and `f` for an IEEE-754 binary64 cell. `-` denotes no arguments or no result. An extern has at most six integer/address arguments, four float arguments, and zero or one result. `FCALL.X name` consumes the ordered declared argument vector from X and appends its result on X when one exists. The opposite stack's live prefix is preserved; there is no A-only repacking convention.

Revision 6/profile 4 contains the eight callable-profile sections plus section 9. The extern section is a u32 count followed by variable records: u8 argument count, u8 result count, u16 symbol-name bytes, argument kind bytes, result kind bytes, then the ASCII identifier. Serialized `FCALL.X` stores the extern's u16 table index: three bytes total, with no mutable cache field.

## Binding and execution

Bindings are VM-local and must be installed before any module is loaded:

```c
abc_vm_bind_foreign(vm, "host_mix",
                    (abc_foreign_address)host_mix, &error);
abc_vm_load(vm, module, &error);
```

`abc_vm_load` rejects a module if any named extern is unbound. Bindings cannot change after a module has been loaded into that VM. The host function's actual C signature must exactly match the module declaration. Integer cells use `uint64_t`, address cells use the platform's 64-bit integer/pointer argument class, and float cells use `double`. Results use the corresponding return class.

The build generates a finite C-ABI bridge for every permitted integer/float register shape. No compiler or dynamic symbol lookup runs while loading a module. `FCALL` is a full cache synchronization boundary in the interpreter. The native sink synchronizes required homes and emits the foreign boundary using the bound extern index and selected bank. Eager/lazy native preparation follows the chosen execution mode; the extern binding itself is resolved when the VM image is loaded. Neither mode rewrites FCALL bytecode.

Foreign calls are host effects: the host function is responsible for pointer validity, termination and side effects. The in-process staging service prohibits foreign execution; leaving externs unbound rejects preparation of a module that declares them. Supporting runtime foreign calls does not authorize compile-time host effects. Active API and optimizer tests exercise both banks, ordered arguments, live prefixes and single execution of effects; see `REFACTOR.md`.
