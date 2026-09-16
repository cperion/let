-- Tagged unions (§11.5). A sum is Copy exactly when every alternative is, and a sum that holds a
-- non-Copy alternative is the reason the drop has to dispatch on the tag: only the active
-- alternative is a value, so only the active alternative is released. The interpreter oracle and
-- the emitted C must agree, so both are exercised here -- the shared semantics are §13, and this
-- is the elimination rule around them.
package.path='./?.lua;./?/init.lua;'..package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List; local execute=require('test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual)))
    checks=checks+1
end

-- A resource whose destructor counts, so an inactive alternative being released is visible.
local buffer=B.Named('Buf')
local contracts={
    open_buf={symbol='open_buf',phase='runtime',purity='pure',signature=B.Signature(L{B.Parameter(B.Int,A.Read)},L{buffer})},
    kill_buf={symbol='kill_buf',phase='runtime',purity='ordered',signature=B.Signature(L{B.Parameter(buffer,A.Own)},L{B.Unit})},
}
local options={hosts=contracts,resources={Buf={destroy='kill_buf'}}}
local killed=0
local implementations={open_buf=function(n) return n end, kill_buf=function(value) killed=killed+1 end}

-- Build, emit (so an unrepresentable sum fails here too), then run the module and answer with its
-- last binding. The sum type word lives inside the word because a module-level type word binding
-- is a separate, pre-existing gap.
local function run(source)
    local program=V.parse(source,'sum.let'):build(options)
    program:verify_flow(contracts)
    V.print(program:emit(options))
    local namespace=execute(program.functions[1],{},implementations,100000,program.functions)
    return namespace.fields[#namespace.fields]
end

-- The payload of the active alternative is released exactly once.
killed=0
eq(run([[
let probe = do : Int
    let Opt = Int or Buf
    let opened = open_buf(16);
    let value = Opt.right move opened;
    return 0
end
let result = probe()
]]),0,'a sum with an owned alternative builds and runs')
eq(killed,1,'§11.5 the active alternative is released through the tag')

-- An alternative that was never written owns nothing, so nothing is released.
killed=0
eq(run([[
let probe = do : Int
    let Opt = Int or Buf
    let value = Opt.left 65;
    return 0
end
let result = probe()
]]),0,'a sum holding a Copy alternative builds and runs')
eq(killed,0,'§11.5 an inactive alternative is never released')

-- Projection reads the active alternative.
killed=0
eq(run([[
let probe = do : Int
    let Opt = Int or Buf
    let value = Opt.left 65;
    return value.left
end
let result = probe()
]]),65,'§11.5 a projection reads the active alternative')

-- Moving the payload out leaves a hole, and the drop skips what the move already took.
killed=0
eq(run([[
let probe = do : Int
    let Opt = Int or Buf
    let opened = open_buf(16);
    let value = Opt.right move opened;
    let taken = move value.right;
    return 0
end
let result = probe()
]]),0,'a payload can be moved out of a sum')
eq(killed,1,'§11.5 a moved-out payload is released once, not twice')

-- A Copy sum is still Copy, and equality stays available.
local copy_sum=V.parse('let probe = do : Bool\n    let Opt = Int or Text\n    let a = Opt.left 65;\n    let b = Opt.left 65;\n    return a.tag == b.tag\nend\nlet result = probe()\n','copy.let'):build(options)
copy_sum:verify_flow(contracts)
V.print(copy_sum:emit(options))
local namespace=execute(copy_sum.functions[1],{},implementations,100000,copy_sum.functions)
eq(namespace.fields[#namespace.fields],true,'a Copy sum compares by its tag')

print(('passed %d tagged union checks'):format(checks))
