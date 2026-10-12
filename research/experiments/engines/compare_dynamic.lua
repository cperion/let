#!/usr/bin/env luajit
-- Alternate before/after processes on identical verified ABC, including typed
-- controls. Each sample is runlet's median of three executions after warmup.
local here=arg[0]:match('^(.*)/') or '.'
package.path=here..'/?.lua;'..package.path
local workloads=require('dynamic_workloads')
local before=assert(arg[1],'usage: compare_dynamic.lua BEFORE_RUNLET [AFTER_RUNLET]')
local after=arg[2] or here..'/runlet'
local pairs=tonumber(os.getenv('PAIRS') or '9')
assert(pairs>=3 and pairs%2==1,'PAIRS must be odd and >=3')
local sf=assert(io.open('/proc/self/status'));local core=assert(sf:read('*a'):match('Cpus_allowed_list:%s*(%d+)'));sf:close()
local function run(args)
  local words={} for i,v in ipairs(args) do words[i]=string.format('%q',tostring(v)) end
  local p=assert(io.popen(table.concat(words,' ').." 2>&1; printf '\n__STATUS__%d\n' $?"))
  local text=p:read('*a');p:close();local out,status=text:match('^(.*)\n__STATUS__(%d+)\n$')
  assert(status=='0',text);return out
end
local tmp=run{'mktemp','-d','/tmp/abc-scalar-pairs.XXXXXX'}:gsub('%s+$','')
local function median(values)table.sort(values);return values[(#values+1)/2] end
local function sample(exe,mode,path,expected)
  local fields={} for value in run{'taskset','-c',core,exe,mode,path,3}:gmatch('%S+') do fields[#fields+1]=assert(tonumber(value)) end
  assert(#fields==6 and fields[1]==expected,'result mismatch');return fields[2],fields[5]
end
local function main()
  print(('core=%s pairs=%d samples=3; alternating process order; ns/iteration'):format(core,pairs))
  print('workload form mode before after median_after/before before_bytes after_bytes')
  for _,b in ipairs(workloads.cases) do for _,dynamic in ipairs{false,true} do
    local stem=tmp..'/'..b.name..(dynamic and '-dynamic' or '-typed')
    local f=assert(io.open(stem..'.abcasm','wb'));assert(f:write(workloads.assembly(b,b.n,dynamic)));assert(f:close())
    run{here..'/../../../build/abc','asm',stem..'.abcasm','-o',stem..'.abc'}
    for mode in (os.getenv('MODES') or 'interpreted compiled lazy'):gmatch('%S+') do
      local old,new,ratios={},{},{};local ob,nb
      for i=1,pairs do
        local a,z
        if i%2==1 then a,ob=sample(before,mode,stem..'.abc',workloads.expected(b,b.n));z,nb=sample(after,mode,stem..'.abc',workloads.expected(b,b.n))
        else z,nb=sample(after,mode,stem..'.abc',workloads.expected(b,b.n));a,ob=sample(before,mode,stem..'.abc',workloads.expected(b,b.n)) end
        old[i],new[i],ratios[i]=a*1e9/b.n,z*1e9/b.n,z/a
      end
      print(('%s %s %s %.3f %.3f %.3f %d %d'):format(b.name,dynamic and 'dynamic' or 'typed',mode,median(old),median(new),median(ratios),ob,nb))
    end
  end end
end
local ok,err=xpcall(main,debug.traceback);run{'rm','-rf',tmp};if not ok then error(err,0) end
