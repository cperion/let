package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local S=require('let.schema');local IR=require('let.ir');local C=require('let.compiler')
local Life=require('let.lifetime');local I,L=S.Ir,S.List
local Assembler=require('assembler');local D=require('let.diag')
local functions,foreigns={},{}
local ptr=S.Ptr(S.U64)
local function build(name,emit,inputs,resultTypes)
 local b=IR.builder();local body={};local lifetime=Life.emitter(b,foreigns)
 local params,args,types={},{},{}
 for index,ty in ipairs(inputs or {}) do
  local value=b:valueId();params[index]=I.ValueParam(index-1,value,ty);args[index]=b:ref(value,ty);types[index]=S.inValue(ty)
 end
 emit(b,body,lifetime,args)
 local fn=I.Fn(name,I.Body,0,L(types),L(resultTypes or {S.U64}),L(params),L(body));functions[#functions+1]=fn;return fn
end
local root=I.ModuleRoot('persistent_counter',S.U64,true)
functions.moduleData={I.ModuleData(root,string.rep('\0',8))}
local function element(b,address) return b:ptrIndex(address,b:u32(0),S.U64) end
build('plain',function(b,body) b:return_(body,{b:int(S.U64,42)}) end)
build('normal',function(b,body,life)
 local scope=life:scope(body,2);local owner=life:allocate(body,scope,0,'local_bytes',8)
 local address=life:data(body,owner);b:store(body,element(b,address),b:int(S.U64,42))
 life:retain(body,scope,1,owner);life:drop(body,scope,0)
 local answer=b:read(body,S.U64,element(b,address));life:leave(body,scope);b:return_(body,{b:ref(answer,S.U64)})
end)
build('factory',function(b,body,life,args)
 local scope=life:scope(body,1);local owner=life:allocate(body,scope,0,'local_bytes',8)
 local address=life:data(body,owner);b:store(body,element(b,address),b:int(S.U64,42))
 life:move(body,args[1],0,scope,0);life:leave(body,scope);b:return_(body,{address})
end,{ptr},{ptr})
build('nested',function(b,body,life)
 local scope=life:scope(body,1);local result=b:valueId()
 b:emit(body,I.Call(L{result},'factory',L{I.ValueArg(scope)}))
 local answer=b:read(body,S.U64,element(b,b:ref(result,ptr)))
 life:leave(body,scope);b:return_(body,{b:ref(answer,S.U64)})
end)
build('abort_after_store',function(b,body,life)
 local scope=life:scope(body,1);life:allocate(body,scope,0,'local_bytes',8)
 b:store(body,I.Global(root),b:int(S.U64,99))
 b:trap(body,b:bool(true),'division-zero');life:leave(body,scope);b:return_(body,{b:int(S.U64,0)})
end)
build('read_persistent',function(b,body)
 local value=b:read(body,S.U64,I.Global(root));b:return_(body,{b:ref(value,S.U64)})
end)
build('failed_init',function(b,body,life)
 local scope=life:scope(body,2);life:allocate(body,scope,0,'local_bytes',8)
 life:call(body,'owner_new',{scope,life:number(1),life:number(999),life:number(8)})
 life:leave(body,scope);b:return_(body,{b:int(S.U64,0)})
end)
build('recursive_failure',function(b,body,life)
 local scope=life:scope(body,1);life:allocate(body,scope,0,'local_bytes',8)
 local result=b:valueId();b:emit(body,I.Call(L{result},'recursive_failure',L{}))
 life:leave(body,scope);b:return_(body,{b:ref(result,S.U64)})
end)
build('forgot_leave',function(b,body,life)
 local scope=life:scope(body,1);life:allocate(body,scope,0,'local_bytes',8);b:return_(body,{b:int(S.U64,0)})
end)
build('held_child',function(b,body,life)
 local scope=life:scope(body,2)
 local parent=life:allocate(body,scope,0,'local_owner',8)
 local child=life:allocate(body,scope,1,'local_bytes',8)
 local address=life:data(body,child);b:store(body,element(b,address),b:int(S.U64,42))
 life:call(body,'owner_set',{parent,child});life:drop(body,scope,1)
 local answer=b:read(body,S.U64,element(b,address));life:leave(body,scope);b:return_(body,{b:ref(answer,S.U64)})
end)
local exports={'plain','normal','nested','abort_after_store','read_persistent','failed_init','recursive_failure','forgot_leave','held_child'}
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
 FCALL.A __let_rt_v1_scope_enter
 FADDR.B 32
 PUSH.B 0
 PUSH.B 0
 PUSH.B 8
 FCALL.B __let_rt_v1_owner_new
 FCALL.B __let_rt_v1_owner_data
 PUSH.A 42
 ST64.B 0
 FADDR.A 32
 FCALL.A __let_rt_v1_scope_leave
 CGET.A 4
 MOVE.B
 RET.A 5 3
.export live_banks
]]
local file=assert(io.open('../build/runtime-owners.abcasm','wb'));file:write(assembly);file:close()
for _,mirror in ipairs{false,true} do
 local text=mirror and assembly:gsub('%.A','.__MIRROR'):gsub('%.B','.A'):gsub('%.__MIRROR','.B') or assembly
 local bytes=Assembler.assemble(text)
 for _,optimized in ipairs{false,true} do
  local image=optimized and C.optimize(bytes) or bytes
  local name='../build/runtime-owners-'..(mirror and 'b' or 'a')..(optimized and '-opt' or '')..'.abc'
  local output=assert(io.open(name,'wb'));output:write(image);output:close()
 end
