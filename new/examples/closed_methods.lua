local Point = word{x = U32}
local Counter = word{count = U32,
    read = word(function() return count end),
    reset = word(function() count = 0 end),
    pair = word(function() return count, false end),
    copy = word(function() return Point{x = count} end),
    constant = U32:of(7),
}
return {types = {Counter = Counter, Point = Point}, functions = {
    read = Counter.read, reset = Counter.reset, pair = Counter.pair, copy = Counter.copy,
    constant = Counter.constant,
    run = word(U32, function(n)
        local c = Counter{count = n}; local before = c.read(); local p = c.copy()
        c.reset(); local after, flag = c.pair()
        return before, after, p, flag, c.constant()
    end),
}}
