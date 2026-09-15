-- Host entries: one minimal exported word per feature, each *executed* through the test
-- interpreter rather than inspected. The kernels exercise captures, preludes, mutable stages and
-- recursion at once, which is why each fix there moved the failure to a different kernel; this
-- file is the cheap instrument that should have come first.
package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('v2'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('v2.test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual)))
    checks=checks+1
end

-- Builds a program, returns the builder (for its host entries) and a way to call one.
local function build(source,options)
    local program,builder=V.parse(source,'entry.let'):build(options or {})
    program:verify_flow((options or {}).hosts or {})
    local entries={}
    for _,entry in ipairs(builder.host_entries or {}) do entries[entry.name]=entry end
    local function call(name,...)
        local entry=assert(entries[name],'no host entry for ' .. name)
        local fn=assert(program.functions[entry.id],'host entry has no function')
        return execute(fn,{...},{},100000,program.functions)
    end
    return builder,entries,call
end

-- §5 An exported word whose stages are all still open takes one parameter per stage.
local builder,entries,call=build[[
let add = let a : Int let b : Int do return a + b end
]]
check(entries.add~=nil,'a two-stage word has a host entry')
eq(entries.add.bundle,0,'with no fields in front')
eq(entries.add.stages,2,'and both stages as parameters')
eq(call('add',20,22),42,'and the entry computes with them')

-- §6.2 A prelude between two stages runs *inside* the entry: the host supplies the stages, not
-- the prelude, so the name has to be bound by the entry rather than passed to it.
builder,entries,call=build[[
let between =
    let n : Int
    let step = n - 1;
    let total : Int
    do return total + step
end
]]
eq(entries.between.bundle,0,'a word with a prelude between stages has no fields yet')
eq(entries.between.stages,2,'and still takes both stages')
eq(call('between',5,10),14,'and the prelude runs in the entry')

-- §10.1 A captured word's capture is its first field, so the host passes it from the namespace.
builder,entries,call=build[[
let factor = 6;
let scale = let x : Int do return x * factor end
]]
eq(entries.scale.bundle,1,'a capture is a field the host passes')
eq(entries.scale.stages,1,'and the open stage follows it')
eq(call('scale',7,0),42,'the capture arrives as the first argument')

-- §8.4 A mutable stage is a place, so the host passes an address of its own storage.
local holder={value=0}
local function mutate(value) holder.value=value end
builder,entries,call=build[[
let bump = let p mut : Int let by : Int do p = p + by; return p end
]]
eq(entries.bump.stages,2,'a mutable stage is still one parameter')
eq(call('bump',holder,5),5,'the entry writes through the place it was given')
eq(holder.value,5,'and the write is visible to the host')

print(('passed %d v2 host-entry checks'):format(checks))
