package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler');local D=require('let.diag')
local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function execute(unit,args,wanted)
 for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
  local result=C.stage(unit.functions,{profile='slet',entry='main',mode=mode,optimize=false,arguments=args or {}})
  executions=executions+1;check(tonumber(result.cells[1])==wanted,mode..' result')
 end
 return unit
end
local function run(source,args,wanted)
 return execute(C.typed{profile='slet',source=source,name='vocabulary.slet'},args,wanted)
end
local function reject(code,source)
 local ok,err=pcall(C.typed,{profile='slet',source=source,name='vocabulary-reject.slet'})
 check(not ok and D.is(err) and err.code==code,code..': '..tostring(err));return err
end
run([[
let Context = { amount: u32, action: (u32): u32 }
let plus_two(n: u32): u32 = n + 2
let with_context(n: u32, body: (Context): u32): u32 = body(Context { amount = n, action = plus_two })
let main(n: u32): u32 = with_context(n) do(ctx...)
 return action(amount)
end
]],{40},42)
run([[
let Context = { amount: u32 }
let main(n: u32): u32 = do
 let ctx = Context { amount = n }
 let ctx...
 ctx.amount = 99
 return amount + 2
end
]],{40},42)
run([[
let Context = { amount: u32 }
let make(n: u32): Context = Context { amount = n }
let main(n: u32): u32 = do
 let ctx... = make(n)
 ctx.amount = 99
 return amount + 2
end
]],{40},42)
reject('spread-shadow',[[
let Context = { amount: u32 }
let main(n: u32): u32 = do
 let amount = n
 let f(ctx...: Context): u32 = do return 0 end
 return f(Context { amount = 1 })
end
]])
reject('spread-shadow','let Context = { u32: u32 }; let main(ctx...: Context): u32 = do return 0 end')
reject('spread-shadow','let Context = { n: u32 }; let main(ctx...: Context, n: u32): u32 = do return n end')
reject('spread-source','let main(ctx...: u32): u32 = do return ctx end')
run([[
let Option = oneof { none: unit, some: u32 }
let main(n: u32): u32 = do
 let Option...
 let value = some(n)
 return value { none = do() = 0, some = do(x: u32) = x + 2 }
end
]],{40},42)
run([[
let Context = { amount: u32 }
let Tracker = { calls: u32, make(n: u32): Context = do calls += 1 return Context { amount = n } end }
let main(n: u32): u32 = do
 let t = Tracker { calls = 0 }
 let ctx... = t.make(n)
 ctx.amount = 90
 return amount + t.calls + 1
end
]],{40},42)
run([[
let Child = { value: u32, bump(n: u32): u32 = do value += n return value end }
let Context = { child: Child }
let main(n: u32): u32 = do
 let ctx = Context { child = Child { value = n } }
 let ctx...
 ctx.child.value = 90
 return child.bump(2)
end
]],{40},42)
run([[
let Context = { amount: u32 }
let use_context(ctx...: Context): u32 = do let nested(): u32 = amount + 2 return nested() end
let main(n: u32): u32 = use_context(Context { amount = n })
]],{40},42)
reject('slet-forbidden',[[
let Context = { amount: u32 }
let escape(ctx...: Context) = do return do() = amount end
let main(n: u32): u32 = escape(Context { amount = n })()
]])
reject('unknown-name',[[
let Context = { amount: u32, method(): u32 = amount }
let main(ctx...: Context): u32 = do return method() end
]])
reject('spread-shadow',[[
let Context = { amount: u32 }
let main(): u32 = do let ctx = Context { amount = 1 } let ctx... let ctx... return amount end
]])
reject('spread-shadow','let Context = { ctx: u32 }; let main(ctx...: Context): u32 = do return 0 end')
reject('definition-value','let Context = { amount: u32 }; let main(): u32 = Context + 1')
-- One public spelling denotes one binding, even across export sections. Alias
-- targets may be shared when the public names themselves are distinct.
for _,exports in ipairs{
 'types = { Thing = Record }, functions = { Thing = answer }',
 'functions = { Thing = answer }, types = { Thing = Record }',
 'types = { Record }, functions = { Record = answer }',
 'types = { Thing = Record, Thing = Record }, functions = {}',
 'functions = { answer, answer }',
 'functions = { Thing = answer, Thing = answer }',
} do
 reject('duplicate-name','let Record = { value: u32 }; let answer(): u32 = 42; return { '..exports..' }')
end
-- Duplicate public names are rejected before invalid alias resolution/static work.
reject('duplicate-name','return { types = { clash = Missing }, functions = { clash = absent } }')
execute(C.typed{profile='slet',source=[[
let Record = { value: u32 }
let main(): u32 = 42
return { types = { First = Record, Second = Record }, functions = { main, answer = main }, results = { [main] = u32 } }
]]},{},42)
local separate=C.typed{profile='slet',source=[[
let Record = { value: u32 }
let answer(): u32 = 42
return { types = { PublicRecord = Record }, functions = { Record = answer } }
]]}
check(separate.namespace.members.Record.kind=='word' and separate.namespace.members.PublicRecord.kind=='type',
 'private type spelling may be a distinct public word alias')
separate=C.typed{profile='slet',source=[[
let Record = { value: u32 }
let answer(): u32 = 42
return { types = { answer = Record }, functions = { public_answer = answer } }
]]}
check(separate.namespace.members.answer.kind=='type' and separate.namespace.members.public_answer.kind=='word',
 'private word spelling may be a distinct public type alias')
