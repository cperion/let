local file=debug.getinfo(1,'S').source:sub(2)
local here=file:match('^(.*[/\\])') or './'
local root=here..'../../../'
package.path=root..'frontend/?.lua;'..root..'build/?.lua;'..here..'?.lua;'..package.path
local Probe=require('probe')
local function fixed(n) return {kind='fixed',arity=n} end
local signatures={add=fixed(2),double=fixed(1),take=fixed(1),pair=fixed(0),work=fixed(0),
    finish=fixed(0),send=fixed(1),apply=fixed(2),['g.spawn']=fixed(1),
    ['m.function']=fixed(3),['f.b.cget']=fixed(1),['f.b.muli']=fixed(1),['f.b.ret']=fixed(2),
    fmt={kind='rest'},dynamic={kind='dynamic'},point={kind='keyed'},x={kind='value'},y={kind='value'}}
local cases={
    {'scalar','double 3','double((3))'},
    {'binary','add 3 4','add((3), (4))'},
    {'nested','add double 3 4','add((double((3))), (4))'},
    {'values','add x y','add((x), (y))'},
    {'infix','double 3 + 4','(double((3)) + 4)'},
    {'multiply','add 1 2 * 3','(add((1), (2)) * 3)'},
    {'power','double 3 ^ 2','(double((3)) ^ 2)'},
    {'grouped explicit','add(1, 2 * 3)','add(1, (2 * 3))'},
    {'partial explicit','add(3)','add(3)'},
    {'nullary value','work','work'},
    {'nullary explicit','work()','work()'},
    {'final scalar adjustment','take pair()','take((pair()))'},
    {'final forwarding unchanged','take(pair())','take(pair())'},
    {'higher order explicit','apply(double, 3)','apply(double, 3)'},
    {'second unary operand','add 1 -2','add((1), ((- 2)))'},
    {'nullary callable argument','apply work 3','apply((work), (3))'},
    {'comma is outer boundary','add(double 3, 4)','add(double((3)), 4)'},
    {'block','g.spawn do return work() end','g.spawn(|| -> do return work() end)'},
    {'explicit block','g.spawn() do return work() end','g.spawn(|| -> do return work() end)'},
    {'binding','let n = add double 3 4','let n = add((double((3))), (4))','statements'},
    {'separate statements','send item\nfinish()','send((item)); finish()','statements'},
    {'space equivalence','send item finish()','send((item)); finish()','statements'},
    {'semicolon boundary','send item; finish()','send((item)); finish()','statements'},
    {'builder','m.function 1 1 do |f| f.b.cget 0 f.b.muli 2 f.b.ret 1 1 return end',
      'm.function((1), (1), |f| -> do f.b.cget((0)); f.b.muli((2)); f.b.ret((1), (1)); return end)','statements'},
}
local checks=0
for _,case in ipairs(cases) do
    local actual=Probe.parse(case[2],signatures,case[4])
    assert(actual==case[3],case[1]..'\nexpected '..case[3]..'\nactual   '..actual)
    checks=checks+1;print('ACCEPT '..case[1]..' => '..actual)
end
local rejected={
    {'bare partial','add 3','bare-arity'},
    {'comma argument','add 3, 4','bare-arity'},
    {'mixed explicit/bare','add (1 + 2) 3','bare-boundary'},
    {'higher order bare','apply double 3','bare-arity'},
    {'group after bare operand attaches as call','add 1 (double)','bare-arity'},
    {'rest','fmt 1 2','bare-boundary'},
    {'dynamic','dynamic 1','bare-boundary'},
    {'keyed','point 1 2','bare-boundary'},
    {'nullary surplus','work 3','bare-boundary'},
    {'first unary','double -3','bare-unary'},
    {'unknown block','unknown do return end','bare-signature'},
    {'block not final','add do return 1 end','bare-block'},
    {'crossing explicit separator','send item; finish()',nil,'statements',2},
    {'no implicit unit','g.spawn do 1 end','call-statement'},
    {'comparison chaining','1 < 2 < 3','parse'},
}
for _,case in ipairs(rejected) do
    local sig=signatures
    if case[5] then sig={};for k,v in pairs(signatures) do sig[k]=v end;sig.send=fixed(case[5]) end
    local ok,why=pcall(Probe.parse,case[2],sig,case[4])
    assert(not ok,case[1]..' unexpectedly accepted')
    if case[3] then assert(tostring(why):find(case[3],1,true),case[1]..': '..tostring(why)) end
    checks=checks+1;print('REJECT '..case[1]..' => '..tostring(why))
end
local changed={};for k,v in pairs(signatures) do changed[k]=v end;changed.send=fixed(2)
local before=Probe.parse('send item\nfinish()',signatures,'statements')
local after=Probe.parse('send item\nfinish()',changed,'statements')
assert(before=='send((item)); finish()' and after=='send((item), (finish()))')
checks=checks+1
print('HAZARD signature change: '..before..' -> '..after)

-- Production compiler/VM sees ONLY desugared existing syntax. This neither
-- changes the parser nor establishes availability of target builders/tasks.
local Compiler=require('let.compiler')
local modes={'interpreted','threaded','eager','lazy'}
local prelude=[[
let double(x: u32): u32 = x * 2
let add(a, b: u32): u32 = a + b
let take(x: u32): u32 = x
let pair(): (u32, u32) = do return 7, 11 end
]]
local vmCases={
    {'add double 3 4',10}, {'double 3 + 4',10}, {'add 1 2 * 3',9},
    {'double 3 ^ 2',36}, {'add(1, 2 * 3)',7},
}
local executions=0
for _,case in ipairs(vmCases) do
    local lowered=Probe.parse(case[1],signatures)
    local artifact=Compiler.compile{profile='slet',name='arity-probe.slet',
        source=prelude..'\nlet main(): u32 = '..lowered..'\n'}
    for _,mode in ipairs(modes) do
        local result=Compiler.stage(artifact.functions,{profile='slet',entry='main',exports={'main'},mode=mode})
        assert(tonumber(result.cells[1])==case[2],case[1]..' failed in '..mode)
        executions=executions+1
    end
    print('VM '..case[1]..' => '..case[2]..' (four modes)')
end
local adjusted=Probe.parse('take pair()',signatures)
local supported,diagnostic=pcall(Compiler.compile,{profile='slet',name='arity-vector-gap.slet',
    source=prelude..'\nlet main(): u32 = '..adjusted..'\n'})
assert(not supported and diagnostic.code=='result-arity','Update this recorded production gap if result adjustment becomes supported')
print('CURRENT FRONTEND GAP: '..adjusted..' rejects result-arity; scalar adjustment is not VM-validated')
print(string.format('PASS: %d parser/ambiguity checks; %d production VM executions; 1 recorded frontend gap',checks,executions))
