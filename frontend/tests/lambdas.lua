-- Lambda types are stated once: from context or explicit parameter annotations.
local source=debug.getinfo(1,'S').source:sub(2)
local root=(source:match('^(.*[/\\])') or './')..'../'
package.path=root..'?.lua;'..root..'?/init.lua;'..root..'../build/?.lua;'..package.path
local Compiler=require('let.compiler')
local D=require('let.diag')
local S=require('let.schema')
local Int=require('int64')
local checks,executions=0,0
local function check(value,message) assert(value,message); checks=checks+1 end
local cases={
    {name='context',body='let add: (u32, u32): u32 = do(a, b) = a + b\nreturn add(n, 2)',expected={'42'},results={S.u32}},
    {name='parameters',body='let add = do(a, b: u32) = a + b\nreturn add(n, 2)',expected={'42'},results={S.u32}},
    {name='redundant',body='let add: (u32, u32): u32 = do(a, b: u32) = a + b\nreturn add(n, 2)',expected={'42'},results={S.u32}},
    {name='nullary',body='let value = do() = 42\nreturn value()',expected={'42'},results={S.u32}},
    {name='block',body='let choose = do(a: u32) if a == 0 then return 2 end return a + 2 end\nreturn choose(n)',expected={'42'},results={S.u32}},
    {name='vector',contract='(u32, bool)',body='let pair = do(a: u32) return a + 2, true end\nreturn pair(n)',expected={'42','1'},results={S.u32,S.bool}},
    {name='unit',contract='unit',body='let noop = do return end\nreturn noop()',expected={},results={S.unit}},
    {name='immediate',body='return (do(a: u32) = a + 2)(n)',expected={'42'},results={S.u32}},
    {name='floating',contract='f64',body='let add = do(a: f64) = a + 2.0\nreturn add(f64(n))',expected={'4631107791820423168'},results={S.f64}},
    {name='argument-context',prelude='let apply(f: (u32): u32, x: u32): u32 = f(x)\n',
        body='return apply(do(a) = a + 2, n)',expected={'42'},results={S.u32}},
}
local equivalent={}
for _,case in ipairs(cases) do
    local text=(case.prelude or '')..'let run(n: u32): '..(case.contract or 'u32')..' = do\n'..case.body..'\nend\nreturn { functions = { run } }'
    local artifact=Compiler.compile{profile='slet',name=case.name..'.slet',source=text}
    equivalent[case.name]=artifact.assembly
    local typedLet=Compiler.typed{profile='let',name=case.name..'.let',source=text}
    local letLambda
    for _,fn in ipairs(typedLet.functions) do if fn.id:find('_lambda_',1,true) then letLambda=fn end end
    check(typedLet.phase=='typed-ir' and letLambda and #letLambda.results==#case.results,'Let shares lambda inference without requiring executable lowering')
    for index,ty in ipairs(case.results) do check(letLambda.results[index]==ty,'Let retains exact inferred result types') end
    local lambda
    for _,fn in ipairs(artifact.functions) do if fn.id:find('_lambda_',1,true) then lambda=fn end end
    check(lambda and #lambda.results==#case.results,case.name..' emits a complete lambda result contract')
    for index,ty in ipairs(case.results) do check(lambda.results[index]==ty,case.name..' infers the exact result type') end
    local images={}
    for _,optimize in ipairs{false,true} do
        for _,mode in ipairs{'interpreted','eager','lazy','threaded'} do
            local result=Compiler.stage(artifact.functions,{profile='slet',entry='run',mode=mode,optimize=optimize,arguments={40}})
            check(#result.cells==#case.expected,case.name..' result-vector arity')
            for index,value in ipairs(case.expected) do check(Int.format(result.cells[index],false)==value,case.name..' result in '..mode) end
            executions=executions+1
            if not images[optimize] then images[optimize]=result.module else check(images[optimize]==result.module,'mode-independent bytecode: '..case.name) end
        end
    end
end
check(equivalent.context==equivalent.parameters and equivalent.context==equivalent.redundant,
    'annotation placement does not change emitted representation or code')
local invalid={
    {'untyped','type-required','let f = do(a, b) = a + b\nreturn 0'},
    {'missing-one','type-required','let f = do(a: u32, b) = a + b\nreturn 0'},
    {'annotation-conflict','type-mismatch','let f: (u32): u32 = do(a: bool) = 0\nreturn 0'},
    {'result-conflict','type-mismatch','let f: (u32): bool = do(a) = a\nreturn 0'},
    {'inferred-result-conflict','type-mismatch','let f = do(a: u32) if a == 0 then return 1 end return true end\nreturn 0'},
    {'missing-return','missing-return','let f = do(a: u32) let x = a end\nreturn 0'},
}
for _,case in ipairs(invalid) do
    local name=case[1]..'.slet'
    local ok,diagnostic=pcall(Compiler.typed,{profile='slet',name=name,
        source='let main(): u32 = do\n'..case[3]..'\nend'})
    check(not ok and D.is(diagnostic) and diagnostic.code==case[2] and diagnostic.span and diagnostic.span.file==name,
        case[1]..' rejects with source diagnostic: '..tostring(diagnostic))
end
print(('PASS: lambda signatures stated once (%d checks, %d VM executions)'):format(checks,executions))
