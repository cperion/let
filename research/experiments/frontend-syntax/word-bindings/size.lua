-- Run from a checkout's frontend directory, against its compiler and assembler.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local Compiler=require('let.compiler')
local Assembler=require('assembler')
local source=[[
let option = oneof { none: unit, some: u32 }
let unwrap(value: option): u32 = value {
  none = do() = 0,
  some = do(payload) = payload + 2,
}
let main(): u32 = unwrap(option.some(40))
]]
local artifact=Compiler.compile{profile='slet',name='handler-size.slet',source=source}
local calls,views=0,0
local function visit(node)
    if node.kind=='Call' or node.kind=='Indirect' then calls=calls+1 end
    if node.kind=='View' then views=views+1 end
    node:each(visit)
end
for _,fn in ipairs(artifact.functions) do for _,stmt in ipairs(fn.body) do visit(stmt) end end
local bytes=Assembler.assemble(artifact.assembly)
print(('functions=%d call_sites=%d views=%d module_bytes=%d assembly_bytes=%d'):format(
    #artifact.functions,calls,views,#bytes,#artifact.assembly))
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
    local result=Compiler.stage(artifact.functions,{profile='slet',entry='main',mode=mode,optimize=false})
    assert(tonumber(result.cells[1])==42,mode..' result')
end
print('four-mode result=42; no timing measurement')
