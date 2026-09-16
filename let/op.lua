-- One definition of each pure operation, shared by the abstract evaluator and the concrete test
-- oracle, so folding cannot disagree with execution (DEMAND.md §3). The exact scalar semantics
-- live in `let/scalar`; this table says which one an operator means.
return function(V)
local A,B=V.AST,V.Belt
local scalar=require('let.scalar')

local Op={}

-- The width a fixed-width integer reduces to, or nil for Int and Float. An operator's meaning is
-- chosen by this, from the Let type, never by the host's representation of the value.
function Op.kind(type_)
    if type_==B.U8 then return 8 end
    if type_==B.U32 then return 32 end
    if type_==B.Float32 then return 'f32' end
    return nil
end

-- Binary operators over known values. `Divide` here is non-trapping Float division; an Int
-- division is a `CheckedBinary` and uses `Op.checked`, which traps.
Op.binary={
    [A.Add]=scalar.add, [A.Subtract]=scalar.subtract, [A.Multiply]=scalar.multiply,
    [A.Divide]=scalar.fdivide,
    [A.Equal]=scalar.equal, [A.NotEqual]=scalar.not_equal,
    [A.Less]=scalar.less, [A.LessEqual]=scalar.less_equal,
    [A.Greater]=scalar.greater, [A.GreaterEqual]=scalar.greater_equal,
    [A.And]=function(a,b) return a and b end, [A.Or]=function(a,b) return a or b end,
    [A.BitAnd]=scalar.band, [A.BitOr]=scalar.bor, [A.BitXor]=scalar.bxor,
    [A.ShiftLeft]=scalar.shl, [A.ShiftRight]=scalar.shr,
}

Op.unary={
    [A.Negate]=scalar.negate, [A.Not]=function(a) return not a end, [A.BitNot]=scalar.bitnot,
    [A.ToFloat]=scalar.to_float, [A.ToInt]=scalar.to_int,
    [A.ToU8]=scalar.to_u8, [A.ToU32]=scalar.to_u32, [A.ToF32]=scalar.to_f32,
    [A.TextSize]=scalar.text_size,
    -- `IsNull` is not here: a pointer is not a Let value, so it never folds.
}

-- Operations that can trap, used when the divisor is not known non-zero.
Op.checked={[A.Divide]=scalar.divide, [A.Remainder]=scalar.remainder}

return Op
end
