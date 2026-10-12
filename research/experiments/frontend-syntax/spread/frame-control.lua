-- No spread syntax: isolates the pre-existing optimizer frame access defect.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C,Stage,D=require('let.compiler'),require('let.stage'),require('let.diag')
local source=[[
let use(a: Array(U32,2)): U32 = a[0]+a[1]
let main(n: U32): U32 = use([n,2])
]]
local unit=C.typed{profile='slet',source=source,name='frame-control.slet'}
local raw=C.lower(unit.functions,{profile='slet',exports={'main'}})
for _,optimized in ipairs{false,true} do
 local session=Stage.open{mode='interpreted',optimize=optimized}
 local ok,result=pcall(function() return session:prepare(raw,unit.functions):call{entry='main',arguments={40}} end)
 if ok then assert(tonumber(result.cells[1])==42);print('optimized='..tostring(optimized)..' -> 42')
 else assert(D.is(result) and result.code=='abc-opt-invalid' and tostring(result):find('frame access outside a live byte block',1,true));print('optimized='..tostring(optimized)..' BLOCKED: '..tostring(result)) end
 session:close()
end
