-- Type-directed Rc materialization. Source Rc values own header addresses;
-- ordinary references, register copies and spills never acquire holdings.
local S=require('let.schema')
local M={}
local function tree(d)
 if d.tree then return d.tree end
 local root={children={}};local keys={}
 for _,path in ipairs(d.paths) do
  local node=root;local encoded={}
  for _,key in ipairs(path) do
   local name=type(key)=='table' and 'case:'..key.case or type(key)..':'..key
   encoded[#encoded+1]=#name..':'..name
   node.byKey=node.byKey or {};local child=node.byKey[name]
   if not child then child={key=key,children={}};node.byKey[name]=child;node.children[#node.children+1]=child end
   node=child
  end
  node.owner=true;keys[#keys+1]=table.concat(encoded,'/')
 end
 d.tree=root;d.key=table.concat(keys,';');return root
end
function M.drops(program,physical,fresh)
 local function component(ty,key)
  local item=physical:layout(ty)
  if type(key)=='table' then return S.caseOf(ty,key.case),item.payloadOffset end
  if type(key)=='number' then return ty.element,key*item.stride end
  return item.fields[key].type,item.fields[key].offset
 end
 local drops={}
 return function(d,header)
  if #d.paths==0 then return nil end
  header=header or 0
  local key=S.encode(d.type)..':'..header
  local root=tree(d);key=key..':'..d.key
  if drops[key] then return drops[key] end
  local name=fresh('_let_drop_');drops[key]=name
  local lines={'.function '..name..' 2 0 aa -'};local labels=0
  local function emit(line) lines[#lines+1]='  '..line end
  local function label() labels=labels+1;return '_drop_'..labels end
  local function address(n)
   emit('CGET.A 1');if n~=0 then emit('PUSH.B 1');emit('IDX.A '..n) end
  end
  local function visit(node,ty,n)
   if node.owner then emit('CGET.A 0');address(n);emit('FCALL.A __let_rt_source_drop');return end
   local done=ty:isTaggedType() and label()
   for _,child in ipairs(node.children) do
    local part,offset=component(ty,child.key);local skip
    if type(child.key)=='table' then
     skip=label();address(n);emit('LD32.A 0');emit('PUSH.B '..physical:layout(ty).tags[child.key.case]);emit('EQ.A');emit('JZ.A '..skip)
    end
    visit(child,part,n+offset)
    if skip then emit('JMP '..done);lines[#lines+1]=skip..':' end
   end
   if done then lines[#lines+1]=done..':' end
  end
  visit(root,d.type,header)
  lines[#lines+1]='  RET.A 2 0';program.lifecycle[name]=lines;return name
 end
end
function M.program(selected)
 assert(selected.phase=='selected-program','materialization needs checked, entry-selected source')
 local I,L=S.Ir,S.List
 local D=require('let.diag');local Walk=require('let.walk');local Layout=require('let.layout')
 local ptr=S.Ptr(S.U8)
 local program={phase='physical-program',source=selected.source,functions={},modules={},foreigns={},lifecycle={},sourceNodes={}}
 local physical=Layout.physical(program)
 local reserved,definitions,contracts={},{},{}
 for _,fn in ipairs(selected.functions) do reserved[fn.id]=true;definitions[fn.id]=fn;contracts[fn.id]=fn end
 for _,f in ipairs(selected.foreigns) do reserved[f.target]=true;contracts[f.target]=f end
 local serial=0
 local function fresh(prefix)
  local name;repeat serial=serial+1;name=prefix..serial until not reserved[name]
  reserved[name]=true;return name
 end
 local function gate(message) D.reject('Rc-interface',message) end
 local function exposesRc(t,seen)
  if t:isRc() then return true end
  seen=seen or {};if seen[t] then return false end;seen[t]=true
  if t:isNamed() then
   local actual=selected.source.typeCells[t.cell]
   if not actual then gate('Unresolved public/foreign pointee type '..t.cell) end
   return exposesRc(actual,seen)
  end
  if t:isRef() or t:isPtr() then return exposesRc(t.target,seen) end
  if t:isView() or t:isOwned() or t:isTagged() then
   for _,input in ipairs(t.visible.inputs) do if exposesRc(input.type,seen) then return true end end
   for _,result in ipairs(t.visible.results) do if exposesRc(result,seen) then return true end end
   if t:isOwned() and exposesRc(t.environment,seen) then return true end
  end
  if t:isArray() or t:isSlice() then return exposesRc(t.element,seen) end
  if t:isRecord() then for _,f in ipairs(t.fields) do if exposesRc(f.type,seen) then return true end end
  elseif t:isTaggedType() then for _,f in ipairs(S.alternatives(t)) do if exposesRc(f.type,seen) then return true end end end
  return false
 end
 local mapped={}
 local mapType,mapSignature
 mapSignature=function(sig)
  local inputs,results={},{}
  for _,p in ipairs(sig.inputs) do
   if p.kind=='InValue' and S.hasRc(p.type) then gate('Owning callable arguments are not yet admitted') end
   inputs[#inputs+1]=p.kind=='InValue' and S.inValue(mapType(p.type)) or S.inPlace(mapType(p.type))
  end
  for _,t in ipairs(sig.results) do if S.hasRc(t) then gate('Owning callable results are not yet admitted') end;results[#results+1]=mapType(t) end
  return S.Sig(inputs,results)
 end
 mapType=function(t)
  if mapped[t] then return mapped[t] end
  local result=t
  if t:isRc() then result=ptr
  elseif t:isRef() then result=S.Ref(mapType(t.target))
  elseif t:isPtr() then result=S.Ptr(mapType(t.target))
  elseif t:isSlice() then result=S.Slice(mapType(t.element))
  elseif t:isArray() then result=S.Array(mapType(t.element),t.length)
  elseif t:isRecord() then local fields={};for _,f in ipairs(t.fields) do fields[f.name]=mapType(f.type) end;result=S.Record(fields)
  elseif t:isTaggedType() then
   if t:isTagged() and S.hasRc(t) then gate('Owning callable environments are not yet admitted') end
   local fields={};for _,f in ipairs(S.alternatives(t)) do fields[f.name]=mapType(f.type) end
   result=t:isTagged() and S.Tagged(mapSignature(t.visible),fields) or S.Sum(fields)
  elseif t:isView() then result=S.View(mapSignature(t.visible))
  elseif t:isOwned() then
   if S.hasRc(t.environment) then gate('Owning callable environments are not yet admitted') end
   result=S.Owned(t.key,mapSignature(t.visible),mapType(t.environment))
  end
  mapped[t]=result;return result
 end
 local function paths(ty,path,out)
  path=path or {};out=out or {}
  if ty:isRc() then out[#out+1]=path;return out end
  local function child(t,k)
   local p={};for i,v in ipairs(path) do p[i]=v end;p[#p+1]=k;paths(t,p,out)
  end
  if ty:isRecord() then for _,f in ipairs(ty.fields) do child(f.type,f.name) end
  elseif ty:isArray() then for i=0,ty.length-1 do child(ty.element,i) end
  elseif ty:isSum() then for _,f in ipairs(S.alternatives(ty)) do child(f.type,{case=f.name}) end end
  return out
 end
 local external={}
 for _,f in ipairs(selected.foreigns) do
  local ins,outs={},{}
  for _,p in ipairs(f.inputs) do if exposesRc(p.type) then gate('Foreign Rc transport is not yet admitted') end;ins[#ins+1]=p.kind=='InPlace' and S.inPlace(mapType(p.type)) or S.inValue(mapType(p.type)) end
  for _,t in ipairs(f.results) do if exposesRc(t) then gate('Foreign Rc transport is not yet admitted') end;outs[#outs+1]=mapType(t) end
  program.foreigns[#program.foreigns+1]=I.Foreign(f.target,L(ins),L(outs));external[f.target]=true
 end
 for _,m in ipairs(selected.modules) do
  if S.hasRc(m.root.type) then gate('Owning module initialization is not yet admitted') end
  program.modules[#program.modules+1]=I.ModuleData(I.ModuleRoot(m.root.identity,mapType(m.root.type),m.root.writable),m.bytes)
 end
 local function foreign(name,types)
  local id='__let_rt_source_'..name
  if not external[id] then
   local inputs={};for _,t in ipairs(types) do inputs[#inputs+1]=S.inValue(t) end
   program.foreigns[#program.foreigns+1]=I.Foreign(id,L(inputs),L{});external[id]=true
  end
  return id
 end
 local drop=M.drops(program,physical,fresh)
 local function descriptor(t) return {type=mapType(t),paths=paths(t)} end
 local function destructor(d,header)
  local name=drop(d,header)
  if name then foreign('drop',{ptr,ptr});return I.CEntry(name,ptr) end
  return I.Null(ptr)
 end
 local function uint(n) return I.Const(S.U64,I.UInt(n)) end
 local function index(n) return I.Const(S.U32,I.UInt(n)) end
 local function address(place,ty) return I.Convert(I.Addr(place,S.Ptr(ty)),ptr) end
 local function call(out,name,args)
  local arguments,types={},{}
  for _,e in ipairs(args) do arguments[#arguments+1]=I.ValueArg(e);types[#types+1]=e.type end
  out[#out+1]=I.Call(L{},foreign(name,types),L(arguments))
 end
 local function falls(body)
  local s=body[#body];if not s then return true end
  if s.kind=='Return' or s.kind=='Next' or s.kind=='Loop' then return false end
  if s.kind=='Trap' and s.failure.kind=='Const' and s.failure.literal.kind=='Boolean' and s.failure.literal.value then return false end
  if s.kind=='If' then return falls(s.yes) or falls(s.no) end
  if s.kind=='Switch' then for _,c in ipairs(s.cases) do if falls(c.body) then return true end end;return false end
  return true
 end
 for _,fn in ipairs(selected.functions) do
  if selected.entries[fn.id] then
   for _,p in ipairs(fn.inputs) do if exposesRc(p.type) then gate('Public Rc arguments are not yet admitted') end end
   for _,t in ipairs(fn.results) do if exposesRc(t) then gate('Public Rc results are not yet admitted') end end
  end
  local valueId,storageId=0,0
  Walk.walk(fn,{enter=function(n)
   if S.Ty.V:isclassof(n) then return false end
   if I.Value:isclassof(n) then valueId=math.max(valueId,n.id)
   elseif I.Storage:isclassof(n) then storageId=math.max(storageId,n.id) end
  end})
  local function value() valueId=valueId+1;return I.Value(valueId) end
  local function storage() storageId=storageId+1;return I.Storage(storageId) end
  local function capture(out,e)
   if e.kind=='Ref' or e.kind=='Const' or e.kind=='Null' or e.kind=='Code' or e.kind=='CEntry' then return e end
   local v=value();out[#out+1]=I.Let(v,e.type,e);return I.Ref(v,e.type)
  end
  local function read(out,p,t) local v=value();out[#out+1]=I.Read(v,t,p);return I.Ref(v,t) end
  local frame=storage();local fields={a_previous=ptr,b_drop=ptr};local framePaths={};local fieldTypes={};local slotCount=0
  local frameAddress=address(I.Project(I.Local(frame),I.Field('a_previous')),ptr)
  local function slot(t)
   assert(S.hasRc(t),'only declared owning values need holding slots')
   slotCount=slotCount+1;local name=string.format('h_%08d',slotCount)
   fields[name]=mapType(t);fieldTypes[name]=t
   for _,path in ipairs(paths(t)) do local p={name};for _,part in ipairs(path) do p[#p+1]=part end;framePaths[#framePaths+1]=p end
   return I.Project(I.Local(frame),I.Field(name))
  end
  local values,locals,types={},{},{}
  local function define(v,t) types[v.id]=t;if S.hasRc(t) then values[v.id]=slot(t) end end
  local inputs,params,outputs,results,imports={},{},{},{},{}
  for _,p in ipairs(fn.params) do
   local input=fn.inputs[p.input+1];local ty=mapType(p.type)
   if input.kind=='InValue' and S.hasRc(p.type) then
    if p.kind~='ValueParam' then gate('Owning value inputs require value bindings') end
    local incoming=storage();define(p.binding,p.type)
    inputs[p.input+1]=S.inPlace(ty);params[#params+1]=I.PlaceParam(p.input,incoming,ty)
    imports[#imports+1]={from=I.Local(incoming),to=values[p.binding.id],type=p.type}
   else
    inputs[p.input+1]=input.kind=='InPlace' and S.inPlace(ty) or S.inValue(ty)
    params[#params+1]=p.kind=='PlaceParam' and I.PlaceParam(p.input,p.binding,ty) or I.ValueParam(p.input,p.binding,ty)
    if p.kind=='ValueParam' then types[p.binding.id]=p.type end
   end
  end
  for i,t in ipairs(fn.results) do
   if S.hasRc(t) then
    local out=storage();outputs[i]=I.Local(out)
    params[#params+1]=I.PlaceParam(#inputs,out,mapType(t));inputs[#inputs+1]=S.inPlace(mapType(t))
   else results[#results+1]=mapType(t) end
  end
  -- Reserve actual value slots once, independently of CFG query contexts.
  Walk.walk(fn,{enter=function(n)
   if S.Ty.V:isclassof(n) or I.Expr:isclassof(n) or I.Place:isclassof(n) then return false end
   if I.Stmt:isclassof(n) then
    if n.kind=='Var' and S.hasRc(n.type) then locals[n.storage.id]=slot(n.type)
    elseif n.kind=='Let' or n.kind=='Read' or n.kind=='RcNew' or n.kind=='ConstructVariant' or n.kind=='View' then define(n.value,n.type)
    elseif n.kind=='VariantPayload' then define(n.value,S.caseOf(n.sum,n.tag))
    elseif n.kind=='Call' or n.kind=='Indirect' then
     local sig=n.kind=='Call' and assert(contracts[n.target],'missing call contract') or n.callable.type.visible
     if sig then for i,v in ipairs(n.results) do define(v,sig.results[i]) end end
    end
   end
  end})
  local function rawPlace(base,offset,t)
   local bytes=I.Addr(I.PtrIndex(base,index(offset),S.U8),ptr)
   return I.PtrIndex(I.Convert(bytes,S.Ptr(t)),index(0),t)
  end
  -- Initialize only tags and actual holding fields. Nonowning fields may be
  -- uninitialized until their value is installed; no public null Ref is invented.
  local initialize
  initialize=function(out,base,t,offset,tag)
   offset=offset or 0
   if t:isRc() then out[#out+1]=I.Store(rawPlace(base,offset,ptr),I.Null(ptr))
   elseif t:isRecord() then
    local layout=physical:layout(mapType(t))
    for _,f in ipairs(t.fields) do if S.hasRc(f.type) then initialize(out,base,f.type,offset+layout.fields[f.name].offset) end end
   elseif t:isArray() and S.hasRc(t.element) then
    local stride=physical:layout(mapType(t)).stride
    for i=0,t.length-1 do initialize(out,base,t.element,offset+i*stride) end
   elseif t:isSum() and S.hasRc(t) then
    local layout=physical:layout(mapType(t));tag=tag or S.alternatives(t)[1].name
    out[#out+1]=I.Store(rawPlace(base,offset,S.U32),index(layout.tags[tag]))
    initialize(out,base,S.caseOf(t,tag),offset+layout.payloadOffset)
   end
  end
  local nullHoldings
  nullHoldings=function(out,base,t,bits,offset)
   offset=offset or 0
   if t:isRc() then out[#out+1]=I.Store(rawPlace(base,offset,ptr),I.Null(ptr))
   elseif t:isRecord() then
    local layout=physical:layout(mapType(t))
    for _,f in ipairs(t.fields) do if S.hasRc(f.type) then nullHoldings(out,base,f.type,I.Get(bits,I.Field(f.name),mapType(f.type)),offset+layout.fields[f.name].offset) end end
   elseif t:isArray() and S.hasRc(t.element) then
    local stride=physical:layout(mapType(t)).stride
    for i=0,t.length-1 do nullHoldings(out,base,t.element,I.Get(bits,I.Element(i),mapType(t.element)),offset+i*stride) end
   elseif t:isSum() and S.hasRc(t) then
    if bits.kind~='Ref' then bits=capture(out,bits) end
    local cases={};local sum=mapType(t)
    for i,c in ipairs(S.alternatives(t)) do
     local body={}
     if S.hasRc(c.type) then
      local v=value();body[#body+1]=I.VariantPayload(v,bits.value,sum,c.name)
      nullHoldings(body,base,c.type,I.Ref(v,mapType(c.type)),offset+physical:layout(sum).payloadOffset)
     end
     cases[#cases+1]=I.Case(c.name,i==#S.alternatives(t),L(body))
    end
    out[#out+1]=I.Switch(bits.value,sum,L(cases))
   end
  end
  local function clear(out,p,t) call(out,'clear',{address(p,mapType(t)),destructor(descriptor(t))}) end
  local function fixed(out,p,t)
   local root=p;while root.kind=='Project' do root=root.base end
   if root.kind=='Local' or root.kind=='Global' then return p end
   local a=capture(out,address(p,t));return I.PtrIndex(I.Convert(a,S.Ptr(t)),index(0),t)
  end
  local function transfer(out,from,to,t)
   local ty=mapType(t);from=fixed(out,from,ty);to=fixed(out,to,ty)
   local bits=read(out,from,ty);local base=capture(out,address(from,ty))
   -- Addresses and the raw value precede the non-failing store/tag-dispatch
   -- window. Source holdings are nulled, not released. No count traffic.
   out[#out+1]=I.Store(to,bits);nullHoldings(out,base,t,bits)
  end
  local function payloadPlace(base,t)
   local ty=mapType(t)
   return I.PtrIndex(I.Convert(base,S.Ptr(ty)),index(0),ty)
  end
  local function displaced(base,offset)
   return I.Addr(I.PtrIndex(base,index(offset),S.U8),ptr)
  end
  local acquire
  acquire=function(out,dest,t,source)
   if t:isRc() then call(out,'hold',{address(dest,ptr),source})
   elseif not S.hasRc(t) then return
   elseif t:isRecord() then
    for _,f in ipairs(t.fields) do acquire(out,I.Project(dest,I.Field(f.name)),f.type,I.Get(source,I.Field(f.name),mapType(f.type))) end
   elseif t:isArray() then
    for i=0,t.length-1 do acquire(out,I.Index(dest,index(i),mapType(t.element)),t.element,I.Get(source,I.Element(i),mapType(t.element))) end
   elseif t:isSum() then
    if source.kind~='Ref' then source=capture(out,source) end
    local sum=mapType(t);local base=capture(out,address(dest,sum));local cases={}
    for i,c in ipairs(S.alternatives(t)) do
     local body={};initialize(body,base,t,0,c.name)
     if c.type~=S.Unit then
      local v=value();body[#body+1]=I.VariantPayload(v,source.value,sum,c.name)
      acquire(body,payloadPlace(displaced(base,physical:layout(sum).payloadOffset),c.type),c.type,I.Ref(v,mapType(c.type)))
     end
     cases[#cases+1]=I.Case(c.name,i==#S.alternatives(t),L(body))
    end
    out[#out+1]=I.Switch(source.value,sum,L(cases))
   else gate('Owning environments require a separately approved interface') end
  end
  local scratch={}
  local function copy(out,dest,t,source)
   dest=fixed(out,dest,mapType(t));source=capture(out,source)
   if t:isRc() then acquire(out,dest,t,source);return end
   if not S.hasRc(t) then out[#out+1]=I.Store(dest,source);return end
   local tmp=scratch[t];if not tmp then tmp=slot(t);scratch[t]=tmp end
   acquire(out,tmp,t,source) -- All incoming holdings before any old release.
   clear(out,dest,t)
   out[#out+1]=I.Store(dest,source)
   nullHoldings(out,address(tmp,mapType(t)),t,source)
  end
  local clone
  clone=function(n,out)
   if type(n)~='table' then return n end
   if S.Ty.V:isclassof(n) then return mapType(n) end
   if I.Local:isclassof(n) and locals[n.storage.id] then return locals[n.storage.id] end
   if I.Ref:isclassof(n) and values[n.value.id] then return read(out,values[n.value.id],mapType(n.type)) end
   if I.RcBorrow:isclassof(n) then
    local holding=n.holding;local owner
    if holding.kind=='BorrowArg' then owner=read(out,clone(holding.place,out),ptr)
    else
     assert(holding.value.kind=='Ref' and values[holding.value.value.id],'borrow needs an owning binding')
     owner=read(out,values[holding.value.value.id],ptr)
    end
    local ty=mapType(n.type.target);local offset=Layout.align(32,physical:layout(ty).align)
    return I.Addr(payloadPlace(displaced(owner,offset),n.type.target),mapType(n.type))
   end
   local class=getmetatable(n);local fs=class and class.__fields
   if not fs then return n end
   local args={}
   for i,f in ipairs(fs) do
    local item=n[f.name]
    if f.list then local parts={};for j,x in ipairs(item) do parts[j]=clone(x,out) end;args[i]=L(parts)
    elseif f.type~='string' and f.type~='number' and f.type~='boolean' and f.type~='any' then args[i]=clone(item,out)
    else args[i]=item end
   end
   local result=class(unpack(args,1,#fs))
   if I.Stmt:isclassof(n) or I.Expr:isclassof(n) then program.sourceNodes[result]=n;result.span=n.span end
   return result
  end
  local scopes={}
  local transform
  transform=function(body,out,isLoop)
   local scope={slots={},loop=isLoop};scopes[#scopes+1]=scope
   local function scoped(p,t) scope.slots[#scope.slots+1]={place=p,type=t} end
   local function cleanup(s) for i=#s.slots,1,-1 do local x=s.slots[i];clear(out,x.place,x.type) end end
   for _,s in ipairs(body) do
    local first=#out+1;local k=s.kind
    if k=='RcNew' then
     local initial=capture(out,clone(s.initial,out));local t=s.initial.type;local item=physical:layout(mapType(t));local offset=Layout.align(32,item.align)
     local dest=values[s.value.id];scoped(dest,s.type)
     call(out,'alloc',{address(dest,ptr),uint(offset+item.size),uint(math.max(8,item.align)),destructor(descriptor(t),offset)})
     local owner=read(out,dest,ptr);local payload=payloadPlace(displaced(owner,offset),t)
     acquire(out,payload,t,initial)
     out[#out+1]=I.Store(payload,initial)
    elseif k=='Var' and locals[s.storage.id] then
     local dest=locals[s.storage.id];scoped(dest,s.type)
     if s.initial then copy(out,dest,s.type,clone(s.initial,out)) end
    elseif (k=='Let' or k=='Read' or k=='ConstructVariant' or k=='VariantPayload') and values[s.value.id] then
     local dest=values[s.value.id];local t=types[s.value.id];local source
     if k=='Let' then source=clone(s.expr,out)
     elseif k=='Read' then source=read(out,clone(s.place,out),mapType(t))
     elseif k=='ConstructVariant' then
      local payload=s.payload and clone(s.payload,out);local v=value();out[#out+1]=I.ConstructVariant(v,mapType(t),s.tag,payload);source=I.Ref(v,mapType(t))
     else
      local variant=values[s.variant.id] and read(out,values[s.variant.id],mapType(s.sum)).value or s.variant
      local v=value();out[#out+1]=I.VariantPayload(v,variant,mapType(s.sum),s.tag);source=I.Ref(v,mapType(t))
     end
     scoped(dest,t);copy(out,dest,t,source)
    elseif k=='Store' and S.hasRc(s.value.type) then
     local dest=clone(s.place,out);local incoming=clone(s.value,out);copy(out,dest,s.value.type,incoming)
    elseif k=='Call' then
     local contract=assert(contracts[s.target]);local args,returned={},{};local owningCall=false
     for _,input in ipairs(contract.inputs) do owningCall=owningCall or input.kind=='InValue' and S.hasRc(input.type) end
     for _,t in ipairs(contract.results) do owningCall=owningCall or S.hasRc(t) end
     for i,a in ipairs(s.arguments) do
      local input=contract.inputs[i]
      if input.kind=='InValue' and S.hasRc(input.type) then
       assert(definitions[s.target],'foreign owning transport was not rejected')
       local dest=slot(input.type);copy(out,dest,input.type,clone(a.value,out));args[#args+1]=I.BorrowArg(dest)
      elseif a.kind=='ValueArg' then
       local incoming=clone(a.value,out);args[#args+1]=I.ValueArg(owningCall and capture(out,incoming) or incoming)
      else
       local incoming=clone(a.place,out);args[#args+1]=I.BorrowArg(owningCall and fixed(out,incoming,mapType(input.type)) or incoming)
      end
     end
     for i,v in ipairs(s.results) do
      local t=contract.results[i]
      if S.hasRc(t) then local dest=values[v.id];clear(out,dest,t);scoped(dest,t);args[#args+1]=I.BorrowArg(dest)
      else returned[#returned+1]=v end
     end
     out[#out+1]=I.Call(L(returned),s.target,L(args))
    elseif k=='Return' then
     local returned={}
     for i,e in ipairs(s.values) do
      local incoming=clone(e,out)
      if outputs[i] then copy(out,outputs[i],fn.results[i],incoming)
      else returned[#returned+1]=slotCount>0 and capture(out,incoming) or incoming end
     end
     out[#out+1]=I.Return(L(returned))
    elseif k=='If' then
     local test=clone(s.test,out);local yes,no={},{};transform(s.yes,yes);transform(s.no,no)
     out[#out+1]=I.If(test,L(yes),L(no))
    elseif k=='Loop' then local nested={};transform(s.body,nested,true);out[#out+1]=I.Loop(L(nested))
    elseif k=='Switch' then
     local variant=values[s.variant.id] and read(out,values[s.variant.id],mapType(s.sum)).value or s.variant
     local cases={};for _,c in ipairs(s.cases) do local nested={};transform(c.body,nested);cases[#cases+1]=I.Case(c.tag,c.fallback,L(nested)) end
     out[#out+1]=I.Switch(variant,mapType(s.sum),L(cases))
    elseif k=='Next' then
     for i=#scopes,1,-1 do cleanup(scopes[i]);if scopes[i].loop then break end end
     out[#out+1]=s
    elseif k=='VariantMatches' or k=='VariantPayload' then
     local variant=values[s.variant.id] and read(out,values[s.variant.id],mapType(s.sum)).value or s.variant
     out[#out+1]=I[k](s.value,variant,mapType(s.sum),s.tag)
    else
     if k=='View' then for _,a in ipairs(s.slots) do if a.kind=='ValueArg' and S.hasRc(a.value.type) then gate('Owning callable captures are not yet admitted') end end end
     if k=='Indirect' then mapSignature(s.callable.type.visible) end
     local copied=clone(s,out);out[#out+1]=copied
    end
    for i=first,#out do local n=out[i];if not program.sourceNodes[n] then program.sourceNodes[n]=s;n.span=s.span end end
   end
   if falls(body) then cleanup(scope) end
   scopes[#scopes]=nil
  end
  local body={};transform(fn.body,body)
  local prefix={}
  if slotCount>0 then
   local frameType=S.Record(fields)
   prefix[#prefix+1]=I.Var(frame,frameType,nil)
   prefix[#prefix+1]=I.Store(I.Project(I.Local(frame),I.Field('a_previous')),I.Null(ptr))
   prefix[#prefix+1]=I.Store(I.Project(I.Local(frame),I.Field('b_drop')),I.Null(ptr))
   for _,f in ipairs(frameType.fields) do if fieldTypes[f.name] then
    initialize(prefix,address(I.Project(I.Local(frame),I.Field(f.name)),f.type),fieldTypes[f.name])
   end end
   call(prefix,'enter',{frameAddress,destructor{type=frameType,paths=framePaths}})
   for _,p in ipairs(imports) do transfer(prefix,p.from,p.to,p.type) end
  end
  local function finish(statements)
   local out={}
   for _,s in ipairs(statements) do
    local first=#out+1
    if s.kind=='Return' then if slotCount>0 then call(out,'leave',{frameAddress}) end;out[#out+1]=s
    elseif s.kind=='If' then out[#out+1]=I.If(s.test,L(finish(s.yes)),L(finish(s.no)))
    elseif s.kind=='Loop' then out[#out+1]=I.Loop(L(finish(s.body)))
    elseif s.kind=='Switch' then
     local cases={};for _,c in ipairs(s.cases) do cases[#cases+1]=I.Case(c.tag,c.fallback,L(finish(c.body))) end
     out[#out+1]=I.Switch(s.variant,s.sum,L(cases))
    else out[#out+1]=s end
    for i=first,#out do local n=out[i];if not program.sourceNodes[n] then program.sourceNodes[n]=program.sourceNodes[s] or s;n.span=s.span end end
   end
   return out
  end
  for _,s in ipairs(prefix) do program.sourceNodes[s]=fn end
  for _,s in ipairs(finish(body)) do prefix[#prefix+1]=s end
  program.functions[#program.functions+1]=I.Fn(fn.id,fn.role,fn.hidden,L(inputs),L(results),L(params),L(prefix))
 end
 require('let.check').program(program.functions,program.modules,program.foreigns,true)
 return program
end
return M
