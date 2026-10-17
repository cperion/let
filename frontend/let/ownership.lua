-- Collector-free source ownership inference. The access worklist supplies actual
-- roots, ordered retention events and call substitution; this module never walks
-- executable bodies or computes source values. Physical placement is a later client.
local S=require('let.schema')
local D=require('let.diag')
local B,O=S.Borrow,S.Ownership
local M={}
local function key(v) return S.encode(v) end
function M.checkedAccess(ty,seen)
 if ty:isRef() or ty:isSlice() or ty:isView() or ty:isOwned() then return true end
 seen=seen or {};if seen[ty] then return false end;seen[ty]=true
 if ty:isRecord() then for _,f in ipairs(ty.fields) do if M.checkedAccess(f.type,seen) then return true end end end
 if ty:isArray() then return M.checkedAccess(ty.element,seen) end
 if ty:isTaggedType() then for _,f in ipairs(S.alternatives(ty)) do if M.checkedAccess(f.type,seen) then return true end end end
 return false
end
local function selected(ty,path)
 if path.kind=='Root' then return ty end
 local parent=selected(ty,path.base)
 if path.kind=='Field' then return S.field(parent,path.name) end
 if path.kind=='Case' then for _,f in ipairs(S.alternatives(parent)) do if f.name==path.name then return f.type end end end
 if path.kind=='Element' then return parent.element end
end
function M.checkedPath(ty,path) return M.checkedAccess(assert(selected(ty,path))) end
-- Component identities stop at a carrier; pointee layouts are not expanded.
-- Array indices deliberately retain the existing conservative Element class.
function M.components(ty,path,out)
 path=path or B.Root;out=out or {}
 if ty:isRef() or ty:isSlice() or ty:isView() or ty:isOwned() then out[path]=true
 elseif ty:isRecord() then
  for _,f in ipairs(ty.fields) do M.components(f.type,B.Field(path,f.name),out) end
 elseif ty:isArray() then M.components(ty.element,B.Element(path),out)
 elseif ty:isTaggedType() then
  for _,f in ipairs(S.alternatives(ty)) do M.components(f.type,B.Case(path,f.name),out) end
 end
 return out
