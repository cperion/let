local H = ...
local Word = require("word")
local IR = require("word.ir")

H.test("U32 arithmetic operators have exact integer and modular edge semantics", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/numeric.lua")
    for _, name in ipairs({"quotient", "floor"}) do
        H.eq(s:value(m[name](7, 2)), 3); H.eq(s:value(m[name](0xffffffff, 3)), 1431655765)
        H.eq(s:value(m[name](0xfffffffe, 0xffffffff)), 0)
    end
    H.eq(s:value(m.remainder(0xffffffff, 3)), 0)
    H.eq(s:value(m.remainder(0xfffffffe, 0xffffffff)), 0xfffffffe)
    for _, row in ipairs({{0, 0, 1}, {0, 1, 0}, {2, 31, 0x80000000}, {2, 32, 0},
        {0xffffffff, 2, 1}, {0xffffffff, 0xffffffff, 0xffffffff}, {3, 20, 3486784401}}) do
        H.eq(s:value(m.power(row[1], row[2])), row[3])
        H.eq(s:value(s:normalize(m.power:of(row[1], row[2]))), row[3])
    end
    H.eq(s:value(m.negate(1)), 0xffffffff); H.eq(s:value(m.negate(0)), 0)
    H.eq(s:value(m.invert(0)), 0xffffffff); H.eq(s:value(m.invert(0xffffffff)), 0)
    H.eq(s:value(s.U32:of(3) ^ 20), 3486784401)
end)

H.test("U32 bitwise operations and oversized logical shifts agree with the declared width", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/numeric.lua")
    H.eq(s:value(m.band(0xaaaaaaaa, 0x55555555)), 0)
    H.eq(s:value(m.bor(0xaaaaaaaa, 0x55555555)), 0xffffffff)
    H.eq(s:value(m.bxor(0xffffffff, 0x55555555)), 0xaaaaaaaa)
    H.eq(s:value(m.left(0xffffffff, 31)), 0x80000000)
    H.eq(s:value(m.right(0x80000000, 31)), 1)
    for _, shift in ipairs({32, 33, 63, 64, 0xffffffff}) do
        H.eq(s:value(m.left(0xffffffff, shift)), 0); H.eq(s:value(m.right(0xffffffff, shift)), 0)
    end
    H.raises("reject", "type", function() m.left(1, -1) end)
    H.raises("reject", "arithmetic-type", function() return s.Bool(true):band(1) end)
end)

H.test("known zero divisors reject without publishing a result or damaging later compilation", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/numeric.lua")
    for _, name in ipairs({"quotient", "floor", "remainder"}) do
        H.raises("reject", "division-zero", function() m[name](7, 0) end)
        H.raises("reject", "division-zero", function() s:normalize(m[name]:of(7, 0)) end)
        local f = m[name]; local bad = s.word(s.U32, function(n) return f(n, 0) end)
        H.raises("reject", "division-zero", function() s:compile{functions = {f = bad}} end)
        H.eq(s._engine.scope:current(), nil)
    end
    assert(IR.verify(s:compile{functions = m}))
end)

H.test("new numeric IR verifies operand types and survives explicit IR-limit failure", function()
    local s = Word.new{max_values = 2}; local m = s:load(H.root .. "examples/numeric.lua")
    H.raises("resource", "ir-values", function() s:compile{functions = {f = m.power}} end)
    H.eq(s._engine.scope:current(), nil); s._engine.max_values = 10000
    for _, name in ipairs({"quotient", "remainder", "power", "band", "bor", "bxor", "left", "right"}) do
        local program = s:compile{functions = {f = m[name]}}
        local op = program.functions[1].blocks[1].instructions[1]
        local argument = op.args[2]; op.args[2] = 999999
        H.raises("bug", "invalid-ir", function() IR.verify(program) end)
        op.args[2] = argument; assert(IR.verify(program))
    end
end)
