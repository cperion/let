local H = ...
local Word = require("word")
local IR = require("word.ir")
local Borrow = require("word.borrow")

H.test("borrowed callback and storage captures have explicit non-retaining environments", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/borrowed_captures.lua")
    local callback = s.word(s.U32, function(x) return x + 7 end)
    local c, other = m.types.Counter{value = 3}, m.types.State{value = 10}
    local result, copied = c.run(callback, other, 4)
    H.eq(s:value(result), 35); H.eq(s:value(copied), 18)
    H.eq(s:value(c.value), 7); H.eq(s:value(other.value), 10)
    H.eq(s:value(m.functions.plain(callback, 3)), 14)
    H.eq(s:value(m.functions.frozen(callback, 3)), 18)
    local p = s:compile(m); assert(IR.verify(p))
    local environments, addresses = 0, 0
    for _, fn in ipairs(p.functions) do for _, block in ipairs(fn.blocks) do for _, ins in ipairs(block.instructions) do
        if ins.op == "Capture" then environments = environments + 1; assert(Borrow.type(ins.type)) end
        if ins.op == "Address" then addresses = addresses + 1 end
    end end end
    assert(environments > 0 and addresses > 0)
    H.eq(s:emit_c(m), s:emit_c(m))
end)

H.test("captured places preserve aliases, lexical roots and by-value result boundaries", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/borrowed_captures.lua")
    H.eq(s:value(m.functions.replacement(4)), 34)
    H.eq(s:value(m.functions.paths(0)), 30); H.eq(s:value(m.functions.paths(4)), 15)
    local result, count = m.functions.method(4)
    H.eq(s:value(result), 4); H.eq(s:value(count), 4)
    local state = m.types.State{value = 3}
    local copied = m.functions.copy(state, 4)
    H.eq(s:value(copied.value), 7); H.eq(s:value(state.value), 3)
    H.eq(s:value(m.functions.frames(4)), 11)
    assert(IR.verify(s:compile(m)))
end)

H.test("borrowed capture environments prevent unsafe self-tail replacement", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/borrowed_captures.lua")
    local p = s:compile(m); local calls = Borrow.verify(p); local protected = 0
    for _, fn in ipairs(p.functions) do for _, block in ipairs(fn.blocks) do for _, ins in ipairs(block.instructions) do
        if ins.op == "Call" and ins.target == "self" and ins.captures then
            assert(calls[ins]); protected = protected + 1
        end
    end end end
    assert(protected > 0)
end)

H.test("captured borrows cannot escape as closures or hide in source records", function()
    local s = Word.new(); local m = s:load_string([[
        local Callback = word(U32)
        local State = word{value = U32}
        local Holder = word{f = Callback}
        local C = word{value = U32, escape = word(Callback, function(callback)
            return word(U32, function(x) return value + callback(x) end)
        end)}
        return {results = {[Callback] = U32}, functions = {
            callback = word(Callback, function(callback)
                return word(U32, function(x) return callback(x) end)
            end),
            storage = word(State, function(state)
                return word(U32, function(x) state.value = state.value + x; return state.value end)
            end),
            field = word(Callback, function(callback)
                local f = word(U32, function(x) return callback(x) end)
                return Holder{f = f}
            end),
            lexical = C.escape,
            frozen = C:of{value = 3}.escape,
        }}
    ]])
    for _, f in pairs(m.functions) do
        H.raises("reject", "borrow-escape", function() s:compile{functions = {f = f}, results = m.results} end)
        H.eq(s._engine.scope:current(), nil)
    end
end)

H.test("borrowed captures keep their bindings immutable", function()
    local s = Word.new(); local m = s:load_string([[
        local Callback = word(U32)
        local identity = word(U32, function(x) return x end)
        return {results = {[Callback] = U32}, functions = {f = word(Callback, U32, function(callback, n)
            local inner = word(U32, function(x) callback = identity; return callback(x) end)
            return inner(n)
        end)}}
    ]])
    H.raises("reject", "capture-changed", function() s:compile(m) end)
end)

H.test("borrowed reference IR validates types and does not authorize retaining record construction", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/borrowed_captures.lua")
    local function program() return s:compile{functions = {f = m.functions.replacement}} end
    local p = program(); local found
    for _, fn in ipairs(p.functions) do for _, block in ipairs(fn.blocks) do for _, ins in ipairs(block.instructions) do
        if ins.op == "Capture" then ins.op = "Construct"; found = true end
    end end end
    assert(found)
    H.raises("reject", "borrow-escape", function() Borrow.verify(p) end)
    H.raises("reject", "borrow-escape", function() require("word.c").emit(p) end)
    for _, op in ipairs({"Address", "Deref"}) do
        p = program(); found = nil
        for _, fn in ipairs(p.functions) do for _, block in ipairs(fn.blocks) do for _, ins in ipairs(block.instructions) do
            if ins.op == op then
                if op == "Address" then ins.target_type = s.U32 else ins.reference_type = s.U32 end
                found = true
            end
        end end end
        assert(found)
        H.raises("bug", "invalid-ir", function() IR.verify(p) end)
    end
end)
