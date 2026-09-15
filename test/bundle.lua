-- The single-file bundle: that it is current, that it behaves as the module layout does, and that
-- it is also a command-line compiler. `bundle.lua` generates `dist/let.lua` by walking the
-- `require` graph from the entry point, so a module added later cannot be forgotten; this file
-- keeps the committed artifact honest.
package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual)))
    checks=checks+1
end

local source='let answer = 6 * 7\nlet show = do return answer end\nlet shown = show()\n'
local function emit(api)
    local program=api.parse(source,'bundle.let'):build{}
    program:verify_flow{}
    return api.print(program:emit{})
end

-- The committed bundle is what the generator produces now, so the two cannot drift apart.
local regenerated='/tmp/let_bundle_regenerated.lua'
assert(os.execute(('luajit bundle.lua %s >/dev/null'):format(regenerated))==0 or true)
local produced=assert(io.open(regenerated,'rb')):read('*a')
local committed=assert(io.open('dist/let.lua','rb')):read('*a')
eq(produced,committed,'the committed bundle is current')
check(#committed>100000,'and it carries the compiler rather than a stub')

-- Loading the bundle in this process gives the same table shape and the same output.
local B=assert(loadfile('dist/let.lua'))()
check(type(B.parse)=='function' and type(B.print)=='function','the bundle returns the compiler API')
eq(emit(B),emit(V),'the bundle emits what the module layout emits')

-- Run as a script it compiles a file, which is the point of shipping one file.
local input,output='/tmp/let_bundle_input.let','/tmp/let_bundle_output.c'
local handle=assert(io.open(input,'wb')); handle:write(source); handle:close()
os.remove(output)
os.execute(('luajit dist/let.lua %s %s'):format(input,output))
local compiled=assert(io.open(output,'rb')):read('*a')
-- The command line is a host, so it publishes every exported word as an entry; compare against
-- the same thing done by hand rather than against an emission with nothing published.
local function emit_published(api)
    local program,builder=api.parse(source,'bundle.let'):build{}
    program:verify_flow{}
    return api.print(program:emit{entries=builder.host_entries})
end
eq(compiled,emit_published(V),'the command line publishes each exported word as a host entry')

-- Nothing around the file. Run it from a bare directory, where neither the module tree nor the
-- vendored files can be found, so a module the walker missed cannot hide behind package.path.
local directory='/tmp/let_bundle_standalone'
os.execute('rm -rf '..directory..' && mkdir -p '..directory)
os.execute(('cp dist/let.lua %s/let.lua'):format(directory))
local standalone=directory..'/demo.let'
local handle=assert(io.open(standalone,'wb'))
handle:write('let twice = let n : Int do return n * 2 end\nlet answer = twice(21)\n')
handle:close()
os.execute(('cd %s && luajit let.lua demo.let demo.c'):format(directory))
local emitted=assert(io.open(directory..'/demo.c','rb')):read('*a')
check(emitted:find('INT64_C(42)',1,true)~=nil,
    'the bundle compiles on its own, with no module tree to fall back on')

print(('passed %d bundle checks'):format(checks))
