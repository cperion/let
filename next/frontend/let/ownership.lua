-- Explicit Rc types select allocation/copy/drop. These are only the remaining
-- lifetime relations and strong-edge checks; no placement or preservation solver.
local S=require('let.schema')
local D=require('let.diag')
local B,O=S.Borrow,S.Ownership
local M={}
local EMPTY=S.List{}
local checked=setmetatable({},{__mode='k'})
function M.checkedAccess(t)
 local known=checked[t];if known~=nil then return known end
 local yes=t:isRc() or t:isRef() or t:isSlice() or t:isView() or t:isOwned()
 if t:isRecord() then for _,f in ipairs(t.fields) do yes=yes or M.checkedAccess(f.type) end
 elseif t:isArray() then yes=M.checkedAccess(t.element)
 elseif t:isTaggedType() then for _,f in ipairs(S.alternatives(t)) do yes=yes or M.checkedAccess(f.type) end end
 checked[t]=yes;return yes
end
function M.selected(t,path)
 if path.kind=='Root' then return t end
 local parent=M.selected(t,path.base)
 if path.kind=='Field' then return S.field(parent,path.name) end
 if path.kind=='Case' then return S.caseOf(parent,path.name) end
 return parent.element
end
function M.checkedPath(t,path) return M.checkedAccess(M.selected(t,path)) end
function M.context(parent,point)
 for _,p in ipairs(parent) do if p==point then return parent,true end end
 local out={};for i,p in ipairs(parent) do out[i]=p end;out[#out+1]=point;return S.List(out)
end
function M.localSource(frame,storage,context,folded)
 if folded then return B.Recurring(frame,storage,context) end
 return #context==0 and B.Local(frame,storage) or B.Instantiated(frame,storage,context)
end
function M.root(source)
 if source.kind=='Global' then return O.Module(source) end
 if source.kind=='Heap' then return O.Fresh(source) end
 return O.Formal(source)
end
local function frame(source) while source.kind=='FieldGuard' do source=source.parent end;return source end
function M.sameContext(a,b)
 a,b=a or EMPTY,b or EMPTY
 if #a~=#b then return false end
 for i,p in ipairs(a) do if p~=b[i] then return false end end
 return true
end
function M.borrowStore(holder,source,current)
 if holder.kind=='Heap' then return false end
 source=frame(source)
 if source.kind=='Global' then return true end
 local formal=source.kind=='ValueInput' or source.kind=='PlaceInput' or source.kind=='ContentsInput' or source.kind=='CallOutput'
 if holder.kind=='ValueInput' or holder.kind=='PlaceInput' or holder.kind=='ContentsInput' then return formal and holder.frame==source.frame end
 if formal then
  if holder.frame==source.frame then return true end
  for _,p in ipairs(holder.context or EMPTY) do if p.frame==source.frame then return true end end
  return false
 end
 local a,b=holder.context or EMPTY,source.context or EMPTY
 if holder.frame==source.frame and M.sameContext(a,b) and (current or not source.folded and source.kind~='Recurring') then return true end
 if #a<=#b or source.folded or source.kind=='Recurring' then return false end
 for i,p in ipairs(b) do if a[i]~=p then return false end end
 return a[#b+1].frame==source.frame
end
function M.localTo(source,fn,context)
 source=frame(source)
 return (source.kind=='Local' or source.kind=='Instantiated' or source.kind=='Recurring' or source.kind=='ValueGuard') and source.frame==fn and M.sameContext(source.context,context)
end
-- Iterative SCC traversal. Construction alone points to older holdings; a cycle
-- requires a later strong mutation. Borrowed references are never graph edges.
function M.strongCycle(edges,construction)
 construction=construction or {}
 local outgoing,incoming,roots={},{},{}
 for e in pairs(edges) do
  roots[e.holder]=true;roots[e.target]=true
  outgoing[e.holder]=outgoing[e.holder] or {};outgoing[e.holder][#outgoing[e.holder]+1]=e.target
  incoming[e.target]=incoming[e.target] or {};incoming[e.target][#incoming[e.target]+1]=e.holder
 end
 local seen,order={},{}
 for root in pairs(roots) do if not seen[root] then
  local work={{root,1}};seen[root]=true
  while #work>0 do
   local top=work[#work];local children=outgoing[top[1]] or {};local child=children[top[2]]
   if child then top[2]=top[2]+1;if not seen[child] then seen[child]=true;work[#work+1]={child,1} end
   else order[#order+1]=top[1];work[#work]=nil end
  end
 end end
 local component={};local serial=0
 for i=#order,1,-1 do if not component[order[i]] then
  serial=serial+1;local work={order[i]};component[order[i]]=serial;local cursor=1
  while cursor<=#work do local r=work[cursor];cursor=cursor+1
   for _,parent in ipairs(incoming[r] or {}) do if not component[parent] then component[parent]=serial;work[#work+1]=parent end end
  end
  local concrete=false;for _,root in ipairs(work) do if root.kind=='Fresh' then concrete=true end end
  if concrete then
   local witness={}
   for e in pairs(edges) do if component[e.holder]==serial and component[e.target]==serial then witness[#witness+1]=e end end
   for _,e in ipairs(witness) do if not construction[e.site.point] then return witness end end
  end
 end end
end
function M.analyze(functions,queries,construction)
 local result={}
 for _,fn in ipairs(functions) do
  local edges=queries[fn.id].strong
  local witness=M.strongCycle(edges,construction)
  if witness then local err=D.make('reject','Ref-cycle','Explicit Rc strong edges form a cycle');err.witness=witness;error(err,0) end
  result[fn.id]={edges=edges}
 end
 return result
end
return M
