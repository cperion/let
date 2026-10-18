package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local S=require('let.schema')
local Program=require('let.program')
local D=require('let.diag')
local I,L=S.Ir,S.List
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function reject(code,source,profiles)
 for _,profile in ipairs(profiles or {'slet','let'}) do
  local ok,err=pcall(C.typed,{profile=profile,source=source})
  check(not ok and D.is(err) and err.code==code,profile..'/'..code..': '..tostring(err))
 end
end
local function run(source,wanted,profile)
 local unit=C.typed({profile=profile or 'slet',source=source},{staticMode='interpreted',staticOptimize=false})
 for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimize in ipairs{false,true} do
  local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
  executions=executions+1;check(tonumber(result.cells[1])==wanted,mode..'/'..tostring(optimize))
 end end
 return unit
end
local prelude='let Point = { x: U32 }\nlet Holder = { value: Ref(Point) }\n'
-- The former promotion cases now reject. No amount of caller demand repairs them.
for _,body in ipairs{
 'let bad(): Ref(Point) = do let p = Point { x = 42 } return Ref(p) end',
 'let bad(): Slice(U32) = do let xs = [42] return Slice(xs) end',
 'let bad(p: Point): Ref(U32) = Ref(p.x)',
 'let identity(p: Ref(Point)): Ref(Point) = p let bad(): Holder = do let p = Point { x = 42 } return Holder { value = identity(Ref(p)) } end',
 'let bad(holder: Ref(Holder)): Unit = do let p = Point { x = 42 } holder.value = Ref(p) return end',
 [[let put(holder: Ref(Holder), value: Ref(Point)): Unit = do holder.value = value return end
 let relay(holder: Ref(Holder), value: Ref(Point)): Unit = put(holder,value)
 let bad(holder: Ref(Holder)): Unit = do let p = Point { x = 42 } relay(holder,Ref(p)) return end]],
 [[let put(holder: Ref(Holder), value: Ref(Point)): Unit = do holder.value = value return end
 let bad(incoming: Ref(Point)): Holder = do let p = Point { x = 42 } let h = Holder { value = incoming } put(Ref(h),Ref(p)) return h end]],
 [[let bad(incoming: Ref(Point), condition: Bool): Holder = do
 let p = Point { x = 42 } let h = Holder { value = incoming }
 if condition then h.value = Ref(p) end return h end]],
} do reject('borrow-escape',prelude..body..' let main(): U32 = 0') end
for _,body in ipairs{
 'let bad(view: Slice(U32)): Unit = do view[0] = 42 return end',
 'let bad(view: Slice(Point)): Unit = do view[0].x += 1 return end',
 'let mutate(p: Ref(Point)): Unit = do p.x += 1 return end let bad(view: Slice(Point)): Unit = mutate(Ref(view[0]))',
 'let mutate(p: Ref(Point)): Unit = do p.x += 1 return end let bad(view: Slice(Point)): Unit = view[0].mutate()',
 'let bad(view: Slice(Point)): Bool = Ptr(view[0]) == null(Point)',
} do reject('readonly-write',prelude..body..' let main(): U32 = 0') end
local higher=prelude..[[
let Actions = { body: (): Unit }
let apply(body: (): Unit): Unit = body()
let relay(body: (): Unit): Unit = apply(body)
let identity(body: (): Unit): (): Unit = body
let through(actions: Actions): Unit = actions.body()
let recursive(n: U32, body: (): Unit): Unit = do if n == 0 then return body() end return recursive(n-1,body) end
]]
for _,invocation in ipairs{'saved()','apply(saved)','relay(saved)','identity(saved)()',
 'through(Actions { body = saved })','recursive(2,saved)','apply do() holder.value = Ref(p) return end'} do
 reject('borrow-escape',higher..[[
 let bad(holder: Ref(Holder)): U32 = do let p = Point { x = 42 }
 let saved = do() holder.value = Ref(p) return end
 ]]..invocation..[[ return 0 end let main(): U32 = 0]],{'let'})
