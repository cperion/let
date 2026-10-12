-- Concrete bindings for the shared control-flow definition. No EXT semantics
-- or opcode-family dispatch belongs here.
local flow=require('gen.scalar_semantics')
local s=require('gen.semantics')
local M={}
local function emit_body(emit,builder,state,name,effect_handler)
  local b={}
  function b:emit(text) emit(text) end
  function b:publish()
    for i=0,state.a-1 do emit(('asp[%d]=h%d;'):format(i,i)) end
    for i=0,state.b-1 do emit(('bsp[%d]=h%d;'):format(i,3-i)) end
    for i=0,state.c-1 do emit(('csp[%d]=c%d;'):format(i,i)) end
  end
  function b:begin()
    emit('{const abc_module *module=r->m;uint64_t x=0,y=0;unsigned selected=0;(void)module;(void)x;(void)y;(void)selected;')
  end
  function b:close() emit('}') end
  function b:safepoint()
    emit('if(atomic_load(&v->collection_requested)){')
    self:publish()
    emit(('v->ca=v->cb=v->cc=0;v->na=(size_t)(asp-v->a)+%d;v->nb=(size_t)(bsp-v->b)+%d;v->nc=(size_t)(csp-v->c)+%d;abc_dynamic_collect(v);v->na=v->nb=v->nc=0;}'):format(state.a,state.b,state.c))
  end
  function b:load(n)
    local p=builder(state);emit('x='..p:peek('A',n-1)..';')
    if n==2 then emit('y='..p:peek('A',0)..';') end
  end
  function b:select(family,tags)
    local tagx='abc_repr_tag(v->dynamic,x,gc_heap_contains)'
    local tagy='abc_repr_tag(v->dynamic,y,gc_heap_contains)'
    if family=='UNARY' then emit('selected='..tagx..';')
    elseif family=='EQUALITY' then emit('selected=abc_scalar_equality_kind('..tagx..','..tagy..');')
    else local floating=0;for _,t in ipairs(tags) do if t=='F64' then floating=1 end end
      emit(('selected=abc_scalar_promote(%s,%s,%d);'):format(tagx,tagy,floating)) end
  end
  function b:decode(t,i) local v=i==0 and 'x' or 'y';emit(v..'=abc_repr_bits('..v..','..flow.tag(t)..');') end
  function b:decode_selected() emit('x=abc_repr_bits(x,selected);') end
  function b:route_binary() end -- x/y already bind the two ABC operands.
  function b:route_literal() emit('y=bits;if(p[6]){uint64_t swap=x;x=y;y=swap;}') end
  function b:abort(reason) emit('ABORT('..reason..');') end
  function b:binary(op)
    if op:match('^DIV') or op:match('^REM') then emit('if(!y){');self:abort(1);emit('}') end
    emit('x='..s.expr(s.binary[op],'x','y')..';')
  end
  function b:float_binary(op) emit('x='..s.expr(s.float_binary[op],'x','y')..';') end
  function b:pow() emit('x=vm_pow(x,y);') end
  function b:step(step)
    local kind,op=step[1],step[2]
    if kind=='mask' then emit('x&='..op..';')
    elseif kind=='unary' then emit('x='..s.expr(s.unary[op],'x')..';')
    elseif kind=='check' then emit('if('..s.expr(s.checks[op],'x')..'){');self:abort(3);emit('}')
    elseif kind=='canonical' then emit('if(float_nan_bits(x))x=UINT64_C(0x7ff8000000000000);')
    elseif op=='FNEG' then emit('x^=UINT64_C(0x8000000000000000);')
    elseif op=='F2IS' or op=='F2IU' then emit('if(!vm_'..op:lower()..'(x,&x)){');self:abort(3);emit('}')
    else emit('x=vm_'..op:lower()..'(x);') end
  end
  function b:eq_zero() emit('x=x==0;') end
  function b:string_equal() emit('x=abc_repr_string_equal(x,y);') end
  function b:mixed_equal() emit('x=abc_scalar_mixed_equal(x,y);') end
  function b:commit(pops,values)
    local cache=builder(state)
    for _=1,pops do cache:pop('A',true) end
    for _,value in ipairs(values) do cache:push('A',value) end
    cache:forget_unused();emit(cache:finish())
  end
  function b:finish(pops,kind,t,preserve)
    if kind=='any' then
      local tag=flow.tag(t)
      if t=='F64' then emit('x=encode_float(x);')
      elseif not preserve and (t=='U8' or t=='U16' or t=='U32' or t=='I32') then emit('x=immediate('..tag..',x);')
      else
        emit('if(abc_repr_fits('..tag..',x))x=immediate('..tag..',x);else{');self:publish()
        emit(('x=vm_scalar_allocate(asp+%d,bsp+%d,csp+%d,%s,x);if(!x)return abc_fail(e,ABC_NOMEM,pc,"scalar allocation failed");}'):format(state.a,state.b,state.c,tag))
      end
    end
    self:commit(pops,kind=='none' and {} or {'x'})
  end
  function b:constant(value,pops) emit('x='..value..';');self:finish(pops,'raw') end
  function b:test_descriptor()
    emit('unsigned actual=abc_repr_tag(v->dynamic,x,gc_heap_contains);unsigned predicate=layout.tag==255||actual==layout.tag;')
    emit('if(layout.form==ABC_ANY_LAYOUT_OBJECT){abc_object *object=abc_repr_object(v->dynamic,x,gc_heap_contains);predicate=object&&object->kind==layout.object_kind&&(!layout.exact_descriptor||object->descriptor==di);}')
  end
  function b:finish_test() emit('x=predicate;');self:finish(1,'raw') end
  function b:require_test(reason) emit('if(!predicate){');self:abort(reason);emit('}') end
  function b:unbox()
    emit('const uint8_t *address=(const uint8_t *)(uintptr_t)x;x=layout.address?(uint64_t)(uintptr_t)(address+layout.offset[0]):abc_u64(address+layout.offset[0]);if(layout.cells==2){y=layout.width[1]==4?abc_u32(address+layout.offset[1]):abc_u64(address+layout.offset[1]);')
    self:commit(1,{'x','y'});emit('}else{');self:commit(1,{'x'});emit('}')
  end
  function b:effect() emit('ABC_HANDLER_TAIL return '..effect_handler..'(ABC_HANDLER_PASS);') end
  flow.emit(b,name)
