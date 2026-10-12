-- One scalar computation. Backends bind control, representation and ordinary
-- typed operations; they do not select language operations or own EXT cases.
local s=require('gen.semantics')
local M={names={},bodies={}}
local ints={'U8','U16','U32','U64','I32','I64'}
local nums={'U8','U16','U32','U64','I32','I64','F64'}
local function tag(t) return type(t)=='number' and tostring(t) or 'ABC_ANY_'..t end
M.tag=tag
local function define(name,body) M.names[#M.names+1]=name;M.bodies[name]=body end
local function cases(b,expr,tags,body,otherwise)
  b:emit('switch('..expr..'){')
  for _,t in ipairs(tags) do b:emit('case '..tag(t)..':{');body(t);b:emit('}') end
  b:emit('default:{');if otherwise then otherwise() else b:abort(6) end;b:emit('}}')
end
local function choose(b,family,tags,body,otherwise)
  b:select(family,tags)
  cases(b,'selected',tags,body,otherwise)
end
local function normalize(b,t) for _,step in ipairs(s.scalar_normalization(t)) do b:step(step) end end
local function arithmetic(b,name,t)
  local ops=s.scalar_binary[name]
  if t=='F64' then b:float_binary(assert(ops[3]))
  elseif ops[1]=='POW' then b:pow()
  else b:binary(ops[(t=='I32' or t=='I64') and 2 or 1]) end
  if name~='DLT' and name~='DLE' then normalize(b,t) end
end
local function layout(b)
  b:emit('unsigned di=abc_u32(p+2);const abc_descriptor *descriptor=&module->descriptors[di];abc_any_layout layout=abc_any_descriptor_layout(descriptor);')
end
local function identity(b)
  b:load(1)
  b:emit('if(layout.tag==255){');b:finish(1,'keep');b:emit('}')
  choose(b,'UNARY',{'WORD'},function() b:finish(1,'keep') end)
end
define('ANY_BOX',function(b)
  layout(b)
  b:emit('if(layout.form==ABC_ANY_LAYOUT_IDENTITY){');identity(b);b:emit('}')
  b:emit('if(layout.form==ABC_ANY_LAYOUT_SCALAR&&descriptor->tag==ABC_DESC_PRIMITIVE){')
  cases(b,'layout.tag',s.scalar_tags,function(t)
    if t=='UNIT' then b:constant('immediate(ABC_ANY_UNIT,0)',0,'UNIT')
    else b:load(1);b:finish(1,'any',t,true) end
  end)
  b:emit('}')
  b:effect()
end)
define('ANY_IS',function(b)
  layout(b);b:emit('if(!layout.form){');b:abort(6);b:emit('}')
  b:load(1);b:test_descriptor();b:finish_test()
end)
define('ANY_CAST',function(b)
  layout(b);b:emit('if(!layout.form){');b:abort(6);b:emit('}')
  b:emit('if(layout.form==ABC_ANY_LAYOUT_IDENTITY){');identity(b);b:emit('}')
  b:load(1)
  b:emit('if(layout.form==ABC_ANY_LAYOUT_OBJECT){')
  b:test_descriptor();b:require_test(6);b:unbox();b:emit('}')
  local targets={'UNIT','BOOL','U8','U16','U32','U64','I32','I64','F64','PTR'}
  cases(b,'layout.tag',targets,function(to)
    local numeric=to~='UNIT' and to~='BOOL' and to~='PTR'
    choose(b,'UNARY',numeric and nums or {to},function(from)
      if to=='UNIT' then b:finish(1,'none')
      else
        b:decode(from,0)
        if numeric then for _,step in ipairs(s.scalar_conversion(from,to)) do b:step(step) end end
        b:finish(1,'raw')
      end
    end)
  end)
end)
for _,name in ipairs(s.scalar_binary_order) do
  define(name,function(b)
    b:load(2)
    choose(b,'NUMERIC',s.scalar_binary[name][3] and nums or ints,function(t)
      b:decode(t,0);b:decode(t,1);b:route_binary()
      arithmetic(b,name,t)
      b:finish(2,(name=='DLT' or name=='DLE') and 'raw' or 'any',t)
    end)
  end)
end
for _,name in ipairs(s.scalar_unary_order) do
  define(name,function(b)
    local bool=name=='DLNOT' or name=='DREQUIRE_BOOL'
    b:load(1)
    choose(b,'UNARY',bool and {'BOOL'} or s.scalar_unary[name][2] and nums or ints,function(t)
      b:decode(t,0)
      if name=='DLNOT' then b:eq_zero()
      elseif name~='DREQUIRE_BOOL' then
        if t=='F64' then b:step{'float_unary','FNEG'} else b:step{'unary',s.scalar_unary[name][1]};normalize(b,t) end
      end
      b:finish(1,bool and 'raw' or 'any',t)
    end)
  end)
end
for _,name in ipairs{'DEQ','DNE'} do
  define(name,function(b)
    b:load(2)
    choose(b,'EQUALITY',{'UNIT','BOOL','U8','I32','F64','STRING','PTR','WORD','CLOSURE','AGGREGATE',14,15},function(t)
      if t==14 or t==15 then b:decode(t==14 and 'I64' or 'U64',0);b:decode(t==14 and 'U64' or 'I64',1)
      elseif t~='STRING' and t~='WORD' and t~='CLOSURE' and t~='AGGREGATE' then b:decode(t,0);b:decode(t,1) end
      b:route_binary()
      if t=='F64' then b:float_binary('FEQ')
      elseif t=='STRING' then b:string_equal()
      elseif t==14 or t==15 then b:mixed_equal()
      else b:binary('EQ') end
      if name=='DNE' then b:step{'unary','LNOT'} end
      b:finish(2,'raw')
    end,function() b:constant(name=='DNE' and '1' or '0',2) end)
  end)
end
for i=1,12 do local name=s.scalar_binary_order[i]
  define(name..'L',function(b)
    b:load(1)
    b:select('UNARY',nums)
    b:emit('if(selected<ABC_ANY_U8||selected>ABC_ANY_F64){');b:abort(6);b:emit('}')
    b:emit('const abc_dynamic_constant *literal=&module->dynamic_constants[abc_u32(p+2)];unsigned literal_tag=abc_primitive_tag(literal->kind);uint64_t bits=0;memcpy(&bits,literal->payload,literal->length);')
    b:emit('if(!abc_scalar_literal(selected,&literal_tag,&bits,literal->flags&1)){');b:abort(6);b:emit('}')
    b:emit('unsigned result_tag=abc_scalar_promote(selected,literal_tag,'..(s.scalar_binary[name][3] and '1' or '0')..');')
    b:decode_selected();b:route_literal()
    cases(b,'result_tag',s.scalar_binary[name][3] and nums or ints,function(t)
      arithmetic(b,name,t);b:finish(1,'any',t)
    end)
  end)
end
function M.emit(b,name)
  b:begin(name);b:safepoint();M.bodies[name](b);b:close()
end
return M
