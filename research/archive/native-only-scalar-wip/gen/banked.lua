-- Emit handlers indexed by the actual interpreter cache state.
-- Placement is derived from gen/cache.lua; instruction effects below follow docs/spec.md.
local root = (arg[0]:match('^(.*)/[^/]+$') or '.')
package.path = root .. '/?.lua;' .. root .. '/../tools/?.lua;' .. package.path
local cache = require('cache')
local semantics = require('semantics')
local banked = require('banked_manifest')
local manifest = require('opcodes')
local output = assert(arg[1], 'output directory required')
local files = {}
for i=0,7 do files[i] = assert(io.open(('%s/banked_%d.c.tmp'):format(output,i),'wb')) end
local out
local function emit(s) assert(out:write(s, '\n')) end
local stacks = { A = 'a', B = 'b', C = 'c' }
local B = {}; B.__index = B
local function builder(state)
  return setmetatable({ state = cache.state(state.a,state.b,state.c), lines = {}, n = 0 }, B)
end
function B:line(s) self.lines[#self.lines+1] = s end
function B:temp(expression)
  self.n = self.n + 1
  local name = 't' .. self.n
  self:line('uint64_t ' .. name .. ' = ' .. expression .. ';')
  return name
end
function B:location(stack, depth)
  local reg = cache.register(self.state,stack,depth)
  if reg then return reg end
  local key = stacks[stack]
  local cached = self.state[key]
  return ('%ssp[-1-(%s)]'):format(key,depth == 0 and (0-cached) or ('(' .. depth .. ' - ' .. cached .. ')'))
end
function B:peek(stack,depth) return self:location(stack,depth or 0) end
function B:cvalue(depth)
  local expression=('csp[-1-((int)(%s)-%d)]'):format(depth,self.state.c)
  local regs={'c0','c1','c2'}; for d=self.state.c-1,0,-1 do expression=('((%s)==%d?%s:%s)'):format(depth,self.state.c-1-d,regs[d+1],expression) end
  return expression
end
function B:cset(depth,value)
  local regs={'c0','c1','c2'}
  for d=self.state.c-1,0,-1 do self:line(('if((%s)==%d) %s=%s; else '):format(depth,self.state.c-1-d,regs[d+1],value)) end
  self:line(('csp[-1-((int)(%s)-%d)]=%s;'):format(depth,self.state.c,value))
end
function B:pop(stack,discard)
  local source
  if not discard then source = self:temp(self:peek(stack)) end
  if self.state[stacks[stack]] == 0 then self:line('--' .. stacks[stack] .. 'sp;') end
  self.state = cache.pop(self.state,stack)
  return source
end
function B:forget_unused()
  for i=0,3 do if not (i<self.state.a or i>=4-self.state.b) then self:line(('h%d=0;'):format(i)) end end
  for i=self.state.c,2 do self:line(('c%d=0;'):format(i)) end
end
function B:push(stack,value)
  local captured = self:temp(value)
  local key = stacks[stack]
  local next_state,spill = cache.push(self.state,stack)
  if spill then
    for _,step in ipairs(cache.spill_steps(self.state,spill)) do
      local function loc(reg) return reg end
      if step.kind == 'store' then
        local k = stacks[spill]
        self:line(('*%ssp++ = %s;'):format(k,loc(step.source)))
      else self:line(loc(step.destination) .. ' = ' .. loc(step.source) .. ';') end
    end
  end
  self.state = next_state
  self:line(self:peek(stack) .. ' = ' .. captured .. ';')
end
function B:finish()
  local s=self.state
  self:line(('ip=next; ABC_HANDLER_TAIL return T_a%db%dc%d[*ip](ABC_HANDLER_PASS);'):format(s.a,s.b,s.c))
  return table.concat(self.lines,' ')
end
local operations = {}
local function define(name, function_body)
  assert(not operations[name], 'duplicate ' .. name)
  operations[name] = function_body
end
for _, X in ipairs({ 'A','B' }) do
  for _, width in ipairs({8,32,64}) do
    local immediate = ({ [8]='abc_imm8(p[1])', [32]='(uint64_t)(int64_t)abc_i32(p+1)', [64]='abc_u64(p+1)' })[width]
    define('PUSH'..width..'_'..X,function(b) b:push(X,immediate) end)
  end
  define('DUP_'..X,function(b) b:push(X,b:peek(X)) end)
  define('DROP_'..X,function(b) b:pop(X,true) end)
  define('CPUSH_'..X,function(b) b:push('C',b:pop(X)) end)
  define('CGET0_'..X,function(b) b:push(X,b:peek('C',0)) end)
  define('CGET1_'..X,function(b) b:push(X,b:peek('C',1)) end)
  define('CGETN_'..X,function(b) b:push(X,b:cvalue('p[1]')) end)
  define('CGETR_'..X,function(b) b.cgetr=X end)
end
define('CPUSHN',function(b) b.cpushn=true end)
define('CPOP',function(b) b:pop('C',true) end)
for _, pair in ipairs({ {'A','B'}, {'B','A'} }) do
  local X,Y = pair[1],pair[2]
  define('COPY_'..X..Y,function(b) b:push(Y,b:peek(X)) end)
  define('MOVE_'..X..Y,function(b) b:push(Y,b:pop(X)) end)
end
local binary = semantics.binary
for _,name in ipairs(semantics.binary_order) do
  for _,X in ipairs({'A','B'}) do
    define(name..'_'..X,function(b)
      local x,y=b:temp(b:peek('A')),b:temp(b:peek('B'))
      if name:match('^DIV') or name:match('^REM') then b:line('if('..y..'==0) ABORT(1);') end
      local result=b:temp(semantics.expr(binary[name],x,y))
      b:pop(X=='A' and 'B' or 'A',true)
      b:line(b:peek(X)..' = '..result..';')
    end)
  end
end
for _,name in ipairs(semantics.float_binary_order) do
  for _,X in ipairs({'A','B'}) do
    define(name..'_'..X,function(b)
      local x,y=b:temp(b:peek('A')),b:temp(b:peek('B'))
      local result=b:temp(semantics.expr(semantics.float_binary[name],x,y))
      b:pop(X=='A' and 'B' or 'A',true); b:line(b:peek(X)..' = '..result..';')
    end)
  end
end
local unary = semantics.unary
for _,name in ipairs(semantics.unary_order) do
  for _,X in ipairs({'A','B'}) do
    define(name..'_'..X,function(b)
      local x=b:temp(b:peek(X))
      b:line(b:peek(X)..' = '..semantics.expr(unary[name],x)..';')
    end)
  end
end
define('FNEG',function(b) b:line(b:peek('A')..' ^= UINT64_C(0x8000000000000000);') end)
define('I2FS',function(b) b:line(b:peek('A')..' = vm_i2fs('..b:peek('A')..');') end)
define('I2FU',function(b) b:line(b:peek('A')..' = vm_i2fu('..b:peek('A')..');') end)
for _,name in ipairs({'F2IS','F2IU'}) do define(name,function(b)
  local result=b:temp('0'); b:line('if(!vm_'..name:lower()..'('..b:peek('A')..', &'..result..')) ABORT(3);'); b:line(b:peek('A')..' = '..result..';')
end) end
for _,name in ipairs(semantics.immediate_order) do
  for _,X in ipairs({'A','B'}) do
    define(name..'I_'..X,function(b)
      local x,y=b:temp(b:peek(X)),b:temp('abc_imm8(p[1])')
      b:line(b:peek(X)..' = '..semantics.expr(binary[name],x,y)..';')
    end)
  end
end
for _,name in ipairs(semantics.c_operand_order) do
  for _,X in ipairs({'A','B'}) do
    define(name..'C_'..X,function(b)
      local x,y=b:temp(b:peek(X)),b:temp(b:cvalue('p[1]'));b:line(b:peek(X)..' = '..semantics.expr(binary[name],x,y)..';')
    end)
  end
end
define('ZX8',function(b) b:line(b:peek('A')..' &= 255;') end)
define('ZX16',function(b) b:line(b:peek('A')..' &= 65535;') end)
for _,name in ipairs({'POW','POWS'}) do
  define(name,function(b)
    local y=b:temp(b:peek('B'))
    if name=='POWS' then b:line('if(abc_signed('..y..')<0) ABORT(4);') end
    b:pop('B',true)
    b:line(b:peek('A')..' = vm_pow('..b:peek('A')..','..y..');')
  end)
end
local checks=semantics.checks
for _,name in ipairs(semantics.check_order) do
  define(name,function(b)
    local x=b:temp(b:peek('A'))
    b:line('if('..semantics.expr(checks[name],x)..') ABORT(3);')
  end)
end
for _,X in ipairs({'A','B'}) do
  define('CSET0_'..X,function(b)
    local x=b:pop(X)
    b:line(b:peek('C')..' = '..x..';')
  end)
  define('CSETN_'..X,function(b) local x=b:pop(X);b:cset('p[1]',x) end)
end
define('JMP',function(b) b:line('next+=abc_i16(p+1);') end)
define('JMP32',function(b) b:line('next+=abc_i32(p+1);') end)
define('SWITCH',function(b) local x=b:pop('A'); b:line('if('..x..'<abc_u16(p+1)) next+=abc_i32(p+3+4*(uint32_t)'..x..');') end)
for _,X in ipairs({'A','B'}) do
  for _,name in ipairs({'JZ','JNZ'}) do
    define(name..'_'..X,function(b)
      local x=b:pop(X)
      b:line('if(('..x..'==0)=='..(name=='JZ' and '1' or '0')..') next+=abc_i16(p+1);')
    end)
  end
end
local comparisons=semantics.comparisons
for _,name in ipairs(semantics.branch_order) do
  define(name,function(b)
    local x,y=b:pop('A'),b:pop('B')
    b:line('if('..semantics.expr(comparisons[name],x,y)..') next+=abc_i16(p+1);')
  end)
end
for _,name in ipairs(semantics.float_branch_order) do
  define(name,function(b)
    local x,y=b:pop('A'),b:pop('B')
    b:line('if('..semantics.expr(semantics.float_branches[name],x,y)..') next+=abc_i16(p+1);')
  end)
end
for _,name in ipairs({'BEQI','BNEI','BLTI','BLEI','BGTI','BGEI','BLTUI','BLEUI','BGTUI','BGEUI'}) do
  define(name,function(b)
    local x,y=b:pop('A'),b:temp('abc_imm8(p[1])')
    b:line('if('..semantics.expr(comparisons[name:sub(1,-2)],x,y)..') next+=abc_i16(p+2);')
  end)
end
for _,X in ipairs({'A','B'}) do
  local destination=X=='B' and 1 or 0
  define('CALL_'..X,function(b) b.generic_call=destination;b.needs_run=true end)
  for n=0,2 do
    define('CALL_'..X..'_'..n,function(b) b.needs_run=true
      b:forget_unused()
      b:line('const abc_call_info *callee=&r->image->call_info[r->image->direct_callees[pc]-1]; const uint8_t *target=r->code+callee->entry;')
      b:line(('if(v->nf==v->capacity || asp+((int)%d-%d)+callee->max_a>v->a+v->capacity || bsp+%d+callee->max_b>v->b+v->capacity || csp+%d+1+callee->max_c>v->c+v->capacity) return abc_fail(e,ABC_STACK,pc,"stack limit reached");'):format(b.state.a,n,b.state.b,b.state.c))
      b:line(('v->frames[v->nf++]=(abc_frame){(uint32_t)(next-r->code),%d};'):format(destination))
      b:push('C','(uint32_t)(next-r->code)')
      for _=1,n do b:push('C',b:pop('A')) end
      b:line('next=target;')
    end)
  end
end
define('TCALL',function(b) b.generic_tail=true;b.needs_run=true end)
for k=0,2 do for n=0,2 do
  define('TCALL_'..k..'_'..n,function(b) b.needs_run=true
    b:forget_unused()
    b:line('const abc_call_info *callee=&r->image->call_info[r->image->direct_callees[pc]-1]; const uint8_t *target=r->code+callee->entry;')
    b:line(('if(asp+((int)%d-%d)+callee->max_a>v->a+v->capacity || bsp+%d+callee->max_b>v->b+v->capacity || csp+((int)%d-%d)+callee->max_c>v->c+v->capacity) return abc_fail(e,ABC_STACK,pc,"stack limit reached");'):format(b.state.a,n,b.state.b,b.state.c,k))
    local args={} for j=n,1,-1 do args[j]=b:pop('A') end
    for _=1,k do b:pop('C',true) end
    for j=n,1,-1 do b:push('C',args[j]) end
    b:line('next=target;')
  end)
end end
define('RET',function(b) b.generic_return=true;b.needs_run=true end)
for k=0,2 do for r=0,2 do
  define('RET_'..k..'_'..r,function(b) b.ret={k=k,r=r};b.needs_run=true end)
end end
for _,op in ipairs(manifest.ops) do
  if op.name:match('^CALLI') then define(op.name,function(b)local target=b:pop('B');b.indirect={form=op.name:match('_B') and 1 or 0,tail=false,target=target};b.needs_run=true end)
  elseif op.name:match('^TCALLI') then define(op.name,function(b)local target=b:pop('B');b.indirect={form=2,tail=true,target=target};b.needs_run=true end) end
end
for _,op in ipairs(manifest.ops) do if op.kind==manifest.kind.MEMORY then
  define(op.name,function(b)
    local m=op.mem local a=manifest.memory_action local X=m.to_b==1 and 'B' or 'A'
    local off=op.len==5 and 'abc_u32(p+1)' or op.len==3 and 'abc_u16(p+1)' or '0'
    local function load(address) return b:temp(('banked_load((const uint8_t *)(%s),%d,%d)'):format(address,m.width,m.sign)) end
    if m.action==a.ALLOC then b.mem_alloc=true;b.needs_run=true
    elseif m.action==a.FREE then b.mem_free=true
    elseif m.action==a.FLOAD then b:push(X,load(('((uint8_t *)csp+8*%d-(%s))'):format(b.state.c,off)))
    elseif m.action==a.FSTORE then local value=b:pop(X);b:line(('banked_store((uint8_t *)csp+8*%d-(%s),%d,%s);'):format(b.state.c,off,m.width,value))
    elseif m.action==a.FADDR then b:push(X,('(uint64_t)(uintptr_t)((uint8_t *)csp+8*%d-(%s))'):format(b.state.c,off))
    elseif m.action==a.GLOAD then b.needs_run=true;b:push('A',load(('r->image->bytes+(%s)'):format(off)))
    elseif m.action==a.GSTORE then b.needs_run=true;local value=b:pop('A');b:line(('banked_store(r->image->bytes+(%s),%d,%s);'):format(off,m.width,value))
    elseif m.action==a.GADDR then b.needs_run=true;b:push(X,('(uint64_t)(uintptr_t)(r->image->bytes+(%s))'):format(off))
    elseif m.action==a.PLOAD then local loc=b:peek(X);b:line(('%s=banked_load((const uint8_t *)(uintptr_t)(%s+(%s)),%d,%d);'):format(loc,loc,off,m.width,m.sign))
    elseif m.action==a.PSTORE then b.needs_run=true;local address=b:pop('A');local value=b:pop('B');b:line(('banked_store((uint8_t *)(uintptr_t)(%s+(%s)),%d,%s);vm_dynamic_write_native(%s+(%s),%d);'):format(address,off,m.width,value,address,off,m.width))
    elseif m.action==a.XLOAD then local index=b:pop('B');local loc=b:peek('A');b:line(('%s=banked_load((const uint8_t *)(uintptr_t)(%s+%s*%d),%d,%d);'):format(loc,loc,index,m.width,m.width,m.sign))
    elseif m.action==a.INDEX then local index=b:pop('B');local loc=b:peek('A');b:line(('%s+=%s*(%s);'):format(loc,index,off))
    elseif m.action==a.COPY then b.needs_run=true;local dst=b:pop('A');local src=b:pop('B');b:line(('if(%s){memmove((void *)(uintptr_t)%s,(const void *)(uintptr_t)%s,%s);vm_dynamic_write_native(%s,%s);}'):format(off,dst,src,off,dst,off))
    else error('unknown memory action '..m.action) end
  end)
end end
define('HALT',function(b) b.halt=true;b.needs_run=true end)
define('ABORT',function(b) b.abort=true;b.needs_run=true end)
define('FCALL',function(b) b.foreign=true;b.needs_run=true end)
define('EXT',function(b) b.dynamic_ext=true;b.needs_run=true end)
for _,op in ipairs(manifest.ops) do
  local indirect=op.name:match('^CALLI') or op.name:match('^TCALLI')
  if op.kind~=manifest.kind.MEMORY and op.kind~=manifest.kind.EXT and op.kind~=manifest.kind.FCALL and not indirect then
    assert(banked[op.name], 'missing generated opcode: '..op.name)
  end
end
for name in pairs(banked) do assert(operations[name], 'missing banked semantics: '..name) end
local declared={} for _,op in ipairs(manifest.ops) do declared[op.name]=op end
for name in pairs(operations) do assert(banked[name] or (declared[name] and declared[name].kind==manifest.kind.MEMORY) or name:match('^CALLI') or name:match('^TCALLI') or name=='FCALL' or name=='EXT', 'banked handler not declared: '..name) end
local states = cache.states()
local header = assert(io.open(output..'/banked.h.tmp','wb'))
header:write('/* Generated interpreter dispatch tables. */\n#ifndef ABC_BANKED_H\n#define ABC_BANKED_H\n#include "vm_internal.h"\n#include "handler_abi.h"\n')
for _,s in ipairs(states) do
  header:write(('extern const abc_handler T_a%db%dc%d[256];\n'):format(s.a,s.b,s.c))
end
header:write('extern const abc_handler *const abc_tables[100];\n#endif\n')
for i=0,7 do
  out=files[i]
  emit('#include "banked.h"')
  emit('static inline uint64_t banked_load(const uint8_t *p,unsigned width,unsigned sign){uint64_t v=0;memcpy(&v,p,width);if(sign&&width==4)v=(uint64_t)(int64_t)(int32_t)v;return v;}')
  emit('static inline void banked_store(uint8_t *p,unsigned width,uint64_t v){memcpy(p,&v,width);}')
  emit('#define ABORT(REASON) do { unsigned reason=(REASON); abc_run *ar=abc_active_run; uint32_t at=(uint32_t)(ip-ar->code); abc_error *ae=ar->e; abc_status status=abc_fail(ae,ABC_ABORT,at,"language abort %u",reason); if(ae) ae->reason=(uint8_t)reason; return status; } while(0)')
end
local names,opinfo = {},{}
for _,op in ipairs(manifest.ops) do opinfo[op.name]=op end
for name in pairs(operations) do names[#names+1]=name end
table.sort(names)
for index,s in ipairs(states) do
  out=files[(index-1)%8]
  local suffix=('a%db%dc%d'):format(s.a,s.b,s.c)
  local key=(s.a*5+s.b)*4+s.c
  local entries = {}
  for _,opcode in ipairs(names) do
    local b=builder(s)
    local info=assert(opinfo[opcode])
    operations[opcode](b)
    b.branch=info.kind==manifest.kind.BRANCH or info.kind==manifest.kind.BRI or info.kind==manifest.kind.JMP32 or info.kind==manifest.kind.SWITCH
    if b.branch then b.needs_run=true end
    if b.dynamic then
      entries[opcode]=cold
    else
      local fn='h_'..suffix..'_'..opcode
      entries[opcode]=fn
      emit(('static ABC_HANDLER_CC abc_value %s(ABC_HANDLER_ARGS) {'):format(fn))
      if b.needs_run then emit('abc_run *r=abc_active_run; abc_vm *v=r->v; abc_error *e=r->e; uint32_t pc=(uint32_t)(ip-r->code); (void)v;(void)e;(void)pc;') end
      emit(('const uint8_t *p=ip,*next=ip+%s; (void)p;(void)next;(void)asp;(void)bsp;(void)csp;(void)h0;(void)h1;(void)h2;(void)h3;(void)c0;(void)c1;(void)c2;'):format(info.kind==manifest.kind.SWITCH and 'abc_instruction_length(ip)' or info.kind==manifest.kind.EXT and 'abc_instruction_length(ip)' or tostring(info.len)))
      if b.foreign then
        if s.a>0 then for j=0,s.a-1 do emit(('*asp++=h%d;'):format(j)) end end
        if s.b>0 then for j=0,s.b-1 do emit(('*bsp++=h%d;'):format(3-j)) end end
        if s.c>0 then for j=0,s.c-1 do emit(('*csp++=c%d;'):format(j)) end end
        emit('v->ca=v->cb=v->cc=0;v->na=(size_t)(asp-v->a);v->nb=(size_t)(bsp-v->b);v->nc=(size_t)(csp-v->c);abc_status status=vm_foreign(r,p,pc);if(status!=ABC_OK)return status;asp=v->a+v->na;bsp=v->b+v->nb;csp=v->c+v->nc;h0=h1=h2=h3=c0=c1=c2=0;ip=next;ABC_HANDLER_TAIL return T_a0b0c0[*ip](ABC_HANDLER_PASS);')
      elseif b.dynamic_ext then
        if s.a>0 then for j=0,s.a-1 do emit(('*asp++=h%d;'):format(j)) end end
        if s.b>0 then for j=0,s.b-1 do emit(('*bsp++=h%d;'):format(3-j)) end end
        if s.c>0 then for j=0,s.c-1 do emit(('*csp++=c%d;'):format(j)) end end
        emit('v->ca=v->cb=v->cc=0;v->na=(size_t)(asp-v->a);v->nb=(size_t)(bsp-v->b);v->nc=(size_t)(csp-v->c);abc_status status=vm_dynamic(r,p,pc);if(status!=ABC_OK)return status;asp=v->a+v->na;bsp=v->b+v->nb;csp=v->c+v->nc;h0=h1=h2=h3=c0=c1=c2=0;if(p[1]==EXT_DTCALL){unsigned k=abc_u32(p+5),n=p[3];abc_frame fr=v->frames[--v->nf];csp-=k+1;if(fr.to_b){for(unsigned j=0;j<n;j++)*bsp++=asp[-(int)n+(int)j];asp-=n;}next=r->code+fr.return_pc;if(!v->nf){v->na=(size_t)(asp-v->a);v->nb=(size_t)(bsp-v->b);v->nc=(size_t)(csp-v->c);r->pc=(uint32_t)(next-r->code);r->done=1;return ABC_OK;}}ip=next;ABC_HANDLER_TAIL return T_a0b0c0[*ip](ABC_HANDLER_PASS);')
      elseif b.indirect then
        emit(table.concat(b.lines,' '))
        emit(('int callee_index;abc_status resolved=vm_resolve_indirect(r,p,pc,%s,%d,&callee_index);if(resolved!=ABC_OK)return resolved;const abc_call_info *callee=&r->image->call_info[callee_index];unsigned n=p[%d],ac=%d,cc=%d;'):format(b.indirect.target,b.indirect.form,b.indirect.tail and 2 or 1,s.a,s.c))
        if b.indirect.tail then
          emit(('unsigned k=p[1];if(asp+((int)%d-(int)n)+callee->max_a>v->a+v->capacity||bsp+%d+callee->max_b>v->b+v->capacity||csp+((int)%d-(int)k)+callee->max_c>v->c+v->capacity)return abc_fail(e,ABC_STACK,pc,"stack limit reached");'):format(s.a,b.state.b,s.c))
          emit('for(unsigned j=0;j<k;j++){if(cc)cc--;else --csp;}')
        else
          emit(('if(v->nf==v->capacity||asp+((int)%d-(int)n)+callee->max_a>v->a+v->capacity||bsp+%d+callee->max_b>v->b+v->capacity||csp+%d+1+callee->max_c>v->c+v->capacity)return abc_fail(e,ABC_STACK,pc,"stack limit reached");v->frames[v->nf++]=(abc_frame){(uint32_t)(next-r->code),%d};uint64_t value=(uint32_t)(next-r->code);if(cc<3){if(cc==0)c0=value;else if(cc==1)c1=value;else c2=value;cc++;}else{*csp++=c0;c0=c1;c1=c2;c2=value;}'):format(s.a,b.state.b,s.c,b.indirect.form))
        end
        emit('for(unsigned j=0;j<n;j++){uint64_t value;if(ac){if(ac==1)value=h0;else if(ac==2)value=h1;else if(ac==3)value=h2;else value=h3;ac--;}else value=*--asp;if(cc<3){if(cc==0)c0=value;else if(cc==1)c1=value;else c2=value;cc++;}else{*csp++=c0;c0=c1;c1=c2;c2=value;}}')
        emit(('ip=r->code+r->m->functions[callee_index].entry;ABC_HANDLER_TAIL return abc_tables[(ac*5+%d)*4+cc][*ip](ABC_HANDLER_PASS);'):format(b.state.b))
      elseif b.mem_alloc or b.mem_free then
        if s.c>0 then for j=0,s.c-1 do emit(('*csp++=c%d;'):format(j)) end end
        if b.mem_alloc then emit('size_t count=(abc_u16(p+1)+7u)/8u;if(count>(size_t)((v->c+v->capacity)-csp))return abc_fail(e,ABC_STACK,pc,"frame block stack limit reached");memset(csp,0,count*8);csp+=count;')
        else emit('csp-=(abc_u16(p+1)+7u)/8u;') end
        for j=s.c,2 do emit(('c%d=0;'):format(j)) end
        emit(('ip=next;ABC_HANDLER_TAIL return T_a%db%dc0[*ip](ABC_HANDLER_PASS);'):format(s.a,s.b))
      elseif b.halt then
        if s.a>0 then for j=0,s.a-1 do emit(('*asp++=h%d;'):format(j)) end end
        if s.b>0 then for j=0,s.b-1 do emit(('*bsp++=h%d;'):format(3-j)) end end
        if s.c>0 then for j=0,s.c-1 do emit(('*csp++=c%d;'):format(j)) end end
        emit('v->ca=v->cb=v->cc=0;v->na=(size_t)(asp-v->a);v->nb=(size_t)(bsp-v->b);v->nc=(size_t)(csp-v->c);r->pc=(uint32_t)(next-r->code);r->done=1;return ABC_OK;')
      elseif b.abort then
        emit('ABORT(p[1]);')
      elseif b.cpushn then
        if s.a>0 then for j=0,s.a-1 do emit(('*asp++=h%d;'):format(j)) end end
        if s.c>0 then for j=0,s.c-1 do emit(('*csp++=c%d;'):format(j)) end end
        emit('for(unsigned j=0;j<p[1];j++)*csp++=*--asp;')
        for j=0,3-s.b do emit(('h%d=0;'):format(j)) end; for j=0,2 do emit(('c%d=0;'):format(j)) end
        emit(('ip=next;ABC_HANDLER_TAIL return T_a0b%dc0[*ip](ABC_HANDLER_PASS);'):format(s.b))
      elseif b.cgetr then
        if b.cgetr=='A' then
          if s.a>0 then for j=0,s.a-1 do emit(('*asp++=h%d;'):format(j)) end end
        else
          if s.b>0 then for j=0,s.b-1 do emit(('*bsp++=h%d;'):format(3-j)) end end
        end
        if s.c>0 then for j=0,s.c-1 do emit(('*csp++=c%d;'):format(j)) end end
        emit(('for(unsigned j=0;j<p[2];j++)*%ssp++=csp[-1-(int)p[1]-(int)j];'):format(b.cgetr:lower()))
        if b.cgetr=='A' then for j=0,3-s.b do emit(('h%d=0;'):format(j)) end else for j=4-s.a,3 do emit(('h%d=0;'):format(j)) end end
        for j=0,2 do emit(('c%d=0;'):format(j)) end
        emit(('ip=next;ABC_HANDLER_TAIL return T_a%db%dc0[*ip](ABC_HANDLER_PASS);'):format(b.cgetr=='A' and 0 or s.a,b.cgetr=='B' and 0 or s.b))
      elseif b.generic_call~=nil then
        emit('unsigned n=p[5];uint32_t target_pc=(uint32_t)((int64_t)(next-r->code)+abc_i32(p+1));uint32_t ci=r->image->direct_callees[pc];const abc_call_info *callee;if(ci)callee=&r->image->call_info[ci-1];else{const abc_function *f=abc_function_entry(r->m,target_pc);ci=(uint32_t)(f-r->m->functions)+1;r->image->direct_callees[pc]=ci;callee=&r->image->call_info[ci-1];}')
        emit(('if(v->nf==v->capacity||asp+((int)%d-(int)n)+callee->max_a>v->a+v->capacity||bsp+%d+callee->max_b>v->b+v->capacity||csp+%d+1+callee->max_c>v->c+v->capacity)return abc_fail(e,ABC_STACK,pc,"stack limit reached");'):format(s.a,s.b,s.c))
        if s.a>0 then for j=0,s.a-1 do emit(('*asp++=h%d;'):format(j)) end end
        if s.c>0 then for j=0,s.c-1 do emit(('*csp++=c%d;'):format(j)) end end
        emit(('v->frames[v->nf++]=(abc_frame){(uint32_t)(next-r->code),%d};*csp++=(uint32_t)(next-r->code);for(unsigned j=0;j<n;j++)*csp++=asp[-1-(int)j];asp-=n;if(n<=2)r->image->code[pc]=(uint8_t)(OP_CALL_%s_0+n);ip=r->code+target_pc;'):format(b.generic_call,b.generic_call==1 and 'B' or 'A'))
        for j=0,3-s.b do emit(('h%d=0;'):format(j)) end;for j=0,2 do emit(('c%d=0;'):format(j)) end
        emit(('ABC_HANDLER_TAIL return T_a0b%dc0[*ip](ABC_HANDLER_PASS);'):format(s.b))
      elseif b.generic_return then
        if s.a>0 then for j=0,s.a-1 do emit(('*asp++=h%d;'):format(j)) end end
        if s.b>0 then for j=0,s.b-1 do emit(('*bsp++=h%d;'):format(3-j)) end end
        if s.c>0 then for j=0,s.c-1 do emit(('*csp++=c%d;'):format(j)) end end
        emit('unsigned k=p[1],n=p[2];abc_frame fr=v->frames[--v->nf];csp-=k+1;if(fr.to_b){for(unsigned j=0;j<n;j++)*bsp++=asp[-(int)n+(int)j];asp-=n;}next=r->code+fr.return_pc;')
        emit('if(k<=2&&n<=2)r->image->code[pc]=(uint8_t)(OP_RET_0_0+k*3+n);')
        emit('if(!v->nf){v->ca=v->cb=v->cc=0;v->na=(size_t)(asp-v->a);v->nb=(size_t)(bsp-v->b);v->nc=(size_t)(csp-v->c);r->pc=(uint32_t)(next-r->code);r->done=1;return ABC_OK;}')
        emit('ip=next;ABC_HANDLER_TAIL return T_a0b0c0[*ip](ABC_HANDLER_PASS);')
      elseif b.generic_tail then
        emit(('size_t da=(size_t)(asp-v->a)+%d,db=(size_t)(bsp-v->b)+%d,dc=(size_t)(csp-v->c)+%d;'):format(s.a,s.b,s.c))
        emit('unsigned k=p[5],n=p[6];uint32_t target_pc=(uint32_t)((int64_t)(next-r->code)+abc_i32(p+1));const uint8_t *target=r->code+target_pc;uint32_t ci=r->image->direct_callees[pc];const abc_call_info *callee;if(ci)callee=&r->image->call_info[ci-1];else{const abc_function *f=abc_function_entry(r->m,target_pc);ci=(uint32_t)(f-r->m->functions)+1;r->image->direct_callees[pc]=ci;callee=&r->image->call_info[ci-1];}')
        emit('if(da<n||dc<k||da-n+callee->max_a>v->capacity||db+callee->max_b>v->capacity||dc-k+callee->max_c>v->capacity)return abc_fail(e,ABC_STACK,pc,"stack limit reached");')
        if s.a>0 then for j=0,s.a-1 do emit(('*asp++=h%d;'):format(j)) end end
        if s.c>0 then for j=0,s.c-1 do emit(('*csp++=c%d;'):format(j)) end end
        emit('csp-=k;for(unsigned j=0;j<n;j++)*csp++=asp[-1-(int)j];asp-=n;')
        emit('if(k<=2&&n<=2)r->image->code[pc]=(uint8_t)(OP_TCALL_0_0+k*3+n);')
        emit(('ip=target;ABC_HANDLER_TAIL return T_a0b%dc0[*ip](ABC_HANDLER_PASS);'):format(s.b))
      elseif b.ret then
        local base=builder(s)
        for _=1,b.ret.k+1 do base:pop('C',true) end
        base:line('abc_frame fr=v->frames[--v->nf]; next=r->code+fr.return_pc;')
        emit(table.concat(base.lines,' '))
        local function finish_return_path(path)
          path:forget_unused(); local z=path.state
          emit(table.concat(path.lines,' '))
          emit(('if(!v->nf) { v->ca=%d;v->cb=%d;v->cc=%d;v->na=(size_t)(asp-v->a);v->nb=(size_t)(bsp-v->b);v->nc=(size_t)(csp-v->c);v->h[0]=h0;v->h[1]=h1;v->h[2]=h2;v->h[3]=h3;v->cr[0]=c0;v->cr[1]=c1;v->cr[2]=c2;r->pc=(uint32_t)(next-r->code);r->done=1;return ABC_OK;}'):format(z.a,z.b,z.c))
          emit(('ip=next; ABC_HANDLER_TAIL return T_a%db%dc%d[*ip](ABC_HANDLER_PASS);'):format(z.a,z.b,z.c))
        end
        local keep=builder(base.state)
        emit('if(!fr.to_b) {')
        finish_return_path(keep)
        emit('}')
        local move=builder(base.state); local results={}
        for j=b.ret.r,1,-1 do results[j]=move:pop('A') end
        for j=1,b.ret.r do move:push('B',results[j]) end
        finish_return_path(move)
      else
        b:forget_unused(); emit(b:finish())
      end
      emit('}')
    end
  end
  emit(('const abc_handler T_%s[256] = {'):format(suffix))
  for _,op in ipairs(manifest.ops) do
    local fn=assert(entries[op.name],'missing generated entry '..op.name)
    emit(('[OP_%s] = %s,'):format(op.name,fn))
  end
  emit('};')
end
out=files[0]
emit('const abc_handler *const abc_tables[100] = {')
for _,s in ipairs(states) do
  local key=(s.a*5+s.b)*4+s.c
  emit(('[%d] = T_a%db%dc%d,'):format(key,s.a,s.b,s.c))
end
emit('};')
assert(header:close())
assert(os.rename(output..'/banked.h.tmp',output..'/banked.h'))
for i=0,7 do
  assert(files[i]:close())
  assert(os.rename(('%s/banked_%d.c.tmp'):format(output,i),('%s/banked_%d.c'):format(output,i)))
end

