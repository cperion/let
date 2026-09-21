local H = ...
local Word = require("word")
local IR = require("word.ir")
local Trace = require("word.trace")

H.test("symbolic comparisons assemble typed branch trees and known conditions do not fork", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/branches.lua")
    local fn = s:compile{functions = {f = m.functions.piecewise}}.functions[1]
    H.eq(#fn.blocks, 3); H.eq(fn.blocks[1].exit.op, "Branch")
    H.eq(fn.blocks[1].instructions[2].op, "Compare"); assert(IR.verify_function(fn))
    H.eq(s:value(m.functions.piecewise(9)), 18); H.eq(s:value(m.functions.piecewise(10)), 15)
    H.eq(#s:compile{functions = {f = m.functions.piecewise:of(9)}}.functions[1].blocks, 1)
end)

H.test("replay emits a prefix store once and keeps branch-local storage in its arm", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/branches.lua")
    local fn = s:compile{functions = {f = m.functions.update}}.functions[1]
    local stores = 0
    for _, ins in ipairs(fn.blocks[1].instructions) do if ins.op == "Store" then stores = stores + 1 end end
    H.eq(stores, 1); H.eq(#fn.blocks, 7)
    local p = m.types.State{count = 2, flag = false}
    local yes, no = m.functions.update(p, 2), m.functions.update(p, 9)
    H.eq(s:value(yes.count), 16); H.eq(s:value(yes.flag), true)
    H.eq(s:value(no.count), 7); H.eq(s:value(no.flag), false)
    H.eq(s:value(p.count), 2)
end)

H.test("short circuit preserves receiver effects and comparison results become Bool", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/branches.lua")
    for _, x in ipairs({0, 5}) do
        for _, y in ipairs({0, 5}) do
            local p = m.types.State{count = 0, flag = false}
            local out = m.functions.short_circuit(p, x, y)
            H.eq(s:value(out.count), x < 5 and 2 or 1)
            H.eq(s:value(out.flag), x < 5 and y < 5)
        end
    end
    local program = s:compile{functions = m.functions}
    for _, fn in ipairs(program.functions) do assert(IR.verify_function(fn)) end
end)

H.test("all leaves must agree on semantic result type", function()
    local s = Word.new(); local m = s:load_string([[
        local P = word{x = U32}
        local A, B = P:of{x = 1}, P:of{x = 2}
        return {scalar = word(U32, function(x) if x:lt(1) then return x else return true end end),
            unit = word(U32, function(x) if x:lt(1) then return else return x end end),
            record = word(U32, function(x) if x:lt(1) then return A{} else return B{} end end)}
    ]])
    for _, f in pairs(m) do
        H.raises("reject", "branch-result", function() s:compile{functions = {f = f}} end)
        H.eq(s._engine.scope:current(), nil)
    end
end)

H.test("path failure leaves no partial artifact and retry can raise the path budget", function()
    local s = Word.new{max_paths = 1}
    local f = s.word(s.U32, function(x) if x:lt(10) then return x + 1 else return x - 1 end end)
    local hook, mask, count = debug.gethook()
    H.raises("resource", "trace-paths", function() s:compile{functions = {f = f}} end)
    H.eq(s._engine.scope:current(), nil)
    local h, m, c = debug.gethook(); H.eq(h, hook); H.eq(m, mask); H.eq(c, count)
    s._engine.max_paths = 2
    H.eq(#s:compile{functions = {f = f}}.functions[1].blocks, 3)
end)

H.test("the instruction budget covers the assembled tree, not just each replay", function()
    local s = Word.new{max_values = 15}
    local f = s.word(s.U32, function(x)
        if x:lt(1) then return ((x + 2) * 3 + 4) * 5 else return ((x + 6) * 7 + 8) * 9 end
    end)
    H.raises("resource", "ir-values", function() s:compile{functions = {f = f}} end)
    H.eq(s._engine.scope:current(), nil)
    s._engine.max_values = 100
    H.eq(#s:compile{functions = {f = f}}.functions[1].blocks, 3)
end)

H.test("unbounded symbolic Lua loops stop at the decision-depth limit", function()
    local s = Word.new()
    local f = s.word(s.U32, function(x) while x:gt(0) do x = x - 1 end; return x end)
    H.raises("resource", "trace-depth", function() s:compile{functions = {f = f}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("fork unwinding checks mutations and genuine errors are not swallowed", function()
    local s = Word.new(); local changed = 0
    local f = s.word(s.U32, function(x)
        changed = changed + 1
        if x:lt(10) then return x else return x + 1 end
    end)
    H.raises("reject", "capture-changed", function() s:compile{functions = {f = f}} end)
    H.eq(changed, 1); H.eq(s._engine.scope:current(), nil)
    local m = s:load_string([[return {f = word(U32, function(x)
        if x:lt(10) then return x else return unavailable end
    end)}]])
    for _ = 1, 2 do
        H.raises("reject", "unknown-name", function() s:compile{functions = m} end)
        H.eq(s._engine.scope:current(), nil)
    end
end)

H.test("prefix validation detects changed constants, stores, calls, predicates and missing decisions", function()
    -- Synthetic driver inputs deliberately violate replay purity; these are not supported DSL programs.
    local s = Word.new(); local P = s:type(s.word{a = s.U32, b = s.U32})
    local a = s.word(s.U32, function(x) return x end)
    local b = s.word(s.U32, function(x) return x end)
    for _, mode in ipairs({"constant", "store", "call", "predicate", "return"}) do
        local runs = 0
        H.raises("reject", "replay-diverged", function()
            Trace.explore(function(oracle)
                runs = runs + 1
                local builder = IR.builder(100, oracle); oracle.builder = builder
                local x = builder:parameter(s.U32)
                if runs > 1 and mode == "return" then return builder:finish(s.U32, x) end
                local changed = runs > 1
                local n = builder:constant(s.U32, changed and mode == "constant" and 2 or 1)
                local root = builder:local_record(P, builder:construct(P, {a = n, b = n}))
                builder:store(s.U32, root, {changed and mode == "store" and "b" or "a"}, x)
                oracle:enter(changed and mode == "call" and b or a, {s.U32(1)})
                local predicate = builder:emit{op = "Compare", type = s.Bool, operand_type = s.U32,
                    predicate = changed and mode == "predicate" and "eq" or "lt", args = {x, n}}
                oracle:choose(predicate)
                return builder:finish(s.U32, x)
            end, 4, 100)
        end)
    end
end)

H.test("branch verifier enforces dominance, conditions, targets and predicate types", function()
    local s = Word.new()
    local f = s.word(s.U32, function(x) if x:lt(10) then return x + 1 else return x + 2 end end)
    local function bad(change)
        local fn = s:compile{functions = {f = f}}.functions[1]
        change(fn)
        H.raises("bug", "invalid-ir", function() IR.verify_function(fn) end)
    end
    bad(function(fn) fn.blocks[1].exit.condition = fn.parameters[1].id end)
    bad(function(fn) fn.blocks[1].exit.yes = 1 end)
    bad(function(fn) fn.blocks[1].exit.no = 999 end)
    bad(function(fn) fn.blocks[3].exit.value = fn.blocks[2].instructions[1].id end)
    bad(function(fn) fn.blocks[1].instructions[2].operand_type = s.Bool end)
end)

H.test("failed replay leaves clean frames and permits same-session retry", function()
    local s = Word.new{max_values = 1}; local m = s:load(H.root .. "examples/branches.lua")
    local hook, mask, count = debug.gethook()
    H.raises("resource", "ir-values", function() s:compile{functions = {f = m.functions.update}} end)
    H.eq(s._engine.scope:current(), nil)
    local h, msk, cnt = debug.gethook(); H.eq(h, hook); H.eq(msk, mask); H.eq(cnt, count)
    s._engine.max_values = 10000
    assert(IR.verify(s:compile{functions = {f = m.functions.update}}))
end)
