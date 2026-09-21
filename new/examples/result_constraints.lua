local cycle
cycle = word(U32, function(n) return cycle(n + 1) end)
local closed
closed = word(function() return closed() end)
local sum
sum = word(U32, function(n)
    if n:gt(0) then local total, count = sum(n - 1); return total + n, count + 1 end
    return 0, 0
end)
return {functions = {cycle = cycle, closed = closed, sum = sum},
    results = {[cycle] = U32, [closed] = Unit, [sum] = {U32, U32}}}
