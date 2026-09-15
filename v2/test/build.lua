package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('v2'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('v2.test.execute')
local span=V.Source.Span('spec-fixture.let',7,3); local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(value,wanted,message) check(value==wanted,(message or 'result') .. ': ' .. tostring(value) .. ' ~= ' .. tostring(wanted)) end
local function n(name) return A.Name(name,span) end
local function i(value) return A.Integer(tostring(value),span) end
local function b(value) return A.Boolean(value,span) end
local function op(operator,left,right) return A.Binary(operator,left,right,span) end
local function ret(value) return A.Return(value,span) end
local function call(name,...) return A.Invoke(n(name),L{...},span) end
local function discard(value) return A.Discard(value,span) end
local function data(value) return A.Chain(L(),A.Data(value),span) end
local function local_(name,value,mutable) return A.Local(A.Binding(name,mutable or false,nil,data(value),span),span) end
local function assign(name,value) return A.Assign(n(name),value,span) end
local function stage(name,type_,cap) return A.Stage(name,cap or A.Read,type_ and A.Constraint(type_,L()) or nil,span) end
local function if_(condition,yes,no) return A.If(condition,L(yes),L(no or {}),span) end
local function while_(condition,body) return A.While(condition,L(body),span) end
local function move(name) return A.Move(n(name),span) end
local function borrow(name) return A.Borrow(n(name),span) end
local function case(labels,body) return A.Case(L(labels),L(body),span) end
local function switch(subject,cases,otherwise) return A.Switch(subject,L(cases),L(otherwise or {}),span) end
local box=B.Named('Box')
local function host(symbol,result,parameters) return {symbol=symbol,phase='runtime',purity='ordered',signature=B.Signature(L(parameters),L{result})} end
local function p(type_,cap) return B.Parameter(type_,cap or A.Read) end
local options={resources={Box={destroy='drop'}},hosts={
    tick=host('tick',B.Int,{p(B.Int)}),
    truth=host('truth',B.Bool,{p(B.Int)}),
    open=host('open',box,{p(B.Int)}),
    peek=host('peek',B.Int,{p(box)}),
    consume=host('consume',B.Unit,{p(box,A.Own)}),
    both=host('both',B.Unit,{p(box),p(box,A.Own)}),
    bump=host('bump',B.Unit,{p(B.Int,A.Mut)}),
    overlap=host('overlap',B.Unit,{p(B.Int,A.Mut),p(B.Int)})
}}
local function build(statements,stages,opts)
    return A.Chain(L(stages or {}),A.Body(L(statements)),span):build_function('fixture',opts or options)
end
local events,alive={},{}
local function log(text) events[#events+1]=text end
local hosts={
    tick=function(x) log('tick:' .. tonumber(x)); return x end,
    truth=function(x) log('truth:' .. tonumber(x)); return x~=0 end,
    open=function(x) local id=tonumber(x); assert(not alive[id]); alive[id]=true; log('open:' .. id); return id end,
    peek=function(x) assert(alive[x]); log('peek:' .. x); return x*10LL end,
    consume=function(x) assert(alive[x]); alive[x]=nil; log('consume:' .. x) end,
    drop=function(x) assert(alive[x],'double destruction'); alive[x]=nil; log('drop:' .. x) end,
    bump=function(x) x.value=x.value+1LL; log('bump') end
}
local function run(fn,args,trace)
    events,alive={},{}; local result=execute(fn,args,hosts)
    if trace then eq(table.concat(events,','),trace,'effect/cleanup trace') end
    return result
end
local function reject(statements,pattern,stages,opts)
    local ok,err=pcall(build,statements,stages,opts)
    check(not ok and tostring(err):find(pattern),'expected ' .. pattern .. ', got ' .. tostring(err))
    check(tostring(err):find('spec%-fixture.let:7:3:'),'diagnostic needs its source span')
end
-- §§4.1, 9.4: lexical snapshots, shadowing, and SSA assignment without storage.
local snapshot=build({local_('x',i(1),true),local_('saved',n('x')),assign('x',i(9)),ret(op(A.Add,n('saved'),n('x')))})
eq(run(snapshot),10)
for _,block in ipairs(snapshot.blocks) do for _,instruction in ipairs(block.instructions) do
    check(not B.Store:isclassof(instruction.operation) and not B.Allocate:isclassof(instruction.operation),'unescaped scalar mutation must use SSA versions')
end end
local shadow=build({local_('x',i(42)),if_(n('flag'),{local_('x',op(A.Add,n('x'),i(1)))}),ret(n('x'))},{stage('flag','Bool')})
eq(run(shadow,{true}),42); eq(run(shadow,{false}),42)
local joined=build({local_('x',i(1),true),if_(n('flag'),{assign('x',i(10))},{assign('x',i(20))}),ret(n('x'))},{stage('flag','Bool')})
eq(run(joined,{true}),10); eq(run(joined,{false}),20)
local returning=build({local_('x',i(1),true),if_(n('flag'),{ret(i(42))},{assign('x',i(7))}),ret(n('x'))},{stage('flag','Bool')})
eq(run(returning,{true}),42); eq(run(returning,{false}),7)
-- §§4.3, 13, 14: left-to-right effects; pins preserve earlier operands across branches.
local pinned=build({ret(op(A.Equal,call('truth',i(1)),op(A.And,n('flag'),call('truth',i(2)))))},{stage('flag','Bool')})
eq(run(pinned,{false},'truth:1'),false); eq(run(pinned,{true},'truth:1,truth:2'),true)
local lazy=build({ret(op(A.Or,n('flag'),op(A.Equal,op(A.Divide,i(1),i(0)),i(0))))},{stage('flag','Bool')})
eq(run(lazy,{true}),true)
local ok,err=pcall(run,lazy,{false}); check(not ok and tostring(err):find('trap:'),'selected division must trap')
local order=build({ret(op(A.Add,call('tick',i(1)),call('tick',i(2))))})
eq(run(order,{},'tick:1,tick:2'),3)
local unused=build({discard(op(A.Divide,i(1),i(0))),ret(i(42))})
local demand=unused.blocks[1]:demands(); local checked_position
for index,instruction in ipairs(unused.blocks[1].instructions) do if B.CheckedBinary:isclassof(instruction.operation) then checked_position=#unused.blocks[1].parameters+index-1 end end
check(demand[checked_position][1] and not demand[checked_position][0],'discarded division retained through effect, not data demand')
ok,err=pcall(run,unused); check(not ok and tostring(err):find('trap:'),'unused ordered operation remains observable')
-- §7: loop conditions run at the original header, even when they contain CFG.
local looping=build({local_('x',i(0),true),local_('saved',n('x')),while_(op(A.And,op(A.Less,n('x'),n('limit')),call('truth',i(1))),{assign('x',op(A.Add,n('x'),i(1)))}),ret(op(A.Add,n('x'),n('saved')))},{stage('limit','Int')})
eq(run(looping,{3},'truth:1,truth:1,truth:1'),3); eq(run(looping,{0},''),0)
local choose=build({switch(call('tick',n('x')),{case({i(0)},{ret(i(10))}),case({i(1),i(2)},{ret(i(20))})},{ret(i(30))})},{stage('x','Int')})
for x=-1,3 do eq(run(choose,{x},'tick:' .. x),x==0 and 10 or (x==1 or x==2) and 20 or 30) end
local bool_switch=build({switch(n('x'),{case({b(true)},{ret(i(1))}),case({b(false)},{ret(i(0))})})},{stage('x','Bool')})
eq(run(bool_switch,{true}),1); eq(run(bool_switch,{false}),0)
-- §§6.4-6.5, 9: initialization, movement, replacement and reverse cleanup.
local cleanup=build({local_('a',call('open',i(1))),local_('b',call('open',i(2))),ret(i(42))})
eq(run(cleanup,{},'open:1,open:2,drop:2,drop:1'),42)
local tail=build({local_('a',call('open',i(1))),local_('b',call('open',i(2))),ret(call('consume',move('b')))})
run(tail,{},'open:1,open:2,drop:1,consume:2')
local normal=build({local_('a',call('open',i(1))),local_('b',call('open',i(2))),discard(call('consume',move('b'))),ret(i(42))})
eq(run(normal,{},'open:1,open:2,consume:2,drop:1'),42)
local conditional=build({local_('a',call('open',i(1))),if_(n('flag'),{discard(call('consume',move('a')))}),ret(i(42))},{stage('flag','Bool')})
eq(run(conditional,{true},'open:1,consume:1'),42); eq(run(conditional,{false},'open:1,drop:1'),42)
local replaced=build({local_('a',call('open',i(1)),true),assign('a',call('open',i(2))),ret(i(42))})
eq(run(replaced,{},'open:1,open:2,drop:1,drop:2'),42)
local restored=build({local_('a',call('open',i(1)),true),if_(n('flag'),{discard(call('consume',move('a')))}),assign('a',call('open',i(2))),ret(i(42))},{stage('flag','Bool')})
eq(run(restored,{true},'open:1,consume:1,open:2,drop:2'),42); eq(run(restored,{false},'open:1,open:2,drop:1,drop:2'),42)
local temporary=build({ret(call('tick',call('peek',call('open',i(1)))))})
eq(run(temporary,{},'open:1,peek:1,drop:1,tick:10'),10)
local trap=build({local_('a',call('open',i(1))),ret(op(A.Divide,i(1),i(0)))})
ok,err=pcall(run,trap); check(not ok and tostring(err):find('trap:'),'trap expected'); eq(table.concat(events,','),'open:1','traps do not clean up')
local resource_loop=build({local_('a',call('open',i(1)),true),local_('x',i(0),true),while_(op(A.Less,n('x'),i(2)),{assign('a',call('open',op(A.Add,n('x'),i(2)))),assign('x',op(A.Add,n('x'),i(1)))}),ret(i(42))})
eq(run(resource_loop,{},'open:1,open:2,drop:1,open:3,drop:2,drop:3'),42)
local crossed=build({local_('a',call('open',i(1))),local_('b',call('open',i(2))),if_(n('flag'),{discard(call('consume',move('a')))},{discard(call('consume',move('b')))}),ret(i(42))},{stage('flag','Bool')})
eq(run(crossed,{true},'open:1,open:2,consume:1,drop:2'),42)
eq(run(crossed,{false},'open:1,open:2,consume:2,drop:1'),42)
local swapped=build({local_('x',i(1),true),local_('y',i(2),true),local_('count',i(0),true),while_(op(A.Less,n('count'),i(3)),{local_('saved',n('x')),assign('x',n('y')),assign('y',n('saved')),assign('count',op(A.Add,n('count'),i(1)))}),ret(op(A.Add,op(A.Multiply,n('x'),i(10)),n('y')))})
eq(run(swapped),21,'backedge transfer is parallel')
local result_resource=build({local_('a',call('open',i(1))),local_('b',call('open',i(2))),ret(move('b'))})
eq(run(result_resource,{},'open:1,open:2,drop:1'),2); check(alive[2],'returned owner must survive')
-- §9.3: external mutable places use ordered loads/stores, not scalar copy-back.
local mutable=build({discard(call('bump',borrow('x'))),assign('x',op(A.Add,n('x'),i(1))),ret(n('x'))},{stage('x','Int',A.Mut)})
local address={value=40LL}; eq(run(mutable,{address},'bump'),42); eq(address.value,42)
-- §§11, 13: representations and exact literal boundaries.
eq(run(build({ret(n('x'))},{stage('x')},{parameters={B.Int}}),{42}),42)
eq(run(build({ret(op(A.Equal,A.Text('a\0é',span),A.Text('a\0é',span)))})),true)
eq(run(build({ret(op(A.Add,i('9223372036854775807'),i(1)))})),-9223372036854775808LL)
eq(run(build({ret(op(A.Divide,A.Unary(A.Negate,i('9223372036854775808'),span),A.Unary(A.Negate,i(1),span)))})),-9223372036854775808LL)
reject({ret(i('9223372036854775808'))},'out of Int range')
reject({ret(i('0x_1'))},'invalid integer spelling')
reject({ret(n('missing'))},'unknown name')
reject({local_('x',i(1)),local_('x',i(2))},'duplicate binding')
reject({local_('x',i(1)),assign('x',i(2))},'immutable')
reject({if_(i(1),{})},'expected')
reject({local_('a',call('open',i(1))),discard(call('consume',move('a'))),discard(call('peek',n('a')))},'use after move')
reject({local_('a',call('open',i(1))),ret(call('peek',n('a')))},'tail invocation borrow')
reject({local_('a',call('open',i(1))),discard(call('both',n('a'),move('a')))},'conflicting borrow')
reject({discard(call('overlap',borrow('x'),n('x'))) },'conflicting borrow',{stage('x','Int',A.Mut)})
reject({local_('a',call('open',i(1))),if_(n('flag'),{discard(call('consume',move('a')))}),ret(move('a'))},'use after move',{stage('flag','Bool')})
reject({ret(move('a'))},'borrowed stage',{stage('a','Box')})
reject({local_('x',i(1),true),discard(call('bump',borrow('x')))},'address%-taken locals')
reject({ret(call('tick'))},'exactly saturate')
reject({switch(i(1),{case({i(1)},{ret(i(1))}),case({i('0x1')},{ret(i(2))})})},'duplicate case')
local prelude=A.Prelude(A.Binding('p',false,nil,data(call('tick',i(1))),span))
ok,err=pcall(function() A.Chain(L{stage('a','Int'),prelude,stage('b','Int')},A.Body(L{ret(i(42))}),span):build_function('staged',options) end)
check(not ok and tostring(err):find('preludes must run between arguments'),'§6.2 forbids lowering a prelude into an all-arguments-bound terminal')
local shadow_options={hosts={fixture=options.hosts.tick}}
reject({ret(call('fixture',i(1)))},'source%-word invocation',{},shadow_options)
reject({ret(call('x'))},'invocation requires a runtime word',{stage('x','Int')})
local owned_entry=build({ret(move('a'))},{stage('a','Box',A.Own)})
events,alive={}, {[1]=true}; eq(execute(owned_entry,{1},hosts),1); check(alive[1] and #events==0,'owned entry transfers without destroying its return')
-- Deliberately malformed belts must not pass the separate flow verifier.
local r=function(d,o) return B.Ref(d,o or 0) end
local effect=B.Parameter(B.Effect,A.Read)
local bad=B.Function('bad',B.Signature(L{effect},L{B.Int,B.Effect}),L{B.Block(L{effect},L{
    B.Instruction(B.IntegerLiteral('1'),L{B.Int},nil),
    B.Instruction(B.HostCall('tick',r(1),L{r(0)}),L{B.Int,B.Effect},nil)
},B.Return(L{r(0),r(2)}))})
ok,err=pcall(function() bad:verify_flow(options.hosts) end)
check(not ok and tostring(err):find('effect chain bypasses'),'cannot bypass an ordered producer at return')
check(not package.loaded['let.infer'] and not package.loaded['let.evaluate'] and not package.loaded['let.codegen'],'builder must be independent of the current compiler')
print(('passed %d specification-grounded v2 build checks'):format(checks))

