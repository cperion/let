-- Authoritative typed ABC value/layout contract. Metadata only: no source evaluation.
local S=require('let.schema')
local D=require('let.diag')
local M={}
local function unsupported(what) D.todo('abc-lowering','ABC lowering is not implemented for '..what) end
function M.cellKind(ty)
 if ty==S.Unit then return nil end
 if ty:isInteger() or ty==S.Bool then return 'i' end
 if ty==S.F64 then return 'f' end
 if ty:isRef() or ty:isPtr() then return 'a' end
 return false
end
function M.valueComponents(ty)
 local kind=M.cellKind(ty)
 if kind then return {ty} end
 if ty==S.Unit then return {} end
 if ty:isSlice() then return {S.Ref(ty.element),S.U32} end
 if ty:isView() then return {S.Ptr(S.Unit),S.Ptr(S.Unit)} end
 local result={}
 if ty:isRecord() then
  for _,field in ipairs(ty.fields) do
   local parts=M.valueComponents(field.type);if parts==false then return false end
   for _,part in ipairs(parts) do result[#result+1]=part end
  end
  return result
 end
 if ty:isArray() then
  local parts=M.valueComponents(ty.element);if parts==false then return false end
  for _=1,ty.length do for _,part in ipairs(parts) do result[#result+1]=part end end
  return result
 end
 return false
end
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
function M.layout(ty,seen)
 if ty==S.Unit then return {size=0,align=1} end
 if ty==S.Bool or ty==S.U8 then return {size=1,align=1} end
 if ty==S.U16 then return {size=2,align=2} end
 if ty==S.U32 or ty==S.I32 then return {size=4,align=4} end
 if ty==S.U64 or ty==S.I64 or ty==S.F64 or ty:isRef() or ty:isPtr() then return {size=8,align=8} end
 if ty:isSlice() then return {size=16,align=8,fields={data={offset=0,type=S.Ref(ty.element)},length={offset=8,type=S.U32}}} end
 if ty:isView() then return {size=16,align=8,fields={code={offset=0,type=S.Ptr(S.Unit)},environment={offset=8,type=S.Ref(S.Unit)}}} end
 seen=seen or {};if seen[ty] then unsupported('recursive by-value layout '..S.display(ty)) end;seen[ty]=true
 if ty:isRecord() then
  local result={size=0,align=1,fields={}}
  for _,field in ipairs(ty.fields) do
   local item=M.layout(field.type,seen);result.size=M.align(result.size,item.align)
   result.fields[field.name]={offset=result.size,type=field.type,layout=item}
   result.size=result.size+item.size;if item.align>result.align then result.align=item.align end
  end
  result.size=M.align(result.size,result.align);seen[ty]=nil;return result
 end
 if ty:isArray() then
  local item=M.layout(ty.element,seen);local stride=M.align(item.size,item.align);seen[ty]=nil
  return {size=stride*ty.length,align=item.align,element=item,stride=stride}
 end
 if ty:isTaggedType() then
  local result={align=4,tags={},payloads={}};local payloadSize=0
  for index,case in ipairs(S.alternatives(ty)) do
   local item=M.layout(case.type,seen);result.tags[case.name]=index-1
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
function M.abiComponents(ty)
 local components=M.valueComponents(ty)
 if components~=false then return components end
 if ty:isTaggedType() then
  if not M.pointerFree(ty) then unsupported('aggregate call ABI with managed or address-bearing sum '..S.display(ty)) end
  local result={};for _=1,math.floor((M.layout(ty).size+7)/8) do result[#result+1]=S.U64 end
  return result
 end
 return false
end
function M.cellKinds(ty)
 local components=M.abiComponents(ty);if components==false then return false end
 local result={};for _,component in ipairs(components) do result[#result+1]=M.cellKind(component) end
 return result
end
return M