local directory=os.tmpname();os.remove(directory);assert(os.execute('mkdir -p '..directory)==0)
local function file(name,text)
 local handle=assert(io.open(directory..'/'..name..'.slet','w'));handle:write(text);handle:close()
end
file('lib',[[
let Record = { value: u32 }
let Option = oneof { none: unit, some: u32 }
let inc(n: u32): u32 = n + 1
let private(n: u32): u32 = n + 100
return { types = { Record, Option }, functions = { inc } }
]])
file('main',[[
use lib...
let main(n: u32): u32 = do
 let r = Record { value = n }
 let Option...
 let value = some(r.value)
 return value { none = do() = 0, some = do(x: u32) = inc(x) }
end
]])
execute(C.typedFile(directory..'/main.slet'),{41},42)
file('main',[[
use lib
let names... = lib
let helper(r: Record): u32 = inc(r.value)
let main(n: u32): u32 = helper(Record { value = n })
]])
execute(C.typedFile(directory..'/main.slet'),{41},42)
file('main',[[
use lib
let early(n: u32): u32 = inc(n)
let lib...
let main(n: u32): u32 = early(n)
]])
local ok,err=pcall(C.typedFile,directory..'/main.slet')
check(not ok and D.is(err) and err.code=='unknown-name','earlier body cannot see later expansion: '..tostring(err))
file('main',[[
use lib...
let answer = later(41)
let later(n: u32): u32 = inc(n)
let main(): u32 = answer
]])
execute(C.typedFile(directory..'/main.slet',{staticMode='interpreted'}),{},42)
file('main',[[
use lib...
let Alias = Record
let through(r: Alias): u32 = inc(r.value)
let main(n: u32): u32 = through(Alias { value = n })
]])
execute(C.typedFile(directory..'/main.slet'),{41},42)
file('main',[[
use lib
let main(n: u32): u32 = do let names... = lib return inc(n) end
]])
execute(C.typedFile(directory..'/main.slet'),{41},42)
file('mid',[[
use lib...
return { types = { Record }, functions = { inc } }
]])
file('main',[[
use mid...
let main(n: u32): u32 = inc(n)
]])
local reexported=C.typedFile(directory..'/main.slet')
execute(reexported,{41},42)
check(reexported.modules[directory..'/mid.slet'].namespace.members.inc==reexported.modules[directory..'/lib.slet'].namespace.members.inc,'re-export preserves definition identity')
check(not reexported.modules[directory..'/mid.slet'].namespace.members.Option,'expansion does not implicitly re-export')
file('main','use lib...; let inc(n: u32): u32 = n; let main(): u32 = 0')
ok,err=pcall(C.typedFile,directory..'/main.slet')
check(not ok and D.is(err) and err.code=='spread-shadow','later explicit declarations participate in collision checking: '..tostring(err))
file('main','use lib; let main(): u32 = lib.private(1)')
ok,err=pcall(C.typedFile,directory..'/main.slet')
check(not ok and D.is(err) and err.code=='unknown-field','private declarations are excluded: '..tostring(err))
file('lib',[[
let helper(n: u32): u32 = n + 2
let Record = { value: u32, answer(): u32 = helper(value) }
return { types = { Record }, functions = {} }
]])
file('main','use lib...; let main(n: u32): u32 = do let r = Record { value = n } return r.answer() end')
execute(C.typedFile(directory..'/main.slet'),{40},42)
file('base',[[
let value(n: u32): u32 = n + 100
return { functions = { value } }
]])
file('lib',[[
use base...
let Record = { value: u32, answer(): u32 = value + 2 }
return { types = { Record }, functions = {} }
]])
file('main','use lib...; let main(n: u32): u32 = do let r = Record { value = n } return r.answer() end')
execute(C.typedFile(directory..'/main.slet'),{40},42)
file('main','use lib; let main() = lib')
ok,err=pcall(C.typedFile,directory..'/main.slet')
check(not ok and D.is(err) and err.code=='definition-value','namespace cannot escape through runtime results: '..tostring(err))
file('main','use lib; let main(): u32 = do let lib... let lib... return 0 end')
ok,err=pcall(C.typedFile,directory..'/main.slet')
check(not ok and D.is(err) and err.code=='spread-shadow','duplicate local module expansion rejects: '..tostring(err))
file('cycle_a','use cycle_b...; let a(): u32 = 1; return { functions = { a } }')
file('cycle_b','use cycle_a...; let b(): u32 = 2; return { functions = { b } }')
ok,err=pcall(C.typedFile,directory..'/cycle_a.slet')
check(not ok and D.is(err) and err.code=='import-cycle','import expansion preserves cycle checking: '..tostring(err))
file('foreign_lib',[[
extern let hidden_host(n: u32): u32
return { functions = { public_host = hidden_host } }
]])
file('main','use foreign_lib; let main(n: u32): u32 = hidden_host(n)')
ok,err=pcall(C.typedFile,directory..'/main.slet')
check(not ok and D.is(err) and err.code=='unknown-name','dependency ABI symbols are not source imports: '..tostring(err))
file('main','use foreign_lib...; let main(n: u32): u32 = public_host(n)')
local foreignUnit=C.typedFile(directory..'/main.slet')
check(#foreignUnit.unit.foreigns==1 and foreignUnit.unit.foreigns[1].target=='hidden_host',
 'explicit public foreign aliases retain their ABI declaration')
assert(os.execute('rm -r '..directory)==0)
print(('vocabulary: %d checks, %d VM executions'):format(checks,executions))
