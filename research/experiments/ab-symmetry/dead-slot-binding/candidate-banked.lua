-- Cache-state handlers for revision 6. Semantics use me/other; cache.lua owns placement.
local root=arg[0]:match('^(.*)/[^/]+$') or '.'
package.path=root..'/?.lua;'..root..'/../tools/?.lua;'..package.path
local cache=require('cache')
local semantics=require('semantics')
local manifest=require('opcodes')
local output=assert(arg[1],'output directory required')
local files={}
for index=0,7 do files[index]=assert(io.open(('%s/banked_%d.c.tmp'):format(output,index),'wb')) end
local out
local function emit(text) assert(out:write(text,'\n')) end
local keys={A='a',B='b',C='c'}
local function opposite(stack) return stack=='A' and 'B' or 'A' end
local Builder={};Builder.__index=Builder
local function builder(state)
 return setmetatable({state=cache.state(state.a,state.b,state.c),lines={},temporary_count=0},Builder)
end
function Builder:line(text) self.lines[#self.lines+1]=text end
function Builder:temp(expression)
 self.temporary_count=self.temporary_count+1
 local name='captured_'..self.temporary_count
 self:line('uint64_t '..name..' = '..expression..';')
 return name
end
function Builder:peek(stack,depth)
 depth=depth or 0
 local register=cache.register(self.state,stack,depth)
 if register then return register end
 return ('%ssp[%d]'):format(keys[stack],self.state[keys[stack]]-depth-1)
end
function Builder:cvalue(depth)
 local expression=('csp[-1-((int)(%s)-%d)]'):format(depth,self.state.c)
 for index=self.state.c-1,0,-1 do expression=('((%s)==%d?c%d:%s)'):format(depth,self.state.c-1-index,index,expression) end
 return expression
end
function Builder:cset(depth,value)
 for index=self.state.c-1,0,-1 do self:line(('if((%s)==%d)c%d=%s;else '):format(depth,self.state.c-1-index,index,value)) end
 self:line(('csp[-1-((int)(%s)-%d)]=%s;'):format(depth,self.state.c,value))
end
function Builder:pop(stack,discard)
 local captured=not discard and self:temp(self:peek(stack)) or nil
 if self.state[keys[stack]]==0 then self:line('--'..keys[stack]..'sp;') end
 self.state=cache.pop(self.state,stack)
 return captured
end
function Builder:push(stack,value)
 local captured=self:temp(value)
 local next_state,spill=cache.push(self.state,stack)
 if spill then
  for _,step in ipairs(cache.spill_steps(self.state,spill)) do
   if step.kind=='store' then self:line(('*%ssp++=%s;'):format(keys[spill],step.source))
   else self:line(step.destination..'='..step.source..';') end
  end
 end
 self.state=next_state
 self:line(self:peek(stack)..'='..captured..';')
end
local function flush_stack(state,stack)
 for depth=state[keys[stack]]-1,0,-1 do
  emit(('*%ssp++=%s;'):format(keys[stack],cache.register(state,stack,depth)))
 end
end
-- Cache occupancy is the liveness authority. Dead ABI slots carry no value;
-- forwarding their old bits would make the host compiler preserve them anyway.
local function handler_arguments(state)
 local live={}
 for _,stack in ipairs{'A','B','C'} do
  for depth=0,state[keys[stack]]-1 do live[cache.register(state,stack,depth)]=true end
 end
 local arguments={'ip','asp','bsp','csp'}
 for index=0,cache.operand_registers-1 do
  local name='h'..index;arguments[#arguments+1]=live[name] and name or '0'
 end
 for index=0,cache.interpreter_c_registers-1 do
  local name='c'..index;arguments[#arguments+1]=live[name] and name or '0'
 end
 return table.concat(arguments,',')
end
local function dispatch(state)
 emit(('ip=next;ABC_HANDLER_TAIL return T_a%db%dc%d[*ip](%s);'):format(state.a,state.b,state.c,handler_arguments(state)))
end
local function dynamic_dispatch(a,b,c)
 emit(('ABC_HANDLER_TAIL return abc_tables[((%s)*5+(%s))*4+(%s)][*ip](ABC_HANDLER_PASS);'):format(a,b,c))
end
local function publish(a,b,c,pc)
 emit(('v->ca=%s;v->cb=%s;v->cc=%s;'):format(a,b,c))
 emit('v->na=(size_t)(asp-v->a);v->nb=(size_t)(bsp-v->b);v->nc=(size_t)(csp-v->c);')
 emit('v->h[0]=h0;v->h[1]=h1;v->h[2]=h2;v->h[3]=h3;v->cr[0]=c0;v->cr[1]=c1;v->cr[2]=c2;')
 emit(('r->pc=%s;r->done=1;return ABC_OK;'):format(pc))
end
-- Dynamic counts select transitions of the same cache, not a second allocator.
local function pop_dynamic(stack,count,maximum)
 emit(('uint64_t value;if(%s){switch(%s){'):format(count,count))
 for cells=1,maximum do
  local state=cache.state(stack=='A' and cells or 0,stack=='B' and cells or 0,stack=='C' and cells or 0)
  emit(('case %d:value=%s;break;'):format(cells,cache.register(state,stack,0)))
 end
 emit(('default:__builtin_unreachable();}%s--;}else value=*--%ssp;'):format(count,keys[stack]))
end
local function push_dynamic(stack,count,value)
 local maximum=stack=='C' and 3 or 4
 emit(('switch(%s){'):format(count))
 for cells=0,maximum do
  local state=cache.state(stack=='A' and cells or 0,stack=='B' and cells or 0,stack=='C' and cells or 0)
  local transfer=builder(state);transfer:push(stack,value)
  emit(('case %d:{%s %s=%d;break;}'):format(cells,table.concat(transfer.lines,' '),count,transfer.state[keys[stack]]))
 end
 emit('default:__builtin_unreachable();}')
end
local function drop_context(count)
 emit(('if((%s)<=cached_context)cached_context-=(%s);else{csp-=(%s)-cached_context;cached_context=0;}'):format(count,count,count))
end
local function scalar_transfer(binding,transfer,me,other,instruction)
 local kind=transfer.kind
 if kind=='push' then
  local values={[8]='abc_imm8(operand[0])',[32]='(uint64_t)(int64_t)abc_i32(operand)',[64]='abc_u64(operand)'}
  binding:push(me,values[transfer.width])
 elseif kind=='dup' then binding:push(me,binding:peek(me))
 elseif kind=='drop' then binding:pop(me,true)
 elseif kind=='copy' then binding:push(other,binding:peek(me))
 elseif kind=='move' then binding:push(other,binding:pop(me))
 elseif kind=='cpush' then binding:push('C',binding:pop(me))
 elseif kind=='cpop' then binding:pop('C',true)
 elseif kind=='cget' then binding:push(me,transfer.depth and binding:peek('C',transfer.depth) or binding:cvalue('operand[0]'))
 elseif kind=='cset' then binding:cset(transfer.depth and tostring(transfer.depth) or 'operand[0]',binding:pop(me))
 elseif kind=='binary' or kind=='float_binary' then
  local left,right=binding:temp(binding:peek(me)),binding:temp(binding:peek(other))
  if transfer.check_zero then binding:line('if('..right..'==0)ABORT(1);') end
  local expressions=kind=='binary' and semantics.binary or semantics.float_binary
  local result=binding:temp(semantics.expr(expressions[transfer.operation],left,right))
  binding:pop(other,true);binding:line(binding:peek(me)..'='..result..';')
 elseif kind=='unary' then
  local value=binding:temp(binding:peek(me));binding:line(binding:peek(me)..'='..semantics.expr(semantics.unary[transfer.operation],value)..';')
 elseif kind=='float_unary' then
  local location=binding:peek(me)
  if transfer.operation=='FNEG' then binding:line(location..'^=UINT64_C(0x8000000000000000);')
  elseif transfer.operation=='I2FS' or transfer.operation=='I2FU' then binding:line(location..'=vm_'..transfer.operation:lower()..'('..location..');')
  else local result=binding:temp('0');binding:line('if(!vm_'..transfer.operation:lower()..'('..location..',&'..result..'))ABORT(3);'..location..'='..result..';') end
 elseif kind=='immediate' or kind=='c_operand' then
  local left=binding:temp(binding:peek(me))
  local right=binding:temp(kind=='immediate' and 'abc_imm8(operand[0])' or binding:cvalue('operand[0]'))
  binding:line(binding:peek(me)..'='..semantics.expr(semantics.binary[transfer.operation],left,right)..';')
 elseif kind=='check' then
  local value=binding:temp(binding:peek(me));binding:line('if('..semantics.expr(semantics.checks[transfer.operation],value)..')ABORT(3);')
 elseif kind=='power' then
  local left,right=binding:temp(binding:peek(me)),binding:temp(binding:peek(other))
  if transfer.signed_exponent then binding:line('if(abc_signed('..right..')<0)ABORT(4);') end
  binding:pop(other,true);binding:line(binding:peek(me)..'=vm_pow('..left..','..right..');')
 elseif kind=='jump' then binding:line('next+=abc_i'..transfer.width..'(operand);')
 elseif kind=='zero_branch' then
  local value=binding:pop(me);binding:line(('if(%s%s0)next+=abc_i16(operand);'):format(value,transfer.zero and '==' or '!='))
 elseif kind=='branch' or kind=='float_branch' or kind=='immediate_branch' then
  local left=binding:pop(me)
  local right=kind=='immediate_branch' and binding:temp('abc_imm8(operand[0])') or binding:pop(other)
  local expressions=kind=='float_branch' and semantics.float_branches or semantics.comparisons
  binding:line('if('..semantics.expr(expressions[transfer.operation],left,right)..')next+=abc_i16(operand'..(kind=='immediate_branch' and '+1' or '')..');')
 elseif kind=='switch' then
  local value=binding:pop(me);binding:line('if('..value..'<abc_u16(operand))next+=abc_i32(operand+2+4*(uint32_t)'..value..');')
 elseif kind=='memory' then
  local memory,action=instruction.mem,manifest.memory_action
  local offset=instruction.layout_name=='U32' and 'abc_u32(operand)' or instruction.layout_name=='U16' and 'abc_u16(operand)' or '0'
  local function load(address) return ('banked_load((const uint8_t *)(%s),%d,%d)'):format(address,memory.width,memory.sign) end
  if memory.action==action.FLOAD then binding:push(me,load(('(uint8_t *)csp+8*%d-(%s)'):format(binding.state.c,offset)))
  elseif memory.action==action.FSTORE then local value=binding:pop(me);binding:line(('banked_store((uint8_t *)csp+8*%d-(%s),%d,%s);'):format(binding.state.c,offset,memory.width,value))
  elseif memory.action==action.FADDR then binding:push(me,('(uint64_t)(uintptr_t)((uint8_t *)csp+8*%d-(%s))'):format(binding.state.c,offset))
  elseif memory.action==action.GLOAD then binding:push(me,load('r->image->bytes+('..offset..')'))
  elseif memory.action==action.GSTORE then local value=binding:pop(me);binding:line(('banked_store(r->image->bytes+(%s),%d,%s);'):format(offset,memory.width,value))
  elseif memory.action==action.GADDR then binding:push(me,'(uint64_t)(uintptr_t)(r->image->bytes+('..offset..'))')
  elseif memory.action==action.PLOAD then local address=binding:temp(binding:peek(me));binding:line(binding:peek(me)..'='..load('(uintptr_t)('..address..'+('..offset..'))')..';')
  elseif memory.action==action.PSTORE then local address,value=binding:pop(me),binding:pop(other);binding:line(('banked_store((uint8_t *)(uintptr_t)(%s+(%s)),%d,%s);'):format(address,offset,memory.width,value))
  elseif memory.action==action.XLOAD then local address,index=binding:temp(binding:peek(me)),binding:pop(other);binding:line(binding:peek(me)..'='..load(('(uintptr_t)(%s+%s*%d)'):format(address,index,memory.width))..';')
  elseif memory.action==action.INDEX then local index=binding:pop(other);binding:line(binding:peek(me)..'+='..index..'*('..offset..');')
  elseif memory.action==action.COPY then local destination,source=binding:pop(me),binding:pop(other);binding:line(('if(%s)memmove((void *)(uintptr_t)%s,(const void *)(uintptr_t)%s,%s);'):format(offset,destination,source,offset))
  else error('unbound memory action') end
 else return false end
 return true
end
local states=cache.states()
local header=assert(io.open(output..'/banked.h.tmp','wb'))
header:write('#pragma once\n#include "vm_internal.h"\n#include "handler_abi.h"\n')
for _,state in ipairs(states) do header:write(('extern const abc_handler T_a%db%dc%d[256];\n'):format(state.a,state.b,state.c)) end
header:write('extern const abc_handler *const abc_tables[100];\n')
for index=0,7 do
 out=files[index]
 emit('#include "banked.h"')
 emit('static inline uint64_t banked_load(const uint8_t *address,unsigned width,unsigned sign){uint64_t value=0;memcpy(&value,address,width);if(sign&&width==4)value=(uint64_t)(int64_t)(int32_t)value;return value;}')
 emit('static inline void banked_store(uint8_t *address,unsigned width,uint64_t value){memcpy(address,&value,width);}')
 emit('#define ABORT(REASON) do{unsigned reason=(REASON);abc_status status=abc_fail(e,ABC_ABORT,pc,"language abort %u",reason);if(e)e->reason=(uint8_t)reason;return status;}while(0)')
end
local function emit_handler(state,instruction,me,extended,suffix)
 local operation=manifest.operations[instruction.operation+1]
 local transfer=assert(semantics.transfers[operation],'missing semantic family '..operation)
 local kind=transfer.kind
 local other=opposite(me)
 local name='handler_'..suffix..'_'..operation..(me and '_'..me or '')
 local next_length=kind=='switch' and '3u+4u*abc_u16(ip+1)' or tostring(instruction.len)
 emit(('static ABC_HANDLER_CC abc_value %s(ABC_HANDLER_ARGS){'):format(name))
 emit('abc_run *r=abc_active_run;abc_vm *v=r->v;abc_error *e=r->e;uint32_t pc=(uint32_t)(ip-r->code);(void)v;(void)e;(void)pc;')
 emit(('const uint8_t *operand=ip+%d,*next=ip+(%s);(void)operand;(void)next;(void)asp;(void)bsp;(void)csp;(void)h0;(void)h1;(void)h2;(void)h3;(void)c0;(void)c1;(void)c2;'):format(extended and 2 or 1,next_length))
 local binding=builder(state)
 if scalar_transfer(binding,transfer,me,other,instruction) then
  emit(table.concat(binding.lines,' '));dispatch(binding.state)
 elseif kind=='ext' then
  emit(('ABC_HANDLER_TAIL return extended_%s_%s[ip[1]](%s);'):format(suffix,me,handler_arguments(state)))
 elseif kind=='abort' then emit('ABORT(operand[0]);')
 elseif kind=='allocate' or kind=='free' then
  flush_stack(state,'C')
  emit('size_t cells=(abc_u16(operand)+7u)/8u;')
  if kind=='allocate' then emit('if(cells>(size_t)(v->c+v->capacity-csp))return abc_fail(e,ABC_STACK,pc,"frame block stack limit reached");memset(csp,0,cells*8);csp+=cells;')
  else emit('csp-=cells;') end
  dispatch(cache.state(state.a,state.b,0))
 elseif kind=='cpushn' then
  emit(('unsigned cached_selected=%d,cached_context=%d;'):format(state[keys[me]],state.c))
  emit('for(unsigned index=0;index<operand[0];index++){')
  pop_dynamic(me,'cached_selected',state[keys[me]])
  push_dynamic('C','cached_context','value');emit('}')
  emit('ip=next;');dynamic_dispatch(me=='A' and 'cached_selected' or tostring(state.a),me=='B' and 'cached_selected' or tostring(state.b),'cached_context')
 elseif kind=='cgetr' then
  -- Keep the existing range-transfer boundary: publish only its destination and C.
  flush_stack(state,me);flush_stack(state,'C')
  emit(('for(unsigned index=0;index<operand[1];index++)*%ssp++=csp[-1-(int)operand[0]-(int)index];'):format(keys[me]))
  dispatch(cache.state(me=='A' and 0 or state.a,me=='B' and 0 or state.b,0))
 elseif kind=='fcall' then
  flush_stack(state,'A');flush_stack(state,'B');flush_stack(state,'C')
  emit('v->ca=v->cb=v->cc=0;v->na=(size_t)(asp-v->a);v->nb=(size_t)(bsp-v->b);v->nc=(size_t)(csp-v->c);')
  emit(('abc_status status=vm_foreign(r,abc_u16(operand),%d,pc);if(status!=ABC_OK)return status;'):format(me=='A' and 0 or 1))
  emit('asp=v->a+v->na;bsp=v->b+v->nb;csp=v->c+v->nc;')
  dispatch(cache.state(0,0,0))
 elseif kind=='halt' then
  flush_stack(state,'A');flush_stack(state,'B');flush_stack(state,'C')
  if me=='B' then emit('size_t results=(size_t)(bsp-v->b);memcpy(asp,v->b,results*8);asp+=results;bsp=v->b;') end
  publish('0','0','0','(uint32_t)(next-r->code)')
 elseif kind=='call' or kind=='tcall' or kind=='calli' or kind=='tcalli' then
  local tail=kind=='tcall' or kind=='tcalli'
  local indirect=kind=='calli' or kind=='tcalli'
  if indirect then
   local target=binding:pop(other);emit(table.concat(binding.lines,' '))
   emit(('uint32_t callee_index;abc_status status=vm_resolve_indirect(r,pc,%s,&callee_index);if(status!=ABC_OK)return status;'):format(target))
  else emit('uint32_t callee_index=r->image->direct_callees[pc];') end
  local remaining=binding.state
  emit('const abc_call_info *callee=&r->image->call_info[callee_index];')
  emit(('unsigned arguments=operand[%d],frame_cells=%s,cached_selected=%d,cached_context=%d;'):format(indirect and (tail and 1 or 0) or (tail and 5 or 4),tail and (indirect and 'operand[0]' or 'operand[4]') or '0',remaining[keys[me]],remaining.c))
  emit(('size_t depth_a=(size_t)(asp-v->a)+%d,depth_b=(size_t)(bsp-v->b)+%d,depth_c=(size_t)(csp-v->c)+%d;'):format(remaining.a,remaining.b,remaining.c))
  emit(('if(%sdepth_a-%s+callee->max_a>v->capacity||depth_b-%s+callee->max_b>v->capacity||depth_c%s+callee->max_c>v->capacity)return abc_fail(e,ABC_STACK,pc,"stack limit reached");'):format(tail and '' or 'v->nf==v->capacity||',me=='A' and 'arguments' or '0',me=='B' and 'arguments' or '0',tail and '-frame_cells' or '+1'))
  if tail then drop_context('frame_cells')
  else
   emit(('v->frames[v->nf++]=(abc_frame){(uint32_t)(next-r->code),%d};'):format(me=='A' and 0 or 1))
   push_dynamic('C','cached_context','(uint32_t)(next-r->code)')
  end
  emit('(void)frame_cells;for(unsigned index=0;index<arguments;index++){')
  pop_dynamic(me,'cached_selected',remaining[keys[me]]);push_dynamic('C','cached_context','value');emit('}')
  emit('ip=r->code+callee->entry;')
  dynamic_dispatch(me=='A' and 'cached_selected' or tostring(remaining.a),me=='B' and 'cached_selected' or tostring(remaining.b),'cached_context')
 elseif kind=='ret' then
  emit(('unsigned cached_context=%d;unsigned cells=(unsigned)operand[0]+1,results=operand[1];'):format(state.c))
  drop_context('cells')
  emit('abc_frame continuation=v->frames[--v->nf];')
  emit(('if(continuation.result_destination_stack==%d){'):format(me=='A' and 0 or 1))
  emit('if(!v->nf){');publish(tostring(state.a),tostring(state.b),'cached_context','continuation.return_pc');emit('}')
  emit('ip=r->code+continuation.return_pc;');dynamic_dispatch(tostring(state.a),tostring(state.b),'cached_context');emit('}')
  flush_stack(state,me)
  emit(('const uint64_t *result_values=%ssp-results;%ssp-=results;unsigned cached_destination=%d;'):format(keys[me],keys[me],state[keys[other]]))
  emit('for(unsigned index=0;index<results;index++){')
  push_dynamic(other,'cached_destination','result_values[index]');emit('}')
  local a=other=='A' and 'cached_destination' or '0'
  local b=other=='B' and 'cached_destination' or '0'
  emit('if(!v->nf){');publish(a,b,'cached_context','continuation.return_pc');emit('}')
  emit('ip=r->code+continuation.return_pc;');dynamic_dispatch(a,b,'cached_context')
 else error('missing concrete transfer '..operation) end
 emit('}')
 return name
end
for index,state in ipairs(states) do
 out=files[(index-1)%8]
 local suffix=('a%db%dc%d'):format(state.a,state.b,state.c)
 for _,me in ipairs{'A','B'} do
  local handlers={}
  for _,instruction in ipairs(manifest.ext_ops) do handlers[#handlers+1]=emit_handler(state,instruction,me,true,suffix) end
  emit(('static const abc_handler extended_%s_%s[EXT_COUNT]={%s};'):format(suffix,me,table.concat(handlers,',')))
 end
 local handlers={}
 for _,instruction in ipairs(manifest.ops) do
  local me=instruction.stack==manifest.stack.A and 'A' or instruction.stack==manifest.stack.B and 'B' or nil
  handlers[#handlers+1]=emit_handler(state,instruction,me,false,suffix)
 end
 emit(('const abc_handler T_%s[256]={%s};'):format(suffix,table.concat(handlers,',')))
end
out=files[0];emit('const abc_handler *const abc_tables[100]={')
for _,state in ipairs(states) do emit(('[%d]=T_a%db%dc%d,'):format((state.a*5+state.b)*4+state.c,state.a,state.b,state.c)) end
emit('};')
assert(header:close());assert(os.rename(output..'/banked.h.tmp',output..'/banked.h'))
for index=0,7 do assert(files[index]:close());assert(os.rename(('%s/banked_%d.c.tmp'):format(output,index),('%s/banked_%d.c'):format(output,index))) end
