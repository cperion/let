local sum
sum = word(U32, function(n)
    if n:eq(0) then return U32(0) end
    return n + sum(n - 1)
end)

local reverse
reverse = word(U32, function(n)
    if n:gt(0) then return reverse(n - 1) end
    return U32(42)
end)

local accumulate
accumulate = word(U32, U32, function(n, total)
    if n:eq(0) then return total end
    return accumulate(n - 1, total + n)
end)

local swap
swap = word(U32, U32, U32, function(n, a, b)
    if n:eq(0) then return a end
    return swap(n - 1, b, a)
end)

local even
even = word(U32, function(n)
    if n:eq(0) then return Bool(true) end
    return not even(n - 1):eq(true)
end)

local generic
generic = word(Type, U32, U32, function(T, step, n)
    if n:eq(0) then return T(0) end
    return generic(T, step, n - 1) + step
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

local after
after = word(Point, U32, function(p, n)
    if n:eq(0) then return end
    after(p, n - 1)
    p.x = p.x + 1 -- Work after a void call prevents tail rewriting.
end)

return {
    types = {Point = Point},
    functions = {sum = sum, alias = sum, reverse = reverse, accumulate = accumulate,
        swap = swap, even = even, triple = generic:of(U32, 3), walk = walk, unit = unit, after = after},
}
