-- Generate the musttail-dispatch transfer front-end for the internal symbolic ABC VM.
local root=(arg[0]:match('^(.*)/[^/]+$') or '.')
package.path=root..'/?.lua;'..root..'/../tools/?.lua;'..package.path
local manifest=require('opcodes')
local semantics=require('semantics')
local dir=assert(arg[1],'output directory required')
local path=dir..'/symbolic_dispatch.c.tmp'
local out=assert(io.open(path,'wb'))
local function emit(line) assert(out:write(line,'\n')) end

emit('#include "symbolic.h"')
emit('#include "opcodes.h"')
emit('typedef abc_symbolic_exit (*abc_symbolic_handler)(abc_symbolic_machine *);')
emit('static const abc_symbolic_handler handlers[OP_COUNT];')
emit('#define SYM_NEXT(N) do { m->pc+=(N)+m->extra_advance; m->extra_advance=0; if(m->pc>=m->end || (m->blocks&&m->blocks[m->pc])) return ABC_SYM_EXIT_BLOCK; ABC_MUSTTAIL return handlers[m->code[m->pc]](m); } while(0)')
emit('static abc_symbolic_exit boundary(abc_symbolic_machine *m){return abc_symbolic_machine_boundary(m);}')

local function transfer(op)
  local effect=semantics.symbolic[op.name]
  if effect then return effect end
  if op.mem then return {kind='memory'} end
  local name=op.name
  if name=='EXT' then return {kind='dynamic'} end
  if name=='FCALL' then return {kind='foreign'} end
  if name=='RET' then return {kind='return'} end
  if name=='TCALL' then return {kind='tail'} end
  if name=='CALL_A' or name=='CALL_B' then return {kind='call',destination=name:sub(-1)} end
  if name=='CALLI_A' or name=='CALLI_B' then return {kind='indirect',destination=name:sub(-1)} end
  if name=='TCALLI' then return {kind='indirect_tail'} end
  if name:match('^CALL') or name:match('^TCALL') or name:match('^RET') then
    return {kind='effect',family='call'}
  end
  error('opcode lacks symbolic transfer metadata: '..name)
end

