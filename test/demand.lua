package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local checks=0
local function check(v,message) assert(v,message); checks=checks+1 end
local span=V.Source.Span('demand.let',1,1)
local range=V.Source.Range(span,span)
local function n(name) return A.Name(name,span) end
local function i(value) return A.Integer(tostring(value),span) end
local function call(name,value) return A.Invoke(n(name),L{value},span) end
local function ret(value) return A.Return(value,span) end
local function local_(name,value,mutable) return A.Local(A.Binding(name,mutable or false,nil,A.Chain(L(),A.Data(value),span),span,range),span) end
local function stage(name,type_) return A.Stage(name,A.Read,A.Constraint(type_,L(),range,span),span,range) end
local function host(name,purity,type_) return {symbol=name,phase='runtime',purity=purity,signature=B.Signature(L{B.Parameter(type_ or B.Int,A.Read)},L{B.Int})} end
local hosts={math=host('math','pure'),tick=host('tick','ordered'),peek=host('peek','pure',B.Named('Box'))}
local options={hosts=hosts,resources={Box={destroy='drop'}}}
local function build(stages,statements) return A.Chain(L(stages),A.Body(L(statements),nil),span):build_function('test',options) end
local function inspect(fn,class)
    local needed=fn:demands(); local total,live=0,0
    for id,block in ipairs(fn.blocks) do for i,instruction in ipairs(block.instructions) do if class:isclassof(instruction.operation) then
        total=total+1; if needed[id] and needed[id][#block.parameters+i-1] then live=live+1 end
    end end end
    return total,live
end
local dead=build({stage('flag','Bool')},{local_('unused',call('math',i(123))),A.If(n('flag'),L(),L(),span),ret(i(42))})
local total,live=inspect(dead,B.PureHostCall)
check(total==1 and live==0,'pure result must remain dead across branch interfaces')
local local_need=dead.blocks[1]:demands(); local pure_position
for index,instruction in ipairs(dead.blocks[1].instructions) do if B.PureHostCall:isclassof(instruction.operation) then pure_position=#dead.blocks[1].parameters+index-1 end end
check(local_need[pure_position],'block-local demand alone conservatively retains outgoing packet values')
local kept=build({stage('flag','Bool')},{local_('unused',call('tick',i(123))),A.If(n('flag'),L(),L(),span),ret(i(42))})
total,live=inspect(kept,B.HostCall); check(total==1 and live==1,'ordered calls cannot disappear with their unused data results')
local loop=build({stage('limit','Int')},{local_('unused',call('math',i(123))),local_('x',i(0),true),
    A.While(A.Binary(A.Less,n('x'),n('limit'),span),L{A.Assign(n('x'),A.Binary(A.Add,n('x'),i(1),span),span)},span),ret(n('x'))})
total,live=inspect(loop,B.PureHostCall); check(total==1 and live==0,'dead loop-carried SSA cycles must not become their own demand roots')
local read=build({stage('box','Box')},{A.Discard(call('peek',n('box')),span),ret(i(42))})
total,live=inspect(read,B.HostCall); check(total==1 and live==1,'a pure host promise cannot bypass memory/ownership dependencies')
local effect=B.Parameter(B.Effect,A.Read)
local ref=function(distance,output) return B.Ref(distance,output or 0) end
local forever=B.Function('forever',B.Signature(L{effect},L{B.Unit,B.Effect}),L{B.Block(L{effect},L{
    B.Instruction(B.IntegerLiteral('1'),L{B.Int},span),
    B.Instruction(B.HostCall('tick',ref(1),L{ref(0)}),L{B.Int,B.Effect},span)
},B.Jump(B.Edge(1,L{ref(0,1)})))})
forever:verify_flow(hosts)
local needed=forever:demands()
check(needed[1][2][1] and not needed[1][2][0],'nonreturning loops still root observable effects')
-- Unreachable blocks are not roots merely because they contain effects.
local entry=B.Block(L{effect},L{B.Instruction(B.UnitLiteral,L{B.Unit},span)},B.Return(L{ref(0),ref(1)}))
local program=B.Function('entry',forever.signature,L{entry,
    B.Block(forever.blocks[1].parameters,forever.blocks[1].instructions,B.Jump(B.Edge(2,L{ref(0,1)})))
}):verify_flow(hosts)
local demand,reachable=program:demands()
check(not reachable[2] and not demand[2],'unreachable effectful blocks must not seed demand')
local before=tostring(loop); loop:demands(); check(tostring(loop)==before,'analysis must not renumber or mutate the belt')
print(('passed %d whole-function demand checks'):format(checks))

