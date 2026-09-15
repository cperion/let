package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('test.execute')
local count=0
local function check(value,message) assert(value,message); count=count+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual))); count=count+1
end
local read=B.Parameter(B.Text,A.Read)
local hosts={mark={symbol='mark',phase='runtime',purity='ordered',signature=B.Signature(L{read},L{B.Text})}}
local function build(source,extra)
    local options={hosts=hosts}
    for key,value in pairs(extra or {}) do options[key]=value end
    return V.parse(source,'program.let'):build(options)
end
-- Evaluates the module initializer and returns the namespace bundle.
local function module_namespace(program,host_functions)
    return execute(program.functions[1],{},host_functions or {},100000,program.functions)
end
local function field(order,name,namespace)
    for i,entry in ipairs(order) do if entry==name then return namespace.fields[i] end end
    error('no module binding ' .. name)
end

-- §17.1 Currying versus calling. `multiply 6 7` stays an uninvoked saturated word.
local program,builder=build[[
let multiply =
    let x : Int
    let y : Int
    do
        return x * y
    end
let double = multiply 2
let pending = multiply 6 7
let a = double(21)
let b = pending()
let c = multiply(6, 7)
]]
local ns=module_namespace(program)
eq(field(builder.module_order,'a',ns),42,'specialized word invoked')
eq(field(builder.module_order,'b',ns),42,'saturated word invoked explicitly')
eq(field(builder.module_order,'c',ns),42,'direct invocation')
check(type(field(builder.module_order,'pending',ns))=='table','a saturated word is a word value, not its result')

-- Invoking a partial word must not change it: a second call site still sees the
-- unsupplied receiver and supplies its own transient stages.
program,builder=build[[
let multiply = let x : Int let y : Int do return x * y end
let first = multiply(6, 7)
let second = multiply(3, 4)
]]
ns=module_namespace(program)
eq(field(builder.module_order,'first',ns),42,'first invocation of a partial word')
eq(field(builder.module_order,'second',ns),12,'a partial receiver is unchanged by an invocation')

-- §17.2 An inter-stage prelude runs when its stage is supplied, not at invocation.
program,builder=build[[
let affine =
    let scale : Int
    let bias : Int
    let twice_bias = bias * 2
    do
        return scale + twice_bias
    end
let configured = affine 10 16
let result = configured()
]]
ns=module_namespace(program)
eq(field(builder.module_order,'result',ns),42,'prelude value is stable state')

-- §20 Argument/prelude order: prelude between stages fires before the next argument.
program,builder=build[[
let staged =
    let first
    let prelude = mark("prelude")
    let second
    do
        return {}
    end
let result = staged(mark("first"), mark("second"))
]]
local events={}
ns=module_namespace(program,{mark=function(text) events[#events+1]=text; return text end})
eq(table.concat(events,','),'first,prelude,second','§20 prelude ordering')

-- §5.2 A data terminal returns data immediately and does not become an executable word.
program,builder=build[[
let pair =
    let left : Int
    let right : Int
    { left, right }
let p = pair 10 20
]]
ns=module_namespace(program)
local p=field(builder.module_order,'p',ns)
eq(p.fields[1],10,'positional data terminal, first element')
eq(p.fields[2],20,'positional data terminal, second element')

-- §15.1 A do terminal is the initialization body: its return is the namespace, and the
-- preludes stay the module's own state rather than becoming the namespace.
program,builder=build[[
let first = mark("a")
do
    return { let answer = 42 }
end
]]
ns=module_namespace(program,{mark=function(text) return text end})
eq(ns.fields[builder.module_exports.answer+1],42,'§15.1 a do terminal returns its namespace')

-- §15.1 New owned state in the namespace would have no unload path, because the host only
-- destroys the state the initializer returns as the module's own state.
local box_host={open={symbol='open',phase='runtime',purity='ordered',
    signature=B.Signature(L{B.Parameter(B.Int,A.Read)},L{B.Named('Box')})}}
local ok,err=pcall(function()
    build([[
let first = open(1)
do
    return { let fresh = open(9) }
end
]],{hosts=box_host,resources={Box={destroy='close'}}})
end)
check(not ok and tostring(err):find('may not construct new owned state'),
    '§15.1 a do terminal may not construct new owned state')
ok,err=pcall(function()
    build([[
let first = open(1)
do
    return { let shown = move first }
end
]],{hosts=box_host,resources={Box={destroy='close'}}})
end)
check(ok,'§15.1 a do terminal may move an owned prelude into its namespace')

-- §3.4 An invocation is a valid specialization atom. A word that comes back from a call is still
-- a word: its template and supplied count are in its type and its fields are the members of what
-- the callee returned, so it can be specialized and then invoked like any other.
program,builder=build[[
let adder = let x : Int
            do return x end
let make = do return adder end
let specialized = make() 7
let answer = specialized()
]]
ns=module_namespace(program)
eq(field(builder.module_order,'answer',ns),7,'§3.4 a word returned by a call can be specialized and invoked')

-- §10.2 Private mutable prelude state: two specializations do not share a counter.
program,builder=build[[
let counter =
    let start : Int
    let value mut = start
    do
        value = value + 1
        return value
    end
let errors = counter 0
let requests = counter 100
let first = errors()
let second = errors()
let third = requests()
]]
ns=module_namespace(program)
eq(field(builder.module_order,'first',ns),1,'first counter invocation')
eq(field(builder.module_order,'second',ns),2,'interior mutable state persists across invocations')
eq(field(builder.module_order,'third',ns),101,'independent specializations own distinct state')

-- §4.2 Self recursion through a tail transfer reuses one frame.
program,builder=build[[
let countdown =
    let n : Int
    do
        if n == 0 do
            return 0
        end
        return countdown(n - 1)
    end
let answer = countdown(20000)
]]
ns=module_namespace(program)
eq(field(builder.module_order,'answer',ns),0,'tail self recursion is bounded')

-- §11.2 `Executable` is a shape, not a type: the word an argument supplies is the stage's
-- type. The continuation idiom passes two words and invokes the selected one.
program,builder=build[[
let success = let value : Int do return value end
let failure = let code : Int do return -code end
let checked_divide =
    let ok : Executable
    let bad : Executable
    let numerator : Int
    let denominator : Int
    do
        if denominator == 0 do
            return bad(1)
        else
            return ok(numerator / denominator)
        end
    end
let divide = checked_divide success failure
let good = divide(84, 2)
let bad = divide(1, 0)
]]
ns=module_namespace(program)
eq(field(builder.module_order,'good',ns),42,'an Executable stage resolves to the word the argument supplies')
eq(field(builder.module_order,'bad',ns),-1,'and reaches the word the other branch selects')
check(builder.host_entry_skips.checked_divide~=nil,'an Executable stage leaves the word without a host entry')
check(tostring(builder.host_entry_skips.checked_divide):find('no type without an argument',1,true)~=nil,'and records why')

-- The supplied value must be an executable word, with a `do` terminal.
local function rejects(source)
    local ok=pcall(build,source)
    check(not ok,'expected a rejection: '..source)
end
rejects('let apply = let f : Executable do return f(1) end\nlet y = apply(3)')
rejects('let apply = let f : Executable do return f(1) end\nlet data = let n : Int; n + 1\nlet y = apply(data)')

print(('passed %d program construction checks'):format(count))
