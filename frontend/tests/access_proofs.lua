package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local S=require('let.schema')
local IR=require('let.ir')
local Program=require('let.program')
local D=require('let.diag')
local I,L=S.Ir,S.List
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function reject(code,source,profiles)
 for _,profile in ipairs(profiles or {'slet','let'}) do
  local ok,err=pcall(function()
   local unit=C.typed{profile=profile,source=source,name='access-proof.'..profile}
   return require('let.layout').program(unit.program)
  end)
  check(not ok and D.is(err) and err.code==code,profile..'/'..code..': '..tostring(err))
 end
end
local function counted(reason,source,profiles)
 for _,profile in ipairs(profiles or {'slet','let'}) do
  local unit=C.typed{profile=profile,source=source,name='access-proof.'..profile};local found=false
  for _,fn in ipairs(unit.functions) do for _,r in ipairs(unit.program.ownership[fn.id].summary.counted) do if r.reason==reason then found=true end end end
  check(found,profile..': expected counted '..reason..' obligation')
 end
end
local function run(source,wanted,options)
 local unit=C.typed({profile='slet',source=source,name='access-proof.slet'},options)
 for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimize in ipairs{false,true} do
  local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
  executions=executions+1;check(tonumber(result.cells[1])==wanted,mode..'/'..tostring(optimize))
 end end
 return unit
end
local prelude='let Point = { x: U32 }\n'
counted('return',prelude..'let bad(): Ref(Point) = do let p = Point { x = 42 } return Ref(p) end let main(): U32 = 0')
counted('return','let bad(): Slice(U32) = do let xs = [42] return Slice(xs) end let main(): U32 = 0')
counted('return',prelude..'let bad(p: Point): Ref(U32) = Ref(p.x) let main(): U32 = 0')
counted('return',prelude..[[
let Holder = { value: Ref(Point) }
let identity(p: Ref(Point)): Ref(Point) = p
let bad(): Holder = do let p = Point { x = 42 } return Holder { value = identity(Ref(p)) } end
let main(): U32 = 0
]])
counted('return',[[
let bad(n: U32): (U32): U32 = do let saved = n return do(x: U32) = saved + x end
let main(): U32 = 0
]],{'let'})
counted('return',prelude..[[
let bad(): (): U32 = do let p = Point { x = 42 } return do() = p.x end
let main(): U32 = 0
]],{'let'})
counted('store',prelude..[[
let Holder = { value: Ref(Point) }
let bad(holder: Ref(Holder)): Unit = do let p = Point { x = 42 } holder.value = Ref(p) return end
let main(): U32 = 0
]])
counted('store',prelude..[[
let Holder = { value: Ref(Point) }
let put(holder: Ref(Holder), value: Ref(Point)): Unit = do holder.value = value return end
let relay(holder: Ref(Holder), value: Ref(Point)): Unit = put(holder,value)
let bad(holder: Ref(Holder)): Unit = do let p = Point { x = 42 } relay(holder,Ref(p)) return end
let main(): U32 = 0
]])
counted('return',prelude..[[
let Holder = { value: Ref(Point) }
let put(holder: Ref(Holder), value: Ref(Point)): Unit = do holder.value = value return end
let bad(incoming: Ref(Point)): Holder = do
 let local = Point { x = 42 } let holder = Holder { value = incoming }
 put(Ref(holder),Ref(local))
 return holder
end
let main(): U32 = 0
]])
counted('return',prelude..[[
let Holder = { value: Ref(Point) }
let bad(incoming: Ref(Point), condition: Bool): Holder = do
 let p = Point { x = 42 } let holder = Holder { value = incoming }
 if condition then holder.value = Ref(p) end
 return holder
end
let main(): U32 = 0
]])
reject('readonly-write',[[
let bad(view: Slice(U32)): Unit = do view[0] = 42 return end
let main(): U32 = 0
]])
reject('readonly-write',prelude..[[
let bad(view: Slice(Point)): Unit = do view[0].x += 1 return end
let main(): U32 = 0
]])
reject('readonly-write',prelude..[[
let mutate(p: Ref(Point)): Unit = do p.x += 1 return end
let bad(view: Slice(Point)): Unit = mutate(Ref(view[0]))
let main(): U32 = 0
]])
reject('readonly-write',prelude..[[
let mutate(p: Ref(Point)): Unit = do p.x += 1 return end
let bad(view: Slice(Point)): Unit = view[0].mutate()
let main(): U32 = 0
]])
-- Formal callable transport composes the actual contract, not an unknown-effect
-- substitute. All spellings and forwarding routes retain the same store bound.
local higherPrelude=prelude..[[
let Holder = { value: Ref(Point) }
let Actions = { body: (): Unit }
let apply(body: (): Unit): Unit = body()
let relay(body: (): Unit): Unit = apply(body)
let identity(body: (): Unit): (): Unit = body
let through(actions: Actions): Unit = actions.body()
let recursive(n: U32, body: (): Unit): Unit = do
 if n == 0 then return body() end
 return recursive(n - 1, body)
end
]]
for _,invocation in ipairs{'saved()','apply(saved)','relay(saved)','identity(saved)()',
 'through(Actions { body = saved })','recursive(2, saved)',
 'apply do() holder.value = Ref(p) return end'} do
 counted('store',higherPrelude..[[
let bad(holder: Ref(Holder)): U32 = do
 let p = Point { x = 42 }
 let saved = do() holder.value = Ref(p) return end
 ]]..invocation..[[
 return 0
end
let main(): U32 = 0
]],{'let'})
end
counted('return',prelude..[[
let invoke(body: (): Ref(Point)): Ref(Point) = body()
let bad(): Ref(Point) = do
 let p = Point { x = 42 }
 return invoke(do() = Ref(p))
end
let main(): U32 = 0
]],{'let'})
counted('return',prelude..[[
let invoke(body: (): Ref(Point)): Ref(Point) = body()
let Holder = { value: Ref(Point) }
let bad(incoming: Ref(Point)): Ref(Point) = do
 let p = Point { x = 42 }
 let ctx... = Holder { value = incoming }
 let body = do() = value
 value = Ref(p)
 return (invoke)(body)
end
let main(): U32 = 0
]],{'let'})
local function runCallable(source,wanted)
 local unit=C.typed{profile='let',source=source,name='higher-order-access.let'}
 for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimize in ipairs{false,true} do
  local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
  executions=executions+1;check(tonumber(result.cells[1])==wanted,'higher-order contract '..mode..'/'..tostring(optimize))
 end end
 return unit
