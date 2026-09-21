local Counter = word{value = U32,
    add = word(U32, function(n) value = value + n; return value end),
    read = word(Unit, function() return value end),
    sum = word(U32, function(n)
        if n:gt(0) then value = value + n; return sum(n - 1) end
        return value
    end)}
local Holder = word{c = Counter}:of{c = {value = 7}}
return {types = {Counter = Counter}, functions = {
    add = Counter.add, alias = Counter.add,
    step3 = Counter.add:of(3), read = Counter.read,
    sum = Counter.sum, known = Holder.c.read,
}}
