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
return M

