package.path='./?.lua;./?/init.lua;../tools/?.lua;'..package.path
local Compiler=require('let.compiler')
local S=require('let.schema')
local D=require('let.diag')
local checks=0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function rejects(code,fn)
    local ok,err=pcall(fn)
    check(not ok and D.is(err) and err.code==code,code..': '..tostring(err))
end
local source=[[
let seed(n: u32): u32 = n + 1
let add(a: u32, b: u32): u32 = a + b
let main(): u32 = do
  let known = seed(20)
  let alias = known
  let plus = add(alias)
  let again = plus
  return again(21)
end
return { functions = { main } }
]]
local parsed=Compiler.source{profile='slet',source=source,name='source-demands.slet'}
rejects('execution-policy',function() Compiler.typed(parsed) end)
check(parsed.phase=='parsed','typing must not mutate the parsed unit')
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
    for _,optimize in ipairs{false,true} do
        local unit=Compiler.typed(parsed,{staticMode=mode,staticOptimize=optimize})
        local result=Compiler.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize})
        check(tonumber(result.cells[1])==42,'computed/alias/partial result '..mode)
        local views=0
        local function inspect(stmt) if stmt.kind=='View' then views=views+1 end;stmt:each(inspect) end
        for _,fn in ipairs(unit.functions) do for _,stmt in ipairs(fn.body) do inspect(stmt) end end
        check(views==0,'direct source callable needs no materialized adapter')
        check(parsed.phase=='parsed','repeated typing remains request-local')
    end
end
local function run(text,expected,options)
    local unit=Compiler.typed({profile='slet',source=text,name='source-boundary.slet'},options)
    local result=Compiler.stage(unit.functions,{profile='slet',entry='main',mode='interpreted',optimize=false})
    check(tonumber(result.cells[1])==expected,'boundary returned '..tostring(result.cells[1]))
    return unit
end
run([[
let add(a: u32, b: u32): u32 = a + b
let main(): u32 = do
  let n = 21
  let plus = add(n)
  return plus(21)
end
return { functions = { main } }
]],42)
run([[
let main(): u32 = do
  let base = 10
  let digits { a: u32, b: u32, c: u32 }: u32 = base + a * 100 + b * 10 + c
  let middle = digits { b = 2 }
  return middle(1, 3)
end
return { functions = { main } }
]],133)
run([[
let pair(): (u32, u32) = do return 20, 22 end
let cell = { n: u32 }
let put(p: ref(cell)): unit = do p.n = 1 return end
let main(): u32 = do
  let box = cell { n = 0 }
  let invoke(): (u32, u32) = do
    defer put(ref(box))
    return pair()
  end
  let a, b = invoke()
  return a + b + box.n
end
return { functions = { main } }
]],43)
rejects('static-required',function() Compiler.typed{profile='slet',source=[[
let add(a: u32, b: u32): u32 = a + b
let bad(n: u32): u32 = do let p = add(n) return p(1) end
return { functions = { bad } }
]]} end)
run([[
let value = seed(41)
let seed(n: u32): u32 = n + 1
let main(): u32 = value
return { functions = { main } }
]],42,{staticMode='interpreted',staticOptimize=false})
rejects('static-cycle',function() Compiler.typed({profile='slet',source=[[
let a = b
let b = a
let main(): u32 = a
return { functions = { main } }
]]},{staticMode='interpreted'}) end)
run([[
let add(a: u32, b: u32): u32 = a + b
let main(): u32 = do
  let plus = add(20)
  let nested(x: u32): u32 = plus(x)
  let lambda: (u32): u32 = do(x: u32) = nested(x)
  return lambda(22)
end
return { functions = { main } }
]],42)
run([[
let cell = { n: u32 }
let put(p: ref(cell)): unit = do p.n = 42 return end
let finish(p: ref(cell)): unit = do defer put(p) return end
let main(): u32 = do let box = cell { n = 0 } finish(ref(box)) return box.n end
return { functions = { main } }
]],42)
run([[
let sum(n: u32): u32 = do if n == 0 then return 0 end return n + sum(n - 1) end
let add(a: u32, b: u32): u32 = a + b
let main(): u32 = do let f = add(sum(6)) return f(21) end
return { functions = { main } }
]],42,{staticMode='interpreted',staticOptimize=false})
rejects('static-division-zero',function() Compiler.typed({profile='slet',source=[[
let add(a: u32, b: u32): u32 = a + b
let main(): u32 = do let f = add(1 / 0) return f(1) end
]]},{staticMode='interpreted',staticOptimize=false}) end)
rejects('static-foreign',function() Compiler.typed({profile='slet',source=[[
extern let host(): u32
let add(a: u32, b: u32): u32 = a + b
let main(): u32 = do let f = add(host()) return f(1) end
]]},{staticMode='interpreted'}) end)

-- Transport exact f64 bits without a host-double round trip, including NaN payloads.
local ffi=require('let.abi')
local IR=require('let.ir');local I,L=S.Ir,S.ASDL.List
local Int=require('int64')
for _,bits in ipairs{'0x8000000000000000','0x7ff8000000001234','0xfff0000000000000'} do
    local value={type=S.f64,bits=Int.parse(bits)}
    local literal=require('let.specialize').constant(IR.builder(),value,S.f64)
    check(literal.literal.kind=='FloatBits','VM transport retains exact float representation')
    local fn=I.Fn('main',I.Entry,0,L{},L{S.f64},L{},L{I.Return(L{literal})})
    for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
        local result=Compiler.stage({fn},{profile='slet',entry='main',mode=mode,optimize=false})
        check(result.cells[1]==value.bits,'exact f64 bits in '..mode)
    end
end
print('source demand checks: '..checks)
