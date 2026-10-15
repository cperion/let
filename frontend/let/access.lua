-- Access/retention analysis of checked IR. Scalar computation and execution stay
-- in the VM. Each body is inspected once to build provenance/state relations;
-- calls compose those summaries, never replay source bodies or IR operands under
-- another frame's ordinals. The finite query worklist also closes recursion.
local S=require('let.schema')
local D=require('let.diag')
local B=S.Borrow
local Ownership=require('let.ownership')
local O=S.Ownership
local M={}
local ROOT=B.Root
local function key(value) return S.encode(value) end
local checkedAccess,checkedPath=Ownership.checkedAccess,Ownership.checkedPath
local function empty() return {refs={},calls={},unknown=false} end
local function target(source)
 assert(source.kind=='Global' or source.kind=='Local' or source.kind=='Instantiated' or source.kind=='Recurring' or source.kind=='PlaceInput','loan source is not a physical target')
 return B.StorageRoot(source)
end
local function owner(route)
 if route.kind=='StorageRoot' then return route.storage end
 if route.kind=='InputTarget' then return B.ValueInput(route.frame,route.parameter,route.path) end
 return B.CallOutput(route.invocation,route.result,route.path)
end
local function location(route,path,writable,source,current)
 return {location=B.Location(route,path),source=source or owner(route),writable=writable,current=current or false}
end
local function accessKey(a) return key(a.location)..':'..key(a.source)..':'..tostring(a.writable)..':'..tostring(a.current) end
local function add(set,a)
 local id=accessKey(a);if set[id] then return false end;set[id]=a;return true
end
local function mergeSet(dst,src)
 local changed=false;for _,a in pairs(src or {}) do if add(dst,a) then changed=true end end;return changed
end
local function merge(dst,src)
 local changed=false
 if src.unknown and not dst.unknown then dst.unknown=true;changed=true end
 for p,set in pairs(src.refs) do dst.refs[p]=dst.refs[p] or {};if mergeSet(dst.refs[p],set) then changed=true end end
 for p,codes in pairs(src.calls) do
  dst.calls[p]=dst.calls[p] or {}
  for id,binding in pairs(codes) do if not dst.calls[p][id] then dst.calls[p][id]=binding;changed=true end end
 end
 return changed
end
local function clone(value) local out=empty();merge(out,value);return out end
-- `current` is a relative proof, not part of root identity. Arguments, results
-- and state cross activation boundaries: equal folded families are not proof
-- that their live allocations belong to this activation.
local function external(value)
 local out=empty();out.unknown=value.unknown
 for p,set in pairs(value.refs) do
  out.refs[p]={};for _,a in pairs(set) do add(out.refs[p],location(a.location.root,a.location.path,a.writable,a.source)) end
 end
 for p,codes in pairs(value.calls) do out.calls[p]=codes end
 return out
end
local function externalTargets(set)
 local out={};for _,a in pairs(set) do add(out,location(a.location.root,a.location.path,a.writable,a.source)) end;return out
end
local function single(a) local out={};add(out,a);return out end
local function at(value,path) return value.refs[path] or {} end
local function prepend(path,base)
 if path.kind=='Root' then return base end
 if path.kind=='Field' then return B.Field(prepend(path.base,base),path.name) end
 if path.kind=='Case' then return B.Case(prepend(path.base,base),path.name) end
 return B.Element(prepend(path.base,base))
end
local function under(path,base)
 if path==base then return ROOT end
 if path.kind=='Root' then return nil end
 local tail=under(path.base,base);if not tail then return nil end
 if path.kind=='Field' then return B.Field(tail,path.name) end
 if path.kind=='Case' then return B.Case(tail,path.name) end
 return B.Element(tail)
end
local function project(value,path)
 local out=empty();out.unknown=value.unknown
 for p,set in pairs(value.refs) do local suffix=under(p,path);if suffix then out.refs[suffix]=set end end
 for p,codes in pairs(value.calls) do local suffix=under(p,path);if suffix then out.calls[suffix]=codes end end
 return out
end
local function component(dst,value,path)
 local out=empty();out.unknown=value.unknown
 for p,set in pairs(value.refs) do out.refs[prepend(p,path)]=set end
 for p,codes in pairs(value.calls) do out.calls[prepend(p,path)]=codes end
 return merge(dst,out)
