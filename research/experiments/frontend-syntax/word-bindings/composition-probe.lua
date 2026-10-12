package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local A=require('assembler')
for _,case in ipairs{
{'sum',[[let option = oneof { none: unit, some: u32 }
let unwrap(value: option): u32 = value { none = do() = 0, some = do(payload) = payload + 2 }
let main(): u32 = unwrap(option.some(40))]]},
{'scalar',[[let plus(x: u32): u32 = x + 2
let main(x: u32): u32 = plus(x)]]}
} do
local artifact=C.compile{profile='slet',source=case[2],name='compose.slet'}
if case[1]=='sum' and os.getenv('SHOW_ASM') then print(artifact.assembly) end
local raw=A.assemble(artifact.assembly)
local optimized=C.optimize(raw)
print(case[1], 'raw='..#raw,'optimized='..#optimized,'unchanged='..tostring(raw==optimized))
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
local result=C.stage(artifact.functions,{profile='slet',entry='main',mode=mode,optimize=true,arguments=case[1]=='scalar' and {40} or {}})
assert(tonumber(result.cells[1])==42)
end
end
