local Point = word{x = U32, y = U32}
local XAxis = Point:of{y = 0}
local Settings = word{element = Type, enabled = Bool, bias = U32, marker = Unit}
local Config = Settings:of{element = U32, enabled = false, bias = 7, marker = Unit()}
local Box = word{point = XAxis}

return {
    types = {XAxis = XAxis, Config = Config, Box = Box},
    functions = {
        make = word(U32, function(x) return XAxis{x = x} end),
        sum = word(XAxis, function(p) return p.x + p.y end),
        configured = word(Config, U32, function(c, x)
            if c.enabled:eq(true) then return c.element(x + 100) end
            return c.element(x + c.bias)
        end),
        nested = word(Box, function(b)
            b.point.x = b.point.x + 1
            return b.point
        end),
        local_specialization = word(U32, function(x)
            local Line = Point:of{y = 3}
            local p = Line{x = x}
            return p.x + p.y
        end),
    },
}
