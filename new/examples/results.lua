local Point = word{x = U32}
local pair = word(U32, function(n) return n, n + 1 end)
local sum
sum = word(U32, function(n)
    if n:gt(0) then local total, count = sum(n - 1); return total + n, count + 1 end
    return 0, 0
end)
return {types = {Point = Point}, functions = {
    pair = pair, sum = sum,
    constants = word(function() return 7, false, nil, 9 end),
    consume = word(U32, function(n) local a, b = pair(n); return a * 1000 + b end),
    choose = word(U32, function(n)
        if n:gt(0) then return n, false, nil end
        return 42, true, nil
    end),
    copies = word(Point, function(p) return p, p end),
}}
