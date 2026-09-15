-- Test-only belt interpreter. This is not an evaluator used by the compiler.
local V=require('v2'); local B,A=V.Belt,V.AST
-- Exact scalars come from the same module the abstract evaluator uses, so the concrete
-- oracle and compile-time folding cannot disagree.
local ffi=require('ffi')
local scalar=V.scalar; local unit=scalar.unit
-- Test-only driver state: frames nest for ordinary calls and are replaced by tail calls.
local Run={}; Run.__index=Run
function Run:get(ref)
    local producer=self.block:resolve(self.position,ref); local value=self.values[producer][ref.output+1]
    assert(value~=nil,'undefined belt value'); return value
end
function Run:arguments(refs) local values={}; for i,ref in ipairs(refs) do values[i]=self:get(ref) end; return values end
function B.Op:execute() error('missing test interpreter opcode') end
function B.IntegerLiteral:execute() return scalar.integer(self.spelling,error) end
function B.BooleanLiteral:execute() return self.value end
function B.TextLiteral:execute() return self.value end
function B.UnitLiteral:execute() return unit end
function A.Add:execute(a,b) return scalar.add(a,b) end
function A.Subtract:execute(a,b) return scalar.subtract(a,b) end
function A.Multiply:execute(a,b) return scalar.multiply(a,b) end
-- `scalar` is the exact-arithmetic authority; these wrappers add the interpreter's
-- presentation of a trap, which is `trap: <reason>` like the C host hook.
function A.Divide:execute(a,b)
    if b==0 then error('trap: division by zero',0) end
    return scalar.divide(a,b)
end
function A.Remainder:execute(a,b)
    if b==0 then error('trap: remainder by zero',0) end
    return scalar.remainder(a,b)
end
function A.Equal:execute(a,b) return scalar.equal(a,b) end
function A.NotEqual:execute(a,b) return scalar.not_equal(a,b) end
function A.Less:execute(a,b) return scalar.less(a,b) end
function A.LessEqual:execute(a,b) return scalar.less_equal(a,b) end
function A.Greater:execute(a,b) return scalar.greater(a,b) end
function A.GreaterEqual:execute(a,b) return scalar.greater_equal(a,b) end
function A.And:execute(a,b) return a and b end
function A.Or:execute(a,b) return a or b end
function A.Negate:execute(a) return scalar.negate(a) end
function A.Not:execute(a) return not a end
function B.Unary:execute(ctx) return self.operator:execute(ctx:get(self.operand)) end
function B.Binary:execute(ctx) return self.operator:execute(ctx:get(self.left),ctx:get(self.right)) end
function B.CheckedBinary:execute(ctx) return self.operator:execute(ctx:get(self.left),ctx:get(self.right)),ctx:get(self.effect)+1 end
function B.PureHostCall:execute(ctx)
    local result=assert(ctx.hosts[self.symbol])(unpack(ctx:arguments(self.arguments)))
    if result==nil then result=unit end; return result
end
function B.HostCall:execute(ctx)
    local result=assert(ctx.hosts[self.symbol])(unpack(ctx:arguments(self.arguments)))
    if result==nil then result=unit end; return result,ctx:get(self.effect)+1
end
function B.Load:execute(ctx) return ctx:get(self.address).value,ctx:get(self.effect)+1 end
function B.Store:execute(ctx) ctx:get(self.address).value=ctx:get(self.value); return ctx:get(self.effect)+1 end
function B.Move:execute(ctx) return ctx:get(self.value),ctx:get(self.effect)+1 end
function B.Destroy:execute(ctx) assert(ctx.hosts[self.destructor])(ctx:get(self.value)); return ctx:get(self.effect)+1 end
function B.Construct:execute(ctx) local fields={}; for i,ref in ipairs(self.fields) do fields[i]=ctx:get(ref) end; return {fields=fields} end
function B.LoadField:execute(ctx) return ctx:get(self.record).fields[self.field+1] end
function B.StoreField:execute(ctx)
    local word=ctx:get(self.record); local fields={} for i,value in ipairs(word.fields) do fields[i]=value end
    fields[self.field+1]=ctx:get(self.value); return {fields=fields}
end
function B.CallFunction:execute(ctx)
    local fn=assert(ctx.program[self.target],'unknown call target')
    local incoming={ctx:get(self.effect)}
    for i,value in ipairs(ctx:arguments(self.arguments)) do incoming[i+1]=value end
    return unpack(Run.frame(fn,incoming,ctx.hosts,ctx.program,ctx.limit))
end
function B.TailCall:execute(ctx)
    local incoming={ctx:get(self.effect)}
    for i,value in ipairs(ctx:arguments(self.arguments)) do incoming[i+1]=value end
    return false,{tail={target=self.target,arguments=incoming}}
end
function B.Jump:execute(ctx) return self.edge.target,ctx:arguments(self.edge.arguments) end
function B.Branch:execute(ctx) local edge=ctx:get(self.condition) and self.yes or self.no; return edge.target,ctx:arguments(edge.arguments) end
function B.Return:execute(ctx) return false,ctx:arguments(self.values) end
function B.Trap:execute() error('trap: ' .. self.reason) end
-- Run one function frame with `incoming[1]` as its effect token. A tail call replaces
-- the frame instead of growing the test interpreter's Lua stack.
function Run.frame(fn,incoming,hosts,program,limit)
    while true do
        local block_id,steps=1,0
        while block_id do
            steps=steps+1; assert(steps<=limit,'test interpreter fuel exhausted')
            local block=fn.blocks[block_id]
            assert(#incoming==#block.parameters,'bad test packet')
            local ctx=setmetatable({block=block,values={},hosts=hosts,program=program,limit=limit},Run)
            for i,value in ipairs(incoming) do ctx.values[i-1]={value} end
            for i,instruction in ipairs(block.instructions) do
                ctx.position=#block.parameters+i-1; ctx.values[ctx.position]={instruction.operation:execute(ctx)}
            end
            ctx.position=#block.parameters+#block.instructions
            block_id,incoming=block.exit:execute(ctx)
        end
        if incoming.tail then
            fn=assert(program[incoming.tail.target],'unknown tail target'); incoming=incoming.tail.arguments
        else return incoming end
    end
end
return function(fn,arguments,hosts,limit,program)
    program=program or {[1]=fn}; limit=limit or 100000
    local incoming={0}
    for i,value in ipairs(arguments or {}) do
        local type_=fn.signature.parameters[i+1].type
        incoming[i+1]=type_==B.Int and ffi.new('int64_t',value) or value
    end
    local results=Run.frame(fn,incoming,hosts or {},program,limit)
    return results[1],results[#results]
end

