-- Exact pointer-free ABI transport. This copies representations; it never computes
-- source operations. Images own their bytes and contain no VM/session addresses.
local S=require('let.schema')
local Layout=require('let.layout')
local D=require('let.diag')
local ffi=require('let.abi')
local M={}
local function contract(ty)
 if not Layout.pointerFree(ty) or Layout.abiComponents(ty)==false then
  D.reject('static-transport','No durable pointer-free transport for '..S.display(ty))
 end
 return Layout.layout(ty)
end
M.contract=contract
local function cellBytes(cell)
 local data=ffi.new('uint64_t[1]',cell)
 return ffi.string(data,8)
end
-- Visit ABI cells in source order, carrying their byte range within an image.
local function ranges(ty,base,visit)
 local item=Layout.layout(ty)
 if ty==S.Unit then return end
 if ty:isRecord() then
  for _,field in ipairs(ty.fields) do ranges(field.type,base+item.fields[field.name].offset,visit) end
 elseif ty:isArray() then
  for index=0,ty.length-1 do ranges(ty.element,base+index*item.stride,visit) end
 elseif ty:isTaggedType() then
  for index=0,math.floor((item.size+7)/8)-1 do visit(S.U64,base+index*8,math.min(8,item.size-index*8)) end
 else visit(ty,base,item.size) end
end
M.ranges=ranges
function M.fromCells(ty,cells,first)
 local item=contract(ty);first=first or 1
 local bytes=ffi.new('uint8_t[?]',math.max(1,item.size))
 ranges(ty,0,function(_,offset,size)
  if cells[first]==nil then D.bug('static-results','Missing aggregate result cell') end
  ffi.copy(bytes+offset,cellBytes(cells[first]),size);first=first+1
 end)
 return {type=ty,image=ffi.string(bytes,item.size)},first
end
function M.cells(snapshot)
 local item=contract(snapshot.type)
 if type(snapshot.image)~='string' or #snapshot.image~=item.size then
  D.reject('static-argument','Snapshot bytes disagree with their typed layout')
 end
 local cells={}
 ranges(snapshot.type,0,function(ty,offset,size)
  local word=ffi.new('uint64_t[1]')
  ffi.copy(word,snapshot.image:sub(offset+1,offset+size),size)
  -- Sign extension is part of the integer ABI representation, not a source cast.
  if ty:isInteger() and ty:isSigned() and size<8 then
   local signed=ffi.cast('int'..(size*8)..'_t *',word)[0]
   word[0]=ffi.cast('uint64_t',ffi.cast('int64_t',signed))
  end
  cells[#cells+1]=ffi.new('uint64_t',word[0])
 end)
 return cells
end
return M
