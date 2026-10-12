package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local ok,result=pcall(C.typed,{profile='slet',name='export-name.slet',source=[[
let Record = { value: u32 }
let answer(): u32 = 42
return { types = { Thing = Record }, functions = { Thing = answer } }
]]})
print(ok and ('accepted; functions='..#result.functions) or tostring(result))
