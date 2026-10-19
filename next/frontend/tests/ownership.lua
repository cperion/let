package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local S=require('let.schema')
local D=require('let.diag')
local Owner=require('let.ownership')
local checks=0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function reject(code,source,emit)
 for _,profile in ipairs{'slet','let'} do
  local ok,err=pcall(function()
   local unit=C.typed{profile=profile,source=source}
   if emit and profile=='slet' then return require('let.abc').lower(unit.program,{profile=profile,exports={'main'}}) end
  end)
  if not emit or profile=='slet' then check(not ok and D.is(err) and err.code==code,code..': '..tostring(err)) end
 end
end
check(not S.hasRc(S.Array(S.Rc(S.U32),0)),'zero-length arrays have no actual owning fields')
local prelude=[[
let Point = { x: U32 }
let Box = { child: Rc(Point) }
let leaf(n: U32): Rc(Point) = Rc(Point { x = n })
]]
for _,body in ipairs{
 'let bad(): Ref(Point) = do let r = leaf(1) return r.borrow() end',
 'let bad(r: Rc(Point)): Ref(Point) = r.borrow()',
 'let bad(): Ref(Point) = do let p = Point { x = 1 } return Ref(p) end',
 'let bad(p: Point): Ref(U32) = Ref(p.x)',
 'let bad(): Slice(U32) = do let r = Rc([1,2]) let p = r.borrow() return Slice(p) end',
} do reject('borrow-escape',prelude..body..' let main(): U32 = 0') end
for _,expression in ipairs{'Rc(Ref(p))','Rc(Slice(xs))','Rc([Ref(p)])'} do
 reject('Rc-payload',prelude..'let main(): U32 = do let p = Point { x = 1 } let xs = [1,2] let bad = '..expression..' return 0 end')
end
-- Borrow a holding, not an implicitly retained snapshot of its former target.
local invalidations={
 'p.child = leaf(2)',
 'replace(p)',
 'if n == 0 then p.child = leaf(2) end',
}
for _,mutation in ipairs(invalidations) do
 reject('borrow-invalidated',prelude..[[
 let replace(p: Ref(Box)): Unit = do p.child = leaf(2) return end
 let main(n: U32): U32 = do let root = Rc(Box { child = leaf(1) }) let p = root.borrow()
 let old = p.child.borrow()
 ]]..mutation..[[ return old.x end]])
end
reject('borrow-invalidated',prelude..[[
let main(n: U32): U32 = do let root = Rc([leaf(1),leaf(2)]) let p = root.borrow()
 let old = p[0].borrow() p[n] = leaf(3) return old.x end]])
-- Exact distinct fields/elements remain independent. Owned reads remain safe
-- snapshots regardless of later writes to the originating field.
for _,body in ipairs{
 [[let root = Rc(Box { child = leaf(n) }) let p = root.borrow() let saved = p.child
 p.child = leaf(n+1) let q = saved.borrow() return q.x]],
 [[let root = Rc([leaf(n),leaf(n+1)]) let p = root.borrow() let saved = p[0].borrow()
 p[1] = leaf(n+2) return saved.x]],
 [[let r = leaf(n) let copy = r let p = copy.borrow() return p.x]],
} do
 local unit=C.typed{profile='slet',source=prelude..'let main(n: U32): U32 = do '..body..' end'}
 check(unit.program~=nil,'valid explicit holding or disjoint-field borrow')
 local artifact=require('let.abc').lower(unit.program,{profile='slet',exports={'main'}})
 check(artifact.assembly:find('__let_rt_source_hold',1,true)~=nil,'semantic Rc copies acquire holdings')
 check(unit.program.flow==nil,'no obsolete contents-version/loan-demand publication')
