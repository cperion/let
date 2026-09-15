package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('v2'); local B,A,C,L=V.Belt,V.AST,V.C,V.List
assert(not package.loaded['let.infer'] and not package.loaded['let.evaluate'])
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function ref(distance,output) return B.Ref(distance,output or 0) end
local int=B.Parameter(B.Int,A.Read)
local effect=B.Parameter(B.Effect,A.Read)
local function instruction(op,types) return B.Instruction(op,types or L{B.Int},nil) end
local function verify(block,results)
    return B.Function('test',B.Signature(block.parameters,results or L{B.Int}),L{block}):verify_numbering()
end
-- Parameter a at 0, b at 1; dead literal at 2, add at 3, multiply at 4.
local block=B.Block(L{int,int},L{
    instruction(B.IntegerLiteral('7')),
    instruction(B.Binary(A.Add,ref(2),ref(1))),
    instruction(B.Binary(A.Multiply,ref(0),ref(0)))
},B.Return(L{ref(0)}))
verify(block)
local demanded,uses=block:demands()
check(not demanded[2],'dead producer must not be demanded')
check(demanded[0][0] and demanded[1][0] and demanded[3][0] and demanded[4][0],'reachable producers must be demanded')
check(uses[3][0]==2,'two consumers share one producer')
check(block.instructions[2].operation.left.distance==2,'demand must not renumber the original belt')
-- Host result is unused, but its effect successor is an exit root.
local effects=B.Block(L{effect},L{
    instruction(B.IntegerLiteral('42')),
    instruction(B.HostCall('observe',ref(1),L{ref(0)}),L{B.Int,B.Effect})
},B.Return(L{ref(1),ref(0,1)}))
verify(effects,L{B.Int,B.Effect})
local live=effects:demands()
check(live[2][1] and not live[2][0],'retain the effect without demanding the unused host result')
check(live[0][0] and live[1][0],'effect roots demand prior effects and arguments')
local loop=B.Block(L{int},L(),B.Jump(B.Edge(1,L{ref(0)})))
verify(loop)
check(loop:demands()[0][0],'backedge packet demands its current input')
local branch=B.Block(L{B.Parameter(B.Bool,A.Read),int},L(),
    B.Branch(ref(1),B.Edge(2,L{ref(0)}),B.Edge(2,L{ref(0)})))
local exit=B.Block(L{int},L(),B.Return(L{ref(0)}))
B.Function('branch',B.Signature(branch.parameters,L{B.Int}),L{branch,exit}):verify_numbering()
check(branch:demands()[0][0],'branch condition is a control root')
local function rejects(fn,pattern)
    local ok,err=pcall(fn); check(not ok and tostring(err):find(pattern),'expected ' .. pattern .. ', got ' .. tostring(err))
end
rejects(function() block:resolve(3,ref(3)) end,'precedes block')
rejects(function() block:resolve(3,ref(-1)) end,'nonnegative integer')
rejects(function() block:resolve(3,ref(0.5)) end,'nonnegative integer')
rejects(function() block:resolve(3,ref(2,1)) end,'parameter has only output zero')
rejects(function() block:resolve(4,ref(0,1)) end,'invalid producer output')
rejects(function() verify(B.Block(L{int},L(),B.Jump(B.Edge(2,L{ref(0)})))) end,'invalid block target')
rejects(function() verify(B.Block(L{int},L(),B.Jump(B.Edge(1,L())))) end,'edge parameter count mismatch')
local span=V.Source.Span('test.let',1,1)
local subject=A.Name('x',span)
local arm=A.Case(L{A.Integer('0',span)},L{A.Return(A.Integer('42',span),span)},span)
local selection=A.Switch(subject,L{arm},L(),span)
check(selection.subject==subject and #selection.cases==1,'AST keeps source-level switch structure')
local c=C.Unit(L{'stdint.h'},L{C.Function('answer',false,true,C.I64,L(),C.Block(L{C.Return(C.Integer(0,42))}))})
check(#c.declarations==1,'C output vocabulary constructs independently')
check(not package.loaded['let.codegen'],'v2 must not delegate to the old backend')
print(('passed %d v2 vocabulary/numbering checks'):format(checks))

