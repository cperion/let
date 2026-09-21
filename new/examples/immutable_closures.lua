local make = word(U32, function(n)
    return word(U32, function(x) return n + x end)
end)
local nested = word(U32, function(n)
    return word(U32, function(x)
        return word(U32, function(y) return n + x + y end)
    end)
end)
local recursive = word(U32, function(n)
    local f
    f = word(U32, function(x)
        if x:eq(0) then return n end
        return f(x - 1) + 1
    end)
    return f
end)
local mutual = word(U32, function(n)
    local even, odd
    even = word(U32, function(x)
        if x:eq(0) then return n end
        return odd(x - 1)
    end)
    odd = word(U32, function(x)
        if x:eq(0) then return n + 1 end
        return even(x - 1)
    end)
    return even, odd
end)
return {make = make, nested = nested, recursive = recursive, mutual = mutual}
