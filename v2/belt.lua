-- Immutable semantic producers. Relative references never change during demand analysis.
return function(context)
    context:Define [[
module Belt {
    Destination = Persistent | Transient
    Access = CopyAccess | OwnAccess | ReadAccess | MutAccess
    Field = (string? name, Type type, boolean mutable)
    Type = Int | Bool | Unit | Text | Effect
         | Named(string name) | Address(Type pointee)
         | Borrow(Type pointee, boolean stable)
         | Aggregate(Field* fields, boolean is_copy)
         | Word(number template, number supplied, Field* fields, boolean is_copy)
         | Callable(Signature signature)
    Parameter = (Type type, AST.Capability capability)
    Signature = (Parameter* parameters, Type* results)
    Ref = (number distance, number output)
    Instruction = (Op operation, Type* results, Source.Span? span)
    Op = IntegerLiteral(string spelling) | BooleanLiteral(boolean value) | UnitLiteral | TextLiteral(string value)
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
end

