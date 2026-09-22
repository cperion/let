local H = ...
local Word = require("word")
local Host = require("word.host")

H.test("lexical construction uses prototype nesting rather than dynamic callers", function()
    local function outer() return function() return absent_lexical_probe end end
    local function unrelated() return function() return another_lexical_probe end end
    assert(Host.nested_terminal(outer, outer()))
    assert(not Host.nested_terminal(outer, unrelated()))
    assert(Host.environment_names(outer()).absent_lexical_probe)
    local cloned = Host.clone(outer)
    H.eq(Host.code_identity(cloned), Host.code_identity(outer))
    H.eq(Host.code_identity(cloned()), Host.code_identity(outer()))
end)

H.test("nested words bind their defining method receiver and sibling methods", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/lexical_locals.lua")
    local c = m.types.Counter{count = 3}
    H.eq(s:value(c.step(5)), 8)
    H.eq(s:value(c.sum(4)), 12)
    local frozen = c.snapshot(nil)
    c.add(10)
    H.eq(s:value(frozen(2)), 14)
    local supplied = frozen:of(2)
    H.eq(s:value(supplied()), 14)
    H.eq(supplied, frozen:of(2))
    local weak = setmetatable({frozen, supplied}, {__mode = "v"})
    frozen, supplied = nil, nil
    collectgarbage("collect"); collectgarbage("collect")
    H.eq(weak[1], nil); H.eq(weak[2], nil)
    assert(require("word.ir").verify(s:compile(m)))
end)

H.test("local lexical words can inline immutable snapshots alongside their receiver", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, run = word(U32, function(n)
            local before = value
            local f = word(U32, function(x) value = value + x; return value + before end)
            return f(n)
        end)}
        return {C = C, run = C.run}
    ]])
    local c = m.C{value = 3}
    H.eq(s:value(c.run(2)), 8); H.eq(s:value(c.value), 5)
    assert(require("word.ir").verify(s:compile{functions = {run = m.run}}))
end)

H.test("nested lexical receiver views cannot escape", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{count = U32, escape = word(Unit, function()
            return word(U32, function(x) return count + x end)
        end)}
        return {C = C, escape = C.escape}
    ]])
    H.raises("reject", "borrow-escape", function() m.C{count = 3}.escape(nil) end)
    H.raises("reject", "borrow-escape", function() s:compile{functions = {escape = m.escape}} end)
end)

H.test("module words do not inherit a dynamic caller's receiver", function()
    local s = Word.new(); local m = s:load_string([[
        local outside = word(U32, function(x) return count + x end)
        local C = word{count = U32, call = word(U32, function(x) return outside(x) end)}
        return {C = C}
    ]])
    H.raises("reject", "unknown-name", function() m.C{count = 3}.call(1) end)
    H.raises("reject", "unknown-name", function() s:compile{functions = {call = m.C.call}} end)
end)
