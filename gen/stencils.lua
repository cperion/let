-- Generate register-addressed x86-64 stencil sources from shared VM semantics.
local root=(arg[0]:match('^(.*)/[^/]+$') or '.')
package.path=root..'/?.lua;'..package.path
local semantics=require('semantics')
local dir=assert(arg[1],'output directory required')
local c=assert(io.open(dir..'/stencils.c.tmp','wb'))
local order=assert(io.open(dir..'/stencils.order.tmp','wb'))
local names=assert(io.open(dir..'/stencil_names.h.tmp','wb'))
local n=0
local function emit(s) assert(c:write(s,'\n')) end
local function stencil(name,body,args)
  order:write(name,'\n')
  names:write(('#define ABC_STENCIL_%s %d\n'):format(name:upper(),n))
  n=n+1
  emit(('ABC_JIT_CC abc_value %s(%s) { %s }'):format(name,args or 'ABC_JIT_ARGS',body))
end
emit('#include <stdint.h>')
emit('#include <math.h>')
emit('#include <stddef.h>')
emit('typedef uint64_t abc_value;')
emit('#define ABC_JIT_CC __attribute__((preserve_none))')
emit('#define ABC_JIT_ARGS abc_value *asp, abc_value *bsp, abc_value *csp, abc_value r0, abc_value r1, abc_value r2, abc_value r3, abc_value r4, abc_value r5, abc_value r6, abc_value r7')
emit('#define ABC_JIT_PASS asp,bsp,csp,r0,r1,r2,r3,r4,r5,r6,r7')
emit('typedef ABC_JIT_CC abc_value (*abc_jit_fn)(ABC_JIT_ARGS);')
emit('typedef abc_value (*abc_lazy_prepare_fn)(abc_value);')
emit('typedef abc_value (*abc_resolve_fn)(abc_value,abc_value);')
emit('typedef abc_value (*abc_dynamic_fn)(abc_value **,abc_value **,abc_value **,const unsigned char *,unsigned);')
emit('typedef void (*abc_managed_write_fn)(abc_value,unsigned);')
emit('typedef unsigned (*abc_foreign_bridge)(const void *,void (*)(void),const abc_value *,abc_value *);')
emit('#define TAIL __attribute__((musttail))')
emit('extern ABC_JIT_CC abc_value HOLE_NEXT(ABC_JIT_ARGS);')
emit('extern ABC_JIT_CC abc_value HOLE_TAKEN(ABC_JIT_ARGS);')
emit('extern char HOLE_IMM[], HOLE_IMM2[], HOLE_BIAS[], HOLE_FINAL[], HOLE_STATE[], HOLE_ERROR[];')
emit('static __attribute__((always_inline)) inline int64_t abc_signed(abc_value x){ return x<=INT64_MAX?(int64_t)x:-1-(int64_t)(UINT64_MAX-x); }')
emit('static __attribute__((always_inline)) inline abc_value vm_sar(abc_value x,abc_value n){ return n>=64?(x>>63?UINT64_MAX:0):(n?((x>>n)|(x>>63?UINT64_MAX<<(64-n):0)):x); }')
emit('static __attribute__((always_inline)) inline abc_value jit_pow(abc_value x,abc_value n){ abc_value r=1; while(n){if(n&1)r*=x;x*=x;n>>=1;}return r; }')
emit('static __attribute__((always_inline)) inline int32_t abc_i32_from_u64(abc_value x){ uint32_t lo=(uint32_t)x; return lo<UINT32_C(0x80000000)?(int32_t)lo:(int32_t)abc_signed((abc_value)lo|UINT64_C(0xffffffff00000000)); }')
emit('typedef union { abc_value u; double d; } jit_float_cast;')
emit('static __attribute__((always_inline)) inline double vm_float(abc_value x){jit_float_cast v={.u=x};return v.d;}')
emit('static __attribute__((always_inline)) inline abc_value vm_float_bits(double d){jit_float_cast v={.d=d};return v.u;}')
emit('static __attribute__((always_inline)) inline abc_value vm_fadd(abc_value x,abc_value y){return vm_float_bits(vm_float(x)+vm_float(y));}')
emit('static __attribute__((always_inline)) inline abc_value vm_fsub(abc_value x,abc_value y){return vm_float_bits(vm_float(x)-vm_float(y));}')
emit('static __attribute__((always_inline)) inline abc_value vm_fmul(abc_value x,abc_value y){return vm_float_bits(vm_float(x)*vm_float(y));}')
emit('static __attribute__((always_inline)) inline abc_value vm_fdiv(abc_value x,abc_value y){return vm_float_bits(vm_float(x)/vm_float(y));}')
emit('static __attribute__((always_inline)) inline int vm_flt(abc_value x,abc_value y){return vm_float(x)<vm_float(y);}')
emit('static __attribute__((always_inline)) inline int vm_fle(abc_value x,abc_value y){return vm_float(x)<=vm_float(y);}')
emit('static __attribute__((always_inline)) inline int vm_feq(abc_value x,abc_value y){return vm_float(x)==vm_float(y);}')
emit('static __attribute__((always_inline)) inline abc_value vm_u2f_bits(abc_value v,abc_value sign){if(!v)return sign;unsigned p=63u-(unsigned)__builtin_clzll(v);abc_value q;if(p<=52)q=v<<(52-p);else{unsigned s=p-52;abc_value rem=v&((UINT64_C(1)<<s)-1),half=UINT64_C(1)<<(s-1);q=v>>s;if(rem>half||(rem==half&&(q&1))){q++;if(q==UINT64_C(1)<<53){q>>=1;p++;}}}return sign|((abc_value)(p+1023)<<52)|(q&UINT64_C(0x000fffffffffffff));}')
emit('static __attribute__((always_inline)) inline abc_value vm_i2fs(abc_value x){abc_value s=x>>63?UINT64_C(0x8000000000000000):0;return vm_u2f_bits(s?0-x:x,s);}')
emit('static __attribute__((always_inline)) inline abc_value vm_i2fu(abc_value x){return vm_u2f_bits(x,0);}')
emit('static __attribute__((always_inline)) inline abc_value jit_error(void){abc_value x;__asm__("movabsq $HOLE_ERROR,%0":"=r"(x));return x;}')
emit('static __attribute__((always_inline)) inline abc_value jit_final(void){abc_value x;__asm__("movabsq $HOLE_FINAL,%0":"=r"(x));return x;}')
emit('#define NEXT TAIL return HOLE_NEXT(ABC_JIT_PASS);')
local R=8
local layout=assert(io.open(dir..'/stencil_layout.h.tmp','wb'))
layout:write('#ifndef ABC_STENCIL_LAYOUT_H\n#define ABC_STENCIL_LAYOUT_H\n')
layout:write('#define ABC_STENCIL_CONST(D) ((D)*8)\n')
layout:write('#define ABC_STENCIL_MOV(D,S) ((D)*8+1+((S)<(D)?(S):(S)-1))\n')
for d=0,R-1 do
  stencil(('const_%d'):format(d),('__asm__("movabsq $HOLE_IMM,%%0":"=r"(r%d)); NEXT'):format(d))
  for s=0,R-1 do
    if d~=s then stencil(('mov_%d_%d'):format(d,s),('r%d=r%d; NEXT'):format(d,s)) end
  end
