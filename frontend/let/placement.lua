-- Concrete field-drop generation retained from the retired materializer.
-- Paths identify actual holdings selected by source proofs, never merely fields
-- whose source type contains access. No source-to-physical program transform is
-- provided until the proof-directed lifetime cutover is integrated.
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
return M
