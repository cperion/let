-- Real programs, which must build, emit and run (§7). The per-mechanism suites prove each
-- mechanism in isolation; this is the only place that asks whether they *compose*, and that is where
-- the defects found by writing programs actually lived -- a qualifier dropped between the value form
-- and the type form of a record, a sum that claimed not to own its payload, a fold whose body could
-- not be passed as a word.
--
-- Each program is a module whose last binding is the observable result. A program that needs a host
-- declares it here, next to the program that uses it, so this file reads as the contract the
-- language is being asked to keep. The expected result is stated with the program, because a program
-- with no stated result is a program nobody checked.
package.path='./?.lua;./?/init.lua;'..package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual)))
    checks=checks+1
end

local function source(name)
    local file=assert(io.open('test/programs/'..name..'.let','rb'),'missing test program '..name)
    local text=file:read('*a'); file:close(); return text
end

-- A resource whose release is counted, so a drop is observable rather than assumed.
local thing=B.Named('Thing')
local releases
local thing_contracts={
    make={symbol='make',phase='runtime',purity='ordered',
        signature=B.Signature(L{B.Parameter(B.Int,A.Read)},L{thing})},
}
local thing_implementations={
    make=function(handle) return handle end,
    kill=function(handle) releases=releases+1 end,
}
local thing_options={hosts=thing_contracts,resources={Thing={destroy='kill'}}}

local programs={
    {name='fold',result=7},
    {name='fold_variable',result=8},
    {name='borrow_place',result=7},
    {name='mutable_member',result=2},
    {name="sum_drop",result=0,options=thing_options,implementations=thing_implementations,
        before=function() releases=0 end,
        after=function() eq(releases,1,'sum_drop: the owned payload is released exactly once') end},
}

for _,program in ipairs(programs) do
    local options=program.options or {}
    if program.before then program.before() end
    local built=V.parse(source(program.name),program.name..'.let'):build(options)
    built:verify_flow(options.hosts)
    -- Rendering is part of the contract: an unrepresentable value fails here, not at a C compiler
    -- the suite does not run.
    V.print(built:emit(options))
    local namespace=execute(built.functions[1],{},program.implementations or {},100000,built.functions)
    eq(namespace.fields[#namespace.fields],program.result,program.name..': the expected result')
    if program.after then program.after() end
end

-- Programs the language *refuses*, and the reason it gives. A refusal and a gap read
-- differently on purpose: one means rewrite the program, the other means the compiler is
-- missing something. Sharing a word for both is why an ownership error once arrived
-- prefixed "construction not yet implemented". So the prefix is asserted absent, and the
-- reason present.
local refusals={
    {name='break outside a loop',source=[[
let run = do : Int break return 0 end
let answer = run()
]],fragment='break outside a loop'},
    {name='continue outside a loop',source=[[
let run = do : Int continue return 0 end
let answer = run()
]],fragment='continue outside a loop'},
}
for _,case in ipairs(refusals) do
    local ok,err=pcall(function()
        V.parse(case.source,case.name..'.let'):build({hosts=thing_contracts,resources={Thing={destroy='kill'}}})
    end)
    check(not ok,case.name..': expected the language to refuse it')
    if not ok then
        check(tostring(err):find(case.fragment,1,true)~=nil,
            case.name..': expected the reason to name '..case.fragment..', got '..tostring(err))
        check(tostring(err):find('construction not yet implemented',1,true)==nil,
            case.name..': a refusal must not read like a gap, got '..tostring(err))
    end
end

print(('passed %d real-program checks'):format(checks))
