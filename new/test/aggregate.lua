local H = ...
local Word = require("word")
local Model = require("word.model")

H.test("static aggregate supply deeply snapshots host tables and rejects nested writes", function()
    local s = Word.new(); local P = s.word{x = s.U32, flag = s.Bool}
    local Pair = s.word{left = P, right = P}; local R = s.word{pair = Pair}
    local input = {x = 3, flag = false}
    local C = R:of{pair = {left = input, right = input}}
    input.x = 100; input.flag = true
    H.eq(s:value(C.pair.left.x), 3); H.eq(s:value(C.pair.right.flag), false)
    local snapshot = s:value(C.pair)
    snapshot.left.x = 9; snapshot.right.flag = true
    H.eq(s:value(C.pair.left.x), 3); H.eq(s:value(C.pair.right.flag), false)
    H.raises("reject", "static-field", function() C.pair.left.x = 4 end)
    H.raises("reject", "static-field", function() C.pair.left = {x = 4, flag = true} end)
    local instance = C{}
    H.raises("reject", "static-field", function() instance.pair = C.pair end)
    H.raises("reject", "static-field", function() C{pair = C.pair} end)
    H.eq(s:value(instance).pair.left.x, 3)
end)

H.test("aggregate keys include types and values and compatible keyed supply composes", function()
    local s = Word.new(); local P = s.word{x = s.U32, y = s.U32}:of{y = 0}
    local R = s.word{point = P, enabled = s.Bool}
    local a = R:of{point = {x = 7}}:of{enabled = false}
    local b = R:of{enabled = false, point = {x = s.U32(7)}}
    H.eq(a, b); H.eq(a:of{point = a.point}, a)
    H.eq(Model.key(a.point), Model.key(b.point)); H.eq(s:value(a.point.y), 0)
    assert(a ~= R:of{point = {x = 8}, enabled = false})
    H.raises("reject", "static-conflict", function() a:of{point = {x = 8}} end)
    H.raises("reject", "static-field", function() R:of{point = {x = 7, y = 0}} end)
    local Other = s.word{x = s.U32, y = s.U32}:of{y = 1}
    local foreign_type = s.word{p = Other}:of{p = {x = 7}}.p
    H.raises("reject", "type", function() R:of{point = foreign_type} end)
end)

H.test("record construction, assignment, arguments and results materialize independent copies", function()
    local s = Word.new(); local P = s.word{x = s.U32}; local Box = s.word{p = P}
    local K = Box:of{p = {x = 3}}.p
    local box = Box{p = K}; box.p.x = 9; H.eq(s:value(K.x), 3)
    box.p = K; box.p.x = 8; H.eq(s:value(K.x), 3)
    local bump = s.word(P, function(p) p.x = p.x + 1; return p end)
    local a, b = bump(K), bump(K)
    a.x = 99; H.eq(s:value(b.x), 4); H.eq(s:value(K.x), 3)
    local specialized = bump:of(K)
    H.eq(s:value(specialized().x), 4); H.eq(s:value(specialized().x), 4)
    H.eq(s:value(K.x), 3)
    s:emit_c{functions = {bump = specialized}}
    H.raises("reject", "runtime-in-normalization", function() s:normalize(specialized) end)
end)

H.test("normalization retains immutable aggregates but ordinary returns remain mutable copies", function()
    local s = Word.new(); local P = s.word{x = s.U32}; local K = s.word{p = P}:of{p = {x = 7}}.p
    local get = s.word(function() return K end)
    local normalized = s:normalize(get)
    H.eq(normalized, K); H.eq(s:normalize(normalized), K)
    H.eq(s:value(get).x, 7); H.eq(Model.word(get).result, K)
    local a, b = get(), get(); a.x = 8
    H.eq(s:value(b.x), 7); H.eq(s:value(K.x), 7)
    local Alias = s.word(function() return K end)
    H.eq(s.word{p = P}:of{p = Alias}.p, K)
    local live = s.word(function() return P{x = 7} end)
    H.raises("reject", "runtime-in-normalization", function() s.word{p = P}:of{p = live} end)
end)

