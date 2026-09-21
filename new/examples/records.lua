local Point = word{ x = U32, y = U32 }
local Pair = word{ left = Point, right = Point }

local make = word(U32, U32, function(x, y) return Point{ x = x, y = y } end)
local shift = word(Point, U32, function(p, amount)
    p.x = p.x + amount
    return p
end)
local exercise = word(Pair, function(p)
    local child = p.left
    local old = child.x
    p.left = p.right
    child.x = child.x + 1
    return old + p.left.x + p.right.x
end)

return {
    types = { Point = Point, Pair = Pair },
    functions = { make = make, shift = shift, exercise = exercise },
}
