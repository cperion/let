-- Generate finite C-ABI bridges for the FCALL signature limits in docs/spec.md.
local output=assert(arg[1],'output C path required')
local f=assert(io.open(output..'.tmp','wb'))
local function emit(s) assert(f:write(s,'\n')) end
emit('#include "vm_internal.h"')
local shapes={}
local function bridge(n,mask)
  local types,args={},{}
  for i=0,n-1 do local fl=(mask & (1<<i))~=0;types[#types+1]=fl and 'double' or 'uint64_t';args[#args+1]=fl and ('vm_float(args[%d])'):format(i) or ('args[%d]'):format(i) end
  local params,actual,name=#types==0 and 'void' or table.concat(types,','),table.concat(args,','),('foreign_%d_%d'):format(n,mask)
  emit(('static abc_status %s(const abc_extern *ext,abc_foreign_address fn,const uint64_t *args,uint64_t *out){'):format(name))
  emit(('if(!ext->results){((void(*)(%s))fn)(%s);return ABC_OK;}'):format(params,actual))
  emit(('if(ext->result_kinds[0]==ABC_KIND_FLOAT){double r=((double(*)(%s))fn)(%s);*out=vm_float_bits(r);return ABC_OK;}'):format(params,actual))
  emit(('*out=((uint64_t(*)(%s))fn)(%s);return ABC_OK;}'):format(params,actual))
  shapes[#shapes+1]={key=n*1024+mask,name=name}
end
for n=0,10 do for mask=0,(1<<n)-1 do local fl,ints=0,0;for i=0,n-1 do if(mask&(1<<i))~=0 then fl=fl+1 else ints=ints+1 end end;if fl<=4 and ints<=6 then bridge(n,mask) end end end
emit('abc_foreign_bridge_fn abc_foreign_select(const abc_extern *ext){unsigned mask=0;for(unsigned i=0;i<ext->arguments;i++)if(ext->argument_kinds[i]==ABC_KIND_FLOAT)mask|=1u<<i;switch((ext->arguments<<10)|mask){')
for _,s in ipairs(shapes) do emit(('case %d:return %s;'):format(s.key,s.name)) end
emit('default:return NULL;}}')
emit('abc_status abc_foreign_invoke(const abc_extern *ext,abc_foreign_address fn,const uint64_t *args,uint64_t *out){abc_foreign_bridge_fn bridge=abc_foreign_select(ext);return bridge?bridge(ext,fn,args,out):ABC_INVALID;}')
assert(f:close());assert(os.rename(output..'.tmp',output))
