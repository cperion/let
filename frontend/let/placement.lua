-- Concrete field-drop generation retained from the retired materializer.
-- Paths identify actual holdings selected by source proofs, never merely fields
-- whose source type contains access. Program materialization consumes a completed
-- binding; it never guesses lifetime operations from source type membership.
local S=require('let.schema')
local M={}

-- Compiler-only holding paths form a traversal tree. Case nodes guard union
-- payloads; they are never serialized or interpreted by the runtime.
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

-- This is only the existing concrete C-entry emitter. It cannot choose
-- holdings, copy source values or route execution through the retired lowering.
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
-- Concrete materialization owns storage and ordered effects. It does not infer
-- roots, choose a may-alias member or turn carrier copies into count traffic.
function M.program(bound)
 assert(bound.phase=='bound-program','materialization needs a completed lifetime binding')
 local I,L=S.Ir,S.List
 local Walk=require('let.walk')
 local program={phase='physical-program',source=bound.source,binding=bound,
  functions={},modules=bound.modules,foreigns={},lifecycle={}}
 local external={};for _,f in ipairs(bound.foreigns) do program.foreigns[#program.foreigns+1]=f;external[f.target]=true end
 local physical=require('let.layout').physical(program)
 local ptr=S.Ptr(S.U8)
 local serial=0;local reserved={}
 for _,instance in ipairs(bound.instances) do reserved[instance.id]=true end
 for _,f in ipairs(bound.foreigns) do reserved[f.target]=true end
 local function fresh(prefix)
  local name
  repeat serial=serial+1;name=prefix..serial until not reserved[name]
  reserved[name]=true;return name
 end
 local drop=M.drops(program,physical,fresh)
 local function foreign(name,types)
  local id='__let_rt_source_'..name
  if not external[id] then
   local inputs={};for _,ty in ipairs(types) do inputs[#inputs+1]=S.inValue(ty) end
   program.foreigns[#program.foreigns+1]=I.Foreign(id,L(inputs),L{});external[id]=true
  end
  return id
 end
 local function uint(n) return I.Const(S.U64,I.UInt(n)) end
 local function index(n) return I.Const(S.U32,I.UInt(n)) end
 local function address(place,ty) return I.Convert(I.Addr(place,S.Ptr(ty)),ptr) end
 local function call(body,name,args)
  local arguments,types={},{ }
  for _,expr in ipairs(args) do arguments[#arguments+1]=I.ValueArg(expr);types[#types+1]=expr.type end
  body[#body+1]=I.Call(L{},foreign(name,types),L(arguments))
 end
 local function destructor(desc,header)
  local name=drop(desc,header)
  if name then foreign('drop',{ptr,ptr});return I.CEntry(name,ptr) end
  return I.Null(ptr)
 end
 for _,instance in ipairs(bound.instances) do
  local fn=instance.source
  if not next(instance.holdings) and (instance.result_count or 0)==0 then program.functions[#program.functions+1]=fn
  else
   local valueId,storageId=0,0
   Walk.walk(fn,{enter=function(node)
    if S.Ty.V:isclassof(node) then return false end
    if I.Value:isclassof(node) then valueId=math.max(valueId,node.id)
    elseif I.Storage:isclassof(node) then storageId=math.max(storageId,node.id) end
   end})
   local function value() valueId=valueId+1;return I.Value(valueId) end
   local function storage() storageId=storageId+1;return I.Storage(storageId) end
   local function capture(body,expr)
    local v=value();body[#body+1]=I.Let(v,expr.type,expr);return I.Ref(v,expr.type)
   end
   local function read(body,place,ty)
    local v=value();body[#body+1]=I.Read(v,ty,place);return I.Ref(v,ty)
   end
   local inputs,params={},{ }
   for _,p in ipairs(fn.inputs) do inputs[#inputs+1]=p end
   for _,p in ipairs(fn.params) do params[#params+1]=p end
   local outputs={}
   for role=1,instance.result_count do
    local slot=storage();outputs[role]=I.Local(slot)
    params[#params+1]=I.PlaceParam(#inputs,slot,ptr);inputs[#inputs+1]=S.inPlace(ptr)
   end
   local slots,localKeys={},{ }
   for k,r in pairs(instance.holdings) do
    if r.output then slots[k]=outputs[r.output] else localKeys[#localKeys+1]=k end
   end
   table.sort(localKeys)
   local body,frame,frameType,frameAddress,frameDrop={}
   if #localKeys>0 then
    -- The ABI header is exactly two pointers. Only actual holding fields follow.
    local fields={a_previous=ptr,b_drop=ptr};local paths={}
    frame=storage()
    for i,k in ipairs(localKeys) do
     local field=string.format('h_%08d',i);fields[field]=ptr;paths[#paths+1]={field}
     slots[k]=I.Project(I.Local(frame),I.Field(field))
    end
    frameType=S.Record(fields)
    local zero={};for _ in ipairs(frameType.fields) do zero[#zero+1]=I.Null(ptr) end
    body[#body+1]=I.Var(frame,frameType,I.Make(frameType,L(zero)))
    frameAddress=address(I.Local(frame),frameType)
    frameDrop=destructor{type=frameType,paths=paths}
    call(body,'enter',{frameAddress,frameDrop})
   end
   local points={};for point,stmt in pairs(instance.context.graph.statement_at) do points[stmt]=point end
   local function clone(node)
    if type(node)~='table' or S.Ty.V:isclassof(node) then return node end
    if node.kind=='Local' and instance.allocations[node.storage.id] then
     return I.Deref(node,instance.allocations[node.storage.id].type)
    end
    local class=getmetatable(node);local fields=class and class.__fields
    if not fields then return node end
    local args,changed={ },false
    for i,f in ipairs(fields) do
     local original=node[f.name];local replacement=original
     if f.list then
      local items={};local different=false
      for j,item in ipairs(original) do items[j]=clone(item);different=different or items[j]~=item end
      if different then replacement=L(items) end
     elseif f.type~='string' and f.type~='number' and f.type~='boolean' and f.type~='any' then replacement=clone(original) end
     args[i]=replacement;changed=changed or replacement~=original
    end
    if not changed then return node end
    return class(unpack(args,1,#fields))
   end
   local function clear(out,slot)
    call(out,'clear',{address(slot,ptr),destructor{type=ptr,paths={{}}}})
   end
   local function transfer(out,source,destination)
    if source==destination then return end
    -- Capture addresses and value before committing either store. The window
    -- contains only two ordinary stores: no call, allocation or checked index.
    local from=capture(out,address(source,ptr));local to=capture(out,address(destination,ptr))
    local src=I.PtrIndex(from,index(0),ptr);local dst=I.PtrIndex(to,index(0),ptr)
    local owner=read(out,src,ptr)
    out[#out+1]=I.Store(dst,owner);out[#out+1]=I.Store(src,I.Null(ptr))
   end
   local transform
   transform=function(statements,out)
    for _,stmt in ipairs(statements) do
     local point=points[stmt]
     if stmt.kind=='Var' and instance.allocations[stmt.storage.id] then
      local r=instance.allocations[stmt.storage.id]
      local initial=stmt.initial and capture(out,clone(stmt.initial))
      local layout=physical:layout(r.type)
      local payload=require('let.layout').align(32,layout.align)
      call(out,'alloc',{address(slots[r.key],ptr),uint(payload+layout.size),uint(math.max(8,layout.align)),I.Null(ptr)})
      local owner=read(out,slots[r.key],ptr)
      local data=I.Convert(I.Addr(I.PtrIndex(owner,index(payload),S.U8),ptr),S.Ptr(r.type))
      out[#out+1]=I.Var(stmt.storage,S.Ptr(r.type),data)
      if initial then out[#out+1]=I.Store(I.Deref(I.Local(stmt.storage),r.type),initial) end
     elseif stmt.kind=='Call' then
      local binding=instance.calls[point]
      local args={};for _,arg in ipairs(stmt.arguments) do args[#args+1]=clone(arg) end
      for role=1,binding and binding.resources or 0 do
       local slot=assert(slots['r:'..point.ordinal..':'..role])
       if instance.context.control.cyclic[point] then clear(out,slot) end
       args[#args+1]=I.BorrowArg(slot)
      end
      out[#out+1]=I.Call(stmt.results,stmt.target,L(args))
     elseif stmt.kind=='Return' then
      local values={};for _,expr in ipairs(stmt.values) do values[#values+1]=capture(out,clone(expr)) end
      local moved={}
      for id,ret in pairs(instance.returns[point] or {}) do if ret.resource and not moved[ret.resource] then
       moved[ret.resource]=true;transfer(out,assert(slots[ret.resource]),outputs[instance.results[id].role])
      end end
      if frame then call(out,'leave',{frameAddress}) end
      out[#out+1]=I.Return(L(values))
     elseif stmt.kind=='If' then
      local yes,no={},{ };transform(stmt.yes,yes);transform(stmt.no,no)
      out[#out+1]=I.If(clone(stmt.test),L(yes),L(no))
     elseif stmt.kind=='Loop' then
      local nested={};transform(stmt.body,nested);out[#out+1]=I.Loop(L(nested))
     elseif stmt.kind=='Switch' then
      local cases={};for _,case in ipairs(stmt.cases) do
       local nested={};transform(case.body,nested);cases[#cases+1]=I.Case(case.tag,case.fallback,L(nested))
      end
      out[#out+1]=I.Switch(stmt.variant,stmt.sum,L(cases))
     else out[#out+1]=clone(stmt) end
    end
   end
   transform(fn.body,body)
   program.functions[#program.functions+1]=I.Fn(fn.id,fn.role,fn.hidden,L(inputs),fn.results,L(params),L(body))
  end
 end
 require('let.check').program(program.functions,program.modules,program.foreigns,true)
 return program
end
return M
