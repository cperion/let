# Loaded module-image copy API

**Working-tree implementation; bounded staging qualification, not an ownership API.**
The current aggregate/access batch remains incomplete; see
[its evidence and higher-order blocker](../research/experiments/frontend-syntax/module-aggregate-access/README.md).

```c
abc_status abc_vm_read_image(
    const abc_vm *vm, const abc_module *module,
    size_t offset, void *output, size_t size, abc_error *error);
```

Copies `size` bytes at the module-image-relative `offset` from that module identity's
already loaded persistent image in `vm`. It does not execute code, implicitly load
an image, retain an output owner, relocate addresses or synchronize concurrent access.
The caller supplies valid live handles and writable, nonoverlapping output storage,
and serializes copying with VM execution/image mutation. `error` may be null.

- `ABC_OK`: bytes copied; zero length allows null output and offset at image end.
- `ABC_INVALID`: null VM/module, or null output with nonzero size.
- `ABC_ARGUMENTS`: offset/size outside the module image; checks avoid addition overflow.
- `ABC_NOT_FOUND`: no image for that module identity is loaded in this VM.

Input and extent checks precede image lookup/copy. On failure, destination bytes
remain unchanged; `error` is cleared/set normally. This API does not roll back writes
made by an earlier aborted VM call. Plain copies are not atomic snapshots.

## Bounded compiler use

`frontend/let/layout.lua` defines the existing layouts and cell ABI shared with
lowering. `snapshot.lua` transports supported pointer-free fixed-layout records, arrays and
sums, preserving typed integer and IEEE-754 bits rather than converting source values.
`stage.lua` returns raw `cells`, typed `values` and accepted `moduleData` byte images.
Aggregate handles have `{type=Ty, image=bytes}`; specialization materializes checked
`Ir.Bytes` through the existing backend. Scalar transport remains compatible.

A compilation demand copies module-root extents only after successful VM execution
and typed result transport. The compilation session publishes accepted compiler-owned
bytes after all copies succeed, then residual lowering places those bytes in the
ordinary data/rodata image. Returned bytes survive VM/session teardown.

Address-bearing records, refs, slices and callable environments are not snapshot
transport. Copying pointer bits would not establish lifetime or relocation. This
boundary adds no counted/frozen owners, release machinery, revision-6 encoding change
or runtime dependency on `abc-opt`. Exact floating-payload tagged-byte copying also
does not resolve the separate packed float extraction/arithmetic bug.

`tools/validate_api.c` checks this C contract in all four execution modes.
`frontend/tests/aggregate_staging.lua` checks typed roundtrips, persistent roots,
initializer state, imports, repeated requests and selected failure boundaries.
Full validation passes, but higher-order retention proof remains an explicit blocker.
