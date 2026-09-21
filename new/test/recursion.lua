local H = ...
local Word = require("word")
local IR = require("word.ir")

local function example()
    local s = Word.new()
    return s, s:load(H.root .. "examples/recursion.lua")
end
local function calls(fn)
    local out = {}
    for _, block in ipairs(fn.blocks) do
        for _, ins in ipairs(block.instructions) do if ins.op == "Call" then out[#out + 1] = ins end end
    end
    return out
end

H.test("grounded recursion runs concretely and reserves a typed residual self call", function()
    local s, m = example()
    for n = 0, 12 do
        H.eq(s:value(m.functions.sum(n)), n * (n + 1) / 2)
        H.eq(s:value(m.functions.even(n)), n % 2 == 0)
        H.eq(s:value(m.functions.triple(n)), 3 * n)
    end
    local fn = s:compile{functions = {sum = m.functions.sum}}.functions[1]
    H.eq(#calls(fn), 1); H.eq(calls(fn)[1].target, "self"); H.eq(calls(fn)[1].type, s.U32)
    H.eq(#fn.blocks, 3); H.eq(#fn.parameters, 1)
    local c = s:emit_c{functions = {sum = m.functions.sum}}
    assert(c:find("= word_sum(", 1, true)); assert(not c:find("for (;;)", 1, true))
end)

H.test("a recursive first arm waits for a grounded return without guessing a result", function()
    local s, m = example()
    H.eq(s:value(m.functions.reverse(12)), 42)
    local c = s:emit_c{functions = {reverse = m.functions.reverse}}
    H.eq(c, s:emit_c{functions = {reverse = m.functions.reverse}})
    assert(c:find("for (;;)", 1, true)); assert(c:find("continue;", 1, true))
    local f; local Bool = s.Bool
    f = s.word(s.U32, function(n) if n:gt(0) then return f(n - 1) end; return Bool(false) end)
    H.eq(s:compile{functions = {f = f}}.functions[1].result, s.Bool)
end)

H.test("tail calls retain all operands and snapshots for simultaneous replacement", function()
    local s, m = example()
    H.eq(s:value(m.functions.swap(11, 7, 9)), 9)
    H.eq(s:value(m.functions.swap(12, 7, 9)), 7)
    local fn = s:compile{functions = {swap = m.functions.swap}}.functions[1]
    H.eq(#calls(fn)[1].args, 3)
    local c = s:emit_c{functions = {swap = m.functions.swap}}
    assert(c:find("wordnext_3 = v2;", 1, true))
    assert(c:find("for (;;)", 1, true))
end)

H.test("recursive static prefixes erase but changed known arguments do not reuse the entry", function()
    local s, m = example()
    local fn = s:compile{functions = {triple = m.functions.triple}}.functions[1]
    H.eq(#fn.parameters, 1); H.eq(#calls(fn)[1].args, 1)
    local f; local U32 = s.U32
    f = s.word(U32, U32, function(step, n)
        if n:eq(0) then return U32(0) end
        return f(step + 1, n - 1) + step
    end)
    local changed = s:compile{functions = {f = f:of(3)}}
    H.eq(#changed.functions, 2)
    H.eq(#changed.functions[2].parameters, 2) -- Step is runtime data in the separate helper.
    H.eq(s:value(f:of(3)(8)), 52)
    local g
    g = s.word(s.Bool, U32, function(flag, n) if n:eq(0) then return flag end; return g(flag, n - 1) end)
    H.eq(s:compile{functions = {g = g:of(false)}}.functions[1].result, s.Bool)
    H.eq(s:value(g(false, 3)), false)
end)

H.test("recursive record inputs and results preserve by-value boundaries", function()
    local s, m = example(); local P = m.types.Point
    for n = 0, 8 do
        local p = P{x = 2, y = 5}; local result = m.functions.walk(p, n)
        H.eq(s:value(p.x), 2); H.eq(s:value(p.y), 5)
        H.eq(s:value(result.x), 3 + n)
        H.eq(s:value(result.y), 5 + 2 * n + n * (n + 1) / 2)
        result.x = 0; H.eq(s:value(p.x), 2)
    end
    local fn = s:compile{functions = {walk = m.functions.walk}}.functions[1]
    H.eq(fn.result, s:type(P)); H.eq(#calls(fn), 1); H.eq(#calls(fn)[1].args, 2)
end)

H.test("void recursive calls remain ordered operations with no invented payload", function()
    local s, m = example()
    H.eq(s:value(m.functions.unit(nil, 8)), nil)
    for _, name in ipairs({"unit", "after"}) do
        local fn = s:compile{functions = {f = m.functions[name]}}.functions[1]
        H.eq(fn.result, s.Unit); H.eq(calls(fn)[1].id, nil); H.eq(calls(fn)[1].type, s.Unit)
    end
    local c = s:emit_c{functions = {after = m.functions.after}}
    assert(c:find("    word_after(", 1, true)); assert(not c:find("for (;;)", 1, true))
end)

H.test("fully known recursive demands still normalize instead of producing calls", function()
    local s, m = example(); local w = m.functions.sum:of(10)
    H.eq(s:value(s:normalize(w)), 55)
    H.eq(#calls(s:compile{functions = {f = w}}.functions[1]), 0)
end)

H.test("recursive return conflicts and invalid recursive arguments are source errors", function()
    local s = Word.new(); local U32 = s.U32
    local f
    f = s.word(U32, function(n)
        if n:eq(0) then return U32(0) end
        f(n - 1); return true
    end)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = f}} end)
    local g
    g = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return g(false) end)
    H.raises("reject", "type", function() s:compile{functions = {g = g}} end)
end)

H.test("ungrounded cycles remain TODO while grounded recursive helpers outline", function()
    local s = Word.new(); local U32 = s.U32
    local f; f = s.word(U32, function(n) return f(n) end)
    H.raises("reject", "recursive-result", function() s:compile{functions = {f = f}} end)
    local g; g = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return g(n - 1) end)
    local wrapper = s.word(U32, function(n) return g(n) end)
    H.eq(#s:compile{functions = {f = wrapper}}.functions, 2)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("recursive discovery checks capture mutations and propagates actual terminal errors", function()
    local s = Word.new(); local U32 = s.U32; local state = 0; local f
    f = s.word(U32, function(n)
        if n:gt(0) then state = state + 1; return f(n - 1) end
        return U32(0)
    end)
    H.raises("reject", "capture-changed", function() s:compile{functions = {f = f}} end)
    local g
    g = s.word(U32, function(n) if n:gt(0) then return g(n - 1) end; local bad = nil; return bad.x end)
    H.raises("lua", "terminal-error", function() s:compile{functions = {g = g}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("recursive discovery resources and concrete depth failures leave clean retry state", function()
    local s, m = example(); local engine = s._engine
    engine.max_paths = 1
    H.raises("resource", "trace-paths", function() s:compile{functions = {f = m.functions.reverse}} end)
    engine.max_paths = 128
    H.raises("resource", "call-depth", function() m.functions.sum(100) end)
    H.eq(engine.scope:current(), nil)
    local expected = s:emit_c{functions = {f = m.functions.reverse}}
    H.eq(s:emit_c{functions = {f = m.functions.reverse}}, expected)
end)

H.test("recursive IR validates target, signature, argument dominance and void payloads", function()
    local s = Word.new()
    local function fn(ins, result, exit)
        return {parameters = {{id = 1, type = s.U32}}, result = result or s.U32,
            blocks = {{id = 1, instructions = {ins}, exit = exit or {op = "Return", value = 2}}}}
    end
    H.eq(IR.verify_function(fn({op = "Call", target = "self", type = s.U32, args = {1}, id = 2})), true)
    local bad = {
        {op = "Call", target = 1, type = s.U32, args = {1}, id = 2},
        {op = "Call", target = "self", type = s.Bool, args = {1}, id = 2},
        {op = "Call", target = "self", type = s.U32, args = {}, id = 2},
        {op = "Call", target = "self", type = s.U32, args = {2}, id = 2},
    }
    for _, ins in ipairs(bad) do H.raises("bug", "invalid-ir", function() IR.verify_function(fn(ins)) end) end
    local void = {op = "Call", target = "self", type = s.Unit, args = {1}}
    H.eq(IR.verify_function(fn(void, s.Unit, {op = "Return"})), true)
    void.id = 2
    H.raises("bug", "invalid-ir", function() IR.verify_function(fn(void, s.Unit, {op = "Return"})) end)
end)

H.test("finite inlining can close a cycle back to the current recursive entry", function()
    local s = Word.new(); local U32 = s.U32; local a, b
    a = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return b(n - 1) + 1 end)
    b = s.word(U32, function(n) if n:eq(0) then return U32(1) end; return a(n - 1) + 1 end)
    local program = s:compile{functions = {a = a, b = b}}
    H.eq(#program.functions, 2)
    for _, fn in ipairs(program.functions) do H.eq(#calls(fn), 1); H.eq(fn.result, U32) end
    for n = 0, 10 do H.eq(s:value(a(n)), n + n % 2); H.eq(s:value(b(n)), n + (1 - n % 2)) end
end)

H.test("erased callable prefixes can participate in recursive entry matching", function()
    local s = Word.new(); local U32 = s.U32; local f, callback
    f = s.word(s.word(U32), U32, function(op, n)
        if n:eq(0) then return U32(0) end
        return op(n - 1) + 1
    end)
    callback = s.word(U32, function(n) return f(callback, n) end)
    local root = f:of(callback)
    H.eq(s:value(root(8)), 8)
    local fn = s:compile{functions = {f = root}}.functions[1]
    H.eq(#fn.parameters, 1); H.eq(#calls(fn)[1].args, 1)
end)

H.test("result discovery has its own bounded path search and clean retries", function()
    local s = Word.new{max_paths = 2}; local U32 = s.U32; local f
    f = s.word(U32, function(n)
        if n:gt(1) then return f(n - 1) end
        if n:eq(0) then return U32(0) end
        return f(0)
    end)
    H.raises("resource", "trace-paths", function() s:compile{functions = {f = f}} end)
    H.eq(s._engine.scope:current(), nil)
    s._engine.max_paths = 128
    H.eq(s:compile{functions = {f = f}}.functions[1].result, U32)
end)

H.test("more-specialized recursive definitions retain their additional static knowledge", function()
    local s = Word.new(); local U32 = s.U32; local f
    local add = s.word(U32, U32, function(x, y) return x + y end)
    f = s.word(U32, function(n)
        if n:eq(0) then return U32(7) end
        return add:of(f:of(0)())(n)
    end)
    H.eq(s:value(f(3)), 10)
    H.eq(#calls(s:compile{functions = {f = f}}.functions[1]), 0)
end)
