-- Materialize a checked source graph. Counts protect semantic holdings in actual
-- concrete storage; transient ABC cells merely transport bits. No runtime layout
-- interpreter, scope-slot registry or second ownership analysis is involved.
local S=require('let.schema')
local IR=require('let.ir')
local Check=require('let.check')
local Walk=require('let.walk')
local Ownership=require('let.ownership')
local Layout=require('let.layout')
local D=require('let.diag')
local I,L=S.Ir,S.List
local P=S.Ptr(S.Unit)
local REF=S.Record{data=P,owner=P}
local M={}
local names={alloc='__let_rt_source_alloc',hold='__let_rt_source_hold',clear='__let_rt_source_clear',enter='__let_rt_source_enter',leave='__let_rt_source_leave',drop='__let_rt_source_drop'}
local function reject(message) D.reject('ownership-materialization',message) end
local function field(p,name) return I.Project(p,I.Field(name)) end
local function prepend(path,key) local out={key};for _,v in ipairs(path) do out[#out+1]=v end;return out end

function M.program(source,options)
 assert(source.phase=='checked-program')
 local program={phase='physical-program',source=source,functions={},modules={},foreigns={},lifecycle={}}
 local physical=Layout.physical(program)
 local types,contracts,definitions,allocated,named={}, {}, {}, {}, {}
 local serial=0
 for _,fn in ipairs(source.functions) do definitions[fn.id]=fn;named[fn.id]=true;allocated[fn.id]={} end
 for _,external in ipairs(source.foreigns) do named[external.target]=true end
 for _,data in ipairs(source.modules) do named[data.root.identity]=true end
 for _,fn in ipairs(source.functions) do
  for _,requirement in ipairs(source.ownership[fn.id].summary.counted) do
   local r=requirement.root.source
   if r.frame==fn.id and r.kind=='Local' then allocated[fn.id][r.storage]=true end
  end
 end
 -- A source definition whose placement changes with a callback/recursive context
 -- needs a distinct physical instance. Never promote the whole family silently.
 for _,fn in ipairs(source.functions) do for _,requirement in ipairs(source.ownership[fn.id].summary.counted) do
  local r=requirement.root.source
  if not allocated[r.frame] or not allocated[r.frame][r.storage] then reject('Context-dependent allocation needs a resolved physical function instance: '..r.frame) end
 end end
 local function fresh(prefix)
  repeat serial=serial+1 until not named[prefix..serial]
  local name=prefix..serial;named[name]=true;return name
 end
 local function managed(ty) return Ownership.checkedAccess(ty) end
 local function privateTagged(ty)
  if ty:isTaggedType() then return not Layout.pointerFree(ty) end
  if ty:isRecord() then for _,f in ipairs(ty.fields) do if privateTagged(f.type) then return true end end end
  if ty:isArray() then return privateTagged(ty.element) end
  return false
 end
 -- Private flattening is not permission to widen unrelated public/foreign
 -- aggregate ABIs. Managed borrowed inputs retain their separate admission below.
 local function newAggregateABI(ty) return not managed(ty) and Layout.scalar:abiComponents(ty)==false end
 local describe,signature
 local borrowing={}
 for _,fn in ipairs(source.functions) do
  local proof=source.ownership[fn.id].summary;local safe=#proof.counted==0 and #proof.edges==0
  for _,ty in ipairs(fn.results) do if managed(ty) then safe=false end end
  for _,input in ipairs(fn.inputs) do if input.kind=='InPlace' and managed(input.type) then safe=false end end
  Walk.walk(fn,{enter=function(node)
   if S.Ty.V:isclassof(node) then
    if managed(node) and not (node:isRef() and Layout.pointerFree(node.target)) then safe=false end
    if node:isPtr() and managed(node.target) then safe=false end
    return false
   end
   if node.kind=='Call' and definitions[node.target] then
    for _,ty in ipairs(definitions[node.target].results) do if managed(ty) then safe=false end end
   end
  end})
  borrowing[fn.id]=safe
 end
 -- A place-only formal transports one address unless this body can form or
 -- forward an owning-capable reference to its root. Propagate that requirement
 -- through direct calls before fixing any physical signature.
 local ownerInputs,forwarding={},{}
 for _,fn in ipairs(source.functions) do
  local inputs={};ownerInputs[fn.id]=inputs;local parameters={}
  for index,p in ipairs(fn.params) do if p.kind=='PlaceParam' then parameters[p.binding.id]=index end end
  local function parameter(p)
   while p.kind=='Project' or p.kind=='Index' do p=p.base end
   return p.kind=='Local' and parameters[p.storage.id] or nil
  end
  Walk.walk(fn,{enter=function(node)
   if S.Ty.V:isclassof(node) then return false end
   if node.kind=='Addr' and node.type:isRef() then local index=parameter(node.place);if index then inputs[index]=true end
   elseif node.kind=='View' or node.kind=='Indirect' then
    for _,arg in ipairs(node.kind=='View' and node.slots or node.arguments) do if arg.kind=='BorrowArg' then local index=parameter(arg.place);if index then inputs[index]=true end end end
   elseif node.kind=='Call' then
    for index,arg in ipairs(node.arguments) do if arg.kind=='BorrowArg' then
     local from=parameter(arg.place);if from then forwarding[#forwarding+1]={from=inputs,input=from,target=node.target,argument=index} end
    end end
   end
  end})
 end
 local changed=true
 while changed do changed=false;for _,edge in ipairs(forwarding) do
  if ownerInputs[edge.target] and ownerInputs[edge.target][edge.argument] and not edge.from[edge.input] then edge.from[edge.input]=true;changed=true end
 end end
 local function resultRecord(results)
  local owning=false;for _,ty in ipairs(results) do owning=owning or managed(ty) end
  if not owning then return nil end
  local fields,paths={},{}
  for index,ty in ipairs(results) do
   local name=string.format('r%04d',index);local d=describe(ty);fields[name]=d.type
   for _,p in ipairs(d.paths) do paths[#paths+1]=prepend(p,name) end
  end
  return {type=S.Record(fields),paths=paths}
 end
 signature=function(inputs,results,owners,borrowed)
  local args={};for index,input in ipairs(inputs) do
   if input.kind=='InPlace' then
    args[#args+1]=not borrowed and (not owners or owners[index]) and S.inValue(REF) or S.inPlace(describe(input.type).type)
   elseif borrowed and input.type:isRef() then args[#args+1]=S.inPlace(input.type.target)
   else args[#args+1]=S.inValue(describe(input.type).type) end
  end
  local out=resultRecord(results);local returns={}
  if out then args[#args+1]=S.inValue(P) else for _,ty in ipairs(results) do returns[#returns+1]=describe(ty).type end end
  return {inputs=L(args),results=L(returns),output=out}
 end
 describe=function(ty)
  if types[ty] then return types[ty] end
  local d={type=ty,paths={}};types[ty]=d
  if ty:isRef() then d.type=REF;d.paths={{'owner'}}
  elseif ty:isSlice() then d.type=S.Record{data=REF,length=S.U32};d.paths={{'data','owner'}}
  elseif ty:isOwned() then
   local environment=describe(ty.environment);d.type=environment.type;d.paths=environment.paths
  elseif ty:isView() then
   local sig=signature(ty.visible.inputs,ty.visible.results);d.signature=sig
   d.view=S.View(S.Sig(sig.inputs,sig.results));d.type=S.Record{callable=d.view,owner=P};d.paths={{'owner'}}
  elseif ty:isRecord() then
   local fields={};for _,f in ipairs(ty.fields) do
    local part=describe(f.type);fields[f.name]=part.type
    for _,p in ipairs(part.paths) do d.paths[#d.paths+1]=prepend(p,f.name) end
   end;d.type=S.Record(fields)
  elseif ty:isArray() then
   local part=describe(ty.element);d.type=S.Array(part.type,ty.length)
   for index=0,ty.length-1 do for _,p in ipairs(part.paths) do d.paths[#d.paths+1]=prepend(p,index) end end
  elseif ty:isTaggedType() then
   local cases={};for _,f in ipairs(S.alternatives(ty)) do
    local part=describe(f.type);cases[f.name]=part.type;local key={case=f.name}
    for _,p in ipairs(part.paths) do d.paths[#d.paths+1]=prepend(p,key) end
   end;d.type=S.Sum(cases)
  elseif ty==S.Any then reject('Erased owning values need a resolved physical contract') end
  return d
 end
 for _,fn in ipairs(source.functions) do contracts[fn.id]=signature(fn.inputs,fn.results,ownerInputs[fn.id],borrowing[fn.id]) end
 for _,name in ipairs(options.exports or {}) do
  local fn=definitions[name]
  if fn then
   for _,input in ipairs(fn.inputs) do if privateTagged(input.type) or (input.kind=='InValue' and newAggregateABI(input.type)) or ((input.kind=='InPlace' or managed(input.type)) and not borrowing[fn.id]) then reject('Public owning/access inputs are not supported: '..name) end end
   for _,ty in ipairs(fn.results) do if managed(ty) or privateTagged(ty) or newAggregateABI(ty) then reject('Public owning/access results are not supported: '..name) end end
  end
 end
 for _,data in ipairs(source.modules) do
  if managed(data.root.type) then reject('Persistent module holdings are not supported') end
  program.modules[#program.modules+1]=data
 end
 for _,external in ipairs(source.foreigns) do
  for _,input in ipairs(external.inputs) do if input.kind~='InValue' or managed(input.type) or privateTagged(input.type) or newAggregateABI(input.type) then reject('Foreign ownership transport is not supported') end end
  for _,ty in ipairs(external.results) do if managed(ty) or privateTagged(ty) or newAggregateABI(ty) then reject('Foreign ownership transport is not supported') end end
  program.foreigns[#program.foreigns+1]=external;definitions[external.target]=external;contracts[external.target]=signature(external.inputs,external.results)
 end
 for _,op in ipairs{'alloc','hold','clear','enter','leave','drop'} do
  local ts=op=='alloc' and {P,S.U64,S.U64,P} or op=='leave' and {P} or {P,P};local ins={}
  for _,ty in ipairs(ts) do ins[#ins+1]=S.inValue(ty) end
  program.foreigns[#program.foreigns+1]=I.Foreign(names[op],L(ins),L{})
 end
 -- Compiler-only holding paths form a traversal tree. Case nodes guard union
 -- payloads; they are never serialized or interpreted by the runtime.
 local function tree(d)
  if d.tree then return d.tree end
  local root={children={}};local keys={}
  for _,path in ipairs(d.paths) do
   local node=root;local encoded={}
   for _,key in ipairs(path) do
    local name=type(key)=='table' and 'case:'..key.case or type(key)..':'..key
    if type(key)=='table' then d.conditional=true end
    encoded[#encoded+1]=#name..':'..name
    node.byKey=node.byKey or {};local child=node.byKey[name]
    if not child then child={key=key,children={}};node.byKey[name]=child;node.children[#node.children+1]=child end
    node=child
   end
   node.owner=true;keys[#keys+1]=table.concat(encoded,'/')
  end
  d.tree=root;d.key=table.concat(keys,';');return root
 end
 local function component(ty,key)
  local item=physical:layout(ty)
  if type(key)=='table' then return S.caseOf(ty,key.case),item.payloadOffset end
  if type(key)=='number' then return ty.element,key*item.stride end
  return item.fields[key].type,item.fields[key].offset
 end
 local drops={}
 local function drop(d,header)
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
   if node.owner then emit('CGET.A 0');address(n);emit('FCALL.A '..names.drop);return end
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
 local function sameContract(fn,c)
  if c.output or #fn.inputs~=#c.inputs or #fn.results~=#c.results then return false end
  for i,input in ipairs(fn.inputs) do if input~=c.inputs[i] then return false end end
  for i,ty in ipairs(fn.results) do if ty~=c.results[i] then return false end end
  return true
 end
 local function transform(fn)
  local borrowed=borrowing[fn.id]
  -- A proven borrowed body whose types AND call contracts are unchanged needs
  -- no ownership materialization. Keep ordinary value/local slot selection;
  -- do not turn its scalar or packed values into an aggregate activation block.
  local unchanged=borrowed and sameContract(fn,contracts[fn.id])
  if unchanged then Walk.walk(fn,{enter=function(node)
   if not unchanged then return false end
   if S.Ty.V:isclassof(node) and node:isRef() then unchanged=false;return false end
   if node.kind=='Call' and not sameContract(definitions[node.target],contracts[node.target]) then unchanged=false;return false end
  end}) end
  if unchanged then program.functions[#program.functions+1]=fn;return end
  local describe=borrowed and function(ty) return {type=ty:isRef() and P or ty,paths={}} end or describe
  local b=IR.builder();local body=L{};local values,storage,addressed,moves={},{},{},{}
  local definitionsAt,uses,usedAt={},{},{}
  local function usesIn(node,loop)
   if S.Ty.V:isclassof(node) then return end
   if node.kind=='Loop' then loop=node end
   local function use(id) uses[id]=(uses[id] or 0)+1;usedAt[id]=loop end
   if node.kind=='Switch' or node.kind=='VariantMatches' or node.kind=='VariantPayload' then use(node.variant.id) end
   if I.Ref:isclassof(node) then use(node.value.id)
   elseif node.kind=='Let' or node.kind=='Read' or node.kind=='View' or node.kind=='ConstructVariant' or node.kind=='VariantPayload' or node.kind=='VariantMatches' then definitionsAt[node.value.id]=loop
   elseif node.kind=='Call' or node.kind=='Indirect' then for _,id in ipairs(node.results) do definitionsAt[id.id]=loop end end
   for _,child in ipairs(Walk.nodeChildren(node)) do usesIn(child,loop) end
  end
  usesIn(fn,false)
  Walk.walk(fn,{enter=function(node)
   if S.Ty.V:isclassof(node) then return false end
   if node.kind=='Addr' or node.kind=='BorrowArg' then
    local p=node.place;while p.kind=='Project' or p.kind=='Index' do p=p.base end
    if p.kind=='Local' then addressed[p.storage.id]=true end
   end
  end})
  local frame=b:storageId();local framePlace=I.Local(frame);local frameAddressId=b:valueId()
  local fields=borrowed and {} or {a_previous=P,b_drop=P};local framePaths={};local slotSerial=0
  local function slot(d,root)
   slotSerial=slotSerial+1;local name=string.format('s%06d',slotSerial);fields[name]=d.type
   if root then framePaths[#framePaths+1]={name}
   else for _,p in ipairs(d.paths) do framePaths[#framePaths+1]=prepend(p,name) end end
   return field(framePlace,name)
  end
  local function read(list,ty,p) return b:ref(b:read(list,ty,p),ty) end
  local function valueId(list,ty,value) return value.kind=='Ref' and value.value or b:let(list,ty,value) end
  local function address(p,ty) return b:convert(b:addr(p,S.Ptr(ty),S.Borrow.WriteAccess),P) end
  local function ptr(p,ty) return I.PtrIndex(b:convert(p,S.Ptr(ty)),b:u32(0),ty) end
  local function null() return b:nullPtr(P) end
  local function ref(data,owner) return b:make(REF,{data,owner}) end
  local function member(value,key,ty) return b:get(value,key,ty) end
  local function invoke(list,op,args) local aa={};for _,a in ipairs(args) do aa[#aa+1]=I.ValueArg(a) end;b:emit(list,I.Call(L{},names[op],L(aa))) end
  local function clear(list,p,d)
   local name=drop(d);if name then invoke(list,'clear',{address(p,d.type),b:code(name,P,true)}) end
  end
  local zeroValues={}
  local function zero(list,ty)
   if ty:isPtr() then return b:nullPtr(ty) end
   if ty:isRecord() then local parts={};for _,f in ipairs(ty.fields) do parts[#parts+1]=zero(list,f.type) end;return b:make(ty,parts) end
   if ty:isArray() then local parts={};for _=1,ty.length do parts[#parts+1]=zero(list,ty.element) end;return b:make(ty,parts) end
   if ty:isView() then return b:callable(null(),null(),ty) end
   if ty:isTaggedType() then
    if zeroValues[ty] then return zeroValues[ty] end
    local first=S.alternatives(ty)[1];local value=b:valueId()
    local payload=first.type~=S.Unit and zero(list,first.type) or nil
    b:emit(list,I.ConstructVariant(value,ty,first.name,payload));zeroValues[ty]=b:ref(value,ty);return zeroValues[ty]
   end
   return b:const(ty,ty==S.F64 and I.Float(0) or ty==S.Bool and I.Boolean(false) or I.UInt(0))
  end
  local function payloadPlace(p,ty,tag)
   local byte=I.PtrIndex(b:convert(address(p,ty),S.Ptr(S.U8)),b:u32(physical:layout(ty).payloadOffset),S.U8)
   return ptr(address(byte,S.U8),S.caseOf(ty,tag))
  end
  local function owners(list,p,d,incoming,acquire)
   local function visit(list,node,p,ty,value)
    if node.owner then
     if acquire then invoke(list,'hold',{address(p,P),value}) else b:store(list,p,null()) end
    elseif ty:isTaggedType() then
     if not value then
      -- Clearing a moved value needs its tag, not a copy of its entire payload.
      local tag=read(list,S.U32,ptr(address(p,ty),S.U32))
      for _,child in ipairs(node.children) do
       local name=child.key.case;local branch=L{}
       visit(branch,child,payloadPlace(p,ty,name),S.caseOf(ty,name),nil)
       b:emit(list,I.If(b:bin('Eq',tag,b:u32(physical:layout(ty).tags[name]),S.Bool),branch,L{}))
      end
      return
     end
     local id=valueId(list,ty,value);local cases={};local alternatives=S.alternatives(ty)
     for index,case in ipairs(alternatives) do
      local branch=L{};local child=node.byKey and node.byKey['case:'..case.name]
      if acquire then
       -- Scratch was zeroed in full before changing any tag. Publish the active
       -- case before its first acquire, including all enclosing union tags.
       b:store(branch,ptr(address(p,ty),S.U32),b:u32(index-1))
      end
      if child then
       local payload
       if value then local v=b:valueId();b:emit(branch,I.VariantPayload(v,id,ty,case.name));payload=b:ref(v,case.type) end
       visit(branch,child,payloadPlace(p,ty,case.name),case.type,payload)
      end
      cases[#cases+1]=I.Case(case.name,index==#alternatives,branch)
     end
     b:emit(list,I.Switch(id,ty,L(cases)))
    else
     for _,child in ipairs(node.children) do
      local key=child.key;local part=component(ty,key)
      local sub=type(key)=='number' and I.Index(p,b:u32(key),part) or field(p,key)
      visit(list,child,sub,part,value and member(value,key,part))
     end
    end
   end
   visit(list,tree(d),p,d.type,incoming)
  end
  local function clearOwners(list,p,d) owners(list,p,d,nil,false) end
  local function zeroUnions(list,p,d)
   local function visit(node,p,ty)
    if ty:isTaggedType() then
     local size=physical:layout(ty).size;assert(size%8==0,'an owning union has address alignment')
     local words=b:convert(address(p,ty),S.Ptr(S.U64))
     for i=0,size/8-1 do b:store(list,I.PtrIndex(words,b:u32(i),S.U64),b:int(S.U64,0)) end
    else
     for _,child in ipairs(node.children) do
      local key=child.key;local part=component(ty,key)
      visit(child,type(key)=='number' and I.Index(p,b:u32(key),part) or field(p,key),part)
     end
    end
   end
   visit(tree(d),p,d.type)
  end
  local function copy(list,destination,d,value)
   if d.type==S.Unit then return end
   if #d.paths==0 then b:store(list,destination,value);return end
   -- Capture the entire incoming value before any destination mutation. Newly
   -- retained fields are published immediately in cleanup-visible scratch storage.
   local captured=b:ref(valueId(list,d.type,value),d.type)
   local moved=moves[value]
   if moved then
    -- A last, single use in the defining iteration transfers the actual holding.
    -- An outer-loop value is never consumed by its first dynamic use.
    clear(list,destination,d);b:store(list,destination,captured);clearOwners(list,moved,d);moves[value]=nil;return
   end
   local temporary=slot(d)
   clear(list,temporary,d)
   -- Clear stale non-owning union bytes too: changing a tag must never expose
   -- old scalar/data bits as a newly initialized owner field.
   if d.conditional then zeroUnions(list,temporary,d) end
   owners(list,temporary,d,captured,true)
   -- All acquires succeeded. Fill data bits, drop old destination, then transfer
   -- the scratch holding. There are no failing operations between transfer/clear.
   b:store(list,temporary,captured)
   clear(list,destination,d)
   b:store(list,destination,read(list,d.type,temporary));clearOwners(list,temporary,d)
  end
  local function publish(list,id,ty,value)
   local d=describe(ty)
   if #d.paths>0 then
    local p=values[id] and values[id].place or slot(d);copy(list,p,d,value);values[id]={place=p,type=d.type}
   else values[id]={value=b:ref(b:let(list,d.type,value),d.type),type=d.type} end
  end
  local params={};local contract=contracts[fn.id]
  for index,p in ipairs(fn.params) do
   local input=contract.inputs[index];local ty=input.type
   if input.kind=='InPlace' then
    local id=b:storageId();params[index]=I.PlaceParam(index-1,id,ty);local data=address(I.Local(id),ty)
    if p.kind=='PlaceParam' then storage[p.binding.id]={type=p.type,data=data,owner=null()}
    else values[p.binding.id]={value=data,type=P} end
   else
    local id=b:valueId();params[index]=I.ValueParam(index-1,id,ty);local value=b:ref(id,ty)
    if p.kind=='PlaceParam' then storage[p.binding.id]={type=p.type,data=member(value,'data',P),owner=member(value,'owner',P)}
    else values[p.binding.id]={value=value,type=ty} end
   end
  end
  local output
  if contract.output then
   local id=b:valueId();params[#params+1]=I.ValueParam(#params,id,P);output=ptr(b:ref(id,P),contract.output.type)
  end
  local expr,place,statements
  local function sourceType(p)
   if p.kind=='Local' then return assert(storage[p.storage.id]).type end
   if p.kind=='Global' then return p.root.type end
   if p.kind=='Project' then return S.field(S.environmentOf(sourceType(p.base)),p.field.name) end
   return p.type
  end
  local function newRoot(list,id,ty,d)
   local r=storage[id]
   if not r then
    r={type=ty,descriptor=d}
    if allocated[fn.id][id] then r.holding=slot({type=P,paths={}},true)
    elseif physical:layout(d.type).size==0 then
     local anchor=slot({type=S.U8,paths={}});r.place=ptr(address(anchor,S.U8),d.type)
    else r.place=slot(d) end
    storage[id]=r
   end
   if r.holding then
    local layout=physical:layout(d.type);local name=drop(d,32)
    invoke(list,'alloc',{address(r.holding,P),b:int(S.U64,32+layout.size),b:int(S.U64,math.max(8,layout.align)),name and b:code(name,P,true) or null()})
   else clear(list,r.place,d) end
   return r
  end
  local function rootPlace(list,r)
   if r.holding then
    local owner=read(list,P,r.holding)
    local bytes=I.PtrIndex(b:convert(owner,S.Ptr(S.U8)),b:u32(32),S.U8)
    return ptr(address(bytes,S.U8),r.descriptor.type),owner
   elseif r.data then return ptr(r.data,describe(r.type).type),r.owner
   else return r.place,null() end
  end
  place=function(list,p)
   if p.kind=='Local' then return rootPlace(list,assert(storage[p.storage.id])) end
   if p.kind=='Global' then return p,null() end
   if p.kind=='Project' then local base,owner=place(list,p.base);return field(base,p.field.name),owner end
   if p.kind=='Index' then local base,owner=place(list,p.base);return I.Index(base,expr(list,p.index),describe(p.type).type),owner end
   if p.kind=='Deref' then
    local base=place(list,p.base);local value=read(list,describe(sourceType(p.base)).type,base)
    if value.type==P then return ptr(value,describe(p.type).type),null() end
    return ptr(member(value,'data',P),describe(p.type).type),member(value,'owner',P)
   end
   if p.kind=='SliceIndex' then
    local view=expr(list,p.view);local index=expr(list,p.index);local data=member(view,'data',REF)
    b:trap(list,b:bin('Ge',index,member(view,'length',S.U32),S.Bool),'index-range')
    return I.PtrIndex(b:convert(member(data,'data',P),S.Ptr(describe(p.type).type)),index,describe(p.type).type),member(data,'owner',P)
   end
   if p.kind=='PtrIndex' then return I.PtrIndex(expr(list,p.view),expr(list,p.index),p.type),null() end
   reject('Unresolved place '..p.kind)
  end
  expr=function(list,e)
   local k=e.kind
   if k=='Ref' then
    local v=assert(values[e.value.id]);local value=v.value or read(list,v.type,v.place)
    if v.place and uses[e.value.id]==1 and definitionsAt[e.value.id]==usedAt[e.value.id] then moves[value]=v.place end
    return value
   end
   if k=='Addr' then local p,owner=place(list,e.place);local data=address(p,describe(sourceType(e.place)).type);return e.type:isPtr() and b:convert(data,e.type) or borrowed and data or ref(data,owner) end
   if k=='Const' then
    if e.type:isSlice() then
     local bytes=e.literal.bytes;local ty=S.Array(S.U8,math.max(1,#bytes));local root=I.ModuleRoot(fresh('_let_string_'),ty,false)
     program.modules[#program.modules+1]=I.ModuleData(root,#bytes>0 and bytes or '\0')
     return b:make(describe(e.type).type,{ref(address(I.Global(root),ty),null()),b:u32(#bytes)})
    end
    return b:const(e.type,e.literal)
   end
   if k=='Null' then return b:nullPtr(e.type) end
   if k=='Code' then return b:code(e.entry,e.type,false) end
   if k=='Make' then local parts={};for _,v in ipairs(e.fields) do parts[#parts+1]=expr(list,v) end;return b:make(describe(e.type).type,parts) end
   if k=='Get' then return member(expr(list,e.aggregate),e.field.kind=='Field' and e.field.name or e.field.index,describe(e.type).type) end
   if k=='Un' then return b:un(e.op.kind,expr(list,e.operand),e.type) end
   if k=='Bin' then
    local left,right=expr(list,e.left),expr(list,e.right)
    if e.left.type:isRef() and (e.op.kind=='Eq' or e.op.kind=='Ne') then
     if left.type~=P then left=member(left,'data',P) end
     if right.type~=P then right=member(right,'data',P) end
    end
    return b:bin(e.op.kind,left,right,e.type)
   end
   if k=='Convert' then return b:convert(expr(list,e.operand),describe(e.type).type) end
   if k=='SliceLength' then return member(expr(list,e.view),'length',S.U32) end
   reject('Unresolved owning expression '..k)
  end
  local function argument(list,a,input)
   if a.kind=='ValueArg' then
    local value=expr(list,a.value)
    if input and input.kind=='InPlace' then
     local data=value.type==P and value or member(value,'data',P)
     return I.BorrowArg(ptr(data,input.type))
    end
    if a.value.type:isRef() and input and value.type~=input.type then value=ref(value,null()) end
    return I.ValueArg(value)
   end
   local p,owner=place(list,a.place)
   if input and input.kind=='InPlace' then return I.BorrowArg(p) end
   return I.ValueArg(ref(address(p,describe(sourceType(a.place)).type),owner))
  end
  local function call(list,s,indirect)
   local c=indirect and describe(s.callable.type).signature or contracts[s.target]
   local args={};for index,a in ipairs(s.arguments) do args[#args+1]=argument(list,a,c.inputs[index]) end
   local out
   if c.output then out=slot(c.output);clear(list,out,c.output);args[#args+1]=I.ValueArg(address(out,c.output.type)) end
   local results={};for _ in ipairs(c.results) do results[#results+1]=b:valueId() end
   if indirect then
    local d=describe(s.callable.type);local callable=member(expr(list,s.callable),'callable',d.view)
    local value=b:let(list,d.view,callable);b:emit(list,I.Indirect(L(results),b:ref(value,d.view),L(args)))
   else b:emit(list,I.Call(L(results),s.target,L(args))) end
   local original=indirect and s.callable.type.visible.results or definitions[s.target].results
   for index,id in ipairs(s.results) do
    if out then values[id.id]={place=field(out,string.format('r%04d',index)),type=describe(original[index]).type}
    else values[id.id]={value=b:ref(results[index],c.results[index]),type=c.results[index]} end
   end
  end
  statements=function(list,items,inLoop)
   for _,s in ipairs(items) do local k=s.kind
    if k=='Let' then publish(list,s.value.id,s.type,expr(list,s.expr))
    elseif k=='Read' then local p=place(list,s.place);publish(list,s.value.id,s.type,read(list,describe(s.type).type,p))
    elseif k=='Var' then
     if inLoop and not allocated[fn.id][s.storage.id] and addressed[s.storage.id] then reject('Loop-local borrowed storage needs a resolved iteration lifetime') end
     local d=describe(s.type);local r=newRoot(list,s.storage.id,s.type,d)
     if s.initial then local value=expr(list,s.initial);copy(list,rootPlace(list,r),d,value) end
    elseif k=='Store' then
     local value=expr(list,s.value);local destination=place(list,s.place);copy(list,destination,describe(s.value.type),value)
    elseif k=='Call' then call(list,s,false)
    elseif k=='Indirect' then call(list,s,true)
    elseif k=='View' and s.type:isOwned() then
     assert(s.type.environment==S.Unit and #s.slots==0)
     publish(list,s.value.id,s.type,b:const(S.Unit,I.UInt(0)))
    elseif k=='View' then
     local d=describe(s.type);local captured,paths={},{}
     for index,a in ipairs(s.slots) do
      local name=string.format('c%04d',index);local part=a.kind=='BorrowArg' and {type=REF,paths={{'owner'}}} or describe(a.value.type)
      captured[name]=part.type;for _,p in ipairs(part.paths) do paths[#paths+1]=prepend(p,name) end
     end
     local env={type=S.Record(captured),paths=paths};local data,owner=null(),null()
     if #s.slots>0 then
      if inLoop and not allocated[fn.id][s.adapter.id] then reject('Loop-local callable environment needs a resolved iteration lifetime') end
      local r=newRoot(list,s.adapter.id,env.type,env);local p;p,owner=rootPlace(list,r);data=address(p,env.type)
      for index,a in ipairs(s.slots) do
       local part=a.kind=='BorrowArg' and {type=REF,paths={{'owner'}}} or describe(a.value.type)
       copy(list,field(p,string.format('c%04d',index)),part,argument(list,a).value)
      end
     end
     local adapter=fresh('_let_owned_adapter_');local ab=IR.builder();local paramsA,inputsA,argumentsA={}, {S.inValue(P)},{}
     local envId=ab:valueId();paramsA[1]=I.ValueParam(0,envId,P)
     local envPlace=I.PtrIndex(ab:convert(ab:ref(envId,P),S.Ptr(env.type)),ab:u32(0),env.type)
     local listA=L{}
     local function adapterArgument(value,index)
      local input=contracts[s.entry].inputs[index]
      if input.kind=='InPlace' then
       local data=value.type==REF and ab:get(value,'data',P) or value
       return I.BorrowArg(I.PtrIndex(ab:convert(data,S.Ptr(input.type)),ab:u32(0),input.type))
      end
      return I.ValueArg(value)
     end
     for index=1,#s.slots do local name=string.format('c%04d',index);local ty=captured[name]
      local value=ab:ref(ab:read(listA,ty,field(envPlace,name)),ty)
      argumentsA[#argumentsA+1]=adapterArgument(value,index)
     end
     for _,input in ipairs(d.signature.inputs) do
      local id=ab:valueId();paramsA[#paramsA+1]=I.ValueParam(#inputsA,id,input.type);inputsA[#inputsA+1]=input
      argumentsA[#argumentsA+1]=adapterArgument(ab:ref(id,input.type),#argumentsA+1)
     end
     local resultIds,returnValues={},{};for _,ty in ipairs(d.signature.results) do local id=ab:valueId();resultIds[#resultIds+1]=id;returnValues[#returnValues+1]=ab:ref(id,ty) end
     ab:emit(listA,I.Call(L(resultIds),s.entry,L(argumentsA)));ab:return_(listA,returnValues)
     program.functions[#program.functions+1]=I.Fn(adapter,I.Body,0,L(inputsA),d.signature.results,L(paramsA),listA)
     publish(list,s.value.id,s.type,b:make(d.type,{b:callable(b:code(adapter,P,false),data,d.view),owner}))
    elseif k=='If' then
     local test=expr(list,s.test);local yes,no=L{},L{};statements(yes,s.yes,inLoop);statements(no,s.no,inLoop);b:emit(list,I.If(test,yes,no))
    elseif k=='Loop' then local loop=L{};statements(loop,s.body,true);b:emit(list,I.Loop(loop))
    elseif k=='Next' then b:emit(list,I.Next)
    elseif k=='Trap' then b:trap(list,expr(list,s.failure),s.reason)
    elseif k=='Return' then
     local returned={}
     for index,value in ipairs(s.values) do
      local v=expr(list,value)
      if output then copy(list,field(output,string.format('r%04d',index)),describe(value.type),v) else returned[#returned+1]=v end
     end
     -- Results in caller-owned storage are already cleanup-visible before this
     -- activation releases anything. Scalar returned cells have no holdings.
     if not borrowed then invoke(list,'leave',{b:ref(frameAddressId,P)}) end
     b:return_(list,returned)
    elseif k=='ConstructVariant' then
     local d=describe(s.type);local payload=s.payload and expr(list,s.payload);local id=b:valueId()
     b:emit(list,I.ConstructVariant(id,d.type,s.tag,payload));publish(list,s.value.id,s.type,b:ref(id,d.type))
    elseif k=='VariantMatches' or k=='VariantPayload' or k=='Switch' then
     local d=describe(s.sum);local variant=valueId(list,d.type,expr(list,b:ref(s.variant,s.sum)))
     if k=='Switch' then
      local cases={};for _,case in ipairs(s.cases) do local branch=L{};statements(branch,case.body,inLoop);cases[#cases+1]=I.Case(case.tag,case.fallback,branch) end
      b:emit(list,I.Switch(variant,d.type,L(cases)))
     else
      local id=b:valueId();b:emit(list,k=='VariantMatches' and I.VariantMatches(id,variant,d.type,s.tag) or I.VariantPayload(id,variant,d.type,s.tag))
      local ty=k=='VariantMatches' and S.Bool or S.caseOf(s.sum,s.tag)
      publish(list,s.value.id,ty,b:ref(id,describe(ty).type))
     end
    else reject('Unresolved owning statement '..k) end
   end
  end
  statements(body,fn.body,false)
  local frameType=S.Record(fields);local frameDescriptor={type=frameType,paths=framePaths}
  assert(not borrowed or #framePaths==0,'borrowed specialization acquired a holding')
  local cleanup=not borrowed and drop(frameDescriptor)
  -- Even a scalar-only activation in an owning call chain has a real linked
  -- record; its generated empty cleanup has the same non-failing C ABI.
  if not borrowed and not cleanup then cleanup=fresh('_let_drop_');program.lifecycle[cleanup]={'.function '..cleanup..' 2 0 aa -','  RET.A 2 0'} end
  local frameAddress=b:convert(b:addr(framePlace,S.Ptr(frameType),S.Borrow.WriteAccess),P)
  local entry=L{}
  if #frameType.fields>0 then
   local initial=zero(entry,frameType);entry[#entry+1]=I.Var(frame,frameType,initial)
  end
  if not borrowed then
   entry[#entry+1]=I.Let(frameAddressId,P,frameAddress)
   invoke(entry,'enter',{b:ref(frameAddressId,P),b:code(cleanup,P,true)})
  end
  for _,s in ipairs(body) do entry[#entry+1]=s end
  program.functions[#program.functions+1]=I.Fn(fn.id,fn.role,0,contract.inputs,contract.results,L(params),entry)
 end
 for _,fn in ipairs(source.functions) do transform(fn) end
 Check.program(program.functions,program.modules,program.foreigns,true)
 return program
end
return M
