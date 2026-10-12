-- Computation shared by register-addressed execution bindings. Backend code
-- supplies operands, dispatch and the error exit, not alternative algorithms.
local M={}
function M.helpers(emit,has_signed)
 if not has_signed then emit('static __attribute__((always_inline)) inline int64_t abc_signed(abc_value x){ return x<=INT64_MAX?(int64_t)x:-1-(int64_t)(UINT64_MAX-x); }') end
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
end
function M.float_unary(op,r,error_exit)
 if op=='FNEG' then return r..'^=UINT64_C(0x8000000000000000);' end
 if op=='I2FS' then return r..'=vm_i2fs('..r..');' end
 if op=='I2FU' then return r..'=vm_i2fu('..r..');' end
 if op=='F2IS' then
  return ('{abc_value u=%s,e=(u>>52)&2047,s=u>>63;if(e>1086||(e==1086&&(!s||(u&UINT64_C(0x000fffffffffffff)))))return %s;int sh=(int)e-1023;abc_value m=(u&UINT64_C(0x000fffffffffffff))|UINT64_C(0x0010000000000000),v=sh<0?0:sh<=52?m>>(52-sh):m<<(sh-52);%s=s?0-v:v;}'):format(r,error_exit,r)
 end
 if op=='F2IU' then
  return ('{abc_value u=%s,e=(u>>52)&2047;if(((u>>63)&&(u<<1))||e>=1087)return %s;int sh=(int)e-1023;abc_value m=(u&UINT64_C(0x000fffffffffffff))|UINT64_C(0x0010000000000000);%s=sh<0?0:sh<=52?m>>(52-sh):m<<(sh-52);}'):format(r,error_exit,r)
 end
 error('unknown float unary computation '..tostring(op))
end
function M.power(op,d,s,error_exit)
 local signed=assert(require('semantics').transfers[op]).signed_exponent
 return (signed and ('if(abc_signed('..s..')<0)return '..error_exit..'; ') or '')..d..'=jit_pow('..d..','..s..');'
end
return M
