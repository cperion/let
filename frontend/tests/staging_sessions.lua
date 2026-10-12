-- Public VM bridge contracts. The stateful assembly fixture below intentionally
-- tests module-image ownership, not source lowering (source globals are unfinished).
local source=debug.getinfo(1,'S').source:sub(2)
local root=(source:match('^(.*[/\\])') or './')..'../'
package.path=root..'?.lua;'..root..'?/init.lua;'..root..'../build/?.lua;'..package.path
local Stage=require('let.stage')
local Compiler=require('let.compiler')
local S=require('let.schema')
local D=require('let.diag')
local Int=require('int64')
local ffi=require('let.abi')
local I,L=S.Ir,S.ASDL.List
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function rejects(code,fn,message)
    local ok,err=pcall(fn)
    check(not ok and D.is(err) and err.code==code,(message or code)..': '..tostring(err))
    return err
end
local Util=require('tool_util')
local abiOK,abiFacts,abiError=Util.capture{root..'../build/validate-staging-abi'}
check(abiOK,'public-header ABI probe: '..abiError)
local enums={ABC_OK=0,ABC_EXEC_INTERPRETED=0,ABC_EXEC_COMPILED=1,ABC_EXEC_LAZY=2,ABC_EXEC_THREADED=3,ABC_INTEGER=0,ABC_ADDRESS=1,ABC_FLOAT=2}
for key,value in abiFacts:gmatch('([%w_.]+) (%d+)') do
    local ty,field=key:match('^(.-)%.(.+)$')
    local actual=enums[key]
    if actual==nil then actual=field and ffi.offsetof(ty,field) or ffi.sizeof(key) end
    check(actual==tonumber(value),'FFI declaration matches public header: '..key)
end
local function uint(n,ty) return I.Const(ty or S.u64,I.UInt(n)) end
local function abi(name,results)
    return I.Fn(name,I.Entry,0,L{},L(results),L{},L{I.Return(L{uint(0)})})
end
local artifact={profile='slet',lineMap={},assembly=[[
.profile memory
.datazero 8
.function bump 0 1
  GLD64.A 0
  ADDI.A 1
  DUP.A
  GST64.A 0
  RET.A 0 1
.function get 0 1
  GLD64.A 0
  RET.A 0 1
.function fail 0 1
  PUSH.A 99
  GST64.A 0
  ABORT 2
.export bump
.export get
.export fail
]]}
local declarations={abi('bump',{S.u64}),abi('get',{S.u64}),abi('fail',{S.u64})}
local function call(program,entry) return program:call{entry=entry}.cells[1] end
local input=I.Value(1)
local calc=I.Fn('calc',I.Entry,0,L{S.inValue(S.u32)},L{S.u32},L{I.ValueParam(0,input,S.u32)},
    L{I.Return(L{I.Bin(I.Mul,I.Ref(input,S.u32),uint(2,S.u32),S.u32)})})
local floatIdentity=I.Fn('float_identity',I.Entry,0,L{S.inValue(S.f64)},L{S.f64},L{I.ValueParam(0,input,S.f64)},
    L{I.Return(L{I.Ref(input,S.f64)})})
local floatAdd=I.Fn('float_add',I.Entry,0,L{S.inValue(S.f64)},L{S.f64},L{I.ValueParam(0,input,S.f64)},
    L{I.Return(L{I.Bin(I.Add,I.Ref(input,S.f64),I.Const(S.f64,I.Float(1.0)),S.f64)})})
