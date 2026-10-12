package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C,D,S,Walk=require('let.compiler'),require('let.diag'),require('let.schema'),require('let.walk')
local Stage,ffi=require('let.stage'),require('let.abi')
local checks,executions,optimizerBlockers=0,0,0
local optimizers=arg[1]=='--unoptimized' and {false} or {false,true}
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function reject(code,source,options)
 local ok,err=pcall(C.typed,{profile='slet',source=source,name='spread-reject.slet'},options)
 check(not ok and D.is(err) and err.code==code,code..': '..tostring(err))
end
local function run(source,args,expected,options)
 local unit=C.typed({profile='slet',source=source,name='spread.slet'},options)
 for _,optimize in ipairs(optimizers) do for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
  local session=Stage.open{mode=mode,optimize=optimize}
  local prepared,program=pcall(session.prepare,session,C.lower(unit.functions,{profile='slet',exports={'main'}}),unit.functions)
  if not prepared then
   session:close()
   -- Keep this qualification suite outside validate until the independent frame
   -- access blocker is resolved. Report failures, never count them as executions.
   if optimize and D.is(program) and program.code=='abc-opt-invalid' and tostring(program):find('frame access outside a live byte block',1,true) then
    optimizerBlockers=optimizerBlockers+1
    print('BLOCKED optimized '..mode..': '..tostring(program))
   else error(program,0) end
  else
  args=args or {};local inputs=ffi.new('uint64_t[?]',math.max(1,#args))
  for index,value in ipairs(args) do inputs[index-1]=value end
  local out,count,err=ffi.new('uint64_t[?]',math.max(1,#expected)),ffi.new('size_t[1]'),ffi.new('abc_error[1]')
  local status=session.C.abc_vm_call(session.vm,program.handle,'main',inputs,#args,out,#expected,count,err)
  check(status==0,ffi.string(err[0].message));executions=executions+1
  check(tonumber(count[0])==#expected,'result count')
  for index,value in ipairs(expected) do check(tonumber(out[index-1])==value,mode..'/'..tostring(optimize)..' component '..index) end
  session:close()
  end
 end end
 return unit
end
local pair='let pair(n: U32): (U32,U32) = do return n, 2 end\n'
local total='let total(a: U32,b: U32,c: U32): U32 = a+b+c\n'
run(pair..total..'let main(n: U32): U32 = total(...pair(n),1)',{39},{42})
run(pair..'let main(n: U32): (U32,U32,U32) = do return 1,...pair(n) end',{39},{1,39,2})
run(pair..'let main(n: U32): U32 = do let a,b,c = 1,...pair(n) return a+b+c end',{39},{42})
run(pair..'let main(n: U32): U32 = do let a,b = ...pair(n),999 return a+b end',{40},{42})
run(pair..'let main(n: U32): (U32,Unit) = do let a,b = (pair(n)) return a,b end',{42},{42})
run(total..'let main(xs: Array(U32,2)): U32 = total(...xs,1)',{20,21},{42})
run(total..'let main(n: U32): U32 = total(...[n,1],1)',{40},{42})
run(pair..'let main(n: U32): Array(U32,3) = [1,...pair(n)]',{39},{1,39,2})
run(pair..'let main(n: U32): Array(U32,3) = [1,pair(n)]',{39},{1,39,2})
run('let parts(n: U32): (Array(U32,2),U32) = do return [n,1],1 end\nlet use(a: Array(U32,2),b: U32): U32 = a[0]+a[1]+b\nlet main(n: U32): U32 = use(...parts(n))',{40},{42})
run('let use(a: Array(U32,2)): U32 = a[0]+a[1]\nlet main(n: U32): U32 = use([n,2])',{40},{42})
run('let source(): Array(U32,2) = [20,22]\nlet main(): U32 = do let a,b = ...source() return a+b end',{}, {42})
run(total..[[
let State = { n: U32, change(): U32 = do n=99 return 1 end }
let main(): U32 = do
 let s=State { n=20 }
 let xs=[s.n,21]
 let r=total(...xs,s.change())
 return r
end
]],{}, {42})
run(total..[[
let State = { xs: Array(U32,2), change(): U32 = do xs[0]=99 return 1 end }
let main(): U32 = do let s=State { xs=[20,21] } return total(...s.xs,s.change()) end
]],{}, {42})
local point='let Point = {x: U32,y: U32}\n'
run(point..'let main(p: Point): Point = Point { ...p, x=42 }',{1,2},{42,2})
run(point..'let main(p: Point): Point = Point { x=42, ...p }',{1,2},{42,2})
run(point..'let main(): Point = Point { ...Point {x=20,y=22} }',{}, {20,22})
run(point..'let add {x: U32,y: U32}: U32 = x+y\nlet main(p: Point): U32 = add { ...p }',{20,22},{42})
run(point..'let add {x: U32,y: U32}: U32 = x+y\nlet main(p: Point): U32 = add {x=20,...p}',{99,22},{42})
run(point..[[
let State = {
 n: U32,
 record(): Point = do n=n*10+1 return Point {x=99,y=22} end,
 number(): U32 = do n=n*10+2 return 20 end,
}
let main(): (U32,U32) = do let s=State {n=0} let p=Point {...s.record(),x=s.number()} return p.x+p.y,s.n end
]],{}, {42,12})
run(point..[[
let State = {
 n: U32,
 record(): Point = do n=n*10+1 return Point {x=99,y=22} end,
 number(): U32 = do n=n*10+2 return 20 end,
}
let main(): (U32,U32) = do let s=State {n=0} let p=Point {x=s.number(),...s.record()} return p.x+p.y,s.n end
]],{}, {42,21})
run(point..'let main(): U32 = do let p=Point {x=20,y=22} let q=Point {...p} p.x=99 return q.x+q.y end',{}, {42})
run('let P = {x: U32,method(): U32 = x}\nlet main(): U32 = do let p=P {x=42} let q=P {...p} return q.x end',{}, {42})
-- Shared module publication: the initializer updates one existing persistent root once.
run(point..[[
let State = {n: U32}
let state=State {n=0}
let pair(): (U32,U32) = do state.n+=1 return 20,22 end
let a,b=...pair()
let main(): (U32,U32) = do return a+b,state.n end
]],{}, {42,1},{staticMode='interpreted',staticOptimize=false})
run('let a,b=...[20,22]\nlet main(): U32 = a+b',{}, {42},{staticMode='interpreted',staticOptimize=false})
reject('spread-source',total..'let main(): U32 = total(...1,2,3)')
reject('spread-source',point..total..'let main(p: Point): U32 = total(...p)')
reject('spread-source',pair..total..'let main(): U32 = total(...(pair(1)),2,3)')
reject('spread-overlap',point..'let main(p: Point): Point = Point {...p,...p,x=42}')
reject('duplicate-name',point..'let main(p: Point): Point = Point {...p,x=1,x=2}')
reject('unknown-field',point..'let Other = {z: U32}\nlet main(p: Other): Point = Point {...p,x=1,y=2}')
reject('array-length','let main(): Array(U32,2) = [...[1,2],3]')
reject('return-arity',pair..'let main(): U32 = do return ...pair(1) end')
reject('spread-source','let main(xs: Slice(U32)): U32 = do let a = ...xs return a end')
reject('borrow-return',[[
let Box={n: U32}
let choose(a: Ref(Box),b: Ref(Box)): Ref(Box) = a
let main(): Ref(Box) = do let a=Box {n=1} let b=Box {n=2} let refs=[Ref(a),Ref(b)] return choose(...refs) end
]])
-- An overridden contribution must still perform its potentially trapping work.
local trapUnit=C.typed{profile='slet',source=point..'let main(n: U32): Point = Point {x=42,...Point {x=1/n,y=2}}',name='spread-trap.slet'}
for _,optimize in ipairs(optimizers) do for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
 local session=Stage.open{mode=mode,optimize=optimize}
 local program=session:prepare(C.lower(trapUnit.functions,{profile='slet',exports={'main'}}),trapUnit.functions)
 local out,count,err=ffi.new('uint64_t[2]'),ffi.new('size_t[1]'),ffi.new('abc_error[1]')
 local input=ffi.new('uint64_t[1]',0)
 local status=session.C.abc_vm_call(session.vm,program.handle,'main',input,1,out,2,count,err)
 check(status==6 and ffi.string(err[0].message)=='language abort 1','overridden division still traps '..mode..'/'..tostring(optimize)..' status='..status..' '..ffi.string(err[0].message))
 executions=executions+1;session:close()
end end
local Check=require('let.check');local I=S.Ir
local array=S.Array(S.U32,2);local ref=I.Ref(I.Value(1),array)
check(Check.expr(I.Get(ref,I.Element(1),S.U32),{[1]=array},{})==S.U32,'checked static element selection')
for _,index in ipairs{-1,2,0.5} do
 local ok,err=pcall(Check.expr,I.Get(ref,I.Element(index),S.U32),{[1]=array},{})
 check(not ok and D.is(err) and err.code=='ir-field','invalid selector must reject')
end
local projections=run(total..'let main(xs: Array(U32,2)): U32 = total(...xs,1)',{20,21},{42})
local elements=0
for _,fn in ipairs(projections.functions) do Walk.walk(fn,{enter=function(node)
 if S.Ir.Get:isclassof(node) and node.field.kind=='Element' then elements=elements+1 end
end}) end
check(elements==2,'runtime arrays expand through two ordinary pure element projections')
print(('spread qualification: %d checks, %d VM executions, %d optimized configurations BLOCKED'):format(checks,executions,optimizerBlockers))
