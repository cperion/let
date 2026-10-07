# Continuation-directed compiler lowering

The compiler rule is:

> Compile every expression with an explicit continuation. A call that receives the current continuation unchanged is a tail call; otherwise, save the remaining continuation and transfer to the callee.

> Do not special-case recursion.

This is a frontend/compiler design note. It does not change the VM instruction semantics or make source-language policy part of the VM.

## Continuation-directed lowering

Conceptually:

```text
compile(expression, continuation)
```

A normal operation:

```text
compile(x + y, K)
```

becomes:

```text
compile(x, λa.
    compile(y, λb.
        K(a + b)))
```

A call:

```text
compile(f(x), K)
```

becomes:

```text
evaluate x
transfer to f with continuation K
```

The transfer depends only on `K`:

- If `K` is the function's existing return continuation, emit `TCALL`.
- If `K` contains remaining work, emit `CALL`; that remaining work becomes the return continuation.
- If `K` is statically known and bounded, the residualizer can make it a virtual continuation.
- If it is recursive or runtime-selected, it becomes a C-stack continuation.

Recursion needs no special language rule. A recursive transfer points back to an existing function entry and produces a CFG cycle.

## Examples

### Tail recursion

```text
return f(n - 1)
```

The callee receives the current continuation unchanged:

```text
evaluate n - 1
TCALL f
```

This works equally for mutual recursion:

```text
even → odd → even
```

No SCC-specific source rewrite is necessary.

### Non-tail recursion

```text
return f(n - 1) + 1
```

The continuation contains work:

```text
K1(result) = return result + 1
```

Therefore:

```text
push K1
CALL f
```

After defunctionalization, `K1` is a block label plus its live values.

### Fibonacci

```text
fib(n - 1) + fib(n - 2)
```

becomes conceptually:

```text
push AfterFirst(n)
transfer fib(n - 1)

AfterFirst(a, n):
    push AfterSecond(a)
    transfer fib(n - 2)

AfterSecond(a, b):
    return a + b
```

Defunctionalizing these continuations produces the VM's C-stack continuation loop.

## Compiler pipeline

1. **ANF/SSA normalization.** Make evaluation order and intermediate values explicit.
2. **Continuation-directed lowering.** Lower expressions under their destination and continuation.
3. **Defunctionalization.** Replace known continuation functions with block labels and explicit live fields.
4. **Tail-transfer selection.** An unchanged continuation becomes `TCALL`; a new continuation becomes `CALL`.
5. **Ordinary CFG optimization.** Backedges, joins, dead values, constants and loops require no recursion-specific treatment.
6. **ABC optimization.** After ordinary verified bytecode exists, standalone C `abc-opt` can virtually inline fact-approved acyclic calls, symbolically residualize them and canonically re-project the residual DAG onto A/B/C. This does not revisit tailness.

The compiler does not ask:

```text
Is this function recursive?
```

It asks:

```text
Is there any work after this call?
```

That local rule handles self recursion, mutual recursion and ordinary calls.

## Tail calls modulo accumulation

Matching Clang's Fibonacci accumulator loop requires an additional, narrower rule: **tail call modulo a proven monoid operation**.

For modular integer addition, addition is pure and associative and zero is its identity. Reassociation preserves semantics, so:

```text
fib(n - 1) + fib(n - 2)
```

can become:

```text
acc = 0
loop:
    if n < 2:
        return acc + n
    acc += fib(n - 1)
    n -= 2
    goto loop
```

This transformation is not generally valid:

- Floating-point addition is not associative.
- Checked arithmetic can change which operation traps first.
- Dynamic `+` can dispatch or reject operand combinations.
- Effectful calls constrain evaluation order.

Continuation-directed lowering is the general rule. Accumulator formation is an optional simplification when the pending continuation is a provably pure associative accumulation.

For the production IR, the function-level `tailCalls()` prepass must not drive lowering. Tailness must follow locally from lowering each `Ir.Call` under its actual continuation. Call-graph SCCs belong only to the later `abc-opt` inlining safety decision.

The JIT does not perform ABC re-projection. It consumes verified ABC directly, whether or not a build-time producer previously ran `abc-opt`, and sends symbolic residual operations to register-addressed stencils while preserving block-version context.
