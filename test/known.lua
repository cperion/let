package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual))); checks=checks+1
end
local runtime=B.Parameter(B.Int,A.Read)
local hosts={runtime_int={symbol='runtime_int',phase='runtime',purity='pure',signature=B.Signature(L{runtime},L{B.Int})}}
local function emitted(source)
    local program=V.parse(source,'known.let'):build{hosts=hosts}
    program:verify_flow(hosts)
    return V.print(program:emit{hosts=hosts})
end
-- Executes the module initializer and returns the last binding's value.
local function result(source)
    local program=V.parse(source,'known.let'):build{hosts=hosts}
    local namespace=execute(program.functions[1],{}, {}, 100000, program.functions)
    return namespace.fields[#namespace.fields]
end

-- A loop whose trip count is decidable and whose body is pure is enumerated, so the loop
-- disappears and its result is a constant.
local text=emitted[[
let run = do
    let bias = 7
    let total mut = 0
    let i mut = 0
    while i < 3 do
        total = total + bias * 2;
        i = i + 1
    end
    return total
end
let answer = run()
]]
check(not text:find('goto',1,true),'a decidable pure loop is not emitted at all')
check(not text:find('LET_MUL',1,true) and not text:find('LET_ADD',1,true),'no loop arithmetic survives')
check(text:find('INT64_C(42)',1,true)~=nil,'the loop folds to its final value')

-- A loop whose bound is only known at run time cannot be enumerated, so it is emitted and
-- analyzed with widening instead.
text=emitted[[
let run = do
    let bias = 7
    let total mut = 0
    let i mut = 0
    while i < runtime_int(3) do
        total = total + bias * 2;
        i = i + 1
    end
    return total
end
let answer = run()
]]
check(text:find('goto',1,true)~=nil,'a run-time bound leaves a real loop')
check(not text:find('LET_MUL',1,true),'the loop invariant still folds inside the emitted loop')
check(text:find('INT64_C(14)',1,true)~=nil,'the invariant is a constant inside the loop')
check(text:find('LET_ADD',1,true)~=nil,'the varying part is still computed')

-- Soundness: an induction variable must widen, not be mistaken for a constant. The check
-- is execution, because a wrong constant would still look plausible in the C.
eq(result[[
let run = do
    let i mut = 0;
    while i < 4 do
        i = i + 1
    end
    return i
end
let answer = run()
]],4,'an induction variable widens to a runtime value')

eq(result[[
let run = do
    let i mut = 0;
    let acc mut = 0;
    while i < 4 do
        i = i + 1;
        acc = acc + i
    end
    return acc
end
let answer = run()
]],10,'an accumulator widens and still computes the right value')

-- A value that is invariant only inside the loop stays known there, but a value that
-- varies must not leak a constant out of the loop.
eq(result[[
let run = do
    let base = 5;
    let i mut = 0;
    let seen mut = 0;
    while i < 3 do
        seen = seen + base;
        i = i + 1
    end
    return seen + base
end
let answer = run()
]],20,'a loop-invariant capture folds while the accumulator varies')

-- Nested loops must settle rather than iterate forever, and must still be correct.
eq(result[[
let run = do
    let outer mut = 0;
    let total mut = 0;
    while outer < 3 do
        let inner mut = 0;
        while inner < 3 do
            total = total + 1;
            inner = inner + 1
        end;
        outer = outer + 1
    end
    return total
end
let answer = run()
]],9,'nested loops settle and compute correctly')

-- A loop whose condition is known false never runs; its body must not become a constant.
eq(result[[
let run = do
    let i mut = 0;
    let acc mut = 7;
    while i > 100 do
        acc = acc + 1;
        i = i + 1
    end
    return acc
end
let answer = run()
]],7,'a never-entered loop leaves its variables alone')

print(('passed %d loop-widening checks'):format(checks))
