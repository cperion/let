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
check(artifact.program==program and artifact.layout.program.source==program,'physical emission retains the exact checked source contract')
check(again.assembly==artifact.assembly,'reusing a checked program has stable emission')
local result=Stage.execute(artifact,program.functions,{entry='main',mode='interpreted',optimize=false})
check(tonumber(result.cells[1])==42,'admitted borrowed program still executes')
local calls=0
Access.analyze=function(functions) calls=calls+1;return analyze(functions) end
local compiled=C.compile{profile='slet',source=source}
Access.analyze=analyze
check(calls==1,'source compile analyzes its completed graph once, not again in lowering')
check(compiled.program==compiled.sourceUnit.program,'compile carries the semantic program into emission')

-- End-to-end acceptance for the source-to-physical boundary, intentionally
-- unsatisfied during removal: no repeated inference; public/staging gates remain.
local escaping=[[
let Point = { x: U32 }
let make(): Rc(Point) = Rc(Point { x = 42 })
let main(): U32 = 0
]]
for _,profile in ipairs{'slet','let'} do
 local owned=C.typed{profile=profile,source=escaping}
 check(owned.program.functions[1].results[1]:isRc(),'the declared result, not a counted requirement, owns storage')
 if profile=='slet' then
  Access.analyze=function() error('materialization repeated source analysis') end
  local emitted=ABC.lower(owned.program,{profile=profile,exports={'main'}})
  Access.analyze=analyze
  check(emitted.materialized.source==owned.program and emitted.functions==owned.program.functions,'physical graph retains its exact checked source')
  check(C.lower(owned.functions,{profile=profile,exports={'main'}}).materialized~=nil,'raw lowering explicitly analyzes then materializes')
  rejects('Rc-interface',function() C.compile{profile=profile,source=escaping,exports={'make'}} end)
  check(not emitted.assembly:find('.extern',1,true) and not emitted.assembly:find('.function make ',1,true),'unrequested owning templates emit neither code nor lifetime foreign declarations')
  local pure=Stage.execute(emitted,owned.functions,{entry='main',mode='interpreted',optimize=false})
  check(tonumber(pure.cells[1])==0,'an unused owning template does not turn pure requested code into foreign execution')
 else
  rejects('dynamic-lowering',function() ABC.lower(owned.program,{profile=profile}) end)
  rejects('dynamic-lowering',function() C.lower(owned.functions,{profile=profile}) end)
  rejects('dynamic-lowering',function() C.compile{profile=profile,source=escaping} end)
 end
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
local ownedValue=I.Value(1)
local changed=I.Fn('value',I.Entry,0,L{},L{S.Rc(S.U32)},L{},L{
 I.RcNew(ownedValue,slot,S.Rc(S.U32),I.Const(S.U32,I.UInt(42))),
 I.Return(L{I.Ref(ownedValue,S.Rc(S.U32))})})
functions[1]=changed
check(Check.program(functions),'structural checking does not choose physical placement')
check(changed.access==nil and changed.ownership==nil,'structural checking publishes no proofs')
local second=Program.analyze(functions)
check(first.functions[1]==base and second.functions[1]==changed,'each program owns its function vector')
check(first.access==oldAccess and first.ownership==oldOwnership and first.accessStats==oldStats,'later analysis does not mutate prior results')
check(first.functions[1].results[1]==S.U32 and second.functions[1].results[1]==S.Rc(S.U32),'ownership comes from the changed declared type')
check(second.access~=first.access and second.ownership~=first.ownership,'analysis results are not shared through function identities')
rejects('Rc-interface',function() ABC.lower(second,{profile='slet',exports={'value'}}) end)
rejects('borrow-escape',function() C.typed{profile='slet',source='let bad(): Ref(U32) = do let p = [42] return Ref(p[0]) end let main(): U32 = 0'} end)
local third=Program.analyze({base})
check(third.access.value~=first.access.value and base.access==nil,'even reused function nodes have program-local access results')
local root=I.ModuleRoot('snapshot',S.U32,false)
local data=I.ModuleData(root,string.char(42,0,0,0))
local modules={data};local foreign=I.Foreign('external',L{},L{S.U32});local foreigns={foreign}
local declared=Program.analyze({base},modules,foreigns)
modules[1]=nil;foreigns[1]=nil
check(declared.modules[1]==data and declared.foreigns[1]==foreign,'module and foreign declaration vectors are captured with the graph')
local foreignValue=I.Value(1)
local foreignCaller=I.Fn('foreign_main',I.Entry,0,L{},L{S.U32},L{},L{
 I.Call(L{foreignValue},foreign.target,L{}),I.Return(L{I.Ref(foreignValue,S.U32)})})
local foreignProgram=Program.analyze({foreignCaller},nil,{foreign})
local foreignArtifact=ABC.lower(foreignProgram,{profile='slet',exports={'foreign_main'}})
rejects('static-foreign',function() Stage.execute(foreignArtifact,{foreignCaller},{entry='foreign_main',mode='interpreted'}) end)
print(('program boundary: %d checks, 2 VM executions'):format(checks))
