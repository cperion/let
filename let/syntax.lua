-- The surface vocabulary: what the source says.
--
-- Two things here are deliberate. `TypeExpr` has no application form: `List with Int` is `with`
-- (spec §3.1, "a type application is not a distinct form"), so `Ref` carries only a name.
-- Conversions are their own choice -- `Conversion` -- rather than sharing a sum with `Negate`,
-- because `ToFloat` and friends are dictionary words, not operators.
return function(context)
    context:Define [[
module Syntax {
    UnaryOp    = Negate | Not | BitNot
    BinaryOp   = Add | Subtract | Multiply | Divide | Remainder
               | Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual
               | And | Or | BitAnd | BitOr | BitXor | ShiftLeft | ShiftRight
    Conversion = ToFloat | ToInt | ToU8 | ToU32 | ToF32 | ToCString | ToText | TextSize | IsNull

    TypeExpr  = Ref(string name)
              | Record(TypeField* fields)
              | Tuple(TypeExpr* elements)
              | Arrow(TypeExpr from, TypeExpr to)
              | Sum(TypeExpr left, TypeExpr right)
              | Do(TypeExpr result)
              attributes (Source.Span span)
    TypeField = (string name, boolean mutable, TypeExpr type, Source.Span span)

    Program   = (Chain file)
    Binding   = (string name, boolean mutable, TypeExpr? constraint, Chain value,
                 Source.Span span, Source.Range name_range)
    Chain     = (Item* items, Terminal? terminal, Source.Span span)
    StageSpec = (string name, Semantic.Capability capability, TypeExpr? constraint,
                 Source.Span span, Source.Range name_range)
    Item      = Stage(StageSpec stage)
              | Prelude(Binding binding)
              | Extern(string name, boolean pure, string? symbol, StageSpec* parameters,
                       TypeExpr? result, Source.Span span, Source.Range name_range)
              | Host(string name, string? destroys, string? borrows, Source.Span span,
                     Source.Range name_range)
    Terminal  = Data(Expr value) | Body(Stmt* statements, TypeExpr? result)
              attributes (Source.Span span)

    Expr      = Name(string name) | Integer(string spelling) | Float(string spelling)
              | Boolean(boolean value) | Text(string value) | Unit
              | Unary(UnaryOp operator, Expr operand)
              | Binary(BinaryOp operator, Expr left, Expr right)
              | Convert(Conversion kind, Expr value)
              | Specialize(Expr word, Expr argument)
              | Invoke(Expr word, Expr* arguments)
              | Word(Chain chain)
              | NamedAggregate(Binding* members)
              | PositionalAggregate(Chain* elements)
              | Project(Expr base, string name, Source.Range member_range)
              | Index(Expr base, Expr index)
              | Move(Expr place) | Borrow(Expr place)
              | TypeSum(TypeExpr left, TypeExpr right)
              attributes (Source.Span span)

    Stmt      = Local(Binding binding) | Assign(Expr place, Expr value)
              | Return(Expr? value) | Discard(Expr value)
              | If(Expr condition, Stmt* yes, Stmt* no)
              | While(Expr condition, Stmt* body)
              | Break | Continue
              | Switch(Expr subject, Case* cases, Stmt* otherwise)
              attributes (Source.Span span)
    Label     = Shape(TypeExpr type) | Constant(Expr value)
    Case      = (Label* labels, string? binds, Stmt* body, Source.Span span)
}
    ]]
end
