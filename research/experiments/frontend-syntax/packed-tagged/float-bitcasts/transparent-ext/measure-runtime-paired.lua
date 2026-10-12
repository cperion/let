-- Same bytecode images, two locally loaded runtimes, alternating raw public calls.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local ffi,Int=require('let.abi'),require('int64')
local Asm,Opt=require('assembler'),require('let.optimize')
local S=require('let.schema');require('let.ir')
local I,L=S.Ir,S.List
local libraries={ffi.load(assert(arg[1],'before runtime path')),ffi.load(arg[2] or '../build/libabc.so')}
local dump=arg[3]
local manifest=dump and assert(io.open(dump..'/manifest.txt','w'))
local function median(v) table.sort(v);return v[math.floor(#v/2)+1] end
local function program(C,image,mode)
 local err,mp,vp=ffi.new('abc_error[1]'),ffi.new('abc_module *[1]'),ffi.new('abc_vm *[1]')
 local function status(s) assert(s==0,ffi.string(err[0].message)) end
 status(C.abc_module_load(image,#image,mp,err))
 local limits=ffi.new('abc_limits[1]');limits[0].mode=mode
 status(C.abc_vm_create(limits,vp,err));status(C.abc_vm_load(vp[0],mp[0],err))
 return {C=C,module=mp[0],vm=vp[0],output=ffi.new('uint64_t[1]'),count=ffi.new('size_t[1]'),err=err}
end
local function measure(name,image,mode,raw,expected,iterations)
 if dump then
  local path=dump..'/'..name..'_mode_'..mode..'.abc'
  local file=assert(io.open(path,'wb'));assert(file:write(image));assert(file:close())
  assert(manifest:write(name,' ',mode,' ',path,' ',raw,' ',expected,'\n'))
  return
 end
 local inputs=ffi.new('uint64_t[1]');inputs[0]=Int.parse(raw)
 local programs={program(libraries[1],image,mode),program(libraries[2],image,mode)}
 local times={{},{}}
 local function call(index)
  local p=programs[index]
  local status=p.C.abc_vm_call(p.vm,p.module,'main',inputs,1,p.output,1,p.count,p.err)
  if status~=0 then error(ffi.string(p.err[0].message)) end
 end
 for _=1,10000 do call(1);call(2) end
 for sample=1,11 do for pass=1,2 do
  local index=sample%2==1 and pass or 3-pass
  local start=os.clock();for _=1,iterations do call(index) end
  times[index][#times[index]+1]=(os.clock()-start)*1e9/iterations
 end end
 for _,p in ipairs(programs) do
  assert(p.count[0]==1 and p.output[0]==Int.parse(expected),'exact raw output: '..name)
  p.C.abc_vm_free(p.vm);p.C.abc_module_free(p.module)
 end
 local a,b=median(times[1]),median(times[2])
 print(('%s,%d,%d,%.3f,%.3f,%+.2f'):format(name,mode,#image,a,b,100*(b/a-1)))
end
print('fixture,mode,module_bytes,before_ns,after_ns,delta_percent')
-- Packed runtime input probes use the current lowering on both engines.
local Lower=require('let.abc');local sum=S.Sum{value=S.F64}
for _,arithmetic in ipairs{false,true} do
 local result=I.Ref(I.Value(3),S.F64)
 if arithmetic then result=I.Bin(I.Add,result,I.Const(S.F64,I.FloatBits(1073741824,0)),S.F64) end
 local fns={I.Fn('main',I.Entry,0,L{S.inValue(S.F64)},L{S.F64},L{I.ValueParam(0,I.Value(1),S.F64)},L{
  I.ConstructVariant(I.Value(2),sum,'value',I.Ref(I.Value(1),S.F64)),
  I.VariantPayload(I.Value(3),I.Value(2),sum,'value'),I.Return(L{result})})}
 local raw=Asm.assemble(Lower.lower(fns,{profile='slet',exports={'main'}}).assembly)
 for _,optimized in ipairs{false,true} do
  local image=optimized and Opt.optimize(raw) or raw
  for mode=0,3 do measure(('packed_%s_opt_%s'):format(arithmetic and 'add' or 'roundtrip',tostring(optimized)),image,mode,
   arithmetic and '0x3ff8000000000000' or '0x7ff0000000000001',arithmetic and '0x400c000000000000' or '0x7ff0000000000001',300000) end
 end
end
-- Unoptimized exact bitcasts and ordinary core/EXT controls, both destinations.
for _,bank in ipairs{'A','B'} do for _,n in ipairs{0,1,8,32,128} do
 for _,family in ipairs{'integer_casts','float_casts','core_ori','core_fneg','ext_addc','ext_branch'} do
  local floating=family=='float_casts' or family=='core_fneg'
  local kind=floating and 'f' or 'i'
  local text={'.profile memory',('.function main 1 1 %s %s'):format(kind,kind)}
  if family=='ext_branch' then
   for index=1,n do
    text[#text+1]=' CGET.'..bank..' 0'
    text[#text+1]=' BEQI.'..bank..' 1 next_'..index
    text[#text+1]=' ABORT 5'
    text[#text+1]='next_'..index..':'
   end
   text[#text+1]=' CGET.'..bank..' 0'
  else
   text[#text+1]=' CGET.'..bank..' 0'
   for _=1,n do
    if family=='integer_casts' then text[#text+1]=' BITS2F.'..bank;text[#text+1]=' F2BITS.'..bank
    elseif family=='float_casts' then text[#text+1]=' F2BITS.'..bank;text[#text+1]=' BITS2F.'..bank
    elseif family=='core_ori' then text[#text+1]=' ORI.'..bank..' 0';text[#text+1]=' ORI.'..bank..' 0'
    elseif family=='core_fneg' then text[#text+1]=' FNEG.'..bank;text[#text+1]=' FNEG.'..bank
    else text[#text+1]=' ADDC.'..bank..' 0';text[#text+1]=' ADDC.'..bank..' 0' end
   end
  end
  text[#text+1]=' RET.'..bank..' 1 1';text[#text+1]='.export main'
  local image=Asm.assemble(table.concat(text,'\n'))
  local control=family=='ext_addc' or family=='ext_branch'
  local raw=control and '1' or '0x7ff0000000000001'
  local expected=family=='ext_addc' and tostring(1+2*n) or raw
  -- The handler change is interpreted-only; other modes are checked above.
  measure(('%s_%s_pairs_%d'):format(family,bank,n),image,0,raw,expected,math.max(30000,math.floor(5000000/(2*n+3))))
 end
end end
if manifest then assert(manifest:close()) end
