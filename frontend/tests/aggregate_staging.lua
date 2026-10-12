package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local S=require('let.schema')
local D=require('let.diag')
local IR=require('let.ir')
local Stage=require('let.stage')
local Snapshot=require('let.snapshot')
local I,L=S.Ir,S.List
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function run(source,wanted)
 for _,staticMode in ipairs{'interpreted','threaded','eager','lazy'} do
  local unit=C.typed({profile='slet',source=source,name='aggregate-staging.slet'},{staticMode=staticMode})
  for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
   for _,optimize in ipairs{false,true} do
    local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
    executions=executions+1;check(tonumber(result.cells[1])==wanted,staticMode..'/'..mode..'/'..tostring(optimize)..': '..tostring(result.cells[1]))
   end
  end
 end
end
run([[
let Context = { amount: U32 }
let make(): Context = Context { amount = 40 }
let ctx... = make()
let bump(): Unit = do amount += 1 return end
let main(): U32 = do let ignored = 0; (bump)(); (bump)(); return amount end
]],42)
run([[
let Context = { amount: U32 }
let state = Context { amount = 40 }
let copied(): U32 = do let ctx = state let ctx... amount += 2 return state.amount end
let main(): U32 = (copied)()
]],42)
run([[
let state = [40, 1]
let main(): U32 = do state[0] += state[1] + 1 return state[0] end
]],42)
run([[
let Context = { amount: U32 }
let state = Context { amount = 39 }
let make(): Context = do state.amount += 1 return Context { amount = state.amount + 2 } end
let other... = make()
let main(): U32 = amount + state.amount
]],82)
run([[
let Context = { amount: U32 }
let state = Context { amount = 40 }
let main(): U32 = do let first = state let second = first second.amount += 2 return state.amount end
]],42)
run([[
let Point = { x: U32 }
let original = Point { x = 40 }
let alias = (original)
let second = alias
let main(): U32 = do second.x = 42 return original.x end
]],42)
run([[
let original = [40, 1]
let alias = original
let main(): U32 = do alias[0] = 42 return original[0] end
]],42)
-- Explicit field reads and returns still copy; equal bytes do not imply aliases.
run([[
let Point = { x: U32 }
let Context = { child: Point }
let ctx... = Context { child = Point { x = 40 } }
let saved = child
let returned(): Point = ctx.child
let copy = (returned)()
let main(): U32 = do saved.x = 1 copy.x = 2 return ctx.child.x + 2 end
]],42)
local aliases=C.typed({profile='slet',source=[[
let Point = { x: U32 }
let original = Point { x = 40 }
let alias = original
let main(): U32 = do alias.x = 42 return original.x end
]]},{staticMode='interpreted'})
check(#aliases.functions.moduleData==1,'top-level aliases retain one module root')
local accesses=0
require('let.walk').walk(aliases.functions[1],{enter=function(node)
 if node.kind=='Global' and node.root then
  accesses=accesses+1;check(node.root==aliases.functions.moduleData[1].root,'both names reach the same root, not equal bytes')
 end
end})
check(accesses==2,'alias write and original read retain the one root')
local localAlias=C.typed({profile='slet',source=[[
let Point = { x: U32 }
let original = Point { x = 40 }
let main(): U32 = do let alias = original alias.x = 42 return original.x end
]]},{staticMode='interpreted'})
local wholeReads=0
require('let.walk').walk(localAlias.functions[1],{enter=function(node)
 if node.kind=='Read' and node.type:isRecord() then wholeReads=wholeReads+1 end
end})
check(wholeReads==0,'an instance alias emits no eager aggregate read')
run('let Point = { x: U32 } let unused = Point { x = 42 } let main(): U32 = 42',42)
run('let Items = Array(Unit, 1) let empty(): Unit = do return end let state: Items = [empty()] let main(): U32 = do let ignored = state[0] return 42 end',42)
-- Repeated typing owns fresh initializer state, even for a reused parsed AST.
local repeated=C.source{profile='slet',source=[[
let Counter = { calls: U32 }
let Context = { amount: U32 }
let counter = Counter { calls = 0 }
let make(): Context = do counter.calls += 1 return Context { amount = 41 } end
let initialized = make()
let main(): U32 = initialized.amount + counter.calls
]]}
for _=1,2 do
 local unit=C.typed(repeated,{staticMode='interpreted'})
 local result=C.stage(unit.functions,{profile='slet',mode='interpreted',entry='main'})
 executions=executions+1;check(tonumber(result.cells[1])==42,'fresh compilation initializer state')
end
local function fromHex(hex) return (hex:gsub('..',function(byte) return string.char(tonumber(byte,16)) end)) end
local function roundtrip(ty,body,image)
 local make=I.Fn('make',I.Entry,0,L{},L{ty},L{},L(body))
 local b=IR.builder();local input=b:valueId()
 local identity=I.Fn('identity',I.Entry,0,L{S.inValue(ty)},L{ty},L{I.ValueParam(0,input,ty)},L{I.Return(L{b:ref(input,ty)})})
 local snapshot
 for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimize in ipairs{false,true} do
  local result=C.stage({make},{profile='slet',mode=mode,optimize=optimize,entry='make'})
  executions=executions+1;snapshot=result.values[1]
  check(snapshot.type==ty and snapshot.image==image,'exact output image '..mode..'/'..tostring(optimize))
  local passed=C.stage({identity},{profile='slet',mode=mode,optimize=optimize,entry='identity',arguments={snapshot}})
  executions=executions+1;check(passed.values[1].image==image,'typed aggregate argument roundtrip '..mode)
  local specialized=C.specialize({identity},{entry='identity',name='fixed',known={snapshot},profile='slet'})
  local fixed=C.stage(specialized.functions,{profile='slet',mode=mode,optimize=optimize,entry='fixed'})
  executions=executions+1;check(fixed.values[1].image==image,'durable known-value specialization '..mode)
 end end
 return snapshot
end
local b=IR.builder()
local Mixed=S.Record{a=S.Bool,b=S.U8,c=S.U16,d=S.I32,e=S.U64,f=S.F64,z=S.Unit}
local fields={b:bool(true),b:int(S.U8,255),b:int(S.U16,0x1234),b:un('Neg',b:int(S.I32,2),S.I32),
 b:int64(S.U64,0x01234567,0x89abcdef),b:const(S.F64,I.FloatBits(0x80000000,0)),b:const(S.Unit,I.UInt(0))}
local mixed=roundtrip(Mixed,{I.Return(L{b:make(Mixed,fields)})},fromHex('01ff3412feffffffefcdab89674523010000000000000080'))
local Array=S.Array(S.F64,2)
local floats=roundtrip(Array,{I.Return(L{b:make(Array,{b:const(S.F64,I.FloatBits(0x80000000,0)),b:const(S.F64,I.FloatBits(0x7ff81234,0x56789abc))})})},
 fromHex('0000000000000080bc9a78563412f87f'))
-- Tagged values use the existing integer-cell ABI. Transport is bit copying,
-- including floating payloads; this does not implement packed float arithmetic.
local Option=S.Sum{none=S.Unit,some=S.U64}
local variant=b:valueId()
roundtrip(Option,{I.ConstructVariant(variant,Option,'some',b:int64(S.U64,0x01234567,0x89abcdef)),I.Return(L{b:ref(variant,Option)})},
 fromHex('0100000000000000efcdab8967452301'))
local FloatOption=S.Sum{none=S.Unit,some=S.F64}
local floatImage=fromHex('0100000000000000bc9a78563412f87f')
roundtrip(FloatOption,{I.Return(L{b:const(FloatOption,I.Bytes(floatImage))})},floatImage)
-- Policy, unsupported-pointer and failed-publication contracts remain explicit.
local function rejected(code,fn)
 local ok,err=pcall(fn);check(not ok and D.is(err) and err.code==code,code..': '..tostring(err))
end
rejected('execution-policy',function() C.typed{profile='slet',source='let Point = { x: U32 } let state = Point { x = 42 } let main(): U32 = state.x'} end)
rejected('static-cycle',function() C.typed({profile='slet',source='let Point = { x: U32 } let a = make() let make(): Point = a let main(): U32 = a.x'},{staticMode='interpreted'}) end)
rejected('static-transport',function() Snapshot.contract(S.Record{access=S.Ref(S.U32)}) end)
rejected('static-argument',function() Snapshot.cells{type=Mixed,image=''} end)
rejected('static-argument',function() C.stage({I.Fn('main',I.Entry,0,L{S.inValue(Mixed)},L{Mixed},L{I.ValueParam(0,I.Value(1),Mixed)},L{I.Return(L{I.Ref(I.Value(1),Mixed)})})},
 {profile='slet',entry='main',mode='interpreted',arguments={floats}}) end)
local failedSource=[[
let Point = { x: U32 }
let state = Point { x = 40 }
let bad(n: U32): Point = do state.x = 99 return Point { x = 1 / n } end
let other = bad(0)
let main(): U32 = state.x
]]
rejected('static-division-zero',function() C.typed({profile='slet',source=failedSource},{staticMode='interpreted'}) end)
local unitBounds=C.typed({profile='slet',source='let Items = Array(Unit, 1) let empty(): Unit = do return end let state: Items = [empty()] let main(): U32 = do let ignored = state[1] return 42 end'},{staticMode='interpreted'})
rejected('static-index-range',function() C.stage(unitBounds.functions,{profile='slet',mode='interpreted',entry='main'}) end)
-- Imported code shares one private root; reopening aliases does not duplicate it.
local directory=os.tmpname();os.remove(directory);assert(os.execute('mkdir -p '..directory)==0)
local function file(name,text) local f=assert(io.open(directory..'/'..name..'.slet','wb'));assert(f:write(text));assert(f:close()) end
file('state',[[
let Point = { x: U32 }
let data = Point { x = 40 }
let bump(): U32 = do data.x += 1 return data.x end
return { functions = { bump } }
]])
file('main',[[use state; let main(): U32 = do let ignored = state.bump() return state.bump() end]])
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
 local unit=C.typedFile(directory..'/main.slet',{staticMode=mode})
 local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode})
 executions=executions+1;check(tonumber(result.cells[1])==42,'imported persistent root '..mode)
 check(#unit.functions.moduleData==1,'import graph has one private root')
end
os.remove(directory..'/main.slet');os.remove(directory..'/state.slet');assert(os.execute('rmdir '..directory)==0)
print(('aggregate staging: %d checks, %d VM executions'):format(checks,executions))
