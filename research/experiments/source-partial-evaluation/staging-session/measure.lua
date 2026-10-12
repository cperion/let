-- Bridge overhead only: identical pre-lowered scalar program, optimization off.
-- stage-before.lua is the exact baseline bridge, retained solely for comparison.
local source=debug.getinfo(1,'S').source:sub(2)
local here=source:match('^(.*[/\\])') or './'
local root=here..'../../../../'
package.path=root..'frontend/?.lua;'..root..'frontend/?/init.lua;'..root..'build/?.lua;'..package.path
local Compiler=require('let.compiler')
local Stage=require('let.stage')
local Before=assert(loadfile(here..'stage-before.lua'))()
local S=require('let.schema')
local ffi=require('ffi')
ffi.cdef[[struct stage_bench_time { long seconds, nanoseconds; };
int clock_gettime(int, struct stage_bench_time *);]]
local t=ffi.new('struct stage_bench_time[1]')
local function now()
    assert(ffi.C.clock_gettime(4,t)==0)
    return tonumber(t[0].seconds)+tonumber(t[0].nanoseconds)*1e-9
end
local I,L=S.Ir,S.ASDL.List
local value=I.Value(1)
local fn=I.Fn('calc',I.Entry,0,L{S.inValue(S.u32)},L{S.u32},L{I.ValueParam(0,value,S.u32)},
    L{I.Return(L{I.Bin(I.Mul,I.Ref(value,S.u32),I.Const(S.u32,I.UInt(2)),S.u32)})})
local artifact=Compiler.lower({fn},{profile='slet',exports={'calc'}})
local names={'subprocess','in-process-one-shot','prepared-session'}
print('mode,bridge,phase,round,calls,seconds')
for _,mode in ipairs{'interpreted','eager','lazy'} do
    local options={mode=mode,optimize=false,entry='calc',arguments={21}}
    local started=now()
    local session=Stage.open{mode=mode,optimize=false}
    local program=session:prepare(artifact,{fn})
    print(('%s,prepared-session,prepare,0,0,%.9f'):format(mode,now()-started))
    started=now(); assert(program:call{entry='calc',arguments={21}}.cells[1]==42)
    print(('%s,prepared-session,first,0,1,%.9f'):format(mode,now()-started))
    local run={
        function() return Before.execute(artifact,{fn},options) end,
        function() return Stage.execute(artifact,{fn},options) end,
        function() return program:call{entry='calc',arguments={21}} end,
    }
    for _,call in ipairs(run) do assert(call().cells[1]==42) end
    for round=1,7 do
        for offset=0,2 do
            local index=(round+offset-1)%3+1
            collectgarbage('collect')
            started=now()
            for _=1,5 do assert(run[index]().cells[1]==42) end
            print(('%s,%s,warm,%d,5,%.9f'):format(mode,names[index],round,now()-started))
        end
    end
    session:close()
end
