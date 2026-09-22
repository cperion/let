# Executable values: records own state, methods borrow

Return a stateful record, not detached methods that secretly own its receiver.

```lua
local make = word(U32, function(n) return Counter{value = n} end)
local c = make(10)
local next_value, read = c.next, c.read
next_value(nil)
read(nil) -- observes the same c
```

C returns an ordinary struct by value. Methods are static code with a typed receiver pointer.
There are no output-storage bundles, ownership graphs, implicit allocations or allocator arguments.
See `examples/stateful_objects.lua`.

## Value and borrowing rules

- Record construction, ordinary argument passing, assignment and returns keep their value-copy rules.
- Selecting a method borrows the receiver; it does not copy state. Copying the view preserves that borrow.
- Borrowed methods/callbacks can be called locally and passed to non-retaining callback parameters.
- They cannot be returned, including through tuples, or installed in record fields. Return the receiver instead.
- A closure capturing mutable storage or another borrowed callable is itself borrowed.
- Methods cannot hide mutable captures outside their record; put that state in the receiver's fields.
- Copying a record creates independent data. Existing method views still refer to the original record.

These are language restrictions, enforced during evaluation as well as C compilation. They are not
temporary gaps to be filled by allocation. There is no general lifetime-parameter or owner-handle syntax.

## Code and ABI

Known executable arguments remain known and calls inline or lower to direct calls. Concrete executable
types carry code identity statically. Capture-free executable results therefore need no environment
pointer or dynamic dispatch.

Genuinely unknown runtime code uses a signature-specific function pointer and borrowed environment pointer.
Its implementation must not retain borrowed inputs, whether by returning them or storing them. Foreign C
implementations must honor the same contract and supply live environment storage for the call.

Opaque signatures do not prove ownership: symbols with those types are conservatively borrowed, including
inside aggregates. They can be consumed or forwarded to another non-retaining call, not repackaged into
escaping results. Concrete immutable executable values are a different case.

## Compiler checks

`word/borrow.lua` checks the non-retaining rules; it does not plan storage or infer owners. The C emitter
rechecks typed IR before emission. Tail-call rewriting is disabled when arguments may borrow the current
activation. Ordinary scalar/record recursion and same-receiver method recursion retain their existing ABI.

## Immutable capture conversion

Immutable closures carry typed environments by value. Scalar captures and owned callable captures
become ordinary fields; known static metadata stays in the code template. Captured bindings cannot be
reassigned. Record methods require static captures; runtime state belongs in explicit receiver fields.

`word/closure.lua` separates compilation-local code templates from fresh capture values. A fresh Lua
terminal is cloned from its bytecode and rebound for each trace invocation; source upvalues and function
environments are never changed. This is ordinary Lua function cloning, not bytecode translation.

Only mutually recursive code links share a capture schema. Those links are static metadata, not runtime
self-pointers. Acyclic captured functions are by-value fields, so known and outlined results have the same
representation. Replay remaps both closure receivers and indirect-call operands.

No runtime symbols may enter static specialization or cached schema/method metadata. The captured
values themselves live only in the current trace's environment construction.

## Lexical receiver plus immutable captures

A locally constructed word can use both lexical receiver fields and immutable snapshots of values.
Its outlined function receives the borrowed receiver pointer and a separate by-value capture record.
Recursive/sibling code links share static templates; each invocation carries fresh capture values.
Snapshots remain unchanged when the receiver mutates. Capture bindings themselves remain immutable.

A non-retaining callback interface can invoke such a word through a caller-local bundle containing
its receiver pointer and copied captures. That bundle is borrowed, cannot escape and needs no allocator.
Tail rewriting preserves the receiver and snapshots all next inputs, including the capture record.

An immutable lexical receiver is different: it can remain checked static metadata while the captured
runtime values form an ordinary owned environment. Such closures can escape, including through nested
factories. See `examples/lexical_captures.lua` and `test/lexical_captures.lua`.

Additional borrowed captures (for example, a runtime callback captured alongside the receiver) still
need a non-retaining outlined environment representation. They can inline but do not become ordinary
retaining record fields; the remaining `staged-definitions` witness covers this boundary.

See `examples/immutable_closures.lua`. C exposes `wordresult_make` and `wordcall_make` for a factory named
`make`; nested callable results get `wordresult_call_make` and `wordcall_make_result`. The type-specific
`wordcalltype_*` helpers also provide direct invocation without a universal function-pointer ABI.
