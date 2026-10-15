package.path='./?.lua;./?/init.lua;../tools/?.lua;'..package.path
local Compiler=require('let.compiler')
local Parse=require('let.parse')
local D=require('let.diag')
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function reject(code,source)
    local ok,err=pcall(Compiler.typed,{profile='slet',source=source,name='word-reject.slet'})
    check(not ok and D.is(err) and err.code==code,code..': '..tostring(err))
end
local function run(source,expected)
    local unit=Compiler.typed{profile='slet',source=source,name='word-bindings.slet'}
    for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
        local result=Compiler.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=false})
        check(tonumber(result.cells[1])==expected,mode..' word result: '..tostring(result.cells[1]))
        executions=executions+1
    end
    return unit
end
local function counts(unit)
    local views,indirect=0,0
    local function visit(stmt)
        if stmt.kind=='View' then views=views+1 elseif stmt.kind=='Indirect' then indirect=indirect+1 end
        stmt:each(visit)
    end
    for _,fn in ipairs(unit.functions) do for _,stmt in ipairs(fn.body) do visit(stmt) end end
    return #unit.functions,views,indirect
end
local named=run('let twice(x: U32) = x * 2\nlet main() = twice(21)',42)
local literal=run('let twice = do(x: U32) = x * 2\nlet main = do() = twice(21)',42)
local nf,nv,ni=counts(named);local lf,lv,li=counts(literal)
check(nf==lf and nf==2 and nv==0 and lv==0 and ni==0 and li==0,'same direct word representation without environments')
for _,definition in ipairs{
    'let fact(n: U32): U32 = if n == 0 then 1 else n * fact(n - 1)',
    'let fact = do(n: U32): U32 = if n == 0 then 1 else n * fact(n - 1)',
} do run(definition..'\nlet main() = fact(5)',120) end
for _,definition in ipairs{
    'let count(n: U32): U32 = if n == 0 then base else count(n - 1) + 1',
    'let count = do(n: U32): U32 = if n == 0 then base else count(n - 1) + 1',
} do run('let main() = do let base = 40 '..definition..' return count(2) end',42) end
run([[
let first = do(x: U32) = second(x)
let second(x: U32) = x + 1
let main = do() = first(41)
]],42)
run([[
let main() = do
  let base = 40
  let outer = do() = (do(x: U32) = base + x)(2)
  return outer()
end
]],42)
run([[
let main() = do
  let base = 40
  let outer() = do let inner(x: U32) = base + x return inner(2) end
  return outer()
end
]],42)
local aliases=run([[
let twice = do(x: U32) = x * 2
let main() = do let a: (U32): U32 = twice let b = a return b(21) end
]],42)
local af,av,ai=counts(aliases)
check(af==2 and av==0 and ai==0,'typed aliases do not create definitions, environments or indirect calls')
run([[
let choose(x: U32): U32 = 900
let main() = do
  let choose = do(x: U32) = x + 1
  let alias = choose
  return alias(41)
end
]],42)
for _,source in ipairs{
    'let id(x) = x\nreturn { functions = { id } }',
    'let id = do(x) = x\nreturn { functions = { id } }',
} do
    local unit=Compiler.typed{profile='let',source=source}
    check(unit.signatures.id.inputs[1].type==require('let.schema').Any and unit.signatures.id.results[1]==require('let.schema').Any,'both spellings share progressive defaults without implicit generics')
end
for _,definition in ipairs{
    'let change(x: Cell): U32 = do x.value = 1 return x.value end',
    'let change = do(x: Cell): U32 x.value = 1 return x.value end',
} do run('let Cell = { value: U32 }\n'..definition..'\nlet main() = do let c = Cell { value = 41 } return change(c) + c.value end',42) end
for _,definition in ipairs{
    'let read(): U32 = box.value',
    'let read = do(): U32 = box.value',
} do
    local escaped=Compiler.typed{profile='slet',source='let Cell = { value: U32 }\nlet make(): (): U32 = do let box = Cell { value = 42 } '..definition..' return read end\nreturn { functions = { make } }'}
    local ok,err=pcall(Compiler.lower,escaped.functions,{profile='slet',exports={'make'}})
    check(not ok and D.is(err) and err.code=='ownership-materialization','Owning public callable export requires its own ABI')
    run('let Cell = { value: U32 }\nlet main() = do let box = Cell { value = 42 } '..definition..' return read() end',42)
