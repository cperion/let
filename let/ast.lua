-- Let source vocabulary. No inferred types, ownership state, or backend nodes.
return function(context)
    context:Define [[
module Source {
    Span = (string file, number line, number column)
    Range = (Span start, Span stop)
    Token = (string kind, string spelling, string? value, Span span)
}
module AST {
    Capability = Read | Mut | Own | OwnMut
    UnaryOp = Negate | Not | BitNot | ToFloat | ToInt | ToCString | ToText | TextSize | IsNull
    BinaryOp = Add | Subtract | Multiply | Divide | Remainder
             | Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual
             | And | Or | BitAnd | BitOr | BitXor | ShiftLeft | ShiftRight
    TypeExpr = Ref(string name, Expr* arguments, Source.Range name_range) | Apply(TypeExpr constructor, TypeExpr argument)
             | Arrow(TypeExpr from, TypeExpr to) | Sum(TypeExpr left, TypeExpr right)
             | Do(TypeExpr result)
             | Record(TypeField* fields) | Tuple(TypeExpr* elements)
         attributes (Source.Span span)
    TypeField = (string name, boolean mutable, TypeExpr type, Source.Span span)
    Program = (Chain file)
    Binding = (string name, boolean mutable, TypeExpr? constraint, Chain value, Source.Span span, Source.Range name_range)
    Chain = (Item* items, Terminal? terminal, Source.Span span)
    Item = Stage(string name, Capability capability, TypeExpr? constraint, Source.Span span, Source.Range name_range)
         | Prelude(Binding binding)
         | Extern(string name, boolean pure, string? symbol, Stage* parameters, TypeExpr? result, Source.Span span, Source.Range name_range)
    Terminal = Data(Expr value) | Body(Stmt* statements, TypeExpr? result)
    Expr = Name(string name) | Integer(string spelling) | Float(string spelling) | Boolean(boolean value)
         | Text(string value) | Unit
         | Unary(UnaryOp operator, Expr operand)
         | Binary(BinaryOp operator, Expr left, Expr right)
         | Specialize(Expr word, Expr argument)
         | Invoke(Expr word, Expr* arguments)
         | Word(Chain chain)
         | NamedAggregate(Binding* members, boolean nominal) | PositionalAggregate(Chain* elements)
         | Project(Expr base, string name, Source.Range member_range) | Index(Expr base, Expr index)
         | Move(Expr place) | Borrow(Expr place)
         | SumType(TypeExpr left, TypeExpr right)
         attributes (Source.Span span)
    Stmt = Local(Binding binding) | Assign(Expr place, Expr value)
         | Return(Expr? value) | Discard(Expr value)
         | If(Expr condition, Stmt* yes, Stmt* no)
         | While(Expr condition, Stmt* body)
         | Break | Continue
         | Switch(Expr subject, Case* cases, Stmt* otherwise)
         attributes (Source.Span span)
    Case = (Expr* labels, Stmt* body, Source.Span span)
}
    ]]
    -- Migration alias (§11): an annotation names a type word, so the former Constraint node is
    -- the Ref alternative. Consumers reading `.name`/`.arguments` keep working while the new
    -- alternatives are wired in.
    context.AST.Constraint = context.AST.Ref
end

