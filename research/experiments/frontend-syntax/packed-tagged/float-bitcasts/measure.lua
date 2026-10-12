-- Exact runtime input, raw-cell VM calls. Run from either frontend with same runtime.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C,S=require('let.compiler'),require('let.schema');require('let.ir')
local Stage,ffi,Int=require('let.stage'),require('let.abi'),require('int64')
local I,L=S.Ir,S.List
local ty=S.Sum{value=S.F64}
local function value(id,t)return I.Ref(I.Value(id),t)end
local function functions(arithmetic)
 local result=value(3,S.F64)
 if arithmetic then result=I.Bin(I.Add,result,I.Const(S.F64,I.FloatBits(1073741824,0)),S.F64) end
 return {I.Fn('main',I.Entry,0,L{S.inValue(S.F64)},L{S.F64},L{I.ValueParam(0,I.Value(1),S.F64)},L{
  I.ConstructVariant(I.Value(2),ty,'value',value(1,S.F64)),
  I.VariantPayload(I.Value(3),I.Value(2),ty,'value'),I.Return(L{result})})}
end
local function median(v)table.sort(v);return v[math.floor(#v/2)+1]end
for _,arithmetic in ipairs{false,true} do
 local fns=functions(arithmetic);local artifact=C.lower(fns,{profile='slet',exports={'main'}})
 print('fixture',arithmetic and 'add' or 'roundtrip','raw module bytes',#require('assembler').assemble(artifact.assembly),'CALLOC',select(2,artifact.assembly:gsub('CALLOC','')))
 for _,optimized in ipairs{false,true} do for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
  local session=Stage.open{mode=mode,optimize=optimized};local start=os.clock()
  local program=session:prepare(artifact,fns);local preparation=os.clock()-start
  local args,out,count,err=ffi.new('uint64_t[1]'),ffi.new('uint64_t[1]'),ffi.new('size_t[1]'),ffi.new('abc_error[1]')
  args[0]=Int.parse(arithmetic and '0x3ff8000000000000' or '0x7ff0000000000001')
  local expected=Int.parse(arithmetic and '0x400c000000000000' or '0x7ff0000000000001')
  local function call()
   assert(session.C.abc_vm_call(session.vm,program.handle,'main',args,1,out,1,count,err)==0,ffi.string(err[0].message))
  end
  start=os.clock();call();local first=os.clock()-start
  assert(count[0]==1 and out[0]==expected,'exact first-call result')
  for _=1,1000 do call() end
  local times={};local iterations=20000
  for _=1,7 do start=os.clock();for _=1,iterations do call() end;times[#times+1]=(os.clock()-start)/iterations end
  assert(out[0]==expected,'exact steady result')
  print(('optimized=%s mode=%s prepare_ms=%.3f first_us=%.3f steady_ns=%.1f'):format(tostring(optimized),mode,1000*preparation,1e6*first,1e9*median(times)))
  session:close()
 end end
end
