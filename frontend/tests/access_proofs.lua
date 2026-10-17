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
-- Original-site lifetime publication: versions describe contents, not root
-- identity. The saved SSA read survives a replacement of its source slot.
do
 local B,T=S.Borrow,S.Lifetime
 local p,q,flag,saved,current=I.Value(1),I.Value(2),I.Value(3),I.Value(4),I.Value(5)
 local slot=I.Storage(1);local ref=S.Ref(S.U32)
 local initialize=I.Var(slot,ref,I.Ref(p,ref))
 local snapshot=I.Read(saved,ref,I.Local(slot))
 local trap=I.Trap(I.Const(S.Bool,I.Boolean(false)),'unreachable failure')
 local replacement=I.Store(I.Local(slot),I.Ref(q,ref))
 local branch=I.If(I.Ref(flag,S.Bool),L{replacement},L{})
 local reread=I.Read(current,ref,I.Local(slot))
 local ret=I.Return(L{I.Ref(saved,ref),I.Ref(current,ref)})
 local fn=I.Fn('versions',I.Entry,0,L{S.inValue(ref),S.inValue(ref),S.inValue(S.Bool)},L{ref,ref},
  L{I.ValueParam(0,p,ref),I.ValueParam(1,q,ref),I.ValueParam(2,flag,S.Bool)},
  L{initialize,snapshot,trap,branch,reread,ret})
 local program=Program.analyze{fn};local flow=program.flow
 local graph=flow.functions.versions;local facts=flow.contexts[flow.roots.versions]
 local template=program.ownership.versions.lifetime_template.contexts[flow.roots.versions]
 local function point(n) return B.Point('versions',n) end
 local loc=B.Location(B.StorageRoot(B.Local('versions',1)),B.Root)
 check(graph.statement_at[point(2)]==snapshot and graph.statement_at[point(5)]==replacement,'flow refers to original source nodes')
 check(graph.nodes[point(3)].next[1]==point(4),'false trap preserves the normal successor')
 check(facts.sites[point(7)]~=nil,'post-trap uses are published after convergence')
 check(facts.contents_versions.before[point(2)][loc]==T.Written(point(1),loc),'snapshot reads the original contents version')
 check(facts.sites[point(5)].invalidates[loc]==T.Written(point(1),loc),'replacement kills the preceding contents')
 local joined=facts.contents_versions.before[point(6)][loc]
 check(joined==T.Join(point(6),loc),'branch joins have finite source-site version identities')
 local incoming=facts.contents_versions.incoming[joined]
 check(incoming[T.Written(point(1),loc)] and incoming[T.Written(point(5),loc)],'join retains both incoming versions')
 check(template.live_out[point(5)][T.Defined(point(2),saved.id,B.Root)],'saved read remains live across replacement')
 check(not template.live_in[point(2)][T.Defined(point(2),saved.id,B.Root)],'definition kills its own outgoing loan demand')
 check(template.live_out[point(5)][T.Contents(T.Written(point(5),loc))],'owning edge carries its own version demand')
 check(not template.live_out[point(5)][T.Contents(T.Written(point(1),loc))],'join does not assign the other edge witness to a writing edge')
 for _,site in pairs(facts.sites) do for id in pairs(site.uses) do
  check(graph.operands[id.point][id.operand]~=nil,'every carrier use retains its original operand')
 end end
 for _,holding in ipairs(program.ownership.versions.summary.holdings) do
  check(holding.destination==loc,'source retention includes the actual destination component')
 end
 local dynamicTrap=I.Fn('dynamic_trap',I.Entry,0,L{S.inValue(S.Bool),S.inValue(ref)},L{ref},
  L{I.ValueParam(0,flag,S.Bool),I.ValueParam(1,p,ref)},
  L{I.Trap(I.Ref(flag,S.Bool),'conditional'),I.Return(L{I.Ref(p,ref)})})
 local dynamicProgram=Program.analyze{dynamicTrap}
 check(#dynamicProgram.flow.functions.dynamic_trap.nodes[B.Point('dynamic_trap',1)].next==1,'unknown conditional trap has a success edge')
 local fatal=I.Fn('fatal',I.Entry,0,L{S.inValue(ref)},L{ref},L{I.ValueParam(0,p,ref)},
  L{I.Trap(I.Const(S.Bool,I.Boolean(true)),'always'),I.Return(L{I.Ref(p,ref)})})
 local dead=Program.analyze{fatal};local deadFacts=dead.flow.contexts[dead.flow.roots.fatal]
 check(deadFacts.sites[B.Point('fatal',2)]==nil,'always-true trap has no normal continuation')
 -- A write on a loop backedge remains a kill on every occurrence. The Join
 -- edges may be cyclic; the interned Version itself is never recursive.
 local loopStore=I.Store(I.Local(slot),I.Ref(q,ref))
 local loopRead=I.Read(saved,ref,I.Local(slot))
 local loop=I.Fn('versions_loop',I.Entry,0,L{S.inValue(ref),S.inValue(ref)},L{},
  L{I.ValueParam(0,p,ref),I.ValueParam(1,q,ref)},
  L{initialize,I.Loop(L{loopRead,loopStore,I.Next})})
 local loopProgram=Program.analyze{loop};local loopFacts=loopProgram.flow.contexts[loopProgram.flow.roots.versions_loop]
 local loopLoc=B.Location(B.StorageRoot(B.Local('versions_loop',1)),B.Root)
 local loopPoint=B.Point('versions_loop',2);local writePoint=B.Point('versions_loop',4)
 local loopVersion=loopFacts.contents_versions.before[loopPoint][loopLoc]
 check(loopVersion==T.Join(loopPoint,loopLoc),'loop-carried contents use one finite join')
 check(loopFacts.sites[writePoint].invalidates[loopLoc]==loopVersion,'loop write invalidates the preceding iteration')
 check(loopFacts.contents_versions.incoming[loopVersion][T.Written(writePoint,loopLoc)],'backedge carries the write version')
 -- Scalar loads through a reference still demand protection of its root.
 local derefCell=I.Storage(2);local scalar=I.Value(6)
 local deref=I.Fn('scalar_access',I.Entry,0,L{S.inValue(ref)},L{S.U32},L{I.ValueParam(0,p,ref)},L{
  I.Var(derefCell,ref,I.Ref(p,ref)),I.Read(scalar,S.U32,I.Deref(I.Local(derefCell),S.U32)),I.Return(L{I.Ref(scalar,S.U32)})})
 local scalarProgram=Program.analyze{deref};local scalarFacts=scalarProgram.flow.contexts[scalarProgram.flow.roots.scalar_access]
 local scalarSite=scalarFacts.sites[B.Point('scalar_access',2)]
 check(next(scalarSite.contents)~=nil and next(scalarSite.root_uses)~=nil,'scalar dereference keeps contents and containing-root demands')
 local scalarOnly=I.Fn('scalar_only',I.Entry,0,L{},L{S.U32},L{},L{I.Return(L{I.Const(S.U32,I.UInt(42))})})
 local scalarOnlyProgram=Program.analyze{scalarOnly}
 local scalarTemplates=scalarOnlyProgram.ownership.scalar_only.lifetime_template
 check(scalarTemplates.contexts[scalarTemplates.entry].empty,'scalar-only function has an empty lifetime template')
 check(fn.access==nil and fn.ownership==nil and fn.flow==nil,'flow and liveness are owned by the checked program')
 local direct=I.Fn('direct_address',I.Entry,0,L{},L{ref},L{},L{
  I.Var(slot,S.U32,I.Const(S.U32,I.UInt(42))),I.Return(L{I.Addr(I.Local(slot),ref,B.WriteAccess)})})
 local directProgram=Program.analyze{direct};local directTemplate=directProgram.ownership.direct_address.lifetime_template
 local directFacts=directTemplate.contexts[directTemplate.entry]
 local directRoot=S.Ownership.Fresh(B.Local('direct_address',slot.id))
 check(not directFacts.empty and directFacts.root_live_out[B.Point('direct_address',1)][directRoot],'direct address result demands the allocation root without an intermediate SSA carrier')
 check(not directFacts.root_live_in[B.Point('direct_address',1)][directRoot],'allocation defines its root demand')
 -- Distinct results at one Call are distinct loans even when their types and
 -- component paths coincide. Root equality is not a source-binding identity.
 local pair=I.Fn('pair_loans',I.Body,0,L{S.inValue(ref),S.inValue(ref)},L{ref,ref},
  L{I.ValueParam(0,p,ref),I.ValueParam(1,q,ref)},L{I.Return(L{I.Ref(p,ref),I.Ref(q,ref)})})
 local pairCall=I.Fn('pair_caller',I.Entry,0,L{S.inValue(ref),S.inValue(ref)},L{ref,ref},
  L{I.ValueParam(0,p,ref),I.ValueParam(1,q,ref)},L{
   I.Call(L{saved,current},'pair_loans',L{I.ValueArg(I.Ref(p,ref)),I.ValueArg(I.Ref(q,ref))}),
   I.Return(L{I.Ref(saved,ref),I.Ref(current,ref)})})
 local pairsProgram=Program.analyze{pair,pairCall};local pairsTemplate=pairsProgram.ownership.pair_caller.lifetime_template
 local outgoing=pairsTemplate.contexts[pairsTemplate.entry].live_out[B.Point('pair_caller',1)]
 check(outgoing[T.Defined(B.Point('pair_caller',1),saved.id,B.Root)] and outgoing[T.Defined(B.Point('pair_caller',1),current.id,B.Root)],'same-site call results retain separate loan IDs')
 -- Effects of a bound call invalidate the caller's actual field, not a
 -- callee-formal placeholder. Publication contains IDs, not query objects.
 local formalSlot=I.Storage(9);local ignored=I.Value(9)
 local replace=I.Fn('replace_loan',I.Body,0,L{S.inPlace(ref),S.inValue(ref)},L{S.Unit},
  L{I.PlaceParam(0,formalSlot,ref),I.ValueParam(1,q,ref)},L{
   I.Store(I.Local(formalSlot),I.Ref(q,ref)),I.Return(L{I.Const(S.Unit,I.UInt(0))})})
 local mutation=I.Fn('mutation',I.Entry,0,L{S.inValue(ref),S.inValue(ref)},L{ref,ref},
  L{I.ValueParam(0,p,ref),I.ValueParam(1,q,ref)},L{initialize,snapshot,
   I.Call(L{ignored},'replace_loan',L{I.BorrowArg(I.Local(slot)),I.ValueArg(I.Ref(q,ref))}),reread,ret})
 local mutationProgram=Program.analyze{replace,mutation}
 local mutationFacts=mutationProgram.flow.contexts[mutationProgram.flow.roots.mutation]
 local callPoint=B.Point('mutation',3)
 local mutationLoc=B.Location(B.StorageRoot(B.Local('mutation',slot.id)),B.Root)
 check(mutationFacts.sites[callPoint].invalidates[mutationLoc]==T.Written(B.Point('mutation',1),mutationLoc),'bound call kills actual caller contents')
 local calleeId=next(mutationFacts.call_edges[callPoint])
 check(calleeId and mutationFacts.call_edges[callPoint][calleeId]==true and mutationProgram.flow.contexts[calleeId].fn_id=='replace_loan','call edge identifies the converged child context')
 -- A runtime index can itself use a slice carrier. Preserve both that demand
 -- and the exact original place/index for later address capture, not a reread.
 local xs=I.Storage(3);local view=I.Value(7);local item=I.Value(8)
 local index=I.SliceLength(I.Ref(view,S.Slice(S.U32)),S.U32)
 local indexed=I.Index(I.Local(xs),index,S.U32)
 local array=S.Array(S.U32,2)
 local indexing=I.Fn('indexing',I.Entry,0,L{S.inValue(S.Slice(S.U32))},L{S.U32},
  L{I.ValueParam(0,view,S.Slice(S.U32))},L{
   I.Var(xs,array,I.Make(array,L{I.Const(S.U32,I.UInt(1)),I.Const(S.U32,I.UInt(2))})),
   I.Read(item,S.U32,indexed),I.Return(L{I.Ref(item,S.U32)})})
 local indexingProgram=Program.analyze{indexing}
 local indexPoint=B.Point('indexing',2);local indexFacts=indexingProgram.flow.contexts[indexingProgram.flow.roots.indexing]
 local indexTemplate=indexingProgram.ownership.indexing.lifetime_template
 check(indexTemplate.contexts[indexTemplate.entry].live_in[indexPoint][T.Parameter('indexing',0,B.Root)],'dynamic index carrier demand remains live')
 local original=indexingProgram.flow.functions.indexing.operands[indexPoint]
 local found=false;for _,operand in ipairs(original) do if operand==indexed and operand.index==index then found=true end end
 check(found,'indexed locator retains the exact original place and index')
 -- Keep each read alternative tied to its own field; a union of guards cannot
 -- certify every alternative on every path.
 local holder=S.Record{value=ref};local left,right,choice=I.Storage(11),I.Storage(12),I.Storage(13)
 local holderRef=S.Ref(holder)
 local function addr(storage) return I.Addr(I.Local(storage),holderRef,B.WriteAccess) end
 local alternatives=I.Fn('read_alternatives',I.Entry,0,L{S.inValue(ref),S.inValue(ref),S.inValue(S.Bool)},L{ref},
  L{I.ValueParam(0,p,ref),I.ValueParam(1,q,ref),I.ValueParam(2,flag,S.Bool)},L{
   I.Var(left,holder,I.Make(holder,L{I.Ref(p,ref)})),I.Var(right,holder,I.Make(holder,L{I.Ref(q,ref)})),
   I.Var(choice,holderRef,addr(left)),I.If(I.Ref(flag,S.Bool),L{I.Store(I.Local(choice),addr(right))},L{}),
   I.Read(saved,ref,I.Project(I.Deref(I.Local(choice),holder),I.Field('value'))),I.Return(L{I.Ref(saved,ref)})})
 local alternativesProgram=Program.analyze{alternatives}
 local alternativesFacts=alternativesProgram.flow.contexts[alternativesProgram.flow.roots.read_alternatives]
 local leftLoc=B.Location(B.StorageRoot(B.Local('read_alternatives',left.id)),B.Field(B.Root,'value'))
 local rightLoc=B.Location(B.StorageRoot(B.Local('read_alternatives',right.id)),B.Field(B.Root,'value'))
 local located
 for _,use in pairs(alternativesFacts.sites[B.Point('read_alternatives',6)].contents) do
  if use.locations[leftLoc] then located=use end
 end
 check(located and located.locations[rightLoc],'selected read keeps both possible protecting field locations')
 for _,alternative in pairs(located.alternatives[leftLoc]) do
  check(alternative.source==B.ValueInput('read_alternatives',0,B.Root),'left field keeps only its own referent provenance')
 end
 for _,alternative in pairs(located.alternatives[rightLoc]) do
  check(alternative.source==B.ValueInput('read_alternatives',1,B.Root),'right field keeps only its own referent provenance')
 end
 -- A false trap cannot hide the later escaping source self-cycle.
 local box=S.Record{child=S.U32,saved=ref};local boxSlot=I.Storage(20)
 local childPlace=I.Project(I.Local(boxSlot),I.Field('child'))
 local cyclic=I.Fn('cycle_after_trap',I.Entry,0,L{S.inValue(ref)},L{S.Ref(box)},L{I.ValueParam(0,p,ref)},L{
  I.Var(boxSlot,box,I.Make(box,L{I.Const(S.U32,I.UInt(1)),I.Ref(p,ref)})),trap,
  I.Store(I.Project(I.Local(boxSlot),I.Field('saved')),I.Addr(childPlace,ref,B.WriteAccess)),
  I.Return(L{I.Addr(I.Local(boxSlot),S.Ref(box),B.WriteAccess)})})
 local cycleOK,cycleError=pcall(Program.analyze,{cyclic})
 check(not cycleOK and D.is(cycleError) and cycleError.code=='Ref-cycle','post-trap owning cycle is still rejected')
 local ptr=S.Ptr(S.U32)
 local raw=I.Fn('raw_transport',I.Entry,0,L{S.inValue(ptr)},L{ptr},L{I.ValueParam(0,p,ptr)},L{
  I.Var(slot,ptr,I.Ref(p,ptr)),I.Read(saved,ptr,I.Local(slot)),I.Return(L{I.Ref(saved,ptr)})})
 local rawProgram=Program.analyze{raw};local rawTemplate=rawProgram.ownership.raw_transport.lifetime_template
 check(rawTemplate.contexts[rawTemplate.entry].empty,'raw pointer contents do not become checked lifetime loans')
end
print(('access proofs: %d checks, %d VM executions'):format(checks,executions))
