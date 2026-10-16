-- Removal-checkpoint probe, run from frontend. The first argument is an
-- immutable pre-removal placement.lua extracted from revision 80a4bfc8.
-- It is used only as a drop-generation oracle, never as a production fallback.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local D=require('let.diag')
local Layout=require('let.layout')
local Placement=require('let.placement')
local function read(path)
 local f=assert(io.open(path,'rb'));local text=f:read('*a');f:close();return text
end
assert(Placement.program==nil,'retired program materializer remains reachable')
local source=read('tests/source_owners.lua')
local boundary=assert(source:find('local exports=',1,true))
source=assert(loadstring(source:sub(1,boundary-1)..'\nreturn source'))()
local unit=C.typed({profile='slet',source=source},{staticMode='interpreted',staticOptimize=false})
local function rejected(run,code)
 local ok,err=pcall(run)
 assert(not ok and D.is(err) and err.code==code,tostring(err))
 print('expected rejection: '..tostring(err))
end
rejected(function() require('let.abc').lower(unit.program,{profile='slet',exports={'main'}}) end,'ownership-materialization')
-- Raw-IR entry must also analyze then reject, not fall back to borrowed emission.
rejected(function() C.lower(unit.functions,{profile='slet',exports={'main'}}) end,'ownership-materialization')
rejected(function() C.compile{profile='slet',source=[[
let Point={x: U32}
let Choice=oneof {point: Ref(Point)}
let main(): U32 = do
 let p=Point {x=42}
 let v=Choice.point(Ref(p))
 return v {point(p)=p.x}
end
]],exports={'main'}} end,'abc-lowering')
local before=read(assert(arg[1],'pre-removal oracle path required'))
local n
before,n=before:gsub('local M={}','local M={captures={}}',1);assert(n==1)
before,n=before:gsub(' local function sameContract',[[
 local originalDrop=drop
 drop=function(d,header)
  local name=originalDrop(d,header)
  M.captures[#M.captures+1]={descriptor=d,header=header,name=name}
  return name
 end
 local function sameContract]],1);assert(n==1)
local old=assert(loadstring(before,'@pre-removal-placement.lua'))()
local historical=old.program(unit.program,{exports={'main'}})
local program={phase='physical-program',lifecycle={}}
local serial=0
local drops=Placement.drops(program,Layout.physical(program),function(prefix)
 serial=serial+1;return prefix..serial
end)
local compared=0
for _,item in ipairs(old.captures) do
 local d={type=item.descriptor.type,paths=item.descriptor.paths}
 local name=drops(d,item.header)
 if item.name then
  local a,b=historical.lifecycle[item.name],program.lifecycle[assert(name)]
  assert(#a==#b)
  -- The declaration name is allocated by the surrounding program; the entire
  -- executable body and local labels must remain byte-for-byte identical.
  for i=2,#a do assert(a[i]==b[i],item.name..' line '..i) end
  compared=compared+1
 else assert(name==nil,'empty holding set manufactured a cleanup entry') end
end
print(('retained drop generator: %d descriptor uses match pre-removal bodies; %d concrete callbacks'):format(compared,serial))
local borrowed=C.compile{profile='slet',source=[[
let Point={x: U32}
let read_only(p: Ref(Point)): U32 = p.x
let main(): U32 = do let p=Point {x=42} return read_only(Ref(p)) end
]],exports={'main'}}
assert(not borrowed.assembly:find('__let_rt_source_',1,true))
assert(not borrowed.assembly:find('.centry',1,true))
assert(borrowed.layout.owning==nil and borrowed.layout.materialize==nil)
local result=require('let.stage').execute(borrowed,borrowed.functions,{entry='main',mode='interpreted',optimize=false})
assert(tonumber(result.cells[1])==42)
print('ordinary borrowed source: 42, no lifetime imports or lifecycle entries')
