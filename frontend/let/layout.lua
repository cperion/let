-- Physical layouts consume an admitted program contract, not source types alone.
-- Pointer-free snapshots use scalar below; only program() selects reference layout.
local S=require('let.schema')
local D=require('let.diag')
local M={}
local Layout={};Layout.__index=Layout
local function unsupported(what) D.todo('abc-lowering','ABC lowering is not implemented for '..what) end
function M.pointerFree(ty,seen)
 if ty==S.Unit or ty:isInteger() or ty==S.Bool or ty==S.F64 then return true end
 seen=seen or {};if seen[ty] then return true end;seen[ty]=true
 if ty:isRecord() then
  for _,field in ipairs(ty.fields) do if not M.pointerFree(field.type,seen) then return false end end
  return true
 end
 if ty:isArray() then return M.pointerFree(ty.element,seen) end
 if ty:isTaggedType() then
  for _,field in ipairs(S.alternatives(ty)) do if not M.pointerFree(field.type,seen) then return false end end
  return true
 end
 return false
end
function M.align(value,boundary) return math.floor((value+boundary-1)/boundary)*boundary end
local function reference(self)
 if not self.reference then D.bug('layout-contract','Reference layout requires an admitted program') end
 return self.reference
end
function Layout:cellKind(ty)
 if ty==S.Unit then return nil end
 if ty:isInteger() or ty==S.Bool then return 'i' end
 if ty==S.F64 then return 'f' end
 if ty:isRef() then return reference(self).kind end
 if ty:isPtr() then return 'a' end
 return false
