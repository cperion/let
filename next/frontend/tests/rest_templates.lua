package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C,D,S,Walk=require('let.compiler'),require('let.diag'),require('let.schema'),require('let.walk')
local ffi=require('let.abi')
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local options={staticMode='interpreted',staticOptimize=false}
local function reject(code,text,profile)
 local ok,err=pcall(function()
  local unit=C.typed({profile=profile or 'slet',source=text,name='rest-reject.slet'},options)
  return require('let.layout').program(unit.program)
 end)
 check(not ok and D.is(err) and err.code==code,code..': '..tostring(err))
end
local function rejectBorrow(text,profile) reject('borrow-escape',text,profile) end
local function run(text,args,wanted,unoptimized)
 local unit=C.typed({profile='slet',source=text,name='rest.slet'},options)
 for _,optimize in ipairs(unoptimized and {false} or {false,true}) do
  for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
   local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize,arguments=args or {}})
   executions=executions+1
   check(#result.values==#wanted,'logical result count')
   for index,value in ipairs(wanted) do
    local item=result.values[index];local actual=tonumber(item.bits)
    if item.type==S.F64 then local bits=ffi.new('uint64_t[1]',item.bits);actual=tonumber(ffi.cast('double*',bits)[0]) end
    check(actual==value,mode..'/'..tostring(optimize)..' component '..index..' actual='..tostring(actual))
   end
  end
 end
 return unit
end
run('let count(...args): U32 = args.length; let main(): U32 = count()',{}, {0})
run('let count(...args): U32 = args.length; let main(n: U32): U32 = count(n,2.5,true)',{21},{3})
run('let pass(...args) = do return ...args end; let main(n: U32): (U32,F64,Bool) = do return pass(n,2.5,true) end',{21},{21,2.5,1})
run('let first(...args): U32 = args[0]; let main(n: U32): U32 = first(n,99)',{42},{42})
run('let empty(): Unit = do return end; let count(...args): U32 = args.length; let main(): U32 = count(empty(),empty())',{}, {2})
run('let last(...args): U32 = args[args.length-1]; let main(n: U32): U32 = last(1,n)',{42},{42})
run('let add(a: U32,b: U32,...args): U32 = a+b+args[0]; let main(n: U32): U32 = add(n)(1,1)',{40},{42})
run('let add(a: U32,b: U32,...args): U32 = a+b+args[0]; let main(n: U32): U32 = add(40)(n,1)',{1},{42})
run('let use(a: U32,b: U32): U32 = a+b; let pass(...args): U32 = use(...args); let main(n: U32): U32 = pass(...[n,2])',{40},{42})
run('let pair(n: U32): (U32,U32) = do return n,2 end; let pass(...args): U32 = args[0]+args[1]+args[2]; let main(n: U32): U32 = pass(1,...pair(n))',{39},{42})
run('let pass(...args): U32 = do let inner(): U32 = args[1] return inner() end; let main(n: U32): U32 = pass(1,n)',{42},{42})
run('let pass = do(...args): U32 = args[0]; let main(n: U32): U32 = pass(n)',{42},{42})
local adapter='let apply(T: Type,f: T,...args) = f(...args);\n'
local twice='let twice(n: U32): U32 = n*2;\n'
local direct=run(adapter..twice..'let main(n: U32): U32 = apply((U32): U32,twice,n)',{21},{42})
local calls,indirects,views=0,0,0
for _,fn in ipairs(direct.functions) do if fn.id:find('apply_instance_',1,true) then Walk.walk(fn,{enter=function(node)
 if S.Ir.Call:isclassof(node) then calls=calls+1;check(node.target=='twice','known callee direct')
 elseif S.Ir.Indirect:isclassof(node) then indirects=indirects+1 elseif S.Ir.View:isclassof(node) then views=views+1 end
end}) end end
check(calls==1 and indirects==0 and views==0,'known adapter has direct call, no callable/pack allocation')
local unknown=run(adapter..twice..'let invoke(f: (U32): U32,n: U32): U32 = apply((U32): U32,f,n); let main(n: U32): U32 = invoke(twice,n)',{21},{42})
local found=0
for _,fn in ipairs(unknown.functions) do if fn.id:find('apply_instance_',1,true) then Walk.walk(fn,{enter=function(node) if S.Ir.Indirect:isclassof(node) then found=found+1 end end}) end end
check(found==1,'unknown implementation uses the declared fixed indirect ABI')
run(adapter..twice..'let u32=apply((U32): U32); let main(n: U32): U32 = u32(twice,n)',{21},{42})
run(adapter..'let pair(n: U32): (U32,U32) = do return n,2 end; let main(n: U32): (U32,U32) = do return apply((U32): (U32,U32),pair,n) end',{40},{40,2})
local reused=run('let first(...args): U32 = args[0]; let main(n: U32): U32 = first(n)+first(n+1)',{20},{41})
local instances=0
for _,fn in ipairs(reused.functions) do if fn.id:find('first_instance_',1,true) then instances=instances+1 end end
check(instances==1,'same code/type/pack shape reuses one elaborated instance, not argument values')
run('let down(n: U32,...args): U32 = do if n==0 then return args[0] else return down(n-1,...args) end end; let main(n: U32): U32 = down(n,42)',{12},{42})
run(adapter..'let down(n: U32): U32 = do if n==0 then return 42 else return apply((U32): U32,down,n-1) end end; let main(n: U32): U32 = down(n)',{12},{42})
run(adapter..[[
let Box={n: U32}
let main(): U32 = do
 let a=Box {n=10} let b=Box {n=20} let r=Ref(a)
 let walk(n: U32): U32 = do
  if n==0 then return r.n else return apply((U32): U32,walk,n-1)+r.n end
 end
 r=Ref(b)
 return walk(2)
end
]],{}, {30},true)
-- Definition-time reference holding, even though instance checking happens after replacement.
run([[
let Box={n: U32}
let main(): U32 = do
 let a=Box {n=10} let b=Box {n=20} let r=Ref(a)
 let saved(...args): U32 = r.n
 r=Ref(b)
 return saved()
end
]],{}, {10},true)
run([[
let Box={n: U32}
let main(): (U32,U32) = do
 let a=Box {n=10} let b=Box {n=20} let r=Ref(a)
 let first(...args): U32 = r.n
 r=Ref(b)
 let second(...args): U32 = r.n
 return second(),first()
end
]],{}, {20,10},true)
run([[
let Box={n: U32}
let main(flag: Bool): U32 = do
 let a=Box {n=10} let b=Box {n=20} let r=Ref(a)
 if flag then
  let saved(...args): U32 = r.n
  r=Ref(b)
  return saved()
 else return 42 end
end
]],{1}, {10},true)
-- An opened place remains live; a deliberately saved field remains a snapshot.
run([[
let Box={n: U32}
let main(): (U32,U32) = do
 let box=Box {n=10} let box...
 let old=n
 let live(...args): U32 = n
 let frozen(...args): U32 = old
 box.n=42
 return live(),frozen()
end
]],{}, {42,10},true)
-- Known code transports different holdings through explicit inputs of one instance.
run(adapter..[[
let main(n: U32): U32 = do
 let a=do(x: U32): U32 = n+x
 return apply((U32): U32,a,2)+apply((U32): U32,a,3)
end
]],{10},{25})
-- Component snapshots occur once, before later supplies mutate the source.
run([[
let State={n: U32, change(): U32 = do n=99 return 2 end}
let sum(...args): U32 = args[0]+args[1]
let main(): U32 = do let s=State {n=40} return sum(s.n,s.change()) end
]],{}, {42})
run('let choose(...args): U32 = do let f=args[0] return f(args[1]) end; let twice(n: U32): U32=n*2; let main(n: U32): U32 = choose(twice,n)',{21},{42})
run('let State={n: U32, add(...args): U32 = n+args[0]}; let main(n: U32): U32 = do let s=State {n=n} return s.add(2) end',{40},{42})
run('let plus(n: U32,...args): U32 = n+args[0]; let main(n: U32): U32 = n.plus(2)',{40},{42})
run('let State={n: U32, add(a: U32,b: U32,...args): U32 = n+a+b+args[0]}; let main(): U32 = do let s=State {n=20} let p=s.add(20) return p(1,1) end',{}, {42})
run('let identity(T: Type,x: T): T = x; let main(n: U32): U32 = identity(U32,n)',{42},{42})
run('let Box={n: U32, get(): U32 = n}; let make(T: Type,n: U32): T = T {n=n}; let main(n: U32): U32 = do let b=make(Box,n) return b.get() end',{42},{42},true)
run('let index(...args): U32 = args[U64(0)]; let main(n: U32): U32 = index(n)',{42},{42})
run([[
let State={n: U32}
let trace=State {n=0}
let mark(n: U32): Unit = do trace.n=trace.n*10+n return end
let result(n: U32): (U32,U32) = do mark(2) return n,2 end
let traced(T: Type,f: T,...args) = do mark(1) defer mark(3) return f(...args) end
let main(n: U32): (U32,U32,U32) = do let a,b=traced((U32): (U32,U32),result,n) return a,b,trace.n end
]],{40},{40,2,123})
run(adapter..[[
let State={n: U32}
let main(): U32 = do
 let state=State {n=10} let state...
 let value(): U32 = n
 state.n=42
 return (apply)((): U32,value)
end
]],{}, {42},true)
run([[
let Left={n: U32, get(): U32 = n+1}
let Right={n: U32, get(): U32 = n+2}
let get(...args): U32 = args[0].get()
let main(): U32 = do let a=Left {n=20} let b=Right {n=20} return (get)(a)+(get)(b) end
]],{}, {43},true)
local snapshots=run([[
let Box={n: U32}
let main(): U32 = do
 let a=Box {n=10} let b=Box {n=20} let r=Ref(a)
 let saved(...args): U32 = r.n
 r=Ref(b)
 return saved(1)+saved(1.5)
end
]],{}, {20},true)
local captureReads=0
for _,fn in ipairs(snapshots.functions) do if fn.id=='main' then Walk.walk(fn,{enter=function(node)
 if S.Ir.Read:isclassof(node) and node.type:isRef() then captureReads=captureReads+1 end
end}) end end
check(captureReads==1,'different pack shapes share the selected definition-time snapshot')
local unused=run([[
let Box={n: U32}
let main(): U32 = do let box=Box {n=1} let r=Ref(box) let unused(...args): U32 = r.n return 42 end
]],{}, {42})
local reads=0
for _,fn in ipairs(unused.functions) do Walk.walk(fn,{enter=function(node) if S.Ir.Read:isclassof(node) then reads=reads+1 end end}) end
check(reads==0,'unused template has no capture reads or executable body')
rejectBorrow([[
let Box={n: U32}
let Holder={r: Ref(Box)}
let save(dst: Ref(Holder),...args): Unit = do dst.r=args[0] return end
let main(dst: Ref(Holder)): Unit = do let box=Box {n=1} return save(dst,Ref(box)) end
]])
rejectBorrow([[
let Box={n: U32}
let hold(...args) = do let remember(): Ref(Box) = args[0] return remember end
let main(): (): Ref(Box) = do let box=Box {n=1} return hold(Ref(box)) end
]],'let')
rejectBorrow(adapter..[[
let Box={n: U32}
let Holder={r: Ref(Box)}
let main(dst: Ref(Holder)): Unit = do
 let box=Box {n=1}
 let save(n: U32): Unit = do dst.r=Ref(box) return end
 return apply((U32): Unit,save,0)
end
]])
reject('static-required','let add(a: U32,b: U32,...args): U32 = a+b; let main(n: U32): U32 = (add(n))(1,1)')
reject('pack-use','let f(...args): U32 = do args=1 return 1 end; let main(): U32 = f(1)')
reject('pack-index','let add(a: U32,...args): U32 = args[0]; let main(n: U32): U32 = add(n)(2)')
reject('pack-use','let f(...args): U32 = do let x=args return 1 end; let main(): U32 = f(1)')
reject('pack-use','let f(...args) = args; let main(): U32 = f(1)')
reject('pack-use','let f(...args): U32 = do let xs=[args] return 1 end; let main(): U32 = f(1)')
reject('pack-index','let f(...args): U32 = args[0]; let main(): U32 = f()')
reject('pack-index','let f(n: U32,...args): U32 = args[n]; let main(n: U32): U32 = f(n,1)')
reject('pack-index','let f(...args): U32 = args[-1]; let main(): U32 = f(1)')
reject('pack-index','let f(...args): U32 = args[0.5]; let main(): U32 = f(1)')
reject('template-use','let f(...args): U32 = args[0]; let use(g: (U32): U32): U32 = g(1); let main(): U32 = use(f)')
reject('type-mismatch',adapter..'let main(): U32 = apply(U32,1,2)')
rejectBorrow([[
let Box={n: U32}
let first(...args): Ref(Box) = args[0]
let main(): Ref(Box) = do let box=Box {n=1} return first(Ref(box)) end
]])
-- Source-only exports/imports retain definitions, never variadic ABC entries.
local path=os.tmpname();assert(os.remove(path));assert(os.execute('mkdir '..path)==0)
local function file(name,text) local f=assert(io.open(path..'/'..name,'w'));assert(f:write(text));assert(f:close()) end
file('lib.slet',adapter..twice..'let Meta=Type; return { types={Meta}, functions={apply,twice} }')
file('first.slet','use lib; let identity(T: lib.Meta,x: T): T = x; let run(n: U32): U32 = lib.apply((U32): U32,lib.twice,identity(U32,n)); return {functions={run}}')
file('second.slet','use lib; let run(n: U32): U32 = lib.apply((U32): U32,lib.twice,n); return {functions={run}}')
file('main.slet','use first; use second; let main(n: U32): U32 = first.run(n)+second.run(n); return {functions={main}}')
local imported=C.typedFile(path..'/main.slet',options)
local sourceOnly=false
for _,loaded in pairs(imported.modules) do if loaded.namespace.members.apply then
 sourceOnly=true;check(loaded.unit.runtimeExports[1]=='twice' and #loaded.unit.runtimeExports==1,'template not exported as ABC entry')
end end
check(sourceOnly,'template remained publicly importable as source metadata')
for _,optimize in ipairs{false,true} do for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
 local result=C.stage(imported.functions,{profile='slet',entry='main',mode=mode,optimize=optimize,arguments={21}})
 check(tonumber(result.cells[1])==84,'shared imported instance executes twice');executions=executions+1
end end
assert(os.execute('rm -r '..path)==0)
print(('rest templates: %d checks, %d VM executions'):format(checks,executions))
