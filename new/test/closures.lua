local H = ...
local Word = require("word")

H.test("immutable capture mutation rejects without changing the source closure", function()
    local s = Word.new(); local m = s:load_string([[
        return {make = word(U32, function(n)
            return word(U32, function(x) n = n + x; return n end)
        end)}
    ]])
    H.raises("reject", "capture-changed", function() s:compile{functions = m} end)
    local f = m.make(3)
    H.raises("reject", "capture-changed", function() f(2) end)
end)

H.test("runtime captures cannot enter static specialization or record method metadata", function()
    for _, body in ipairs({
        "local f = word(U32, function(x) return n + x end); return apply:of(f)(1)",
        "local C = word{read = word(Unit, function() return n end)}; return C{}",
    }) do
        local s = Word.new(); local m = s:load_string([[
            local Unary = word(U32)
            local apply = word(Unary, U32, function(f, x) return f(x) end)
            return {run = word(U32, function(n) ]] .. body .. [[ end)}
        ]])
        H.raises("reject", "capture-type", function() s:compile{functions = m} end)
    end
end)

H.test("immutable closures accept typed runtime callbacks without retaining them", function()
    local s = Word.new(); local m = s:load_string([[
        local Unary = word(U32)
        return {results = {[Unary] = U32}, functions = {make = word(U32, function(n)
            return word(Unary, U32, function(f, x) return n + f(x) end)
        end)}}
    ]])
    assert(require("word.ir").verify(s:compile(m)))
end)
