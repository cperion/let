local H = ...
local Word = require("word")
local Model = require("word.model")
local IR = require("word.ir")

H.test("keyed static supply removes inputs without mutating the original", function()
    local s = Word.new(); local P = s.word{x = s.U32, y = s.U32}
    local supply = {y = 0}; local X = P:of(supply); supply.y = 9
    local p = X{x = 3}; local original = P{x = 2, y = 4}
    H.eq(s:value(p.y), 0); H.eq(s:value(X.y), 0); H.eq(P.y, s.U32)
    original.y = 8; p.x = 10
    H.eq(s:value(original.y), 8); H.eq(s:value(p.x), 10)
    H.raises("reject", "static-field", function() p.y = 0 end)
    H.raises("reject", "static-field", function() X{x = 3, y = 0} end)
    H.raises("reject", "missing-field", function() X{} end)
end)

H.test("keyed specialization composes and canonicalizes static knowledge", function()
    local s = Word.new(); local P = s.word{x = s.U32, y = s.U32, flag = s.Bool}
    local a = P:of{y = 0}:of{flag = false}
    local b = P:of{flag = false, y = s.U32(0)}
    H.eq(a, b); H.eq(a:of{y = 0}, a); H.eq(a:of{}, a)
    H.eq(a, s.word{flag = s.Bool, y = s.U32, x = s.U32}:of{y = 0, flag = false})
    assert(a ~= P:of{y = 1, flag = false})
    assert(a ~= P:of{y = 0, flag = true})
    H.raises("reject", "static-conflict", function() a:of{y = 1} end)
    H.raises("reject", "unknown-field", function() P:of{z = 0} end)
    H.raises("reject", "keyed-supply", function() P:of(0) end)
    H.raises("reject", "keyed-supply", function() P:of({}, {}) end)
    H.raises("reject", "type", function() P:of{y = false} end)
end)

H.test("static Type Bool and Unit fields remain visible without runtime slots", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/specialized.lua")
    local Config = m.types.Config; local c = Config{}
    H.eq(c.element, s.U32); H.eq(s:value(c.enabled), false); H.eq(s:value(c.marker), nil)
    H.eq(s:value(m.functions.configured(c, 5)), 12)
    local snapshot = s:value(c)
    H.eq(snapshot.element, s.U32); H.eq(snapshot.enabled, false); H.eq(snapshot.bias, 7)
    H.eq(#Model.record(Config).runtime_order, 0)
    H.raises("reject", "static-field", function() c.marker = s.Unit() end)
    local U32 = s.U32; local Alias = s.word(function() return U32 end)
    local T = s.word{element = s.Type}
    H.eq(T:of{element = Alias}, T:of{element = U32})
end)

H.test("nested value boundaries preserve static fields and type identity", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/specialized.lua")
    local X, Box = m.types.XAxis, m.types.Box
    local b = Box{point = X{x = 4}}; local p = m.functions.nested(b)
    H.eq(s:value(p.x), 5); H.eq(s:value(p.y), 0); H.eq(s:value(b.point.x), 4)
    local snapshot = s:value(b); H.eq(snapshot.point.y, 0)
    local other = s.word{x = s.U32, y = s.U32}:of{y = 1}
    H.raises("reject", "type", function() b.point = other{x = 8} end)
    H.eq(s:value(m.functions.local_specialization(10)), 13)
end)

H.test("keyed supply forwards through static factories", function()
    local s = Word.new(); local m = s:load_string([[
        local Pair = word(Type, Type, function(A, B) return word{first = A, second = B} end)
        local P = Pair:of(U32, Bool):of{first = 7}
        return {P = P, get = word(P, function(p) return p.first end)}
    ]])
    local p = m.P{second = false}
    H.eq(s:value(p.first), 7); H.eq(s:value(p.second), false)
    H.eq(s:value(m.get(p)), 7)
    assert(IR.verify(s:compile{functions = {get = m.get}}))
end)

H.test("keyed supply rejects runtime and foreign values without leaking context", function()
    local s = Word.new(); local P = s.word{x = s.U32}; local R = s.word{child = P}
    H.raises("reject", "static-required", function() R:of{child = P{x = 1}} end)
    local foreign = Word.new()
    H.raises("reject", "foreign-session", function() P:of{x = foreign.U32(1)} end)
    local bad = s.word(s.U32, function(x) return P:of{x = x}{} end)
    H.raises("reject", "static-required", function() s:compile{functions = {bad = bad}} end)
    H.eq(s._engine.scope:current(), nil)
    local good = s.word(s.U32, function(x) local Q = P:of{x = 7}; return x + Q.x end)
    assert(IR.verify(s:compile{functions = {good = good}}))
end)

H.test("computed keyed specialization retains canonical bindings", function()
    local s = Word.new(); local U32 = s.U32
    local P = s.word{x = U32, y = U32}
    local computed = s.word(function()
        local total = 0; for _ = 1, 10000 do total = total + 1 end
        return U32(total)
    end)
    local Q = P:of{x = computed, y = 0}
    H.eq(s:value(Q.x), 10000); H.eq(s:value(Q{}.y), 0); H.eq(P.x, U32)
    H.eq(Q, P:of{x = 10000, y = 0})
    H.eq(s._engine.scope:current(), nil)
end)

H.test("erased Type knowledge does not require a runtime representation", function()
    local s = Word.new(); local T = s.word{element = s.Type}:of{element = s.Type}
    H.eq(T{}.element, s.Type)
    assert(IR.verify(s:compile{types = {Meta = T}}))
    assert(not s:emit_c{types = {Meta = T}}:find("f_element", 1, true))
end)

H.test("IR cannot construct or load a statically bound field", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/specialized.lua")
    local program = s:compile{functions = {sum = m.functions.sum}}
    for _, ins in ipairs(program.functions[1].blocks[1].instructions) do
        if ins.op == "Load" then ins.path = {"y"}; break end
    end
    H.raises("bug", "invalid-ir", function() IR.verify(program) end)
    program = s:compile{functions = {make = m.functions.make}}
    for _, ins in ipairs(program.functions[1].blocks[1].instructions) do
        if ins.op == "Construct" then ins.fields.y = ins.fields.x; break end
    end
    H.raises("bug", "invalid-ir", function() IR.verify(program) end)
end)
