return {
    quotient = word(U32, U32, function(a, b) return a / b end),
    floor = word(U32, U32, function(a, b) return a:idiv(b) end),
    remainder = word(U32, U32, function(a, b) return a % b end),
    power = word(U32, U32, function(a, b) return a ^ b end),
    band = word(U32, U32, function(a, b) return a:band(b) end),
    bor = word(U32, U32, function(a, b) return a:bor(b) end),
    bxor = word(U32, U32, function(a, b) return a:bxor(b) end),
    left = word(U32, U32, function(a, b) return a:shl(b) end),
    right = word(U32, U32, function(a, b) return a:shr(b) end),
    negate = word(U32, function(a) return -a end),
    invert = word(U32, function(a) return a:bnot() end),
}
