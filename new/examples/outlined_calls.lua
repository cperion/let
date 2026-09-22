local Callback = word(U32)
local apply = word(Callback, U32, function(f, x) return f(x) end)
local make = word(U32, function(n)
    return word(U32, function(x) return n + x end)
end)
local Counter = word{
    value = U32,
    inc = word(U32, function(n) value = value + n; return value end),
    repeat_inc = word(U32, function(n)
        if n:eq(0) then return value end
        value = value + 1
        return repeat_inc(n - 1)
    end),
}
local scale = word(U32, U32, function(k, x) return k * x end)
local twice, thrice = scale:of(2), scale:of(3)
local Identity = word(Type, function(T) return word(T, function(x) return x end) end)
local id32 = Identity:of(U32)
local Holder = word{callback = Callback, call = word(U32, function(x) return callback(x) end)}
return {
    types = {Counter = Counter},
    results = {[Callback] = U32},
    outline = {apply, make, Counter.inc, Counter.repeat_inc, twice, id32, Holder.call},
    functions = {
        member = word(U32, function(x)
            local holder = Holder{callback = id32}
            return holder.call(x)
        end),
        identity = word(U32, function(x) return id32(x) end),
        identity_callback = word(U32, function(x) return apply(id32, x) end),
        scaled = word(U32, function(x) return twice(x) + thrice(x) end),
        owned = word(U32, function(n) return apply(make(n), 2) end),
        borrowed = word(U32, function(n)
            local c = Counter{value = 3}
            local before = c.value
            local a, b = c.inc(n), c.inc(1)
            local r = c.repeat_inc(4)
            local f = word(U32, function(x) return c.inc(x) + n end)
            local result = apply(f, 2)
            return before, a, b, r, result, c.value
        end),
    },
}
