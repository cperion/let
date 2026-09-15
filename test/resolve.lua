package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B=V.AST,V.Belt; local count=0
local function check(value) assert(value); count=count+1 end
local program=V.parse([[
let bias=7
let unused=99
let factory=
    let initial=mark(bias)
    let seed:Int
    let value mut=seed
    let step:Int
    do
        let callback=do value=value+step return bias end
        if step==0 do return callback() end
        return factory(seed,step-1)
    end
]],'resolve.let')
local resolved=program:resolve{hosts={mark={phase='runtime'}}}
local factory=resolved.module.names.factory; local plan=factory.template
check(#plan.steps==2 and plan.initial.first==1 and plan.initial.last==1)
check(plan.steps[1].prepare.first==3 and plan.steps[1].prepare.last==3)
check(plan.steps[2].prepare.first>plan.steps[2].prepare.last)
check(#plan.captures==1 and plan.captures[1]==resolved.module.names.bias)
local callback=plan.body_scope.names.callback.template
check(#callback.captures==3 and callback.captures[1]==plan.scope.names.value)
local writes=false
for _,use in ipairs(callback.capture_uses) do if use.access=='write' and use.definition==plan.scope.names.value then writes=true end end
check(writes)
local self_name=program.file.items[3].binding.value.terminal.statements[3].value.word
check(resolved.references[self_name][1].definition==factory and plan.self==factory)
local shadow=V.parse('let f=let x:Int do let x=x+1 return x end','shadow.let')
local names=shadow:resolve(); local f=names.module.names.f.template
check(f.scope.names.x~=f.body_scope.names.x)
check(require('test.execute')(shadow.file.items[1].binding.value:build_function('f'),{41},{})==42)
local scalar={type=B.Int,mode='copy'}; local owned={type=B.Named('StatefulWord'),mode='fresh'}
check(A.Read:bind_argument(scalar,B.Persistent,error)==B.CopyAccess)
local access,temporary=A.Read:bind_argument(owned,B.Transient,error)
check(access==B.ReadAccess and temporary)
check(A.OwnMut:bind_argument(owned,B.Persistent,error)==B.OwnAccess)
check(V.specialization_access(owned,error)==B.OwnAccess)
local ok=pcall(V.specialization_access,{type=owned.type,mode='borrow'},error)
check(not ok)
print(('passed %d lexical/stage contract checks'):format(count))

