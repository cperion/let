-- Emit explicit lifetime effects using the existing checked IR builder. No
-- executable ownership IR, source evaluator or ISA owner kind is introduced.
-- This is the physical lifetime client; source placement must select roots and
-- representations before using it. Unsupported source escapes remain rejected.
local S=require('let.schema')
local Runtime=require('let.runtime')
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*)/[^/]+$') or '.'
local types=assert(loadfile(path..'/../../gen/holding.lua'))()
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
 function emitter:holdingCode(layout)
  assert(functions,'holding code needs its module function list')
  functions.holdings=functions.holdings or {};local entry=functions.holdings[layout]
  if not entry then
   local serial=functions.holdingSerial or 0;functions.holdingSerial=serial+1
   entry={name='_let_holding_'..serial};functions.holdings[layout]=entry
  end
  return entry
 end
 function emitter:releaseEntry(body,layout)
  local entry=self:holdingCode(layout)
  if not entry.release then
   local release=types.release(entry.name..'_release',layout,foreigns)
   functions[#functions+1]=release;entry.release=release.id
  end
  return self:call(body,'release_bind',{I.Code(entry.release,S.Ptr(S.U64))})
 end
 function emitter:copyInto(body,layout,destination,source)
  local entry=self:holdingCode(layout)
  if not entry.copy then
   local copy=types.copy(entry.name..'_copy',layout,foreigns)
   functions[#functions+1]=copy;entry.copy=copy.id
  end
  builder:emit(body,I.Call(L{},entry.copy,L{I.ValueArg(destination),I.ValueArg(source)}))
 end
 function emitter:allocate(body,scope,slot,layout,bytes)
  local release=self:releaseEntry(body,layout)
  return self:call(body,'owner_new',{scope,self:number(slot),self:number(bytes or layout.size),self:number(layout.align),self:number(layout.shared and 1 or 0),release})
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
