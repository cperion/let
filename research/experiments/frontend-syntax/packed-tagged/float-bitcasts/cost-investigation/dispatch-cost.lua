-- Verified bytecode-only dispatch-cost isolation; runtime/generators are unchanged.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local Stage,ffi,S,Int=require('let.stage'),require('let.abi'),require('let.schema'),require('int64')
require('let.ir')
local I,L=S.Ir,S.List
local modes=arg[1]=='all' and {'interpreted','threaded','eager','lazy'} or {'interpreted'}
local families={
 {name='integer_bitcasts',kind='i',type=S.U64,ops={'BITS2F','F2BITS'}},
 {name='integer_core_identities',kind='i',type=S.U64,ops={'ORI','ORI'},immediate=' 0'},
 {name='float_bitcasts',kind='f',type=S.F64,ops={'F2BITS','BITS2F'}},
 {name='float_sign_pair',kind='f',type=S.F64,ops={'FNEG','FNEG'}},
}
local function median(xs) table.sort(xs);return xs[math.floor(#xs/2)+1] end
print('mode,bank,pairs,family,raw_bytes,median_ns,ns_per_operation_above_baseline')
for _,mode in ipairs(modes) do for _,bank in ipairs{'A','B'} do for _,pairs in ipairs{0,1,8,32,128,512} do
 local programs,sessions,outputs,counts,errors,images={},{},{},{},{},{}
 local times={{},{},{},{}}
 local inputs=ffi.new('uint64_t[1]');inputs[0]=Int.parse('0x7ff0000000000001')
 for index,family in ipairs(families) do
  local text={'.profile memory',('.function main 1 1 %s %s'):format(family.kind,family.kind),' CGET.'..bank..' 0'}
  for _=1,pairs do for _,op in ipairs(family.ops) do text[#text+1]=' '..op..'.'..bank..(family.immediate or '') end end
  text[#text+1]=' RET.'..bank..' 1 1';text[#text+1]='.export main'
  local artifact={profile='slet',assembly=table.concat(text,'\n'),moduleData={}}
  local fn=I.Fn('main',I.Entry,0,L{S.inValue(family.type)},L{family.type},L{I.ValueParam(0,I.Value(1),family.type)},L{I.Return(L{I.Ref(I.Value(1),family.type)})})
  sessions[index]=Stage.open{mode=mode,optimize=false}
  programs[index]=sessions[index]:prepare(artifact,{fn});images[index]=#programs[index].image
  outputs[index],counts[index],errors[index]=ffi.new('uint64_t[1]'),ffi.new('size_t[1]'),ffi.new('abc_error[1]')
 end
 local function call(index)
  local session=sessions[index]
  local status=session.C.abc_vm_call(session.vm,programs[index].handle,'main',inputs,1,outputs[index],1,counts[index],errors[index])
  if status~=0 then error(ffi.string(errors[index][0].message)) end
 end
 for _=1,1000 do for index=1,4 do call(index) end end
 local iterations=math.max(10000,math.floor(3000000/(2*pairs+3)))
 for sample=1,9 do for pass=1,4 do
  local index=(pass+sample-2)%4+1
  local start=os.clock();for _=1,iterations do call(index) end
  times[index][#times[index]+1]=(os.clock()-start)*1e9/iterations
 end end
 for index,family in ipairs(families) do
  assert(counts[index][0]==1 and outputs[index][0]==inputs[0],'raw signaling-NaN bits changed')
  local ns=median(times[index]);family.baselines=family.baselines or {};local key=mode..bank
  if pairs==0 then family.baselines[key]=ns end
  local slope=pairs==0 and 0 or (ns-family.baselines[key])/(2*pairs)
  print(('%s,%s,%d,%s,%d,%.3f,%.3f'):format(mode,bank,pairs,family.name,images[index],ns,slope))
  sessions[index]:close()
 end
end end end
