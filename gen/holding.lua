-- Build-time holding code from compiler-selected physical layouts. No runtime
-- TypeOps bundle or field-plan table: known copy is a direct call; release code
-- is independently realized with the native runtime callback ABI.
local S=require('let.schema')
local IR=require('let.ir')
local Runtime=require('let.runtime')
local I,L=S.Ir,S.List
local M={scope_header_cells=2,scope_slot_cells=1}
local function function_(name,inputs,foreigns,emit)
 local pointer=S.Ptr(S.U64);local b=IR.builder();local body,params,args,signature={},{},{},{}
 for i=1,inputs do local v=b:valueId();params[i]=I.ValueParam(i-1,v,pointer);args[i]=b:ref(v,pointer);signature[i]=S.inValue(pointer) end
 local function call(op,arguments)
  local decl=Runtime.install(foreigns,op)
  local supplied={};for _,arg in ipairs(arguments) do supplied[#supplied+1]=I.ValueArg(arg) end
  local results={};for _ in ipairs(decl.results) do results[#results+1]=b:valueId() end
  b:emit(body,I.Call(L(results),decl.target,L(supplied)))
  if results[1] then return b:ref(results[1],decl.results[1]) end
 end
 emit(b,body,args,call);b:return_(body,{})
 return I.Fn(name,I.Body,0,L(signature),L{},L(params),L(body))
end
function M.copy(name,layout,foreigns)
 return function_(name,2,foreigns,function(b,body,args,call)
  local pointer=S.Ptr(S.U64)
  local dst,src=call('owner_data',{args[1]}),call('owner_data',{args[2]})
  local ty=layout.type
  local value=b:read(body,ty,b:ptrIndex(b:convert(src,S.Ptr(ty)),b:u32(0),ty))
  b:store(body,b:ptrIndex(b:convert(dst,S.Ptr(ty)),b:u32(0),ty),b:ref(value,ty))
  for ordinal,offset in ipairs(layout.owners) do
   assert(offset>=0 and offset%8==0 and offset+8<=layout.size,'invalid owning field')
   local held=b:read(body,pointer,b:ptrIndex(b:convert(src,S.Ptr(pointer)),b:u32(offset/8),pointer))
   call('owner_hold',{b:ref(held,pointer)})
   call('owner_commit',{args[1],b:int(S.U64,ordinal)})
  end
 end)
end
function M.release(name,layout,foreigns)
 return function_(name,1,foreigns,function(b,body,args,call)
  -- Constants specialize code, never a runtime field-plan table. The C leaf
  -- checks the committed prefix and only enqueues; the outer C loop drains.
  for ordinal,offset in ipairs(layout.owners) do
   assert(offset>=0 and offset%8==0 and offset+8<=layout.size,'invalid owning field')
   call('owner_release_field',{args[1],b:int(S.U64,offset),b:int(S.U64,ordinal)})
  end
 end)
end
return M
