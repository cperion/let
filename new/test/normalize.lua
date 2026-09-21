local H = ...
local Word = require("word")
local Model = require("word.model")

local function factories(s)
    return s:load_string([[
        local Identity = word(Type, function(T)
            return word(T, function(x) return x end)
        end)
        local Pair = word(Type, Type, function(A, B)
            return word{ first = A, second = B }
        end)
        return { Identity = Identity, Pair = Pair }
    ]], "=(factories)")
end

H.test("Type specialization produces a callable Identity", function()
    local s = Word.new(); local m = factories(s)
    local id = m.Identity:of(s.U32)
    H.eq(s:value(id(42)), 42)
    H.eq(s:value(m.Identity:of(s.Bool)(false)), false)
    H.eq(id, m.Identity:of(s.U32))
    H.eq(s:normalize(id), s:normalize(id))
    H.eq(s:value(id:of(7)()), 7)
    H.eq(m.Identity:of(s.Type)(s.U32), s.U32)
end)

H.test("definition and specialization are lazy even when closed", function()
    local s = Word.new()
    local m = s:load_string([[
        local broken = word(Type, function(T) return unavailable end)
        return { broken = broken:of(U32) }
    ]])
    H.eq(Model.get(m.broken).result, nil)
    H.raises("reject", "unknown-name", function() s:normalize(m.broken) end)
    H.eq(Model.get(m.broken).result, nil)
    H.raises("reject", "unknown-name", function() s:normalize(m.broken) end)
end)

H.test("empty factory invocation returns a word without invoking it", function()
    local s = Word.new(); local m = factories(s)
    local inner = m.Identity:of(s.U32)()
    assert(Model.word(inner)); H.eq(s:value(inner(9)), 9)
    local delayed = s:load_string([[
        return { f = word(function() return word(function() return unavailable end) end) }
    ]]).f
    local child = delayed()
    assert(Model.word(child))
    H.raises("reject", "unknown-name", function() child() end)
end)

H.test("closed scalar demands normalize and compose", function()
    local s = Word.new()
    local add = s.word(s.U32, s.U32, function(a, b) return a + b end)
    local thirty = add:of(10, 20)
    H.eq(s:value(thirty), 30); H.eq(s:value(thirty + s.U32(2)), 32)
    H.eq(s:value(s.U32(2) + thirty), 32); H.eq(thirty:eq(30), true)
    H.eq(s:value(add:of(thirty)(5)), 35)
    H.eq(s:normalize(thirty), s:normalize(thirty))
    H.raises("reject", "arity", function() thirty(1) end)
    H.raises("reject", "scalar-required", function() return s.U32 + s.U32(1) end)
end)

H.test("keyed schemas are immutable, canonical and structurally interned", function()
    local s = Word.new(); local m = factories(s)
    local P = m.Pair:of(s.U32, s.Bool)
    H.eq(P.first, s.U32); H.eq(P.second, s.Bool)
    local fields = { second = s.Bool, first = s.U32 }
    local schema = s.word(fields); fields.first = s.Bool
    H.eq(s:type(schema), s:type(P))
    H.eq(s:normalize(P), s:type(P))
    H.eq(s:type(s.word{}), s:type(s.word{}))
    H.raises("reject", "immutable", function() P.first = s.Bool end)
    H.raises("reject", "unknown-member", function() return P.missing end)
    for _, key in ipairs({ "of", "eq", "", 1 }) do
        H.raises("reject", "schema-key", function() s.word{ [key] = s.U32 } end)
    end
end)

H.test("schemas preserve field names and nested shapes", function()
    local s = Word.new()
    local a = s:type(s.word{ left = s.U32 })
    local b = s:type(s.word{ right = s.U32 })
    assert(a ~= b)
    local nested = s:type(s.word{ child = a, flag = s.Bool })
    H.eq(nested.child.left, s.U32)
    assert(nested ~= s:type(s.word{ child = b, flag = s.Bool }))
end)

H.test("Type argument demands canonicalize aliases, not the receiving factory", function()
    local s = Word.new(); local m = factories(s); local U32 = s.U32
    local alias = s.word(function() return U32 end)
    local a, b = m.Identity:of(alias), m.Identity:of(s.U32)
    H.eq(a, b); H.eq(s:value(a(123)), 123)
    local A = s.word{ value = s.U32 }
    local B = s.word{ value = alias }
    H.eq(m.Identity:of(A), m.Identity:of(B))
end)

