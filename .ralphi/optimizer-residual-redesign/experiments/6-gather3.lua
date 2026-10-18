-- Caller pushes 1,2,3 and calls f(a,b,c); f returns its three C cells.
-- The printed order answers which pushed value is "argument zero" / C0.
package.path='tools/?.lua;'..package.path
local assembler=require('assembler')
local src=[[
.function main 0 3
  PUSH.A 1
  PUSH.A 2
  PUSH.A 3
  CALL.A f 3
  RET.A 0 3
.function f 3 3
  CGET.A 0
  CGET.A 1
  CGET.A 2
  RET.A 3 3
.export main
]]
local path='.ralphi/optimizer-residual-redesign/experiments/6-may-write-out/gather3.abc'
local h=assert(io.open(path,'wb'));h:write((assembler.assemble(src)));h:close()
for _,mode in ipairs{'interpreted','jit=threaded','compiled','lazy'} do
  local p=assert(io.popen(('build/abc run %q main --%s 2>&1'):format(path,mode)))
  print(mode, (p:read('*a'):gsub('%s+$','')), p:close())
end
