-- Validate the flow emitted by the builder, independently of its mutable drafts.
-- This is type/effect verification, not a second ownership checker for arbitrary IR.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local Check={}; Check.__index=Check
function Check:type(ref) local _,type_=self.block:resolve(self.position,ref); return type_ end
function Check:expect(ref,type_)
    assert(self:type(ref):same(type_),'operand type mismatch')
end
function Check:results(types)
    assert(#types==#self.instruction.results,'instruction result count mismatch')
    for i,type_ in ipairs(types) do assert(self.instruction.results[i]:same(type_),'instruction result type mismatch') end
end
function Check:effect(ref)
    local producer,type_=self.block:resolve(self.position,ref)
    assert(type_==B.Effect and producer==self.effect_position and ref.output==self.effect_output,'effect chain bypasses an ordered operation')
end
function Check:ordered(ref,types)
    for _,type_ in ipairs(types) do assert(type_~=B.Effect,'ordered operation must have exactly one effect result') end
    self:effect(ref); local results=L(); results:insertall(types); results:insert(B.Effect); self:results(results)
    self.effect_position,self.effect_output=self.position,#types
end
function B.Op:verify() error('flow verifier does not yet support this opcode',0) end
function B.IntegerLiteral:verify(ctx)
    local text=self.spelling; local negative=text:sub(1,1)=='-'
    require('let.literal').integer(negative and text:sub(2) or text,negative,function(m) error(m,0) end)
    ctx:results(L{B.Int})
end
function B.BooleanLiteral:verify(ctx) ctx:results(L{B.Bool}) end
function B.UnitLiteral:verify(ctx) ctx:results(L{B.Unit}) end
function B.TextLiteral:verify(ctx) ctx:results(L{B.Text}) end
function B.FloatLiteral:verify(ctx)
    require('let.literal').float(self.spelling,function(m) error(m,0) end)
    ctx:results(L{B.Float})
end
function B.Unary:verify(ctx)
    local type_=ctx:type(self.operand)
    if self.operator==A.Not then ctx:expect(self.operand,B.Bool); ctx:results(L{B.Bool})
    elseif self.operator==A.ToFloat then ctx:expect(self.operand,B.Int); ctx:results(L{B.Float})
    elseif self.operator==A.ToInt then ctx:expect(self.operand,B.Float); ctx:results(L{B.Int})
    else
        assert(type_==B.Int or type_==B.Float,'negation requires a numeric operand')
        ctx:results(L{type_})
    end
end
function A.BinaryOp:verify(ctx,left,right)
    local type_=ctx:type(left)
    ctx:expect(right,type_)
    assert(type_==B.Int or type_==B.Float,'arithmetic requires a numeric operand')
    return type_
end
local function compare(_,ctx,left,right)
    local type_=ctx:type(left); ctx:expect(right,type_)
    assert(type_==B.Int or type_==B.Float,'comparison requires a numeric operand'); return B.Bool
end
A.Less.verify=compare; A.LessEqual.verify=compare; A.Greater.verify=compare; A.GreaterEqual.verify=compare
local function equal_(_,ctx,left,right)
    local type_=ctx:type(left); assert(type_:copyable(),'no implicit equality for this type'); ctx:expect(right,type_); return B.Bool
end
A.Equal.verify=equal_; A.NotEqual.verify=equal_
local function boolean_(_,ctx,left,right) ctx:expect(left,B.Bool); ctx:expect(right,B.Bool); return B.Bool end
A.And.verify=boolean_; A.Or.verify=boolean_
function B.Binary:verify(ctx)
    local result=self.operator:verify(ctx,self.left,self.right)
    assert(not ((self.operator==A.Divide or self.operator==A.Remainder) and result==B.Int),'potential trap must consume an effect')
    ctx:results(L{result})
end
function B.CheckedBinary:verify(ctx)
    assert(self.operator==A.Divide or self.operator==A.Remainder,'unsupported checked operator')
    ctx:expect(self.left,B.Int); ctx:expect(self.right,B.Int); ctx:ordered(self.effect,L{B.Int})
end
function B.HostCall:verify(ctx)
    local host=assert(ctx.hosts[self.symbol],'missing host contract'); local signature=host.signature
    assert(#signature.parameters==#self.arguments,'host argument count mismatch')
    for i,parameter in ipairs(signature.parameters) do
        if parameter.capability==A.Mut then
            -- A mutable stage is reached through a borrow of the caller's place (§6.3).
            local borrow=ctx:type(self.arguments[i])
            assert(B.Borrow:isclassof(borrow) and borrow.pointee:same(parameter.type),'host mutable stage requires a mutable place')
        else
            ctx:expect(self.arguments[i],parameter.type)
        end
    end
    ctx:ordered(self.effect,signature.results)
end
function B.PureHostCall:verify(ctx)
    local host=assert(ctx.hosts[self.symbol],'missing host contract'); local signature=host.signature
    assert(host.purity=='pure' and #signature.results==1 and signature.results[1]:copyable(),'invalid pure host result contract')
    assert(#signature.parameters==#self.arguments,'host argument count mismatch')
    for i,parameter in ipairs(signature.parameters) do
        assert(parameter.type:copyable() and parameter.capability~=A.Mut,'pure host producer cannot bypass memory/ownership ordering')
        ctx:expect(self.arguments[i],parameter.type)
    end
    ctx:results(signature.results)
end
-- Records declare their own shape in the instruction's result type, so the verifier
-- checks the operand types against it instead of inventing member names.
-- Borrowing a place is an operation in its own right (§9.3): it is the same storage, but
-- the type becomes a borrow, which is what carries the ownership and lifetime rules.
function B.BorrowPlace:verify(ctx)
    local pointee=ctx:pointee(self.address)
    ctx:results(L{B.Borrow(pointee,self.stable)})
end
-- A field of a place is a place, so it is reached through a borrow of that field (§9.3).
function B.FieldAddress:verify(ctx)
    local record=ctx:pointee(self.place)
    local fields=record:record()
    assert(fields and self.field<#fields,'a field address requires a valid record field')
    ctx:results(L{B.Borrow(fields[self.field+1].type,self.stable)})
end
function B.Construct:verify(ctx)
    local result=ctx.instruction.results[1]
    local fields=result and result:record()
    assert(fields and #fields==#self.fields,'construct must declare a record result')
    for i,ref in ipairs(self.fields) do ctx:expect(ref,fields[i].type) end
    ctx:results(L{result})
end
function B.LoadField:verify(ctx)
    local record=ctx:type(self.record); local fields=record:record()
    assert(fields and self.field<#fields,'load requires a valid record field')
    ctx:results(L{fields[self.field+1].type})
end
function B.StoreField:verify(ctx)
    local record=ctx:type(self.record); local fields=record:record()
    assert(fields and self.field<#fields,'store requires a valid record field')
    ctx:expect(self.value,fields[self.field+1].type); ctx:results(L{record})
end
function Check:callee(target,arguments)
    local callee=assert(self.functions[target],'unknown call target'); callee=callee.signature or callee
    assert(#arguments==#callee.parameters-1,'call argument count mismatch')
    for i,ref in ipairs(arguments) do self:expect(ref,callee.parameters[i+1].type) end
    return callee
end
function B.Allocate:verify(ctx)
    local type_=ctx:type(self.initial)
    ctx:ordered(self.effect,L{B.Address(type_)})
end
function Check:pointee(ref)
    local type_=self:type(ref)
    assert(B.Address:isclassof(type_) or B.Borrow:isclassof(type_),'a place is required here')
    return type_.pointee
end
function B.Load:verify(ctx)
    ctx:ordered(self.effect,L{ctx:pointee(self.address)})
end
function B.Store:verify(ctx)
    local pointee=ctx:pointee(self.address)
    ctx:expect(self.value,pointee); ctx:ordered(self.effect,L())
end
function B.Move:verify(ctx)
    -- Ownership transfer applies to any non-Copy value, including a record of resources.
    local type_=ctx:type(self.value); assert(not type_:copyable(),'move requires a non-Copy value')
    ctx:ordered(self.effect,L{type_})
end
function B.Destroy:verify(ctx)
    assert(B.Named:isclassof(ctx:type(self.value)),'destroy requires a represented resource'); ctx:ordered(self.effect,L())
end
function Check:edge(edge)
    local parameters=self.fn.blocks[edge.target].parameters
    -- Zipping the two lists hides a length mismatch; the packet is the target block's shape.
    assert(#edge.arguments==#parameters,'edge packet count mismatch')
    for i,ref in ipairs(edge.arguments) do self:expect(ref,parameters[i].type) end
    self:effect(edge.arguments[1])
end
function B.Return:verify(ctx)
    assert(#self.values==#ctx.fn.signature.results,'return count mismatch')
    for i,ref in ipairs(self.values) do ctx:expect(ref,ctx.fn.signature.results[i]) end
    ctx:effect(self.values[#self.values])
end
function B.Jump:verify(ctx) ctx:edge(self.edge) end
function B.Branch:verify(ctx) ctx:expect(self.condition,B.Bool); ctx:edge(self.yes); ctx:edge(self.no) end
function B.Trap:verify(ctx) ctx:effect(self.effect) end
function B.CallFunction:verify(ctx)
    local callee=ctx:callee(self.target,self.arguments)
    local results=callee.results
    assert(#results>=2 and results[#results]==B.Effect,'callee must return its final effect')
    -- The call consumes the caller's effect and produces the callee's final effect last.
    ctx:effect(self.effect); ctx:results(results)
    ctx.effect_position,ctx.effect_output=ctx.position,#results-1
end
function B.TailCall:verify(ctx)
    local callee=ctx:callee(self.target,self.arguments); ctx:effect(self.effect)
    local results=ctx.fn.signature.results
    assert(#results==#callee.results,'tail call result count mismatch')
    for i,type_ in ipairs(callee.results) do assert(type_:same(results[i]),'tail call result type mismatch') end
end
function B.Function:verify_flow(hosts,functions)
    functions=functions or {[1]=self}
    self:verify_numbering(); local registry={}
    for _,host in pairs(hosts or {}) do
        assert(host.phase=='runtime' and (host.purity=='pure' or host.purity=='ordered'),'invalid runtime host contract')
        assert(B.Signature:isclassof(host.signature) and #host.signature.results==1,'host requires one Let result')
        assert(not registry[host.symbol],'duplicate host symbol'); registry[host.symbol]=host
    end
    assert(self.signature.results[#self.signature.results]==B.Effect,'function must return its final effect')
    for i=1,#self.signature.results-1 do assert(self.signature.results[i]~=B.Effect,'effect must be the last result') end
    for _,block in ipairs(self.blocks) do
        assert(block.parameters[1] and block.parameters[1].type==B.Effect,'block must receive its effect first')
        for i=2,#block.parameters do assert(block.parameters[i].type~=B.Effect,'block has multiple effects') end
        local ctx=setmetatable({fn=self,block=block,hosts=registry,functions=functions,effect_position=0,effect_output=0},Check)
        for i,instruction in ipairs(block.instructions) do
            ctx.position=#block.parameters+i-1; ctx.instruction=instruction; instruction.operation:verify(ctx)
        end
        ctx.position=#block.parameters+#block.instructions; block.exit:verify(ctx)
    end
    for i,param in ipairs(self.signature.parameters) do
        local entry=self.blocks[1].parameters[i]
        assert(param.type:same(entry.type) and param.capability==entry.capability,'entry signature mismatch')
    end
    return self
end
function B.Program:verify_flow(hosts)
    local functions={} for i,fn in ipairs(self.functions) do functions[i]=fn.signature end
    for i,fn in ipairs(self.functions) do
        -- Naming the function costs nothing and saves guessing which one failed.
        local ok,err=pcall(fn.verify_flow,fn,hosts,functions)
        if not ok then error(('function %d (%s): %s'):format(i,fn.name,tostring(err)),0) end
    end
    return self
end
end

