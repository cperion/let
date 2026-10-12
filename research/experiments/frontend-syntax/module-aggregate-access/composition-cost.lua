-- Run from frontend, also against the pre-correction frontend snapshot.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local Access=require('let.access')
local original=Access.program
local times,peaks={},{}
Access.program=function(functions)
 collectgarbage('collect');local memory=collectgarbage('count');local start=os.clock()
 local summary=original(functions)
 local elapsed=os.clock()-start;local peak=collectgarbage('count')-memory
 times[#times+1]=elapsed;peaks[#peaks+1]=peak
 -- Keep summaries alive here to include their retained metadata.
 collectgarbage('collect')
 local retained=collectgarbage('count')-memory
 if #times==7 then
  table.sort(times);table.sort(peaks)
  print(('access median CPU: %.6fs; peak Lua delta: %.1f KiB; last retained Lua delta: %.1f KiB'):format(times[4],peaks[4],retained))
  local stats=functions.accessStats
  if stats then print(('contexts: %d; provenance/state points: %d; worklist evaluations: %d'):format(stats.contexts,stats.relations,stats.iterations)) end
 end
 return summary
end
local lines={'let Point = { x: U32 }','let apply(body: (): Unit): Unit = body()'}
for i=1,12 do
 lines[#lines+1]=('let relay_%d(body: (): Unit): Unit = %s(body)'):format(i,i==1 and 'apply' or 'relay_'..(i-1))
end
lines[#lines+1]=[[
let main(): U32 = do
 let p = Point { x = 40 }
 let body = do() p.x += 1 return end
 relay_12(body)
 relay_12(body)
 return p.x
end
]]
local source=table.concat(lines,'\n')
for _=1,7 do C.typed{profile='let',source=source,name='composition-cost.let'} end
