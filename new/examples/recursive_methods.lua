local Step = word(U32, function(n)
    if n:gt(0) then value = value + stride; return advance(n - 1) end
    return value
end)
local Counter
Counter = word{value = U32, stride = U32, advance = Step,
    walk = word(U32, function(n)
        if n:gt(0) then value = value + stride; walk(n - 1) end
    end),
    snapshot = word(U32, function(n)
        if n:gt(0) then return snapshot(n - 1) end
        return Counter{value = value, stride = stride}
    end),
    a = word(U32, function(n)
        if n:gt(0) then return b(n) + a(n - 1) end
        return value
    end),
    b = word(U32, function(n)
        if n:gt(0) then return b(n - 1) + a(n - 1) end
        value = value + 1; return value
    end)}
local Fast = Counter:of{stride = 3}
local Pair = word{left = Counter, right = Counter}
local Other = word{value = U32, stride = U32, extra = Bool, advance = Step}
return {types = {Counter = Counter}, functions = {
    nested = word(U32, function(n)
        local p = Pair{left = {value = 1, stride = 2}, right = {value = 20, stride = 3}}
        local advance = p.left.advance
        advance(n); p.right.advance(n + 1)
        return p.left.value * 1000 + p.right.value
    end),
    specialized = word(U32, function(n)
        local c = Fast{value = 1}; c.advance(n); c.walk(n)
        local p = c.snapshot(n); p.value = p.value + 7
        return p.value * 1000 + c.value
    end),
    owners = word(U32, function(n)
        local a = Counter{value = 1, stride = 2}
        local b = Other{value = 5, stride = 3, extra = false}
        a.advance(n); b.advance(n); return a.value * 1000 + b.value
    end),
    mutual = word(U32, function(n)
        local c = Counter{value = 1, stride = 1}; return c.a(n) + c.value
    end),
    byvalue = word(Counter, U32, function(c, n)
        c.advance(n); return c.snapshot(n)
    end),
}}
