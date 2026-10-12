-- Run from frontend, against either committed or working-copy abc.lua.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C,S=require('let.compiler'),require('let.schema');require('let.ir')
local Stage,ffi,Int=require('let.stage'),require('let.abi'),require('int64')
local I,L=S.Ir,S.ASDL.List
local function ref(n,t) return I.Ref(I.Value(n),t) end
local record=S.record{a=S.u8,b=S.u16,c=S.u32}
local inner=S.sum{value=record};local outer=S.sum{nested=inner};local floating=S.sum{value=S.f64}
local cases={
 {'float-construction',I.Fn('main',I.Entry,0,L{},L{floating},L{},L{
  I.ConstructVariant(I.Value(1),floating,'value',I.Const(S.f64,I.FloatBits(2147483648,0))),I.Return(L{ref(1,floating)})}),{}, {'0','0x8000000000000000'}},
 {'runtime-float-construction',I.Fn('main',I.Entry,0,L{S.inValue(S.f64)},L{floating},L{I.ValueParam(0,I.Value(1),S.f64)},L{
  I.ConstructVariant(I.Value(2),floating,'value',ref(1,S.f64)),I.Return(L{ref(2,floating)})}),{'0x7ff8000012345678'}, {'0','0x7ff8000012345678'}},
 {'float-extraction',I.Fn('main',I.Entry,0,L{S.inValue(floating)},L{S.f64},L{I.ValueParam(0,I.Value(1),floating)},L{
  I.VariantPayload(I.Value(2),I.Value(1),floating,'value'),I.Return(L{ref(2,S.f64)})}),{'0','0x8000000000000000'}, {'0x8000000000000000'}},
 {'float-arithmetic',I.Fn('main',I.Entry,0,L{S.inValue(floating)},L{S.f64},L{I.ValueParam(0,I.Value(1),floating)},L{
  I.VariantPayload(I.Value(2),I.Value(1),floating,'value'),I.Return(L{I.Bin(I.Add,ref(2,S.f64),I.Const(S.f64,I.Float(1)),S.f64)})}),{'0','0x8000000000000000'}, {'0x3ff0000000000000'}},
 {'nested-extraction',I.Fn('main',I.Entry,0,L{S.inValue(outer)},L{inner},L{I.ValueParam(0,I.Value(1),outer)},L{
  I.VariantPayload(I.Value(2),I.Value(1),outer,'nested'),I.Return(L{ref(2,inner)})}),{'0','0x89abcdef34560012'}, {'0x3456001200000000','0x89abcdef'}},
}
for _,case in ipairs(cases) do
 print('\nCASE '..case[1]);local artifact=C.lower({case[2]},{profile='slet',exports={'main'}});print(artifact.assembly)
 for _,optimize in ipairs{false,true} do for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
  local session=Stage.open{mode=mode,optimize=optimize}
  local ok,result=pcall(function()
   local program=session:prepare(artifact,{case[2]})
   local args=ffi.new('uint64_t[?]',math.max(1,#case[3]));for n,v in ipairs(case[3]) do args[n-1]=Int.parse(v) end
   local out,count,err=ffi.new('uint64_t[?]',#case[4]),ffi.new('size_t[1]'),ffi.new('abc_error[1]')
   local status=session.C.abc_vm_call(session.vm,program.handle,'main',args,#case[3],out,#case[4],count,err)
   if status~=0 then return 'VM failure: '..ffi.string(err[0].message) end
   local values,match={},tonumber(count[0])==#case[4]
   for n,v in ipairs(case[4]) do values[#values+1]=tostring(out[n-1]);match=match and out[n-1]==Int.parse(v) end
   return (match and 'PASS ' or 'MISMATCH ')..table.concat(values,', ')
  end)
  print(mode..' optimize='..tostring(optimize)..' '..(ok and result or tostring(result)));session:close()
 end end
end
