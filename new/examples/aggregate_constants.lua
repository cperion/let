local Point = word{
    x = U32, y = U32, marker = Unit,
    sum = word(Unit, function() return x + y end),
    set = word(U32, function(n) x = n end),
}
local Empty = word{}
local Meta = word{element = Type, flag = Bool, empty = Empty}
local Config = word{origin = Point, meta = Meta, bias = U32}
local Frozen = Config:of{
    origin = {x = 3, y = 4},
    meta = {element = U32, flag = false, empty = {}},
}
local Box = word{point = Point}
local shift = word(Point, U32, function(p, n)
    p.x = p.x + n
    return p
end)

return {
    types = {Point = Point, Config = Frozen, Box = Box},
    functions = {
        origin = word(function() return Frozen.origin end),
        shifted = shift:of(Frozen.origin),
        evaluate = word(Frozen, U32, function(cfg, n)
            local T = cfg.meta.element
            if cfg.meta.flag:eq(false) then return T(n + cfg.origin.sum(nil) + cfg.bias) end
            return T(n)
        end),
        reset = word(Box, U32, function(box, n)
            if n:lt(10) then box.point = Frozen.origin
            else box.point = shift(Frozen.origin, n) end
            box.point.y = box.point.y + 1
            return box
        end),
    },
}