end
local reentry=assembly:gsub('%.profile foreign','.profile foreign\n.extern host_reenter - i',1)..[[
.function reentry 0 1 - i
 CALLOC 24
 FADDR.A 24
 PUSH.A 24
 FCALL.A __let_rt_v1_scope_enter
 FADDR.A 24
 PUSH.A 0
 PUSH.A 0
 PUSH.A 8
 FCALL.A __let_rt_v1_owner_new
 DROP.A
 FCALL.A host_reenter
 FADDR.A 24
 FCALL.A __let_rt_v1_scope_leave
 RET.A 3 1
.export reentry
]]
local reentryFile=assert(io.open('../build/runtime-owners-reentry.abc','wb'));reentryFile:write((Assembler.assemble(reentry)));reentryFile:close()
local checks,executions=0,0
local function check(condition,message) checks=checks+1;assert(condition,message) end
for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do for _,optimize in ipairs{false,true} do
 for _,name in ipairs{'normal','nested','held_child'} do
  local result=C.stage(functions,{profile='slet',foreigns=foreigns,entry=name,mode=mode,optimize=optimize})
  executions=executions+1;check(tonumber(result.cells[1])==42,'runtime staging '..mode..'/'..name)
 end
end end
local bad=assembly:gsub('__let_rt_v1_owner_new','__let_rt_v9_owner_new')
local ffi=require('let.abi');local lib=ffi.load('../build/libabc.so');local module=ffi.new('abc_module *[1]');local error=ffi.new('abc_error[1]')
local data=Assembler.assemble(bad)
check(lib.abc_module_load(data,#data,module,error)~=0 and module[0]==nil,'unknown private runtime ABI rejects during module load')
bad=assembly:gsub('%.extern __let_rt_v1_owner_new aiii a','%.extern __let_rt_v1_owner_new aiii i')
data=Assembler.assemble(bad)
check(lib.abc_module_load(data,#data,module,error)~=0 and module[0]==nil,'runtime signature mismatch rejects during module load')
local ok,err=pcall(C.typed,{profile='slet',source='extern let __let_rt_v1_scope_leave(p: Ptr(U64)): Unit; let main(): U32 = 0'})
check(not ok and D.is(err) and err.code=='runtime-contract','source foreign words cannot impersonate runtime primitives: '..tostring(err))
local Runtime=require('let.runtime')
check(not Runtime.staging('\n.extern host_effect i i\n'),'ordinary host effects remain forbidden in staging')
ffi.cdef('int abc_emit_c(const void *,size_t,char **,size_t *,abc_error *); void abc_emitted_c_free(char *);')
local tool=ffi.load('../build/libabc-opt.so');local cSource=ffi.new('char *[1]');local cSize=ffi.new('size_t[1]')
data=Assembler.assemble(assembly)
check(tool.abc_emit_c(data,#data,cSource,cSize,error)~=0 and cSource[0]==nil,'restricted portable-C emitter must not accept runtime lifetime calls without its execution binding')
print(('runtime owner lowering: %d checks, %d VM executions; emitted both-bank raw/optimized images'):format(checks,executions))