H.test("deferred input types do not force during definition", function()
    local s = Word.new()
    local m = s:load_string([[
        local Later
        local Alias = word(function() return Later end)
        local f = word(Alias, function(x) return x end)
        Later = U32
        return { f = f, Alias = Alias }
    ]])
    H.eq(Model.get(m.Alias).result, nil)
    H.eq(s:value(m.f(12)), 12)
    local fn = s:compile{ functions = { f = m.f } }.functions[1]
    H.eq(fn.parameters[1].type, s.U32)
end)

H.test("static Type positions reject runtime values and unspecialized C parameters", function()
    local s = Word.new(); local m = factories(s)
    H.raises("reject", "type-required", function() m.Identity:of(s.U32(4)) end)
    H.raises("reject", "type-required", function() m.Identity:of(s.word(s.U32)) end)
    H.raises("reject", "static-required", function() s:compile{ functions = { f = m.Identity } } end)
    local returns_type = s:load_string("return { f = word(U32, function(x) return U32 end) }").f
    H.raises("reject", "static-runtime", function() s:compile{ functions = { f = returns_type } } end)
    local foreign = Word.new()
    H.raises("reject", "foreign-session", function() m.Identity:of(foreign.U32) end)
end)

H.test("static word results can be used locally without a runtime closure", function()
    local s = Word.new(); local m = factories(s)
    local Identity = m.Identity; local U32 = s.U32
    local f = s.word(s.U32, function(x) return Identity:of(U32)(x) + 1 end)
    H.eq(s:value(f(7)), 8)
    local fn = s:compile{ functions = { f = f } }.functions[1]
    H.eq(#fn.parameters, 1); H.eq(fn.result, s.U32)
end)

H.test("self and mutual normalization cycles fail without provisional values", function()
    local s = Word.new(); local a, b
    a = s.word(function() return b() end)
    b = s.word(function() return a() end)
    H.raises("reject", "normalization-cycle", function() s:normalize(a) end)
    H.eq(Model.get(a).result, nil); H.eq(Model.get(b).result, nil)
    H.eq(s._engine.scope:current(), nil)
    local self_call
    self_call = s.word(function() return self_call() end)
    H.raises("reject", "normalization-cycle", function() s:normalize(self_call) end)
end)

H.test("by-value schema cycles reject rather than inventing a finite type", function()
    local s = Word.new()
    local m = s:load_string([[
        local Bad
        Bad = word(function() return word{ child = Bad } end)
        return { Bad = Bad }
    ]])
    H.raises("reject", "type-cycle", function() s:type(m.Bad) end)
    H.eq(next(s._engine.schemas), nil)
end)

H.test("known recursive computation uses argument-sensitive static keys", function()
    local s = Word.new(); local sum
    sum = s.word(s.U32, function(n)
        if n:eq(0) then return n end
        return n + sum(n - 1)
    end)
    H.eq(s:value(s:normalize(sum:of(6))), 21)
    H.eq(s:value(s:normalize(sum:of(4))), 10)
end)

H.test("normalization work and nesting are bounded and unwind", function()
    local s = Word.new{ max_normalizations = 3 }; local grow
    grow = s.word(s.U32, function(n) return grow(n + 1) end)
    H.raises("resource", "normalizations", function() s:normalize(grow:of(0)) end)
    H.eq(s._engine.scope:current(), nil)
    H.eq(Model.get(grow:of(0)).result, nil)
    s = Word.new(); local forever
    forever = s.word(s.U32, function(n) return forever(n + 1) end)
    H.raises("resource", "normalization-depth", function() s:normalize(forever:of(0)) end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("normalization cache rechecks captures and type requirements", function()
    local s = Word.new(); local current = s.U32
    local alias = s.word(function() return current end)
    local f = s.word(alias, function(x) return x end)
    s:compile{ functions = { f = f } }
    current = s.Bool
    H.raises("reject", "capture-changed", function() s:type(alias) end)
    H.raises("reject", "capture-changed", function() s:compile{ functions = { f = f } } end)
end)

H.test("normalization cannot mutate frozen captures or consume dynamic captures", function()
    local s = Word.new(); local n = 1; local U32 = s.U32
    local mutate = s.word(function() n = n + 1; return U32(n) end)
    H.raises("reject", "capture-changed", function() s:normalize(mutate) end)
    H.eq(s._engine.scope:current(), nil)
    local m = s:load_string([[
        local current = U32(0)
        local deferred = word(function() return current end)
        return { f = word(U32, function(x) current = x; return deferred + 1 end) }
    ]])
    H.raises("todo", "host-captures", function() s:compile{ functions = { f = m.f } } end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("local constructor aliases work in embedded type factories", function()
    local s = Word.new(); local word = s.word
    local Identity = word(s.Type, function(T) return word(T, function(x) return x end) end)
    H.eq(s:value(Identity:of(s.U32)(42)), 42)
end)

H.test("partial Type supply composes without executing the factory", function()
    local s = Word.new(); local m = factories(s)
    local partial = m.Pair:of(s.U32)
    H.eq(Model.get(partial).result, nil)
    local complete = partial:of(s.Bool)
    H.eq(Model.get(complete).result, nil)
    H.eq(complete, m.Pair:of(s.U32, s.Bool))
    H.eq(complete.second, s.Bool)
end)

H.test("static value captures distinguish generated specializations", function()
    local s = Word.new()
    local m = s:load_string([[
        return { Scale = word(U32, function(scale)
            return word(U32, function(x) return scale * x end)
        end) }
    ]])
    local a, b = m.Scale:of(2), m.Scale:of(3)
    H.eq(s:value(a(7)), 14); H.eq(s:value(b(7)), 21)
    assert(s:normalize(a) ~= s:normalize(b))
    H.eq(s:normalize(a), s:normalize(m.Scale:of(2)))
    local code = s:compile{ functions = { a = a, b = b } }
    H.eq(#code.functions, 2)
end)

H.test("nested normalization restores the active residual builder", function()
    local s = Word.new(); local U32 = s.U32
    local constant = s.word(function() return U32(2) end)
    local f = s.word(s.U32, function(x) return constant + x + constant end)
    H.eq(s:value(f(3)), 7)
    local fn = s:compile{ functions = { f = f } }.functions[1]
    H.eq(#fn.parameters, 1); H.eq(#fn.blocks[1].instructions, 3)
    H.eq(fn.blocks[1].instructions[1].value, 2)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("nested empty factory calls have the same run and normalization semantics", function()
    local s = Word.new()
    local m = s:load_string([[
        local factory = word(function() return word(function() return U32(7) end) end)
        return { outer = word(function() local f = factory(); return f() end), factory = factory }
    ]])
    H.eq(s:value(m.outer()), 7)
    H.eq(s:value(s:normalize(m.outer)), 7)
    H.eq(s:value(s:normalize(m.factory)), 7)
    -- Demanding the factory's scalar normal form must not poison its call result.
    H.eq(s:value(m.outer()), 7)
    local fn = s:compile{ functions = { outer = m.outer } }.functions[1]
    H.eq(fn.blocks[1].instructions[1].value, 7)
end)

H.test("a word-valued call result is not a guessed scalar at a cycle", function()
    local s = Word.new(); local self_word
    self_word = s.word(function() return self_word end)
    H.eq(self_word(), self_word)
    H.raises("reject", "normalization-cycle", function() s:normalize(self_word) end)
    H.eq(self_word(), self_word)
    H.raises("reject", "normalization-cycle", function() s:normalize(self_word) end)
    H.eq(s._engine.scope:current(), nil)
end)

H.test("failed static demands leave no active record and can be retried", function()
    local s = Word.new{max_normalizations = 1}; local U32 = s.U32
    local inner = s.word(function() return U32(7) end)
    local outer = s.word(function() return inner() end)
    H.raises("resource", "normalizations", function() s:normalize(outer) end)
    H.eq(s._engine.scope:current(), nil)
    H.eq(Model.word(outer).result, nil)
    for _, w in pairs(s._engine.specializations) do
        H.eq(Model.get(w).state, nil); H.eq(Model.get(w).error, nil)
    end
    s._engine.max_normalizations = 1000
    H.eq(s:value(s:normalize(outer)), 7)
end)

H.test("failed IR generation is not a persistent cache entry", function()
    local s = Word.new{ max_values = 1 }
    local f = s.word(s.U32, function(x) return x + 1 end)
    H.raises("resource", "ir-values", function() s:compile{ functions = { f = f } } end)
    s._engine.max_values = 20
    local a = s:compile{ functions = { f = f } }
    local b = s:compile{ functions = { f = f } }
    assert(a.functions[1] ~= b.functions[1])
    H.eq(s._engine.code, nil); H.eq(s._engine.normalized, nil); H.eq(s._engine.types, nil)
end)

H.test("runtime symbols cannot bind Type inputs", function()
    local s = Word.new(); local m = factories(s); local Identity = m.Identity
    local bad = s.word(s.U32, function(x) return Identity:of(x)(x) end)
    H.raises("reject", "type-required", function() s:compile{ functions = { bad = bad } } end)
    H.eq(s._engine.scope:current(), nil)
end)
