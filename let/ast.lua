-- Let source vocabulary. No inferred types, ownership state, or backend nodes.
return function(context)
    context:Define [[
module Source {
    Span = (string file, number line, number column)
    Token = (string kind, string spelling, string? value, Span span)
}
module AST {
    Capability = Read | Mut | Own | OwnMut
    UnaryOp = Negate | Not | ToFloat | ToInt | ToCString | ToText | TextSize | IsNull
    BinaryOp = Add | Subtract | Multiply | Divide | Remainder
             | Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual
             | And | Or
    Constraint = (string name, Expr* arguments)
    Program = (Chain file)
    Binding = (string name, boolean mutable, Constraint? constraint, Chain value, Source.Span span)
    Chain = (Item* items, Terminal? terminal, Source.Span span)
    Item = Stage(string name, Capability capability, Constraint? constraint, Source.Span span)
         | Prelude(Binding binding)
         | Extern(string name, boolean pure, string? symbol, Stage* parameters, Constraint? result, Source.Span span)
    Terminal = Data(Expr value) | Body(Stmt* statements)
    Expr = Name(string name) | Integer(string spelling) | Float(string spelling) | Boolean(boolean value)
         | Text(string value) | Unit
         | Unary(UnaryOp operator, Expr operand)
         | Binary(BinaryOp operator, Expr left, Expr right)
         | Specialize(Expr word, Expr argument)
         | Invoke(Expr word, Expr* arguments)
         | Word(Chain chain)
         | NamedAggregate(Binding* members) | PositionalAggregate(Chain* elements)
         | Project(Expr base, string name) | Index(Expr base, Expr index)
         | Move(Expr place) | Borrow(Expr place)
         attributes (Source.Span span)
    Stmt = Local(Binding binding) | Assign(Expr place, Expr value)
         | Return(Expr? value) | Discard(Expr value)
         | If(Expr condition, Stmt* yes, Stmt* no)
         | While(Expr condition, Stmt* body)
         | Switch(Expr subject, Case* cases, Stmt* otherwise)
         attributes (Source.Span span)
    Case = (Expr* labels, Stmt* body, Source.Span span)
}
    ]]
end

