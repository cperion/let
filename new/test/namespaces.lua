local H = ...
local Word = require("word")
local Model = require("word.model")
local IR = require("word.ir")

H.test("receiver-free namespaces execute, normalize and export without storage parameters", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/namespaces.lua")
    H.eq(s:value(m.functions.add(10, 20)), 30)
    H.eq(s:value(s:normalize(m.functions.add:of(10, 20))), 30)
    H.eq(s:value(s:normalize(m.functions.constant)), 30)
    H.eq(s:value(m.functions.sum(5)), 15)
    H.eq(s:value(s:normalize(m.functions.sum:of(5))), 15)
    H.eq(s:value(m.functions.triple(7)), 21); H.eq(s:value(m.functions.quintuple(7)), 35)
    H.eq(s:value(m.functions.twice(7)), 42); H.eq(s:value(m.functions.composed(7)), 56)
    local program = s:compile(m); assert(IR.verify(program))
    for _, fn in ipairs(program.functions) do H.eq(fn.receiver, nil) end
end)

H.test("namespaces still require real receivers when data inputs remain", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, read = word(Unit, function() return value end)}
        return {C = C, Fixed = C:of{value = 9}}
    ]])
    H.raises("reject", "missing-receiver", function() m.C.read(nil) end)
    H.eq(s:value(m.Fixed.read(nil)), 9); H.eq(s:value(m.Fixed{}.read(nil)), 9)
    H.eq(s:value(s:normalize(m.Fixed.read:of(nil))), 9)
    local apply = s.word(s.word(s.Unit), function(f) return f(nil) end)
    H.eq(s:value(apply(m.Fixed.read)), 9)
end)

H.test("readonly receiver normalization distinguishes snapshots and rejects writes", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, read = word(Unit, function() return value end),
            write = word(Unit, function() value = value + 1 end)}
        local Holder = word{c = C}
        return {a = Holder:of{c = {value = 7}}, b = Holder:of{c = {value = 11}}}
    ]])
    local a, b = m.a.c.read:of(nil), m.b.c.read:of(nil)
    H.eq(s:value(s:normalize(a)), 7); H.eq(s:value(s:normalize(b)), 11)
    local result = Model.word(a).result; H.eq(s:normalize(a), result)
    H.raises("reject", "static-field", function() s:normalize(m.a.c.write:of(nil)) end)
    H.eq(s._engine.scope:current(), nil); H.eq(s:value(s:normalize(a)), 7)
end)

H.test("namespace normalization cycles use semantic receiver keys, not selection identity", function()
    local s = Word.new(); local m = s:load_string([[
        local N = word{loop = word(function() return loop() end),
            value = word(function() return U32(7) end)}
        return {N = N}
    ]])
    H.raises("reject", "normalization-cycle", function() s:normalize(m.N.loop) end)
    H.eq(s._engine.scope:current(), nil); H.eq(s:value(s:normalize(m.N.value)), 7)
    assert(IR.verify(s:compile{functions = {loop = m.N.loop}, results = {[m.N.loop] = s.Unit}}))
end)

H.test("cached readonly method results recheck metadata inside their receiver snapshots", function()
    local s = Word.new(); local rate = 3
    local P = s.word{x = s.U32, helper = s.word(s.U32, function(n) return n + rate end)}
    local m = s:load_string([[return {C = word{T = Type, value = U32,
        read = word(Unit, function() return value end)}}]])
    local Holder = s.word{c = m.C}:of{c = {T = P, value = 7}}
    local read = Holder.c.read:of(nil)
    H.eq(s:value(s:normalize(read)), 7); assert(Model.word(read).result)
    rate = 4
    H.raises("reject", "capture-changed", function() s:normalize(read) end)
    rate = 3; H.eq(s:value(s:normalize(read)), 7)
end)

H.test("method definitions and readonly selections can pass through static factories", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, read = word(Unit, function() return value end)}
        local Fixed = C:of{value = 7}
        return {C = C, factory = word(function() return C.read end),
            fixed = word(function() return Fixed.read end),
            escape = word(U32, function(n) return Fixed.read end)}
    ]])
    local read = m.fixed(); H.eq(s:value(read(nil)), 7)
    local captured = s.word(s.Unit, function() return read(nil) end)
    H.eq(s:value(s:normalize(captured:of(nil))), 7)
    H.eq(Model.word(s:normalize(m.factory)).owner, Model.word(m.C.read).owner)
    H.raises("reject", "missing-receiver", function() s:type(m.C.read:of(nil)) end)
    assert(IR.verify(s:compile{functions = {escape = m.escape}}))
    assert(IR.verify(s:compile{functions = {factory = m.factory, fixed = m.fixed, captured = captured}}))
end)
