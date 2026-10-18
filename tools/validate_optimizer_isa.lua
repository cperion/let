-- Revision-6 optimizer contract tests. Inputs are assembled, not frontend lowered.
package.path='tools/?.lua;frontend/?.lua;'..package.path
local assembler,util,manifest=require('assembler'),require('tool_util'),require('opcodes')
local optimizer=require('let.optimize')
local runtime=arg[1] or 'build/abc-runtime'
local directory=arg[2] or '/tmp/abc-optimizer-isa'
assert(os.execute('mkdir -p '..string.format('%q',directory))==0)
local function u32(s,p)local a,b,c,d=s:byte(p,p+3);return a+b*256+c*65536+d*16777216 end
local function code(bytes)
 local p=17
 for _=1,u32(bytes,9) do
  local tag,n=u32(bytes,p),u32(bytes,p+4);p=p+8
  if tag==2 then return bytes:sub(p,p+n-1) end
  p=p+n
 end
 error('missing code section')
end
local function instructions(bytes)
 local result,starts={},{};local p=1
 while p<=#bytes do
  local opcode=bytes:byte(p);local descriptor=manifest.ops[opcode+1]
  if opcode==0xf8 or opcode==0xf9 then descriptor=manifest.ext_ops[bytes:byte(p+1)+1] end
  assert(descriptor and descriptor.len>0,'invalid emitted encoding')
  local n=descriptor.len
  if descriptor.kind==manifest.kind.SWITCH then n=n+4*(bytes:byte(p+1)+256*bytes:byte(p+2)) end
  assert(p+n-1<=#bytes,'truncated instruction')
  result[#result+1]={pc=p-1,opcode=opcode,selector=(opcode==0xf8 or opcode==0xf9) and bytes:byte(p+1),name=descriptor.name}
  starts[p-1]=true;p=p+n
 end
 return result,starts
end
local cases={
 {name='sub-c',args='10 3',expected='7',source=[[.function main 2 1
 CGET.B 0
 CGET.A 1
 SUB.B
 RET.B 2 1
 ]],extended=1},
 {name='nested-sub',args='10 8 3',expected='5',source=[[.function main 3 1
 CGET.A 0
 CGET.B 1
 CGET.A 2
 SUB.B
 SUB.A
 RET.A 3 1
 ]],no_moves=true},
 {name='divide',args='91 7',expected='13',source=[[.function main 2 1
 CGET.B 0
 CGET.A 1
 DIVU.B
 RET.B 2 1
 ]]},
 {name='shift',args='128 2',expected='32',source=[[.function main 2 1
 CGET.B 0
 CGET.A 1
 SHR.B
 RET.B 2 1
 ]]},
 {name='normalize',args='300',expected='44',source=[[.function main 1 1
 CGET.B 0
 ZX8.B
 RET.B 1 1
 ]]},
 {name='capture',args='10 3 111',expected='7 111',source=[[.function main 3 2
 CGET.A 2
 CGET.B 0
 CGET.A 1
 CSET.A 0
 CGET.A 0
 SUB.B
 MOVE.A
 RET.B 3 2
 ]]},
 {name='immediate-branch',args='3',expected='22',source=[[.function main 1 1
 CGET.B 0
 BGTI.B 2 yes
 PUSH.B 11
 RET.B 1 1
 yes:
 PUSH.B 22
 RET.B 1 1
 ]],extended=8},
 {name='fused-branch',args='3',expected='22',source=[[.function main 1 1
 CGET.B 0
 PUSH.A 2
 LE.B
 JZ.B yes
 PUSH.B 11
 RET.B 1 1
 yes:
 PUSH.B 22
 RET.B 1 1
 ]]},
 {name='phi-results',args='3',expected='22 33',source=[[.function main 1 2
 CGET.B 0
 BEQI.B 3 yes
 PUSH.B 11
 PUSH.B 44
 RET.B 1 2
 yes:
 PUSH.B 22
 PUSH.B 33
 RET.B 1 2
 ]],extended=4},
 {name='switch',args='1',expected='22',source=[[.function main 1 1
 CGET.B 0
 SWITCH.B zero one
 PUSH.B 33
 RET.B 1 1
 zero:
 PUSH.B 11
 RET.B 1 1
 one:
 PUSH.B 22
 RET.B 1 1
 ]]},
 {name='halt',args='',expected='7',source=[[.function main 0 1
 PUSH.B 10
 PUSH.A 3
 SUB.B
 HALT.B
 ]],halt=true},
 {name='halt-argument',args='10',expected='7',source=[[.function main 1 1
 CGET.B 0
 CPOP
 PUSH.A 3
 SUB.B
 HALT.B
 ]],halt=true},
 {name='memory-addresses',args='7',expected='7 77',source=[[.profile memory
 .datazero 16
 .function main 1 2 i ii
 CGET.A 0
 GADDR.B 0
 ST64.B 0
 PUSH.A 77
 GADDR.B 8
 ST64.B 0
 GLD64.B 0
 GLD64.B 8
 RET.B 1 2
 ]]},
 {name='halt-empty',args='',expected='',source=[[.function main 0 0
 PUSH.B 1
 DROP.B
 HALT.B
 ]],halt=true},
 {name='trap',args='10 0',trap=true,source=[[.function main 2 1
 CGET.B 0
 CGET.A 1
 DIVU.B
 RET.B 2 1
 ]]},
 {name='known-check',args='',trap=true,source=[[.function main 0 1
 PUSH.B 300
 CHKU8.B
 RET.B 0 1
 ]]},
 {name='check',args='300',trap=true,source=[[.function main 1 1
 CGET.B 0
 CHKU8.B
 RET.B 1 1
 ]]}
}
for call_bank=0,1 do for return_bank=0,1 do
 local caller=call_bank==0 and 'A' or 'B';local callee=return_bank==0 and 'A' or 'B'
 cases[#cases+1]={name='call-'..caller..callee,args='10 3',expected='7',source=([[
.function main 2 1
 CGET.%s 0
 CGET.%s 1
 CALL.%s helper 2
 RET.%s 2 1
.function helper 2 1
 CGET.%s 0
 CGET.%s 1
 SUB.%s
 RET.%s 2 1
.export main
 ]]):format(caller,caller,caller,caller,callee,callee=='A' and 'B' or 'A',callee,callee)}
