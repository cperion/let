-- Revision-6 frontend contracts: no old-ISA fixture translation.
local here=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or './'
package.path=here..'../?.lua;'..here..'../../tools/?.lua;'..package.path
local Compiler,S=require('let.compiler'),require('let.schema')
require('let.ir')
local assembler,util=require('assembler'),require('tool_util')
local I,L=S.Ir,S.ASDL.List
local function uint(n,ty)return I.Const(ty or S.u64,I.UInt(n)) end
local function bin(op,left,right,ty)return I.Bin(op,left,right,ty or S.u64) end
local a,b,c=I.Value(1),I.Value(2),I.Value(3)
local function ref(v)return I.Ref(v,S.u64) end
local yes=I.Const(S.bool,I.Boolean(true))
local scalar=I.Fn('main',I.Entry,0,L{S.inValue(S.u64),S.inValue(S.u64),S.inValue(S.u64)},
 L{S.u64,S.u64,S.u64,S.bool},L{I.ValueParam(0,a,S.u64),I.ValueParam(1,b,S.u64),I.ValueParam(2,c,S.u64)},
 L{I.Return(L{uint(111),bin(I.Sub,ref(a),bin(I.Sub,ref(b),ref(c))),
  bin(I.Div,ref(a),bin(I.Div,ref(b),ref(c))),
  bin(I.Eq,yes,bin(I.Gt,ref(b),ref(c),S.bool),S.bool)})})
local function real(n)return I.Const(S.f64,I.Float(n)) end
local nan=bin(I.Div,real(0),real(0),S.f64)
local comparisons,types={},{}
for _,op in ipairs{I.Gt,I.Ge,I.Lt,I.Le,I.Eq,I.Ne} do
 comparisons[#comparisons+1]=bin(op,nan,real(1),S.bool);types[#types+1]=S.bool
 comparisons[#comparisons+1]=bin(I.Eq,yes,bin(op,real(1),nan,S.bool),S.bool);types[#types+1]=S.bool
end
local floating=I.Fn('main',I.Entry,0,L{},L(types),L{},L{I.Return(L(comparisons))})
local badCast=I.Convert(I.Convert(uint(300),S.u8),S.u64)
local traps={}
for _,op in ipairs{I.Gt,I.Ge} do
 traps[#traps+1]=I.Fn('main',I.Entry,0,L{},L{S.bool},L{},L{
  I.Return(L{bin(op,bin(I.Div,uint(1),uint(0)),badCast,S.bool)})})
end
local root=here..'../../'
local base=os.tmpname();os.remove(base)
local checks=0
local function run(command)
 local pipe=assert(io.popen(command.." 2>&1; printf '\\n__STATUS__%d\\n' $?"))
 local text=pipe:read('*a');pipe:close()
 local body,status=text:match('^(.*)\n__STATUS__(%d+)\n$');assert(status,text)
 return body:gsub('%s+$',''),tonumber(status)
end
local fixtures={{scalar,'100 20 3','111 83 16 1'},
 {floating,'','0 0 0 0 0 0 0 0 0 0 1 1'},
 {traps[1],'',false},{traps[2],'',false}}
for index,fixture in ipairs(fixtures) do
 local artifact=Compiler.lower({fixture[1]},{profile='slet',exports={'main'}})
 if index==1 then
  assert(artifact.assembly:find('SUB.B',1,true) and artifact.assembly:find('DIVU.B',1,true))
  assert(not artifact.assembly:find('MOVE.AB',1,true) and not artifact.assembly:find('MOVE.BA',1,true))
  local _,moves=artifact.assembly:gsub('MOVE%.[AB]','')
  assert(moves==1,'only the reversed comparison result requires transport')
 end
 local assembly=artifact.assembly
 if index==1 then
  -- A frontend function's RET source is independent of an external caller's
  -- bank. Keep actual live prefixes on both stacks across a vector return.
  assembly=assembly..[[
.function probe 0 6
 PUSH.A 7
 PUSH.B 9
 PUSH.B 100
 PUSH.B 20
 PUSH.B 3
 CALL.B main 3
 MOVE.A
 RET.B 0 6
.export probe
]]
 end
 local path=base..'-'..index..'.abc';local optimized=path..'.opt'
 util.write(path,assembler.assemble(assembly))
 local text,status=run(string.format('%q %q -o %q',root..'build/abc-opt',path,optimized));assert(status==0,text)
 for _,module in ipairs{path,optimized} do for _,mode in ipairs{'interpreted','compiled','lazy','jit=threaded'} do
  text,status=run(string.format('%q run %q main %s --%s',root..'build/abc-runtime',module,fixture[2],mode))
  if fixture[3] then assert(status==0 and text==fixture[3],text)
  else assert(status==1 and text:find('language abort 1',1,true),text) end
  checks=checks+1
  if index==1 then
   text,status=run(string.format('%q run %q probe --%s',root..'build/abc-runtime',module,mode))
   assert(status==0 and text=='9 111 83 16 1 7',text);checks=checks+1
  end
 end end
 if index~=2 then
  local cpath=path..'.c';local executable=path..'.exe'
  text,status=run(string.format('%q --emit-c %q -o %q',root..'build/abc-opt',path,cpath));assert(status==0,text)
  local driver=index==1 and [[
int main(void) {
 uint64_t args[3]={100,20,3},results[6]={0};abc_aot_error error;
 if(abc_export_main(args,3,results,4,&error)!=ABC_AOT_OK)return 1;
 if(results[0]!=111||results[1]!=83||results[2]!=16||results[3]!=1)return 2;
 if(abc_export_probe(NULL,0,results,6,&error)!=ABC_AOT_OK)return 3;
 return results[0]!=9||results[1]!=111||results[2]!=83||results[3]!=16||results[4]!=1||results[5]!=7;
}
]] or [[
int main(void) {
 uint64_t result=999;abc_aot_error error;
 int status=abc_export_main(NULL,0,&result,1,&error);
 return status!=ABC_AOT_ABORT||error.reason!=1||error.offset!=4||result!=999;
}
]]
  util.write(cpath,util.read(cpath)..driver)
  text,status=run(string.format('%q -O2 -std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-unused-function %q -o %q',arg[1] or os.getenv('CC') or 'cc',cpath,executable));assert(status==0,text)
  text,status=run(string.format('%q',executable));assert(status==0,text);checks=checks+1
  os.remove(cpath);os.remove(executable)
 end
 os.remove(path);os.remove(optimized)
end
print(('PASS: symmetric frontend placement, NaN comparisons and evaluation order (%d executions)'):format(checks))
