local H = ...
local Word = require("word")
local Model = require("word.model")
local Host = require("word.host")

H.test("LuaJIT keeps typed comparisons while explicit adapters handle raw literals", function()
    local s = Word.new(); local a, b = s.U32(3), s.U32(4)
    H.eq(a < b, true); H.eq(b <= a, false); H.eq(b > a, true)
    H.eq(a:lt(4), true); H.eq(a:le(3), true); H.eq(a:gt(2), true); H.eq(a:ge(3), true)
    H.eq(pcall(function() return a < 4 end), false)
    H.eq(a == 3, false); H.eq(not not s.Bool(false), true)
    H.eq(s:value(a:band(1)), 1); H.eq(s:value(a:bnot()), 4294967292)
end)

H.test("LuaJIT native capabilities are probed without using bitwise proxy syntax", function()
    local f = loadstring("return 7 & 3")
    if f then H.eq(f(), 3) end -- Some LuaJIT builds expose syntax; the DSL does not depend on it.
    local p = Host.table.pack(nil, false, 3, nil)
    H.eq(p.n, 4); H.eq(select("#", Host.table.unpack(p, 1, p.n)), 4)
    assert(Host.table ~= table and Host.math ~= math)
end)

H.test("U32 multiplication retains low bits above the double precision boundary", function()
    local s = Word.new()
    for _, row in ipairs({{4294967295, 4294967295, 1}, {4294967294, 4294967294, 4},
        {2147483649, 2147483649, 1}, {4294967295, 2147483649, 2147483647}}) do
        H.eq(s:value(s.U32(row[1]) * row[2]), row[3])
    end
    H.eq(s.U32:of(-0.0), s.U32:of(0)); H.eq(s:value(s.U32(-0.0)), 0)
end)

H.test("LuaJIT proxy ownership collects whole engine and record cycles", function()
    local weak = setmetatable({}, {__mode = "v"})
    local function build()
        local s = Word.new(); local P = s.word{x = s.U32}
        local p = P{x = 7}; weak[1], weak[2], weak[3] = s._engine, P, p
    end
    build(); for _ = 1, 3 do collectgarbage() end
    H.eq(weak[1], nil); H.eq(weak[2], nil); H.eq(weak[3], nil)
end)

H.test("LuaJIT checks global dependencies in nested function prototypes", function()
    local s = Word.new()
    local f = s.word(s.U32, function(x) local function helper() return math.floor(7) end; return x + helper() end)
    H.raises("todo", "host-captures", function() f(1) end)
    H.raises("todo", "host-captures", function() s.word(math.abs)() end)
    local _ENV = 7 -- An ordinary Lua 5.1 local, not a magic environment upvalue.
    H.eq(s:value(s.word(function() return _ENV end)()), 7)
end)

H.test("LuaJIT function environments freeze without changing the caller environment", function()
    local s = Word.new(); local m = s:load_string("return {f = word(U32, function(x) return U32(x) end)}")
    H.eq(s:value(m.f(3)), 3)
    local fn = Model.word(m.f).definition.terminal; local before = getfenv(fn)
    setfenv(fn, s._engine.scope:environment(s._engine.prelude))
    local ok, err = pcall(function() H.raises("reject", "capture-changed", function() m.f(3) end) end)
    setfenv(fn, before); assert(ok, err)
    H.eq(s:value(m.f(4)), 4); H.eq(s._engine.scope:current(), nil)
end)
