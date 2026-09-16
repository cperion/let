package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('test.execute')
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
    buffer_size={symbol='buffer_size',phase='runtime',purity='ordered',
        signature=B.Signature(L{B.Parameter(buffer,A.Read)},L{B.Int})},
},resources={Buffer={destroy='close_buffer'}}}
local events,live={},{}
local host_functions={
    open_buffer=function(n)
        local handle=tonumber(n); live[handle]=true
        events[#events+1]='open:'..handle; return handle
    end,
    write_byte=function(a,i,v) events[#events+1]=('write:%d:%d'):format(tonumber(i),tonumber(v)) end,
    consume_buffer=function(b) events[#events+1]='consume:'..tonumber(b) end,
    buffer_size=function(b) return live[tonumber(b)] and 1 or 0 end,
    close_buffer=function(b)
        local handle=tonumber(b)
        if not live[handle] then events[#events+1]='DOUBLE-CLOSE:'..handle end
        live[handle]=nil; events[#events+1]='close:'..handle
    end,
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
let example = do : Unit
    let buffer mut = open_buffer(1024);
    write_byte(mut buffer, 0, 42);
    consume_buffer(move buffer)
end
let r = example()
]]
eq(table.concat(events,','),'open:1024,write:0:42,consume:1024','§17.4 a mutable stage receives the caller place')

-- §6.3 A user word with an `own` stage takes the argument from the call site, not from a host:
-- the argument is transferred to the callee, which uses it and destroys it exactly once. The
-- result is only 1 if the callee could still reach the live buffer.
events={}
eq(run[[
let consume =
    let buffer own : Buffer
    do : Int
        let bytes = buffer_size(buffer);
        return bytes
    end
let main = do : Int
    let first = open_buffer(16);
    let left = consume(move first);
    return left
end
let answer = main()
]],1,'a user word owns its own-stage argument and destroys it once')
eq(table.concat(events,','),'open:16,close:16','§6.3 the callee destroys the argument after using it')

-- §5.4 A prelude resource an invocation reaches is invocation-local, but it must outlive the
-- callee's use of it: the entry that receives it owns and destroys it, not the call site.
events={}
eq(run[[
let use =
    let n : Int
    let buf = open_buffer(n)
    do : Int
        let bytes = buffer_size(buf);
        return bytes
    end
let main = do : Int
    let r = use(16);
    return r
end
let answer = main()
]],1,'a resource prelude outlives the callee that reads it')
eq(table.concat(events,','),'open:16,close:16','and is destroyed once, by the entry that received it')

-- §6.3 A mutable stage writes the caller's place, so the change is visible afterwards.
eq(run[[
let bump = let counter mut : Int let by : Int do : Int counter = counter + by; return counter end
let f = do : Int let n mut = 40; let r = bump(mut n, 2); return r + n end
let r = f()
]],84,'§6.3 the callee writes the caller place')

eq(run[[
let take = let p mut : Int do : Int p = p + 5; return p end
let f = do : Int let n mut = 37; let r = take(mut n); return r + n end
let r = f()
]],84,'an address-taken Copy local round-trips through memory')

-- §9.3 Any subplace can be lent, not only a whole binding: a member of an aggregate is
-- reached by a field address, so the callee writes the owner's field.
eq(run[[
let bump = let p mut : Int let by : Int do : Int p = p + by; return p end
let f = do : Int
    let a mut = { let x = 1 let y = 2 };
    let r = bump(mut a.x, 40);
    return a.x + r
end
let r = f()
]],82,'§9.3 a mutable borrow of a projected member')
eq(run[[
let bump = let p mut : Int let by : Int do : Int p = p + by; return p end
let f = do : Int
    let a mut = { 1, 2 };
    let r = bump(mut a[0], 40);
    return a[0] + r
end
let r = f()
]],82,'§9.3 a mutable borrow of a constant index')
eq(run[[
let bump = let p mut : Int let by : Int do : Int p = p + by; return p end
let f = do : Int
    let a mut = { let b = { let c = 1 } };
    let r = bump(mut a.b.c, 40);
    return a.b.c + r
end
let r = f()
]],82,'§9.3 a mutable borrow of a nested member')

-- §9.4 Assignment through a projected member of a place writes the owner's storage rather
-- than replacing the place's address with a record.
eq(run[[
let touch = let box mut : { let x : Int let y : Int } let n : Int do : Int return n end
let f = do : Int
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
let f = do : Int
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
let f = do : Int
    let values = { 10, 20, 30 };
    let i mut = 2;
    return values[i]
end
let r = f()
]],30,'§8.4 a runtime index selects the last member')

-- §9.4 Indexed assignment writes the selected member, and the out-of-range case traps
-- rather than being silently ignored.
eq(run[[
let f = do : Int
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
let f = do : Int
    let a mut = { 1, 2 };
    a[0] = 9;
    return a[0] + a[1]
end
let r = f()
]],11,'§9.4 indexed assignment through a constant index')

local trapped=select(2,pcall(run,[[
let f = do : Int
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
let f = do : Int let v = { 1, "a" }; let i mut = 0; return v[i] end
let r = f()
]],'needs members of one type','§8.4 a runtime index over mixed members is rejected')

-- §9.3 A runtime index in a borrowed path selects a place rather than a value, so the
-- selection joins field addresses and the members must share one type.
eq(run[[
let bump = let p mut : Int let by : Int do : Int p = p + by; return p end
let f = do : Int
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
let bump = let p mut : Int let by : Int do : Int p = p + by; return p end
let f = do : Int
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
let f = do : Int
    let a mut = { let b mut = { let c mut = 1 let d = 2 } };
    a.b.c = 3;
    return a.b.c
end
let r = f()
]],3,'§9.4 assignment to a nested member')
eq(run[[
let f = do : Int
    let a mut = { let b = { let c = 1 } let d = 5 };
    a.b.c = 9;
    return a.b.c + a.d
end
let r = f()
]],14,'§9.4 a nested write preserves its siblings')
eq(run[[
let f = do : Int
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
let f = do : Int
    let a = { let b = { let c mut = 1 } };
    a.b.c = 7;
    return a.b.c
end
let r = f()
]],7,'§8.3 interior mutability reaches through a nested path')
rejects([[
let f = do : Int
    let a = { let b = { let c = 1 } };
    a.b.c = 7;
    return a.b.c
end
let r = f()
]],'immutable member','§8.3 a nested path with no mutable member is rejected')
-- §8.4 An index yields a mutable element place, and a projection through it is still a
-- place, so a runtime index may appear in the middle of an assignment path. The suffix after
-- it is resolved against the member's type, which must therefore be one type.
eq(run[[
let f = do : Int
    let a mut = { { 1, 2 }, { 3, 4 } };
    let i = 1;
    a[i][1] = 9;
    return a[0][1] + a[1][1]
end
let r = f()
]],11,'§9.4 assignment through a runtime index in the middle of a path')
eq(run[[
let f = do : Int
    let a mut = { let p mut = { let b mut = 1 let c = 2 } let q mut = { let b mut = 10 let c = 20 } };
    let i = 1;
    a[i].b = 40;
    return a[0].b + a[0].c + a[1].b
end
let r = f()
]],43,'§9.4 mid-path runtime index on a named member')
eq(run[[
let f = do : Int
    let a mut = { let p mut = { let b mut = { let c mut = 1 } } let q mut = { let b mut = { let c mut = 5 } } };
    let i = 1;
    a[i].b.c = 7;
    return a[0].b.c + a[1].b.c
end
let r = f()
]],8,'§9.4 mid-path runtime index with a nested suffix')
rejects([[
let f = do : Int
    let a mut = { { 1, 2 }, { 3, 4 } };
    let i = 0;
    let j = 1;
    a[i][j] = 9;
    return 0
end
let r = f()
]],'two runtime indices','§9.4 two runtime indices in one path are rejected')

-- §9.2 A Copy value owns no state to remove, so `move` of a Copy place is a copy: the
-- place stays initialized and the value is indistinguishable from a read.
eq(run[[
let f = do : Int
    let x = 42;
    let y = move x;
    return x + y - 41
end
let r = f()
]],43,'§9.2 moving a Copy binding leaves it initialized')
eq(run[[
let f = do : Int
    let a = { let b = 42 let c = 5 };
    let y = move a.b;
    return a.b + y - 41
end
let r = f()
]],43,'§9.2 moving a Copy member leaves the aggregate whole')
eq(run[[
let f = do : Int
    let a = { 10, 20 };
    let y = move a[0];
    return a[0] + y
end
let r = f()
]],20,'§9.2 moving a Copy positional element')
eq(run[[
let twice = let n : Int do : Int return n + n end
let f = do : Int
    let x = 3;
    return twice(move x)
end
let r = f()
]],6,'§9.2 a Copy argument may be spelled move')

-- §9.2 A plain stage receives a read-only borrow "for the invocation", so the caller keeps
-- ownership: the value is still there afterwards, and the caller releases it once.
events={} ; live={}
eq(run[[
let touch = let b : Buffer do : Int return 0 end
let f = do : Int
    let b = open_buffer(1);
    let n = touch(b);
    consume_buffer(move b);
    return n
end
let r = f()
]],0,'§9.2 a plain stage borrows its non-Copy argument')
eq(table.concat(events,','),'open:1,consume:1',
    '§9.2 the argument survives the borrow and stays the caller\'s to release')
eq(run[[
let f = do : Int
    let b = open_buffer(4);
    let n = buffer_size(b);
    return n
end
let r = f()
]],1,'§9.2 a plain stage reads a live value')

-- §9.2 A word's own locals are activation state even when the word has no stages, so its
-- return destroys them rather than leaving them in the word's retained state scope.
events={} ; live={}
eq(run[[
let f = do : Int
    let b = open_buffer(2);
    return 0
end
let r = f()
]],0,'§9.2 a word with no stages releases its locals')
eq(table.concat(events,','),'open:2,close:2','§9.2 the local is released exactly once')

-- §6.5 A tail invocation retires this activation, so it can neither borrow an argument for
-- the call nor hand the callee a borrow of a local. Both are ownership errors, not gaps.
rejects([[
let f = do : Int return buffer_size(open_buffer(3)) end
let r = f()
]],'cannot borrow an argument for the call','§6.5 a tail call cannot borrow a temporary')
rejects([[
let f = do : Int
    let b = open_buffer(3);
    return buffer_size(b)
end
let r = f()
]],'does not outlive caller cleanup','§6.5 a tail call cannot pass a local borrow')

-- §9.2 A move on one arm of a branch leaves the aggregate partially initialized on that
-- path only, so the state of a subplace can be a run-time fact. Destruction guards it, the
-- same way conditional destruction of a whole binding is guarded (§6.5).
events={}
eq(run[[
let f = do : Int
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    let k = 1;
    if k == 1 do
        let gone = move a.b;
    end
    return 0
end
let r = f()
]],0,'§9.2 a partial move on one branch')
eq(table.concat(events,','),'open:1,open:2,close:1,close:2',
    '§9.2 the moved subplace is released by its new owner and the rest by the aggregate')

-- The other branch did not move it, so the aggregate still releases it -- the guard must not
-- turn a conditional move into a leak.
events={}
eq(run[[
let f = do : Int
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    let k = 2;
    if k == 1 do
        let gone = move a.b;
    end
    return 0
end
let r = f()
]],0,'§9.2 a branch that did not move the subplace')
eq(table.concat(events,','),'open:1,open:2,close:2,close:1',
    '§9.2 a subplace that was not moved is still released once by the aggregate')

-- §9.4 Replacing a subplace whose state is a run-time fact releases the old value only where
-- one is still there.
events={}
eq(run[[
let f = do : Int
    let a mut = { let b = open_buffer(1) let c = open_buffer(2) };
    let k = 2;
    if k == 1 do
        let gone = move a.b;
    end
    a.b = open_buffer(9);
    return 0
end
let r = f()
]],0,'§9.4 assignment over a subplace that may have been moved')
eq(table.concat(events,','),'open:1,open:2,open:9,close:1,close:2,close:9',
    '§9.4 a possibly-moved old value is released once, and only when it is still there')
rejects([[
let f = do : Int
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    let k = 1;
    if k == 1 do
        let gone = move a.b;
    end
    return a.b
end
let r = f()
]],'may be uninitialized','§9.2 reading a subplace that may be uninitialized is rejected')

-- §7.3 an expression may be a statement, and §9.2 admits `move place` as an expression. A
-- bare `move a.b` therefore transfers ownership of the subplace; the discarded value is
-- destroyed at the discard, and the aggregate is left with a hole it no longer releases.
events={}
eq(run[[
let f = do : Int
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    move a.b
    return 0
end
let r = f()
]],0,'§9.2 a bare `move place` statement transfers ownership')
eq(table.concat(events,','),'open:1,open:2,close:1,close:2',
    '§9.2 the discarded move releases its value, and the aggregate releases only the rest')

-- §9.2 A hole introduced inside a loop is diagnosed: the loop entry's fact would have to be
-- dynamic for a backedge to carry the hole, and the body's own move then reads a place that
-- is only *maybe* initialized. That is an analysis limit, not an illegal program.
rejects([[
let f = do : Int
    let a mut = { let b = open_buffer(1) let c = 2 };
    let i mut = 0;
    while i < 2 do
        if i == 0 do
            let gone = move a.b;
        end
        i = i + 1
    end
    return a.c
end
let r = f()
]],'path%-sensitive initialization analysis','§9.2 a hole introduced inside a loop needs path-sensitive facts')

-- §9.2 Moving out of a subplace leaves that subplace uninitialized and the aggregate
-- partially initialized: the sibling is unaffected, and each buffer is released once, by
-- whichever binding owns it when it goes out of scope.
events={}
eq(run[[
let f = do : Int
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    let moved = move a.b;
    return 0
end
let r = f()
]],0,'§9.2 moving a subplace out of an aggregate')
eq(table.concat(events,','),'open:1,open:2,close:1,close:2','§9.2 a moved subplace is released exactly once, by its new owner')
eq(run[[
let f = do : Int
    let a = { let b = open_buffer(1) let c = 5 };
    let moved = move a.b;
    return a.c
end
let r = f()
]],5,'§9.2 a partially moved aggregate keeps its other subplaces')

rejects([[
let f = do : Int
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    let moved = move a.b;
    return a.b
end
let r = f()
]],'uninitialized subplace','§9.2 reading a moved subplace is rejected')

-- Moving or handing out the aggregate as a value would consume a subplace that has no value.
rejects([[
let f = do : Int
    let a = { let b = open_buffer(1) let c = open_buffer(2) };
    let moved = move a.b;
    let whole = move a;
    return 0
end
let r = f()
]],'partially initialized aggregate','§9.2 moving a partially initialized aggregate is rejected')
rejects([[
let f = do : Int
    let a = { let p = { let b = open_buffer(1) let c = 5 } };
    let moved = move a.p.b;
    return a.p
end
let r = f()
]],'partially initialized subplace','§9.2 handing out a partially initialized subplace is rejected')

-- A deep read only names the subplace it reads, so a sibling inside the same record is fine.
eq(run[[
let f = do : Int
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
let f = do : Int
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
let f = do : Int
    let a = { open_buffer(1), open_buffer(2) };
    let moved = move a[0];
    return 0
end
let r = f()
]],0,'§9.2 a constant index moves one element')
eq(table.concat(events,','),'open:1,open:2,close:1,close:2','§9.2 an element moved by index is released once')
rejects([[
let f = do : Int
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
let take = let p mut : Int do : Int p = p + 5; return p end
let f = do : Int let n mut = 37; return take(mut n) end
let r = f()
]],'tail invocation borrow does not outlive caller cleanup','§6.5 a tail call cannot pass a caller-owned place')

-- §10.1 A non-escaping word captures an owned binding as a borrow, so the two share state
-- and mutation through the capture is visible to the owner.
eq(run[[
let counter = let start : Int let v mut = start do : Int v = v + 1; return v end
let c = counter 0
let f = do : Int let r = c(); return r end
let a = f()
let b = f()
let d = c()
]],3,'§10.1 a captured word shares its owner state (the last value is 3)')

-- The capture is a borrow of the *owner*, so it cannot leave the activation that owns it.
rejects([[ 
let make = do : do Int
    let counter = let start : Int let v mut = start do : Int v = v + 1; return v end
    let c = counter 0
    let f = do : Int let r = c(); return r end
    return move f
end
let g = make()
]],'borrows activation state','§10.1 a borrow of activation-local state cannot be returned')

-- A capture used only inside its own activation is fine.
eq(run[[
let make = do : Int
    let counter = let start : Int let v mut = start do : Int v = v + 1; return v end
    let c = counter 0
    let f = do : Int let r = c(); return r end
    let r = f();
    return r + f()
end
let g = make()
]],3,'§10.1 a local borrow used within its activation is allowed')

-- §9.2 Only a mutable binding can be lent mutably, and only a borrowed place may be passed
-- to a mutable stage.
rejects([[
let take = let p mut : Int do : Int p = p + 1; return p end
let f = do : Int let n = 1; return take(mut n) end
let r = f()
]],'mutable borrow requires a mutable binding','an immutable binding cannot be lent mutably')
rejects([[
let take = let p mut : Int do : Int p = p + 1; return p end
let f = do : Int let n mut = 1; return take(n) end
let r = f()
]],'mutable stage requires mut place','a mutable stage refuses a plain value')

-- The address is what makes it a place: the emitted C declares a local and takes its
-- address, and the load/store go through it.
local text=emitted[[
let bump = let p mut : Int let by : Int do : Int p = p + by; return p end
let f = do : Int let n mut = 40; let r = bump(mut n, 2); return r end
let r = f()
]]
check(text:find('(&v',1,true)~=nil,'an address-taken local is a C local whose address is taken')
check(text:find('int64_t* p1_1',1,true)~=nil,'a mutable stage is a pointer parameter, not a copy')
check(text:find('(*p1_1) =',1,true)~=nil,'the callee writes through that pointer')

-- Taking an address must not turn *other* mutable state into memory: a word's mutable
-- prelude is not borrowed, so it stays SSA and still folds.
local folded=emitted([[
let counter = let start : Int let v mut = start do : Int v = v + 1; return v end
let c = counter 0
let a = c()
let b = c()
]])
check(not folded:find('LET_ADD',1,true),'an unborrowed mutable prelude still folds')
check(folded:find('INT64_C(2)',1,true)~=nil,'and its successive values are constants')

print(('passed %d place/borrow checks'):format(checks))
