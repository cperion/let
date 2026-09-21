local H = ...
local Word = require("word")
local table = require("word.host").table
local Model = require("word.model")
local IR = require("word.ir")

H.test("direct method exports share code identities and distinguish borrowed and frozen receivers", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/method_exports.lua")
    local program = s:compile(m); H.eq(#program.functions, 5)
    local exports = {}; for _, export in ipairs(program.exports) do exports[export.name] = export.target end
    H.eq(exports.add, exports.alias)
    H.eq(program.functions[exports.add].receiver.type, s:type(m.types.Counter))
    H.eq(#program.functions[exports.step3].parameters, 0)
    H.eq(program.functions[exports.known].receiver, nil); assert(IR.verify(program))
    H.eq(s:emit_c(m), s:emit_c(m))
end)

H.test("mutable bound exports and nonrepresentable receiver layouts reject", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/method_exports.lua")
    local c = m.types.Counter{value = 7}
    H.raises("reject", "bound-method-export", function() s:compile{functions = {f = c.add}} end)
    local get = s.word(s.U32, function(n) return n end)
    local Meta = s.word{T = s.Type, get = get}
    H.raises("reject", "runtime-type", function() s:compile{functions = {f = Meta.get}} end)
    assert(IR.verify(s:compile{functions = {f = Meta:of{T = s.U32}.get}}))
    H.eq(s._engine.scope:current(), nil)
end)

H.test("closed getters, resetters, value constructors and multiple results classify without fake receiver values", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/closed_methods.lua")
    local c = m.types.Counter{count = 9}
    H.eq(s:value(c.read()), 9); H.eq(s:value(c.constant()), 7)
    local copy = c.copy(); copy.x = 20; H.eq(s:value(c.count), 9)
    c.reset(); local value, flag = c.pair()
    H.eq(s:value(value), 0); H.eq(s:value(flag), false)
    local values = table.pack(m.functions.run(5)); H.eq(values.n, 5)
    H.eq(s:value(values[1]), 5); H.eq(s:value(values[2]), 0)
    H.eq(s:value(values[3].x), 5); H.eq(s:value(values[4]), false); H.eq(s:value(values[5]), 7)
    local t = s:type(m.types.Counter); H.eq(#Model.record(t).runtime_order, 1)
    assert(IR.verify(s:compile(m)))
end)

H.test("closed-child classification does not reuse a cached module read when the owner shadows it", function()
    local s = Word.new(); local m = s:load_string([[
        local member = word(function() return U32 end)
        return {member = member, A = word{x = member}, B = word{U32 = U32, x = member}}
    ]])
    local a = s:type(m.A); H.eq(Model.record(a).fields.x, s.U32)
    H.eq(Model.word(m.member).result, s.U32)
    local b = s:type(m.B); assert(Model.record(b).methods.x)
    H.eq(s:value(m.B{U32 = 9}.x()), 9)
    H.eq(s:type(m.A), a); H.eq(s:type(m.B), b)
    H.eq(s:normalize(m.member), s.U32)
end)

H.test("successful type-producing children retain their normalized identities and name-only dependencies", function()
    local s = Word.new(); local m = s:load_string([[
        local factory = word(function()
            return word{value = U32, read = word(Unit, function() return value end)}
        end)
        return {factory = factory, Outer = word{child = factory}}
    ]])
    local t = s:type(m.Outer); local result = Model.word(m.factory).result
    local serial = s._engine.next_definition
    for _ = 1, 5 do H.eq(s:type(m.Outer), t); H.eq(Model.word(m.factory).result, result) end
    H.eq(s._engine.next_definition, serial)
    for name, value in pairs(Model.word(m.factory).result_names) do
        H.eq(type(name), "string"); H.eq(value, true)
    end
end)

H.test("classification preserves immediate-terminal lookup and propagates real errors", function()
    local s = Word.new(); local m = s:load_string([[
        return {C = word{count = U32, bad = word(function()
            local function helper() return count end
            return helper()
        end)}}
    ]])
    H.raises("reject", "unknown-name", function() s:type(m.C) end)
    local broken = s.word(function() local x = nil; return x.field end)
    H.raises("lua", "terminal-error", function() s:type(s.word{broken = broken}) end)
    local changed = 0; local effect = s.word(function() changed = changed + 1; return changed end)
    H.raises("reject", "capture-changed", function() s:type(s.word{effect = effect}) end)
    H.eq(s._engine.scope:current(), nil)
end)
