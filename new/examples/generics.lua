local Identity = word(Type, function(T)
    return word(T, function(x) return x end)
end)

local Pair = word(Type, Type, function(A, B)
    return word{ first = A, second = B }
end)

local P = Pair:of(U32, Bool)

return {
    identity = Identity:of(U32),
    flag = Identity:of(Bool),
    increment = word(P.first, function(x) return x + 1 end),
}
