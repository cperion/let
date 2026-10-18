-- Run from frontend/. Compile the unchanged diagnostic fixture, not its harness.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local file=assert(io.open('../research/experiments/runtime-owners/explicit-rc-performance-investigation/fixture.lua'))
local text=file:read('*a');file:close()
local source=assert(text:match('local source=%[%[(.-)%]%]'))
local exports={};for name in assert(text:match('local exports={(.-)}')):gmatch("'([^']+)'") do exports[#exports+1]=name end
local C=require('let.compiler');local A=require('assembler');local O=require('let.optimize')
collectgarbage('collect')
local before=collectgarbage('count');local start=os.clock()
local artifact=C.compile{profile='slet',source=source,exports=exports,staticMode='interpreted',staticOptimize=false}
local seconds=os.clock()-start;local heap=collectgarbage('count')
collectgarbage('collect');local retained=collectgarbage('count')
local stats=artifact.program.accessStats
print(('frozen fixture: %d functions, %d bindings, %d iterations, %d CFG points'):format(#artifact.program.functions,stats.contexts,stats.iterations,stats.relations))
print(('compile CPU %.6fs; analysis CPU %.6fs; heap before %.3f MiB, after %.3f MiB, after collection %.3f MiB'):format(seconds,stats.seconds,before/1024,heap/1024,retained/1024))
local raw=A.assemble(artifact.assembly);start=os.clock();local optimized=O.optimize(raw)
print(('assembly %d bytes; raw %d bytes; optimized %d bytes; optimizer CPU %.6fs'):format(#artifact.assembly,#raw,#optimized,os.clock()-start))
