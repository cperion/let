-- The C library the command-line host offers under the `c` namespace, so a Let program can call
-- libc with no hand-written host. Each entry states the Let signature the frontend checks, the C
-- prototype the emitter spells where a C type is not the Let type's natural mapping (§15.3), and
-- the ownership and nullability the boundary declares (spec §12.4).
--
-- `CString` is a borrowed `const char*` and `CPointer` an opaque `void*`; both are types of their
-- own rather than `Text`, and `c.string` / `c.text` are the explicit crossings.
--
-- The set is deliberately small and sound at the Let type level: string, integer and byte
-- functions, no variadic form (`printf`), and no dereference or pointer arithmetic. Those need a
-- surface the specification does not define yet, and inventing one here would be a language
-- decision, not a vocabulary.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local int=B.Parameter(B.Int,A.Read)
local cstring=B.Parameter(B.CString,A.Read)
local cpointer=B.Parameter(B.CPointer,A.Read)

local function word(symbol,purity,signature,extra)
    local descriptor={symbol=symbol,phase='runtime',purity=purity,signature=signature}
    for key,value in pairs(extra or {}) do descriptor[key]=value end
    return descriptor
end
local function ordered(symbol,signature,extra) return word(symbol,'ordered',signature,extra) end
local function pure(symbol,signature,extra) return word(symbol,'pure',signature,extra) end

return {
    -- The explicit crossings between a Let Text and a borrowed C string, and an opaque pointer.
    string={phase='runtime',conversion='cstring'},
    text={phase='runtime',conversion='ctext'},

    puts=ordered('puts',B.Signature(L{cstring},L{B.Int}),{c={result='int'}}),
    putchar=ordered('putchar',B.Signature(L{int},L{B.Int}),{c={params={'int'},result='int'}}),
    strlen=pure('strlen',B.Signature(L{cstring},L{B.Int}),{c={result='size_t'}}),
    strcmp=pure('strcmp',B.Signature(L{cstring,cstring},L{B.Int}),{c={result='int'}}),
    atoi=pure('atoi',B.Signature(L{cstring},L{B.Int}),{c={result='int'}}),
    llabs=pure('llabs',B.Signature(L{int},L{B.Int}),{c={params={'long long'},result='long long'}}),
    getenv=pure('getenv',B.Signature(L{cstring},L{B.CString}),{ownership='borrowed',nullable=true}),

    -- C memory. Let never dereferences a `CPointer`, so the result of `malloc` is released by an
    -- explicit `free`; the ownership call is the program's, exactly as in C.
    malloc=ordered('malloc',B.Signature(L{int},L{B.CPointer}),
        {c={params={'size_t'},result='void *'},ownership='owned'}),
    free=ordered('free',B.Signature(L{cpointer},L{B.Unit}),
        {c={params={'void *'},result='void'}}),
    memcpy=ordered('memcpy',B.Signature(L{cpointer,cstring,int},L{B.CPointer}),
        {c={params={'void *','const void *','size_t'},result='void *'}}),
    memset=ordered('memset',B.Signature(L{cpointer,int,int},L{B.CPointer}),
        {c={params={'void *','int','size_t'},result='void *'}}),
    memcmp=pure('memcmp',B.Signature(L{cpointer,cstring,int},L{B.Int}),
        {c={params={'const void *','const void *','size_t'},result='int'}}),
}
end
