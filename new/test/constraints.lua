local H = ...
local Word = require("word")
local IR = require("word.ir")
local Model = require("word.model")

H.test("declared results type ungrounded open and closed recursion without guessed values", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/result_constraints.lua")
    local p = s:compile(m); H.eq(#p.functions, 3); assert(IR.verify(p))
    local c = s:emit_c(m); assert(c:find("for (;;)", 1, true))
    H.raises("reject", "recursive-result", function() s:compile{functions = {f = m.functions.cycle}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("pending groups can use different declared result ABIs without a completed base return", function()
    local s = Word.new(); local a, b
    a = s.word(s.U32, function(n) if b(n):eq(true) then return a(n - 1) end; return a(n + 1) end)
    b = s.word(s.U32, function(n) if a(n):eq(0) then return b(n - 1) end; return b(n + 1) end)
    local spec = {functions = {a = a}, results = {[a] = s.U32, [b] = s.Bool}}
    local p = s:compile(spec); assert(IR.verify(p)); H.eq(#p.functions, 2)
    assert(p.functions[1].result ~= p.functions[2].result)
end)

H.test("declarations check all return paths and already-inlined calls", function()
    local s = Word.new(); local U32 = s.U32
    local bad = s.word(U32, function(n) if n:gt(0) then return n end; return false end)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = bad}, results = {[bad] = U32}} end)
    local helper = s.word(U32, function(n) return n + 1 end)
    local root = s.word(U32, function(n) return helper(n) end)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = root}, results = {[helper] = s.Bool}} end)
    local pair = s.word(U32, function(n) return n, false end)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = pair}, results = {[pair] = {U32, U32}}} end)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = pair}, results = {[pair] = U32}} end)
    assert(IR.verify(s:compile{functions = {f = pair}, results = {[pair] = {U32, s.Bool}}}))
end)

H.test("new declarations cannot bypass static-call checks through cached outer results", function()
    local s = Word.new(); local U32 = s.U32
    local helper = s.word(U32, function(n) return n + 1 end)
    local root = s.word(function() return helper(3) end)
    H.eq(s:value(s:normalize(root)), 4)
    H.raises("reject", "branch-result", function() s:compile{functions = {f = root}, results = {[helper] = s.Bool}} end)
    H.eq(s:value(s:normalize(root)), 4); H.eq(s._engine.scope:current(), nil)
    assert(IR.verify(s:compile{functions = {f = root}, results = {[helper] = U32}}))
end)

H.test("export factories retain declarations on the actual runtime producer", function()
    local s = Word.new(); local f
    f = s.word(s.U32, function(n) return f(n + 1) end)
    local factory = s.word(function() return f end)
    assert(IR.verify(s:compile{functions = {f = factory}, results = {[f] = s.U32}}))
    H.raises("reject", "branch-result", function() s:compile{functions = {f = factory}, results = {[factory] = s.U32}} end)
end)

H.test("result declarations validate dense type lists, session identity and runtime representation", function()
    local s = Word.new(); local f = s.word(function() return 7 end)
    H.raises("reject", "result-constraint", function() s:compile{results = false} end)
    H.raises("reject", "result-constraint", function() s:compile{results = {[f] = {[2] = s.U32}}} end)
    H.raises("reject", "result-constraint", function() s:compile{results = {[s.U32] = s.U32}} end)
    H.raises("reject", "runtime-type", function() s:compile{results = {[f] = s.Type}} end)
    H.raises("reject", "foreign-session", function() s:compile{results = {[f] = Word.new().U32}} end)
    H.raises("reject", "expected-word", function() s:compile{results = {unknown = s.U32}} end)
    assert(IR.verify(s:compile{functions = {f = f}, results = {[f] = {s.U32}}}))
    local unit = s.word(function() end)
    assert(IR.verify(s:compile{functions = {f = unit}, results = {[unit] = {}}}))
end)

H.test("receiver result declarations share code, reject conflicting aliases and retain safe self tails", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, spin = word(U32, function(n) return spin(n + 1) end)}
        return {C = C, f = word(U32, function(n) local c = C{value = 0}; return c.spin(n) end)}
    ]])
    local spec = {functions = {f = m.f}, results = {[m.C.spin] = s.U32}}
    local p = s:compile(spec); assert(IR.verify(p)); assert(p.functions[2].receiver)
    assert(s:emit_c(spec):find("for (;;)", 1, true))
    local a, b = m.C{value = 1}, m.C{value = 2}
    H.raises("reject", "result-constraint", function()
        s:compile{functions = {f = m.f}, results = {[a.spin] = s.U32, [b.spin] = s.Bool}}
    end)
    s._engine.max_functions = 1
    H.raises("resource", "function-instances", function() s:compile(spec) end)
    s._engine.max_functions = 128; H.eq(s._engine.scope:current(), nil); assert(IR.verify(s:compile(spec)))
end)

H.test("explicit result lists supply unknown recursive result arity", function()
    local s = Word.new(); local pair
    pair = s.word(s.U32, function(n) return pair(n + 1) end)
    local p = s:compile{functions = {f = pair}, results = {[pair] = {s.U32, s.Bool, s.Unit}}}
    local t = Model.record(p.functions[1].result)
    H.eq(t.tuple_arity, 3); H.eq(t.fields.r2, s.Bool); assert(IR.verify(p))
end)
