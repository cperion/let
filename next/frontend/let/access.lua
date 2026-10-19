-- Borrow/effect checking of the original typed IR. Ownership is declared by Rc.
-- A call-site binding has one monotone input and one result; changing memory is
-- never a query identity. Only argument-reachable storage and named globals cross
-- a call. There are no ownership demands, carrier dependency graphs, contents
-- versions, whole-caller-state keys or published per-instruction snapshots.
local S=require('let.schema')
local D=require('let.diag')
local Owner=require('let.ownership')
local B,O,I=S.Borrow,S.Ownership,S.Ir
local ROOT=B.Root
local M={}
local encoded=setmetatable({},{__mode='k'})
local function key(v) local s=encoded[v];if not s then s=S.encode(v);encoded[v]=s end;return s end
local function empty() return {refs={},calls={},tags={},unknown=false} end
local function owner(root)
 if root.kind=='StorageRoot' then return root.storage end
 if root.kind=='InputTarget' then return B.ValueInput(root.frame,root.parameter,root.path) end
 if root.kind=='ContentsTarget' then return B.ContentsInput(root.frame,root.read,root.operand,root.path) end
 return B.CallOutput(root.invocation,root.result,root.path)
end
local function access(root,path,writable,source,current,bad,borrowed)
 return {location=B.Location(root,path),source=source or owner(root),writable=writable,current=current or false,bad=bad or false,borrowed=borrowed or false}
end
local function accessKey(a) return key(a.location)..':'..key(a.source)..':'..tostring(a.writable)..':'..tostring(a.current)..':'..tostring(a.bad)..':'..tostring(a.borrowed) end
local function add(set,a) local k=accessKey(a);if set[k] then return false end;set[k]=a;return true end
local function singleton(a) local set={};add(set,a);return set end
local function union(a,b) local changed=false;for k,v in pairs(b or {}) do if not a[k] then a[k]=v;changed=true end end;return changed end
local function merge(a,b)
 local changed=false
 if b.unknown and not a.unknown then a.unknown=true;changed=true end
 for _,field in ipairs{'refs','calls','tags'} do for p,set in pairs(b[field]) do
  if not a[field][p] then a[field][p]={};changed=true end
  if union(a[field][p],set) then changed=true end
 end end
 return changed
end
local function clone(v) local out=empty();merge(out,v);return out end
local function append(path,base)
 if path.kind=='Root' then return base end
 if path.kind=='Field' then return B.Field(append(path.base,base),path.name) end
 if path.kind=='Case' then return B.Case(append(path.base,base),path.name) end
 if path.kind=='Index' then return B.Index(append(path.base,base),path.index) end
 return B.Element(append(path.base,base))
end
local function aliases(a,b)
 if a==b then return true end
 if a.kind=='Root' or b.kind=='Root' then return false end
 local element=a.kind=='Element' and (b.kind=='Element' or b.kind=='Index') or b.kind=='Element' and a.kind=='Index'
 return (element or a.kind==b.kind and a.name==b.name and a.index==b.index) and aliases(a.base,b.base)
end
local function under(path,base,exact)
 if path==base or not exact and aliases(path,base) then return ROOT end
 if path.kind=='Root' then return nil end
 local tail=under(path.base,base,exact);if not tail then return nil end
 if path.kind=='Field' then return B.Field(tail,path.name) end
 if path.kind=='Case' then return B.Case(tail,path.name) end
 if path.kind=='Index' then return B.Index(tail,path.index) end
 return B.Element(tail)
end
local function overlaps(a,b) return a.root==b.root and (under(a.path,b.path)~=nil or under(b.path,a.path)~=nil) end
local function project(v,path)
 local out=empty();out.unknown=v.unknown
 for _,field in ipairs{'refs','calls','tags'} do for p,set in pairs(v[field]) do
  local suffix=under(p,path);if suffix then out[field][suffix]=out[field][suffix] or {};union(out[field][suffix],set) end
 end end
 return out
end
local function component(dst,v,path)
 if v.unknown then dst.unknown=true end
 for _,field in ipairs{'refs','calls','tags'} do for p,set in pairs(v[field]) do
  local at=append(p,path);dst[field][at]=dst[field][at] or {};union(dst[field][at],set)
 end end
end
local function cross(v)
 local out=clone(v)
 for p,set in pairs(v.refs) do out.refs[p]={};for _,a in pairs(set) do add(out.refs[p],access(a.location.root,a.location.path,a.writable,a.source,false,a.bad,a.borrowed)) end end
 return out
end
local function crossTargets(set)
 local out={};for _,a in pairs(set) do add(out,access(a.location.root,a.location.path,a.writable,a.source,false,a.bad,a.borrowed)) end;return out
