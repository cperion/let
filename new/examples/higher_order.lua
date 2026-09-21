local Unary = word(U32)
local BinOp = word(U32, U32)
local add = word(U32, U32, function(a, b) return a + b end)
local multiply = word(U32, U32, function(a, b) return a * b end)
local apply = word(Unary, U32, function(f, x) return f(x) end)
local apply2 = word(BinOp, U32, U32, function(f, a, b) return f(a, b) end)
local add10 = add:of(10)
local Compose = word(Unary, Unary, function(f, g)
    return word(U32, function(x) return f(g(x)) end)
end)

return {
    add = apply2:of(add),
    multiply = apply2:of(multiply),
    add10 = apply:of(add10),
    nested = apply:of(apply:of(add10)),
    composed = Compose:of(add10, add:of(1)),
    local_call = word(U32, function(x) return apply2(add, x, 1) end),
    predicate = apply:of(word(U32, function(_) return true end)),
}
