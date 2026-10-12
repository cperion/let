package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local D=require('let.diag')
local Walk=require('let.walk')
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function reject(code,text)
    local ok,err=pcall(C.typed,{profile='slet',source=text,name='chain-reject.slet'})
    check(not ok and D.is(err) and err.code==code,code..': '..tostring(err))
end
local function run(text,args,wanted)
    -- No static execution policy: saturation must not demand runtime arguments.
    local unit=C.typed{profile='slet',source=text,name='chains.slet'}
    for _,optimize in ipairs{false,true} do
        for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
            local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=optimize,arguments=args})
            executions=executions+1;check(tonumber(result.cells[1])==wanted,mode..'/'..tostring(optimize)..' result')
        end
    end
    return unit
end
local add='let add(x: u32, y: u32): u32 = x + y\n'
run(add..'let main(n: u32): u32 = add(n)(2)',{40},42)
run(add..'let main(n: u32): u32 = add(n + 1)(1)',{40},42)
run(add..'let main(): u32 = do let g = add(40) return g(2) end',{},42)
run(add..'let main(n: u32): u32 = add()(n)()(2)',{40},42)
run(add..'let main(n: u32): u32 = (add(n)(2))',{40},42)
run('let with_value(x: u32, f: (): u32): u32 = x + f()\nlet main(n: u32): u32 = with_value(n) do return 2 end',{40},42)
local indirect=run(add..[[
let apply(f: (u32, u32): u32, n: u32): u32 = f(n)(2)
let main(n: u32): u32 = apply(add, n)
]],{40},42)
local found=false
for _,fn in ipairs(indirect.functions) do if fn.id=='apply' then
    local calls,views=0,0
    Walk.walk(fn,{enter=function(node) if node.kind=='Indirect' then calls=calls+1 elseif require('let.schema').Ir.View:isclassof(node) then views=views+1 end end})
    check(calls==1 and views==0,'runtime callable chain emits one indirect call, no partial adapter');found=true
end end
check(found,'inspected runtime callable function')
run([[
let curried(x: u32) = do(y: u32): u32 = y + 2
let main(n: u32): u32 = curried(n)(40)
]],{123},42)
run([[
let pair(n: u32): (u32, u32) = do return n, 2 end
let total(a: u32, b: u32, f: (): u32): u32 = a + b + f()
let main(n: u32): u32 = total(pair(n)) do return 1 end
]],{39},42)
run([[
let collect(a: u32, b: u32): u32 = a + b
let trace = {
 value: u32,
 mark(n: u32): u32 = do value = value * 10 + n return n end,
 factory(): (u32, u32): u32 = do value = value * 10 + 1 return collect end,
}
let main(): u32 = do
 let t = trace { value = 0 }
 let result = t.factory()(t.mark(2))(t.mark(3))
 return t.value * 10 + result
end
]],{},1235)
run([[
let collect(a: u32, b: u32): u32 = a + b
let trace = { value: u32, change(): u32 = do value = 99 return 2 end }
let main(): u32 = do
 let t = trace { value = 40 }
 return collect(t.value)(t.change())
end
]],{},42)
run([[
let trace = {
 value: u32,
 finish(a: u32, b: u32): unit = do value += a + b return end,
}
let helper(t: ref(trace), n: u32): unit = do
 defer t.finish(n)(2)
 t.value = 1
 return
end
let main(n: u32): u32 = do let t = trace { value = 0 } helper(ref(t), n) return t.value end
]],{40},43)
run([[
let counter = { value: u32, add(x: u32, y: u32): u32 = do value += x + y return value end }
let holder = { current: ref(counter), redirect(next: ref(counter)): u32 = do current = next return 2 end }
let main(n: u32): u32 = do
 let first = counter { value = 10 }
 let second = counter { value = 100 }
 let h = holder { current = ref(first) }
 let result = h.current.add(n)(h.redirect(ref(second)))
 return result * 1000 + first.value * 10 + second.value
end
]],{30},42520)
for _,body in ipairs{
 'let g = add(n) return g(2)',
 'return (add(n))(2)',
 'return accept(add(n))',
} do reject('static-required',add..'let accept(f: (u32): u32): u32 = f(2)\nlet main(n: u32): u32 = do '..body..' end') end
reject('slet-forbidden',add..'let apply(f: (u32, u32): u32, n: u32): u32 = (f(n))(2)\nlet main(n: u32): u32 = apply(add, n)')
reject('arity',add..'let main(n: u32): u32 = add(n)(2, 3)')
reject('arity','let unary(n: u32): u32 = n\nlet main(): u32 = unary(1, 2)')
reject('type-mismatch','let stop(n: u32): unit = do return end\nlet main(): u32 = stop 1 2')
reject('arity',add..'let main(n: u32): unit = do defer add(n) return end')
-- A trapping argument must execute before the next suffix, not at final CALL.
-- An explicit checked IR trap uses reason 2; division-by-zero must win instead.
-- A separate memory-backed callee probe is retained in the experiment evidence.
local trapped=C.typed{profile='slet',source=add..[[
let bad(): u32 = 0
let main(n: u32): u32 = add(1 / n)(bad())
]]}
local S=require('let.schema');local I=S.Ir
for _,fn in ipairs(trapped.functions) do if fn.id=='bad' then
    table.insert(fn.body,1,I.Trap(I.Const(S.bool,I.Boolean(true)),'index-range'))
end end
for _,optimize in ipairs{false,true} do for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
    local ok,err=pcall(C.stage,trapped.functions,{profile='slet',entry='main',mode=mode,optimize=optimize,arguments={0}})
    check(not ok and D.is(err) and err.code=='static-division-zero','earlier division trap precedes later suffix: '..tostring(err))
    executions=executions+1
end end
print(('application chains: %d checks, %d VM executions'):format(checks,executions))
