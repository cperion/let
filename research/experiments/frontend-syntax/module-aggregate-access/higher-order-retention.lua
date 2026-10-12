package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local D=require('let.diag')
local template=[[
let Point = { x: U32 }
let Holder = { value: Ref(Point) }
let apply(body: (): Unit): Unit = body()
let bad(holder: Ref(Holder)): U32 = do
 let p = Point { x = 42 }
 let saved = do() holder.value = Ref(p) return end
 %s
 return 0
end
let main(): U32 = 0
]]
for _,invocation in ipairs{'saved()','apply(saved)'} do
 local ok,err=pcall(C.typed,{profile='let',source=template:format(invocation),name='higher-order-retention.let'})
 print(invocation,ok and 'ACCEPTED (retention proof regression)' or tostring(err))
 assert(not ok and D.is(err) and err.code=='borrow-store','Direct and higher-order stores must retain the same bounds')
end