local function action(op)
  local effect=transfer(op)
  if effect.kind=='push' then
    local value=effect.width==8 and 'abc_imm8(p[1])' or effect.width==32 and '(uint64_t)(int64_t)abc_i32(p+1)' or 'abc_u64(p+1)'
    return ('abc_symbolic_machine_push(m,ABC_SYM_%s,%s)'):format(effect.stack,value)
  elseif effect.kind=='dup' then return ('abc_symbolic_machine_dup(m,ABC_SYM_%s)'):format(effect.stack)
  elseif effect.kind=='drop' then return ('abc_symbolic_machine_drop(m,ABC_SYM_%s)'):format(effect.stack)
  elseif effect.kind=='cpush' then return ('abc_symbolic_machine_cpush(m,ABC_SYM_%s)'):format(effect.stack)
  elseif effect.kind=='cpushn' then return 'abc_symbolic_machine_cpushn(m,p[1])'
  elseif effect.kind=='cpop' then return 'abc_symbolic_machine_cpop(m)'
  elseif effect.kind=='transfer' then return ('abc_symbolic_machine_transfer(m,ABC_SYM_%s,ABC_SYM_%s,%d)'):format(effect.from,effect.to,effect.consume and 1 or 0)
  elseif effect.kind=='cget' then return ('abc_symbolic_machine_cget(m,ABC_SYM_%s,%s)'):format(effect.stack,effect.depth=='immediate' and 'p[1]' or effect.depth)
  elseif effect.kind=='cget_range' then return ('abc_symbolic_machine_cget_range(m,ABC_SYM_%s,p[1],p[2])'):format(effect.stack)
  elseif effect.kind=='cset' then return ('abc_symbolic_machine_cset(m,ABC_SYM_%s,%s)'):format(effect.stack,effect.depth=='immediate' and 'p[1]' or effect.depth)
  elseif effect.kind=='binary' then return ('abc_symbolic_machine_binary(m,OP_%s_A,ABC_SYM_%s)'):format(effect.operation,effect.destination)
  elseif effect.kind=='unary' then return ('abc_symbolic_machine_unary(m,OP_%s_A,ABC_SYM_%s)'):format(effect.operation,effect.stack)
  elseif effect.kind=='float_binary' then return ('abc_symbolic_machine_float_binary(m,OP_%s_A,ABC_SYM_%s)'):format(effect.operation,effect.destination)
  elseif effect.kind=='immediate' then return ('abc_symbolic_machine_immediate(m,OP_%sI_A,ABC_SYM_%s,abc_imm8(p[1]))'):format(effect.operation,effect.stack)
  elseif effect.kind=='c_operand' then return ('abc_symbolic_machine_c_operand(m,OP_%sC_A,ABC_SYM_%s,p[1])'):format(effect.operation,effect.stack)
  elseif effect.kind=='float_unary' then return ('abc_symbolic_machine_float_unary(m,OP_%s)'):format(effect.operation)
  elseif effect.kind=='mask' then return ('abc_symbolic_machine_immediate(m,OP_ANDI_A,ABC_SYM_A,%d)'):format(effect.immediate)
  elseif effect.kind=='pow' then return ('abc_symbolic_machine_pow(m,OP_%s)'):format(op.name)
  elseif effect.kind=='check' then return ('abc_symbolic_machine_check(m,OP_%s)'):format(op.name)
  elseif effect.kind=='jump' then
    local offset=effect.width==16 and 'abc_i16(p+1)' or 'abc_i32(p+1)'
    return ('abc_symbolic_machine_control(m,ABC_SYM_CONTROL_JUMP,OP_%s,0,0,0,(uint32_t)((int64_t)(m->pc+%d)+%s),m->pc+%d,0)'):format(op.name,op.len,offset,op.len)
  elseif effect.kind=='zero_branch' then return ('abc_symbolic_machine_control(m,ABC_SYM_CONTROL_ZERO,OP_%s,%d,0,ABC_SYM_%s,(uint32_t)((int64_t)(m->pc+%d)+abc_i16(p+1)),m->pc+%d,0)'):format(op.name,effect.relation,effect.stack,op.len,op.len)
  elseif effect.kind=='branch' then return ('abc_symbolic_machine_control(m,ABC_SYM_CONTROL_INTEGER,OP_%s,%d,0,0,(uint32_t)((int64_t)(m->pc+%d)+abc_i16(p+1)),m->pc+%d,0)'):format(op.name,effect.relation,op.len,op.len)
  elseif effect.kind=='float_branch' then return ('abc_symbolic_machine_control(m,ABC_SYM_CONTROL_FLOAT,OP_%s,%d,0,0,(uint32_t)((int64_t)(m->pc+%d)+abc_i16(p+1)),m->pc+%d,0)'):format(op.name,effect.relation,op.len,op.len)
  elseif effect.kind=='immediate_branch' then return ('abc_symbolic_machine_control(m,ABC_SYM_CONTROL_IMMEDIATE,OP_%s,%d,%d,ABC_SYM_A,(uint32_t)((int64_t)(m->pc+%d)+abc_i16(p+2)),m->pc+%d,abc_imm8(p[1]))'):format(op.name,effect.relation,effect.reverse and 1 or 0,op.len,op.len)
  elseif effect.kind=='abort' then return 'abc_symbolic_machine_abort(m,p[1])'
  elseif effect.kind=='switch' then return 'abc_symbolic_machine_switch(m,abc_u16(p+1),m->pc+3+4*abc_u16(p+1))'
  elseif effect.kind=='halt' then return 'abc_symbolic_machine_halt(m)'
  elseif effect.kind=='memory' then return ('abc_symbolic_machine_memory(m,OP_%s)'):format(op.name)
  elseif effect.kind=='return' then return 'abc_symbolic_machine_return(m,p[1],p[2])'
  elseif effect.kind=='call' then return ('abc_symbolic_machine_call(m,(uint32_t)((int64_t)(m->pc+%d)+abc_i32(p+1)),p[5],ABC_SYM_%s,m->pc+%d)'):format(op.len,effect.destination,op.len)
  elseif effect.kind=='indirect' then return ('abc_symbolic_machine_indirect(m,0,p[1],ABC_SYM_%s,0)'):format(effect.destination)
  elseif effect.kind=='indirect_tail' then return 'abc_symbolic_machine_indirect(m,p[1],p[2],ABC_SYM_A,1)'
  elseif effect.kind=='tail' then return ('abc_symbolic_machine_tail(m,(uint32_t)((int64_t)(m->pc+%d)+abc_i32(p+1)),p[5],p[6])'):format(op.len)
  elseif effect.kind=='dynamic' then return 'abc_symbolic_machine_dynamic(m)'
  elseif effect.kind=='foreign' then return 'abc_symbolic_machine_foreign(m)'
  elseif effect.kind=='effect' then return ('abc_symbolic_machine_effect(m,OP_%s)'):format(op.name)
  end
  error('unknown symbolic effect '..effect.kind)
