-- Exact scalar semantics, shared by the concrete test interpreter and the abstract
-- evaluator so the two cannot drift.
--
-- LuaJIT's 64-bit cdata arithmetic is already the behavior §13.2 requires: wrapping
-- +,-,*; quotient truncated toward zero; remainder with the dividend's sign; and
-- INT_MIN / -1 wrapping to INT_MIN with INT_MIN % -1 equal to zero.
local ffi=require('ffi')
local literal=require('let.literal')
local M={}

M.min=ffi.cast('int64_t',0x8000000000000000ULL)
M.unit={}

-- Validates spelling and range, then converts without passing through a Lua number.
function M.integer(spelling,fail)
    local negative=spelling:sub(1,1)=='-'
    local _,_,hi,lo=literal.integer(negative and spelling:sub(2) or spelling,negative,fail or error)
    local magnitude=ffi.cast('uint64_t',hi)*4294967296ULL+lo
    return negative and -ffi.cast('int64_t',magnitude) or ffi.cast('int64_t',magnitude)
end

-- A Float value is a Lua number (a binary64), and this conversion is the one authority for
-- both folding and C emission, so the two cannot round differently.
function M.float(spelling,fail) return literal.float(spelling,fail or error) end

function M.fdivide(a,b) return a/b end

function M.add(a,b) return a+b end
function M.subtract(a,b) return a-b end
function M.multiply(a,b) return a*b end
function M.negate(a) return -a end

-- Division and remainder by zero trap; callers either know the divisor is non-zero
-- (and fold) or must keep a residual checked operation.
function M.divide(a,b)
    if b==0 then error('division by zero') end
    return a/b
end
function M.remainder(a,b)
    if b==0 then error('remainder by zero') end
    return a%b
end

function M.equal(a,b) return a==b end
function M.not_equal(a,b) return a~=b end
function M.less(a,b) return a<b end
function M.less_equal(a,b) return a<=b end
function M.greater(a,b) return a>b end
function M.greater_equal(a,b) return a>=b end

-- Two's-complement limbs for C emission.
function M.limbs(value)
    local unsigned=ffi.cast('uint64_t',value)
    return tonumber(unsigned/4294967296ULL),tonumber(unsigned%4294967296ULL)
end

return M
