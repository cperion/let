local H = ...
local Word = require("word")
local Model = require("word.model")

H.test("extracted methods retain independent immediate receivers", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/methods.lua")
    local a, b = m.types.Fast{count = 1}, m.types.Fast{count = 10}
    local fa, fb = a.step, b.step
    H.eq(s:value(fa(3)), 7); H.eq(s:value(fb(4)), 18)
    H.eq(s:value(fa(1)), 9); H.eq(s:value(b.count), 18)
    local snapshot = s:value(a)
    H.eq(snapshot.count, 9); H.eq(snapshot.gain, 2); H.eq(snapshot.step, nil)
    H.raises("reject", "method-write", function() a.step = fa end)
    H.raises("reject", "unknown-field", function() m.types.Fast{count = 1, step = fa} end)
end)

H.test("bound specialization retains storage without entering static metadata", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/methods.lua")
    local c = m.types.Fast{count = 1}
    local f = c.step:of(3)
    H.eq(s:value(f()), 7); H.eq(s:value(f()), 13)
    H.eq(Model.word(f).result, nil)
    H.raises("reject", "runtime-in-normalization", function() s:normalize(f) end)
    local apply = s.word(s.word(s.U32), s.U32, function(g, n) return g(n) end)
    H.raises("reject", "static-required", function() apply:of(c.step) end)
    H.raises("reject", "missing-receiver", function() m.types.Fast.step(1) end)
    assert(s:compile{functions = {step = m.types.Fast.step}}.functions[1].receiver)
end)

H.test("method callbacks mutate the receiver but ordinary record arguments copy", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/methods.lua")
    local c = m.types.Fast{count = 5}
    local out = m.functions.advance(c, 3)
    H.eq(s:value(c.count), 5); H.eq(s:value(out.count), 19)
    H.eq(s:value(m.functions.sibling(c, 3).count), 17)
    local box = m.types.Box{inner = c}
    H.eq(s:value(m.functions.nested(box, 20).inner.count), 26)
    H.eq(s:value(box.inner.count), 5)
end)

H.test("shared child definitions do not acquire a mutable parent", function()
    local s = Word.new(); local m = s:load_string([[
        local step = word(U32, function(n) count = count + gain * n; return count end)
        local A = word{count = U32, gain = U32, step = step}:of{gain = 1}
        local B = word{count = U32, gain = U32, step = step}:of{gain = 3}
        return {A = A, B = B}
    ]])
    local a, b = m.A{count = 0}, m.B{count = 0}
    H.eq(s:value(a.step(2)), 2); H.eq(s:value(b.step(2)), 6)
    H.eq(s:value(a.step(2)), 4)
    assert(s:type(m.A) ~= s:type(m.B))
end)

H.test("method identities participate in schemas and type demand never runs open methods", function()
    local s = Word.new(); local m = s:load_string([[
        local a = word(U32, function(n) return n + 1 end)
        local b = word(U32, function(n) return n + 2 end)
        local bad = word(Unit, function() while true do end end)
        return {A = word{x = U32, f = a}, Same = word{f = a, x = U32},
            B = word{x = U32, f = b}, Unused = word{bad = bad}}
    ]])
    H.eq(s:type(m.A), s:type(m.Same)); assert(s:type(m.A) ~= s:type(m.B))
    local p = m.Unused{}; H.eq(next(s:value(p)), nil)
    s:emit_c{types = {Unused = m.Unused}}
end)

H.test("receiver scope respects parameters, upvalues, static false and write protection", function()
    local s = Word.new(); local m = s:load_string([[
        local captured = U32(90)
        return {C = word{count = U32, captured = U32, flag = Bool,
            param = word(U32, function(count) return count + 1 end),
            local_value = word(Unit, function() return captured end),
            flag_value = word(Unit, function() return flag end),
            set = word(U32, function(n) count = n end),
        }:of{flag = false}}
    ]])
    local c = m.C{count = 10, captured = 7}
    H.eq(s:value(c.param(2)), 3); H.eq(s:value(c.local_value(nil)), 90)
    H.eq(s:value(c.flag_value(nil)), false)
    local fixed = m.C:of{count = 4}{captured = 7}
    H.raises("reject", "static-field", function() fixed.set(8) end)
    H.eq(s:value(fixed.count), 4)
end)

