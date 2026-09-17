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

-- The libc words the corpus uses, implemented over a Lua table so a buffer program can run in the
-- interpreter rather than only under a C compiler. A handle indexes a table of bytes.
local memory,next_handle={},0
local libc_implementations={
    malloc=function(n) next_handle=next_handle+1; memory[next_handle]={}; return next_handle end,
    free=function(handle) memory[handle]=nil end,
    -- The index arrives as an Int, which on LuaJIT is int64 cdata, and two equal cdata values are
    -- not the same table key. So the fake memory keys on the number it stands for.
    let_store_byte=function(handle,index,value) memory[handle][tonumber(index)]=value end,
    let_load_byte=function(handle,index) return memory[handle][tonumber(index)] or 0 end,
}
local libc_options={dictionary={c={members=V.libc.members}},resources={CAlloc=V.libc.resources.CAlloc}}

local programs={
    {name='fold',result=7},
    {name='fold_variable',result=8},
    {name='borrow_place',result=7},
    {name='mutable_member',result=2},
    -- A call whose argument splits the block: `cells[i]` traps when the index is out of range, so
    -- the callee's captured field crosses a boundary on the way to the call.
    {name='capture_element',result=16},
    -- §6.5 A tail transfer to the same word carries that word's mutable state as its packet, so the
    -- recursion is a loop with the state as a loop variable and the write-back happens once, on the
    -- way out. It is 3 + 2 + 1.
    {name='tail_state',result=6},
    -- §6.5 A tail call may borrow a value the word does not own: the word's *prelude* lives in its
    -- bundle rather than in the activation, so the borrow survives the transfer. This was refused
    -- as "tail invocation borrow does not outlive caller cleanup", and the same code with the
    -- buffer as a body local is correctly refused -- see the refusals below.
    {name='tail_prelude',result=7,options=libc_options,implementations=libc_implementations},
    {name="sum_drop",result=0,options=thing_options,implementations=thing_implementations,
        before=function() releases=0 end,
        after=function() eq(releases,1,'sum_drop: the owned payload is released exactly once') end},
    -- §9.2/§10.1 An address-taken owned local whose liveness is a run-time fact at the scope's end.
    -- The guard releases it where it is still there, and the `move` released it where it is not --
    -- one release either way, which is what makes the pair a test of the guard rather than of the
    -- program: an unconditional release gives two in the moved arm and none gives zero.
    {name='conditional_drop',result=0,options=thing_options,implementations=thing_implementations,
        before=function() releases=0 end,
        after=function() eq(releases,1,'conditional_drop: the value still here is released once') end},
    {name='conditional_drop_moved',result=0,options=thing_options,implementations=thing_implementations,
        before=function() releases=0 end,
        after=function() eq(releases,1,'conditional_drop_moved: the moved value was released once, and not twice') end},
}

for _,program in ipairs(programs) do
    local options=program.options or {}
    if program.before then program.before() end
    local built=V.parse(source(program.name),program.name..'.let'):build(options)
    -- `emit` verifies the flow itself, with the vocabulary's symbols -- so a host reached through a
    -- dictionary (`c.malloc`) is covered, which an explicit `verify_flow(options.hosts)` was not.
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
    -- The counterpart of the corpus's `tail_prelude`: the same code with the buffer as a body
    -- local instead of a prelude is a borrow that really does die with the activation, so the
    -- refusal must stay.
    {name='tail borrow of a body local',options=libc_options,source=[[
let read_at = let i : Int do : Int
    let cells = c.malloc(4);
    return c.load_byte(cells, i)
end
let answer = read_at(0)
]],fragment='tail invocation borrow does not outlive caller cleanup'},
}
for _,case in ipairs(refusals) do
    local ok,err=pcall(function()
        local options=case.options or {hosts=thing_contracts,resources={Thing={destroy='kill'}}}
        V.parse(case.source,case.name..'.let'):build(options)
    end)
    check(not ok,case.name..': expected the language to refuse it')
    if not ok then
        check(tostring(err):find(case.fragment,1,true)~=nil,
            case.name..': expected the reason to name '..case.fragment..', got '..tostring(err))
        check(tostring(err):find('construction not yet implemented',1,true)==nil,
            case.name..': a refusal must not read like a gap, got '..tostring(err))
    end
end

-- Programs the compiler cannot build yet. A gap and a refusal read differently on purpose -- one
-- means the compiler is missing a mechanism, the other means the program is wrong -- so the prefix
-- is asserted *present* here, the opposite of the checks above.
local gaps={
    -- The state has to come back through the result, and a transfer to a different word has nowhere to
    -- put it: the callee's signature is its own. A self transfer does have somewhere -- its packet is
    -- the state -- which is why `tail_state` above builds.
    {name='a tail transfer to a different word, from a word whose state must be written back',
     source=[[
let total mut = 0
let helper = let n : Int do : Int return n end
let run = let n : Int do : Int
    total = total + n;
    return helper(n)
end
let r = run(1)
]],
     fragment='tail invocation from a word whose state must be written back, to a different word'},
}
for _,case in ipairs(gaps) do
    local ok,err=pcall(function() V.parse(case.source,case.name..'.let'):build{} end)
    check(not ok,case.name..': expected the compiler to say it cannot build this')
    if not ok then
        check(tostring(err):find('construction not yet implemented',1,true)~=nil,
            case.name..': expected a gap rather than a refusal, got '..tostring(err))
        check(tostring(err):find(case.fragment,1,true)~=nil,
            case.name..': expected the reason to name '..case.fragment..', got '..tostring(err))
    end
end

print(('passed %d real-program checks'):format(checks))
