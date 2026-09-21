local H = ...
local Word = require("word")
local IR = require("word.ir")

H.test("literal result defaults agree across calls, normalization, specialization and export", function()
    local s = Word.new()
    for _, n in ipairs({0, 1, 42, 0xffffffff, 42.0}) do
        local f = s.word(function() return n end)
        H.eq(s:value(f()), n); H.eq(s:value(s:normalize(f)), n)
        local consumer = s.word(s.U32, function(x) return x + 1 end):of(f)
        H.eq(s:value(consumer()), (n + 1) % 4294967296)
        local program = s:compile{functions = {f = f}}
        H.eq(program.functions[1].result, s.U32); assert(IR.verify(program))
    end
end)

H.test("invalid raw numeric results reject without wrapping or guessing another numeric type", function()
    local s = Word.new()
    for _, n in ipairs({-1, 0x100000000, 0.5, math.huge, -math.huge}) do
        local f = s.word(function() return n end)
        H.raises("reject", "type", function() f() end)
        H.raises("reject", "type", function() s:normalize(f) end)
        H.raises("reject", "type", function() s:compile{functions = {f = f}} end)
        H.eq(s._engine.scope:current(), nil)
    end
    local nan = s.word(function() return 0 / 0 end)
    H.raises("reject", "type", function() nan() end)
    local raw = s.word(function() return 0xffffffff + 1 end)
    H.raises("reject", "type", function() raw() end)
    local U32 = s.U32; local typed = s.word(function() return U32(0xffffffff) + 1 end)
    H.eq(s:value(typed()), 0)
end)

H.test("numeric literal branches and recursion ground U32 without overriding other result types", function()
    local s = Word.new(); local sum
    sum = s.word(s.U32, function(n) if n:gt(0) then return sum(n - 1) + n end; return 0 end)
    H.eq(s:value(sum(5)), 15); assert(IR.verify(s:compile{functions = {f = sum}}))
    local mixed = s.word(s.U32, function(n) if n:gt(0) then return false end; return 0 end)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = mixed}} end)
    H.eq(s:value(s.word(function() return false end)()), false)
    H.eq(s:value(s.word(function() end)()), nil)
end)
