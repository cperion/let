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
 if path.kind=='Element' or path.kind=='Index' then return parent.element end
end
function M.checkedPath(ty,path) return M.checkedAccess(assert(selected(ty,path))) end
-- Component identities stop at a carrier; pointee layouts are not expanded.
-- Concrete array components stay independent; dynamic places use the existing
-- conservative Element alias class, which may overlap any concrete index.
function M.components(ty,path,out)
 path=path or B.Root;out=out or {}
 if ty:isRef() or ty:isSlice() or ty:isView() or ty:isOwned() then out[path]=true
 elseif ty:isRecord() then
  for _,f in ipairs(ty.fields) do M.components(f.type,B.Field(path,f.name),out) end
 elseif ty:isArray() and M.checkedAccess(ty.element) then
  for i=0,ty.length-1 do M.components(ty.element,B.Index(path,i),out) end
 elseif ty:isTaggedType() then
  for _,f in ipairs(S.alternatives(ty)) do M.components(f.type,B.Case(path,f.name),out) end
 end
 return out
end
function M.activeCases(path)
 local out={}
 while path and path.kind~='Root' do
  if path.kind=='Case' then out[#out+1]={path=path.base,tag=path.name} end
  path=path.base
 end
 -- Outer tags must be checked before reading an inner tag in a union payload.
 for i=1,math.floor(#out/2) do out[i],out[#out-i+1]=out[#out-i+1],out[i] end
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
 if source.kind=='ValueInput' or source.kind=='PlaceInput' or source.kind=='ContentsInput' then return O.Formal(source) end
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
   if source.kind=='ContentsInput' then return source.read.frame..'/contents@'..source.read.ordinal end
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
 local template={phase='loan-demand',sites={},relations={},live_in={},live_out={},root_live_in={},root_live_out={},empty=true}
 -- These edges preserve the particular source binding/read/result, rather than
 -- trying to reconstruct snapshot aliases from equal root provenance. Written
 -- and Join nodes stay finite even when their edges form a loop.
 local function relation(loan,edges,origin)
  template.relations[loan]={dependencies=edges,origin=origin}
 end
 for point,site in pairs(facts.sites) do
  for value,components in pairs(site.definitions) do
   for path,edges in pairs(components) do
    relation(L.Defined(point,value,path),edges,{point=point,value=value,path=path})
   end
  end
  for loc,edges in pairs(site.written_dependencies) do
   relation(L.Contents(L.Written(point,loc)),edges,{point=point,location=loc})
  end
 end
 for version,inputs in pairs(facts.contents_versions.incoming) do
  local edges={}
  for incoming in pairs(inputs) do edges[L.Carrier(L.Contents(incoming))]=true end
  relation(L.Contents(version),edges,{point=version.point,location=version.location})
 end
 local predecessors={}
 for point,site in pairs(facts.sites) do
  local decision={uses={},defines={},root_uses=site.root_uses,root_dependencies=site.root_dependencies,root_demands={},root_defines={},contents=site.contents,invalidates=site.invalidates}
  for value,components in pairs(site.definitions) do
   for path in pairs(components) do decision.defines[L.Defined(point,value,path)]=true end
  end
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
-- Bind the finite loan graph, not machine instances or runtime layouts. Call
-- edges retain their substitution environment: two calls of an identical query
-- must not merge their input guards merely because their roots compare equal.
-- Ownership.bind's protection/instance solver consumes this graph; a frontier
-- here is an obligation, never proof of an available capability or holding.
function M.bindLoans(program,entries)
 assert(program.phase=='checked-program','loan binding needs the immutable checked graph')
 assert(type(entries)=='table','loan binding requires explicit entry requests')
 local L=S.Lifetime
 local result={phase='loan-contracts',source=program,entries={},contexts={},nodes={},calls={},frontiers={}}
 local pending={}
 local function context(id)
  if result.contexts[id] then return result.contexts[id] end
  local facts=assert(program.flow.contexts[id],'unknown checked call context')
  local c={id=id,facts=facts,graph=program.flow.functions[facts.fn_id],loans={},dependencies={},returns={},root_uses={},calls={},incoming={}}
  result.contexts[id]=c;pending[#pending+1]=c;return c
 end
 for _,name in ipairs(entries) do
  local id=program.flow.roots[name]
  if not id then D.reject('lower-export','Unknown loan-binding entry '..tostring(name)) end
  result.entries[name]=context(id)
 end
 local cursor=1
 while cursor<=#pending do
  local c=pending[cursor];cursor=cursor+1
  for point,site in pairs(c.facts.sites) do
   c.calls[point]={}
   local children={};for childId in pairs(site.calls) do children[#children+1]=childId end;table.sort(children)
   for _,childId in ipairs(children) do
    local child=context(childId)
    local call={point=point,caller=c,callee=child,arguments={},contents={},source=site.call_arguments[childId]}
    c.calls[point][childId]=call;child.incoming[#child.incoming+1]=call;result.calls[#result.calls+1]=call
   end
  end
 end
 local function node(c,kind,symbol)
  local path=symbol.path or symbol.use and symbol.use.path or symbol.version and symbol.version.location.path
  local n={id=#result.nodes+1,context=c,kind=kind,symbol=symbol,edges={},active_cases=M.activeCases(path)}
  result.nodes[#result.nodes+1]=n;return n
 end
 local function edge(from,to,call,alternative)
  from.edges[#from.edges+1]={target=to,call=call,alternative=alternative}
 end
 local function frontier(n,reason)
  n.frontier=reason;result.frontiers[n]=reason
 end
 local loan,dependency,returns
 local work={}
 loan=function(c,id)
  local n=c.loans[id]
  if not n then n=node(c,id.kind,id);c.loans[id]=n;work[#work+1]=n end
  return n
 end
 dependency=function(c,id)
  local n=c.dependencies[id]
  if not n then n=node(c,id.kind,id);c.dependencies[id]=n;work[#work+1]=n end
  return n
 end
 returns=function(c,point,index,path)
  c.returns[point]=c.returns[point] or {};local site=c.returns[point]
  site[index]=site[index] or {};local n=site[index][path]
  if not n then
   n=node(c,'Return',{point=point,result=index,path=path});site[index][path]=n;work[#work+1]=n
  end
  return n
 end
 local function dependencies(n,c,edges)
  for _,id in ipairs(list(edges or {})) do edge(n,dependency(c,id)) end
 end
 -- Intern argument bindings separately, even when Access reused the same query.
 for _,call in ipairs(result.calls) do
  for alternative,args in ipairs(call.source or {}) do
   local actual={};call.arguments[alternative]=actual
   for index,arg in ipairs(args) do
    actual[index]={}
    for path,edges in pairs(arg.dependencies) do
     local n=node(call.caller,'Argument',{point=call.point,index=index-1,path=path})
     n.call=call;n.alternative=alternative;dependencies(n,call.caller,edges);actual[index][path]=n
    end
   end
  end
 end
 for _,c in ipairs(pending) do
  local template=program.ownership[c.facts.fn_id].lifetime_template.contexts[c.id]
  for id in pairs(template.relations) do loan(c,id) end
  for point,site in pairs(c.facts.sites) do
   for _,use in pairs(site.uses) do loan(c,use.loan) end
   for use in pairs(site.contents) do dependency(c,L.Read(use)) end
   for use in pairs(site.addresses) do dependency(c,L.Address(use)) end
   for use,parts in pairs(site.root_dependencies) do
    local relevant=false
    for _,target in pairs(site.root_uses[use]) do
     if template.sites[point].root_demands[M.root(target.source)] then relevant=true;break end
    end
    if relevant then
     local n=node(c,'RootUse',use);c.root_uses[use]=n;n.provenance=site.root_uses[use]
     for _,edges in pairs(parts) do dependencies(n,c,edges) end
    end
   end
   for index,parts in pairs(site.returns) do for path in pairs(parts) do returns(c,point,index-1,path) end end
  end
 end
 cursor=1
 while cursor<=#work do
  local n=work[cursor];cursor=cursor+1
  local c,id=n.context,n.symbol
  local facts,graph=c.facts,c.graph
  local template=program.ownership[facts.fn_id].lifetime_template.contexts[c.id]
  if n.kind=='Defined' then
   local relation=template.relations[id]
   if relation then dependencies(n,c,relation.dependencies) else frontier(n,'missing-definition') end
  elseif n.kind=='Contents' then
   local version=id.version
   if version.kind=='Entry' then
    n.bindings={}
    for _,call in ipairs(c.incoming) do
     local before=call.caller.facts.contents_versions.before[call.point]
     local v=before[version.location]
     if v then
      local actual=loan(call.caller,L.Contents(v));n.bindings[call]=actual;call.contents[version.location]=actual
     end
    end
    frontier(n,'entry-contents')
   elseif version.kind=='Join' then
    -- Preserve predecessor selection. A bag of incoming guards is not a
    -- witness that every member exists on every path through the join.
    for previous,p in pairs(graph.nodes) do
     for _,successor in ipairs(p.next) do if successor==version.point and facts.contents_versions.after[previous] then
      local v=facts.contents_versions.after[previous][version.location]
      if v then
       local to=loan(c,L.Contents(v));edge(n,to);n.edges[#n.edges].predecessor=previous
      end
     end end
    end
    if graph.entry==version.point then edge(n,loan(c,L.Contents(L.Entry(version.location)))) end
   else
    local relation=template.relations[id]
    if relation then dependencies(n,c,relation.dependencies) else frontier(n,'missing-write') end
   end
  elseif n.kind=='Parameter' then
   assert(id.frame==facts.fn_id,'parameter dependency escaped its defining context')
   n.bindings={}
   for _,call in ipairs(c.incoming) do
    local alternatives={};n.bindings[call]=alternatives
    for index,args in ipairs(call.arguments) do alternatives[index]=args[id.parameter+1] and args[id.parameter+1][id.path] end
   end
   frontier(n,'input')
  elseif n.kind=='Carrier' then
   if id.loan.kind=='Defined' or id.loan.kind=='Parameter' then
    local frame=id.loan.kind=='Defined' and id.loan.point.frame or id.loan.frame
    assert(frame==facts.fn_id,'carrier dependency refers to a foreign source activation')
   end
   edge(n,loan(c,id.loan))
  elseif n.kind=='Read' then
   local read=assert(facts.sites[id.use.point].contents[id.use],'missing original contents read')
   n.read=read;n.locator=graph.operands[id.use.point][id.use.operand]
   for version in pairs(read.versions) do edge(n,loan(c,L.Contents(version))) end
  elseif n.kind=='Address' then
   local site=assert(facts.sites[id.use.point])
   n.provenance=assert(site.addresses[id.use],'missing original address')
   n.parents=site.address_dependencies[id.use] or {}
   for _,edges in pairs(n.parents) do dependencies(n,c,edges) end
   n.locator=graph.operands[id.use.point][id.use.operand]
  elseif n.kind=='Result' then
   for _,call in pairs(c.calls[id.call]) do
    for point,site in pairs(call.callee.facts.sites) do
     local parts=site.returns[id.result+1]
     if parts and parts[id.path] then edge(n,returns(call.callee,point,id.result,id.path),call) end
    end
   end
   if not next(c.calls[id.call]) then frontier(n,'unbound-call') end
  elseif n.kind=='CallContents' then
   for _,call in pairs(c.calls[id.call]) do
    for point in pairs(call.callee.facts.sites) do
     if call.callee.graph.nodes[point].returns then
      local version=call.callee.facts.contents_versions.after[point][id.location]
      if version then edge(n,loan(call.callee,L.Contents(version)),call)
      else
       -- A target with no access to this root leaves this caller version alone.
       local previous=assert(facts.contents_versions.before[id.call][id.location])
       edge(n,loan(c,L.Contents(previous)));n.edges[#n.edges].call_alternative=call
      end
     end
    end
   end
   if not next(c.calls[id.call]) then frontier(n,'unbound-call-contents') end
  elseif n.kind=='Return' then
   dependencies(n,c,facts.sites[id.point].returns[id.result+1][id.path])
  else error('unknown loan-contract node '..n.kind) end
 end
 return result
end

-- Demand propagation is separate from protection: a requested capability must
-- still have a live guard at its original use. A resolved concrete holding can
-- supply a capability directly; otherwise follow the original producer edges.
-- Requests and supplied bindings belong to this solve, never to shared checked IR.
function M.capabilities(contracts,requests,supplied)
 assert(contracts.phase=='loan-contracts','capability solving needs bound loan edges')
 supplied=supplied or {}
 local origins,returned,users={},{},{}
 local work,queued={},{}
 local function enqueue(n)
  if not queued[n] then queued[n]=true;work[#work+1]=n end
 end
 local function watches(n,input) users[input][n]=true end
 for _,n in ipairs(contracts.nodes) do origins[n]={};returned[n]={};users[n]={} end
 for _,n in ipairs(contracts.nodes) do
  for _,e in ipairs(n.edges) do
   watches(n,e.target)
   if e.call then
    for _,args in ipairs(e.call.arguments) do for _,parts in pairs(args) do for _,actual in pairs(parts) do watches(n,actual) end end end
    for _,actual in pairs(e.call.contents) do watches(n,actual) end
   end
  end
  enqueue(n)
 end
 local function moduleAddress(n)
  if n.kind~='Address' or next(n.parents) then return false end
  for _,target in pairs(n.provenance) do if target.source.kind~='Global' then return false end end
  return next(n.provenance)~=nil
 end
 local cursor=1
 while cursor<=#work do
  local n=work[cursor];cursor=cursor+1;queued[n]=nil
  local changed=false
  local function include(source)
   if not origins[n][source] then origins[n][source]=true;changed=true end
  end
  local function copy(source) for origin in pairs(origins[source]) do include(origin) end end
  if supplied[n] or n.frontier or n.kind=='Address' and #n.edges==0 then include(n)
  else
   for _,e in ipairs(n.edges) do
    if not e.call then copy(e.target)
    else
     local call=e.call
     for origin in pairs(origins[e.target]) do
      if origin.context==call.callee and origin.frontier=='input' then
       -- A result borrowed from an input recovers its capability from the
       -- captured caller argument. It does not widen the identity callee's ABI.
       for _,args in ipairs(call.arguments) do
        local actual=args[origin.symbol.parameter+1] and args[origin.symbol.parameter+1][origin.symbol.path]
        if actual then copy(actual) else returned[n][origin]='missing-input-binding';include(n) end
       end
      elseif origin.context==call.callee and origin.frontier=='entry-contents' then
       local actual=origin.bindings[call]
       if actual then copy(actual) else returned[n][origin]='missing-contents-binding';include(n) end
      elseif moduleAddress(origin) then include(origin)
      else
       -- A local capability cannot be read from an expired callee activation.
       -- Its result/exit contract must supply it (often from a result holding).
       -- This records a requirement; it does not invent that holding or ABI.
       returned[n][origin]=origin.frontier or true;include(n)
      end
     end
    end
   end
  end
  if changed then for user in pairs(users[n]) do enqueue(user) end end
 end
 local demands={phase='capability-demands',nodes={},addresses={},inputs={},contents={},results={},unresolved={},supplied={},empty={},origins=origins}
 work={}
 local function requireNode(n)
  assert(n and origins[n],'capability request belongs to another binding')
  if not demands.nodes[n] then demands.nodes[n]=true;work[#work+1]=n end
 end
 for _,n in ipairs(requests) do requireNode(n) end
 cursor=1
 while cursor<=#work do
  local n=work[cursor];cursor=cursor+1
  if supplied[n] then demands.supplied[n]=supplied[n]
  elseif n.frontier=='input' then
   demands.inputs[n]=true
   for _,alternatives in pairs(n.bindings) do for _,actual in pairs(alternatives) do requireNode(actual) end end
  elseif n.frontier=='entry-contents' then
   demands.contents[n]=true
   for _,actual in pairs(n.bindings) do requireNode(actual) end
  elseif n.frontier then demands.unresolved[n]=n.frontier
  elseif n.kind=='Address' and #n.edges==0 then demands.addresses[n]=true
  else
   if not next(origins[n]) then demands.empty[n]=true end
   for origin in pairs(origins[n]) do
    if origin~=n then requireNode(origin)
    else
     demands.results[n]=returned[n]
     for source,reason in pairs(returned[n]) do if reason~=true then demands.unresolved[source]=reason end end
    end
   end
  end
 end
 -- Keep failures behind forwarded result boundaries visible without turning
 -- them into extra callee input/result cells. Recursive forwarding may cycle.
 local inspected={}
 work={};for n in pairs(demands.results) do work[#work+1]=n end;cursor=1
 while cursor<=#work do
  local n=work[cursor];cursor=cursor+1
  if not inspected[n] then
   inspected[n]=true
   for source,reason in pairs(returned[n]) do
    if reason~=true then demands.unresolved[source]=reason end
    work[#work+1]=source
   end
  end
 end
 -- Empty demand/origin sets are not lifetime evidence. The protection solver
 -- must still discharge inactive payloads, non-owning constants and guard uses.
 return demands
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