end
local function list(set)
 local out={};for v in pairs(set) do out[#out+1]=v end
 table.sort(out,function(a,b) return key(a)<key(b) end)
 return S.List(out)
end
function M.root(source)
 if source.kind=='Global' then return O.Module(source) end
 if source.kind=='Local' or source.kind=='Instantiated' or source.kind=='Recurring' then return O.Fresh(source) end
 if source.kind=='ValueInput' or source.kind=='PlaceInput' then return O.Formal(source) end
 assert(source.kind=='CallOutput','unknown owner provenance')
 return O.Deferred(source)
end
function M.context(parent,point)
 -- Recursive allocation families are folded at repeated call sites, rather than
 -- expanding fresh names forever or imposing a recursion-depth budget. If they
 -- require a growing owning chain, folding exposes a strict-order cycle.
 for _,p in ipairs(parent) do if p==point then return parent,true end end
 local out={};for i,p in ipairs(parent) do out[i]=p end;out[#out+1]=point
 return S.List(out)
end
function M.localSource(frame,storage,context,folded)
 if folded then return B.Recurring(frame,storage,context) end
 return #context==0 and B.Local(frame,storage) or B.Instantiated(frame,storage,context)
end
local EMPTY=S.List{}
local function extent(source)
 return O.Activation(source.frame,source.context or EMPTY,source.kind=='Recurring')
end
local function within(inner,outer)
 -- Equal recursive family names are not an independent lifetime proof: they
 -- can denote a caller's and callee's different live allocations.
 if outer.folded then return false end
 if inner==outer then return true end
 if #inner.context<=#outer.context then return false end
 for i,p in ipairs(outer.context) do if inner.context[i]~=p then return false end end
 return inner.context[#outer.context+1].frame==outer.frame
end
function M.events() return {holdings={},escapes={},spans={}} end
function M.hold(events,holder,target,site,span,activation,destination)
 local h=O.Holding(M.root(holder),M.root(target),site,activation,destination)
 events.holdings[h]=h;events.spans[site]=span
end
function M.returned(events,source,site,span)
 local root=M.root(source)
 if root.kind=='Fresh' and extent(source)==site.extent then
  local r=O.Requirement(root,site,'return');events.escapes[r]=r;events.spans[site]=span
 end
end
function M.merge(dst,src)
 local changed=false
 for _,field in ipairs{'holdings','escapes'} do
  for id,v in pairs(src[field]) do if not dst[field][id] then dst[field][id]=v;changed=true end end
 end
 for site,span in pairs(src.spans) do dst.spans[site]=span end
 return changed
end
local function independent(holding,counted)
 local holder,target=holding.holder,holding.target
 if target.kind=='Module' then return true end
 if holder.kind~='Fresh' or counted[holder] then return false end
 if holding.activation then return true end
 local h=extent(holder.source)
 if target.kind=='Fresh' then return within(h,extent(target.source)) end
 if target.kind=='Formal' then
  -- Entry provenance is guaranteed for that activation and descendants. This
  -- proof uses the input contract, never the holding edge being omitted.
  return within(h,O.Activation(target.source.frame,EMPTY,false))
 end
 return false
end
local function witness(edges)
 -- Iterative Kosaraju: host-stack depth is independent of graph depth. Inspect
 -- whole SCCs, not just DFS backedges (a formal-only backedge can conceal a
 -- larger component containing a concrete counted root).
 local outgoing,incoming,roots={},{},{}
 for e in pairs(edges) do
  roots[e.holder]=true;roots[e.target]=true
  outgoing[e.holder]=outgoing[e.holder] or {};local a=outgoing[e.holder];a[#a+1]=e
  incoming[e.target]=incoming[e.target] or {};local b=incoming[e.target];b[#b+1]=e.holder
 end
 for _,a in pairs(outgoing) do table.sort(a,function(x,y) return key(x)<key(y) end) end
 local seen,order={},{}
 for _,root in ipairs(list(roots)) do if not seen[root] then
  local stack={{root=root,index=1}};seen[root]=true
  while #stack>0 do
   local top=stack[#stack];local e=(outgoing[top.root] or {})[top.index]
   if not e then order[#order+1]=top.root;stack[#stack]=nil
   else
    top.index=top.index+1
    if not seen[e.target] then seen[e.target]=true;stack[#stack+1]={root=e.target,index=1} end
   end
  end
 end end
 seen={}
 for i=#order,1,-1 do local root=order[i];if not seen[root] then
  local members,stack={}, {root};seen[root]=true
  while #stack>0 do
   local r=stack[#stack];stack[#stack]=nil;members[r]=true
   for _,p in ipairs(incoming[r] or {}) do if not seen[p] then seen[p]=true;stack[#stack+1]=p end end
  end
  local concrete
  for _,r in ipairs(list(members)) do if r.kind=='Fresh' then concrete=r;break end end
  -- Free formals describe conditional owning specializations. Preserve their
  -- inequalities for substitution; actual bounded borrows may discharge them.
  if concrete then
   for _,first in ipairs(outgoing[concrete] or {}) do if members[first.target] then
    if first.target==concrete then return S.List{first} end
    local pending,via={first.target},{[first.target]=first};local cursor=1
    while cursor<=#pending do
     local r=pending[cursor];cursor=cursor+1
     for _,e in ipairs(outgoing[r] or {}) do if members[e.target] and not via[e.target] then
      via[e.target]=e;pending[#pending+1]=e.target
     end end
    end
    if via[concrete] then
     local reversed={};local r=concrete
     while r~=first.target do local e=via[r];reversed[#reversed+1]=e;r=e.holder end
     local cycle={first};for j=#reversed,1,-1 do cycle[#cycle+1]=reversed[j] end
     return S.List(cycle)
    end
   end end
  end
 end end
end
function M.solve(events,results,unknown)
 local roots,counted,requirements,queue,byHolder={},{},{},{},{}
 local function requireCount(root,site,reason)
  if root.kind~='Fresh' then return false end
  local r=O.Requirement(root,site,reason);requirements[r]=true
  if counted[root] then return end;counted[root]=true;queue[#queue+1]=root
 end
 for r in pairs(events.escapes) do requireCount(r.root,r.site,r.reason) end
 -- Escape placement and retention are mutually dependent: counting an aggregate
 -- invalidates activation-only borrowing of its fields/environment holdings.
 -- Revisit only that holder's outgoing dependencies, not the entire graph.
 for h in pairs(events.holdings) do
  byHolder[h.holder]=byHolder[h.holder] or {};local outgoing=byHolder[h.holder];outgoing[#outgoing+1]=h
  if not independent(h,counted) then requireCount(h.target,h.site,'store') end
 end
 local cursor=1
 while cursor<=#queue do
  local root=queue[cursor];cursor=cursor+1
  for _,h in ipairs(byHolder[root] or {}) do requireCount(h.target,h.site,'store') end
 end
 local edges,borrows={},{}
 for h in pairs(events.holdings) do
  roots[h.holder]=true;roots[h.target]=true
  if independent(h,counted) then
   if h.holder.kind=='Fresh' then borrows[O.BorrowProof(h.target,h.activation or extent(h.holder.source),h.site)]=true end
  else edges[O.Edge(h.holder,h.target,h.site)]=true end
 end
 for r in pairs(requirements) do roots[r.root]=true end
 for _,r in ipairs(results) do for _,root in ipairs(r.roots) do roots[root]=true end end
 local summary=O.Summary(list(roots),results,list(events.holdings),list(borrows),list(edges),list(requirements),unknown)
 return summary,witness(edges)
end
local function diagnostic(code,message,site,spans,summary,cycle)
 if cycle then
  local function name(root)
   local source=root.source
   if root.kind=='Fresh' then
    local out=source.frame..'/storage'..source.storage
    for _,point in ipairs(source.context or EMPTY) do out=out..'@'..point.frame..'#'..point.ordinal end
    return out
   end
   if root.kind=='Module' then return source.storage end
   if root.kind=='Deferred' then return source.invocation.frame..'/result'..source.result end
   return source.frame..'/input'..source.parameter
  end
  local first=cycle[1]
  message=message..': '..name(first.holder)..' -> '..name(first.target)..
   ' at '..first.site.point.frame..'#'..first.site.point.ordinal..' ('..#cycle..' edge cycle; full witness attached)'
 end
 local err=D.make('reject',code,message,spans[site])
 -- Preserve the actual-root witness with the rejected proof.
 err.ownership=summary;err.witness=cycle;error(err,0)
end
-- Backward demand over the original CFG. Join contents are edge-bound: a
-- predecessor owes its own incoming version, never the union of other paths'
-- witnesses. This computes demand only; it does not certify a guard or invent
-- an acquisition from a may-alias set.
local function lifetimeTemplate(graph,facts)
 local L=S.Lifetime
 local template={phase='loan-demand',sites={},live_in={},live_out={},root_live_in={},root_live_out={},empty=true}
 local predecessors={}
 for point,site in pairs(facts.sites) do
  local decision={uses={},defines={},root_uses=site.root_uses,root_demands={},root_defines={},contents=site.contents,invalidates=site.invalidates}
  template.sites[point]=decision;template.live_in[point]={};template.live_out[point]={};predecessors[point]={}
  template.root_live_in[point]={};template.root_live_out[point]={}
  for _,targets in pairs(site.root_uses) do for _,a in pairs(targets) do
   local source=a.source
   local own=source.frame==graph.fn.id and (source.kind=='Local' or source.kind=='Instantiated' or source.kind=='Recurring')
    and source==M.localSource(graph.fn.id,source.storage,facts.context,facts.folded)
   if not own or graph.addressed[source.storage] then
    decision.root_demands[M.root(source)]=true;template.empty=false
   end
  end end
  for _,use in pairs(site.uses) do decision.uses[use.loan]=true;template.empty=false end
  for _,use in pairs(site.contents) do
   for version in pairs(use.versions) do decision.uses[L.Contents(version)]=true;template.empty=false end
  end
  for location in pairs(site.invalidates) do decision.defines[L.Contents(L.Written(point,location))]=true;template.empty=false end
 end
 for storage in pairs(graph.addressed) do
  local point=graph.storage_origins[storage]
  if point and template.sites[point] then
   local root=M.root(M.localSource(graph.fn.id,storage,facts.context,facts.folded))
   template.sites[point].root_defines[root]=true
  end
 end
 -- A definition is killed on every execution of its source point, including
 -- the next loop iteration. Equal source IDs do not identify an allocation.
 for _,site in pairs(template.sites) do
  for loan in pairs(site.uses) do
   if loan.kind=='Defined' then
    local definition=assert(template.sites[loan.point],'use has no reachable definition')
    definition.defines[loan]=true
   end
  end
 end
 for point in pairs(template.sites) do
  for _,successor in ipairs(graph.nodes[point].next) do
   if predecessors[successor] then predecessors[successor][point]=true end
  end
 end
 local work,queued={},{}
 local function enqueue(point)
  if not queued[point] then queued[point]=true;work[#work+1]=point end
 end
 local points={};for point in pairs(template.sites) do points[#points+1]=point end
 table.sort(points,function(a,b) return a.ordinal>b.ordinal end)
 for _,point in ipairs(points) do enqueue(point) end
 local cursor=1
 while cursor<=#work do
  local point=work[cursor];cursor=cursor+1;queued[point]=nil
  local site=template.sites[point];local output=template.live_out[point]
  for _,successor in ipairs(graph.nodes[point].next) do
   for loan in pairs(template.live_in[successor] or {}) do
    local version=loan.kind=='Contents' and loan.version
    if version and version.kind=='Join' and version.point==successor then
     local incoming=assert(facts.contents_versions.after[point][version.location])
     output[L.Contents(incoming)]=true
    else output[loan]=true end
   end
  end
  local changed=false;local input=template.live_in[point]
  local roots=template.root_live_out[point]
  for _,successor in ipairs(graph.nodes[point].next) do
   for root in pairs(template.root_live_in[successor] or {}) do roots[root]=true end
  end
  local rootInput=template.root_live_in[point]
  for root in pairs(site.root_demands) do
   if not rootInput[root] then rootInput[root]=true;changed=true end
  end
  for root in pairs(roots) do
   if not site.root_defines[root] and not rootInput[root] then rootInput[root]=true;changed=true end
  end
  for loan in pairs(site.uses) do if not input[loan] then input[loan]=true;changed=true end end
  for loan in pairs(output) do
   if not site.defines[loan] and not input[loan] then input[loan]=true;changed=true end
  end
  if changed then for previous in pairs(predecessors[point]) do enqueue(previous) end end
 end
 return template
end

function M.analyze(functions,queries,flow)
 local inferred={}
 local templates={}
 assert(flow,'ownership analysis requires the completed source flow')
 for id,facts in pairs(flow.contexts) do
  local fn=facts.fn_id;templates[fn]=templates[fn] or {phase='loan-demand',contexts={},entry=flow.roots[fn]}
  templates[fn].contexts[id]=lifetimeTemplate(flow.functions[fn],facts)
 end
 for _,fn in ipairs(functions) do
  local query=queries[fn.id];local results={}
  for i,value in ipairs(query.results) do
   for path,refs in pairs(value.refs) do if M.checkedPath(fn.results[i],path) then
    local roots={};for _,a in pairs(refs) do roots[M.root(a.source)]=true end
    results[#results+1]=O.Result(i-1,path,list(roots))
   end end
  end
  table.sort(results,function(a,b) return key(a)<key(b) end)
  local summary,cycle=M.solve(query.ownership,S.List(results),query.unknown)
  inferred[fn.id]={summary=summary,cycle=cycle,spans=query.ownership.spans,lifetime_template=templates[fn.id]}
 end
 return inferred
end
function M.validate(functions,inferred)
 -- Check the complete graph. Unsupported placement is an executable-admission
 -- decision, not a failed proof, and must never conceal a caller's concrete cycle.
 for _,fn in ipairs(functions) do
  local entry=inferred[fn.id]
  if entry.cycle then diagnostic('Ref-cycle','Owning references require a cyclic strict owner order',entry.cycle[1].site,entry.spans,entry.summary,entry.cycle) end
 end
end
return M
