-- Build-time generation of ordinary checked IR from a selected physical layout.
-- Offsets below are compiler layout facts, never a runtime holding-plan format.
-- The runtime sees only prepared operation identities and the immutable ABI layout.
local S=require('let.schema')
local IR=require('let.ir')
local Runtime=require('let.runtime')
local I,L=S.Ir,S.List
local M={scope_header_cells=2,scope_slot_cells=1}
function M.generate(name,layout,foreigns)
 local pointer=S.Ptr(S.U64)
 local function function_(suffix,inputs,emit)
  local b=IR.builder();local body,params,args,signature={},{},{},{}
  for i=1,inputs do local v=b:valueId();params[i]=I.ValueParam(i-1,v,pointer);args[i]=b:ref(v,pointer);signature[i]=S.inValue(pointer) end
  local function call(op,arguments)
   local decl=Runtime.install(foreigns,op)
   local supplied={};for _,arg in ipairs(arguments) do supplied[#supplied+1]=I.ValueArg(arg) end
   local results={};for _ in ipairs(decl.results) do results[#results+1]=b:valueId() end
   b:emit(body,I.Call(L(results),decl.target,L(supplied)))
   if results[1] then return b:ref(results[1],decl.results[1]) end
  end
  emit(b,body,args,call);b:return_(body,{})
  return I.Fn(name..suffix,I.Body,0,L(signature),L{},L(params),L(body))
 end
 local function held(b,body,data,offset)
  assert(offset%8==0,'owning cell alignment')
  local base=b:convert(data,S.Ptr(pointer))
  local value=b:read(body,pointer,b:ptrIndex(base,b:u32(offset/8),pointer))
  return b:ref(value,pointer)
 end
 local copy=function_('_copy',2,function(b,body,args,call)
  local dst,src=call('owner_data',{args[1]}),call('owner_data',{args[2]})
  local ty=layout.type
  local value=b:read(body,ty,b:ptrIndex(b:convert(src,S.Ptr(ty)),b:u32(0),ty))
  b:store(body,b:ptrIndex(b:convert(dst,S.Ptr(ty)),b:u32(0),ty),b:ref(value,ty))
  for ordinal,offset in ipairs(layout.owners) do
   call('owner_hold',{held(b,body,src,offset)})
   call('owner_commit',{args[1],b:int(S.U64,ordinal)})
  end
 end)
 local release=function_('_release',1,function(b,body,args,call)
  local data=call('owner_data',{args[1]});local initialized=call('owner_initialized',{args[1]})
  for ordinal,offset in ipairs(layout.owners) do
   local yes={};local start=#body
   call('owner_enqueue',{held(b,body,data,offset)})
   for i=start+1,#body do yes[#yes+1]=body[i] end
   for i=#body,start+1,-1 do body[i]=nil end
   b:emit(body,I.If(b:bin('Ge',initialized,b:int(S.U64,ordinal),S.Bool),L(yes),L{}))
  end
 end)
 return copy,release
end
return M
