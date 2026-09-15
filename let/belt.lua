-- Immutable semantic producers. Relative references never change during demand analysis.
return function(context)
    context:Define [[
module Belt {
    Destination = Persistent | Transient
    Access = CopyAccess | OwnAccess | ReadAccess | MutAccess
    Field = (string? name, Type type, boolean mutable)
    Type = Int | Float | Bool | Unit | Text | Effect
         | Named(string name) | Address(Type pointee)
         | Borrow(Type pointee, boolean stable)
         | Aggregate(Field* fields, boolean is_copy)
         | Word(number template, number supplied, Field* fields, boolean is_copy)
         | Callable(Signature signature)
    Parameter = (Type type, AST.Capability capability)
    Signature = (Parameter* parameters, Type* results)
    Ref = (number distance, number output)
    Instruction = (Op operation, Type* results, Source.Span? span)
    Op = IntegerLiteral(string spelling) | FloatLiteral(string spelling) | BooleanLiteral(boolean value) | UnitLiteral | TextLiteral(string value)
       | Unary(AST.UnaryOp operator, Ref operand)
       | Binary(AST.BinaryOp operator, Ref left, Ref right)
       | CheckedBinary(AST.BinaryOp operator, Ref effect, Ref left, Ref right)
       | BorrowPlace(Ref address, boolean stable)
       | FieldAddress(Ref place, number field, boolean stable)
       | Construct(Ref* fields, boolean is_copy)
       | LoadField(Ref record, number field)
       | StoreField(Ref record, number field, Ref value)
       | CallFunction(number target, Ref effect, Ref* arguments)
       | HostCall(string symbol, Ref effect, Ref* arguments)
       | PureHostCall(string symbol, Ref* arguments)
       | Allocate(Ref effect, Ref initial)
       | Load(Ref effect, Ref address) | Store(Ref effect, Ref address, Ref value)
       | Move(Ref effect, Ref value) | Destroy(Ref effect, Ref value, string destructor)
    Edge = (number target, Ref* arguments)
    Exit = Return(Ref* values) | Jump(Edge edge)
         | Branch(Ref condition, Edge yes, Edge no)
         | TailCall(number target, Ref effect, Ref* arguments)
         | Trap(Ref effect, string reason)
    Block = (Parameter* parameters, Instruction* instructions, Exit exit)
    Function = (string name, Signature signature, Block* blocks)
    Template = (string name, number stages, number captures, Source.Span? span)
    Program = (string name, Template* templates, Function* functions)
}
    ]]

    local B=context.Belt
    -- Type semantics belong to the belt vocabulary, not to one consumer: construction,
    -- verification, demand analysis and emission all ask these questions.
function B.Type:same(other) return self==other end
function B.Named:same(other) return B.Named:isclassof(other) and self.name==other.name end
function B.Address:same(other) return B.Address:isclassof(other) and self.pointee:same(other.pointee) end
local function fields_same(a,b)
    if #a~=#b then return false end
    for i,field in ipairs(a) do
        if field.name~=b[i].name or field.mutable~=b[i].mutable or not field.type:same(b[i].type) then return false end
    end
    return true
end
-- A borrow is a view of a place: the same pointee, but not the same thing to own.
function B.Borrow:same(other)
    return B.Borrow:isclassof(other) and self.stable==other.stable and self.pointee:same(other.pointee)
end
function B.Aggregate:same(other)
    return B.Aggregate:isclassof(other) and self.is_copy==other.is_copy and fields_same(self.fields,other.fields)
end
function B.Word:same(other)
    return B.Word:isclassof(other) and self.template==other.template and self.supplied==other.supplied
        and self.is_copy==other.is_copy and fields_same(self.fields,other.fields)
end
function B.Type:copyable() return false end
function B.Int:copyable() return true end
function B.Float:copyable() return true end
function B.Bool:copyable() return true end
function B.Unit:copyable() return true end
function B.Text:copyable() return true end
-- §8.5: an aggregate is Copy exactly when every contained value is Copy and it declares
-- no mutable member. Both facts are recorded in the type, because member types alone
-- cannot express a declared mutable member.
function B.Aggregate:copyable() return self.is_copy end

-- Word records and aggregates are both ordered fields; only words carry a template.
function B.Type:record() return nil end
function B.Aggregate:record() return self.fields end
function B.Word:record() return self.fields end
function B.Word:copyable() return self.is_copy end

end

