-- The C library the command-line host offers under the `c` namespace, so a Let program can call
-- libc with no hand-written host. Each entry states the Let signature the frontend checks and,
-- where a C integer is not `Int64`, the C prototype the emitter spells (§15.3).
--
-- `CString` is a borrowed `const char*`, a type of its own rather than `Text`: the two are not
-- the same thing, and `c.string`/`c.text` are the explicit crossings.
--
-- The set is deliberately small and sound at the Let type level: string and integer functions,
-- no variadic form (`printf`), and no raw pointer (`malloc`). Those need a surface this compiler
-- does not define yet, and inventing one here would be a language decision, not a vocabulary.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local int=B.Parameter(B.Int,A.Read)
local cstring=B.Parameter(B.CString,A.Read)

local function ordered(symbol,signature,c) return {symbol=symbol,phase='runtime',purity='ordered',signature=signature,c=c} end
local function pure(symbol,signature,c) return {symbol=symbol,phase='runtime',purity='pure',signature=signature,c=c} end

return {
    -- The explicit crossings between a Let Text and a borrowed C string.
    string={phase='runtime',conversion='cstring'},
    text={phase='runtime',conversion='ctext'},

    puts=ordered('puts',B.Signature(L{cstring},L{B.Int}),{result='int'}),
    putchar=ordered('putchar',B.Signature(L{int},L{B.Int}),{params={'int'},result='int'}),
    strlen=pure('strlen',B.Signature(L{cstring},L{B.Int}),{result='size_t'}),
    strcmp=pure('strcmp',B.Signature(L{cstring,cstring},L{B.Int}),{result='int'}),
    atoi=pure('atoi',B.Signature(L{cstring},L{B.Int}),{result='int'}),
    llabs=pure('llabs',B.Signature(L{int},L{B.Int}),{params={'long long'},result='long long'}),
    getenv=pure('getenv',B.Signature(L{cstring},L{B.CString})),
}
end
