package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual))); checks=checks+1
end
local box=B.Named('Box')
local open={symbol='open',phase='runtime',purity='ordered',
    signature=B.Signature(L{B.Parameter(B.Int,A.Read)},L{box})}
local options={hosts={open=open},resources={Box={destroy='close'}}}
local events={}
local host_functions={
    open=function(n) events[#events+1]='open:'..tonumber(n); return n end,
    close=function(b) events[#events+1]='close:'..tonumber(b) end,
}
local function rejects(source,pattern,description)
    local ok,err=pcall(function() V.parse(source,'aggregate.let'):build(options) end)
    check(not ok and tostring(err):find(pattern),
        ('%s: expected %q, got %s'):format(description or 'rejection',pattern,tostring(err):gsub('\n.*','')))
end

-- Runs the module initializer and returns the last module binding's value.
local function run(source,opts)
    local build_options={}
    for key,value in pairs(options) do build_options[key]=value end
    for key,value in pairs(opts or {}) do build_options[key]=value end
    local program=V.parse(source,'aggregate.let'):build(build_options)
    program:verify_flow(build_options.hosts)
    local namespace=execute(program.functions[1],{},host_functions,100000,program.functions)
    return namespace.fields[#namespace.fields],program
end
local function result(source,opts)
    local value=run(source,opts)
    return value
end

-- §8.1 Named aggregates expose exactly their direct members, read by projection.
eq(result[[
let point = { let x = 10 let y = 20 }
let r = point.x + point.y
]],30,'§8.1 named projection')

-- §8.2 Positional elements are zero-based, and the length is static.
eq(result[[
let rgb = { 255, 128, 32 }
let r = rgb[0] + rgb[2]
]],287,'§8.2 positional indexing')
eq(result[[
let nested = { { 1, 2 }, { 3, 4 } }
let r = nested[1][0]
]],3,'§8.2 nested indexing')

-- §8.3 Projection never invokes, and works inside a callee that captured the aggregate.
eq(result[[
let service = { let value = 40 let name = 2 }
let show = do : Int return service.value + service.name end
let r = show()
]],42,'§8.3 projection through a capture')

-- §8.3 A member declared mut stays writable through an immutable owning binding.
eq(result[[
let f = do : Int
    let record = { let value mut = 0 let label = 1 };
    record.value = 5;
    return record.value + record.label
end
let r = f()
]],6,'§8.3 interior mutable member')
eq(result[[
let f = do : Int
    let record mut = { let value = 0 let label = 1 };
    record.value = 5;
    return record.value + record.label
end
let r = f()
]],6,'§8.3 member of a mutable record')
rejects([[
let f = do : Int let record = { let value = 0 }; record.value = 5; return record.value end
let r = f()
]],'immutable member','§8.3 immutable member is rejected')

-- §8.5 An aggregate owns its members and destroys them in reverse initialization order.
events={}
run[[
let f = do : Int
    let pair = { let first = open(1) let second = open(2) };
    return 0
end
let r = f()
]]
eq(table.concat(events,','),'open:1,open:2,close:2,close:1','§8.5 reverse member destruction')

events={}
run[[
let f = do : Int
    let outer = { let inner = { open(1), open(2) } let second = open(3) };
    return 0
end
let r = f()
]]
eq(table.concat(events,','),'open:1,open:2,open:3,close:3,close:2,close:1','§8.5 nested reverse destruction')

events={}
run[[
let f = do : Int
    let pair = { let first = open(1) let second = open(2) };
    let moved = move pair;
    return 0
end
let r = f()
]]
eq(table.concat(events,','),'open:1,open:2,close:2,close:1','§8.5 a moved aggregate destroys its members once')

-- §8.5 An aggregate containing owned state is not Copy.
rejects([[
let f = do : Int
    let pair = { open(1) };
    let alias = pair;
    return 0
end
let r = f()
]],'move','§8.5 an owning aggregate is not Copy')

-- §17.3 A named aggregate of words; projection returns the word and the following
-- invocation runs it. The word is rebuilt from the record, so it works through a capture.
eq(result[[
let arithmetic = {
    let add = let x : Int let y : Int do : Int return x + y end
    let negate = let x : Int do : Int return -x end
}
let show = do : Int return arithmetic.add(40, 2) + arithmetic.negate(7) end
let r = show()
]],35,'§17.3 projected word invocation through a capture')
eq(result[[
let arithmetic = { let add = let x : Int let y : Int do : Int return x + y end }
let r = arithmetic.add(40, 2)
]],42,'§17.3 projected word invocation at module level')

-- The diagnostic must say why rather than silently mis-lower the program.
-- §8.4 A runtime index is resolved by selecting among the members (test/place.lua covers the
-- trap and the mixed-member diagnostic).
eq(result[[
let rgb = { 1, 2, 3 }
let f = do : Int let i = 1; return rgb[i] end
let r = f()
]],2,'§8.4 a runtime index reads the selected member')
rejects([[
let point = { let x = 1 }
let r = point.y
]],'no member y','unknown member name')
rejects([[
let rgb = { 1, 2, 3 }
let r = rgb[7]
]],'outside the valid range','a constant out-of-range index is diagnosed')

-- §8.3 A named member declared `mut` is an interior mutable place. It is part of the record's
-- type, so the record is not Copy, and it stays writable through a `mut` borrow even though
-- the containing binding need not be -- while a read-only borrow does not grant the write.
check(result[[
let Counter = { let at mut : Int let stop : Int }
let bump = let c mut : Counter do : Int
    c.at = c.at + 1;
    return c.at
end
let run = do : Int
    let c mut = Counter 0 4;
    let first = bump(mut c);
    let second = bump(mut c);
    return second
end
let answer = run()
]]==2,'a `mut` member is writable through a mutable borrow')
check(result[[
let Counter = { let at mut : Int let stop : Int }
let run = do : Int
    let c = Counter 0 4;
    return c.at
end
let answer = run()
]]==0,'a `mut` member is readable through an immutable binding')
rejects([[
let Counter = { let at mut : Int let stop : Int }
let c = Counter 0 4
let d = c
]],'move or a fresh result','a record with a `mut` member is not Copy')

print(('passed %d aggregate/projection checks'):format(checks))
