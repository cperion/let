-- Final register-threaded handlers. There is no ABC opcode/register decoding.
local root=(arg[0]:match('^(.*)/[^/]+$') or '.')
package.path=root..'/?.lua;'..package.path
local forms,semantics,compute=require('execution_forms'),require('semantics'),require('execution_compute')
local path=assert(arg[1],'output C file required')
local out=assert(io.open(path..'.tmp','wb'))
local function emit(s) assert(out:write(s,'\n')) end
emit('#include "threaded.h"')
emit('#include <math.h>')
compute.helpers(emit,true)
emit('typedef void *(*copy_fn)(void *,const void *,size_t);')
emit('typedef uint64_t (*resolve_fn)(uint64_t,uint64_t,uintptr_t,uintptr_t,uintptr_t,uint64_t *);')
emit('typedef int (*service_fn)(uintptr_t,uint64_t *,uint64_t *,uint64_t *,const uint64_t *,uint32_t);')
emit('typedef uint64_t *(*bounds_fn)(unsigned);')
emit('#define NEXT(N) do { ip+=(N); __attribute__((musttail)) return ip[0].handler(ABC_THREAD_PASS); } while(0)')
emit('#define TRANSFER(P) do { ip=(P); __attribute__((musttail)) return ip[0].handler(ABC_THREAD_PASS); } while(0)')
local types={}
for _,k in ipairs(forms.loads) do types[k[1]]=k[2] end
local function body(f)
 local k,op=f.kind,f.operation
 local d=f.registers[1] and ('r'..f.registers[1])
 local s=f.registers[2] and ('r'..f.registers[2])
 local imm='ip[1].bits'
 local next=' NEXT('..f.words..');'
 local code
 if k=='const' then code=d..'='..imm..';'
 elseif k=='move' then code=d..'='..s..';'
 elseif k=='binary' or k=='binary32' or k=='immediate' or k=='immediate32' then
  local narrow=k=='binary32' or k=='immediate32'
  local immediate=k=='immediate' or k=='immediate32'
  local lhs=narrow and ('(abc_value)(uint32_t)'..d) or d
  if narrow and op=='SAR' then lhs='(abc_value)(int64_t)abc_i32_from_u64('..d..')' end
  local rhs=immediate and imm or s
  local expr=semantics.expr(assert(semantics.binary[op]),lhs,rhs)
  local guard=k=='binary' and semantics.transfers[op].check_zero and ('if(!'..s..')return ip[1].bits; ') or ''
  code=guard..d..'='..(narrow and '(uint32_t)('..expr..')' or expr)..';'
 elseif k=='unary' then code=d..'='..semantics.expr(assert(semantics.unary[op]),d)..';'
 elseif k=='float_binary' then code=d..'='..semantics.expr(assert(semantics.float_binary[op]),d,s)..';'
 elseif k=='float_unary' then code=compute.float_unary(op,d,'ip[1].bits')
 elseif k=='branch' or k=='float_branch' or k=='zero_branch' then
  local condition
  if k=='zero_branch' then condition=d..(op=='EQ' and '==0' or '!=0')
  elseif k=='branch' then condition=semantics.expr(assert(semantics.binary[op]),d,s)
  else condition=semantics.expr(assert(semantics.float_binary[({FBLT='FLT',FBLE='FLE',FBEQ='FEQ'})[op]]),d,s) end
  return 'if('..condition..'){TRANSFER(ip[1].target);} NEXT(2);'
 elseif k=='home_load' then code='memcpy(&'..d..',(const uint8_t *)'..f.stack..'sp+abc_signed(ip[1].bits),8);'
 elseif k=='home_store' then code='memcpy((uint8_t *)'..f.stack..'sp+abc_signed(ip[1].bits),&'..d..',8);'
 elseif k=='memory_load' or k=='frame_load' or k=='global_load' then
  local address=k=='memory_load' and ('(uintptr_t)'..d..'+ip[1].bits') or k=='frame_load' and '(uintptr_t)csp+ip[1].bits' or 'ip[1].bits'
  code='{'..assert(types[op])..' value;memcpy(&value,(const void *)(uintptr_t)('..address..'),sizeof value);'..d..'=(abc_value)value;}'
 elseif k=='memory_store' or k=='frame_store' or k=='global_store' then
  local address=k=='memory_store' and ('(uintptr_t)'..d..'+ip[1].bits') or k=='frame_store' and '(uintptr_t)csp+ip[1].bits' or 'ip[1].bits'
  local value=k=='memory_store' and s or d
  code='{'..assert(types[op])..' value=('..types[op]..')'..value..';memcpy((void *)(uintptr_t)('..address..'),&value,sizeof value);}'
 elseif k=='frame_address' then code=d..'=(uintptr_t)csp+ip[1].bits;'
 elseif k=='global_address' then code=d..'=ip[1].bits;'
 elseif k=='index' then code=d..'+=ip[1].bits*'..s..';'
 elseif k=='memory_copy' then code='if(ip[1].bits)((copy_fn)(uintptr_t)ip[2].bits)((void *)(uintptr_t)'..d..',(const void *)(uintptr_t)'..s..',(size_t)ip[1].bits);'
 elseif k=='frame_zero' then code='{uint64_t *p=(uint64_t *)((uint8_t *)csp+abc_signed(ip[2].bits));size_t n=(size_t)ip[1].bits;while(n--)*p++=0;}'
 elseif k=='pow' then
  code=compute.power(op,d,s,'ip[1].bits')
 elseif k=='check' then code='if('..semantics.expr(assert(semantics.checks[op]),d)..')return ip[1].bits;'
 elseif k=='foreign' then
  code='{abc_value result=0;abc_value *arguments=(abc_value *)((uint8_t *)'..f.stack..'sp+abc_signed(ip[1].bits));abc_status status=((abc_foreign_bridge_fn)(uintptr_t)ip[2].bits)((const abc_extern *)(uintptr_t)ip[3].bits,(abc_foreign_address)(uintptr_t)ip[4].bits,arguments,&result);if(status)return (ip[5].bits&~UINT64_C(255))|(uint64_t)status;'
  if op==1 then code=code..'*arguments=result;' end
  code=code..'}'
 elseif k=='service' then code='{uint64_t saved[8]={r0,r1,r2,r3,r4,r5,r6,0};if(((service_fn)(uintptr_t)ip[1].bits)((uintptr_t)(ip+3),asp,bsp,csp,saved,(uint32_t)ip[2].bits))return 0;}'
 elseif k=='abort' then return 'return ip[1].bits;'
 elseif k=='guard' then code='if((uintptr_t)'..f.stack..'sp+ip[1].bits>(uintptr_t)((bounds_fn)(uintptr_t)ip[2].bits)('..({a=0,b=1,c=2})[f.stack]..'))return ip[3].bits;'
 elseif k=='resolve_indirect' then
  code='{uint64_t entry,status=((resolve_fn)(uintptr_t)ip[1].bits)(r0,ip[2].bits,(uintptr_t)asp+ip[3].bits,(uintptr_t)bsp+ip[4].bits,(uintptr_t)csp+ip[5].bits,&entry);if(status)return status;r0=entry;}'
 elseif k=='store_continuation' then code='{uint64_t target=(uintptr_t)ip[2].target;memcpy((uint8_t *)csp+abc_signed(ip[1].bits),&target,8);}'
 elseif k=='rebase' then code=f.stack..'sp=(uint64_t *)((uint8_t *)'..f.stack..'sp+abc_signed(ip[1].bits));'
 elseif k=='continue' then return 'TRANSFER((const abc_thread_word *)(uintptr_t)'..d..');'
 elseif k=='jump' then return 'TRANSFER(ip[1].target);'
 elseif k=='finish' then return '*(uint64_t *)(uintptr_t)ip[1].bits=r0;return 0;'
 elseif k=='return_ok' then return 'return 0;'
 else error('unbound threaded form '..f.name..' ('..k..')') end
 return code..next
end
local count=0
for _,f in ipairs(forms.forms) do if forms.available(f,'threaded') then
 emit('static ABC_THREAD_CC uint64_t thread_'..f.name..'(ABC_THREAD_ARGS) { '..body(f)..' }')
 count=count+1
end end
emit('const abc_thread_form abc_thread_forms[ABC_FORM_COUNT]={')
for _,f in ipairs(forms.forms) do
 local target=0
 for i,operand in ipairs(f.operands) do if operand:match(':tape$') then assert(target==0);target=i end end
 emit(forms.available(f,'threaded') and (' {thread_%s,%d,%d},'):format(f.name,f.words,target) or ' {NULL,0,0},')
end
emit('};')
assert(out:close());assert(os.rename(path..'.tmp',path))
io.stderr:write(('generated %d seven-register threaded handlers\n'):format(count))
