-- Run from frontend: /tmp/lua-compat ../research/experiments/frontend-syntax/receiver-scopes/capture-probe.lua
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local cases={
 {'lexical-dot-capture',[[
let main(n: u32): u32 = do
 let addition = do(p: u32): u32 = p + n
 let nested(): u32 = 40.addition()
 return nested()
end
]]},
 {'ordinary-capture-control',[[
let main(n: u32): u32 = do
 let addition = do(p: u32): u32 = p + n
 let nested(): u32 = addition(40)
 return nested()
end
]]},
 {'member-wins-no-capture-control',[[
let Holder = { value: u32, addition(): u32 = value }
let main(n: u32): u32 = do
 let addition = do(p: u32): u32 = p + n
 let make() = do(r: Holder): u32 = r.addition()
 let word = make()
 return word(Holder { value = 42 })
end
]]},
}
for _,case in ipairs(cases) do
 local ok,unit=pcall(C.typed,{profile='slet',source=case[2],name=case[1]..'.slet'})
 if not ok then print(case[1]..': '..tostring(unit))
 else
  local result=C.stage(unit.functions,{profile='slet',entry='main',arguments={2},mode='interpreted'})
  print(case[1]..': ACCEPT, result='..tonumber(result.cells[1]))
 end
end
