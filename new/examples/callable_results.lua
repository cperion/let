local Unary = word(U32)
local Maker = word(Unit)
local increment = word(U32, function(n) return n + 1 end)
local double = word(U32, function(n) return n * 2 end)
local choose = word(Bool, function(flag)
    if flag:eq(true) then return increment end
    return double
end)
local make = word(Unit, function() return increment end)
return {types = {Unary = Unary, Maker = Maker},
    results = {[Unary] = U32, [Maker] = Unary, [make] = Unary, [choose] = Unary},
    functions = {make = make, choose = choose, apply_maker = word(Maker, U32, function(f, n) return f(nil)(n) end)},
}
