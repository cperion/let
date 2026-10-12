-- Symbolic bindings for scalar_semantics.lua. These bind existing stack/cache
-- operations and residual control; instruction selection lives only in flow.
local flow=require('gen.scalar_semantics')
local M={}
function M.emit(emit)
  local b={}
  function b:emit(text) emit(text) end
  function b:begin(name)
    emit('static int scalar_'..name..'(abc_symbolic_machine *m,abc_symbolic_dynamic *effect,unsigned selected){')
    emit('abc_symbolic_context *x=m->context;uint32_t base=x->n[ABC_SYM_A]-effect->pops;const uint8_t *p=m->code+m->pc;const abc_module *module=m->module;(void)base;(void)p;(void)module;(void)selected;')
  end
  function b:close() emit('}') end
  function b:safepoint() emit('if(selected==SCALAR_ENTER&&m->emit_safepoint&&!m->emit_safepoint(m->sink,m->pc))return 0;') end
  function b:load() end -- Inputs already occupy the shared machine's A stack.
  function b:select(family,tags)
    local mask={};for _,t in ipairs(tags) do mask[#mask+1]='(1u<<'..flow.tag(t)..')' end
    emit('if(!scalar_select(m,effect,ABC_SYM_SCALAR_'..family..','..table.concat(mask,'|')..',&selected))return 0;')
  end
  function b:decode(_,i) emit(('if(!scalar_primitive(m,ABC_SYM_SCALAR_DECODE,0,&x->s[ABC_SYM_A][base+%d],NULL,NULL))return 0;'):format(i)) end
  function b:decode_selected() self:decode(nil,0) end
  function b:route_binary()
    emit('abc_symbolic_value right=abc_symbolic_pop(x,ABC_SYM_A);if(!abc_symbolic_push(x,ABC_SYM_B,right))return machine_fail(m,"scalar operand transport failed");')
  end
  function b:route_literal()
    emit('abc_symbolic_value right=abc_symbolic_constant(bits,ABC_SYM_A,(int32_t)base);if(p[6]){abc_symbolic_value swap=x->s[ABC_SYM_A][base];x->s[ABC_SYM_A][base]=right;right=swap;}if(!abc_symbolic_push(x,ABC_SYM_B,right))return machine_fail(m,"literal operand transport failed");')
  end
  function b:abort(reason) emit('return abc_symbolic_machine_abort(m,'..reason..');') end
  function b:binary(op) emit('if(!abc_symbolic_machine_binary(m,OP_'..op..'_A,ABC_SYM_A))return 0;') end
  function b:float_binary(op) emit('if(!abc_symbolic_machine_float_binary(m,OP_'..op..'_A,ABC_SYM_A))return 0;') end
  function b:pow() emit('if(!abc_symbolic_machine_pow(m,OP_POW))return 0;') end
  function b:step(step)
    local kind,op=step[1],step[2];local expression
    if kind=='mask' then expression='abc_symbolic_machine_immediate(m,OP_ANDI_A,ABC_SYM_A,'..op..')'
    elseif kind=='unary' then expression='abc_symbolic_machine_unary(m,OP_'..op..'_A,ABC_SYM_A)'
    elseif kind=='float_unary' then expression='abc_symbolic_machine_float_unary(m,OP_'..op..')'
    elseif kind=='check' then expression='abc_symbolic_machine_check(m,OP_'..op..')'
    elseif kind=='canonical' then expression='scalar_primitive(m,ABC_SYM_SCALAR_CANONICAL,0,abc_symbolic_top(x,ABC_SYM_A,0),NULL,NULL)'
    else error(kind) end
    emit('if(!'..expression..')return 0;')
  end
  function b:eq_zero() emit('if(!abc_symbolic_machine_push(m,ABC_SYM_B,0))return 0;');self:binary('EQ') end
  function b:special_binary(op)
    emit('abc_symbolic_value result;if(!scalar_primitive(m,ABC_SYM_SCALAR_'..op..',0,abc_symbolic_top(x,ABC_SYM_A,0),abc_symbolic_top(x,ABC_SYM_B,0),&result))return 0;(void)abc_symbolic_pop(x,ABC_SYM_B);*abc_symbolic_top(x,ABC_SYM_A,0)=result;')
  end
  function b:string_equal() self:special_binary('STRING_EQ') end
  function b:mixed_equal() self:special_binary('MIXED_EQ') end
  function b:finish(pops,kind,t,preserve)
    if kind~='none' then
      emit('effect->result[0]=*abc_symbolic_top(x,ABC_SYM_A,0);effect->result[0].dst_stack=ABC_SYM_A;effect->result[0].dst_home=(int32_t)base;')
      if kind=='raw' then emit('abc_symbolic_forget_dynamic(&effect->result[0]);')
      elseif kind=='any' then
        local tag=flow.tag(t)
        if preserve then emit('int fits=abc_symbolic_dynamic_box_specialization(module,di,effect->result[0]);') end
        emit('effect->result[0].dynamic_tags=(1u<<'..tag..');effect->result[0].dynamic_repr=ABC_SYM_REPR_RAW;effect->result[0].dynamic_width='..(preserve and 'fits?' or '')..'abc_numeric_width('..tag..')'..(preserve and ':0' or '')..';effect->result[0].zero_extended=0;')
      end
    end
    if pops==2 then emit('if(x->n[ABC_SYM_A]==base+1&&!abc_symbolic_push(x,ABC_SYM_A,abc_symbolic_constant(0,ABC_SYM_A,(int32_t)base+1)))return machine_fail(m,"scalar input shape restoration failed");') end
    emit('return 1;')
  end
  function b:constant(value,_,t)
    emit('effect->result[0]=abc_symbolic_constant('..value..',ABC_SYM_A,(int32_t)base);')
    if t then emit('effect->result[0].dynamic_tags=(1u<<'..flow.tag(t)..');effect->result[0].dynamic_repr=ABC_SYM_REPR_ENCODED;') end
    emit('return 1;')
  end
  function b:test_descriptor() emit('abc_symbolic_value predicate;if(!scalar_test(m,di,&x->s[ABC_SYM_A][base],&predicate))return 0;') end
  function b:finish_test() emit('effect->result[0]=predicate;return 1;') end
  function b:require_test(reason) emit('if(!abc_symbolic_machine_require(m,&predicate,'..reason..'))return 0;') end
  function b:unbox() emit('return scalar_primitive(m,ABC_SYM_SCALAR_UNBOX,di,&x->s[ABC_SYM_A][base],NULL,effect->result);') end
  function b:effect() emit('return scalar_effect(m,effect);') end
  for _,name in ipairs(flow.names) do flow.emit(b,name) end
  emit('static int scalar_instruction(const abc_module *module,const abc_symbolic_dynamic *effect){(void)module;switch(effect->selector){')
  for _,name in ipairs(flow.names) do emit('case EXT_'..name..':') end
  emit('return 1;default:return 0;}}')
  emit('int abc_symbolic_scalar_arm(abc_symbolic_machine *m,abc_symbolic_dynamic *effect,unsigned selected,abc_symbolic_value *out){(void)out;switch(effect->selector){')
  for _,name in ipairs(flow.names) do emit('case EXT_'..name..':return scalar_'..name..'(m,effect,selected);') end
  emit('default:return machine_fail(m,"unclassified scalar instruction");}}')
  emit('static int scalar_dispatch(abc_symbolic_machine *m,abc_symbolic_dynamic *effect){return abc_symbolic_scalar_arm(m,effect,SCALAR_ENTER,effect->result);}')
end
return M
