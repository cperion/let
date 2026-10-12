local root=(arg[0]:match("^(.*)/tools/[^/]+$") or ".")
local abc=root.."/build/abc"
local cc=os.getenv("CC") or "cc"
local tmp=("/tmp/abc-c-aot-%d"):format(os.time())

local function quote(value) return string.format("%q",value) end
local function run(command)
    local status=os.execute(command)
    assert(status==0,command)
end
local function write(path,text)
    local file=assert(io.open(path,"wb"))
    assert(file:write(text))
    assert(file:close())
end
local function capture(command)
    local process=assert(io.popen(command,"r"))
    local output=process:read("*a"):gsub("%s+$","")
    assert(process:close(),command)
    return output
end

run("mkdir -p "..quote(tmp))
local assembly=[[
.function arithmetic 2 1
 CGET.A 0
 CGET.B 1
 ADD.A
 MULI.A 3
 RET.A 2 1
.export arithmetic

.function choose 1 1
 CGET.A 0
 BLTUI.A 10 small
 PUSH.A 99
 RET.A 1 1
small:
 CGET.A 0
 ADDI.A 1
 RET.A 1 1
.export choose

.function loop 2 1
again:
 CGET.A 0
 JZ.A done
 CGET.A 0
 SUBI.A 1
 CGET.A 1
 ADDI.A 2
 TCALL.A loop 2 2
done:
 CGET.A 1
 RET.A 2 1
.export loop

.function add 2 1
 CGET.A 0
 CGET.B 1
 ADD.A
 RET.A 2 1

.function caller 0 1
 PUSH.A 20
 PUSH.A 22
 CALL.A add 2
 RET.A 0 1
.export caller

 .function fib 1 1
  PUSH.A 2
  CGET.B 0
  BLEU.A recurse
  CGET.A 0
  RET.A 1 1
 recurse:
  CGET.A 0
  SUBI.A 1
  ZX32.A
  CALL.A fib 1
  CGET.A 0
  SUBI.A 2
  ZX32.A
  CALL.A fib 1
  MOVE.A
  ADD.A
  ZX32.A
  RET.A 1 1
 .function fib_main 0 1
  PUSH.A 10
  TCALL.A fib 0 1
 .export fib_main
]]
for mirror=0,1 do
local source=mirror==0 and assembly or assembly:gsub('%.([AB])',function(bank)return bank=='A' and '.B' or '.A' end)
write(tmp.."/program.abcasm",source)
run(quote(abc).." asm "..quote(tmp.."/program.abcasm").." -o "..quote(tmp.."/program.abc"))
run(quote(abc).." c "..quote(tmp.."/program.abc").." -o "..quote(tmp.."/program.c"))
local generated=assert(io.open(tmp.."/program.c","rb"));local generated_text=generated:read("*a");generated:close()
assert(not generated_text:find("values%[") and not generated_text:find("call_args",1,true) and
       not generated_text:find("call_results",1,true),
       "portable C direct path must use C locals and scalar calls, not generic value/argument/result arrays")
assert(generated_text:find("static inline uint64_t abc_aot_function_",1,true),
       "portable C pure scalar functions use direct internal signatures")

local harness=[[
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include "program.c"

static int invoke(const char *name, uint64_t a, uint64_t b, size_t count) {
    const abc_aot_export *entry=abc_aot_find(name);
    uint64_t arguments[2]={a,b},results[2]={0,0};
    abc_aot_error error;
    int status;
    if(!entry)return 1;
    status=entry->entry(arguments,count,results,2,&error);
    if(status)return 2;
    printf("%" PRId64 "\n",(int64_t)results[0]);
    return 0;
}
int main(void) {
    return invoke("arithmetic",20,22,2) ||
           invoke("choose",9,0,1) ||
           invoke("choose",10,0,1) ||
           invoke("loop",5,32,2) ||
           invoke("caller",0,0,0) ||
           invoke("fib_main",0,0,0);
}
]]
write(tmp.."/harness.c",harness)
run(quote(cc).." -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-unused-function -O2 -I"..quote(tmp).." "..quote(tmp.."/harness.c").." -o "..quote(tmp.."/aot"))

local interpreted=table.concat({
    capture(quote(abc).." run "..quote(tmp.."/program.abc").." arithmetic 20 22 --interpreted"),
    capture(quote(abc).." run "..quote(tmp.."/program.abc").." choose 9 --interpreted"),
    capture(quote(abc).." run "..quote(tmp.."/program.abc").." choose 10 --interpreted"),
    capture(quote(abc).." run "..quote(tmp.."/program.abc").." loop 5 32 --interpreted"),
    capture(quote(abc).." run "..quote(tmp.."/program.abc").." caller --interpreted"),
    capture(quote(abc).." run "..quote(tmp.."/program.abc").." fib_main --interpreted"),
},"\n")
local aot=capture(quote(tmp.."/aot"))
assert(interpreted=='126\n10\n99\n42\n42\n55','independent arithmetic/control/call expectations changed')
assert(aot==interpreted,
    ("portable C mismatch\nAOT:\n%s\ninterpreter:\n%s"):format(aot,interpreted))
assert(generated_text:find("static inline uint32_t abc_aot_function_",1,true),
       "portable C preserves proven private recursive u32 signatures")

end
run("rm -rf "..quote(tmp))
print("validated 12 mirrored portable C residual arithmetic, branch, loop, call, and export cases")