end
-- Scalar register/storage contents are not borrow facts. Do not copy them
-- through CFG states merely because the original IR has an SSA binding.
local function meaningful(v) return v.unknown or next(v.refs) or next(v.calls) or next(v.tags) end
local function put(map,k,v) map[k]=meaningful(v) and v or nil end
local function copyMap(map) local out={};for k,v in pairs(map) do out[k]=clone(v) end;return out end
local function joinMap(dst,src)
 local changed=false
 for k,v in pairs(src) do if meaningful(v) then
  if not dst[k] then dst[k]=clone(v);changed=true elseif merge(dst[k],v) then changed=true end
 end end
 return changed
end
local function seed(t,frame,index,path,point,operand)
 path=path or ROOT;local v=empty()
 if t:isRc() or t:isRef() or t:isPtr() or t:isSlice() or t:isView() or t:isOwned() or t==S.Any then
  if t~=S.Any then
   local root=point and B.ContentsTarget(frame,point,operand,path) or B.InputTarget(frame,index,path)
   v.refs[ROOT]=singleton(access(root,ROOT,not t:isSlice()))
  end
  if t:isView() or t:isOwned() or t==S.Any then
   local code=point and B.ContentsCode(point,operand,path) or B.ParameterCode(frame,index,path)
   v.calls[ROOT]={[code]={origin=code}}
  end
 elseif t:isRecord() then for _,f in ipairs(t.fields) do component(v,seed(f.type,frame,index,B.Field(path,f.name),point,operand),B.Field(ROOT,f.name)) end
 elseif t:isArray() and Owner.checkedAccess(t.element) then for i=0,t.length-1 do component(v,seed(t.element,frame,index,B.Index(path,i),point,operand),B.Index(ROOT,i)) end
 elseif t:isTaggedType() then
  v.tags[ROOT]={}
  for _,f in ipairs(S.alternatives(t)) do v.tags[ROOT][f.name]=true;component(v,seed(f.type,frame,index,B.Case(path,f.name),point,operand),B.Case(ROOT,f.name)) end
 end
 return v
