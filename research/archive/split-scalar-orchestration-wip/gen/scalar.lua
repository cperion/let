-- Expand shared scalar recipes into concrete expressions and symbolic ABC
-- operations. This is source generation, not a residual IR or runtime VM.
local root=(arg[0]:match('^(.*)/[^/]+$') or '.')
package.path=root..'/?.lua;'..package.path
local s=require('semantics')
local dir=assert(arg[1])
local function output(name)
  local f=assert(io.open(dir..'/'..name,'wb'))
  return function(text)assert(f:write(text,'\n'))end,function()assert(f:close())end
end
local c,close=output('scalar_ops.h')
c('#ifndef ABC_SCALAR_OPS_H\n#define ABC_SCALAR_OPS_H')
c('/* Generated from gen/semantics.lua. All concrete bodies inline in banked handlers. */')
c('#define SCALAR_INLINE static __attribute__((always_inline)) inline')
local function concrete_step(step)
  local kind,op=step[1],step[2]
  if kind=='mask' then return 'x&='..op..';'
  elseif kind=='unary' then return 'x='..s.expr(s.unary[op],'x')..';'
  elseif kind=='check' then return 'if('..s.expr(s.checks[op],'x')..')return 3;'
  elseif kind=='canonical' then return 'if(float_nan_bits(x))x=UINT64_C(0x7ff8000000000000);'
  elseif op=='F2IS' or op=='F2IU' then return 'if(!vm_'..op:lower()..'(x,&x))return 3;'
  else return 'x=vm_'..op:lower()..'(x);' end
end
local function symbolic_step(step)
  local kind,op=step[1],step[2]
  if kind=='mask' then return 'abc_symbolic_machine_immediate(m,OP_ANDI_A,ABC_SYM_A,'..op..')'
  elseif kind=='unary' then return 'abc_symbolic_machine_unary(m,OP_'..op..'_A,ABC_SYM_A)'
  elseif kind=='check' then return 'abc_symbolic_machine_check(m,OP_'..op..')'
  elseif kind=='canonical' then return 'scalar_primitive(m,ABC_SYM_SCALAR_CANONICAL,0,abc_symbolic_top(m->context,ABC_SYM_A,0),NULL,NULL)'
  else return 'abc_symbolic_machine_float_unary(m,OP_'..op..')' end
end
c('SCALAR_INLINE uint64_t abc_scalar_normalize(unsigned tag,uint64_t x){switch(tag){')
for _,tag in ipairs(s.scalar_tags) do
  local steps=s.scalar_normalization(tag)
  if #steps>0 then c('case ABC_ANY_'..tag..':');for _,step in ipairs(steps) do c(concrete_step(step)) end;c('break;') end
end
c('default:break;}return x;}')
c('SCALAR_INLINE unsigned abc_scalar_binary_bits(unsigned selector,unsigned tag,uint64_t x,uint64_t y,uint64_t *out){switch(selector){')
for _,name in ipairs(s.scalar_binary_order) do
  local ops=s.scalar_binary[name]
  c('case EXT_'..name..':')
  if ops[3] then c('if(tag==ABC_ANY_F64){*out='..s.expr(s.float_binary[ops[3]],'x','y')..';return 0;}') end
  if name=='DDIV' or name=='DREM' then c('if(!y)return 1;') end
  local function expr(op)return op=='POW' and 'vm_pow(x,y)' or s.expr(s.binary[op],'x','y')end
  c('*out='..(ops[1]==ops[2] and expr(ops[1]) or '(abc_numeric_signed(tag)?('..expr(ops[2])..'):('..expr(ops[1])..'))')..';')
  if name~='DLT' and name~='DLE' then c('*out=abc_scalar_normalize(tag,*out);') end
  c('return 0;')
end
c('default:return 6;}}')
c('SCALAR_INLINE unsigned abc_scalar_convert(unsigned from,unsigned to,uint64_t x,uint64_t *out){switch(from){')
for i=3,9 do local from=s.scalar_tags[i];c('case ABC_ANY_'..from..':switch(to){')
  for j=3,9 do local to=s.scalar_tags[j];c('case ABC_ANY_'..to..':')
    for _,step in ipairs(s.scalar_conversion(from,to)) do c(concrete_step(step)) end
    c('*out=x;return 0;')
  end
  c('default:return 6;}')
