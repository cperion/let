local H = ...
local Word = require("word")
local IR = require("word.ir")
local function calls(fn)
    local out = {}
    for _, block in ipairs(fn.blocks) do for _, ins in ipairs(block.instructions) do
        if ins.op == "Call" then out[#out + 1] = ins end
    end end
    return out
end

H.test("explicit outlining contains replay multiplication at shared function boundaries", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/outlining.lua")
    H.raises("resource", "trace-paths", function() s:compile{functions = m.functions} end)
    H.eq(s._engine.scope:current(), nil)
    local p = s:compile(m); assert(IR.verify(p))
    H.eq(#p.functions, 2)
    local top = p.functions[p.exports[1].target]
    local cs = calls(top)
    H.eq(#cs, 2); H.eq(cs[1].target, cs[2].target)
    H.eq(#top.blocks, 63); H.eq(#p.functions[cs[1].target].blocks, 63)
    H.eq(s:value(m.functions.top(0,0,0,0,0,0,0,0,0,0)), 687)
    H.eq(s:emit_c(m), s:emit_c(m))
    -- Policy is compilation-local, not a mutation of the source word.
    H.raises("resource", "trace-paths", function() s:compile{functions = m.functions} end)
end)

H.test("outline entries select exact static specializations without losing static erasure", function()
    local s = Word.new(); local m = s:load_string([[
        local scale = word(U32, U32, function(k, x) return k * x end)
        local twice, thrice = scale:of(2), scale:of(3)
        return {outline = {twice, twice}, functions = {run = word(U32, function(x)
            return twice(x) + thrice(x) + scale(4, x)
        end)}}
    ]])
    local p = s:compile(m); H.eq(#p.functions, 2)
    local cs = calls(p.functions[p.exports[1].target])
    H.eq(#cs, 1); H.eq(#p.functions[cs[1].target].parameters, 1)
    H.eq(s:value(m.functions.run(7)), 63)
end)

H.test("outlining follows callable factory application without retaining its Type input", function()
    local s = Word.new(); local m = s:load_string([[
        local Identity = word(Type, function(T) return word(T, function(x) return x end) end)
        local id32 = Identity:of(U32)
        local Callback = word(U32)
        return {outline = {id32}, results = {[Callback] = U32},
            functions = {run = word(U32, function(x) return id32(x) end)}}
    ]])
    local p = s:compile(m); H.eq(#p.functions, 2)
    local cs = calls(p.functions[p.exports[1].target]); H.eq(#cs, 1)
    local helper = p.functions[cs[1].target]
    H.eq(#helper.parameters, 1); H.eq(helper.parameters[1].type, s.U32); H.eq(helper.result, s.U32)
    H.eq(s:emit_c(m), s:emit_c(m))
end)

H.test("factory policy discovery restarts replay even for an already compiled callee", function()
    local s = Word.new(); local m = s:load_string([[
        local f = word(U32, function(x) if x:lt(5) then return x + 1 end; return x + 2 end)
        local factory = word(function() return f end)
        return {outline = {factory}, functions = {a_helper = f, top = word(U32, function(x)
            local first = f(x)
            return first + factory(x)
        end)}}
    ]])
    local p = s:compile(m); assert(IR.verify(p)); H.eq(#p.functions, 2)
    local top = p.functions[p.exports[2].target]; H.eq(#top.blocks, 1)
    local cs = calls(top); H.eq(#cs, 2); H.eq(cs[1].target, p.exports[1].target)
    H.eq(cs[1].target, cs[2].target)
end)

H.test("outlined methods and owned or borrowed callable boundaries retain their ABIs", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/outlined_calls.lua")
    H.eq(s:value(m.functions.scaled(7)), 35); H.eq(s:value(m.functions.owned(5)), 7)
    local before, a, b, r, result, value = m.functions.borrowed(5)
    for i, v in ipairs({before, a, b, r, result, value}) do H.eq(s:value(v), ({3,8,9,13,20,15})[i]) end
    local p = s:compile(m); assert(IR.verify(p))
    local alone = s:compile{functions = {f = m.functions.identity_callback}, outline = m.outline, results = m.results}
    H.eq(#alone.functions, 3); assert(IR.verify(alone))
    assert(next(require("word.borrow").verify(p)))
    local self_calls, receiver_calls = 0, 0
    for _, fn in ipairs(p.functions) do for _, ins in ipairs(calls(fn)) do
        if ins.target == "self" then self_calls = self_calls + 1 end
        if ins.receiver then receiver_calls = receiver_calls + 1 end
    end end
    assert(self_calls > 0 and receiver_calls > 0)
end)

H.test("outlined method selections resolve signature-valued owner layouts and result contracts", function()
    local s = Word.new(); local m = s:load_string([[
        local F = word(U32)
        local C = word{cb = F, apply = word(U32, function(x) return cb(x) end)}
        local id = word(U32, function(x) return x end)
        return {C = C, F = F, method = C.apply,
            run = word(U32, function(x) local c = C{cb = id}; return c.apply(x) end)}
    ]])
    local spec = {functions = {run = m.run}, outline = {m.method}, results = {[m.F] = s.U32}}
    local p = s:compile(spec); assert(IR.verify(p)); H.eq(#p.functions, 3)
    H.eq(#calls(p.functions[p.exports[1].target]), 1)
    local entry = s:compile{types = {C = m.C}, functions = {apply = m.method},
        outline = {m.method}, results = spec.results}
    H.eq(#entry.functions, 1); H.eq(entry.functions[1].receiver.type, entry.types[1].type)
    spec.results[m.method] = s.Bool
    H.raises("reject", "branch-result", function() s:compile(spec) end)
end)

H.test("outlined immutable receiver specializations erase their storage ABI", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{bias = U32, read = word(Unit, function() return bias end)}
        local Fixed = C:of{bias = 7}
        return {outline = {Fixed.read}, functions = {run = word(U32, function(x) return Fixed.read(nil) + x end)}}
    ]])
    local p = s:compile(m); H.eq(#p.functions, 2)
    local cs = calls(p.functions[p.exports[1].target]); H.eq(#cs, 1)
    H.eq(cs[1].receiver, nil)
    local helper = p.functions[cs[1].target]; H.eq(helper.receiver, nil); H.eq(#helper.parameters, 0)
end)

H.test("outlining leaves required type normalization unchanged and does not compile unused entries", function()
    local s = Word.new(); local m = s:load_string([[
        local scalar = word(function() return U32 end)
        local unused = word(Type, function(T) return T end)
        return {outline = {scalar, unused}, functions = {run = word(scalar, function(x) return x + 1 end)}}
    ]])
    local p = s:compile(m); H.eq(#p.functions, 1)
    H.eq(s:value(m.functions.run(5)), 6)
end)

H.test("requested boundaries reject missing runtime ABIs instead of silently inlining", function()
    local s = Word.new(); local m = s:load_string([[
        local id = word(Type, U32, function(T, x) return x end)
        local Callback = word(U32)
        local apply = word(Callback, U32, function(f, x) return f(x) end)
        local inc = word(U32, function(x) return x + 1 end)
        local mul = word(U32, U32, function(n, x) return n * x end)
        local bind = word(U32, U32, function(n, x) return mul:of(n)(x) end)
        return {id = id, apply = apply, bind = bind,
            known = word(U32, function(x) return bind(3, x) end),
            typed = word(U32, function(x) return id(U32, x) end),
            callback = word(U32, function(x) return apply(inc, x) end)}
    ]])
    assert(s:compile{functions = {run = m.typed}})
    H.raises("reject", "static-required", function()
        s:compile{functions = {run = m.typed}, outline = {m.id}}
    end)
    H.raises("reject", "callable-result", function()
        s:compile{functions = {run = m.callback}, outline = {m.apply}}
    end)
    assert(s:compile{functions = {run = m.known}})
    H.raises("reject", "static-required", function()
        s:compile{functions = {run = m.known}, outline = {m.bind}}
    end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("explicitly outlined mutual recursion grounds results without recursive inlining", function()
    local s = Word.new(); local m = s:load_string([[
        local even, odd
        even = word(U32, function(n)
            if U32(0):lt(n) then return odd(n - 1) end
            return Bool(true)
        end)
        odd = word(U32, function(n)
            if U32(0):lt(n) then return even(n - 1) end
            return Bool(false)
        end)
        return {functions = {even = even}, outline = {even, odd}}
    ]])
    local p = s:compile(m); assert(IR.verify(p)); H.eq(#p.functions, 2)
    H.eq(s:value(m.functions.even(6)), true)
    H.eq(s:value(m.functions.even(7)), false)
end)

H.test("explicit boundaries do not permit escaping borrowed captures", function()
    local s = Word.new(); local m = s:load_string([[
        local State = word{value = U32}
        local escape = word(State, function(state)
            return word(U32, function(x) return state.value + x end)
        end)
        return {outline = {escape}, functions = {run = word(State, U32, function(state, x)
            return escape(state)(x)
        end)}}
    ]])
    H.raises("reject", "borrow-escape", function() s:compile(m) end)
end)

H.test("outline specifications validate dense executable selections", function()
    local s = Word.new(); local f = s.word(s.U32, function(x) return x end)
    local other = Word.new(); local foreign = other.word(other.U32, function(x) return x end)
    for _, list in ipairs({false, {name = f}, {[2] = f}, {s.U32}, {s.word(s.U32)}, {foreign}}) do
        H.raises("reject", "outline", function() s:compile{functions = {f = f}, outline = list} end)
    end
    assert(s:compile{functions = {f = f}, outline = {f}}) -- the entry's body must execute
end)
