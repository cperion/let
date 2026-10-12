-- Compiler/runtime declaration boundary. This loads generated literal metadata,
-- not the generator or any execution engine. Source foreign declarations cannot
-- introduce primitive names; the lowering builder below is their producer.
local S=require('let.schema')
local D=require('let.diag')
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*)/[^/]+$') or '.'
local declarations=assert(loadfile(path..'/../../build/generated/runtime_primitives.lua'))()
local M={catalog=declarations}
function M.reserved(name) return name:sub(1,9)=='__let_rt_' end
function M.declaration(name)
 local p=assert(declarations['__let_rt_v1_'..name],'unknown runtime primitive')
 local types={i=S.U64,a=S.Ptr(S.U64),f=S.F64};local inputs,results={},{}
 for kind in p.inputs:gmatch('.') do inputs[#inputs+1]=S.inValue(types[kind]) end
 for kind in p.results:gmatch('.') do results[#results+1]=types[kind] end
 local declaration=S.Ir.Foreign('__let_rt_v1_'..name,S.List(inputs),S.List(results))
 return declaration
end
function M.validate(declaration)
 local p=declarations[declaration.target]
 if not p then D.bug('runtime-contract','Unknown compiler runtime primitive') end
 local Layout=require('let.layout');local inputs,results={},{}
 for _,input in ipairs(declaration.inputs) do
  if input.kind~='InValue' then D.bug('runtime-contract','Runtime ABI input is not a cell value') end
  local kinds=Layout.cellKinds(input.type);if not kinds then D.bug('runtime-contract','Runtime input has no cell ABI') end
  for _,kind in ipairs(kinds) do inputs[#inputs+1]=kind end
 end
 for _,ty in ipairs(declaration.results) do
  local kinds=Layout.cellKinds(ty);if not kinds then D.bug('runtime-contract','Runtime result has no cell ABI') end
  for _,kind in ipairs(kinds) do results[#results+1]=kind end
 end
 if table.concat(inputs)~=p.inputs or table.concat(results)~=p.results then D.bug('runtime-contract','Runtime primitive signature disagrees with generated catalog') end
end
function M.staging(assembly)
 for name,inputs,results in assembly:gmatch('[\r\n]%s*%.extern%s+([%w_]+)%s+([iaf%-]+)%s+([iaf%-]+)') do
  local p=declarations[name]
  if not p or inputs~=(p.inputs=='' and '-' or p.inputs) or results~=(p.results=='' and '-' or p.results) then return false end
 end
 return true
end
return M
