# Fused native continuation baseline

Snapshots of `src/residualize.c` and `gen/stencils.lua` at `b84c37c`, before
splitting native frame transport from control transfer. These are reference
implementations, not build inputs or compatibility layers.

Consult `docs/spec.md`, “Calls / One primitive” (frame operation followed by jump), for
semantics. Preserve argument order, CALL.A/CALL.B result routing, explicit ABC
C-stack continuations, stack-capacity checks, host sentinel handling, and the
register-bearing symbolic context when porting behavior.
