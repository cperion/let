-- Measurement only: no checker implementation changes. Run from either frontend.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local Access=require('let.access')
local mode=arg[1] or 'scale'
local function source(kind,n,locals)
 local lines={}
 if kind=='callback' then
  lines={'let Point = { x: U32 }','let apply(body: (): Unit): Unit = body()'}
  for i=1,n do lines[#lines+1]=('let relay_%d(body: (): Unit): Unit = %s(body)'):format(i,i==1 and 'apply' or 'relay_'..(i-1)) end
  lines[#lines+1]='let main(): U32 = do let p = Point { x = 40 } let body = do() p.x += 1 return end'
  for i=1,locals or 0 do lines[#lines+1]=('let unused_%d = [0]'):format(i) end
  local call=n==0 and 'apply' or 'relay_'..n
  lines[#lines+1]=call..'(body) '..call..'(body) return p.x end'
 else
  lines={'let apply(x: U32): U32 = x + 1'}
  for i=1,n do lines[#lines+1]=('let relay_%d(x: U32): U32 = %s(x)'):format(i,i==1 and 'apply' or 'relay_'..(i-1)) end
  lines[#lines+1]='let main(): U32 = do'
  for i=1,locals or 0 do lines[#lines+1]=('let unused_%d = [0]'):format(i) end
  local call=n==0 and 'apply' or 'relay_'..n
  lines[#lines+1]='return '..call..'(20) + '..call..'(20) end'
 end
 return table.concat(lines,'\n')
end
local function median(values) table.sort(values);return values[math.floor(#values/2)+1] end
local function measure(kind,n,locals)
 local text=source(kind,n,locals)
 local unit=C.typed{profile='let',source=text,name='access-perf.let'}
 for _=1,8 do Access.program(unit.functions) end
 local access,total={},{}
 for _=1,11 do
  collectgarbage('collect');local start=os.clock()
  for _=1,5 do Access.program(unit.functions) end
  access[#access+1]=(os.clock()-start)/5
  collectgarbage('collect');start=os.clock()
  for _=1,3 do C.typed{profile='let',source=text,name='access-perf.let'} end
  total[#total+1]=(os.clock()-start)/3
 end
 local st=unit.functions.accessStats
 print(('%s wrappers=%d unused_locals=%d functions=%d access_ms=%.3f typed_ms=%.3f contexts=%s points=%s evaluations=%s'):format(kind,n,locals or 0,#unit.functions,1000*median(access),1000*median(total),st and st.contexts or '-',st and st.relations or '-',st and st.iterations or '-'))
end
if mode=='profile' then
 local kind=arg[2] or 'callback';local n=tonumber(arg[3]) or 12
 local unit=C.typed{profile='let',source=source(kind,n,tonumber(arg[4]) or 0),name='access-profile.let'}
 for _=1,20 do Access.program(unit.functions) end
 local profiler=require('jit.p');profiler.start('li1',arg[5] or '/tmp/access-profile.txt')
 local start=os.clock();local count=0
 repeat Access.program(unit.functions);count=count+1 until os.clock()-start>8
 profiler.stop();print('profile runs',count,'CPU',os.clock()-start)
else
 for _,kind in ipairs{'scalar','callback'} do for _,n in ipairs{0,4,8,12,24,48} do measure(kind,n,0) end end
 for _,kind in ipairs{'scalar','callback'} do for _,locals in ipairs{8,32,64} do measure(kind,12,locals) end end
end
