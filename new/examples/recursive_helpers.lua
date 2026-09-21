local sum
sum = word(U32, function(n)
    if n:eq(0) then return U32(0) end
    return n + sum(n - 1)
end)

local generic
generic = word(Type, U32, U32, function(T, step, n)
    if n:eq(0) then return T(0) end
    return generic(T, step, n - 1) + step
end)

local even
even = word(U32, function(n)
    if n:gt(0) then return not even(n - 1):eq(true) end
    return Bool(true)
end)

local Point = word{x = U32, y = U32}
local walk
walk = word(Point, U32, function(p, n)
    p.x = p.x + 1
    if n:eq(0) then return p end
    local result = walk(p, n - 1)
    result.y = result.y + p.x
    return result
end)

local unit
unit = word(Unit, U32, function(u, n)
    if n:eq(0) then return end
    return unit(u, n - 1)
end)

local zero
zero = word(function()
    local p = Point{x = 0, y = 0}
    if p.x:eq(0) then return U32(7) end
    return zero() -- Conservative replay checks this arm too.
end)

return {
    types = {Point = Point},
    functions = {
        total = word(U32, function(n) return sum(n) + 1 end),
        typed = word(U32, function(n) return generic:of(U32, 3)(n) end),
        predicate = word(U32, function(n)
            if even(n):eq(true) then return U32(7) end
            return U32(9)
        end),
        walk = word(Point, U32, function(p, n)
            local result = walk(p, n)
            result.y = result.y + 1
            return result
        end),
        unit = word(U32, function(n) unit(nil, n); return Bool(true) end),
        zero = word(U32, function(n) return zero() + n end),
    },
}
