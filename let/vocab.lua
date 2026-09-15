-- Structural vocabulary. Phase modules install behavior on these constructors.
local asdl = require('asdl')
local V = asdl.NewContext()
V:Define [[
module Source {
    Span = (string file, number line, number column)
    Token = (string tag, string text, Span span)
}
module Syntax {
    Program = (Binding* bindings)
    Binding = (string name, boolean mutable, string? annotation, Chain value, Source.Span span)
    Chain = (Item* items, Terminal terminal, Source.Span span)
    Item = Stage(string name, string? annotation, Semantic.Capability capability, Source.Span span)
         | Prelude(Binding binding)
    Terminal = Body(Stmt* statements) | Data(Expr value)
    Expr = Name(string name) | Integer(string spelling) | Boolean(boolean value) | Unit
         | Unary(string operator, Expr operand)
         | Binary(string operator, Expr left, Expr right)
         | Specialize(Expr word, Expr argument)
         | Invoke(Expr word, Expr* arguments)
         | Move(string name) | Borrow(string name)
         attributes (Source.Span span)
    Stmt = Local(Binding binding) | Assign(string name, Expr value)
         | Return(Expr? value) | Discard(Expr value)
         | If(Expr condition, Stmt* yes, Stmt* no)
         | While(Expr condition, Stmt* body)
         attributes (Source.Span span)
}
module Semantic {
    Capability = Read | Mut | Own | OwnMut
    Shape = Int | Bool | Unit | Resource(string name, string destructor) unique
    Value = Scalar(Shape shape, Evaluation.Atom atom) | Word(number id, Value* bound) | Host(number id)
    Binding = (Value value, boolean mutable, Capability? capability)
    Signature = (Shape* parameters, Shape result) unique
    ActivationField = DataField(Shape shape) | WordField(number word, number supplied) | HostField(number host)
        attributes (string name, Capability capability, Source.Span span)
}
module Analysis {
    Value = Scalar(number type) | Word(number id, number supplied) | Host(number id)
}
module Evaluation {
    Atom = Bits(number hi, number lo) | Truth(boolean value) | Nothing unique
    Value = Known(Semantic.Shape shape, Atom atom)
          | Dynamic(Semantic.Shape shape, Residual.Expr expression) | Bottom(Semantic.Shape shape)
          | Place(Semantic.Shape shape, number id)
          | Resource(Semantic.Shape shape, Residual.Expr expression, number? owner, boolean fresh)
          | Word(number id, Value* bound) | Host(number id)
    Flow = Continue | Returned(Value value) | Stopped
}
module Residual {
    CType = I64 | Bool | U8 | Pointer(CType pointee) unique
    Expr = Integer(number hi, number lo) | Boolean(boolean value) | Unit
         | Local(CType type, number id) | Argument(CType type, number index)
         | Deref(CType type, Expr pointer) | Address(Expr place)
         | Binary(string operator, Expr left, Expr right)
         | Compare(string operator, Expr left, Expr right)
         | Select(Expr condition, Expr yes, Expr no) | Call(number function_id, Expr* arguments)
    Stmt = Assign(Expr place, Expr value) | SeqStmt(Stmt* statements)
         | IfStmt(Expr condition, Stmt yes, Stmt no)
         | WhileStmt(Stmt test, Expr condition, Stmt body)
         | Label(number id) | Jump(number label, Expr* places, Expr* arguments)
         | Exit(number label, Expr value) | Region(number label, CType? result, Stmt body)
         | PendingExit(number label, number edge)
         | ReturnStmt(Expr value) | VoidCall(number function_id, Expr* arguments) | Trap
    Function = (number id, string c_name, boolean exported, boolean external, CType* parameters, CType? result, Stmt? body)
    Module = (Function* functions)
}
 ]]
return { Source = V.Source, Syntax = V.Syntax, Semantic = V.Semantic, Analysis = V.Analysis, Evaluation = V.Evaluation, Residual = V.Residual, List = asdl.List }

