-- Emit explicit lifetime effects using the existing checked IR builder. No
-- executable ownership IR, source evaluator or ISA owner kind is introduced.
-- This is the physical lifetime client; source placement must select roots and
-- representations before using it. Unsupported source escapes remain rejected.
local S=require('let.schema')
local Runtime=require('let.runtime')
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*)/[^/]+$') or '.'
local types=assert(loadfile(path..'/../../gen/type_ops.lua'))()
local I,L=S.Ir,S.List
local M={types=types}
function M.emitter(builder,foreigns,functions)
 local emitter={builder=builder,foreigns=foreigns}
 function emitter:call(body,name,args)
  local declaration=Runtime.install(foreigns,name)
  local arguments={};for _,arg in ipairs(args) do arguments[#arguments+1]=I.ValueArg(arg) end
  local results={};for _ in ipairs(declaration.results) do results[#results+1]=builder:valueId() end
  builder:emit(body,I.Call(L(results),declaration.target,L(arguments)))
  if results[1] then return builder:ref(results[1],declaration.results[1]) end
 end
 function emitter:number(n) return builder:int(S.U64,n) end
 function emitter:scope(body,slots)
  assert(slots>=0 and slots%1==0,'invalid holding count')
  local cells=types.scope_header_cells+slots*types.scope_slot_cells
  local storage=builder:var(body,S.Array(S.U64,cells))
  local place=I.Index(I.Local(storage),builder:u32(0),S.U64)
  local scope=builder:addr(place,S.Ptr(S.U64))
  self:call(body,'scope_enter',{scope,self:number(cells*8)})
  return scope
 end
 function emitter:typeOps(body,layout)
  assert(functions,'type operations need their module function list')
  functions.typeOps=functions.typeOps or {};local entry=functions.typeOps[layout]
  if not entry then
   local serial=functions.typeOpSerial or 0;functions.typeOpSerial=serial+1
   local copy,release=types.generate('_let_holding_'..serial,layout,foreigns)
   functions[#functions+1]=copy;functions[#functions+1]=release
   entry={copy=copy.id,release=release.id};functions.typeOps[layout]=entry
  end
  local ptr=S.Ptr(S.U64)
  return self:call(body,'type_bind',{self:number(layout.size),self:number(layout.align),self:number(layout.shared and 1 or 0),I.Code(entry.copy,ptr),I.Code(entry.release,ptr)})
 end
 function emitter:allocate(body,scope,slot,layout,bytes)
  local descriptor=self:typeOps(body,layout)
  return self:call(body,'owner_new',{scope,self:number(slot),descriptor,self:number(bytes or layout.size)})
 end
 function emitter:data(body,owner) return self:call(body,'owner_data',{owner}) end
 function emitter:retain(body,scope,slot,owner) self:call(body,'owner_retain',{scope,self:number(slot),owner}) end
 function emitter:drop(body,scope,slot) self:call(body,'owner_drop',{scope,self:number(slot)}) end
 function emitter:move(body,destination,slot,source,sourceSlot)
  self:call(body,'owner_move',{destination,self:number(slot),source,self:number(sourceSlot)})
 end
 function emitter:leave(body,scope) self:call(body,'scope_leave',{scope}) end
 return emitter
end
return M
