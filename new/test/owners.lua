local H = ...
local Word = require("word")
local Model = require("word.model")
local IR = require("word.ir")

H.test("nested keyed selections bind actual outer state and survive field replacement", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/lexical_owners.lua")
    local O = m.types.Outer
    local a = O{bias = 3, left = {value = 1}, right = {value = 9}}
    local b = O{bias = 30, left = {value = 2}, right = {value = 8}}
    local ar, br = a.left.read, b.left.read
    H.eq(s:value(ar()), 4); H.eq(s:value(br()), 32)
    a.left = {value = 7}
    H.eq(s:value(ar()), 10); H.eq(s:value(br()), 32)
    local step = a.left.step:of(2)
    H.eq(s:value(step()), 16); H.eq(s:value(a.bias), 5)
    H.eq(s:value(b.bias), 30)
    H.eq(s:value(m.functions.replace(50)), 53)
end)

H.test("recursive sibling occurrences share storage without sharing lexical paths", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/lexical_owners.lua")
    local a, b, bias, left, right = m.functions.run(4)
    H.eq(s:value(a), 23); H.eq(s:value(b), 46); H.eq(s:value(bias), 18)
    H.eq(s:value(left), 9); H.eq(s:value(right), 28)
    local p = s:compile(m); assert(IR.verify(p))
    local receivers = 0
    for _, fn in ipairs(p.functions) do
        if fn.receiver then
            receivers = receivers + 1
            H.eq(fn.receiver.type, s:type(m.types.Outer))
        end
    end
    H.eq(receivers, 2) -- left.step and right.step have distinct occurrences.
    H.eq(s:emit_c(m), s:emit_c(m))
end)

H.test("nearest keyed scope shadows outer fields and outer sibling methods retain their owner", function()
    local s = Word.new(); local m = s:load_string([[
        local O = word{value = U32, bias = U32,
            bump = word(U32, function(n) bias = bias + n end),
            middle = word{value = U32, inner = word{
                value = U32,
                read = word(function() return value + bias end),
                call = word(U32, function(n) bump(n); return read() end),
            }},
        }
        return {O = O, run = word(O, U32, function(o, n) return o.middle.inner.call(n) end)}
    ]])
    local o = m.O{value = 100, bias = 3, middle = {value = 50, inner = {value = 7}}}
    H.eq(s:value(o.middle.inner.call(2)), 12); H.eq(s:value(o.bias), 5)
    H.eq(s:value(m.run(o, 3)), 15); H.eq(s:value(o.bias), 5) -- argument copy
    assert(IR.verify(s:compile{functions = {run = m.run}}))
end)

H.test("shared child definitions do not retain a last parent or inherit dynamic callers", function()
    local s = Word.new(); local m = s:load_string([[
        local read = word(function() return bias + value end)
        local Child = word{value = U32, read = read}
        local A = word{bias = U32, child = Child}
        local B = word{bias = U32, other = Child}
        local outside = word(Unit, function() return bias end)
        local Caller = word{bias = U32, call = word(Unit, function() return outside(nil) end)}
        return {A = A, B = B, Caller = Caller, read = read,
            run = word(A, B, function(a, b) return a.child.read() + b.other.read() end)}
    ]])
    local a = m.A{bias = 2, child = {value = 3}}
    local b = m.B{bias = 20, other = {value = 4}}
    H.eq(s:value(a.child.read()), 5); H.eq(s:value(b.other.read()), 24)
    H.eq(s:value(a.child.read()), 5)
    H.eq(Model.word(m.read).owner, nil); H.eq(Model.word(m.read).definition.parent, nil)
    H.raises("reject", "unknown-name", function() m.Caller{bias = 7}.call(nil) end)
    assert(IR.verify(s:compile{functions = {run = m.run}}))
end)

