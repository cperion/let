package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local unit=C.typed({profile='slet',source=[[
let Point = { x: U32 }
let original = Point { x = 40 }
let alias = original
let main(): U32 = do alias.x = 42 return original.x end
]]},{staticMode='interpreted'})
local result=C.stage(unit.functions,{profile='slet',mode='interpreted',entry='main'})
print('module alias result',tonumber(result.cells[1]),'expected',42)
print('physical logical roots',#unit.functions.moduleData,'expected',1)
assert(tonumber(result.cells[1])==42,'module alias must observe the shared root')
assert(#unit.functions.moduleData==1,'module alias must not create copied storage')