end
local nodes=[[
let Node = { next: Link, value: U32 }
let Link = oneof { empty: Unit, node: Rc(Node) }
let leaf(): Rc(Node) = Rc(Node { next = Link.empty(), value = 42 })
]]
for _,mutation in ipairs{
 'let p = a.borrow() p.next = Link.node(a)',
 'let p = a.borrow() let q = b.borrow() p.next = Link.node(b) q.next = Link.node(a)',
 'link(a.borrow(),a)',
} do reject('Ref-cycle',nodes..[[
let link(p: Ref(Node), q: Rc(Node)): Unit = do p.next = Link.node(q) return end
let main(): U32 = do let a = leaf() let b = leaf()
]]..mutation..' return 0 end') end
local acyclic=C.typed{profile='slet',source=nodes..[[
let chain(n: U32): Rc(Node) = do if n == 0 then return leaf() end
 let child = chain(n-1) return Rc(Node { next = Link.node(child), value = n }) end
let main(n: U32): U32 = do let r = chain(n) let p = r.borrow() return p.value end
]]}
check(acyclic.program~=nil,'recursive fresh construction does not invent a cycle')
-- Named indirection is a type definition, not permission to borrow any layout.
do
 local I,L=S.Ir,S.List;local p,q=I.Value(1),I.Value(2)
 local payload=S.Record{x=S.U32};local rc=S.Rc(S.Named('test:payload'))
 local function named(target)
  local functions={I.Fn('named',I.Entry,0,L{S.inValue(rc)},L{S.U32},L{I.ValueParam(0,p,rc)},L{
   I.Let(q,S.Ref(target),I.RcBorrow(I.ValueArg(I.Ref(p,rc)),S.Ref(target))),I.Return(L{I.Const(S.U32,I.UInt(0))})})}
  functions.typeCells={['test:payload']=payload};return functions
 end
 check(require('let.program').analyze(named(payload))~=nil,'named Rc borrow resolves its actual payload')
 local ok,err=pcall(require('let.program').analyze,named(S.U64))
 check(not ok and D.is(err) and err.code=='ir-Rc','named Rc cannot be borrowed as an unrelated layout')
 local initial=I.Make(payload,L{I.Const(S.U32,I.UInt(0))});local root=I.Storage(1)
 local duplicate={I.Fn('duplicate_root',I.Entry,0,L{},L{S.U32},L{},L{
  I.Var(root,payload,initial),I.RcNew(p,root,S.Rc(payload),initial),I.Return(L{I.Const(S.U32,I.UInt(0))})})}
 ok,err=pcall(require('let.program').analyze,duplicate)
 check(not ok and D.is(err) and err.code=='ir-storage','Rc identities cannot collide with local storage')
end
-- Retain the iterative graph algorithm, not its former promotion-event wrapper.
local B,O,L=S.Borrow,S.Ownership,S.List
local edges,roots={},{}
for i=1,1500 do roots[i]=O.Fresh(B.Heap('graph',i,L{},false)) end
local activation=O.Activation('graph',L{},false)
for i=1,#roots-1 do edges[O.Edge(roots[i],roots[i+1],O.Site(B.Point('graph',i),activation))]=true end
check(Owner.strongCycle(edges)==nil,'long strong DAG checks iteratively')
edges[O.Edge(roots[#roots],roots[1],O.Site(B.Point('graph',#roots),activation))]=true
check(Owner.strongCycle(edges)~=nil,'long cycle rejected iteratively')
local pure=C.compile{profile='slet',source=[[
let Point = { x: U32 } let read(p: Ref(Point)): U32 = p.x
let main(): U32 = do let p = Point { x = 42 } return read(Ref(p)) end
]],exports={'main'}}
check(not pure.assembly:find('__let_rt_source_',1,true),'borrow-only code has no RC traffic or empty cleanup frame')
reject('Rc-interface',prelude..'let main(): Rc(Point) = leaf(1)',true)
reject('Rc-interface',prelude..[[let invoke(f: (): U32): U32 = f() let main(): U32 = do let r = leaf(1) let f: (): U32 = do() let p = r.borrow() return p.x end return invoke(f) end]],true)
reject('Rc-interface',prelude..[[let invoke(f: (U32): Rc(Point), n: U32): Rc(Point) = f(n) let main(): U32 = do let r = invoke(leaf,1) let p = r.borrow() return p.x end]],true)
for _,value in ipairs{'Ref(p)','Holder { value = Ref(p) }'} do
 local ok,err=pcall(C.typed,{profile='let',source=prelude..'let Holder = { value: Ref(Point) } let bad(): Any = do let p = Point { x = 1 } return '..value..' end let main(): U32 = 0'})
 check(not ok and D.is(err) and err.code=='borrow-escape','erasure cannot erase a borrow lifetime: '..tostring(err))
end
-- Query count is a structural regression check, not a wall-clock benchmark.
local loop=C.typed{profile='slet',source=prelude..[[
let parent(n: U32): Rc(Box) = Rc(Box { child = leaf(n) })
let main(n: U32): U32 = do
 let walk(i: U32, total: U32): U32 = do if i == n then return total end
 let root = parent(i) let p = root.borrow() let child = p.child let q = child.borrow()
 return walk(i+1,total+q.x) end
 return walk(0,0) end
]]}
check(loop.program.accessStats.contexts<40,'changing caller storage cannot multiply call-site bindings')
local diamond={'let f0(n: U32): U32 = n'}
for i=1,14 do diamond[#diamond+1]=('let f%d(n: U32): U32 = f%d(n)+f%d(n)'):format(i,i-1,i-1) end
diamond[#diamond+1]='let main(n: U32): U32 = f14(n)'
local scalar=C.typed{profile='slet',source=table.concat(diamond,'\n')}
check(scalar.program.accessStats.contexts==#scalar.functions,'scalar call diamonds have one check per function, not one per path')
check(Owner.capabilities==nil and Owner.reuseRequirements==nil and Owner.rootBindings==nil,'implicit ownership solver is absent')
print(('explicit ownership checking: %d checks; loop %d bindings / %d iterations'):format(checks,loop.program.accessStats.contexts,loop.program.accessStats.iterations))
