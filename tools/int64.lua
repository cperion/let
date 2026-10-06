-- Exact cell arithmetic for LuaJIT. No uint64 value passes through a double.
local ffi, bit = require('ffi'), require('bit')
local M = {}
M.ffi, M.bit = ffi, bit
local U, I = ffi.typeof('uint64_t'), ffi.typeof('int64_t')
M.zero, M.one = U(0), U(1)
M.max = bit.bnot(U(0))
M.sign = bit.lshift(U(1), 63)
M.types = {u8={8,false}, u16={16,false}, u32={32,false}, u64={64,false},
           i32={32,true}, i64={64,true}}
function M.u(value) return ffi.cast(U, value) end
function M.i(value) return ffi.cast(I, value) end
function M.negative(value) return M.i(value) < I(0) end
function M.mask(width) return width == 64 and M.max or bit.lshift(U(1), width) - U(1) end
function M.format(value, signed)
    local text=tostring(signed and M.i(value) or M.u(value)):gsub('U?LL$', '')
    return text
end
function M.parse(text)
    local negative = text:sub(1,1) == '-'
    if negative then text = text:sub(2) end
    local base = 10
    if text:sub(1,2):lower() == '0x' then base, text = 16, text:sub(3)
    elseif text:sub(1,2):lower() == '0b' then base, text = 2, text:sub(3) end
    if text == '' or text:sub(1,1) == '_' or text:sub(-1) == '_' or text:find('__',1,true) then
        error('invalid integer or digit separator', 0)
    end
    local value = U(0)
    for digit in text:gmatch('.') do
        if digit ~= '_' then
            local n = tonumber(digit, 16)
            if not n or n >= base then error('invalid integer digit', 0) end
            if value > (M.max - U(n)) / U(base) then error('literal exceeds 64 bits', 0) end
            value = value * U(base) + U(n)
        end
    end
    if negative then
        if value > M.sign then error('signed literal is below i64 minimum', 0) end
        value = -value
    end
    return M.u(value), negative
end
function M.fits(value, negative, width, signed)
    value = M.u(value)
    if negative then
        if not signed then return false end
        local minimum = width == 64 and M.i(M.sign) or -M.i(bit.lshift(U(1), width-1))
        return M.i(value) >= minimum and M.i(value) <= I(0)
    end
    return value <= (signed and (bit.lshift(U(1), width-1)-U(1)) or M.mask(width))
end
function M.constant(value, type_, negative)
    return {value=M.u(value), type=type_, literal_negative=negative or false}
end
function M.natural(c)
    if c.type ~= 'literal' then return c.type end
    if c.literal_negative then return 'i64' end
    return c.value <= U(0xffffffff) and 'u32' or 'u64'
end
function M.isnegative(c)
    local t = M.natural(c)
    return M.types[t] and M.types[t][2] and M.negative(c.value) or false
end
function M.normalize(value, type_)
    if type_ == 'unit' then return U(0) end
    if type_ == 'bool' then return M.u(value) end
    local width, signed = unpack(M.types[type_])
    if type_ == 'i32' then return M.u(ffi.cast('int32_t', value)) end
    return width == 64 and M.u(value) or bit.band(M.u(value), M.mask(width))
end
function M.convert(c, target, explicit)
    local source = M.natural(c)
    if source == 'unit' or source == 'bool' or target == 'unit' or target == 'bool' then
        if source ~= target then error('cannot convert '..source..' to '..target, 0) end
        return M.constant(c.value, target)
    end
    if explicit and c.type ~= 'literal' and M.types[source][1] == M.types[target][1] and M.types[target][1] < 64 then
        return M.constant(M.normalize(c.value, target), target)
    end
    local width, signed = unpack(M.types[target])
    if not M.fits(c.value, M.isnegative(c), width, signed) then
        error('numeric-range: '..M.format(c.value, M.isnegative(c))..' does not fit '..target, 0)
    end
    return M.constant(c.value, target)
end
function M.common(a,b)
    if a == b then return a end
    if not M.types[a] or not M.types[b] then error('cannot combine '..a..' and '..b,0) end
    if M.types[a][2] ~= M.types[b][2] then error('signed and unsigned operands need an explicit conversion',0) end
    return M.types[a][1] >= M.types[b][1] and a or b
end
function M.widenable(a,b)
    if a == b then return true end
    local x,y = M.types[a], M.types[b]
    if not x or not y then return false end
    if x[2] == y[2] then return x[1] <= y[1] end
    return not x[2] and y[2] and x[1] < y[1]
end
function M.pack(value, bytes)
    local parts = {}
    value = M.u(value)
    for i=0,bytes-1 do parts[#parts+1] = string.char(tonumber(bit.band(bit.rshift(value,i*8), U(255)))) end
    return table.concat(parts)
end
function M.pow(x,e)
    local result = U(1)
    while e ~= U(0) do
        if bit.band(e,U(1)) ~= U(0) then result = result*x end
        x=x*x; e=bit.rshift(e,1)
    end
    return result
end
function M.binary(op, left, right, type_)
    local signed = M.types[type_] and M.types[type_][2]
    local x,y = left.value,right.value
    local a,b = signed and M.i(x) or x, signed and M.i(y) or y
    local value
    if op == '+' then value=x+y
    elseif op == '-' then value=x-y
    elseif op == '*' then value=x*y
    elseif op == '/' or op == '%' then
        if y == U(0) then error('known zero divisor rejects at compile time',0) end
        -- LuaJIT/C division of MIN/-1 must not reach the native divide trap.
        if signed and x == M.sign and y == M.max then value = op == '/' and M.sign or U(0)
        else value = op == '/' and (a/b) or (a%b) end
    elseif op == '^' then value=M.pow(x,y)
    elseif op == '&' then value=bit.band(x,y)
    elseif op == '|' then value=bit.bor(x,y)
    elseif op == '~' then value=bit.bxor(x,y)
    elseif op == '<<' then value=y >= U(64) and U(0) or bit.lshift(x,tonumber(y))
    elseif op == '>>' then
        if y >= U(64) then value = signed and M.negative(x) and M.max or U(0)
        elseif signed then value=bit.arshift(M.i(x),tonumber(y))
        else value=bit.rshift(x,tonumber(y)) end
    elseif op == '==' then value=a==b and 1 or 0
    elseif op == '!=' then value=a~=b and 1 or 0
    elseif op == '<' then value=a<b and 1 or 0
    elseif op == '<=' then value=a<=b and 1 or 0
    elseif op == '>' then value=a>b and 1 or 0
    elseif op == '>=' then value=a>=b and 1 or 0
    else error('unsupported operator '..op,0) end
    local comparison = op=='==' or op=='!=' or op=='<' or op=='<=' or op=='>' or op=='>='
    return M.constant(comparison and M.u(value) or M.normalize(value,type_), comparison and 'bool' or type_)
end
return M

