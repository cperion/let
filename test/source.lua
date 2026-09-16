package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A=V.AST; local execute=require('test.execute')
local count=0
local function check(value) assert(value); count=count+1 end
local function parse(text) return V.parse(text,'source.let') end
local source=[[
let example = let n : Int do : Int
    let x mut = 1
    let y mut = 2
    let count mut = 0
    while count < n do
        let saved = x
        x = y
        y = saved
        count = count + 1
    end
    switch x do
    case 1 return 12
    case 2 return 21
    else return 0
    end
end
]]
local function run(text,n) local p=parse(text); return execute(p.file.items[1].binding.value:build_function('example'),{n},{}) end
check(run(source,3)==21); check(run(source,4)==12)
local tokens=V.Lexer.new(source,'source.let'):scan(); local spelling={}
for _,token in ipairs(tokens) do if token.kind~='eof' then spelling[#spelling+1]=token.spelling end end
check(run(table.concat(spelling,' \t\r\n'),3)==21)
local separated=parse('let f=do : Unit first(); second() end').file.items[1].binding.value.terminal.statements
local juxtaposed=parse('let f=do : Unit first()\nsecond() end').file.items[1].binding.value.terminal.statements
check(#separated==2 and #juxtaposed==1 and A.Specialize:isclassof(juxtaposed[1].value))
local word=parse('let f=let x:Int let p=mark(x) let y:Int do : Int return apply(y, let z:Int do : Int return z+x end) end').file.items[1].binding.value
check(#word.items==3 and A.Prelude:isclassof(word.items[2]))
check(A.Word:isclassof(word.terminal.statements[1].value.arguments[2]))
local aggregate=parse('let a={let p=1; do : Int return p end, {let left=2 let right=3}}').file.items[1].binding.value.terminal.value
check(A.PositionalAggregate:isclassof(aggregate) and A.NamedAggregate:isclassof(aggregate.elements[2].terminal.value))
local body=parse('let f=do : Int let x=1 target.member[index[0]]=x return x end').file.items[1].binding.value.terminal.statements
check(#body==3 and A.Index:isclassof(body[2].place))
local text=parse('let text="é\\u{1f600}\\u{0}\\n"').file.items[1].binding.value.terminal.value
check(text.value=='é' .. string.char(240,159,152,128,0,10))
check(run('let example=do : Int return -9223372036854775808 end')==V.scalar.min)
-- §3/§11 type expressions: arrow, sum, keyed record, positional record, and the terminal result.
local arrow=parse('let f : Int -> Int -> Int = do : Int return 1 end').file.items[1].binding.constraint
check(A.Arrow:isclassof(arrow) and A.Arrow:isclassof(arrow.to) and arrow.from.name=='Int' and arrow.to.to.name=='Int')
local sum=parse('let f : Int | Text = 0').file.items[1].binding.constraint
check(A.Sum:isclassof(sum) and sum.left.name=='Int' and sum.right.name=='Text')
local record=parse('let f : { let x : Int let y : Text } = {}').file.items[1].binding.constraint
check(A.Record:isclassof(record) and #record.fields==2 and record.fields[2].name=='y')
local mutable=parse('let f : { let x mut : Int } = {}').file.items[1].binding.constraint
check(A.Record:isclassof(mutable) and mutable.fields[1].mutable,'a record type member carries mut')
-- §11.2: an aggregate of stages is a constructor word, not a separate type syntax.
local ctor=parse('let Point = { let x : Int let y : Text }').file.items[1].binding.value.terminal.value
check(A.Word:isclassof(ctor),'an aggregate of stages is a constructor word')
local tuple=parse('let f : { Int, Text } = {}').file.items[1].binding.constraint
check(A.Tuple:isclassof(tuple) and #tuple.elements==2)
local result=parse('let f = do : Unit return {} end').file.items[1].binding.value.terminal.result
check(result and result.name=='Unit')
local grouped=parse('let f : (Int -> Int) -> Int = 0').file.items[1].binding.constraint
check(A.Arrow:isclassof(grouped) and A.Arrow:isclassof(grouped.from))
print(('passed %d source integration checks'):format(count))

