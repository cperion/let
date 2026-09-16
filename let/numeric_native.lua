-- The 64-bit integer backend for PUC Lua 5.3 and 5.4.
--
-- There, an integer is already signed 64-bit and wraps for `+`, `-`, `*` and unary `-`, so the
-- arithmetic needs no help. What differs from §13.2 is spelled out here: Lua's `//` and `%`
-- floor instead of truncating toward zero, `>>` is logical, and a shift count of 64 or more
-- produces zero instead of wrapping.
local M = {}

M.min = math.mininteger

function M.from_limbs(hi, lo, negative)
    local value = hi * 4294967296 + lo
    return negative and -value or value
end

function M.from_float(value)
    if value ~= value then return 0 end
    if value >= 9223372036854775808.0 then return math.maxinteger end
    if value < -9223372036854775808.0 then return math.mininteger end
    local truncated = value < 0 and math.ceil(value) or math.floor(value)
    return math.tointeger(truncated) or 0
end

function M.to_float(value) return value + 0.0 end

function M.to_string(value) return tostring(value) end

-- Round a binary64 to the nearest binary32, ties to even, preserving NaN and infinity.
function M.round32(value) return (string.unpack('<f', string.pack('<f', value))) end

function M.to_limbs(value)
    return (value >> 32) & 0xffffffff, value & 0xffffffff
end

-- Reduce to the low `width` bits. Fixed-width arithmetic computes in 64 bits and then
-- reduces here, so the width is the language's, not the host's.
function M.truncate(width, value)
    if width == 8 then return value & 0xff end
    return value & 0xffffffff
end

function M.add(a, b) return a + b end
function M.sub(a, b) return a - b end
function M.mul(a, b) return a * b end
function M.neg(a) return -a end

-- Truncated division: floor the quotient, then step back toward zero when the signs differ.
function M.div(a, b)
    if a == math.mininteger and b == -1 then return math.mininteger end
    local quotient = a // b
    if a % b ~= 0 and ((a < 0) ~= (b < 0)) then quotient = quotient + 1 end
    return quotient
end

function M.rem(a, b)
    if a == math.mininteger and b == -1 then return 0 end
    return a - M.div(a, b) * b
end

function M.band(a, b) return a & b end
function M.bor(a, b) return a | b end
function M.bxor(a, b) return a ~ b end
function M.bnot(a) return ~a end

function M.shl(a, b) return a << (b & 63) end

function M.shr(a, b)
    local shift = b & 63
    if shift == 0 then return a end
    local bits = a >> shift
    if a < 0 then bits = bits | (~0 << (64 - shift)) end
    return bits
end

return M
