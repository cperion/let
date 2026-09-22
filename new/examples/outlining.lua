-- Each function has five independent decisions. Explicit boundaries prevent
-- the two classify calls from multiplying the caller's replay paths.
local classify = word(U32, U32, U32, U32, U32, function(a, b, c, d, e)
    local t = U32(0)
    if a:lt(5) then t = t + 1 else t = t + 2 end
    if b:lt(10) then t = t + 4 else t = t + 8 end
    if c:lt(15) then t = t + 16 else t = t + 32 end
    if d:lt(20) then t = t + 64 else t = t + 128 end
    if e:lt(25) then t = t + 256 else t = t + 512 end
    return t
end)
local top = word(U32, U32, U32, U32, U32, U32, U32, U32, U32, U32,
    function(p, q, r, s, u, v, w, x, y, z)
        local acc = classify(p, q, r, s, u) + classify(v, w, x, y, z)
        if p:lt(1) then acc = acc + 1 else acc = acc + 2 end
        if q:lt(2) then acc = acc + 1 else acc = acc + 2 end
        if r:lt(3) then acc = acc + 1 else acc = acc + 2 end
        if s:lt(4) then acc = acc + 1 else acc = acc + 2 end
        if u:lt(5) then acc = acc + 1 else acc = acc + 2 end
        return acc
    end)
return {functions = {top = top}, outline = {classify}}
