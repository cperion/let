local Math = word{
    add = word(U32, U32, function(a, b) return a + b end),
    sum = word(U32, function(n)
        if n:eq(0) then return U32(0) end
        return n + sum(n - 1)
    end),
}
local Scaled = word{factor = U32,
    scale = word(U32, function(n) return factor * n end),
    twice = word(U32, function(n) return scale(n) + scale(n) end),
}
local Three = Scaled:of{factor = 3}
local Five = Scaled:of{factor = 5}
return {functions = {
    add = Math.add, alias = Math.add, sum = Math.sum,
    triple = Three.scale, quintuple = Five.scale, twice = Three.twice,
    constant = word(function() return Math.add(10, 20) end),
    composed = word(U32, function(n) return Math.add(Three.scale(n), Five.scale(n)) end),
}}
