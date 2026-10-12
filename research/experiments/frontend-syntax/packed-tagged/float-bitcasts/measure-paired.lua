-- Paired, interleaved comparison in one process; same IR/runtime/host, two lowerings.
-- Argument is the adapted pre-packed abc.lua recorded in README, not runtime code.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local S=require('let.schema');require('let.ir')
local current=require('let.abc');local before=assert(loadfile(assert(arg[1])))()
local Stage,ffi,Int=require('let.stage'),require('let.abi'),require('int64')
local assembler,optimizer=require('assembler'),require('let.optimize')
local I,L=S.Ir,S.List
local ty=S.Sum{value=S.F64}
local function value(id,t)return I.Ref(I.Value(id),t)end
local function median(v)table.sort(v);return v[math.floor(#v/2)+1]end
for _,arithmetic in ipairs{false,true} do
 local result=value(3,S.F64)
 if arithmetic then result=I.Bin(I.Add,result,I.Const(S.F64,I.FloatBits(1073741824,0)),S.F64) end
 local fns={I.Fn('main',I.Entry,0,L{S.inValue(S.F64)},L{S.F64},L{I.ValueParam(0,I.Value(1),S.F64)},L{
  I.ConstructVariant(I.Value(2),ty,'value',value(1,S.F64)),
  I.VariantPayload(I.Value(3),I.Value(2),ty,'value'),I.Return(L{result})})}
 local artifacts={before.lower(fns,{profile='slet',exports={'main'}}),current.lower(fns,{profile='slet',exports={'main'}})}
 print('fixture',arithmetic and 'add' or 'roundtrip')
 for i,artifact in ipairs(artifacts) do
  local bytes=assembler.assemble(artifact.assembly)
  print(i==1 and 'before' or 'current','raw',#bytes,'optimized',#optimizer.optimize(bytes),'CALLOC',select(2,artifact.assembly:gsub('CALLOC','')))
 end
 for _,optimized in ipairs{false,true} do for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
  local sessions,programs,outputs,counts,errors={},{},{},{},{}
  local args=ffi.new('uint64_t[1]');args[0]=Int.parse(arithmetic and '0x3ff8000000000000' or '0x7ff0000000000001')
  local expected=Int.parse(arithmetic and '0x400c000000000000' or '0x7ff0000000000001')
  local times={{},{}};local preparation,first={},{}
  local function call(i)
   local session=sessions[i]
   local status=session.C.abc_vm_call(session.vm,programs[i].handle,'main',args,1,outputs[i],1,counts[i],errors[i])
   if status~=0 then error(ffi.string(errors[i][0].message)) end
  end
  for i=1,2 do
   sessions[i]=Stage.open{mode=mode,optimize=optimized};local start=os.clock();programs[i]=sessions[i]:prepare(artifacts[i],fns);preparation[i]=os.clock()-start
   outputs[i],counts[i],errors[i]=ffi.new('uint64_t[1]'),ffi.new('size_t[1]'),ffi.new('abc_error[1]')
   start=os.clock();call(i);first[i]=os.clock()-start
   assert(counts[i][0]==1 and outputs[i][0]==expected,'exact first-call bits')
  end
  for _=1,10000 do call(1);call(2) end
  local iterations=200000
  for sample=1,9 do for pass=1,2 do
   local i=sample%2==1 and pass or 3-pass
   local start=os.clock();for _=1,iterations do call(i) end;times[i][#times[i]+1]=(os.clock()-start)/iterations
  end end
  for i=1,2 do assert(outputs[i][0]==expected,'exact steady bits');sessions[i]:close() end
  local a,b=median(times[1]),median(times[2])
  print(('optimized=%s mode=%s before_ns=%.1f current_ns=%.1f delta_pct=%+.1f prepare_ms=%.3f/%.3f first_us=%.1f/%.1f'):format(tostring(optimized),mode,1e9*a,1e9*b,100*(b/a-1),1e3*preparation[1],1e3*preparation[2],1e6*first[1],1e6*first[2]))
 end end
end
