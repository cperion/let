-- Run from frontend; intentionally reports an unresolved optimizer failure.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local unit=C.typed{profile='slet',name='chain-memory.slet',source=[[
let add(a: u32, b: u32): u32 = a + b
let bad(): u32 = do let xs: array(u32, 1) = [1] return xs[9] end
let main(n: u32): u32 = add(1 / n, bad())
]]}
for _,optimize in ipairs{false,true} do
    local ok,err=pcall(C.stage,unit.functions,{profile='slet',entry='main',mode='interpreted',optimize=optimize,arguments={0}})
    print('optimize='..tostring(optimize),ok and 'unexpected success' or tostring(err))
end
