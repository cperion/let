# Rejected native-only scalar refactor (working snapshot)

Snapshot of the uncommitted native-only implementation after `e723f1e`.
Its checks and scalar bodies lived in the native sink, leaving the banked
interpreter on the generic EXT boundary. This is archived as a refactoring
reference, not a completed engine-wide design or a supported implementation.

The replacement must put scalar semantics in the shared generation/execution
layer, retaining only representation placement and native control emission in
the native sink. No later allocator or residual-value IR is intended.
