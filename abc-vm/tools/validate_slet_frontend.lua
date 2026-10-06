local root=(arg[0]:match('^(.*)/tools/[^/]+$') or '.')
package.path=root..'/tools/?.lua;'..package.path
local frontend=require('slet_frontend')

local source=[=[
let forms(x, y: i64): i64 = do
    if 3 < x then return (x + 5) ~ y end
    if x >= -2 then return x - y end
    return x * 7
end
let unsigned(a, b: u32): u32 = if a < b then (a << 3) | 1 else (a >> 2) & 7
let main(): i64 = forms(4, 1)
]=]
local asm=frontend.compile(source,{'forms','unsigned'})
local required={
    'BLEI 3 ', 'BLTI %-2 ', 'ADDI%.A 5', 'XORC%.A 1', 'SUBC%.A 1', 'MULI%.A 7',
    'BLEU ', 'SHLI%.A 3', 'ORI%.A 1', 'SHRI%.A 2', 'ANDI%.A 7',
}
for _,pattern in ipairs(required) do assert(asm:match(pattern),'missing spec lowering: '..pattern..'\n'..asm) end
assert(not asm:match('PUSH%.A 5'), 'constant arithmetic regressed to PUSH/MOVE/OP')
assert(not asm:match('LTU%.A%s+JZ'), 'comparison regressed to materialized boolean branch')
print('validated spec operand-form frontend lowering')

