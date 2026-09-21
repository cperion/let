local Unary = word(U32)
local apply = word(Unary, U32, function(f, n) return f(n) + f(n + 1) end)
local increment = word(U32, function(n) return n + 1 end)
return {
    types = {Unary = Unary},
    results = {[Unary] = U32},
    functions = {apply = apply, run = word(U32, function(n) return apply(increment, n) end),
        forward = word(Unary, U32, function(f, n) return apply(f, n) end)},
}
