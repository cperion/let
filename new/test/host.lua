local H = ...
local Word = require("word")
local table = require("word.host").table
local Scope = require("word.scope")

H.test("Lua table-call sugar does not encode shape", function()
    local function f(...) return table.pack(...) end
    local a, b = f{ x = 1 }, f({ x = 1 })
    H.eq(a.n, b.n); H.eq(a[1].x, b[1].x)
end)

H.test("relational hooks produce real Lua booleans", function()
    local choices = { false, true }
    local mt = { __lt = function() return table.remove(choices, 1) end }
    local x, y = setmetatable({}, mt), setmetatable({}, mt)
    H.eq(x < y, false); H.eq(y > x, true)
    H.eq(pcall(function() return x < 10 end), false) -- Measured LuaJIT boundary.
end)

H.test("truthiness and mixed equality are not symbolic hooks", function()
    local calls = 0
    local x = setmetatable({}, { __eq = function() calls = calls + 1; return true end })
    H.eq(not not x, true); H.eq(x == 3, false); H.eq(calls, 0)
end)

H.test("loader uses immutable empty proxy environment", function()
    local s = Word.new()
    local m = s:load_string("return { f = word(U32, function(x) return x + 1 end) }")
    H.eq(s:value(m.f(4)), 5)
    H.raises("reject", "module-write", function() s:load_string("leak = 4; return {}") end)
    H.raises("reject", "unknown-name", function() s:load_string("return { x = io }") end)
end)

H.test("frames restore across nested errors", function()
    local scope = Scope.new()
    local outer = { mode = "test" }
    scope:with(outer, function()
        H.eq(scope:current(), outer)
        local ok = pcall(function() scope:with({}, function() error("expected") end) end)
        H.eq(ok, false); H.eq(scope:current(), outer)
    end)
    H.eq(scope:current(), nil)
end)

H.test("frame stacks are coroutine-local", function()
    local scope = Scope.new()
    scope:with({ name = "outer" }, function()
        local co = coroutine.create(function()
            H.eq(scope:current(), nil)
            scope:with({ name = "inner" }, function() H.eq(scope:current().name, "inner") end)
        end)
        local ok, err = coroutine.resume(co); assert(ok, err)
        H.eq(scope:current().name, "outer")
    end)
end)

H.test("long Lua work runs without an instruction quota or replacing the host debug hook", function()
    local s = Word.new(); local m = s:load_string([[
        return {f = word(U32, function(x)
            local total = 0
            for _ = 1, 1100000 do total = total + 1 end
            return x + total
        end)}
    ]])
    local before, mask, count = debug.gethook()
    local ticks = 0
    local function hook() ticks = ticks + 1 end
    debug.sethook(hook, "", 1000)
    local ok, err = pcall(function()
        H.eq(s:value(m.f(1)), 1100001)
        H.eq(s:value(s:normalize(m.f:of(1))), 1100001)
        local ir = s:compile{functions = {f = m.f}}
        H.eq(#ir.functions, 1)
        local current, current_mask, current_count = debug.gethook()
        H.eq(current, hook); H.eq(current_mask, ""); H.eq(current_count, 1000)
        assert(ticks > 0) -- JIT-compiled loops need not issue a hook per interpreted instruction.
        H.eq(s._engine.scope:current(), nil)
    end)
    debug.sethook(before, mask, count)
    assert(ok, tostring(err))
end)

H.test("scope errors leave the host debug hook installed", function()
    local scope = Scope.new()
    local before, mask, count = debug.gethook()
    local function hook() end
    debug.sethook(hook, "", 1000)
    local ok, err = pcall(function()
        local succeeded = pcall(function() scope:with({}, function() error("expected") end) end)
        H.eq(succeeded, false); H.eq(scope:current(), nil)
        local current, current_mask, current_count = debug.gethook()
        H.eq(current, hook); H.eq(current_mask, ""); H.eq(current_count, 1000)
    end)
    debug.sethook(before, mask, count)
    assert(ok, tostring(err))
end)

H.test("receiver proxy protocol does not give helpers dynamic scope (host probe)", function()
    -- Future receiver mechanism, not a claim that keyed words are implemented.
    local frame, terminal
    local env = setmetatable({}, {
        __index = function(_, key)
            local caller = debug.getinfo(2, "f").func
            if frame and caller == frame.terminal then return frame.owner[key] end
            if key == "count" then return 100 end
        end,
        __newindex = function(_, key, value)
            assert(frame and debug.getinfo(2, "f").func == frame.terminal)
            frame.owner[key] = value
        end,
    })
    local helper = assert(load("return function() return count end", "helper", "t", env))()
    terminal = assert(load("return function(n) count = count + n; return count end", "terminal", "t", env))()
    frame = { terminal = terminal, owner = { count = 1 } }
    H.eq(terminal(2), 3); H.eq(helper(), 100); H.eq(terminal(4), 7)
    H.eq(next(env), nil)
end)
