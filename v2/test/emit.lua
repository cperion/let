package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('v2'); local A,B,L=V.AST,V.Belt,V.List
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local read=B.Parameter(B.Int,A.Read)
local hosts={
    emit={symbol='emit',phase='runtime',purity='ordered',signature=B.Signature(L{read},L{B.Unit})},
    pure_calc={symbol='pure_calc',phase='runtime',purity='pure',signature=B.Signature(L{read},L{B.Int})},
}
local function emitted(source)
    local program=V.parse(source,'emit.let'):build{hosts=hosts}
    program:verify_flow(hosts)
    return V.print(program:emit{hosts=hosts})
end
-- Statement-level calls, so a prototype or declaration does not count.
local function calls(text,name)
    local found={}
    for line in text:gmatch('[^\n]+') do
        local argument=line:match('^%s+' .. name .. '%((.+)%)')
        if argument then found[#found+1]=argument end
    end
    return found
end
-- Callee definitions, so a test can assert how many words were emitted at all. The module
-- initializer and its unload function are the host interface, not callees.
local function definitions(text)
    local found={}
    for line in text:gmatch('[^\n]+') do
        local name=line:match('(let_[%w_]+)%s*%(')
        if name and line:find('%)%s*{%s*$') and name~='let_module_init' and name~='let_module_unload' then
            found[#found+1]=name
        end
    end
    return found
end
local function foldable(source) return #definitions(emitted(source))==0 end

-- Demand ---------------------------------------------------------------------------

local text=emitted[[
let f = do
    emit(1);
    let dead = 41 * 1000;
    let also_dead = 7 - 3;
    let unused_pure = pure_calc(2);
    emit(3);
    return 5
end
let r = f()
]]
check(not text:find('LET_MUL',1,true),'unused multiplication helper is not emitted')
check(not text:find('LET_SUB',1,true),'unused subtraction helper is not emitted')
check(not text:find('INT64_C(1000)',1,true),'unused literal operands are not emitted')
check(not text:find('pure_calc(v',1,true),'unused pure host call is not emitted')
local ordered=calls(text,'emit')
check(#ordered==2,'both ordered host calls remain')
check(ordered[1]:find('INT64_C(1)',1,true)~=nil,'first ordered call keeps its argument')
check(ordered[2]:find('INT64_C(3)',1,true)~=nil,'second ordered call keeps its argument')

-- A binding that no path reads must not survive as a loop packet field, because the
-- header/body/exit interfaces carry in-scope bindings across every backedge.
-- A run-time bound keeps a real loop, so the loop packet still exists to be pruned.
text=emitted[[
let g = do
    let unused = 99;
    let counter mut = 0;
    while counter < pure_calc(3) do
        counter = counter + 1
    end
    return counter
end
let s = g()
]]
check(not text:find('INT64_C(99)',1,true),'unused loop packet field and its literal are dropped')
check(text:find('LET_ADD',1,true)~=nil,'the demanded loop body is still emitted')
check(text:find('goto',1,true)~=nil,'a run-time bound keeps the loop')

-- A decidable loop with a pure body and no demanded result leaves nothing behind at all.
local folded=emitted[[
let g = do
    let counter mut = 0;
    while counter < 3 do
        counter = counter + 1
    end
    return counter
end
let s = g()
]]
check(not folded:find('goto',1,true),'a decidable loop is enumerated, not emitted')
check(#definitions(folded)==0,'an enumerated loop emits no callee function')

-- Folding: pure ------------------------------------------------------------------

check(foldable[[
let f = do
    let folded = 6 * 7;
    return folded
end
let r = f()
]],'pure arithmetic folds, so the entry is never emitted')

text=emitted[[
let f = do
    let kept mut = 0;
    if 1 == 2 do kept = 1 end
    return kept
end
let r = f()
]]
check(not text:find('LET_ADD',1,true) and not text:find('LET_MUL',1,true),'folding needs no helpers')
check(not text:find('if (',1,true),'a known condition removes the branch entirely')

-- §13.2: a known non-zero divisor is folded and its check omitted, while a possible
-- failure stays. A known zero divisor must remain observable rather than become a
-- compile-time diagnostic.
check(foldable[[
let f = do
    let quotient = 6 / 2;
    let remainder = -7 % 2;
    return quotient + remainder
end
let r = f()
]],'§16.2 known non-zero divisor folds and omits the check')

text=emitted[[
let f = do
    return 1 / 0
end
let r = f()
]]
check(text:find('let_div',1,true)~=nil,'a known zero divisor keeps a residual trapping operation')

text=emitted[[
let f =
    let n : Int
    do
        return n / 2
    end
let r = f(pure_calc(1))
]]
check(text:find('let_div',1,true)~=nil,'an unknown-during-analysis divisor keeps the check')

-- Folding: cross-function ---------------------------------------------------------

local program=V.parse([[
let multiply = let x : Int let y : Int do return x * y end
let pending = multiply 6 7
let counter = let start : Int let value mut = start do value = value + 1; return value end
let errors = counter 0
let a = pending()
let first = errors()
let second = errors()
]],'fold.let'):build{}
local full=V.print(program:emit{})
check(#definitions(full)==0,'a fully known call emits no callee function')
check(not full:find('LET_MUL',1,true) and not full:find('LET_ADD',1,true),'a fully known call emits no arithmetic helper')
check(full:find('INT64_C(42)',1,true)~=nil,'known call result 42 is a constant')
check(full:find('INT64_C(1)',1,true)~=nil and full:find('INT64_C(2)',1,true)~=nil,
    'two invocations of a known-state word fold to 1 then 2, threading the state')

-- Folding must stop where it cannot be justified. A pure host is never executed by the
-- compiler, so its result stays a runtime value and the callee keeps a real entry.
text=emitted[[
let multiply = let x : Int let y : Int do return x * y end
let a = multiply(pure_calc(1), 7)
]]
check(#definitions(text)>=1,'a runtime-argument call still emits its entry')
check(text:find('pure_calc(',1,true)~=nil,'a demanded pure host call stays in the C')

local effectful=V.parse([[
let noisy = let x : Int do print_mark(x); return x end
let r = noisy(5)
]],'effect.let'):build{hosts={print_mark={symbol='print_mark',phase='runtime',purity='ordered',
    signature=B.Signature(L{read},L{B.Unit})}}}
local effect_text=V.print(effectful:emit{hosts={print_mark={symbol='print_mark',phase='runtime',purity='ordered',
    signature=B.Signature(L{read},L{B.Unit})}}})
check(effect_text:find('print_mark',1,true)~=nil,'an ordered call inside a known packet is still emitted')
check(#definitions(effect_text)>=1,'a callee that demands ordered work keeps its entry')

-- Partial records ------------------------------------------------------------------

-- A record with a run-time member is answered member by member. Reading only the known
-- member therefore needs no record and no projection: the member's value is inlined and the
-- construction becomes undemanded. One run-time member used to make every member opaque.
-- The definition, not the prototype: the prototype line has no brace on it.
local function body(text,name)
    local from=text:find(name..'%([^\n]-{')
    if not from then return '' end
    local to=text:find('\n}',from) or #text
    return text:sub(from,to)
end

local partial=emitted[[
let f = let n : Int do
    let bag = { let factor = 6 let runtime = n };
    return bag.factor
end
let r = f(pure_calc(2))
]]
local f_body=body(partial,'let_f_3')
check(f_body:find('INT64_C%(6%)')~=nil,'a known member of a partial record is inlined')
check(f_body:find('%.f%d')==nil,'that read needs no projection')

-- Reading the run-time member still is a projection, and the record is still what carries
-- the two members, so the construction stays.
local through=emitted[[
let f = let n : Int do
    let bag = { let factor = 6 let runtime = n };
    return bag.runtime
end
let r = f(pure_calc(2))
]]
check(body(through,'let_f_3'):find('%.f%d')~=nil,'a run-time member is still projected')

-- Returning the whole record keeps it a value: the caller observes every member, so nothing
-- about it may be substituted in place of the record.
check(#definitions(emitted[[
let f = let n : Int do
    let bag = { let known = 1 let runtime = n };
    return bag
end
let r = f(pure_calc(2))
]])==1,'returning a partial record keeps its callee')


print(('passed %d v2 demand and folding emission checks'):format(checks))
