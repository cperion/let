-- Generate register-addressed x86-64 stencil sources from shared VM semantics.
local root=(arg[0]:match('^(.*)/[^/]+$') or '.')
package.path=root..'/?.lua;'..package.path
local semantics=require('semantics')
local forms=require('execution_forms')
local compute=require('execution_compute')
local dir=assert(arg[1],'output directory required')
local c=assert(io.open(dir..'/stencils.c.tmp','wb'))
local order=assert(io.open(dir..'/stencils.order.tmp','wb'))
local names=assert(io.open(dir..'/stencil_names.h.tmp','wb'))
local n=0
local function emit(s) assert(c:write(s,'\n')) end
local function stencil(name,body,args,result)
  local form=assert(forms.by_name[name],'unregistered execution form '..name)
  assert(form.id==n,'native binding order disagrees with execution forms: '..name)
  order:write(name,'\n')
  names:write(('#define ABC_STENCIL_%s %d\n'):format(name:upper(),n))
  n=n+1
  emit(('%s %s(%s) { %s }'):format(result or 'ABC_JIT_CC abc_value',name,args or 'ABC_JIT_ARGS',body))
end
emit('#include <stdint.h>')
emit('#include <math.h>')
emit('#include <stddef.h>')
emit('#include "owner.h"')
emit('typedef uint64_t abc_value;')
emit('#define ABC_JIT_CC __attribute__((preserve_none))')
emit('#define ABC_JIT_ARGS abc_value *asp, abc_value *bsp, abc_value *csp, abc_value r0, abc_value r1, abc_value r2, abc_value r3, abc_value r4, abc_value r5, abc_value r6, abc_value r7')
emit('#define ABC_JIT_PASS asp,bsp,csp,r0,r1,r2,r3,r4,r5,r6,r7')
emit('typedef ABC_JIT_CC abc_value (*abc_jit_fn)(ABC_JIT_ARGS);')
emit('typedef abc_value (*abc_lazy_prepare_fn)(abc_value,abc_value *);')
emit('typedef abc_value (*abc_resolve_fn)(abc_value,abc_value,uintptr_t,uintptr_t,uintptr_t,abc_value *);')
emit('typedef unsigned (*abc_foreign_bridge)(const void *,void (*)(void),const abc_value *,abc_value *);')
emit('typedef void *(*abc_memory_copy_fn)(void *,const void *,size_t);')
emit('typedef void (*abc_release_field_fn)(abc_owner_context *,abc_owner *,size_t,abc_value);')
emit('typedef void *(*abc_release_data_fn)(const abc_owner *);')
emit('typedef uint64_t *(*abc_release_progress_fn)(const abc_owner *);')
emit('typedef void (*abc_release_enqueue_fn)(abc_owner_context *,abc_owner *);')
emit('typedef abc_value *(*abc_bounds_fn)(unsigned);')
emit('#define TAIL __attribute__((musttail))')
emit('extern ABC_JIT_CC abc_value HOLE_NEXT(ABC_JIT_ARGS);')
emit('extern ABC_JIT_CC abc_value HOLE_TAKEN(ABC_JIT_ARGS);')
emit('extern char HOLE_IMM[], HOLE_IMM2[], HOLE_BIAS[], HOLE_FINAL[], HOLE_STATE[], HOLE_ERROR[];')
compute.helpers(emit)
emit('static __attribute__((always_inline)) inline abc_value jit_error(void){abc_value x;__asm__("movabsq $HOLE_ERROR,%0":"=r"(x));return x;}')
emit('static __attribute__((always_inline)) inline abc_value jit_final(void){abc_value x;__asm__("movabsq $HOLE_FINAL,%0":"=r"(x));return x;}')
emit('#define NEXT TAIL return HOLE_NEXT(ABC_JIT_PASS);')
local R=forms.native_registers
for d=0,R-1 do
  stencil(('const_%d'):format(d),('__asm__("movabsq $HOLE_IMM,%%0":"=r"(r%d)); NEXT'):format(d))
  for s=0,R-1 do
    if d~=s then stencil(('mov_%d_%d'):format(d,s),('r%d=r%d; NEXT'):format(d,s)) end
  end