local floatArtifact=Compiler.lower({floatIdentity,floatAdd},{profile='slet',exports={'float_identity','float_add'}})
local unitFn=I.Fn('empty',I.Entry,0,L{},L{S.unit},L{},L{I.Return(L{uint(0,S.unit)})})
local calcArtifact=Compiler.lower({calc,unitFn},{profile='slet',exports={'calc','empty'}})
for _,mode in ipairs{'interpreted','eager','lazy','threaded'} do
    for _,optimize in ipairs{false,true} do
        local session=Stage.open{mode=mode,optimize=optimize}
        local first=session:prepare(artifact,declarations)
        check(call(first,'bump')==1 and call(first,'bump')==2,mode..' retains one prepared image')
        local second=session:prepare(artifact,declarations)
        check(call(second,'get')==0 and call(first,'get')==2,'identical bytes have distinct module identities')
        local other=Stage.open{mode=mode,optimize=optimize}
        local isolated=other:prepare(artifact,declarations)
        check(call(isolated,'get')==0,'separate session does not share writes')
        rejects('static-index-range',function() call(first,'fail') end,'structured VM abort')
        check(call(first,'get')==99 and call(first,'bump')==100,'abort resets stacks but does not roll back image writes')
        check(call(isolated,'get')==0 and call(second,'get')==0,'failed session work does not affect other images')
        other:close(); other:close()
        rejects('static-session',function() call(isolated,'get') end,'closed program rejects')
        rejects('static-session',function() other:prepare(artifact,declarations) end,'closed prepare rejects')
        rejects('static-option',function() first:call{entry='get',mode='lazy'} end,'session policy cannot change per call')
        local nested=false
        first:call{entry='get',progress=function(event)
            if event.phase=='start' then
                rejects('static-session',function() call(first,'get') end,'reentrant execution rejects')
                rejects('static-session',function() session:close() end,'callback cannot free active VM')
                nested=true
            end
        end}
        check(nested and call(first,'get')==100,'reentrant failures leave session usable')
        local ok,err=pcall(function() first:call{entry='get',progress=function() error('callback-marker',0) end} end)
        check(not ok and err=='callback-marker' and call(first,'get')==100,'callback error clears busy guard')
        local trapped=rejects('static-index-range',function()
            first:call{entry='fail',progress=function(event) if event.phase=='abort' then error('notification-error',0) end end}
        end,'VM error wins over failed abort notification')
        check(trapped.vmStatus=='abort' and trapped.abortReason==2,'structured status/reason are retained')
        local arithmetic=session:prepare(calcArtifact,{calc,unitFn})
        check(#arithmetic:call{entry='empty'}.cells==0,'unit has no physical result cell')
        check(arithmetic:call{entry='calc',arguments={21}}.cells[1]==42,'VM arithmetic in '..mode)
        local floats=session:prepare(floatArtifact,{floatIdentity,floatAdd})
        for _,bits in ipairs{'0','9223372036854775808','9218868437227405312','9221120237041090626','18442240474082181120'} do
            local result=floats:call{entry='float_identity',arguments={{type=S.f64,bits=Int.parse(bits)}}}
            check(Int.format(result.cells[1],false)==bits,'f64 identity preserves exact bits: '..bits)
        end
        check(Int.format(floats:call{entry='float_add',arguments={'4607182418800017408'}}.cells[1],false)=='4611686018427387904',
            'floating arithmetic is performed by VM')
        rejects('static-argument',function() arithmetic:call{entry='calc',arguments={ffi.new('double',21)}} end,'no implicit cdata conversion')
        local mismatch=session:prepare(calcArtifact,{I.Fn('calc',I.Entry,0,L{S.inValue(S.f64)},L{S.u32},L{},L{})})
        rejects('static-signature',function() mismatch:call{entry='calc',arguments={0}} end,'signature kinds checked')
        local address=session:prepare(artifact,{abi('get',{S.ref(S.unit)})})
        rejects('static-transport',function() call(address,'get') end,'address transport is not a scalar guess')
        rejects('static-assembly',function() session:prepare({assembly='not an instruction',lineMap={}},{}) end,'malformed assembly rejects')
        rejects(optimize and 'abc-opt-invalid' or 'static-vm-invalid',function()
            session:prepare({assembly='.function bad 0 1\nRET.A 0 1\n.export bad\n',lineMap={}},{abi('bad',{S.u64})})
        end,'public loader independently rejects invalid bytecode')
        check(call(first,'get')==99,'prepare errors leave existing images intact')
        session:close(); session:close()
        rejects('static-session',function() call(first,'get') end,'explicit close releases handles')
    end
end

-- Defensive finalizers must not root their own session/program cycles.
for _,mode in ipairs{'interpreted','eager','lazy','threaded'} do
    local function abandon()
        local session=Stage.open{mode=mode,optimize=false}
        local program=session:prepare(artifact,declarations)
        check(call(program,'bump')==1,'abandoned session starts with a fresh image')
        return setmetatable({session,program},{__mode='v'})
    end
    local weak=abandon()
    collectgarbage('collect'); collectgarbage('collect')
    check(weak[1]==nil and weak[2]==nil,'defensive finalizers do not retain session cycles')
end

-- Every one-shot failure must execute explicit cleanup, including callbacks.
local realOpen=Stage.open; local opened
Stage.open=function(options) opened=realOpen(options); return opened end
for _,phase in ipairs{'start','finish'} do
    local ok,err=pcall(Stage.execute,calcArtifact,{calc},{mode='interpreted',entry='calc',arguments={21},optimize=false,
        progress=function(event) if event.phase==phase then error('one-shot-'..phase,0) end end})
    check(not ok and err=='one-shot-'..phase and opened.closed and opened.vm==nil and #opened.programs==0,
        'one-shot '..phase..' callback failure closes session')
end
rejects('static-assembly',function() Stage.execute({assembly='bad',lineMap={}},{},{mode='interpreted',optimize=false}) end)
check(opened.closed and opened.vm==nil,'one-shot prepare failure closes session')
rejects('static-index-range',function() Stage.execute(artifact,declarations,{mode='interpreted',entry='fail',optimize=false}) end)
check(opened.closed and opened.vm==nil and #opened.programs==0,'one-shot VM abort closes session')
Stage.open=realOpen
rejects('static-option',function() Stage.open{mode='interpreted',runtime='/alternate/executable'} end,'obsolete subprocess option rejects')
rejects('static-stack',function() Stage.open{mode='interpreted',stackCells=math.huge} end,'invalid resource limit rejects')

-- Independent process: no optimizer library/module and no subprocess execution
-- are available inside the staging bridge, including during error handling.
local env='ABC_OPT_LIBRARY=/does/not/exist '
local command=env..Util.command({os.getenv('LUA') or 'luajit',root..'tests/staging_no_optimizer.lua'})
check(os.execute(command)==0,'unoptimized VM staging is independent of optimizer and subprocess helpers')
print(('PASS: owned staging sessions (%d checks)'):format(checks))