end
local binary=semantics.binary_order
layout:write('#define ABC_STENCIL_BINARY_BASE 64\n#define ABC_STENCIL_BINARY(OP,D,S) (ABC_STENCIL_BINARY_BASE+(OP)*64+(D)*8+(S))\n')
for i,name in ipairs(binary) do layout:write(('#define ABC_JOP_%s %d\n'):format(name,i-1)) end
for _,op in ipairs(binary) do
  local expr=assert(semantics.binary[op],op)
  for d=0,R-1 do for s=0,R-1 do
    local e=semantics.expr(expr,'r'..d,'r'..s)
    local guard=(op:match('^DIV') or op:match('^REM')) and ('if(!r%d)return jit_error(); '):format(s) or ''
    stencil(('%s_%d_%d'):format(op:lower(),d,s),guard..('r%d=%s; NEXT'):format(d,e))
  end end
end
layout:write('#define ABC_STENCIL_BINARY_REV_BASE (ABC_STENCIL_BINARY_BASE+19*64)\n#define ABC_STENCIL_BINARY_REV(OP,D,S) (ABC_STENCIL_BINARY_REV_BASE+(OP)*64+(D)*8+(S))\n')
for _,op in ipairs(binary) do
  local expr=assert(semantics.binary[op],op)
  for d=0,R-1 do for s=0,R-1 do
    local e=semantics.expr(expr,'r'..s,'r'..d)
    local guard=(op:match('^DIV') or op:match('^REM')) and ('if(!r%d)return jit_error(); '):format(d) or ''
    stencil(('rev_%s_%d_%d'):format(op:lower(),d,s),guard..('r%d=%s; NEXT'):format(d,e))
  end end
end
local binary32={'ADD','SUB','MUL','AND','OR','XOR'}
layout:write('#define ABC_STENCIL_BINARY32_BASE (ABC_STENCIL_BINARY_REV_BASE+19*64)\n#define ABC_STENCIL_BINARY32(OP,D,S) (ABC_STENCIL_BINARY32_BASE+(OP)*64+(D)*8+(S))\n')
for i,name in ipairs(binary32) do layout:write(('#define ABC_J32_%s %d\n'):format(name,i-1)) end
local asm32={ADD='addl',SUB='subl',MUL='imull',AND='andl',OR='orl',XOR='xorl'}
for _,op in ipairs(binary32) do for d=0,R-1 do for s=0,R-1 do
  stencil(('u32_%s_%d_%d'):format(op:lower(),d,s),('__asm__("%s %%k1,%%k0":"+r"(r%d):"r"(r%d)); NEXT'):format(asm32[op],d,s))
end end end
layout:write('#define ABC_STENCIL_BINARY32_REV_BASE (ABC_STENCIL_BINARY32_BASE+6*64)\n#define ABC_STENCIL_BINARY32_REV(OP,D,S) (ABC_STENCIL_BINARY32_REV_BASE+(OP)*64+(D)*8+(S))\n')
for _,op in ipairs(binary32) do for d=0,R-1 do for s=0,R-1 do
  if op=='SUB' then stencil(('u32_rev_%s_%d_%d'):format(op:lower(),d,s),('r%d=(uint32_t)r%d-(uint32_t)r%d; NEXT'):format(d,s,d))
  else stencil(('u32_rev_%s_%d_%d'):format(op:lower(),d,s),('__asm__("%s %%k1,%%k0":"+r"(r%d):"r"(r%d)); NEXT'):format(asm32[op],d,s)) end