end
local binary=semantics.binary_order

for _,op in ipairs(binary) do
  local expr=assert(semantics.binary[op],op)
  for d=0,R-1 do for s=0,R-1 do
    local e=semantics.expr(expr,'r'..d,'r'..s)
    local guard=semantics.transfers[op].check_zero and ('if(!r%d)return jit_error(); '):format(s) or ''
    stencil(('%s_%d_%d'):format(op:lower(),d,s),guard..('r%d=%s; NEXT'):format(d,e))
  end end
end
local binary32=forms.binary32
local asm32={ADD='addl',SUB='subl',MUL='imull',AND='andl',OR='orl',XOR='xorl'}
for _,op in ipairs(binary32) do for d=0,R-1 do for s=0,R-1 do
  stencil(('u32_%s_%d_%d'):format(op:lower(),d,s),('__asm__("%s %%k1,%%k0":"+r"(r%d):"r"(r%d)); NEXT'):format(asm32[op],d,s))
end end end
local unary=semantics.unary_order
for _,op in ipairs(unary) do
  local expr=assert(semantics.unary[op],op)
  for d=0,R-1 do
    stencil(('%s_%d'):format(op:lower(),d),('r%d=%s; NEXT'):format(d,semantics.expr(expr,'r'..d)))
  end
end
local immediate=semantics.immediate_order
local immediate_asm={ADD='addq',SUB='subq',MUL='imulq',AND='andq',OR='orq',XOR='xorq',SHL='shlq',SHR='shrq',SAR='sarq'}
for _,op in ipairs(immediate) do
  for d=0,R-1 do
    stencil(('%si_%d'):format(op:lower(),d),('__asm__("%s $HOLE_IMM,%%0":"+r"(r%d)); NEXT'):format(immediate_asm[op],d))
  end
end

local immediate32_asm={ADD='addl',SUB='subl',MUL='imull',AND='andl',OR='orl',XOR='xorl',SHL='shll',SHR='shrl',SAR='sarl'}
for _,op in ipairs(immediate) do for d=0,R-1 do
  stencil(('u32_%si_%d'):format(op:lower(),d),('__asm__("%s $HOLE_IMM,%%k0":"+r"(r%d)); NEXT'):format(immediate32_asm[op],d))
end end

for d=0,R-1 do
  stencil(('jz_%d'):format(d),('__asm__("testq %%0,%%0; jz HOLE_TAKEN"::"r"(r%d):"cc"); __builtin_unreachable();'):format(d))
  stencil(('jnz_%d'):format(d),('__asm__("testq %%0,%%0; jnz HOLE_TAKEN"::"r"(r%d):"cc"); __builtin_unreachable();'):format(d))
  for _,stack in ipairs({'a','b','c'}) do
    stencil(('load_%s_%d'):format(stack,d),('__asm__("movq HOLE_IMM(%%1),%%0":"=r"(r%d):"r"(%ssp)); NEXT'):format(d,stack))
    stencil(('store_%s_%d'):format(stack,d),('__asm__("movq %%1,HOLE_IMM(%%0)"::"r"(%ssp),"r"(r%d):"memory"); NEXT'):format(stack,d))
  end
end
local branches=forms.branches
local branch_cc={EQ='je',NE='jne',LT='jl',LE='jle',LTU='jb',LEU='jbe'}
for _,op in ipairs(branches) do
  for a=0,R-1 do for b=0,R-1 do
    stencil(('b%s_%d_%d'):format(op:lower(),a,b),('__asm__("cmpq %%1,%%0; %s HOLE_TAKEN"::"r"(r%d),"r"(r%d):"cc"); __builtin_unreachable();'):format(branch_cc[op],a,b))
  end end
end


