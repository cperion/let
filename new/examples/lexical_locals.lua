local Counter = word{count = U32,
    add = word(U32, function(n) count = count + n; return count end),
    step = word(U32, function(n)
        local increment = word(U32, function(x) return add(x) end)
        return increment(n)
    end),
    sum = word(U32, function(n)
        local loop
        loop = word(U32, function(x)
            if x:eq(0) then return count end
            count = count + 1
            return loop(x - 1)
        end)
        return loop(n)
    end),
    snapshot = word(Unit, function()
        local value = count
        return word(U32, function(x) return value + x end)
    end),
}
return {types = {Counter = Counter}, functions = {step = Counter.step, sum = Counter.sum, snapshot = Counter.snapshot}}
