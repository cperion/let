local H = ...
local Word = require("word")
local IR = require("word.ir")

local function calls(fn)
    local out = {}
    for _, block in ipairs(fn.blocks) do
        for _, ins in ipairs(block.instructions) do if ins.op == "Call" then out[#out + 1] = ins end end
    end
    return out
end
local function cross(fn)
    local out = {}; for _, ins in ipairs(calls(fn)) do if ins.target ~= "self" then out[#out + 1] = ins end end
    return out
end

H.test("recursive helper wrappers reserve verified private targets with distinct signatures", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_helpers.lua")
    for _, name in ipairs({"total", "typed", "predicate", "walk", "unit", "zero"}) do
        local program = s:compile{functions = {f = m.functions[name]}}
        H.eq(#program.functions, 2); assert(IR.verify(program))
        local edges = cross(program.functions[1]); assert(#edges > 0)
        for _, ins in ipairs(edges) do H.eq(ins.target, 2); H.eq(ins.type, program.functions[2].result) end
        H.eq(#calls(program.functions[2]) > 0, true)
        if name == "predicate" then H.eq(program.functions[1].result, s.U32); H.eq(program.functions[2].result, s.Bool) end
        if name == "unit" then H.eq(program.functions[1].result, s.Bool); H.eq(program.functions[2].result, s.Unit) end
        if name == "zero" then H.eq(#program.functions[2].parameters, 0) end
    end
end)

H.test("multiple wrappers and exported aliases share a helper without changing self identity", function()
    local s = Word.new(); local U32 = s.U32; local sum
    sum = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return sum(n - 1) + n end)
    local a = s.word(U32, function(n) return sum(n) + 1 end)
    local b = s.word(U32, function(n) return sum(n) + 2 end)
    local program = s:compile{functions = {a = a, b = b, z = sum, zz = sum}}
    H.eq(#program.functions, 3)
    local target = program.exports[3].target; H.eq(target, program.exports[4].target)
    H.eq(cross(program.functions[program.exports[1].target])[1].target, target)
    H.eq(cross(program.functions[program.exports[2].target])[1].target, target)
    H.eq(calls(program.functions[target])[1].target, "self")
    H.eq(#s:compile{functions = {z = sum}}.functions, 1) -- No persistent helper registry.
end)

H.test("outlining preserves known recursion and call-site facts in later exports and branches", function()
    local s = Word.new(); local U32 = s.U32; local helper
    local P = s.word{x = U32}
    helper = s.word(P, U32, function(p, n)
        if n:eq(0) then return U32(7) end
        return helper(p, n - 1)
    end)
    local trigger = s.word(P, U32, function(p, n) return helper(p, n) end)
    local add = s.word(U32, U32, function(x, y) return x + y end)
    local known = s.word(P, U32, function(p, n) return add:of(helper(p, 0))(n) end)
    local program = s:compile{functions = {a = trigger, z = known}}
    H.eq(#calls(program.functions[program.exports[2].target]), 0)
    local sum
    sum = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return sum(n - 1) + n end)
    local f = s.word(U32, function(n)
        if n:gt(10) then return sum(n) end
        return add:of(sum(3))(n)
    end)
    assert(IR.verify(s:compile{functions = {f = f}}))
    H.eq(s:value(f(2)), 8); H.eq(s:value(f(11)), 66)
end)

H.test("erased generic and callable helper prefixes retain their specialization identities", function()
    local s = Word.new(); local U32 = s.U32; local f, callback
    f = s.word(s.word(U32), U32, function(op, n) if n:eq(0) then return U32(0) end; return op(n - 1) + 1 end)
    callback = s.word(U32, function(n) return f(callback, n) end)
    local bound = f:of(callback)
    local wrapper = s.word(U32, function(n) return bound(n) end)
    local program = s:compile{functions = {f = wrapper}}
    H.eq(#program.functions, 2); H.eq(#program.functions[2].parameters, 1)
    H.eq(s:value(wrapper(6)), 6)
    local g
    g = s.word(s.Type, U32, U32, function(T, step, n)
        if n:eq(0) then return T(0) end; return g(T, step, n - 1) + step
    end)
    local a, b = g:of(U32, 3), g:of(U32, 5)
    local combined = s.word(U32, function(n) return a(n) + b(n) end)
    program = s:compile{functions = {f = combined}}
    H.eq(#program.functions, 3)
    H.eq(#program.functions[2].parameters, 1); H.eq(#program.functions[3].parameters, 1)
    H.eq(s:value(combined(4)), 32)
end)

H.test("finite inline mutual cycles can be outlined behind a wrapper", function()
    local s = Word.new(); local U32 = s.U32; local a, b
    a = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return b(n - 1) + 1 end)
    b = s.word(U32, function(n) if n:eq(0) then return U32(1) end; return a(n - 1) + 1 end)
    local root = s.word(U32, function(n) return a(n) end)
    H.eq(#s:compile{functions = {root = root}}.functions, 2)
    H.eq(s:value(root(9)), 10)
end)

H.test("ambiguous helpers require declarations and helper metadata requires explicit specialization", function()
    local s = Word.new(); local U32 = s.U32; local f
    f = s.word(U32, function(n) return f(n) end)
    local root = s.word(U32, function(n) return f(n) end)
    H.raises("reject", "recursive-result", function() s:compile{functions = {f = root}} end)
    local generic
    generic = s.word(s.Type, U32, function(T, n) if n:eq(0) then return T(0) end; return generic(T, n - 1) end)
    root = s.word(U32, function(n) return generic(U32, n) end)
    H.raises("reject", "static-required", function() s:compile{functions = {f = root}} end)
    local a, b
    a = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return b(n) + a(n - 1) end)
    b = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return a(n - 1) + b(n - 1) end)
    root = s.word(U32, function(n) return a(n) end)
    H.eq(#s:compile{functions = {f = root}}.functions, 3)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("function-limit failures leave no stale reservations", function()
    H.raises("reject", "options", function() Word.new{max_functions = 0} end)
    local s = Word.new{max_functions = 1}; local U32 = s.U32; local helper
    helper = s.word(U32, function(n) if n:gt(0) then return helper(n - 1) end; return U32(7) end)
    local root = s.word(U32, function(n) return helper(n) + 1 end)
    H.raises("resource", "function-instances", function() s:compile{functions = {f = root}} end)
    H.eq(s._engine.scope:current(), nil)
    s._engine.max_functions = 2
    local expected = s:emit_c{functions = {f = root}}
    H.eq(s:emit_c{functions = {f = root}}, expected)
end)

H.test("private call IR validates target signatures independently of the caller", function()
    local s = Word.new()
    local function program(ins)
        return {types = {}, exports = {{name = "root", target = 1}}, functions = {
            {parameters = {{id = 1, type = s.U32}}, result = s.Bool, blocks = {{id = 1,
                instructions = {ins}, exit = {op = "Return", value = 2}}}},
            {parameters = {{id = 1, type = s.U32}}, result = s.Bool, blocks = {{id = 1,
                instructions = {{op = "Constant", id = 2, type = s.Bool, value = true}}, exit = {op = "Return", value = 2}}}},
        }}
    end
    local good = {op = "Call", target = 2, args = {1}, type = s.Bool, id = 2}
    assert(IR.verify(program(good)))
    for _, ins in ipairs({
        {op = "Call", target = 3, args = {1}, type = s.Bool, id = 2},
        {op = "Call", target = 2, args = {}, type = s.Bool, id = 2},
        {op = "Call", target = 2, args = {2}, type = s.Bool, id = 2},
        {op = "Call", target = 2, args = {1}, type = s.U32, id = 2},
    }) do H.raises("bug", "invalid-ir", function() IR.verify(program(ins)) end) end
    local p = program(good); p.functions[2].parameters[1].type = s.Bool
    H.raises("bug", "invalid-ir", function() IR.verify(p) end)
    p = program(good); p.functions[2] = {}
    H.raises("bug", "invalid-ir", function() IR.verify(p) end)
end)

H.test("helper discovery preserves capture checks, real errors and word-result limits", function()
    local s = Word.new(); local U32 = s.U32; local state = 0; local helper
    helper = s.word(U32, function(n)
        if n:gt(0) then return helper(n - 1) end
        state = state + 1; return U32(0)
    end)
    local root = s.word(U32, function(n) return helper(n) end)
    H.raises("reject", "capture-changed", function() s:compile{functions = {f = root}} end)
    local bad
    bad = s.word(U32, function(n) if n:gt(0) then return bad(n - 1) end; local x = nil; return x.field end)
    root = s.word(U32, function(n) return bad(n) end)
    H.raises("lua", "terminal-error", function() s:compile{functions = {f = root}} end)
    local P = s.word{x = U32}; local next_word = s.word(U32, function(n) return n + 1 end); local factory
    factory = s.word(function()
        local p = P{x = 0}; if p.x:eq(0) then return next_word end; return factory()
    end)
    root = s.word(U32, function(n) return factory()(n) end)
    H.eq(s:value(root(3)), 4)
    assert(require("word.ir").verify(s:compile{functions = {f = root}}))
    H.eq(s._engine.scope:current(), nil)
end)

H.test("recursive receiver selections are not mistaken for ordinary helper identities", function()
    local s = Word.new(); local m = s:load_string([[
        local Counter = word{value = U32, step = word(U32, function(n)
            if n:eq(0) then return value end
            value = value + 1; return step(n - 1)
        end)}
        return {f = word(U32, function(n) local c = Counter{value = 0}; return c.step(n) end)}
    ]])
    H.eq(s:value(m.f(3)), 3)
    local program = s:compile{functions = m}
    H.eq(#program.functions, 2); assert(program.functions[2].receiver)
    H.eq(s._engine.scope:current(), nil)
end)
