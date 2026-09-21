local Unary = word(U32)
local apply_twice = word(Unary, U32, function(f, n)
    f(n)
    return f(n)
end)

local Counter = word{
    count = U32,
    gain = U32,
    step = word(U32, function(n)
        count = count + gain * n
        return count
    end),
    twice = word(U32, function(n)
        step(n)
        return step(n)
    end),
}
local Fast = Counter:of{gain = 2}
local Box = word{inner = Fast}

return {
    types = {Counter = Counter, Fast = Fast, Box = Box},
    functions = {
        advance = word(Fast, U32, function(c, n)
            local f = c.step
            apply_twice(f, n)
            f:of(1)()
            return c
        end),
        independent = word(U32, function(n)
            local a = Fast{count = n}
            local b = Fast{count = 5}
            local f = a.step
            b.step(3)
            local old = a.count
            f(4)
            return old + a.count + b.count
        end),
        nested = word(Box, U32, function(box, n)
            local f = box.inner.step
            box.inner = Fast{count = n}
            f(3) -- The receiver is the field place, not its previous contents.
            return box
        end),
        sibling = word(Fast, U32, function(c, n)
            c.twice(n)
            return c
        end),
    },
}
