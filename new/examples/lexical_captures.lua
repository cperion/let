local Callback = word(U32)
local apply
apply = word(Callback, U32, function(f, n)
    if n:eq(0) then return f(2) end
    return apply(f, n - 1)
end)
local Counter = word{
    value = U32,
    run = word(U32, function(n)
        local before = value
        local loop
        loop = word(U32, function(x)
            if x:eq(0) then return value + before end
            value = value + 1
            return loop(x - 1)
        end)
        return loop(n)
    end),
    mutual = word(U32, function(n)
        local before = value
        local a, b
        a = word(U32, function(x)
            if x:eq(0) then return before + value end
            value = value + 1
            return b(x - 1)
        end)
        b = word(U32, function(x)
            if x:eq(0) then return before * 2 + value end
            value = value + 2
            return a(x - 1)
        end)
        return a(n)
    end),
    callback = word(U32, function(n)
        local before = value
        local f = word(U32, function(x)
            value = value + x
            return before + value
        end)
        return apply(f, n)
    end),
    owned = word(U32, function(n)
        local before = value
        local add = word(U32, function(x) return before + x end)
        local loop
        loop = word(U32, function(x)
            if x:eq(0) then return add(value) end
            value = value + 1
            return loop(x - 1)
        end)
        return loop(n)
    end),
}
local Config = word{offset = U32, make = word(U32, function(n)
    return word(U32, function(x) return offset + n + x end)
end), nested = word(U32, function(n)
    return word(U32, function(x)
        return word(U32, function(y) return offset + n + x + y end)
    end)
end)}
local Seven, Eleven = Config:of{offset = 7}, Config:of{offset = 11}
return {
    types = {Counter = Counter},
    results = {[Callback] = U32},
    functions = {
        run = Counter.run, mutual = Counter.mutual, callback = Counter.callback, owned = Counter.owned,
        make7 = Seven.make, make11 = Eleven.make, nested = Seven.nested,
        twice = word(U32, function(n)
            local c = Counter{value = 3}
            local a = c.run(n)
            return a, c.run(n), c.value
        end),
    },
}
