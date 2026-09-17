-- Numbering and dependency traversal only; not type, ownership, or effect verification.
return function(V)
    local B,L=V.Belt,V.List
    local function natural(n) return type(n)=='number' and n>=0 and n<math.huge and n==math.floor(n) end
    local function append(out,refs) for _,ref in ipairs(refs) do out:insert(ref) end end
    function B.Op:inputs() return L() end
    function B.Unary:inputs() return L{self.operand} end
    function B.TextOf:inputs() return L{self.pointer,self.size} end
    function B.Binary:inputs() return L{self.left,self.right} end
    function B.CheckedBinary:inputs() return L{self.effect,self.left,self.right} end
    function B.BorrowPlace:inputs() return L{self.address} end
    function B.FieldAddress:inputs() return L{self.place} end
    function B.Construct:inputs() return self.fields end
    function B.InjectSum:inputs() return L{self.payload} end
    function B.LoadField:inputs() return L{self.record} end
    function B.SelectField:inputs() return L{self.record,self.key} end
    function B.StoreField:inputs() return L{self.record,self.value} end
    function B.CallFunction:inputs() local out=L{self.effect}; append(out,self.arguments); return out end
    function B.HostCall:inputs() local out=L{self.effect}; append(out,self.arguments); return out end
    function B.PureHostCall:inputs() return self.arguments end
    function B.Allocate:inputs() return L{self.effect,self.initial} end
    function B.Load:inputs() return L{self.effect,self.address} end
    function B.Store:inputs() return L{self.effect,self.address,self.value} end
    function B.Move:inputs() return L{self.effect,self.value} end
    function B.Destroy:inputs() return L{self.effect,self.value} end
    function B.Exit:edges() return L() end
    function B.Jump:edges() return L{self.edge} end
    function B.Branch:edges() return L{self.yes,self.no} end
    function B.Return:inputs() return self.values end
    function B.Jump:inputs() return self.edge.arguments end
    function B.Branch:inputs() local out=L{self.condition}; append(out,self.yes.arguments); append(out,self.no.arguments); return out end
    function B.TailCall:inputs() local out=L{self.effect}; append(out,self.arguments); return out end
    function B.Trap:inputs() return L{self.effect} end
    function B.Block:resolve(position,ref)
        assert(natural(position) and position<=#self.parameters+#self.instructions,'invalid consumer position')
        assert(natural(ref.distance) and natural(ref.output),'belt references require nonnegative integer distance and output')
        local producer=position-1-ref.distance
        assert(producer>=0,'reference precedes block entry')
        if producer<#self.parameters then
            assert(ref.output==0,'a block parameter has only output zero')
            return producer,self.parameters[producer+1].type
        end
        local instruction=self.instructions[producer-#self.parameters+1]
        assert(ref.output<#instruction.results,'invalid producer output')
        return producer,instruction.results[ref.output+1]
    end
    function B.Function:verify_numbering()
        assert(#self.blocks>0,'function needs an entry block')
        assert(#self.blocks[1].parameters==#self.signature.parameters,'entry parameter count mismatch')
        for _,block in ipairs(self.blocks) do
            local position=#block.parameters
            for _,instruction in ipairs(block.instructions) do
                for _,ref in ipairs(instruction.operation:inputs()) do block:resolve(position,ref) end
                position=position+1
            end
            for _,ref in ipairs(block.exit:inputs()) do block:resolve(position,ref) end
            for _,edge in ipairs(block.exit:edges()) do
                assert(natural(edge.target) and edge.target>=1 and self.blocks[edge.target],'invalid block target')
                assert(#edge.arguments==#self.blocks[edge.target].parameters,'edge parameter count mismatch')
            end
        end
        return self
    end
    -- A local dependency closure, not global liveness or an optimization pass.
    -- All exit operands are roots, including effect tokens and both branch packets.
    function B.Block:demands()
        local demanded,uses={},{}
        local function demand(position,ref)
            local producer=self:resolve(position,ref)
            demanded[producer]=demanded[producer] or {}; demanded[producer][ref.output]=true
            uses[producer]=uses[producer] or {}; uses[producer][ref.output]=(uses[producer][ref.output] or 0)+1
        end
        for _,ref in ipairs(self.exit:inputs()) do demand(#self.parameters+#self.instructions,ref) end
        for i=#self.instructions,1,-1 do
            local position=#self.parameters+i-1
            if demanded[position] then
                for _,ref in ipairs(self.instructions[i].operation:inputs()) do demand(position,ref) end
            end
        end
        return demanded,uses
    end
end

