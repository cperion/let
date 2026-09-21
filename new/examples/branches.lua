local State = word{
    count = U32,
    flag = Bool,
    test = word(U32, function(n)
        count = count + 1
        return n:lt(5)
    end),
    step = word(U32, function(n)
        count = count + n
        if count:lt(10) then return count * 2 else return count - 1 end
    end),
}

return {
    types = {State = State},
    functions = {
        piecewise = word(U32, function(x)
            if x:lt(10) then return x * 2 else return x + 5 end
        end),
        logic = word(U32, U32, Bool, function(x, y, flag)
            return (x:lt(10) and y:ge(3)) or flag:eq(true)
        end),
        equal = word(Bool, Bool, function(a, b) return a:eq(b) end),
        update = word(State, U32, function(p, x)
            local old = p.count
            p.count = p.count + 1
            if x < p.count then
                p.count = p.count + 10
            else
                local temporary = State{count = old, flag = false}
                temporary.count = temporary.count * 2
                p.count = temporary.count
            end
            p.flag = x:eq(old)
            p.count = p.count + 3
            return p
        end),
        short_circuit = word(State, U32, U32, function(p, x, y)
            p.flag = p.test(x):eq(true) and p.test(y):eq(true)
            return p
        end),
        method = word(State, U32, function(p, n)
            local f = p.step
            local result = f(n)
            p.flag = result:eq(p.count)
            return p
        end),
        unit = word(U32, function(x)
            if x:lt(1) then return end
            local unused = x + 1
        end),
    },
}
