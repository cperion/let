package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C,D=require('let.compiler'),require('let.diag')
local checks,executions=0,0
local function check(ok,why) checks=checks+1;assert(ok,why) end
local prelude=[[
let Point = { x: U32 }
let nudge(p: Ref(Point), dx: U32): Unit = do p.x += dx return end
let shifted(p: Point, dx: U32): Point = do p.x += dx return p end
]]
local function execute(unit,wanted)
 for _,optimize in ipairs{false,true} do for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
  local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
  check(tonumber(result.cells[1])==wanted,mode..'/'..tostring(optimize)..': '..tostring(result.cells[1]));executions=executions+1
 end end
 return unit
end
local function run(source,wanted,prefix)
 return execute(C.typed{profile='slet',source=(prefix or prelude)..source,name='receiver-scope.slet'},wanted)
end
local function reject(code,source,prefix)
 local ok,err=pcall(C.typed,{profile='slet',source=(prefix or prelude)..source,name='receiver-reject.slet'})
 check(not ok and D.is(err) and err.code==code,code..': '..tostring(err))
end
run('let main(): U32 = do let p = Point { x = 40 } p.nudge(2) return p.x end',42)
run('let main(): U32 = do let p = Point { x = 40 } nudge(Ref(p), 2) return p.x end',42)
run('let main(): U32 = do let p = Point { x = 40 } let r = Ref(p) r.nudge(2) return p.x end',42)
reject('type-mismatch','let main(): U32 = do let p = Point { x = 40 } nudge(p, 2) return p.x end')
reject('receiver-temporary','let make(): Point = Point { x = 40 }; let main(): U32 = do make().nudge(2) return 0 end')
run('let main(): U32 = do let p = Point { x = 40 } let q = p.shifted(2) return p.x + q.x end',82)
run('let main(): U32 = do let p = Point { x = 40 } let p... nudge 2 return p.x + x end',84)
run('let main(): U32 = do let p = Point { x = 40 } let r... = Ref(p) nudge 2 return p.x + x end',84)
run([[
let apply(p: Ref(Point), body: (Ref(Point)): U32): U32 = body(p)
let main(): U32 = do let p = Point { x = 40 } return apply(Ref(p)) do(ctx...) nudge 2 return ctx.x end end
]],42)
run([[
let apply(p: Point, body: (Point): U32): U32 = body(p)
let main(): U32 = do let p = Point { x = 40 } let answer = apply(p) do(ctx...) nudge 2 return ctx.x end return answer + p.x end
]],82)
run([[
let helper(x: U32): U32 = x + 2
let main(): U32 = do let p = Point { x = 0 } let p... return (helper)(40) end
]],42)
reject('type-mismatch',[[
let helper(x: U32): U32 = x + 2
let main(): U32 = do let p = Point { x = 0 } let p... return helper(40) end
]])
run([[
let helper(x: U32): U32 = x + 2
let main(): U32 = do let p = Point { x = 0 } let p... let local_helper = helper return local_helper(40) end
]],42)
run([[
let main(): U32 = do let p = Point { x = 40 } let p... let nested() = do nudge 2 return end nested() return p.x end
]],42)
run([[
let main(): U32 = do let p = Point { x = 40 } let p... let nested = do() nudge 2 return end nested() return p.x end
]],42)
run([[
let main(): U32 = do let p = Point { x = 40 } let p... defer nudge(2) return p.x end
]],40)
run([[
let Point = { x: U32, nudge(dx: U32): U32 = do x += dx return x end }
let nudge(p: Point, dx: U32): U32 = 999
let main(): U32 = do let p = Point { x = 40 } return p.nudge(2) end
]],42,'')
run([[
let Point = { x: U32, nudge(dx: U32): U32 = do x += dx return x end }
let main(): U32 = do let p = Point { x = 40 } let p... return nudge(2) end
]],42,'')
reject('type-mismatch',[[
let Point = { nudge: U32 }
let nudge(p: Point, dx: U32): U32 = 42
let main(): U32 = do let p = Point { nudge = 0 } return p.nudge(2) end
]],'')
run([[
let change(p: Ref(Point)): U32 = do p.x = 50 return 2 end
let main(): U32 = do let p = Point { x = 40 } let q = p.shifted(change(Ref(p))) return q.x + p.x end
]],92)
run([[
let change(p: Ref(Point)): U32 = do p.x = 50 return 2 end
let main(): U32 = do let p = Point { x = 40 } p.nudge(change(Ref(p))) return p.x end
]],52)
run('let main(): U32 = do let p = Point { x = 40 } p.nudge()(2) return p.x end',42)
run([[
let Index = { n: U32, next(): U32 = do let old = n n += 1 return old end }
let main(): U32 = do let values = [Point { x = 40 }, Point { x = 90 }] let index = Index { n = 0 } values[index.next()].nudge(2) return values[0].x + index.n end
]],43)
run([[
let Holder = { point: Point }
let Index = { n: U32, next(): U32 = do let old = n n += 1 return old end }
let main(): U32 = do let values = [Holder { point = Point { x = 40 } }] let index = Index { n = 0 } values[index.next()].point.nudge(2) return values[0].point.x + index.n end
]],43)
run([[
let Point = { x: U32, answer(): U32 = x }
let Other = { y: U32, answer(): U32 = y }
let main(): U32 = do let p = Point { x = 40 } let p... let q = Other { y = 42 } let q... return answer() end
]],42,'')
reject('unknown-name',[[
let Point = { x: U32, answer(): U32 = x }
let Other = { y: U32 }
let main(): U32 = do let p = Point { x = 40 } let p... let q = Other { y = 42 } let q... return answer() end
]],'')
reject('arity',[[
let Point = { x: U32, nudge(): U32 = x }
let nudge(p: Point, dx: U32): U32 = 42
let main(): U32 = do let p = Point { x = 40 } return p.nudge(2) end
]],'')
reject('slet-forbidden',[[
let make(p: Ref(Point)) = do let p... return do() nudge 2 return end end
let main(): U32 = do let p = Point { x = 40 } let f = make(Ref(p)) f() return p.x end
]])
-- Merely defining a word inside a receiver scope must not capture that receiver.
run([[
let make(p: Ref(Point)) = do let p... return do() = 42 end
let main(): U32 = do let p = Point { x = 0 } let f = make(Ref(p)) return f() end
]],42)
run([[
let main(): U32 = do let p = Point { x = 40 } let p... let nested() = do let deeper() = do nudge 2 return end deeper() return end nested() return p.x end
]],42)
reject('borrow-return',[[
let identity(p: Ref(Point)): Ref(Point) = p
let main(): Ref(Point) = do let p = Point { x = 40 } return p.identity() end
]])
local function assembly(call)
 local unit=C.typed{profile='slet',source=prelude..'let main(): U32 = do let p = Point { x = 40 } '..call..' return p.x end'}
 return C.lower(unit.functions,{profile='slet'}).assembly
