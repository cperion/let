local H = ...
local Word = require("word")
local IR = require("word.ir")

H.test("positional requirements accept executable words and remaining signatures", function()
    local s = Word.new(); local U32 = s.U32
    local Sig = s.word(U32); local add = s.word(U32, U32, function(a, b) return a + b end)
    local apply = s.word(Sig, U32, function(f, x) return f(x) end)
    local add10 = add:of(10)
    H.eq(s:value(apply(add10, 4)), 14)
    H.eq(s:value(apply:of(add10)(4)), 14)
    H.eq(apply:of(add10), apply:of(add10))
    local program = s:compile{functions = {f = apply:of(add10)}}
    H.eq(#program.functions[1].parameters, 1); H.eq(program.functions[1].result, U32)
end)

H.test("callable binding checks inputs without executing the implementation", function()
    local s = Word.new(); local U32 = s.U32
    local bad = s.word(U32, function(_) return U32("not a number") end)
    local ignore = s.word(s.word(U32), function(_) return U32(7) end)
    local bound = ignore:of(bad)
    H.eq(s:value(bound()), 7)
    assert(IR.verify(s:compile{functions = {ignore = bound}}))
    local apply = s.word(s.word(U32), U32, function(f, x) return f(x) end)
    H.raises("reject", "type", function() apply:of(bad)(1) end)
end)

H.test("callable mismatch is rejected even if the parameter is unused", function()
    local s = Word.new(); local U32 = s.U32
    local take = s.word(s.word(U32), function(_) return U32(0) end)
    local wrong = s.word(s.Bool, function(x) return x end)
    H.raises("reject", "callable-shape", function() take:of(wrong) end)
    H.raises("reject", "callable-shape", function() take:of(s.word(U32, U32, function(a, b) return a + b end)) end)
    H.raises("reject", "callable-required", function() take:of(s.word(U32)) end)
    H.raises("reject", "callable-required", function() take:of(function(x) return x end) end)
    H.raises("reject", "callable-required", function() take:of(U32(1)) end)
    H.raises("reject", "callable-required", function() take:of(s.word{x = U32}) end)
    local foreign = Word.new(); local f = foreign.word(foreign.U32, function(x) return x end)
    H.raises("reject", "foreign-session", function() take:of(f) end)
end)

H.test("callable results are inferred at use rather than guessed from their inputs", function()
    local s = Word.new(); local U32 = s.U32
    local yes = s.word(U32, function(_) return true end)
    local apply = s.word(s.word(U32), U32, function(f, x) return f(x) end):of(yes)
    H.eq(s:value(apply(1)), true)
    H.eq(s:compile{functions = {f = apply}}.functions[1].result, s.Bool)
    local wrong = s.word(s.word(U32), U32, function(f, x) return f(x) + 1 end):of(yes)
    H.raises("reject", "arithmetic-type", function() s:compile{functions = {wrong = wrong}} end)
end)

H.test("zero-argument callables are not eagerly invoked by binding", function()
    local s = Word.new(); local U32 = s.U32
    local make_type = s.word(function() return U32 end)
    local use = s.word(s.word(), U32, function(f, x) local T = f(); return T(x) end)
    H.eq(s:value(use(make_type, 8)), 8)
    assert(IR.verify(s:compile{functions = {use = use:of(make_type)}}))
    local unit = s.word(s.word(), function(f) return f() end):of(s.Unit)
    H.eq(s:value(unit()), nil)
    H.eq(s:compile{functions = {unit = unit}}.functions[1].result, s.Unit)
end)

H.test("nested calling requirements compare structurally and intrinsically", function()
    local s = Word.new(); local U32 = s.U32
    local a, b = s.word(U32), s.word(U32)
    local use = s.word(a, U32, function(f, x) return f(x) end)
    local outer = s.word(s.word(b, U32), U32, function(f, x) return f(U32, x) end)
    H.eq(s:value(outer(use, 9)), 9)
    assert(IR.verify(s:compile{functions = {outer = outer:of(use)}}))
    local bad = s.word(s.word(s.Bool), U32, function(_, x) return x end)
    H.raises("reject", "callable-shape", function() outer:of(bad) end)
    local template = s.word(U32, function(_) return U32("unused requirement body") end)
    local from_template = s.word(template, U32, function(f, x) return f(x) end)
    H.eq(s:value(from_template(U32, 3)), 3)
end)

H.test("signature aliases and callable factories normalize on demand", function()
    local s = Word.new(); local m = s:load_string([[
        local Signature = word(function() return word(U32) end)
        local Identity = word(Type, function(T) return word(T, function(x) return x end) end)
        local apply = word(Signature, U32, function(f, x) return f(x) end)
        return {f = apply:of(Identity:of(U32))}
    ]])
    H.eq(s:value(m.f(42)), 42)
    assert(IR.verify(s:compile{functions = m}))
end)

H.test("callable record inputs preserve static schema knowledge and value copies", function()
    local s = Word.new(); local P = s.word{x = s.U32, y = s.U32}
    local X = P:of{y = 0}; local Y = P:of{y = 1}
    local bump = s.word(X, function(p) p.x = p.x + 1; return p end)
    local apply = s.word(s.word(X), X, function(f, p) return f(p) end)
    local p = X{x = 5}; local q = apply(bump, p)
    H.eq(s:value(p.x), 5); H.eq(s:value(q.x), 6); H.eq(s:value(q.y), 0)
    H.raises("reject", "callable-shape", function() apply:of(s.word(Y, function(p) return p end)) end)
    assert(IR.verify(s:compile{functions = {bump = apply:of(bump)}}))
end)

H.test("supplied callable captures are rechecked before specialization reuse", function()
    local s = Word.new(); local bias = 1
    local f = s.word(s.U32, function(x) return x + bias end)
    local apply = s.word(s.word(s.U32), s.U32, function(g, x) return g(x) end):of(f)
    s:compile{functions = {f = apply}}
    bias = 2
    H.raises("reject", "capture-changed", function() s:compile{functions = {f = apply}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("deep static callable composition stops with a resource diagnostic", function()
    local s = Word.new(); local U32 = s.U32
    local apply = s.word(s.word(U32), U32, function(f, x) return f(x) end)
    local f = U32
    for _ = 1, 40 do f = apply:of(f) end
    H.raises("resource", "call-depth", function() f(1) end)
    H.eq(s._engine.scope:current(), nil)
    H.raises("resource", "call-depth", function() s:compile{functions = {f = f}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("distinct callable specializations nest without false recursion", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/higher_order.lua")
    H.eq(s:value(m.nested(3)), 13)
    H.eq(s:value(m.composed(3)), 14)
    assert(IR.verify(s:compile{functions = m}))
end)
