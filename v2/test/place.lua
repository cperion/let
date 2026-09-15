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
    open_buffer=function(n) events[#events+1]='open:'..tonumber(n); return tonumber(n) end,
    write_byte=function(a,i,v) events[#events+1]=('write:%d:%d'):format(tonumber(i),tonumber(v)) end,
    consume_buffer=function(b) events[#events+1]='consume:'..tonumber(b) end,
    close_buffer=function(b) events[#events+1]='close:'..tonumber(b) end,
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
eq(table.concat(events,','),'open:1024,write:0:42,consume:1024','§17.4 a mutable stage receives the caller place')

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

-- §8.4 A runtime index selects among the members. An aggregate is a record with as many
-- members as the source wrote, so the selection costs one comparison per member, and the
-- members must share a type because the selection's result is one value.
eq(run[[
let f = do
    let values = { 10, 20, 30 };
    let total mut = 0;
    let i mut = 0;
    while i < 3 do
        total = total + values[i];
        i = i + 1
    end
    return total
end
let r = f()
]],60,'§8.4 a runtime index reads the selected member')

eq(run[[
let f = do
    let values = { 10, 20, 30 };
    let i mut = 2;
    return values[i]
end
let r = f()
]],30,'§8.4 a runtime index selects the last member')

-- §9.4 Indexed assignment writes the selected member, and the out-of-range case traps
-- rather than being silently ignored.
eq(run[[
let f = do
    let a mut = { 1, 2, 3 };
    let i mut = 0;
    while i < 3 do
        a[i] = a[i] * 10;
        i = i + 1
    end
    return a[0] + a[1] + a[2]
end
let r = f()
]],60,'§9.4 indexed assignment through a runtime index')
eq(run[[
let f = do
    let a mut = { 1, 2 };
    a[0] = 9;
    return a[0] + a[1]
end
let r = f()
]],11,'§9.4 indexed assignment through a constant index')

local trapped=select(2,pcall(run,[[
let f = do
    let a mut = { 1, 2 };
    let i mut = 5;
    a[i] = 9;
    return a[0]
end
let r = f()
]]))
check(tostring(trapped):find('index out of range'),'§8.4 an out-of-range index traps')

-- A runtime index needs one member type, because the selection produces one value.
rejects([[
let f = do let v = { 1, "a" }; let i mut = 0; return v[i] end
let r = f()
]],'needs members of one type','§8.4 a runtime index over mixed members is rejected')

-- §9.3 A runtime index in a borrowed path selects a place rather than a value, so the
-- selection joins field addresses and the members must share one type.
eq(run[[
let bump = let p mut : Int let by : Int do p = p + by; return p end
let f = do
    let a mut = { 1, 2, 3 };
    let i mut = 0;
    while i < 3 do
        bump(mut a[i], 1);
        i = i + 1
    end
    return a[0] + a[1] + a[2]
end
let r = f()
]],9,'§9.3 a mutable borrow through a runtime index')
rejects([[
let bump = let p mut : Int let by : Int do p = p + by; return p end
let f = do
    let a mut = { 1, true };
    let i mut = 0;
    let r = bump(mut a[i], 1);
    return r
end
let r = f()
]],'needs members of one type','§9.3 a borrowed runtime index over mixed members is rejected')

-- §9.4 Assignment to a path rebuilds each level of it, so a nested place is writable and
-- every sibling keeps its value.
eq(run[[
let f = do
    let a mut = { let b mut = { let c mut = 1 let d = 2 } };
    a.b.c = 3;
    return a.b.c
end
let r = f()
]],3,'§9.4 assignment to a nested member')
eq(run[[
let f = do
    let a mut = { let b = { let c = 1 } let d = 5 };
    a.b.c = 9;
    return a.b.c + a.d
end
let r = f()
]],14,'§9.4 a nested write preserves its siblings')
eq(run[[
let f = do
    let a mut = { let b mut = { 0, 0 } };
    let i mut = 0;
    while i < 2 do
        a.b[i] = i + 10;
        i = i + 1
    end
    return a.b[0] + a.b[1]
end
let r = f()
]],21,'§9.4 a runtime index writes into a nested aggregate')

-- §8.3 A member declared mut is interior mutable state, so the whole path into it is
-- writable even though the root binding is not mut.
eq(run[[
let f = do
    let a = { let b = { let c mut = 1 } };
    a.b.c = 7;
    return a.b.c
end
let r = f()
]],7,'§8.3 interior mutability reaches through a nested path')
rejects([[
let f = do
    let a = { let b = { let c = 1 } };
    a.b.c = 7;
    return a.b.c
end
let r = f()
]],'immutable member','§8.3 a nested path with no mutable member is rejected')
rejects([[
let f = do
    let a mut = { { 1, 2 }, { 3, 4 } };
    let i = 0;
    a[i][1] = 9;
    return a[0][1]
end
let r = f()
]],'runtime index in the middle','§9.4 a runtime index in the middle of a path is rejected')

-- §9.2 Moving out of a subplace leaves that subplace uninitialized and the aggregate
-- partially initialized: the sibling is unaffected, and each buffer is released once, by
-- whichever binding owns it when it goes out of scope.
events={}
eq(run[[
let f = do
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    let moved = move a.b;
    return 0
end
let r = f()
]],0,'§9.2 moving a subplace out of an aggregate')
eq(table.concat(events,','),'open:1,open:2,close:1,close:2','§9.2 a moved subplace is released exactly once, by its new owner')
eq(run[[
let f = do
    let a = { let b = open_buffer(1) let c = 5 };
    let moved = move a.b;
    return a.c
end
let r = f()
]],5,'§9.2 a partially moved aggregate keeps its other subplaces')

rejects([[
let f = do
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    let moved = move a.b;
    return a.b
end
let r = f()
]],'uninitialized subplace','§9.2 reading a moved subplace is rejected')

-- Moving or handing out the aggregate as a value would consume a subplace that has no value.
rejects([[
let f = do
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    let moved = move a.b;
    let whole = move a;
    return 0
end
let r = f()
]],'partially initialized aggregate','§9.2 moving a partially initialized aggregate is rejected')
rejects([[
let f = do
    let a = { let p = { let b = open_buffer(1) let c = 5 } };
    let moved = move a.p.b;
    return a.p
end
let r = f()
]],'partially initialized subplace','§9.2 handing out a partially initialized subplace is rejected')

-- A deep read only names the subplace it reads, so a sibling inside the same record is fine.
eq(run[[
let f = do
    let a = { let p = { let b = open_buffer(1) let c = 5 } };
    let moved = move a.p.b;
    return a.p.c
end
let r = f()
]],5,'§9.2 a deep read passes through a partially initialized record')

-- Reassigning a subplace reinitializes that path, so a later read is legal and the hole is
-- released with the value that replaces it.
events={}
eq(run[[
let f = do
    let a mut = { let b = open_buffer(1) let c = open_buffer(2) };
    let moved = move a.b;
    a.b = open_buffer(9);
    return 0
end
let r = f()
]],0,'§9.2 assignment reinitializes a moved subplace')
eq(table.concat(events,','),'open:1,open:2,open:9,close:1,close:2,close:9','§9.2 a replaced hole is not released twice')

-- A positional element moves the same way, but the path must be statically known.
events={}
eq(run[[
let f = do
    let a = { open_buffer(1), open_buffer(2) };
    let moved = move a[0];
    return 0
end
let r = f()
]],0,'§9.2 a constant index moves one element')
eq(table.concat(events,','),'open:1,open:2,close:1,close:2','§9.2 an element moved by index is released once')
rejects([[
let f = do
    let a = { open_buffer(1), open_buffer(2) };
    let i = 0;
    let moved = move a[i];
    return 0
end
let r = f()
]],'statically known path','§9.2 a runtime path cannot be partially moved')

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
