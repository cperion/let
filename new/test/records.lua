local H = ...
local Word = require("word")
local Model = require("word.model")
local IR = require("word.ir")

H.test("keyed construction validates fields and snapshots scalar reads", function()
    local s = Word.new(); local P = s.word{x = s.U32, enabled = s.Bool}
    local p = P{x = 1, enabled = false}
    local old, alias = p.x, p
    p.x = 9
    H.eq(s:value(old), 1); H.eq(s:value(alias.x), 9); H.eq(s:value(p.enabled), false)
    local snapshot = s:value(p); snapshot.x = 99
    H.eq(s:value(p.x), 9)
    H.raises("reject", "missing-field", function() P{x = 1} end)
    H.raises("reject", "unknown-field", function() P{x = 1, enabled = false, z = 2} end)
    H.raises("reject", "type", function() p.x = false end)
    H.raises("reject", "unknown-field", function() p.z = 1 end)
    H.raises("reject", "keyed-supply", function() P(p) end)
end)

H.test("nested fields are copied by value but field aliases retain their place", function()
    local s = Word.new(); local P = s.word{x = s.U32}; local R = s.word{a = P, b = P}
    local source = P{x = 1}; local r = R{a = source, b = source}
    source.x = 10
    H.eq(s:value(r.a.x), 1); H.eq(s:value(r.b.x), 1)
    local alias = r.a
    r.a = P{x = 7}
    H.eq(s:value(alias.x), 7)
    alias.x = 8
    H.eq(s:value(r.a.x), 8); H.eq(s:value(r.b.x), 1)
    r.a = r.b; r.b.x = 5
    H.eq(s:value(r.a.x), 1)
end)

H.test("record arguments and results have value boundaries", function()
    local s = Word.new(); local P = s.word{x = s.U32}
    local bump = s.word(P, function(p) p.x = p.x + 1; return p end)
    local p = P{x = 5}; local q = bump(p)
    H.eq(s:value(p.x), 5); H.eq(s:value(q.x), 6)
    q.x = 40; H.eq(s:value(p.x), 5)
    H.eq(s:value(bump{x = 7}.x), 8)
    local R = s.word{child = P}
    local take = s.word(R, function(r) return r.child end)
    local r = R{child = p}; local child = take(r); child.x = 99
    H.eq(s:value(r.child.x), 5)
end)

H.test("runtime instances are neither specialization inputs nor static results", function()
    local s = Word.new(); local P = s.word{x = s.U32}
    local p = P{x = 1}
    local f = s.word(P, function(x) return x end)
    H.raises("reject", "static-required", function() f:of(p) end)
    H.raises("reject", "static-required", function() s:normalize(p) end)
    local make = s.word(function() return P{x = 3} end)
    H.raises("reject", "runtime-in-normalization", function() s:normalize(make) end)
    H.eq(Model.get(make).result, nil)
    local first, second = make(), make(); first.x = 9
    H.eq(s:value(second.x), 3)
    assert(IR.verify(s:compile{functions = {make = make}}))
    H.eq(Model.get(make).result, nil)
    local captured = s.word(function() return p.x end)
    H.raises("todo", "host-captures", function() s:compile{functions = {captured = captured}} end)
end)

H.test("Unit fields and empty records have explicit runtime representations", function()
    local s = Word.new(); local E = s.word{}; local U = s.word{unit = s.Unit}
    H.eq(next(s:value(E{})), nil)
    local p = U{}; H.eq(s:value(p.unit), nil); p.unit = s.Unit()
    local f = s.word(U, function(x) return x.unit end)
    H.eq(s:value(f(p)), nil)
    assert(IR.verify(s:compile{types = {Empty = E, WithUnit = U}, functions = {f = f}}))
end)

H.test("record type and session boundaries reject incompatible data", function()
    local s = Word.new(); local P = s.word{x = s.U32}; local B = s.word{x = s.Bool}
    local consume = s.word(P, function(p) return p.x end)
    H.raises("reject", "type", function() consume(B{x = false}) end)
    local foreign = Word.new(); local Q = foreign.word{x = foreign.U32}
    H.raises("reject", "foreign-session", function() consume(Q{x = 1}) end)
    local Meta = s.word{type = s.Type}
    H.raises("reject", "runtime-type", function() Meta{type = s.U32} end)
    H.raises("reject", "runtime-type", function() s:compile{types = {Meta = Meta}} end)
    H.raises("reject", "runtime-type", function() s:compile{types = {Type = s.Type}} end)
end)

H.test("export factory chains share a bounded normalization demand", function()
    local s = Word.new{max_normalizations = 3}
    local m = s:load_string([[
        local grow
        grow = word(U32, function(n) return grow:of(n + 1) end)
        return {grow = grow:of(0)}
    ]])
    H.raises("resource", "normalizations", function() s:compile{functions = m} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("shared type graphs do not expand during checking and huge layouts stop explicitly", function()
    local s = Word.new(); local t = s.U32
    for _ = 1, 17 do t = s:type(s.word{a = t, b = t}) end
    assert(Model.runtime_type(t))
    H.raises("resource", "record-layout", function() s:emit_c{types = {Huge = t}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("record IR distinguishes storage from values and checks paths", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/records.lua")
    local program = s:compile(m); assert(IR.verify(program))
    local fn = program.functions[program.exports[1].target]
    local store
    for _, ins in ipairs(fn.blocks[1].instructions) do if ins.op == "Store" then store = ins; break end end
    assert(store)
    store.root = fn.parameters[1].id
    H.raises("bug", "invalid-ir", function() IR.verify(program) end)
    program = s:compile(m); fn = program.functions[program.exports[1].target]
    for _, ins in ipairs(fn.blocks[1].instructions) do
        if ins.op == "Store" then ins.path = {"missing"}; break end
    end
    H.raises("bug", "invalid-ir", function() IR.verify(program) end)
    assert(IR.verify(s:compile(m)))
end)
