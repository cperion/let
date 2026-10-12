-- Run from the project root. No frontend or ABC optimizer dependency.
package.path='tools/?.lua;'..package.path
local assembler,util=require('assembler'),require('tool_util')
local emitter,compiler,output=assert(arg[1]),assert(arg[2]),assert(arg[3])
local cases={{'warm-top',104000000},{'post-call-top',104000000},
 {'post-call-mixed',84000000},{'post-call-deep',44000000},
 {'ab-control',0},{'fib28',317811}}
local function failure_driver(success_argument,failure_argument,result,reason,origin)
 return ([[
#include <stdio.h>
int main(void) {
 uint64_t argument=%s,result=999;abc_aot_error error;
 int status=abc_export_main(&argument,1,&result,1,&error);
 if(status!=ABC_AOT_OK||result!=%d||error.status!=ABC_AOT_OK||error.offset!=UINT32_MAX)return 1;
 argument=%s;result=999;
 status=abc_export_main(&argument,1,&result,1,&error);
 if(status!=ABC_AOT_ABORT||error.status!=ABC_AOT_ABORT||error.reason!=%d||error.offset!=%d||result!=999)return 2;
 status=abc_export_main(&argument,1,&result,1,NULL);
 if(status!=ABC_AOT_ABORT||result!=999)return 3;
 puts("1");return 0;
}
]]):format(success_argument,result,failure_argument,reason,origin)
end
cases[#cases+1]={'zero-result',77,source=[[
.function main 0 1
 PUSH.B 123
 CALL.B discard 1
 PUSH.B 77
 RET.B 0 1
.function discard 1 0
 RET.A 1 0
.export main
]],nonfailing=true,scalar_caller=true}
cases[#cases+1]={'empty-vectors',77,source=[[
.function main 0 1
 CALL.B noop 0
 PUSH.B 77
 RET.B 0 1
.function noop 0 0
 RET.A 0 0
.export main
]],nonfailing=true,scalar_caller=true}
cases[#cases+1]={'multi-result-scalar-caller',7,source=[[
.function main 0 1
 PUSH.B 10
 PUSH.B 3
 CALL.B pair 2
 MOVE.B
 SUB.B
 RET.B 0 1
.function pair 2 2
 CGET.A 0
 CGET.A 1
 RET.A 2 2
.export main
]],nonfailing=true,scalar_caller=true}
cases[#cases+1]={'multi-result-vector-caller',1,source=[[
.function main 0 2
 PUSH.B 10
 PUSH.B 3
 CALL.B pair 2
 RET.B 0 2
.function pair 2 2
 CGET.A 0
 CGET.A 1
 RET.A 2 2
.export main
]],nonfailing=true,driver=[[
#include <stdio.h>
int main(void) {
 uint64_t results[2]={999,999};abc_aot_error error;
 int status=abc_export_main(NULL,0,results,2,&error);
 if(status!=ABC_AOT_OK||results[0]!=10||results[1]!=3||error.status!=ABC_AOT_OK)return 1;
 puts("1");return 0;
}
]]}
cases[#cases+1]={'failing-scalar-result',1,source=[[
.function main 1 1
 PUSH.B 21
 CGET.B 0
 CALL.B divide 2
 RET.B 1 1
.function divide 2 1
 CGET.A 0
 CGET.B 1
 DIVU.A
 RET.A 2 1
.export main
]],failing=true,driver=failure_driver('3','0',7,1,14)}
cases[#cases+1]={'failing-zero-result',1,source=[[
.function main 1 1
 CGET.B 0
 CALL.B check 1
 PUSH.B 77
 RET.B 1 1
.function check 1 0
 CGET.A 0
 CHKNN.A
 DROP.A
 RET.B 1 0
.export main
]],failing=true,driver=failure_driver('0','UINT64_C(9223372036854775808)',77,3,13)}
cases[#cases+1]={'failing-multi-result',1,source=[[
.function main 1 1
 PUSH.B 21
 CGET.B 0
 CALL.B divide 2
 DROP.B
 RET.B 1 1
.function divide 2 2
 CGET.A 0
 CGET.B 1
 DIVU.A
 CGET.A 1
 RET.A 2 2
.export main
]],failing=true,driver=failure_driver('3','0',7,1,15)}
for _,width in ipairs{8,16,32} do
 cases[#cases+1]={'normalize-'..width,1,source=([[
.function main 1 2
 CGET.A 0
 CGET.B 0
 ZX%d.B
 MOVE.A
 RET.B 1 2
.export main
 ]]):format(width),driver=([[
#include <stdio.h>
int main(void) {
 const uint64_t inputs[]={0,255,256,65535,65536,UINT64_MAX,
   UINT64_C(9223372036854775808),UINT64_C(4294967297)};
 for(size_t i=0;i<sizeof(inputs)/sizeof(inputs[0]);i++) {
  uint64_t results[2]={999,999};abc_aot_error error;
  int status=abc_export_main(&inputs[i],1,results,2,&error);
  if(status!=ABC_AOT_OK||error.status!=ABC_AOT_OK||
     results[0]!=(inputs[i]&UINT64_C(%s))||results[1]!=inputs[i])return 1;
 }
 puts("1");return 0;
}
 ]]):format(width==8 and '255' or width==16 and '65535' or '4294967295')}
end
local function run(command)
 local status=os.execute(command)
 assert(status==0,'command failed: '..command)
end
run('mkdir -p '..string.format('%q',output))
for _,case in ipairs(cases) do
 local original=case.source or util.read('research/experiments/pre-tooling-vm/programs/'..case[1]..'.abcasm')
 for mirror=0,1 do
  local name=case[1]..(mirror==1 and '-mirror' or '')
  local source=mirror==1 and original:gsub('%.([AB])',function(bank)return bank=='A' and '.B' or '.A' end) or original
  local base=output..'/'..name
  util.write(base..'.abc',assembler.assemble(source))
  run(string.format('%q %q > %q',emitter,base..'.abc',base..'.c'))
  local generated=util.read(base..'.c')
  if case.nonfailing then
   assert(generated:match('call_results_%d+,NULL%)'),name..': missing proven-nonfailing NULL channel')
   assert(not generated:match('int call_status_'),name..': unnecessary status propagation')
  end
  if case.scalar_caller then
   assert(generated:match('static inline uint%d+_t abc_aot_function_0%('),name..': scalar ABI was discarded')
  end
  if case.failing then
   assert(generated:match('call_results_%d+,error%)'),name..': missing failure channel')
   assert(generated:match('if%(call_status_%d+%)return call_status_%d+;'),name..': missing status propagation')
  end
  local driver=case.driver or [[
#include <stdio.h>
int main(void) {
 uint64_t result=0;abc_aot_error error;
 int status=abc_export_main(NULL,0,&result,1,&error);
 if(status){fprintf(stderr,"AOT failure: %d\n",status);return 1;}
 printf("%llu\n",(unsigned long long)result);return 0;
}
]]
  util.write(base..'.c',generated..driver..'\n')
  run(string.format('%q -O2 -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-unused-function %q -o %q',compiler,base..'.c',base))
  local pipe=assert(io.popen(string.format('%q',base),'r'))
  local actual=pipe:read('*a');assert(pipe:close())
  assert(tonumber(actual)==case[2],name..': '..actual)
  print(name..': '..actual:gsub('%s+$','')..' PASS')
 end
end
print((#cases*2)..' mirrored portable-C execution cases passed')
