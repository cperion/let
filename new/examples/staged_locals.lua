return {
    captured = word(U32, function(n)
        local add = word(U32, function(x) return n + x end)
        if n:lt(10) then return add(3) end
        return add(7)
    end),
    local_type = word(U32, function(n)
        local Pair = word{x = U32, y = U32}
        local p = Pair{x = n, y = n + 1}
        return p.x + p.y
    end),
}
