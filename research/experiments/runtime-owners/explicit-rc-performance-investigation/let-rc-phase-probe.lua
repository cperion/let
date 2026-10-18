package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local profile=require('jit.profile')
local counts={};local started=os.clock();local last=started
profile.start('li10',function(thread,samples,state)
 local stack=profile.dumpstack(thread,'pl',6);local k=state..' '..stack;counts[k]=(counts[k] or 0)+samples
 if os.clock()-last>5 then io.stderr:write(('progress cpu=%.1f heap=%.1f MiB\n'):format(os.clock()-started,collectgarbage('count')/1024));io.stderr:flush();last=os.clock() end
end)
local function wrap(module,name)
 local m=require(module);local fn=m[name]
 m[name]=function(...)
  local at=os.clock();local result={fn(...)}
  io.stderr:write(('phase %s.%s %.3fs heap=%.1f MiB\n'):format(module,name,os.clock()-at,collectgarbage('count')/1024));io.stderr:flush()
  if module=='let.access' and name=='analyze' then for k,v in pairs(result[3]) do io.stderr:write(' access '..k..'='..tostring(v)..'\n') end end
  return unpack(result)
 end
end
for _,entry in ipairs{{'let.check','program'},{'let.access','analyze'},{'let.ownership','analyze'},{'let.program','analyze'},{'let.placement','program'},{'let.abc','lower'},{'let.semantic','build'}} do wrap(unpack(entry)) end
local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*)/[^/]+$')
local f=assert(io.open(directory..'/fixture.lua'));local text=f:read('*a');f:close()
local source=assert(text:match('local source=%[%[(.-)%]%]'))
local exports=assert(loadstring('return '..assert(text:match('local exports=(%b{})'))))()
local artifact=require('let.compiler').compile{profile='slet',source=source,exports=exports,staticMode='interpreted',staticOptimize=false}
profile.stop()
local sorted={};for k,v in pairs(counts) do sorted[#sorted+1]={k,v} end;table.sort(sorted,function(a,b)return a[2]>b[2]end)
for i=1,math.min(25,#sorted) do print(sorted[i][2],sorted[i][1]) end
local byFn={};local total=0
for _,ctx in pairs(artifact.program.flow.contexts) do byFn[ctx.fn_id]=(byFn[ctx.fn_id] or 0)+1;total=total+1 end
local top={};for k,v in pairs(byFn) do top[#top+1]={k,v} end;table.sort(top,function(a,b)return a[2]>b[2]end)
print('source functions',#artifact.program.functions,'contexts',total,'assembly bytes',#artifact.assembly)
for i=1,math.min(15,#top) do print('contexts',unpack(top[i])) end
