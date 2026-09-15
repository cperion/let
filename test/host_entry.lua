-- Host entries: one minimal exported word per feature, each *executed* through the test
-- interpreter rather than inspected. The kernels exercise captures, preludes, mutable stages and
-- recursion at once, which is why each fix there moved the failure to a different kernel; this
-- file is the cheap instrument that should have come first.
package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual)))
    checks=checks+1
end

-- Builds a program and hands back the ways a host has into it: the exported words' entries, and
-- the namespace the initializer returned, from which a host reads a word's own fields.
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
    return {builder=builder,entries=entries,call=call,program=program,
        namespace=function() return (execute(program.functions[1],{},{},100000,program.functions)) end}
end

-- §5 An exported word whose stages are all still open takes one parameter per stage.
local host=build[[
let add = let a : Int let b : Int do return a + b end
]]
check(host.entries.add~=nil,'a two-stage word has a host entry')
eq(host.entries.add.bundle,0,'with no fields in front')
eq(host.entries.add.stages,2,'and both stages as parameters')
eq(host.call('add',20,22),42,'and the entry computes with them')

-- §6.2 A prelude between two stages runs *inside* the entry: the host supplies the stages, not
-- the prelude, so the name has to be bound by the entry rather than passed to it.
host=build[[
let between =
    let n : Int
    let step = n - 1;
    let total : Int
    do return total + step
end
]]
eq(host.entries.between.bundle,0,'a word with a prelude between stages has no fields yet')
eq(host.entries.between.stages,2,'and still takes both stages')
eq(host.call('between',5,10),14,'and the prelude runs in the entry')

-- §10.1 A captured word's capture is its first field, and the host reads it from the namespace
-- the initializer returned rather than conjuring it: that value is what the entry expects first.
host=build[[
let factor = 6;
let scale = let x : Int do return x * factor end
]]
eq(host.entries.scale.bundle,1,'a capture is a field the host passes')
eq(host.entries.scale.stages,1,'and the open stage follows it')
check(host.namespace()~=nil,'the initializer gives the host the namespace')
eq(host.call('scale',7,6),42,'the capture arrives as the first argument')

-- §8.4 A mutable stage is a place, so the host passes a pointer to its own storage and the entry
-- writes through it.
local holder={value=0}
host=build[[
let bump = let counter mut : Int let by : Int do counter = counter + by; return counter end
]]
eq(host.entries.bump.stages,2,'a mutable stage is one parameter')
eq(host.call('bump',holder,5),5,'the entry writes through the place it was given')
eq(holder.value,5,'and the write is visible to the host')

-- §5 A word with no stages left is still invokable, and its terminal is what the entry runs.
host=build[[
let fixed = let value : Int do return value + 1 end
let applied = fixed 41
]]
check(host.entries.applied~=nil,'an already-applied word still has an entry')
eq(host.entries.applied.stages,0,'with nothing left to supply')
eq(host.call('applied',41),42,'and its terminal runs on the field the host passed')

-- A stage whose type only an argument can determine -- unannotated, or `Copy` -- cannot be a host
-- entry, because the host has no argument to learn it from. The word is still legal; it simply
-- has no entry, and the builder says why.
host=build[[
let generic = let anything do return anything end
]]
check(host.entries.generic==nil,'a stage without a type has no host entry')
check(host.builder.host_entry_skips.generic~=nil,'and the builder records why')



-- The host can only call an entry that was written out, so an entry is a root of emission: it
-- has no caller inside the belt, and without this nothing would make it live.
host=build[[
let add = let a : Int let b : Int do return a + b end
]]
local statistics={}
local unit=host.program:emit{hosts={},entries=host.builder.host_entries,statistics=statistics}
local text=V.print(unit)
check(statistics.entries~=nil and #statistics.entries==1,'the entry is reported to the host')
local entry=statistics.entries[1]
check(entry.c_name~=nil,'with the C name the host calls')
check(text:find(entry.c_name..'(int64_t',1,true)~=nil,'and that function is emitted')
check(text:find('#define LET_ADD',1,true)~=nil,'and it computes')

-- The shipped path is a host, and it must publish the entries: this is the check whose absence let
-- every exported word be dead-code eliminated through `luajit let.lua in.let out.c`.
local shipped='/tmp/let_host_shipped'
os.execute('rm -rf '..shipped..' && mkdir -p '..shipped)
os.execute(('cp dist/let.lua %s/let.lua'):format(shipped))
local input=assert(io.open(shipped..'/demo.let','wb'))
input:write('let twice = let n : Int do return n * 2 end\nlet answer = twice(21)\n')
input:close()
os.execute(('cd %s && luajit let.lua demo.let demo.c'):format(shipped))
local emitted=assert(io.open(shipped..'/demo.c','rb')):read('*a')
local name=emitted:match('extern int64_t (let_[%w_]*_host)%(')
check(name~=nil,'the command-line compiler publishes an entry instead of eliminating it')
check(emitted:find('let_trap')~=nil and emitted:find('INT64_C',1,true)~=nil,'and the entry is a real function')
check(emitted:find('static int64_t '..name,1,true)==nil,'named for the linker, so a host can call it')

-- The ABI the host actually links against. A C main calls the emitted entry the way the host
-- will: the word's own fields first, then the stages it still needs, and a mutable stage is a
-- pointer to the host's own storage.
local function compile_and_run(name,unit_text,statistics,main)
    local stem='/tmp/let_host_entry_' .. name
    local out=assert(io.open(stem .. '.c','wb'))
    out:write(unit_text)
    out:write('\nvoid let_trap(char* reason){ (void)reason; __builtin_trap(); }\n')
    out:write(main)
    out:close()
    local status=os.execute(('cc -std=c11 -O1 -w %s.c -o %s && %s'):format(stem,stem,stem))
    return status
end

local native_host=build[[
let add = let a : Int let b : Int do return a + b end
let bump = let counter mut : Int let by : Int do counter = counter + by; return counter end
]]
local native_statistics={}
local native_text=V.print(native_host.program:emit{hosts={},entries=native_host.builder.host_entries,
    statistics=native_statistics})
local names={}
for _,entry in ipairs(native_statistics.entries) do names[entry.name]=entry.c_name end
check(names.add~=nil and names.bump~=nil,'both entries are published to the host')
local status=compile_and_run('abi',native_text,native_statistics,
    ('int main(void){ let_module_init(); if (%s(20,22)!=42) return 1; int64_t value=40;'):format(names.add)..
    (' if (%s(&value,2)!=42) return 2; if (value!=42) return 3; return 0; }'):format(names.bump))
eq(status,0,'a C main calls the entries and the mutable one writes through its pointer')

print(('passed %d host-entry checks'):format(checks))
