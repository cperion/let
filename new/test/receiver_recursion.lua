local H = ...
local Word = require("word")
local IR = require("word.ir")

H.test("recursive method code shares identities without sharing receiver storage", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_methods.lua")
    local program = s:compile{functions = {nested = m.functions.nested}}
    H.eq(#program.functions, 2); assert(program.functions[2].receiver)
    assert(IR.verify(program))
    for n = 0, 5 do H.eq(s:value(m.functions.nested(n)), (1 + 2 * n) * 1000 + 20 + 3 * (n + 1)) end
    H.eq(s:emit_c(m), s:emit_c(m))
end)

H.test("recursive receiver schemas, static fields, Unit effects and record copies remain distinct", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_methods.lua")
    local program = s:compile{functions = {f = m.functions.owners}}
    H.eq(#program.functions, 3)
    assert(program.functions[2].receiver.type ~= program.functions[3].receiver.type)
    for n = 0, 4 do
        H.eq(s:value(m.functions.owners(n)), (1 + 2 * n) * 1000 + 5 + 3 * n)
        H.eq(s:value(m.functions.specialized(n)), (8 + 6 * n) * 1000 + 1 + 6 * n)
        local p = m.types.Counter{value = 5, stride = 2}
        H.eq(s:value(m.functions.byvalue(p, n).value), 5 + 2 * n); H.eq(s:value(p.value), 5)
    end
    assert(IR.verify(s:compile(m)))
end)

H.test("mutually pending receiver methods ground complete storage signatures", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_methods.lua")
    local program = s:compile{functions = {f = m.functions.mutual}}
    H.eq(#program.functions, 3); assert(IR.verify(program))
    for i = 2, 3 do assert(program.functions[i].receiver and program.functions[i].blocks) end
end)

H.test("immutable receiver recursion retains static knowledge and rejects writes", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, read = word(U32, function(n)
            if n:gt(0) then return read(n - 1) + value end; return value
        end), write = word(U32, function(n)
            if n:gt(0) then return write(n - 1) end; value = value + 1; return value
        end)}
        local Holder = word{c = C}:of{c = {value = 7}}
        return {good = word(U32, function(n) return Holder.c.read(n) end),
            bad = word(U32, function(n) return Holder.c.write(n) end)}
    ]])
    local program = s:compile{functions = {f = m.good}}
    for _, fn in ipairs(program.functions) do H.eq(fn.receiver, nil) end
    H.eq(s:value(m.good(4)), 35)
    H.raises("reject", "static-field", function() s:compile{functions = {f = m.bad}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("receiver IR rejects missing, mismatched and non-storage call operands", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_methods.lua")
    local program = s:compile{functions = {f = m.functions.nested}}
    local call
    for _, block in ipairs(program.functions[1].blocks) do
        for _, ins in ipairs(block.instructions) do if ins.op == "Call" then call = ins; break end end
    end
    assert(call and call.receiver)
    local receiver = call.receiver
    call.receiver = nil; H.raises("bug", "invalid-ir", function() IR.verify(program) end)
    call.receiver = {root = program.functions[1].parameters[1].id, type = receiver.type, path = {}}
    H.raises("bug", "invalid-ir", function() IR.verify(program) end)
    call.receiver = {root = receiver.root, type = s.U32, path = receiver.path}
    H.raises("bug", "invalid-ir", function() IR.verify(program) end)
    call.receiver = receiver; assert(IR.verify(program))
end)

H.test("failed method compilation retains no receiver reservations", function()
    local s = Word.new{max_functions = 1}; local m = s:load(H.root .. "examples/recursive_methods.lua")
    H.raises("resource", "function-instances", function() s:compile(m) end)
    H.eq(s._engine.scope:current(), nil)
    s._engine.max_functions = 128; local first = s:emit_c(m); H.eq(s:emit_c(m), first)
end)