end end
cases[#cases+1]={name='recursive-b',args='10',expected='55',source=[[
.function main 1 1
 CGET.B 0
 BEQI.B 0 base
 CGET.B 0
 SUBI.B 1
 CALL.B main 1
 CGET.A 0
 ADD.B
 RET.B 1 1
 base:
 PUSH.A 0
 RET.A 1 1
]]}
cases[#cases+1]={name='tail-b',args='100 0',expected='5050',source=[[
.function main 2 1
 CGET.B 0
 BEQI.B 0 base
 CGET.B 0
 SUBI.B 1
 CGET.A 0
 CGET.B 1
 ADD.B
 TCALL.B main 2 2
 base:
 CGET.B 1
 RET.B 2 1
]]}
for _,kind in ipairs{'difference','observe'} do
 cases[#cases+1]={name='foreign-'..kind,args='111',expected='7 111',foreign=true,source=([[
.profile foreign
.extern %s ii %s
.function main 1 2 i ii
 CGET.A 0
 PUSH.B 10
 PUSH.B 3
 FCALL.B %s
 %s
 MOVE.A
 RET.B 1 2
.export main
 ]]):format(kind,kind=='observe' and '-' or 'i',kind,kind=='observe' and 'PUSH.B 7' or '')}
end
-- Frame allocation is an existing optimizer boundary, including through wrappers.
for _,tail in ipairs{false,true} do
 cases[#cases+1]={name=tail and 'frame-tail-boundary' or 'frame-call-boundary',args='42',expected='42',retained=true,source=([[
.profile memory
.function main 1 1 i i
 CGET.A 0
 %s
.function helper 1 1 i i
 CALLOC 8
 FADDR.A 8
 CGET.B 1
 ST64.A 0
 FADDR.A 8
 LD64.A 0
 CFREE 8
 RET.A 1 1
.export main
 ]]):format(tail and 'TCALL.A helper 1 1' or 'CALL.A helper 1\n RET.A 1 1')}
