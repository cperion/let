-- The 64-bit integer backend for LuaJIT.
--
-- LuaJIT's FFI `int64_t` already wraps for `+`, `-`, `*` and unary `-` exactly as §13.2
-- requires, and its cdata `/` and `%` already truncate toward zero with the dividend's sign.
-- This file holds the operations LuaJIT does not give directly, and the value construction,
-- so nothing above it depends on FFI.
local ffi = require('ffi')

local M = {}

M.min = ffi.cast('int64_t', 0x8000000000000000ULL)

function M.from_limbs(hi, lo, negative)
    local magnitude = ffi.cast('uint64_t', hi) * 4294967296ULL + lo
    return negative and -ffi.cast('int64_t', magnitude) or ffi.cast('int64_t', magnitude)
end

-- Float to Int: truncate toward zero, saturate at the bounds, and a NaN becomes zero (§13.3).
function M.from_float(value)
    if value ~= value then return ffi.new('int64_t', 0) end
    if value >= 9223372036854775808.0 then return ffi.cast('int64_t', 0x7fffffffffffffffULL) end
    if value < -9223372036854775808.0 then return ffi.cast('int64_t', 0x8000000000000000ULL) end
    return ffi.new('int64_t', value)
end

function M.to_float(value) return tonumber(value) end

-- The exact decimal, with no host spelling: LuaJIT appends `LL` to cdata integers.
function M.to_string(value) return (tostring(value):gsub('LL$','')) end

-- Round a binary64 to the nearest binary32, ties to even, preserving NaN and infinity.
function M.round32(value) return tonumber(ffi.cast('float', value)) end

function M.to_limbs(value)
    local unsigned = ffi.cast('uint64_t', value)
    return tonumber(unsigned / 4294967296ULL), tonumber(unsigned % 4294967296ULL)
end

-- Reduce to the low `width` bits as a non-negative Int. Fixed-width arithmetic computes in
-- 64 bits and then reduces here, so the width is the language's, not the host's.
function M.truncate(width, value)
    if width == 8 then return ffi.cast('int64_t', ffi.cast('uint8_t', value)) end
    return ffi.cast('int64_t', ffi.cast('uint32_t', value))
end

-- Arithmetic wraps identically on both hosts, but the backends expose it so `scalar` never
-- names a host operator directly.
function M.add(a, b) return a + b end
function M.sub(a, b) return a - b end
function M.mul(a, b) return a * b end
function M.neg(a) return -a end

function M.div(a, b) return a / b end
function M.rem(a, b) return a % b end

function M.band(a, b) return a & b end
function M.bor(a, b) return a | b end
function M.bxor(a, b) return a ~ b end
function M.bnot(a) return ~a end

-- A shift count is reduced modulo 64, and `<<` keeps the low 64 bits (§13.2).
function M.shl(a, b)
    return ffi.cast('int64_t', ffi.cast('uint64_t', a) << (ffi.cast('uint64_t', b) % 64))
end

-- LuaJIT's cdata `>>` is logical, so arithmetic is written out: shift the bit pattern, then
-- fill the vacated high bits with the sign bit.
function M.shr(a, b)
    local shift = ffi.cast('uint64_t', b) % 64
    local bits = ffi.cast('uint64_t', a) >> shift
    if a < 0 and shift ~= 0 then bits = bits | ~(ffi.cast('uint64_t', 0xffffffffffffffffULL) >> shift) end
    return ffi.cast('int64_t', bits)
end

return M
