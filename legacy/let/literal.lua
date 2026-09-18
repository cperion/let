-- Validate spelling/range without passing a 64-bit integer through a Lua number.
local M={}
function M.integer(spelling,negative,fail)
    local base,body=10,spelling
    if body:sub(1,2)=='0x' then base,body=16,body:sub(3) end
    local digits=body:gsub('_','')
    if body=='' or body:sub(1,1)=='_' or body:sub(-1)=='_' or body:find('__',1,true) or
       not digits:match(base==16 and '^[0-9a-fA-F]+$' or '^[0-9]+$') then fail('invalid integer spelling') end
    local hi,lo=0,0
    for digit in digits:gmatch('.') do
        local next_=lo*base+tonumber(digit,base)
        lo,hi=next_%4294967296,hi*base+math.floor(next_/4294967296)
        if hi>2147483648 or (hi==2147483648 and (lo~=0 or not negative)) then fail('integer literal out of Int range') end
    end
    local sign=negative and (hi~=0 or lo~=0) and '-' or ''
    return sign .. (base==16 and '0x' or '') .. digits,sign .. hi .. ':' .. lo,hi,lo
end
-- A Float literal: the grammar has a digit on each side of `.`, and an exponent carries at
-- least one digit. Value and C emission both take their bits from this one conversion, so
-- folding and execution cannot round differently.
local function digits(text)
    return text~='' and text:sub(1,1)~='_' and text:sub(-1)~='_' and not text:find('__',1,true)
        and text:match('^[0-9_]+$')~=nil
end
function M.float(spelling,fail)
    local mantissa,exponent=spelling,nil
    local at=spelling:find('[eE]')
    if at then
        mantissa=spelling:sub(1,at-1); exponent=spelling:sub(at+1)
        local sign=exponent:sub(1,1)
        if sign=='+' or sign=='-' then exponent=exponent:sub(2) end
        if not digits(exponent) then fail('invalid Float spelling') end
    end
    local point=mantissa:find('.',1,true)
    if point then
        if not digits(mantissa:sub(1,point-1)) or not digits(mantissa:sub(point+1)) then fail('invalid Float spelling') end
    elseif not digits(mantissa) then fail('invalid Float spelling') end
    if not point and not at then fail('invalid Float spelling') end
    local value=tonumber((spelling:gsub('_','')))
    if value==nil then fail('invalid Float spelling') end
    return value
end
return M