end
-- CFG nodes reference original statements, not a second expression/value IR.
local function graph(fn)
 local g={fn=fn,nodes={},types={},values={},origins={},scopes={},globals={},calls={},contextFree=true}
 local function scalar(t) return t:isInteger() or t==S.F64 or t==S.Bool or t==S.Unit end
 for _,input in ipairs(fn.inputs) do if input.kind~='InValue' or not scalar(input.type) then g.contextFree=false end end
 for _,t in ipairs(fn.results) do if not scalar(t) then g.contextFree=false end end
 for _,p in ipairs(fn.params) do
  if p.kind=='PlaceParam' then g.types[p.binding.id]=p.type else g.values[p.binding.id]={type=p.type,scope=0} end
 end
 local ordinal,scope=0,0
 local function block(body,nextPoint,backedge,parent)
  scope=scope+1;local current=scope;g.scopes[current]=parent or 0
  local points={}
  for _,s in ipairs(body) do
   ordinal=ordinal+1;local p=B.Point(fn.id,ordinal);points[s]=p
   local node={point=p,stmt=s,scope=current};g.nodes[p]=node
   if s.kind=='Var' then g.types[s.storage.id]=s.type;g.origins[s.storage.id]=node
   elseif s.kind=='RcNew' then g.types[s.root.id]=s.initial.type;g.origins[s.root.id]=node
   elseif s.kind=='View' and s.adapter then g.origins[s.adapter.id]=node end
   if s.kind=='Let' or s.kind=='Read' or s.kind=='RcNew' or s.kind=='View' or s.kind=='ConstructVariant' or s.kind=='VariantPayload' or s.kind=='VariantMatches' then
    g.values[s.value.id]={point=p,scope=current,type=s.kind=='VariantPayload' and S.caseOf(s.sum,s.tag) or s.kind=='VariantMatches' and S.Bool or s.type}
   end
   for _,v in ipairs(s.results or {}) do g.values[v.id]={point=p,scope=current} end
  end
  local next=nextPoint
  for i=#body,1,-1 do
   local s=body[i];local p=points[s];local n=g.nodes[p];n.next=next and {next} or {}
   if s.kind=='Return' then n.next={}
   elseif s.kind=='If' then
    n.next={};local literal=s.test.kind=='Const' and s.test.literal.kind=='Boolean' and s.test.literal
    if not literal or literal.value then local to=block(s.yes,next,backedge,current);if to then n.next[#n.next+1]=to end end
    if not literal or not literal.value then local to=block(s.no,next,backedge,current);if to then n.next[#n.next+1]=to end end
   elseif s.kind=='Switch' then
    n.next={};n.cases={}
    for _,c in ipairs(s.cases) do local to=block(c.body,next,backedge,current);if to then n.next[#n.next+1]=to;n.cases[to]=c.tag end end
   elseif s.kind=='Loop' then n.next={block(s.body,nil,p,current)}
   elseif s.kind=='Next' then n.next=backedge and {backedge} or {}
   elseif s.kind=='Trap' and s.failure.kind=='Const' and s.failure.literal.kind=='Boolean' and s.failure.literal.value then n.next={} end
   next=p
  end
  return next
 end
 g.entry=block(fn.body)
 require('let.walk').walk(fn,{enter=function(n)
  if S.Ty.V:isclassof(n) then return false end
  if I.Call:isclassof(n) then g.calls[n.target]=true
  elseif I.View:isclassof(n) or I.Code:isclassof(n) then g.calls[n.entry]=true end
  if I.Global:isclassof(n) then g.globals[B.StorageRoot(B.Global(n.root.identity))]=true end
 end})
 return g
end
local function ordered(set) local out={};for _,v in pairs(set) do out[#out+1]=v end;table.sort(out,function(a,b)return accessKey(a)<accessKey(b)end);return out end
function M.analyze(functions)
 local started=os.clock();local graphs,definitions={},{}
 local stats={contexts=0,iterations=0,relations=0,points=0}
 for _,fn in ipairs(functions) do definitions[fn.id]=fn;graphs[fn.id]=graph(fn);for _ in pairs(graphs[fn.id].nodes) do stats.relations=stats.relations+1 end end
 -- Named global effects are transitive, unlike caller frame storage.
 local changed=true
 while changed do changed=false
  for _,g in pairs(graphs) do for target in pairs(g.calls) do
   if graphs[target] and union(g.globals,graphs[target].globals) then changed=true end
  end end
 end
 for _,g in pairs(graphs) do if next(g.globals) then g.contextFree=false end end
 local contexts,queue,head={}, {},1
 local function enqueue(c) if not c.queued then c.queued=true;queue[#queue+1]=c end end
 local function reachable(memory,args,globals)
  local selected,pending,seen={}, {},{}
  local function root(r) if not seen[r] then seen[r]=true;pending[#pending+1]=r end end
  local function value(v) for _,set in pairs(v.refs) do for _,a in pairs(set) do root(a.location.root) end end end
  for _,a in ipairs(args) do if a.targets then for _,r in pairs(a.targets) do root(r.location.root) end else value(a.value) end end
  for r in pairs(globals or {}) do root(r) end
  local i=1
  while i<=#pending do local r=pending[i];i=i+1;local v=memory[r]
   if v then selected[r]=cross(v);value(v) end
  end
  return selected,seen
 end
 local function request(name,args,memory,path,folded)
  path=path or S.List{};folded=folded or false
  local identity=O.Activation(name,path,folded);local c=contexts[identity]
  if not c then
   c={id=identity,g=graphs[name],context=path,folded=folded,args={},input={},visible={},users={},results={},state={},reads={},writes={},requirements={},strong={},failures={},invocations={},normal=false}
   contexts[identity]=c;stats.contexts=stats.contexts+1
  end
  local changed=false
  for i,a in ipairs(args) do
   local old=c.args[i]
   if not old then c.args[i]=a.targets and {targets=crossTargets(a.targets),type=a.type,unknown=a.unknown} or {value=cross(a.value),type=a.type};changed=true
   elseif a.targets then if union(old.targets,crossTargets(a.targets)) then changed=true end;if a.unknown and not old.unknown then old.unknown=true;changed=true end
   elseif merge(old.value,cross(a.value)) then changed=true end
  end
  local incoming,visible=reachable(memory,args,c.g.globals)
  if joinMap(c.input,incoming) then changed=true end
  if union(c.visible,visible) then changed=true end
  if changed or not c.ran then enqueue(c) end
  return c
 end
 local function run(c)
  local g,fn=c.g,c.g.fn
  local out={results={},state={},reads={},writes={},requirements={},strong={},failures={},invocations={},normal=false}
  for i in ipairs(fn.results) do out.results[i]=empty() end
  local aliasesByStorage={};local initial={values={},memory=copyMap(c.input)}
  for _,p in ipairs(fn.params) do local a=c.args[p.input+1]
   if p.kind=='PlaceParam' then aliasesByStorage[p.binding.id]=a else put(initial.values,p.binding.id,clone(a.value)) end
  end
  local function root(storage,heap)
   local source=heap and B.Heap(fn.id,storage,c.context,c.folded) or Owner.localSource(fn.id,storage,c.context,c.folded)
   return B.StorageRoot(source)
  end
  local function failure(code,message,node)
   out.failures[code..':'..node.point.ordinal]={code=code,message=message..' ('..fn.id..')',span=node.stmt.span}
  end
  local function checkAccess(set,node)
   for _,a in pairs(set) do if a.bad then failure('borrow-invalidated','Borrow used after its storage or holding was invalidated',node) end end
  end
  local function checkValue(v,t,node)
   local function covered(ty,path)
    if ty:isRc() or ty:isRef() or ty:isSlice() then return v.refs[path] and next(v.refs[path])~=nil end
    if ty:isRecord() then for _,f in ipairs(ty.fields) do if not covered(f.type,B.Field(path,f.name)) then return false end end
    elseif ty:isArray() and Owner.checkedAccess(ty.element) then for i=0,ty.length-1 do if not covered(ty.element,B.Index(path,i)) then return false end end
    elseif ty:isTaggedType() and Owner.checkedAccess(ty) then
     local tags=v.tags[path];if not tags then return false end
     for tag in pairs(tags) do if not covered(S.caseOf(ty,tag),B.Case(path,tag)) then return false end end
    end
    return true
   end
   if Owner.checkedAccess(t) and (v.unknown or not covered(t,ROOT)) then failure('borrow-proof','Access has no established provenance',node) end
   for path,set in pairs(v.refs) do
    local ty=t~=S.Any and Owner.selected(t,path)
    local next={}
    for _,a in pairs(set) do
     local borrowed=a.borrowed
     if ty then borrowed=ty:isRef() or ty:isSlice() or ty:isView() or ty:isOwned() end
     local item=access(a.location.root,a.location.path,a.writable,a.source,a.current,a.bad,borrowed);add(next,item)
     if borrowed then checkAccess(singleton(item),node) end
    end
    v.refs[path]=next
   end
  end
  local function publish(which,targets)
   for _,a in pairs(targets) do
    if c.visible[a.location.root] or a.location.root.kind~='StorageRoot' then add(out[which],a) end
   end
  end
  local function record(which,targets,node,write)
   checkAccess(targets,node);publish(which,targets)
   if write then for _,a in pairs(targets) do if not a.writable then failure('readonly-write','Write or mutable borrowing reaches readonly storage',node) end end end
  end
  local function typeOf(p)
   if p.kind=='Local' then return g.types[p.storage.id] end
   if p.kind=='Global' then return p.root.type end
   if p.kind=='Project' then return S.field(typeOf(p.base),p.field.name) end
   return p.type
  end
  local function poison(state,predicate)
   local function value(v)
    local result=clone(v)
    for p,set in pairs(v.refs) do
     local next={};for _,a in pairs(set) do add(next,access(a.location.root,a.location.path,a.writable,a.source,a.current,a.bad or predicate(a.source),a.borrowed)) end
     result.refs[p]=next
    end
    return result
   end
   for id,v in pairs(state.values) do state.values[id]=value(v) end
   for id,v in pairs(state.memory) do state.memory[id]=value(v) end
  end
  local function written(source,locations)
   if source.kind~='FieldGuard' then return false end
   for _,a in pairs(locations) do if overlaps(source.slot,a.location) then return true end end
   return written(source.parent,locations)
  end
  local function invalidate(state,locations) poison(state,function(source)return written(source,locations)end) end
  local function localSource(source)
   return source.frame==fn.id and Owner.sameContext(source.context,c.context)
  end
  local function redefined(source,node)
   if source.kind=='FieldGuard' then return redefined(source.parent,node) end
   if not localSource(source) then return false end
   if source.kind=='ValueGuard' then return g.values[source.value] and g.values[source.value].point==node.point end
   if source.kind=='Local' or source.kind=='Instantiated' or source.kind=='Recurring' then return g.origins[source.storage]==node end
   return false
  end
  local function containsScope(parent,child)
   if parent==0 then return true end
   while child and child~=0 do if child==parent then return true end;child=g.scopes[child] end
   return false
  end
  local function scopeEnded(source,to)
   if source.kind=='FieldGuard' then return scopeEnded(source.parent,to) end
   if not localSource(source) then return false end
   if source.kind=='ValueGuard' then local origin=g.values[source.value];return origin and not containsScope(origin.scope,to) end
   if source.kind=='Local' or source.kind=='Instantiated' or source.kind=='Recurring' then
    local origin=g.origins[source.storage];local ty=g.types[source.storage]
    return origin and ty and S.hasRc(ty) and not containsScope(origin.scope,to)
   end
   return false
  end
  local expr,place,argument,store
  local function read(state,targets,ty,node,operand)
   record('reads',targets,node,false);local v=empty()
   for _,a in pairs(targets) do
    local r=a.location.root;local stored=state.memory[r];local part=stored and project(stored,a.location.path)
    if r.kind=='InputTarget' or r.kind=='ContentsTarget' or r.kind=='OutputTarget' then
     local fallback=seed(ty,r.frame or fn.id,0,ROOT,node.point,operand or 0)
     if not part then part=fallback else
      for _,field in ipairs{'refs','calls','tags'} do for path,set in pairs(fallback[field]) do if not part[field][path] then part[field][path]=set end end end
     end
    end
    if part then merge(v,part) elseif Owner.checkedAccess(ty) then v.unknown=true end
   end
   checkValue(v,ty,node);return v
  end
  place=function(p,state,node)
   local k=p.kind
   if k=='Local' then
    local a=aliasesByStorage[p.storage.id]
    if a then checkAccess(a.targets,node);return a.targets end
    return singleton(access(root(p.storage.id),ROOT,true,nil,true))
   elseif k=='Global' then return singleton(access(B.StorageRoot(B.Global(p.root.identity)),ROOT,p.root.writable))
   elseif k=='Project' or k=='Index' then
    local base=place(p.base,state,node);local path
    if k=='Project' then path=B.Field(ROOT,p.field.name) else
     expr(p.index,state,node);local constant=p.index.kind=='Const' and p.index.literal.kind=='UInt' and p.index.literal.value
     path=constant and B.Index(ROOT,constant) or B.Element(ROOT)
    end
    local set={};for _,a in pairs(base) do add(set,access(a.location.root,append(path,a.location.path),a.writable,a.source,a.current,a.bad)) end;return set
   elseif k=='Deref' then
    local v=read(state,place(p.base,state,node),typeOf(p.base),node,0);return v.refs[ROOT] or {}
   elseif k=='SliceIndex' or k=='PtrIndex' then
    local v=expr(p.view,state,node);expr(p.index,state,node);local set={}
    if k=='PtrIndex' then out.unknown=true end
    for _,a in pairs(v.refs[ROOT] or {}) do add(set,access(a.location.root,k=='PtrIndex' and a.location.path or B.Element(a.location.path),k=='PtrIndex' and a.writable or false,a.source,a.current,a.bad)) end
    return set
   end
   D.bug('access-place','Unknown place '..k)
  end
  expr=function(e,state,node)
   local k=e.kind;local v=empty()
   if k=='Ref' then v=state.values[e.value.id] or empty()
   elseif k=='Addr' then
    v.refs[ROOT]=place(e.place,state,node)
    if not e.access or e.access.kind=='WriteAccess' then record('requirements',v.refs[ROOT],node,true) end
   elseif k=='RcBorrow' then
    if e.holding.kind=='BorrowArg' then
     for _,slot in pairs(place(e.holding.place,state,node)) do
      local held=read(state,singleton(slot),typeOf(e.holding.place),node,0)
      for _,a in pairs(held.refs[ROOT] or {}) do v.refs[ROOT]=v.refs[ROOT] or {};add(v.refs[ROOT],access(a.location.root,a.location.path,a.writable,B.FieldGuard(slot.source,slot.location),slot.current,a.bad)) end
     end
    else
     local holding=e.holding.value;local held=expr(holding,state,node)
     local guard=B.ValueGuard(fn.id,holding.value.id,c.context,c.folded)
     for _,a in pairs(held.refs[ROOT] or {}) do v.refs[ROOT]=v.refs[ROOT] or {};add(v.refs[ROOT],access(a.location.root,a.location.path,a.writable,guard,true,a.bad)) end
    end
   elseif k=='Get' then v=project(expr(e.aggregate,state,node),e.field.kind=='Field' and B.Field(ROOT,e.field.name) or B.Index(ROOT,e.field.index))
   elseif k=='Make' then
    if e.type:isSlice() then
     local first=expr(e.fields[1],state,node);v.unknown=first.unknown;v.refs[ROOT]={}
     for _,a in pairs(first.refs[ROOT] or {}) do add(v.refs[ROOT],access(a.location.root,a.location.path,false,a.source,a.current,a.bad)) end
     for i=2,#e.fields do expr(e.fields[i],state,node) end
    else for i,f in ipairs(e.fields) do component(v,expr(f,state,node),e.type:isArray() and B.Index(ROOT,i-1) or B.Field(ROOT,e.type.fields[i].name)) end end
   elseif k=='Convert' then
    v=clone(expr(e.operand,state,node))
    if e.operand.type==S.Any and Owner.checkedAccess(e.type) and not next(v.refs) and not next(v.calls) then v.unknown=true end
   elseif k=='Const' and e.type:isSlice() then v.refs[ROOT]=singleton(access(B.StorageRoot(B.Global('literal:'..e.literal.bytes)),ROOT,false))
   elseif k=='Code' then local code=B.KnownCode(node.point);v.calls[ROOT]={[code]={origin=code,target=e.entry,captures={}}}
   else e:each(function(child)expr(child,state,node)end) end
   checkValue(v,e.type,node);return v
  end
  argument=function(a,state,node)
   if a.kind=='BorrowArg' then return {targets=place(a.place,state,node),type=typeOf(a.place)} end
   return {value=expr(a.value,state,node),type=a.value.type}
  end
  store=function(state,targets,v,ty,node,initializing)
   checkValue(v,ty,node)
   if S.hasRc(ty) and not next(targets) then failure('borrow-proof','Owning store has no established target for strong-edge checking',node) end
   if not initializing then record('writes',targets,node,true);invalidate(state,targets) end
   local n=0;for _ in pairs(targets) do n=n+1 end
   for _,a in pairs(targets) do
    local holder=owner(a.location.root)
    for p,set in pairs(v.refs) do if ty==S.Any or Owner.checkedPath(ty,p) then
     local owning=ty~=S.Any and Owner.selected(ty,p):isRc()
     for _,r in pairs(set) do
      if owning then
       if holder.kind=='Heap' or holder.kind=='Global' or holder.kind=='ValueInput' or holder.kind=='PlaceInput' or holder.kind=='ContentsInput' then
        local edge=O.Edge(Owner.root(holder),Owner.root(r.source),O.Site(node.point,O.Activation(fn.id,c.context,c.folded)));out.strong[edge]=true
       end
      elseif r.borrowed and not Owner.borrowStore(holder,r.source,a.current and r.current) then failure('borrow-escape','Stored borrow outlives its protecting storage or holding',node) end
     end
    end end
    local current=state.memory[a.location.root] or empty();current=clone(current)
    local exact=n==1 and a.location.root.kind=='StorageRoot'
    local path=a.location.path;while path.kind~='Root' do if path.kind=='Element' then exact=false end;path=path.base end
    if exact then
     for _,field in ipairs{'refs','calls','tags'} do for p in pairs(current[field]) do if under(p,a.location.path,true) then current[field][p]=nil end end end
     if a.location.path==ROOT then current.unknown=false end
    end
    component(current,v,a.location.path);put(state.memory,a.location.root,current)
   end
  end
  local function opaque(args,node)
   out.unknown=true
   for _,a in ipairs(args) do
    local borrowed=a.targets or a.type and Owner.checkedAccess(a.type)
    if a.value then for _,set in pairs(a.value.refs) do for _,r in pairs(set) do borrowed=borrowed or r.borrowed and r.source.kind~='Global' end end end
    if borrowed then failure('borrow-proof','Opaque effect has no checked retention contract',node) end
   end
  end
  local function invoke(name,args,state,node)
   local callee=graphs[name]
   if not callee then opaque(args,node);return nil,true end
   if #args<#callee.fn.inputs then
    failure('Rc-interface','Owning runtime partial-call environments are not admitted',node);return nil,false
   elseif #args>#callee.fn.inputs then opaque(args,node);return nil,true end
   local bound={}
   for i,input in ipairs(callee.fn.inputs) do
    local a=assert(args[i],'missing checked argument')
    bound[i]=input.kind=='InValue' and {value=a.value or read(state,a.targets,input.type,node,i),type=input.type} or {targets=a.targets,type=input.type}
   end
   -- A scalar-only boundary with no named-global access cannot share storage
   -- with its caller. Check its locals normally, once; do not create call-path
   -- instances for private lifetimes that cannot cross the boundary.
   local path,repeated,folded
   if not callee.contextFree then path,repeated=Owner.context(c.context,node.point);folded=c.folded or repeated end
   local child=request(name,bound,state.memory,path,folded);child.users[c.id]=c
   for _,field in ipairs{'reads','writes','requirements'} do publish(field,child[field]) end
   for _,field in ipairs{'strong','failures','invocations'} do union(out[field],child[field]) end
   if child.unknown then out.unknown=true end
   if not child.normal then return nil,false end
   invalidate(state,child.writes)
   -- Import only normal-return effects and reachable results, never a callee's
   -- private scratch/frame state. Unchanged input storage is not overwritten.
   local changedRoots={};for _,a in pairs(child.writes) do changedRoots[a.location.root]=true end
   for r in pairs(changedRoots) do if child.state[r] then state.memory[r]=cross(child.state[r]) end end
   local results={};local roots={}
   for i,v in ipairs(child.results) do results[i]=cross(v);roots[i]={value=results[i]} end
   for r,v in pairs(reachable(child.state,roots)) do state.memory[r]=v end
   return results,true
  end
  local before,work,queued={}, {},{}
  local function enqueuePoint(p,state)
   if not p then return end
   local old=before[p];local changed=false
   if not old then old={values=copyMap(state.values),memory=copyMap(state.memory)};before[p]=old;changed=true
   else if joinMap(old.values,state.values) then changed=true end;if joinMap(old.memory,state.memory) then changed=true end end
   if changed and not queued[p] then queued[p]=true;work[#work+1]=p end
  end
  enqueuePoint(g.entry,initial)
  local cursor=1
  while cursor<=#work do
   local p=work[cursor];cursor=cursor+1;queued[p]=nil;stats.points=stats.points+1
   local node=g.nodes[p];local s=node.stmt;local state={values=copyMap(before[p].values),memory=copyMap(before[p].memory)}
   local k=s.kind;local proceed=true
   if s.value and I.Value:isclassof(s.value) or s.results or k=='Var' or k=='View' then poison(state,function(source)return redefined(source,node)end) end
   if k=='RcNew' then
    local v=expr(s.initial,state,node);local r=root(s.root.id,true)
    store(state,singleton(access(r,ROOT,true,nil,true)),v,s.initial.type,node,true)
    local held=empty();held.refs[ROOT]=singleton(access(r,ROOT,true,nil,true));state.values[s.value.id]=held
   elseif k=='Let' then put(state.values,s.value.id,clone(expr(s.expr,state,node)))
   elseif k=='Var' then
    local v=s.initial and expr(s.initial,state,node) or empty()
    if s.initial then store(state,singleton(access(root(s.storage.id),ROOT,true,nil,true)),v,s.type,node,true)
    else state.memory[root(s.storage.id)]=nil end
   elseif k=='Read' then put(state.values,s.value.id,read(state,place(s.place,state,node),s.type,node,0))
   elseif k=='Store' then local targets=place(s.place,state,node);local v=expr(s.value,state,node);store(state,targets,v,s.value.type,node)
   elseif k=='ConstructVariant' then
    local v=empty();v.tags[ROOT]={[s.tag]=true};if s.payload then component(v,expr(s.payload,state,node),B.Case(ROOT,s.tag)) end;state.values[s.value.id]=v
   elseif k=='VariantPayload' then put(state.values,s.value.id,project(state.values[s.variant.id] or empty(),B.Case(ROOT,s.tag)))
   elseif k=='VariantMatches' then checkValue(state.values[s.variant.id] or empty(),s.sum,node);state.values[s.value.id]=nil
   elseif k=='View' then
    local code=#c.context==0 and B.KnownCode(p) or B.InstanceCode(p,c.context,c.folded)
    local binding={origin=code,target=s.entry,captures={}};local v=empty();v.calls[ROOT]={[code]=binding}
    if s.adapter then
     binding.environment=root(s.adapter.id);state.memory[binding.environment]=nil
     v.refs[ROOT]=singleton(access(binding.environment,ROOT,true,nil,true,false,true))
    end
    for i,a in ipairs(s.slots) do
     local held=argument(a,state,node);binding.captures[i]={borrowed=held.targets~=nil,type=held.type}
     if not binding.environment then D.bug('access-environment','Captures require their actual environment storage') end
     local saved=held.value;local ty=held.type
     if held.targets then saved=empty();saved.refs[ROOT]=held.targets;ty=S.Ref(ty) end
     local field=B.Field(ROOT,string.format('_%04d',i))
     store(state,singleton(access(binding.environment,field,true,nil,true)),saved,ty,node,true)
    end
    state.values[s.value.id]=v
   elseif k=='Call' or k=='Indirect' then
    local args={};for i,a in ipairs(s.arguments) do args[i]=argument(a,state,node) end
    local returned
    if k=='Call' then returned,proceed=invoke(s.target,args,state,node)
    else
     local callable=expr(s.callable,state,node);local codes=callable.calls[ROOT] or {};local joined={values={},memory={}};returned={};proceed=false
     for _,binding in pairs(codes) do
      local alternative={values=copyMap(state.values),memory=copyMap(state.memory)};local part,normal
      if binding.target then
       local actual={}
       for i,a in ipairs(binding.captures) do
        local ty=definitions[binding.target].inputs[i].type
        local captured=read(alternative,singleton(access(binding.environment,B.Field(ROOT,string.format('_%04d',i)),false)),a.borrowed and S.Ref(ty) or ty,node,i)
        actual[#actual+1]=a.borrowed and {targets=captured.refs[ROOT] or {},type=ty} or {value=captured,type=ty}
       end
       for _,a in ipairs(args) do actual[#actual+1]=a end
       part,normal=invoke(binding.target,actual,alternative,node)
      else
       local obligation=B.Invocation(p,binding.origin);out.invocations[obligation]=obligation;part={};normal=true
       local sig=s.callable.type.visible
       for i in ipairs(s.results) do part[i]=sig and seed(sig.results[i],fn.id,i-1,ROOT,p,0) or empty() end
      end
      if normal then
       proceed=true;joinMap(joined.values,alternative.values);joinMap(joined.memory,alternative.memory)
       for i in ipairs(s.results) do
        local v=part and part[i] or empty();if not part then v.unknown=true end
        returned[i]=returned[i] or empty();merge(returned[i],v)
       end
      end
     end
     if not next(codes) then
      if callable.unknown or s.callable.type==S.Any then opaque(args,node);returned=nil;proceed=true
      else failure('borrow-proof','Callable has no established target or input contract',node) end
     end
     if proceed and next(codes) then state=joined end
    end
    if proceed then for i,v in ipairs(s.results) do
     local r=returned and returned[i] or empty();if not returned then r.unknown=true end;put(state.values,v.id,r)
    end end
   elseif k=='Return' then
    out.normal=true;local exported={}
    for i,e in ipairs(s.values) do
     local v=expr(e,state,node)
     for _,set in pairs(v.refs) do
      for _,a in pairs(set) do if a.borrowed and Owner.localTo(a.source,fn.id,c.context) then failure('borrow-escape','Returned borrow names a dying local or Rc holding',node) end end
     end
     merge(out.results[i],v);exported[i]={value=v}
    end
    local writtenRoots={};for _,a in pairs(out.writes) do writtenRoots[a.location.root]=true end
    joinMap(out.state,reachable(state.memory,exported,writtenRoots))
   elseif k=='If' then expr(s.test,state,node)
   elseif k=='Switch' then checkValue(state.values[s.variant.id] or empty(),s.sum,node)
   elseif k=='Trap' then expr(s.failure,state,node)
   elseif k=='Dynamic' then
    local args={};for i,e in ipairs(s.operands) do args[i]={value=expr(e,state,node),type=e.type} end
    opaque(args,node)
    for _,v in ipairs(s.results) do local unknown=empty();unknown.unknown=true;state.values[v.id]=unknown end
   end
   if proceed then for _,to in ipairs(node.next) do
    local edge={values=copyMap(state.values),memory=copyMap(state.memory)};local admitted=true
    if node.cases then
     local v=state.values[s.variant.id] or empty();local tag=node.cases[to];local tags=v.tags[ROOT]
     admitted=not tags or tags[tag]
     if admitted then
      local narrowed=empty();component(narrowed,project(v,B.Case(ROOT,tag)),B.Case(ROOT,tag));narrowed.tags[ROOT]={[tag]=true};edge.values[s.variant.id]=narrowed
     end
    end
    if admitted then poison(edge,function(source)return scopeEnded(source,g.nodes[to].scope)end);enqueuePoint(to,edge) end
   end end
  end
  return out
 end
 local roots={}
 for _,fn in ipairs(functions) do
  local args,memory={},{}
  for i,input in ipairs(fn.inputs) do
   if input.kind=='InPlace' then
    local r=B.StorageRoot(B.PlaceInput(fn.id,i-1,ROOT));args[i]={targets=singleton(access(r,ROOT,true)),type=input.type};put(memory,r,seed(input.type,fn.id,i-1))
   else args[i]={value=seed(input.type,fn.id,i-1),type=input.type} end
  end
  roots[fn.id]=request(fn.id,args,memory)
 end
 while head<=#queue do
  local c=queue[head];head=head+1;c.queued=false;stats.iterations=stats.iterations+1
  local out=run(c);c.ran=true;local changed=false
  for _,field in ipairs{'reads','writes','requirements','strong','failures','invocations'} do if union(c[field],out[field]) then changed=true end end
  if out.normal and not c.normal then c.normal=true;changed=true end
  if out.unknown and not c.unknown then c.unknown=true;changed=true end
  for i,v in ipairs(out.results) do c.results[i]=c.results[i] or empty();if merge(c.results[i],v) then changed=true end end
  if joinMap(c.state,out.state) then changed=true end
  if changed then for _,user in pairs(c.users) do enqueue(user) end end
 end
 local summaries={}
 for _,fn in ipairs(functions) do
  local c=roots[fn.id]
  local function footprint(set)
   local list,seen={},{};for _,a in ipairs(ordered(set)) do if not seen[a.location] then seen[a.location]=true;list[#list+1]=a.location end end
   return B.Footprint(S.List(list),c.unknown or false)
  end
  local results={}
  for i,v in ipairs(c.results) do
   local components={}
   for path,set in pairs(v.refs) do
    local sources,seen={},{};for _,a in ipairs(ordered(set)) do if not seen[a.source] then seen[a.source]=true;sources[#sources+1]=a.source end end
    components[#components+1]=B.Component(path,B.Loans(S.List(sources)))
   end
   table.sort(components,function(a,b)return key(a.path)<key(b.path)end);results[i]=B.Contents(S.List(components))
  end
  local invocations={};for _,v in pairs(c.invocations) do invocations[#invocations+1]=v end
  summaries[fn.id]={reads=footprint(c.reads),writes=footprint(c.writes),writable=footprint(c.requirements),results=results,invocations=S.List(invocations)}
 end
 local construction={};for _,g in pairs(graphs) do for p,n in pairs(g.nodes) do if n.stmt.kind=='RcNew' then construction[p]=true end end end
 stats.seconds=os.clock()-started
 return roots,summaries,stats,construction
end
function M.validate(functions,roots)
 for _,fn in ipairs(functions) do
  local failures={};for _,f in pairs(roots[fn.id].failures) do failures[#failures+1]=f end
  table.sort(failures,function(a,b)
   if a.code~=b.code then
    if a.code=='readonly-write' then return true end
    if b.code=='readonly-write' then return false end
    return a.code<b.code
   end
   return a.message<b.message
  end)
  if failures[1] then local f=failures[1];D.reject(f.code,f.message,f.span) end
 end
end
return M