H.test("nested Type, Unit and empty fields stay metadata until a representable value is needed", function()
    local s = Word.new(); local Empty = s.word{}
    local Meta = s.word{element = s.Type, marker = s.Unit, flag = s.Bool, empty = Empty}
    local Holder = s.word{meta = Meta}
    local C = Holder:of{meta = {element = s.U32, flag = false, empty = {}}}
    H.eq(C.meta.element, s.U32); H.eq(s:value(C.meta.flag), false); H.eq(s:value(C.meta.marker), nil)
    local snapshot = s:value(C.meta)
    H.eq(snapshot.element, s.U32); H.eq(next(snapshot.empty), nil)
    snapshot.empty.changed = true; H.eq(next(s:value(C.meta.empty)), nil)
    s:emit_c{types = {Holder = C}}
    local meta = C.meta; local get = s.word(function() return meta end)
    H.eq(s:normalize(get), meta)
    H.raises("reject", "runtime-type", function() get() end)
    H.raises("reject", "runtime-type", function() s:compile{functions = {get = get}} end)
    assert(C ~= Holder:of{meta = {element = s.Bool, flag = false, empty = {}}})
end)

H.test("constant receivers allow reads but do not permit state writes", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/aggregate_constants.lua")
    local K = m.types.Config.origin
    H.eq(s:value(K.sum(nil)), 7)
    H.raises("reject", "static-field", function() K.set(100) end)
    H.eq(s:value(K.x), 3)
    local p = m.functions.shifted(5)
    H.eq(s:value(p.x), 8); H.eq(s:value(K.x), 3)
    local cfg = m.types.Config{bias = 2}
    H.eq(s:value(m.functions.evaluate(cfg, 10)), 19)
end)

H.test("aggregate supply checks nested fields, dynamic leaves and foreign sessions", function()
    local s = Word.new(); local P = s.word{x = s.U32}; local R = s.word{p = P}
    H.raises("reject", "missing-field", function() R:of{p = {}} end)
    H.raises("reject", "unknown-field", function() R:of{p = {x = 1, extra = 2}} end)
    H.raises("reject", "type", function() R:of{p = {x = false}} end)
    H.raises("reject", "keyed-supply", function() R:of{p = setmetatable({x = 1}, {})} end)
    H.raises("reject", "static-required", function() R:of{p = P{x = 1}} end)
    local other = Word.new()
    H.raises("reject", "foreign-session", function() R:of{p = {x = other.U32(1)}} end)
    local Nested = s.word{r = R}
    H.raises("reject", "static-required", function() Nested:of{r = {p = P{x = 1}}} end)
    local f = s.word(s.U32, function(x) return R:of{p = {x = x}}.p.x end)
    H.raises("reject", "static-required", function() s:compile{functions = {f = f}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("immutable aggregate captures recheck embedded type-word dependencies", function()
    local s = Word.new(); local factor = 1
    local method = s.word(s.U32, function(n) return n + factor end)
    local Target = s.word{method = method}; local Meta = s.word{element = s.Type}
    local K = s.word{meta = Meta}:of{meta = {element = Target}}.meta
    local get = s.word(function() return K end)
    s:normalize(get); factor = 2
    H.raises("reject", "capture-changed", function() s:normalize(get) end)
    H.raises("reject", "capture-changed", function() s:value(K) end)
end)

H.test("static aggregate depth is bounded even when snapshots are composed incrementally", function()
    local s = Word.new(); local T = s:type(s.word{x = s.U32})
    local K = s.word{p = T}:of{p = {x = 1}}.p
    for _ = 2, 32 do
        T = s:type(s.word{child = T})
        K = s.word{p = T}:of{p = {child = K}}.p
    end
    T = s:type(s.word{child = T})
    H.raises("resource", "static-aggregate-depth", function() s.word{p = T}:of{p = {child = K}} end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("computed aggregate bindings canonicalize without changing the source schema", function()
    local s = Word.new(); local U32 = s.U32
    local P = s.word{x = U32, y = U32}; local R = s.word{p = P}
    local computed = s.word(function()
        local n = 0; for _ = 1, 10000 do n = n + 1 end
        return U32(n)
    end)
    H.eq(R.p, s:type(P))
    H.eq(R:of{p = {x = computed, y = 2}}, R:of{p = {x = 10000, y = 2}})
end)

H.test("shared immutable payloads cannot expand into unbounded canonical keys", function()
    local s = Word.new()
    local T = s:type(s.word{x = s.U32})
    local K = s.word{p = T}:of{p = {x = 1}}.p
    for _ = 2, 15 do
        T = s:type(s.word{left = T, right = T})
        K = s.word{p = T}:of{p = {left = K, right = K}}.p
    end
    T = s:type(s.word{left = T, right = T})
    H.raises("resource", "static-aggregate-size", function() s.word{p = T}:of{p = {left = K, right = K}} end)
    H.eq(s._engine.scope:current(), nil)
end)
