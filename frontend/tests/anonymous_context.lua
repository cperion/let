package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C,D,P,S,Walk=require('let.compiler'),require('let.diag'),require('let.parse'),require('let.schema'),require('let.walk')
local checks,executions,unoptimizedProbes=0,0,0
local function check(ok,why) checks=checks+1;assert(ok,why) end
local options={staticMode='interpreted',staticOptimize=false}
local prefix='let Box = { x: U32 }\n'
local function run(text,wanted,unoptimized,prelude)
 local unit=C.typed({profile='slet',source=(prelude or prefix)..text,name='anonymous-context.slet'},options)
 if unoptimized then unoptimizedProbes=unoptimizedProbes+1 end
 for _,optimize in ipairs(unoptimized and {false} or {false,true}) do for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
  local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
  check(tonumber(result.cells[1])==wanted,mode..'/'..tostring(optimize)..': '..tostring(result.cells[1]));executions=executions+1
 end end
 return unit
end
local function rejects(code,text,profile)
 local ok,err=pcall(C.typed,{profile=profile or 'slet',source=prefix..text,name='anonymous-reject.slet'},options)
 check(not ok and D.is(err) and err.code==code,code..': '..tostring(err))
end
local function parse(text) return P.source(text..'\nreturn { functions = {} }','anonymous-parse.let') end
local sample=[[let run_session (...: Ref(Terminal), editor: Ref(Editor)) = do
  editor. apply (editor.mode.command_for (read_key))
  draw do(full_frame...)
    draw_buffer (editor)
    draw_status (editor)
  end
  if editor.running then run_session (editor) end
end]]
local word=parse(sample).declarations[1].def
check(#word.params==2 and word.params[1].kind=='VocabularyParam' and word.params[1].name==nil,'original snippet has two requirements, no fabricated name')
check(word.params[2].name.text=='editor','anonymous annotation does not group with next parameter')
local params=parse('let f(...: Box, n: U32, ...args) = do return n end').declarations[1].def.params
check(#params==3 and params[1].kind=='VocabularyParam' and params[3].kind=='RestParam','anonymous opening and named rest are distinct')
local lambda=parse('let f=do(...) return (...) end').declarations[1].def.values[1]
check(lambda.params[1].name==nil and lambda.body.statements[1].values[1].value.kind=='CurrentContext','contextual anonymous lambda and bare current context')
local supply=parse('let f(...: Box) = do return ...,...[1,2],(...).x end').declarations[1].def.body.statements[1].values
check(supply[1].kind=='CurrentContext' and supply[2].kind=='Spread' and supply[3].kind=='FieldSelect','bare context, array spread and grouped projection parse separately')
local unit=run([[
let nudge(p: Ref(Box), dx: U32): Unit = do p.x+=dx return end
let opened(...: Ref(Box), dx: U32): U32 = do nudge(dx) return (...).x end
let main(): U32 = do let p=Box{x=40} let result=opened(Ref(p),2) return result+p.x end
]],84)
for _,fn in ipairs(unit.functions) do if fn.id=='opened' then
 check(#fn.inputs==2 and fn.hidden==0,'anonymous context is an ordinary ABI input, not hidden transport')
 check(fn.inputs[1].type:isRef() and fn.inputs[2].type==S.U32,'selected parameter types and order')
end end
run([[
let opened(...: Box): U32 = do x+=2 return (...).x end
let main(): U32 = do let p=Box{x=40} let got=opened(p) return got+p.x end
]],82)
run([[
let opened(...: Box): U32 = do let snapshot=(...) x+=2 return snapshot.x+x end
let main(): U32 = do let p=Box{x=40} return opened(p) end
]],82,true)
run([[
let identity(...: Ref(Box)): Ref(Box) = do return ... end
let main(): U32 = do let p=Box{x=42} let r=identity(Ref(p)) return r.x end
]],42)
run([[
let apply(p: Ref(Box), body: (Ref(Box)): U32): U32 = body(p)
let main(): U32 = do let p=Box{x=40} return apply(Ref(p)) do(...) x+=2 return (...).x end end
]],42)
run([[
let apply(p: Box, body: (Box): U32): U32 = body(p)
let main(): U32 = do let p=Box{x=40} let got=apply(p) do(...) x+=2 return (...).x end return got+p.x end
]],82)
run([[
let down(...: Ref(Box), n: U32): U32 = do
 if n==0 then return x else return down(n-1) end
end
let main(): U32 = do let p=Box{x=42} return down(Ref(p),8) end
]],42)
run([[
let main(): U32 = do let p=Box{x=42}
 let down(...: Ref(Box), n: U32): U32 = do
  if n==0 then return x else return (down)(...,n-1) end
 end
 return down(Ref(p),8)
end
]],42)
run([[
let add(...: Ref(Box), ...args): U32 = do return x+args[0] end
let main(): U32 = do let p=Box{x=40} return add(Ref(p),2) end
]],42)
run([[
let add(ctx...: Ref(Box), ...args): U32 = do return ctx.x+args[0] end
let main(): U32 = do let p=Box{x=40} return add(Ref(p),2) end
]],42)
run([[
let add(T: Type, ...: T, ...args): U32 = do return x+args[0] end
let main(): U32 = do let p=Box{x=40} return add(Ref(Box),Ref(p),2) end
]],42)
run([[
let main(): U32 = do let p=Box{x=42} let root...=Ref(p) return (...).x end
]],42)
run([[
let main(): U32 = do let a=Box{x=10} let b=Box{x=20} let r...=Ref(a)
 let saved(): U32 = do return (...).x end
 r=Ref(b) a.x=42
 return saved()
end
]],42,true)
run([[
let take(...: Ref(Box)): U32 = do
 let saved(): U32 = do return (...).x end
 x+=2 return saved()
end
let main(): U32 = do let p=Box{x=40} return take(Ref(p)) end
]],42,true)
run([[
let bump(p: Ref(Box)): Unit = do p.x+=2 return end
let take(...: Ref(Box)): U32 = do defer (bump)(...) return x end
let main(): U32 = do let p=Box{x=40} let before=take(Ref(p)) return before+p.x end
]],82)
run([[
let Inner={y: U32}
let main(): U32 = do let a=Box{x=10} let outer...=Ref(a)
 let inner(...: Ref(Inner)): U32 = do return (...).y end
 let b=Inner{y=32} return (inner)(Ref(b))+(...).x
end
]],42)
-- Actual member wins; an opened callable field receives no inserted receiver.
run([[
let main(): U32 = do let p=Box{x=40} return opened(Ref(p)) end
]],42,false,[[
let Box={x: U32, nudge(dx: U32): Unit=do x+=dx return end}
let nudge(p: Ref(Box),dx: U32): Unit=do p.x=999 return end
let opened(...: Ref(Box)): U32=do nudge(2) return x end
]])
run([[
let inc(n: U32): U32 = n+2
let CallableBox={apply: (U32): U32}
let opened(...: Ref(CallableBox)): U32 = do return apply(40) end
let main(): U32 = do let p=CallableBox{apply=inc} return opened(Ref(p)) end
]],42,true)
-- Context is lexical, not dynamically inherited from an ordinary caller.
rejects('context-required','let outside(): U32=do return (...).x end; let main():U32=0')
rejects('context-required','let main(): U32=do let x=(...) return 0 end')
rejects('parameter-type','let opened(...) = do return 0 end; let main(): U32=0')
rejects('spread-source','let opened(...: U32): U32=do return 0 end; let main(): U32=0')
rejects('spread-shadow','let opened(...: Ref(Box),x: U32): U32=do return x end; let main(): U32=0')
rejects('vocabulary-position','let f(n: U32,...: Box)=0; let main(): U32=0')
rejects('vocabulary-position','let f(n: U32,ctx...: Box)=0; let main(): U32=0')
rejects('vocabulary-position','let f(T: Type,n: U32,...: T)=0; let main(): U32=0')
rejects('parameter-type','let opened(...) = do return 0 end; let main(): U32=0','let')
rejects('context-use','let opened(...:Ref(Box),other:Ref(Box)):Unit=do ... = other return end; let main():U32=0')
rejects('context-use','let opened(...:Box,other:Box):Unit=do let marker=0; (...) = other return end; let main():U32=0')
rejects('not-a-place','let opened(...:Ref(Box)):Ref(Ref(Box))=Ref(...); let main():U32=0')
rejects('not-a-place','let opened(...:Ref(Box)):Ptr(Ref(Box))=Ptr(...); let main():U32=0')
local unsafe='let Destination={held:Ref(U32)}; let unsafe(...: Box,destination:Ref(Destination)):Unit=do destination.held=Ref((...).x) return end; let main():U32=0'
rejects('borrow-store',unsafe)
rejects('borrow-store',unsafe,'let')
rejects('vocabulary-position','let f(a...: Box,...: Box)=do return 0 end; let main(): U32=0')
rejects('vocabulary-position','extern let f(...: Box): Unit; let main(): U32=0')
rejects('rest-position','let f(...args,n: U32)=do return 0 end; let main(): U32=0')
rejects('borrow-return','let opened(...: Box): Ref(Box)=do return Ref(...) end; let main(): U32=0')
rejects('borrow-return','let opened(...: Box): Ref(Box)=do return Ref(...) end; let main(): U32=0','let')
run([[
let Point={x:F64,y:F64}
let squared(...:Point):F64=x*x+y*y
let main():U32=do let p=Point{x=3.0,y=4.0} return U32(squared(p)) end
]],25)
run([[
let opened(...: Ref(Box)): U32 = x+2
let main(): U32 = do let p=Box{x=40} return opened(Ref(p)) end
]],42)
run([[
let opened(ctx...: Ref(Box)): U32 = ctx.x+2
let main(): U32 = do let p=Box{x=40} return opened(Ref(p)) end
]],42)
run([[
let apply(p: Ref(Box), body: (Ref(Box)): U32): U32=body(p)
let main(): U32=do let p=Box{x=40} return apply(Ref(p)) do(...) = x+2 end
]],42)
run([[
let identity(...: Ref(Box)): Ref(Box) = (...)
let opened(...:Ref(Box)):U32=do let held=(...); (...).x=42 return x end
let main():U32=do let p=Box{x=40} return (opened)((identity)(Ref(p))) end
]],42)
run([[
let add(T: Type,...:T,...args):U32=x+args[0]
let main():U32=do let p=Box{x=40} return add(Ref(Box),Ref(p),2) end
]],42)
run([[
let T=Type
let add(T:Type,...:T,n:U32):U32=x+n
let main():U32=do let p=Box{x=40} return add(Ref(Box),Ref(p),2) end
]],42)
run([[
let unused(...:Ref(Box)):U32=42
let main():U32=do let p=Box{x=40} return unused(Ref(p)) end
]],42)
local unused=C.typed({profile='slet',source=prefix..'let unused(...:Ref(Box)):U32=42; let main():U32=0'},options)
local reads=0
for _,fn in ipairs(unused.functions) do if fn.id=='unused' then Walk.walk(fn,{enter=function(node) if S.Ir.Read:isclassof(node) and node.type==S.U32 then reads=reads+1 end end}) end end
check(reads==0,'unused opening has no eager scalar field reads')
-- Named/unnamed opening produces identical executable IR for field-only activity.
local named=C.typed({profile='slet',source=prefix..'let opened(ctx...: Ref(Box)): U32=do x+=2 return x end; let main(): U32=0'},options)
local anonymous=C.typed({profile='slet',source=prefix..'let opened(...: Ref(Box)): U32=do x+=2 return x end; let main(): U32=0'},options)
local function body(functions) for _,fn in ipairs(functions) do if fn.id=='opened' then return S.encode(fn.body) end end end
check(body(named.functions)==body(anonymous.functions),'anonymous opening introduces no alternative computation or fabricated runtime namespace')
print(('anonymous context: %d checks, %d VM executions; %d probes unoptimized only'):format(checks,executions,unoptimizedProbes))