end
-- No allocation and no Rc: reject already-unsupported multi-path effects before
-- expanding 4096 paths and repeating their 32-effect common suffix.
for _,before in ipairs{false,true} do
 local lines={'.profile memory','.datazero 8','.function main 1 1 i i','CGET.A 0','CALL.A helper 1','RET.A 1 1','.function helper 1 1 i i'}
 local function effects() for i=1,32 do lines[#lines+1]='GADDR.A 0\n PUSH.B '..i..'\n ST64.A 0' end end
 if before then effects() end
 for i=1,12 do lines[#lines+1]='CGET.A 0\n JZ.A skip'..i..'\n PUSH.A '..i..'\n DROP.A\n skip'..i..':' end
 if not before then effects() end
 lines[#lines+1]='GADDR.A 0\n LD64.A 0\n RET.A 1 1\n .export main'
 cases[#cases+1]={name=before and 'effects-before-branches' or 'effects-after-branches',args='1',expected='32',retained=true,source=table.concat(lines,'\n')}
end
local extra_samples={
 ['immediate-branch']={{'0','11'},{'2','11'},{'-1','11'}},
 ['fused-branch']={{'2','11'},{'-1','11'}},
 ['phi-results']={{'0','11 44'}},
 ['switch']={{'0','11'},{'2','33'},{'-1','33'}},
 ['shift']={{'128 64','0'},{'128 65','0'}},
 ['recursive-b']={{'0','0'},{'1','1'}},
 ['tail-b']={{'0 77','77'}}
}
local runs=0
for _,case in ipairs(cases) do for mirror=0,1 do
 local source=mirror==0 and case.source or case.source:gsub('%.([AB])',function(bank)return bank=='A' and '.B' or '.A' end)
 local name=case.name..(mirror==1 and '-mirror' or '')
 local original=assembler.assemble(source)
 local optimized,map=optimizer.optimizeMapped(original)
 local input_code,output_code=code(original),code(optimized)
 local output_instructions,output_starts=instructions(output_code)
 local input_instructions,input_starts=instructions(input_code)
 local mapped=0;for _ in pairs(map) do mapped=mapped+1 end
 -- A canonical input may re-emit identical bytes. Retained functions map
 -- every original instruction; actual emission maps its residual operations.
 if case.retained then assert(output_code==input_code,name..': crossed an unsupported effect/frame boundary')
 else assert(output_code~=input_code or mapped<#input_instructions,name..': did not exercise optimized emission') end
 assert(optimized:sub(1,8)==original:sub(1,8),name..': changed revision/profile')
 for target,origin in pairs(map) do
  assert(output_starts[target] and input_starts[origin],name..': provenance points inside an instruction')
 end
 if case.extended then
  local found=false;for _,instruction in ipairs(output_instructions) do if instruction.selector==case.extended and instruction.opcode==(mirror==0 and 0xf9 or 0xf8) then found=true end end
  assert(found,name..': required EXT form was not emitted')
 end
 if case.no_moves then
  for _,instruction in ipairs(output_instructions) do assert(instruction.opcode~=0x0e and instruction.opcode~=0x0f,name..': operand-orientation repair MOVE') end
 end
 if case.halt then
  local found=false;for _,instruction in ipairs(output_instructions) do if instruction.opcode<=1 then found=true end end
  assert(found,name..': lost host-only HALT contract')
 end
 local before,after=directory..'/'..name..'-original.abc',directory..'/'..name..'-optimized.abc'
 util.write(before,original);util.write(after,optimized)
 if case.foreign then
  local host=arg[3] or 'build/validate-optimizer-foreign'
  assert(os.execute(string.format('%q %q %q',host,before,after))==0,name..': foreign host check failed')
  runs=runs+3
 else
 local samples={{case.args,case.expected}}
 for _,sample in ipairs(extra_samples[case.name] or {}) do samples[#samples+1]=sample end
 for _,sample in ipairs(samples) do
 for _,mode in ipairs{'interpreted','compiled','lazy','jit=threaded'} do
  local texts,statuses={},{}
  for _,path in ipairs{before,after} do
   local command=string.format('%q run %q main %s --%s 2>&1',runtime,path,sample[1],mode)
   local pipe=assert(io.popen(command.."; printf '\\n__STATUS__%d\\n' $?"))
   local text=pipe:read('*a');pipe:close()
   local body,status=text:match('^(.*)\n__STATUS__(%d+)\n$');assert(status,text)
   texts[#texts+1]=body:gsub('%s+$','');statuses[#statuses+1]=tonumber(status)
  end
  if case.trap then
   assert(statuses[1]==1 and statuses[2]==1,name..': missing abort exit status')
   assert(texts[1]:match(': ([^:]+)$')==texts[2]:match(': ([^:]+)$'),name..': changed trap diagnostic')
   local original_pc=tonumber(assert(texts[1]:match('abort at byte 0x(%x+)')),16)
   local optimized_pc=tonumber(assert(texts[2]:match('abort at byte 0x(%x+)')),16)
   assert(map[optimized_pc]==original_pc,name..': incorrect trap provenance')
  else
   assert(statuses[1]==0 and statuses[2]==0 and texts[1]==sample[2] and texts[2]==sample[2],name..' '..mode..': '..texts[1]..' / '..texts[2])
  end
  runs=runs+1
 end
 end
 end
 print(name..': optimized emission and four-mode execution PASS')
end end
print(('optimizer ISA: %d mirrored modules, %d original/optimized execution pairs'):format(#cases*2,runs))
