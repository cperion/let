# Rejected partial scalar sharing

This snapshot shared arithmetic/conversion recipes but retained independent
scalar orchestration in `gen/scalar_banked.lua` and `src/symbolic_scalar.inc`.
The interpreter also reselected the arithmetic opcode inside a generic scalar
operation routine. Passing differential tests did not make that the requested
one-computation design.

The replacement defines checks, branches, representation steps and typed
operations together in `gen/scalar_semantics.lua`. Concrete and symbolic files
bind those steps; they do not independently select EXT semantics. The archived
measurements are historical, not measurements of that replacement.
