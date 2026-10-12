package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local Parse=require('let.parse')
local Lex=require('let.lex')
local A=require('let.ast')
local C=require('let.compiler')
local D=require('let.diag')
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function equivalent(body,expanded)
 local source='let main = do '..body..' return 0 end'
 local tokens=Lex.tokens(source,'endall.let')
 local before=#tokens
 local parsed=Parse.program(tokens)
 check(A.shape(parsed)==A.shape(Parse.source('let main = do '..expanded..' return 0 end')),'expanded AST: '..body)
 check(#tokens==before,'parser leaves caller tokens unchanged')
 check(A.shape(Parse.program(tokens))==A.shape(parsed),'repeat parse is stable')
 return parsed,source
end
check(Lex.tokens('endall')[1].kind=='keyword','reserved endall')
equivalent('outer do return 42 endall','outer do return 42 end')
local tree,source=equivalent('outer do inner do return 42 endall','outer do inner do return 42 end end')
-- Structural equivalence above covers all nodes; source-origin checks below use
-- reflection so the test does not depend on statement wrapper spelling.
local origin=assert(source:find('endall',1,true));local closers=0
local function spans(node)
 if type(node)~='table' then return end
 if node.kind=='Lambda' and node.span and node.span.finish==origin+6 then closers=closers+1 end
 local mt=getmetatable(node)
 if mt and mt.__fields then
  for _,field in ipairs(mt.__fields) do if field.name~='span' then spans(node[field.name]) end end
 elseif mt==A.List then for _,child in ipairs(node) do spans(child) end end
end
spans(tree);check(closers==2,'expanded lambda closers retain endall origin')
equivalent('outer do\n-- comment\n inner do\nreturn 42\nendall','outer do inner do return 42 end end')
equivalent('outer do if true then inner do return 42 endall end endall','outer do if true then inner do return 42 end end end')
equivalent('outer do let x = (inner do return 42 endall) endall','outer do let x = (inner do return 42 end) end')
equivalent('outer do consume(inner do return 42 endall) endall','outer do consume(inner do return 42 end) end')
equivalent('outer do let x = [inner do return 42 endall] endall','outer do let x = [inner do return 42 end] end')
equivalent('outer do let x = consume { value = inner do return 42 endall } endall','outer do let x = consume { value = inner do return 42 end } end')
equivalent('outer do let nested = do() inner do return 42 endall return 0 end endall','outer do let nested = do() inner do return 42 end return 0 end end')
equivalent('outer do let nested = do() = inner do return 42 endall endall','outer do let nested = do() = inner do return 42 end end')
for _,body in ipairs{
 'endall', 'if true then endall end', 'outer do if true then endall end end',
 'outer(do() return 42 endall)', 'let nested = do() return 42 endall',
 'outer do consume(endall) end', 'outer do let x = [endall] end',
 'outer do consume { value = endall } end',
} do
 local ok,err=pcall(Parse.source,'let main = do '..body..' return 0 end','invalid-endall.let')
 check(not ok and D.is(err) and err.code=='parse','boundary rejection: '..body..': '..tostring(err))
end
local program=[[
let State = { value: U32 }
let finish(p: Ref(State)): Unit = do p.value += 10 return end
let run(p: Ref(State), body: (): U32): U32 = do
 p.value += 1
 defer finish(p)
 return body()
end
let main(): U32 = do
 let p = State { value = 0 }
 let result = run(Ref(p)) do
  return run(Ref(p)) do
   return p.value
 endall
 return result + p.value
end
]]
local explicit=program:gsub('endall','end end')
check(A.shape(Parse.source(program))==A.shape(Parse.source(explicit)),'execution fixture AST equivalence')
for _,text in ipairs{program,explicit} do
 -- Existing local nonescaping capture admission; generated IR remains fully typed.
 local unit=C.typed{profile='let',source=text,name='endall-execution.let'}
 for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
  for _,optimize in ipairs{false,true} do
   local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
   executions=executions+1
   check(tonumber(result.cells[1])==24,'return/defer equivalence '..mode..' '..tostring(optimize))
  end
 end
end
print(('endall: %d checks, %d VM executions'):format(checks,executions))
