-- Run in its own process with ABC_OPT_LIBRARY pointing at a nonexistent file.
local source=debug.getinfo(1,'S').source:sub(2)
local root=(source:match('^(.*[/\\])') or './')..'../'
package.path=root..'?.lua;'..root..'?/init.lua;'..root..'../build/?.lua;'..package.path
assert(not package.loaded['let.optimize'])
package.preload['let.optimize']=function() error('staging attempted to load optimizer',0) end
local Compiler=require('let.compiler')
local S=require('let.schema')
local D=require('let.diag')
local Util=require('tool_util')
local I,L=S.Ir,S.ASDL.List
local value=I.Value(1)
local fn=I.Fn('calc',I.Entry,0,L{S.inValue(S.U32)},L{S.U32},L{I.ValueParam(0,value,S.U32)},
    L{I.Return(L{I.Bin(I.Mul,I.Ref(value,S.U32),I.Const(S.U32,I.UInt(2)),S.U32)})})
local trap=I.Trap(I.Const(S.Bool,I.Boolean(true)),'index-range')
trap.span={file='no-optimizer.slet',line=7}
local fail=I.Fn('fail',I.Entry,0,L{},L{S.U32},L{},L{trap,I.Return(L{I.Const(S.U32,I.UInt(0))})})
-- Fail immediately if the removed process/file execution path is touched.
local function forbidden() error('staging attempted subprocess/file execution',0) end
Util.capture,Util.publish,os.execute,io.popen=forbidden,forbidden,forbidden,forbidden
for _,mode in ipairs{'interpreted','eager','lazy','threaded'} do
    local result=Compiler.stage({fn},{profile='slet',entry='calc',arguments={21},mode=mode,optimize=false})
    assert(result.cells[1]==42,'unoptimized VM arithmetic failed')
    local ok,diagnostic=pcall(Compiler.stage,{fail},{profile='slet',entry='fail',mode=mode,optimize=false})
    assert(not ok and D.is(diagnostic) and diagnostic.code=='static-index-range' and diagnostic.span==trap.span,
        'unoptimized VM error provenance failed: '..tostring(diagnostic))
end
assert(not package.loaded['let.optimize'],'optimizer was loaded')
print('PASS: unoptimized staging uses only the in-process VM in all four modes')
