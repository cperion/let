local H = ...
local Word = require("word")
local IR = require("word.ir")

local function affine(s)
    return s.word(s.U32, s.U32, s.U32, function(a, b, x) return a * x + b end)
end

H.test("affine run and immutable compositional specialization", function()
    local s = Word.new(); local f = affine(s)
    local a, b = f:of(3, 7), f:of(3):of(7)
    H.eq(a, b); H.eq(a:of(), a)
    H.eq(s:value(a(4)), 19); H.eq(s:value(f(2, 1, 4)), 9)
    H.raises("reject", "immutable", function() a.static = {} end)
    H.raises("reject", "immutable", function() s.U32(3).value = 7 end)
    H.raises("reject", "unknown-member", function() return a.with end)
end)

H.test("definition and :of do not execute a terminal", function()
    local s = Word.new(); local executions = 0
    local w = s.word(s.U32, function(x) executions = executions + 1; return x end)
    local closed = w:of(10)
    H.eq(executions, 0); assert(closed)
end)

H.test("U32 wraparound is exact in known execution", function()
    local s = Word.new(); local max = s.U32(0xffffffff)
    H.eq(s:value(max + 1), 0)
    H.eq(s:value(s.U32(0) - 1), 0xffffffff)
    H.eq(s:value(max * max), 1)
    H.eq(s:value(2 * max), 0xfffffffe)
    H.eq(s:value(s.U32(65536) * 65536), 0)
end)

H.test("known comparison, Bool and Unit", function()
    local s = Word.new()
    H.eq(s.U32(3):eq(3), true); H.eq(s.U32(3) < s.U32(4), true); H.eq(s.U32(4) <= s.U32(3), false)
    H.eq(s.Bool(false):eq(false), true)
    local f = s.word(s.Bool, function(b) return b end)
    H.eq(s:value(f(false)), false)
    H.eq(s:value(s.word(function() end)()), nil)
    H.raises("reject", "arithmetic-type", function() return s.Bool(true) + 1 end)
end)

H.test("literal and arity errors are rejection, not TODO", function()
    local s = Word.new(); local f = affine(s)
    H.raises("reject", "arity", function() f(1, 2) end)
    H.raises("reject", "arity", function() f:of(1, 2, 3, 4) end)
    H.raises("reject", "type", function() f:of(1, nil, 2) end)
    for _, bad in ipairs({ -1, 0x100000000, 0.5, true, "3", math.huge }) do
        H.raises("reject", "type", function() s.U32(bad) end)
    end
    H.raises("reject", "signature-call", function() s.word(s.U32, s.U32)(1, 2) end)
end)

H.test("sessions do not share values or definitions", function()
    local a, b = Word.new(), Word.new()
    H.raises("reject", "foreign-session", function() return a.U32(1) + b.U32(2) end)
    H.raises("reject", "foreign-session", function() a.word(b.U32, function(x) return x end) end)
end)

H.test("symbolic arguments cannot enter :of", function()
    local s = Word.new(); local f = affine(s)
    local w = s.word(s.U32, function(x) return f:of(x) end)
    H.raises("reject", "static-required", function() s:compile{ functions = { bad = w } } end)
end)