end end end
layout:write('#define ABC_STENCIL_UNARY_BASE (ABC_STENCIL_BINARY32_REV_BASE+6*64)\n#define ABC_STENCIL_UNARY(OP,D) (ABC_STENCIL_UNARY_BASE+(OP)*8+(D))\n')
local unary=semantics.unary_order
for i,name in ipairs(unary) do layout:write(('#define ABC_JUN_%s %d\n'):format(name,i-1)) end
for _,op in ipairs(unary) do
  local expr=assert(semantics.unary[op],op)
  for d=0,R-1 do
    stencil(('%s_%d'):format(op:lower(),d),('r%d=%s; NEXT'):format(d,semantics.expr(expr,'r'..d)))
  end
end
layout:write('#define ABC_STENCIL_IMMEDIATE_BASE (ABC_STENCIL_UNARY_BASE+5*8)\n#define ABC_STENCIL_IMMEDIATE(OP,D) (ABC_STENCIL_IMMEDIATE_BASE+(OP)*8+(D))\n')
local immediate=semantics.immediate_order
for i,name in ipairs(immediate) do layout:write(('#define ABC_JIMM_%s %d\n'):format(name,i-1)) end
local immediate_asm={ADD='addq',SUB='subq',MUL='imulq',AND='andq',OR='orq',XOR='xorq',SHL='shlq',SHR='shrq',SAR='sarq'}
for _,op in ipairs(immediate) do
  for d=0,R-1 do
    stencil(('%si_%d'):format(op:lower(),d),('__asm__("%s $HOLE_IMM,%%0":"+r"(r%d)); NEXT'):format(immediate_asm[op],d))
  end
end
layout:write('#define ABC_STENCIL_IMMEDIATE32_BASE (ABC_STENCIL_IMMEDIATE_BASE+9*8)\n#define ABC_STENCIL_IMMEDIATE32(OP,D) (ABC_STENCIL_IMMEDIATE32_BASE+(OP)*8+(D))\n')
local immediate32_asm={ADD='addl',SUB='subl',MUL='imull',AND='andl',OR='orl',XOR='xorl',SHL='shll',SHR='shrl',SAR='sarl'}
for _,op in ipairs(immediate) do for d=0,R-1 do
  stencil(('u32_%si_%d'):format(op:lower(),d),('__asm__("%s $HOLE_IMM,%%k0":"+r"(r%d)); NEXT'):format(immediate32_asm[op],d))
end end
layout:write('#define ABC_STENCIL_ACCESS_BASE (ABC_STENCIL_IMMEDIATE32_BASE+9*8)\n#define ABC_STENCIL_JZ(D) (ABC_STENCIL_ACCESS_BASE+(D)*8)\n#define ABC_STENCIL_JNZ(D) (ABC_STENCIL_ACCESS_BASE+(D)*8+1)\n#define ABC_STENCIL_LOAD(STACK,D) (ABC_STENCIL_ACCESS_BASE+(D)*8+2+(STACK)*2)\n#define ABC_STENCIL_STORE(STACK,D) (ABC_STENCIL_ACCESS_BASE+(D)*8+3+(STACK)*2)\n')
for d=0,R-1 do
  stencil(('jz_%d'):format(d),('__asm__("testq %%0,%%0; jz HOLE_TAKEN"::"r"(r%d):"cc"); __builtin_unreachable();'):format(d))
  stencil(('jnz_%d'):format(d),('__asm__("testq %%0,%%0; jnz HOLE_TAKEN"::"r"(r%d):"cc"); __builtin_unreachable();'):format(d))
  for _,stack in ipairs({'a','b','c'}) do
    stencil(('load_%s_%d'):format(stack,d),('__asm__("movq HOLE_IMM(%%1),%%0":"=r"(r%d):"r"(%ssp)); NEXT'):format(d,stack))
    stencil(('store_%s_%d'):format(stack,d),('__asm__("movq %%1,HOLE_IMM(%%0)"::"r"(%ssp),"r"(r%d):"memory"); NEXT'):format(stack,d))
  end
