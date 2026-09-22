local H = ...
local Word = require("word")
local IR = require("word.ir")

H.test("outlined lexical words carry snapshots separately from borrowed receiver state", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/lexical_captures.lua")
    for _, name in ipairs({"run", "owned"}) do
        local c = m.types.Counter{value = 3}
        H.eq(s:value(c[name](4)), 10); H.eq(s:value(c.value), 7)
    end
    local c = m.types.Counter{value = 3}
    H.eq(s:value(c.mutual(4)), 12); H.eq(s:value(c.value), 9)
    c.value = 3; H.eq(s:value(c.mutual(3)), 13); H.eq(s:value(c.value), 7)
    c.value = 3; H.eq(s:value(c.callback(4)), 8); H.eq(s:value(c.value), 5)
    local p = s:compile(m); assert(IR.verify(p))
    local captured = 0
    for _, fn in ipairs(p.functions) do
        if fn.captures then captured = captured + 1; assert(fn.receiver) end
    end
    assert(captured >= 3)
    local first = s:emit_c(m); H.eq(s:emit_c(m), first)
end)

H.test("lexical capture code shares across fresh values without retaining earlier environments", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/lexical_captures.lua")
    local a, b, count = m.functions.twice(4)
    H.eq(s:value(a), 10); H.eq(s:value(b), 18); H.eq(s:value(count), 11)
    local p = s:compile{functions = {twice = m.functions.twice}}
    H.eq(#p.functions, 2); assert(p.functions[2].captures)
    assert(IR.verify(p))
    H.eq(s._engine.scope:current(), nil)
end)

H.test("nested owner occurrences retain capture parameters across recursive replay", function()
    local s = Word.new(); local m = s:load_string([[
        local Inner = word{value = U32, run = word(U32, function(n)
            local before = value
            local loop
            loop = word(U32, function(x)
                if x:eq(0) then return before + bias + value end
                value = value + 1; bias = bias + 2
                return loop(x - 1)
            end)
            return loop(n)
        end)}
        local O = word{bias = U32, child = Inner}
        return {run = word(U32, function(n)
            local o = O{bias = 10, child = {value = 3}}
            return o.child.run(n)
        end)}
    ]])
    H.eq(s:value(m.run(4)), 28)
    local p = s:compile{functions = m}; assert(IR.verify(p)); assert(p.functions[2].captures)
end)

H.test("lexical capture conversion checks immutable bindings and does not permit escapes", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, bad = word(U32, function(n)
            local before = value
            local f = word(U32, function(x) before = before + x; return value + before end)
            return f(n)
        end), escape = word(U32, function(n)
            local before = n
            return word(U32, function(x) return value + before + x end)
        end)}
        return {C = C}
    ]])
    H.raises("reject", "capture-changed", function() m.C{value = 3}.bad(2) end)
    H.raises("reject", "capture-changed", function() s:compile{functions = {bad = m.C.bad}} end)
    H.raises("reject", "borrow-escape", function() s:compile{functions = {escape = m.C.escape}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("immutable lexical owners stay static while escaping environments own their captures", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/lexical_captures.lua")
    H.eq(s:value(m.functions.make7(3)(2)), 12)
    H.eq(s:value(m.functions.make11(3)(2)), 16)
    H.eq(s:value(m.functions.nested(3)(2)(1)), 13)
    assert(IR.verify(s:compile(m)))
    H.eq(s:emit_c(m), s:emit_c(m))
end)

H.test("capture-call IR checks missing operands, operand types and storage provenance", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/lexical_captures.lua")
    local function program() return s:compile{functions = {run = m.functions.run}} end
    for _, mutate in ipairs({
        function(ins) ins.captures = nil end,
        function(ins) ins.captures = ins.args[1] end,
        function(ins, p) ins.captures = p.functions[1].receiver.id end,
    }) do
        local p = program(); local found
        for _, block in ipairs(p.functions[1].blocks) do
            for _, ins in ipairs(block.instructions) do
                if ins.op == "Call" then mutate(ins, p); found = true; break end
            end
            if found then break end
        end
        assert(found)
        H.raises("bug", "invalid-ir", function() IR.verify(p) end)
    end
end)