H.test("IR has one parameter, checked operations and constants", function()
    local s = Word.new(); local f = affine(s):of(3, 7)
    local p = s:compile{ functions = { transform = f, alias = f } }
    H.eq(#p.functions, 1); H.eq(#p.exports, 2); assert(IR.verify(p))
    local fn = p.functions[1]; H.eq(#fn.parameters, 1); H.eq(fn.result, s.U32)
    local ops = {}
    for _, ins in ipairs(fn.blocks[1].instructions) do ops[#ops + 1] = ins.op end
    H.eq(table.concat(ops, ","), "Constant,Mul,Constant,Add")
    p.functions[1].blocks[1].instructions[1].value = 999
    local fresh = s:compile{ functions = { transform = f } }
    H.eq(fresh.functions[1].blocks[1].instructions[1].value, 3)
end)

H.test("fully static arguments fold without runtime parameters", function()
    local s = Word.new(); local f = affine(s):of(3, 7, 4)
    H.eq(s:value(f()), 19)
    local fn = s:compile{ functions = { constant = f } }.functions[1]
    H.eq(#fn.parameters, 0); H.eq(#fn.blocks[1].instructions, 1)
    H.eq(fn.blocks[1].instructions[1].value, 19)
end)

H.test("word composition uses the same symbolic operator path", function()
    local s = Word.new()
    local twice = s.word(s.U32, function(x) return x + x end)
    local composed = s.word(s.U32, function(x) return twice(x) + 1 end)
    H.eq(s:value(composed(4)), 9)
    local fn = s:compile{ functions = { composed = composed } }.functions[1]
    H.eq(#fn.parameters, 1); assert(IR.verify_function(fn))
end)

H.test("capture changes cannot reuse stale compiled code", function()
    local s = Word.new(); local factor = 3
    local child = s.word(s.U32, function(x) return factor * x end)
    local parent = s.word(s.U32, function(x) return child(x) end)
    s:compile{ functions = { f = parent } }
    factor = 4
    H.raises("reject", "capture-changed", function() s:compile{ functions = { f = parent } } end)
end)

H.test("terminal mutation of a frozen capture is rejected", function()
    local s = Word.new(); local n = 0
    local f = s.word(s.U32, function(x) n = n + 1; return x end)
    H.raises("reject", "capture-changed", function() f(1) end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("failed compilation does not publish incomplete IR", function()
    local s = Word.new()
    local m = s:load_string("return { f = word(U32, function(x) return unavailable end) }")
    for _ = 1, 2 do
        H.raises("reject", "unknown-name", function() s:compile{ functions = { f = m.f } } end)
    end
    H.eq(s._engine.scope:current(), nil)
end)

H.test("verifier rejects bad operands and constants", function()
    local s = Word.new(); local f = affine(s):of(3, 7)
    local p = s:compile{ functions = { f = f } }
    p.functions[1].blocks[1].instructions[2].args[1] = 999
    H.raises("bug", "invalid-ir", function() IR.verify(p) end)
    p = s:compile{ functions = { f = f } }
    p.functions[1].blocks[1].instructions[1].value = -1
    H.raises("bug", "invalid-ir", function() IR.verify(p) end)
end)

H.test("residual budget is a resource diagnostic", function()
    local s = Word.new{ max_values = 2 }
    H.raises("resource", "ir-values", function() s:compile{ functions = { f = affine(s):of(3, 7) } } end)
end)

H.test("todo trap has a stable actionable identity", function()
    local d = H.raises("todo", "host-captures", function() Word.todo("host-captures", "test context") end)
    assert(tostring(d):find("next:", 1, true)); H.eq(d.detail, "test context")
    H.raises("bug", "unknown-todo", function() Word.todo("typo") end)
end)

H.test("bad option and export shapes are rejected", function()
    for _, options in ipairs({ false, 3, { max_functions = false }, { max_values = "2" }, { typo = 3 } }) do
        H.raises("reject", "options", function() Word.new(options) end)
    end
    local s = Word.new()
    H.raises("reject", "exports", function() s:compile{ functions = false } end)
    H.raises("reject", "exports", function() s:compile{ functions = { [1] = s.U32 } } end)
end)

H.test("known false and true specialize control flow without replay", function()
    local s = Word.new()
    local choose = s.word(s.Bool, s.U32, function(flag, x)
        if flag:eq(true) then return x + 1 else return x - 1 end
    end)
    local no, yes = choose:of(false), choose:of(true)
    assert(no ~= yes)
    H.eq(s:value(no(0)), 0xffffffff); H.eq(s:value(yes(0)), 1)
    local p = s:compile{ functions = { no = no, yes = yes } }
    H.eq(#p.functions, 2)
    H.eq(p.functions[1].blocks[1].instructions[2].op, "Sub")
    H.eq(p.functions[2].blocks[1].instructions[2].op, "Add")
end)

-- A TODO is not a pass. Every live catalogue entry needs a reproducing witness.
H.gap("host-captures", function()
    local s = Word.new(); local host = { n = 3 }
    local f = s.word(s.U32, function(x) return host.n * x end)
    s:compile{ functions = { f = f } }
end)
H.test("unbound method exports declare typed receiver storage", function()
    local s = Word.new(); local C = s.word{value = s.U32, step = s.word(s.U32, function(n) return n end)}
    local p = s:compile{functions = {step = C.step}}; assert(p.functions[1].receiver)
end)
H.test("signature-valued member schemas can be demanded", function()
    local s = Word.new(); s:type(s.word{callback = s.word(s.U32)})
end)
H.test("numeric terminal results default to checked U32 values", function()
    local s = Word.new(); H.eq(s:value(s.word(function() return 42 end)()), 42)
end)
H.test("multiple results expand at Lua call boundaries", function()
    local s = Word.new(); local a, b = s.word(s.U32, function(x) return x, x + 1 end)(1)
    H.eq(s:value(a), 1); H.eq(s:value(b), 2)
end)
H.test("typed U32 division implements integer quotient", function()
    local s = Word.new(); H.eq(s:value(s.U32(7) / 2), 3)
end)
H.test("recursive results require grounding or an explicit declaration", function()
    local s = Word.new(); local f
    f = s.word(s.U32, function(x) return f(x) end)
    H.raises("reject", "recursive-result", function() s:compile{functions = {f = f}} end)
    assert(IR.verify(s:compile{functions = {f = f}, results = {[f] = s.U32}}))
end)
H.test("outlined staged words transport immutable snapshots alongside lexical receivers", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, run = word(U32, function(n)
            local before = value
            local loop
            loop = word(U32, function(x)
                if x:eq(0) then return value + before end
                return loop(x - 1)
            end)
            return loop(n)
        end)}
        return {run = C.run}
    ]])
    assert(IR.verify(s:compile{functions = m}))
end)
H.test("outlined lexical words transport additional borrowed callbacks without retention", function()
    local s = Word.new(); local m = s:load_string([[
        local Callback = word(U32)
        local C = word{value = U32, run = word(Callback, U32, function(callback, n)
            local loop
            loop = word(U32, function(x)
                if x:eq(0) then return value + callback(x) end
                return loop(x - 1)
            end)
            return loop(n)
        end)}
        return {functions = {run = C.run}, results = {[Callback] = U32}}
    ]])
    assert(IR.verify(s:compile(m)))
end)
H.test("local staged definitions compile", function()
    local s = Word.new()
    local m = s:load_string("return { f = word(U32, function(x) local g = word(U32, function(y) return y end); return g(x) end) }")
    s:compile{ functions = { f = m.f } }
end)
H.test("unknown runtime callable results require a declaration, not a missing ABI", function()
    local s = Word.new(); local signature = s.word(s.U32)
    local f = s.word(signature, function(g) return g(1) end)
    local err = H.raises("reject", "callable-result", function()
        s:compile{ functions = { f = f } }
    end)
    assert(err.message:find("results[signature]", 1, true))
    assert(IR.verify(s:compile{functions = {f = f}, results = {[signature] = s.U32}}))
end)
H.test("capture-free executable results compile", function()
    local s = Word.new(); local f = affine(s)
    local wrapper = s.word(s.U32, function(_) return f end)
    s:compile{ functions = { wrapper = wrapper } }
end)
