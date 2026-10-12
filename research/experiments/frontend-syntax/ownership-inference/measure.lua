-- Run from either frontend tree. Seven same-source compilations per case;
-- analysis includes access plus ownership checking when that client exists.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local Access=require('let.access')
local ok,Owner=pcall(require,'let.ownership')
local original=Access.program
local accessTime,ownerTime,stats=0,0,nil
Access.program=function(functions,...)
 local start=os.clock();local result=original(functions,...);accessTime=accessTime+os.clock()-start
 stats=functions.accessStats;return result
end
if ok and require('let.schema').Ownership then
 local infer=Owner.program
 Owner.program=function(...)
  local start=os.clock();local result=infer(...);ownerTime=ownerTime+os.clock()-start;return result
 end
end
local function source(kind,n)
 local lines={}
 if kind=='callback' then
  lines={'let Point = { x: U32 }','let apply(body: (): Unit): Unit = body()'}
  for i=1,n do lines[#lines+1]=('let relay_%d(body: (): Unit): Unit = %s(body)'):format(i,i==1 and 'apply' or 'relay_'..(i-1)) end
  lines[#lines+1]='let main(): U32 = do let p = Point { x = 40 } let body = do() p.x += 1 return end'
  lines[#lines+1]=('relay_%d(body) relay_%d(body) return p.x end'):format(n,n)
 else
  lines={'let apply(n: U32): U32 = n+1'}
  for i=1,n do lines[#lines+1]=('let relay_%d(n: U32): U32 = %s(n)'):format(i,i==1 and 'apply' or 'relay_'..(i-1)) end
  lines[#lines+1]=('let main(): U32 = relay_%d(20)+relay_%d(20)'):format(n,n)
 end
 return table.concat(lines,'\n')
end
local function median(values) table.sort(values);return values[4] end
for _,case in ipairs{{'scalar',12},{'scalar',40},{'callback',12},{'callback',24}} do
 local times,analysis,memory={},{},{}
 local unit
 for _=1,7 do
  collectgarbage('collect');local before=collectgarbage('count');accessTime=0;ownerTime=0
  local start=os.clock();unit=C.typed{profile='let',source=source(case[1],case[2]),name='ownership-cost.let'}
  times[#times+1]=1000*(os.clock()-start);analysis[#analysis+1]=1000*(accessTime+ownerTime)
  memory[#memory+1]=collectgarbage('count')-before
 end
 print(('%s wrappers=%d typed_ms=%.3f analysis_ms=%.3f live_Lua_delta_KiB=%.1f contexts=%d evaluations=%d'):format(
  case[1],case[2],median(times),median(analysis),median(memory),stats.contexts,stats.iterations))
end
