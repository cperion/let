local Counter = word{value = U32,
    next = word(Unit, function() value = value + 1; return value end),
    read = word(Unit, function() return value end),
}
local make = word(U32, function(n) return Counter{value = n} end)
return {
    types = {Counter = Counter},
    functions = {make = make, next = Counter.next, read = Counter.read,
        run = word(U32, function(n)
            local c = make(n)
            local next_value, read = c.next, c.read
            return next_value(nil), read(nil)
        end),
    },
}
