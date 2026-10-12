-- Production ASDL frontend -> revision-6 ABC -> shared optimizer -> VM.
-- The retired direct source-to-assembly bootstrap is not a dependency.
local root=(arg[0]:match('^(.*)/tools/[^/]+$') or '.')
package.path=root..'/frontend/?.lua;'..root..'/frontend/?/init.lua;'..root..'/build/?.lua;'..package.path
local Compiler=require('let.compiler')
local Assembler=require('assembler')
local Util=require('tool_util')
local D=require('let.diag')
local abc=root..'/build/abc'
local source=[=[
let forms(x, y: i64): i64 = do
    if i64(3) < x then return (x + i64(5)) ~ y end
    if x >= i64(-2) then return x - y end
    return x * i64(7)
end
let unsigned(a, b: u32): u32 = if a < b then (a << 3) | 1 else (a >> 2) & 7
let ordered(x, y: i64): i64 = x - (y / i64(2))
let main(): i64 = forms(i64(4), i64(1))
]=]
local artifact=Compiler.compile{profile='slet',name='operand-forms.slet',source=source,
    exports={'main','forms','unsigned','ordered'}}
local input=Assembler.assemble(artifact.assembly)
local optimized=Compiler.optimize(input)
assert(Compiler.optimize(optimized)==optimized,'production optimizer is not at a fixpoint')
local prefix=os.tmpname(); os.remove(prefix)
local executions=0
local function execute(path,entry,arguments,expected,mode)
    local command={abc,'run',path}
    if entry then command[#command+1]=entry end
    for _,argument in ipairs(arguments) do command[#command+1]=argument end
    command[#command+1]='--'..mode
    local ok,output,errors=Util.capture(command)
    assert(ok and output:gsub('%s+$','')==expected,
        path..' '..(entry or 'main')..' '..mode..': '..errors..output..' (expected '..expected..')')
    executions=executions+1
end
local cases={
    {'main',{},'8'},
    {'forms',{'4','1'},'8'}, {'forms',{'3','2'},'1'},
    {'forms',{'-2','5'},'-7'}, {'forms',{'-3','1'},'-21'},
    {'unsigned',{'1','2'},'9'}, {'unsigned',{'8','8'},'2'},
    {'unsigned',{'31','0'},'7'}, {'unsigned',{'4294967295','0'},'7'},
    {'unsigned',{'268435456','536870912'},'2147483649'},
    {'ordered',{'50','14'},'43'}, {'ordered',{'5','-14'},'12'},
}
for index,bytes in ipairs{input,optimized} do
    local path=prefix..'-'..index..'.abc'; Util.publish(bytes,path)
    for _,case in ipairs(cases) do for _,mode in ipairs{'interpreted','compiled','lazy','jit=threaded'} do
        execute(path,case[1],case[2],case[3],mode)
    end end
    os.remove(path)
end
-- Exercise the actual source-file CLI, not an alternative source compiler.
for _,case in ipairs{{'fibonacci','55'},{'countdown','5000050000'}} do
    for _,mode in ipairs{'interpreted','compiled','lazy','jit=threaded'} do
        execute(root..'/examples/'..case[1]..'.slet',nil,{},case[2],mode)
    end
end

-- These were bootstrap-only capabilities. Keep their production rejection
-- explicit instead of replacing them with different successful programs.
local rejected={
    {name='top-level-partial.slet',code='semantic-todo',source=[[
let xorshift(a, b, c, state: u32): u32 = do
    let x = state ~ (state << a)
    let y = x ~ (x >> b)
    return y ~ (y << c)
end
let next32 = xorshift(13, 17, 5)
let main(): (u32, u32) = do
    let x = next32(1)
    return x, next32(x)
end
]]},
    {name='runtime-partial.slet',code='static-required',source=[[
let seed(x: u64): u64 = x
let add(a, b: u64): u64 = a + b
let main(): (u64, u64) = do
    let base = seed(40)
    let p = add(base)
    let q = add(seed(41))
    return p(2), q(2)
end
]]},
}
for _,case in ipairs(rejected) do
    local ok,diagnostic=pcall(Compiler.compile,{profile='slet',name=case.name,source=case.source})
    assert(not ok and D.is(diagnostic) and diagnostic.code==case.code and
        diagnostic.span and diagnostic.span.file==case.name,
        'unsupported production source lost its explicit diagnostic: '..case.name..': '..tostring(diagnostic))
end
print(('validated production SLet frontend/optimizer: %d executions, 2 explicit unsupported-source diagnostics'):format(executions))
