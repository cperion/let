-- Which argument position reaches the callee's C0?  f(a,b) returns a*10+b
-- (CGET 0 is "argument zero" per docs/spec.md, "Calls").  The caller pushes
-- 1 then 2 and calls f with two arguments.
package.path='tools/?.lua;'..package.path
local assembler=require('assembler')
local src=[[
.function main 0 1
  PUSH.A 1
  PUSH.A 2
  CALL.A f 2
  RET.A 0 1
.function f 2 1
  CGET.A 0
  PUSH.B 10
  MUL.A
  CGET.B 1
  ADD.A
  RET.A 2 1
.export main
]]
local path='.ralphi/optimizer-residual-redesign/experiments/6-may-write-out/gather.abc'
local f=assert(io.open(path,'wb'));f:write((assembler.assemble(src)));f:close()
for _,mode in ipairs{'interpreted','jit=threaded','compiled','lazy'} do
  local p=assert(io.popen(('build/abc run %q main --%s 2>&1'):format(path,mode)))
  print(mode, (p:read('*a'):gsub('%s+$','')), p:close())
end
