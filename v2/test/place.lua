package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('v2'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('v2.test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual))); checks=checks+1
end

-- §17.4's hosts, with the mutable stage declaring the *Let* type: the address is the
-- builder's business, not the host's.
local buffer=B.Named('Buffer')
local options={hosts={
    open_buffer={symbol='open_buffer',phase='runtime',purity='ordered',
        signature=B.Signature(L{B.Parameter(B.Int,A.Read)},L{buffer})},
    write_byte={symbol='write_byte',phase='runtime',purity='ordered',
        signature=B.Signature(L{B.Parameter(buffer,A.Mut),B.Parameter(B.Int,A.Read),B.Parameter(B.Int,A.Read)},L{B.Unit})},
    consume_buffer={symbol='consume_buffer',phase='runtime',purity='ordered',
        signature=B.Signature(L{B.Parameter(buffer,A.Own)},L{B.Unit})},
},resources={Buffer={destroy='close_buffer'}}}
local events={}
local host_functions={
    open_buffer=function(n) events[#events+1]='open:'..tonumber(n); return 7 end,
    write_byte=function(a,i,v) events[#events+1]=('write:%d:%d'):format(tonumber(i),tonumber(v)) end,
    consume_buffer=function(b) events[#events+1]='consume:'..tonumber(b) end,
    close_buffer=function() events[#events+1]='close' end,
}
local function run(source)
    local program=V.parse(source,'place.let'):build(options)
    program:verify_flow(options.hosts)
    local namespace=execute(program.functions[1],{},host_functions,100000,program.functions)
    return namespace.fields[#namespace.fields]
end
local function rejects(source,pattern,description)
    local ok,err=pcall(function() V.parse(source,'place.let'):build(options) end)
    check(not ok and tostring(err):find(pattern),
        ('%s: expected %q, got %s'):format(description or 'rejection',pattern,tostring(err):gsub('\n.*','')))
end
local function emitted(source,opts)
    local program=V.parse(source,'place.let'):build(opts or options)
    program:verify_flow((opts or options).hosts)
    return V.print(program:emit(opts or options))
end

-- §17.4 The canonical visible-ownership-transfer example: `mut buffer` lends the caller's
-- place, and moving afterwards transfers the resource out of it.
events={}
run[[
let example = do
    let buffer mut = open_buffer(1024);
    write_byte(mut buffer, 0, 42);
    consume_buffer(move buffer)
end
let r = example()
]]
eq(table.concat(events,','),'open:1024,write:0:42,consume:7','§17.4 a mutable stage receives the caller place')

-- §6.3 A mutable stage writes the caller's place, so the change is visible afterwards.
eq(run[[
let bump = let counter mut : Int let by : Int do counter = counter + by; return counter end
let f = do let n mut = 40; let r = bump(mut n, 2); return r + n end
let r = f()
]],84,'§6.3 the callee writes the caller place')

eq(run[[
let take = let p mut : Int do p = p + 5; return p end
let f = do let n mut = 37; let r = take(mut n); return r + n end
let r = f()
]],84,'an address-taken Copy local round-trips through memory')

-- §9.3 Any subplace can be lent, not only a whole binding: a member of an aggregate is
-- reached by a field address, so the callee writes the owner's field.
eq(run[[
let bump = let p mut : Int let by : Int do p = p + by; return p end
let f = do
    let a mut = { let x = 1 let y = 2 };
    let r = bump(mut a.x, 40);
    return a.x + r
end
let r = f()
]],82,'§9.3 a mutable borrow of a projected member')
eq(run[[
let bump = let p mut : Int let by : Int do p = p + by; return p end
let f = do
    let a mut = { 1, 2 };
    let r = bump(mut a[0], 40);
    return a[0] + r
end
let r = f()
]],82,'§9.3 a mutable borrow of a constant index')
eq(run[[
let bump = let p mut : Int let by : Int do p = p + by; return p end
let f = do
    let a mut = { let b = { let c = 1 } };
    let r = bump(mut a.b.c, 40);
    return a.b.c + r
end
let r = f()
]],82,'§9.3 a mutable borrow of a nested member')

-- §9.4 Assignment through a projected member of a place writes the owner's storage rather
-- than replacing the place's address with a record.
eq(run[[
let touch = let box mut let n : Int do return n end
let f = do
    let a mut = { let x = 1 let y = 2 };
    let r = touch(mut a, 5);
    a.x = 9;
    return a.x + a.y
end
let r = f()
]],11,'§9.4 assignment through a projected member of a place')

-- §6.5 A tail transfer retires the activation, so a borrow of one of its places cannot be
-- passed: the callee would outlive the storage.
rejects([[ 
let take = let p mut : Int do p = p + 5; return p end
let f = do let n mut = 37; return take(mut n) end
let r = f()
]],'tail invocation borrow does not outlive caller cleanup','§6.5 a tail call cannot pass a caller-owned place')

-- §10.1 A non-escaping word captures an owned binding as a borrow, so the two share state
-- and mutation through the capture is visible to the owner.
eq(run[[
let counter = let start : Int let v mut = start do v = v + 1; return v end
let c = counter 0
let f = do let r = c(); return r end
let a = f()
let b = f()
let d = c()
]],3,'§10.1 a captured word shares its owner state (the last value is 3)')

-- The capture is a borrow of the *owner*, so it cannot leave the activation that owns it.
rejects([[ 
let make = do
    let counter = let start : Int let v mut = start do v = v + 1; return v end
    let c = counter 0
    let f = do let r = c(); return r end
    return move f
end
let g = make()
]],'borrows activation state','§10.1 a borrow of activation-local state cannot be returned')

-- A capture used only inside its own activation is fine.
eq(run[[
let make = do
    let counter = let start : Int let v mut = start do v = v + 1; return v end
    let c = counter 0
    let f = do let r = c(); return r end
    let r = f();
    return r + f()
end
let g = make()
]],3,'§10.1 a local borrow used within its activation is allowed')

-- §9.2 Only a mutable binding can be lent mutably, and only a borrowed place may be passed
-- to a mutable stage.
rejects([[
let take = let p mut : Int do p = p + 1; return p end
let f = do let n = 1; return take(mut n) end
let r = f()
]],'mutable borrow requires a mutable binding','an immutable binding cannot be lent mutably')
rejects([[
let take = let p mut : Int do p = p + 1; return p end
let f = do let n mut = 1; return take(n) end
let r = f()
]],'mutable stage requires mut place','a mutable stage refuses a plain value')

-- The address is what makes it a place: the emitted C declares a local and takes its
-- address, and the load/store go through it.
local text=emitted[[
let bump = let p mut : Int let by : Int do p = p + by; return p end
let f = do let n mut = 40; let r = bump(mut n, 2); return r end
let r = f()
]]
check(text:find('(&v',1,true)~=nil,'an address-taken local is a C local whose address is taken')
check(text:find('int64_t* p1_1',1,true)~=nil,'a mutable stage is a pointer parameter, not a copy')
check(text:find('(*p1_1) =',1,true)~=nil,'the callee writes through that pointer')

-- Taking an address must not turn *other* mutable state into memory: a word's mutable
-- prelude is not borrowed, so it stays SSA and still folds.
local folded=emitted([[
let counter = let start : Int let v mut = start do v = v + 1; return v end
let c = counter 0
let a = c()
let b = c()
]])
check(not folded:find('LET_ADD',1,true),'an unborrowed mutable prelude still folds')
check(folded:find('INT64_C(2)',1,true)~=nil,'and its successive values are constants')

print(('passed %d v2 place/borrow checks'):format(checks))