H.test("deferred child schemas inherit declared owners but unrelated type demands do not", function()
    local s = Word.new(); local m = s:load_string([[
        local Child = word(function()
            return word{value = U32, read = word(function() return bias + value end)}
        end)
        local O = word{bias = U32, child = Child}
        local Unrelated = word{read = word(function() return bias end)}
        local Bad = word{bias = U32, child = word(function()
            local read = Unrelated.read
            return word{value = U32}
        end)}
        return {O = O, Bad = Bad, run = word(O, function(o) return o.child.read() end)}
    ]])
    H.eq(s:value(m.O{bias = 4, child = {value = 3}}.child.read()), 7)
    assert(IR.verify(s:compile{functions = {run = m.run}}))
    H.raises("reject", "unknown-name", function() s:type(m.Bad) end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("immutable nested snapshots retain only their selected actual owner occurrence", function()
    local s = Word.new(); local m = s:load_string([[
        local Inner = word{value = U32,
            read = word(Unit, function() return bias + value end),
            bump = word(U32, function(n) bias = bias + n; return bias + value end)}
        local Outer = word{bias = U32, left = Inner, right = Inner}
        local Fixed = Outer:of{bias = 3, left = {value = 4}, right = {value = 9}}
        local Half = Outer:of{left = {value = 4}, right = {value = 9}}
        local consume = word(Inner, function(child) return child.read(nil) end)
        return {Inner = Inner, Outer = Outer, Fixed = Fixed, Half = Half, consume = consume}
    ]])
    H.eq(s:value(m.Fixed.left.read(nil)), 7)
    H.eq(s:value(s:normalize(m.Fixed.right.read:of(nil))), 12)
    H.raises("reject", "missing-receiver", function() m.Half.left.read(nil) end)
    local h = m.Half{bias = 10}
    local left, right = h.left, h.right
    H.eq(s:value(left.read(nil)), 14); H.eq(s:value(right.read(nil)), 19)
    H.eq(s:value(left.bump(2)), 16); H.eq(s:value(h.bias), 12)
    H.raises("reject", "unknown-name", function() m.consume(left) end)
    local Detached = s.word{child = m.Inner}:of{child = m.Fixed.left}
    H.raises("reject", "unknown-name", function() Detached.child.read(nil) end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("borrowed immutable snapshot occurrences lift through their live root paths", function()
    local s = Word.new(); local m = s:load_string([[
        local Inner = word{value = U32, read = word(Unit, function() return bias + value end)}
        local Outer = word{bias = U32, left = Inner}
        local Half = Outer:of{left = {value = 4}}
        local Unary = word(U32)
        local apply = word(Unary, U32, function(f, x) return f(x) end)
        return {Unary = Unary, functions = {
            run = word(U32, U32, function(initial, n)
                local h = Half{bias = initial}
                local selected = h.left
                local loop
                loop = word(U32, function(x)
                    if x:eq(0) then return selected.read(nil) end
                    h.bias = h.bias + 1
                    return loop(x - 1)
                end)
                return loop(n)
            end),
            escape = word(U32, function(initial)
                local h = Half{bias = initial}
                local selected = h.left
                return word(U32, function(x) return selected.read(nil) + x end)
            end),
            metadata = word(U32, function(initial)
                local h = Half{bias = initial}
                local selected = h.left
                local f = word(U32, function(x) return selected.read(nil) + x end)
                return apply:of(f)(1)
            end),
        }}
    ]])
    H.eq(s:value(m.functions.run(10, 3)), 17)
    local program = s:compile{functions = {run = m.functions.run}}
    assert(IR.verify(program))
    local address, captures = false, false
    for _, fn in ipairs(program.functions) do for _, block in ipairs(fn.blocks) do
        for _, ins in ipairs(block.instructions) do
            address = address or ins.op == "Address"
            captures = captures or ins.op == "Capture"
        end
    end end
    assert(address and captures)
    H.raises("reject", "borrow-escape", function()
        s:compile{functions = {escape = m.functions.escape}, results = {[m.Unary] = s.U32}}
    end)
    H.raises("reject", "capture-type", function()
        s:compile{functions = {metadata = m.functions.metadata}}
    end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("immutable occurrence captures key and trace the rooted outer snapshot", function()
    local s = Word.new(); local m = s:load_string([[
        local Inner = word{value = U32, read = word(Unit, function() return bias + value end)}
        local Outer = word{bias = U32, left = Inner}
        local A = Outer:of{bias = 3, left = {value = 4}}
        local B = Outer:of{bias = 10, left = {value = 4}}
        local function make(selected)
            return word(U32, function(n)
                local loop
                loop = word(U32, function(x)
                    if x:eq(0) then return selected.read(nil) end
                    return loop(x - 1)
                end)
                return loop(n)
            end)
        end
        return {A = A, B = B, functions = {a = make(A.left), b = make(B.left)}}
    ]])
    H.eq(s:value(m.functions.a(1)), 7); H.eq(s:value(m.functions.b(1)), 14)
    local a = require("word.trace").describe(m.A.left)
    local b = require("word.trace").describe(m.B.left)
    H.eq(a.tag, "occurrence"); H.eq(b.tag, "occurrence"); assert(a.owner ~= b.owner)
    local program = s:compile{functions = m.functions}
    assert(IR.verify(program)); H.eq(#program.functions, 4)
end)

H.test("unbound nested interfaces retain static root keys and lexical occurrence identity", function()
    local s = Word.new(); local m = s:load_string([[
        local Inner = word{value = U32, read = word(Unit, function() return bias + value end)}
        local Outer = word{bias = U32, left = Inner, right = Inner}
        local A = Outer:of{left = {value = 1}, right = {value = 20}}
        local B = Outer:of{left = {value = 2}, right = {value = 30}}
        return {A = A, B = B}
    ]])
    local program = s:compile{functions = {
        aleft = m.A.left.read, aright = m.A.right.read, bleft = m.B.left.read}}
    assert(IR.verify(program))
    local exports = {}; for _, export in ipairs(program.exports) do exports[export.name] = export.target end
    assert(exports.aleft ~= exports.aright and exports.aleft ~= exports.bleft)
    for _, name in ipairs({"aleft", "aright", "bleft"}) do
        H.eq(program.functions[exports[name]].receiver.type,
            name == "bleft" and s:type(m.B) or s:type(m.A))
    end
end)

H.test("nested keyed method views cannot escape and detached copies do not invent owners", function()
    local s = Word.new(); local m = s:load_string([[
        local Inner = word{value = U32, read = word(Unit, function() return bias + value end)}
        local O = word{bias = U32, child = Inner}
        local consume = word(Inner, function(child) return child.read(nil) end)
        return {O = O,
            escape = word(O, function(o) return o.child.read end),
            detached = word(O, function(o) return consume(o.child) end)}
    ]])
    local o = m.O{bias = 2, child = {value = 3}}
    H.raises("reject", "borrow-escape", function() m.escape(o) end)
    H.raises("reject", "borrow-escape", function() s:compile{functions = {f = m.escape}} end)
    H.raises("reject", "unknown-name", function() m.detached(o) end)
    H.raises("reject", "unknown-name", function() s:compile{functions = {f = m.detached}} end)
    H.eq(s._engine.scope:current(), nil)
end)
