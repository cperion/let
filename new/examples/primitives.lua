local Seven = U32:of(7)
local No = Bool:of(false)
local Number = Type:of(U32)
local Point = word{x = Number}
local PointAlias = Type:of(Point)
local ZeroArg = word()
local call = word(ZeroArg, function(f) return f() end)

return {
    types = {Number = Number, Point = PointAlias},
    functions = {
        seven = Seven,
        no = No,
        maximum = U32:of(4294967295),
        callback = call:of(Seven),
        unit = call:of(Unit:of()),
        typed = word(Number, function(x) return Number(x + Seven) end),
        make = word(U32, function(x) return PointAlias{x = x} end),
        local_bind = word(U32, function(x)
            local two = U32:of(2)
            if x:lt(10) then return x + two() else return x * two() end
        end),
    },
}
