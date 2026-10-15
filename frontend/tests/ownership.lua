package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local S=require('let.schema')
local Program=require('let.program')
local Layout=require('let.layout')
local Owner=require('let.ownership')
local D=require('let.diag')
local I,B,O,L=S.Ir,S.Borrow,S.Ownership,S.List
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function reject(code,source,profiles)
 local last
 for _,profile in ipairs(profiles or {'slet','let'}) do
  local ok,err=pcall(function()
   local unit=C.typed{profile=profile,source=source,name='ownership.'..profile}
   return Layout.program(unit.program)
  end)
  check(not ok and D.is(err) and err.code==code,profile..'/'..code..': '..tostring(err))
  check(O.Summary:isclassof(err.ownership),'ownership rejection has canonical proof evidence')
  last=err
 end
 return last
end
local function summary(unit,id) return assert(unit.program.ownership[id]).summary end
local function run(source,wanted,profile)
 local unit=C.typed({profile=profile or 'slet',source=source,name='ownership.'..(profile or 'slet')},{staticMode='interpreted'})
 for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimize in ipairs{false,true} do
  local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
  executions=executions+1;check(tonumber(result.cells[1])==wanted,mode..'/'..tostring(optimize))
 end end
 return unit
end
local function cycle(err)
 check(err.witness and #err.witness>0,'cycle has edge/source witness')
 for i,e in ipairs(err.witness) do
  check(e.target==err.witness[i%#err.witness+1].holder,'witness is a closed actual-root path')
  local found=false;for _,edge in ipairs(err.ownership.edges) do if edge==e then found=true end end
  check(found,'witness edge is in inferred summary')
 end
end
local prelude=[[
let Point = { x: U32 }
let Box = { child: Point, saved: Ref(Point) }
]]
local bounded=run(prelude..[[
let main(): U32 = do
 let seed = Point { x = 1 }
 let p = Box { child = Point { x = 42 }, saved = Ref(seed) }
 p.saved = Ref(p.child)
 return p.saved.x
end
]],42)
local boundedSummary=summary(bounded,'main')
check(#boundedSummary.edges==0 and #boundedSummary.counted==0,'bounded self/interior access has no owning edge')
check(#boundedSummary.borrows>0,'bounded retention has independent activation evidence')
local self=reject('Ref-cycle',prelude..[[
let bad(seed: Ref(Point)): Ref(Box) = do
 let p = Box { child = Point { x = 42 }, saved = seed }
 p.saved = Ref(p.child)
 return Ref(p)
end
let main(): U32 = 0
]])
cycle(self)
check(#self.witness==1,'interior child retains containing root, not a separately promoted child')
-- Both concrete roots must be fresh per call, including when the factory is
-- reached through the same wrapper body. Neither type identity nor callee-local
-- storage ordinal is an owner identity.
local factories=prelude..[[
let make(seed: Ref(Point)): Ref(Box) = do
 let p = Box { child = Point { x = 42 }, saved = seed }
 return Ref(p)
end
let relay(seed: Ref(Point)): Ref(Box) = make(seed)
]]
for _,factory in ipairs{'make','relay'} do
 local linked=reject('Ref-cycle',factories..[[
let main(seed: Ref(Point)): Ref(Box) = do
 let a = ]]..factory..[[(seed)
 let b = ]]..factory..[[(seed)
 a.saved = Ref(b.child)
 b.saved = Ref(a.child)
 return a
end
]])
 cycle(linked)
 check(#linked.witness==2,'two factory calls produce two distinct owners')
 for _,e in ipairs(linked.witness) do
  check(e.holder.kind=='Fresh' and e.holder.source.kind=='Instantiated','caller binds a fresh-result owner variable')
  check(e.holder~=e.target,'distinct calls must not collapse into a type/self edge')
  check(#e.holder.source.context==(factory=='make' and 1 or 2),'nested call context is qualified')
 end
end
local alias=reject('Ref-cycle',factories..[[
let main(seed: Ref(Point)): Ref(Box) = do
 let a = make(seed)
 let alias = a
 alias.saved = Ref(a.child)
 return a
end
]])
cycle(alias);check(#alias.witness==1,'copying a reference preserves its actual owner')
local joined=reject('Ref-cycle',prelude..[[
let bad(seed: Ref(Point), choose: Bool): Ref(Box) = do
 let a = Box { child = Point { x = 1 }, saved = seed }
 let b = Box { child = Point { x = 2 }, saved = seed }
 if choose then a.saved = Ref(b.child) else b.saved = Ref(a.child) end
 return Ref(a)
end
let main(): U32 = 0
]])
cycle(joined);check(#joined.witness==2,'mutually exclusive strong edges are unioned, not path-selected')
-- Initializers and by-value record copies participate at their actual destination.
local copies=reject('borrow-return',prelude..[[
let Holder = { value: Ref(Point) }
let bad(): Ref(Holder) = do
 let p = Point { x = 42 }
 let original = Holder { value = Ref(p) }
 let copied = original
 return Ref(copied)
end
let main(): U32 = 0
]])
check(#copies.ownership.edges>0,'copy into counted destination creates owning dependency')
local counted={};for _,r in ipairs(copies.ownership.counted) do counted[r.root]=true end
for _,e in ipairs(copies.ownership.edges) do
 check(counted[e.holder] and counted[e.target],'counted copy recursively requires its retained root')
end
local closure=reject('Ref-cycle',[[
let Button = { value: U32, action: (): Unit }
let noop(): Unit = do return end
let bad(): Ref(Button) = do
 let button... = Button { value = 0, action = noop }
 let closure = do() value += 1 return end
 button.action = closure
 return Ref(button)
end
let main(): U32 = 0
]],{'let'})
cycle(closure)
check(#closure.witness==2,'button/environment cycle is two real holdings, not flattened capture self-edge')
local safeClosure=run([[
let Button = { value: U32, action: (): Unit }
let noop(): Unit = do return end
let main(): U32 = do
 let button... = Button { value = 40, action = noop }
 let closure = do() value += 1 return end
 button.action = closure
 button.action()
 button.action()
 return value
end
]],42,'let')
check(#summary(safeClosure,'main').counted==0,'bounded environment/button graph remains borrowed')
local put=run(prelude..[[
let put(holder: Ref(Box), value: Ref(Point)): Unit = do holder.saved = value return end
let forward(holder: Ref(Box), value: Ref(Point)): Unit = put(holder,value)
let main(): U32 = do
 let p = Point { x = 42 }
 let box = Box { child = Point { x = 0 }, saved = Ref(p) }
 forward(Ref(box),Ref(p))
 return box.saved.x
end
]],42)
local formal=summary(put,'put')
check(#formal.edges==1 and formal.edges[1].holder.kind=='Formal' and formal.edges[1].target.kind=='Formal',
 'generic summary exports formal owning inequality, not a type-reach test')
check(#summary(put,'main').edges==0,'actual bounded bindings discharge the generic retention inequality')
check(#summary(put,'forward').edges==1,'forwarding preserves the instantiated summary')
local selfLink=[[
let self_link(p: Ref(Box)): Unit = do p.saved = Ref(p.child) return end
]]
local boundedFormal=run(prelude..selfLink..[[
let main(): U32 = do
 let seed = Point { x = 1 }
 let box = Box { child = Point { x = 42 }, saved = Ref(seed) }
 self_link(Ref(box))
 return box.saved.x
end
]],42)
local conditional=summary(boundedFormal,'self_link').edges[1]
check(conditional and conditional.holder==conditional.target and conditional.holder.kind=='Formal',
 'formal-only self inequality remains conditional on the calling ownership specialization')
check(#summary(boundedFormal,'main').edges==0,'bounded actual root discharges conditional self inequality')
local owningFormal=reject('Ref-cycle',factories..selfLink..[[
let main(seed: Ref(Point)): Ref(Box) = do let p=make(seed) self_link(p) return p end
]])
cycle(owningFormal)
check(#owningFormal.witness==1,'counted actual binding cannot discharge the same self inequality')
local recursive=run(prelude..[[
let identity(p: Ref(Point), n: U32): Ref(Point) = do
 if n == 0 then return p end
 return identity(p,n-1)
end
let main(): U32 = do let p = Point { x = 42 } let r = identity(Ref(p),4) return r.x end
]],42)
check(#summary(recursive,'main').counted==0,'recursive forwarding preserves actual borrowed input root')
local growing=reject('Ref-cycle',[[
let Node = { next: Ref(Node), value: U32 }
let chain(seed: Ref(Node), n: U32): Ref(Node) = do
 if n == 0 then return seed end
 let next = chain(seed,n-1)
 let p = Node { next = next, value = n }
 return Ref(p)
end
let main(): U32 = 0
]])
cycle(growing)
check(growing.witness[1].holder.source.kind=='Recurring','unbounded recursive owning chain cannot invent indefinitely fresh ranks')
local module=run([[
let Point = { x: U32 }
let state = Point { x = 42 }
let expose(): Ref(Point) = Ref(state)
let main(): U32 = do let r = expose() return r.x end
]],42)
local moduleResult=summary(module,'expose').results[1].roots[1]
check(moduleResult.kind=='Module' and #summary(module,'expose').counted==0,'module roots require no count')
local raw=run([[
let Point = { x: U32 }
let main(): U32 = do
 let p = Point { x = 40 }
 let pointer = Ptr(p.x)
 pointer[0] += 2
 return p.x
end
]],42)
check(#summary(raw,'main').holdings==0,'raw pointers supply neither strong edges nor lifetime proof')
for _,profile in ipairs{'slet','let'} do
 local rawReturn=C.typed{profile=profile,source=[[
let Point = { x: U32 }
let unchecked(): Ptr(U32) = do let p = Point { x = 42 } return Ptr(p.x) end
let main(): U32 = 0
]]}
 local facts=summary(rawReturn,'unchecked')
 check(#facts.results==0 and #facts.counted==0,'raw pointer return must not export a checked owner loan')
end
-- A checked-IR factory also exercises reachable result-state transport: read an
-- address-bearing field of two independently instantiated roots after the calls.
local Point=S.Record{x=S.U32};local Holder=S.Record{value=S.Ref(Point)}
local input=I.Value(1);local local_=I.Storage(1)
local make=I.Fn('make_ir',I.Body,0,L{S.inValue(S.Ref(Point))},L{S.Ref(Holder)},
 L{I.ValueParam(0,input,S.Ref(Point))},L{
 I.Var(local_,Holder,I.Make(Holder,L{I.Ref(input,S.Ref(Point))})),
 I.Return(L{I.Addr(I.Local(local_),S.Ref(Holder),B.WriteAccess)})})
local x,y,ap,bp=I.Storage(1),I.Storage(2),I.Storage(3),I.Storage(4)
local av,bv,ar,br=I.Value(1),I.Value(2),I.Value(3),I.Value(4)
local function point(n) return I.Make(Point,L{I.Const(S.U32,I.UInt(n))}) end
local function address(s,ty) return I.Addr(I.Local(s),S.Ref(ty),B.WriteAccess) end
local caller=I.Fn('caller_ir',I.Entry,0,L{},L{S.Ref(Point),S.Ref(Point)},L{},L{
 I.Var(x,Point,point(1)),I.Var(y,Point,point(2)),
 I.Call(L{av},'make_ir',L{I.ValueArg(address(x,Point))}),I.Var(ap,S.Ref(Holder),I.Ref(av,S.Ref(Holder))),
 I.Call(L{bv},'make_ir',L{I.ValueArg(address(y,Point))}),I.Var(bp,S.Ref(Holder),I.Ref(bv,S.Ref(Holder))),
 I.Read(ar,S.Ref(Point),I.Project(I.Deref(I.Local(ap),Holder),I.Field('value'))),
 I.Read(br,S.Ref(Point),I.Project(I.Deref(I.Local(bp),Holder),I.Field('value'))),
 I.Return(L{I.Ref(ar,S.Ref(Point)),I.Ref(br,S.Ref(Point))})})
local program=Program.analyze({make,caller})
local ok,err=pcall(Layout.program,program)
check(not ok and err.code=='borrow-return','inference does not enable unimplemented counted ABI')
check(program.ownership.caller_ir~=nil and caller.ownership==nil,'the checked program owns summaries before placement rejection')
local results=program.ownership.caller_ir.summary.results
check(#results==2 and #results[1].roots==1 and #results[2].roots==1,'fresh root contents transport without cross-call contamination')
check(results[1].roots[1]~=results[2].roots[1],'two retained input roots remain distinct through factory fields')
for _,r in ipairs(results) do check(r.roots[1].source.kind=='Local' and r.roots[1].source.frame=='caller_ir','field reads recover actual caller roots') end
-- Nonrecursive graph depth must not become C/Lua host recursion depth. These
-- events use precisely the same solver as checked source; this is not the only
-- integration test for the graph helper.
local events=Owner.events();local roots={};local extent=O.Activation('long',L{},false)
for i=1,1200 do roots[i]=B.Local('long',i) end
Owner.returned(events,roots[1],O.Site(B.Point('long',1),extent))
for i=1,#roots-1 do Owner.hold(events,roots[i],roots[i+1],O.Site(B.Point('long',i+1),extent)) end
local summary,w=Owner.solve(events,L{},false)
check(not w and #summary.edges==1199,'long ownership DAG is solved iteratively')
local required={};for _,r in ipairs(summary.counted) do required[r.root]=true end
local n=0;for _ in pairs(required) do n=n+1 end
check(n==1200,'count requirements reach the end of the graph')
Owner.hold(events,roots[#roots],roots[1],O.Site(B.Point('long',1201),extent))
summary,w=Owner.solve(events,L{},false)
check(w and #w==1200,'long cycle has complete nonrecursive witness')
-- Recursive query convergence is not a borrow/lifetime proof. Folded names
-- can stand for distinct activations even when their frame/context fields match.
local point=B.Point('recursive',1)
local context,folded=Owner.context(L{point},point)
check(folded and #context==1,'repeated call site folds without a depth budget')
local recurring=Owner.events();local recursiveSite=O.Site(point,O.Activation('recursive',context,true))
local rh=Owner.localSource('recursive',1,context,true)
local rt=Owner.localSource('recursive',2,context,true)
Owner.hold(recurring,rh,rt,recursiveSite)
local recursiveSummary=Owner.solve(recurring,L{},false)
check(#recursiveSummary.borrows==0 and #recursiveSummary.counted>0,'equal recursive family extents cannot elide retention')
-- A formal-only DFS backedge must not conceal the larger concrete SCC.
local mixed=Owner.events();local site=O.Site(B.Point('mixed',1),O.Activation('mixed',L{},false))
local a,b,f=B.ValueInput('mixed',0,B.Root),B.ValueInput('mixed',1,B.Root),B.Local('mixed',1)
Owner.hold(mixed,a,b,site);Owner.hold(mixed,b,a,site);Owner.hold(mixed,a,f,site);Owner.hold(mixed,f,b,site)
summary,w=Owner.solve(mixed,L{},false)
check(w and #w==3,'SCC analysis finds concrete cycle beyond a formal-only backedge')
local reordered=Owner.events()
Owner.hold(reordered,f,b,site);Owner.hold(reordered,a,f,site);Owner.hold(reordered,b,a,site);Owner.hold(reordered,a,b,site)
local again=Owner.solve(reordered,L{},false)
check(summary==again,'summary sets canonicalize independently of event insertion order')
print(('ownership inference: %d checks, %d VM executions'):format(checks,executions))
