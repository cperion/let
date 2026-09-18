-- The representation vocabulary.
--
-- Belt owns representation only. It has no `Word`, `Arrow`, `Do`, `TypeWord`, `Address`, `Borrow`
-- or `Callable`: the first four are *type words* and live in Semantic, the next two are reference
-- apparatus and are a lowering fact, and a uniform callable is a vtable (DESIGN §S2, §S5). What it
-- keeps is the one representation the ownership model needs -- `Cell`, the storage a captured
-- place lives in -- and `Op = Pure | Ordered`, so "pure folds, ordered schedules" is dispatch.
return function(context)
    -- A sum's fields are its TAG and its PAYLOADS: field `0` is the tag, and field `1+K` is
    -- alternative `K`'s payload (§3.5, §S59). Both are KNOWN offsets, so every field read of a sum
    -- is a pure `LoadField`, exactly like a record's. The read that would NOT be pure is one that
    -- names an alternative without having tested the tag -- and the language has no such read,
    -- because a payload is reached by the arm that matched it. There is nothing left to trap.
    context:Define [[
module Belt {
    Ref       = (number distance, number output)

    PureOp    = IntegerLiteral(string spelling) | FloatLiteral(string spelling)
              | BooleanLiteral(boolean value) | UnitLiteral | TextLiteral(string value)
              | TextOf(Ref pointer, Ref size)
              | Unary(Semantic.UnaryOp operator, Ref operand)
              | Binary(Semantic.BinaryOp operator, Ref left, Ref right)
              | Convert(Semantic.Conversion kind, Ref value)
              | Construct(Ref* fields)
              | InjectSum(number index, Ref payload)
              | LoadField(Ref record, number field)
              | FieldAddress(Ref cell, number field)
              | PureHostCall(string symbol, Ref* arguments)
    OrderedOp = CheckedBinary(Semantic.BinaryOp operator, Ref effect, Ref left, Ref right)
              | CallFunction(number target, Ref effect, Ref* arguments)
              | HostCall(string symbol, Ref effect, Ref* arguments)
              | Allocate(Ref effect, Ref initial)
              | Load(Ref effect, Ref cell) | Store(Ref effect, Ref cell, Ref value)
              | StoreField(Ref record, number field, Ref value)
              | Move(Ref effect, Ref value) | Destroy(Ref effect, Ref value, string destructor)
    Op        = Pure(PureOp operation) | Ordered(OrderedOp operation)

    Field       = (string? name, Type type, boolean mutable)
    Type        = Int | U8 | U32 | Float | Float32 | Bool | Unit | Text | Effect
                | CString | CPointer
                | Named(string name) | Aggregate(Field* fields) | Sum(Type* alternatives)
                | Cell(Type contents)
    Instruction = (Op operation, Type* results, Source.Span? span)
    Parameter   = (Type type, Semantic.Capability capability)
    Signature   = (Parameter* parameters, Type* results)
    Edge        = (number target, Ref* arguments)
    Exit        = Return(Ref* values)
                | Jump(Edge edge)
                | Branch(Ref condition, Edge yes, Edge no)
                | TailCall(number target, Ref effect, Ref* arguments)
                | Trap(Ref effect, string reason)
    Block       = (Parameter* parameters, Instruction* instructions, Exit exit)
    Function    = (string name, Signature signature, Block* blocks, boolean exported)
    Program     = (string name, Chain.Template* templates, Function* functions)
}
    ]]

    -- §3.5's injection is derived by comparing the value's type with the sum's alternatives, and
    -- `Lower` compares BELT types -- the semantic side has its own `equals` because the two are
    -- separate vocabularies (§10). Scalars are unique classes so identity is right; aggregates, sums
    -- and cells compare structurally; a named type is a name.
    local B = context.Belt
    function B.Type:equals(other) return self == other end
    -- §S49: this side MIRRORS the semantic equality, because `Lower` compares belt types and
    -- `Belt.Sum:alternative` is where it matters. A host type is nominal (§S44), so two `B.Named`
    -- values name one type exactly when their names are equal -- and this was missing here while
    -- `Semantic.Named:equals` had said so since §S44, which made every sum with a host alternative
    -- unable to inject or to discriminate. Nothing reached it until a binder had to look one up.
    function B.Named:equals(other)
        return B.Named:isclassof(other) and self.name == other.name
    end
    function B.Aggregate:equals(other)
        if not B.Aggregate:isclassof(other) or #self.fields ~= #other.fields then return false end
        for index, field in ipairs(self.fields) do
            local peer = other.fields[index]
            if field.mutable ~= peer.mutable or field.name ~= peer.name then return false end
            if not field.type:equals(peer.type) then return false end
        end
        return true
    end
    function B.Sum:equals(other)
        if not B.Sum:isclassof(other) or #self.alternatives ~= #other.alternatives then return false end
        for index, alternative in ipairs(self.alternatives) do
            if not alternative:equals(other.alternatives[index]) then return false end
        end
        return true
    end
    function B.Cell:equals(other)
        return B.Cell:isclassof(other) and self.contents:equals(other.contents)
    end

    -- Which alternative of a sum this type selects, and how many matched. The same rule as
    -- `Semantic.Sum:alternative`, on the side of the mapping that `Lower` works in.
    function B.Sum:alternative(type_)
        local found, count = nil, 0
        for index, alternative in ipairs(self.alternatives) do
            if alternative:equals(type_) then found, count = index - 1, count + 1 end
        end
        return found, count
    end
end
