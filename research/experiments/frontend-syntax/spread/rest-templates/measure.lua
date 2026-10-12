-- Absolute specialization/code-growth evidence, not a speedup or memory bound.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C,S,Walk,Asm=require('let.compiler'),require('let.schema'),require('let.walk'),require('assembler')
print('family,count,instances,functions,IR_nodes,raw_module_bytes,median_type_ms')
for _,family in ipairs{'same_shape','distinct_lengths'} do for _,count in ipairs{1,2,4,8,16,32} do
 local calls={}
 for i=1,count do
  local args={'n'}
  if family=='distinct_lengths' then for j=2,i do args[#args+1]=tostring(j) end end
  calls[#calls+1]='first('..table.concat(args,',')..')'
 end
 local source='let first(...args): U32 = args[0]\nlet main(n: U32): U32 = '..table.concat(calls,'+')
 local samples,unit={},nil
 for trial=1,7 do
  collectgarbage('collect');local start=os.clock()
  unit=C.typed{profile='slet',source=source,name='growth.slet'}
  samples[trial]=(os.clock()-start)*1000
 end
 table.sort(samples)
 local instances,nodes=0,0
 for _,fn in ipairs(unit.functions) do
  if fn.id:find('first_instance_',1,true) then instances=instances+1 end
  Walk.walk(fn,{enter=function() nodes=nodes+1 end})
 end
 local artifact=C.lower(unit.functions,{profile='slet',exports={'main'}})
 local bytes=Asm.assemble(artifact.assembly)
 local result=C.stage(unit.functions,{profile='slet',entry='main',mode='interpreted',optimize=false,arguments={1}})
 assert(tonumber(result.cells[1])==count)
 print(('%s,%d,%d,%d,%d,%d,%.3f'):format(family,count,instances,#unit.functions,nodes,#bytes,samples[4]))
end end