end

for _,op in ipairs(manifest.ops) do
  local lower=op.name:lower()
  local a=action(op)
  if a then
    local effect=transfer(op)
    local control=effect.kind=='jump' or effect.kind=='zero_branch' or effect.kind=='branch' or effect.kind=='float_branch' or effect.kind=='immediate_branch' or effect.kind=='abort' or effect.kind=='switch' or effect.kind=='halt'
    local value=effect.kind=='binary' or effect.kind=='unary' or effect.kind=='float_binary' or effect.kind=='immediate' or effect.kind=='c_operand' or effect.kind=='float_unary' or effect.kind=='mask' or effect.kind=='pow' or effect.kind=='check'
    local effects=effect.kind=='effect' or effect.kind=='memory' or effect.kind=='return' or effect.kind=='call' or effect.kind=='indirect' or effect.kind=='indirect_tail' or effect.kind=='tail' or effect.kind=='dynamic' or effect.kind=='foreign'
    local mask=control and 'ABC_SYM_TRANSFER_CONTROL' or effects and 'ABC_SYM_TRANSFER_EFFECT' or value and 'ABC_SYM_TRANSFER_VALUE' or 'ABC_SYM_TRANSFER_STACK'
    local length=op.name=='EXT' and 'abc_instruction_length(p)' or tostring(op.len)
    emit(('static abc_symbolic_exit h_%s(abc_symbolic_machine *m){const uint8_t*p=m->code+m->pc;(void)p;if(m->transfer_mask&&!(m->transfer_mask&%s))return boundary(m);if(!(%s))return m->exit;SYM_NEXT(%s);}'):format(lower,mask,a,length))
  else error('symbolic transfer has no generator action: '..op.name)
  end
end
emit('static const abc_symbolic_handler handlers[OP_COUNT]={')
for _,op in ipairs(manifest.ops) do emit((' [OP_%s]=h_%s,'):format(op.name,op.name:lower())) end
emit('};')
emit('abc_symbolic_exit abc_symbolic_dispatch(abc_symbolic_machine*m){if(!m||!m->context||!m->code||m->pc>=m->end)return ABC_SYM_EXIT_FAILURE;abc_clear(m->error);m->exit=ABC_SYM_EXIT_BLOCK;ABC_MUSTTAIL return handlers[m->code[m->pc]](m);}')
emit('#undef SYM_NEXT')
assert(out:close())
assert(os.rename(path,dir..'/symbolic_dispatch.c'))
io.stderr:write(('generated %d symbolic opcode handlers\n'):format(#manifest.ops))

