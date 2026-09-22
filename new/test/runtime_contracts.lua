local H = ...
local Word = require("word")
local IR = require("word.ir")

H.test("runtime callable declarations are checked through nested record inputs", function()
    local s = Word.new(); local Signature = s.word(s.U32)
    local Holder = s.word{callback = Signature}
    local Outer = s.word{inner = Holder}
    local f = s.word(Outer, s.U32, function(o, x) return o.inner.callback(x) end)
    H.raises("reject", "callable-result", function() s:compile{functions = {f = f}} end)
    assert(IR.verify(s:compile{functions = {f = f}, results = {[Signature] = s.U32}}))
    -- A declaration belongs to this compilation, not the schema or the session.
    H.raises("reject", "callable-result", function() s:compile{functions = {f = f}} end)
end)

H.test("nested runtime calling requirements need each unknown result contract", function()
    local s = Word.new(); local Inner = s.word(s.U32); local Outer = s.word(Inner, s.U32)
    local f = s.word(Outer, Inner, s.U32, function(apply, callback, x) return apply(callback, x) end)
    H.raises("reject", "callable-result", function()
        s:compile{functions = {f = f}, results = {[Outer] = s.U32}}
    end)
    assert(IR.verify(s:compile{functions = {f = f}, results = {[Inner] = s.U32, [Outer] = s.U32}}))
end)

H.test("declared runtime callbacks cross recursive helper ABIs without static binding", function()
    local s = Word.new(); local m = s:load_string([[
        local Signature = word(U32)
        local loop
        loop = word(Signature, U32, function(callback, n)
            if n:eq(0) then return callback(n) end
            return loop(callback, n - 1) + 1
        end)
        local inc = word(U32, function(x) return x + 2 end)
        return {Signature = Signature, loop = loop,
            run = word(Signature, U32, function(callback, n) return loop(callback, n) end),
            known = word(U32, function(n) return loop(inc, n) end)}
    ]])
    local spec = {functions = {run = m.run}, results = {[m.Signature] = s.U32}}
    local p = s:compile(spec)
    assert(IR.verify(p)); H.eq(#p.functions, 2)
    H.eq(s:value(m.known(4)), 6)
    assert(IR.verify(s:compile{functions = {known = m.known}, results = {[m.Signature] = s.U32}}))
    H.eq(s:emit_c(spec), s:emit_c(spec))
end)

H.test("input-only callable requirements remain valid when supplied statically", function()
    local s = Word.new(); local Signature = s.word(s.U32)
    local apply = s.word(Signature, s.U32, function(f, x) return f(x) end)
    local predicate = s.word(s.U32, function(x) return x:eq(0) end)
    local f = apply:of(predicate)
    H.eq(s:value(f(0)), true); H.eq(s:value(f(1)), false)
    assert(IR.verify(s:compile{functions = {f = f}}))
end)