end
for _,body in ipairs{
 'let bad(n: U32): (U32): U32 = do let saved = n return do(x: U32) = saved+x end',
 'let bad(): (): U32 = do let p = Point { x = 42 } return do() = p.x end',
 [[let invoke(body: (): Ref(Point)): Ref(Point) = body()
 let bad(): Ref(Point) = do let p = Point { x = 42 } return invoke(do() = Ref(p)) end]],
 [[let save(holder: Ref(Holder), body: (): Ref(Point)): Unit = do holder.value = body() return end
 let bad(holder: Ref(Holder)): Unit = do let p = Point { x = 42 } save(holder,do() = Ref(p)) return end]],
 [[let Actions = { safe: (): Unit, bad: (): Unit }
 let bad(holder: Ref(Holder)): Unit = do let p = Point { x = 42 }
 let actions = Actions { safe = do() return end, bad = do() holder.value = Ref(p) return end }
 actions.bad() return end]],
} do reject('borrow-escape',prelude..body..' let main(): U32 = 0',{'let'}) end
local higherUnit=run(higher..[[
let main(): U32 = do let p = Point { x = 40 } let saved = do() p.x += 1 return end
 relay(saved) identity(saved)() return p.x end
]],42,'let')
check(#higherUnit.program.access.apply.invocations>0,'formal callback obligation remains explicit')
-- Calls observe the environment at each invocation, not a code-global capture union.
run(prelude..[[
let sequence(holder: Ref(Holder), q: Ref(Point), body: (): U32): U32 = do
 let before = body() holder.value = q let after = body() return before+after end
let main(): U32 = do let p = Point { x = 40 } let q = Point { x = 42 }
 let ctx... = Holder { value = Ref(p) } let saved = value let body = do() = value.x
 return (sequence)(Ref(ctx),Ref(q),body)+saved.x end
]],122,'let')
local between=prelude..[[
let between(holder: Ref(Holder), first: Ref(Point), last: Ref(Point), body: (): Ref(Point)): Ref(Point) = do
 holder.value = first let result = body() holder.value = last return result end
]]
reject('borrow-escape',between..[[
let bad(incoming: Ref(Point)): Ref(Point) = do let p = Point { x = 42 }
 let ctx... = Holder { value = incoming } let body = do() = value
 return (between)(Ref(ctx),Ref(p),incoming,body) end let main(): U32 = 0
]],{'let'})
run(between..[[
let remember(incoming: Ref(Point)): Ref(Point) = do let p = Point { x = 0 }
 let ctx... = Holder { value = incoming } let body = do() = value
 return (between)(Ref(ctx),incoming,Ref(p),body) end
let main(): U32 = do let p = Point { x = 42 } let r = remember(Ref(p)) return r.x end
]],42,'let')
run(prelude..[[
let invoke(body: (): Ref(Point)): Ref(Point) = body()
let remember(incoming: Ref(Point)): Ref(Point) = do let p = Point { x = 0 }
 let selected = incoming let body = do() = selected selected = Ref(p) return invoke(body) end
let main(): U32 = do let p = Point { x = 42 } let r = remember(Ref(p)) return r.x end
]],42,'let')
run(prelude..[[
let Actions = { saved: (): U32, live: (): U32 }
let main(): U32 = do let p = Point { x = 40 } let q = Point { x = 42 }
 let ctx... = Holder { value = Ref(p) } let snapshot = value
 let actions = Actions { saved = do() = snapshot.x, live = do() = value.x }
 value = Ref(q) return actions.saved()+actions.live() end
]],82,'let')
run([[let Actions = { first: (): U32, second: (): U32 }
let main(): U32 = do let actions = Actions { first = do() = 40, second = do() = 42 } return actions.second() end]],42,'let')
for _,replacement in ipairs{'holder.value = Ref(local)','if choose then holder.value = Ref(local) end'} do
 run(prelude..[[
 let saved(incoming: Ref(Point), choose: Bool): Ref(Point) = do
 let local = Point { x = 0 } let holder = Holder { value = incoming } let before = holder.value
 ]]..replacement..[[ return before end
 let main(): U32 = do let p = Point { x = 42 } let r = saved(Ref(p),true) return r.x end]],42)
end
local identity=run(prelude..[[
let identity(p: Ref(Point)): Ref(Point) = p
let main(): U32 = do let p = Point { x = 40 } let r = identity(Ref(p)) r.x += 2 return p.x end]],42)
check(identity.program.access.identity.results[1].components[1].loans.sources[1].kind=='ValueInput','borrow result retains input relation')
run(prelude..[[
let put(holder: Ref(Holder), value: Ref(Point)): Unit = do holder.value = value return end
let main(): U32 = do let p = Point { x = 40 } let q = Point { x = 42 }
 let holder = Holder { value = Ref(p) } put(Ref(holder),Ref(q)) return holder.value.x end]],42)
run([[let Point = { x: U32, mutate(): Unit = do x += 2 return end }
let main(): U32 = do let values = [Point { x = 40 }] let view = Slice(values)
 let saved: Point = view[0] saved.mutate() return saved.x+values[0].x end]],82)
run(prelude..[[let query(p: Point): U32 = p.x
let main(): U32 = do let values = [Point { x = 42 }] let view = Slice(values) return view[0].query() end]],42)
run(prelude..[[let state = Point { x = 40 } let expose(): Ref(Point) = Ref(state)
let main(): U32 = do let r = expose() r.x += 2 return state.x end]],42)
run('let expose(): Slice(U8) = "*" let main(): U32 = U32(expose()[0])',42)
reject('borrow-escape',[[
let Point = { x: U32 }
let Holder = { saved_ref: Ref(Point), replace(next: Ref(Point)): Ref(Point) = do saved_ref = next return saved_ref end }
let bad(incoming: Ref(Point)): Ref(Point) = do let holder = Holder { saved_ref = incoming }
 let local = Point { x = 42 } return holder.replace(Ref(local)) end let main(): U32 = 0]])
local getter=run([[
let Point={x:U32} let Box={child:Ref(Point)}
let child(p:Ref(Box)):Ref(Point)=p.child
let main():U32=do let a=Point{x=17} let b=Point{x=25} let box=Box{child=Ref(a)}
 let saved=child(Ref(box)) box.child=Ref(b) let current=child(Ref(box)) return saved.x+current.x end
]],42)
check(getter.program.access.child.results[1].components[1].loans.sources[1].kind=='ContentsInput','open field results preserve an input contents relation')
-- Opaque provenance and readonly permission failures stay closed at typed IR.
local function rejectsIR(code,functions,modules,foreigns)
 local ok,err=pcall(Program.analyze,functions,modules,foreigns);check(not ok and D.is(err) and err.code==code,tostring(err))
end
local Point=S.Record{x=S.U32};local ref=S.Ref(S.U32);local p,r=I.Value(1),I.Value(2);local slot=I.Storage(1)
rejectsIR('ir-initialized',{I.Fn('uninitialized',I.Entry,0,L{},L{ref},L{},L{
 I.Var(slot,ref,nil),I.Read(r,ref,I.Local(slot)),I.Return(L{I.Ref(r,ref)})})})
local flag=I.Value(3)
rejectsIR('ir-initialized',{I.Fn('maybe_initialized',I.Entry,0,L{S.inValue(ref),S.inValue(S.Bool)},L{ref},L{I.ValueParam(0,p,ref),I.ValueParam(1,flag,S.Bool)},L{
 I.Var(slot,ref,nil),I.If(I.Ref(flag,S.Bool),L{I.Store(I.Local(slot),I.Ref(p,ref))},L{}),
 I.Read(r,ref,I.Local(slot)),I.Return(L{I.Ref(r,ref)})})})
local foreign=I.Foreign('unknown',L{},L{ref})
rejectsIR('borrow-proof',{I.Fn('unknown_result',I.Entry,0,L{},L{ref},L{},L{
 I.Call(L{r},'unknown',L{}),I.Return(L{I.Ref(r,ref)})})},nil,{foreign})
local view=S.View(S.Sig({}, {ref}))
rejectsIR('borrow-proof',{I.Fn('opaque_view',I.Entry,0,L{},L{ref},L{},L{
 I.View(p,view,'unknown',L{},nil),I.Indirect(L{r},I.Ref(p,view),L{}),I.Return(L{I.Ref(r,ref)})})},nil,{foreign})
local borrowing=I.Foreign('uncontracted',L{S.inValue(ref)},L{S.Unit})
rejectsIR('borrow-proof',{I.Fn('opaque_borrow',I.Entry,0,L{S.inValue(ref)},L{S.Unit},L{I.ValueParam(0,p,ref)},L{
 I.Call(L{r},'uncontracted',L{I.ValueArg(I.Ref(p,ref))}),I.Return(L{I.Const(S.Unit,I.UInt(0))})})},nil,{borrowing})
local root=I.ModuleRoot('readonly',Point,false)
local mutate=I.Fn('mutate',I.Body,0,L{S.inPlace(Point)},L{S.Unit},L{I.PlaceParam(0,slot,Point)},L{
 I.Store(I.Project(I.Local(slot),I.Field('x')),I.Const(S.U32,I.UInt(1))),I.Return(L{I.Const(S.Unit,I.UInt(0))})})
local caller=I.Fn('caller',I.Entry,0,L{},L{S.Unit},L{},L{I.Call(L{r},'mutate',L{I.BorrowArg(I.Global(root))}),I.Return(L{I.Const(S.Unit,I.UInt(0))})})
rejectsIR('readonly-write',{mutate,caller},{I.ModuleData(root,string.char(42,0,0,0))})
-- A conditional trap does not erase its success edge; an unconditional one does.
for _,fatal in ipairs{false,true} do
 local fn=I.Fn('after_trap',I.Entry,0,L{},L{ref},L{},L{
  I.Var(slot,S.U32,I.Const(S.U32,I.UInt(42))),I.Trap(I.Const(S.Bool,I.Boolean(fatal)),'failure'),
  I.Return(L{I.Addr(I.Local(slot),ref,S.Borrow.WriteAccess)})})
 if fatal then check(Program.analyze{fn}~=nil,'unreachable escape after fatal trap') else rejectsIR('borrow-escape',{fn}) end
end
print(('borrow/effect checks: %d checks, %d VM executions'):format(checks,executions))