for _,op in ipairs(semantics.float_binary_order) do for d=0,R-1 do for s=0,R-1 do
  local expression=semantics.expr(semantics.float_binary[op],'r'..d,'r'..s)
  stencil(('float_%s_%d_%d'):format(op:lower(),d,s),('r%d=%s; NEXT'):format(d,expression))
end end end

for _,op in ipairs(semantics.float_unary_order) do for d=0,R-1 do
  stencil(('float_%s_%d'):format(op:lower(),d),compute.float_unary(op,'r'..d,'jit_error()')..' NEXT')
end end

local float_cc={FBLT='jb',FBLE='jbe',FBEQ='je'}
for _,op in ipairs(semantics.float_branch_order) do for a=0,R-1 do for b=0,R-1 do
  stencil(('float_b%s_%d_%d'):format(op:sub(3):lower(),a,b),('__asm__("movq %%0,%%%%xmm0; movq %%1,%%%%xmm1; ucomisd %%%%xmm1,%%%%xmm0; jp 1f; %s HOLE_TAKEN; 1:"::"r"(r%d),"r"(r%d):"xmm0","xmm1","cc"); __builtin_unreachable();'):format(float_cc[op],a,b))
end end end
local loads=forms.loads
local load_ins={u8='movzbq',u16='movzwq',u32='movl',s32='movslq',u64='movq'}
local load_dst={u8='%0',u16='%0',u32='%k0',s32='%0',u64='%0'}
for _,kind in ipairs(loads) do for d=0,R-1 do local k=kind[1]; stencil(('mem_load_%s_%d'):format(k,d),'__asm__("'..load_ins[k]..' HOLE_IMM(%0),'..load_dst[k]..'":"+r"(r'..d..')::"memory"); NEXT') end end
local stores=forms.stores
local store_ins={u8='movb',u16='movw',u32='movl',u64='movq'}
local store_src={u8='%b1',u16='%w1',u32='%k1',u64='%1'}
for _,kind in ipairs(stores) do for a=0,R-1 do for v=0,R-1 do local k=kind[1]; stencil(('mem_store_%s_%d_%d'):format(k,a,v),'__asm__("'..store_ins[k]..' '..store_src[k]..',HOLE_IMM(%0)"::"r"(r'..a..'),"r"(r'..v..'):"memory"); NEXT') end end end

for a=0,R-1 do for i=0,R-1 do stencil(('index_%d_%d'):format(a,i),('r%d+=(abc_value)((int32_t)(intptr_t)HOLE_IMM)*r%d; NEXT'):format(a,i)) end end

for a=0,R-1 do for b=0,R-1 do
  stencil(('memcpy_%d_%d'):format(a,b),('{size_t n=(uint32_t)(uintptr_t)HOLE_IMM;if(n){abc_value copy;__asm__("movabsq $HOLE_FINAL,%%0":"=r"(copy));((abc_memory_copy_fn)(uintptr_t)copy)((void *)(uintptr_t)r%d,(const void *)(uintptr_t)r%d,n);}} NEXT'):format(a,b))
end end

stencil('calloc','{uint64_t*d=csp+(int32_t)(intptr_t)HOLE_IMM2;size_t n=(uint32_t)(uintptr_t)HOLE_IMM;while(n--)*d++=0;} NEXT')

for _,kind in ipairs(loads) do for d=0,R-1 do local k=kind[1]; stencil(('frame_load_%s_%d'):format(k,d),'__asm__("'..load_ins[k]..' HOLE_IMM(%1),'..load_dst[k]..'":"=r"(r'..d..'):"r"(csp):"memory"); NEXT') end end

for _,kind in ipairs(stores) do for v=0,R-1 do local k=kind[1]; stencil(('frame_store_%s_%d'):format(k,v),'__asm__("'..store_ins[k]..' '..store_src[k]..',HOLE_IMM(%0)"::"r"(csp),"r"(r'..v..'):"memory"); NEXT') end end