end
check(assembly('p.nudge(2)')==assembly('nudge(Ref(p), 2)'), 'lifted receiver uses identical ABC to explicit reference supply')
-- Capture selection follows the selected binding, not the dotted spelling.
run([[
let main(): U32 = do let n = 2 let addition = do(p: U32): U32 = p + n let nested(): U32 = 40.addition() return nested() end
]],42)
run([[
let Holder = { value: U32, addition(): U32 = value }
let main(): U32 = do let n = 2 let addition = do(p: U32): U32 = p + n let make() = do(r: Holder): U32 = r.addition() let word = make() return word(Holder { value = 42 }) end
]],42,'')
local deduplicated=run([[
let main(): U32 = do let n = 20 let add(x: U32): U32 = x + n let both(): U32 = add(n + 2) return both() end
]],42)
local last=deduplicated.functions[#deduplicated.functions]
check(last.hidden==1,'direct and callable-held uses share one captured holding')
-- An early recursive call must receive captures discovered later in the body.
run([[
let main(): U32 = do let n = 42 let recur(k: U32): U32 = do if k > 0 then return recur(k - 1) end return n end return recur(3) end
]],42)
run([[
let main(): U32 = do let n = 42 let recur(k: U32): U32 = do let step(v: U32): U32 = recur(v) if k > 0 then return step(k - 1) end return n end return recur(3) end
]],42)
run([[
let main(): U32 = do let n = 42 let recur(k: U32): U32 = do let step(v: U32): U32 = do let again(w: U32): U32 = recur(w) return again(v) end if k > 0 then return step(k - 1) end return n end return recur(3) end
]],42)
run([[
let main(): U32 = do let p = Point { x = 40 } let p... let recur(k: U32): U32 = do if k > 0 then return recur(k - 1) end nudge 2 return p.x end return recur(3) end
]],42)
run([[
let main(): U32 = do let p = Point { x = 38 } let p... let recur(k: U32): Unit = do if k > 0 then defer recur(k - 1) end nudge 1 return end recur(3) return p.x end
]],42)
run([[
let action(p: Ref(Point)): Unit = do let p... defer nudge 2 return end
let main(): U32 = do let p = Point { x = 40 } action(Ref(p)) return p.x end
]],42)
-- Reference captures snapshot the reference at word formation, not invocation.
run([[
let main(): U32 = do let p = Point { x = 42 } let q = Point { x = 90 } let r = Ref(p) let recur(k: U32): U32 = do if k > 0 then return recur(k - 1) end return r.x end r = Ref(q) return recur(3) end
]],42)
reject('slet-forbidden',[[
let Holder = { action: (U32): U32 }
let main(): U32 = do let n = 42 let recur(k: U32): U32 = do let step(v: U32): U32 = recur(v) let holder = Holder { action = step } if k > 0 then return holder.action(k - 1) end return n end return recur(3) end
]],'')
reject('static-cycle',[[
let add(a: U32, b: U32): U32 = a + b
let main(): U32 = do let recur(k: U32): U32 = do let bound = add(recur(0)) return bound(k) end return recur(1) end
]],'')
-- Existing managed-front-end admission of local environments must finalize a
-- late recursive capture before choosing adapter layout. These bodies use only
-- typed IR and do not return an environment or require dynamic lowering.
execute(C.typed{profile='let',source=[[
let Holder = { action: (U32): U32 }
let main(): U32 = do let n = 40 let recur(k: U32, dx: U32): U32 = do let holder = Holder { action = recur(0) } if k > 0 then return holder.action(2) end return n + dx end return recur(1, 0) end
]]},42)
execute(C.typed{profile='let',source=[[
let Holder = { action: (U32): U32 }
let main(): U32 = do let n = 42 let recur(k: U32): U32 = do let step(v: U32): U32 = recur(v) let holder = Holder { action = step } if k > 0 then return holder.action(k - 1) end return n end return recur(3) end
]]},42)
-- A locally opened scope replaces the inherited receiver; it need not capture it.
run([[
let Other = { y: U32, answer(): U32 = y }
let make(p: Point) = do let p... return do() let q... = Other { y = 42 } return answer() end end
let main(): U32 = do let word = make(Point { x = 0 }) return word() end
]],42)
print(('receiver scopes before imports: %d checks, %d VM executions'):format(checks,executions));io.stdout:flush()
local directory=os.tmpname();os.remove(directory);assert(os.execute('mkdir -p '..directory)==0)
local function file(name,source)
 local handle=assert(io.open(directory..'/'..name..'.slet','w'));handle:write(source);handle:close()
end
file('library','let inc(n: U32): U32 = n + 1; return { functions = { inc } }')
file('main',[[
use library
let Context = { amount: U32 }
let main(): U32 = do let ctx = Context { amount = 41 } let ctx... return library.inc(amount) end
]])
execute(C.typedFile(directory..'/main.slet'),42)
file('main','use library...; let main(): U32 = 41.inc()')
execute(C.typedFile(directory..'/main.slet'),42)
file('main','use library; let main(): U32 = 41.inc()')
local imported,importError=pcall(C.typedFile,directory..'/main.slet')
check(not imported and D.is(importError) and importError.code=='unknown-name','namespace import does not install lexical receiver words')
os.remove(directory..'/main.slet');os.remove(directory..'/library.slet');assert(os.execute('rmdir '..directory)==0)
local ok,dynamic=pcall(C.typed,{profile='let',source=[[
let nudge(p: Any, dx: Any): Any = 42
let main(p: Any): Any = p.nudge(2)
]],name='dynamic-receiver.let'})
check(ok,'dynamic member route remains valid: '..tostring(dynamic))
local operations={}
require('let.walk').walk(dynamic.functions[2],{enter=function(node) if node.kind then operations[node.kind]=true end end})
check(operations.WordGet and operations.Indirect,'dynamic receiver must use member lookup and dynamic invocation')
-- Completion waits for bodies, including finite dependency cycles, and never
-- reports an open component as ready because a recursive edge was encountered.
local Source=require('let.source_state')
local first,second=Source.capturePlan(),Source.capturePlan()
local left,right=Source.captureStream(first),Source.captureStream(second)
Source.followCaptures(left,right,function() end)
Source.followCaptures(right,left,function() end)
local completed,completionOrder=0,{}
Source.whenCapturesClosed({captures=left},function() check(first.closed and second.closed,'capture component published atomically');completed=completed+1;completionOrder[#completionOrder+1]='first' end)
Source.whenCapturesClosed({captures=right},function() completionOrder[#completionOrder+1]='second' end)
Source.finishCaptures(first)
check(not first.closed and completed==0,'unfinished recursive capture dependency waits')
Source.finishCaptures(second)
check(first.closed and second.closed and completed==1,'capture cycle closes once all bodies finish')
check(table.concat(completionOrder,',')=='second,first','capture completion follows stable dependency order')
-- Live opening: scalar projections remain places across writes and captures.
run('let main(): U32 = do let p = Point { x = 40 } let p... x += 2 return p.x end',42)
run('let main(): U32 = do let p = Point { x = 40 } let p... let saved = x x += 2 return saved + x end',82)
local liveCapture=run([[
let main(): U32 = do
 let p = Point { x = 40 } let p...
 let observe(): U32 = x
 p.x = 42
 return observe()
end
]],42)
local foundPlace=false
for _,fn in ipairs(liveCapture.functions) do
 for _,input in ipairs(fn.inputs) do if input.kind=='InPlace' then foundPlace=true end end
end
check(foundPlace,'opened scalar capture uses existing place transport, not a value snapshot')
run([[
let main(): U32 = do
 let p = Point { x = 40 } let p...
 let change(): Unit = do let deeper(): Unit = do x += 2 return end deeper() return end
 change() return p.x
end
]],42)
run([[
let main(): U32 = do
 let p = Point { x = 40 } let p... let saved = x
 let observe(): U32 = saved + x
 p.x = 42 return observe()
end
]],82)
run([[
let main(): U32 = do
 let p = Point { x = 38 } let p...
 let recur(n: U32): U32 = do if n > 0 then x += 1 return recur(n - 1) end return x end
 return recur(4)
end
]],42)
run([[
let copied(ctx...: Point): U32 = do x += 2 return x end
let borrowed(ctx...: Ref(Point)): U32 = do x += 2 return x end
let main(): U32 = do let p = Point { x = 40 } let ignored = copied(p) return borrowed(Ref(p)) + p.x end
]],84)
run([[
let Context = { child: Point }
let main(): U32 = do
 let ctx = Context { child = Point { x = 40 } } let ctx...
 let use_child(): U32 = do
  let saved = child
  child.x += 2
  return saved.x + child.x
 end
 return use_child()
end
]],82)
run([[
let Context = { action: (U32): U32 }
let first(n: U32): U32 = n + 1
let second(n: U32): U32 = n + 2
let main(): U32 = do
 let ctx = Context { action = first } let ctx...
 let invoke(): U32 = action(40)
 ctx.action = second
 return invoke()
end
]],42,'')
run([[
let Context = { target: Ref(Point) }
let main(): U32 = do
 let p = Point { x = 40 } let q = Point { x = 42 }
 let ctx = Context { target = Ref(p) } let ctx...
 let saved = target
 let observe(): U32 = target.x + saved.x
 ctx.target = Ref(q)
 return observe()
end
]],82)
reject('slet-forbidden','let make(p: Ref(Point)) = do let p... return do() = x end let main(): U32 = 0')
check(assembly('let p... x += 2')==assembly('p.x += 2'),'opened field write produces identical ABC to qualified access')
check(assembly('let p...')==assembly(''),'unused opening emits no field reads or copies')
print(('receiver scopes: %d checks, %d VM executions'):format(checks,executions))
