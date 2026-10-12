-- Identical revision-6 modules for both real-VM builds; no frontend dependency.
package.path=assert(arg[2])..'/tools/?.lua;'..package.path
local assembler,util=require('assembler'),require('tool_util')
local output=assert(arg[1]);local manifest={}
local function save(name,source,expected,bench)
 util.write(output..'/'..name..'.abcasm',source)
 util.write(output..'/'..name..'.abc',assembler.assemble(source))
 manifest[#manifest+1]=('%s\t%.0f\t%s'):format(name,expected,bench==false and 'check' or 'bench')
end
local iterations=500000
local function reads(name,depths,boundary)
 local source={boundary=='free' and '.profile memory' or '.profile integer', boundary=='free' and '.function main 0 1 - i' or '.function main 0 1'}
 for value=1,7 do source[#source+1]='PUSH.A '..value..'\nCPUSH.A' end
 source[#source+1]='PUSH.A '..iterations..'\nCPUSH.A\nPUSH.A 0\nloop:'
 if boundary=='call' then source[#source+1]='PUSH.B 1\nPUSH.B 2\nPUSH.B 3\nCALL.B drain 3'
 elseif boundary=='free' then source[#source+1]='CALLOC 32\nCFREE 32' end
 local sum=0
 for i=1,32 do
  local depth=depths[(i-1)%#depths+1]
  source[#source+1]='CGET.B '..depth..'\nADD.A';sum=sum+8-depth
 end
 source[#source+1]='CGET.B 0\nADDI.B -1\nCSET.B 0\nCGET.B 0\nJNZ.B loop\nRET.A 8 1'
 if boundary=='call' then source[#source+1]='.function drain 3 0\nRET.B 3 0' end
 save(name,table.concat(source,'\n')..'\n',sum*iterations)
end
reads('warm-top',{1,2})
reads('post-call-top',{1,2},'call')
reads('post-call-mixed',{1,2,3,5},'call')
reads('post-call-deep',{3,5,6,7},'call')
reads('post-free-top',{1,2},'free')
save('ab-control',[[.function main 0 1
 PUSH.A 3000000
 loop:
 ADDI.A -1
 DUP.A
 JNZ.A loop
 RET.A 0 1
]],0)
save('fib28',[[.function main 0 1
 PUSH.A 28
 CALL.A fib 1
 RET.A 0 1
 .function fib 1 1
 CGET.A 0
 PUSH.B 2
 LTU.A
 JNZ.A base
 CGET.A 0
 ADDI.A -1
 CALL.A fib 1
 CGET.B 0
 ADDI.B -2
 CALL.B fib 1
 ADD.A
 RET.A 1 1
 base:
 CGET.A 0
 RET.A 1 1
]],317811)
save('frame-alias',([[.profile memory
 .function main 0 1 - i
 CALLOC 8
 PUSH.A %d
 CPUSH.A
 PUSH.A 0
 loop:
 PUSH.A 9
 FST64.A 16
 FADDR.A 16
 PUSH.B 5
 ST64.A 0
 FADDR.B 16
 LD64.B 0
 ADD.A
 CGET.B 0
 ADDI.B -1
 CSET.B 0
 CGET.B 0
 JNZ.B loop
 CPOP
 CFREE 8
 RET.A 0 1
]]):format(iterations),iterations*5)
save('global-memory',[[.profile memory
 .datazero 8
 .function main 0 1 - i
 PUSH.B 0
 GST64.B 0
 PUSH.A 1000000
 CPUSH.A
 loop:
 GLD64.B 0
 ADDI.B 1
 GST64.B 0
 CGET.A 0
 ADDI.A -1
 CSET.A 0
 CGET.A 0
 JNZ.A loop
 GLD64.A 0
 RET.A 1 1
]],1000000)
save('escaped-caller-block',[[.profile memory
 .function main 0 1 - i
 CALLOC 8
 FADDR.B 8
 CALL.B writer 1
 FLD64.A 8
 CFREE 8
 RET.A 0 1
 .function writer 1 0 a -
 CGET.A 0
 PUSH.B 41
 ST64.A 0
 RET.B 1 0
]],41,false)
save('partial-frame-write',[[.profile memory
 .function main 0 1 - i
 CALLOC 24
 PUSH.A 287454020
 FST64.A 24
 FADDR.A 24
 PUSH.B 85
 ST8.A 1
 FADDR.B 24
 LD64.B 0
 CFREE 24
 RET.B 0 1
]],287462724,false)
save('frame-copy-overlap',[[.profile memory
 .function main 0 1 - i
 CALLOC 24
 PUSH.A 11
 FST64.A 24
 PUSH.B 22
 FST64.B 16
 PUSH.A 33
 FST64.A 8
 FADDR.A 16
 FADDR.B 24
 MEMCPY.A 16
 FLD64.A 8
 CFREE 24
 RET.A 0 1
]],22,false)
util.write(output..'/workloads.tsv',table.concat(manifest,'\n')..'\n')