end
reject('unknown-name','let main() = do let x = x + 1 return x end')
reject('result-type','let recursive = do(n: U32) = recursive(n)\nlet main() = recursive(1)')
reject('result-type','let recursive(n: U32) = recursive(n)\nlet main() = recursive(1)')
run([[
let Option = oneof { none: Unit, some: U32 }
let unwrap(value: Option): U32 = value {
  none() = 0,
  some(payload): U32 = do return payload + 2 end,
}
let main() = unwrap(Option.some(40))
]],42)
run([[
let Option = oneof { none: Unit, some: U32 }
let some(x: U32): U32 = x + 1
let zero(): U32 = 0
let main() = do
  let value = Option.some(40)
  let a = value { none = zero, some = some }
  return value { none() = 0, some(x) = some(x) + a - 40 }
end
]],42)
run([[
let Option = oneof { none: Unit, some: U32 }
let inc(x: U32): U32 = x + 1
let zero(): U32 = 0
let Tracker = {
  value: U32,
  full(n: U32): (U32): U32 = do value = value * 10 + n return inc end,
  empty(n: U32): (): U32 = do value = value * 10 + n return zero end,
}
let main() = do
  let t = Tracker { value = 0 }
  let value = Option.some(29)
  let result = value { some = t.full(1), none = t.empty(2) }
  return result + t.value
end
]],42)
run([[
let inc(x: U32): U32 = x + 1
let main() = do let f = if true then inc else inc return f(41) end
]],42)
reject('type-mismatch','let Option = oneof { value: U32 }\nlet main(): U32 = do let v = Option.value(1) return v { value(x: Bool) = 42 } end')
reject('type-mismatch','let Option = oneof { value: U32 }\nlet main(): U32 = do let v = Option.value(1) return v { value(x): U64 = 42 } end')
run([[
let Counter = { value: U32, bump(n: U32): U32 = do value += n return value end }
let main() = do let c = Counter { value = 40 } return c.bump(2) end
]],42)
local parsed=Parse.source('let commands = Table { save(editor) = editor.save(), quit(editor) = do editor.quit() end }\nreturn { functions = {} }')
local fields=parsed.declarations[1].def.values[1].fields
check(fields[1].value.kind=='Lambda' and fields[2].value.body.kind=='Block','keyed entries are lambda values, not methods')
local sum=Parse.source('let Option = oneof { value: U32 }\nreturn { types = { Option } }')
check(sum.declarations[1].def.values[1].kind=='SumSchema','sum constructor is syntax-owned')
for _,source in ipairs{
    'let oneof = 1\nreturn { functions = {} }',
    'let main(oneof: U32): U32 = oneof',
    'let main() = do let oneof = 1 return oneof end',
    'let bad = f { field: U32 }\nreturn { functions = {} }',
    'let Bad = oneof({ field: U32 })\nreturn { functions = {} }',
} do reject('parse',source) end
reject('type-required','let Invalid = oneof { method() = 1 }\nreturn { types = { Invalid } }')
for _,source in ipairs{
    'let forward(...args) = do return ...args end\nreturn { functions = { forward } }',
    'let forward = do(...args) return ...args end\nreturn { functions = { forward } }',
} do
    local unit=Compiler.typed{profile='slet',source=source,name='source-template-export.slet'}
    check(unit.namespace.members.forward.target.sourceTemplate,'rest word remains a public source definition')
    check(#unit.runtimeExports==0 and #unit.functions==0,'no erased variadic ABC entry')
end
local directory=os.tmpname();os.remove(directory)
assert(os.execute('mkdir '..string.format('%q',directory))==0)
local function write(path,text) local file=assert(io.open(path,'wb'));assert(file:write(text));assert(file:close()) end
write(directory..'/words.slet',[[
let twice = do(x: U32) = x * 2
let named(x: U32) = x + 1
return { functions = { twice, named } }
]])
write(directory..'/main.slet',[[
use words
let main() = do let alias: (U32): U32 = words.twice return alias(words.named(20)) end
]])
local loaded=Compiler.typedFile(directory..'/main.slet')
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
    local result=Compiler.stage(loaded.functions,{profile='slet',entry='main',mode=mode,optimize=false})
    executions=executions+1;check(tonumber(result.cells[1])==42,'imported literal/named words and aliases in '..mode)
end
os.remove(directory..'/words.slet');os.remove(directory..'/main.slet');assert(os.execute('rmdir '..string.format('%q',directory))==0)
print(('word bindings: %d checks, %d VM executions'):format(checks,executions))
