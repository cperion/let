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
check(expression('do(x: u32) = x + 1').body.kind=='Expression','arrow-free expression lambda')
check(expression('do() = unit()').kind=='Lambda','nullary expression lambda')
check(expression('do(x: u32) return x end').body.kind=='Block','parameterized block lambda')
check(expression('do return 1 end').params[1]==nil,'nullary block lambda')
check(expression('do(x: u32) = do return x end').body.value.kind=='Lambda','expression body returns nested block without grouping')
check(expression('do(x: u32): u32 = x').result.kind=='Single','explicit lambda result annotation')
check(expression('do(): (u32, bool) return 1, true end').result.kind=='Many','vector lambda annotation')
rejects('do = 1');rejects('do(x) == x');rejects('|x| x')
check(Parse.source('let make(x: u32) = do() = x\nreturn { functions = { make } }').declarations[1].def.body.value.kind=='Lambda','named expression may return a nullary lambda')
rejects('|x: u32| -> x')
rejects('|x: u32| do return x end')
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
local rest=Parse.source('let f(a: u32, ...args): u32 = a\nreturn { functions = { f } }')
check(rest.declarations[1].def.params[2].kind=='RestParam','named final rest AST')
rejected('rest-position',function() Parse.source('let f(...args, x: u32): u32 = x') end)
check(expression('do(...args) return 0 end').params[1].kind=='RestParam','literal do shares rest requirement syntax')
local names=Parse.source('use ...std.text; let ...text; return { functions = {} }')
check(names.declarations[1].spread and names.declarations[2].kind=='SpreadDecl','import and binding spread AST')
check(expression('a .. b .. c').right.operator=='..','right-associative concatenation syntax')
for _,case in ipairs{
    {'spread-unimplemented','let main(): u32 = f(...xs)'},
    {'spread-unimplemented','let ...unknown; let main(): u32 = 0'},
    {'spread-unimplemented','use ...missing; let main(): u32 = 0'},
    {'rest-unimplemented','let f(...args): u32 = 0; return { functions = { f } }'},
    {'concatenation-unimplemented','let main(): u32 = "a" .. "b"'},
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
run('let main = do(): u32 = 42',42)
run('let add(x: u32, y: u32): u32 = x + y\nlet main(): u32 = add 20 22',42)
run('let make(x: u32) = do(y: u32) = y + 2\nlet main(): u32 = make 0 40',42)
run('let make() = do() = 42\nlet main(): u32 = make()()',42)
run('let make() = do(): u32 return 42 end\nlet main(): u32 = make()()',42)
run('let apply(x: u32, f: (): u32): u32 = x + f()\nlet main(): u32 = apply 20 do return 22 end',42)
run([[
let pair(): (u32, u32) = do return 20, 22 end
let take(x: u32): u32 = x
let add(x: u32, y: u32): u32 = x + y
let main(): u32 = take((pair())) + add(pair())
]],62)
run([[
let invoke(x: u32, f: (): u32): u32 = x + f()
let pair(): (u32, u32) = do return 20, 900 end
let main(): u32 = invoke(pair(), do return 22 end)
]],42)
run([[
let invoke(f: (u32): u32): u32 = f(20)
let main(): u32 = invoke do(n): u32 return n + 22 end
]],42)
run([[
let cell = { value: u32 }
let main(): u32 = do
  let box = cell { value = 0 }
  let delayed = do box.value = 42 return box.value end
  if box.value != 0 then return 100 end
  return delayed()
end
]],42)
run([[
let id(n: u32): u32 = n
let main(): u32 = id 40 + (do return 2 end)()
]],42)
run([[
let pair(): (u32, u32) = do return 20, 22 end
let forward(): (u32, u32, u32) = do return 1, pair() end
let main(): u32 = do let first, a, b = forward() return first + a + b end
]],43)
check(Compiler.typed{profile='slet',source='let main = do return end'}.phase=='typed-ir','entry discovery does not impose a new result ABI')
run('let main(): i64 = i64(42)',42)
run('let main = do(): i64 = i64(42)',42)
rejected('export-callable',function() Compiler.typed{profile='slet',source='let main = 42'} end)
run([[
let invoke(f: (u32): u32): u32 = f(21)
let main(): u32 = invoke do(x): u32 = x * 2
]],42)
run([[
let make(): (u32): u32 = (do(y: u32): u32 = 20 + y)
let main(): u32 = do let f = make() return f(22) end
return { functions = { main } }
]],42)
rejected('type-mismatch',function() Compiler.typed{profile='slet',source=[[
let main(): u32 = do let f: (u32): u32 = do(x): bool = true return 0 end
]]} end)
print(('syntax batch: %d checks, %d VM executions'):format(checks,executions))
