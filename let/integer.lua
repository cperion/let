-- Exact literal validation is shared by checking and residualization.
local A = require('let.vocab').Syntax
local fail = require('let.lexer').fail
function A.Integer:parts(allow_min)
    local text = self.spelling:gsub('_', '')
    local base = 10
    if text:sub(1, 2) == '0x' then base, text = 16, text:sub(3) end
    local hi, lo = 0, 0
    for c in text:gmatch('.') do
        local digit = tonumber(c, base)
        local n = lo * base + digit
        lo, hi = n % 4294967296, hi * base + math.floor(n / 4294967296)
        if hi > 2147483648 or (hi == 2147483648 and (lo ~= 0 or not allow_min)) then fail(self.span, 'integer literal out of Int range') end
    end
    return hi, lo
end
return A.Integer