for d=0,R-1 do stencil(('frame_addr_%d'):format(d),'__asm__("leaq HOLE_IMM(%1),%0":"=r"(r'..d..'):"r"(csp)); NEXT') end

for _,kind in ipairs(loads) do for d=0,R-1 do stencil(('global_load_%s_%d'):format(kind[1],d),('r%d=(abc_value)*(%s *)(uintptr_t)HOLE_FINAL; NEXT'):format(d,kind[2])) end end

for _,kind in ipairs(stores) do for v=0,R-1 do stencil(('global_store_%s_%d'):format(kind[1],v),('*('..kind[2]..' *)(uintptr_t)HOLE_FINAL=('..kind[2]..')r'..v..'; NEXT')) end end

for d=0,R-1 do stencil(('global_addr_%d'):format(d),('r%d=(abc_value)(uintptr_t)HOLE_FINAL; NEXT'):format(d)) end

for a=0,R-1 do for b=0,R-1 do stencil(('pow_%d_%d'):format(a,b),compute.power('POW','r'..a,'r'..b,'jit_error()')..' NEXT') end end
for a=0,R-1 do for b=0,R-1 do stencil(('pows_%d_%d'):format(a,b),compute.power('POWS','r'..a,'r'..b,'jit_error()')..' NEXT') end end
local check_suffix=forms.check_suffix
for _,op in ipairs(semantics.check_order) do for r=0,R-1 do
  local condition=semantics.expr(assert(semantics.checks[op]),'r'..r)
  stencil(('check_%s_%d'):format(check_suffix[op],r),('if(%s)return jit_error(); NEXT'):format(condition))
end end

for _,stack in ipairs{'a','b'} do for results=0,1 do
  local arguments=stack..'sp+(int32_t)(intptr_t)HOLE_IMM'
  local publish=results==1 and stack..'sp[(int32_t)(intptr_t)HOLE_IMM]=out;' or ''
  stencil(('fcall_%s_%d'):format(stack,results),'abc_value bridge,ext,target,out=0;__asm__("movabsq $HOLE_FINAL,%0":"=r"(bridge));__asm__("movabsq $HOLE_STATE,%0":"=r"(ext));__asm__("movabsq $HOLE_BIAS,%0":"=r"(target));unsigned status=((abc_foreign_bridge)(uintptr_t)bridge)((const void *)(uintptr_t)ext,(void(*)(void))(uintptr_t)target,'..arguments..',&out);if(status)return (jit_error()&~UINT64_C(255))|status;'..publish..'NEXT')
end end
stencil('abort','return jit_error();')
for index,stack in ipairs({'a','b','c'}) do stencil('guard_'..stack,('abc_value raw,*next;__asm__("movabsq $HOLE_FINAL,%%0":"=r"(raw));__asm__("leaq HOLE_IMM(%%1),%%0":"=r"(next):"r"(%ssp));if(next>((abc_bounds_fn)(uintptr_t)raw)(%d))return jit_error();NEXT'):format(stack,index-1)) end
stencil('resolve_indirect','abc_value resolver,pc,entry;__asm__("movabsq $HOLE_FINAL,%0":"=r"(resolver));__asm__("movabsq $HOLE_STATE,%0":"=r"(pc));abc_value status=((abc_resolve_fn)(uintptr_t)resolver)(r0,pc,(uintptr_t)asp+(intptr_t)HOLE_IMM,(uintptr_t)bsp+(intptr_t)HOLE_BIAS,(uintptr_t)csp+(intptr_t)HOLE_IMM2,&entry);if(status)return status;r0=entry;NEXT')
-- Frame transport falls through to ordinary transfers; no call/return fusion.
-- STORE_LABEL uses compiler scratch, leaving every carried bank register intact.
stencil('store_label','abc_value label;__asm__("movabsq $HOLE_TAKEN,%0":"=r"(label));__asm__("movq %1,HOLE_IMM(%0)"::"r"(csp),"r"(label):"memory");NEXT')
for _,stack in ipairs({'a','b','c'}) do
  stencil('rebase_'..stack,('__asm__("leaq HOLE_IMM(%%0),%%0":"+r"(%ssp));NEXT'):format(stack))
