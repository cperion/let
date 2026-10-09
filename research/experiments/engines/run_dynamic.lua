#!/usr/bin/env luajit
local here=arg[0]:match('^(.*)/') or '.'
package.path=here..'/?.lua;'..package.path
local workloads=require('dynamic_workloads')
local abc=here..'/../../../build/abc'
local cc=os.getenv('CC') or 'clang'
local lua=os.getenv('LUAJIT') or 'luajit'
local trials=tonumber(os.getenv('TRIALS') or '9')
assert(trials and trials>=3 and trials%2==1,'TRIALS must be odd and >=3')
local sf=assert(io.open('/proc/self/status'));local status=sf:read('*a');sf:close()
local core=assert(status:match('Cpus_allowed_list:%s*(%d+)'))
local function quote(x) return "'"..tostring(x):gsub("'","'\\''").."'" end
local function run(args,unbound)
  local words=unbound and {} or {'taskset','-c',core}
  for _,v in ipairs(args) do words[#words+1]=v end
  for i,v in ipairs(words) do words[i]=quote(v) end
  local p=assert(io.popen(table.concat(words,' ').." 2>&1; printf '\n__STATUS__%d\n' $?"))
  local text=p:read('*a');p:close()
  local out,code=text:match('^(.*)\n__STATUS__(%d+)\n$')
  assert(code and tonumber(code)==0,table.concat(words,' ')..': '..text)
  return out
end
local tmp=run({'mktemp','-d','/tmp/abc-dynamic-bench.XXXXXX'},true):gsub('%s+$','')
local function assemble(b,n,dynamic,suffix)
  local path=tmp..'/'..b.name..(dynamic and '-dynamic' or '-typed')..suffix
  local f=assert(io.open(path..'.abcasm','wb'))
  assert(f:write(workloads.assembly(b,n,dynamic)));assert(f:close())
  run{abc,'asm',path..'.abcasm','-o',path..'.abc'}
  return path..'.abc'
end
local function fields(text)
  local f={};for word in text:gmatch('%S+') do f[#f+1]=assert(tonumber(word),text) end
  return f
end
local function execution(path,mode,expected)
  local f=fields(run{here..'/runlet',mode,path,trials})
  assert(#f==6 and f[1]==expected,path..' '..mode..': incorrect result')
  return {seconds=f[2],read=f[3],load=f[4],bytes=f[5],first=f[6]}
end
local function baseline(args,expected)
  local f=fields(run(args));assert(#f==2 and f[1]==expected,'baseline result mismatch')
  return f[2]
end
local function main()
  print(('dynamic suite: core=%s trials=%d; no abc-opt, no portable C AOT'):format(core,trials))
  print(run({cc,'--version'},true):match('[^\n]+'))
  print(run({lua,'-v'},true):match('[^\n]+'))
  local modes={'interpreted','compiled','lazy'}
  local checks=0
  -- Small boundary cases catch incorrect loop counts, tag-alternation parity,
  -- and checksum collisions before measuring the larger workloads.
  for _,b in ipairs(workloads.cases) do
    for _,n in ipairs{0,1,2,17,257} do
      local expected=workloads.expected(b,n)
      for _,dynamic in ipairs{false,true} do
        local path=assemble(b,n,dynamic,'-check-'..n)
        for _,mode in ipairs(modes) do
          local out=run{abc,'run',path,'main','--'..mode}
          assert(tonumber(out)==expected,b.name..' '..mode..': '..out)
          checks=checks+1
        end
      end
      baseline({here..'/dynamic-native',b.name,n,3},expected)
      baseline({lua,here..'/dynamic.lua',b.name,n,3},expected)
      baseline({lua,'-joff',here..'/dynamic.lua',b.name,n,3},expected)
      checks=checks+3
    end
  end
  print(('validated %d small-case results'):format(checks))
  local rows={}
  for _,b in ipairs(workloads.cases) do
    local expected=workloads.expected(b,b.n)
    local row={b=b,typed={},dynamic={}}
    local typed=assemble(b,b.n,false,'-timed')
    local dynamic=assemble(b,b.n,true,'-timed')
    for _,mode in ipairs(modes) do
      row.typed[mode]=execution(typed,mode,expected)
      row.dynamic[mode]=execution(dynamic,mode,expected)
    end
    row.native=baseline({here..'/dynamic-native',b.name,b.n,trials},expected)
    row.luaoff=baseline({lua,'-joff',here..'/dynamic.lua',b.name,b.n,trials},expected)
    row.luajit=baseline({lua,here..'/dynamic.lua',b.name,b.n,trials},expected)
    rows[#rows+1]=row
  end
  print('\nmedian ns/iteration: T=typed ABC, D=dynamic ABC; I/E/L=interpreted/eager/lazy')
  print(('%-15s%9s%9s%9s%9s%9s%9s%9s%9s%9s'):format('workload','T-I','D-I','T-E','D-E','T-L','D-L','LJ-off','LuaJIT','C'))
  for _,r in ipairs(rows) do
    local scale=1e9/r.b.n;local t,d=r.typed,r.dynamic
    print(('%-15s%9.3f%9.3f%9.3f%9.3f%9.3f%9.3f%9.3f%9.3f%9.3f'):format(r.b.name,
      t.interpreted.seconds*scale,d.interpreted.seconds*scale,t.compiled.seconds*scale,d.compiled.seconds*scale,
      t.lazy.seconds*scale,d.lazy.seconds*scale,r.luaoff*scale,r.luajit*scale,r.native*scale))
  end
  print('\ndynamic / typed ratio; >1 means dynamic is slower')
  print(('%-15s%12s%12s%12s'):format('workload','interpreted','eager','lazy'))
  for _,r in ipairs(rows) do
    print(('%-15s%12.2f%12.2f%12.2f'):format(r.b.name,
      r.dynamic.interpreted.seconds/r.typed.interpreted.seconds,
      r.dynamic.compiled.seconds/r.typed.compiled.seconds,r.dynamic.lazy.seconds/r.typed.lazy.seconds))
  end
  print('\ndynamic native setup (single VM creation/load) and emitted body bytes; excludes activation stubs')
  print(('%-15s%12s%12s%12s%12s'):format('workload','E load us','L load us','E bytes','L bytes'))
  for _,r in ipairs(rows) do
    print(('%-15s%12.2f%12.2f%12d%12d'):format(r.b.name,
      r.dynamic.compiled.load*1e6,r.dynamic.lazy.load*1e6,r.dynamic.compiled.bytes,r.dynamic.lazy.bytes))
  end
  print('\nLuaJIT and C are algorithm baselines, not emulations of ABC tags/checks/memory traffic. Only paired ABC columns isolate representation costs. No aggregate, allocation-heavy or dynamic-call claim follows from these numeric cases.')
end
local ok,err=xpcall(main,debug.traceback)
run({'rm','-rf',tmp},true)
if not ok then error(err,0) end
