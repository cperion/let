-- Why template instance creation cannot replace definition-time capture formation.
package.path='./?.lua;./?/init.lua;../tools/?.lua;'..package.path
local C=require('let.compiler')
local source=[[
let Box={n: U32}
let main(): U32 = do
 let a=Box {n=10}
 let b=Box {n=20}
 let r=Ref(a)
 let saved(): U32 = r.n
 r=Ref(b)
 return saved()
end
]]
local unit=C.typed{profile='slet',source=source,name='formation-point.slet'}
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
 local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=false})
 assert(tonumber(result.cells[1])==10,'ordinary captures snapshot at formation, not invocation')
 print(mode..': captured original reference -> '..tonumber(result.cells[1]))
end
for _,fn in ipairs(unit.functions) do
 print('function '..fn.id)
 for index,stmt in ipairs(fn.body) do print(index,tostring(stmt)) end
end
