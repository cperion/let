local H = ...
local Word = require("word")
local table = require("word.host").table
local IR = require("word.ir")
local Model = require("word.model")

H.test("multiple static results preserve order, false and Unit slots through caching", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/results.lua")
    local values = table.pack(m.functions.constants()); H.eq(values.n, 4)
    H.eq(s:value(values[1]), 7); H.eq(s:value(values[2]), false)
    H.eq(s:value(values[3]), nil); H.eq(s:value(values[4]), 9)
    local a, b, c, d = s:normalize(m.functions.constants)
    local cached = Model.word(m.functions.constants).result
    H.eq(s:value(a), 7); H.eq(s:value(b), false); H.eq(s:value(c), nil); H.eq(s:value(d), 9)
    H.eq(s:normalize(m.functions.constants), a); H.eq(Model.word(m.functions.constants).result, cached)
end)

H.test("Lua adjusts multiple word results only at ordinary call and return boundaries", function()
    local s = Word.new(); local m = s:load_string([[
        local pair = word(U32, function(n) return n, n + 1 end)
        local add = word(U32, U32, function(a, b) return a + b end)
        return {forward = word(U32, function(n) return pair(n) end),
            trim = word(U32, function(n) return (pair(n)) end),
            list = word(U32, function(n) return pair(n), pair(n + 10) end),
            consume = word(U32, function(n) return add(pair(n)) end)}
    ]])
    local a, b = m.forward(4); H.eq(s:value(a), 4); H.eq(s:value(b), 5)
    local trim = table.pack(m.trim(4)); H.eq(trim.n, 1); H.eq(s:value(trim[1]), 4)
    local list = table.pack(m.list(4)); H.eq(list.n, 3)
    H.eq(s:value(list[1]), 4); H.eq(s:value(list[2]), 14); H.eq(s:value(list[3]), 15)
    H.eq(s:value(m.consume(4)), 9); assert(IR.verify(s:compile{functions = m}))
end)

H.test("multiple record results are independent values, including repeated static snapshots", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/results.lua")
    local p = m.types.Point{x = 3}; local a, b = m.functions.copies(p)
    a.x = 9; H.eq(s:value(b.x), 3); H.eq(s:value(p.x), 3)
    local P = m.types.Point; local Holder = s.word{p = P}:of{p = {x = 7}}
    local f = s.word(function() return Holder.p, Holder.p end)
    a, b = s:normalize(f); H.raises("reject", "static-field", function() a.x = 99 end)
    a, b = f(); a.x = 99; H.eq(s:value(b.x), 7); H.eq(s:value(Holder.p.x), 7)
    assert(IR.verify(s:compile{functions = {f = f}}))
end)

H.test("result packs carry static words locally without inventing a runtime callable ABI", function()
    local s = Word.new(); local U32 = s.U32
    local plus = s.word(U32, function(x) return x + 1 end)
    local factory = s.word(function() return U32, plus end)
    local t, f = s:normalize(factory); H.eq(t, U32); H.eq(f, plus)
    local root = s.word(U32, function(n) local T, g = factory(); return g(n) + T(1) end)
    H.eq(s:value(root(5)), 7); assert(IR.verify(s:compile{functions = {f = root}}))
    local escaping = s.word(U32, function(n) return n, plus end)
    assert(IR.verify(s:compile{functions = {f = escaping}}))
end)

H.test("recursive result packs ground concrete arity and component types", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/results.lua")
    local a, b = m.functions.sum(5); H.eq(s:value(a), 15); H.eq(s:value(b), 5)
    local program = s:compile(m); assert(IR.verify(program))
    local tuple
    for _, export in ipairs(program.exports) do
        if export.name == "sum" then tuple = Model.record(program.functions[export.target].result) end
    end
    H.eq(tuple.tuple_arity, 2); H.eq(tuple.fields.r1, s.U32); H.eq(tuple.fields.r2, s.U32)
    local arity = s.word(s.U32, function(n) if n:gt(0) then return 1, 2 end; return 1 end)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = arity}} end)
    local types = s.word(s.U32, function(n) if n:gt(0) then return 1, false end; return 1, 2 end)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = types}} end)
    local R = s.word{r1 = s.U32, r2 = s.U32}
    local shape = s.word(s.U32, function(n) if n:gt(0) then return 1, 2 end; return R{r1 = 1, r2 = 2} end)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = shape}} end)
end)

H.test("result tuple types survive failed materialization without exposing partial values", function()
    local s = Word.new{max_values = 1}; local m = s:load(H.root .. "examples/results.lua")
    H.raises("resource", "ir-values", function() s:compile(m) end)
    H.eq(s._engine.scope:current(), nil); s._engine.max_values = 10000
    H.eq(s:emit_c(m), s:emit_c(m)); H.eq(s:value(s:normalize(m.functions.constants)), 7)
end)
