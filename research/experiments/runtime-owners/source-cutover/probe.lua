package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local A=require('assembler')
local ffi=require('let.abi')
local rt=ffi.load('../build/libabc.so')
local source=[[
let Point = { x: U32 }
let Box = { child: Ref(Point) }
let leaf(v: U32): Ref(Point) = do
 let point = Point { x = v }
 return Ref(point)
end
let parent(v: U32): Ref(Box) = do
 let p = Box { child = leaf(v) }
 return Ref(p)
end
let main(n: U32): U32 = do
 let p = parent(n)
 let saved = p.child
 p.child = leaf(n+1)
 return saved.x*100+p.child.x
end
]]
local ok,artifact=xpcall(function() return C.compile{profile='slet',name='owning-source.slet',source=source,exports={'main'}} end,function(e) return tostring(e)..'\n'..debug.traceback() end)
assert(ok,artifact)
local f=assert(io.open('../build/owning-source.abcasm','wb'));f:write(artifact.assembly);f:close()
local bytes=A.assemble(artifact.assembly)
local f=assert(io.open('../build/owning-source.abc','wb'));f:write(bytes);f:close()
local err=ffi.new('abc_error[1]')
local function check(status) assert(status==0,tonumber(status)..': '..ffi.string(err[0].message)..' at '..tonumber(err[0].offset)) end
for _,optimized in ipairs{false,true} do
 local image=optimized and require('let.optimize').optimize(bytes) or bytes
 local m=ffi.new('abc_module *[1]');check(rt.abc_module_load(image,#image,m,err))
 for _,mode in ipairs{0,3,1,2} do
  local limits=ffi.new('abc_limits',{stack_cells=65536,mode=mode});local vm=ffi.new('abc_vm *[1]');check(rt.abc_vm_create(limits,vm,err))
  check(rt.abc_vm_load(vm[0],m[0],err))
  local input=ffi.new('uint64_t[1]',2);local out=ffi.new('uint64_t[1]',999);local n=ffi.new('size_t[1]')
  check(rt.abc_vm_call(vm[0],m[0],'main',input,1,out,1,n,err));assert(tonumber(out[0])==203,tostring(out[0]))
  print('source parent/child saved copy replacement',optimized,mode,tonumber(out[0]))
  rt.abc_vm_free(vm[0])
 end
 rt.abc_module_free(m[0])
end