end
local function seed(ty,frame,index,path,invocation)
 path=path or ROOT;local out=empty()
 if ty:isRef() or ty:isPtr() or ty:isSlice() or ty:isView() or ty:isOwned() or ty==S.Any then
  if ty~=S.Any then
   local route=invocation and B.OutputTarget(invocation,index,path) or B.InputTarget(frame,index,path)
   out.refs[ROOT]=single(location(route,ROOT,not ty:isSlice()))
  end
  if ty:isView() or ty:isOwned() or ty==S.Any then
   local code=invocation and B.ResultCode(invocation,index,path) or B.ParameterCode(frame,index,path)
   out.calls[ROOT]={[code]={origin=code,slots={}}}
  end
 elseif ty:isRecord() then
  for _,f in ipairs(ty.fields) do component(out,seed(f.type,frame,index,B.Field(path,f.name),invocation),B.Field(ROOT,f.name)) end
 elseif ty:isArray() then component(out,seed(ty.element,frame,index,B.Element(path),invocation),B.Element(ROOT))
 elseif ty:isTaggedType() then
  for _,f in ipairs(S.alternatives(ty)) do component(out,seed(f.type,frame,index,B.Case(path,f.name),invocation),B.Case(ROOT,f.name)) end
 end
 return out
end
local function sortedKeys(set,encode)
 local out={};for id in pairs(set) do out[#out+1]=encode and encode(id) or id end;table.sort(out);return out
end
local function factKey(value)
 local out={value.unknown and '?' or '!'}
 for _,p in ipairs(sortedKeys(value.refs,key)) do out[#out+1]=p end
 for p,set in pairs(value.refs) do for id in pairs(set) do out[#out+1]=key(p)..'='..id end end
 for p,codes in pairs(value.calls) do for id in pairs(codes) do out[#out+1]=key(p)..'@'..key(id) end end
 table.sort(out);return table.concat(out,';')
end
local function copyState(state) local out={};for id,v in pairs(state) do out[id]=clone(v) end;return out end
local function joinState(dst,src)
 local changed=false
 for id,v in pairs(src) do
  if not dst[id] then dst[id]=empty();changed=true end
  if merge(dst[id],v) then changed=true end
 end
 return changed
end
local function stateKey(state)
 local out={};for _,id in ipairs(sortedKeys(state,key)) do out[#out+1]=id end
 for id,v in pairs(state) do out[#out+1]=key(id)..'='..factKey(v) end
 table.sort(out);return table.concat(out,'|')
end
local function argKey(arg)
 if arg.targets then return (arg.readonly and 'R:' or 'W:')..(arg.unknown and '?' or '!')..table.concat(sortedKeys(arg.targets),';') end
 return 'V:'..factKey(arg.value)
end
local function ordered(set)
 local out={};for _,v in pairs(set) do out[#out+1]=v end
 table.sort(out,function(a,b) return accessKey(a)<accessKey(b) end);return out
end

-- Only provenance-bearing expression structure is retained. There are no scalar
-- operators/literals to interpret, no placement, and no executable call bodies.
-- Successor edges refer to the original checked control/effect points.
local function build(fn)
 local summary={fn=fn,nodes={},storageTypes={},placeParams={}}
 for _,p in ipairs(fn.params) do
  if p.kind=='PlaceParam' then summary.storageTypes[p.binding.id]=p.type;summary.placeParams[p.binding.id]=p.input end
 end
 local function types(body)
  for _,s in ipairs(body) do
   if s.kind=='Var' then summary.storageTypes[s.storage.id]=s.type
   elseif s.kind=='If' then types(s.yes);types(s.no)
   elseif s.kind=='Switch' then for _,c in ipairs(s.cases) do types(c.body) end
   elseif s.kind=='Loop' then types(s.body) end
  end
 end
 types(fn.body)
 local value,place
 place=function(p)
  local k=p.kind
  if k=='Local' then return {root=target(B.Local(fn.id,p.storage.id)),param=summary.placeParams[p.storage.id],type=summary.storageTypes[p.storage.id],readonly=false} end
  if k=='Global' then return {root=target(B.Global(p.root.identity)),type=p.root.type,readonly=not p.root.writable} end
  if k=='Project' or k=='Index' then
   local base=place(p.base)
   return {base=base,path=k=='Project' and B.Field(ROOT,p.field.name) or B.Element(ROOT),type=k=='Project' and S.field(base.type,p.field.name) or p.type,readonly=base.readonly}
  end
  if k=='Deref' then return {deref=place(p.base),type=p.type,readonly=false} end
  if k=='SliceIndex' or k=='PtrIndex' then return {view=value(p.view),type=p.type,readonly=k=='SliceIndex',pointer=k=='PtrIndex'} end
  D.bug('access-place','Unknown place in access summary')
 end
 local function expose(p)
  while p.base do p=p.base end
  if p.root and p.root.kind=='StorageRoot' and p.root.storage.kind=='Local' and not p.param then summary.fresh=true end
 end
 value=function(e)
  local k=e.kind
  if k=='Ref' then return {id=e.value.id,type=e.type} end
  if k=='Addr' then
   local p=place(e.place);expose(p)
   return {address=p,type=e.type,write=not e.access or e.access.kind=='WriteAccess'}
  end
  if k=='Get' then return {base=value(e.aggregate),path=e.field.kind=='Element' and B.Element(ROOT) or B.Field(ROOT,e.field.name),type=e.type} end
  if k=='Make' then
   local fields={};for i,f in ipairs(e.fields) do fields[i]=value(f) end
   return {fields=fields,type=e.type}
  end
  if k=='Convert' then return {conversion=value(e.operand),type=e.type} end
  if k=='Const' and e.type:isSlice() then return {literal=e.literal.bytes,type=e.type} end
  local children={}
  if k=='Un' or k=='Is' then children[1]=value(e.operand)
  elseif k=='Bin' then children[1]=value(e.left);children[2]=value(e.right)
  elseif k=='SliceLength' then children[1]=value(e.view) end
  return {type=e.type,children=children}
 end
 local function argument(a)
  if a.kind=='BorrowArg' then local p=place(a.place);expose(p);return {place=p} end
  return {value=value(a.value)}
 end
 local function arguments(args) local out={};for i,a in ipairs(args) do out[i]=argument(a) end;return out end
 local points={};local ordinal=0
 local function enumerate(body)
  for _,s in ipairs(body) do
   ordinal=ordinal+1;points[s]=B.Point(fn.id,ordinal)
   if s.kind=='If' then enumerate(s.yes);enumerate(s.no)
   elseif s.kind=='Switch' then for _,c in ipairs(s.cases) do enumerate(c.body) end
   elseif s.kind=='Loop' then enumerate(s.body) end
  end
 end
 enumerate(fn.body)
 local graph
 graph=function(body,nextPoint,backedge)
  local next=nextPoint
  for i=#body,1,-1 do
   local s=body[i];local point=points[s];local node={point=point,span=s.span,next=next and {next} or {}}
   local k=s.kind
   if k=='Let' then node.define=s.value.id;node.value=value(s.expr)
   elseif k=='Var' then node.initialize=target(B.Local(fn.id,s.storage.id));node.value=s.initial and value(s.initial);node.type=s.type
   elseif k=='Read' then node.define=s.value.id;node.read=place(s.place);node.type=s.type
   elseif k=='Store' then node.store=place(s.place);node.value=value(s.value);node.type=s.value.type
   elseif k=='View' then node.define=s.value.id;node.code=B.KnownCode(point);node.entry=s.entry;node.slots=arguments(s.slots);node.type=s.type;node.adapter=s.adapter and target(B.Local(fn.id,s.adapter.id))
   elseif k=='Call' or k=='Indirect' then
    node.invoke=k=='Call' and {target=s.target} or {value=value(s.callable)}
    node.arguments=arguments(s.arguments);node.results={}
    for j,v in ipairs(s.results) do node.results[j]=v.id end
    if k=='Indirect' then node.signature=s.callable.type==S.Any and nil or s.callable.type.visible end
   elseif k=='ConstructVariant' then node.define=s.value.id;node.variant=s.payload and value(s.payload);node.path=B.Case(ROOT,s.tag)
   elseif k=='VariantPayload' then node.define=s.value.id;node.value={base={id=s.variant.id},path=B.Case(ROOT,s.tag)}
   elseif k=='Return' then
    node.returns={};for j,e in ipairs(s.values) do node.returns[j]=value(e) end;node.next={}
   elseif k=='If' then
    node.observes={value(s.test)}
    local test=s.test.kind=='Const' and s.test.literal.kind=='Boolean' and s.test.literal or nil
    node.next={}
    if not test or test.value then local edge=graph(s.yes,next,backedge);if edge then node.next[#node.next+1]=edge end end
    if not test or not test.value then local edge=graph(s.no,next,backedge);if edge then node.next[#node.next+1]=edge end end
   elseif k=='Switch' then
    node.next={};for _,c in ipairs(s.cases) do local edge=graph(c.body,next,backedge);if edge then node.next[#node.next+1]=edge end end
   elseif k=='Loop' then node.next={graph(s.body,nil,point)}
   elseif k=='Next' then node.next=backedge and {backedge} or {}
   elseif k=='Dynamic' then node.opaque=true
   elseif k=='Trap' then node.observes={value(s.failure)};node.next={}
   end
   if node.adapter or (node.initialize and checkedAccess(node.type)) or (node.invoke and not node.invoke.target) then summary.fresh=true end
   summary.nodes[point]=node;next=point
  end
  return next
 end
 summary.entry=graph(fn.body)
 return summary
end

local function engine(program)
 local contexts,queue,bindings={}, {}, {}
 local head=1
 local stats={contexts=0,relations=0,iterations=0}
 for _,s in pairs(program) do for _ in pairs(s.nodes) do stats.relations=stats.relations+1 end end
 local function enqueue(ctx)
  if not ctx.queued then ctx.queued=true;queue[#queue+1]=ctx end
 end
 local function bindingChanged()
  for _,ctx in pairs(contexts) do enqueue(ctx) end
 end
 local function request(frame,args,state,context,folded)
  context=context or S.List{};folded=folded or false
  local parts={frame,key(O.Activation(frame,context,folded)),stateKey(state)};for i,a in ipairs(args) do parts[#parts+1]=i..':'..argKey(a) end
  local id=table.concat(parts,'\n');local ctx=contexts[id]
  if not ctx then
   ctx={id=id,summary=assert(program[frame]),context=context,folded=folded,args=args,input=copyState(state),users={},results={},state={},reads={},writes={},requirements={},transfers={},invocations={},failures={},ownership=Ownership.events(),unknown=false}
   contexts[id]=ctx;stats.contexts=stats.contexts+1;enqueue(ctx)
  end
  return ctx
 end
 local function run(ctx)
  local summary=ctx.summary;local fn=summary.fn
  local values,entry,aliases={},copyState(ctx.input),{}
  local out={results={},state={},reads={},writes={},requirements={},transfers={},invocations={},failures={},ownership=Ownership.events(),unknown=false}
  local extent=O.Activation(fn.id,ctx.context,ctx.folded)
  local function site(node) return O.Site(node.point,extent) end
  local function qualify(route)
   if route.kind=='StorageRoot' and route.storage.kind=='Local' and route.storage.frame==fn.id then
    return target(Ownership.localSource(fn.id,route.storage.storage,ctx.context,ctx.folded))
   end
   return route
  end
  local function codeAt(point)
   return #ctx.context==0 and B.KnownCode(point) or B.InstanceCode(point,ctx.context,ctx.folded)
  end
  for i in ipairs(fn.results) do out.results[i]=empty() end
  local function failure(code,message,node)
   local id=code..':'..key(node.point)
   out.failures[id]={code=code,message=message,span=node.span}
  end
  local function record(set,targets,node,write)
   for _,a in pairs(targets) do
    if write and not a.writable then failure('readonly-write','Write or mutable borrowing reaches readonly storage',node) end
    add(set,a)
   end
  end
  local function invalidate(state,targets)
   for _,a in pairs(targets) do local id=a.location.root;if state[id] then state[id].unknown=true end end
  end
  local function read(state,targets,ty,uncertain)
   local value=empty();value.unknown=uncertain and checkedAccess(ty) or false
   for _,a in pairs(targets) do
    local stored=state[a.location.root]
    if stored then merge(value,project(stored,a.location.path))
    elseif checkedAccess(ty) then value.unknown=true;out.unknown=true end
   end
   return value
  end
  for _,p in ipairs(fn.params) do
   local a=assert(ctx.args[p.input+1],'missing access summary argument')
   if p.kind=='PlaceParam' then
    local root=qualify(target(B.Local(fn.id,p.binding.id)));aliases[root]=a
   else values[p.binding.id]=clone(a.value) end
  end
  local place,fact,argument,store
  place=function(p,state,node)
   if p.root then
    local root=qualify(p.root);local alias=aliases[root]
    if alias then return alias.targets,alias.unknown end
    return single(location(root,ROOT,not p.readonly,nil,root.kind=='StorageRoot' and root.storage.kind~='Global')),false
   end
   if p.base then
    local base,uncertain=place(p.base,state,node);local targets={}
    for _,a in pairs(base) do add(targets,location(a.location.root,prepend(p.path,a.location.path),a.writable,a.source,a.current)) end
    return targets,uncertain
   end
   if p.deref then
    local base,uncertain=place(p.deref,state,node)
    local carried=read(state,base,p.deref.type,uncertain);local targets=at(carried,ROOT)
    if not next(targets) then out.unknown=true end
    return targets,carried.unknown
   end
   local value=fact(p.view,state,node);local targets={}
   if p.pointer then out.unknown=true end
   for _,a in pairs(at(value,ROOT)) do
    add(targets,location(a.location.root,p.pointer and a.location.path or B.Element(a.location.path),p.pointer and a.writable or false,a.source,a.current))
   end
   return targets,value.unknown
  end
  fact=function(term,state,node)
   if not term then return empty() end
   if term.id then return values[term.id] or empty() end
   if term.base then return project(fact(term.base,state,node),term.path) end
   if term.address then
    local targets,uncertain=place(term.address,state,node)
    if term.write then
     if term.address.readonly then failure('readonly-write','Mutable borrowing requires writable access',node) end
     record(out.requirements,targets,node,true)
    end
    local value=empty();value.refs[ROOT]=targets
    value.unknown=uncertain or term.address.pointer==true
    return value
   end
   if term.fields then
    local value=empty();local ty=term.type
    if ty:isSlice() then
     local targets={};for _,a in pairs(at(fact(term.fields[1],state,node),ROOT)) do add(targets,location(a.location.root,a.location.path,false,a.source,a.current)) end
     value.refs[ROOT]=targets
    elseif ty:isRecord() then for i,f in ipairs(ty.fields) do component(value,fact(term.fields[i],state,node),B.Field(ROOT,f.name)) end
    elseif ty:isArray() then for _,f in ipairs(term.fields) do component(value,fact(f,state,node),B.Element(ROOT)) end end
    return value
   end
   if term.conversion then
    local value=clone(fact(term.conversion,state,node))
    if term.conversion.type==S.Any and checkedAccess(term.type) then
     local hasContract=(term.type:isView() or term.type:isOwned()) and next(value.calls) or next(value.refs)
     if not hasContract then value.unknown=true end
    end
    return value
   end
   if term.literal then
    local value=empty();value.refs[ROOT]=single(location(target(B.Global('literal:'..term.literal)),ROOT,false));return value
   end
   for _,child in ipairs(term.children or {}) do fact(child,state,node) end
   return empty()
  end
  argument=function(a,state,node)
   if a.place then
    local targets,uncertain=place(a.place,state,node)
    return {targets=targets,unknown=uncertain,readonly=a.place.readonly,type=a.place.type}
   end
   return {value=clone(fact(a.value,state,node)),type=a.value.type}
  end
  store=function(state,targets,value,ty,node)
   if value.unknown and checkedAccess(ty) then failure('borrow-proof','Stored access has no established owner provenance',node) end
   local count=0;for _ in pairs(targets) do count=count+1 end
   for _,a in pairs(targets) do
    local destination=owner(a.location.root)
    for p,set in pairs(value.refs) do for _,retained in pairs(set) do
     local source=retained.source;local checked=checkedPath(ty,p)
     if checked then Ownership.hold(out.ownership,destination,source,site(node),node.span,a.current and retained.current and extent or nil) end
     local id=accessKey(a)..':'..key(p)..':'..accessKey(retained)
     out.transfers[id]={target=a,path=p,retained=retained,checked=checked}
    end end
    local route=a.location.path;local unique=a.location.root.kind=='StorageRoot' and (destination.kind=='Local' or destination.kind=='Instantiated' or destination.kind=='Recurring')
    while route.kind~='Root' do if route.kind=='Element' then unique=false end;route=route.base end
    local current=state[a.location.root] or empty();state[a.location.root]=current
    if unique and count==1 then
     for p in pairs(current.refs) do if under(p,a.location.path) then current.refs[p]=nil end end
     for p in pairs(current.calls) do if under(p,a.location.path) then current.calls[p]=nil end end
     if a.location.path==ROOT then current.unknown=false end
    end
    component(current,value,a.location.path)
   end
  end
  local function opaque(args,state,node)
   out.unknown=true
   for _,a in ipairs(args) do
    if a.targets or (a.type and checkedAccess(a.type)) then
     failure('borrow-proof','Opaque call has no checked retention contract for supplied access',node)
    end
    local sets=a.targets and {a.targets} or a.value.refs
    for _,targets in pairs(sets) do
     record(out.requirements,targets,node,true);record(out.reads,targets,node,false);record(out.writes,targets,node,true);invalidate(state,targets)
    end
   end
  end
  local function compose(frame,args,state,node)
   if not program[frame] then opaque(args,state,node);return nil end
   local bound={}
   for i,a in ipairs(args) do
    local input=program[frame].fn.inputs[i]
    if input.kind=='InValue' then bound[i]={value=external(a.targets and read(state,a.targets,input.type,a.unknown) or a.value)}
    else bound[i]={targets=externalTargets(a.targets),unknown=a.unknown,readonly=a.readonly,type=a.type} end
   end
   local transported={};for root,v in pairs(state) do transported[root]=external(v) end
   local context,folded=ctx.context,ctx.folded
   if program[frame].fresh then
    local repeated;context,repeated=Ownership.context(context,node.point);folded=folded or repeated
   end
   local child=request(frame,bound,transported,context,folded);child.users[ctx.id]=ctx
   Ownership.merge(out.ownership,child.ownership)
   mergeSet(out.requirements,child.requirements);mergeSet(out.reads,child.reads);mergeSet(out.writes,child.writes)
   for id,invocation in pairs(child.invocations) do out.invocations[id]=invocation end
   for id,f in pairs(child.failures) do out.failures[id]=f end
   out.unknown=out.unknown or child.unknown
   -- These are completed child-state relations at this invocation, not a bag of
   -- callback effects appended after unrelated stores in the caller.
   for root in pairs(state) do if child.state[root] then state[root]=external(child.state[root]) end end
   -- Fresh result roots carry their established contents back to the caller.
   -- Transport only reachable storage, not every local of the child activation.
   local pending,seen,carried,seenCodes={},{},{},{}
   local function targets(set)
    for _,a in pairs(set) do
     local root=a.location.root
     if not seen[root] then seen[root]=true;pending[#pending+1]=root end
    end
   end
   for _,v in ipairs(child.results) do carried[#carried+1]=v end
   local cursor,valueCursor=1,1
   while cursor<=#pending or valueCursor<=#carried do
    while valueCursor<=#carried do
     local v=carried[valueCursor];valueCursor=valueCursor+1
     for _,set in pairs(v.refs) do targets(set) end
     for _,codes in pairs(v.calls) do for code,binding in pairs(codes) do
      if not seenCodes[code] then
       seenCodes[code]=true
       for _,a in ipairs(binding.slots) do
        if a.targets then targets(a.targets) else carried[#carried+1]=a.value end
       end
      end
     end end
    end
    local root=pending[cursor]
    if root then
     cursor=cursor+1
     if child.state[root] then state[root]=external(child.state[root]);carried[#carried+1]=child.state[root] end
    end
   end
   for id,t in pairs(child.transfers) do
    local destination=owner(t.target.location.root)
    -- A copied input retained only in callee-local storage does not escape into
    -- the caller. The callee's own local-store/return checks still apply there.
    if destination.kind~='Instantiated' or destination.frame~=frame or O.Activation(destination.frame,destination.context,false)~=O.Activation(frame,child.context,child.folded) then
     out.transfers[id]=t
    end
   end
   local results={};for i,v in ipairs(child.results) do results[i]=external(v) end
   return results
  end
  local before,work,queued={}, {}, {}
  local function enqueuePoint(point,state)
   if not point then return end
   local first=not before[point];before[point]=before[point] or {}
   if joinState(before[point],state) or first then
    if not queued[point] then work[#work+1]=point;queued[point]=true end
   end
  end
  enqueuePoint(summary.entry,entry)
  local cursor=1
  while cursor<=#work do
   local point=work[cursor];cursor=cursor+1;queued[point]=nil
   local node=summary.nodes[point];local state=copyState(before[point]);local value
   for _,observation in ipairs(node.observes or {}) do fact(observation,state,node) end
   if node.initialize then
    local root=qualify(node.initialize);local initial=fact(node.value,state,node)
    store(state,single(location(root,ROOT,true,nil,true)),initial,node.type,node)
   elseif node.read then
    local targets,uncertain=place(node.read,state,node);record(out.reads,targets,node,false);value=read(state,targets,node.type,uncertain)
   elseif node.store then
    if node.store.readonly then failure('readonly-write','Writes require a writable place',node) end
    local targets=place(node.store,state,node);record(out.writes,targets,node,true)
    store(state,targets,fact(node.value,state,node),node.type,node)
   elseif node.code then
    local code=codeAt(node.point);local binding=bindings[code]
    if not binding then binding={origin=code,target=node.entry,slots={}};bindings[code]=binding end
    local changed=false
    for i,a in ipairs(node.slots) do
     local held=argument(a,state,node);local old=binding.slots[i]
     if not old then binding.slots[i]=held;changed=true
     elseif held.targets then
      if mergeSet(old.targets,held.targets) then changed=true end
      if held.readonly and not old.readonly then old.readonly=true;changed=true end
      if held.unknown and not old.unknown then old.unknown=true;changed=true end
     elseif merge(old.value,held.value) then changed=true end
    end
    if changed then bindingChanged() end
    value=empty();value.calls[ROOT]={[code]=binding}
    local adapter=node.adapter and qualify(node.adapter)
    if adapter then value.refs[ROOT]=single(location(adapter,ROOT,true,nil,true)) end
    for _,a in ipairs(binding.slots) do
     local sets=a.targets and {a.targets} or a.value.refs
     for p,set in pairs(sets) do
      -- A materialized callable retains its environment root. Its captures are
      -- outgoing environment holdings, not additional direct roots of the value.
      if not adapter then value.refs[ROOT]=value.refs[ROOT] or {};mergeSet(value.refs[ROOT],set) end
      if adapter and (a.targets or checkedPath(a.type,p)) then
       for _,retained in pairs(set) do Ownership.hold(out.ownership,owner(adapter),retained.source,site(node),node.span,retained.current and extent or nil) end
      end
     end
     if a.value then value.unknown=value.unknown or a.value.unknown end
    end
   elseif node.invoke then
    local args={};for i,a in ipairs(node.arguments) do args[i]=argument(a,state,node) end
    local returned={}
    if node.invoke.target then
     returned=compose(node.invoke.target,args,state,node)
     if not returned then
      returned={};for i in ipairs(node.results) do returned[i]=empty();returned[i].unknown=true end
     end
    else
     local callable=fact(node.invoke.value,state,node);local codes=callable.calls[ROOT] or {};local states={};local known=false
     for _,binding in pairs(codes) do
      known=true;local alternative=copyState(state);local part
      if binding.target then
       local actual={};for _,a in ipairs(binding.slots) do actual[#actual+1]=a end;for _,a in ipairs(args) do actual[#actual+1]=a end
       local targetSummary=program[binding.target]
       if not node.signature and targetSummary and #actual<#targetSummary.fn.inputs then
        -- Legacy Any partial supply forms a callable, not an invocation of a
        -- body with missing inputs. Preserve its supplied provenance as holdings.
        local code=codeAt(point);local partial=bindings[code]
        if not partial then partial={origin=code,target=binding.target,slots={}};bindings[code]=partial end
        local changed=false
        for i,a in ipairs(actual) do
         local held=partial.slots[i]
         if not held then partial.slots[i]=a;changed=true
         elseif a.targets then if mergeSet(held.targets,a.targets) then changed=true end
         elseif merge(held.value,a.value) then changed=true end
        end
        if changed then bindingChanged() end
        local v=empty();v.calls[ROOT]={[code]=partial}
        for _,a in ipairs(partial.slots) do
         for _,set in pairs(a.targets and {a.targets} or a.value.refs) do v.refs[ROOT]=v.refs[ROOT] or {};mergeSet(v.refs[ROOT],set) end
         if a.value then v.unknown=v.unknown or a.value.unknown end
        end
        part={v}
       else part=compose(binding.target,actual,alternative,node) end
      else
       local obligation=B.Invocation(point,binding.origin);out.invocations[obligation]=obligation
       part={}
       for i,id in ipairs(node.results) do
        local ty=node.signature and node.signature.results[i] or S.Any
        part[i]=seed(ty,fn.id,i-1,ROOT,point)
       end
      end
      joinState(states,alternative)
      if part then for i,v in ipairs(part) do returned[i]=returned[i] or empty();merge(returned[i],v) end
      else for i in ipairs(node.results) do returned[i]=returned[i] or empty();returned[i].unknown=true end end
     end
     if known then state=states
     else
      local supplied={{value=callable}};for _,a in ipairs(args) do supplied[#supplied+1]=a end
      opaque(supplied,state,node)
      for i in ipairs(node.results) do returned[i]=empty();returned[i].unknown=true end
     end
    end
    for i,id in ipairs(node.results) do
     values[id]=values[id] or empty();merge(values[id],returned[i] or empty())
    end
   elseif node.returns then
    for i,t in ipairs(node.returns) do
     local v=fact(t,state,node)
     if checkedAccess(fn.results[i]) then
      for p,set in pairs(v.refs) do for _,a in pairs(set) do
       if checkedPath(fn.results[i],p) then Ownership.returned(out.ownership,a.source,site(node),node.span) end
      end end
      if v.unknown then failure('borrow-proof','Returned access has no established owner provenance',node) end
     end
     merge(out.results[i],v)
    end
    joinState(out.state,state)
   elseif node.variant then value=empty();component(value,fact(node.variant,state,node),node.path)
   elseif node.value then value=fact(node.value,state,node)
   elseif node.opaque then out.unknown=true end
   if node.define then
    values[node.define]=values[node.define] or empty()
    if merge(values[node.define],value or empty()) then
     -- Value identities are immutable; loop-carried formations join possibilities.
     -- Requeue dependent reachable points without generating new binding trees.
     for p in pairs(before) do if not queued[p] then work[#work+1]=p;queued[p]=true end end
    end
   end
   for _,successor in ipairs(node.next) do enqueuePoint(successor,state) end
  end
  return out
 end
 local function drain()
  while head<=#queue do
   local ctx=queue[head];head=head+1;ctx.queued=false;stats.iterations=stats.iterations+1
   local next=run(ctx);local changed=false
   for _,field in ipairs{'reads','writes','requirements'} do if mergeSet(ctx[field],next[field]) then changed=true end end
   for _,field in ipairs{'transfers','invocations','failures'} do
    for id,v in pairs(next[field]) do if not ctx[field][id] then ctx[field][id]=v;changed=true end end
   end
   for i,v in ipairs(next.results) do ctx.results[i]=ctx.results[i] or empty();if merge(ctx.results[i],v) then changed=true end end
   if Ownership.merge(ctx.ownership,next.ownership) then changed=true end
   if joinState(ctx.state,next.state) then changed=true end
   if next.unknown and not ctx.unknown then ctx.unknown=true;changed=true end
   if changed then for _,user in pairs(ctx.users) do enqueue(user) end end
  end
 end
 return {request=request,drain=drain,stats=stats}
end

function M.analyze(functions)
 local start=os.clock();local program={};for _,fn in ipairs(functions) do program[fn.id]=build(fn) end
 -- Alpha-renaming is necessary only where a call can produce local root/code
 -- identities. Propagate that property through direct calls, including SCCs;
 -- scalar-only call chains must not acquire one query per full call path.
 local changed=true
 while changed do
  changed=false
  for _,s in pairs(program) do if not s.fresh then
   for _,node in pairs(s.nodes) do
    local child=node.invoke and node.invoke.target and program[node.invoke.target]
    if child and child.fresh then s.fresh=true;changed=true;break end
   end
  end end
 end
 local queries=engine(program);local roots,summaries={},{}
 for _,fn in ipairs(functions) do
  local args,state={},{}
  for i,input in ipairs(fn.inputs) do
   if input.kind=='InPlace' then
    local route=target(B.PlaceInput(fn.id,i-1,ROOT));args[i]={targets=single(location(route,ROOT,true)),readonly=false}
    state[route]=seed(input.type,fn.id,i-1)
   else args[i]={value=seed(input.type,fn.id,i-1)} end
  end
  roots[fn.id]=queries.request(fn.id,args,state)
 end
 queries.drain()
 for _,fn in ipairs(functions) do
  local summary=roots[fn.id]
  local function footprint(set)
   local list,seen={},{}
   for _,a in ipairs(ordered(set)) do local id=key(a.location);if not seen[id] then list[#list+1]=a.location;seen[id]=true end end
   return B.Footprint(S.List(list),summary.unknown)
  end
  local results={}
  for i,v in ipairs(summary.results) do
   local components={}
   for path,set in pairs(v.refs) do
    local sources,seen={},{}
    for _,a in ipairs(ordered(set)) do local id=key(a.source);if not seen[id] then sources[#sources+1]=a.source;seen[id]=true end end
    table.sort(sources,function(a,b) return key(a)<key(b) end)
    components[#components+1]=B.Component(path,B.Loans(S.List(sources)))
   end
   table.sort(components,function(a,b) return key(a.path)<key(b.path) end)
   results[i]=B.Contents(S.List(components))
  end
  local bounds,seen={},{}
  for _,t in pairs(summary.transfers) do
   if t.checked then
    local bound=B.Outlives(t.retained.source,owner(t.target.location.root));local id=key(bound)
    if not seen[id] then bounds[#bounds+1]=bound;seen[id]=true end
   end
  end
  table.sort(bounds,function(a,b) return key(a)<key(b) end)
  local invocations={};for _,v in pairs(summary.invocations) do invocations[#invocations+1]=v end
  table.sort(invocations,function(a,b) return key(a)<key(b) end)
  summaries[fn.id]={reads=footprint(summary.reads),writes=footprint(summary.writes),writable=footprint(summary.requirements),results=results,bounds=S.List(bounds),invocations=S.List(invocations)}
 end
 queries.stats.seconds=os.clock()-start
 return roots,summaries,queries.stats
end
function M.validate(functions,roots)
 for _,fn in ipairs(functions) do
  local failures={};for _,f in pairs(roots[fn.id].failures) do failures[#failures+1]=f end
  table.sort(failures,function(a,b)
   if a.code~=b.code then return a.code=='readonly-write' end
   return (a.message or '')<(b.message or '')
  end)
  if failures[1] then local f=failures[1];D.reject(f.code,f.message,f.span) end
 end
end
return M