H.test("word calls cannot inherit a caller receiver and errors restore scope", function()
    local s = Word.new(); local m = s:load_string([[
        local outsider = word(Unit, function() return count end)
        return {outside = outsider, C = word{count = U32,
            fail = word(Unit, function() return outsider(nil) end),
            read = word(Unit, function() return count end),
            wrong = word(Unit, function() absent = U32(1) end),
        }}
    ]])
    local c = m.C{count = 8}
    H.raises("reject", "unknown-name", function() c.fail(nil) end)
    H.raises("reject", "module-write", function() c.wrong(nil) end)
    H.eq(s:value(c.read(nil)), 8)
    H.raises("reject", "unknown-name", function() m.outside(nil) end)
    H.eq(#Model.word(m.C).engine.scope:stack(), 0)
end)

H.test("environment hooks exclude unregistered raw helpers", function()
    -- Exercise the production hook directly: arbitrary helper captures remain unsupported.
    local scope = require("word.scope").new(100000)
    local env = scope:environment{count = 99}
    local direct, indirect, write = assert(load([[
        local function helper() return count end
        return function() return count end, function() return helper() end,
            function() count = 4; return count end
    ]], "scope helpers", "t", env))()
    local value = false
    local frame = {has_member = function(k) return k == "count" end,
        read_member = function() return value end, write_member = function(_, v) value = v end}
    frame.terminal = direct; H.eq(scope:with(frame, direct), false)
    frame.terminal = indirect; H.eq(scope:with(frame, indirect), 99)
    frame.terminal = write; H.eq(scope:with(frame, write), 4)
    H.eq(env.count, 99); H.eq(#scope:stack(), 0)
end)

H.test("receiver returns and captured receivers reject rather than leaking storage", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{count = U32, step = word(U32, function(n) count = count + n; return count end)}
        return {C = C, escape = word(U32, function(n) return C{count = n}.step end)}
    ]])
    H.raises("reject", "borrow-escape", function() m.escape(3) end)
    H.raises("reject", "borrow-escape", function() s:compile{functions = {escape = m.escape}} end)
    local f = m.C{count = 1}.step
    local captured = s.word(s.U32, function(n) return f(n) end)
    H.raises("todo", "host-captures", function() s:compile{functions = {captured = captured}} end)
end)

H.test("receiver errors restore frames for a later call", function()
    local s = Word.new(); local m = s:load_string([[
        return {C = word{count = U32, read = word(Unit, function() return count end),
            fail = word(Unit, function() local missing = nil; return missing.field end)}}
    ]])
    local c = m.C{count = 42}
    local engine = Model.word(m.C).engine
    local hook, mask, count = debug.gethook()
    H.raises("lua", "terminal-error", function() c.fail(nil) end)
    H.eq(#engine.scope:stack(), 0)
    local h, msk, cnt = debug.gethook(); H.eq(h, hook); H.eq(msk, mask); H.eq(cnt, count)
    H.eq(s:value(c.read(nil)), 42)
end)

H.test("cross-receiver callbacks restore the outer receiver and closed bound callbacks work", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{count = U32,
            step = word(U32, function(n) count = count + n; return count end),
            delegate = word(word(U32), U32, function(f, n)
                count = count + 1
                f(n)
                return count
            end),
        }
        return {C = C, closed = word(word(), function(f) return f() end)}
    ]])
    local a, b = m.C{count = 1}, m.C{count = 10}
    H.eq(s:value(a.delegate(b.step, 5)), 2)
    H.eq(s:value(b.count), 15)
    H.eq(s:value(m.closed(a.step:of(3))), 5)
    H.eq(s:value(b.count), 15)
end)

H.test("a retained residual method is checked against its trace extent", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/methods.lua")
    local C, held = m.types.Fast, nil
    local f = s.word(s.U32, function(n)
        held = C{count = n}.step -- Forbidden host mutation, deliberately retained for the negative check.
        return n
    end)
    H.raises("todo", "host-captures", function() s:compile{functions = {f = f}} end)
    H.raises("reject", "symbol-extent", function() held(1) end)
    H.eq(#Model.word(C).engine.scope:stack(), 0)
end)
