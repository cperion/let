package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local S=require('let.schema')
local D=require('let.diag')
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
for _,name in ipairs{'U8','U16','U32','U64','I32','I64','F64','Bool','Unit','Any','String'} do
 local profile=name=='Any' and 'let' or 'slet'
 local unit=C.typed{profile=profile,source='let identity(x: '..name..'): '..name..' = x let main(): U32 = 42'}
 check(unit.functions[1].inputs[1].type==S[name],'canonical builtin '..name)
 local old=name:lower()
 local ok,err=pcall(C.typed,{profile=profile,source='let identity(x: '..old..'): U32 = 42 let main(): U32 = 42'})
 check(not ok and D.is(err) and err.code=='type-required','no lowercase builtin alias '..old)
end
check(S.Type==S.Ty.Type and not S.runtime(S.Type),'metatype descriptor renamed without adding runtime admission')
check(S.List==S.ASDL.List,'schema list constructor remains the canonical class')
for _,name in ipairs{'Ref','Ptr','Array','Slice'} do
 local spelling=name=='Array' and 'Array(U32, 2)' or name..'(U32)'
 local unit=C.typed{profile='slet',source='let identity(x: '..spelling..'): '..spelling..' = x let main(): U32 = 42'}
 check(unit.functions[1].inputs[1].type.kind==name,'canonical type constructor '..name)
 local ok,err=pcall(C.typed,{profile='slet',source='let identity(x: '..spelling:gsub(name,name:lower())..'): U32 = 42 let main(): U32 = 42'})
 check(not ok and D.is(err) and err.code=='type-required','no lowercase type constructor alias '..name)
end
local source=[[
let Point = { x: U32 }
let main(): U32 = do
 let p = Point { x = 40 }
 let r: Ref(Point) = Ref(p)
 r.x += 2
 let q: Ptr(Point) = Ptr(p)
 let xs: Array(U32, 2) = [q[0].x, 9]
 let view: Slice(U32) = Slice(xs)
 return U32(view[0])
end
]]
local artifact=C.compile{profile='slet',source=source,name='type-names.slet'}
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimize in ipairs{false,true} do
 local result=C.stage(artifact.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
 executions=executions+1;check(tonumber(result.cells[1])==42,'constructor value forms '..mode..'/'..tostring(optimize))
end end
for _,call in ipairs{'ref(p)','ptr(p)','slice(xs)'} do
 local ok,err=pcall(C.typed,{profile='slet',source='let Point = { x: U32 } let main(): U32 = do let p = Point { x = 42 } let xs = [42] let unused = '..call..' return 42 end'})
 check(not ok and D.is(err) and err.code=='unknown-name','no lowercase value constructor alias '..call)
end
-- User names still resolve by binding, not by their first letter. This deliberately
-- unconventional spelling verifies that the rename introduced no case grammar.
local unit=C.typed{profile='slet',source='let lowercase = { x: U32 } let main(): U32 = do let Uppercase = lowercase { x = 42 } return Uppercase.x end'}
check(unit.phase=='typed-ir','capitalization does not classify user bindings')
print(('type names: %d checks, %d VM executions'):format(checks,executions))
