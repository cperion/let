local Callback = word(U32)
local State = word{
    value = U32,
    add = word(U32, function(n) value = value + n; return value end),
}
local Counter = word{value = U32, run = word(Callback, State, U32, function(callback, other, n)
    local before = value
    local loop
    loop = word(U32, function(x)
        if x:eq(0) then return before + value + callback(other.value) end
        value = value + 1
        other.value = other.value + 2
        return loop(x - 1)
    end)
    return loop(n), other.value
end)}
local apply
apply = word(Callback, U32, function(callback, n)
    if n:eq(0) then return callback(1) end
    return apply(callback, n - 1)
end)
local frames
frames = word(Callback, U32, function(callback, n)
    if n:eq(0) then return callback(1) end
    local state = State{value = n}
    local next = word(U32, function(x) return callback(x) + state.value end)
    return frames(next, n - 1)
end)
local identity = word(U32, function(x) return x end)
local Inner = word{value = U32, read = word(function() return bias + value end)}
local Outer = word{bias = U32, child = Inner}
local Both = word{bias = U32, left = Inner, right = Inner}
local Fixed = word{offset = U32, run = word(Callback, U32, function(callback, n)
    local read = word(U32, function(x) return offset + callback(x) end)
    return apply(read, n)
end)}:of{offset = 10}
return {
    types = {State = State, Counter = Counter, Callbacks = word{call = Callback}},
    results = {[Callback] = U32},
    functions = {
        run = Counter.run, frozen = Fixed.run,
        plain = word(Callback, U32, function(callback, n)
            local loop
            loop = word(U32, function(x)
                if x:eq(0) then return callback(7) end
                return loop(x - 1)
            end)
            return loop(n)
        end),
        method = word(U32, function(n)
            local state = State{value = 3}
            local add = state.add
            local callback = word(U32, function(x) return add(x) end)
            local result = apply(callback, n)
            return result, state.value
        end),
        replacement = word(U32, function(n)
            local o = Outer{bias = 10, child = {value = 3}}
            local child = o.child
            local loop
            loop = word(U32, function(x)
                if x:eq(0) then return child.read() end
                child.value = child.value + 1
                return loop(x - 1)
            end)
            o.child = {value = 20}
            return loop(n)
        end),
        paths = word(U32, function(n)
            local o = Both{bias = 10, left = {value = 1}, right = {value = 20}}
            local selected = o.left
            if n:eq(0) then selected = o.right end
            local loop
            loop = word(U32, function(x)
                if x:eq(0) then return selected.read() end
                selected.value = selected.value + 1
                return loop(x - 1)
            end)
            return loop(n)
        end),
        frames = word(U32, function(n) return frames(identity, n) end),
        copy = word(State, U32, function(state, n)
            local loop
            loop = word(U32, function(x)
                if x:eq(0) then return state end
                state.value = state.value + 1
                return loop(x - 1)
            end)
            return loop(n)
        end),
    },
}