end
c('default:if(from==to){*out=x;return 0;}return 6;}}')
c('SCALAR_INLINE unsigned abc_scalar_unary_bits(unsigned selector,unsigned tag,uint64_t x,uint64_t *out){switch(selector){')
for _,name in ipairs(s.scalar_unary_order) do
  local ops=s.scalar_unary[name];c('case EXT_'..name..':')
  if name=='DLNOT' or name=='DREQUIRE_BOOL' then c('if(tag!=ABC_ANY_BOOL)return 6;*out='..(name=='DLNOT' and 'x==0' or 'x')..';return 0;')
  else
    if ops[2] then c('if(tag==ABC_ANY_F64){*out=x^UINT64_C(0x8000000000000000);return 0;}') end
    c('if(!abc_numeric_integer(tag))return 6;*out=abc_scalar_normalize(tag,'..s.expr(s.unary[ops[1]],'x')..');return 0;')
  end
end
c('default:return 6;}}')
c('#undef SCALAR_INLINE\n#endif');close()
local y,done=output('symbolic_scalar_ops.inc')
y('/* Generated typed compositions; no native register/stencil identities. */')
y('static int scalar_normalize(abc_symbolic_machine *m,unsigned tag){switch(tag){')
for _,tag in ipairs(s.scalar_tags) do local steps=s.scalar_normalization(tag)
  if #steps>0 then y('case ABC_ANY_'..tag..':return '..(function()local a={}for _,step in ipairs(steps)do a[#a+1]=symbolic_step(step)end;return table.concat(a,'&&')end)()..';') end
end
y('default:return 1;}}')
y('static int scalar_binary(abc_symbolic_machine *m,unsigned selector,unsigned tag){int ok;switch(selector){')
for _,name in ipairs(s.scalar_binary_order) do
  local ops=s.scalar_binary[name];y('case EXT_'..name..':')
  if ops[3] then y('if(tag==ABC_ANY_F64)return abc_symbolic_machine_float_binary(m,OP_'..ops[3]..'_A,ABC_SYM_A);') end
  if ops[1]=='POW' then y('ok=abc_symbolic_machine_pow(m,OP_POW);')
  else y('ok=abc_symbolic_machine_binary(m,'..(ops[1]==ops[2] and 'OP_'..ops[1]..'_A' or 'abc_numeric_signed(tag)?OP_'..ops[2]..'_A:OP_'..ops[1]..'_A')..',ABC_SYM_A);') end
  y('return ok'..((name=='DLT' or name=='DLE') and '' or '&&scalar_normalize(m,tag)')..';')
end
y('default:return 0;}}')
y('static int scalar_convert(abc_symbolic_machine *m,unsigned from,unsigned to){switch(from){')
for i=3,9 do local from=s.scalar_tags[i];y('case ABC_ANY_'..from..':switch(to){')
  for j=3,9 do local to=s.scalar_tags[j];y('case ABC_ANY_'..to..':')
    local steps=s.scalar_conversion(from,to);local expr={}
    for _,step in ipairs(steps) do expr[#expr+1]=symbolic_step(step) end
    y('return '..(#expr==0 and '1' or table.concat(expr,'&&'))..';')
  end
  y('default:return from==to;}')
end
y('default:return from==to;}}')
y('static int scalar_unary(abc_symbolic_machine *m,unsigned selector,unsigned tag){switch(selector){')
for _,name in ipairs(s.scalar_unary_order) do local ops=s.scalar_unary[name];y('case EXT_'..name..':')
  if name=='DLNOT' then y('return abc_symbolic_machine_push(m,ABC_SYM_B,0)&&abc_symbolic_machine_binary(m,OP_EQ_A,ABC_SYM_A);')
  elseif name=='DREQUIRE_BOOL' then y('return 1;')
  else
    if ops[2] then y('if(tag==ABC_ANY_F64)return abc_symbolic_machine_float_unary(m,OP_FNEG);') end
    y('return abc_symbolic_machine_unary(m,OP_'..ops[1]..'_A,ABC_SYM_A)&&scalar_normalize(m,tag);')
  end
end
y('default:return 0;}}');done()