end
function Layout:valueComponents(ty)
 local kind=self:cellKind(ty)
 if kind then return {ty} end
 if ty:isRef() then return {S.Ptr(S.Unit),S.Ptr(S.Unit)} end
 if ty==S.Unit then return {} end
 if ty:isSlice() then local parts=self:valueComponents(S.Ref(ty.element));parts[#parts+1]=S.U32;return parts end
 if ty:isView() then local r=reference(self);return r.size==16 and {S.Ptr(S.Unit),S.Ptr(S.Unit),S.Ptr(S.Unit)} or {S.Ptr(S.Unit),S.Ptr(S.Unit)} end
 local result={}
 if ty:isRecord() then
  for _,field in ipairs(ty.fields) do
   local parts=self.packedAddresses and self:abiComponents(field.type) or self:valueComponents(field.type);if parts==false then return false end
   for _,part in ipairs(parts) do result[#result+1]=part end
  end
  return result
 end
 if ty:isArray() then
  local parts=self.packedAddresses and self:abiComponents(ty.element) or self:valueComponents(ty.element);if parts==false then return false end
  for _=1,ty.length do for _,part in ipairs(parts) do result[#result+1]=part end end
  return result
 end
 return false
end
function Layout:layout(ty,seen)
 if ty==S.Unit then return {size=0,align=1} end
 if ty==S.Bool or ty==S.U8 then return {size=1,align=1} end
 if ty==S.U16 then return {size=2,align=2} end
 if ty==S.U32 or ty==S.I32 then return {size=4,align=4} end
 if ty:isRef() then return reference(self) end
 if ty==S.U64 or ty==S.I64 or ty==S.F64 or ty:isPtr() then return {size=8,align=8} end
 if ty:isSlice() then local r=reference(self);return {size=r.size+8,align=8,fields={data={offset=0,type=S.Ref(ty.element)},length={offset=r.size,type=S.U32}}} end
 if ty:isView() then local r=reference(self);return {size=r.size+8,align=8,fields={code={offset=0,type=S.Ptr(S.Unit)},environment={offset=8,type=S.Ref(S.Unit)}}} end
 seen=seen or {};if seen[ty] then unsupported('recursive by-value layout '..S.display(ty)) end;seen[ty]=true
 if ty:isRecord() then
  local result={size=0,align=1,fields={}}
  for _,field in ipairs(ty.fields) do
   local item=self:layout(field.type,seen);result.size=M.align(result.size,item.align)
   result.fields[field.name]={offset=result.size,type=field.type,layout=item}
   result.size=result.size+item.size;if item.align>result.align then result.align=item.align end
  end
  result.size=M.align(result.size,result.align);seen[ty]=nil;return result
 end
 if ty:isArray() then
  local item=self:layout(ty.element,seen);local stride=M.align(item.size,item.align);seen[ty]=nil
  return {size=stride*ty.length,align=item.align,element=item,stride=stride}
 end
 if ty:isTaggedType() then
  local result={align=4,tags={},payloads={}};local payloadSize=0
  for index,case in ipairs(S.alternatives(ty)) do
   local item=self:layout(case.type,seen);result.tags[case.name]=index-1
   result.payloads[case.name]={type=case.type,layout=item}
   if item.align>result.align then result.align=item.align end
   if item.size>payloadSize then payloadSize=item.size end
  end
  result.payloadOffset=M.align(4,result.align)
  for _,payload in pairs(result.payloads) do payload.offset=result.payloadOffset end
  result.size=M.align(result.payloadOffset+payloadSize,result.align);seen[ty]=nil;return result
 end
 seen[ty]=nil;unsupported('layout of type '..S.display(ty))
end
function Layout:abiComponents(ty)
 local components=self:valueComponents(ty)
 if components~=false then return components end
 if ty:isTaggedType() then
  if not self.packedAddresses and not M.pointerFree(ty) then unsupported('aggregate call ABI with managed or address-bearing sum '..S.display(ty)) end
  local result={};for _=1,math.floor((self:layout(ty).size+7)/8) do result[#result+1]=S.U64 end
  return result
 end
 return false
end
function Layout:cellKinds(ty)
 local components=self:abiComponents(ty);if components==false then return false end
 local result={};for _,component in ipairs(components) do result[#result+1]=self:cellKind(component) end
 return result
end
M.scalar=setmetatable({},Layout)
function M.program(program)
 assert(program.phase=='checked-program','layout needs a checked program')
 local owning=false
 for _,fn in ipairs(program.functions) do if #program.ownership[fn.id].summary.counted>0 then owning=true end end
 local materialize=owning
 if not materialize then
  local Walk,Ownership=require('let.walk'),require('let.ownership');local seen={}
  local function needs(ty)
   if seen[ty] then return end;seen[ty]=true
   if ty:isTaggedType() and Ownership.checkedAccess(ty) then materialize=true
   elseif ty:isRecord() then for _,f in ipairs(ty.fields) do needs(f.type) end
   elseif ty:isArray() then needs(ty.element)
   elseif ty:isOwned() then needs(ty.environment) end
   -- Raw pointer/reference targets and callable signatures are not embedded
   -- values. Actual payload reads/arguments expose their own types in the IR.
  end
  for _,fn in ipairs(program.functions) do
   for _,input in ipairs(fn.inputs) do needs(input.type) end
   for _,ty in ipairs(fn.results) do needs(ty) end
   Walk.walk(fn,{enter=function(node)
    if materialize or S.Ty.V:isclassof(node) then return false end
    if S.Ir.Expr:isclassof(node) or node.kind=='Var' or node.kind=='Let' or node.kind=='Read' or node.kind=='View' or node.kind=='ConstructVariant' then needs(node.type)
    elseif node.kind=='Switch' or node.kind=='VariantMatches' or node.kind=='VariantPayload' then needs(node.sum) end
   end})
  end
 end
 return setmetatable({program=program,owning=owning,materialize=materialize,reference={kind=not owning and 'a' or false,size=owning and 16 or 8,align=8}},Layout)
end
function M.physical(program)
 assert(program.phase=='physical-program','physical layout needs a materialized program')
 -- Ownership is explicit in concrete records and operations. Remaining View
 -- cells transport borrowed code/environment addresses, not another holding.
 return setmetatable({program=program,packedAddresses=true,reference={kind='a',size=8,align=8}},Layout)
end
return M
