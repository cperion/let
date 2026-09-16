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
    do : Int
        let callback=do : Int value=value+step return bias end
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
local shadow=V.parse('let f=let x:Int do : Int let x=x+1 return x end','shadow.let')
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
-- §3.2: an adjacent expression statement continues a binding's value, so it needs ";". The
-- diagnostic names that cause rather than reporting the binding's own name as unknown.
local function separator_message(text)
    local _,problems=V.parse(text,'separator.let'):resolve{}
    for _,problem in ipairs(problems) do
        if tostring(problem.message):find('end the value with ";"',1,true) then return problem.message end
    end
    return nil
end
check(separator_message('let f=let x:Int do : Int return x end\ndo : Unit let b=1\nf(b) return end')~=nil)
check(separator_message('let f=let x:Int do : Int return x end\ndo : Unit let b=1;\nf(b) return end')==nil)
-- §3.3 A resolved declaration carries the range of its name, and a duplicate binding names it.
local ranged=V.parse('let a : Int = 1\nlet b = let n : Int do : Int return n end','range.let')
local ranged_names=ranged:resolve()
check(ranged_names.module.names.a.range.start.line==1 and ranged_names.module.names.a.range.start.column==5)
local ranged_stage=ranged_names.module.names.b.template.steps[1].stage
check(ranged_names.bindings[ranged_stage].range.start.line==2 and ranged_names.bindings[ranged_stage].range.start.column==13)
local _,duplicates=V.parse('let a : Int = 1\nlet a : Int = 2','duplicate.let'):resolve{}
check(#duplicates==1 and duplicates[1].span.line==2 and duplicates[1].span.column==5)
local duplicated,duplicate_error=pcall(function()
    V.parse('let a : Int = 1\nlet a : Int = 2','duplicate.let'):build{}
end)
check(not duplicated and tostring(duplicate_error):find('duplicate.let:2:5:',1,true))
-- Resolution collects every problem rather than throwing at the first, and build fails fast.
local _,tolerant=V.parse('let x : Int = missing\nlet y : Int = also_missing','tolerant.let'):resolve{}
check(#tolerant==2 and tolerant[1].span.line==1 and tolerant[2].span.line==2)
local tolerant_built,tolerant_error=pcall(function()
    V.parse('let x : Int = missing\nlet y : Int = also_missing','tolerant.let'):build{}
end)
check(not tolerant_built and tostring(tolerant_error):find('tolerant.let:1:15: unknown name missing',1,true))
-- §11.5 `or` is disjunction: between two type words it forms the tagged union, between values
-- it is the logical or. Only the operands can tell the two apart, so both are checked here.
local union=V.parse('let Opt = Int or Text','union.let'):resolve{}
local union_node=union.module.names.Opt.node.value.terminal.value
check(union.unions[union_node]==true and union.type_refs[union_node.left].node.type==true)
local logical=V.parse('let flag : Bool = true\nlet both = flag or false','logical.let'):resolve{}
local logical_node=logical.module.names.both.node.value.terminal.value
check(logical.unions[logical_node]==nil and logical.references[logical_node.left][1].definition==logical.module.names.flag)
check(#logical.diagnostics==0)
-- §: a statement list declares its names before resolving them, so a word may name a word defined
-- below it, which is what mutual recursion needs. The resolver accepts that; the builder cannot
-- capture a binding whose storage is not allocated yet, and names the piece it is missing rather
-- than crashing on it.
local forward=V.parse('let f = let x : Int do : Int return g(x) end\nlet g = let n : Int do : Int return n end\nlet answer = do : Int return f(1) end','forward.let')
local _,forward_problems=forward:resolve{}
check(#forward_problems==0,'a word may name a word declared below it')
local forwarded,forward_error=pcall(function() forward:build{} end)
check(not forwarded and tostring(forward_error):find('storage is not allocated up front',1,true)~=nil,
    'the builder names the missing piece instead of crashing')

-- A use that runs *now* cannot reach a binding whose initializer has not run, and the message names
-- that rather than calling the name unknown.
local _,early=V.parse('let a = b + 1\nlet b = 2','early.let'):resolve{}
check(#early==1 and tostring(early[1].message):find('is used before its initializer runs',1,true)~=nil,
    'a name used before its initializer runs names that cause')

-- A word invoked while the module initializes would run before a binding declared below it exists,
-- which the resolver accepts and the program-level check refuses.
local _,eager=V.parse('let f = let x : Int do : Int return g(x) end\nlet first = f(1)\nlet g = let n : Int do : Int return n end','eager.let'):resolve{}
local refusal=nil
for _,problem in ipairs(eager) do
    if tostring(problem.message):find('is invoked while the module initializes',1,true) then refusal=problem end
end
check(refusal~=nil and refusal.span.line==2,'a forward-referencing word invoked during initialization is refused')

print(('passed %d lexical/stage contract checks'):format(count))

