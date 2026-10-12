# Arity-directed application experiment

**Isolated experiment, not approved production syntax.** No production parser,
compiler, VM or Makefile changed. This tests a supplied-signature parser against
concrete examples before deciding whether signature-aware parsing belongs in Let.
No source type inference, import resolution or assembler builder is implemented here.

## Run

From repository root, with the existing runtime/frontend build available:

```sh
/tmp/lua-compat research/experiments/arity-application/run.lua
```

The probe uses the production lexer and a hand-supplied signature environment.
The test runner checks exact parenthesized output and passes supported scalar outputs
to the actual compiler/staging service under interpreted/threaded/eager/lazy modes.
Lua performs syntax manipulation, not evaluation of source values.

Recorded result: **40 parsing/ambiguity checks, 20 production VM executions and one
explicitly recorded frontend limitation**. Raw results in `evidence/results.log`;
the discovery failure is preserved separately. No broad suite or benchmark was run.
The successful raw run originated at `/tmp/let-arity-probe.d69kHU/results.log`.

## Candidate tested

- Fixed statically supplied ordered arities; source expressions, not result cells,
  determine how many operands a bare application consumes.
- Bare application saturates, without comma-separated arguments or implicit partials.
- Nested bare application binds tighter than infix, including power.
- Each bare argument is scalar-adjusted, including the final argument; explicit calls
  retain their existing result forwarding contract.
- Explicit parentheses take precedence regardless of whitespace. No callable-value
  invocation is inferred from a nullary name.
- A final `do` block supplies the final callable requirement. Blocks are emitted as
  explicit lambdas; `return` remains local. Explicit unit returns are retained.
- Newlines are ignored. Semicolons establish explicit statement boundaries.
- Unknown/dynamic/rest/keyed callees have no bare-call interface and need delimiters.

The probe additionally rejects a **first unary bare operand** to expose the conflict
with subtraction/xor instead of deciding silently. For example, use `double(-3)`;
`add 1 -2` has an already-started two-operand supply and parses as `add(1,-2)`.
This is an experimental restriction, not an accepted addition to syntax.md.

## Useful shapes

```text
add double 3 4     -> add((double((3))), (4))
double 3 + 4       -> double(3) + 4
add 1 2 * 3        -> add(1,2) * 3
```

The extra parentheses in actual output explicitly request scalar adjustment.

Builder-shaped input:

```let
m.function 1 1 do |f|
  f.b.cget 0
  f.b.muli 2
  f.b.ret 1 1
  return
end
```

This produces ordinary explicit applications and a lambda. `m.function` and `f.b.*`
signatures are fixture-supplied, not inferred. This is a parse/desugaring result,
not execution of an implemented assembler library.

## Findings that constrain the language decision

### 1. Signature changes can silently change statement grouping

```let
send item
finish()
```

With send arity one: `send(item); finish()`.
With send arity two: `send(item, finish())`.

The probe demonstrates both. A semicolon makes the arity-two form reject rather
than swallowing the next statement. Newline-insensitive arity parsing cannot promise
that every signature change causing regrouping is a diagnostic.

### 2. Existing explicit-call syntax makes grouped bare operands awkward

`add (1 + 2) 3` starts with an explicit partial application and then has surplus text.
Even `add 1 (double)` treats `1(double)` as a syntactic call before semantic checking,
then lacks the second add operand. A whitespace-insensitive grammar cannot turn
those parentheses into argument grouping selectively without another rule.

Use `add(1 + 2, 3)` and explicit higher-order calls. `apply double 3` attempts a
nested saturated double call and then lacks apply's second argument. Nullary word
values remain passable: `apply work 3` is syntactically `apply(work,3)`.

### 3. Scalar-result adjustment is not fully supported by the current frontend

The proposal renders `take pair()` as `take((pair()))` to select the first of pair's
results. Current production semantic construction rejects this with `result-arity`.
The production parser also erases ordinary grouping nodes, so printing parentheses
alone is not a complete implementation strategy for the target adjustment contract.

The runner records this limitation rather than bypassing it or claiming it executed.
F05 needs explicit scalar/result-adjustment representation/handling independent of
whether bare syntax is ultimately adopted. The other five scalar examples execute
in four modes and produce independently specified expected numbers.

### 4. Signature discovery remains untested

No header prepass, schema method lookup, forward-reference resolution, source import
loading or incremental tooling strategy is established. Bare locals do not infer
callable interfaces from their initializer in this experiment. Block fixture receiver
paths are predeclared externally; they are not evidence of sound lexical/schema
resolution. No parsing relies on running a callee or inspecting a runtime value.

## Deliberate scope limits

The parser covers numeric/bool/reference expressions, fixed calls, selected operators,
single local bindings, call/return statements and simple block parameters. It rejects
text literals, schemas, arrays, spread and unsupported syntax rather than pretending
to be a second complete Let parser. It does not check ordinary call arities/types,
return reachability or group ownership; production compilation checks only the emitted
scalar fixtures. Operator precedence is copied only for this experiment, not a new
authoritative language table.

## Next decision

Review whether builder convenience justifies signature-sensitive parsing plus the
explicit-call/first-unary restrictions and statement-boundary hazard. If proceeding,
approve signature discovery, scalar-adjustment AST representation and declaration
compatibility policy before production implementation. Do not add this experiment to
the main test suite or target grammar merely because its selected cases pass.
