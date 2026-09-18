-- The one owner of what an opcode reads, and later of what it means.
--
-- DESIGN §11: *"the opcode semantics live in one registry"*. The emitter asks this for the refs an
-- instruction reads instead of listing operands itself -- which is exactly how the emitter and the
-- abstract evaluator would otherwise drift apart. Scalar semantics join it when the abstract
-- evaluator needs them shared with the concrete oracle.
--
-- `instruction.operation` is `Op = Pure(PureOp) | Ordered(OrderedOp)`, so the inner operation is
-- one level in. The **effect** is a ref like any other here: it is evidence of order, not a value,
-- and only the emitter decides that it has no C representation.
return function(V)
    local B = V.Belt
    local Op = {}

    -- The refs an instruction reads, in the order its opcode declares them.
    function Op.inputs(instruction)
        local op = instruction.operation.operation
        -- The literal family reads nothing: its value is in the opcode. `TextLiteral` is in it for
        -- the same reason as the rest -- the text is the constant, not a reference to one.
        if B.IntegerLiteral:isclassof(op) or B.FloatLiteral:isclassof(op)
            or B.BooleanLiteral:isclassof(op)
            or B.UnitLiteral:isclassof(op) or B.TextLiteral:isclassof(op) then
            return {}
        end
        if B.Construct:isclassof(op) then return op.fields end
        if B.Unary:isclassof(op) then return {op.operand} end
        if B.Convert:isclassof(op) then return {op.value} end
        if B.InjectSum:isclassof(op) then return {op.payload} end
        if B.Destroy:isclassof(op) then return {op.effect, op.value} end
        if B.Binary:isclassof(op) then return {op.left, op.right} end
        if B.CheckedBinary:isclassof(op) then return {op.effect, op.left, op.right} end
        if B.LoadField:isclassof(op) then return {op.record} end
        -- A cell's reads and writes: the storage op takes the effect and the whole record, the
        -- cell ops take the effect and the cell.
        if B.Allocate:isclassof(op) then return {op.effect, op.initial} end
        if B.Load:isclassof(op) then return {op.effect, op.cell} end
        if B.Store:isclassof(op) then return {op.effect, op.cell, op.value} end
        if B.FieldAddress:isclassof(op) then return {op.cell} end
        if B.StoreField:isclassof(op) then return {op.record, op.value} end
        -- A move consumes the effect; the value it transfers is the same ref the consumer holds.
        if B.Move:isclassof(op) then return {op.effect, op.value} end
        -- A host call reads its arguments, and an ORDERED one reads the effect first -- the same
        -- shape as `CallFunction`, because the effect is evidence of order and not of value.
        if B.PureHostCall:isclassof(op) then
            local refs = {}
            for _, ref in ipairs(op.arguments) do refs[#refs + 1] = ref end
            return refs
        end
        if B.HostCall:isclassof(op) then
            local refs = {op.effect}
            for _, ref in ipairs(op.arguments) do refs[#refs + 1] = ref end
            return refs
        end
        if B.CallFunction:isclassof(op) then
            local refs = {op.effect}
            for _, ref in ipairs(op.arguments) do refs[#refs + 1] = ref end
            return refs
        end
        error('no input rule for ' .. tostring(getmetatable(op) and getmetatable(op).kind), 0)
    end

    -- Whether an opcode has C work of its own. A `Move` does not: it is an ownership transition,
    -- and its runtime representation is nothing -- the value is already in hand and the source is
    -- simply not destroyed. Everything else is either a value the output can see or an effect
    -- whose scheduled work is that statement.
    function Op.emits(op)
        return not B.Move:isclassof(op)
    end

    return Op
end
