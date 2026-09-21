local H = ...
local Word = require("word")

local function rejects(body)
    local source = [[
        local Read = word(Unit)
        local C = word{value = U32, read = word(Unit, function() return value end)}
        local Box = word{callback = Read}
        local f = word(U32, function(n)
            local c = C{value = n}
    ]] .. body .. [[
        end)
        return {functions = {f = f}, results = {[Read] = U32}}
    ]]
    for _, compile in ipairs({false, true}) do
        local s = Word.new(); local m = s:load_string(source)
        local d = H.raises("reject", "borrow-escape", function()
            if compile then s:compile(m) else m.functions.f(3) end
        end)
        assert(d.message:find("return the stateful record", 1, true))
    end
end

H.test("borrowed method results reject directly and in result packs", function()
    rejects("return c.read")
    rejects("return n, c.read")
end)

H.test("borrowed methods cannot be hidden in record construction or assignment", function()
    rejects("return Box{callback = c.read}")
    rejects("local b = Box{callback = word(Unit, function() return 0 end)}; b.callback = c.read; return n")
end)

H.test("callback parameters are non-retaining even when their code is known inline", function()
    rejects("local forward = word(Read, function(f) return f end); return forward(c.read)")
    rejects("local save = word(Read, function(f) local b = Box{callback = f}; return n end); return save(c.read)")
end)

H.test("borrowed callback parameters can be invoked and forwarded without retention", function()
    local s = Word.new(); local m = s:load_string([[
        local Read = word(Unit)
        local invoke = word(Read, function(f) return f(nil) end)
        local forward = word(Read, function(f) return invoke(f) end)
        local C = word{value = U32, read = word(Unit, function() return value end)}
        return {results = {[Read] = U32}, functions = {forward = forward, run = word(U32, function(n)
            local c = C{value = n}; return forward(c.read)
        end)}}
    ]])
    H.eq(s:value(m.functions.run(7)), 7)
    assert(require("word.ir").verify(s:compile(m)))
end)

H.test("opaque callback results cannot escape through an exported parameter", function()
    local s = Word.new(); local signature = s.word(s.Unit)
    local f = s.word(signature, function(callback) return callback end)
    H.raises("reject", "borrow-escape", function()
        s:compile{functions = {f = f}, results = {[signature] = s.U32}}
    end)
end)

H.test("closures cannot conceal a borrowed receiver through captured words", function()
    rejects("return word(Unit, function() return c.value end)")
    rejects("local read = c.read; return word(Unit, function() return read(nil) end)")
    rejects("local inner = word(Unit, function() return c.value end); return word(Unit, function() return inner(nil) end)")
    rejects("local Bad = word{read = word(Unit, function() return c.value end)}; return Bad{}")
end)

H.test("C emission rechecks borrows instead of trusting cached storage plans", function()
    local s = Word.new(); local signature = s.word(s.Unit)
    local f = s.word(signature, function(callback) return callback(nil) end)
    local program = s:compile{functions = {f = f}, results = {[signature] = s.U32}}
    local fn = program.functions[program.exports[1].target]
    fn.result = fn.parameters[1].type
    fn.blocks[1].exit.value = fn.parameters[1].id
    assert(require("word.ir").verify(program))
    H.raises("reject", "borrow-escape", function() require("word.c").emit(program) end)
end)
