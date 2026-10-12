-- Generate shared scalar control flow and the checked numeric conversion used
-- at object/call ABIs. There is no runtime scalar opcode dispatcher here.
local s=require('gen.semantics')
local dir=assert(arg[1])
local function output(name)
  local f=assert(io.open(dir..'/'..name,'wb'))
  return function(text)assert(f:write(text,'\n'))end,function()assert(f:close())end
end
local c,close=output('scalar_ops.h')
c('#ifndef ABC_SCALAR_OPS_H\n#define ABC_SCALAR_OPS_H')
c('/* ABI conversion only. Opcode bodies are emitted by scalar_semantics.lua. */')
c('static __attribute__((always_inline)) inline unsigned abc_scalar_convert(unsigned from,unsigned to,uint64_t x,uint64_t *out){switch(from){')
for i=3,9 do local from=s.scalar_tags[i];c('case ABC_ANY_'..from..':switch(to){')
  for j=3,9 do local to=s.scalar_tags[j];c('case ABC_ANY_'..to..':')
    for _,step in ipairs(s.scalar_conversion(from,to)) do
      local kind,op=step[1],step[2]
      if kind=='mask' then c('x&='..op..';')
      elseif kind=='unary' then c('x='..s.expr(s.unary[op],'x')..';')
      elseif kind=='check' then c('if('..s.expr(s.checks[op],'x')..')return 3;')
      elseif kind=='canonical' then c('if(float_nan_bits(x))x=UINT64_C(0x7ff8000000000000);')
      elseif op=='F2IS' or op=='F2IU' then c('if(!vm_'..op:lower()..'(x,&x))return 3;')
      else c('x=vm_'..op:lower()..'(x);') end
    end
    c('*out=x;return 0;')
  end
  c('default:return 6;}')
end
c('default:if(from==to){*out=x;return 0;}return 6;}}\n#endif');close()
local emit,done=output('symbolic_scalar_ops.inc')
require('gen.scalar_symbolic').emit(emit);done()
