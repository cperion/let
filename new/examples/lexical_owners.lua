local Inner = word{
    value = U32,
    read = word(function() return bias + value end),
    step = word(U32, function(n)
        if n:eq(0) then return read() end
        bias = bias + 1
        value = value + 2
        return step(n - 1)
    end),
}
local Outer = word{bias = U32, left = Inner, right = Inner}
return {
    types = {Outer = Outer},
    functions = {
        run = word(U32, function(n)
            local o = Outer{bias = 10, left = {value = 1}, right = {value = 20}}
            local left = o.left.step(n)
            local right = o.right.step(n)
            return left, right, o.bias, o.left.value, o.right.value
        end),
        replace = word(U32, function(x)
            local o = Outer{bias = 3, left = {value = 1}, right = {value = 9}}
            local read = o.left.read
            o.left = {value = x}
            return read()
        end),
    },
}
