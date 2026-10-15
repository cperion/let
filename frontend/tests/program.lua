package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local Check=require('let.check')
local Program=require('let.program')
local Access=require('let.access')
local Layout=require('let.layout')
local ABC=require('let.abc')
local Stage=require('let.stage')
local S=require('let.schema')
local D=require('let.diag')
local I,L=S.Ir,S.List
local checks=0
local function check(ok,why) checks=checks+1;assert(ok,why) end
local function rejects(code,run)
 local ok,err=pcall(run);check(not ok and D.is(err) and err.code==code,code..': '..tostring(err));return err
end
local source=[[
let Point = { x: U32 }
let read(p: Ref(Point)): U32 = p.x
let main(): U32 = do let p = Point { x = 42 } return read(Ref(p)) end
]]
local unit=C.typed{profile='slet',source=source}
local program=unit.program
check(program.phase=='checked-program','typed source owns its checked graph')
check(program.access.read and program.ownership.read,'program owns both analyses')
for _,fn in ipairs(unit.functions) do
 check(fn.access==nil and fn.ownership==nil,'shared IR has no mutable analysis annotations')
end
check(unit.functions.accessStats==nil and program.accessStats~=nil,'statistics belong to the analyzed graph')
-- Checking and emitting an existing program cannot silently invoke inference.
local analyze=Access.analyze
Access.analyze=function() error('unexpected repeated access analysis') end
Check.program(program.functions,program.modules,program.foreigns)
local artifact=ABC.lower(program,{profile='slet',exports={'main'}})
local again=ABC.lower(program,{profile='slet',exports={'main'}})
Access.analyze=analyze
check(artifact.program==program and artifact.layout.program==program,'emission uses the exact program contract')
check(again.assembly==artifact.assembly,'reusing a checked program has stable emission')
local result=Stage.execute(artifact,program.functions,{entry='main',mode='interpreted',optimize=false})
check(tonumber(result.cells[1])==42,'admitted borrowed program still executes')
local calls=0
Access.analyze=function(functions) calls=calls+1;return analyze(functions) end
local compiled=C.compile{profile='slet',source=source}
Access.analyze=analyze
check(calls==1,'source compile analyzes its completed graph once, not again in lowering')
check(compiled.program==compiled.sourceUnit.program,'compile carries the semantic program into emission')

-- Valid owning source is analyzable; no executable path may borrow its storage
-- merely because the runtime binding is missing.
local escaping=[[
let Point = { x: U32 }
let make(): Ref(Point) = do let p = Point { x = 42 } return Ref(p) end
let main(): U32 = 0
]]
for _,profile in ipairs{'slet','let'} do
 local owned=C.typed{profile=profile,source=escaping}
 check(#owned.program.ownership.make.summary.counted>0,'typing preserves the counted requirement')
 local err=rejects('borrow-return',function() Layout.program(owned.program) end)
 check(err.ownership==owned.program.ownership.make.summary,'admission reports the already-solved evidence')
 rejects('borrow-return',function() ABC.lower(owned.program,{profile=profile}) end)
 rejects('borrow-return',function() C.lower(owned.functions,{profile=profile}) end)
 rejects('borrow-return',function() C.compile{profile=profile,source=escaping} end)
end
rejects('layout-contract',function() Layout.scalar:cellKind(S.Ref(S.U32)) end)
rejects('layout-contract',function() Layout.scalar:layout(S.Slice(S.U32)) end)
rejects('layout-contract',function() Layout.scalar:abiComponents(S.View(S.Sig({},{}))) end)
check(artifact.layout:cellKind(S.Ref(S.U32))=='a','admitted reference selects an address cell')
check(#artifact.layout:abiComponents(S.Slice(S.U32))==2,'admitted slice has the borrowed ABI')
check(Layout.scalar:layout(S.Record{x=S.U32,y=S.U32}).size==8,'pointer-free layout needs no lifetime contract')

-- A transformation creates a new graph. Neither shared Fn nodes nor the input
-- vectors become caches that can overwrite a previously analyzed program.
local base=I.Fn('value',I.Entry,0,L{},L{S.U32},L{},L{I.Return(L{I.Const(S.U32,I.UInt(42))})})
local functions={base}
local first=Program.analyze(functions)
local oldAccess,oldOwnership,oldStats=first.access,first.ownership,first.accessStats
local slot=I.Storage(1)
local changed=I.Fn('value',I.Entry,0,L{},L{S.Ref(S.U32)},L{},L{
 I.Var(slot,S.U32,I.Const(S.U32,I.UInt(42))),
 I.Return(L{I.Addr(I.Local(slot),S.Ref(S.U32),S.Borrow.WriteAccess)})})
functions[1]=changed
check(Check.program(functions),'structural checking does not reject missing runtime placement')
check(changed.access==nil and changed.ownership==nil,'structural checking publishes no proofs')
local second=Program.analyze(functions)
check(first.functions[1]==base and second.functions[1]==changed,'each program owns its function vector')
check(first.access==oldAccess and first.ownership==oldOwnership and first.accessStats==oldStats,'later analysis does not mutate prior results')
check(#first.ownership.value.summary.counted==0 and #second.ownership.value.summary.counted>0,'changed graph has its own ownership decision')
check(second.access~=first.access and second.ownership~=first.ownership,'analysis results are not shared through function identities')
rejects('borrow-return',function() Layout.program(second) end)
local third=Program.analyze({base})
check(third.access.value~=first.access.value and base.access==nil,'even reused function nodes have program-local access results')
local root=I.ModuleRoot('snapshot',S.U32,false)
local data=I.ModuleData(root,string.char(42,0,0,0))
local modules={data};local foreign=I.Foreign('external',L{},L{S.U32});local foreigns={foreign}
local declared=Program.analyze({base},modules,foreigns)
modules[1]=nil;foreigns[1]=nil
check(declared.modules[1]==data and declared.foreigns[1]==foreign,'module and foreign declaration vectors are captured with the graph')
print(('program boundary: %d checks, 1 VM execution'):format(checks))
