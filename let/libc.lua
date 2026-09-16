-- The C library the command-line host offers under the `c` namespace, so a Let program can call
-- libc with no hand-written host. Each entry states the Let signature the frontend checks, the C
-- prototype the emitter spells where a C type is not the Let type's natural mapping (§15.3), and
-- the ownership and nullability the boundary declares (spec §12.4).
--
-- `CString` is a borrowed `const char*` and `CPointer` an opaque `void*`; both are types of their
-- own rather than `Text`, and `c.string` / `c.text` are the explicit crossings.
--
-- Owned C memory is a `resource` whose C representation is a pointer (`CAlloc`), so Let owns it
-- and destroys it exactly once with `free`; there is no `c.free` to call. A foreign call that
-- mutates the bytes behind the pointer does so outside Let's invariants, which is why those calls
-- are `ordered`.
--
-- The set is deliberately small and sound at the Let type level: string, integer and byte
-- functions, no variadic form (`printf`), and no dereference or pointer arithmetic. Those need a
-- surface the specification does not define yet, and inventing one here would be a language
-- decision, not a vocabulary.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local int=B.Parameter(B.Int,A.Read)
local cstring=B.Parameter(B.CString,A.Read)
local allocation=B.Parameter(B.Named('CAlloc'),A.Read)

local function word(symbol,purity,signature,extra)
    local descriptor={symbol=symbol,phase='runtime',purity=purity,signature=signature}
    for key,value in pairs(extra or {}) do descriptor[key]=value end
    return descriptor
end
local function ordered(symbol,signature,extra) return word(symbol,'ordered',signature,extra) end
local function pure(symbol,signature,extra) return word(symbol,'pure',signature,extra) end

return {
    -- A pointer-shaped resource: owned by Let, destroyed by `free`, never dereferenced by Let.
    resources={CAlloc={destroy='free',representation='pointer'}},
    members={
        -- The explicit crossings between a Let Text and a borrowed C string.
        string={phase='runtime',conversion='cstring'},
        text={phase='runtime',conversion='ctext'},
        -- The byte length of a Text, and a null test for a borrowed pointer.
        byte_length={phase='runtime',conversion='byte_length'},
        null={phase='runtime',conversion='null'},
        -- A Text view over a borrowed pointer and a length, so a read buffer becomes a Text.
        text_of={phase='runtime',conversion='text_of'},

        puts=ordered('puts',B.Signature(L{cstring},L{B.Int}),{c={result='int'}}),
        putchar=ordered('putchar',B.Signature(L{int},L{B.Int}),{c={params={'int'},result='int'}}),
        strlen=pure('strlen',B.Signature(L{cstring},L{B.Int}),{c={result='size_t'}}),
        strcmp=pure('strcmp',B.Signature(L{cstring,cstring},L{B.Int}),{c={result='int'}}),
        atoi=pure('atoi',B.Signature(L{cstring},L{B.Int}),{c={result='int'}}),
        llabs=pure('llabs',B.Signature(L{int},L{B.Int}),{c={params={'long long'},result='long long'}}),
        getenv=pure('getenv',B.Signature(L{cstring},L{B.CString}),
            {c={result='char *'},ownership='borrowed',nullable=true}),

        -- C memory. The allocation is the owner; `memset`/`memcpy`/`memcmp` borrow it.
        malloc=ordered('malloc',B.Signature(L{int},L{B.Named('CAlloc')}),
            {c={params={'size_t'},result='void *'}}),
        memset=ordered('memset',B.Signature(L{allocation,int,int},L{B.CPointer}),
            {c={params={'void *','int','size_t'},result='void *'}}),
        memcpy=ordered('memcpy',B.Signature(L{allocation,cstring,int},L{B.CPointer}),
            {c={params={'void *','const void *','size_t'},result='void *'}}),
        memcmp=pure('memcmp',B.Signature(L{allocation,cstring,int},L{B.Int}),
            {c={params={'const void *','const void *','size_t'},result='int'}}),
        -- A file descriptor reads into an owned allocation and writes a borrowed Text view; the
        -- count comes from `c.byte_length`, so no terminator is assumed.
        write=ordered('write',B.Signature(L{int,cstring,int},L{B.Int}),
            {c={params={'int','const void *','size_t'},result='long'}}),
        -- Byte and binary32 buffers: `CAlloc` is the owned buffer, the index is a runtime Int,
        -- and the emitter supplies these helpers, so no external runtime is needed. A read is
        -- ordered because the bytes behind the pointer can change between calls.
        load_byte=ordered('let_load_byte',B.Signature(L{allocation,int},L{B.Int}),
            {c={params={'void *','int64_t'},result='int64_t'},helper='buffer'}),
        store_byte=ordered('let_store_byte',B.Signature(L{allocation,int,int},L{B.Unit}),
            {c={params={'void *','int64_t','int64_t'},result='void'},helper='buffer'}),
        load_f32=ordered('let_load_f32',B.Signature(L{allocation,int},L{B.Float32}),
            {c={params={'void *','int64_t'},result='float'},helper='buffer'}),
        store_f32=ordered('let_store_f32',B.Signature(L{allocation,int,B.Parameter(B.Float32,A.Read)},L{B.Unit}),
            {c={params={'void *','int64_t','float'},result='void'},helper='buffer'}),
        read=ordered('read',B.Signature(L{int,allocation,int},L{B.Int}),
            {c={params={'int','void *','size_t'},result='long'}}),
    },
}
end