end
local safeHigher=runCallable(higherPrelude..[[
let main(): U32 = do
 let p = Point { x = 40 }
 let saved = do() p.x += 1 return end
 relay(saved)
 identity(saved)()
 return p.x
end
]],42)
check(#safeHigher.program.access[safeHigher.functions[1].id].invocations>0,'formal invocation obligation is published')
-- Query live places at the invocation point, not at wrapper entry or after all
-- its stores. The two intermediate snapshots must remain independent.
runCallable(prelude..[[
let Holder = { value: Ref(Point) }
let sequence(holder: Ref(Holder), q: Ref(Point), body: (): U32): U32 = do
 let before = body()
 holder.value = q
 let after = body()
 return before + after
end
let main(): U32 = do
 let p = Point { x = 40 } let q = Point { x = 42 }
 let ctx... = Holder { value = Ref(p) }
 let saved = value
 let body = do() = value.x
 return (sequence)(Ref(ctx), Ref(q), body) + saved.x
end
]],122)
-- A live callback must read between these stores. Moving invocation effects
-- behind the second store would incorrectly hide the local result's escape.
local orderedPrelude=prelude..[[
let Holder = { value: Ref(Point) }
let between(holder: Ref(Holder), first: Ref(Point), last: Ref(Point), body: (): Ref(Point)): Ref(Point) = do
 holder.value = first
 let result = body()
 holder.value = last
 return result
end
]]
counted('return',orderedPrelude..[[
let bad(incoming: Ref(Point)): Ref(Point) = do
 let p = Point { x = 42 }
 let ctx... = Holder { value = incoming }
 let body = do() = value
 return (between)(Ref(ctx), Ref(p), incoming, body)
end
let main(): U32 = 0
]],{'let'})
runCallable(orderedPrelude..[[
let remember(incoming: Ref(Point)): Ref(Point) = do
 let p = Point { x = 0 }
 let ctx... = Holder { value = incoming }
 let body = do() = value
 return (between)(Ref(ctx), incoming, Ref(p), body)
end
let main(): U32 = do let p = Point { x = 42 } let r = remember(Ref(p)) return r.x end
]],42)
-- A value holding is a saved snapshot, unlike the live opened place above.
runCallable(prelude..[[
let invoke(body: (): Ref(Point)): Ref(Point) = body()
let remember(incoming: Ref(Point)): Ref(Point) = do
 let p = Point { x = 0 }
 let selected = incoming
 let body = do() = selected
 selected = Ref(p)
 return invoke(body)
end
let main(): U32 = do let p = Point { x = 42 } let r = remember(Ref(p)) return r.x end
]],42)
-- A callback result feeds an ordinary store; retaining its actual local owner
-- must not be erased by a formal invocation/result identity.
counted('store',higherPrelude..[[
let save(holder: Ref(Holder), body: (): Ref(Point)): Unit = do
 holder.value = body()
 return
end
let bad(holder: Ref(Holder)): Unit = do
 let p = Point { x = 42 }
 save(holder, do() = Ref(p))
 return
end
let main(): U32 = 0
]],{'let'})
-- Concrete callable holdings retain their formation context and component. A
-- harmless sibling field cannot hide a retaining callback, or become its code.
counted('store',prelude..[[
let Holder = { value: Ref(Point) }
let Actions = { safe: (): Unit, bad: (): Unit }
let bad(holder: Ref(Holder)): Unit = do
 let p = Point { x = 42 }
 let actions = Actions {
  safe = do() return end,
  bad = do() holder.value = Ref(p) return end,
 }
 actions.bad()
 return
end
let main(): U32 = 0
]],{'let'})
local concrete=C.typed{profile='let',source=[[
let Actions = { first: (): U32, second: (): U32 }
let main(): U32 = do
 let actions = Actions { first = do() = 40, second = do() = 42 }
 return actions.second()
end
]]}
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimize in ipairs{false,true} do
 local result=C.stage(concrete.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
 executions=executions+1;check(tonumber(result.cells[1])==42,'qualified callable component '..mode)
end end
local holdings=C.typed{profile='let',source=[[
let Point = { x: U32 }
let Holder = { r: Ref(Point) }
let Actions = { saved: (): U32, live: (): U32 }
let main(): U32 = do
 let p = Point { x = 40 } let q = Point { x = 42 }
 let ctx... = Holder { r = Ref(p) }
 let snapshot = r
 let actions = Actions { saved = do() = snapshot.x, live = do() = r.x }
 r = Ref(q)
 return actions.saved() + actions.live()
end
]]}
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimize in ipairs{false,true} do
 local result=C.stage(holdings.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
 executions=executions+1;check(tonumber(result.cells[1])==82,'value snapshot versus live place holding '..mode)
end end
-- Collection-element schema propagation is a separate existing admission gap.
reject('unknown-name',[[
let Point = { x: U32, mutate(): Unit = do x += 1 return end }
let bad(view: Slice(Point)): Unit = view[0].mutate()
let main(): U32 = 0
]])
run([[
let Point = { x: U32 }
let query(p: Point): U32 = p.x
let main(): U32 = do let values = [Point { x = 42 }] let view = Slice(values) return view[0].query() end
]],42)
run([[
let Point = { x: U32, mutate(): Unit = do x += 2 return end }
let main(): U32 = do
 let values = [Point { x = 40 }] let view = Slice(values)
 let saved: Point = view[0]
 saved.mutate()
 return saved.x + values[0].x
end
]],82)
-- Saved field reads retain their original loan even after the live field changes.
run(prelude..[[
let Holder = { value: Ref(Point) }
let saved(incoming: Ref(Point)): Ref(Point) = do
 let local = Point { x = 0 }
 let holder = Holder { value = incoming }
 let before = holder.value
 holder.value = Ref(local)
 return before
end
let main(): U32 = do let p = Point { x = 42 } let r = saved(Ref(p)) return r.x end
]],42)
run(prelude..[[
let Holder = { value: Ref(Point) }
let saved(incoming: Ref(Point), choose: Bool): Ref(Point) = do
 let local = Point { x = 0 } let holder = Holder { value = incoming }
 let before = holder.value
 if choose then holder.value = Ref(local) end
 return before
end
let main(): U32 = do let p = Point { x = 42 } let r = saved(Ref(p),true) return r.x end
]],42)
reject('readonly-write',prelude..[[
let bad(view: Slice(Point)): Bool = Ptr(view[0]) == null(Point)
let main(): U32 = 0
]])
local identity=run(prelude..[[
let identity(p: Ref(Point)): Ref(Point) = p
let main(): U32 = do let p = Point { x = 40 } let r = identity(Ref(p)) r.x += 2 return p.x end
]],42)
check(identity.program.access[identity.functions[1].id].results[1].components[1].loans.sources[1].kind=='ValueInput','identity exports actual input provenance')
run(prelude..[[
let Holder = { value: Ref(Point) }
let put(holder: Ref(Holder), value: Ref(Point)): Unit = do holder.value = value return end
let main(): U32 = do
 let p = Point { x = 40 } let q = Point { x = 42 }
 let holder = Holder { value = Ref(p) }
 put(Ref(holder),Ref(q))
 return holder.value.x
end
]],42)
local module=run(prelude..[[
let state = Point { x = 40 }
let expose(): Ref(Point) = Ref(state)
let main(): U32 = do let r = expose() r.x += 2 return state.x end
]],42,{staticMode='interpreted'})
check(module.program.access[module.functions[1].id].results[1].components[1].loans.sources[1].kind=='Global','module references retain module-root identity')
run('let expose(): Slice(U8) = "*" let main(): U32 = U32(expose()[0])',42)
-- Return state from a PlaceParam method follows its stores, rather than keeping
-- the entry field as an alias. The caller instantiates its owner constraint.
counted('return',[[
let Point = { x: U32 }
let Holder = {
 saved_ref: Ref(Point),
 replace(next: Ref(Point)): Ref(Point) = do saved_ref = next return saved_ref end,
}
let bad(incoming: Ref(Point)): Ref(Point) = do
 let holder = Holder { saved_ref = incoming } let local = Point { x = 42 }
 return holder.replace(Ref(local))
end
let main(): U32 = 0
]])
-- Readonly module permissions must survive ordinary direct-call summaries, not
-- merely syntax-level bans on slice stores.
local Point=S.Record{x=S.U32}
local root=I.ModuleRoot('readonly_test',Point,false)
local bytes=require('let.snapshot').fromCells(Point,{42}).image
local storage=I.Storage(1)
local place=I.Project(I.Local(storage),I.Field('x'))
local mutation=I.Fn('mutate',I.Body,0,L{S.inPlace(Point)},L{S.Unit},L{I.PlaceParam(0,storage,Point)},L{I.Store(place,I.Const(S.U32,I.UInt(1))),I.Return(L{I.Const(S.Unit,I.UInt(0))})})
local caller=I.Fn('main',I.Entry,0,L{},L{S.Unit},L{},L{I.Call(L{I.Value(1)},'mutate',L{I.BorrowArg(I.Global(root))}),I.Return(L{I.Const(S.Unit,I.UInt(0))})})
local functions={mutation,caller};functions.moduleData={I.ModuleData(root,bytes)}
local ok,err=pcall(Program.analyze,functions)
check(not ok and D.is(err) and err.code=='readonly-write','callee mutation cannot acquire readonly module permissions')
-- Borrow/callable metadata closes a cyclic holding graph over finite qualified
-- definitions. This is typing/analysis convergence only, not runtime qualification
-- of loop-carried frame-backed environments or their storage reuse.
local signature=S.Sig({}, {S.U32});local view=S.View(signature)
local constant=I.Fn('constant',I.Body,0,L{},L{S.U32},L{},L{I.Return(L{I.Const(S.U32,I.UInt(40))})})
local input,result=I.Value(1),I.Value(2)
local forwarded=I.Fn('forwarded',I.Body,1,L{S.inValue(view)},L{S.U32},L{I.ValueParam(0,input,view)},L{
 I.Indirect(L{result},I.Ref(input,view),L{}),I.Return(L{I.Ref(result,S.U32)})})
local initial,before,after=I.Value(1),I.Value(2),I.Value(3)
local cell,environment=I.Storage(1),I.Storage(2)
local cyclic=I.Fn('cyclic',I.Entry,0,L{},L{S.U32},L{},L{
 I.View(initial,view,'constant',L{},nil),I.Var(cell,view,I.Ref(initial,view)),
 I.Loop(L{I.Read(before,view,I.Local(cell)),
  I.View(after,view,'forwarded',L{I.ValueArg(I.Ref(before,view))},environment),
  I.Store(I.Local(cell),I.Ref(after,view)),I.Next})})
local cyclicProgram=Program.analyze({constant,forwarded,cyclic})
check(cyclicProgram.access.cyclic~=nil,'cyclic callable holding graph reaches a finite metadata fixed point')
-- Explicit unknown implementations do not manufacture returned borrow provenance.
local b=IR.builder();local value=b:valueId()
local foreign=I.Foreign('unknown',L{},L{S.Ref(S.U32)})
local unknown=I.Fn('unknown_result',I.Entry,0,L{},L{S.Ref(S.U32)},L{},L{I.Call(L{value},'unknown',L{}),I.Return(L{b:ref(value,S.Ref(S.U32))})})
ok,err=pcall(Program.analyze,{unknown},nil,{foreign})
check(not ok and D.is(err) and err.code=='borrow-proof','opaque result does not acquire a lifetime proof')
local opaqueView=S.View(S.Sig({}, {S.Ref(S.U32)}))
local callee,borrowed=I.Value(1),I.Value(2)
local indirect=I.Fn('opaque_indirect',I.Entry,0,L{},L{S.Ref(S.U32)},L{},L{
 I.View(callee,opaqueView,'unknown',L{},nil),I.Indirect(L{borrowed},I.Ref(callee,opaqueView),L{}),
 I.Return(L{I.Ref(borrowed,S.Ref(S.U32))})})
ok,err=pcall(Program.analyze,{indirect},nil,{foreign})
check(not ok and D.is(err) and err.code=='borrow-proof','concrete opaque view retains the missing-result proof, not a nonexistent signature field')
-- Loan origins cannot masquerade as footprint addresses. Symbolic targets are
-- explicit, and actual caller storage replaces them when summaries compose.
for _,fn in ipairs(safeHigher.functions) do
 local access=safeHigher.program.access[fn.id]
 for _,footprint in ipairs{access.reads,access.writes,access.writable} do
  for _,loc in ipairs(footprint.writes) do
   check(S.Borrow.Target:isclassof(loc.root),'footprint root is a target, not an owner loan')
   if loc.root.kind=='StorageRoot' then
    check(loc.root.storage.kind~='ValueInput' and loc.root.storage.kind~='CallOutput','owner-only sources cannot be physical storage')
   end
  end
 end
end
local borrowingForeign=I.Foreign('uncontracted',L{S.inValue(S.Ref(S.U32))},L{S.Unit})
local heldInput,ignored=I.Value(1),I.Value(2)
local opaqueBorrow=I.Fn('opaque_borrow',I.Entry,0,L{S.inValue(S.Ref(S.U32))},L{S.Unit},L{I.ValueParam(0,heldInput,S.Ref(S.U32))},L{
 I.Call(L{ignored},'uncontracted',L{I.ValueArg(I.Ref(heldInput,S.Ref(S.U32)))}),
 I.Return(L{I.Const(S.Unit,I.UInt(0))})})
ok,err=pcall(Program.analyze,{opaqueBorrow},nil,{borrowingForeign})
check(not ok and D.is(err) and err.code=='borrow-proof','opaque supplied borrow requires a retention contract')
-- Unknown target provenance remains unknown after a dereference/projection.
local nestedTy=S.Record{value=S.Ref(S.U32)}
local nestedForeign=I.Foreign('unknown_holder',L{},L{S.Ref(nestedTy)})
local pointer,field=I.Value(1),I.Value(2);local pointerCell=I.Storage(1)
local unknownField=I.Fn('unknown_field',I.Entry,0,L{},L{S.Ref(S.U32)},L{},L{
 I.Call(L{pointer},'unknown_holder',L{}),I.Var(pointerCell,S.Ref(nestedTy),I.Ref(pointer,S.Ref(nestedTy))),
 I.Read(field,S.Ref(S.U32),I.Project(I.Deref(I.Local(pointerCell),nestedTy),I.Field('value'))),
 I.Return(L{I.Ref(field,S.Ref(S.U32))})})
ok,err=pcall(Program.analyze,{unknownField},nil,{nestedForeign})
check(not ok and D.is(err) and err.code=='borrow-proof','unknown dereferenced field cannot acquire an owner proof')
-- A recursive unchecked pointer walk must converge without inventing an
-- unbounded owner-path family. It retains an explicitly unknown footprint.
local recursive=C.typed{profile='slet',source=[[
let walk(p: Ptr(U32), n: U32): Unit = do
 if n > 0 then p[0] = n return walk(Ptr(p[0]), n - 1) end
 return
end
let main(): U32 = 0
]]}
check(recursive.program.access[recursive.functions[1].id].writes.unknown,'unchecked pointer walk retains unknown effects')
print(('access proofs: %d checks, %d VM executions'):format(checks,executions))
