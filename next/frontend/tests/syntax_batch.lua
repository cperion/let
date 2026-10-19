package.path='./?.lua;./?/init.lua;../tools/?.lua;'..package.path
local Parse=require('let.parse')
local Lex=require('let.lex')
local Compiler=require('let.compiler')
local D=require('let.diag')
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function rejected(code,fn)
    local ok,err=pcall(fn)
    check(not ok and D.is(err) and err.code==code,code..': '..tostring(err))
end
local function expression(text)
    return Parse.source('let sample = '..text..'\nreturn { functions = {} }','syntax-batch.let').declarations[1].def.values[1]
end
local function rejects(text,code) rejected(code or 'parse',function() expression(text) end) end
local tokens=Lex.tokens('... .. . -> --> comment\n21.member 1.5 1..2','dots.let')
local expected={'...','..','.','-','>','21','.','member','1.5','1','..','2'}
for index,text in ipairs(expected) do check(tokens[index].text==text,'longest-token/numeric boundary '..index) end
check(expression('do(x: U32) = x + 1').body.kind=='Expression','arrow-free expression lambda')
check(expression('do() = Unit()').kind=='Lambda','nullary expression lambda')
check(expression('do(x: U32) return x end').body.kind=='Block','parameterized block lambda')
check(expression('do return 1 end').params[1]==nil,'nullary block lambda')
check(expression('do(x: U32) = do return x end').body.value.kind=='Lambda','expression body returns nested block without grouping')
check(expression('do(x: U32): U32 = x').result.kind=='Single','explicit lambda result annotation')
check(expression('do(): (U32, Bool) return 1, true end').result.kind=='Many','vector lambda annotation')
rejects('do = 1');rejects('do(x) == x');rejects('|x| x')
check(Parse.source('let make(x: U32) = do() = x\nreturn { functions = { make } }').declarations[1].def.body.value.kind=='Lambda','named expression may return a nullary lambda')
rejects('|x: U32| -> x')
rejects('|x: U32| do return x end')
rejects('do return 1 end()')
rejects('do return 1 end.field')
check(expression('(do return 1 end)()').callee.kind=='Group','group permits immediate block invocation')
local literal=expression('f "{}".fmt(1)[0]')
check(literal.kind=='Apply' and #literal.arguments==1 and literal.arguments[1].kind=='IndexExpr','literal chain belongs to argument')
check(expression('f 1 + 2').left.kind=='Apply','infix outside literal argument')
check(expression('f - 1').kind=='BinaryExpr','minus is not literal sugar')
check(expression('f[1]').kind=='IndexExpr','indexing unchanged')
check(expression('(f 1) 2').callee.kind=='Group','explicit grouping calls result')
rejects('f x')
check(expression('f 1 2').callee.kind=='Apply','literal suffixes associate left')
check(expression('f 1 do return 2 end').callee.kind=='Apply','block applies to literal application result')
check(expression('f { x = 1 } do return 2 end').callee.kind=='RecordSupply','block applies to keyed supply result')
check(expression('f 1 2 + 3').left.callee.kind=='Apply','whole suffix chain binds before infix')
local block=expression('f(pair()) do return 3 end')
check(#block.arguments==1 and block.arguments[1].kind=='Lambda' and block.callee.kind=='Apply','trailing block never reopens argument list')
check(expression('(f(1)) do return 2 end').callee.kind=='Group','grouped application invokes its result')
local group=expression('((pair()))')
check(group.kind=='Group' and group.value.kind=='Group','grouping retained rather than erased')
local spread=expression('f(...pair(), 1, ...xs)')
check(spread.arguments[1].kind=='Spread' and spread.arguments[3].kind=='Spread','ordered spread AST')
check(expression('point { ...p, x = 1 }').fields[1].kind=='FieldSpread','keyed spread AST')
check(expression('[...xs, 1]').items[1].kind=='Spread','array spread AST')
rejects('1 + ...xs','spread-context');rejects('{ ...p }')
local rest=Parse.source('let f(a: U32, ...args): U32 = a\nreturn { functions = { f } }')
check(rest.declarations[1].def.params[2].kind=='RestParam','named final rest AST')
rejected('rest-position',function() Parse.source('let f(...args, x: U32): U32 = x') end)
check(expression('do(...args) return 0 end').params[1].kind=='RestParam','literal do shares rest requirement syntax')
local names=Parse.source('use std.text...; let text...; let context... = make(); return { functions = {} }')
check(names.declarations[1].spread and names.declarations[1].path=='std.text','suffix import spread AST')
check(names.declarations[2].kind=='SpreadDecl' and names.declarations[2].name.text=='text' and not names.declarations[2].initial,'expand existing binding AST')
check(names.declarations[3].initial.kind=='Apply' and names.declarations[3].name.text=='context','initialized vocabulary binding AST')
local vocabulary=expression('do(ctx...: Context) return ctx end')
check(vocabulary.params[1].kind=='VocabularyParam' and vocabulary.params[1].annotation.name.text=='Context','annotated vocabulary parameter AST')
check(expression('do(ctx...: Context, x: U32, ...args) return x end').params[3].kind=='RestParam','vocabulary and rest remain distinct')
check(Parse.source('let f(ctx...: Context) = 1; return { functions = {} }').declarations[1].def.body.kind=='Expression','named expression-body opening')
check(expression('do(ctx...: Context) = 1').body.kind=='Expression','literal expression-body opening')
local named=Parse.source('let configure(ctx...) = do let inner... = make(ctx); return end; return { functions = {} }')
check(named.declarations[1].def.params[1].kind=='VocabularyParam','named block vocabulary parameter')
local statement=named.declarations[1].def.body.statements[1]
check(statement.kind=='SpreadStmt' and statement.name.text=='inner' and statement.initial.kind=='Apply','local initialized vocabulary AST')
for _,text in ipairs{'use ...std.text','let ...context'} do
    rejected('spread-context',function() Parse.source(text) end)
end
for _,text in ipairs{
    'let f(a..., b...) = do return end',
    'let f(a...: Context, b...: Context) = do return end',
    'extern let f(ctx...: Context): Unit',
} do rejected('vocabulary-position',function() Parse.source(text) end) end
for _,text in ipairs{'let make()...', 'let ctx... = make(), other()', 'use std.text...more'} do
    rejected('parse',function() Parse.source(text) end)
end
local indexed=Compiler.source{profile='slet',source='let context... = make(); let context...; return { functions = {} }'}
check(indexed.bindings.context~=nil,'only initialized context adds an explicit module binding')
rejected('duplicate-name',function() Compiler.source{profile='slet',source='let context... = make(); let context = 1; return { functions = {} }'} end)
local captured=Compiler.typed{profile='slet',source=[[
let Context = { amount: U32 }
let factory(seed: U32): Context = Context { amount = seed }
let main(seed: U32): U32 = do let word = do() let ctx... = factory(seed) return amount end return word() end
]]}
check(captured.functions[#captured.functions].hidden==1,'initialized context captures its selected outer seed, not its own binding')
captured=Compiler.typed{profile='slet',source=[[
let Context = { amount: U32 }
let main(): U32 = do let ctx = Context { amount = 42 } let word = do() let ctx... return amount end return word() end
]]}
local fn=captured.functions[#captured.functions]
check(fn.hidden==1 and fn.params[1].kind=='PlaceParam','existing-context expansion captures the actual context place')
check(expression('a .. b .. c').right.operator=='..','right-associative concatenation syntax')
for _,case in ipairs{
    {'spread-source','let f(x: U32): U32 = x; let main(): U32 = f(...1)'},
    {'spread-source','let unknown...; let main(): U32 = 0'},
    {'unknown-name','let ctx... = make(); let main(): U32 = 0'},
    {'import-input','use missing...; let main(): U32 = 0'},
    {'parameter-type','let main(ctx...) = do return 0 end'},
    {'pack-index','let f(...args): U32 = args[0]; let main(): U32 = f(); return { functions = { main } }'},
    {'concatenation-unimplemented','let main(): U32 = "a" .. "b"'},
} do rejected(case[1],function() Compiler.typed{profile='slet',source=case[2]} end) end

local function run(source,expected)
    local unit=Compiler.typed{profile='slet',source=source,name='syntax-execution.slet'}
    for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
        local result=Compiler.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=false})
        executions=executions+1
        check(tonumber(result.cells[1])==expected,'execution '..mode..': '..tostring(result.cells[1]))
    end
    return unit
end
run('let main = do return 42 end',42)
run('let main = do(): U32 = 42',42)
run('let add(x: U32, y: U32): U32 = x + y\nlet main(): U32 = add 20 22',42)
run('let make(x: U32) = do(y: U32) = y + 2\nlet main(): U32 = make 0 40',42)
run('let make() = do() = 42\nlet main(): U32 = make()()',42)
run('let make() = do(): U32 return 42 end\nlet main(): U32 = make()()',42)
run('let apply(x: U32, f: (): U32): U32 = x + f()\nlet main(): U32 = apply 20 do return 22 end',42)
run([[
let pair(): (U32, U32) = do return 20, 22 end
let take(x: U32): U32 = x
let add(x: U32, y: U32): U32 = x + y
let main(): U32 = take((pair())) + add(pair())
]],62)
run([[
let invoke(x: U32, f: (): U32): U32 = x + f()
let pair(): (U32, U32) = do return 20, 900 end
let main(): U32 = invoke(pair(), do return 22 end)
]],42)
run([[
let invoke(f: (U32): U32): U32 = f(20)
let main(): U32 = invoke do(n): U32 return n + 22 end
]],42)
run([[
let Cell = { value: U32 }
let main(): U32 = do
  let box = Cell { value = 0 }
  let delayed = do box.value = 42 return box.value end
  if box.value != 0 then return 100 end
  return delayed()
end
]],42)
run([[
let id(n: U32): U32 = n
let main(): U32 = id 40 + (do return 2 end)()
]],42)
run([[
let pair(): (U32, U32) = do return 20, 22 end
let forward(): (U32, U32, U32) = do return 1, pair() end
let main(): U32 = do let first, a, b = forward() return first + a + b end
]],43)
check(Compiler.typed{profile='slet',source='let main = do return end'}.phase=='typed-ir','entry discovery does not impose a new result ABI')
run('let main(): I64 = I64(42)',42)
run('let main = do(): I64 = I64(42)',42)
rejected('export-callable',function() Compiler.typed{profile='slet',source='let main = 42'} end)
run([[
let invoke(f: (U32): U32): U32 = f(21)
let main(): U32 = invoke do(x): U32 = x * 2
]],42)
run([[
let make(): (U32): U32 = (do(y: U32): U32 = 20 + y)
let main(): U32 = do let f = make() return f(22) end
return { functions = { main } }
]],42)
rejected('type-mismatch',function() Compiler.typed{profile='slet',source=[[
let main(): U32 = do let f: (U32): U32 = do(x): Bool = true return 0 end
]]} end)
print(('syntax batch: %d checks, %d VM executions'):format(checks,executions))
