-- Exact scalar semantics, shared by the concrete test interpreter, compile-time folding, and
-- (through the emitter's own text) the C program, so no two of them can disagree.
--
-- Int and Float arithmetic is the host's own `+`, `-`, `*` and unary `-` on the value the
-- backend uses: LuaJIT's int64 cdata and PUC Lua's integer both wrap exactly as §13.2 requires,
-- and a Float is a binary64. Everything the two hosts spell differently -- truncated division
-- and remainder, bitwise, shifts, conversions, and the C limbs -- comes from `let/host`, so the
-- language's semantics do not depend on which runtime is running the compiler.
local numeric = require('let.numeric')
local literal = require('let.literal')

local M = {}

M.min = numeric.min
M.unit = {}

-- Validates spelling and range, then converts without passing through a Lua number.
function M.integer(spelling, fail)
    local negative = spelling:sub(1, 1) == '-'
    local _, _, hi, lo = literal.integer(negative and spelling:sub(2) or spelling, negative, fail or error)
    return numeric.from_limbs(hi, lo, negative)
end

-- An Int from a host value, for the test interpreter's stage and result conversion.
function M.int64(value) return numeric.from_float(value) end

-- A Float value is a binary64, and this conversion is the one authority for both folding and C
-- emission, so the two cannot round differently.
function M.float(spelling, fail) return literal.float(spelling, fail or error) end

-- Float division is the IEEE operation; a Float32 division rounds the binary64 result back to
-- binary32, so folding and the emitted `float` division agree (DEMAND.md §3).
function M.fdivide(a, b, kind)
    if kind == 'f32' then return numeric.round32(a / b) end
    return a / b
end

-- The two core conversions. `to_float` is total; `to_int` is also total, truncating toward
-- zero and saturating at the Int bounds with a NaN becoming zero, so it stays a pure value
-- operation that can be folded and dropped.
function M.to_float(value) return numeric.to_float(value) end
function M.to_int(value) return numeric.from_float(value) end
-- The fixed-width conversions truncate the low bits of an Int; they are the explicit crossings
-- §13.2 asks for, so no literal or value changes width implicitly.
function M.to_u8(value) return numeric.truncate(8, value) end
function M.to_u32(value) return numeric.truncate(32, value) end
-- A binary64 rounded to the nearest binary32, ties to even (§13.3).
function M.to_f32(value) return numeric.round32(value) end

-- Arithmetic computes the mathematical result, then reduces it modulo 2^width when the type is
-- a fixed-width integer. The width comes from the Let type, never from the host's
-- representation: a nil width is Int (which the host wraps at 64 bits, as §13.2 requires) or
-- Float (where `+ - *` are the binary64 operations).
-- The `kind` is the result type's: 'f32' rounds to binary32, 8/32 reduce modulo 2^width, and
-- nil is Int (the host wraps at 64 bits) or Float (binary64).
function M.add(a, b, kind)
    if kind == 'f32' then return numeric.round32(a + b) end
    if kind then return numeric.truncate(kind, numeric.add(a, b)) end
    return a + b
end
function M.subtract(a, b, kind)
    if kind == 'f32' then return numeric.round32(a - b) end
    if kind then return numeric.truncate(kind, numeric.sub(a, b)) end
    return a - b
end
function M.multiply(a, b, kind)
    if kind == 'f32' then return numeric.round32(a * b) end
    if kind then return numeric.truncate(kind, numeric.mul(a, b)) end
    return a * b
end
function M.negate(a, kind)
    if kind == 'f32' then return numeric.round32(-a) end
    if kind then return numeric.truncate(kind, numeric.neg(a)) end
    return -a
end

-- Division and remainder by zero trap; callers either know the divisor is non-zero (and fold)
-- or must keep a residual checked operation. Truncation and sign come from the backend, because
-- Lua's floor division is not §13.2's.
function M.divide(a, b, width)
    if b == 0 then error('division by zero') end
    local quotient = numeric.div(a, b)
    return width and numeric.truncate(width, quotient) or quotient
end
function M.remainder(a, b, width)
    if b == 0 then error('remainder by zero') end
    local rest = numeric.rem(a, b)
    return width and numeric.truncate(width, rest) or rest
end

function M.equal(a, b) return a == b end
function M.not_equal(a, b) return a ~= b end
function M.less(a, b) return a < b end
function M.less_equal(a, b) return a <= b end
function M.greater(a, b) return a > b end
function M.greater_equal(a, b) return a >= b end

-- Bitwise operations are integer-only and the hosts spell them differently, so they come from
-- the backend and are reduced to the width. §13.2 fixes the semantics: `>>` is arithmetic for
-- Int and logical for the unsigned widths, which for a non-negative fixed-width value is the
-- same operation, and a shift count is reduced modulo the width.
function M.band(a, b, width) local r = numeric.band(a, b); return width and numeric.truncate(width, r) or r end
function M.bor(a, b, width) local r = numeric.bor(a, b); return width and numeric.truncate(width, r) or r end
function M.bxor(a, b, width) local r = numeric.bxor(a, b); return width and numeric.truncate(width, r) or r end
function M.bitnot(a, width) local r = numeric.bnot(a); return width and numeric.truncate(width, r) or r end
function M.shl(a, b, width)
    if width then return numeric.truncate(width, numeric.shl(a, numeric.rem(b, width))) end
    return numeric.shl(a, b)
end
function M.shr(a, b, width)
    if width then return numeric.truncate(width, numeric.shr(a, numeric.rem(b, width))) end
    return numeric.shr(a, b)
end

-- Two's-complement limbs for C emission.
function M.limbs(value) return numeric.to_limbs(value) end

-- The exact decimal of an Int, independent of the host's spelling of its integer type.
function M.int_string(value) return numeric.to_string(value) end

-- The byte length of a Text, shared so a known Text folds and the emitted C reads `.size`.
function M.text_size(value) return #value end

return M
