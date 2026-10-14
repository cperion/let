package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local S=require('let.schema');local IR=require('let.ir');local C=require('let.compiler')
local Life=require('let.lifetime');local I,L=S.Ir,S.List
local Assembler=require('assembler');local D=require('let.diag')
local functions,foreigns={},{};local ptr=S.Ptr(S.U64)
local bytes={type=S.U64,size=8,align=8,owners={}}
local link={type=ptr,size=8,align=8,owners={0}}
local pair={type=S.Record{first=ptr,second=ptr},size=16,align=8,owners={0,8}}
local function build(name,emit,inputs,results)
 local b=IR.builder();local body={};local life=Life.emitter(b,foreigns,functions)
 local params,args,types={},{},{}
 for index,ty in ipairs(inputs or {}) do local v=b:valueId();params[index]=I.ValueParam(index-1,v,ty);args[index]=b:ref(v,ty);types[index]=S.inValue(ty) end
 emit(b,body,life,args)
 local fn=I.Fn(name,I.Body,0,L(types),L(results or {S.U64}),L(params),L(body));functions[#functions+1]=fn;return fn
end
local root=I.ModuleRoot('persistent_counter',S.U64,true);functions.moduleData={I.ModuleData(root,string.rep('\0',8))}
local function element(b,address) return b:ptrIndex(address,b:u32(0),S.U64) end
local function install(b,body,life,parent,child,offset,ordinal)
 life:call(body,'owner_hold',{child})
 local address=life:data(body,parent)
 b:store(body,b:ptrIndex(b:convert(address,S.Ptr(ptr)),b:u32(offset/8),ptr),child)
 life:call(body,'owner_commit',{parent,b:int(S.U64,ordinal)})
end
build('plain',function(b,body) b:return_(body,{b:int(S.U64,42)}) end)
build('get_release',function(b,body,life) b:return_(body,{life:releaseEntry(body,bytes)}) end,nil,{ptr})
build('get_link_release',function(b,body,life) b:return_(body,{life:releaseEntry(body,link)}) end,nil,{ptr})
build('normal',function(b,body,life)
 local scope=life:scope(body,2);local owner=life:allocate(body,scope,0,bytes)
 local address=life:data(body,owner);b:store(body,element(b,address),b:int(S.U64,42))
 life:retain(body,scope,1,owner);life:drop(body,scope,0)
 local answer=b:read(body,S.U64,element(b,address));life:leave(body,scope);b:return_(body,{b:ref(answer,S.U64)})
end)
build('factory',function(b,body,life,args)
 local scope=life:scope(body,1);local owner=life:allocate(body,scope,0,bytes)
 local address=life:data(body,owner);b:store(body,element(b,address),b:int(S.U64,42))
 life:move(body,args[1],0,scope,0);life:leave(body,scope);b:return_(body,{address})
end,{ptr},{ptr})
build('nested',function(b,body,life)
 local scope=life:scope(body,1);local result=b:valueId();b:emit(body,I.Call(L{result},'factory',L{I.ValueArg(scope)}))
 local answer=b:read(body,S.U64,element(b,b:ref(result,ptr)));life:leave(body,scope);b:return_(body,{b:ref(answer,S.U64)})
end)
build('abort_after_store',function(b,body,life)
 local scope=life:scope(body,1);life:allocate(body,scope,0,bytes);b:store(body,I.Global(root),b:int(S.U64,99))
 b:trap(body,b:bool(true),'division-zero');life:leave(body,scope);b:return_(body,{b:int(S.U64,0)})
end)
build('read_persistent',function(b,body) local v=b:read(body,S.U64,I.Global(root));b:return_(body,{b:ref(v,S.U64)}) end)
build('failed_init',function(b,body,life)
 local scope=life:scope(body,2);life:allocate(body,scope,0,bytes)
 life:call(body,'owner_new',{scope,life:number(1),life:number(8),life:number(8),life:number(0),b:nullPtr(ptr)})
 life:leave(body,scope);b:return_(body,{b:int(S.U64,0)})
end)
build('recursive_failure',function(b,body,life)
 local scope=life:scope(body,1);life:allocate(body,scope,0,bytes)
 local result=b:valueId();b:emit(body,I.Call(L{result},'recursive_failure',L{}));life:leave(body,scope);b:return_(body,{b:ref(result,S.U64)})
end)
build('forgot_leave',function(b,body,life)
 local scope=life:scope(body,1);life:allocate(body,scope,0,bytes);b:return_(body,{b:int(S.U64,0)})
end)
build('held_child',function(b,body,life)
 local scope=life:scope(body,2);local parent=life:allocate(body,scope,0,link);local child=life:allocate(body,scope,1,bytes)
 local address=life:data(body,child);b:store(body,element(b,address),b:int(S.U64,42))
 install(b,body,life,parent,child,0,1);life:drop(body,scope,1)
 local answer=b:read(body,S.U64,element(b,address));life:leave(body,scope);b:return_(body,{b:ref(answer,S.U64)})
end)
build('copy_pair',function(b,body,life)
 local scope=life:scope(body,3);local child=life:allocate(body,scope,0,bytes)
 local parent=life:allocate(body,scope,1,pair);install(b,body,life,parent,child,0,1);install(b,body,life,parent,child,8,2)
 local copy=life:allocate(body,scope,2,pair)
 life:copyInto(body,pair,copy,parent)
 life:leave(body,scope);b:return_(body,{b:int(S.U64,42)})
end)
build('release_loop',function(b,body,life,args)
 local data=life:data(body,args[1]);local initialized=life:call(body,'owner_initialized',{args[1]})
 local index=b:var(body,S.U32,b:u32(0));local loop={};local i=b:read(loop,S.U32,I.Local(index))
 local done={};b:return_(done,{})
 local step={};local value=b:read(step,ptr,b:ptrIndex(b:convert(data,S.Ptr(ptr)),b:ref(i,S.U32),ptr))
 life:call(step,'owner_enqueue',{b:ref(value,ptr)})
 b:store(step,I.Local(index),b:bin('Add',b:ref(i,S.U32),b:u32(1),S.U32));b:emit(step,I.Next)
 b:emit(loop,I.If(b:bin('Ge',b:convert(b:ref(i,S.U32),S.U64),initialized,S.Bool),L(done),L(step)))
 b:emit(body,I.Loop(L(loop)))
end,{ptr},{})
for _,count in ipairs{0,1,2} do
 build('loop_'..count,function(b,body,life)
  local scope=life:scope(body,2);local child=life:allocate(body,scope,0,bytes)
  local release=life:call(body,'release_bind',{I.Code('release_loop',ptr)})
  local parent=life:call(body,'owner_new',{scope,life:number(1),life:number(16),life:number(8),life:number(0),release})
  for i=1,count do install(b,body,life,parent,child,(i-1)*8,i) end
  life:leave(body,scope);b:return_(body,{b:int(S.U64,42)})
 end)
end
build('release_variant',function(b,body,life,args)
 local initialized=life:call(body,'owner_initialized',{args[1]});local empty={};b:return_(empty,{})
 b:emit(body,I.If(b:bin('Eq',initialized,b:int(S.U64,0),S.Bool),L(empty),L{}))
 local data=life:data(body,args[1]);local tag=b:read(body,S.U64,element(b,data))
 local left,right={},{}
 life:call(left,'owner_release_field',{args[1],b:int(S.U64,8),b:int(S.U64,1)})
 life:call(right,'owner_release_field',{args[1],b:int(S.U64,16),b:int(S.U64,1)})
 b:emit(body,I.If(b:bin('Eq',b:ref(tag,S.U64),b:int(S.U64,0),S.Bool),L(left),L(right)));b:return_(body,{})
end,{ptr},{})
for _,tag in ipairs{0,1} do
 build('variant_'..tag,function(b,body,life)
  local scope=life:scope(body,2);local child=life:allocate(body,scope,0,bytes)
  local release=life:call(body,'release_bind',{I.Code('release_variant',ptr)})
  local parent=life:call(body,'owner_new',{scope,life:number(1),life:number(24),life:number(8),life:number(0),release})
  b:store(body,element(b,life:data(body,parent)),b:int(S.U64,tag))
  install(b,body,life,parent,child,tag==0 and 8 or 16,1)
  life:leave(body,scope);b:return_(body,{b:int(S.U64,42)})
 end)
end
build('variant_empty',function(b,body,life)
 local scope=life:scope(body,1);local release=life:call(body,'release_bind',{I.Code('release_variant',ptr)})
 life:call(body,'owner_new',{scope,life:number(0),life:number(24),life:number(8),life:number(0),release})
 life:leave(body,scope);b:return_(body,{b:int(S.U64,42)})
end)
build('binding_failure',function(b,body,life)
 local scope=life:scope(body,2);life:allocate(body,scope,0,bytes)
 life:allocate(body,scope,1,{type=pair.type,size=16,align=8,owners={0,8}})
 life:leave(body,scope);b:return_(body,{b:int(S.U64,42)})
end)
build('chain',function(b,body,life)
 local scope=life:scope(body,2);local release=life:releaseEntry(body,link);local leaf=life:allocate(body,scope,0,bytes)
 local current=b:var(body,ptr,leaf);local counter=b:var(body,S.U64,b:int(S.U64,0));local loop={}
 local value=b:read(loop,ptr,I.Local(current))
 local parent=life:call(loop,'owner_new',{scope,life:number(1),life:number(8),life:number(8),life:number(0),release})
 install(b,loop,life,parent,b:ref(value,ptr),0,1);life:drop(loop,scope,0);life:move(loop,scope,0,scope,1)
 b:store(loop,I.Local(current),parent)
 local index=b:read(loop,S.U64,I.Local(counter));local next_=b:bin('Add',b:ref(index,S.U64),b:int(S.U64,1),S.U64)
 b:store(loop,I.Local(counter),next_)
 local finish={};life:leave(finish,scope);b:return_(finish,{b:int(S.U64,42)})
 b:emit(loop,I.If(b:bin('Ge',next_,b:int(S.U64,100000),S.Bool),L(finish),L{I.Next}))
 b:emit(body,I.Loop(L(loop)))
end)
build('bad_release',function(b,body,life,args)
 life:call(body,'scope_leave',{args[1]});b:return_(body,{})
end,{ptr},{})
build('bad_type',function(b,body,life)
 life:call(body,'release_bind',{I.Code('bad_release',ptr)});b:return_(body,{b:int(S.U64,42)})
end)
build('bad_policy',function(b,body,life)
 local scope=life:scope(body,1);local release=life:releaseEntry(body,bytes)
 life:call(body,'owner_new',{scope,life:number(0),life:number(8),life:number(8),b:int64(S.U64,1,0),release})
 life:leave(body,scope);b:return_(body,{b:int(S.U64,42)})
end)
local exports={'bad_type','bad_policy','plain','get_release','normal','nested','abort_after_store','read_persistent','failed_init','recursive_failure','forgot_leave','held_child','copy_pair','chain','binding_failure','get_link_release','loop_0','loop_1','loop_2','variant_0','variant_1','variant_empty','release_variant'}
local artifact=C.lower(functions,{profile='slet',foreigns=foreigns,exports=exports})
local assembly=artifact.assembly..[[
.function live_banks 0 3 - iii
 PUSH.A 333
 CPUSH.A
 CALLOC 32
 PUSH.A 111
 PUSH.B 222
 FADDR.A 32
 PUSH.A 32
 FCALL.A __let_rt_v3_scope_enter
 CALL.A get_link_release 0
 FADDR.B 32
 PUSH.B 0
 PUSH.B 8
 PUSH.B 8
 PUSH.B 0
 MOVE.A
 FCALL.B __let_rt_v3_owner_new
 CPUSH.B
 CALL.A get_release 0
 FADDR.B 40
 PUSH.B 1
 PUSH.B 8
 PUSH.B 8
 PUSH.B 0
 MOVE.A
 FCALL.B __let_rt_v3_owner_new
 DUP.B
 FCALL.B __let_rt_v3_owner_hold
 CGET.A 0
 FCALL.A __let_rt_v3_owner_data
 ST64.A 0
 CGET.A 0
 PUSH.A 1
 FCALL.A __let_rt_v3_owner_commit
 FADDR.A 40
 FCALL.A __let_rt_v3_scope_leave
 CGET.A 5
 MOVE.B
 RET.A 6 3
.export live_banks
]]
local file=assert(io.open('../build/runtime-owners.abcasm','wb'));file:write(assembly);file:close()
for _,mirror in ipairs{false,true} do
 local text=mirror and assembly:gsub('%.A','.__MIRROR'):gsub('%.B','.A'):gsub('%.__MIRROR','.B') or assembly
 local bytes_=Assembler.assemble(text)
 for _,optimized in ipairs{false,true} do
  local image=optimized and C.optimize(bytes_) or bytes_;local name='../build/runtime-owners-'..(mirror and 'b' or 'a')..(optimized and '-opt' or '')..'.abc'
  local output=assert(io.open(name,'wb'));output:write(image);output:close()
 end
end
local reentry=assembly:gsub('%.profile foreign','.profile foreign\n.extern host_reenter - i',1)..[[
.function reentry 0 1 - i
 CALLOC 24
 FADDR.A 24
 PUSH.A 24
 FCALL.A __let_rt_v3_scope_enter
 FADDR.A 24
 PUSH.A 0
 PUSH.A 8
 PUSH.A 8
 PUSH.A 0
 CALL.A get_release 0
 FCALL.A __let_rt_v3_owner_new
 DROP.A
 FCALL.A host_reenter
 FADDR.A 24
 FCALL.A __let_rt_v3_scope_leave
 RET.A 3 1
.export reentry
]]
local output=assert(io.open('../build/runtime-owners-reentry.abc','wb'));output:write((Assembler.assemble(reentry)));output:close()
local checks,executions=0,0
local function check(c,message) checks=checks+1;assert(c,message) end
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimized in ipairs{false,true} do
 for _,name in ipairs{'normal','nested','held_child','copy_pair','loop_0','loop_1','loop_2','variant_0','variant_1','variant_empty'} do
  local result=C.stage(functions,{profile='slet',foreigns=foreigns,entry=name,mode=mode,optimize=optimized})
  executions=executions+1;check(tonumber(result.cells[1])==42,mode..'/'..name)
 end
end end
local ffi=require('let.abi');local lib=ffi.load('../build/libabc.so');local module=ffi.new('abc_module *[1]');local error=ffi.new('abc_error[1]')
for _,bad in ipairs{(assembly:gsub('__let_rt_v3_owner_new','__let_rt_v2_owner_new')),(assembly:gsub('%.extern __let_rt_v3_owner_new aiiiia a','%.extern __let_rt_v3_owner_new aiiiia i'))} do
 local data=Assembler.assemble(bad);check(lib.abc_module_load(data,#data,module,error)~=0 and module[0]==nil,'obsolete ABI/mismatched primitive must reject')
end
local ok,err=pcall(C.typed,{profile='slet',source='extern let __let_rt_v3_scope_leave(p: Ptr(U64)): Unit; let main(): U32 = 0'})
check(not ok and D.is(err) and err.code=='runtime-contract','source cannot impersonate runtime primitives')
check(not require('let.runtime').staging('\n.extern host_effect i i\n'),'ordinary host effects remain forbidden')
print(('C release glue: %d checks, %d VM executions; both-bank raw/optimized images'):format(checks,executions))
