local a, b
a = word(U32, U32, function(n, seed)
    -- Recursive arm first: another pending entry may need this signature
    -- before this compilation has reached its own base return.
    if n:gt(0) then return b(n, seed) + a(n - 1, seed) end
    return seed
end)
b = word(U32, U32, function(n, seed)
    if n:gt(0) then return b(n - 1, seed) + a(n - 1, seed) end
    return seed + 1
end)

return {
    a = a,
    b = b,
    wrapped = word(U32, U32, function(n, seed) return a(n, seed) + 1 end),
}