end
for r=0,R-1 do
  stencil(('continue_%d'):format(r),('TAIL return ((abc_jit_fn)(uintptr_t)r%d)(ABC_JIT_PASS);'):format(r))
end
stencil('jump','TAIL return HOLE_TAKEN(ABC_JIT_PASS);')
stencil('finish','*(abc_value *)(uintptr_t)HOLE_FINAL=r0; return 0;')
stencil('return_ok','return 0;')

stencil('lazy_entry','abc_value state,prepare;__asm__("movabsq $HOLE_STATE,%0":"=r"(state));abc_value body=__atomic_load_n((abc_value*)(uintptr_t)state,__ATOMIC_ACQUIRE);if(!body){__asm__("movabsq $HOLE_FINAL,%0":"=r"(prepare));abc_value failure=0;body=((abc_lazy_prepare_fn)(uintptr_t)prepare)(state,&failure);if(failure)return failure;}TAIL return ((abc_jit_fn)(uintptr_t)body)(ABC_JIT_PASS);')
for r=0,R-1 do
 stencil(('release_field_%d'):format(r),('abc_value raw,offset,ordinal;__asm__("movabsq $HOLE_FINAL,%%0":"=r"(raw));__asm__("movabsq $HOLE_IMM,%%0":"=r"(offset));__asm__("movabsq $HOLE_STATE,%%0":"=r"(ordinal));((abc_release_field_fn)(uintptr_t)raw)((abc_owner_context*)(uintptr_t)r7,(abc_owner*)(uintptr_t)r%d,(size_t)offset,ordinal);NEXT'):format(r))
end
for _,kind in ipairs{'data','progress','enqueue'} do for r=0,R-1 do
 local expression
 if kind=='data' then expression=('r%d=(abc_value)(uintptr_t)((abc_release_data_fn)(uintptr_t)raw)((abc_owner*)(uintptr_t)r%d);'):format(r,r)
 elseif kind=='progress' then expression=('r%d=*((abc_release_progress_fn)(uintptr_t)raw)((abc_owner*)(uintptr_t)r%d);'):format(r,r)
 else expression=('((abc_release_enqueue_fn)(uintptr_t)raw)((abc_owner_context*)(uintptr_t)r7,(abc_owner*)(uintptr_t)r%d);'):format(r) end
 stencil(('release_%s_%d'):format(kind,r),'abc_value raw;__asm__("movabsq $HOLE_FINAL,%0":"=r"(raw));'..expression..'NEXT')
end end
-- One normal native frame contains homes/spills chosen by the existing symbolic
-- allocator. No VM context, ABC frame chain, TLS rebinding or cleanup stacks.
stencil('release_entry','abc_value bytes,b,c;__asm__("movabsq $HOLE_IMM,%0":"=r"(bytes));__asm__("movabsq $HOLE_BIAS,%0":"=r"(b));__asm__("movabsq $HOLE_IMM2,%0":"=r"(c));unsigned char *frame=__builtin_alloca((size_t)bytes);(void)HOLE_TAKEN((abc_value*)frame,(abc_value*)(frame+b),(abc_value*)(frame+c),(abc_value)(uintptr_t)owner,0,0,0,0,0,0,(abc_value)(uintptr_t)context);','abc_owner_context *context,abc_owner *owner','void')
assert(n==#forms.forms,'missing native execution form bindings')
names:write(('#define ABC_STENCIL_COUNT %d\n'):format(n))
assert(c:close()); assert(order:close()); assert(names:close())
assert(os.rename(dir..'/stencils.c.tmp',dir..'/stencils.c'))
assert(os.rename(dir..'/stencils.order.tmp',dir..'/stencils.order'))
assert(os.rename(dir..'/stencil_names.h.tmp',dir..'/stencil_names.h'))
io.stderr:write(('generated %d register-addressed stencils\n'):format(n))