end
-- Ordinary extended-opcode dispatch: each selector has its own typed-handler
-- continuation site, just like a core opcode. No observations or quickening.
function M.emit_handlers(emit,builder,state,entry)
  local manifest=require('tools.opcodes');local lengths={}
  for _,op in ipairs(manifest.ext_ops) do lengths[op.name]=op.len end
  emit('static ABC_HANDLER_CC abc_value '..entry..'_effect(ABC_HANDLER_ARGS);')
  for _,name in ipairs(flow.names) do
    emit('static ABC_HANDLER_CC abc_value '..entry..'_'..name..'(ABC_HANDLER_ARGS){')
    emit('abc_run *r=abc_active_run;abc_vm *v=r->v;abc_error *e=r->e;uint32_t pc=(uint32_t)(ip-r->code);(void)v;(void)e;(void)pc;')
    emit(('const uint8_t *p=ip,*next=ip+%d;(void)p;(void)next;(void)asp;(void)bsp;(void)csp;(void)h0;(void)h1;(void)h2;(void)h3;(void)c0;(void)c1;(void)c2;'):format(lengths[name]))
    emit_body(emit,builder,state,name,entry..'_effect');emit('}')
  end
  emit('static ABC_HANDLER_CC abc_value '..entry..'(ABC_HANDLER_ARGS){')
  emit('static const abc_handler selectors[]={')
  for _,op in ipairs(manifest.ext_ops) do emit(entry..(flow.bodies[op.name] and '_'..op.name or '_effect')..',') end
  emit('};ABC_HANDLER_TAIL return selectors[ip[1]](ABC_HANDLER_PASS);}')
end
return M
