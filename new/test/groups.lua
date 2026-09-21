local H = ...
local Word = require("word")
local IR = require("word.ir")

local function cyclic(program)
    local active, done = {}, {}
    local function visit(i)
        if active[i] then return true end
        if done[i] then return false end
        active[i] = true
        for _, block in ipairs(program.functions[i].blocks) do
            for _, ins in ipairs(block.instructions) do
                if ins.op == "Call" and ins.target ~= "self" and visit(ins.target) then return true end
            end
        end
        active[i] = nil; done[i] = true
    end
    for i in ipairs(program.functions) do if visit(i) then return true end end
    return false
end

H.test("pending helper signatures ground before bodies and produce genuine call graph cycles", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_groups.lua")
    local program = s:compile{functions = {f = m.wrapped}}
    H.eq(#program.functions, 3); assert(cyclic(program)); assert(IR.verify(program))
    for _, fn in ipairs(program.functions) do
        assert(fn.blocks and #fn.blocks > 0); H.eq(fn.result, s.U32); H.eq(#fn.parameters, 2)
    end
    H.eq(s:emit_c{functions = m}, s:emit_c{functions = m})
    local a, b = 1, 2
    for n = 0, 5 do
        H.eq(s:value(m.a(n, 1)), a); H.eq(s:value(m.b(n, 1)), b)
        b = (a + b) % 4294967296; a = (a + b) % 4294967296
    end
end)

H.test("mutual groups permit different grounded result types without caller-type guesses", function()
    local s = Word.new(); local U32, Bool = s.U32, s.Bool; local a, b
    a = s.word(U32, function(n)
        if n:eq(0) then return U32(1) end
        if b(n):eq(true) then return a(n - 1) + 1 end
        return a(n - 1) + 2
    end)
    b = s.word(U32, function(n)
        if n:eq(0) then return Bool(true) end
        if a(n - 1):lt(10) then return b(n - 1) end
        return not b(n - 1):eq(true)
    end)
    local root = s.word(U32, function(n) return a(n) end)
    local program = s:compile{functions = {f = root}}
    assert(cyclic(program))
    local has_bool, has_u32 = false, false
    for _, fn in ipairs(program.functions) do
        has_bool = has_bool or fn.result == Bool; has_u32 = has_u32 or fn.result == U32
    end
    assert(has_bool and has_u32); H.eq(s:value(root(3)), 4)
end)

H.test("grounded declarations do not hide later conflicting returns or invalid result uses", function()
    local s = Word.new(); local U32 = s.U32; local a, b
    a = s.word(U32, function(n)
        if n:gt(0) then b(n); return false end
        return U32(0)
    end)
    b = s.word(U32, function(n)
        if n:gt(0) then b(n - 1); return a(n - 1) end
        return U32(0)
    end)
    H.raises("reject", "branch-result", function() s:compile{functions = {a = a}} end)
    H.eq(s._engine.scope:current(), nil)
    local Bool = s.Bool; local x, y
    x = s.word(U32, function(n) if n:gt(0) then y(n); return x(n - 1) + 1 end; return Bool(false) end)
    y = s.word(U32, function(n) if n:gt(0) then y(n - 1); x(n - 1) end end)
    local ok, err = pcall(function() s:compile{functions = {x = x}} end)
    assert(not ok and Word.is_diagnostic(err) and err.kind == "reject", tostring(err))
    H.eq(s._engine.scope:current(), nil)
end)

H.test("pending group probes propagate real Lua and capture errors", function()
    local s = Word.new(); local U32 = s.U32; local state = 0; local a, b
    a = s.word(U32, function(n)
        if n:gt(0) then return b(n) + a(n - 1) end
        state = state + 1; return U32(0)
    end)
    b = s.word(U32, function(n) if n:gt(0) then return b(n - 1) + a(n - 1) end; return U32(0) end)
    H.raises("reject", "capture-changed", function() s:compile{functions = {a = a}} end)
    local x, y
    x = s.word(U32, function(n) if n:gt(0) then return y(n) + x(n - 1) end; local bad = nil; return bad.field end)
    y = s.word(U32, function(n) if n:gt(0) then return y(n - 1) + x(n - 1) end; return U32(0) end)
    H.raises("lua", "terminal-error", function() s:compile{functions = {x = x}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("unknown groups never bootstrap a result from circular assumptions", function()
    local s = Word.new(); local a, b
    a = s.word(s.U32, function(n) return b(n) end)
    b = s.word(s.U32, function(n) return a(n) end)
    H.raises("reject", "recursive-result", function() s:compile{functions = {a = a}} end)
    H.eq(s._engine.scope:current(), nil)
    local declaration = {parameters = {{id = 1, type = s.U32}}, result = s.U32}
    H.raises("bug", "invalid-ir", function()
        IR.verify{functions = {declaration}, exports = {{name = "bad", target = 1}}, types = {}}
    end)
end)

H.test("group reservations clean up after function-limit failures", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_groups.lua")
    local spec = {functions = {f = m.wrapped}}
    local expected = s:emit_c(spec)
    s._engine.max_functions = 2
    H.raises("resource", "function-instances", function() s:compile(spec) end)
    s._engine.max_functions = 128
    H.eq(s._engine.scope:current(), nil)
    H.eq(s:emit_c(spec), expected)
end)