end
layout:write('#define ABC_STENCIL_BRANCH_BASE (ABC_STENCIL_ACCESS_BASE+8*8)\n#define ABC_STENCIL_BRANCH(OP,A,B) (ABC_STENCIL_BRANCH_BASE+(OP)*64+(A)*8+(B))\n')
local branches={} for _,name in ipairs(semantics.branch_order) do branches[#branches+1]=name:sub(2) end
for i,name in ipairs(branches) do layout:write(('#define ABC_JBR_%s %d\n'):format(name,i-1)) end
local branch_cc={EQ='je',NE='jne',LT='jl',LE='jle',LTU='jb',LEU='jbe'}
for _,op in ipairs(branches) do
  for a=0,R-1 do for b=0,R-1 do
    stencil(('b%s_%d_%d'):format(op:lower(),a,b),('__asm__("cmpq %%1,%%0; %s HOLE_TAKEN"::"r"(r%d),"r"(r%d):"cc"); __builtin_unreachable();'):format(branch_cc[op],a,b))
  end end
end

layout:write('#define ABC_STENCIL_FLOAT_BINARY_BASE (ABC_STENCIL_BRANCH_BASE+6*64)\n#define ABC_STENCIL_FLOAT_BINARY(OP,D,S) (ABC_STENCIL_FLOAT_BINARY_BASE+(OP)*64+(D)*8+(S))\n')
for i,name in ipairs(semantics.float_binary_order) do layout:write(('#define ABC_JFLOAT_%s %d\n'):format(name,i-1)) end
for _,op in ipairs(semantics.float_binary_order) do for d=0,R-1 do for s=0,R-1 do
  local expression=semantics.expr(semantics.float_binary[op],'r'..d,'r'..s)
  stencil(('float_%s_%d_%d'):format(op:lower(),d,s),('r%d=%s; NEXT'):format(d,expression))
end end end
layout:write('#define ABC_STENCIL_FLOAT_BINARY_REV_BASE (ABC_STENCIL_FLOAT_BINARY_BASE+7*64)\n#define ABC_STENCIL_FLOAT_BINARY_REV(OP,D,S) (ABC_STENCIL_FLOAT_BINARY_REV_BASE+(OP)*64+(D)*8+(S))\n')
for _,op in ipairs(semantics.float_binary_order) do for d=0,R-1 do for s=0,R-1 do
  local expression=semantics.expr(semantics.float_binary[op],'r'..s,'r'..d)
  stencil(('float_rev_%s_%d_%d'):format(op:lower(),d,s),('r%d=%s; NEXT'):format(d,expression))
end end end
layout:write('#define ABC_STENCIL_FLOAT_UNARY_BASE (ABC_STENCIL_FLOAT_BINARY_REV_BASE+7*64)\n#define ABC_STENCIL_FLOAT_UNARY(OP,D) (ABC_STENCIL_FLOAT_UNARY_BASE+(OP)*8+(D))\n')
for i,name in ipairs(semantics.float_unary_order) do layout:write(('#define ABC_JFUN_%s %d\n'):format(name,i-1)) end
for d=0,R-1 do stencil(('float_fneg_%d'):format(d),('r%d^=UINT64_C(0x8000000000000000); NEXT'):format(d)) end
for d=0,R-1 do stencil(('float_i2fs_%d'):format(d),('r%d=vm_i2fs(r%d); NEXT'):format(d,d)) end
for d=0,R-1 do stencil(('float_i2fu_%d'):format(d),('r%d=vm_i2fu(r%d); NEXT'):format(d,d)) end
for d=0,R-1 do stencil(('float_f2is_%d'):format(d),('{abc_value u=r%d,e=(u>>52)&2047,s=u>>63;if(e>1086||(e==1086&&(!s||(u&UINT64_C(0x000fffffffffffff)))))return jit_error();int sh=(int)e-1023;abc_value m=(u&UINT64_C(0x000fffffffffffff))|UINT64_C(0x0010000000000000),v=sh<0?0:sh<=52?m>>(52-sh):m<<(sh-52);r%d=s?0-v:v;} NEXT'):format(d,d)) end
for d=0,R-1 do stencil(('float_f2iu_%d'):format(d),('{abc_value u=r%d,e=(u>>52)&2047;if(((u>>63)&&(u<<1))||e>=1087)return jit_error();int sh=(int)e-1023;abc_value m=(u&UINT64_C(0x000fffffffffffff))|UINT64_C(0x0010000000000000);r%d=sh<0?0:sh<=52?m>>(52-sh):m<<(sh-52);} NEXT'):format(d,d)) end
layout:write('#define ABC_STENCIL_FLOAT_BRANCH_BASE (ABC_STENCIL_FLOAT_UNARY_BASE+5*8)\n#define ABC_STENCIL_FLOAT_BRANCH(OP,A,B) (ABC_STENCIL_FLOAT_BRANCH_BASE+(OP)*64+(A)*8+(B))\n')
local float_cc={FBLT='jb',FBLE='jbe',FBEQ='je'}
for _,op in ipairs(semantics.float_branch_order) do for a=0,R-1 do for b=0,R-1 do
  stencil(('float_b%s_%d_%d'):format(op:sub(3):lower(),a,b),('__asm__("movq %%0,%%%%xmm0; movq %%1,%%%%xmm1; ucomisd %%%%xmm1,%%%%xmm0; jp 1f; %s HOLE_TAKEN; 1:"::"r"(r%d),"r"(r%d):"xmm0","xmm1","cc"); __builtin_unreachable();'):format(float_cc[op],a,b))
end end end
layout:write('#define ABC_STENCIL_MEM_LOAD_BASE (ABC_STENCIL_FLOAT_BRANCH_BASE+3*64)\n#define ABC_STENCIL_MEM_LOAD(K,D) (ABC_STENCIL_MEM_LOAD_BASE+(K)*8+(D))\n')
local loads={{'u8','uint8_t'},{'u16','uint16_t'},{'u32','uint32_t'},{'s32','int32_t'},{'u64','uint64_t'}}
local load_ins={u8='movzbq',u16='movzwq',u32='movl',s32='movslq',u64='movq'}
local load_dst={u8='%0',u16='%0',u32='%k0',s32='%0',u64='%0'}
for _,kind in ipairs(loads) do for d=0,R-1 do local k=kind[1]; stencil(('mem_load_%s_%d'):format(k,d),'__asm__("'..load_ins[k]..' HOLE_IMM(%0),'..load_dst[k]..'":"+r"(r'..d..')::"memory"); NEXT') end end
layout:write('#define ABC_STENCIL_MEM_STORE_BASE (ABC_STENCIL_MEM_LOAD_BASE+5*8)\n#define ABC_STENCIL_MEM_STORE(K,A,V) (ABC_STENCIL_MEM_STORE_BASE+(K)*64+(A)*8+(V))\n')
local stores={{'u8','uint8_t'},{'u16','uint16_t'},{'u32','uint32_t'},{'u64','uint64_t'}}
local store_ins={u8='movb',u16='movw',u32='movl',u64='movq'}
local store_src={u8='%b1',u16='%w1',u32='%k1',u64='%1'}
for _,kind in ipairs(stores) do for a=0,R-1 do for v=0,R-1 do local k=kind[1]; stencil(('mem_store_%s_%d_%d'):format(k,a,v),'__asm__("'..store_ins[k]..' '..store_src[k]..',HOLE_IMM(%0)"::"r"(r'..a..'),"r"(r'..v..'):"memory"); NEXT') end end end
layout:write('#define ABC_STENCIL_INDEX_BASE (ABC_STENCIL_MEM_STORE_BASE+4*64)\n#define ABC_STENCIL_INDEX(A,I) (ABC_STENCIL_INDEX_BASE+(A)*8+(I))\n')
for a=0,R-1 do for i=0,R-1 do stencil(('index_%d_%d'):format(a,i),('r%d+=(abc_value)((int32_t)(intptr_t)HOLE_IMM)*r%d; NEXT'):format(a,i)) end end
layout:write('#define ABC_STENCIL_MEMCPY_BASE (ABC_STENCIL_INDEX_BASE+64)\n#define ABC_STENCIL_MEMCPY(A,B) (ABC_STENCIL_MEMCPY_BASE+(A)*8+(B))\n')
for a=0,R-1 do for b=0,R-1 do stencil(('memcpy_%d_%d'):format(a,b),('{uint8_t*d=(uint8_t *)(uintptr_t)r%d,*s=(uint8_t *)(uintptr_t)r%d;size_t n=(uint32_t)(uintptr_t)HOLE_IMM;while(n--)*d++=*s++;} NEXT'):format(a,b)) end end
layout:write('#define ABC_STENCIL_MANAGED_WRITE_BASE (ABC_STENCIL_MEMCPY_BASE+64)\n#define ABC_STENCIL_MANAGED_WRITE(A) (ABC_STENCIL_MANAGED_WRITE_BASE+(A))\n')
for a=0,R-1 do stencil(('managed_write_%d'):format(a),('abc_value fn;__asm__("movabsq $HOLE_FINAL,%%0":"=r"(fn));((abc_managed_write_fn)(uintptr_t)fn)(r%d+(int32_t)(intptr_t)HOLE_IMM,(unsigned)(uintptr_t)HOLE_IMM2); NEXT'):format(a)) end
layout:write('#define ABC_STENCIL_DYNAMIC_ENCODE_BASE (ABC_STENCIL_MANAGED_WRITE_BASE+8)\n#define ABC_STENCIL_DYNAMIC_ENCODE(A) (ABC_STENCIL_DYNAMIC_ENCODE_BASE+(A))\n')
for a=0,R-1 do stencil(('dynamic_encode_%d'):format(a),('r%d=UINT64_C(0xffff000000000000)|((abc_value)(uintptr_t)HOLE_IMM<<40)|(r%d&UINT64_C(0x000000ffffffffff)); NEXT'):format(a,a)) end
layout:write('#define ABC_STENCIL_CALLOC (ABC_STENCIL_DYNAMIC_ENCODE_BASE+8)\n')
stencil('calloc','{uint64_t*d=csp+(int32_t)(intptr_t)HOLE_IMM2;size_t n=(uint32_t)(uintptr_t)HOLE_IMM;while(n--)*d++=0;} NEXT')
layout:write('#define ABC_STENCIL_FRAME_LOAD_BASE (ABC_STENCIL_CALLOC+1)\n#define ABC_STENCIL_FRAME_LOAD(K,D) (ABC_STENCIL_FRAME_LOAD_BASE+(K)*8+(D))\n')
for _,kind in ipairs(loads) do for d=0,R-1 do local k=kind[1]; stencil(('frame_load_%s_%d'):format(k,d),'__asm__("'..load_ins[k]..' HOLE_IMM(%1),'..load_dst[k]..'":"=r"(r'..d..'):"r"(csp):"memory"); NEXT') end end
layout:write('#define ABC_STENCIL_FRAME_STORE_BASE (ABC_STENCIL_FRAME_LOAD_BASE+5*8)\n#define ABC_STENCIL_FRAME_STORE(K,V) (ABC_STENCIL_FRAME_STORE_BASE+(K)*8+(V))\n')
for _,kind in ipairs(stores) do for v=0,R-1 do local k=kind[1]; stencil(('frame_store_%s_%d'):format(k,v),'__asm__("'..store_ins[k]..' '..store_src[k]..',HOLE_IMM(%0)"::"r"(csp),"r"(r'..v..'):"memory"); NEXT') end end
layout:write('#define ABC_STENCIL_FRAME_ADDR_BASE (ABC_STENCIL_FRAME_STORE_BASE+4*8)\n#define ABC_STENCIL_FRAME_ADDR(D) (ABC_STENCIL_FRAME_ADDR_BASE+(D))\n')
for d=0,R-1 do stencil(('frame_addr_%d'):format(d),'__asm__("leaq HOLE_IMM(%1),%0":"=r"(r'..d..'):"r"(csp)); NEXT') end
layout:write('#define ABC_STENCIL_GLOBAL_LOAD_BASE (ABC_STENCIL_FRAME_ADDR_BASE+8)\n#define ABC_STENCIL_GLOBAL_LOAD(K,D) (ABC_STENCIL_GLOBAL_LOAD_BASE+(K)*8+(D))\n')
for _,kind in ipairs(loads) do for d=0,R-1 do stencil(('global_load_%s_%d'):format(kind[1],d),('r%d=(abc_value)*(%s *)(uintptr_t)HOLE_FINAL; NEXT'):format(d,kind[2])) end end
layout:write('#define ABC_STENCIL_GLOBAL_STORE_BASE (ABC_STENCIL_GLOBAL_LOAD_BASE+5*8)\n#define ABC_STENCIL_GLOBAL_STORE(K,V) (ABC_STENCIL_GLOBAL_STORE_BASE+(K)*8+(V))\n')
for _,kind in ipairs(stores) do for v=0,R-1 do stencil(('global_store_%s_%d'):format(kind[1],v),('*('..kind[2]..' *)(uintptr_t)HOLE_FINAL=('..kind[2]..')r'..v..'; NEXT')) end end
layout:write('#define ABC_STENCIL_GLOBAL_ADDR_BASE (ABC_STENCIL_GLOBAL_STORE_BASE+4*8)\n#define ABC_STENCIL_GLOBAL_ADDR(D) (ABC_STENCIL_GLOBAL_ADDR_BASE+(D))\n')
for d=0,R-1 do stencil(('global_addr_%d'):format(d),('r%d=(abc_value)(uintptr_t)HOLE_FINAL; NEXT'):format(d)) end
layout:write('#define ABC_STENCIL_POW_BASE (ABC_STENCIL_GLOBAL_ADDR_BASE+8)\n#define ABC_STENCIL_POW(A,B) (ABC_STENCIL_POW_BASE+(A)*8+(B))\n#define ABC_STENCIL_POWS(A,B) (ABC_STENCIL_POW_BASE+64+(A)*8+(B))\n')
for a=0,R-1 do for b=0,R-1 do stencil(('pow_%d_%d'):format(a,b),('r%d=jit_pow(r%d,r%d); NEXT'):format(a,a,b)) end end
for a=0,R-1 do for b=0,R-1 do stencil(('pows_%d_%d'):format(a,b),('if(abc_signed(r%d)<0)return jit_error(); r%d=jit_pow(r%d,r%d); NEXT'):format(b,a,a,b)) end end
layout:write('#define ABC_STENCIL_CHECK_BASE (ABC_STENCIL_POW_BASE+128)\n#define ABC_STENCIL_CHECK(K,R) (ABC_STENCIL_CHECK_BASE+(K)*8+(R))\n')
local check_suffix={CHKU8='u8',CHKU16='u16',CHKU32='u32',CHKI32='i32',CHKNN='nn'}
for _,op in ipairs(semantics.check_order) do for r=0,R-1 do
  local condition=semantics.expr(assert(semantics.checks[op]),'r'..r)
  stencil(('check_%s_%d'):format(check_suffix[op],r),('if(%s)return jit_error(); NEXT'):format(condition))
end end
layout:write('#define ABC_STENCIL_FCALL0 (ABC_STENCIL_CHECK_BASE+5*8)\n#define ABC_STENCIL_FCALL1 (ABC_STENCIL_FCALL0+1)\n#define ABC_STENCIL_ABORT (ABC_STENCIL_FCALL1+1)\n#define ABC_STENCIL_GUARD_BASE (ABC_STENCIL_ABORT+1)\n#define ABC_STENCIL_GUARD(S) (ABC_STENCIL_GUARD_BASE+(S))\n#define ABC_STENCIL_CALLI_BASE (ABC_STENCIL_GUARD_BASE+3)\n#define ABC_STENCIL_CALLI(R) (ABC_STENCIL_CALLI_BASE+(R))\n#define ABC_STENCIL_TCALLI(R) (ABC_STENCIL_CALLI_BASE+8+(R))\n#define ABC_STENCIL_RAW_CALLI_BASE (ABC_STENCIL_CALLI_BASE+16)\n#define ABC_STENCIL_RAW_CALLI(R) (ABC_STENCIL_RAW_CALLI_BASE+(R))\n#define ABC_STENCIL_RAW_TCALLI(R) (ABC_STENCIL_RAW_CALLI_BASE+8+(R))\n#define ABC_STENCIL_CALL (ABC_STENCIL_RAW_CALLI_BASE+16)\n#define ABC_STENCIL_CALL_JUMP (ABC_STENCIL_CALL+1)\n#define ABC_STENCIL_CALL_RESUME (ABC_STENCIL_CALL+2)\n#define ABC_STENCIL_RETURN_CONT (ABC_STENCIL_CALL+3)\n#define ABC_STENCIL_RETURN_SENTINEL (ABC_STENCIL_CALL+4)\n#define ABC_STENCIL_TCALL (ABC_STENCIL_CALL+5)\n#define ABC_STENCIL_JUMP (ABC_STENCIL_CALL+6)\n#define ABC_STENCIL_FINISH (ABC_STENCIL_CALL+7)\n')
stencil('fcall0','abc_value bridge,ext,target,out=0;__asm__("movabsq $HOLE_FINAL,%0":"=r"(bridge));__asm__("movabsq $HOLE_STATE,%0":"=r"(ext));__asm__("movabsq $HOLE_BIAS,%0":"=r"(target));if(((abc_foreign_bridge)(uintptr_t)bridge)((const void *)(uintptr_t)ext,(void(*)(void))(uintptr_t)target,asp+(int32_t)(intptr_t)HOLE_IMM,&out))return jit_error();NEXT')
stencil('fcall1','abc_value bridge,ext,target,out=0;__asm__("movabsq $HOLE_FINAL,%0":"=r"(bridge));__asm__("movabsq $HOLE_STATE,%0":"=r"(ext));__asm__("movabsq $HOLE_BIAS,%0":"=r"(target));if(((abc_foreign_bridge)(uintptr_t)bridge)((const void *)(uintptr_t)ext,(void(*)(void))(uintptr_t)target,asp+(int32_t)(intptr_t)HOLE_IMM,&out))return jit_error();asp[(int32_t)(intptr_t)HOLE_IMM]=out;NEXT')
stencil('abort','return jit_error();')
for _,stack in ipairs({'a','b','c'}) do stencil('guard_'..stack,('if(%ssp+(int32_t)(intptr_t)HOLE_IMM>(abc_value *)(uintptr_t)jit_final())return jit_error(); NEXT'):format(stack)) end
for r=0,R-1 do stencil(('calli_%d'):format(r),('abc_value fn,state; __asm__("movabsq $HOLE_FINAL,%%0":"=r"(fn)); __asm__("movabsq $HOLE_STATE,%%0":"=r"(state)); abc_value status=((abc_jit_fn)(uintptr_t)fn)(asp+(int32_t)(intptr_t)HOLE_IMM,bsp+(int32_t)(intptr_t)HOLE_BIAS,csp+(int32_t)(intptr_t)HOLE_IMM2,r%d,state,0,0,0,0,0,0); if(status)return status; NEXT'):format(r)) end
for r=0,R-1 do stencil(('tcalli_%d'):format(r),('abc_value fn,state; __asm__("movabsq $HOLE_FINAL,%%0":"=r"(fn)); __asm__("movabsq $HOLE_STATE,%%0":"=r"(state)); TAIL return ((abc_jit_fn)(uintptr_t)fn)(asp+(int32_t)(intptr_t)HOLE_IMM,bsp+(int32_t)(intptr_t)HOLE_BIAS,csp+(int32_t)(intptr_t)HOLE_IMM2,r%d,state,0,0,0,0,0,0);'):format(r)) end
for r=0,R-1 do stencil(('raw_calli_%d'):format(r),('abc_value resolver,state,fn;__asm__("movabsq $HOLE_FINAL,%%0":"=r"(resolver));__asm__("movabsq $HOLE_STATE,%%0":"=r"(state));fn=((abc_resolve_fn)(uintptr_t)resolver)(r%d,state);if(!fn)return jit_error();abc_value status=((abc_jit_fn)(uintptr_t)fn)(asp+(int32_t)(intptr_t)HOLE_IMM,bsp+(int32_t)(intptr_t)HOLE_BIAS,csp+(int32_t)(intptr_t)HOLE_IMM2,0,0,0,0,0,0,0,0);if(status)return status;NEXT'):format(r)) end
for r=0,R-1 do stencil(('raw_tcalli_%d'):format(r),('abc_value resolver,state,fn;__asm__("movabsq $HOLE_FINAL,%%0":"=r"(resolver));__asm__("movabsq $HOLE_STATE,%%0":"=r"(state));fn=((abc_resolve_fn)(uintptr_t)resolver)(r%d,state);if(!fn)return jit_error();TAIL return ((abc_jit_fn)(uintptr_t)fn)(asp+(int32_t)(intptr_t)HOLE_IMM,bsp+(int32_t)(intptr_t)HOLE_BIAS,csp+(int32_t)(intptr_t)HOLE_IMM2,0,0,0,0,0,0,0,0);'):format(r)) end
stencil('call','abc_value status=((abc_jit_fn)HOLE_TAKEN)(asp+(int32_t)(intptr_t)HOLE_IMM,bsp+(int32_t)(intptr_t)HOLE_BIAS,csp+(int32_t)(intptr_t)HOLE_IMM2,0,0,0,0,0,0,0,0); if(status)return status; NEXT')
stencil('call_jump','abc_value cont; __asm__("movabsq $HOLE_NEXT,%0":"=r"(cont)); *(abc_value *)((unsigned char *)csp+(intptr_t)HOLE_ERROR)=cont; TAIL return ((abc_jit_fn)HOLE_TAKEN)(asp+(int32_t)(intptr_t)HOLE_IMM,bsp+(int32_t)(intptr_t)HOLE_BIAS,csp+(int32_t)(intptr_t)HOLE_IMM2,r0,r1,r2,r3,r4,r5,r6,r7);')
stencil('call_resume','asp-=(int32_t)(intptr_t)HOLE_IMM; bsp-=(int32_t)(intptr_t)HOLE_BIAS; csp-=(int32_t)(intptr_t)HOLE_IMM2; NEXT')
stencil('return_cont','abc_value cont=*(abc_value *)((unsigned char *)csp+(intptr_t)HOLE_IMM); if(cont==UINT32_MAX)return 0; TAIL return ((abc_jit_fn)(uintptr_t)cont)(ABC_JIT_PASS);')
stencil('return_sentinel','*(abc_value *)((unsigned char *)csp+(intptr_t)HOLE_IMM)=UINT32_MAX; NEXT')
stencil('tcall','TAIL return ((abc_jit_fn)HOLE_TAKEN)(asp+(int32_t)(intptr_t)HOLE_IMM,bsp+(int32_t)(intptr_t)HOLE_BIAS,csp+(int32_t)(intptr_t)HOLE_IMM2,0,0,0,0,0,0,0,0);')
stencil('jump','TAIL return HOLE_TAKEN(ABC_JIT_PASS);')
stencil('finish','*(abc_value *)(uintptr_t)HOLE_FINAL=r0; return 0;')
stencil('return_ok','return 0;')
stencil('dynamic','abc_value fn,state,status,*ap=asp+(int32_t)(intptr_t)HOLE_BIAS,*bp=bsp+(int32_t)(intptr_t)HOLE_IMM2,*cp=csp+(int32_t)(intptr_t)HOLE_ERROR;__asm__("movabsq $HOLE_FINAL,%0":"=r"(fn));__asm__("movabsq $HOLE_STATE,%0":"=r"(state));status=((abc_dynamic_fn)(uintptr_t)fn)(&ap,&bp,&cp,(const unsigned char *)(uintptr_t)state,(unsigned)(uintptr_t)HOLE_IMM);if(status)return status;NEXT')
stencil('dynamic_tail','abc_value fn,state,status,cont,*ap=asp+(int32_t)(intptr_t)HOLE_BIAS,*bp=bsp+(int32_t)(intptr_t)HOLE_IMM2,*cp=csp+(int32_t)(intptr_t)HOLE_ERROR;__asm__("movabsq $HOLE_FINAL,%0":"=r"(fn));__asm__("movabsq $HOLE_STATE,%0":"=r"(state));status=((abc_dynamic_fn)(uintptr_t)fn)(&ap,&bp,&cp,(const unsigned char *)(uintptr_t)state,(unsigned)(uintptr_t)HOLE_IMM);if(status)return status;cont=*(abc_value *)((unsigned char *)csp+(intptr_t)HOLE_TAKEN);if(cont==UINT32_MAX)return 0;TAIL return ((abc_jit_fn)(uintptr_t)cont)(ap,bp,csp,0,0,0,0,0,0,0,0);')
layout:write('#define ABC_STENCIL_RETURN_OK (ABC_STENCIL_FINISH+1)\n#define ABC_STENCIL_DYNAMIC (ABC_STENCIL_RETURN_OK+1)\n#define ABC_STENCIL_DYNAMIC_TAIL (ABC_STENCIL_DYNAMIC+1)\n#define ABC_STENCIL_LAZY_ENTRY (ABC_STENCIL_DYNAMIC_TAIL+1)\n#endif\n')
stencil('lazy_entry','abc_value state;__asm__("movabsq $HOLE_STATE,%0":"=r"(state));abc_value*s=(abc_value*)(uintptr_t)state;s[0]=(abc_value)(uintptr_t)asp;s[1]=(abc_value)(uintptr_t)bsp;s[2]=(abc_value)(uintptr_t)csp;s[3]=r0;s[4]=r1;s[5]=r2;s[6]=r3;s[7]=r4;s[8]=r5;s[9]=r6;s[10]=r7;abc_value body=((abc_lazy_prepare_fn)HOLE_FINAL)(state);if(s[11])return s[11];TAIL return ((abc_jit_fn)(uintptr_t)body)((abc_value*)(uintptr_t)s[0],(abc_value*)(uintptr_t)s[1],(abc_value*)(uintptr_t)s[2],s[3],s[4],s[5],s[6],s[7],s[8],s[9],s[10]);')
layout:write(('#define ABC_STENCIL_NUMERIC_CLASSIFY(R) (%d+(R))\n'):format(n))
emit('typedef abc_value (*abc_numeric_classify_fn)(abc_value,abc_value,abc_value,abc_value);')
for r=0,R-1 do stencil(('numeric_classify_%d'):format(r),('abc_value fn,state;__asm__("movabsq $HOLE_FINAL,%%0":"=r"(fn));__asm__("movabsq $HOLE_STATE,%%0":"=r"(state));r%d=((abc_numeric_classify_fn)(uintptr_t)fn)(state,asp[(int32_t)(intptr_t)HOLE_IMM],asp[(int32_t)(intptr_t)HOLE_IMM+1],(unsigned)(uintptr_t)HOLE_IMM2);NEXT'):format(r)) end
layout:write(('#define ABC_STENCIL_NUMERIC_DECODE(R) (%d+(R))\n'):format(n))
for r=0,R-1 do stencil(('numeric_decode_%d'):format(r),('abc_value fn,state;__asm__("movabsq $HOLE_FINAL,%%0":"=r"(fn));__asm__("movabsq $HOLE_STATE,%%0":"=r"(state));r%d=((abc_resolve_fn)(uintptr_t)fn)(r%d,state);NEXT'):format(r,r)) end
names:write(('#define ABC_STENCIL_COUNT %d\n'):format(n))
assert(c:close()); assert(order:close()); assert(names:close()); assert(layout:close())
assert(os.rename(dir..'/stencils.c.tmp',dir..'/stencils.c'))
assert(os.rename(dir..'/stencils.order.tmp',dir..'/stencils.order'))
assert(os.rename(dir..'/stencil_names.h.tmp',dir..'/stencil_names.h'))
assert(os.rename(dir..'/stencil_layout.h.tmp',dir..'/stencil_layout.h'))
io.stderr:write(('generated %d register-addressed stencils\n'):format(n))

